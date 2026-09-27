//
//  VoiceTopology.swift
//  openshape3d
//
//  PrintCAD V1: a body's kernel faces and edges (world space), and the pure
//  selectors that turn "the top face", "the top edges", "the vertical edges",
//  "the edges of this face", "the hole edges" or a clicked face into kernel
//  indices the feature ops take. Data comes from the same listing as
//  `GET /v1/faces` / `/v1/edges` (AgentBridge), so indices always agree.
//

import Foundation
import simd

struct VoiceKernelFace: Equatable {
    enum Kind: Equatable { case planar, cylindrical(radius: Double), other }
    let index: Int
    let centroid: SIMD3<Double>
    /// Outward normal for planar faces; the axis for cylinders.
    let normal: SIMD3<Double>
    let area: Double
    let kind: Kind
}

struct VoiceKernelEdge: Equatable {
    let index: Int
    /// The two faces the edge joins (kernel indices).
    let faces: [Int]
    let midpoint: SIMD3<Double>?
    let length: Double?
}

struct VoiceTopology: Equatable {
    let bodyID: BodyID
    let faces: [VoiceKernelFace]
    let edges: [VoiceKernelEdge]

    /// Normals within ~8° count as "the same direction".
    static let parallel = 0.99

    // MARK: Faces

    func face(_ index: Int) -> VoiceKernelFace? { faces.first { $0.index == index } }

    /// The outermost planar face pointing along `direction` — "the top face"
    /// is the highest face whose normal points up.
    func extremeFace(along direction: SIMD3<Double>) -> VoiceKernelFace? {
        let d = simd_normalize(direction)
        return faces
            .filter { $0.kind == .planar && simd_dot($0.normal, d) > Self.parallel }
            .max { simd_dot($0.centroid, d) < simd_dot($1.centroid, d) }
    }

    /// The planar face lying in the plane through `point` with `normal`
    /// (the face the user clicked, re-found after earlier steps changed the
    /// body). Nearest centroid wins when several share the plane.
    func face(inPlaneThrough point: SIMD3<Double>, normal: SIMD3<Double>,
              tolerance: Double = 1e-3) -> VoiceKernelFace? {
        let n = simd_normalize(normal)
        return faces
            .filter {
                $0.kind == .planar && simd_dot($0.normal, n) > Self.parallel
                    && abs(simd_dot($0.centroid - point, n)) < tolerance
            }
            .min { simd_distance($0.centroid, point) < simd_distance($1.centroid, point) }
    }

    // MARK: Edges

    func edges(touching faceIndices: Set<Int>) -> [VoiceKernelEdge] {
        edges.filter { !faceIndices.isDisjoint(with: $0.faces) }
    }

    /// Edges between two planar faces that both face sideways — a box's
    /// four upright corner edges.
    var verticalEdges: [VoiceKernelEdge] {
        edges.filter { edge in
            edge.faces.count == 2 && edge.faces.allSatisfy { index in
                guard let f = face(index), f.kind == .planar else { return false }
                return abs(f.normal.y) < 0.1
            }
        }
    }

    /// Edges on a cylindrical face — hole rims, boss rims, rounded corners.
    var roundEdges: [VoiceKernelEdge] {
        let round = Set(faces.filter { if case .cylindrical = $0.kind { return true }; return false }.map(\.index))
        return edges(touching: round)
    }

    /// Kernel edges nearest to each clicked (mesh) edge midpoint.
    func edges(nearest midpoints: [SIMD3<Double>], tolerance: Double = 0.5) -> [VoiceKernelEdge] {
        var picked: [VoiceKernelEdge] = []
        for point in midpoints {
            let best = edges
                .compactMap { edge in edge.midpoint.map { (edge, simd_distance($0, point)) } }
                .min { $0.1 < $1.1 }
            if let best, best.1 <= tolerance, !picked.contains(best.0) { picked.append(best.0) }
        }
        return picked
    }
}

// MARK: - Loading through the agent layer

/// One exec op's result, read from the agent layer's JSON reply.
struct VoiceOpResult: Equatable {
    let featureID: String?
    let producedBodyIDs: [BodyID]
    let changedBodyIDs: [BodyID]
}

enum VoiceAgent {
    /// Run an exec op on `viewModel` through the agent layer (one undo step).
    @MainActor
    static func run(_ op: AgentExecOp, on viewModel: EditorViewModel) -> Result<VoiceOpResult, VoiceApplyError> {
        read(AgentBridge.shared.perform(op, on: viewModel)).flatMap { json in
            if json["failed"] as? Bool == true {
                return .failure(.message(json["message"] as? String ?? "The operation failed."))
            }
            func ids(_ key: String) -> [BodyID] {
                (json[key] as? [String] ?? []).compactMap { UUID(uuidString: $0).map { BodyID(raw: $0) } }
            }
            return .success(VoiceOpResult(featureID: json["featureID"] as? String,
                                          producedBodyIDs: ids("producedBodyIDs"),
                                          changedBodyIDs: ids("changedBodyIDs")))
        }
    }

    @MainActor
    static func topology(of bodyID: BodyID, on viewModel: EditorViewModel) -> Result<VoiceTopology, VoiceApplyError> {
        let bridge = AgentBridge.shared
        return read(bridge.faces(of: bodyID, on: viewModel)).flatMap { facesJSON in
            read(bridge.edges(of: bodyID, on: viewModel)).map { edgesJSON in
                VoiceTopology(bodyID: bodyID,
                              faces: (facesJSON["faces"] as? [[String: Any]] ?? []).compactMap(face),
                              edges: (edgesJSON["edges"] as? [[String: Any]] ?? []).compactMap(edge))
            }
        }
    }

    private static func read(_ response: AgentResponse) -> Result<[String: Any], VoiceApplyError> {
        let json = (try? JSONSerialization.jsonObject(with: response.body)) as? [String: Any] ?? [:]
        guard response.status == 200, json["ok"] as? Bool != false else {
            let message = json["message"] as? String ?? "The operation was refused (\(response.status))."
            return .failure(.message(message))
        }
        return .success(json)
    }

    private static func vector(_ any: Any?) -> SIMD3<Double>? {
        guard let a = any as? [Double], a.count == 3 else {
            guard let n = any as? [NSNumber], n.count == 3 else { return nil }
            return SIMD3(n[0].doubleValue, n[1].doubleValue, n[2].doubleValue)
        }
        return SIMD3(a[0], a[1], a[2])
    }

    private static func face(_ row: [String: Any]) -> VoiceKernelFace? {
        guard let index = row["index"] as? Int,
              let centroid = vector(row["centroid"]), let normal = vector(row["normal"]) else { return nil }
        let kind: VoiceKernelFace.Kind
        switch row["kind"] as? String {
        case "planar": kind = .planar
        case "cylindrical": kind = .cylindrical(radius: row["radiusMM"] as? Double ?? 0)
        default: kind = .other
        }
        return VoiceKernelFace(index: index, centroid: centroid, normal: normal,
                               area: row["areaMM2"] as? Double ?? 0, kind: kind)
    }

    private static func edge(_ row: [String: Any]) -> VoiceKernelEdge? {
        guard let index = row["index"] as? Int else { return nil }
        return VoiceKernelEdge(index: index, faces: row["faces"] as? [Int] ?? [],
                               midpoint: vector(row["midpoint"]), length: row["lengthMM"] as? Double)
    }
}
