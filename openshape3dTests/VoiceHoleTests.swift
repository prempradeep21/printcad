//
//  VoiceHoleTests.swift
//  openshape3dTests
//
//  PrintCAD V1.3 — Jev's decision becomes geometry. Pure sizing/centroid
//  checks, then real-kernel checks on a parametric 40 × 20 × 2 mm plate:
//  "drill a hole in the centre" removes π·r²·2 mm³, is ONE undo step, and a
//  failure keeps the last valid model. Jev and the microphone are fakes.
//

import XCTest
import SwiftData
import simd
@testable import openshape3d

// MARK: - Sizing (pure)

final class VoiceRecipeTests: XCTestCase {
    private func decision(_ numbers: [(String, NumberRole)], depth: VoiceDepth = .throughAll) -> VoiceDecision {
        let parsed = SpokenNumberParser.numbers(in: numbers.map(\.0).joined(separator: " "))
        XCTAssertEqual(parsed.count, numbers.count, "fixture parse")
        return VoiceDecision(
            action: .hole, confidence: 1, alternatives: [], placement: .faceCenter, depth: depth,
            numbers: zip(parsed, numbers).map { .init(number: $0, role: $1.1, confidence: 1) },
            model: "m", latency: 0)
    }

    func testNoSizeSaidIsAFiveMillimetreThroughHole() {
        XCTAssertEqual(try VoiceRecipe.hole(from: decision([])).get(), HoleSpec(diameter: 5, depth: nil))
    }

    func testASpokenDiameterIsUsedExactly() {
        XCTAssertEqual(try VoiceRecipe.hole(from: decision([("seven mm", .diameter)])).get().diameter, 7)
    }

    func testARadiusIsDoubled() {
        XCTAssertEqual(try VoiceRecipe.hole(from: decision([("2 mm", .radius)])).get().diameter, 4)
    }

    func testAFastenerSizeGetsThePrinterClearance() {
        XCTAssertEqual(try VoiceRecipe.hole(from: decision([("M3", .diameter)])).get().diameter, 3.2, accuracy: 1e-9)
        // Even if Jev labels it something else, M3 is still a diameter.
        XCTAssertEqual(try VoiceRecipe.hole(from: decision([("M3", .other)])).get().diameter, 3.2, accuracy: 1e-9)
    }

    func testABlindHoleUsesTheSpokenDepth() {
        let spec = try? VoiceRecipe.hole(from: decision([("3 mm", .diameter), ("1 mm", .depth)], depth: .blind)).get()
        XCTAssertEqual(spec, HoleSpec(diameter: 3, depth: 1))
    }

    func testABlindHoleWithNoDepthAsksInsteadOfGuessing() {
        XCTAssertEqual(VoiceRecipe.hole(from: decision([("3 mm", .diameter)], depth: .blind)), .failure(.missingDepth))
    }

    func testSummaries() {
        XCTAssertEqual(VoiceRecipe.summary(HoleSpec(diameter: 5, depth: nil)), "Ø5 mm hole, through")
        XCTAssertEqual(VoiceRecipe.summary(HoleSpec(diameter: 3.2, depth: 1.5)), "Ø3.2 mm hole, 1.5 mm deep")
    }

    func testCentroidOfARectangleIsItsMiddle() {
        let c = VoiceRecipe.centroid(of: [SIMD2(-20, -10), SIMD2(20, -10), SIMD2(20, 10), SIMD2(-20, 10)])
        XCTAssertEqual(c.x, 0, accuracy: 1e-9)
        XCTAssertEqual(c.y, 0, accuracy: 1e-9)
    }

    /// The face plane's origin is the VERTEX average; for an L the balance
    /// point differs, and the balance point is "the centre".
    func testCentroidOfAnLShapeIsTheAreaCentroidNotTheVertexAverage() {
        // 20 × 20 square with the top-right 10 × 10 quarter removed.
        let l: [SIMD2<Double>] = [SIMD2(0, 0), SIMD2(20, 0), SIMD2(20, 10), SIMD2(10, 10), SIMD2(10, 20), SIMD2(0, 20)]
        let c = VoiceRecipe.centroid(of: l)
        // Area 300: (200·(10,5) + 100·(5,15)) / 300 = (8.333, 8.333).
        XCTAssertEqual(c.x, 25.0 / 3, accuracy: 1e-9)
        XCTAssertEqual(c.y, 25.0 / 3, accuracy: 1e-9)
        let vertexAverage = l.reduce(.zero, +) / Double(l.count)
        XCTAssertNotEqual(vertexAverage.x, c.x, accuracy: 0.5)
    }
}

// MARK: - Real geometry

@MainActor
final class VoiceHoleGeometryTests: XCTestCase {
    private static var retained: [EditorViewModel] = []
    private var jev: FakeClassifier!
    private var mic: FakeTranscriber!

    private func makeViewModel() throws -> EditorViewModel {
        let schema = Schema([Project.self, PersistedBody.self, PersistedSketch.self,
                             PersistedPlane.self, PersistedImage.self, PersistedSymbol.self])
        let container = try ModelContainer(for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        let context = ModelContext(container)
        let project = Project(name: "Voice Hole Test")
        context.insert(project)
        let vm = EditorViewModel(project: project, modelContext: context)
        Self.retained.append(vm)
        jev = FakeClassifier()
        mic = FakeTranscriber()
        let mic = self.mic!
        vm.voice = VoiceSession(makeTranscriber: { mic }, classifier: jev)
        return vm
    }

    /// Parametric 40 × 20 × 2 mm plate (x ±20, z ±10, y 0…2), owned by a
    /// feature node like a sketched-and-extruded plate would be.
    @discardableResult
    private func addPlate(to vm: EditorViewModel) -> BodyID {
        let id = BodyID()
        vm.session.recordAndRebuild([FeatureNode(
            name: "Plate",
            kind: .primitive(spec: .box(width: 40, depth: 20, height: 2), placement: .identity),
            outputBodyIDs: [id])], title: "Plate")
        return id
    }

    private func volume(_ vm: EditorViewModel, _ id: BodyID) -> Double {
        MeasureKit.volume(of: vm.session.document.body(with: id)!)
    }

    private func pickTopFace(_ vm: EditorViewModel, at x: Double = 5, _ z: Double = 3) {
        vm.handle(.tap(ray: Ray(origin: SIMD3(Float(x), 10, Float(z)), direction: SIMD3(0, -1, 0))))
    }

    /// Say `words` with the top face picked and let Jev answer `decision`.
    private func speak(_ vm: EditorViewModel, _ words: String, _ decision: VoiceDecision) async {
        jev.decision = decision
        if vm.voiceActive {
            await vm.voice.start()   // tap the mic again for the next instruction
        } else {
            vm.openVoice()
        }
        await settle()
        mic.hear(words)
        vm.submitVoice()
        await settle()
    }

    private func settle() async {
        for _ in 0..<20 { await Task.yield() }
    }

    func testDrillAHoleInTheCentreCutsAFiveMillimetreThroughHoleAsOneUndoStep() async throws {
        let vm = try makeViewModel()
        let plate = addPlate(to: vm)
        let before = volume(vm, plate)
        XCTAssertEqual(before, 1600, accuracy: 1)

        pickTopFace(vm)
        XCTAssertEqual(vm.mode, .faceSelected(plate))
        let undoDepth = vm.session.undoStack.undoCommands.count

        await speak(vm, "draw a hole in the center of this surface", .sample(.hole))

        XCTAssertEqual(vm.voice.applied, .init(ok: true, message: "Ø5 mm hole, through"))
        let removed = before - volume(vm, plate)
        XCTAssertEqual(removed, Double.pi * 2.5 * 2.5 * 2, accuracy: 0.6, "a Ø5 through hole in 2 mm")
        XCTAssertEqual(vm.session.undoStack.undoCommands.count, undoDepth + 1, "ONE undo step")
        XCTAssertEqual(vm.session.undoStack.undoTitle, "Voice Hole")
        let holeSketch = try XCTUnwrap(vm.session.document.sketches.last)
        XCTAssertTrue(holeSketch.isHidden, "the consumed sketch hides like any extruded sketch")
        XCTAssertEqual(vm.mode, .selected(plate))

        vm.undo()
        XCTAssertEqual(volume(vm, plate), before, accuracy: 1e-6, "one undo brings the plate back")
        XCTAssertFalse(vm.session.document.sketches.contains { $0.id == holeSketch.id })
    }

    func testTheHoleIsAtTheCentreOfTheFaceNotWhereTheFaceWasClicked() async throws {
        let vm = try makeViewModel()
        let plate = addPlate(to: vm)
        pickTopFace(vm, at: 15, 7)   // off-centre click
        await speak(vm, "hole in the middle", .sample(.hole))
        XCTAssertEqual(vm.voice.applied?.ok, true)

        let sketch = try XCTUnwrap(vm.session.document.sketches.last)
        guard case .circle(_, let centre, let radius) = try XCTUnwrap(sketch.entities.first) else {
            return XCTFail("expected a circle")
        }
        let world = sketch.plane.toWorld(centre)
        XCTAssertEqual(world.x, 0, accuracy: 1e-6)
        XCTAssertEqual(world.z, 0, accuracy: 1e-6)
        XCTAssertEqual(world.y, 2, accuracy: 1e-6, "on the top face")
        XCTAssertEqual(radius, 2.5, accuracy: 1e-9)
        _ = plate
    }

    func testASpokenSizeAndDepthMakeABlindHole() async throws {
        let vm = try makeViewModel()
        let plate = addPlate(to: vm)
        let before = volume(vm, plate)
        pickTopFace(vm)
        let words = "4 mm hole 1 mm deep"
        let numbers = SpokenNumberParser.numbers(in: words)
        var decision = VoiceDecision.sample(.hole)
        decision = VoiceDecision(action: .hole, confidence: 1, alternatives: [], placement: .faceCenter,
                                 depth: .blind,
                                 numbers: [.init(number: numbers[0], role: .diameter, confidence: 1),
                                           .init(number: numbers[1], role: .depth, confidence: 1)],
                                 model: "m", latency: 0)
        await speak(vm, words, decision)
        XCTAssertEqual(vm.voice.applied, .init(ok: true, message: "Ø4 mm hole, 1 mm deep"))
        XCTAssertEqual(before - volume(vm, plate), Double.pi * 4 * 1, accuracy: 0.4)
    }

    func testClickingAnotherFaceWhileJevAnswersDoesNotMoveTheHole() async throws {
        let vm = try makeViewModel()
        let plate = addPlate(to: vm)
        pickTopFace(vm)
        jev.hold = true
        jev.decision = .sample(.hole)
        vm.openVoice()
        await settle()
        mic.hear("hole in the centre")
        vm.submitVoice()
        await settle()
        // Meanwhile the user clicks the side of the plate.
        vm.handle(.tap(ray: Ray(origin: SIMD3(30, 1, 0), direction: SIMD3(-1, 0, 0))))
        jev.release()
        await settle()
        XCTAssertEqual(vm.voice.applied?.ok, true)
        let sketch = try XCTUnwrap(vm.session.document.sketches.last)
        XCTAssertEqual(sketch.plane.toWorld(.zero).y, 2, accuracy: 1e-6, "still the top face")
        _ = plate
    }

    func testANonParametricBodyIsRefusedAndNothingChanges() async throws {
        let vm = try makeViewModel()
        var document = vm.session.document
        let loose = Body(name: "Imported", transform: .identity,
                         euclidMesh: .primitive(.box(width: 2, depth: 2, height: 2)),
                         revision: document.nextRevision())
        vm.session.perform(AddBodyCommand(body: loose))
        vm.handle(.tap(ray: Ray(origin: SIMD3(0.5, 10, 0.3), direction: SIMD3(0, -1, 0))))
        let changes = vm.session.changeCount
        await speak(vm, "hole in the centre", .sample(.hole))
        XCTAssertEqual(vm.voice.applied?.ok, false)
        XCTAssertTrue(vm.voice.applied?.message.contains("isn't parametric") == true, "\(String(describing: vm.voice.applied))")
        XCTAssertEqual(vm.session.changeCount, changes)
    }

    func testAHoleWithNothingPickedAsksForAFace() async throws {
        let vm = try makeViewModel()
        addPlate(to: vm)
        await speak(vm, "drill a hole", .sample(.hole))
        XCTAssertEqual(vm.voice.applied?.ok, false)
        XCTAssertTrue(vm.voice.applied?.message.contains("Click the face") == true)
    }

    func testAnUnsureAnswerIsNotAppliedUntilTheUserPicks() async throws {
        let vm = try makeViewModel()
        let plate = addPlate(to: vm)
        let before = volume(vm, plate)
        pickTopFace(vm)
        await speak(vm, "put a thing here", .sample(.boss, confidence: 0.4))
        XCTAssertNil(vm.voice.applied, "nothing applied while unsure")
        XCTAssertEqual(volume(vm, plate), before)

        vm.voice.choose(.hole)
        XCTAssertEqual(vm.voice.applied?.ok, true)
        XCTAssertLessThan(volume(vm, plate), before)
    }

    func testSayingUndoUndoesTheHole() async throws {
        let vm = try makeViewModel()
        let plate = addPlate(to: vm)
        let before = volume(vm, plate)
        pickTopFace(vm)
        await speak(vm, "hole in the centre", .sample(.hole))
        XCTAssertLessThan(volume(vm, plate), before)

        await speak(vm, "undo that", .sample(.undo))
        XCTAssertEqual(vm.voice.applied, .init(ok: true, message: "Undid the last edit"))
        XCTAssertEqual(volume(vm, plate), before, accuracy: 1e-6)
    }
}
