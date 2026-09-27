//
//  VoiceIntent.swift
//  openshape3d
//
//  PrintCAD V1: what Jev is asked and how its answer is read. Pure — the
//  HTTP call lives in JevClient.swift, execution in EditorViewModel+VoiceApply.
//
//  A command is split into steps (CommandSplitter). For EVERY step Jev answers
//  the same small set of typed questions — which action, on what, where, how
//  deep, which way, about which axis, set-or-change, which variable, and what
//  each spoken number means — all in ONE request, answered in parallel.
//  Jev only ever chooses between the options below; it never writes numbers
//  or text, so it cannot invent an operation. Catalog: docs/printcad/VOICE.md.
//

import Foundation

// MARK: - Options

enum VoiceAction: String, CaseIterable {
    // Features on a face
    case hole
    case cornerHoles = "corner_holes"
    case pocket, boss, pad
    case extrudeFaceOut = "extrude_face_out", cutFaceIn = "cut_face_in"
    case moveFace = "move_face", draftFace = "draft_face", deleteFace = "delete_face"
    case shellRemoveFace = "shell_remove_face"
    // Edges
    case filletEdges = "fillet_edges", chamferEdges = "chamfer_edges"
    // Sketch profile
    case extrudeProfile = "extrude_profile", cutProfile = "cut_profile"
    // Bodies
    case shellBody = "shell_body"
    case mirrorBody = "mirror_body", linearPattern = "linear_pattern", circularPattern = "circular_pattern"
    case moveBody = "move_body", rotateBody = "rotate_body", scaleBody = "scale_body"
    case duplicateBody = "duplicate_body", deleteBody = "delete_body", hideBody = "hide_body"
    case showAll = "show_all"
    case joinBodies = "join_bodies", subtractBodies = "subtract_bodies", intersectBodies = "intersect_bodies"
    // New solids
    case addBox = "add_box", addCylinder = "add_cylinder", addSphere = "add_sphere"
    // Editing what exists
    case modifyLast = "modify_last", repeatLast = "repeat_last", setVariable = "set_variable"
    case undo, redo
    // View
    case viewTop = "view_top", viewBottom = "view_bottom", viewFront = "view_front", viewBack = "view_back"
    case viewLeft = "view_left", viewRight = "view_right", viewIsometric = "view_isometric", fitView = "fit_view"
    // Inspect
    case measureThickness = "measure_thickness", measureArea = "measure_area"
    case measureVolume = "measure_volume", measureSize = "measure_size", printCheck = "print_check"
    // Output
    case exportSTL = "export_stl", export3MF = "export_3mf"
    case notUnderstood = "not_understood"

    /// The rubric Jev reads for this option.
    var criterion: String {
        switch self {
        case .hole: return "Drill or cut one round hole into a face"
        case .cornerHoles: return "Drill holes near each corner of a face (mounting holes)"
        case .pocket: return "Cut a rectangular pocket, recess or cut-out into a face"
        case .boss: return "Add a round post, peg, boss, stand-off or cylinder standing on a face"
        case .pad: return "Add a rectangular block, pad or rib standing on a face"
        case .extrudeFaceOut: return "Pull, raise or extrude a face outward so the part gets thicker, taller or longer ('pull this up 5 mm')"
        case .cutFaceIn: return "Push an existing face inward, making the part thinner/shorter"
        case .moveFace: return "Slide a face sideways to a new position without growing the part outward"
        case .draftFace: return "Tilt or add draft angle to a face"
        case .deleteFace: return "Remove or delete a face and heal the gap"
        case .shellRemoveFace: return "Hollow out or shell the part, leaving the clicked face open (box, cup, tray, enclosure) — the usual meaning of 'hollow it out'"
        case .filletEdges: return "Round off or fillet edges"
        case .chamferEdges: return "Bevel or chamfer edges"
        case .extrudeProfile: return "Extrude a flat sketch profile into a new solid"
        case .cutProfile: return "Cut a sketch profile through or into existing material"
        case .shellBody: return "Hollow the part completely sealed, with no opening at all ('closed', 'sealed', 'no opening')"
        case .mirrorBody: return "Mirror a part across a plane or face"
        case .linearPattern: return "Make several copies of a part in a row"
        case .circularPattern: return "Make several copies of a part around a centre in a circle"
        case .moveBody: return "Move or translate a whole part by a distance"
        case .rotateBody: return "Rotate or turn a whole part by an angle"
        case .scaleBody: return "Scale a whole part by a percentage or factor ('to 150%', 'twice as big', 'half size')"
        case .duplicateBody: return "Make one copy of a part next to it"
        case .deleteBody: return "Delete a whole part"
        case .hideBody: return "Hide a part from view"
        case .showAll: return "Show all hidden parts again"
        case .joinBodies: return "Join, merge or union parts together into one"
        case .subtractBodies: return "Subtract one part from another"
        case .intersectBodies: return "Keep only where parts overlap"
        case .addBox: return "Create a new box, cube or block from nothing"
        case .addCylinder: return "Create a new cylinder or disc from nothing"
        case .addSphere: return "Create a new sphere or ball from nothing"
        case .modifyLast: return "Change a size of the edit just made instead of adding anything new: 'make it 6', '2 mm deeper', 'a bit bigger', 'wider', 'change that to 4'"
        case .repeatLast: return "Do the same thing again on the new selection"
        case .setVariable: return "Set or change a named variable to a value"
        case .undo: return "Undo the previous edit"
        case .redo: return "Redo the edit that was undone"
        case .viewTop: return "Show the model from the top"
        case .viewBottom: return "Show the model from the bottom"
        case .viewFront: return "Show the model from the front"
        case .viewBack: return "Show the model from the back"
        case .viewLeft: return "Show the model from the left side"
        case .viewRight: return "Show the model from the right side"
        case .viewIsometric: return "Show an isometric 3D view"
        case .fitView: return "Zoom to fit or recentre the whole model on screen"
        case .measureThickness: return "Tell how thick or deep something is"
        case .measureArea: return "Tell the area of a face"
        case .measureVolume: return "Tell the volume or weight of a part"
        case .measureSize: return "Tell the overall size or dimensions of a part"
        case .printCheck: return "Check whether the part will fit and print on the 3D printer"
        case .exportSTL: return "Export or save the model as an STL file for printing"
        case .export3MF: return "Export or save the model as a 3MF file"
        case .notUnderstood: return "None of the above, or the request is unclear"
        }
    }

    var title: String {
        rawValue.replacingOccurrences(of: "_", with: " ").capitalized
            .replacingOccurrences(of: "Stl", with: "STL").replacingOccurrences(of: "3Mf", with: "3MF")
    }
}

/// What a step acts on.
enum VoiceTargetChoice: String, CaseIterable {
    case picked, wholeBody = "whole_body", previousResult = "previous_result", allBodies = "all_bodies"
    case topFace = "top_face", bottomFace = "bottom_face", frontFace = "front_face", backFace = "back_face"
    case leftFace = "left_face", rightFace = "right_face"
    case allEdges = "all_edges", topEdges = "top_edges", bottomEdges = "bottom_edges"
    case verticalEdges = "vertical_edges", pickedFaceEdges = "picked_face_edges", holeEdges = "hole_edges"
    case nothing

    var criterion: String {
        switch self {
        case .picked: return "What the user clicked / 'this' / 'here' / 'it' (the `selection`)"
        case .wholeBody: return "The whole part"
        case .previousResult: return "The part changed or made by the previous step"
        case .allBodies: return "Every part in the model"
        case .topFace: return "The top face of the part"
        case .bottomFace: return "The bottom face of the part"
        case .frontFace: return "The front face of the part"
        case .backFace: return "The back face of the part"
        case .leftFace: return "The left side face of the part"
        case .rightFace: return "The right side face of the part"
        case .allEdges: return "All edges of the part"
        case .topEdges: return "The edges around the top of the part"
        case .bottomEdges: return "The edges around the bottom of the part"
        case .verticalEdges: return "The vertical / upright / corner edges of the part"
        case .pickedFaceEdges: return "The edges around the clicked face"
        case .holeEdges: return "The edges of the holes / round edges"
        case .nothing: return "Nothing in particular (view, undo, new part, export…)"
        }
    }
}

enum VoicePlacement: String, CaseIterable {
    case faceCenter = "face_center", clickedPoint = "clicked_point", corners, notApplicable = "not_applicable"

    var criterion: String {
        switch self {
        case .faceCenter: return "At the centre / middle, or no position stated"
        case .clickedPoint: return "At the exact point the user clicked, 'here'"
        case .corners: return "Near the corners"
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

enum VoiceDirection: String, CaseIterable {
    case up, down, left, right, forward, backward, outward, inward
    case notApplicable = "not_applicable"

    var criterion: String {
        switch self {
        case .up: return "Up / upward / higher"
        case .down: return "Down / downward / lower"
        case .left: return "To the left"
        case .right: return "To the right"
        case .forward: return "Forward / toward the front"
        case .backward: return "Backward / toward the back"
        case .outward: return "Outward / away from the part"
        case .inward: return "Inward / into the part"
        case .notApplicable: return "No direction stated"
        }
    }

    /// World direction (the app is Y-up; front is +Z).
    var vector: SIMD3<Double>? {
        switch self {
        case .up: return SIMD3(0, 1, 0)
        case .down: return SIMD3(0, -1, 0)
        case .left: return SIMD3(-1, 0, 0)
        case .right: return SIMD3(1, 0, 0)
        case .forward: return SIMD3(0, 0, 1)
        case .backward: return SIMD3(0, 0, -1)
        case .outward, .inward, .notApplicable: return nil
        }
    }
}

enum VoiceAxis: String, CaseIterable {
    case x, y, z, pickedFace = "picked_face", notApplicable = "not_applicable"

    var criterion: String {
        switch self {
        case .x: return "The X axis / left-right / side to side"
        case .y: return "The Y axis / vertical / up-down"
        case .z: return "The Z axis / front-back"
        case .pickedFace: return "Across or about the clicked face"
        case .notApplicable: return "No axis or plane stated"
        }
    }

    var vector: SIMD3<Double>? {
        switch self {
        case .x: return SIMD3(1, 0, 0)
        case .y: return SIMD3(0, 1, 0)
        case .z: return SIMD3(0, 0, 1)
        case .pickedFace, .notApplicable: return nil
        }
    }
}

/// "make it 6" vs "2 mm deeper" vs "bigger".
enum VoiceRelative: String, CaseIterable {
    case setTo = "set_to", increaseBy = "increase_by", decreaseBy = "decrease_by"
    case bigger, smaller, notApplicable = "not_applicable"

    var criterion: String {
        switch self {
        case .setTo: return "Set to a new value ('make it 6')"
        case .increaseBy: return "Increase by an amount ('2 mm more / deeper / longer')"
        case .decreaseBy: return "Decrease by an amount ('1 mm less / shallower / shorter')"
        case .bigger: return "Bigger / larger / more, no amount given"
        case .smaller: return "Smaller / less, no amount given"
        case .notApplicable: return "Not a change to an existing size"
        }
    }
}

enum NumberRole: String, CaseIterable {
    case diameter, radius, depth, distance, thickness, height, width, length
    case count, angle, spacing, scale, other
}

// MARK: - Request (matches POST /v1/systemone, docs.typesafe.ai/api.md)

struct JevRequest: Encodable, Equatable {
    struct State: Encodable, Equatable {
        let transcript: String
        let selection: String
        /// "s1": "drill a 5 mm hole in the centre"
        let steps: [String: String]
        /// "s1_n1": "5 mm (1st number in s1)" — omitted when nothing was said.
        let numbers: [String: String]?
        /// Existing variable names, when any.
        let variables: [String]?
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
    /// More steps than this is almost certainly a mis-split; they're dropped.
    static let maxSteps = 6

    static func criteria<T: RawRepresentable & CaseIterable>(_ type: T.Type, _ describe: (T) -> String) -> [String: String]
    where T.RawValue == String {
        Dictionary(uniqueKeysWithValues: type.allCases.map { ($0.rawValue, describe($0)) })
    }

    static func jevRequest(for request: VoiceRequest, variables: [String] = []) -> JevRequest {
        let steps = Array(CommandSplitter.steps(in: request.transcript).prefix(maxSteps))
        let stepTexts = steps.isEmpty ? [request.transcript] : steps
        var questions: [String: JevRequest.Question] = [:]
        var numberState: [String: String] = [:]
        let roles = Dictionary(uniqueKeysWithValues: NumberRole.allCases.map { ($0.rawValue, "The number is the \($0.rawValue)") })

        for (index, text) in stepTexts.enumerated() {
            let s = "s\(index + 1)"
            let about = "Step `\(s)` of the user's command (whole command: `transcript`; what is clicked: `selection`)"
            questions["\(s)_action"] = .init(
                instructions: "\(about): which CAD operation does it ask for?",
                criteria: criteria(VoiceAction.self, \.criterion))
            questions["\(s)_target"] = .init(
                instructions: "\(about): what does it act on?",
                criteria: criteria(VoiceTargetChoice.self, \.criterion))
            questions["\(s)_placement"] = .init(
                instructions: "\(about): where on the face should a new feature go?",
                criteria: criteria(VoicePlacement.self, \.criterion))
            questions["\(s)_depth"] = .init(
                instructions: "\(about): how deep should a hole or cut go?",
                criteria: criteria(VoiceDepth.self, \.criterion))
            questions["\(s)_direction"] = .init(
                instructions: "\(about): which direction is stated?",
                criteria: criteria(VoiceDirection.self, \.criterion))
            questions["\(s)_axis"] = .init(
                instructions: "\(about): which axis or plane (for mirror, rotate, pattern)?",
                criteria: criteria(VoiceAxis.self, \.criterion))
            questions["\(s)_relative"] = .init(
                instructions: "\(about): does it set a size or change it relative to what it is?",
                criteria: criteria(VoiceRelative.self, \.criterion))
            if !variables.isEmpty {
                var options = Dictionary(uniqueKeysWithValues: variables.map { ($0, "The variable named \($0)") })
                options["none"] = "No variable is mentioned"
                questions["\(s)_variable"] = .init(
                    instructions: "\(about): which variable from `variables` does it mention?",
                    criteria: options)
            }
            for (n, number) in SpokenNumberParser.numbers(in: text).enumerated() {
                let key = "\(s)_n\(n + 1)"
                numberState[key] = "\(number.phrase) (\(ordinal(n + 1)) number in \(s))"
                questions["\(key)_role"] = .init(
                    instructions: "In step `\(s)`, what does number `\(key)` describe?",
                    criteria: roles)
            }
        }
        return JevRequest(
            state: .init(transcript: request.transcript,
                         selection: request.target.classifierDescription,
                         steps: Dictionary(uniqueKeysWithValues: stepTexts.enumerated().map { ("s\($0.offset + 1)", $0.element) }),
                         numbers: numberState.isEmpty ? nil : numberState,
                         variables: variables.isEmpty ? nil : variables),
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

    static func decision(from response: Response, for request: JevRequest,
                         latency: TimeInterval) throws -> VoiceDecision {
        func answer(_ key: String) throws -> (String, Double, [String: Double]) {
            guard let a = response.answers[key], let choice = a.choice else { throw DecodeError.missingAnswer(key) }
            return (choice, a.confidence ?? 0, a.probabilities ?? [:])
        }
        func option<T: RawRepresentable>(_ key: String, _ type: T.Type) throws -> T where T.RawValue == String {
            let (raw, _, _) = try answer(key)
            guard let value = T(rawValue: raw) else { throw DecodeError.unknownOption(key, raw) }
            return value
        }

        var steps: [VoiceStep] = []
        for index in 0..<request.state.steps.count {
            let s = "s\(index + 1)"
            let text = request.state.steps[s] ?? ""
            let (actionKey, confidence, probabilities) = try answer("\(s)_action")
            guard let action = VoiceAction(rawValue: actionKey) else {
                throw DecodeError.unknownOption("\(s)_action", actionKey)
            }
            var numbers: [VoiceStep.LabelledNumber] = []
            for (n, number) in SpokenNumberParser.numbers(in: text).enumerated() {
                let key = "\(s)_n\(n + 1)_role"
                let (roleKey, roleConfidence, _) = try answer(key)
                guard let role = NumberRole(rawValue: roleKey) else { throw DecodeError.unknownOption(key, roleKey) }
                numbers.append(.init(number: number, role: role, confidence: roleConfidence))
            }
            var variable: String?
            if request.questions["\(s)_variable"] != nil {
                let (name, _, _) = try answer("\(s)_variable")
                variable = name == "none" ? nil : name
            }
            let alternatives = probabilities
                .compactMap { key, p in VoiceAction(rawValue: key).map { VoiceStep.Alternative(action: $0, probability: p) } }
                .sorted { $0.probability > $1.probability }
            steps.append(VoiceStep(
                text: text, action: action, confidence: confidence, alternatives: alternatives,
                target: try option("\(s)_target", VoiceTargetChoice.self),
                placement: try option("\(s)_placement", VoicePlacement.self),
                depth: try option("\(s)_depth", VoiceDepth.self),
                direction: try option("\(s)_direction", VoiceDirection.self),
                axis: try option("\(s)_axis", VoiceAxis.self),
                relative: try option("\(s)_relative", VoiceRelative.self),
                variable: variable, numbers: numbers))
        }
        return VoiceDecision(steps: steps, model: response.model, latency: latency)
    }
}

// MARK: - Decision

/// One instruction within a command.
struct VoiceStep: Equatable {
    struct Alternative: Equatable {
        let action: VoiceAction
        let probability: Double
    }
    struct LabelledNumber: Equatable {
        let number: SpokenNumber
        let role: NumberRole
        let confidence: Double
    }

    var text: String
    var action: VoiceAction
    /// Jev's confidence in `action`, 0…1 (1 once the user picks an option).
    var confidence: Double
    /// Every action option, most likely first.
    var alternatives: [Alternative]
    var target: VoiceTargetChoice
    var placement: VoicePlacement
    var depth: VoiceDepth
    var direction: VoiceDirection
    var axis: VoiceAxis
    var relative: VoiceRelative
    var variable: String?
    var numbers: [LabelledNumber]

    /// Below this, the panel asks instead of acting (tuned with real use).
    static let confirmThreshold = 0.6

    var needsConfirmation: Bool {
        confidence < Self.confirmThreshold || action == .notUnderstood
    }

    /// The top few choices to offer when unsure.
    var suggestions: [Alternative] {
        Array(alternatives.filter { $0.action != .notUnderstood && $0.probability > 0.02 }.prefix(3))
    }

    /// First number Jev labelled with one of `roles`.
    func number(_ roles: NumberRole...) -> SpokenNumber? {
        numbers.first { roles.contains($0.role) }?.number
    }

    /// Every number Jev labelled with one of `roles`, in spoken order.
    func numbers(_ roles: NumberRole...) -> [SpokenNumber] {
        numbers.filter { roles.contains($0.role) }.map(\.number)
    }
}

struct VoiceDecision: Equatable {
    var steps: [VoiceStep]
    /// The versioned model that answered, e.g. "jev-1.13.0".
    let model: String
    /// Enter → answer, seconds.
    let latency: TimeInterval

    /// The first step that needs the user to pick before anything runs.
    var unsureStepIndex: Int? { steps.firstIndex { $0.needsConfirmation } }
    var needsConfirmation: Bool { unsureStepIndex != nil }
    /// Lowest step confidence — what the panel shows.
    var confidence: Double { steps.map(\.confidence).min() ?? 0 }
}
