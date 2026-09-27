//
//  JevLiveEvalTests.swift
//  openshape3dTests
//
//  PrintCAD V1 — how well does the REAL Jev map phrases to actions? Opt-in:
//  skipped unless JEV_LIVE=1 (xcodebuild … TEST_RUNNER_JEV_LIVE=1), because it
//  calls the paid API with the Debug key from .env.local. Prints a table and
//  fails only if action accuracy drops below the bar, so a catalog change
//  that confuses Jev shows up as a number, not a feeling.
//

import XCTest
@testable import openshape3d

@MainActor
final class JevLiveEvalTests: XCTestCase {
    struct Case {
        let words: String
        let target: VoiceTarget
        let actions: [VoiceAction]
        var targets: [VoiceTargetChoice?] = []
        var check: ((VoiceDecision) -> String?)? = nil
    }

    private static let face = VoiceTarget.face(areaMM2: 800)
    private static let edge = VoiceTarget.edges(count: 1)
    private static let body = VoiceTarget.bodies(count: 1)
    private static let profile = VoiceTarget.sketchProfile(areaMM2: 800)

    private let cases: [Case] = [
        Case(words: "draw a hole in the center of this surface", target: face, actions: [.hole]),
        Case(words: "drill a 5 mm hole", target: face, actions: [.hole],
             check: { $0.steps[0].number(.diameter)?.value == 5 ? nil : "5 mm not a diameter" }),
        Case(words: "I want a seven MM hole at the cent of this", target: face, actions: [.hole]),
        Case(words: "3 mm hole here 4 mm deep", target: face, actions: [.hole],
             check: { d in
                 let s = d.steps[0]
                 if s.placement != .clickedPoint { return "placement \(s.placement)" }
                 if s.depth != .blind { return "depth \(s.depth)" }
                 return s.number(.depth)?.value == 4 ? nil : "4 mm not depth"
             }),
        Case(words: "M3 holes in all four corners", target: face, actions: [.cornerHoles]),
        Case(words: "cut a 20 by 10 pocket 2 mm deep", target: face, actions: [.pocket]),
        Case(words: "put a 5 mm post on this 8 mm tall", target: face, actions: [.boss]),
        Case(words: "add a 20 by 20 block on top 3 mm tall", target: face, actions: [.pad]),
        Case(words: "pull this face up 5 mm", target: face, actions: [.extrudeFaceOut]),
        Case(words: "push it in 1 mm", target: face, actions: [.cutFaceIn]),
        Case(words: "hollow it out with 2 mm walls", target: face, actions: [.shellRemoveFace]),
        Case(words: "round this edge 2 mm", target: edge, actions: [.filletEdges]),
        Case(words: "chamfer this 1 mm", target: edge, actions: [.chamferEdges]),
        Case(words: "fillet the top edges 1 mm", target: body, actions: [.filletEdges], targets: [.topEdges]),
        Case(words: "round off all the vertical edges", target: body, actions: [.filletEdges], targets: [.verticalEdges]),
        Case(words: "extrude this 10 mm", target: profile, actions: [.extrudeProfile]),
        Case(words: "cut this all the way through", target: profile, actions: [.cutProfile]),
        Case(words: "mirror it on X", target: body, actions: [.mirrorBody],
             check: { $0.steps[0].axis == .x ? nil : "axis \($0.steps[0].axis)" }),
        Case(words: "make 4 copies 15 mm apart", target: body, actions: [.linearPattern]),
        Case(words: "6 copies around the center", target: body, actions: [.circularPattern]),
        Case(words: "move it up 10 mm", target: body, actions: [.moveBody],
             check: { $0.steps[0].direction == .up ? nil : "direction \($0.steps[0].direction)" }),
        Case(words: "rotate it 90 degrees", target: body, actions: [.rotateBody]),
        Case(words: "scale it to 150%", target: body, actions: [.scaleBody]),
        Case(words: "delete this", target: body, actions: [.deleteBody]),
        Case(words: "add a 20 mm cube", target: .nothing, actions: [.addBox]),
        Case(words: "make it 6", target: .nothing, actions: [.modifyLast]),
        Case(words: "2 mm deeper", target: .nothing, actions: [.modifyLast],
             check: { $0.steps[0].relative == .increaseBy ? nil : "relative \($0.steps[0].relative)" }),
        Case(words: "same again here", target: face, actions: [.repeatLast]),
        Case(words: "undo that", target: .nothing, actions: [.undo]),
        Case(words: "show me the top view", target: .nothing, actions: [.viewTop]),
        Case(words: "how thick is this", target: face, actions: [.measureThickness]),
        Case(words: "will this fit on my printer", target: .nothing, actions: [.printCheck]),
        Case(words: "export an STL", target: .nothing, actions: [.exportSTL]),
        Case(words: "drill a 5 mm hole in the centre then fillet the top edges 1 mm", target: face,
             actions: [.hole, .filletEdges], targets: [nil, .topEdges]),
        Case(words: "hollow it out with 2 mm walls, then export STL", target: face,
             actions: [.shellRemoveFace, .exportSTL]),
        Case(words: "add a 10 mm post here and chamfer its top edge 1 mm", target: face,
             actions: [.boss, .chamferEdges]),
    ]

    func testLiveActionAccuracy() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["JEV_LIVE"] == "1",
                          "Live Jev eval is opt-in: TEST_RUNNER_JEV_LIVE=1")
        let classifier = JevVoiceClassifier()
        try XCTSkipIf(classifier.apiKey == nil, "No Jev key in this build")

        var correctSteps = 0, totalSteps = 0, slotMisses = 0
        var latencies: [Double] = []
        var report = ["", "Jev live eval — \(cases.count) phrases"]
        for c in cases {
            do {
                let d = try await classifier.decide(VoiceRequest(transcript: c.words, target: c.target))
                latencies.append(d.latency)
                let got = d.steps.map(\.action)
                var notes: [String] = []
                if got.count != c.actions.count { notes.append("\(got.count) steps, expected \(c.actions.count)") }
                for (i, expected) in c.actions.enumerated() {
                    totalSteps += 1
                    if i < got.count, got[i] == expected { correctSteps += 1 } else {
                        notes.append("step \(i + 1): \(i < got.count ? got[i].rawValue : "—") ≠ \(expected.rawValue)")
                    }
                    if i < c.targets.count, let t = c.targets[i], i < d.steps.count, d.steps[i].target != t {
                        slotMisses += 1
                        notes.append("target \(d.steps[i].target.rawValue) ≠ \(t.rawValue)")
                    }
                }
                if let problem = c.check?(d) { slotMisses += 1; notes.append(problem) }
                let conf = d.steps.map { String(format: "%.2f", $0.confidence) }.joined(separator: "/")
                report.append("\(notes.isEmpty ? "✓" : "✗") \(String(format: "%.2fs", d.latency)) \(conf)  “\(c.words)” → "
                              + got.map(\.rawValue).joined(separator: " + ")
                              + (notes.isEmpty ? "" : "   [\(notes.joined(separator: "; "))]"))
            } catch {
                totalSteps += c.actions.count
                report.append("✗ ERROR “\(c.words)”: \(error.localizedDescription)")
            }
        }
        let accuracy = Double(correctSteps) / Double(max(totalSteps, 1))
        let sorted = latencies.sorted()
        let median = sorted.isEmpty ? 0 : sorted[sorted.count / 2]
        report.append(String(format: "Action accuracy %.0f%% (%d/%d steps) · slot misses %d · median latency %.2fs · max %.2fs",
                             accuracy * 100, correctSteps, totalSteps, slotMisses, median, sorted.last ?? 0))
        print(report.joined(separator: "\n"))
        let attachment = XCTAttachment(string: report.joined(separator: "\n"))
        attachment.lifetime = .keepAlways
        add(attachment)
        XCTAssertGreaterThanOrEqual(accuracy, 0.85, "Jev action accuracy fell below 85%")
    }
}
