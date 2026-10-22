---
paths:
  - "scripts/content-remote.py"
  - "scripts/weekly/**"
  - "Shared/Services/RemoteContent.swift"
  - "Shared/Services/ContentLibrary.swift"
  - "supabase/**"
---
# Live content

Questions (and any song, cover or story) can go live without a build. Rows in the
`deepcuts_content` table (Sports Supabase project) are layered over the bundled crates by
`ContentLibrary.applying`: a row with a bundled id replaces that item, `retired` hides it, a new id
joins its crate. Unknown crates and rows that fail `RemoteItem.isSound` are ignored.

- App: `RemoteContentService` calls the `deepcuts-content` edge function (`?since=<rev>`, same app
  key as tester-feedback, URL derived from the feedback URL) when the app becomes active, at most
  hourly. Rows are cached in Application Support `live-content.json`, loaded at launch, and swapped
  in between rounds. UI tests (`-ui-reset`) use bundled content only.
- `scripts/content-remote.py`: `status`, `pull`, `merged --out DIR`, `publish FILE [--fix]
  [--drop-bad]`, `retire <id>`. Publish validates the merged crates with
  `scripts/validate-content.py` and rejects anything that adds an error. New ids are
  `<crate>-live-q<N>` so they never collide with bundled `<crate>-q<N>`.
- Weekly job: the iMac runs `scripts/weekly/run.sh` from the `deepcuts-weekly` systemd user timer
  (Sundays 03:00, installed by `scripts/weekly/install.sh`). Per crate, `claude -p --model opus`
  with web tools only writes 20 fact-checked questions (`scripts/weekly/prompt.md`), then the script
  publishes them with `--drop-bad`. They auto-publish with no human review (Jack's call,
  2026-10-22). Logs: `~/deepcuts-weekly/<date>/` on the iMac; failed crates post to #ops.
  The iMac's `~/deepcuts` is a read-only clone that pulls main each run.
- Fixing a reported question: if its id contains `-live-`, it exists only remotely: publish the
  corrected body with `--fix` (or `retire` it). If it's bundled, fix the JSON as usual and also
  publish the corrected body with `--fix` so installed builds get it within the hour.
