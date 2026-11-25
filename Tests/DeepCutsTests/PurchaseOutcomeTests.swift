import RevenueCat
import XCTest
@testable import DeepCuts

/// Ask to Buy and store errors, as the customer sees them on the paywall and the trial page.
final class PurchaseOutcomeTests: XCTestCase {
    func testAskToBuyIsPendingNotAnError() {
        XCTAssertTrue(PurchaseError.isPending(RevenueCat.ErrorCode.paymentPendingError))
        XCTAssertFalse(PurchaseError.isPending(RevenueCat.ErrorCode.purchaseNotAllowedError))
        XCTAssertFalse(PurchaseError.isPending(RevenueCat.ErrorCode.networkError))
        XCTAssertFalse(PurchaseError.isPending(PurchaseError.productsUnavailable))
    }

    func testPendingCopyIsCalm() {
        XCTAssertEqual(PurchaseOutcome.waitingForApproval, "Waiting for approval. Your purchase unlocks once it is approved.")
        XCTAssertFalse(PurchaseOutcome.waitingForApproval.lowercased().contains("error"))
        XCTAssertFalse(PurchaseOutcome.waitingForApproval.contains("—"))
    }

    func testLostConnectionReadsAsTheAppStoreLine() {
        let line = "The App Store isn't reachable right now. Check your connection and try again."
        for code in [RevenueCat.ErrorCode.networkError, .offlineConnectionError] {
            let shown = PurchaseError.shown(code)
            XCTAssertTrue(shown is PurchaseError, "\(code) maps to the app's own line")
            XCTAssertEqual(shown.localizedDescription, line)
        }
        XCTAssertEqual(PurchaseError.shown(PurchaseError.productsUnavailable).localizedDescription, line)
    }

    func testOtherErrorsPassThroughUnchanged() {
        let other = RevenueCat.ErrorCode.purchaseNotAllowedError
        XCTAssertEqual(PurchaseError.shown(other) as? RevenueCat.ErrorCode, other)
        let foreign = URLError(.badURL)
        XCTAssertEqual((PurchaseError.shown(foreign) as? URLError)?.code, .badURL)
    }
}
