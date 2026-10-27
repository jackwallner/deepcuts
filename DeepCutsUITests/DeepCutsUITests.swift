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
        for mode in ["trivia", "hard", "firstOf"] {
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

    func testPsychedelicCrateFromOnboarding() {
        let app = launch()
        let pick = app.buttons["crate-psychedelic-rock"]
        XCTAssertTrue(pick.waitForExistence(timeout: 10))
        pick.tap()
        app.buttons["focus-done"].tap()
        app.tabBars.buttons["Play"].tap()
        let crate = app.buttons["open-psychedelic-rock"]
        XCTAssertTrue(crate.waitForExistence(timeout: 10))
        crate.tap()
        attach(app, "psychedelic-crate")
        let hard = app.buttons["mode-hard"]
        XCTAssertTrue(hard.waitForExistence(timeout: 5))
        hard.tap()
        XCTAssertTrue(app.buttons["choice-1"].waitForExistence(timeout: 6))
        attach(app, "psychedelic-hard-question")
        playRound(app)
        XCTAssertTrue(app.staticTexts["result-score"].waitForExistence(timeout: 10))
    }

    func attach(_ app: XCUIApplication, _ name: String) {
        sleep(2)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testCoverOfTheDayOnToday() {
        let app = launch(["-ui-focus", "classic-rock,southern-rock"])
        let reveal = app.buttons["cover-reveal"]
        XCTAssertTrue(reveal.waitForExistence(timeout: 10))
        reveal.tap()
        XCTAssertTrue(app.staticTexts["cover-original"].waitForExistence(timeout: 5))
        let round = app.buttons["mode-covers"]
        if !round.isHittable { app.swipeUp() }
        round.tap()
        playRound(app)
        XCTAssertTrue(app.staticTexts["result-score"].waitForExistence(timeout: 10))
    }

    func testReportAProblemFromAnAnswer() {
        let app = launch(["-ui-focus", "classic-rock"])
        let play = app.buttons["play-daily"]
        XCTAssertTrue(play.waitForExistence(timeout: 10))
        play.tap()
        let choice = app.buttons["choice-0"]
        XCTAssertTrue(choice.waitForExistence(timeout: 10))
        choice.tap()
        let report = app.buttons["quiz-report"]
        XCTAssertTrue(report.waitForExistence(timeout: 5))
        report.tap()
        XCTAssertTrue(app.textViews["feedback-text"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Report a problem"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["feedback-reported"].exists, "shows the question being reported")
        app.buttons["Cancel"].tap()
        XCTAssertTrue(app.buttons["quiz-next"].waitForExistence(timeout: 5), "back on the same question")
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


    /// Feedback #3: the spinning record on "Got it" kept the screen busy, so Done never answered.
    func testSuggestionDoneFromYouTabAtLargeText() {
        let app = launch(["-ui-focus", "heavy-metal", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryXL"])
        app.tabBars.buttons["You"].tap()
        let suggest = app.buttons["suggest-you"]
        for _ in 0..<6 where !suggest.isHittable { app.scrollViews.firstMatch.swipeUp() }
        suggest.tap()
        let text = app.textViews["feedback-text"]
        XCTAssertTrue(text.waitForExistence(timeout: 5))
        text.typeText("Check Done")
        app.buttons["feedback-send"].tap()
        let done = app.buttons["feedback-done"]
        XCTAssertTrue(done.waitForExistence(timeout: 5))
        done.tap()
        XCTAssertFalse(done.waitForExistence(timeout: 2), "Done closes the sheet")
        XCTAssertTrue(suggest.isHittable)
    }

    /// Feedback #6: the Live tab asks for location only on tap and lists touring acts from your crates.
    func testLiveTabShowsVenuesAndTouringActs() {
        let app = launch(["-ui-focus", "classic-rock,southern-rock", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryXXXL"])
        app.tabBars.buttons["Live"].tap()
        XCTAssertTrue(app.buttons["live-locate"].waitForExistence(timeout: 5))
        let skynyrd = app.buttons["act-Lynyrd Skynyrd"]
        for _ in 0..<8 where !skynyrd.exists || !skynyrd.isHittable { app.scrollViews.firstMatch.swipeUp() }
        XCTAssertTrue(skynyrd.isHittable)
        XCTAssertFalse(app.buttons["act-Metallica"].exists, "only acts from the chosen crates")

        app.terminate()
        let stubbed = launch(["-ui-focus", "classic-rock", "-ui-venues-stub"])
        stubbed.tabBars.buttons["Live"].tap()
        XCTAssertTrue(stubbed.buttons["venue-The Old Mill Ballroom"].waitForExistence(timeout: 5))
        XCTAssertFalse(stubbed.buttons["live-locate"].exists)

        // Feedback #10: search a city instead of here.
        let field = stubbed.textFields["live-city"]
        field.tap()
        field.typeText("Seattle\n")
        XCTAssertTrue(stubbed.staticTexts["Near Seattle"].waitForExistence(timeout: 5))
        XCTAssertTrue(stubbed.buttons["venue-The Old Mill Ballroom"].waitForExistence(timeout: 5))
        stubbed.buttons["live-my-location"].tap()
        XCTAssertTrue(stubbed.staticTexts["Near You"].waitForExistence(timeout: 5))
    }

    /// Feedback #8: You > Settings reorders the Today screen and sets how far to look for venues.
    func testSettingsReorderTodayAndVenueDistance() {
        let app = launch(["-ui-focus", "classic-rock", "-ui-venues-stub"])
        app.tabBars.buttons["You"].tap()
        let open = app.buttons["open-settings"]
        XCTAssertTrue(open.waitForExistence(timeout: 5))
        open.tap()
        let up = app.buttons["move-up-dailyMix"]
        XCTAssertTrue(up.waitForExistence(timeout: 5))
        for _ in 0..<3 { up.tap() }
        XCTAssertFalse(up.isEnabled, "Today's Mix is now first")
        XCTAssertTrue(app.buttons["today-order-reset"].exists)
        app.buttons["50 mi"].tap()

        app.tabBars.buttons["Today"].tap()
        let play = app.buttons["play-daily"]
        let story = app.buttons["story-of-the-day"]
        XCTAssertTrue(play.waitForExistence(timeout: 5))
        XCTAssertTrue(story.waitForExistence(timeout: 5))
        XCTAssertLessThan(play.frame.minY, story.frame.minY, "the mix moved above Liner Notes")

        app.tabBars.buttons["Live"].tap()
        XCTAssertTrue(app.staticTexts["Within 50 mi"].waitForExistence(timeout: 5))
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
        let name = String(format: "%02d-%@", step, name)
        let screenshot = XCUIScreen.main.screenshot()
        try? screenshot.pngRepresentation.write(to: dir.appendingPathComponent(name + ".png"))
        // Attached too, so remote runs (gh-sim) bring the tour back.
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
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
        app.tabBars.buttons["Live"].tap()
        shot("live")
        app.swipeUp()
        shot("live-scrolled")
        app.tabBars.buttons["You"].tap()
        shot("you")
        app.buttons["open-settings"].tap()
        shot("settings")
        app.navigationBars.buttons.firstMatch.tap()
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
