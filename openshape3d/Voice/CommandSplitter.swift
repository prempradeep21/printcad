//
//  CommandSplitter.swift
//  openshape3d
//
//  PrintCAD V1 (multi-step): "drill a 5 mm hole in the centre, then fillet the
//  top edges 1 mm" → two steps. Jev cannot write text, so it cannot split a
//  sentence itself; this pure splitter cuts on sequencing words and on "and"
//  when a new instruction verb follows it. Each step then gets its own set of
//  questions in ONE Jev call (answered in parallel, so no extra latency).
//

import Foundation

enum CommandSplitter {
    /// Words that start an instruction. "and" only splits when one follows,
    /// so "20 by 10 and 2 deep" or "top and bottom edges" stay one step.
    static let instructionVerbs: Set<String> = [
        "drill", "bore", "punch", "cut", "make", "add", "put", "place", "create", "draw",
        "fillet", "round", "chamfer", "bevel", "extrude", "pull", "push", "raise", "lower",
        "thicken", "shell", "hollow", "delete", "remove", "erase", "move", "shift", "rotate",
        "turn", "spin", "mirror", "flip", "copy", "duplicate", "pattern", "array", "repeat",
        "scale", "resize", "hide", "show", "undo", "redo", "export", "save", "set", "change",
        "measure", "check", "zoom", "fit", "view", "sketch", "revolve", "join", "combine",
        "merge", "subtract", "intersect", "offset", "draft", "tilt", "extend", "sink",
    ]

    /// Phrases that always start a new step. ("next" is deliberately absent:
    /// "a hole next to the edge".)
    private static let sequencers = [
        "and then", "and after that", "after that", "afterwards", "and finally", "finally",
        "then", "and also", "also",
    ]

    static func steps(in transcript: String) -> [String] {
        // Hard boundaries first: sentence ends and semicolons.
        let sentences = transcript
            .replacingOccurrences(of: ";", with: ".")
            .components(separatedBy: CharacterSet(charactersIn: ".!?"))
        var steps: [String] = []
        for sentence in sentences {
            steps.append(contentsOf: splitSentence(sentence))
        }
        return steps.map(clean).filter { !$0.isEmpty }
    }

    private static func splitSentence(_ sentence: String) -> [String] {
        // Tokenise keeping the original words (commas become their own token).
        let spaced = sentence.replacingOccurrences(of: ",", with: " , ")
        let words = spaced.split(separator: " ").map(String.init)
        guard !words.isEmpty else { return [] }

        var steps: [[String]] = [[]]
        var i = 0
        while i < words.count {
            // A sequencing phrase starts a new step (never at the very start).
            if let length = sequencerLength(at: i, in: words) {
                if !(steps.last?.filter { $0 != "," }.isEmpty ?? true) { steps.append([]) }
                i += length
                continue
            }
            let lower = words[i].lowercased()
            // ", <verb>" or "and <verb>" starts a new step.
            if lower == "," || lower == "and" {
                let next = i + 1 < words.count ? words[i + 1].lowercased() : ""
                if instructionVerbs.contains(next), !(steps.last?.filter { $0 != "," }.isEmpty ?? true) {
                    steps.append([])
                    i += 1
                    continue
                }
                if lower == "," { i += 1; continue }
            }
            steps[steps.count - 1].append(words[i])
            i += 1
        }
        return steps.map { $0.joined(separator: " ") }
    }

    private static func sequencerLength(at index: Int, in words: [String]) -> Int? {
        let lowered = words.map { $0.lowercased() }
        for phrase in sequencers {
            let parts = phrase.split(separator: " ").map(String.init)
            guard index + parts.count <= lowered.count else { continue }
            if Array(lowered[index..<index + parts.count]) == parts {
                // "then" inside "and then" is handled by the longer phrase first.
                return parts.count
            }
        }
        return nil
    }

    private static func clean(_ step: String) -> String {
        var s = step.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: ",")))
        while s.contains("  ") { s = s.replacingOccurrences(of: "  ", with: " ") }
        return s
    }
}
