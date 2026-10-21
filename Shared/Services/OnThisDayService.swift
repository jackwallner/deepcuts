import Foundation

/// Music history for a calendar day, from Wikipedia's "On this day" feed.
struct MusicMoment: Identifiable, Hashable, Sendable {
    enum Kind: String, Sendable { case born, event }

    let id: String
    let kind: Kind
    let year: Int
    let text: String
    let detail: String?
    let link: URL?
    /// A library artist named in the Wikipedia summary ("Toto" for Steve Lukather).
    var connection: String? = nil
}

enum OnThisDay {
    /// Words in a Wikipedia page description that mark a pop-music person, band or record.
    static let musicWords = [
        "singer", "songwriter", "musician", "guitarist", "drummer", "bassist", "keyboardist",
        "rapper", "band", "rock group", "vocalist", "record producer", "album", "single by", "song by",
    ]

    static func moments(month: Int, day: Int, artists: [String], session: URLSession = .shared) async throws -> [MusicMoment] {
        let path = String(format: "%02d/%02d", month, day)
        guard let url = URL(string: "https://en.wikipedia.org/api/rest_v1/feed/onthisday/all/\(path)") else { return [] }
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.setValue("DeepCuts/1.0 (iOS; jackwallner@gmail.com)", forHTTPHeaderField: "Api-User-Agent")
        let (data, _) = try await session.data(for: request)
        return parse(data, artists: artists)
    }

    static func parse(_ data: Data, artists: [String] = []) -> [MusicMoment] {
        struct Feed: Decodable {
            var births: [Entry]?
            var events: [Entry]?
            var selected: [Entry]?
        }
        struct Entry: Decodable {
            let text: String
            let year: Int?
            let pages: [Page]?
        }
        struct Page: Decodable {
            let description: String?
            let content_urls: URLs?
            let normalizedtitle: String?
            let extract: String?
        }
        struct URLs: Decodable { let mobile: Link? }
        struct Link: Decodable { let page: String? }

        guard let feed = try? JSONDecoder().decode(Feed.self, from: data) else { return [] }

        func isMusic(_ description: String?) -> Bool {
            guard let d = description?.lowercased() else { return false }
            let excluded = ["classical", "opera", "christian", "soprano", "tenor", "baritone", "gospel"]
            return musicWords.contains { d.contains($0) } && !excluded.contains { d.contains($0) }
        }

        func connection(_ page: Page) -> String? {
            guard let extract = page.extract else { return nil }
            // Skip nicknames and longer names that merely contain an artist: "Queen of Salsa",
            // "Queen Elizabeth", a quoted "Queen of Pop-Rap".
            return artists.first { artist in
                let name = NSRegularExpression.escapedPattern(for: artist)
                return artist.count >= 4
                    && extract.range(of: "(?<![\"\u{201C}])\\b\(name)\\b(?! of\\b)(?! [A-Z])", options: .regularExpression) != nil
            }
        }

        var moments: [MusicMoment] = []
        for entry in feed.births ?? [] {
            guard let year = entry.year, year >= 1900, let person = entry.pages?.first, isMusic(person.description) else { continue }
            moments.append(MusicMoment(
                id: "born-\(year)-\(entry.text)", kind: .born, year: year, text: entry.text,
                detail: person.description.map { $0.prefix(1).uppercased() + $0.dropFirst() },
                link: person.content_urls?.mobile?.page.flatMap(URL.init(string:)),
                connection: connection(person)))
        }
        for entry in (feed.selected ?? []) + (feed.events ?? []) {
            guard let year = entry.year, year >= 1940, let page = entry.pages?.first(where: { isMusic($0.description) }) else { continue }
            let id = "event-\(year)-\(entry.text)"
            guard !moments.contains(where: { $0.id == id }) else { continue }
            moments.append(MusicMoment(
                id: id, kind: .event, year: year, text: entry.text, detail: nil,
                link: page.content_urls?.mobile?.page.flatMap(URL.init(string:)),
                connection: connection(page)))
        }
        // Moments tied to the library first, then events, then births; oldest first within each.
        func rank(_ m: MusicMoment) -> Int { m.connection != nil ? 0 : (m.kind == .event ? 1 : 2) }
        return moments.sorted { (rank($0), $0.year) < (rank($1), $1.year) }
    }
}
