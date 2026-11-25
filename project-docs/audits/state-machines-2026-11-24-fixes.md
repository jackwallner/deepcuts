# State machine fixes, 2026-11-24

Follows `state-machines-2026-11-24.md`. **Counts: 0 fixed, 1 held for Jack, 1 dropped in review
(nothing to fix).** No app code changed for this audit; no stored data or settings touched.

| Claim | Result | Commit | Regression test |
|---|---|---|---|
| B1, a round opened from a crate page stops its first clip | Dropped: the repro passed on the starting commit (run 45711207640), so there is no failing test to fix against | none | none (the repro stays in `state-machines-2026-11-24-repro.swift`) |
| Ask to Buy shown as RevenueCat's English error in an alert | Fixed under Rollout A, not counted here | `feat(paywall): show a pending Ask to Buy as waiting for approval` | `PurchaseOutcomeTests` |
| Product call 3, `Membership.resolved` is never read | Held for Jack | none | none |

## Held for Jack

1. **The trial page can show before the customer record loads.** `Membership.swift:49` documents
   `resolved` as "Nobody is sold a trial before this", but no screen reads it. A reinstalled member who picks
   crates before RevenueCat answers sees the trial page; it closes itself once `isPlus` flips
   (`TrialPage.swift:84`), and `recoverReinstalledMembership` syncs an owned subscription. Holding the trial
   page until `resolved` would change when a trial appears, which is your call. Recommendation: hold Continue's
   trial page for at most a second or two while `resolved` is false, then go on, so a member never sees a sell
   and a slow network never blocks onboarding.

## Skipped

None. B1 was dropped in review, not skipped: no failing test on iOS 27.2.
