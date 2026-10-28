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
    /// Famous covers for "Who Did It First?". Optional in the JSON.
    let covers: [CoverSong]?

    var coverSongs: [CoverSong] { covers ?? [] }

    var eraLabel: String { era }
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

/// A cover better known than (or as known as) its original.
struct CoverSong: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let artist: String
    let year: Int
    let album: String
    let original: String
    let originalYear: Int
    let decoys: [String]
    let note: String

    /// Who had it first, then the story, without saying the year twice.
    var originNote: String {
        note.contains(String(originalYear)) ? note : "First released by \(original) in \(originalYear). \(note)"
    }

    /// As a record row: the cover, with who had it first.
    var asSong: Song {
        Song(id: id, title: title, artist: artist, year: year, album: album, note: originNote)
    }
}

struct Story: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let dek: String
    let year: Int
    let body: String
    let songs: [String]
    /// The album whose sleeve illustrates the story. Resolved into the catalog as `cover-<id>`.
    var cover: Cover? = nil
    /// "concert" for a story about one show; nil for records and people.
    var kind: String? = nil

    var isConcert: Bool { kind == "concert" }

    struct Cover: Codable, Hashable, Sendable {
        let album: String
        let artist: String
    }

    var coverKey: String { "cover-\(id)" }

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
