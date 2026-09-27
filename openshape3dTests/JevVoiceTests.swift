//
//  JevVoiceTests.swift
//  openshape3dTests
//
//  PrintCAD V1.2 — spoken numbers, the Jev request/response shapes, and the
//  HTTP client (network stubbed with URLProtocol; no test calls the real Jev).
//  Request/response shapes follow docs.typesafe.ai/api.md and a live call made
//  on 2026-09-28 ("draw a hole in the center of this surface" → hole /
//  face_center / through_all, confidence 1.0, ~0.42 s).
//

import XCTest
@testable import openshape3d

// MARK: - Spoken numbers

final class SpokenNumberParserTests: XCTestCase {
    private func values(_ text: String) -> [Double] {
        SpokenNumberParser.numbers(in: text).map(\.value)
    }

    func testDigitsWithAndWithoutASpaceBeforeTheUnit() {
        XCTAssertEqual(values("drill a 5 mm hole"), [5])
        XCTAssertEqual(values("drill a 5mm hole"), [5])
        XCTAssertEqual(values("2.5 millimetres deep"), [2.5])
    }

    /// What the Mac's recognizer actually produced on 2026-09-28.
    func testNumberWordsAsTheRecognizerWritesThem() {
        XCTAssertEqual(values("I want a seven MM hole at the cent of this"), [7])
        XCTAssertEqual(values("twenty five mm deep"), [25])
        XCTAssertEqual(values("two point five millimetres"), [2.5])
        XCTAssertEqual(values("one hundred and twenty mm"), [120])
    }

    func testTwoNumbersInOneSentenceKeepTheirOrder() {
        let numbers = SpokenNumberParser.numbers(in: "3 mm hole 10 mm deep")
        XCTAssertEqual(numbers.map(\.value), [3, 10])
        XCTAssertEqual(numbers.map(\.phrase), ["3 mm", "10 mm"])
    }

    func testFastenerSizes() {
        let m3 = SpokenNumberParser.numbers(in: "M3 clearance hole")
        XCTAssertEqual(m3, [SpokenNumber(value: 3, unit: .millimetre, isFastenerSize: true)])
        XCTAssertEqual(m3.first?.phrase, "M3 (fastener size)")
        XCTAssertEqual(values("an m 4 hole"), [4])
    }

    func testCentimetresBecomeMillimetresAndDegreesStayDegrees() {
        XCTAssertEqual(values("move it 2 cm"), [20])
        let angle = SpokenNumberParser.numbers(in: "rotate 90 degrees")
        XCTAssertEqual(angle.first?.unit, .degree)
        XCTAssertEqual(angle.first?.phrase, "90°")
    }

    func testPercentages() {
        let numbers = SpokenNumberParser.numbers(in: "scale it to 150% then 80 percent")
        XCTAssertEqual(numbers.map(\.value), [150, 80])
        XCTAssertEqual(numbers.map(\.unit), [.percent, .percent])
        XCTAssertEqual(numbers.first?.phrase, "150%")
    }

    func testCountsWithoutUnits() {
        let numbers = SpokenNumberParser.numbers(in: "make 4 copies")
        XCTAssertEqual(numbers.map(\.value), [4])
        XCTAssertEqual(numbers.first?.unit, SpokenNumber.Unit.none)
    }

    func testThisOneIsNotANumberButOneMillimetreIs() {
        XCTAssertEqual(values("fillet this one"), [])
        XCTAssertEqual(values("chamfer one mm"), [1])
    }

    func testNoNumbers() {
        XCTAssertEqual(values("drill a hole in the centre"), [])
        XCTAssertEqual(values(""), [])
    }
}

// MARK: - Request

/// Builds a reply for EVERY question in `request`: the given choices, else a
/// neutral option (not_applicable / picked / none / other).
enum JevFixture {
    static func reply(for request: JevRequest, _ choices: [String: String],
                      confidence: [String: Double] = [:], model: String = "jev-1.13.0") -> VoiceIntent.Response {
        var answers: [String: VoiceIntent.Response.Answer] = [:]
        for (key, question) in request.questions {
            let options = question.criteria.keys
            let choice = choices[key]
                ?? ["not_applicable", "picked", "none", "other"].first { options.contains($0) }
                ?? options.sorted()[0]
            precondition(options.contains(choice), "\(choice) is not an option of \(key)")
            let p = confidence[key] ?? 1
            var probabilities = Dictionary(uniqueKeysWithValues: options.map { ($0, 0.0) })
            probabilities[choice] = p
            if p < 1, let other = options.first(where: { $0 != choice && $0 != "not_understood" }) {
                probabilities[other] = 1 - p
            }
            answers[key] = .init(type: "choice", choice: choice, confidence: p, probabilities: probabilities)
        }
        return VoiceIntent.Response(model: model, answers: answers)
    }

    static func json(_ response: VoiceIntent.Response) -> Data {
        let answers = response.answers.mapValues { a -> [String: Any] in
            ["type": a.type, "choice": a.choice as Any, "confidence": a.confidence as Any,
             "probabilities": a.probabilities as Any]
        }
        return try! JSONSerialization.data(withJSONObject: ["model": response.model, "answers": answers,
                                                            "usage": ["input_tokens": 1, "output_tokens": 1]])
    }
}

final class JevRequestTests: XCTestCase {
    func testOneStepAsksActionTargetAndSlotsPlusOneRolePerNumber() throws {
        let request = VoiceRequest(transcript: "3 mm hole here, 4 mm deep", target: .face(areaMM2: 800))
        let jev = VoiceIntent.jevRequest(for: request)

        XCTAssertEqual(jev.model, "jev-latest")
        XCTAssertEqual(jev.state.transcript, "3 mm hole here, 4 mm deep")
        XCTAssertEqual(jev.state.selection, "one face, area 800 mm²")
        XCTAssertEqual(jev.state.steps, ["s1": "3 mm hole here 4 mm deep"], "commas inside a step are dropped")
        XCTAssertEqual(jev.state.numbers, ["s1_n1": "3 mm (1st number in s1)", "s1_n2": "4 mm (2nd number in s1)"])
        XCTAssertEqual(Set(jev.questions.keys), ["s1_action", "s1_target", "s1_placement", "s1_depth",
                                                 "s1_direction", "s1_axis", "s1_relative",
                                                 "s1_n1_role", "s1_n2_role"])
        XCTAssertTrue(jev.questions.values.allSatisfy { $0.type == "choice" })
        XCTAssertEqual(Set(jev.questions["s1_n1_role"]!.criteria.keys), Set(NumberRole.allCases.map(\.rawValue)))
    }

    func testAMultiStepCommandGetsQuestionsPerStepInOneRequest() {
        let request = VoiceRequest(
            transcript: "drill a 5 mm hole in the centre, then fillet the top edges 1 mm and mirror it",
            target: .face(areaMM2: 800))
        let jev = VoiceIntent.jevRequest(for: request)
        XCTAssertEqual(jev.state.steps, ["s1": "drill a 5 mm hole in the centre",
                                         "s2": "fillet the top edges 1 mm",
                                         "s3": "mirror it"])
        for s in ["s1", "s2", "s3"] {
            XCTAssertNotNil(jev.questions["\(s)_action"], s)
            XCTAssertNotNil(jev.questions["\(s)_target"], s)
        }
        XCTAssertNotNil(jev.questions["s2_n1_role"])
        XCTAssertNil(jev.questions["s3_n1_role"])
    }

    func testEveryActionAndTargetIsOfferedWithinJevsLimit() {
        let jev = VoiceIntent.jevRequest(for: VoiceRequest(transcript: "x", target: .nothing))
        XCTAssertEqual(Set(jev.questions["s1_action"]!.criteria.keys), Set(VoiceAction.allCases.map(\.rawValue)))
        XCTAssertEqual(Set(jev.questions["s1_target"]!.criteria.keys), Set(VoiceTargetChoice.allCases.map(\.rawValue)))
        XCTAssertLessThanOrEqual(VoiceAction.allCases.count, 255, "Jev's per-question limit")
    }

    func testVariablesAddAVariableQuestion() {
        let jev = VoiceIntent.jevRequest(for: VoiceRequest(transcript: "set wall to 2", target: .nothing),
                                         variables: ["wall", "bolt_d"])
        XCTAssertEqual(Set(jev.questions["s1_variable"]!.criteria.keys), ["wall", "bolt_d", "none"])
        XCTAssertEqual(jev.state.variables, ["wall", "bolt_d"])
    }

    func testNoNumbersMeansNoNumbersInStateAndNoRoleQuestions() throws {
        let jev = VoiceIntent.jevRequest(
            for: VoiceRequest(transcript: "drill a hole in the centre", target: .face(areaMM2: 4)))
        XCTAssertNil(jev.state.numbers)
        XCTAssertFalse(jev.questions.keys.contains { $0.hasSuffix("_role") })
        let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(jev)) as! [String: Any]
        let state = json["state"] as! [String: Any]
        XCTAssertNil(state["numbers"], "omitted, not null")
        XCTAssertNil(state["variables"])
    }
}

// MARK: - Response → decision

final class JevDecisionTests: XCTestCase {
    private func decide(_ transcript: String, _ choices: [String: String],
                        confidence: [String: Double] = [:]) throws -> VoiceDecision {
        let jev = VoiceIntent.jevRequest(for: VoiceRequest(transcript: transcript, target: .face(areaMM2: 800)))
        return try VoiceIntent.decision(from: JevFixture.reply(for: jev, choices, confidence: confidence),
                                        for: jev, latency: 0.42)
    }

    /// The live answer to Prem's own sentence (2026-09-28): hole / centre / through.
    func testTheHoleUseCaseBecomesOneHoleStep() throws {
        let decision = try decide("draw a hole in the center of this surface",
                                  ["s1_action": "hole", "s1_placement": "face_center", "s1_depth": "through_all"])
        XCTAssertEqual(decision.steps.count, 1)
        let step = decision.steps[0]
        XCTAssertEqual(step.action, .hole)
        XCTAssertEqual(step.target, .picked)
        XCTAssertEqual(step.placement, .faceCenter)
        XCTAssertEqual(step.depth, .throughAll)
        XCTAssertEqual(decision.model, "jev-1.13.0")
        XCTAssertEqual(decision.latency, 0.42)
        XCTAssertFalse(decision.needsConfirmation)
    }

    func testStepsKeepTheirOwnActionsTargetsAndNumbers() throws {
        let decision = try decide("drill a 5 mm hole, then fillet the top edges 1 mm", [
            "s1_action": "hole", "s1_n1_role": "diameter",
            "s2_action": "fillet_edges", "s2_target": "top_edges", "s2_n1_role": "radius",
        ])
        XCTAssertEqual(decision.steps.map(\.action), [.hole, .filletEdges])
        XCTAssertEqual(decision.steps.map(\.target), [.picked, .topEdges])
        XCTAssertEqual(decision.steps[0].number(.diameter)?.value, 5)
        XCTAssertEqual(decision.steps[1].number(.radius)?.value, 1)
        XCTAssertEqual(decision.steps[1].text, "fillet the top edges 1 mm")
    }

    func testAnyUnsureStepAsksBeforeAnythingRuns() throws {
        let decision = try decide("drill a hole then do the thing",
                                  ["s1_action": "hole", "s2_action": "boss"],
                                  confidence: ["s2_action": 0.4])
        XCTAssertEqual(decision.unsureStepIndex, 1)
        XCTAssertTrue(decision.needsConfirmation)
        XCTAssertEqual(decision.confidence, 0.4, accuracy: 1e-9)
        XCTAssertTrue(decision.steps[1].suggestions.map(\.action).contains(.boss))
    }

    func testNotUnderstoodAlwaysAsks() {
        XCTAssertTrue(VoiceStep.sample(.notUnderstood, confidence: 0.95).needsConfirmation)
        XCTAssertFalse(VoiceStep.sample(.hole, confidence: 0.8).needsConfirmation)
    }

    func testAnAnswerThatIsNotAnOptionIsAnErrorNotAGuess() throws {
        let jev = VoiceIntent.jevRequest(for: VoiceRequest(transcript: "x", target: .nothing))
        var reply = JevFixture.reply(for: jev, [:])
        var answers = reply.answers
        answers["s1_action"] = .init(type: "choice", choice: "teleport", confidence: 1, probabilities: nil)
        reply = VoiceIntent.Response(model: "m", answers: answers)
        XCTAssertThrowsError(try VoiceIntent.decision(from: reply, for: jev, latency: 0)) {
            XCTAssertEqual($0 as? VoiceIntent.DecodeError, .unknownOption("s1_action", "teleport"))
        }
    }

    func testAMissingAnswerIsAnError() {
        let jev = VoiceIntent.jevRequest(for: VoiceRequest(transcript: "x", target: .nothing))
        XCTAssertThrowsError(try VoiceIntent.decision(from: .init(model: "m", answers: [:]), for: jev, latency: 0)) {
            XCTAssertEqual($0 as? VoiceIntent.DecodeError, .missingAnswer("s1_action"))
        }
    }

    func testTheVariableAnswerIsReadAndNoneMeansNone() throws {
        let jev = VoiceIntent.jevRequest(for: VoiceRequest(transcript: "set wall to 2", target: .nothing),
                                         variables: ["wall"])
        let named = try VoiceIntent.decision(
            from: JevFixture.reply(for: jev, ["s1_action": "set_variable", "s1_variable": "wall", "s1_n1_role": "other"]),
            for: jev, latency: 0)
        XCTAssertEqual(named.steps[0].variable, "wall")
        let none = try VoiceIntent.decision(from: JevFixture.reply(for: jev, [:]), for: jev, latency: 0)
        XCTAssertNil(none.steps[0].variable)
    }
}

// MARK: - HTTP client (stubbed network)

final class StubURLProtocol: URLProtocol {
    nonisolated(unsafe) static var status = 200
    nonisolated(unsafe) static var body = Data()
    nonisolated(unsafe) static var lastRequest: URLRequest?
    nonisolated(unsafe) static var lastBody: Data?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lastRequest = request
        Self.lastBody = request.httpBody ?? request.httpBodyStream.map { stream in
            stream.open(); defer { stream.close() }
            var data = Data()
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let read = stream.read(&buffer, maxLength: buffer.count)
                guard read > 0 else { break }
                data.append(buffer, count: read)
            }
            return data
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: Self.status,
                                       httpVersion: "HTTP/1.1", headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

@MainActor
final class JevClientTests: XCTestCase {
    private func client(key: String? = "test-key") -> JevVoiceClassifier {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        return JevVoiceClassifier(apiKey: key, session: URLSession(configuration: config))
    }

    private let request = VoiceRequest(transcript: "draw a hole in the center of this surface",
                                       target: .face(areaMM2: 3060))

    override func setUp() {
        StubURLProtocol.status = 200
        let jev = VoiceIntent.jevRequest(for: request)
        StubURLProtocol.body = JevFixture.json(JevFixture.reply(
            for: jev, ["s1_action": "hole", "s1_placement": "face_center", "s1_depth": "through_all"]))
        StubURLProtocol.lastRequest = nil
        StubURLProtocol.lastBody = nil
    }

    func testPostsToSystemOneWithTheBearerKeyAndReadsTheDecision() async throws {
        let decision = try await client().decide(request)
        XCTAssertEqual(decision.steps.map(\.action), [.hole])
        XCTAssertEqual(decision.steps[0].placement, .faceCenter)

        let sent = try XCTUnwrap(StubURLProtocol.lastRequest)
        XCTAssertEqual(sent.url?.absoluteString, "https://api.typesafe.ai/v1/systemone")
        XCTAssertEqual(sent.httpMethod, "POST")
        XCTAssertEqual(sent.value(forHTTPHeaderField: "Authorization"), "Bearer test-key")
        let body = try JSONSerialization.jsonObject(with: XCTUnwrap(StubURLProtocol.lastBody)) as! [String: Any]
        XCTAssertEqual(body["model"] as? String, "jev-latest")
        XCTAssertEqual((body["state"] as? [String: Any])?["selection"] as? String, "one face, area 3060 mm²")
    }

    func testNoKeyFailsBeforeAnyNetworkCall() async {
        do {
            _ = try await client(key: nil).decide(request)
            XCTFail("expected missingKey")
        } catch {
            XCTAssertEqual(error as? JevError, .missingKey)
        }
        XCTAssertNil(StubURLProtocol.lastRequest)
    }

    func testHTTPErrorsBecomeClearMessages() async {
        for (status, expected) in [(401, JevError.unauthorized), (429, .busy), (529, .busy), (500, .http(500))] {
            StubURLProtocol.status = status
            StubURLProtocol.body = Data("{}".utf8)
            do {
                _ = try await client().decide(request)
                XCTFail("expected \(expected) for \(status)")
            } catch {
                XCTAssertEqual(error as? JevError, expected, "HTTP \(status)")
            }
        }
    }

    func testA422KeepsJevsExplanation() async {
        StubURLProtocol.status = 422
        StubURLProtocol.body = Data(#"{"detail":"questions.action.criteria too many options"}"#.utf8)
        do {
            _ = try await client().decide(request)
            XCTFail("expected rejected")
        } catch {
            guard case .rejected(let detail) = error as? JevError else { return XCTFail("\(error)") }
            XCTAssertTrue(detail.contains("too many options"), detail)
        }
    }

    func testGarbageIsAnUnreadableReply() async {
        StubURLProtocol.body = Data("not json".utf8)
        do {
            _ = try await client().decide(request)
            XCTFail("expected unreadableReply")
        } catch {
            XCTAssertEqual(error as? JevError, .unreadableReply)
        }
    }
}

// MARK: - Key loading

final class JevKeyTests: XCTestCase {
    func testTheKeyIsReadFromInfoPlistAndTrimmed() {
        XCTAssertEqual(JevKey.load(from: ["JEVAPIKey": "  apikey_abc \n"]), "apikey_abc")
    }

    func testAnUnsetBuildVariableIsNoKey() {
        XCTAssertNil(JevKey.load(from: ["JEVAPIKey": ""]))
        XCTAssertNil(JevKey.load(from: ["JEVAPIKey": "$(JEV_API_KEY)"]))
        XCTAssertNil(JevKey.load(from: [:]))
        XCTAssertNil(JevKey.load(from: nil))
    }
}
