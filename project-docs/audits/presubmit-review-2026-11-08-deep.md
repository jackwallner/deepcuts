# Pre-submit review, deep pass (2026-11-08)

Branch `review/2026-11-08-deepcuts-deep` from `origin/main` at `a29ef95`.

Scope: every user-reachable path on main (purchase, restore, trial page, paywall, onboarding,
progress persistence and old-file decoding, live content, day rollover, previews, Live tab,
feedback, iPhone Duo panes), not just the diff. `MARKETING_VERSION` has only ever been `1.0.0`, so
the baseline for "since the live version" is build 18 (`a7d83a3`, the build submitted 2026-10-28);
its app-source diff to HEAD (day redraw, round double-tap guard, crate picker footer, AX answer
scroll, quiz Done button) was read in full and is clean. The app has no widgets, notifications,
app intents or SwiftData/CoreData, and ships English only.

No simulator or local `xcodebuild test` was used. Unit tests ran on GitHub's Macs via `gh-sim`.

| Severity | Where | What happens | Status |
|---|---|---|---|
| P1 | `DeepCuts/Views/PaywallView.swift:264`, `DeepCuts/Views/TrialPage.swift:94` | When offerings arrive late (the paywall's "Try again" retry, or a trial-page tap that loads them), the trial check never reruns, so the button still says "Start 7-Day Free Trial" and "7 days free" while the store charges a lapsed subscriber at once. The trial page could also start a purchase before any price was on screen. | Fixed: the retry reruns the trial check, and both purchase paths re-check eligibility and the shown price before selling (`PlusPricing.showedTerms`). If either changed, the screen updates and the next tap buys. Test: `PlusTests.testSaleWaitsForTheTermsTheScreenShowed`. |
| P2 | `DeepCuts/Views/PaywallView.swift:151` | When prices were already loaded on open, `loadAttempted` stayed false. Picking a plan the store omitted (for example, lifetime not cleared for sale in a storefront) showed a spinner on a disabled button forever, with no retry. | Fixed: `loadAttempted` is set when prices are already there, so that plan shows "Prices didn't load. Try again". View state, so there's no unit test. The existing paywall UI journeys cover the normal path. |
| P2 | `Shared/Services/FeedbackService.swift:10` | `Distribution.isTestFlight` reads `sandboxReceipt`, which App Review devices also have. A reviewer sees the TestFlight build-pipeline copy ("sends a new TestFlight build", the Today suggest card, You > Suggestions). A suggestion from the reviewer goes out as `channel: testflight` and would start a build session. That's a 2.2 (beta) rejection risk and contradicts "nobody outside TestFlight can start a build". | Not fixed: no client API tells TestFlight apart from App Review sandbox. This needs a decision, for example a server-side tester allowlist by install ID or an App Review hold in the ops poller. |
| P2 | app target (no `PrivacyInfo.xcprivacy`) | The app calls `UserDefaults` itself (`Membership.swift:182`), which is a required-reason API, but ships no privacy manifest of its own (RevenueCat's covers only RevenueCat). Uploads have been accepted so far, but ITMS-91053 can block or flag a build. | Not fixed: the manifest's collected-data types must match the App Store privacy label, which needs Jack's confirmation. Suggested: `NSPrivacyAccessedAPICategoryUserDefaults` with reason `CA92.1`, no tracking. |
| P2 | `DeepCuts/DeepCutsApp.swift:104` | On the unfolded iPhone Duo, the Deep Cuts+ paywall is a plain `.sheet`, not `paneSheet`, so it can sit across the fold. Every other sheet stays in its pane (`.claude/rules/iphone-duo.md`). | Not fixed: it's a layout choice. The paywall's presentation was accepted in `d11bc23`, and it stays fully usable. |

Checked and clean: `ProgressData` decodes every field with `decodeIfPresent`, and no stored type
changed since the first build. Live rows are validated (`RemoteItem.isSound`) before they can reach
an index. Every `correctIndex` falls back safely. The one force unwrap
(`QuizBuilder.firstOf`) is guarded by a non-empty check. Delegate and observer callbacks hop to the
main actor. The production RevenueCat key never configures on a simulator. Restore, Terms of Use
and Privacy Policy appear on both selling surfaces, along with a Close button. Prices come only from
StoreKit, with no hard-coded amounts. There are no health claims, and links to other platforms are
limited to Ticketmaster and Wikipedia content links. Every bundled crate can build a round in each
mode it offers (checked against `catalog.json`).
