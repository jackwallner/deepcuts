import Foundation

/// One row from the deepcuts-content edge function: a new or corrected item for a crate,
/// or a retired one. A row whose id matches a bundled item replaces it.
struct RemoteItem: Codable, Hashable, Sendable {
    enum Payload: Hashable, Sendable {
        case question(Question), song(Song), cover(CoverSong), story(Story)
    }

    let id: String
    let crate: String
    let kind: String
    let status: String
    let rev: Int
    /// Nil when the body didn't decode or failed the checks below; such a row is ignored entirely.
    let payload: Payload?

    var isLive: Bool { status == "live" }

    enum CodingKeys: String, CodingKey { case id, crate, kind, status, rev, body }

    init(id: String, crate: String, kind: String, status: String = "live", rev: Int, payload: Payload?) {
        self.id = id
        self.crate = crate
        self.kind = kind
        self.status = status
        self.rev = rev
        self.payload = payload
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let id = try c.decode(String.self, forKey: .id)
        self.id = id
        crate = try c.decode(String.self, forKey: .crate)
        kind = try c.decode(String.self, forKey: .kind)
        status = try c.decode(String.self, forKey: .status)
        rev = try c.decode(Int.self, forKey: .rev)
        let payload: Payload? = switch kind {
        case "question": (try? c.decode(Question.self, forKey: .body)).map(Payload.question)
        case "song": (try? c.decode(Song.self, forKey: .body)).map(Payload.song)
        case "cover": (try? c.decode(CoverSong.self, forKey: .body)).map(Payload.cover)
        case "story": (try? c.decode(Story.self, forKey: .body)).map(Payload.story)
        default: nil
        }
        self.payload = payload.flatMap { Self.isSound($0, id: id) ? $0 : nil }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(crate, forKey: .crate)
        try c.encode(kind, forKey: .kind)
        try c.encode(status, forKey: .status)
        try c.encode(rev, forKey: .rev)
        switch payload {
        case .question(let q): try c.encode(q, forKey: .body)
        case .song(let s): try c.encode(s, forKey: .body)
        case .cover(let v): try c.encode(v, forKey: .body)
        case .story(let s): try c.encode(s, forKey: .body)
        case nil: break
        }
    }

    /// The checks a round relies on; anything else was validated before it was published.
    static func isSound(_ payload: Payload, id: String) -> Bool {
        switch payload {
        case .question(let q):
            q.id == id && q.choices.count == 4 && Set(q.choices).count == 4 && (0..<4).contains(q.answer) && (1...3).contains(q.difficulty)
        case .song(let s): s.id == id
        case .cover(let v): v.id == id && v.decoys.count == 3
        case .story(let s): s.id == id && !s.paragraphs.isEmpty
        }
    }
}

/// Live content saved on device: every row seen so far, and the rev to sync from next.
struct RemoteContentCache: Codable, Sendable {
    var rev = 0
    var items: [String: RemoteItem] = [:]

    var all: [RemoteItem] { items.values.sorted { $0.rev < $1.rev } }

    mutating func merge(_ rows: [RemoteItem]) {
        for row in rows {
            items[row.id] = row
            rev = max(rev, row.rev)
        }
    }

    static var defaultURL: URL? {
        ProgressStore.defaultURL?.deletingLastPathComponent().appendingPathComponent("live-content.json")
    }

    static func load(from url: URL? = defaultURL) -> RemoteContentCache {
        guard let url, let raw = try? Data(contentsOf: url) else { return RemoteContentCache() }
        return (try? JSONDecoder().decode(RemoteContentCache.self, from: raw)) ?? RemoteContentCache()
    }

    func save(to url: URL? = defaultURL) {
        guard let url, let raw = try? JSONEncoder().encode(self) else { return }
        try? raw.write(to: url, options: .atomic)
    }
}

/// Fetches new and corrected content from the deepcuts-content edge function,
/// which lives next to tester-feedback and takes the same app key.
struct RemoteContentService: Sendable {
    let endpoint: URL?
    let key: String
    var session: URLSession = .shared

    static let live: RemoteContentService = {
        let feedback = FeedbackService.live
        let endpoint = feedback.endpoint?.deletingLastPathComponent().appendingPathComponent("deepcuts-content")
        return RemoteContentService(endpoint: endpoint, key: feedback.key)
    }()

    static let off = RemoteContentService(endpoint: nil, key: "")

    var isConfigured: Bool { endpoint != nil && !key.isEmpty }

    /// Every row changed since `rev`, oldest first.
    func changes(since rev: Int) async throws -> [RemoteItem] {
        guard let endpoint, isConfigured else { return [] }
        struct Page: Decodable { let items: [RemoteItem]; let more: Bool }
        var rows: [RemoteItem] = []
        var cursor = rev
        while true {
            guard var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false) else { return rows }
            components.queryItems = [URLQueryItem(name: "since", value: String(cursor))]
            guard let url = components.url else { return rows }
            var request = URLRequest(url: url, timeoutInterval: 30)
            request.setValue(key, forHTTPHeaderField: "x-app-key")
            let (data, response) = try await session.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
            let page = try JSONDecoder().decode(Page.self, from: data)
            rows += page.items
            guard page.more, let last = page.items.last?.rev, last > cursor else { return rows }
            cursor = last
        }
    }
}
