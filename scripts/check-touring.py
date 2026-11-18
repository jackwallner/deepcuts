#!/usr/bin/env python3
"""Checks every act in LiveMusic.ticketmasterIDs for upcoming dates on its own Ticketmaster page.

Prints LISTED (in `touring` with dates), DROP (listed, no dates), ADD (dates, not listed) and
QUIET (no dates, not listed). Before adding an act, confirm someone who played on its hits is still
in the band; a band with nobody from the records goes in `withoutOriginalMembers` instead.

Usage: python3 scripts/check-touring.py
"""

import re
import time
import urllib.request
from pathlib import Path

SOURCE = Path(__file__).resolve().parent.parent / "Shared/Services/LiveMusic.swift"
AGENT = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 Safari/605.1.15"


def section(text: str, start: str, end: str) -> str:
    return text[text.index(start):text.index(end, text.index(start))]


def upcoming(artist_id: int) -> int | None:
    request = urllib.request.Request(f"https://www.ticketmaster.com/artist/{artist_id}", headers={"User-Agent": AGENT})
    try:
        page = urllib.request.urlopen(request, timeout=30).read().decode("utf-8", "replace")
    except OSError:
        return None
    # The first events block on an artist page is that artist's upcoming dates.
    match = re.search(r'"total":(\d+),"totalLocal"', page)
    return int(match.group(1)) if match else None


def main() -> None:
    source = SOURCE.read_text()
    ids = {name: int(i) for name, i in re.findall(r'"([^"]+)": (\d+)', section(source, "ticketmasterIDs: [String: Int] = [", "\n    ]"))}
    listed = set(re.findall(r'"([^"]+)"(?=[,\]])', section(source, "static let touring", "\n    ]")))
    for name, artist_id in sorted(ids.items()):
        count = upcoming(artist_id)
        if count is None:
            label = "ERROR"
        elif name in listed:
            label = "LISTED" if count else "DROP"
        else:
            label = "ADD" if count else "QUIET"
        print(f"{label:7} {name:28} {count if count is not None else '?'} upcoming")
        time.sleep(1)


if __name__ == "__main__":
    main()
