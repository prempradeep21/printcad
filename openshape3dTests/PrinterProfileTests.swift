//
//  PrinterProfileTests.swift
//  openshape3dTests
//
//  T0.3: the Ender 3 V3 SE profile constants and the ghost build-volume box
//  drawn from them. The app is Y-up, so printer Z (height) maps to world Y.
//

import XCTest
@testable import openshape3d

final class PrinterProfileTests: XCTestCase {

    func testEnder3V3SEProfileMatchesPrinterTable() {
        let p = PrinterProfile.ender3V3SE
        XCTAssertEqual(p.bedWidthMM, 220)
        XCTAssertEqual(p.bedDepthMM, 220)
        XCTAssertEqual(p.maxHeightMM, 250)
        XCTAssertEqual(p.nozzleDiameterMM, 0.4)
        XCTAssertEqual(p.minWallWarningMM, 0.8)
        XCTAssertEqual(p.overhangWarningDegrees, 45)
        XCTAssertEqual(p.holeClearanceMM, 0.2)
        XCTAssertEqual(p.threadClearanceMM, 0.2)
    }

    func testBuildVolumeBoxHasTwelveEdgesAtTheBedCorners() {
        let segments = BuildVolume.edgeSegments(for: .ender3V3SE)
        XCTAssertEqual(segments.count, 24, "12 edges, 2 endpoints each")

        let xs = Set(segments.map(\.x)), ys = Set(segments.map(\.y)), zs = Set(segments.map(\.z))
        XCTAssertEqual(xs, [-110, 110], "centred on the origin across the bed width")
        XCTAssertEqual(zs, [-110, 110], "centred on the origin across the bed depth")
        XCTAssertEqual(ys, [0, 250], "stands on the ground, printer height along world Y")
    }

    func testBuildVolumeEdgesAreAxisAlignedWithBedDimensions() {
        let segments = BuildVolume.edgeSegments(for: .ender3V3SE)
        var lengthsByAxis: [Int: [Float]] = [:]
        for i in stride(from: 0, to: segments.count, by: 2) {
            let d = segments[i + 1] - segments[i]
            let nonZero = (0..<3).filter { d[$0] != 0 }
            XCTAssertEqual(nonZero.count, 1, "edge \(i / 2) is not axis-aligned: \(d)")
            guard let axis = nonZero.first else { continue }
            lengthsByAxis[axis, default: []].append(abs(d[axis]))
        }
        XCTAssertEqual(lengthsByAxis[0], [220, 220, 220, 220], "X edges span the bed width")
        XCTAssertEqual(lengthsByAxis[1], [250, 250, 250, 250], "Y edges span the print height")
        XCTAssertEqual(lengthsByAxis[2], [220, 220, 220, 220], "Z edges span the bed depth")
    }

    func testFitViewBoundsIgnoreTheBuildVolume() {
        var scene = ViewportScene()
        scene.sketchLines = [SketchLineBatch(
            segments: [SIMD3(0, 0, 0), SIMD3(10, 10, 10)], color: SIMD4(1, 1, 1, 1))]
        scene.buildVolumeLines = [SketchLineBatch(
            segments: BuildVolume.edgeSegments(for: .ender3V3SE), color: SIMD4(1, 1, 1, 1))]

        let bounds = try? XCTUnwrap(scene.worldBounds)
        XCTAssertEqual(bounds?.min, SIMD3<Float>(0, 0, 0))
        XCTAssertEqual(bounds?.max, SIMD3<Float>(10, 10, 10))
    }

    func testEmptySceneWithOnlyBuildVolumeHasNoFitBounds() {
        var scene = ViewportScene()
        scene.buildVolumeLines = [SketchLineBatch(
            segments: BuildVolume.edgeSegments(for: .ender3V3SE), color: SIMD4(1, 1, 1, 1))]
        XCTAssertNil(scene.worldBounds, "the ghost box alone is not something to frame")
    }
}
