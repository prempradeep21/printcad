//
//  VoiceEditTests.swift
//  openshape3dTests
//
//  PrintCAD V1 — the voice panel: selection → VoiceTarget, the session's
//  permission / one-utterance listening / Enter → Jev behaviour (with a fake
//  microphone and a fake Jev, so no test opens real audio, a permission
//  prompt or the network), and the Cmd+Shift+V command wiring. Nothing here
//  edits geometry; that starts in V1.3.
//

import XCTest
import SwiftData
import simd
@testable import openshape3d

/// Stands in for the microphone + recognizer.
@MainActor
final class FakeTranscriber: SpeechTranscribing {
    var authorization: SpeechAuthorization = .authorized
    var startError: Error?
    /// When set, `requestAuthorization` waits here until the test resumes it.
    var holdAuthorization = false
    private var pendingAuthorization: CheckedContinuation<SpeechAuthorization, Never>?

    private(set) var startCount = 0
    private(set) var stopCount = 0
    private(set) var isRunning = false
    private var onPartial: ((String) -> Void)?
    private var onLevel: ((Float) -> Void)?
    private var onEnd: (() -> Void)?
    private var onError: ((String) -> Void)?

    func requestAuthorization() async -> SpeechAuthorization {
        guard holdAuthorization else { return authorization }
        return await withCheckedContinuation { pendingAuthorization = $0 }
    }

    func releaseAuthorization() {
        pendingAuthorization?.resume(returning: authorization)
        pendingAuthorization = nil
    }

    func start(onPartial: @escaping (String) -> Void,
               onLevel: @escaping (Float) -> Void,
               onEnd: @escaping () -> Void,
               onError: @escaping (String) -> Void) throws {
        if let startError { throw startError }
        startCount += 1
        isRunning = true
        self.onPartial = onPartial
        self.onLevel = onLevel
        self.onEnd = onEnd
        self.onError = onError
    }

    func stop() {
        stopCount += 1
        isRunning = false
    }

    func hear(_ text: String) { onPartial?(text) }
    func level(_ value: Float) { onLevel?(value) }
    /// The recognizer decided the utterance is over (it stops itself first).
    func finish() {
        isRunning = false
        onEnd?()
    }
    func fail(_ message: String) { onError?(message) }
}

/// Stands in for Jev. Answers with `decision` (or throws `error`) and records
/// what it was asked. `hold` keeps the reply back until `release()`.
@MainActor
final class FakeClassifier: VoiceClassifying {
    var decision = VoiceDecision.sample()
    var error: Error?
    var hold = false
    private(set) var asked: [VoiceRequest] = []
    private var pending: CheckedContinuation<Void, Never>?

    func decide(_ request: VoiceRequest) async throws -> VoiceDecision {
        asked.append(request)
        if hold { await withCheckedContinuation { pending = $0 } }
        if let error { throw error }
        return decision
    }

    func release() {
        pending?.resume()
        pending = nil
    }
}

extension VoiceDecision {
    static func sample(_ action: VoiceAction = .hole, confidence: Double = 1) -> VoiceDecision {
        VoiceDecision(action: action, confidence: confidence,
                      alternatives: [.init(action: action, probability: confidence)],
                      placement: .faceCenter, depth: .throughAll, numbers: [],
                      model: "jev-test", latency: 0.4)
    }
}

private struct BoomError: LocalizedError {
    var errorDescription: String? { "boom" }
}

/// Lets the session's Enter → Jev task run.
@MainActor
private func settle() async {
    for _ in 0..<10 { await Task.yield() }
}

// MARK: - VoiceTarget (pure)

final class VoiceTargetTests: XCTestCase {
    func testChipTextNamesWhatIsSelected() {
        XCTAssertEqual(VoiceTarget.nothing.chipText, "Nothing selected")
        XCTAssertEqual(VoiceTarget.bodies(count: 1).chipText, "Body")
        XCTAssertEqual(VoiceTarget.bodies(count: 3).chipText, "3 bodies")
        XCTAssertEqual(VoiceTarget.edges(count: 1).chipText, "Edge")
        XCTAssertEqual(VoiceTarget.edges(count: 4).chipText, "4 edges")
    }

    func testFaceAreaIsRoundedToOneDecimalAndDropsATrailingZero() {
        XCTAssertEqual(VoiceTarget.face(areaMM2: 800).chipText, "Face · 800 mm²")
        XCTAssertEqual(VoiceTarget.face(areaMM2: 12.34).chipText, "Face · 12.3 mm²")
        XCTAssertEqual(VoiceTarget.face(areaMM2: 3.999).chipText, "Face · 4 mm²")
    }

    func testASketchProfileIsNamedAsSuch() {
        XCTAssertEqual(VoiceTarget.sketchProfile(areaMM2: 3060).chipText, "Sketch profile · 3060 mm²")
        XCTAssertEqual(VoiceTarget.sketchProfile(areaMM2: 3060).classifierDescription,
                       "one closed sketch profile (not a solid yet), area 3060 mm²")
    }

    func testClassifierDescriptionIsOneShortLine() {
        XCTAssertEqual(VoiceTarget.face(areaMM2: 800).classifierDescription, "one face, area 800 mm²")
        XCTAssertEqual(VoiceTarget.edges(count: 2).classifierDescription, "2 edges")
        XCTAssertEqual(VoiceTarget.nothing.classifierDescription, "nothing selected")
    }
}

// MARK: - TranscriptAccumulator (pure)

/// Joins what was heard across mic taps before Enter.
final class TranscriptAccumulatorTests: XCTestCase {
    func testRevisionsReplaceEachOtherWithinOneSegment() {
        var t = TranscriptAccumulator()
        XCTAssertEqual(t.revise("drill"), "drill")
        XCTAssertEqual(t.revise("drill a hole"), "drill a hole")
        XCTAssertEqual(t.text, "drill a hole")
    }

    func testAPauseMidSentenceKeepsTheFirstHalf() {
        var t = TranscriptAccumulator()
        t.revise("drill a 5 mm hole")
        XCTAssertEqual(t.segmentEnded(), "drill a 5 mm hole")
        XCTAssertEqual(t.revise("in the"), "drill a 5 mm hole in the")
        XCTAssertEqual(t.revise("in the centre"), "drill a 5 mm hole in the centre")
    }

    func testSilentSegmentsAddNothing() {
        var t = TranscriptAccumulator()
        t.segmentEnded()
        t.revise("")
        t.segmentEnded()
        XCTAssertEqual(t.text, "")
        t.revise("  chamfer ")
        XCTAssertEqual(t.text, "chamfer")
    }

    func testResetStartsOver() {
        var t = TranscriptAccumulator()
        t.revise("fillet")
        t.segmentEnded()
        t.reset()
        XCTAssertEqual(t.text, "")
        XCTAssertEqual(t.revise("undo"), "undo")
    }
}

// MARK: - VoiceSession (fake microphone, fake Jev)

@MainActor
final class VoiceSessionTests: XCTestCase {
    private func session(_ fake: FakeTranscriber, _ jev: FakeClassifier? = nil) -> VoiceSession {
        VoiceSession(makeTranscriber: { fake }, classifier: jev ?? FakeClassifier())
    }

    func testStartingWithPermissionListensAndShowsWordsAsTheyAreHeard() async {
        let fake = FakeTranscriber()
        let voice = session(fake)
        await voice.start()
        XCTAssertEqual(voice.phase, .listening)
        XCTAssertEqual(fake.startCount, 1)

        // The recognizer revises the whole utterance as it goes.
        fake.hear("drill")
        XCTAssertEqual(voice.transcript, "drill")
        fake.hear("drill a hole in the")
        fake.hear("drill a hole in the centre")
        XCTAssertEqual(voice.transcript, "drill a hole in the centre")
        fake.level(0.6)
        XCTAssertEqual(voice.level, 0.6)
    }

    func testDeniedPermissionExplainsWhyAndNeverOpensTheMicrophone() async {
        let fake = FakeTranscriber()
        fake.authorization = .denied("Microphone access is off.")
        let voice = session(fake)
        await voice.start()
        XCTAssertEqual(voice.phase, .unavailable("Microphone access is off."))
        XCTAssertEqual(fake.startCount, 0)
    }

    func testAMicrophoneThatFailsToStartIsReportedNotSwallowed() async {
        let fake = FakeTranscriber()
        fake.startError = BoomError()
        let voice = session(fake)
        await voice.start()
        guard case .unavailable(let message) = voice.phase else {
            return XCTFail("expected unavailable, got \(voice.phase)")
        }
        XCTAssertTrue(message.contains("boom"), message)
    }

    func testARecognizerErrorStopsTheMicrophoneAndShowsTheMessage() async {
        let fake = FakeTranscriber()
        let voice = session(fake)
        await voice.start()
        fake.fail("Speech recognition stopped: network")
        XCTAssertEqual(voice.phase, .unavailable("Speech recognition stopped: network"))
        XCTAssertFalse(fake.isRunning)
        XCTAssertEqual(voice.level, 0)
    }

    func testClosingWhileThePermissionPromptIsUpNeverStartsTheMicrophone() async {
        let fake = FakeTranscriber()
        fake.holdAuthorization = true
        let voice = session(fake)
        let starting = Task { await voice.start() }
        await Task.yield()
        XCTAssertEqual(voice.phase, .starting)
        voice.stop()
        fake.releaseAuthorization()
        await starting.value
        XCTAssertEqual(voice.phase, .idle)
        XCTAssertEqual(fake.startCount, 0)
    }

    // MARK: No continuous listening (Prem, 2026-09-28)

    func testWhenTheUtteranceEndsTheMicStaysOffAndTheWordsStay() async {
        let fake = FakeTranscriber()
        let voice = session(fake)
        await voice.start()
        fake.hear("drill a hole in the centre")
        fake.finish()
        XCTAssertEqual(voice.phase, .idle, "mic off after the recognizer finishes")
        XCTAssertEqual(voice.transcript, "drill a hole in the centre")
        XCTAssertEqual(fake.startCount, 1, "never restarts on its own")
        XCTAssertTrue(voice.canSubmit)
    }

    func testTappingTheMicAgainBeforeEnterAddsToWhatWasHeard() async {
        let fake = FakeTranscriber()
        let voice = session(fake)
        await voice.start()
        fake.hear("drill a 5 mm hole")
        fake.finish()
        await voice.start()
        XCTAssertEqual(fake.startCount, 2)
        fake.hear("in the centre")
        XCTAssertEqual(voice.transcript, "drill a 5 mm hole in the centre")
    }

    func testPausingByHandKeepsTheWordsAndStopsTheMic() async {
        let fake = FakeTranscriber()
        let voice = session(fake)
        await voice.start()
        fake.hear("chamfer 1 mm")
        voice.pauseListening()
        XCTAssertEqual(voice.phase, .idle)
        XCTAssertFalse(fake.isRunning)
        XCTAssertEqual(voice.transcript, "chamfer 1 mm")
    }

    // MARK: Enter → Jev

    func testEnterWithNothingSaidDoesNothing() async {
        let fake = FakeTranscriber()
        let jev = FakeClassifier()
        let voice = session(fake, jev)
        await voice.start()
        fake.hear("   ")
        XCTAssertFalse(voice.canSubmit)
        XCTAssertNil(voice.submit(target: .nothing))
        await settle()
        XCTAssertTrue(jev.asked.isEmpty)
        XCTAssertEqual(voice.outcome, .none)
    }

    func testEnterStopsListeningAndSendsTheWordsWithTheTargetToJev() async {
        let fake = FakeTranscriber()
        let jev = FakeClassifier()
        jev.hold = true
        let voice = session(fake, jev)
        await voice.start()
        fake.hear("  drill a hole in the centre ")

        let request = voice.submit(target: .face(areaMM2: 800))
        let expected = VoiceRequest(transcript: "drill a hole in the centre", target: .face(areaMM2: 800))
        XCTAssertEqual(request, expected)
        XCTAssertEqual(voice.phase, .idle, "Enter turns the mic off")
        XCTAssertFalse(fake.isRunning)
        XCTAssertEqual(fake.startCount, 1, "and does not start listening again")
        XCTAssertEqual(voice.transcript, "")
        XCTAssertEqual(voice.outcome, .asking(expected))
        XCTAssertFalse(voice.canSubmit, "no second Enter while Jev is answering")

        await settle()
        XCTAssertEqual(jev.asked, [expected])
        jev.release()
        await settle()
        XCTAssertEqual(voice.outcome, .decided(expected, .sample()))
    }

    func testAJevFailureIsShownNotSwallowed() async {
        let fake = FakeTranscriber()
        let jev = FakeClassifier()
        jev.error = JevError.unauthorized
        let voice = session(fake, jev)
        await voice.start()
        fake.hear("fillet 2 mm")
        voice.submit(target: .edges(count: 1))
        await settle()
        guard case .failed(_, let message) = voice.outcome else {
            return XCTFail("expected failed, got \(voice.outcome)")
        }
        XCTAssertTrue(message.contains("401"), message)
    }

    func testClosingWhileJevIsAnsweringDropsTheLateReply() async {
        let fake = FakeTranscriber()
        let jev = FakeClassifier()
        jev.hold = true
        let voice = session(fake, jev)
        await voice.start()
        fake.hear("undo")
        voice.submit(target: .nothing)
        await settle()
        voice.stop()
        jev.release()
        await settle()
        XCTAssertEqual(voice.outcome, .none)
    }

    func testPickingAnOptionAfterAnUnsureAnswerConfirmsIt() async {
        let fake = FakeTranscriber()
        let jev = FakeClassifier()
        jev.decision = .sample(.boss, confidence: 0.45)
        let voice = session(fake, jev)
        await voice.start()
        fake.hear("put a thing here")
        let request = voice.submit(target: .face(areaMM2: 100))!
        await settle()
        guard case .decided(_, let unsure) = voice.outcome else { return XCTFail("\(voice.outcome)") }
        XCTAssertTrue(unsure.needsConfirmation)

        voice.choose(.hole)
        guard case .decided(let sameRequest, let chosen) = voice.outcome else { return XCTFail("\(voice.outcome)") }
        XCTAssertEqual(sameRequest, request)
        XCTAssertEqual(chosen.action, .hole)
        XCTAssertEqual(chosen.confidence, 1)
        XCTAssertFalse(chosen.needsConfirmation)
    }

    func testStopClearsEverythingAndLateWordsAreIgnored() async {
        let fake = FakeTranscriber()
        let voice = session(fake)
        await voice.start()
        fake.hear("chamfer")
        voice.stop()
        XCTAssertEqual(voice.phase, .idle)
        XCTAssertFalse(fake.isRunning)
        XCTAssertEqual(voice.transcript, "")
        fake.hear("chamfer one mm")   // a late callback after close
        XCTAssertEqual(voice.transcript, "")
    }

    func testReopeningAfterDenialAsksAgain() async {
        let fake = FakeTranscriber()
        fake.authorization = .denied("off")
        let voice = session(fake)
        await voice.start()
        fake.authorization = .authorized
        await voice.start()
        XCTAssertEqual(voice.phase, .listening)
    }
}

// MARK: - Editor wiring

@MainActor
final class EditorVoiceTests: XCTestCase {
    private static var retained: [EditorViewModel] = []
    private let jev = FakeClassifier()

    private func makeViewModel() throws -> (EditorViewModel, FakeTranscriber) {
        let schema = Schema([Project.self, PersistedBody.self, PersistedSketch.self,
                             PersistedPlane.self, PersistedImage.self, PersistedSymbol.self])
        let container = try ModelContainer(for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        let context = ModelContext(container)
        let project = Project(name: "Voice Test")
        context.insert(project)
        let vm = EditorViewModel(project: project, modelContext: context)
        Self.retained.append(vm)
        let fake = FakeTranscriber()
        vm.voice = VoiceSession(makeTranscriber: { fake }, classifier: jev)
        return (vm, fake)
    }

    /// 2 × 2 × 2 box: x, z in −1…1, y in 0…2 (same fixture as SelectionTests).
    @discardableResult
    private func addBox(to vm: EditorViewModel) -> Body {
        var document = vm.session.document
        let body = Body(name: "Block", transform: .identity,
                        euclidMesh: .primitive(.box(width: 2, depth: 2, height: 2)),
                        revision: document.nextRevision())
        vm.session.perform(AddBodyCommand(body: body))
        return body
    }

    func testCommandShiftVIsARoutableLaunchableCommand() throws {
        let command = try XCTUnwrap(CommandRegistry.all.first { $0.id == "app.voice" })
        XCTAssertEqual(command.title, "Voice Edit")
        XCTAssertEqual(command.chord, KeyChord("v", [.command, .shift]))
        XCTAssertTrue(CommandRegistry.routableIDs.contains("app.voice"))
        XCTAssertTrue(CommandRegistry.launchableCommands.contains { $0.id == "app.voice" },
                      "offered by Command Search too")
    }

    func testTheCommandTogglesThePanelAndTheMicrophone() async throws {
        let (vm, fake) = try makeViewModel()
        XCTAssertFalse(vm.voiceActive)

        XCTAssertTrue(vm.runCommand("app.voice"))
        XCTAssertTrue(vm.voiceActive)
        await settle()
        XCTAssertEqual(vm.voice.phase, .listening)
        XCTAssertTrue(fake.isRunning)

        XCTAssertTrue(vm.runCommand("app.voice"))
        XCTAssertFalse(vm.voiceActive)
        XCTAssertFalse(fake.isRunning)
        XCTAssertEqual(vm.voice.phase, .idle)
    }

    func testTargetFollowsWhatTheUserClicks() throws {
        let (vm, _) = try makeViewModel()
        let box = addBox(to: vm)
        XCTAssertEqual(vm.voiceTarget, .nothing)

        // Near the top face's +x edge: the edge.
        vm.handle(.tap(ray: Ray(origin: SIMD3(0.97, 10, 0.3), direction: SIMD3(0, -1, 0))))
        XCTAssertEqual(vm.voiceTarget, .edges(count: 1))

        vm.cancelBlend()
        XCTAssertEqual(vm.mode, .selected(box.id))
        XCTAssertEqual(vm.voiceTarget, .bodies(count: 1))

        // Middle of the top face: the face, 2 × 2 = 4 mm².
        vm.handle(.tap(ray: Ray(origin: SIMD3(0.5, 10, 0.3), direction: SIMD3(0, -1, 0))))
        XCTAssertEqual(vm.mode, .faceSelected(box.id))
        guard case .face(let area) = vm.voiceTarget else {
            return XCTFail("expected a face target, got \(vm.voiceTarget)")
        }
        XCTAssertEqual(area, 4, accuracy: 1e-6)
    }

    /// Mac, 2026-09-28: a picked sketch rectangle (extrude arrow up) read
    /// "Nothing selected".
    func testAPickedSketchProfileIsTheTarget() throws {
        let (vm, _) = try makeViewModel()
        let sketch = Sketch(name: "Base", plane: .ground,
                            entities: [.circle(id: UUID(), center: .zero, radius: 0.8)])
        vm.session.perform(AddSketchCommand(sketch: sketch))
        vm.presentSelectThrough(ray: Ray(origin: SIMD3(0.2, 20, 0.3), direction: SIMD3(0, -1, 0)))
        let profile = try XCTUnwrap(vm.selectThroughCandidates?.first {
            if case .profile = $0.target { return true }; return false
        })
        vm.chooseSelectThrough(profile)
        XCTAssertEqual(vm.mode, .extruding)
        guard case .sketchProfile(let area) = vm.voiceTarget else {
            return XCTFail("expected a sketch profile, got \(vm.voiceTarget)")
        }
        XCTAssertEqual(area, Double.pi * 0.8 * 0.8, accuracy: 0.02, "polygonised circle")
    }

    func testEnterSendsTheWordsAndTheClickedFaceToJevAndChangesNoGeometry() async throws {
        let (vm, fake) = try makeViewModel()
        addBox(to: vm)
        vm.openVoice()
        await settle()
        vm.handle(.tap(ray: Ray(origin: SIMD3(0.5, 10, 0.3), direction: SIMD3(0, -1, 0))))
        fake.hear("draw a hole in the center of this surface")
        let changesBefore = vm.session.changeCount

        let request = try XCTUnwrap(vm.submitVoice())
        XCTAssertEqual(request.transcript, "draw a hole in the center of this surface")
        guard case .face(let area) = request.target else {
            return XCTFail("expected the clicked face, got \(request.target)")
        }
        XCTAssertEqual(area, 4, accuracy: 1e-6)
        await settle()
        XCTAssertEqual(jev.asked, [request])
        XCTAssertEqual(vm.voice.outcome, .decided(request, .sample()))
        XCTAssertEqual(vm.session.changeCount, changesBefore, "V1.2 never edits the model")
        XCTAssertTrue(vm.voiceActive, "the panel stays open to show Jev's answer")
        XCTAssertFalse(fake.isRunning, "and the mic is off")
    }
}
