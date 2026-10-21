# Genre content schema

One file per focus area: `DeepCuts/Content/genres/<id>.json`. The app bundles these
files; nothing is generated at runtime.

```json
{
  "id": "southern-rock",
  "name": "Southern Rock",
  "blurb": "One sentence, under 90 characters, that sells the genre to a fan.",
  "era": "1969-1981",
  "symbol": "guitars.fill",
  "questions": [
    {
      "id": "southern-rock-q01",
      "prompt": "Question text, under 140 characters.",
      "choices": ["Correct answer", "Wrong", "Wrong", "Wrong"],
      "answer": 0,
      "fact": "One or two sentences shown after answering. Adds a detail, does not just repeat the answer.",
      "difficulty": 1
    }
  ],
  "songs": [
    {
      "id": "southern-rock-s01",
      "title": "Free Bird",
      "artist": "Lynyrd Skynyrd",
      "year": 1973,
      "album": "(Pronounced 'Leh-'nerd 'Skin-'nerd)",
      "note": "One sentence fact about the recording."
    }
  ],
  "stories": [
    {
      "id": "southern-rock-st1",
      "title": "Short headline",
      "dek": "One-line subtitle",
      "year": 1977,
      "body": "300 to 450 words. Paragraphs separated by a blank line (\n\n).",
      "songs": ["southern-rock-s01"]
    }
  ]
}
```

Rules
- `answer` is the index of the correct choice. Spread correct positions across 0-3.
- `difficulty`: 1 = a casual fan knows it, 2 = a real fan, 3 = a deep cut.
- `year` on a song is the year of its first release as a single or on its album.
- Only facts that are settled and verifiable. No "best-selling ever" or "first ever"
  claims unless they are undisputed. Nothing about events after 2024.
- Every choice in a question is the same kind of thing (four bands, four years).
- No duplicate questions within or across files.

## Concert stories and covers

Stories may set `"kind": "concert"` for a story about one show or festival (Fillmore East
1971, Woodstock, Live Aid, The Last Waltz). The Stories tab shelves them under Concerts.
Omit `kind` for stories about records and people.

Each crate may have a `covers` list, used by the "Who Did It First?" mode (play the cover,
pick who recorded the song first) and shown on the crate page:

```json
"covers": [
  {
    "id": "classic-rock-c01",
    "title": "All Along the Watchtower",
    "artist": "The Jimi Hendrix Experience",
    "year": 1968,
    "album": "Electric Ladyland",
    "original": "Bob Dylan",
    "originalYear": 1967,
    "decoys": ["Neil Young", "Leonard Cohen", "The Byrds"],
    "note": "One or two sentences on how the cover came about or what changed."
  }
]
```

- `title`/`artist`/`year`/`album` describe the cover recording, which must be on Apple Music.
- `original` is the artist who released the song first (not just the writer, unless they
  are the same). `decoys` are three plausible, wrong originals from the same world.
  None of the decoys may have released the song before the original.
- Pick covers better known than, or as well known as, the original, so the question is a
  real surprise ("Hound Dog": Big Mama Thornton; "Respect": Otis Redding).
