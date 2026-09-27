//
//  TranscriptAccumulator.swift
//  openshape3d
//
//  PrintCAD V1: keeps one instruction whole across mic pauses. Listening
//  stops when the recognizer decides an utterance is over (or the user taps
//  the mic); tapping the mic again before Enter ADDS to what was heard rather
//  than replacing it, so "drill a 5 mm hole … in the centre" stays one command.
//

import Foundation

struct TranscriptAccumulator: Equatable {
    /// Text from recognition tasks that have already ended.
    private(set) var committed = ""
    /// The current task's latest revision (replaced, not appended, each time).
    private(set) var partial = ""

    /// Everything heard since the last reset.
    var text: String {
        [committed, partial]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    /// The current task revised its transcript. Returns the full text.
    @discardableResult
    mutating func revise(_ revision: String) -> String {
        partial = revision
        return text
    }

    /// The current task ended; its words become permanent.
    @discardableResult
    mutating func segmentEnded() -> String {
        committed = text
        partial = ""
        return committed
    }

    mutating func reset() {
        committed = ""
        partial = ""
    }
}
