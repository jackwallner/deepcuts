---
paths:
  - "DeepCuts/DeepCutsApp.swift"
  - "DeepCuts/ScreenshotScene.swift"
  - "DeepCuts/Views/UnfoldedSplit.swift"
  - "DeepCuts/Views/StoriesView.swift"
  - "DeepCuts/Views/QuizView.swift"
---

# Deep Cuts: iPhone Duo (2026-10-27)

- Unfolded (regular width, at least 720 pt), `RootView` puts the `TabView` (Today, Play,
  Live, You) on the leading side of the fold and `StoriesPane` on the trailing side. Stories
  drops out of the tab bar while split. Pane edges come from `GeometryProxy.verticalFold()`
  (iOS 27.1 `reservedRegions(.division)`), else an even split (`UnfoldedSplit`, unit-tested
  in `UnfoldedSplitTests`). Folded and in portrait it is the phone app, unchanged.
- Why this pairing: Deep Cuts sells on the daily game plus the long-form liner notes. Any
  story link (Today's Liner Notes, a crate's Stories, the shelf) is a `StoryLink`, which
  opens it in the reading pane when `\.isUnfoldedPane` is set, so you read beside the
  screen you came from. The open story is `AppModel.storyPath`, shared with the Stories
  tab, so folding with a story open lands on it.
- The tab bar stays the system one: the `TabView` is framed to the leading pane, so the bar
  floats at the bottom of that pane and never crosses the fold. `tabBarBackdrop` lays paper
  (with a short fade) under it there, because rows showed through the glass bar (run 1,
  2026-10-27). Folded, iOS 27.1 draws the tab bar as a vertical bar at the outer display's
  trailing edge, with the status bar: that is the system's, not ours. UI tests find tabs by
  label through `tab(app, name)`, since `app.tabBars` is empty there.
- Folding only moves frames: the `TabView` and the pane are never swapped by an `if`, so
  tabs keep scroll and navigation.
- The reading pane has no `NavigationStack`: it draws its own "Stories" back button, so no
  system bar button lands at the display's edge outside the pane.
- A round (`QuizView`, a full-screen cover) splits the same way: the question (prompt,
  record, choices) on the leading pane; the answer card and Next at the top of `RoundSheet`
  (answers so far, how many to go) on the trailing pane; `ResultView` drops its recap there.
  A 669 pt pane can't hold question, answer and Next, and scrolling to the answer sliced
  the prompt under the top bar (run 1). Unfolded, a round never scrolls to its answer.
- Both panes fade the last 28 pt at the display's bottom edge (`paneBottomFade`), so no
  line is sliced there. Frame panes after any `safeAreaInset`, which fills its proposal
  and would centre a narrower pane on the fold.
- `FeedbackView` draws its own Cancel (`feedback-cancel`) instead of a toolbar item: on the
  Duo the system moved bar items to its vertical bar, and the test couldn't find Cancel.
- Sheets go through `paneSheet`: a normal sheet on the phone, and unfolded an overlay on the
  pane it came from (a form sheet would sit across the fold). `FeedbackView` and
  `FocusPicker` close through the `close` it passes. Onboarding sits in the leading pane.
- Captures: one `gh-sim all --device "iPhone Duo"` with base args
  `-ui-reset -ui-feedback-stub -ui-focus classic-rock,southern-rock,british-invasion -ui-tour`
  and one `--screen "-ui-screen <scene>"` per surface (`today`, `story`, `play`,
  `live -ui-venues-stub`, `trivia`, `tune`, `listen`; see `ScreenshotScene`). `-ui-tour` walks a
  story, Play and a round for the native recording, and is off when a scene is set.
  Never `--url`: iOS 27.1 raises an "Open in" alert. gh-sim's `--record-seconds` left the
  test-phase recording unfinished on 2026-10-27, which blocked the launch recordings.
- Store copy: never feature Which Came First? (its matchup reads as arithmetic). The trivia
  scene features classic-rock-q01 (Rumours), the tune scene "Another One Bites the Dust".
