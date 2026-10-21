#!/usr/bin/env python3
"""Match every song in DeepCuts/Content/genres to its Apple Music track (iTunes Search API).

Writes DeepCuts/Content/catalog.json (song id -> trackId, previewUrl, artworkUrl,
trackViewUrl) and prints songs it could not match or whose Apple Music release is
older than the year in our content (which means our year is probably wrong).
Already-matched songs are skipped unless --refresh. The API allows ~20 calls/minute.
"""
from __future__ import annotations

import argparse
import json
import pathlib
import re
import sys
import time
import urllib.parse
import urllib.request

ROOT = pathlib.Path(__file__).resolve().parent.parent
GENRES = ROOT / "DeepCuts/Content/genres"
CATALOG = ROOT / "DeepCuts/Content/catalog.json"
PAUSE = 3.2


def norm(s: str) -> str:
    s = s.lower().replace("&", "and")
    s = re.sub(r"\(.*?\)|\[.*?\]", "", s)
    s = re.split(r" - (?:\d{4} )?(?:remaster|remastered|mono|stereo|single|live|version|edit|radio)", s)[0]
    s = re.sub(r"[^a-z0-9 ]", "", s)
    s = re.sub(r"^the ", "", s.strip())
    return re.sub(r"\s+", " ", s).strip()


def search(term: str) -> list[dict]:
    url = "https://itunes.apple.com/search?" + urllib.parse.urlencode(
        {"term": term, "entity": "song", "limit": 25, "country": "US"})
    for attempt in range(4):
        try:
            with urllib.request.urlopen(urllib.request.Request(url, headers={"User-Agent": "deepcuts/1.0"}), timeout=30) as r:
                return json.loads(r.read()).get("results", [])
        except Exception as e:  # 403/429 when rate limited
            time.sleep(20 * (attempt + 1))
            last = e
    print(f"  search failed: {term}: {last}", file=sys.stderr)
    return []


def best(song: dict, results: list[dict]) -> dict | None:
    title, artist = norm(song["title"]), norm(song["artist"])
    ok = []
    for r in results:
        if r.get("kind") != "song" or not r.get("previewUrl"):
            continue
        a, t = norm(r.get("artistName", "")), norm(r.get("trackName", ""))
        if not (artist in a or a in artist) or not a:
            continue
        if t != title and not t.startswith(title + " "):
            continue
        name = (r.get("trackName", "") + " " + r.get("collectionName", "")).lower()
        live = "live" in name and "live" not in song["title"].lower()
        compilation = r.get("collectionArtistName") not in (None, r.get("artistName"))
        karaoke = any(w in name for w in ("karaoke", "tribute", "cover", "re-recorded", "rerecorded"))
        if karaoke:
            continue
        # Prefer the original album over hits packages, for the right artwork.
        album = norm(song.get("album", ""))
        collection = norm(r.get("collectionName", ""))
        on_album = bool(album) and (collection == album or collection.startswith(album + " "))
        hits = any(w in collection for w in ("hits", "best of", "essential", "greatest", "collection", "anthology", "gold"))
        ok.append((live, not on_album, hits, compilation, t != title, r.get("releaseDate", "9999"), r))
    ok.sort(key=lambda x: x[:6])
    return ok[0][6] if ok else None


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--refresh", action="store_true")
    ap.add_argument("--only", help="genre id")
    a = ap.parse_args()
    catalog = json.loads(CATALOG.read_text()) if CATALOG.exists() else {}
    problems = []
    for path in sorted(GENRES.glob("*.json")):
        genre = json.loads(path.read_text())
        if a.only and genre["id"] != a.only:
            continue
        for song in genre["songs"]:
            key = f"{song['title']}|{song['artist']}"
            if catalog.get(song["id"], {}).get("key") == key and not a.refresh:
                continue
            hit = best(song, search(f"{song['title']} {song['artist']} {song['album']}"))
            time.sleep(PAUSE)
            if not hit:
                hit = best(song, search(f"{song['title']} {song['artist']}"))
                time.sleep(PAUSE)
            if not hit:
                hit = best(song, search(song["title"]))
                time.sleep(PAUSE)
            if not hit:
                problems.append(f"NO MATCH  {song['id']}: {song['title']} / {song['artist']}")
                catalog.pop(song["id"], None)
                continue
            catalog[song["id"]] = {
                "key": key,
                "trackId": hit["trackId"],
                "previewUrl": hit.get("previewUrl"),
                "artworkUrl": (hit.get("artworkUrl100") or "").replace("100x100bb", "600x600bb") or None,
                "trackViewUrl": hit.get("trackViewUrl"),
            }
            year = int((hit.get("releaseDate") or "9999")[:4])
            if year < song["year"]:
                problems.append(f"YEAR      {song['id']}: ours {song['year']}, Apple Music {year} "
                                f"({hit.get('collectionName')})")
            print(f"ok {song['id']}: {hit.get('trackName')} / {hit.get('artistName')} ({year})", flush=True)
            CATALOG.write_text(json.dumps(catalog, indent=1, sort_keys=True) + "\n")
    known = {s["id"] for p in GENRES.glob("*.json") for s in json.loads(p.read_text())["songs"]}
    catalog = {k: v for k, v in catalog.items() if k in known}
    CATALOG.write_text(json.dumps(catalog, indent=1, sort_keys=True) + "\n")
    print("\n".join(problems) or "no problems")
    return 0


if __name__ == "__main__":
    sys.exit(main())
