# iPhone Duo: layout review and capture receipt (2026-10-27)

## Pane pairing

Unfolded, the tab bar's open tab (Today by default, or Play, Live, You) fills the leading pane
and Stories becomes a reading pane on the trailing side. Deep Cuts sells on two things, the daily
game and the long-form liner notes; this pairing shows both at once, and any story link (Today's
Liner Notes, a crate's Stories, the shelf) opens beside the screen it came from. A round splits as
a drill beside its progress: the question on the leading pane, the answer, Next and the round so
far on the trailing pane. Folded, the app is the phone app.

Panes meet the fold edges from `reservedRegions(.division)`, else split evenly (unit-tested in
`UnfoldedSplitTests`). Each pane is about 472 pt wide on the 951 pt inner display.

## Evidence

Final capture run (source: this commit before the rebase onto origin/main, which only brought in
unrelated icon, Live and build-number commits):
`deepcuts@20261027-141656-2c78-claude-mbpro28c4f-1027-163033-30710` (GitHub run 40602607149),
iPhone Duo, iOS 27.1. Build ok, tests passed 40 of 40, no crash, app running at the end.
Inner captures 2853x2007 (landscape, as captured), outer 1398x2034. Native recordings
`videos/inner.mp4` and `videos/outer.mp4` (record60: native 60 fps proven in motion windows; the
gaps are the relaunches between scenes). The base launch runs `-ui-tour`, so the first seconds show
a story opening in the pane, Play, and a round with its sheet.

## Store set (inner, two panes) with proposed headers

| File (`shots/`) | Pairing | Header |
| --- | --- | --- |
| `screen1-ui-screen-today-inner.png` | Today's Mix beside the Stories shelf | Ten questions a day from the records you love |
| `screen5-ui-screen-trivia-inner.png` | Rumours question beside the answer and the round | Get the story behind every answer |
| `screen6-ui-screen-tune-inner.png` | Name That Tune beside the answer and the round | Name the song from a short clip |
| `screen2-ui-screen-story-inner.png` | Today beside The Last Waltz | Read the night The Band said goodbye |
| `screen3-ui-screen-play-inner.png` | Play's ways to play beside The Making of Rumours | Play your crates five different ways |
| `screen4-ui-screen-live-ui-venues-stub-inner.png` | Live beside the Stories shelf | See which of your artists still tour |

Outer (folded): `screen1-ui-screen-today-outer.png`, header "Today's Mix fits the folded phone too"
(use only if the set needs a folded frame).

Not for the store: `screen7-ui-screen-listen-*` (the runner's simulator can't play Apple Music
previews, so it shows the "clip didn't load" state), `launch-*` (mid-tour).

## Self-review against the defect list

- Tab bar over rows: the bar floats inside the leading pane; paper with a short fade sits under it
  and scroll content gets matching bottom margin. Clean in today, play and live.
- Two navigation styles: one bottom tab bar on every tab; the reading pane has only a back link.
- Placeholder content: every surface is seeded (bundled crates, sample venues, seeded rounds).
- Status bar over content: the inner status bar sits in the system's trailing strip, clear of
  both panes.
- Content under the fold, sliced glyphs, sheets over the screen: none in the final set.

## Defects found and fixed

1. Rows showed through the floating tab bar (run 1). The bar isn't in the content's bottom safe
   area unfolded, so a safe-area backdrop missed it (run 2). Fix: `tabBarBackdrop`, a fixed
   paper band measured from the display edge plus matching `contentMargins`.
2. The round auto-scrolled to its answer in a 669 pt pane, slicing the prompt under the top bar
   and scrolling the record away (run 1). Fix: unfolded, the answer and Next live at the top of
   the round's sheet and the question pane never scrolls.
3. Story text and rows were cut mid-line at the display's bottom edge (run 1). Fix:
   `paneBottomFade` on the trailing panes and the question pane.
4. The round sheet's header was half scrolled off on open (run 1). Fix: it scrolls only when
   the question changes.
5. UI tests failed on the Duo (run 1): iOS 27.1 shows the folded tab bar as a vertical bar, so
   `app.tabBars` was empty; the feedback sheet's toolbar Cancel and the back button moved into
   that bar too. Fix: `tab(app, name)` and `back(app)` helpers, and an in-content Cancel
   (`feedback-cancel`), which also keeps it inside an unfolded pane.
6. My first `tab` helper was `@MainActor` and broke the UI-test build (run 2). Removed.
7. `tab` tapped before the bar appeared after onboarding, and Tour's back tap missed the
   vertical bar's `BackButton` (run 3). Fixed in `tab` and `back`.
8. The round sheet read "0 of 0 right" before the first answer (recording review). Hidden until
   there is an answer.

## gh-sim runs

1. `...-151200-19436` (GH 40592950741): build ok, 33 passed / 7 failed, captures. Recording
   broken by the tool: the test-phase recording never finalized and blocked the launch ones.
2. `...-154118-11720` (GH 40596711525): UI-test build failed (defect 6), captures.
3. `...-155826-8810` (GH 40598794053): 38 passed / 2 failed (defect 7), captures, recordings ok.
4. `...-163033-30710` (GH 40602607149): ok, 40 passed, captures and recordings. Final Duo evidence.
5. `...-165416-24035` (GH 40605280887): iPhone 17 Pro Max, phone set and tests on the final code.

## iPhone 6.9 inch source captures (run 5, 1320x2868, 40 of 40 tests passed)

In `~/.gh-sim/results/deepcuts@20261027-141656-2c78-claude-mbpro28c4f-1027-165416-24035/shots/`
on jmbp, in store order: `screen1-ui-screen-today.png` (Today's Mix), `screen2-ui-screen-trivia.png`
(Rumours answer and its fact), `screen4-ui-screen-tune.png` (Name That Tune),
`screen5-ui-screen-story.png` (The Last Waltz), `screen6-ui-screen-play.png` (Play and crates),
`screen7-ui-screen-live-ui-venues-stub.png` (Live). Same headers as the Duo table. Skip
`screen3-ui-screen-listen.png` (no preview audio on the runner). The runner's clock is UTC, so
Today reads Wednesday, October 28.
