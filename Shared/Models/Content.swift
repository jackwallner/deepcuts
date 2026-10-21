import Foundation

/// One focus area ("crate"): its trivia, essential songs and long-form stories.
struct Genre: Codable, Identifiable, Sendable {
    let id: String
    let name: String
    let blurb: String
    let era: String
    let questions: [Question]
    let songs: [Song]
    let stories: [Story]

    /// "1969–1983", with a proper en dash for display.
    var eraLabel: String { era.replacingOccurrences(of: "-", with: "\u{2013}") }
}

struct Question: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let prompt: String
    let choices: [String]
    let answer: Int
    let fact: String
    let difficulty: Int
}

struct Song: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let artist: String
    let year: Int
    let album: String
    let note: String
}

struct Story: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let dek: String
    let year: Int
    let body: String
    let songs: [String]

    var paragraphs: [String] {
        body.components(separatedBy: "\n\n").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }

    var readingMinutes: Int {
        max(1, Int((Double(body.split(separator: " ").count) / 220).rounded()))
    }
}

/// Apple Music catalog data for a song, resolved ahead of time by scripts/resolve-catalog.py.
struct CatalogEntry: Codable, Hashable, Sendable {
    let trackId: Int
    let previewUrl: String?
    let artworkUrl: String?
    let trackViewUrl: String?
}
