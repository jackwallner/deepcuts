---
paths:
  - "Shared/Services/Membership.swift"
  - "Shared/Models/Paywall.swift"
  - "DeepCuts/Views/PaywallView.swift"
  - "DeepCuts/Views/TrialPage.swift"
  - "DeepCuts/Views/OnboardingView.swift"
  - "DeepCuts/AppModel.swift"
  - "scripts/asc-setup-*.py"
---

# Deep Cuts+

Decided 2026-10-28 (Jack picked "the NYT Games model" over add-on features such as Save to Apple
Music or artist crates): limit how much you play each day, never what you can play.

## The split
- Free: Today's Mix, one round a day in **each** mode (`ProgressStore.hasFreeRound`, any crate),
  today's story, any story already read, On This Day, Covered, Live, feedback.
- Plus: unlimited rounds, every story. `AppModel.isLocked(_:)` and `AppModel.canRead(_:)` are the
  only gates; `AppModel.start` raises `paywall = .round(mode)` instead of starting.
- Today's story is drawn from stories unread before today (`storyReadOn`), so reading it does not
  hand out a second free story the same day.
- Never lock content (crates, questions) or the daily ritual. Jack dropped content gating.

## Products (App Store Connect, created by `scripts/asc-setup-subscriptions.py` and
`scripts/asc-setup-lifetime-iap.py`)
- Group "Deep Cuts Plus" (display "Deep Cuts+"): `com.jackwallner.deepcuts.monthly` $2.99,
  `.yearly` $19.99, both with a 1-week free trial in every territory (keep the monthly trial).
- `com.jackwallner.deepcuts.lifetime` $39.99 non-consumable.
- PPP: the Vitals tiers scaled to this base (yearly/monthly USD targets 6.99/0.99, 9.99/1.49,
  15.99/2.49). Prices are read live from StoreKit; never hardcode one in the app or docs.

## RevenueCat
- Project `85797d3e` "Deep Cuts: Music Trivia", entitlement `pro`, offering `default` with
  `$rc_annual`, `$rc_monthly`, `$rc_lifetime` (App Store and Test Store products on each).
- DEBUG uses the Test Store key (`test_`, customer `qa-ios`), Release the `appl_` key. A simulator
  never configures the `appl_` key.
- The In-App Purchase key and App Store Connect API key on the RevenueCat app are entered by Jack
  in the dashboard (console-recipes skill, RevenueCat C). Without them purchases don't validate.

## Surfaces (fleet paywall playbook, `~/ios/paywalls/current-paywall-playbook.md`)
- Onboarding trial page (`TrialPage`): one yearly trial, its button in exactly Continue's frame
  (the crate picker reserves an invisible `PlusLegalFooter`), Get Started is the free exit.
- `PaywallView(reason:)`: yearly selected, monthly, lifetime; terms line, Restore, Terms of Use
  (Apple's standard EULA), Privacy Policy. Opened by a locked round, a locked story, You.
- App Store description must keep the Terms of Use (EULA) and Privacy Policy links (3.1.2).
