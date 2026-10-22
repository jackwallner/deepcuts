#!/usr/bin/env python3
"""Print a line whenever tester suggestions are waiting, for the desktop feedback dispatcher.

The dispatcher session runs this under Monitor; each line wakes it to start the
"tester-feedback-build" desktop task, which claims the oldest new row. A waiting set
is repeated every REPEAT seconds, so a start refused while another run is busy is
retried.
"""
from __future__ import annotations

import json
import pathlib
import sys
import time
import urllib.request

POLL = 60
REPEAT = 300


def new_ids() -> list[int]:
    env = dict(line.split("=", 1) for line in (pathlib.Path.home() / ".tester_feedback").read_text().splitlines()
               if "=" in line and not line.startswith("#"))
    req = urllib.request.Request(env["TESTER_FEEDBACK_URL"].strip() + "?status=new",
                                 headers={"x-admin-key": env["TESTER_FEEDBACK_ADMIN_KEY"].strip(),
                                          "user-agent": "deepcuts-feedback/1.0"})
    with urllib.request.urlopen(req, timeout=30) as r:
        return sorted(row["id"] for row in json.loads(r.read()))


def main() -> None:
    last, said = [], 0.0
    while True:
        try:
            ids = new_ids()
        except Exception as e:  # network blips: keep watching
            print(f"watch error: {e}", file=sys.stderr, flush=True)
            ids = last
        if ids and (ids != last or time.time() - said >= REPEAT):
            print(f"NEW FEEDBACK waiting: {', '.join(f'#{i}' for i in ids)}", flush=True)
            said = time.time()
        last = ids
        time.sleep(POLL)


if __name__ == "__main__":
    main()
