//
//  VoiceEditTests.swift
//  openshape3dTests
//
//  PrintCAD V1.1 — the voice panel: selection → VoiceTarget, the session's
//  permission / live-transcript / Enter behaviour (with a fake microphone, so
//  no test ever opens real audio or a permission prompt), and the Cmd+Shift+V
//  command wiring. Nothing here edits geometry; that starts in V1.3.
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
               onError: @escaping (String) -> Void) throws {
        if let startError { throw startError }
        startCount += 1
        isRunning = true
        self.onPartial = onPartial
        self.onLevel = onLevel
        self.onError = onError
    }

    func stop() {
        stopCount += 1
        isRunning = false
    }

    func hear(_ text: String) { onPartial?(text) }
    func level(_ value: Float) { onLevel?(value) }
    func fail(_ message: String) { onError?(message) }
}

private struct BoomError: LocalizedError {
    var errorDescription: String? { "boom" }
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

    func testClassifierDescriptionIsOneShortLine() {
        XCTAssertEqual(VoiceTarget.face(areaMM2: 800).classifierDescription, "one face, area 800 mm²")
        XCTAssertEqual(VoiceTarget.edges(count: 2).classifierDescription, "2 edges")
        XCTAssertEqual(VoiceTarget.nothing.classifierDescription, "nothing selected")
    }
}

// MARK: - VoiceSession (fake microphone)

@MainActor
final class VoiceSessionTests: XCTestCase {
    private func session(_ fake: FakeTranscriber) -> VoiceSession {
        VoiceSession(makeTranscriber: { fake })
    }

    func testStartingWithPermissionListensAndShowsWordsAsTheyAreHeard() async {
        let fake = FakeTranscriber()
        let voice = session(fake)
        await voice.start()
        XCTAssertEqual(voice.phase, .listening)
        XCTAssertEqual(fake.startCount, 1)

        // The recognizer revises the whole transcript as it goes.
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

    func testEnterWithNothingSaidDoesNothing() async {
        let fake = FakeTranscriber()
        let voice = session(fake)
        await voice.start()
        fake.hear("   ")
        XCTAssertFalse(voice.canSubmit)
        XCTAssertNil(voice.submit(target: .nothing))
        XCTAssertNil(voice.lastRequest)
        XCTAssertEqual(fake.startCount, 1, "no restart when nothing was submitted")
    }

    func testEnterPackagesTheWordsWithTheTargetAndStartsAFreshUtterance() async {
        let fake = FakeTranscriber()
        let voice = session(fake)
        await voice.start()
        fake.hear("  drill a hole in the centre ")
        XCTAssertTrue(voice.canSubmit)

        let request = voice.submit(target: .face(areaMM2: 800))
        XCTAssertEqual(request, VoiceRequest(transcript: "drill a hole in the centre",
                                             target: .face(areaMM2: 800)))
        XCTAssertEqual(voice.lastRequest, request)
        XCTAssertEqual(voice.transcript, "", "the next instruction starts empty")
        XCTAssertEqual(voice.phase, .listening, "still listening after Enter")
        XCTAssertEqual(fake.startCount, 2, "recognition restarted for the next utterance")

        fake.hear("fillet")
        XCTAssertEqual(voice.transcript, "fillet", "not appended to the submitted sentence")
    }

    func testStopClearsTheTranscriptAndLateWordsAreIgnored() async {
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
        vm.voice = VoiceSession(makeTranscriber: { fake })
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

    private func settle() async {
        for _ in 0..<5 { await Task.yield() }
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

    func testEnterSendsTheWordsWithTheClickedFaceAndChangesNoGeometry() async throws {
        let (vm, fake) = try makeViewModel()
        addBox(to: vm)
        vm.openVoice()
        await settle()
        vm.handle(.tap(ray: Ray(origin: SIMD3(0.5, 10, 0.3), direction: SIMD3(0, -1, 0))))
        fake.hear("draw a hole in the center of this surface")
        let changesBefore = vm.session.changeCount

        let request = try XCTUnwrap(vm.submitVoice())
        XCTAssertEqual(request.transcript, "draw a hole in the center of this surface")
        guard case .face = request.target else {
            return XCTFail("expected the clicked face, got \(request.target)")
        }
        XCTAssertEqual(vm.session.changeCount, changesBefore, "V1.1 never edits the model")
        XCTAssertTrue(vm.voiceActive, "the panel stays open for the next instruction")
    }
}
