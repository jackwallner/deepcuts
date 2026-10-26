# Deep Cuts Project Guide

Music trivia and music history by focus area ("crates": Classic Rock, Southern Rock,
British Invasion, Heavy Metal, ...). Daily 10-question mix (at most one hard question, ends on a
cover), Trivia, The Hard Ones (difficulty 3 only), Name That Tune with Apple Music previews,
Who Did It First? (covers), Which Came First?, long-form and concert stories, and Wikipedia's
On This Day.
Idea from Jack's dad (John Wallner, `wallners@gmail.com`), who is the first tester.
XcodeGen project/scheme: `DeepCuts`, sim lease owner `deepcuts`.
App Store name **Deep Cuts: Music Trivia**, ASC app ID `6825448110`, bundle `com.jackwallner.deepcuts`.

## Tech Stack
- Swift 6 / SwiftUI (strict concurrency), iOS 17+, iPhone only. No packages, no paywall.
- Content is bundled JSON (`DeepCuts/Content/`), progress is one JSON file in Application Support.
- Network, all optional: iTunes lookup (preview refresh), Wikipedia On This Day, tester feedback,
  live content (new and corrected questions from Supabase, weekly; see `.claude/rules/live-content.md`).

## Layout
- `Shared/Models`: `Content.swift` (Genre, Question, Song, Story, CatalogEntry), `Quiz.swift`
- `Shared/Services`: `ContentLibrary` (loads `Content/genres/*.json` + `catalog.json`),
  `QuizBuilder` (rounds; daily mix is seeded by date + crates), `ProgressStore`,
  `PreviewPlayer` (AVPlayer, 30s previews), `OnThisDayService`, `FeedbackService`, `RemoteContent`
- `DeepCuts/`: `DeepCutsApp` (launch args below), `AppModel` (environment object),
  `Views/` (Theme, Components, Onboarding/FocusPicker, Today, Play/Crate, Quiz/Result, Stories, You, Feedback)
- `DeepCuts/Content/genres/<id>.json`: one crate each, schema in `project-docs/content/SCHEMA.md`.
  `DeepCuts/Content/catalog.json`: song id -> Apple Music track, written by `scripts/resolve-catalog.py`.
- `docs/`: marketing site (GitHub Pages, `main` /docs), mirrored to `https://jackwallner.com/ios/deepcuts/`
  by `.github/workflows/sync-landing-page.yml`. Format: `~/ios/landing-pages/README.md`.
  Working notes go in `project-docs/`.
- `supabase/`: `tester_feedback` and `deepcuts_content` tables, `tester-feedback` and
  `deepcuts-content` edge functions (in the Sports project).

## Rules that hold everywhere
- **Accuracy first.** A wrong answer key ruins a trivia app for this audience. Every new or edited
  question, song year and story must be fact-checked; when unsure, cut it. No em dashes in content.
- After editing content: `python3 scripts/validate-content.py` (also gates `scripts/testflight.sh`),
  and for new songs `python3 scripts/resolve-catalog.py` (about 20 lookups a minute) then review its
  NO MATCH / YEAR lines. `scripts/edit-content.py <crate> <id> '<json>'` sets fields on one item
  without reformatting the file. A new crate also needs an entry in `ContentLibrary.order` and
  `Theme.crate`/`Theme.crateSymbol`.
- Design: warm paper, ink, one record-label red (`Theme`), New York serif headlines, real album art.
  No gradients, no emoji icons, nothing that looks generated. Keep it simple.
- `Config/App.xcconfig` optionally includes `Config/Secrets.xcconfig` (not committed), which holds
  the feedback URL and app key; without it the app builds (gh-sim works) but can't send suggestions. Values live in `~/.tester_feedback`.
- Tests: `xcodebuild test -project DeepCuts.xcodeproj -scheme DeepCuts -destination id=<leased UDID>`.
  UI tests launch with `-ui-reset -ui-feedback-stub` (never send real feedback from a test: a real
  suggestion starts a build session). `-ui-focus classic-rock,southern-rock` skips onboarding.

## Target users (check every change against them)
- **John (Jack's dad), 60s**: grew up on '60s/'70s rock, knows the records cold, reads on an iPhone
  with larger text. Wants real stories and questions a fan respects, no fluff, nothing wrong.
- **Casual listener**: picks Pop or the '80s, plays the daily mix over coffee, wants it quick and fun.
- **Genre specialist** (metal, Southern rock, Motown): wants depth in one crate, not trivia that any
  radio listener knows.

## Tester feedback loop
The You tab and Today screen have "Suggest a change", and every answer card has "Report a problem",
which attaches the question id, prompt and answer as `screen` context. It posts to the `tester-feedback` function;
the ops poller on the MacBook Pro (`~/ios/ops/ops/feedback.py`) sees it within a minute, opens an
#ops thread and starts an Opus session on the iMac in this repo (Remote Control, so it shows in Jack's
Claude app). That session implements it with no approval step (never `needs_jack`), tests on `gh-sim`,
commits, pushes, runs `./scripts/testflight.sh`, and reports back with `python3 scripts/feedback.py status <id> shipped --build N --reply "..."`, which the
tester sees under You > Suggestions. `scripts/feedback.py list` shows pending ones.
A wrong question also gets its fix published live (`scripts/content-remote.py publish --fix`), and a
`-live-` id exists only remotely; see `.claude/rules/live-content.md`.

## Release
- TestFlight: `./scripts/testflight.sh` (validates content first). Internal group **Family**
  (Jack, John, Emi, Michael, Scott) gets every build; no Beta App Review.
  `scripts/asc-testers.py` (hourly `deepcuts-testers.timer` on the iMac) adds accepted invitees and keeps
  non-admin testers locked to Deep Cuts only.
- Not submitted to the App Store yet; that needs Jack (listing, privacy label, previews licensing review).

## Area rules (`.claude/rules/`)
- `live-content.md`: live questions, `content-remote.py`, the weekly iMac job.

---
Shared iOS conventions (build, simulator, release/TestFlight, ASC key, signing, gotchas):
the global agent rules + the `ios-dev` skill.
