#!/usr/bin/env python3
"""Set fields on one item by id: edit-content.py <crate> <item-id> '<json object of fields>'."""
from __future__ import annotations
import json
import pathlib
import sys

GENRES = pathlib.Path(__file__).resolve().parent.parent / "DeepCuts/Content/genres"


def main() -> int:
    crate, item_id, fields = sys.argv[1], sys.argv[2], json.loads(sys.argv[3])
    path = GENRES / f"{crate}.json"
    genre = json.loads(path.read_text())
    items = [x for k in ("questions", "songs", "stories", "covers") for x in genre.get(k, []) if x["id"] == item_id]
    if len(items) != 1:
        print(f"no single item {item_id} in {crate}", file=sys.stderr)
        return 1
    items[0].update(fields)
    path.write_text(json.dumps(genre, indent=2, ensure_ascii=False) + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
