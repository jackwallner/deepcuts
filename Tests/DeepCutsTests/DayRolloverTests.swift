import XCTest
@testable import DeepCuts

/// Today is drawn from the calendar day, so the app has to notice when the day changes under it.
@MainActor
final class DayRolloverTests: XCTestCase {
    private func model() -> AppModel {
        let store = ProgressStore(url: FileManager.default.temporaryDirectory.appendingPathComponent("progress-\(UUID()).json"))
        store.setFocus(["classic-rock"])
        return AppModel(progress: store)
    }

    func testANewDayMovesTheDayAndDropsYesterdaysMoments() {
        let app = model()
        let now = Date.now
        app.refreshDay(now: now)
        let today = app.day
        app.moments = [MusicMoment(id: "event-1970-x", kind: .event, year: 1970, text: "x", detail: nil, link: nil)]

        app.refreshDay(now: now)
        XCTAssertEqual(app.day, today)
        XCTAssertEqual(app.moments.count, 1, "the same day keeps what it loaded")

        app.refreshDay(now: now.addingTimeInterval(2 * 86_400))
        XCTAssertNotEqual(app.day, today)
        XCTAssertTrue(app.moments.isEmpty, "yesterday's history doesn't sit under today's date")
    }

    func testTheFirstLookAfterMidnightFindsTheMixUnplayed() {
        let app = model()
        let now = Date.now
        app.progress.finish(spec: QuizSpec(source: .daily(day: ProgressStore.dayKey(now)), mode: nil, title: "", items: []),
                            result: QuizResult(correct: 7, total: 10))
        XCTAssertNotNil(app.progress.dailyResult(on: now))
        let tomorrow = now.addingTimeInterval(2 * 86_400)
        app.refreshDay(now: tomorrow)
        XCTAssertNil(app.progress.dailyResult(on: tomorrow))
        XCTAssertEqual(app.day, ProgressStore.dayKey(tomorrow))
    }
}
