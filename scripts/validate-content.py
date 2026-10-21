#!/usr/bin/env python3
"""Check every crate file before it ships. Exit 1 on any error. Run by scripts/testflight.sh."""
from __future__ import annotations

import json
import pathlib
import sys
from collections import Counter

ROOT = pathlib.Path(__file__).resolve().parent.parent
GENRES = ROOT / "DeepCuts/Content/genres"
CATALOG = ROOT / "DeepCuts/Content/catalog.json"


def main() -> int:
    errors, warnings = [], []
    catalog = json.loads(CATALOG.read_text()) if CATALOG.exists() else {}
    ids, prompts = Counter(), Counter()
    files = sorted(GENRES.glob("*.json"))
    if not files:
        errors.append("no genre files")
    for path in files:
        raw = path.read_text()
        if "\u2014" in raw:
            errors.append(f"{path.name}: contains an em dash")
        try:
            g = json.loads(raw)
        except ValueError as e:
            errors.append(f"{path.name}: invalid JSON: {e}")
            continue
        gid = g.get("id")
        if gid != path.stem:
            errors.append(f"{path.name}: id {gid!r} does not match the filename")
        for key in ("name", "blurb", "era"):
            if not g.get(key):
                errors.append(f"{gid}: missing {key}")
        qs, songs, stories = g.get("questions", []), g.get("songs", []), g.get("stories", [])
        if len(qs) < 20:
            errors.append(f"{gid}: only {len(qs)} questions")
        for q in qs:
            ids[q["id"]] += 1
            prompts[q["prompt"].strip().lower()] += 1
            c = q.get("choices", [])
            if len(c) != 4 or len({x.strip().lower() for x in c}) != 4:
                errors.append(f"{q['id']}: needs 4 distinct choices")
            if q.get("answer") not in range(4):
                errors.append(f"{q['id']}: answer out of range")
            if q.get("difficulty") not in (1, 2, 3):
                errors.append(f"{q['id']}: difficulty must be 1-3")
            if not q.get("fact"):
                errors.append(f"{q['id']}: missing fact")
        spread = Counter(q.get("answer") for q in qs)
        if qs and max(spread.values()) > len(qs) * 0.45:
            warnings.append(f"{gid}: answer positions lopsided {dict(spread)}")
        song_ids = set()
        for s in songs:
            ids[s["id"]] += 1
            song_ids.add(s["id"])
            if not (1900 <= s.get("year", 0) <= 2024):
                errors.append(f"{s['id']}: year {s.get('year')}")
        playable = [s for s in songs if catalog.get(s["id"], {}).get("previewUrl")]
        if catalog and len({s["artist"] for s in playable}) < 4:
            errors.append(f"{gid}: fewer than 4 artists with previews; Name That Tune can't build a round")
        if catalog and len(playable) < len(songs):
            warnings.append(f"{gid}: {len(songs) - len(playable)} songs without a preview")
        for st in stories:
            ids[st["id"]] += 1
            words = len(st.get("body", "").split())
            if words < 200:
                errors.append(f"{st['id']}: story is only {words} words")
            for sid in st.get("songs", []):
                if sid not in song_ids:
                    errors.append(f"{st['id']}: unknown song {sid}")
    errors += [f"duplicate id {k}" for k, n in ids.items() if n > 1]
    errors += [f"duplicate question: {k[:70]}" for k, n in prompts.items() if n > 1]
    for w in warnings:
        print("warning:", w)
    for e in errors:
        print("error:", e)
    print(f"{len(files)} crates, {sum(1 for k in ids if '-q' in k)} questions checked, {len(errors)} errors")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
