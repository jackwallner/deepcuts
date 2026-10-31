import XCTest

/// Today left open while the calendar day changes: midnight with the app up, or a return after one.
/// The launch switches play today's mix already, then move the clock a day ahead and post the
/// notification the system sends (`-ui-day-flip`, DEBUG builds only).
@MainActor
final class DayRolloverUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    func testTodayOffersANewMixWhenTheDayChanges() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-reset", "-ui-feedback-stub", "-ui-focus", "classic-rock",
                               "-ui-daily-played", "-ui-day-flip", "25"]
        app.launch()
        XCTAssertTrue(app.buttons["daily-more"].waitForExistence(timeout: 15), "today's mix is already played")
        XCTAssertFalse(app.buttons["play-daily"].exists)
        XCTAssertTrue(app.buttons["play-daily"].waitForExistence(timeout: 45), "the next day offers a new mix without a relaunch")
    }
}
