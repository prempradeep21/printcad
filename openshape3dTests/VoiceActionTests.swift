//
//  VoiceActionTests.swift
//  openshape3dTests
//
//  PrintCAD V1 — Jev's decision becomes geometry, for every action family and
//  for multi-step commands. Pure rules first (sizing, splitting, topology
//  selectors, undo folding), then real-kernel checks on a parametric
//  40 × 20 × 2 mm plate. Jev and the microphone are fakes: these tests pin
//  what the app DOES with an answer, not what Jev answers.
//

import XCTest
import SwiftData
import simd
@testable import openshape3d

// MARK: - Sizing rules (pure)

final class VoiceRecipeTests: XCTestCase {
    func testNoSizeSaidIsAFiveMillimetreThroughHole() {
        XCTAssertEqual(try VoiceRecipe.hole(from: .sample(.hole)).get(), HoleSpec(diameter: 5, depth: nil))
    }

    func testASpokenDiameterIsUsedExactlyAndARadiusIsDoubled() {
        XCTAssertEqual(try VoiceRecipe.hole(from: .sample(numbers: [("seven mm", .diameter)])).get().diameter, 7)
        XCTAssertEqual(try VoiceRecipe.hole(from: .sample(numbers: [("2 mm", .radius)])).get().diameter, 4)
    }

    func testAFastenerSizeGetsThePrinterClearance() {
        XCTAssertEqual(try VoiceRecipe.hole(from: .sample(numbers: [("M3", .diameter)])).get().diameter, 3.2, accuracy: 1e-9)
        XCTAssertEqual(try VoiceRecipe.hole(from: .sample(numbers: [("M3", .other)])).get().diameter, 3.2, accuracy: 1e-9)
    }

    func testBlindHoles() {
        XCTAssertEqual(try? VoiceRecipe.hole(from: .sample(depth: .blind, numbers: [("3 mm", .diameter), ("1 mm", .depth)])).get(),
                       HoleSpec(diameter: 3, depth: 1))
        XCTAssertEqual(VoiceRecipe.hole(from: .sample(depth: .blind, numbers: [("3 mm", .diameter)])), .failure(.missingDepth))
    }

    func testRectangles() {
        XCTAssertEqual(VoiceRecipe.rectangle(from: .sample(.pocket, numbers: [("20", .width), ("10", .length), ("2 mm", .depth)])),
                       SIMD2(20, 10))
        XCTAssertEqual(VoiceRecipe.rectangle(from: .sample(.pocket, numbers: [("15 mm", .width)])), SIMD2(15, 15))
        // For a pad the HEIGHT is the extrusion, not a side.
        XCTAssertEqual(VoiceRecipe.rectangle(from: .sample(.pad, numbers: [("20", .width), ("5 mm", .height), ("10", .length)])),
                       SIMD2(20, 10))
        XCTAssertNil(VoiceRecipe.rectangle(from: .sample(.pocket)))
    }

    func testScaleFactors() {
        XCTAssertEqual(VoiceRecipe.scaleFactor(from: .sample(.scaleBody, numbers: [("150%", .scale)])), 1.5)
        XCTAssertEqual(VoiceRecipe.scaleFactor(from: .sample(.scaleBody, numbers: [("2", .scale)])), 2)
        XCTAssertEqual(VoiceRecipe.scaleFactor(from: .sample(.scaleBody, text: "make it twice as big")), 2)
        XCTAssertEqual(VoiceRecipe.scaleFactor(from: .sample(.scaleBody, text: "half the size")), 0.5)
        XCTAssertEqual(VoiceRecipe.scaleFactor(from: .sample(.scaleBody, relative: .bigger, text: "bigger")), 1.25)
        XCTAssertNil(VoiceRecipe.scaleFactor(from: .sample(.scaleBody, text: "scale it")))
    }

    func testRelativeChanges() {
        XCTAssertEqual(VoiceRecipe.change(5, by: .setTo, value: 6), 6)
        XCTAssertEqual(VoiceRecipe.change(5, by: .notApplicable, value: 6), 6)
        XCTAssertEqual(VoiceRecipe.change(5, by: .increaseBy, value: 2), 7)
        XCTAssertEqual(VoiceRecipe.change(5, by: .decreaseBy, value: 2), 3)
        XCTAssertEqual(VoiceRecipe.change(4, by: .bigger, value: nil), 5)
        XCTAssertEqual(VoiceRecipe.change(5, by: .smaller, value: nil), 4)
        XCTAssertNil(VoiceRecipe.change(5, by: .setTo, value: nil))
    }

    func testCentroids() {
        let rect = VoiceRecipe.centroid(of: [SIMD2(-20, -10), SIMD2(20, -10), SIMD2(20, 10), SIMD2(-20, 10)])
        XCTAssertEqual(rect.x, 0, accuracy: 1e-9)
        XCTAssertEqual(rect.y, 0, accuracy: 1e-9)
        // L-shape: the balance point, not the vertex average.
        let l: [SIMD2<Double>] = [SIMD2(0, 0), SIMD2(20, 0), SIMD2(20, 10), SIMD2(10, 10), SIMD2(10, 20), SIMD2(0, 20)]
        let c = VoiceRecipe.centroid(of: l)
        XCTAssertEqual(c.x, 25.0 / 3, accuracy: 1e-9)
        XCTAssertEqual(c.y, 25.0 / 3, accuracy: 1e-9)
    }

    func testCornersAreInsetAndRefusedWhenTheFaceIsTooSmall() {
        let corners = VoiceGeometry.corners(of: (SIMD2(-20, -10), SIMD2(20, 10)), inset: 5)
        XCTAssertEqual(corners, [SIMD2(-15, -5), SIMD2(15, -5), SIMD2(15, 5), SIMD2(-15, 5)])
        XCTAssertTrue(VoiceGeometry.corners(of: (SIMD2(-4, -4), SIMD2(4, 4)), inset: 5).isEmpty)
    }

    func testFacePlaneIsRightHandedWithTheOutwardNormal() {
        for normal in [SIMD3<Double>(0, 1, 0), SIMD3(0, -1, 0), SIMD3(1, 0, 0), SIMD3(0, 0, -1)] {
            let plane = VoiceGeometry.plane(origin: SIMD3(1, 2, 3), normal: normal)
            XCTAssertEqual(simd_distance(plane.normal, normal), 0, accuracy: 1e-9, "\(normal)")
            XCTAssertEqual(plane.toWorld(.zero), SIMD3(1, 2, 3))
        }
    }
}

// MARK: - Splitting commands into steps (pure)

final class CommandSplitterTests: XCTestCase {
    func testOneInstructionStaysOneStep() {
        XCTAssertEqual(CommandSplitter.steps(in: "draw a hole in the center of this surface"),
                       ["draw a hole in the center of this surface"])
    }

    func testThenAndCommasAndAndBeforeAVerbSplit() {
        XCTAssertEqual(CommandSplitter.steps(in: "drill a 5 mm hole in the centre, then fillet the top edges 1 mm and mirror it"),
                       ["drill a 5 mm hole in the centre", "fillet the top edges 1 mm", "mirror it"])
        XCTAssertEqual(CommandSplitter.steps(in: "add a 10 mm post, chamfer its top edge"),
                       ["add a 10 mm post", "chamfer its top edge"])
        XCTAssertEqual(CommandSplitter.steps(in: "hollow it out. after that export STL"),
                       ["hollow it out", "export STL"])
    }

    func testAndBetweenSizesOrTargetsDoesNotSplit() {
        XCTAssertEqual(CommandSplitter.steps(in: "cut a 20 by 10 and 2 mm deep pocket"),
                       ["cut a 20 by 10 and 2 mm deep pocket"])
        XCTAssertEqual(CommandSplitter.steps(in: "fillet the top and bottom edges 1 mm"),
                       ["fillet the top and bottom edges 1 mm"])
        XCTAssertEqual(CommandSplitter.steps(in: "put a hole next to the edge"), ["put a hole next to the edge"])
    }

    func testEmptyAndTrailingConnectorsVanish() {
        XCTAssertEqual(CommandSplitter.steps(in: ""), [])
        XCTAssertEqual(CommandSplitter.steps(in: "undo that then"), ["undo that"])
    }
}

// MARK: - Topology selectors (pure, synthetic box)

final class VoiceTopologyTests: XCTestCase {
    /// A 40 × 20 × 2 box: faces 1 top, 2 bottom, 3 +X, 4 −X, 5 +Z, 6 −Z, and
    /// 7 a hole's cylinder wall; edges 1–4 around the top, 5–8 around the
    /// bottom, 9–12 vertical, 13–14 the hole rims.
    private let box = VoiceTopology(
        bodyID: BodyID(),
        faces: [
            .init(index: 1, centroid: SIMD3(0, 2, 0), normal: SIMD3(0, 1, 0), area: 800, kind: .planar),
            .init(index: 2, centroid: SIMD3(0, 0, 0), normal: SIMD3(0, -1, 0), area: 800, kind: .planar),
            .init(index: 3, centroid: SIMD3(20, 1, 0), normal: SIMD3(1, 0, 0), area: 40, kind: .planar),
            .init(index: 4, centroid: SIMD3(-20, 1, 0), normal: SIMD3(-1, 0, 0), area: 40, kind: .planar),
            .init(index: 5, centroid: SIMD3(0, 1, 10), normal: SIMD3(0, 0, 1), area: 80, kind: .planar),
            .init(index: 6, centroid: SIMD3(0, 1, -10), normal: SIMD3(0, 0, -1), area: 80, kind: .planar),
            .init(index: 7, centroid: SIMD3(0, 1, 0), normal: SIMD3(0, 1, 0), area: 31, kind: .cylindrical(radius: 2.5)),
        ],
        edges: [
            .init(index: 1, faces: [1, 3], midpoint: SIMD3(20, 2, 0), length: 20),
            .init(index: 2, faces: [1, 4], midpoint: SIMD3(-20, 2, 0), length: 20),
            .init(index: 3, faces: [1, 5], midpoint: SIMD3(0, 2, 10), length: 40),
            .init(index: 4, faces: [1, 6], midpoint: SIMD3(0, 2, -10), length: 40),
            .init(index: 5, faces: [2, 3], midpoint: SIMD3(20, 0, 0), length: 20),
            .init(index: 6, faces: [2, 4], midpoint: SIMD3(-20, 0, 0), length: 20),
            .init(index: 7, faces: [2, 5], midpoint: SIMD3(0, 0, 10), length: 40),
            .init(index: 8, faces: [2, 6], midpoint: SIMD3(0, 0, -10), length: 40),
            .init(index: 9, faces: [3, 5], midpoint: SIMD3(20, 1, 10), length: 2),
            .init(index: 10, faces: [3, 6], midpoint: SIMD3(20, 1, -10), length: 2),
            .init(index: 11, faces: [4, 5], midpoint: SIMD3(-20, 1, 10), length: 2),
            .init(index: 12, faces: [4, 6], midpoint: SIMD3(-20, 1, -10), length: 2),
            .init(index: 13, faces: [1, 7], midpoint: SIMD3(2.5, 2, 0), length: 15.7),
            .init(index: 14, faces: [2, 7], midpoint: SIMD3(2.5, 0, 0), length: 15.7),
        ])

    func testNamedFaces() {
        XCTAssertEqual(box.extremeFace(along: SIMD3(0, 1, 0))?.index, 1)
        XCTAssertEqual(box.extremeFace(along: SIMD3(0, -1, 0))?.index, 2)
        XCTAssertEqual(box.extremeFace(along: SIMD3(1, 0, 0))?.index, 3)
        XCTAssertEqual(box.extremeFace(along: SIMD3(0, 0, -1))?.index, 6)
    }

    func testTheClickedFaceIsReFoundByItsPlane() {
        XCTAssertEqual(box.face(inPlaneThrough: SIMD3(5, 2, 3), normal: SIMD3(0, 1, 0))?.index, 1)
        XCTAssertEqual(box.face(inPlaneThrough: SIMD3(5, 0, 3), normal: SIMD3(0, -1, 0))?.index, 2)
        XCTAssertNil(box.face(inPlaneThrough: SIMD3(5, 1.5, 3), normal: SIMD3(0, 1, 0)), "no face at that height")
    }

    func testEdgeGroups() {
        XCTAssertEqual(Set(box.edges(touching: [1]).map(\.index)), [1, 2, 3, 4, 13])
        XCTAssertEqual(Set(box.verticalEdges.map(\.index)), [9, 10, 11, 12])
        XCTAssertEqual(Set(box.roundEdges.map(\.index)), [13, 14])
    }

    func testClickedEdgesMatchByMidpoint() {
        XCTAssertEqual(box.edges(nearest: [SIMD3(19.9, 2, 0.1), SIMD3(-20, 1, 10)]).map(\.index), [1, 11])
        XCTAssertTrue(box.edges(nearest: [SIMD3(5, 5, 5)]).isEmpty, "nothing within tolerance")
    }
}

// MARK: - Undo folding (pure)

@MainActor
final class UndoCoalesceTests: XCTestCase {
    private struct Note: DocumentCommand {
        let title: String
        func apply(to document: inout DesignDocument) { document.variables.append(Variable(name: title, expression: "1")) }
        func revert(in document: inout DesignDocument) { document.variables.removeLast() }
    }

    func testStepsAfterADepthFoldIntoOneUndoableStep() {
        let stack = UndoStack()
        var document = DesignDocument()
        stack.perform(Note(title: "before"), on: &document)
        let depth = stack.undoCommands.count
        for name in ["a", "b", "c"] { stack.perform(Note(title: name), on: &document) }

        XCTAssertTrue(stack.coalesce(from: depth, title: "Voice: three things"))
        XCTAssertEqual(stack.undoCommands.count, 2)
        XCTAssertEqual(stack.undoTitle, "Voice: three things")
        XCTAssertEqual(document.variables.map(\.name), ["before", "a", "b", "c"], "nothing re-applied")

        stack.undo(on: &document)
        XCTAssertEqual(document.variables.map(\.name), ["before"], "one undo reverts all three")
        stack.redo(on: &document)
        XCTAssertEqual(document.variables.map(\.name), ["before", "a", "b", "c"])
    }

    func testNothingToFoldChangesNothing() {
        let stack = UndoStack()
        XCTAssertFalse(stack.coalesce(from: 0, title: "x"))
        XCTAssertTrue(stack.undoCommands.isEmpty)
    }
}

// MARK: - Real geometry

@MainActor
final class VoiceActionGeometryTests: XCTestCase {
    private static var retained: [EditorViewModel] = []
    private var jev: FakeClassifier!
    private var mic: FakeTranscriber!

    private func makeViewModel() throws -> EditorViewModel {
        let schema = Schema([Project.self, PersistedBody.self, PersistedSketch.self,
                             PersistedPlane.self, PersistedImage.self, PersistedSymbol.self])
        let container = try ModelContainer(for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        let context = ModelContext(container)
        let project = Project(name: "Voice Action Test")
        context.insert(project)
        let vm = EditorViewModel(project: project, modelContext: context)
        Self.retained.append(vm)
        jev = FakeClassifier()
        mic = FakeTranscriber()
        let mic = self.mic!
        vm.voice = VoiceSession(makeTranscriber: { mic }, classifier: jev)
        return vm
    }

    /// Parametric 40 × 20 × 2 mm plate (x ±20, z ±10, y 0…2).
    @discardableResult
    private func addPlate(to vm: EditorViewModel, width: Double = 40, depth: Double = 20,
                          height: Double = 2) -> BodyID {
        let id = BodyID()
        vm.session.recordAndRebuild([FeatureNode(
            name: "Plate",
            kind: .primitive(spec: .box(width: width, depth: depth, height: height), placement: .identity),
            outputBodyIDs: [id])], title: "Plate")
        return id
    }

    private func volume(_ vm: EditorViewModel, _ id: BodyID) -> Double {
        vm.session.document.body(with: id).map(MeasureKit.volume) ?? 0
    }

    private func bounds(_ vm: EditorViewModel, _ id: BodyID) -> (min: SIMD3<Double>, max: SIMD3<Double>) {
        MeasureKit.boundingBox(bodies: [vm.session.document.body(with: id)!])!
    }

    private func pickTopFace(_ vm: EditorViewModel, at x: Float = 5, _ z: Float = 3) {
        vm.handle(.tap(ray: Ray(origin: SIMD3(x, 10, z), direction: SIMD3(0, -1, 0))))
    }

    private func settle() async {
        for _ in 0..<20 { await Task.yield() }
    }

    /// Say `words` and let the fake Jev answer `decision`.
    private func speak(_ vm: EditorViewModel, _ words: String, _ decision: VoiceDecision) async {
        jev.decision = decision
        if vm.voiceActive { await vm.voice.start() } else { vm.openVoice() }
        await settle()
        mic.hear(words)
        vm.submitVoice()
        await settle()
    }

    private func assertApplied(_ vm: EditorViewModel, _ expected: String? = nil,
                               file: StaticString = #filePath, line: UInt = #line) {
        guard let applied = vm.voice.applied else { return XCTFail("nothing applied", file: file, line: line) }
        XCTAssertTrue(applied.ok, applied.message, file: file, line: line)
        if let expected { XCTAssertEqual(applied.message, expected, file: file, line: line) }
    }

    // MARK: Holes

    func testDrillAHoleInTheCentreCutsAFiveMillimetreThroughHoleAsOneUndoStep() async throws {
        let vm = try makeViewModel()
        let plate = addPlate(to: vm)
        let before = volume(vm, plate)
        XCTAssertEqual(before, 1600, accuracy: 1)
        pickTopFace(vm)
        let undoDepth = vm.session.undoStack.undoCommands.count

        await speak(vm, "draw a hole in the center of this surface", .sample(.hole))

        assertApplied(vm, "Ø5 mm hole, through")
        XCTAssertEqual(before - volume(vm, plate), .pi * 2.5 * 2.5 * 2, accuracy: 0.6)
        XCTAssertEqual(vm.session.undoStack.undoCommands.count, undoDepth + 1, "ONE undo step")
        let sketch = try XCTUnwrap(vm.session.document.sketches.last)
        XCTAssertTrue(sketch.isHidden)
        guard case .circle(_, let centre, _) = try XCTUnwrap(sketch.entities.first) else { return XCTFail() }
        let world = sketch.plane.toWorld(centre)
        XCTAssertEqual(world.x, 0, accuracy: 1e-6, "centre of the face, not where it was clicked")
        XCTAssertEqual(world.z, 0, accuracy: 1e-6)
        XCTAssertEqual(world.y, 2, accuracy: 1e-6)

        vm.undo()
        XCTAssertEqual(volume(vm, plate), before, accuracy: 1e-6)
    }

    /// Mac: with nothing clicked, the face under the pointer is "this".
    func testWithNothingClickedTheFaceUnderThePointerIsTheTarget() async throws {
        let vm = try makeViewModel()
        let plate = addPlate(to: vm)
        let before = volume(vm, plate)
        vm.hoverRay = Ray(origin: SIMD3(-8, 10, 5), direction: SIMD3(0, -1, 0))
        guard case .face(let area) = vm.voiceTarget else { return XCTFail("chip should show the hovered face") }
        XCTAssertEqual(area, 800, accuracy: 1e-6)
        await speak(vm, "3 mm hole here", .steps(.sample(.hole, placement: .clickedPoint, numbers: [("3 mm", .diameter)])))
        assertApplied(vm, "Ø3 mm hole, through")
        XCTAssertEqual(before - volume(vm, plate), .pi * 1.5 * 1.5 * 2, accuracy: 0.3)
        let sketch = try XCTUnwrap(vm.session.document.sketches.last)
        guard case .circle(_, let centre, _) = try XCTUnwrap(sketch.entities.first) else { return XCTFail() }
        XCTAssertEqual(sketch.plane.toWorld(centre).x, -8, accuracy: 0.01)
        XCTAssertEqual(sketch.plane.toWorld(centre).z, 5, accuracy: 0.01)
    }

    func testAHoleHereGoesWhereTheFaceWasClicked() async throws {
        let vm = try makeViewModel()
        addPlate(to: vm)
        pickTopFace(vm, at: 12, -4)
        await speak(vm, "3 mm hole here", .steps(.sample(.hole, placement: .clickedPoint, numbers: [("3 mm", .diameter)])))
        assertApplied(vm, "Ø3 mm hole, through")
        let sketch = try XCTUnwrap(vm.session.document.sketches.last)
        guard case .circle(_, let centre, _) = try XCTUnwrap(sketch.entities.first) else { return XCTFail() }
        let world = sketch.plane.toWorld(centre)
        XCTAssertEqual(world.x, 12, accuracy: 0.01)
        XCTAssertEqual(world.z, -4, accuracy: 0.01)
    }

    func testFourCornerHoles() async throws {
        let vm = try makeViewModel()
        let plate = addPlate(to: vm)
        let before = volume(vm, plate)
        pickTopFace(vm)
        await speak(vm, "M3 holes in the corners 5 mm in",
                    .steps(.sample(.cornerHoles, placement: .corners, numbers: [("M3", .diameter), ("5 mm", .distance)])))
        assertApplied(vm, "4 × Ø3.2 mm hole, through")
        XCTAssertEqual(before - volume(vm, plate), 4 * .pi * 1.6 * 1.6 * 2, accuracy: 1)
    }

    func testABlindHole() async throws {
        let vm = try makeViewModel()
        let plate = addPlate(to: vm)
        let before = volume(vm, plate)
        pickTopFace(vm)
        await speak(vm, "4 mm hole 1 mm deep",
                    .steps(.sample(.hole, depth: .blind, numbers: [("4 mm", .diameter), ("1 mm", .depth)])))
        assertApplied(vm, "Ø4 mm hole, 1 mm deep")
        XCTAssertEqual(before - volume(vm, plate), .pi * 4 * 1, accuracy: 0.4)
    }

    // MARK: Other features on a face

    func testPocketBossAndPad() async throws {
        let vm = try makeViewModel()
        let plate = addPlate(to: vm, height: 5)
        var v = volume(vm, plate)
        pickTopFace(vm)
        await speak(vm, "20 by 10 pocket 2 mm deep",
                    .steps(.sample(.pocket, depth: .blind, numbers: [("20", .width), ("10", .length), ("2 mm", .depth)])))
        assertApplied(vm, "20 × 10 mm pocket, 2 mm deep")
        XCTAssertEqual(v - volume(vm, plate), 20 * 10 * 2, accuracy: 0.5)

        v = volume(vm, plate)
        pickTopFace(vm, at: 15, 7)
        await speak(vm, "put a 4 mm post 6 mm tall here",
                    .steps(.sample(.boss, placement: .clickedPoint, numbers: [("4 mm", .diameter), ("6 mm", .height)])))
        // The clicked face is re-found by its plane even though the pocket changed it.
        assertApplied(vm, "Ø4 mm post, 6 mm tall")
        XCTAssertEqual(volume(vm, plate) - v, .pi * 2 * 2 * 6, accuracy: 0.6)
        XCTAssertEqual(bounds(vm, plate).max.y, 11, accuracy: 1e-6)
    }

    func testPullAndPushAFace() async throws {
        let vm = try makeViewModel()
        let plate = addPlate(to: vm)
        pickTopFace(vm)
        await speak(vm, "pull this up 3 mm", .steps(.sample(.extrudeFaceOut, numbers: [("3 mm", .distance)])))
        assertApplied(vm)
        XCTAssertEqual(bounds(vm, plate).max.y, 5, accuracy: 1e-6)
    }

    func testShellWithTheClickedFaceOpen() async throws {
        let vm = try makeViewModel()
        let box = addPlate(to: vm, width: 30, depth: 30, height: 20)
        pickTopFace(vm)
        await speak(vm, "hollow it out with 2 mm walls open here",
                    .steps(.sample(.shellRemoveFace, numbers: [("2 mm", .thickness)])))
        assertApplied(vm, "Shelled with 2 mm walls, open face")
        let expected = 30.0 * 30 * 20 - 26 * 26 * 18
        XCTAssertEqual(volume(vm, box), expected, accuracy: 20)
    }

    // MARK: Edges

    func testFilletTheTopEdgesByName() async throws {
        let vm = try makeViewModel()
        let plate = addPlate(to: vm, height: 5)
        let before = volume(vm, plate)
        await speak(vm, "fillet the top edges 1 mm",
                    .steps(.sample(.filletEdges, target: .topEdges, numbers: [("1 mm", .radius)])))
        assertApplied(vm, "1 mm fillet on 4 edges")
        XCTAssertLessThan(volume(vm, plate), before)
    }

    func testChamferTheClickedEdge() async throws {
        let vm = try makeViewModel()
        let plate = addPlate(to: vm, height: 5)
        let before = volume(vm, plate)
        // A tap next to the top +X edge picks that edge (SelectionTests).
        vm.handle(.tap(ray: Ray(origin: SIMD3(19.97, 10, 0.3), direction: SIMD3(0, -1, 0))))
        XCTAssertEqual(vm.mode, .pickingBlendEdges(.fillet))
        await speak(vm, "chamfer this 1 mm", .steps(.sample(.chamferEdges, numbers: [("1 mm", .distance)])))
        assertApplied(vm, "1 mm chamfer on edge")
        XCTAssertEqual(before - volume(vm, plate), 0.5 * 1 * 1 * 20, accuracy: 0.3)
    }

    // MARK: Multi-step

    func testHoleThenFilletRunsBothAsOneUndoStep() async throws {
        let vm = try makeViewModel()
        let plate = addPlate(to: vm, height: 5)
        let before = volume(vm, plate)
        pickTopFace(vm)
        let depth = vm.session.undoStack.undoCommands.count
        await speak(vm, "drill a 5 mm hole in the centre then fillet the top edges 1 mm", .steps(
            .sample(.hole, numbers: [("5 mm", .diameter)], text: "drill a 5 mm hole in the centre"),
            .sample(.filletEdges, target: .topEdges, numbers: [("1 mm", .radius)], text: "fillet the top edges 1 mm")))
        assertApplied(vm, "1. Ø5 mm hole, through  2. 1 mm fillet on 5 edges")
        let after = volume(vm, plate)
        XCTAssertLessThan(after, before - .pi * 2.5 * 2.5 * 5 + 0.5)
        XCTAssertEqual(vm.session.undoStack.undoCommands.count, depth + 1, "the whole command is one undo step")
        XCTAssertTrue(vm.session.undoStack.undoTitle?.hasPrefix("Voice:") == true)
        vm.undo()
        XCTAssertEqual(volume(vm, plate), before, accuracy: 1e-6, "one undo reverts both steps")
    }

    func testAFailingStepUndoesTheEarlierOnesAndSaysWhich() async throws {
        let vm = try makeViewModel()
        let plate = addPlate(to: vm)
        let before = volume(vm, plate)
        pickTopFace(vm)
        let depth = vm.session.undoStack.undoCommands.count
        await speak(vm, "drill a hole then pull the face out", .steps(
            .sample(.hole, text: "drill a hole"),
            .sample(.extrudeFaceOut, text: "pull the face out")))   // no distance → fails
        let applied = try XCTUnwrap(vm.voice.applied)
        XCTAssertFalse(applied.ok)
        XCTAssertTrue(applied.message.hasPrefix("Step 2 (“pull the face out”): How far?"), applied.message)
        XCTAssertTrue(applied.message.hasSuffix("Nothing was changed."), applied.message)
        XCTAssertEqual(volume(vm, plate), before, accuracy: 1e-6)
        XCTAssertEqual(vm.session.undoStack.undoCommands.count, depth)
    }

    // MARK: Whole parts

    func testMirrorPatternMoveRotateScale() async throws {
        let vm = try makeViewModel()
        let plate = addPlate(to: vm, width: 10, depth: 10, height: 2)
        vm.selection = [plate]
        vm.mode = .selected(plate)

        await speak(vm, "move it right 30 mm", .steps(.sample(.moveBody, direction: .right, numbers: [("30 mm", .distance)])))
        assertApplied(vm, "Moved 30 mm")
        let moved = try XCTUnwrap(vm.selection.first)
        XCTAssertEqual(bounds(vm, moved).min.x, 25, accuracy: 1e-6)

        await speak(vm, "mirror it on X", .steps(.sample(.mirrorBody, axis: .x)))
        assertApplied(vm, "Mirrored")
        XCTAssertEqual(vm.session.document.bodies.count, 2)

        await speak(vm, "make 3 copies 15 mm apart", .steps(.sample(.linearPattern, axis: .z,
                    numbers: [("3", .count), ("15 mm", .spacing)], text: "make 3 copies 15 mm apart")))
        assertApplied(vm, "4 in a row, 15 mm apart")
        XCTAssertEqual(vm.session.document.bodies.count, 5)
    }

    func testRotateAndScaleAboutTheCentre() async throws {
        let vm = try makeViewModel()
        let bar = addPlate(to: vm, width: 40, depth: 10, height: 2)
        vm.selection = [bar]
        vm.mode = .selected(bar)
        await speak(vm, "rotate it 90 degrees", .steps(.sample(.rotateBody, axis: .y, numbers: [("90 degrees", .angle)])))
        assertApplied(vm, "Rotated 90°")
        var id = try XCTUnwrap(vm.selection.first)
        var b = bounds(vm, id)
        XCTAssertEqual(b.max.z - b.min.z, 40, accuracy: 1e-3, "the long side now runs along Z")

        await speak(vm, "scale it to 50%", .steps(.sample(.scaleBody, numbers: [("50%", .scale)])))
        assertApplied(vm, "Scaled to 50%")
        id = try XCTUnwrap(vm.selection.first)
        b = bounds(vm, id)
        XCTAssertEqual(b.max.z - b.min.z, 20, accuracy: 1e-3)
    }

    func testAddABoxThenJoinItToThePlate() async throws {
        let vm = try makeViewModel()
        addPlate(to: vm)
        await speak(vm, "add a 10 mm cube", .steps(.sample(.addBox, target: .nothing, numbers: [("10 mm", .width)])))
        assertApplied(vm, "Added a 10 × 10 × 10 mm box")
        XCTAssertEqual(vm.session.document.bodies.count, 2)

        await speak(vm, "join them", .steps(.sample(.joinBodies, target: .allBodies)))
        assertApplied(vm, "Joined 2 parts")
        XCTAssertEqual(vm.session.document.bodies.count, 1)
    }

    func testHideAndShowAll() async throws {
        let vm = try makeViewModel()
        let plate = addPlate(to: vm)
        vm.selection = [plate]
        vm.mode = .selected(plate)
        await speak(vm, "hide it", .steps(.sample(.hideBody)))
        assertApplied(vm)
        XCTAssertTrue(vm.session.document.body(with: plate)?.isHidden == true)
        await speak(vm, "show everything", .steps(.sample(.showAll, target: .allBodies)))
        assertApplied(vm, "Showed 1 hidden part")
        XCTAssertFalse(vm.session.document.body(with: plate)?.isHidden == true)
    }

    // MARK: Editing what exists

    func testMakeItSixResizesTheVoiceHole() async throws {
        let vm = try makeViewModel()
        let plate = addPlate(to: vm)
        let before = volume(vm, plate)
        pickTopFace(vm)
        await speak(vm, "drill a hole in the centre", .sample(.hole))
        assertApplied(vm)
        await speak(vm, "make it 6", .steps(.sample(.modifyLast, relative: .setTo, numbers: [("6", .diameter)])))
        assertApplied(vm, "Diameter is now 6 mm")
        XCTAssertEqual(before - volume(vm, plate), .pi * 3 * 3 * 2, accuracy: 0.7)
    }

    func testTwoMillimetresMoreOnAFillet() async throws {
        let vm = try makeViewModel()
        let plate = addPlate(to: vm, height: 10)
        await speak(vm, "fillet the vertical edges 1 mm",
                    .steps(.sample(.filletEdges, target: .verticalEdges, numbers: [("1 mm", .radius)])))
        assertApplied(vm, "1 mm fillet on 4 edges")
        let v1 = volume(vm, plate)
        await speak(vm, "2 mm more", .steps(.sample(.modifyLast, relative: .increaseBy, numbers: [("2 mm", .radius)])))
        assertApplied(vm, "Fillet Radius is now 3 mm")
        XCTAssertLessThan(volume(vm, plate), v1)
    }

    func testSameAgainRepeatsTheLastCommandOnTheNewPick() async throws {
        let vm = try makeViewModel()
        let plate = addPlate(to: vm, width: 40, depth: 20, height: 2)
        let before = volume(vm, plate)
        pickTopFace(vm, at: 12, -4)
        await speak(vm, "3 mm hole here", .steps(.sample(.hole, placement: .clickedPoint, numbers: [("3 mm", .diameter)])))
        assertApplied(vm)
        pickTopFace(vm, at: -12, 4)
        await speak(vm, "same again here", .steps(.sample(.repeatLast)))
        assertApplied(vm)
        XCTAssertEqual(before - volume(vm, plate), 2 * .pi * 1.5 * 1.5 * 2, accuracy: 0.5)
    }

    func testSetAVariable() async throws {
        let vm = try makeViewModel()
        _ = vm.createVariable(holding: "3", preferredName: "wall")
        await speak(vm, "set wall to 2", .steps(.sample(.setVariable, target: .nothing, variable: "wall",
                                                        numbers: [("2", .other)])))
        assertApplied(vm, "wall = 2")
        XCTAssertEqual(vm.session.document.variables.first?.expression, "2")
    }

    // MARK: Inspect

    func testMeasureAndPrintCheck() async throws {
        let vm = try makeViewModel()
        addPlate(to: vm)
        pickTopFace(vm)
        await speak(vm, "how thick is this", .steps(.sample(.measureThickness)))
        assertApplied(vm, "Thickness: 2 mm")
        await speak(vm, "will this print", .steps(.sample(.printCheck, target: .allBodies)))
        let message = try XCTUnwrap(vm.voice.applied?.message)
        XCTAssertTrue(message.hasPrefix("Fits the Ender 3 V3 SE (40 × 20 × 2 mm)"), message)
    }

    func testTooBigToPrintSaysWhichWay() {
        let tall = Body(name: "Tall", transform: .identity,
                        euclidMesh: .primitive(.box(width: 10, depth: 10, height: 300)), revision: 1)
        let message = VoiceRecipe.printCheck(bodies: [tall])
        XCTAssertTrue(message.hasPrefix("Too big: 300 mm tall (max 250)"), message)
    }

    // MARK: Refusals

    func testANonParametricPartIsRefusedAndNothingChanges() async throws {
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
        XCTAssertTrue(vm.voice.applied?.message.contains("isn't parametric") == true,
                      String(describing: vm.voice.applied))
        XCTAssertEqual(vm.session.changeCount, changes)
    }

    func testAnUnsureAnswerIsNotAppliedUntilTheUserPicks() async throws {
        let vm = try makeViewModel()
        let plate = addPlate(to: vm)
        let before = volume(vm, plate)
        pickTopFace(vm)
        await speak(vm, "put a thing here", .sample(.boss, confidence: 0.4))
        XCTAssertNil(vm.voice.applied)
        XCTAssertEqual(volume(vm, plate), before)
        vm.voice.choose(.hole)
        assertApplied(vm)
        XCTAssertLessThan(volume(vm, plate), before)
    }

    func testSayingUndoUndoesTheLastCommand() async throws {
        let vm = try makeViewModel()
        let plate = addPlate(to: vm)
        let before = volume(vm, plate)
        pickTopFace(vm)
        await speak(vm, "hole in the centre", .sample(.hole))
        XCTAssertLessThan(volume(vm, plate), before)
        await speak(vm, "undo that", .sample(.undo))
        assertApplied(vm, "Undid the last edit")
        XCTAssertEqual(volume(vm, plate), before, accuracy: 1e-6)
    }
}
