//
//  EditorViewModel+Voice.swift
//  openshape3d
//
//  PrintCAD V1.1: the editor side of the voice panel — open/close, and turning
//  the current pick into a `VoiceTarget`. The panel is an overlay, so the
//  viewport stays live: the user clicks a face or edge while talking.
//

import Foundation

extension EditorViewModel {
    /// What the user is pointing at right now.
    var voiceTarget: VoiceTarget {
        switch mode {
        case .faceSelected(let id):
            guard let body = session.document.body(with: id), let context = toolContext else {
                return .bodies(count: 1)
            }
            let area = MeasureKit.faceArea(
                body.render, triangles: context.faceTriangles, scale: body.transform.scale
            )
            return .face(areaMM2: area)
        case .extruding:
            // A picked sketch region (the extrude arrow is up) or a face pull.
            guard let context = toolContext else { return .nothing }
            if context.sketchID != nil {
                let holes = context.holes.reduce(0) { $0 + MeasureKit.area(of: $1) }
                return .sketchProfile(areaMM2: MeasureKit.area(of: context.profile) - holes)
            }
            if let id = context.sourceBody, let body = session.document.body(with: id) {
                return .face(areaMM2: MeasureKit.faceArea(
                    body.render, triangles: context.faceTriangles, scale: body.transform.scale))
            }
            return .nothing
        case .pickingBlendEdges:
            return blendSelectedEdges.isEmpty ? .nothing : .edges(count: blendSelectedEdges.count)
        default:
            if !selection.isEmpty { return .bodies(count: selection.count) }
            // Nothing clicked: the face under the pointer (Mac hover).
            return hoveredVoiceFace.map { .face(areaMM2: $0.area) } ?? .nothing
        }
    }

    func openVoice() {
        guard !voiceActive else { return }
        voiceActive = true
        voice.onDecision = { [weak self] request, decision in
            self?.applyVoiceDecision(request, decision)
        }
        Task { await voice.start() }
    }

    func closeVoice() {
        guard voiceActive else { return }
        voice.stop()
        voiceActive = false
    }

    func toggleVoice() {
        voiceActive ? closeVoice() : openVoice()
    }

    /// Enter in the voice panel: freeze the pick, then send the words
    /// + the pick to Jev. A confident answer is applied when it arrives.
    @discardableResult
    func submitVoice() -> VoiceRequest? {
        let pick = currentVoicePick
        guard let request = voice.submit(target: voiceTarget,
                                         variables: session.document.variables.map(\.name)) else { return nil }
        voicePick = pick
        return request
    }
}
