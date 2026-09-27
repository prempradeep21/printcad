//
//  LiveSpeechTranscriber.swift
//  openshape3d
//
//  PrintCAD V1.1: the real microphone → text pipeline behind the voice panel.
//  AVAudioEngine feeds SFSpeechRecognizer; partial results give the live
//  transcript. Recognition stays on-device when the device supports it, so
//  speech never leaves the machine (only the final text goes to Jev, V1.2).
//
//  Threading: the audio tap and the recognition callback run on background
//  queues. They are built in `nonisolated static` factories that capture only
//  Sendable values and hop to the main actor, because closures written inside
//  this (main-actor) class would otherwise be main-actor isolated and trap
//  when the audio thread calls them.
//

import AVFoundation
import Speech

@MainActor
final class LiveSpeechTranscriber: SpeechTranscribing {
    /// Created fresh on every start, AFTER the audio session is set to record.
    /// An engine whose input node was touched earlier stays bound to the
    /// input-less default session and reports a 0 Hz format (seen on the Mac,
    /// 2026-09-28: "No microphone input was found").
    private var audioEngine: AVAudioEngine?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var recognizer: SFSpeechRecognizer?

    /// Words the recognizer should favour — CAD vocabulary it would otherwise
    /// hear as "skillet", "shampoo" and friends.
    static let vocabulary = [
        "fillet", "chamfer", "extrude", "extrusion", "sketch", "boss", "shell",
        "counterbore", "countersink", "through hole", "blind hole", "M2", "M3",
        "M4", "M5", "mm", "millimetre", "millimeter", "face", "edge", "pocket",
    ]

    func requestAuthorization() async -> SpeechAuthorization {
        guard await Self.speechAuthorization() == .authorized else {
            return .denied("Speech recognition is off for this app. Turn it on in System Settings › Privacy & Security › Speech Recognition.")
        }
        let microphone = await AVAudioApplication.requestRecordPermission()
        guard microphone else {
            return .denied("Microphone access is off for this app. Turn it on in System Settings › Privacy & Security › Microphone.")
        }
        return .authorized
    }

    func start(onPartial: @escaping (String) -> Void,
               onLevel: @escaping (Float) -> Void,
               onError: @escaping (String) -> Void) throws {
        stop()
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US")) ?? SFSpeechRecognizer(),
              recognizer.isAvailable
        else {
            throw TranscriberError.recognizerUnavailable
        }
        self.recognizer = recognizer

        #if os(iOS) || targetEnvironment(macCatalyst)
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: .duckOthers)
        try session.setActive(true, options: .notifyOthersOnDeactivation)
        #endif

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.contextualStrings = Self.vocabulary
        request.taskHint = .dictation
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }
        request.addsPunctuation = false
        self.request = request

        let engine = AVAudioEngine()
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw TranscriberError.noMicrophone(Self.diagnostics(input))
        }
        // nil format = the node's own output format, so the tap can never
        // mismatch it (a mismatch is an Objective-C exception, i.e. a crash).
        input.installTap(onBus: 0, bufferSize: 1024, format: nil,
                         block: Self.makeTap(request: request, onLevel: onLevel))
        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            throw error
        }
        audioEngine = engine

        task = recognizer.recognitionTask(
            with: request,
            resultHandler: Self.makeResultHandler(onPartial: onPartial, onError: onError)
        )
    }

    func stop() {
        if let engine = audioEngine {
            engine.stop()
            engine.inputNode.removeTap(onBus: 0)
            audioEngine = nil
        }
        request?.endAudio()
        task?.cancel()
        request = nil
        task = nil
        #if os(iOS) || targetEnvironment(macCatalyst)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        #endif
    }

    /// What the audio stack reported, for the error line — enough to tell a
    /// permission problem from a missing device from an engine problem.
    private static func diagnostics(_ input: AVAudioInputNode) -> String {
        let out = input.outputFormat(forBus: 0)
        let hardware = input.inputFormat(forBus: 0)
        var parts = [
            "format \(Int(out.sampleRate)) Hz/\(out.channelCount) ch",
            "hardware \(Int(hardware.sampleRate)) Hz/\(hardware.channelCount) ch",
        ]
        switch AVAudioApplication.shared.recordPermission {
        case .granted: parts.append("mic permission granted")
        case .denied: parts.append("mic permission denied")
        default: parts.append("mic permission undetermined")
        }
        #if os(iOS) || targetEnvironment(macCatalyst)
        let session = AVAudioSession.sharedInstance()
        parts.append(session.isInputAvailable ? "input available" : "no input available")
        parts.append("\(session.availableInputs?.count ?? 0) inputs")
        #endif
        return parts.joined(separator: ", ")
    }

    // MARK: - Background-thread callbacks

    /// The permission callback arrives on a background queue.
    private nonisolated static func speechAuthorization() async -> SFSpeechRecognizerAuthorizationStatus {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
    }

    /// Audio thread: append the buffer to the recognizer and report an RMS
    /// level (scaled so normal speech sits around 0.3–0.8).
    private nonisolated static func makeTap(
        request: SFSpeechAudioBufferRecognitionRequest,
        onLevel: @escaping (Float) -> Void
    ) -> AVAudioNodeTapBlock {
        let report = UncheckedSendable(onLevel)
        return { buffer, _ in
            request.append(buffer)
            guard let samples = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return }
            let count = Int(buffer.frameLength)
            var sum: Float = 0
            for i in 0..<count { sum += samples[i] * samples[i] }
            let rms = (sum / Float(count)).squareRoot()
            let level = min(1, rms * 12)
            Task { @MainActor in report.value(level) }
        }
    }

    /// Recognizer queue: forward each revision of the transcript. A final
    /// result with no error just means the utterance ended — not a failure.
    private nonisolated static func makeResultHandler(
        onPartial: @escaping (String) -> Void,
        onError: @escaping (String) -> Void
    ) -> (SFSpeechRecognitionResult?, Error?) -> Void {
        let partial = UncheckedSendable(onPartial)
        let failure = UncheckedSendable(onError)
        return { result, error in
            if let text = result?.bestTranscription.formattedString {
                Task { @MainActor in partial.value(text) }
            }
            if let error = error as NSError?, !Self.isBenign(error) {
                let message = "Speech recognition stopped: \(error.localizedDescription)"
                Task { @MainActor in failure.value(message) }
            }
        }
    }

    /// Cancelling a task (on stop / submit) reports an error; so does a
    /// silence timeout with nothing said. Neither should reach the user.
    private nonisolated static func isBenign(_ error: NSError) -> Bool {
        // kAFAssistantErrorDomain 216 = cancelled, 1110 = no speech detected;
        // 301 = request was cancelled (SFSpeechErrorDomain).
        [216, 1110, 301].contains(error.code)
    }

    enum TranscriberError: LocalizedError {
        case recognizerUnavailable
        case noMicrophone(String)

        var errorDescription: String? {
            switch self {
            case .recognizerUnavailable: return "Speech recognition isn't available right now."
            case .noMicrophone(let details): return "No microphone input was found (\(details))."
            }
        }
    }
}

/// Carries a main-actor callback across the audio/recognizer threads. Safe
/// because the wrapped closure is only ever invoked inside `@MainActor` tasks.
private struct UncheckedSendable<Value>: @unchecked Sendable {
    let value: Value
    init(_ value: Value) { self.value = value }
}
