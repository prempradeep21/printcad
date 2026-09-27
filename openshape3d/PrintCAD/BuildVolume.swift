//
//  BuildVolume.swift
//  openshape3d
//
//  PrintCAD (T0.3): the ghost build-volume box drawn in the viewport. The app
//  is Y-up, so the printer's height (Z) runs along world Y; the bed is centred
//  on the origin in world XZ and sits on the ground (y = 0).
//

import simd

nonisolated enum BuildVolume {

    /// Line color for the ghost box: a muted grey that reads on both themes
    /// without competing with sketch or construction geometry.
    static let lineColor = SIMD4<Float>(0.55, 0.58, 0.62, 0.55)

    /// The box's 12 edges as segment pairs [a0, b0, a1, b1, ...], world space.
    static func edgeSegments(for profile: PrinterProfile) -> [SIMD3<Float>] {
        let hx = Float(profile.bedWidthMM / 2)
        let hz = Float(profile.bedDepthMM / 2)
        let top = Float(profile.maxHeightMM)

        func corner(_ i: Int) -> SIMD3<Float> {
            SIMD3((i & 1) == 0 ? -hx : hx,
                  (i & 2) == 0 ? 0 : top,
                  (i & 4) == 0 ? -hz : hz)
        }
        // Corners differing in exactly one bit share an edge: bit 0 → X,
        // bit 1 → Y, bit 2 → Z. Four edges per axis.
        var segments: [SIMD3<Float>] = []
        segments.reserveCapacity(24)
        for bit in [1, 2, 4] {
            for i in 0..<8 where i & bit == 0 {
                segments.append(corner(i))
                segments.append(corner(i | bit))
            }
        }
        return segments
    }
}
