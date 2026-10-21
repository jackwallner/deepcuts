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
