#!/usr/bin/env python3
"""Live content for Deep Cuts (the deepcuts-content edge function), layered over the bundled crates.

  content-remote.py status                       live and retired rows per crate
  content-remote.py pull [--out FILE]            every row, as JSON
  content-remote.py merged --out DIR             bundled crates with live rows applied (what the app plays)
  content-remote.py publish FILE [--fix] [--drop-bad] [--source S] [--note N] [--dry-run]
      FILE: JSON list of {"crate", "kind": question|song|cover|story, "body"}. New items get ids
      <crate>-live-q<N> (q/s/c/t by kind) when body.id is missing. --fix lets a body.id replace an
      existing bundled or live item (a correction). Rejected unless the merged crates validate with
      no new errors (scripts/validate-content.py); --drop-bad publishes the rest instead.
  content-remote.py retire <id> [--note N]       hide one item everywhere

Installed apps pick up changes within an hour of opening. Credentials: ~/.tester_feedback
(TESTER_FEEDBACK_URL, TESTER_FEEDBACK_ADMIN_KEY); the content function sits next to tester-feedback.
"""
from __future__ import annotations

import argparse
import copy
import importlib.util
import json
import pathlib
import re
import sys
import tempfile
import urllib.request
from collections import Counter

ROOT = pathlib.Path(__file__).resolve().parent.parent
GENRES = ROOT / "DeepCuts/Content/genres"
LISTS = {"question": "questions", "song": "songs", "cover": "covers", "story": "stories"}
LETTER = {"question": "q", "song": "s", "cover": "c", "story": "t"}


def creds() -> tuple[str, str]:
    env = {}
    for line in (pathlib.Path.home() / ".tester_feedback").read_text().splitlines():
        if "=" in line and not line.startswith("#"):
            k, v = line.split("=", 1)
            env[k.strip()] = v.strip()
    url = env["TESTER_FEEDBACK_URL"].rsplit("/", 1)[0] + "/deepcuts-content"
    return url, env["TESTER_FEEDBACK_ADMIN_KEY"]


def call(method: str, query: str = "", body: dict | None = None):
    url, key = creds()
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(url + query, data=data, method=method,
                                 headers={"x-admin-key": key, "content-type": "application/json",
                                          "user-agent": "deepcuts-content/1.0"})
    with urllib.request.urlopen(req, timeout=60) as r:
        return json.loads(r.read())


def pull() -> list[dict]:
    rows, since = [], 0
    while True:
        page = call("GET", f"?since={since}")
        rows += page["items"]
        if not page["more"] or not page["items"]:
            return rows
        since = page["items"][-1]["rev"]


def bundled() -> dict[str, dict]:
    return {p.stem: json.loads(p.read_text()) for p in sorted(GENRES.glob("*.json"))}


def apply(genres: dict[str, dict], rows: list[dict]) -> dict[str, dict]:
    """Same layering as ContentLibrary.applying in the app."""
    latest = {}
    for row in sorted(rows, key=lambda r: r.get("rev", 0)):
        if row["crate"] in genres:
            latest[row["id"]] = row
    for gid, g in genres.items():
        for kind, key in LISTS.items():
            items = []
            for item in g.get(key, []):
                row = latest.get(item["id"])
                if row is None:
                    items.append(item)
                elif row["status"] == "live" and row["crate"] == gid and row["kind"] == kind:
                    items.append(row["body"])
            present = {i["id"] for i in items}
            items += [r["body"] for r in latest.values() if r["status"] == "live" and r["crate"] == gid
                      and r["kind"] == kind and r["id"] not in present]
            if items or key in g:
                g[key] = items
    return genres


def validate(genres: dict[str, dict]) -> tuple[list[str], Counter]:
    spec = importlib.util.spec_from_file_location("validate_content", ROOT / "scripts/validate-content.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    with tempfile.TemporaryDirectory() as tmp:
        for gid, g in genres.items():
            (pathlib.Path(tmp) / f"{gid}.json").write_text(json.dumps(g, indent=2, ensure_ascii=False))
        errors, _, _, ids = module.check(pathlib.Path(tmp))
    return errors, ids


def publish(path: str, fix: bool, drop_bad: bool, source: str, note: str | None, dry_run: bool) -> int:
    items = json.loads(pathlib.Path(path).read_text())
    rows = pull()
    base = apply(bundled(), rows)
    known = {i["id"] for g in base.values() for key in LISTS.values() for i in g.get(key, [])}
    known |= {r["id"] for r in rows}
    used = Counter()
    out = []
    for item in items:
        crate, kind, body = item.get("crate"), item.get("kind"), dict(item.get("body") or {})
        if crate not in base or kind not in LISTS or not body:
            print(f"error: bad item {json.dumps(item)[:120]}", file=sys.stderr)
            return 1
        if "id" not in body:
            prefix = f"{crate}-live-{LETTER[kind]}"
            taken = [int(m.group(1)) for i in known if (m := re.fullmatch(re.escape(prefix) + r"(\d+)", i))]
            used[prefix] = max([used[prefix], *taken]) + 1
            body = {"id": f"{prefix}{used[prefix]}", **body}
            known.add(body["id"])
        elif body["id"] in known and not fix:
            print(f"error: {body['id']} already exists; pass --fix to replace it", file=sys.stderr)
            return 1
        elif body["id"] not in known and fix:
            print(f"error: --fix but {body['id']} doesn't exist", file=sys.stderr)
            return 1
        out.append({"id": body["id"], "crate": crate, "kind": kind, "body": body, "status": "live",
                    "source": source, "note": note})
    before, _ = validate(copy.deepcopy(base))
    while True:
        after, _ = validate(apply(copy.deepcopy(base), [dict(r, rev=10**12 + n) for n, r in enumerate(out)]))
        new = sorted(set(after) - set(before))
        if not new:
            break
        bad = [r for r in out if any(re.search(re.escape(r["id"]) + r"\b", e) or r["body"].get("prompt", "\0").strip().lower()[:70] in e for e in new)]
        for e in new:
            print("error:", e, file=sys.stderr)
        if not drop_bad or not bad:
            print(f"rejected: {len(new)} new validation errors, nothing published", file=sys.stderr)
            return 1
        print(f"dropped {len(bad)}: {', '.join(r['id'] for r in bad)}", file=sys.stderr)
        out = [r for r in out if r not in bad]
    if not out:
        print("nothing left to publish")
        return 0
    if dry_run:
        print(f"ok: {len(out)} items would publish")
        return 0
    for i in range(0, len(out), 500):
        call("POST", body={"items": out[i:i + 500]})
    print(f"published {len(out)}: {', '.join(r['id'] for r in out[:5])}{' ...' if len(out) > 5 else ''}")
    return 0


def retire(item_id: str, note: str | None) -> int:
    rows = {r["id"]: r for r in pull()}
    row = rows.get(item_id)
    if row is None:
        for gid, g in bundled().items():
            for kind, key in LISTS.items():
                for item in g.get(key, []):
                    if item["id"] == item_id:
                        row = {"id": item_id, "crate": gid, "kind": kind, "body": item}
    if row is None:
        print(f"error: no item {item_id}", file=sys.stderr)
        return 1
    call("POST", body={"items": [{"id": item_id, "crate": row["crate"], "kind": row["kind"], "body": row["body"],
                                  "status": "retired", "source": "manual", "note": note}]})
    print(f"retired {item_id}")
    return 0


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)
    sub.add_parser("status")
    p = sub.add_parser("pull")
    p.add_argument("--out")
    p = sub.add_parser("merged")
    p.add_argument("--out", required=True)
    p = sub.add_parser("publish")
    p.add_argument("file")
    p.add_argument("--fix", action="store_true")
    p.add_argument("--drop-bad", action="store_true")
    p.add_argument("--source", default="manual")
    p.add_argument("--note")
    p.add_argument("--dry-run", action="store_true")
    p = sub.add_parser("retire")
    p.add_argument("id")
    p.add_argument("--note")
    a = ap.parse_args()

    if a.cmd == "status":
        counts = Counter((r["crate"], r["status"]) for r in pull())
        for crate in sorted({c for c, _ in counts}):
            print(f"{crate:24} live {counts[(crate, 'live')]:4}  retired {counts[(crate, 'retired')]:4}")
        return 0
    if a.cmd == "pull":
        text = json.dumps(pull(), indent=2, ensure_ascii=False)
        if a.out:
            pathlib.Path(a.out).write_text(text + "\n")
        else:
            print(text)
        return 0
    if a.cmd == "merged":
        out = pathlib.Path(a.out)
        out.mkdir(parents=True, exist_ok=True)
        for gid, g in apply(bundled(), pull()).items():
            (out / f"{gid}.json").write_text(json.dumps(g, indent=2, ensure_ascii=False) + "\n")
        return 0
    if a.cmd == "publish":
        return publish(a.file, a.fix, a.drop_bad, a.source, a.note, a.dry_run)
    return retire(a.id, a.note)


if __name__ == "__main__":
    sys.exit(main())
