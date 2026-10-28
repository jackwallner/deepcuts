import XCTest

extension XCTestCase {
    /// A tab button: in the bottom tab bar, or in the vertical bar iOS 27.1 uses on iPhone Duo.
    func tab(_ app: XCUIApplication, _ name: String) -> XCUIElement {
        let bar = app.tabBars.buttons[name]
        if bar.waitForExistence(timeout: 2) { return bar }
        let button = app.buttons[name].firstMatch
        _ = button.waitForExistence(timeout: 5)
        return button
    }

    /// The back button: in the navigation bar, or in the iPhone Duo's vertical bar.
    func back(_ app: XCUIApplication) {
        let bar = app.navigationBars.buttons.firstMatch
        if bar.exists { bar.tap() } else { app.buttons["BackButton"].firstMatch.tap() }
    }
}

/// The first-run path a new tester takes: pick crates, play today's mix, see the score,
/// browse a crate and a story, and send a suggestion (stubbed, so no build session starts).
final class DeepCutsUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    /// `plus: true` plays as a Deep Cuts+ member, so a test can play any number of rounds.
    func launch(_ extra: [String] = [], plus: Bool = true) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-reset", "-ui-feedback-stub"] + (plus ? ["-ui-plus"] : []) + extra
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
        tab(app, "Play").tap()
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
        tab(app, "Stories").tap()
        let story = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'story-'")).firstMatch
        XCTAssertTrue(story.waitForExistence(timeout: 5))
        story.tap()
        XCTAssertTrue(app.staticTexts["Listen"].waitForExistence(timeout: 5))
    }

    func testPsychedelicCrateFromOnboarding() {
        let app = launch()
        let pick = app.buttons["crate-psychedelic-rock"]
        XCTAssertTrue(pick.waitForExistence(timeout: 10))
        app.scrollViews.firstMatch.swipeUp()  // the last rows sit under the pinned Continue bar
        pick.tap()
        app.buttons["focus-done"].tap()
        tab(app, "Play").tap()
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
        app.buttons["feedback-cancel"].tap()
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
        tab(app, "You").tap()
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
        tab(app, "Live").tap()
        XCTAssertTrue(app.buttons["live-locate"].waitForExistence(timeout: 5))
        let skynyrd = app.buttons["act-Lynyrd Skynyrd"]
        for _ in 0..<8 where !skynyrd.exists || !skynyrd.isHittable { app.scrollViews.firstMatch.swipeUp() }
        XCTAssertTrue(skynyrd.isHittable)
        XCTAssertFalse(app.buttons["act-Metallica"].exists, "only acts from the chosen crates")

        app.terminate()
        let stubbed = launch(["-ui-focus", "classic-rock", "-ui-venues-stub"])
        tab(stubbed, "Live").tap()
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
        tab(app, "You").tap()
        let open = app.buttons["open-settings"]
        XCTAssertTrue(open.waitForExistence(timeout: 5))
        open.tap()
        let up = app.buttons["move-up-linerNotes"]
        XCTAssertTrue(up.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["move-up-dailyMix"].isEnabled, "Today's Mix leads by default")
        up.tap()
        XCTAssertFalse(up.isEnabled, "Liner Notes is now first")
        XCTAssertTrue(app.buttons["today-order-reset"].exists)
        app.buttons["50 mi"].tap()

        tab(app, "Today").tap()
        let play = app.buttons["play-daily"]
        let story = app.buttons["story-of-the-day"]
        XCTAssertTrue(play.waitForExistence(timeout: 5))
        XCTAssertTrue(story.waitForExistence(timeout: 5))
        XCTAssertLessThan(story.frame.minY, play.frame.minY, "Liner Notes moved above the mix")

        tab(app, "Live").tap()
        XCTAssertTrue(app.staticTexts["Within 50 mi"].waitForExistence(timeout: 5))
    }

    /// Answers every item: choice 0 each time, skipping clips that can't load.
    /// Free: the trial page after the crates, one round a day in each mode, today's story.
    func testFreeTierTrialPageAndLimits() {
        let app = launch(plus: false)
        let done = app.buttons["focus-done"]
        XCTAssertTrue(done.waitForExistence(timeout: 10))
        app.buttons["crate-classic-rock"].tap()
        done.tap()

        XCTAssertTrue(app.staticTexts["trial-headline"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["trial-start"].exists)
        XCTAssertTrue(app.buttons["plus-restore"].exists)
        XCTAssertTrue(app.links["Terms of Use"].exists)
        XCTAssertTrue(app.links["Privacy Policy"].exists)
        attach(app, "trial-page")
        app.buttons["trial-skip"].tap()
        XCTAssertTrue(app.buttons["play-daily"].waitForExistence(timeout: 10))

        tab(app, "Play").tap()
        let crate = app.buttons["open-classic-rock"]
        XCTAssertTrue(crate.waitForExistence(timeout: 10))
        crate.tap()
        let trivia = app.buttons["mode-trivia"]
        XCTAssertTrue(trivia.waitForExistence(timeout: 5))
        trivia.tap()
        playRound(app)
        XCTAssertTrue(app.staticTexts["result-score"].waitForExistence(timeout: 10))
        app.buttons["play-again"].tap()
        XCTAssertTrue(app.staticTexts["paywall-headline"].waitForExistence(timeout: 10), "the second round of a mode is Deep Cuts+")
        XCTAssertEqual(app.staticTexts["paywall-headline"].label, "Keep playing")
        XCTAssertTrue(app.buttons["paywall-buy"].exists)
        XCTAssertTrue(app.buttons["plan-lifetime"].exists)
        attach(app, "paywall-round")
        app.buttons["paywall-close"].tap()
        XCTAssertTrue(trivia.waitForExistence(timeout: 5))
        XCTAssertEqual(trivia.value as? String, "Deep Cuts+")
        attach(app, "crate-locked-mode")

        let hard = app.buttons["mode-hard"]
        XCTAssertEqual(hard.value as? String ?? "", "", "other modes still have today's free round")

        tab(app, "Stories").tap()
        let locked = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Deep Cuts+'")).firstMatch
        XCTAssertTrue(locked.waitForExistence(timeout: 5))
        attach(app, "stories-locked")
        locked.tap()
        XCTAssertTrue(app.staticTexts["paywall-headline"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.staticTexts["paywall-headline"].label, "Read every story")
        app.buttons["paywall-close"].tap()

        tab(app, "You").tap()
        XCTAssertTrue(app.buttons["plus-get"].waitForExistence(timeout: 5))
        attach(app, "you-free")
    }

    /// One screenshot per plan, for each product's App Review screenshot.
    func testPaywallPlanShots() {
        let app = launch(["-ui-focus", "classic-rock"], plus: false)
        tab(app, "You").tap()
        let get = app.buttons["plus-get"]
        XCTAssertTrue(get.waitForExistence(timeout: 10))
        get.tap()
        let buy = app.buttons["paywall-buy"]
        XCTAssertTrue(buy.waitForExistence(timeout: 15))
        let deadline = Date().addingTimeInterval(20)
        while !buy.isEnabled && Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.5)) }
        XCTAssertTrue(buy.isEnabled, "prices loaded")
        for plan in ["yearly", "monthly", "lifetime"] {
            app.buttons["plan-\(plan)"].tap()
            attach(app, "paywall-\(plan)")
        }
    }

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
        app.launchArguments = ["-ui-reset", "-ui-feedback-stub", "-ui-plus"] + extra
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
        tab(app, "Play").tap()
        shot("play")
        app.buttons["open-classic-rock"].tap()
        shot("crate")
        app.swipeUp()
        shot("crate-scrolled")
        app.swipeUp()
        app.swipeUp()
        shot("crate-essentials")
        tab(app, "Stories").tap()
        shot("stories")
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'story-'")).firstMatch.tap()
        sleep(2)
        shot("story")
        app.swipeUp()
        shot("story-body")
        back(app)  // a story hides the tab bar
        tab(app, "Live").tap()
        shot("live")
        let city = app.textFields["live-city"]
        city.tap()
        city.typeText("Seattle, WA\n")
        _ = app.buttons["venue-The Showbox"].waitForExistence(timeout: 30)
        shot("live-seattle")
        app.swipeUp()
        shot("live-scrolled")
        tab(app, "You").tap()
        shot("you")
        app.buttons["open-settings"].tap()
        shot("settings")
        back(app)
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
