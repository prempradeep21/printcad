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

final class JevRequestTests: XCTestCase {
    func testTheHoleUseCaseAsksActionPlacementDepthAndOneRolePerNumber() throws {
        let request = VoiceRequest(transcript: "3 mm hole here, 4 mm deep", target: .face(areaMM2: 800))
        let numbers = SpokenNumberParser.numbers(in: request.transcript)
        let jev = VoiceIntent.jevRequest(for: request, numbers: numbers)

        XCTAssertEqual(jev.model, "jev-latest")
        XCTAssertEqual(jev.state.transcript, "3 mm hole here, 4 mm deep")
        XCTAssertEqual(jev.state.selection, "one face, area 800 mm²")
        XCTAssertEqual(jev.state.numbers, ["n1": "3 mm (1st number)", "n2": "4 mm (2nd number)"])
        XCTAssertEqual(Set(jev.questions.keys), ["action", "placement", "depth", "role_n1", "role_n2"])
        XCTAssertTrue(jev.questions.values.allSatisfy { $0.type == "choice" })
        XCTAssertEqual(Set(jev.questions["role_n1"]!.criteria.keys), Set(NumberRole.allCases.map(\.rawValue)))
    }

    func testActionOptionsAreFilteredByWhatIsSelected() {
        func actions(_ target: VoiceTarget) -> Set<String> {
            let jev = VoiceIntent.jevRequest(for: VoiceRequest(transcript: "x", target: target), numbers: [])
            return Set(jev.questions["action"]!.criteria.keys)
        }
        XCTAssertTrue(actions(.face(areaMM2: 1)).contains("hole"))
        XCTAssertFalse(actions(.face(areaMM2: 1)).contains("fillet_edges"))
        XCTAssertTrue(actions(.edges(count: 1)).isSuperset(of: ["fillet_edges", "chamfer_edges"]))
        XCTAssertFalse(actions(.edges(count: 1)).contains("hole"))
        XCTAssertTrue(actions(.sketchProfile(areaMM2: 1)).contains("extrude_profile"))
        XCTAssertEqual(actions(.nothing), ["undo", "redo", "view_top", "view_front", "view_isometric",
                                           "fit_view", "export_stl", "not_understood"])
        for target in [VoiceTarget.face(areaMM2: 1), .edges(count: 1), .sketchProfile(areaMM2: 1),
                       .bodies(count: 1), .nothing] {
            XCTAssertTrue(actions(target).contains("not_understood"), "\(target)")
            XCTAssertLessThanOrEqual(actions(target).count, 255, "Jev's per-question limit")
        }
    }

    func testNoNumbersMeansNoNumbersInStateAndNoRoleQuestions() throws {
        let jev = VoiceIntent.jevRequest(
            for: VoiceRequest(transcript: "drill a hole in the centre", target: .face(areaMM2: 4)), numbers: [])
        XCTAssertNil(jev.state.numbers)
        XCTAssertFalse(jev.questions.keys.contains { $0.hasPrefix("role_") })
        // Encodes as the API expects: numbers omitted, not null.
        let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(jev)) as! [String: Any]
        let state = json["state"] as! [String: Any]
        XCTAssertNil(state["numbers"])
        XCTAssertEqual((json["questions"] as! [String: Any]).count, 3)
    }
}

// MARK: - Response → decision

final class JevDecisionTests: XCTestCase {
    /// Shape of the live reply recorded on 2026-09-28.
    static let liveReply = """
    {"model":"jev-1.13.0","answers":{
      "action":{"type":"choice","choice":"hole","confidence":1.0,
                "probabilities":{"fillet_edges":0.0,"hole":1.0,"boss":0.0,"not_understood":0.0}},
      "placement":{"type":"choice","choice":"face_center","confidence":1.0,
                   "probabilities":{"face_center":1.0,"clicked_point":0.0,"not_applicable":0.0}},
      "depth":{"type":"choice","choice":"through_all","confidence":1.0,
               "probabilities":{"through_all":1.0,"blind":0.0,"not_applicable":0.0}}},
     "usage":{"input_tokens":720,"output_tokens":178}}
    """

    func testTheLiveReplyBecomesAHoleAtTheCentreThroughAll() throws {
        let reply = try JSONDecoder().decode(VoiceIntent.Response.self, from: Data(Self.liveReply.utf8))
        let decision = try VoiceIntent.decision(from: reply, numbers: [], latency: 0.42)
        XCTAssertEqual(decision.action, .hole)
        XCTAssertEqual(decision.placement, .faceCenter)
        XCTAssertEqual(decision.depth, .throughAll)
        XCTAssertEqual(decision.confidence, 1)
        XCTAssertEqual(decision.model, "jev-1.13.0")
        XCTAssertEqual(decision.latency, 0.42)
        XCTAssertFalse(decision.needsConfirmation)
        XCTAssertEqual(decision.alternatives.first?.action, .hole)
    }

    func testNumberRolesAreAttachedInOrder() throws {
        let numbers = SpokenNumberParser.numbers(in: "3 mm hole here, 4 mm deep")
        let reply = VoiceIntent.Response(model: "jev-1.13.0", answers: [
            "action": .init(type: "choice", choice: "hole", confidence: 0.95, probabilities: ["hole": 0.97]),
            "placement": .init(type: "choice", choice: "clicked_point", confidence: 0.9, probabilities: nil),
            "depth": .init(type: "choice", choice: "blind", confidence: 1, probabilities: nil),
            "role_n1": .init(type: "choice", choice: "diameter", confidence: 0.99, probabilities: nil),
            "role_n2": .init(type: "choice", choice: "depth", confidence: 1, probabilities: nil),
        ])
        let decision = try VoiceIntent.decision(from: reply, numbers: numbers, latency: 0.5)
        XCTAssertEqual(decision.numbers.map(\.role), [.diameter, .depth])
        XCTAssertEqual(decision.numbers.map(\.number.value), [3, 4])
        XCTAssertEqual(decision.placement, .clickedPoint)
        XCTAssertEqual(decision.depth, .blind)
    }

    func testLowConfidenceOrNotUnderstoodAsksInsteadOfActing() {
        var decision = VoiceDecision.sample(.boss, confidence: 0.45)
        XCTAssertTrue(decision.needsConfirmation)
        decision = .sample(.notUnderstood, confidence: 0.9)
        XCTAssertTrue(decision.needsConfirmation)
        XCTAssertFalse(VoiceDecision.sample(.hole, confidence: 0.8).needsConfirmation)
    }

    func testSuggestionsAreTheTopThreeRealOptions() {
        let decision = VoiceDecision(
            action: .boss, confidence: 0.4,
            alternatives: [.init(action: .boss, probability: 0.4), .init(action: .notUnderstood, probability: 0.3),
                           .init(action: .hole, probability: 0.2), .init(action: .pocket, probability: 0.08),
                           .init(action: .moveFace, probability: 0.015)],
            placement: .notApplicable, depth: .notApplicable, numbers: [], model: "m", latency: 0)
        XCTAssertEqual(decision.suggestions.map(\.action), [.boss, .hole, .pocket])
    }

    func testAnAnswerThatIsNotAnOptionIsAnErrorNotAGuess() {
        let reply = VoiceIntent.Response(model: "m", answers: [
            "action": .init(type: "choice", choice: "teleport", confidence: 1, probabilities: nil),
            "placement": .init(type: "choice", choice: "face_center", confidence: 1, probabilities: nil),
            "depth": .init(type: "choice", choice: "blind", confidence: 1, probabilities: nil),
        ])
        XCTAssertThrowsError(try VoiceIntent.decision(from: reply, numbers: [], latency: 0)) {
            XCTAssertEqual($0 as? VoiceIntent.DecodeError, .unknownOption("action", "teleport"))
        }
    }

    func testAMissingAnswerIsAnError() {
        let reply = VoiceIntent.Response(model: "m", answers: [:])
        XCTAssertThrowsError(try VoiceIntent.decision(from: reply, numbers: [], latency: 0)) {
            XCTAssertEqual($0 as? VoiceIntent.DecodeError, .missingAnswer("action"))
        }
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
        StubURLProtocol.body = Data(JevDecisionTests.liveReply.utf8)
        StubURLProtocol.lastRequest = nil
        StubURLProtocol.lastBody = nil
    }

    func testPostsToSystemOneWithTheBearerKeyAndReadsTheDecision() async throws {
        let decision = try await client().decide(request)
        XCTAssertEqual(decision.action, .hole)
        XCTAssertEqual(decision.placement, .faceCenter)

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
