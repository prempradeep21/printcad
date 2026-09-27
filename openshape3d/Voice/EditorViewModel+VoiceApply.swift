//
//  EditorViewModel+VoiceApply.swift
//  openshape3d
//
//  PrintCAD V1.3: carry out Jev's decision. The face is captured the moment
//  Enter is pressed (a click during the ~0.5 s wait must not move the hole).
//  A hole is a hidden circle sketch on the face + a subtract extrude into the
//  body, recorded as ONE undo step and replayed through OCCT like a hand-made
//  cut. On any kernel failure the step is undone and the reason shown — the
//  last valid model is kept (CLAUDE.md rule 9).
//

import Foundation
import simd

/// The picked face at the moment Enter was pressed.
struct VoiceFaceSnapshot: Equatable {
    let bodyID: BodyID
    /// World plane of the face (origin on the face, normal off it).
    let plane: SketchPlane
    /// Face outline in `plane` coordinates.
    let loop: [SIMD2<Double>]
}

extension EditorViewModel {
    /// The face under the current pick, if any.
    var currentVoiceFace: VoiceFaceSnapshot? {
        guard let context = toolContext else { return nil }
        switch mode {
        case .faceSelected(let id):
            return VoiceFaceSnapshot(bodyID: id, plane: context.plane, loop: context.profile.loop)
        case .extruding:
            guard let id = context.sourceBody else { return nil }
            return VoiceFaceSnapshot(bodyID: id, plane: context.plane, loop: context.profile.loop)
        default:
            return nil
        }
    }

    /// Carry out a decision; reports the outcome back to the panel.
    func applyVoiceDecision(_ request: VoiceRequest, _ decision: VoiceDecision) {
        let result: Result<String, VoiceApplyError>
        switch decision.action {
        case .hole:
            result = applyVoiceHole(request, decision)
        case .undo:
            if session.undoStack.canUndo { undo(); result = .success("Undid the last edit") }
            else { result = .failure(.message("Nothing to undo.")) }
        case .redo:
            if session.undoStack.canRedo { redo(); result = .success("Redid the edit") }
            else { result = .failure(.message("Nothing to redo.")) }
        case .viewTop:
            result = runCommand("view.top") ? .success("Top view") : .failure(.message("Couldn't change the view."))
        case .viewFront:
            result = runCommand("view.front") ? .success("Front view") : .failure(.message("Couldn't change the view."))
        case .viewIsometric:
            result = runCommand("view.isometric") ? .success("Isometric view") : .failure(.message("Couldn't change the view."))
        case .fitView:
            fitView()
            result = .success("Fitted the view")
        case .notUnderstood:
            result = .failure(.message("Jev didn't understand that. Try naming the operation, e.g. “drill a hole”."))
        default:
            result = .failure(.message("Jev chose “\(decision.action.title)”. Voice can't do that one yet — it's coming in a later step."))
        }
        switch result {
        case .success(let message): voice.reportApplied(ok: true, message: message)
        case .failure(let error): voice.reportApplied(ok: false, message: error.message)
        }
    }

    // MARK: - Hole

    private func applyVoiceHole(_ request: VoiceRequest, _ decision: VoiceDecision) -> Result<String, VoiceApplyError> {
        guard case .face = request.target, let face = voiceFace else {
            return .failure(.message("Click the face the hole goes in, then ask again."))
        }
        guard decision.placement != .clickedPoint else {
            return .failure(.message("Holes at the exact clicked point aren't supported yet — say “in the centre”."))
        }
        let spec: HoleSpec
        switch VoiceRecipe.hole(from: decision) {
        case .success(let s): spec = s
        case .failure(let failure): return .failure(.message(failure.errorDescription ?? "Can't size that hole."))
        }
        guard let body = session.document.body(with: face.bodyID) else {
            return .failure(.message("That body no longer exists."))
        }
        guard let owner = session.document.features.nodes.last(where: { $0.outputBodyIDs.contains(face.bodyID) }) else {
            return .failure(.message("This body isn't parametric (it wasn't sketched/extruded here), so a hole can't be cut by voice."))
        }

        let centre = VoiceRecipe.centroid(of: face.loop)
        let sketch = Sketch(
            name: "Voice Hole Sketch", plane: face.plane,
            entities: [.circle(id: UUID(), center: centre, radius: spec.diameter / 2)],
            isHidden: true)   // consumed by the cut, like any extruded sketch
        guard let outer = ProfileDetector.profiles(at: centre, in: sketch).first else {
            return .failure(.message("Couldn't build the hole's circle on that face."))
        }

        // Which way is "into the body"? The face plane's normal may point
        // either way, so ask Through All both ways and keep the one that hits.
        let normal = simd_normalize(face.plane.normal)
        var inward: (direction: Double, throughDistance: Double)?
        for sign in [-1.0, 1.0] {
            if let d = ExtrudeEndKit.resolve(.throughAll, plane: face.plane, seed: centre,
                                             direction: normal * sign, symmetric: false,
                                             bodies: [body]) {
                inward = (sign, d)
                break
            }
        }
        guard let inward else {
            return .failure(.message("Couldn't find material behind that face to cut into."))
        }
        let distance = inward.direction * (spec.depth ?? inward.throughDistance)

        let profile = ProfileRef(sketchID: sketch.id, entityIDs: Array(outer.sourceEntityIDs),
                                 holeEntityIDs: [], seedPoint: centre)
        let node = FeatureNode(
            name: "Voice Hole",
            kind: .extrude(
                profile: profile, plane: PlaneRef(source: .sketch(sketch.id)),
                distance: Expr(value: distance), symmetric: false,
                boolean: BooleanIntent(op: .subtract,
                                       resolvedTargets: [BodyRef(producer: owner.id, bodyID: face.bodyID)]),
                extraProfiles: []),
            outputBodyIDs: [face.bodyID])

        let volumeBefore = MeasureKit.volume(of: body)
        session.addSketchAndRecord(sketch, nodes: [node], title: "Voice Hole")
        if let error = session.lastEvalErrors[node.id] {
            session.undo()   // keep the last valid model
            return .failure(.message("Couldn't cut the hole: \(Self.describe(error))"))
        }
        if let after = session.document.body(with: face.bodyID),
           MeasureKit.volume(of: after) >= volumeBefore - 1e-6 {
            session.undo()
            return .failure(.message("The cut didn't remove any material, so it was undone."))
        }
        // The face we picked has changed shape; select the body instead.
        toolContext = nil
        selection = [face.bodyID]
        mode = .selected(face.bodyID)
        return .success(VoiceRecipe.summary(spec))
    }

    private static func describe(_ error: FeatureError) -> String {
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
