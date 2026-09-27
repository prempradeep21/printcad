//
//  VoiceTarget.swift
//  openshape3d
//
//  PrintCAD V1 (voice + point editing): WHAT the user is pointing at while
//  they speak. The mouse gives the context ("this face"), the voice gives the
//  instruction. Pure value type so the chip text and the one-line description
//  sent to the intent classifier (V1.2) are testable without a viewport.
//

import Foundation

enum VoiceTarget: Equatable {
    /// Nothing picked: commands like "undo" or "show from top" still work.
    case nothing
    case bodies(count: Int)
    /// A picked face. `areaMM2` is the world-space area of the face.
    case face(areaMM2: Double)
    /// A closed sketch region picked for extrusion — not solid yet.
    case sketchProfile(areaMM2: Double)
    case edges(count: Int)

    /// Short label for the chip in the voice panel.
    var chipText: String {
        switch self {
        case .nothing:
            return "Nothing selected"
        case .bodies(let count):
            return count == 1 ? "Body" : "\(count) bodies"
        case .face(let area):
            return "Face · \(Self.format(area)) mm²"
        case .sketchProfile(let area):
            return "Sketch profile · \(Self.format(area)) mm²"
        case .edges(let count):
            return count == 1 ? "Edge" : "\(count) edges"
        }
    }

    /// One line describing the selection for the intent classifier. Kept
    /// short on purpose: irrelevant state lowers classifier accuracy.
    var classifierDescription: String {
        switch self {
        case .nothing:
            return "nothing selected"
        case .bodies(let count):
            return count == 1 ? "one solid body" : "\(count) solid bodies"
        case .face(let area):
            return "one face, area \(Self.format(area)) mm²"
        case .sketchProfile(let area):
            return "one closed sketch profile (not a solid yet), area \(Self.format(area)) mm²"
        case .edges(let count):
            return count == 1 ? "one edge" : "\(count) edges"
        }
    }

    private static func format(_ value: Double) -> String {
        let rounded = (value * 10).rounded() / 10
        return rounded == rounded.rounded()
            ? String(Int(rounded))
            : String(format: "%.1f", rounded)
    }
}

/// What pressing Enter produces: the input to the Jev request.
struct VoiceRequest: Equatable {
    let transcript: String
    let target: VoiceTarget
    /// The document's variable names, so "set wall to 2" can name one.
    var variables: [String] = []
}
