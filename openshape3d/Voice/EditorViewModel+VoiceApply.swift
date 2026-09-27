//
//  EditorViewModel+VoiceApply.swift
//  openshape3d
//
//  PrintCAD V1: carry out Jev's decision — every step of a command, in order.
//
//  • What was picked is frozen at Enter (`VoicePick`), so a click during the
//    ~0.5 s wait can't move the edit.
//  • Each step resolves its target ("this face", "the top edges", "it", …)
//    against the body's CURRENT kernel faces/edges, so a later step still
//    finds the face an earlier step changed.
//  • Feature work goes through the agent layer (`AgentBridge.perform`) or, for
//    sketch-on-face features, a hidden sketch + extrude — both replay through
//    OCCT like hand-made features.
//  • The whole command is ONE undo step. If any step fails, every earlier step
//    is undone and the reason is shown: the last valid model is kept
//    (CLAUDE.md rule 9).
//

import Foundation
import simd

/// What was picked when Enter was pressed.
struct VoicePick: Equatable {
    /// A clicked face: its body, a point on it and its normal (world).
    struct Face: Equatable {
        let bodyID: BodyID
        let point: SIMD3<Double>
        let normal: SIMD3<Double>
    }
    /// A picked sketch profile (the extrude arrow is up).
    struct Profile: Equatable {
        let sketchID: SketchID
        let plane: SketchPlane
        let seed: SIMD2<Double>
    }

    var face: Face?
    var edgeBodyID: BodyID?
    var edgeMidpoints: [SIMD3<Double>] = []
    var bodies: [BodyID] = []
    var profile: Profile?
    /// Where the face was tapped ("here").
    var clickPoint: SIMD3<Double>?

    /// The body the pick belongs to, if any.
    var bodyID: BodyID? { face?.bodyID ?? edgeBodyID ?? bodies.first }
}

extension EditorViewModel {
    // MARK: - Capturing the pick

    var currentVoicePick: VoicePick {
        var pick = VoicePick()
        pick.bodies = Array(selection)
        if let context = toolContext {
            switch mode {
            case .faceSelected(let id):
                pick.face = face(of: context, bodyID: id)
                pick.clickPoint = voicePickPoint
            case .extruding:
                if let id = context.sourceBody {
                    pick.face = face(of: context, bodyID: id)
                    pick.clickPoint = voicePickPoint
                } else if let sketchID = context.sketchID {
                    pick.profile = .init(sketchID: sketchID, plane: context.plane,
                                         seed: VoiceRecipe.centroid(of: context.profile.loop))
                }
            default:
                break
            }
        }
        if case .pickingBlendEdges = mode, let id = blendBodyID, !blendSelectedEdges.isEmpty {
            pick.edgeBodyID = id
            pick.edgeMidpoints = blendSelectedEdges.map { edge in
                let body = session.document.body(with: id)
                let local = SIMD3<Double>((edge.start + edge.end) / 2)
                return body?.transform.applying(to: local) ?? local
            }
        }
        // Nothing clicked: the face under the pointer is "this" (Mac hover).
        if pick.face == nil, pick.edgeBodyID == nil, pick.bodies.isEmpty, pick.profile == nil,
           let hovered = hoveredVoiceFace {
            pick.face = hovered.face
            pick.clickPoint = hovered.face.point
        }
        return pick
    }

    /// The planar face under the pointer, with its area (nil when the
    /// pointer isn't over a flat face).
    var hoveredVoiceFace: (face: VoicePick.Face, area: Double)? {
        guard let ray = hoverRay, let hit = HitTester.pickBody(ray: ray, in: scene),
              let body = session.document.body(with: hit.bodyID),
              let face = FaceTopology.planarFace(in: body.render, seedTriangle: hit.triangleIndex)
        else { return nil }
        let normal = simd_normalize(body.transform.rotation.act(simd_cross(face.basisX, face.basisY)))
        let area = MeasureKit.faceArea(body.render, triangles: face.triangles, scale: body.transform.scale)
        return (.init(bodyID: body.id, point: SIMD3<Double>(hit.worldPoint), normal: normal), area)
    }

    private func face(of context: ToolContext, bodyID: BodyID) -> VoicePick.Face {
        let centre = VoiceRecipe.centroid(of: context.profile.loop)
        return .init(bodyID: bodyID, point: context.plane.toWorld(centre),
                     normal: simd_normalize(context.plane.normal))
    }

    // MARK: - Running a decision

    /// Carry out every step of a decision; reports the outcome to the panel.
    func applyVoiceDecision(_ request: VoiceRequest, _ decision: VoiceDecision) {
        let pick = voicePick ?? VoicePick()
        let stack = session.undoStack
        let depth = stack.undoCommands.count
        var run = VoiceRun(pick: pick)
        var lines: [String] = []
        let touchesHistory = decision.steps.contains { $0.action == .undo || $0.action == .redo || $0.action == .repeatLast }

        for (index, step) in decision.steps.enumerated() {
            switch perform(step, run: &run, transcript: request.transcript) {
            case .success(let message):
                lines.append(decision.steps.count > 1 ? "\(index + 1). \(message)" : message)
            case .failure(let error):
                // Keep the last valid model: undo whatever earlier steps did.
                var rolledBack = false
                if !touchesHistory {
                    while stack.undoCommands.count > depth { session.undo(); rolledBack = true }
                }
                let which = decision.steps.count > 1 ? "Step \(index + 1) (“\(step.text)”): " : ""
                let tail = rolledBack ? " Nothing was changed." : ""
                voice.reportApplied(ok: false, message: which + error.message + tail)
                return
            }
        }

        let added = stack.undoCommands.count - depth
        if added > 1, !touchesHistory {
            stack.coalesce(from: depth, title: "Voice: \(request.transcript)")
        }
        if added > 0, !touchesHistory {
            lastVoiceSteps = decision.steps.filter { $0.action != .repeatLast }
            if let body = run.lastBody, session.document.body(with: body) != nil {
                toolContext = nil
                selection = [body]
                mode = .selected(body)
            }
        }
        voice.reportApplied(ok: true, message: lines.joined(separator: "  "))
    }

    /// Per-command working state.
    struct VoiceRun {
        let pick: VoicePick
        /// The body the last step changed or made ("it" in the next step).
        var lastBody: BodyID?
        /// The feature the last step recorded ("make it 6").
        var lastFeatureID: FeatureID?
    }

    private func perform(_ step: VoiceStep, run: inout VoiceRun, transcript: String) -> Result<String, VoiceApplyError> {
        switch step.action {
        // Features on a face
        case .hole, .cornerHoles, .pocket, .boss, .pad:
            return sketchOnFace(step, run: &run)
        case .extrudeFaceOut, .cutFaceIn, .moveFace, .draftFace, .deleteFace, .shellRemoveFace:
            return faceOperation(step, run: &run)
        // Edges
        case .filletEdges, .chamferEdges:
            return blend(step, run: &run)
        // Sketch profile
        case .extrudeProfile, .cutProfile:
            return profileOperation(step, run: &run)
        // Bodies
        case .shellBody, .mirrorBody, .linearPattern, .circularPattern, .moveBody, .rotateBody,
             .scaleBody, .duplicateBody, .deleteBody, .hideBody, .showAll,
             .joinBodies, .subtractBodies, .intersectBodies:
            return bodyOperation(step, run: &run)
        case .addBox, .addCylinder, .addSphere:
            return addPrimitive(step, run: &run)
        // Editing
        case .modifyLast:
            return modifyLast(step, run: &run)
        case .repeatLast:
            return repeatLast(run: &run, transcript: transcript)
        case .setVariable:
            return setVoiceVariable(step)
        case .undo:
            guard session.undoStack.canUndo else { return .failure(.message("Nothing to undo.")) }
            undo()
            return .success("Undid the last edit")
        case .redo:
            guard session.undoStack.canRedo else { return .failure(.message("Nothing to redo.")) }
            redo()
            return .success("Redid the edit")
        // View
        case .viewTop: return view("view.top", "Top view")
        case .viewBottom: return view("view.bottom", "Bottom view")
        case .viewFront: return view("view.front", "Front view")
        case .viewBack: return view("view.back", "Back view")
        case .viewLeft: return view("view.left", "Left view")
        case .viewRight: return view("view.right", "Right view")
        case .viewIsometric: return view("view.isometric", "Isometric view")
        case .fitView:
            fitView()
            return .success("Fitted the view")
        // Inspect / output
        case .measureThickness, .measureArea, .measureVolume, .measureSize, .printCheck:
            return measure(step, run: run)
        case .exportSTL, .export3MF:
            return export(step)
        case .notUnderstood:
            return .failure(.message("Jev didn't understand “\(step.text)”. Try naming the operation, e.g. “drill a hole” or “fillet the top edges”."))
        }
    }

    private func view(_ command: String, _ name: String) -> Result<String, VoiceApplyError> {
        runCommand(command) ? .success(name) : .failure(.message("Couldn't change the view."))
    }

    // MARK: - Targets

    /// The body a step acts on.
    private func targetBody(_ step: VoiceStep, run: VoiceRun) -> BodyID? {
        switch step.target {
        case .previousResult:
            return run.lastBody ?? run.pick.bodyID ?? onlyVisibleBody
        default:
            return run.pick.bodyID ?? run.lastBody ?? onlyVisibleBody
        }
    }

    private var visibleBodies: [Body] { session.document.bodies.filter { !$0.isHidden } }

    private var onlyVisibleBody: BodyID? {
        let bodies = visibleBodies
        return bodies.count == 1 ? bodies[0].id : nil
    }

    private func requireBody(_ step: VoiceStep, run: VoiceRun) -> Result<Body, VoiceApplyError> {
        guard let id = targetBody(step, run: run) else {
            return .failure(.message("Which part? Click it first."))
        }
        guard let body = session.document.body(with: id) else {
            return .failure(.message("That part no longer exists."))
        }
        return .success(body)
    }

    private func topology(_ body: Body) -> Result<VoiceTopology, VoiceApplyError> {
        VoiceAgent.topology(of: body.id, on: self).mapError { error in
            error.message.contains("mesh") || error.message.contains("brep")
                ? .message("This part isn't parametric (it wasn't sketched/extruded here), so voice can't edit its faces or edges.")
                : error
        }
    }

    /// The face a step acts on (kernel face, re-found on the current body).
    private func targetFace(_ step: VoiceStep, run: VoiceRun, in topo: VoiceTopology) -> Result<VoiceKernelFace, VoiceApplyError> {
        let named: SIMD3<Double>?
        switch step.target {
        case .topFace: named = SIMD3(0, 1, 0)
        case .bottomFace: named = SIMD3(0, -1, 0)
        case .frontFace: named = SIMD3(0, 0, 1)
        case .backFace: named = SIMD3(0, 0, -1)
        case .leftFace: named = SIMD3(-1, 0, 0)
        case .rightFace: named = SIMD3(1, 0, 0)
        default: named = nil
        }
        if let named {
            guard let face = topo.extremeFace(along: named) else {
                return .failure(.message("This part has no flat \(step.target.rawValue.replacingOccurrences(of: "_", with: " ")).") )
            }
            return .success(face)
        }
        if let picked = run.pick.face, picked.bodyID == topo.bodyID {
            if let face = topo.face(inPlaneThrough: picked.point, normal: picked.normal)
                ?? topo.face(inPlaneThrough: picked.point, normal: -picked.normal) {
                return .success(face)
            }
            return .failure(.message("The clicked face can't be found on the part any more."))
        }
        // Nothing picked: for a single part, "the face" means its top.
        if let top = topo.extremeFace(along: SIMD3(0, 1, 0)), run.pick.face == nil {
            return .success(top)
        }
        return .failure(.message("Click the face first, then ask again."))
    }

    /// The edges a step acts on.
    private func targetEdges(_ step: VoiceStep, run: VoiceRun, in topo: VoiceTopology) -> Result<[VoiceKernelEdge], VoiceApplyError> {
        var edges: [VoiceKernelEdge]
        switch step.target {
        case .allEdges, .wholeBody:
            edges = topo.edges
        case .topEdges:
            edges = topo.extremeFace(along: SIMD3(0, 1, 0)).map { topo.edges(touching: [$0.index]) } ?? []
        case .bottomEdges:
            edges = topo.extremeFace(along: SIMD3(0, -1, 0)).map { topo.edges(touching: [$0.index]) } ?? []
        case .verticalEdges:
            edges = topo.verticalEdges
        case .holeEdges:
            edges = topo.roundEdges
        case .pickedFaceEdges, .topFace, .bottomFace, .frontFace, .backFace, .leftFace, .rightFace:
            switch targetFace(step, run: run, in: topo) {
            case .success(let face): edges = topo.edges(touching: [face.index])
            case .failure(let error): return .failure(error)
            }
        default:
            if run.pick.edgeBodyID == topo.bodyID, !run.pick.edgeMidpoints.isEmpty {
                edges = topo.edges(nearest: run.pick.edgeMidpoints)
            } else if run.pick.face?.bodyID == topo.bodyID {
                // "Round this" with a face clicked: the face's edges.
                switch targetFace(step, run: run, in: topo) {
                case .success(let face): edges = topo.edges(touching: [face.index])
                case .failure(let error): return .failure(error)
                }
            } else {
                return .failure(.message("Which edges? Click an edge, or say e.g. “the top edges”."))
            }
        }
        guard !edges.isEmpty else { return .failure(.message("No matching edges were found on this part.")) }
        return .success(edges)
    }

    // MARK: - Sketch on a face (hole, corner holes, pocket, boss, pad)

    private func sketchOnFace(_ step: VoiceStep, run: inout VoiceRun) -> Result<String, VoiceApplyError> {
        let body: Body
        switch requireBody(step, run: run) { case .success(let b): body = b; case .failure(let e): return .failure(e) }
        guard let owner = session.document.features.nodes.last(where: { $0.outputBodyIDs.contains(body.id) }) else {
            return .failure(.message("This part isn't parametric (it wasn't sketched/extruded here), so voice can't cut or add to it."))
        }
        let topo: VoiceTopology
        switch topology(body) { case .success(let t): topo = t; case .failure(let e): return .failure(e) }
        let face: VoiceKernelFace
        switch targetFace(step, run: run, in: topo) { case .success(let f): face = f; case .failure(let e): return .failure(e) }
        guard face.kind == .planar else { return .failure(.message("That face is curved; pick a flat face.")) }

        let plane = VoiceGeometry.plane(origin: face.centroid, normal: face.normal)
        let bounds = VoiceGeometry.outlineBounds(of: body, on: plane)

        // Where on the face: centre, the clicked point, or the corners.
        var centre = SIMD2<Double>.zero
        if step.placement == .clickedPoint {
            guard let point = run.pick.clickPoint, run.pick.face?.bodyID == body.id else {
                return .failure(.message("Click the exact spot on the face first, then say “here”."))
            }
            centre = plane.toLocal(point)
        }

        var entities: [SketchEntity] = []
        var summary: String
        var cut: Bool
        var depth: Double?   // nil = through all (cuts only)
        var height = 0.0     // additions
        switch step.action {
        case .hole, .cornerHoles:
            let spec: HoleSpec
            switch VoiceRecipe.hole(from: step) { case .success(let s): spec = s; case .failure(let e): return .failure(.message(e.errorDescription ?? "")) }
            cut = true
            depth = spec.depth
            if step.action == .cornerHoles || step.placement == .corners {
                guard let bounds else { return .failure(.message("Couldn't find the corners of that face.")) }
                let inset = step.number(.distance, .spacing)?.value ?? max(5, spec.diameter)
                let corners = VoiceGeometry.corners(of: bounds, inset: inset)
                guard !corners.isEmpty else { return .failure(.message("The face is too small for corner holes \(SpokenNumber.format(inset)) mm in from the edges.")) }
                entities = corners.map { .circle(id: UUID(), center: $0, radius: spec.diameter / 2) }
                summary = "\(corners.count) × " + VoiceRecipe.summary(spec)
            } else {
                entities = [.circle(id: UUID(), center: centre, radius: spec.diameter / 2)]
                summary = VoiceRecipe.summary(spec)
            }
        case .pocket:
            guard let size = VoiceRecipe.rectangle(from: step) else {
                return .failure(.message("How big? Say e.g. “a 20 by 10 pocket, 2 mm deep”."))
            }
            cut = true
            depth = step.number(.depth)?.value
            if depth == nil, step.depth != .throughAll {
                return .failure(.message("How deep? Say e.g. “2 mm deep”, or “through”."))
            }
            entities = [.rect(id: UUID(), min: centre - size / 2, max: centre + size / 2)]
            summary = "\(SpokenNumber.format(size.x)) × \(SpokenNumber.format(size.y)) mm pocket, " +
                (depth.map { "\(SpokenNumber.format($0)) mm deep" } ?? "through")
        case .boss:
            let diameter = step.number(.diameter)?.value ?? step.number(.radius).map { $0.value * 2 } ?? 5
            height = step.number(.height, .length, .distance, .depth, .thickness)?.value ?? 5
            cut = false
            entities = [.circle(id: UUID(), center: centre, radius: diameter / 2)]
            summary = "Ø\(SpokenNumber.format(diameter)) mm post, \(SpokenNumber.format(height)) mm tall"
        default: // .pad
            guard let size = VoiceRecipe.rectangle(from: step) else {
                return .failure(.message("How big? Say e.g. “a 20 by 10 pad, 3 mm tall”."))
            }
            height = step.number(.height, .depth, .thickness)?.value ?? 5
            cut = false
            entities = [.rect(id: UUID(), min: centre - size / 2, max: centre + size / 2)]
            summary = "\(SpokenNumber.format(size.x)) × \(SpokenNumber.format(size.y)) × \(SpokenNumber.format(height)) mm pad"
        }

        let sketch = Sketch(name: "Voice \(step.action.title) Sketch", plane: plane, entities: entities, isHidden: true)
        let profiles = ProfileDetector.detectProfiles(in: sketch).filter { profile in
            // Only the drawn shapes themselves, never regions between them.
            profile.sourceEntityIDs.count == 1
        }
        guard let first = profiles.first else {
            return .failure(.message("Couldn't build that shape on the face."))
        }
        func ref(_ p: Profile) -> ProfileRef {
            ProfileRef(sketchID: sketch.id, entityIDs: Array(p.sourceEntityIDs), holeEntityIDs: [],
                       seedPoint: VoiceRecipe.centroid(of: p.loop))
        }

        let distance: Double
        if cut {
            if let depth {
                distance = -depth
            } else {
                guard let through = ExtrudeEndKit.resolve(.throughAll, plane: plane, seed: VoiceRecipe.centroid(of: first.loop),
                                                          direction: -face.normal, symmetric: false, bodies: [body]) else {
                    return .failure(.message("Couldn't find material behind that face to cut into."))
                }
                distance = -through
            }
        } else {
            distance = height
        }
        let node = FeatureNode(
            name: "Voice \(step.action.title)",
            kind: .extrude(
                profile: ref(first), plane: PlaneRef(source: .sketch(sketch.id)),
                distance: Expr(value: distance), symmetric: false,
                boolean: BooleanIntent(op: cut ? .subtract : .union,
                                       resolvedTargets: [BodyRef(producer: owner.id, bodyID: body.id)]),
                extraProfiles: profiles.dropFirst().map(ref)),
            outputBodyIDs: [body.id])

        let volumeBefore = MeasureKit.volume(of: body)
        session.addSketchAndRecord(sketch, nodes: [node], title: node.name)
        if let error = session.lastEvalErrors[node.id] {
            session.undo()
            return .failure(.message("Couldn't make the \(step.action.title.lowercased()): \(Self.describe(error))"))
        }
        let volumeAfter = session.document.body(with: body.id).map(MeasureKit.volume) ?? volumeBefore
        if abs(volumeAfter - volumeBefore) < 1e-6 {
            session.undo()
            return .failure(.message("That \(step.action.title.lowercased()) didn't change the part, so it was undone."))
        }
        run.lastBody = body.id
        run.lastFeatureID = node.id
        return .success(summary)
    }

    // MARK: - Face operations

    private func faceOperation(_ step: VoiceStep, run: inout VoiceRun) -> Result<String, VoiceApplyError> {
        let body: Body
        switch requireBody(step, run: run) { case .success(let b): body = b; case .failure(let e): return .failure(e) }
        let topo: VoiceTopology
        switch topology(body) { case .success(let t): topo = t; case .failure(let e): return .failure(e) }
        let face: VoiceKernelFace
        switch targetFace(step, run: run, in: topo) { case .success(let f): face = f; case .failure(let e): return .failure(e) }

        let amount = step.number(.distance, .height, .length, .thickness, .depth, .width, .other)?.value
        let op: AgentExecOp
        let summary: String
        switch step.action {
        case .extrudeFaceOut, .cutFaceIn:
            guard let amount else { return .failure(.message("How far? Say e.g. “pull it out 5 mm”.")) }
            let inward = step.action == .cutFaceIn || step.direction == .inward
            op = .pushPull(body: body.id, face: face.index, distance: inward ? -amount : amount, radial: false)
            summary = "\(inward ? "Pushed" : "Pulled") the face \(SpokenNumber.format(amount)) mm \(inward ? "in" : "out")"
        case .moveFace:
            guard let amount else { return .failure(.message("How far? Say e.g. “move this face 3 mm out”.")) }
            let inward = step.direction == .inward || step.direction == .down && face.normal.y > 0.9
            op = .moveFace(body: body.id, face: face.index, delta: SIMD3(0, 0, inward ? -amount : amount))
            summary = "Moved the face \(SpokenNumber.format(amount)) mm \(inward ? "in" : "out")"
        case .draftFace:
            guard let angle = step.number(.angle)?.value ?? step.numbers.first(where: { $0.number.unit == .degree })?.number.value else {
                return .failure(.message("What angle? Say e.g. “2 degrees of draft”."))
            }
            guard abs(face.normal.y) < 0.9 else { return .failure(.message("Draft applies to side faces, not the top or bottom.")) }
            let bottom = topo.extremeFace(along: SIMD3(0, -1, 0))?.centroid.y ?? face.centroid.y
            op = .draftFace(body: body.id, face: face.index,
                            neutralOrigin: SIMD3(face.centroid.x, bottom, face.centroid.z),
                            neutralNormal: SIMD3(0, 1, 0), angleDegrees: angle)
            summary = "\(SpokenNumber.format(angle))° draft"
        case .deleteFace:
            op = .deleteFace(body: body.id, faces: [face.index])
            summary = "Deleted the face"
        default: // .shellRemoveFace
            let thickness = step.number(.thickness, .distance, .other, .width)?.value ?? 1.2
            op = .shell(body: body.id, thickness: thickness, openFaces: [face.index])
            summary = "Shelled with \(SpokenNumber.format(thickness)) mm walls, open face"
        }
        return runOp(op, step: step, body: body.id, summary: summary, run: &run)
    }

    // MARK: - Fillet / chamfer

    private func blend(_ step: VoiceStep, run: inout VoiceRun) -> Result<String, VoiceApplyError> {
        let bodyID = run.pick.edgeBodyID ?? targetBody(step, run: run)
        guard let bodyID, let body = session.document.body(with: bodyID) else {
            return .failure(.message("Which part? Click an edge or the part first."))
        }
        let topo: VoiceTopology
        switch topology(body) { case .success(let t): topo = t; case .failure(let e): return .failure(e) }
        let edges: [VoiceKernelEdge]
        switch targetEdges(step, run: run, in: topo) { case .success(let e): edges = e; case .failure(let e): return .failure(e) }
        let isFillet = step.action == .filletEdges
        let amount = step.number(.radius, .distance, .width, .thickness, .other, .length)?.value
            ?? step.number(.diameter).map { $0.value / 2 } ?? 1
        let noun = edges.count == 1 ? "edge" : "\(edges.count) edges"
        return runOp(.blend(body: body.id, isFillet: isFillet, amount: amount, edges: edges.map(\.index)),
                     step: step, body: body.id,
                     summary: "\(SpokenNumber.format(amount)) mm \(isFillet ? "fillet" : "chamfer") on \(noun)", run: &run)
    }

    // MARK: - Sketch profile

    private func profileOperation(_ step: VoiceStep, run: inout VoiceRun) -> Result<String, VoiceApplyError> {
        guard let profile = run.pick.profile else {
            return .failure(.message("Click the sketch shape first, then say what to do with it."))
        }
        let amount = step.number(.distance, .height, .length, .depth, .thickness, .other)?.value
        if step.action == .extrudeProfile {
            guard let amount else { return .failure(.message("How far? Say e.g. “extrude it 10 mm”.")) }
            let signed = step.direction == .down || step.direction == .inward ? -amount : amount
            return runOp(.extrude(sketch: profile.sketchID, seed: profile.seed, distance: signed, symmetric: false,
                                  taperDegrees: 0, boolean: .newBody, targets: [], end: nil),
                         step: step, body: nil, summary: "Extruded \(SpokenNumber.format(amount)) mm", run: &run)
        }
        let targets = visibleBodies.map(\.id)
        guard !targets.isEmpty else { return .failure(.message("There's nothing to cut into.")) }
        var lastError = VoiceApplyError.message("The cut didn't reach any material.")
        for sign in [1.0, -1.0] {
            let op: AgentExecOp = amount.map {
                .extrude(sketch: profile.sketchID, seed: profile.seed, distance: sign * $0, symmetric: false,
                         taperDegrees: 0, boolean: .subtract, targets: targets, end: nil)
            } ?? .extrude(sketch: profile.sketchID, seed: profile.seed, distance: sign, symmetric: false,
                          taperDegrees: 0, boolean: .subtract, targets: targets, end: .throughAll)
            switch runOp(op, step: step, body: nil,
                         summary: amount.map { "Cut \(SpokenNumber.format($0)) mm deep" } ?? "Cut through", run: &run) {
            case .success(let message): return .success(message)
            case .failure(let error): lastError = error
            }
        }
        return .failure(lastError)
    }

    // MARK: - Whole parts

    private func bodyOperation(_ step: VoiceStep, run: inout VoiceRun) -> Result<String, VoiceApplyError> {
        switch step.action {
        case .showAll:
            let hidden = session.document.bodies.filter(\.isHidden)
            guard !hidden.isEmpty else { return .success("Nothing was hidden") }
            for body in hidden { setItemHidden(.body(body.id), hidden: false) }
            return .success("Showed \(hidden.count) hidden part\(hidden.count == 1 ? "" : "s")")
        case .joinBodies, .subtractBodies, .intersectBodies:
            return combine(step, run: &run)
        default:
            break
        }
        let body: Body
        switch requireBody(step, run: run) { case .success(let b): body = b; case .failure(let e): return .failure(e) }
        let box = MeasureKit.boundingBox(bodies: [body])
        let centre = box.map { ($0.min + $0.max) / 2 } ?? .zero
        let size = box.map { $0.max - $0.min } ?? .zero

        switch step.action {
        case .shellBody:
            let thickness = step.number(.thickness, .distance, .other, .width)?.value ?? 1.2
            return runOp(.shell(body: body.id, thickness: thickness, openFaces: []), step: step, body: body.id,
                         summary: "Hollowed with \(SpokenNumber.format(thickness)) mm walls", run: &run)
        case .mirrorBody:
            let plane: SketchPlane
            if step.axis == .pickedFace || (step.axis == .notApplicable && run.pick.face != nil) {
                guard let face = run.pick.face else { return .failure(.message("Click the face to mirror across.")) }
                plane = VoiceGeometry.plane(origin: face.point, normal: face.normal)
            } else {
                plane = VoiceGeometry.plane(origin: .zero, normal: step.axis.vector ?? SIMD3(1, 0, 0))
            }
            return runOp(.mirror(body: body.id, plane: plane, keepOriginal: true), step: step, body: body.id,
                         summary: "Mirrored", run: &run)
        case .linearPattern, .duplicateBody:
            let axis = direction(step, default: SIMD3(1, 0, 0))
            let extent = abs(simd_dot(size, simd_abs(axis)))
            let spacing = step.number(.spacing, .distance, .length)?.value ?? extent + 5
            var count = 2
            if step.action == .linearPattern {
                let said = step.number(.count).map { Int($0.value.rounded()) } ?? 3
                count = step.text.lowercased().contains("cop") ? said + 1 : said
            }
            guard count >= 2 else { return .failure(.message("A pattern needs at least 2.")) }
            let spec = PatternSpec(kind: .linear, axis: axis, center: .zero, count: count, spacing: spacing)
            return runOp(.pattern(body: body.id, spec: spec), step: step, body: body.id,
                         summary: step.action == .duplicateBody
                            ? "Duplicated \(SpokenNumber.format(spacing)) mm over"
                            : "\(count) in a row, \(SpokenNumber.format(spacing)) mm apart", run: &run)
        case .circularPattern:
            let said = step.number(.count).map { Int($0.value.rounded()) } ?? 6
            let count = step.text.lowercased().contains("cop") ? said + 1 : said
            guard count >= 2 else { return .failure(.message("A pattern needs at least 2.")) }
            let angle = step.number(.angle)?.value ?? 360
            let spec = PatternSpec(kind: .circular, axis: step.axis.vector ?? SIMD3(0, 1, 0), center: .zero,
                                   count: count, spacing: 0, totalAngle: angle * .pi / 180)
            return runOp(.pattern(body: body.id, spec: spec), step: step, body: body.id,
                         summary: "\(count) around the centre", run: &run)
        case .moveBody:
            guard let distance = step.number(.distance, .length, .height, .width, .other)?.value else {
                return .failure(.message("How far? Say e.g. “move it up 10 mm”."))
            }
            var delta = Transform3D.identity
            delta.translation = direction(step, default: SIMD3(1, 0, 0)) * distance
            return runOp(.transform(body: body.id, delta: delta), step: step, body: body.id,
                         summary: "Moved \(SpokenNumber.format(distance)) mm", run: &run)
        case .rotateBody:
            let degrees = step.number(.angle)?.value ?? step.numbers.first(where: { $0.number.unit == .degree })?.number.value ?? 90
            let axis = step.axis.vector ?? SIMD3(0, 1, 0)
            var delta = Transform3D.identity
            delta.rotation = simd_quatd(angle: degrees * .pi / 180, axis: axis)
            delta.translation = centre - delta.rotation.act(centre)
            return runOp(.transform(body: body.id, delta: delta), step: step, body: body.id,
                         summary: "Rotated \(SpokenNumber.format(degrees))°", run: &run)
        case .scaleBody:
            guard let factor = VoiceRecipe.scaleFactor(from: step) else {
                return .failure(.message("By how much? Say e.g. “scale it to 150%” or “twice as big”."))
            }
            var delta = Transform3D.identity
            delta.scale = factor
            delta.translation = centre - centre * factor
            return runOp(.transform(body: body.id, delta: delta), step: step, body: body.id,
                         summary: "Scaled to \(SpokenNumber.format((factor * 1000).rounded() / 10))%", run: &run)
        case .deleteBody:
            deleteItem(.body(body.id))
            return .success("Deleted \(body.name)")
        case .hideBody:
            setItemHidden(.body(body.id), hidden: true)
            return .success("Hid \(body.name)")
        default:
            return .failure(.message("Voice can't do “\(step.action.title)” yet."))
        }
    }

    /// Direction for a move/pattern: the stated direction, else the axis.
    private func direction(_ step: VoiceStep, default fallback: SIMD3<Double>) -> SIMD3<Double> {
        step.direction.vector ?? step.axis.vector ?? fallback
    }

    private func combine(_ step: VoiceStep, run: inout VoiceRun) -> Result<String, VoiceApplyError> {
        var ids = run.pick.bodies.count >= 2 ? run.pick.bodies : visibleBodies.map(\.id)
        guard ids.count >= 2 else { return .failure(.message("Select two or more parts (Shift-click) first.")) }
        let kind: String
        switch step.action {
        case .joinBodies: kind = "union"
        case .subtractBodies:
            kind = "subtract"
            // Keep the biggest part; cut the others out of it.
            ids.sort { a, b in
                let va = session.document.body(with: a).map(MeasureKit.volume) ?? 0
                let vb = session.document.body(with: b).map(MeasureKit.volume) ?? 0
                return va > vb
            }
        default: kind = "intersect"
        }
        let verb = ["union": "Joined", "subtract": "Subtracted", "intersect": "Intersected"][kind] ?? kind
        return runOp(.boolean(kind: kind, target: ids[0], tools: Array(ids.dropFirst())), step: step, body: nil,
                     summary: "\(verb) \(ids.count) parts", run: &run)
    }

    // MARK: - New solids

    private func addPrimitive(_ step: VoiceStep, run: inout VoiceRun) -> Result<String, VoiceApplyError> {
        let spec: PrimitiveSpec
        let summary: String
        switch step.action {
        case .addBox:
            let sizes = step.numbers(.width, .length, .depth, .height, .other, .distance).map(\.value)
            let w = sizes.first ?? 10
            let d = sizes.count > 1 ? sizes[1] : w
            let h = sizes.count > 2 ? sizes[2] : (sizes.count == 2 ? sizes[1] : w)
            spec = .box(width: w, depth: sizes.count == 2 ? w : d, height: h)
            summary = "Added a \(SpokenNumber.format(w)) × \(SpokenNumber.format(sizes.count == 2 ? w : d)) × \(SpokenNumber.format(h)) mm box"
        case .addCylinder:
            let diameter = step.number(.diameter)?.value ?? step.number(.radius).map { $0.value * 2 } ?? 10
            let height = step.number(.height, .length, .depth, .thickness)?.value ?? 10
            spec = .cylinder(radius: diameter / 2, height: height)
            summary = "Added a Ø\(SpokenNumber.format(diameter)) × \(SpokenNumber.format(height)) mm cylinder"
        default:
            let diameter = step.number(.diameter)?.value ?? step.number(.radius).map { $0.value * 2 } ?? 10
            spec = .sphere(radius: diameter / 2)
            summary = "Added a Ø\(SpokenNumber.format(diameter)) mm sphere"
        }
        var placement = Transform3D.identity
        // On the clicked face, if any (primitives start at y = 0).
        if let face = run.pick.face, face.normal.y > 0.9 {
            placement.translation = face.point
        }
        let id = BodyID()
        let node = FeatureNode(name: step.action.title.replacingOccurrences(of: "Add ", with: ""),
                               kind: .primitive(spec: spec, placement: placement), outputBodyIDs: [id])
        session.recordAndRebuild([node], title: "Voice \(node.name)")
        if let error = session.lastEvalErrors[node.id] {
            session.undo()
            return .failure(.message("Couldn't add it: \(Self.describe(error))"))
        }
        run.lastBody = id
        run.lastFeatureID = node.id
        return .success(summary)
    }

    // MARK: - Editing what exists

    private func modifyLast(_ step: VoiceStep, run: inout VoiceRun) -> Result<String, VoiceApplyError> {
        let nodes = session.document.features.nodes
        guard let node = run.lastFeatureID.flatMap({ id in nodes.first { $0.id == id } }) ?? nodes.last else {
            return .failure(.message("There's nothing to change yet."))
        }
        let said = step.numbers.first?.number.value
        let wantsDepth = step.number(.depth, .distance, .height, .length, .thickness) != nil
            || step.text.lowercased().contains("deep") || step.text.lowercased().contains("tall")

        // A voice hole/boss: its size lives on the sketch circle.
        if case let .extrude(profile, _, _, _, _, _) = node.kind, !wantsDepth,
           let sketch = session.document.sketches.first(where: { $0.id == profile.sketchID }),
           sketch.entities.count >= 1,
           sketch.entities.allSatisfy({ if case .circle = $0 { return true }; return false }) {
            let isRadius = step.number(.radius) != nil
            var updates: [(SketchEntity, SketchEntity)] = []
            var newDiameter = 0.0
            for entity in sketch.entities {
                guard case let .circle(id, centre, radius) = entity else { continue }
                let value = isRadius ? said.map { $0 * 2 } : said
                guard let d = VoiceRecipe.change(radius * 2, by: step.relative, value: value) else {
                    return .failure(.message("Change it to what? Say e.g. “make it 6”."))
                }
                guard d > 0 else { return .failure(.message("The size has to stay above 0 mm.")) }
                newDiameter = d
                updates.append((entity, .circle(id: id, center: centre, radius: d / 2)))
            }
            session.performWithSketchRebuild(
                UpdateSketchEntitiesCommand(sketchID: sketch.id, before: updates.map(\.0), after: updates.map(\.1)),
                sketchID: sketch.id)
            if let error = session.lastEvalErrors[node.id] {
                session.undo()
                return .failure(.message("Couldn't resize it: \(Self.describe(error))"))
            }
            run.lastFeatureID = node.id
            run.lastBody = node.outputBodyIDs.first
            return .success("Diameter is now \(SpokenNumber.format((newDiameter * 100).rounded() / 100)) mm")
        }

        // Otherwise the feature's main number.
        guard let (current, rebuild, noun) = VoiceRecipe.mainValue(of: node.kind) else {
            return .failure(.message("Voice can't resize a “\(node.name)” yet."))
        }
        guard let newValue = VoiceRecipe.change(abs(current), by: step.relative, value: said) else {
            return .failure(.message("Change it to what? Say e.g. “make it 6”."))
        }
        guard newValue > 0 else { return .failure(.message("The value has to stay above 0.")) }
        let signed = current < 0 ? -newValue : newValue
        session.editFeature(node.id, to: rebuild(Expr(value: signed)))
        if let error = session.lastEvalErrors[node.id] {
            session.undo()
            return .failure(.message("Couldn't change it: \(Self.describe(error))"))
        }
        run.lastFeatureID = node.id
        run.lastBody = node.outputBodyIDs.first
        return .success("\(noun.capitalized) is now \(SpokenNumber.format((newValue * 100).rounded() / 100)) mm")
    }

    private func repeatLast(run: inout VoiceRun, transcript: String) -> Result<String, VoiceApplyError> {
        guard let steps = lastVoiceSteps, !steps.isEmpty else {
            return .failure(.message("There's no earlier voice command to repeat."))
        }
        var messages: [String] = []
        for step in steps {
            switch perform(step, run: &run, transcript: transcript) {
            case .success(let m): messages.append(m)
            case .failure(let e): return .failure(e)
            }
        }
        return .success("Again: " + messages.joined(separator: ", "))
    }

    private func setVoiceVariable(_ step: VoiceStep) -> Result<String, VoiceApplyError> {
        let variables = session.document.variables
        guard !variables.isEmpty else {
            return .failure(.message("There are no variables yet. Add one in the Variables panel (f(x)) first."))
        }
        guard let name = step.variable, let variable = variables.first(where: { $0.name == name }) else {
            return .failure(.message("Which variable? You have: \(variables.map(\.name).joined(separator: ", "))."))
        }
        guard let value = step.numbers.first?.number.value else {
            return .failure(.message("To what value? Say e.g. “set \(name) to 2”."))
        }
        setVariable(variable.id, name: variable.name, expression: SpokenNumber.format(value))
        return .success("\(name) = \(SpokenNumber.format(value))")
    }

    // MARK: - Inspect / export

    private func measure(_ step: VoiceStep, run: VoiceRun) -> Result<String, VoiceApplyError> {
        if step.action == .printCheck {
            return .success(VoiceRecipe.printCheck(bodies: visibleBodies))
        }
        let body: Body
        switch requireBody(step, run: run) { case .success(let b): body = b; case .failure(let e): return .failure(e) }
        switch step.action {
        case .measureThickness:
            let normal = run.pick.face?.normal ?? SIMD3(0, 1, 0)
            let t = VoiceGeometry.extent(of: body, along: normal)
            return .success("Thickness: \(VoiceRecipe.mm(t))")
        case .measureArea:
            if let face = run.pick.face, case .success(let topo) = topology(body),
               let kernel = topo.face(inPlaneThrough: face.point, normal: face.normal)
                    ?? topo.face(inPlaneThrough: face.point, normal: -face.normal) {
                return .success("Face area: \(VoiceRecipe.number(kernel.area)) mm²")
            }
            return .success("Surface area: \(VoiceRecipe.number(MeasureKit.surfaceArea(body.render, scale: body.transform.scale))) mm²")
        case .measureVolume:
            let v = MeasureKit.volume(of: body)
            return .success("Volume: \(VoiceRecipe.number(v)) mm³ (≈ \(VoiceRecipe.number(v / 1000 * 1.24)) g of PLA)")
        default: // size
            guard let box = MeasureKit.boundingBox(bodies: [body]) else { return .failure(.message("That part is empty.")) }
            let s = box.max - box.min
            return .success("Size: \(VoiceRecipe.number(s.x)) wide × \(VoiceRecipe.number(s.z)) deep × \(VoiceRecipe.number(s.y)) tall mm")
        }
    }

    private func export(_ step: VoiceStep) -> Result<String, VoiceApplyError> {
        let is3MF = step.action == .export3MF
        guard let data = is3MF ? exportThreeMF() : exportSTL() else {
            return .failure(.message("There's nothing to export."))
        }
        let (url, error) = AgentExportFolder.save(data, requestedName: session.project.name,
                                                  format: is3MF ? .threeMF : .stl)
        guard let url else { return .failure(.message(error ?? "The file couldn't be saved.")) }
        return .success("Saved \(url.lastPathComponent) to Downloads")
    }

    // MARK: - Helpers

    /// Run an agent op and record what it touched.
    private func runOp(_ op: AgentExecOp, step: VoiceStep, body: BodyID?, summary: String,
                       run: inout VoiceRun) -> Result<String, VoiceApplyError> {
        switch VoiceAgent.run(op, on: self) {
        case .success(let result):
            run.lastBody = result.producedBodyIDs.last ?? result.changedBodyIDs.first ?? body
            if let id = result.featureID.flatMap(UUID.init(uuidString:)) {
                run.lastFeatureID = session.document.features.nodes.first { $0.id.raw == id }?.id
            }
            return .success(summary)
        case .failure(let error):
            return .failure(error)
        }
    }

    static func describe(_ error: FeatureError) -> String {
        switch error {
        case .brokenRef(let what): return "a reference was lost (\(what))."
        case .emptyGeometry: return "the result was empty."
        case .kernelFailure(let why): return why
        }
    }
}

struct VoiceApplyError: Error, Equatable {
    let message: String
    static func message(_ text: String) -> VoiceApplyError { VoiceApplyError(message: text) }
}
