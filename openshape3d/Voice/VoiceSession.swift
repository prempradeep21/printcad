//
//  VoiceSession.swift
//  openshape3d
//
//  PrintCAD V1: state behind the voice panel. One utterance at a time:
//  open → listen → (recognizer finishes after a pause, or Enter) → mic off.
//  Enter sends the words + the current pick to Jev and shows its decision.
//  Nothing listens continuously: the mic comes back only when the user taps it.
//
//  The microphone sits behind `SpeechTranscribing` and Jev behind
//  `VoiceClassifying`, so all of this is tested with fakes.
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
    /// Start one utterance. `onPartial` receives the utterance so far (not a
    /// delta) each time the recognizer revises it; `onEnd` fires once when the
    /// recognizer decides the utterance is over (the transcriber has stopped
    /// itself by then). `onLevel` is 0…1 for the meter. Main-actor callbacks.
    func start(onPartial: @escaping (String) -> Void,
               onLevel: @escaping (Float) -> Void,
               onEnd: @escaping () -> Void,
               onError: @escaping (String) -> Void) throws
    func stop()
}

@MainActor
@Observable
final class VoiceSession {
    enum Phase: Equatable {
        /// Mic off. Anything heard is kept until Enter or close.
        case idle
        case starting
        case listening
        /// Cannot listen; message explains why (permission, no recognizer…).
        case unavailable(String)
    }

    /// What happened to the last thing sent with Enter.
    enum Outcome: Equatable {
        case none
        case asking(VoiceRequest)
        case decided(VoiceRequest, VoiceDecision)
        case failed(VoiceRequest, String)
    }

    private(set) var phase: Phase = .idle
    /// What has been heard since the last Enter (across mic pauses).
    private(set) var transcript = ""
    /// Input level 0…1 for the meter.
    private(set) var level: Float = 0
    private(set) var outcome: Outcome = .none

    /// What applying the decision did (V1.3): "Ø5 mm hole, through", or why not.
    struct Applied: Equatable {
        let ok: Bool
        let message: String
    }
    private(set) var applied: Applied?

    /// Called with a decision that is sure enough to act on (or one the user
    /// picked). The editor applies it and answers with `reportApplied`.
    @ObservationIgnored var onDecision: ((VoiceRequest, VoiceDecision) -> Void)?

    @ObservationIgnored private let makeTranscriber: @MainActor () -> SpeechTranscribing
    @ObservationIgnored private var transcriber: SpeechTranscribing?
    @ObservationIgnored private let classifier: VoiceClassifying
    /// Joins utterances when the user taps the mic again before Enter.
    @ObservationIgnored private var heard = TranscriptAccumulator()
    /// Bumped on every Enter/close so a slow Jev reply can't land on a newer one.
    @ObservationIgnored private var requestToken = 0

    /// `makeTranscriber` is called lazily on the first `start()`, so creating
    /// an editor (every test does) never touches audio or the network.
    init(makeTranscriber: (@MainActor () -> SpeechTranscribing)? = nil,
         classifier: VoiceClassifying? = nil) {
        self.makeTranscriber = makeTranscriber ?? { LiveSpeechTranscriber() }
        self.classifier = classifier ?? JevVoiceClassifier()
    }

    var isListening: Bool { phase == .listening }

    var isAsking: Bool {
        if case .asking = outcome { return true }
        return false
    }

    /// Enter needs something said and no request already in flight.
    var canSubmit: Bool {
        !isAsking && !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Listen for one utterance. Words already heard (not yet sent) are kept
    /// and the new ones are added after them.
    func start() async {
        guard phase != .starting, phase != .listening else { return }
        phase = .starting
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
        do {
            try transcriber.start(
                onPartial: { [weak self] text in
                    guard let self, self.phase == .listening else { return }
                    self.transcript = self.heard.revise(text)
                },
                onLevel: { [weak self] level in self?.level = level },
                onEnd: { [weak self] in
                    guard let self, self.phase == .listening else { return }
                    self.finishUtterance()
                },
                onError: { [weak self] message in
                    guard let self else { return }
                    self.transcriber?.stop()
                    self.heard.segmentEnded()
                    self.level = 0
                    self.phase = .unavailable(message)
                }
            )
            phase = .listening
        } catch {
            phase = .unavailable("Couldn't start the microphone: \(error.localizedDescription)")
        }
    }

    /// Mic off, keep what was heard (the mic button while listening).
    func pauseListening() {
        guard phase == .listening || phase == .starting else { return }
        transcriber?.stop()
        finishUtterance()
    }

    /// Close: mic off, forget everything, ignore any reply still coming.
    func stop() {
        transcriber?.stop()
        requestToken += 1
        heard.reset()
        phase = .idle
        level = 0
        transcript = ""
        outcome = .none
        applied = nil
    }

    /// Enter: stop listening and send the words + the pick to Jev. Returns the
    /// request (nil when nothing was said or a request is already in flight).
    @discardableResult
    func submit(target: VoiceTarget) -> VoiceRequest? {
        guard canSubmit else { return nil }
        let request = VoiceRequest(
            transcript: transcript.trimmingCharacters(in: .whitespacesAndNewlines),
            target: target)
        if phase == .listening || phase == .starting {
            transcriber?.stop()
            phase = .idle
            level = 0
        }
        heard.reset()
        transcript = ""
        requestToken += 1
        let token = requestToken
        outcome = .asking(request)
        applied = nil
        Task { await self.ask(request, token: token) }
        return request
    }

    /// The user picked an option after an unsure answer.
    func choose(_ action: VoiceAction) {
        guard case .decided(let request, var decision) = outcome else { return }
        decision.action = action
        decision.confidence = 1
        outcome = .decided(request, decision)
        onDecision?(request, decision)
    }

    func reportApplied(ok: Bool, message: String) {
        applied = Applied(ok: ok, message: message)
    }

    private func ask(_ request: VoiceRequest, token: Int) async {
        let result: Outcome
        do {
            result = .decided(request, try await classifier.decide(request))
        } catch {
            result = .failed(request, (error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
        }
        guard token == requestToken else { return }   // closed or superseded
        outcome = result
        if case .decided(let request, let decision) = result, !decision.needsConfirmation {
            onDecision?(request, decision)
        }
    }

    private func finishUtterance() {
        heard.segmentEnded()
        transcript = heard.text
        phase = .idle
        level = 0
    }
}
