import Foundation

/// A tester's suggestion and how far it has got. Status is written by the build session
/// on Jack's Mac: new -> queued -> working -> shipped (or needs_jack / declined).
struct FeedbackItem: Codable, Identifiable, Hashable, Sendable {
    let id: Int
    let createdAt: Date
    let text: String
    let status: String
    let reply: String?
    let build: String?

    enum CodingKeys: String, CodingKey {
        case id, text, status, reply, build
        case createdAt = "created_at"
    }

    var statusLabel: String {
        switch status {
        case "new", "queued": "Received"
        case "working": "Being built"
        case "shipped": build.map { "In TestFlight build \($0)" } ?? "In TestFlight"
        case "needs_jack": "Waiting on Jack"
        case "declined": "Not this time"
        default: status.capitalized
        }
    }

    var isDone: Bool { ["shipped", "declined"].contains(status) }
}

struct FeedbackDraft: Encodable, Sendable {
    let app = "deepcuts"
    let installID: String
    let name: String
    let text: String
    let context: [String: String]
    /// JPEG, base64, at most ~1.5 MB.
    let screenshot: String?

    enum CodingKeys: String, CodingKey {
        case app, name, text, context, screenshot
        case installID = "install_id"
    }
}

/// Talks to the tester-feedback edge function (Supabase). The app key only lets a
/// TestFlight build post suggestions and read back its own.
struct FeedbackService: Sendable {
    let endpoint: URL?
    let key: String
    var session: URLSession = .shared
    /// UI tests: pretend to send, never touch the network (a real send starts a build session).
    var stubbed = false

    static let stub = FeedbackService(endpoint: URL(string: "https://example.invalid"), key: "stub", stubbed: true)

    static let live = FeedbackService(
        endpoint: (Bundle.main.object(forInfoDictionaryKey: "DEEPCUTS_FEEDBACK_URL") as? String).flatMap { $0.isEmpty ? nil : URL(string: $0) },
        key: Bundle.main.object(forInfoDictionaryKey: "DEEPCUTS_FEEDBACK_KEY") as? String ?? "")

    var isConfigured: Bool { endpoint != nil && !key.isEmpty }

    enum Failure: LocalizedError {
        case notConfigured, server(String)

        var errorDescription: String? {
            switch self {
            case .notConfigured: "This build can't send suggestions."
            case .server(let why): why
            }
        }
    }

    func send(_ draft: FeedbackDraft) async throws -> Int {
        if stubbed { return 0 }
        guard let endpoint, isConfigured else { throw Failure.notConfigured }
        var request = URLRequest(url: endpoint, timeoutInterval: 30)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(key, forHTTPHeaderField: "x-app-key")
        request.httpBody = try JSONEncoder().encode(draft)
        let (data, response) = try await session.data(for: request)
        struct Created: Decodable { let id: Int }
        guard (response as? HTTPURLResponse)?.statusCode == 200, let created = try? JSONDecoder().decode(Created.self, from: data) else {
            throw Failure.server(String(data: data, encoding: .utf8).map { String($0.prefix(200)) } ?? "The server didn't answer.")
        }
        return created.id
    }

    func mine(installID: String) async throws -> [FeedbackItem] {
        if stubbed { return [] }
        guard let endpoint, isConfigured,
              var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false) else { throw Failure.notConfigured }
        components.queryItems = [URLQueryItem(name: "app", value: "deepcuts"), URLQueryItem(name: "install_id", value: installID)]
        guard let url = components.url else { throw Failure.notConfigured }
        var request = URLRequest(url: url, timeoutInterval: 20)
        request.setValue(key, forHTTPHeaderField: "x-app-key")
        let (data, _) = try await session.data(for: request)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let raw = try decoder.singleValueContainer().decode(String.self)
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: raw) { return date }
            formatter.formatOptions = [.withInternetDateTime]
            return formatter.date(from: raw) ?? .now
        }
        return try decoder.decode([FeedbackItem].self, from: data)
    }
}
