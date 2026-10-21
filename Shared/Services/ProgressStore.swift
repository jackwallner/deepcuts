import Foundation
import Observation

struct Tally: Codable, Hashable, Sendable {
    var correct = 0
    var answered = 0

    var accuracy: Double? { answered == 0 ? nil : Double(correct) / Double(answered) }
}

struct ProgressData: Codable, Sendable {
    var installID = UUID().uuidString
    var onboarded = false
    var focus: [String] = []
    var testerName = ""
    /// Question id -> last answer was right.
    var answered: [String: Bool] = [:]
    var crateTallies: [String: Tally] = [:]
    var modeTallies: [String: Tally] = [:]
    /// "yyyy-MM-dd" -> today's mix result.
    var daily: [String: QuizResult] = [:]
    var bestScores: [String: Int] = [:]
    var readStories: Set<String> = []
    var feedbackIDs: [Int] = []
}

/// Everything the player has done, saved as one JSON file in Application Support.
@MainActor
@Observable
final class ProgressStore {
    private(set) var data: ProgressData
    private let url: URL?

    init(url: URL? = ProgressStore.defaultURL) {
        self.url = url
        if let url, let raw = try? Data(contentsOf: url),
           let saved = try? JSONDecoder().decode(ProgressData.self, from: raw) {
            data = saved
        } else {
            data = ProgressData()
        }
    }

    nonisolated static var defaultURL: URL? {
        guard let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("progress.json")
    }

    func reset() {
        data = ProgressData()
        save()
    }

    // MARK: Focus

    var focus: [String] { data.focus }

    func setFocus(_ ids: [String]) {
        data.focus = ids
        data.onboarded = !ids.isEmpty
        save()
    }

    func setTesterName(_ name: String) {
        data.testerName = name
        save()
    }

    // MARK: Answers

    var seenQuestions: Set<String> { Set(data.answered.keys) }

    func record(item: QuizItem, correct: Bool) {
        if let id = item.questionID { data.answered[id] = correct }
        data.crateTallies[item.genreID, default: Tally()].add(correct)
        data.modeTallies[item.mode.rawValue, default: Tally()].add(correct)
        save()
    }

    func finish(spec: QuizSpec, result: QuizResult) {
        if case .daily(let day) = spec.source, data.daily[day] == nil {
            data.daily[day] = result
        }
        let key = "\(spec.source)-\(spec.mode?.rawValue ?? "daily")"
        data.bestScores[key] = max(data.bestScores[key] ?? 0, result.correct)
        save()
    }

    func tally(crate id: String) -> Tally { data.crateTallies[id] ?? Tally() }

    var overall: Tally {
        data.crateTallies.values.reduce(into: Tally()) { total, t in
            total.correct += t.correct
            total.answered += t.answered
        }
    }

    func seenCount(in genre: Genre) -> Int {
        genre.questions.filter { data.answered[$0.id] != nil }.count
    }

    // MARK: Daily

    static func dayKey(_ date: Date = .now, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    func dailyResult(on date: Date = .now) -> QuizResult? { data.daily[Self.dayKey(date)] }

    /// Consecutive days with a finished mix, ending today (or yesterday, if today is not played yet).
    func streak(today: Date = .now, calendar: Calendar = .current) -> Int {
        var day = calendar.startOfDay(for: today)
        if data.daily[Self.dayKey(day, calendar: calendar)] == nil {
            day = calendar.date(byAdding: .day, value: -1, to: day) ?? day
        }
        var count = 0
        while data.daily[Self.dayKey(day, calendar: calendar)] != nil {
            count += 1
            day = calendar.date(byAdding: .day, value: -1, to: day) ?? day
        }
        return count
    }

    // MARK: Stories and feedback

    func markRead(_ story: Story) {
        guard !data.readStories.contains(story.id) else { return }
        data.readStories.insert(story.id)
        save()
    }

    func rememberFeedback(_ id: Int) {
        data.feedbackIDs.append(id)
        save()
    }

    // MARK: Persistence

    private func save() {
        guard let url, let raw = try? JSONEncoder().encode(data) else { return }
        try? raw.write(to: url, options: .atomic)
    }
}

extension Tally {
    mutating func add(_ correct: Bool) {
        answered += 1
        if correct { self.correct += 1 }
    }
}
