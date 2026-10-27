import Foundation

enum QuizMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case trivia, hard, tune, covers, firstOf

    var id: String { rawValue }

    var title: String {
        switch self {
        case .trivia: "Trivia"
        case .hard: "The Hard Ones"
        case .tune: "Name That Tune"
        case .covers: "Who Did It First?"
        case .firstOf: "Which Came First?"
        }
    }

    /// Only where the name doesn't say what you do.
    var detail: String? {
        switch self {
        case .covers: "Name the original artist"
        case .firstOf: "Pick the older record"
        default: nil
        }
    }

    var length: String {
        switch self {
        case .trivia, .hard: "10 questions"
        case .tune: "6 clips"
        case .covers: "6 covers"
        case .firstOf: "8 matchups"
        }
    }
}

struct Choice: Hashable, Sendable {
    let title: String
    var subtitle: String? = nil
    /// Song shown as artwork beside the choice (Which Came First?).
    var songID: String? = nil

    /// "Ramblin' Man by The Allman Brothers Band".
    var label: String { subtitle.map { "\(title) by \($0)" } ?? title }
}

struct QuizItem: Identifiable, Hashable, Sendable {
    let id: String
    let mode: QuizMode
    let genreID: String
    let prompt: String
    let choices: [Choice]
    let correctIndex: Int
    let fact: String
    /// The clip to play before answering (Name That Tune).
    var audioSongID: String? = nil
    /// Underlying question id, for "seen" tracking (trivia only).
    var questionID: String? = nil
}

/// What a finished round is called and where it came from.
struct QuizSpec: Hashable, Sendable, Identifiable {
    enum Source: Hashable, Sendable {
        case daily(day: String)
        case crate(String)
        case mix
    }

    let source: Source
    let mode: QuizMode?
    let title: String
    let items: [QuizItem]

    var id: String { "\(source)-\(mode?.rawValue ?? "daily")-\(items.map(\.id).joined())" }

    var isDaily: Bool {
        if case .daily = source { return true }
        return false
    }
}

struct QuizResult: Codable, Hashable, Sendable {
    let correct: Int
    let total: Int
}
