//
//  VoiceRecipe.swift
//  openshape3d
//
//  PrintCAD V1: the pure rules that turn one step of Jev's decision into
//  numbers — sizes from the spoken numbers (with defaults), relative changes
//  ("2 mm deeper", "bigger"), scale factors, the print check, and where "the
//  centre" of an outline is. The editor half lives in EditorViewModel+VoiceApply.
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
    static let printer = PrinterProfile.ender3V3SE
    /// CLAUDE.md printer profile: +0.2 mm on diameter for fastener clearance holes.
    static var fastenerClearance: Double { printer.holeClearanceMM }

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

    // MARK: Holes

    static func hole(from step: VoiceStep) -> Result<HoleSpec, Failure> {
        var diameter: Double?
        var depth: Double?
        for labelled in step.numbers {
            let number = labelled.number
            switch labelled.role {
            case .diameter where diameter == nil:
                diameter = number.isFastenerSize ? number.value + fastenerClearance : number.value
            case .radius where diameter == nil:
                diameter = number.value * 2
            case .depth, .length, .height, .thickness:
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

        switch step.depth {
        case .blind:
            guard let depth else { return .failure(.missingDepth) }
            guard depth > 0 else { return .failure(.badSize("The depth has to be above 0 mm.")) }
            return .success(HoleSpec(diameter: size, depth: depth))
        case .throughAll, .notApplicable:
            // A depth said without Jev choosing "blind" still counts.
            return .success(HoleSpec(diameter: size, depth: depth.flatMap { $0 > 0 ? $0 : nil }))
        }
    }

    static func summary(_ hole: HoleSpec) -> String {
        let d = SpokenNumber.format((hole.diameter * 100).rounded() / 100)
        if let depth = hole.depth {
            return "Ø\(d) mm hole, \(SpokenNumber.format((depth * 100).rounded() / 100)) mm deep"
        }
        return "Ø\(d) mm hole, through"
    }

    // MARK: Rectangles, scale, relative change

    /// Width × length for a pocket or pad: the first two spoken sizes that
    /// aren't its depth/height. One size means a square.
    static func rectangle(from step: VoiceStep) -> SIMD2<Double>? {
        let excluded: Set<NumberRole> = step.action == .pad
            ? [.height, .thickness, .count, .angle, .scale]
            : [.depth, .count, .angle, .scale]
        let sizes = step.numbers.filter { !excluded.contains($0.role) && $0.number.value > 0 }.map(\.number.value)
        switch sizes.count {
        case 0: return nil
        case 1: return SIMD2(sizes[0], sizes[0])
        default: return SIMD2(sizes[0], sizes[1])
        }
    }

    /// "150%", "to 1.5", "twice as big", "half the size", "bigger".
    static func scaleFactor(from step: VoiceStep) -> Double? {
        if let percent = step.numbers.first(where: { $0.number.unit == .percent })?.number.value {
            return percent / 100
        }
        if let factor = step.numbers.first(where: { $0.role == .scale || $0.number.unit == .none })?.number.value, factor > 0 {
            return factor > 20 ? factor / 100 : factor
        }
        let text = step.text.lowercased()
        if text.contains("double") || text.contains("twice") { return 2 }
        if text.contains("triple") { return 3 }
        if text.contains("half") { return 0.5 }
        switch step.relative {
        case .bigger: return 1.25
        case .smaller: return 0.8
        default: return nil
        }
    }

    /// Apply "set to / increase by / decrease by / bigger / smaller".
    static func change(_ current: Double, by relative: VoiceRelative, value: Double?) -> Double? {
        switch relative {
        case .setTo, .notApplicable: return value
        case .increaseBy: return value.map { current + $0 }
        case .decreaseBy: return value.map { current - $0 }
        case .bigger: return value.map { current + $0 } ?? current * 1.25
        case .smaller: return value.map { current - $0 } ?? current * 0.8
        }
    }

    /// The one number a feature is "about" — what "make it 6" changes — and
    /// how to rebuild the feature with a new value.
    static func mainValue(of kind: FeatureKind) -> (Double, (Expr) -> FeatureKind, String)? {
        switch kind {
        case let .extrude(profile, plane, distance, symmetric, boolean, extras):
            return (distance.value, { .extrude(profile: profile, plane: plane, distance: $0, symmetric: symmetric,
                                               boolean: boolean, extraProfiles: extras) }, "depth")
        case let .pushPull(face, distance, mode):
            return (distance.value, { .pushPull(face: face, distance: $0, mode: mode) }, "distance")
        case let .fillet(body, edges, radius):
            return (radius.value, { .fillet(body: body, edges: edges, radius: $0) }, "fillet radius")
        case let .chamfer(body, edges, setback):
            return (setback.value, { .chamfer(body: body, edges: edges, setback: $0) }, "chamfer")
        case let .shell(body, faces, thickness):
            return (thickness.value, { .shell(body: body, openFaces: faces, thickness: $0) }, "wall thickness")
        default:
            return nil
        }
    }

    // MARK: Printing

    /// Does everything fit the bed, and roughly what does it weigh?
    static func printCheck(bodies: [Body]) -> String {
        guard let box = MeasureKit.boundingBox(bodies: bodies) else { return "There's nothing to print." }
        let size = box.max - box.min
        // Printed Z-up: the model's Y (up) is the printer's Z.
        var problems: [String] = []
        if size.x > printer.bedWidthMM { problems.append("\(number(size.x)) mm wide (bed \(number(printer.bedWidthMM)))") }
        if size.z > printer.bedDepthMM { problems.append("\(number(size.z)) mm deep (bed \(number(printer.bedDepthMM)))") }
        if size.y > printer.maxHeightMM { problems.append("\(number(size.y)) mm tall (max \(number(printer.maxHeightMM)))") }
        let grams = bodies.reduce(0) { $0 + MeasureKit.volume(of: $1) } / 1000 * 1.24
        let fit = problems.isEmpty
            ? "Fits the \(printer.name) (\(number(size.x)) × \(number(size.z)) × \(number(size.y)) mm)"
            : "Too big: " + problems.joined(separator: ", ")
        return fit + " · ≈ \(number(grams)) g of PLA · walls and overhangs not checked yet"
    }

    // MARK: Formatting

    static func number(_ value: Double) -> String {
        let rounded = (value * 10).rounded() / 10
        return SpokenNumber.format(rounded)
    }

    static func mm(_ value: Double) -> String { "\(number(value)) mm" }

    // MARK: Geometry

    /// Area centroid of a closed polygon (plane-local). For a rectangle it is
    /// the middle; for an L-shape it is the balance point, not the vertex
    /// average. Falls back to the vertex average for a degenerate loop.
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
}

/// Plane and outline helpers for sketching on a body's face.
enum VoiceGeometry {
    /// A sketch plane on a face: origin at `origin`, normal = `normal`
    /// (outward), x along world X where possible.
    static func plane(origin: SIMD3<Double>, normal: SIMD3<Double>) -> SketchPlane {
        let n = simd_normalize(normal)
        let x = abs(n.y) > 0.9 ? SIMD3<Double>(1, 0, 0) : simd_normalize(simd_cross(SIMD3<Double>(0, 1, 0), n))
        let y = simd_cross(n, x)
        return SketchPlane(origin: origin, xAxis: x, yAxis: y)
    }

    /// The face's outline extent on `plane` (plane coordinates), from the
    /// body's mesh vertices lying in that plane.
    static func outlineBounds(of body: Body, on plane: SketchPlane,
                              tolerance: Double = 1e-3) -> (min: SIMD2<Double>, max: SIMD2<Double>)? {
        let n = simd_normalize(plane.normal)
        var lo = SIMD2<Double>(repeating: .infinity)
        var hi = SIMD2<Double>(repeating: -.infinity)
        var found = false
        for p in body.render.positions {
            let world = body.transform.applying(to: SIMD3<Double>(p))
            guard abs(simd_dot(world - plane.origin, n)) < tolerance else { continue }
            let local = plane.toLocal(world)
            lo = simd_min(lo, local)
            hi = simd_max(hi, local)
            found = true
        }
        return found ? (lo, hi) : nil
    }

    /// Four points `inset` in from each corner of `bounds`; empty when the
    /// face is too small for that.
    static func corners(of bounds: (min: SIMD2<Double>, max: SIMD2<Double>), inset: Double) -> [SIMD2<Double>] {
        let lo = bounds.min + inset
        let hi = bounds.max - inset
        guard hi.x > lo.x, hi.y > lo.y else { return [] }
        return [SIMD2(lo.x, lo.y), SIMD2(hi.x, lo.y), SIMD2(hi.x, hi.y), SIMD2(lo.x, hi.y)]
    }

    /// How far the body reaches along `direction` (its thickness that way).
    static func extent(of body: Body, along direction: SIMD3<Double>) -> Double {
        let d = simd_normalize(direction)
        var lo = Double.infinity
        var hi = -Double.infinity
        for p in body.render.positions {
            let t = simd_dot(body.transform.applying(to: SIMD3<Double>(p)), d)
            lo = min(lo, t)
            hi = max(hi, t)
        }
        return hi >= lo ? hi - lo : 0
    }
}
