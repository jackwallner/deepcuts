import XCTest
@testable import DeepCuts

/// A second tap on a mode row lands while the first round is still coming up.
@MainActor
final class RoundStartTests: XCTestCase {
    private func model() -> AppModel {
        let store = ProgressStore(url: FileManager.default.temporaryDirectory.appendingPathComponent("progress-\(UUID()).json"))
        store.setFocus(["classic-rock"])
        return AppModel(progress: store)
    }

    func testASecondTapDoesNotRaiseThePaywallOverTheRoundJustStarted() {
        let app = model()
        app.start(mode: .trivia, crate: nil)
        let round = app.activeQuiz
        XCTAssertNotNil(round)

        app.start(mode: .trivia, crate: nil)
        XCTAssertNil(app.paywall, "the free round was just spent on the round on screen")
        XCTAssertEqual(app.activeQuiz, round, "the round on screen is not replaced")
    }

    func testTheNextRoundStartsOnceTheFirstIsClosed() {
        let app = model()
        app.start(mode: .hard, crate: nil)
        app.activeQuiz = nil
        app.start(mode: .tune, crate: nil)
        XCTAssertEqual(app.activeQuiz?.mode, .tune)
    }
}
