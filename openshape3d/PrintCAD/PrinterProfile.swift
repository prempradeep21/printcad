//
//  PrinterProfile.swift
//  openshape3d
//
//  PrintCAD (T0.3): the target printer's constants, in one place. Values come
//  from the printer table in CLAUDE.md; everything is millimetres and
//  printer-frame (Z up). Callers that draw in the app's Y-up world convert —
//  see `BuildVolume`.
//
//  nonisolated + Double math to match the kernel.
//

import Foundation

nonisolated struct PrinterProfile: Hashable, Sendable {
    var name: String
    /// Printable area along printer X.
    var bedWidthMM: Double
    /// Printable area along printer Y.
    var bedDepthMM: Double
    /// Maximum print height along printer Z.
    var maxHeightMM: Double
    var nozzleDiameterMM: Double
    /// Walls thinner than this get a print-check warning.
    var minWallWarningMM: Double
    /// Faces steeper than this from vertical get an overhang warning.
    var overhangWarningDegrees: Double
    /// Default extra diameter added to holes.
    var holeClearanceMM: Double
    /// Default radial clearance for printed threads (variable `thread_clearance`).
    var threadClearanceMM: Double

    static let ender3V3SE = PrinterProfile(
        name: "Ender 3 V3 SE",
        bedWidthMM: 220,
        bedDepthMM: 220,
        maxHeightMM: 250,
        nozzleDiameterMM: 0.4,
        minWallWarningMM: 0.8,
        overhangWarningDegrees: 45,
        holeClearanceMM: 0.2,
        threadClearanceMM: 0.2
    )
}
