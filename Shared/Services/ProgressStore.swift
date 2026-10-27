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
    /// Today screen sections, top to bottom, as `TodaySection` raw values.
    var todayOrder: [String] = []
    /// How far the Live tab looks for venues.
    var venueMiles = VenueFinder.defaultMiles
}

extension ProgressData {
    /// Every field is optional on disk, so a file saved by an older build still loads.
    init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        installID = try c.decodeIfPresent(String.self, forKey: .installID) ?? installID
        onboarded = try c.decodeIfPresent(Bool.self, forKey: .onboarded) ?? onboarded
        focus = try c.decodeIfPresent([String].self, forKey: .focus) ?? focus
        testerName = try c.decodeIfPresent(String.self, forKey: .testerName) ?? testerName
        answered = try c.decodeIfPresent([String: Bool].self, forKey: .answered) ?? answered
        crateTallies = try c.decodeIfPresent([String: Tally].self, forKey: .crateTallies) ?? crateTallies
        modeTallies = try c.decodeIfPresent([String: Tally].self, forKey: .modeTallies) ?? modeTallies
        daily = try c.decodeIfPresent([String: QuizResult].self, forKey: .daily) ?? daily
        bestScores = try c.decodeIfPresent([String: Int].self, forKey: .bestScores) ?? bestScores
        readStories = try c.decodeIfPresent(Set<String>.self, forKey: .readStories) ?? readStories
        feedbackIDs = try c.decodeIfPresent([Int].self, forKey: .feedbackIDs) ?? feedbackIDs
        todayOrder = try c.decodeIfPresent([String].self, forKey: .todayOrder) ?? todayOrder
        venueMiles = try c.decodeIfPresent(Int.self, forKey: .venueMiles) ?? venueMiles
    }
}

/// The reorderable sections of the Today screen.
enum TodaySection: String, CaseIterable, Identifiable, Sendable {
    case dailyMix, linerNotes, covered, onThisDay

    var id: String { rawValue }

    var title: String {
        switch self {
        case .linerNotes: "Liner Notes"
        case .covered: "Covered"
        case .onThisDay: "On This Day"
        case .dailyMix: "Today's Mix"
        }
    }
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

    // MARK: Settings

    /// The saved order, with unknown sections dropped and new ones added at the end.
    var todayOrder: [TodaySection] {
        var order = data.todayOrder.compactMap(TodaySection.init(rawValue:))
        order = order.enumerated().filter { order.firstIndex(of: $0.element) == $0.offset }.map(\.element)
        return order + TodaySection.allCases.filter { !order.contains($0) }
    }

    func setTodayOrder(_ order: [TodaySection]) {
        data.todayOrder = order.map(\.rawValue)
        save()
    }

    var venueMiles: Int { VenueFinder.distanceOptions.contains(data.venueMiles) ? data.venueMiles : VenueFinder.defaultMiles }

    func setVenueMiles(_ miles: Int) {
        data.venueMiles = miles
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
