import XCTest

@MainActor
final class ReleaseJourneysUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    func testCoreLoopDailyMixPersists() {
        let app = XCUIApplication()
        QA.launch(app, arguments: ["-ui-reset", "-ui-feedback-stub"])
        let done = app.buttons["focus-done"]
        XCTAssertTrue(done.waitForExistence(timeout: 15))
        QA.checkpoint(app, "choose-crates")
        app.buttons["crate-classic-rock"].tap()
        done.tap()

        let skip = app.buttons["trial-skip"]
        XCTAssertTrue(skip.waitForExistence(timeout: 15))
        QA.checkpoint(app, "onboarding-trial", paywall: true)
        skip.tap()

        let play = app.buttons["play-daily"]
        XCTAssertTrue(play.waitForExistence(timeout: 15))
        QA.checkpoint(app, "today")
        play.tap()
        XCTAssertTrue(app.buttons["choice-0"].waitForExistence(timeout: 15))
        QA.checkpoint(app, "daily-question")

        for index in 0..<10 {
            let choice = app.buttons["choice-0"]
            if choice.waitForExistence(timeout: 8), choice.isEnabled { choice.tap() }
            let next = app.buttons["quiz-next"]
            XCTAssertTrue(next.waitForExistence(timeout: 15))
            if index == 0 { QA.checkpoint(app, "daily-answer") }
            next.tap()
        }

        XCTAssertTrue(app.staticTexts["result-score"].waitForExistence(timeout: 15))
        QA.checkpoint(app, "daily-result")
        app.buttons["result-done"].tap()
        XCTAssertTrue(app.buttons["daily-more"].waitForExistence(timeout: 10))
        QA.checkpoint(app, "today-completed")
        QA.interrupt(app)
        XCTAssertTrue(app.buttons["daily-more"].waitForExistence(timeout: 10))
        app.launchArguments.removeAll { $0 == "-ui-reset" }
        QA.relaunch(app)
        XCTAssertTrue(app.buttons["daily-more"].waitForExistence(timeout: 15))
        XCTAssertFalse(app.buttons["play-daily"].exists)
        QA.checkpoint(app, "daily-persisted")
    }

    func testDeepCutsPlusPaywall() {
        let app = XCUIApplication()
        QA.launch(app, arguments: ["-ui-reset", "-ui-feedback-stub", "-ui-focus", "classic-rock"])
        XCTAssertTrue(app.buttons["play-daily"].waitForExistence(timeout: 15))
        tab(app, "You").tap()
        let get = app.buttons["plus-get"]
        XCTAssertTrue(get.waitForExistence(timeout: 10))
        QA.checkpoint(app, "you-free")
        get.tap()
        XCTAssertTrue(app.buttons["paywall-buy"].waitForExistence(timeout: 15))
        QA.checkpoint(app, "paywall", paywall: true)
        app.buttons["plan-monthly"].tap()
        QA.checkpoint(app, "paywall-monthly", paywall: true)
        app.buttons["plan-lifetime"].tap()
        QA.checkpoint(app, "paywall-lifetime", paywall: true)
        app.buttons["paywall-close"].tap()
        XCTAssertTrue(get.waitForExistence(timeout: 10))
    }

    func testBrowseCratesLiveAndSettings() {
        let app = XCUIApplication()
        QA.launch(app, arguments: ["-ui-reset", "-ui-feedback-stub", "-ui-focus", "classic-rock", "-ui-venues-stub"])
        XCTAssertTrue(app.buttons["play-daily"].waitForExistence(timeout: 15))

        tab(app, "Play").tap()
        let crate = app.buttons["open-classic-rock"]
        XCTAssertTrue(crate.waitForExistence(timeout: 10))
        QA.checkpoint(app, "play")
        crate.tap()
        XCTAssertTrue(app.buttons["mode-trivia"].waitForExistence(timeout: 10))
        QA.checkpoint(app, "crate")

        tab(app, "Live").tap()
        XCTAssertTrue(app.buttons["venue-The Old Mill Ballroom"].waitForExistence(timeout: 10))
        QA.checkpoint(app, "live")
        tab(app, "You").tap()
        XCTAssertTrue(app.buttons["open-settings"].waitForExistence(timeout: 10))
        QA.checkpoint(app, "you")
        app.buttons["open-settings"].tap()
        XCTAssertTrue(app.buttons["move-up-linerNotes"].waitForExistence(timeout: 10))
        QA.checkpoint(app, "settings")
    }
}
