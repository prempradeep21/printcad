//
//  VoiceIntent.swift
//  openshape3d
//
//  PrintCAD V1.2: what Jev is asked and how its answer is read. Pure — the
//  HTTP call lives in JevClient.swift. Jev picks from options we define; the
//  option list is filtered by what is selected so it never sees actions that
//  can't apply. Catalog and rationale: docs/printcad/VOICE.md.
//

import Foundation

// MARK: - Options

enum VoiceAction: String, CaseIterable {
    // Face
    case hole, pocket, boss, extrudeFaceOut = "extrude_face_out", cutFaceIn = "cut_face_in"
    case shellRemoveFace = "shell_remove_face", deleteFace = "delete_face", moveFace = "move_face"
    // Edges
    case filletEdges = "fillet_edges", chamferEdges = "chamfer_edges"
    // Sketch profile
    case extrudeProfile = "extrude_profile", cutProfile = "cut_profile", revolveProfile = "revolve_profile"
    // Bodies
    case mirrorBody = "mirror_body", linearPattern = "linear_pattern", circularPattern = "circular_pattern"
    case moveBody = "move_body", rotateBody = "rotate_body", scaleBody = "scale_body"
    case duplicateBody = "duplicate_body", deleteBody = "delete_body"
    // Anywhere
    case undo, redo, viewTop = "view_top", viewFront = "view_front", viewIsometric = "view_isometric"
    case fitView = "fit_view", exportSTL = "export_stl"
    case notUnderstood = "not_understood"

    /// The rubric Jev reads for this option.
    var criterion: String {
        switch self {
        case .hole: return "Drill or cut a round hole into the selected face"
        case .pocket: return "Cut a rectangular pocket or recess into the selected face"
        case .boss: return "Add a round post, boss or cylinder standing on the selected face"
        case .extrudeFaceOut: return "Pull the selected face outward, adding material (extrude, pull up, thicken)"
        case .cutFaceIn: return "Push the selected face inward, removing material"
        case .shellRemoveFace: return "Hollow the body out, leaving the selected face open"
        case .deleteFace: return "Remove the selected face"
        case .moveFace: return "Move or offset the selected face by a distance"
        case .filletEdges: return "Round the selected edges (fillet)"
        case .chamferEdges: return "Bevel the selected edges (chamfer)"
        case .extrudeProfile: return "Extrude the selected sketch profile into a solid, adding material"
        case .cutProfile: return "Cut the selected sketch profile into existing material (subtract)"
        case .revolveProfile: return "Revolve the selected sketch profile around an axis"
        case .mirrorBody: return "Mirror the selected body"
        case .linearPattern: return "Make copies of the selected body in a row"
        case .circularPattern: return "Make copies of the selected body around a centre"
        case .moveBody: return "Move the selected body by a distance"
        case .rotateBody: return "Rotate the selected body by an angle"
        case .scaleBody: return "Make the selected body bigger or smaller"
        case .duplicateBody: return "Duplicate the selected body"
        case .deleteBody: return "Delete the selected body"
        case .undo: return "Undo the previous edit"
        case .redo: return "Redo the edit that was undone"
        case .viewTop: return "Show the model from the top"
        case .viewFront: return "Show the model from the front"
        case .viewIsometric: return "Show an isometric view"
        case .fitView: return "Zoom to fit or recentre the whole model"
        case .exportSTL: return "Export the model as an STL file for printing"
        case .notUnderstood: return "None of the above, or the request is unclear"
        }
    }

    var title: String {
        rawValue.replacingOccurrences(of: "_", with: " ").capitalized
            .replacingOccurrences(of: "Stl", with: "STL")
    }

    /// Only what can apply to the current pick, plus the always-available ones.
    static func options(for target: VoiceTarget) -> [VoiceAction] {
        let anywhere: [VoiceAction] = [.undo, .redo, .viewTop, .viewFront, .viewIsometric,
                                        .fitView, .exportSTL, .notUnderstood]
        switch target {
        case .face:
            return [.hole, .pocket, .boss, .extrudeFaceOut, .cutFaceIn, .shellRemoveFace,
                    .deleteFace, .moveFace] + anywhere
        case .edges:
            return [.filletEdges, .chamferEdges] + anywhere
        case .sketchProfile:
            return [.extrudeProfile, .cutProfile, .revolveProfile] + anywhere
        case .bodies:
            return [.mirrorBody, .linearPattern, .circularPattern, .moveBody, .rotateBody,
                    .scaleBody, .duplicateBody, .deleteBody] + anywhere
        case .nothing:
            return anywhere
        }
    }
}

enum VoicePlacement: String, CaseIterable {
    case faceCenter = "face_center", clickedPoint = "clicked_point", notApplicable = "not_applicable"

    var criterion: String {
        switch self {
        case .faceCenter: return "At the centre / middle of the selection"
        case .clickedPoint: return "At the point the user clicked, 'here'"
        case .notApplicable: return "No position is involved"
        }
    }
}

enum VoiceDepth: String, CaseIterable {
    case throughAll = "through_all", blind, notApplicable = "not_applicable"

    var criterion: String {
        switch self {
        case .throughAll: return "All the way through, or a hole/cut with no depth stated"
        case .blind: return "A specific depth is stated"
        case .notApplicable: return "Not a hole or cut"
        }
    }
}

enum NumberRole: String, CaseIterable {
    case diameter, radius, depth, distance, thickness, height, width, length
    case count, angle, spacing, other
}

// MARK: - Request (matches POST /v1/systemone, docs.typesafe.ai/api.md)

struct JevRequest: Encodable, Equatable {
    struct State: Encodable, Equatable {
        let transcript: String
        let selection: String
        /// "n1": "7 mm (1st number)" — omitted when nothing was said.
        let numbers: [String: String]?
    }
    struct Question: Encodable, Equatable {
        var type = "choice"
        let instructions: String
        let criteria: [String: String]
    }

    var model = "jev-latest"
    let state: State
    let questions: [String: Question]
}

enum VoiceIntent {
    static func jevRequest(for request: VoiceRequest, numbers: [SpokenNumber]) -> JevRequest {
        let actions = VoiceAction.options(for: request.target)
        var questions: [String: JevRequest.Question] = [
            "action": .init(
                instructions: "Which CAD operation does the user's `transcript` ask for on the `selection`?",
                criteria: Dictionary(uniqueKeysWithValues: actions.map { ($0.rawValue, $0.criterion) })),
            "placement": .init(
                instructions: "Where on the `selection` should the new feature go, per the `transcript`?",
                criteria: Dictionary(uniqueKeysWithValues: VoicePlacement.allCases.map { ($0.rawValue, $0.criterion) })),
            "depth": .init(
                instructions: "How deep should a hole or cut go, per the `transcript`?",
                criteria: Dictionary(uniqueKeysWithValues: VoiceDepth.allCases.map { ($0.rawValue, $0.criterion) })),
        ]
        let roles = Dictionary(uniqueKeysWithValues: NumberRole.allCases.map { ($0.rawValue, "The number is the \($0.rawValue)") })
        for index in numbers.indices {
            let key = "n\(index + 1)"
            questions["role_\(key)"] = .init(
                instructions: "In the `transcript`, what does number `\(key)` describe?",
                criteria: roles)
        }
        let numberState = numbers.isEmpty ? nil : Dictionary(uniqueKeysWithValues: numbers.enumerated().map {
            ("n\($0.offset + 1)", "\($0.element.phrase) (\(ordinal($0.offset + 1)) number)")
        })
        return JevRequest(
            state: .init(transcript: request.transcript,
                         selection: request.target.classifierDescription,
                         numbers: numberState),
            questions: questions)
    }

    private static func ordinal(_ n: Int) -> String {
        switch n {
        case 1: return "1st"
        case 2: return "2nd"
        case 3: return "3rd"
        default: return "\(n)th"
        }
    }

    // MARK: - Response

    struct Response: Decodable {
        struct Answer: Decodable {
            let type: String
            let choice: String?
            let confidence: Double?
            let probabilities: [String: Double]?
        }
        let model: String
        let answers: [String: Answer]
    }

    enum DecodeError: LocalizedError, Equatable {
        case missingAnswer(String)
        case unknownOption(String, String)

        var errorDescription: String? {
            switch self {
            case .missingAnswer(let key): return "Jev's reply had no answer for “\(key)”."
            case .unknownOption(let key, let value): return "Jev answered “\(value)” for “\(key)”, which isn't an option."
            }
        }
    }

    static func decision(from response: Response, numbers: [SpokenNumber],
                         latency: TimeInterval) throws -> VoiceDecision {
        func answer(_ key: String) throws -> (String, Double, [String: Double]) {
            guard let a = response.answers[key], let choice = a.choice else { throw DecodeError.missingAnswer(key) }
            return (choice, a.confidence ?? 0, a.probabilities ?? [:])
        }
        let (actionKey, confidence, probabilities) = try answer("action")
        guard let action = VoiceAction(rawValue: actionKey) else {
            throw DecodeError.unknownOption("action", actionKey)
        }
        let (placementKey, _, _) = try answer("placement")
        guard let placement = VoicePlacement(rawValue: placementKey) else {
            throw DecodeError.unknownOption("placement", placementKey)
        }
        let (depthKey, _, _) = try answer("depth")
        guard let depth = VoiceDepth(rawValue: depthKey) else {
            throw DecodeError.unknownOption("depth", depthKey)
        }
        var labelled: [VoiceDecision.LabelledNumber] = []
        for (index, number) in numbers.enumerated() {
            let key = "role_n\(index + 1)"
            let (roleKey, roleConfidence, _) = try answer(key)
            guard let role = NumberRole(rawValue: roleKey) else { throw DecodeError.unknownOption(key, roleKey) }
            labelled.append(.init(number: number, role: role, confidence: roleConfidence))
        }
        let alternatives = probabilities
            .compactMap { key, p in VoiceAction(rawValue: key).map { VoiceDecision.Alternative(action: $0, probability: p) } }
            .sorted { $0.probability > $1.probability }
        return VoiceDecision(action: action, confidence: confidence, alternatives: alternatives,
                             placement: placement, depth: depth, numbers: labelled,
                             model: response.model, latency: latency)
    }
}

// MARK: - Decision

struct VoiceDecision: Equatable {
    struct Alternative: Equatable {
        let action: VoiceAction
        let probability: Double
    }
    struct LabelledNumber: Equatable {
        let number: SpokenNumber
        let role: NumberRole
        let confidence: Double
    }

    var action: VoiceAction
    /// Jev's confidence in `action`, 0…1 (1 once the user picks an option).
    var confidence: Double
    /// Every action option, most likely first.
    let alternatives: [Alternative]
    let placement: VoicePlacement
    let depth: VoiceDepth
    let numbers: [LabelledNumber]
    /// The versioned model that answered, e.g. "jev-1.13.0".
    let model: String
    /// Enter → answer, seconds.
    let latency: TimeInterval

    /// Below this, the panel asks instead of acting (tuned later with real use).
    static let confirmThreshold = 0.6

    var needsConfirmation: Bool {
        confidence < Self.confirmThreshold || action == .notUnderstood
    }

    /// The top few other choices to offer when unsure.
    var suggestions: [Alternative] {
        Array(alternatives.filter { $0.action != .notUnderstood && $0.probability > 0.02 }.prefix(3))
    }
}
