//
//  VoiceRecipe.swift
//  openshape3d
//
//  PrintCAD V1.3: the pure half of turning Jev's decision into geometry —
//  sizes from the spoken numbers (with defaults), and where "the centre of this
//  face" is. The editor half (sketch + cut, one undo step) is in
//  EditorViewModel+VoiceApply.swift.
//

import Foundation
import simd

/// A hole to cut into a face.
struct HoleSpec: Equatable {
    /// Finished hole diameter in mm (fastener sizes already include clearance).
    let diameter: Double
    /// nil = through all.
    let depth: Double?
}

enum VoiceRecipe {
    /// When no size is said. Prem's plan: "Hole diameter is 5 mm when you don't say a size."
    static let defaultHoleDiameter = 5.0
    /// CLAUDE.md printer profile: +0.2 mm on diameter for fastener clearance holes.
    static let fastenerClearance = 0.2

    enum Failure: LocalizedError, Equatable {
        case missingDepth
        case badSize(String)

        var errorDescription: String? {
            switch self {
            case .missingDepth: return "How deep? Say it with a number, e.g. “4 mm deep”, or say “through”."
            case .badSize(let what): return what
            }
        }
    }

    static func hole(from decision: VoiceDecision) -> Result<HoleSpec, Failure> {
        var diameter: Double?
        var depth: Double?
        for labelled in decision.numbers {
            let number = labelled.number
            switch labelled.role {
            case .diameter where diameter == nil:
                diameter = number.isFastenerSize ? number.value + fastenerClearance : number.value
            case .radius where diameter == nil:
                diameter = number.value * 2
            case .depth, .distance, .length, .height, .thickness:
                if depth == nil { depth = number.value }
            default:
                // A fastener size is a diameter even if Jev labelled it oddly.
                if number.isFastenerSize, diameter == nil {
                    diameter = number.value + fastenerClearance
                }
            }
        }
        let size = diameter ?? defaultHoleDiameter
        guard size > 0 else { return .failure(.badSize("A hole needs a diameter above 0 mm.")) }

        switch decision.depth {
        case .blind:
            guard let depth else { return .failure(.missingDepth) }
            guard depth > 0 else { return .failure(.badSize("The depth has to be above 0 mm.")) }
            return .success(HoleSpec(diameter: size, depth: depth))
        case .throughAll, .notApplicable:
            // A depth said without Jev choosing "blind" still counts.
            return .success(HoleSpec(diameter: size, depth: depth.flatMap { $0 > 0 ? $0 : nil }))
        }
    }

    /// Area centroid of a closed polygon (plane-local). For a rectangle it is
    /// the middle; for an L-shape it is the balance point, not the vertex
    /// average (which the face's plane origin uses). Falls back to the vertex
    /// average for a degenerate loop.
    static func centroid(of loop: [SIMD2<Double>]) -> SIMD2<Double> {
        guard loop.count >= 3 else {
            return loop.isEmpty ? .zero : loop.reduce(.zero, +) / Double(loop.count)
        }
        var area = 0.0
        var c = SIMD2<Double>.zero
        for i in loop.indices {
            let p = loop[i]
            let q = loop[(i + 1) % loop.count]
            let cross = p.x * q.y - q.x * p.y
            area += cross
            c += (p + q) * cross
        }
        area /= 2
        guard abs(area) > 1e-12 else { return loop.reduce(.zero, +) / Double(loop.count) }
        return c / (6 * area)
    }

    /// How the panel describes a hole that was made.
    static func summary(_ hole: HoleSpec) -> String {
        let d = SpokenNumber.format((hole.diameter * 100).rounded() / 100)
        if let depth = hole.depth {
            return "Ø\(d) mm hole, \(SpokenNumber.format((depth * 100).rounded() / 100)) mm deep"
        }
        return "Ø\(d) mm hole, through"
    }
}
