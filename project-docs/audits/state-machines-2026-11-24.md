# State machine audit, 2026-11-24

Scope: the Deep Cuts iOS app (one app target; no widgets, App Intents, notifications or background
tasks, so there are no scheduled or pending requests to reconcile). Audited from committed code at
`6eee83f` (1.0.1, build 25). No app code was changed for this audit.

**Summary: 0 bugs proved by a failing test. 1 claim (B1) was tested and dropped: its repro passed on the starting commit.** Plus 7 product calls (not counted). The Ask to Buy copy (a pending
purchase shown as RevenueCat's English error in an alert) is real, but it is Rollout A's own item and is
fixed and tested there (`rollout-2026-11-24.md`), so it is not counted here.

Evidence run: `gh-sim test --scheme DeepCuts --only DeepCutsUITests/StateMachineAuditRepro`, run
`deepcuts@20261125-140652-e316-claude-imaced0d-1125-141222-9959` (GitHub Actions run 45711207640, Xcode 27.1, iPhone 17, iOS 27.2), on the starting commit: 2 tests, 2 passed. The repro suite is `state-machines-2026-11-24-repro.swift` beside this file (copy it into
`DeepCutsUITests/` to run it). It needs no secrets and passes no build settings.

Test seams used: the UI test launch arguments in `AGENTS.md` (`-ui-reset`, `-ui-plus`, `-ui-focus`) and
the app's accessibility identifiers (`open-<crate>`, `mode-<mode>`, `quiz-prompt`, `clip-toggle`). Seams that
do not exist: a constructible `CustomerInfo` fixture or an injected purchases client (`Membership` calls
`Purchases.shared` directly), so entitlement transitions stay code path or product calls.

## Bugs ranked by impact

| ID | Bug | What the user sees | Promise | User route | Impact | Evidence | file:line |
|---|---|---|---|---|---|---|---|
| B1 (dropped) | Starting a round from a crate page stops the round's first clip | Name That Tune (or Who Did It First?) opened from a crate: the first clip starts, then goes silent as the round finishes sliding up, and the button reads "Play clip". Every later question plays on its own. | `AGENTS.md`: "Name That Tune with Apple Music previews". `Quiz.swift:55`: `audioSongID` is "The clip to play before answering (Name That Tune)". `QuizView.swift:63` autoplays it on every question (`onChange(of: index, initial: true)`). | Play tab, tap a crate (`open-classic-rock`), tap Name That Tune. The round is a `fullScreenCover` (`DeepCutsApp.swift:101`); once it covers the crate page, that page's `onDisappear` runs `app.player.stop()` (`PlayView.swift:162`), the one app-wide player, which is now playing the round's clip. Same from "Play another round" on a crate round's result. | Every player who starts an audio round from a crate page: the genre specialist persona plays from their crate by design, free players get one Name That Tune and one covers round a day each. Every such round loses its first clip; the player has to notice and tap Play. Rounds started from the Play tab or Today are not hit (those pages stop nothing on disappear). | Not proved, dropped. `testRoundFromACrateKeepsItsFirstClipPlaying` passed on the starting commit, as did the control `testControlRoundFromThePlayTabKeepsItsFirstClipPlaying`. Both tests asserted the round was on screen on a "Name that tune" question first. The run logged one AVAudioSession activation warning per test, so each round reached `PreviewPlayer.start` and its clip was not reset to idle 3 s later. On iOS 27.2 the crate page under a `fullScreenCover` does not get `onDisappear` while the round is up. | `PlayView.swift:162`, `QuizView.swift:63`, `PreviewPlayer.swift:47-59` |

## Product calls (not counted: documented, or no cited promise)

1. The daily mix reshuffles after a quit. `startDaily` (`AppModel.swift:67-72`) rebuilds the mix with the
   current `seenQuestions`, so closing it partway and reopening swaps the answered questions for new ones.
   `QuizBuilder.swift:3` says the seed keeps "the daily mix the same all day on every device", but the
   mix already depends on each device's seen set by design, and holding the same questions would hand back
   answers the player has just been shown. Left alone.
2. Closing a round with the X (`QuizView.swift:128`) has no confirmation: a free round is spent at start
   (`AppModel.swift:113`) and a half-played daily mix keeps no result. Design, not a broken promise.
3. `Membership.resolved` is documented as "Nobody is sold a trial before this" (`Membership.swift:49`) but
   nothing reads it. A reinstalled member whose customer record has not loaded yet can see the trial page;
   `TrialPage` finishes onboarding as soon as `isPlus` flips (`TrialPage.swift:84`). Gating the trial page on
   it changes when a trial appears, so it is Jack's call (held in the fixes doc).
4. Changing crates mid-day changes today's free story (`AppModel.storyOfTheDay`), so a free player can read
   more than one free story a day. Generous, not harmful to the user.
5. Flying west after midnight makes `dayKey` an earlier day again: today's mix and each free round come
   back. Generous, no data lost.
6. A killed app on the onboarding trial page reopens on the crate picker with nothing ticked, though the
   picked crates were saved (`OnboardingView.swift:17`, `FocusPicker` starts from `initial: []`).
7. Live content (`refreshContent`) waits an hour after a failed fetch before trying again
   (`AppModel.swift:166`), and a swapped library can change today's mix for a player who has not started it.

## State machines

### SM1. Membership and purchase (`Membership`, `PaywallView`, `TrialPage`)

State: `isConfigured`, `isPlus`, `resolved`, `isTrialing`, `expirationDate`, `willRenew`, `offerings`,
`localOverride` (DEBUG `-ui-plus`), `membership.reinstallSyncDone` (UserDefaults). Per screen: `plan`,
`trialEligible`, `purchasing`, `restoring`, `loading`, `loadAttempted`, `message`.

Invariants: M1 `isPlus` follows the `pro` entitlement after every `apply`; M2 a sale goes ahead only on the
terms the screen showed (`PlusPricing.showedTerms`); M3 the free week is promised only while StoreKit says
the account is eligible; M4 a member is never offered a trial after a reinstall (`recoverReinstalledMembership`).

| From | Event | To | Invariant |
|---|---|---|---|
| Unconfigured (simulator, no `test_` key) | `start()` | resolved, free | none |
| Configured | cached customer info at launch | free or Plus | M1 |
| Configured | `customerInfoStream` update (renewal, lapse, refund, Ask to Buy approved) | free or Plus, sheets close on `isPlus` | M1 |
| Free | buy, Apple sheet, success | Plus after `confirmEntitlement` (3 tries) or the "hasn't unlocked yet" line | M1 |
| Free | buy, user backs out | free, no message | none |
| Free | buy, Ask to Buy | before Rollout A: an alert with RevenueCat's English error. After: "Waiting for approval" under the button, held by that sheet only | Rollout A |
| Free | buy, price or trial changed under the tap | screen redraws to the new terms, no sale | M2, M3 |
| Free, reinstall | `Transaction.currentEntitlements` verified | `syncPurchases`, flag set, Plus | M4 |

No invalid transition found beyond product call 3.

### SM2. Free rounds and the daily mix (`ProgressStore`, `AppModel.start`, `AppModel.startDaily`)

State: `freeRounds[mode] = dayKey`, `daily[dayKey] = QuizResult`, `answered`, tallies, `activeQuiz`, `day`.

Invariants: F1 a free player gets one round per mode per calendar day; F2 today's mix records one result a
day; F3 a lock drawn yesterday redraws today (`AppModel.day`, `DayRedrawTests`); F4 a second tap while a
round comes up does not raise the paywall over it (`activeQuiz == nil` guard).

| From | Event | To | Invariant |
|---|---|---|---|
| Free, mode unplayed today | start | round on screen, `freeRounds[mode] = today` | F1 |
| Free, mode played today | start, or Play another round | paywall (root sheet, or the result's own sheet) | F1 |
| Any | midnight, clock change, foreground | `day` moves, locks and story redraw | F3 |
| Mix unplayed | finish | `daily[today]` written once | F2 |
| Mix on screen | close | nothing saved, next open rebuilds (product calls 1, 2) | none |
| Round on screen | second start tap | ignored | F4 |

### SM3. Preview player (`PreviewPlayer`, one per app)

State: `songID`, `state` (idle, loading, playing, failed), `progress`, the AVPlayer and its observers.

Invariants: P1 one clip at a time; P2 a round's question with a clip autoplays it; P3 leaving a screen stops
what that screen started.

| From | Event | To | Invariant |
|---|---|---|---|
| any | `play(id)` | loading, then playing or failed | P1 |
| playing | clip ends | idle | none |
| any | `stop()` from QuizView, CrateView or StoryView `onDisappear` | idle | P3 |
| round clip loading or playing | a round opens over a crate page (B1, dropped: the crate page gets no onDisappear) | still playing | P2 holds |
| failed | Next | next question, `outcomes[i] = nil` (a skipped clip doesn't count) | none |

### SM4. Stories (`readStories`, `storyReadOn`, `storyOfTheDay`, `canRead`)

Invariants: S1 a free player reads today's story and any story already read; S2 today's story holds still
once read (drawn from stories unread before today). Checked by `DeepCutsTests`; no invalid state found
beyond product call 4.

### SM5. Onboarding (`ProgressData.onboarded`, `focus`, `OnboardingView.picked`)

States: crate picker, trial page, main. A member skips the trial page (`setFocus(onboarded: isPlus)`),
`TrialPage` finishes on purchase or on `isPlus` flipping, Get Started is the free exit. Product calls 3 and 6.

### SM6. Live tab (`LocationProvider`, `venueCity`, `venueMiles`)

States: not asked, locating, denied, failed, located; a saved city overrides location. Permission granted
later in Settings reaches `locationManagerDidChangeAuthorization` and locates. Stale search results are
dropped by comparing the searched location (`LiveView.swift:84,88`). No invalid transition found.

### SM7. Feedback (`FeedbackView`, `showingFeedback`, `feedbackIDs`)

A send failure keeps the text and shows its reason above the button (`FeedbackErrorTests`). No invalid
transition found.

## Phase 2, skeptical review

- B1 dropped. The route is real (Play, crate, Name That Tune) and the code path looked broken on the
  assumption that a full-screen cover removes the presenter and fires its `onDisappear`. The headless
  test says it does not on iOS 27.2: the first clip kept playing. A code-path-only claim is not counted,
  so nothing is fixed for it. If an older iOS (17 to 26) does fire `onDisappear` there, the same repro
  run on that runtime would show it.
- The Ask to Buy item survives (RevenueCat's English "pending" error shown in an alert titled
  Deep Cuts+, `PaywallView.swift` and `TrialPage.swift` `message = error.localizedDescription`), but it is
  Rollout A's own item, fixed and tested there.
- Product call 3 (`resolved` unread) has a cited promise but no headless proof: `Membership` has no
  injected purchases client or `CustomerInfo` fixture. It is held for Jack in the fixes doc because the fix
  would change when the trial page appears.
- Surviving claims: 0.
