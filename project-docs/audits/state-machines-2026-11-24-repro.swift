import XCTest

/// State machine audit 2026-11-24, repro suite. Kept beside the audit doc, out of the test target.
/// Copy into DeepCutsUITests/ to run: gh-sim test --scheme DeepCuts --only DeepCutsUITests/StateMachineAuditRepro
final class StateMachineAuditRepro: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-reset", "-ui-feedback-stub", "-ui-plus", "-ui-focus", "classic-rock"]
        app.launch()
        return app
    }

    /// The clip a round starts on is playing or loading (or shows it failed to load), never back to
    /// the idle "Play clip" a moment after the round comes up.
    private func assertFirstClipStillStarted(_ app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(app.staticTexts["quiz-prompt"].waitForExistence(timeout: 10), "precondition: the round is on screen", file: file, line: line)
        XCTAssertTrue(app.staticTexts["quiz-prompt"].label == "Name that tune", "precondition: a Name That Tune question", file: file, line: line)
        // The cover's presentation has long finished by now.
        sleep(3)
        let toggle = app.buttons["clip-toggle"]
        let idle = toggle.exists && toggle.label.contains("Play clip")
        XCTAssertFalse(idle, "the round's first clip was stopped right after the round opened (label: \(toggle.exists ? toggle.label : "none"))", file: file, line: line)
    }

    /// B1: Play > a crate > Name That Tune. The crate page's onDisappear stops the preview player
    /// once the full-screen round covers it, killing the clip the round just started.
    func testRoundFromACrateKeepsItsFirstClipPlaying() {
        let app = launch()
        tab(app, "Play").tap()
        let crate = app.buttons["open-classic-rock"]
        XCTAssertTrue(crate.waitForExistence(timeout: 10))
        crate.tap()
        let tune = app.buttons["mode-tune"]
        XCTAssertTrue(tune.waitForExistence(timeout: 5), "precondition: the crate page is open")
        tune.tap()
        assertFirstClipStillStarted(app)
    }

    /// Control: the same mode from the Play tab, whose page stops nothing when covered.
    func testControlRoundFromThePlayTabKeepsItsFirstClipPlaying() {
        let app = launch()
        tab(app, "Play").tap()
        let tune = app.buttons["mode-tune"]
        XCTAssertTrue(tune.waitForExistence(timeout: 10))
        tune.tap()
        assertFirstClipStillStarted(app)
    }
}
