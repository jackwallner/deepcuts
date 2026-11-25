import XCTest
@testable import DeepCuts

/// Offering metadata `trial_cta` and the remote switches. The control arm is exactly 1.0.1's copy.
@MainActor
final class RemoteConfigTests: XCTestCase {
    func testMissingNonStringAndUnknownValuesAreTheControl() {
        XCTAssertEqual(TrialCTA.from(metadata: nil), .sevenDay)
        XCTAssertEqual(TrialCTA.from(metadata: [:]), .sevenDay)
        XCTAssertEqual(TrialCTA.from(metadata: ["trial_cta": 3]), .sevenDay)
        XCTAssertEqual(TrialCTA.from(metadata: ["trial_cta": ["my"]]), .sevenDay)
        XCTAssertEqual(TrialCTA.from(metadata: ["trial_cta": "ours"]), .sevenDay)
        XCTAssertEqual(TrialCTA.from(metadata: ["trial_cta": "MY"]), .sevenDay)
    }

    func testEachKnownValueReadsItsArm() {
        XCTAssertEqual(TrialCTA.metadataKey, "trial_cta")
        XCTAssertEqual(TrialCTA.from(metadata: ["trial_cta": "seven_day"]), .sevenDay)
        XCTAssertEqual(TrialCTA.from(metadata: ["trial_cta": "my"]), .my)
        XCTAssertEqual(TrialCTA.from(metadata: ["trial_cta": "your"]), .your)
    }

    func testEachArmTitleOnEachSurface() {
        for surface in TrialCTA.Surface.allCases {
            XCTAssertEqual(TrialCTA.sevenDay.title(surface), "Start 7-Day Free Trial")
            XCTAssertEqual(TrialCTA.my.title(surface), "Start My Free Trial")
            XCTAssertEqual(TrialCTA.your.title(surface), "Start Your Free Trial")
            XCTAssertEqual(PlusPricing.cta(.yearly, trial: true, arm: .my, on: surface), "Start My Free Trial")
            XCTAssertEqual(PlusPricing.cta(.monthly, trial: true, arm: .your, on: surface), "Start Your Free Trial")
        }
    }

    /// The pre-change button, character for character, on the trial page and the paywall.
    func testControlIsTheShippedCopy() {
        XCTAssertEqual(PlusPricing.cta(.yearly, trial: true), "Start 7-Day Free Trial")
        XCTAssertEqual(PlusPricing.cta(.yearly, trial: true, arm: .sevenDay, on: .onboarding), "Start 7-Day Free Trial")
        XCTAssertEqual(PlusPricing.cta(.monthly, trial: true, arm: .sevenDay, on: .paywall), "Start 7-Day Free Trial")
        XCTAssertEqual(Membership().trialCTA, .sevenDay, "no offering loaded is the control")
    }

    /// No free week, no trial promise, whatever the arm (3.1.2). Lifetime never names a trial.
    func testIneligibleWordingUnchanged() {
        for arm in TrialCTA.allCases {
            for surface in TrialCTA.Surface.allCases {
                XCTAssertEqual(PlusPricing.cta(.yearly, trial: false, arm: arm, on: surface), "Subscribe")
                XCTAssertEqual(PlusPricing.cta(.monthly, trial: false, arm: arm, on: surface), "Subscribe")
                XCTAssertEqual(PlusPricing.cta(.lifetime, trial: true, arm: arm, on: surface), "Unlock Deep Cuts+ Forever")
            }
        }
    }

    func testSwitchIsOnUnlessOff() {
        XCTAssertEqual(RemoteSwitch.ratingPrompt.rawValue, "rating_prompt")
        XCTAssertTrue(RemoteConfig.isOn(.ratingPrompt, in: nil))
        XCTAssertTrue(RemoteConfig.isOn(.ratingPrompt, in: [:]))
        XCTAssertTrue(RemoteConfig.isOn(.ratingPrompt, in: ["rating_prompt": "on"]))
        XCTAssertTrue(RemoteConfig.isOn(.ratingPrompt, in: ["rating_prompt": "OFF"]))
        XCTAssertTrue(RemoteConfig.isOn(.ratingPrompt, in: ["rating_prompt": false]))
        XCTAssertFalse(RemoteConfig.isOn(.ratingPrompt, in: ["rating_prompt": "off"]))
    }
}
