//
//  JevClient.swift
//  openshape3d
//
//  PrintCAD V1.2: sends what was said + what is selected to TypeSafe's Jev
//  classifier and reads back a `VoiceDecision`. Plain URLSession — no SDK.
//  API: POST https://api.typesafe.ai/v1/systemone (docs.typesafe.ai/api.md).
//
//  The key comes from the gitignored `.env.local`, which Debug builds pull in
//  through Config/Secrets.xcconfig → Config/Info-Debug.plist ("JEVAPIKey").
//  Release builds carry no key.
//

import Foundation

/// The seam VoiceSession talks to; tests use a fake.
protocol VoiceClassifying {
    func decide(_ request: VoiceRequest) async throws -> VoiceDecision
}

enum JevKey {
    static func load(from info: [String: Any]? = Bundle.main.infoDictionary) -> String? {
        guard let raw = info?["JEVAPIKey"] as? String else { return nil }
        let key = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        // Unset build variable: empty, or the literal "$(JEV_API_KEY)".
        guard !key.isEmpty, !key.hasPrefix("$(") else { return nil }
        return key
    }
}

enum JevError: LocalizedError, Equatable {
    case missingKey
    case unauthorized
    case rejected(String)
    case busy
    case http(Int)
    case unreadableReply

    var errorDescription: String? {
        switch self {
        case .missingKey:
            return "No Jev API key. Put JEV_API_KEY = … in printcad/.env.local and rebuild (Debug)."
        case .unauthorized:
            return "Jev rejected the API key (401). Check JEV_API_KEY in .env.local."
        case .rejected(let detail):
            return "Jev couldn't read the request (422): \(detail)"
        case .busy:
            return "Jev is busy right now — press Enter again in a moment."
        case .http(let code):
            return "Jev returned HTTP \(code)."
        case .unreadableReply:
            return "Jev's reply couldn't be read."
        }
    }
}

struct JevVoiceClassifier: VoiceClassifying {
    static let endpoint = URL(string: "https://api.typesafe.ai/v1/systemone")!

    let apiKey: String?
    let session: URLSession
    /// Measured round trips are ~0.4–0.5 s; this only stops a hang.
    var timeout: TimeInterval = 6

    init(apiKey: String? = JevKey.load(), session: URLSession = .shared) {
        self.apiKey = apiKey
        self.session = session
    }

    func decide(_ request: VoiceRequest) async throws -> VoiceDecision {
        guard let apiKey else { throw JevError.missingKey }
        let numbers = SpokenNumberParser.numbers(in: request.transcript)
        let body = try JSONEncoder().encode(VoiceIntent.jevRequest(for: request, numbers: numbers))

        var http = URLRequest(url: Self.endpoint, timeoutInterval: timeout)
        http.httpMethod = "POST"
        http.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        http.setValue("application/json", forHTTPHeaderField: "Content-Type")
        http.httpBody = body

        let started = Date()
        let (data, response) = try await session.data(for: http)
        let latency = Date().timeIntervalSince(started)

        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        switch status {
        case 200:
            break
        case 401:
            throw JevError.unauthorized
        case 422:
            throw JevError.rejected(String(decoding: data.prefix(300), as: UTF8.self))
        case 429, 529:
            throw JevError.busy
        default:
            throw JevError.http(status)
        }
        guard let reply = try? JSONDecoder().decode(VoiceIntent.Response.self, from: data) else {
            throw JevError.unreadableReply
        }
        return try VoiceIntent.decision(from: reply, numbers: numbers, latency: latency)
    }
}
