import Foundation

/// Deterministic generator so the daily mix is the same all day on every device.
struct SeededRandom: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) { state = seed &+ 0x9E37_79B9_7F4A_7C15 }

    init(string: String) {
        var hash: UInt64 = 0xCBF2_9CE4_8422_2325  // FNV-1a
        for byte in string.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01B3
        }
        self.init(seed: hash)
    }

    mutating func next() -> UInt64 {  // SplitMix64
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

struct QuizBuilder {
    let library: ContentLibrary

    static let triviaCount = 10
    static let tuneCount = 6
    static let firstOfCount = 8
    static let coversCount = 6

    // MARK: Rounds

    func round(mode: QuizMode, genres: [Genre], seen: Set<String>, rng: inout some RandomNumberGenerator) -> [QuizItem] {
        switch mode {
        case .trivia: trivia(genres: genres, count: Self.triviaCount, seen: seen, rng: &rng)
        case .hard: trivia(genres: genres, count: Self.triviaCount, seen: seen, minDifficulty: 3, rng: &rng)
        case .tune: tunes(genres: genres, count: Self.tuneCount, rng: &rng)
        case .covers: covers(genres: genres, count: Self.coversCount, rng: &rng)
        case .firstOf: firstOf(genres: genres, count: Self.firstOfCount, rng: &rng)
        }
    }

    /// Whether a mode can build a round from these crates.
    func offers(_ mode: QuizMode, genres: [Genre]) -> Bool {
        switch mode {
        case .covers: genres.contains { $0.coverSongs.contains { library.hasPreview($0.id) } }
        case .hard: genres.flatMap(\.questions).filter { $0.difficulty >= 3 }.count >= Self.triviaCount
        default: true
        }
    }

    /// Today's mix: 2 clips, 1 matchup, trivia with at most one hard question, and a cover to finish.
    func daily(day: String, genres: [Genre], seen: Set<String> = []) -> [QuizItem] {
        var rng = SeededRandom(string: "daily-\(day)-\(genres.map(\.id).sorted().joined(separator: ","))")
        let clips = tunes(genres: genres, count: 2, rng: &rng)
        let matchup = firstOf(genres: genres, count: 1, rng: &rng)
        let cover = covers(genres: genres, count: 1, rng: &rng)
        // Crates without clips, covers or matchups still get a full ten.
        var items = trivia(genres: genres, count: 10 - clips.count - matchup.count - cover.count,
                           seen: seen, maxHard: 1, rng: &rng)
        for (offset, clip) in clips.enumerated() {
            items.insert(clip, at: min(items.count, 2 + offset * 4))
        }
        items.insert(contentsOf: matchup, at: min(items.count, 4))
        items.append(contentsOf: cover)
        return items
    }

    /// One playable cover to feature on Today, never the one that closes today's mix.
    func coverOfTheDay(day: String, genres: [Genre]) -> (cover: CoverSong, genre: Genre)? {
        let inMix = Set(daily(day: day, genres: genres).map(\.id))
        let pool = genres.flatMap { genre in
            genre.coverSongs.filter { library.hasPreview($0.id) }.map { (cover: $0, genre: genre) }
        }
        let fresh = pool.filter { !inMix.contains("cover-\($0.cover.id)") }
        let choices = fresh.isEmpty ? pool : fresh
        guard !choices.isEmpty else { return nil }
        var rng = SeededRandom(string: "cover-\(day)")
        return choices[Int(rng.next() % UInt64(choices.count))]
    }

    // MARK: Item kinds

    /// Unseen questions first, spread across crates, ordered easy to hard, with at most `maxHard` at difficulty 3.
    func trivia(genres: [Genre], count: Int, seen: Set<String>, maxHard: Int = .max, minDifficulty: Int = 1,
                rng: inout some RandomNumberGenerator) -> [QuizItem] {
        var pools = genres.map { genre in
            let questions = genre.questions.filter { $0.difficulty >= minDifficulty }
            let fresh = questions.filter { !seen.contains($0.id) }.shuffled(using: &rng)
            let old = questions.filter { seen.contains($0.id) }.shuffled(using: &rng)
            return (genre, fresh + old)
        }.shuffled(using: &rng)
        var picked: [(Genre, Question)] = []
        var hard = 0
        func allowed(_ q: Question) -> Bool { q.difficulty < 3 || hard < maxHard }
        while picked.count < count, pools.contains(where: { $0.1.contains(where: allowed) }) {
            for index in pools.indices where picked.count < count {
                guard let i = pools[index].1.firstIndex(where: allowed) else { continue }
                let question = pools[index].1.remove(at: i)
                if question.difficulty >= 3 { hard += 1 }
                picked.append((pools[index].0, question))
            }
        }
        return picked
            .sorted { $0.1.difficulty < $1.1.difficulty }
            .map { genre, question in item(for: question, genre: genre, rng: &rng) }
    }

    func item(for question: Question, genre: Genre, rng: inout some RandomNumberGenerator) -> QuizItem {
        let order = Array(question.choices.indices).shuffled(using: &rng)
        return QuizItem(
            id: question.id, mode: .trivia, genreID: genre.id, prompt: question.prompt,
            choices: order.map { Choice(title: question.choices[$0]) },
            correctIndex: order.firstIndex(of: question.answer) ?? 0,
            fact: question.fact, questionID: question.id)
    }

    /// Clips with a preview, answered from four songs by different artists in the same crate.
    func tunes(genres: [Genre], count: Int, rng: inout some RandomNumberGenerator) -> [QuizItem] {
        let playable = genres.flatMap { genre in
            genre.songs.filter { library.hasPreview($0.id) }.map { (genre, $0) }
        }.shuffled(using: &rng)
        var items: [QuizItem] = []
        var usedArtists: Set<String> = []
        for (genre, song) in playable where items.count < count && !usedArtists.contains(song.artist) {
            let decoys = genre.songs.filter { $0.artist != song.artist && $0.title != song.title }
                .shuffled(using: &rng)
                .reduce(into: [Song]()) { list, candidate in
                    if list.count < 3, !list.contains(where: { $0.artist == candidate.artist }) { list.append(candidate) }
                }
            guard decoys.count == 3 else { continue }
            usedArtists.insert(song.artist)
            let options = ([song] + decoys).shuffled(using: &rng)
            items.append(QuizItem(
                id: "tune-\(song.id)", mode: .tune, genreID: genre.id, prompt: "Name that tune",
                choices: options.map { Choice(title: $0.title, subtitle: $0.artist) },
                correctIndex: options.firstIndex(of: song) ?? 0,
                fact: "\(song.artist), \(song.year). \(song.note)",
                audioSongID: song.id))
        }
        return items
    }

    /// Play a famous cover; pick who released the song first.
    func covers(genres: [Genre], count: Int, rng: inout some RandomNumberGenerator) -> [QuizItem] {
        let playable = genres.flatMap { genre in
            genre.coverSongs.filter { library.hasPreview($0.id) && $0.decoys.count >= 3 }.map { (genre, $0) }
        }.shuffled(using: &rng)
        return playable.prefix(count).map { genre, cover in
            let options = ([cover.original] + cover.decoys.prefix(3)).shuffled(using: &rng)
            return QuizItem(
                id: "cover-\(cover.id)", mode: .covers, genreID: genre.id,
                prompt: "\(cover.artist) had a hit with \"\(cover.title)\" in \(cover.year). Who recorded it first?",
                choices: options.map { Choice(title: $0) },
                correctIndex: options.firstIndex(of: cover.original) ?? 0,
                fact: cover.originNote,
                audioSongID: cover.id)
        }
    }

    /// Two records from the same crate a few years apart. Pick the one released first.
    func firstOf(genres: [Genre], count: Int, rng: inout some RandomNumberGenerator) -> [QuizItem] {
        var items: [QuizItem] = []
        var used: Set<String> = []
        let crates = genres.filter { $0.songs.count >= 2 }
        guard !crates.isEmpty else { return [] }
        var attempts = 0
        while items.count < count, attempts < count * 20 {
            attempts += 1
            let genre = crates.randomElement(using: &rng)!
            let songs = genre.songs.filter { !used.contains($0.id) }.shuffled(using: &rng)
            guard let a = songs.first,
                  let b = songs.dropFirst().first(where: { abs($0.year - a.year) >= 3 && abs($0.year - a.year) <= 12 && $0.artist != a.artist })
            else { continue }
            used.formUnion([a.id, b.id])
            let pair = [a, b].shuffled(using: &rng)
            let older = pair[0].year < pair[1].year ? 0 : 1
            let gap = abs(a.year - b.year)
            items.append(QuizItem(
                id: "first-\(a.id)-\(b.id)", mode: .firstOf, genreID: genre.id, prompt: "Which came first?",
                choices: pair.map { Choice(title: $0.title, subtitle: $0.artist, songID: $0.id) },
                correctIndex: older,
                fact: "\"\(pair[older].title)\" (\(pair[older].year)) came out \(gap) years before \"\(pair[1 - older].title)\" (\(pair[1 - older].year))."))
        }
        return items
    }
}
