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

    /// Enter in the voice panel. V1.1 only records what would be sent to the
    /// intent classifier; V1.2 sends it to Jev and V1.3 applies the edit.
    @discardableResult
    func submitVoice() -> VoiceRequest? {
        voice.submit(target: voiceTarget)
    }
}
