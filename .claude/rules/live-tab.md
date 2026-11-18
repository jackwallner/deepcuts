---
paths:
  - "Shared/Services/LiveMusic.swift"
  - "DeepCuts/Views/LiveView.swift"
  - "scripts/check-touring.py"
---
# Live tab: Your Artists Live

- An act is listed only when (1) it has dates on sale on its own Ticketmaster artist page and
  (2) someone who played on its hits is still in the band. Feedback #6, #18 (John: "should not
  include tribute bands").
- Never link a Ticketmaster name search: it mixes in tribute acts ("Devo" returns Devolucion,
  "AC/DC" only tributes). Every listed act needs an id in `LiveMusic.ticketmasterIDs`.
- Bands touring with nobody from the records go in `LiveMusic.withoutOriginalMembers`, never in
  `touring` (as of 2026-11-18: Lynyrd Skynyrd, no founding member since Gary Rossington died in 2023;
  Molly Hatchet, all originals dead; Atlanta Rhythm Section, only the 1972 debut's singer).
- Refresh: `python3 scripts/check-touring.py` prints DROP (listed, no dates) and ADD (dates, not
  listed). Fact-check the lineup before adding an act. Ticketmaster's `total` before `totalLocal`
  is the artist's upcoming count; pages are fetchable with a desktop Safari user agent.
