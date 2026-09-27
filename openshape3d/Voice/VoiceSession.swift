//
//  VoiceSession.swift
//  openshape3d
//
//  PrintCAD V1.1: state behind the voice panel — permission, listening, the
//  live transcript, and what Enter submits. The microphone/recognizer sits
//  behind `SpeechTranscribing` so this logic is tested with a fake; the real
//  one is `LiveSpeechTranscriber`.
//

import Foundation
import Observation

enum SpeechAuthorization: Equatable {
    case authorized
    /// Microphone or speech recognition refused / unavailable; the string is
    /// shown to the user and says how to fix it.
    case denied(String)
}

/// The seam between the panel's logic and the real microphone.
@MainActor
protocol SpeechTranscribing: AnyObject {
    func requestAuthorization() async -> SpeechAuthorization
    /// Start streaming. `onPartial` receives the whole transcript so far
    /// (not a delta) every time the recognizer revises it. `onLevel` is the
    /// input level, 0…1, for the meter. All callbacks arrive on the main actor.
    func start(onPartial: @escaping (String) -> Void,
               onLevel: @escaping (Float) -> Void,
               onError: @escaping (String) -> Void) throws
    func stop()
}

@MainActor
@Observable
final class VoiceSession {
    enum Phase: Equatable {
        case idle
        case starting
        case listening
        /// Cannot listen; message explains why (permission, no recognizer…).
        case unavailable(String)
    }

    private(set) var phase: Phase = .idle
    /// Live transcript of the current utterance.
    private(set) var transcript = ""
    /// Input level 0…1 for the meter.
    private(set) var level: Float = 0
    /// The last request Enter produced — shown in the panel in V1.1.
    private(set) var lastRequest: VoiceRequest?

    @ObservationIgnored private let makeTranscriber: @MainActor () -> SpeechTranscribing
    @ObservationIgnored private var transcriber: SpeechTranscribing?

    /// `makeTranscriber` is called lazily on the first `start()`, so creating
    /// an editor (every test does) never touches audio.
    init(makeTranscriber: (@MainActor () -> SpeechTranscribing)? = nil) {
        self.makeTranscriber = makeTranscriber ?? { LiveSpeechTranscriber() }
    }

    var isListening: Bool { phase == .listening }

    /// Enter is only meaningful with something said.
    var canSubmit: Bool {
        !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func start() async {
        guard phase != .starting, phase != .listening else { return }
        phase = .starting
        transcript = ""
        lastRequest = nil
        let transcriber = self.transcriber ?? makeTranscriber()
        self.transcriber = transcriber

        switch await transcriber.requestAuthorization() {
        case .denied(let reason):
            phase = .unavailable(reason)
            return
        case .authorized:
            break
        }
        // Closed while the permission prompt was up.
        guard phase == .starting else { return }
        beginStreaming(transcriber)
    }

    func stop() {
        transcriber?.stop()
        phase = .idle
        level = 0
        transcript = ""
    }

    /// Enter: package what was said with what is selected. Returns nil (and
    /// changes nothing) when nothing has been said yet. Clears the transcript
    /// so the next instruction starts fresh, while listening continues.
    @discardableResult
    func submit(target: VoiceTarget) -> VoiceRequest? {
        let text = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        let request = VoiceRequest(transcript: text, target: target)
        lastRequest = request
        transcript = ""
        // Restart recognition so the next utterance is a new transcript
        // rather than a continuation of the one just submitted.
        if phase == .listening, let transcriber {
            transcriber.stop()
            phase = .starting
            beginStreaming(transcriber)
        }
        return request
    }

    private func beginStreaming(_ transcriber: SpeechTranscribing) {
        do {
            try transcriber.start(
                onPartial: { [weak self] text in
                    guard let self, self.phase == .listening else { return }
                    self.transcript = text
                },
                onLevel: { [weak self] level in self?.level = level },
                onError: { [weak self] message in
                    guard let self else { return }
                    self.transcriber?.stop()
                    self.level = 0
                    self.phase = .unavailable(message)
                }
            )
            phase = .listening
        } catch {
            phase = .unavailable("Couldn't start the microphone: \(error.localizedDescription)")
        }
    }
}
