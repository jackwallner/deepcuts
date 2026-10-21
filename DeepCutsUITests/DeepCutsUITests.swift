import XCTest

/// The first-run path a new tester takes: pick crates, play today's mix, see the score,
/// browse a crate and a story, and send a suggestion (stubbed, so no build session starts).
final class DeepCutsUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    func launch(_ extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-reset", "-ui-feedback-stub"] + extra
        app.launch()
        return app
    }

    func testOnboardingDailyMixAndResult() {
        let app = launch()
        let done = app.buttons["focus-done"]
        XCTAssertTrue(done.waitForExistence(timeout: 10))
        XCTAssertFalse(done.isEnabled)
        app.buttons["crate-classic-rock"].tap()
        XCTAssertTrue(done.isEnabled)
        done.tap()

        let play = app.buttons["play-daily"]
        XCTAssertTrue(play.waitForExistence(timeout: 10))
        play.tap()
        playRound(app)
        XCTAssertTrue(app.staticTexts["result-score"].waitForExistence(timeout: 10))
        app.buttons["result-done"].tap()
        XCTAssertFalse(app.buttons["play-daily"].waitForExistence(timeout: 2), "the mix can only be played once a day")
    }

    func testCrateRoundsAndStory() {
        let app = launch(["-ui-focus", "classic-rock"])
        app.tabBars.buttons["Play"].tap()
        let crate = app.buttons["open-classic-rock"]
        XCTAssertTrue(crate.waitForExistence(timeout: 10))
        crate.tap()
        for mode in ["trivia", "firstOf"] {
            let button = app.buttons["mode-\(mode)"]
            XCTAssertTrue(button.waitForExistence(timeout: 5))
            button.tap()
            playRound(app)
            XCTAssertTrue(app.staticTexts["result-score"].waitForExistence(timeout: 10))
            app.buttons["result-done"].tap()
        }
        app.tabBars.buttons["Stories"].tap()
        let story = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'story-'")).firstMatch
        XCTAssertTrue(story.waitForExistence(timeout: 5))
        story.tap()
        XCTAssertTrue(app.staticTexts["Listen"].waitForExistence(timeout: 5))
    }

    func testSuggestionSends() {
        let app = launch(["-ui-focus", "classic-rock"])
        let suggest = app.buttons["suggest-today"]
        let scroll = app.scrollViews.firstMatch
        for _ in 0..<6 where !suggest.isHittable { scroll.swipeUp() }
        suggest.tap()
        let text = app.textViews["feedback-text"]
        XCTAssertTrue(text.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["feedback-send"].isEnabled)
        text.typeText("Add a crate for '50s rock and roll")
        app.buttons["feedback-send"].tap()
        XCTAssertTrue(app.buttons["feedback-done"].waitForExistence(timeout: 10))
        app.buttons["feedback-done"].tap()
    }

    /// Answers every item: choice 0 each time, skipping clips that can't load.
    private func playRound(_ app: XCUIApplication) {
        for _ in 0..<12 {
            let next = app.buttons["quiz-next"]
            let choice = app.buttons["choice-0"]
            if app.staticTexts["result-score"].exists { return }
            if choice.waitForExistence(timeout: 5), choice.isEnabled {
                choice.tap()
            }
            XCTAssertTrue(next.waitForExistence(timeout: 15))
            next.tap()
        }
    }
}

/// Not a pass/fail test: walks every screen and saves screenshots to /tmp/deepcuts-tour
/// for design and persona review. Run with -only-testing:DeepCutsUITests/Tour.
final class Tour: XCTestCase {
    var app: XCUIApplication!
    var step = 0
    let dir = URL(fileURLWithPath: "/tmp/deepcuts-tour")

    func shot(_ name: String) {
        step += 1
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        sleep(1)
        try? XCUIScreen.main.screenshot().pngRepresentation
            .write(to: dir.appendingPathComponent(String(format: "%02d-%@.png", step, name)))
    }

    func testTour() {
        app = XCUIApplication()
        let extra = ProcessInfo.processInfo.environment["TOUR_ARGS"]?.split(separator: " ").map(String.init) ?? []
        app.launchArguments = ["-ui-reset", "-ui-feedback-stub"] + extra
        app.launch()
        XCTAssertTrue(app.buttons["focus-done"].waitForExistence(timeout: 10))
        shot("onboarding")
        app.buttons["crate-classic-rock"].tap()
        app.buttons["crate-southern-rock"].tap()
        shot("onboarding-picked")
        app.buttons["focus-done"].tap()
        XCTAssertTrue(app.buttons["play-daily"].waitForExistence(timeout: 10))
        sleep(3)
        shot("today")
        app.swipeUp()
        shot("today-scrolled")
        app.swipeDown()
        app.buttons["play-daily"].tap()
        for i in 0..<10 {
            if app.staticTexts["result-score"].waitForExistence(timeout: 1) { break }
            let choice = app.buttons["choice-1"]
            guard choice.waitForExistence(timeout: 6) else { break }
            sleep(2)
            shot("quiz-\(i)")
            if choice.isEnabled { choice.tap() }
            shot("quiz-\(i)-answered")
            app.buttons["quiz-next"].tap()
        }
        shot("result")
        app.swipeUp()
        shot("result-scrolled")
        app.buttons["result-done"].tap()
        shot("today-done")
        app.tabBars.buttons["Play"].tap()
        shot("play")
        app.buttons["open-classic-rock"].tap()
        shot("crate")
        app.swipeUp()
        shot("crate-scrolled")
        app.swipeUp()
        app.swipeUp()
        shot("crate-essentials")
        app.tabBars.buttons["Stories"].tap()
        shot("stories")
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'story-'")).firstMatch.tap()
        sleep(2)
        shot("story")
        app.swipeUp()
        shot("story-body")
        app.tabBars.buttons["You"].tap()
        shot("you")
        app.swipeUp()
        shot("you-scrolled")
        app.buttons["suggest-you"].tap()
        shot("feedback")
        app.textViews["feedback-text"].typeText("Add a crate for '50s rock and roll: Elvis, Chuck Berry, Buddy Holly.")
        shot("feedback-typed")
        app.buttons["feedback-send"].tap()
        XCTAssertTrue(app.buttons["feedback-done"].waitForExistence(timeout: 10))
        shot("feedback-sent")
    }
}
