import Observation
import XCTest
@testable import DeepCuts

/// The lock beside a mode and the lock on a story are drawn from the calendar day. When the day
/// turns, whatever drew them has to be told, or a Play or Stories tab left open overnight keeps
/// yesterday's locks (and sends today's free story to the Deep Cuts+ sheet).
@MainActor
final class DayRedrawTests: XCTestCase {
    private final class Flag: @unchecked Sendable { var raised = false }

    private func model() -> AppModel {
        let store = ProgressStore(url: FileManager.default.temporaryDirectory.appendingPathComponent("progress-\(UUID()).json"))
        store.setFocus(["classic-rock"])
        return AppModel(progress: store)
    }

    /// Whether the screen that ran `read` would be told when the day turns two days on.
    private func isTold(of app: AppModel, whenReading read: () -> Void) -> Bool {
        let flag = Flag()
        withObservationTracking(read, onChange: { flag.raised = true })
        app.refreshDay(now: Date.now.addingTimeInterval(2 * 86_400))
        return flag.raised
    }

    func testTheLockOnAModeRowIsRedrawnWhenTheDayTurns() {
        let app = model()
        app.progress.useFreeRound(.trivia)
        XCTAssertTrue(app.isLocked(.trivia), "today's free trivia round is spent")
        XCTAssertTrue(isTold(of: app) { _ = app.isLocked(.trivia) }, "the row still shows yesterday's lock")
    }

    func testTodaysFreeStoryIsRedrawnWhenTheDayTurns() throws {
        let app = model()
        let story = try XCTUnwrap(app.focusGenres.flatMap(\.stories).first)
        XCTAssertTrue(isTold(of: app) { _ = app.canRead(story) }, "the Stories tab still shows yesterday's free story")
    }
}
