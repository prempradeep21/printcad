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
            return selection.isEmpty ? .nothing : .bodies(count: selection.count)
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

    /// Enter in the voice panel: freeze the picked face, then send the words
    /// + the pick to Jev. A confident answer is applied when it arrives.
    @discardableResult
    func submitVoice() -> VoiceRequest? {
        let target = voiceTarget
        let face = currentVoiceFace
        guard let request = voice.submit(target: target) else { return nil }
        voiceFace = face
        return request
    }
}
