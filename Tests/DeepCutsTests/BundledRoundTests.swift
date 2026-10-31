import XCTest
@testable import DeepCuts

/// The rounds the real crates build, not a fixture: every crate, many days.
final class BundledRoundTests: XCTestCase {
    private let library = ContentLibrary.shared

    private func isHard(_ item: QuizItem, in genre: Genre) -> Bool {
        genre.questions.first { $0.id == item.questionID }?.difficulty == 3
    }

    func testEveryCrateBuildsAFullDailyMixOnEveryDay() {
        let builder = QuizBuilder(library: library)
        for genre in library.genres {
            for offset in 0..<56 {
                let day = String(format: "2026-%02d-%02d", offset / 28 + 11, offset % 28 + 1)
                let label = "\(genre.id) \(day)"
                let mix = builder.daily(day: day, genres: [genre], seen: [])
                XCTAssertEqual(mix.count, 10, label)
                XCTAssertEqual(Set(mix.map(\.id)).count, mix.count, "\(label): an item repeats")
                XCTAssertEqual(mix.last?.mode, .covers, "\(label): the mix ends on a cover")
                XCTAssertLessThanOrEqual(mix.filter { isHard($0, in: genre) }.count, 1, "\(label): at most one hard question")
                for item in mix {
                    XCTAssertTrue(item.choices.indices.contains(item.correctIndex), "\(label): \(item.id)")
                    XCTAssertEqual(Set(item.choices.map(\.label)).count, item.choices.count, "\(label): \(item.id) repeats a choice")
                }
            }
        }
    }

    func testEveryCrateFillsTheRoundsItAdvertises() {
        let builder = QuizBuilder(library: library)
        var rng = SeededRandom(seed: 2026)
        for genre in library.genres {
            for _ in 0..<10 {
                XCTAssertEqual(builder.round(mode: .trivia, genres: [genre], seen: [], rng: &rng).count, 10, "\(genre.id) trivia")
                XCTAssertEqual(builder.round(mode: .tune, genres: [genre], seen: [], rng: &rng).count, 6, "\(genre.id) clips")
                XCTAssertEqual(builder.round(mode: .covers, genres: [genre], seen: [], rng: &rng).count, 6, "\(genre.id) covers")
                if builder.offers(.hard, genres: [genre]) {
                    XCTAssertEqual(builder.round(mode: .hard, genres: [genre], seen: [], rng: &rng).count, 10, "\(genre.id) hard")
                }
            }
        }
    }

    func testEveryCrateAnswerKeyPointsAtTheRightChoice() {
        let builder = QuizBuilder(library: library)
        var rng = SeededRandom(seed: 7)
        for genre in library.genres {
            for question in genre.questions {
                let item = builder.item(for: question, genre: genre, rng: &rng)
                XCTAssertEqual(item.choices[item.correctIndex].title, question.choices[question.answer], question.id)
            }
        }
    }
}
