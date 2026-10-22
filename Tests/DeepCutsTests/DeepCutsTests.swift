import XCTest
@testable import DeepCuts

final class ContentTests: XCTestCase {
    func testBundledCratesLoadAndAreWellFormed() {
        let library = ContentLibrary.shared
        XCTAssertGreaterThanOrEqual(library.genres.count, 1)
        var ids = Set<String>()
        for genre in library.genres {
            XCTAssertGreaterThanOrEqual(genre.questions.count, 20, genre.id)
            for q in genre.questions {
                XCTAssertTrue(ids.insert(q.id).inserted, "duplicate \(q.id)")
                XCTAssertEqual(q.choices.count, 4, q.id)
                XCTAssertEqual(Set(q.choices).count, 4, q.id)
                XCTAssertTrue((0..<4).contains(q.answer), q.id)
            }
            for story in genre.stories {
                for id in story.songs { XCTAssertNotNil(library.song(id), "\(story.id) -> \(id)") }
                XCTAssertGreaterThan(story.paragraphs.count, 1, story.id)
            }
        }
    }

    func testCatalogCoversMostSongs() {
        let library = ContentLibrary.shared
        let songs = library.genres.flatMap(\.songs)
        let playable = songs.filter { library.hasPreview($0.id) }
        XCTAssertGreaterThan(Double(playable.count) / Double(max(1, songs.count)), 0.85)
    }
}

final class QuizBuilderTests: XCTestCase {
    static func song(_ id: String, _ artist: String, _ year: Int) -> Song {
        Song(id: id, title: "Song \(id)", artist: artist, year: year, album: "A", note: "n")
    }

    static func question(_ id: String, difficulty: Int, answer: Int = 2) -> Question {
        Question(id: id, prompt: "Q \(id)?", choices: ["a\(id)", "b\(id)", "c\(id)", "d\(id)"], answer: answer, fact: "f", difficulty: difficulty)
    }

    static let genre = Genre(
        id: "g", name: "G", blurb: "b", era: "e",
        questions: (1...12).map { question("q\($0)", difficulty: ($0 % 3) + 1) },
        songs: [song("s1", "A", 1970), song("s2", "B", 1972), song("s3", "C", 1975), song("s4", "D", 1979),
                song("s5", "E", 1981), song("s6", "F", 1966)],
        stories: [],
        covers: [
            CoverSong(id: "c1", title: "Hound Dog", artist: "Elvis Presley", year: 1956, album: "Single",
                      original: "Big Mama Thornton", originalYear: 1953, decoys: ["Ruth Brown", "LaVern Baker", "Etta James"], note: "n"),
            CoverSong(id: "c2", title: "Respect", artist: "Aretha Franklin", year: 1967, album: "I Never Loved a Man",
                      original: "Otis Redding", originalYear: 1965, decoys: ["Sam Cooke", "Wilson Pickett", "Solomon Burke"], note: "n"),
        ])

    static let library = ContentLibrary(
        genres: [genre],
        catalog: Dictionary(uniqueKeysWithValues: (genre.songs + genre.coverSongs.map(\.asSong)).map {
            ($0.id, CatalogEntry(trackId: 1, previewUrl: "https://p/\($0.id)", artworkUrl: nil, trackViewUrl: nil))
        }))

    let builder = QuizBuilder(library: QuizBuilderTests.library)

    func testDailyIsTenItemsAndTheSameAllDay() {
        let a = builder.daily(day: "2026-10-21", genres: [Self.genre])
        let b = builder.daily(day: "2026-10-21", genres: [Self.genre])
        let c = builder.daily(day: "2026-10-22", genres: [Self.genre])
        XCTAssertEqual(a.count, 10)
        XCTAssertEqual(a.map(\.id), b.map(\.id))
        XCTAssertEqual(a.map(\.correctIndex), b.map(\.correctIndex))
        XCTAssertNotEqual(a.map(\.id), c.map(\.id))
        XCTAssertEqual(a.filter { $0.mode == .tune }.count, 2)
        XCTAssertEqual(a.filter { $0.mode == .covers }.count, 1)
        XCTAssertEqual(a.last?.mode, .covers)
        XCTAssertEqual(a.filter { $0.mode == .firstOf }.count, 1)
        let hard = a.compactMap(\.questionID).filter { id in Self.genre.questions.first { $0.id == id }!.difficulty == 3 }
        XCTAssertLessThanOrEqual(hard.count, 1, "the daily mix holds at most one hard question")
    }

    func testCoversAskForTheOriginalArtist() {
        var rng = SeededRandom(seed: 3)
        let items = builder.covers(genres: [Self.genre], count: 6, rng: &rng)
        XCTAssertEqual(items.count, 2)
        for item in items {
            let cover = Self.genre.coverSongs.first { "cover-\($0.id)" == item.id }!
            XCTAssertEqual(item.choices[item.correctIndex].title, cover.original)
            XCTAssertEqual(item.audioSongID, cover.id)
            XCTAssertFalse(item.choices.contains { $0.title == cover.artist })
        }
        XCTAssertTrue(builder.offers(.covers, genres: [Self.genre]))
    }

    func testCoverOfTheDayIsStableAndNotTheMixCover() {
        for day in ["2026-10-21", "2026-10-22", "2026-10-23", "2026-10-24"] {
            let pick = builder.coverOfTheDay(day: day, genres: [Self.genre])
            XCTAssertNotNil(pick)
            XCTAssertEqual(pick?.cover.id, builder.coverOfTheDay(day: day, genres: [Self.genre])?.cover.id)
            let mixCover = builder.daily(day: day, genres: [Self.genre]).last { $0.mode == .covers }
            XCTAssertNotEqual(mixCover?.id, pick.map { "cover-\($0.cover.id)" }, "Today's cover must not spoil the mix")
        }
    }

    func testTriviaKeepsTheRightAnswerAfterShufflingAndRampsUp() {
        var rng = SeededRandom(seed: 7)
        let items = builder.trivia(genres: [Self.genre], count: 10, seen: [], rng: &rng)
        XCTAssertEqual(items.count, 10)
        for item in items {
            let q = Self.genre.questions.first { $0.id == item.questionID }!
            XCTAssertEqual(item.choices[item.correctIndex].title, q.choices[q.answer])
        }
        let difficulties = items.map { id in Self.genre.questions.first { $0.id == id.questionID }!.difficulty }
        XCTAssertEqual(difficulties, difficulties.sorted())
    }

    func testHardOnesAreAllDifficultyThree() {
        var rng = SeededRandom(seed: 9)
        let items = builder.round(mode: .hard, genres: [Self.genre], seen: [], rng: &rng)
        XCTAssertEqual(items.count, 4, "the fixture has four difficulty 3 questions")
        XCTAssertTrue(items.allSatisfy { id in Self.genre.questions.first { $0.id == id.questionID }!.difficulty == 3 })
        XCTAssertFalse(builder.offers(.hard, genres: [Self.genre]), "needs ten hard questions to offer the mode")
    }

    func testTriviaPrefersUnseenQuestions() {
        var rng = SeededRandom(seed: 3)
        let seen = Set((1...8).map { "q\($0)" })
        let items = builder.trivia(genres: [Self.genre], count: 4, seen: seen, rng: &rng)
        XCTAssertEqual(Set(items.compactMap(\.questionID)), ["q9", "q10", "q11", "q12"])
    }

    func testTuneDecoysAreOtherArtists() {
        var rng = SeededRandom(seed: 11)
        let items = builder.tunes(genres: [Self.genre], count: 6, rng: &rng)
        XCTAssertFalse(items.isEmpty)
        for item in items {
            let song = Self.library.song(item.audioSongID!)!
            XCTAssertEqual(item.choices[item.correctIndex].title, song.title)
            XCTAssertEqual(Set(item.choices.compactMap(\.subtitle)).count, 4)
        }
        XCTAssertEqual(Set(items.compactMap(\.audioSongID)).count, items.count)
    }

    func testWhichCameFirstPointsAtTheOlderRecord() {
        var rng = SeededRandom(seed: 5)
        let items = builder.firstOf(genres: [Self.genre], count: 3, rng: &rng)
        XCTAssertFalse(items.isEmpty)
        for item in items {
            let years = item.choices.map { Self.library.song($0.songID!)!.year }
            XCTAssertGreaterThanOrEqual(abs(years[0] - years[1]), 3, "no coin flips")
            XCTAssertEqual(years[item.correctIndex], years.min())
        }
    }
}

@MainActor
final class ProgressTests: XCTestCase {
    func tempStore() -> ProgressStore {
        ProgressStore(url: FileManager.default.temporaryDirectory.appendingPathComponent("progress-\(UUID()).json"))
    }

    func testStreakCountsBackFromTodayOrYesterday() throws {
        let store = tempStore()
        let cal = Calendar(identifier: .gregorian)
        let today = cal.date(from: DateComponents(year: 2026, month: 10, day: 21, hour: 9))!
        for offset in [1, 2, 3, 5] {
            let day = cal.date(byAdding: .day, value: -offset, to: today)!
            store.finish(spec: QuizSpec(source: .daily(day: ProgressStore.dayKey(day, calendar: cal)), mode: nil, title: "", items: []),
                         result: QuizResult(correct: 5, total: 10))
        }
        XCTAssertEqual(store.streak(today: today, calendar: cal), 3)  // today not played yet
        store.finish(spec: QuizSpec(source: .daily(day: ProgressStore.dayKey(today, calendar: cal)), mode: nil, title: "", items: []),
                     result: QuizResult(correct: 9, total: 10))
        XCTAssertEqual(store.streak(today: today, calendar: cal), 4)
    }

    func testDailyScoreIsTheFirstAttemptAndProgressPersists() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("progress-\(UUID()).json")
        let store = ProgressStore(url: url)
        let spec = QuizSpec(source: .daily(day: "2026-10-21"), mode: nil, title: "", items: [])
        store.finish(spec: spec, result: QuizResult(correct: 6, total: 10))
        store.finish(spec: spec, result: QuizResult(correct: 10, total: 10))
        store.setFocus(["classic-rock"])
        let item = QuizItem(id: "q", mode: .trivia, genreID: "classic-rock", prompt: "", choices: [], correctIndex: 0, fact: "", questionID: "q")
        store.record(item: item, correct: true)
        let reloaded = ProgressStore(url: url)
        XCTAssertEqual(reloaded.data.daily["2026-10-21"]?.correct, 6)
        XCTAssertEqual(reloaded.focus, ["classic-rock"])
        XCTAssertTrue(reloaded.data.onboarded)
        XCTAssertEqual(reloaded.tally(crate: "classic-rock").correct, 1)
        XCTAssertEqual(reloaded.data.installID, store.data.installID)
    }
}

final class OnThisDayTests: XCTestCase {
    func testKeepsMusiciansAndRanksLibraryArtistsFirst() throws {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "onthisday-10-21", withExtension: "json"))
        let moments = OnThisDay.parse(try Data(contentsOf: url), artists: ["Toto", "Grateful Dead", "Manfred Mann"])
        XCTAssertFalse(moments.isEmpty)
        XCTAssertTrue(moments.contains { $0.text.contains("Steve Lukather") })
        XCTAssertFalse(moments.contains { $0.text.contains("soprano") || $0.text.contains("operatic") })
        let connected = moments.prefix { $0.connection != nil }
        XCTAssertFalse(connected.isEmpty)
        XCTAssertTrue(moments.dropFirst(connected.count).allSatisfy { $0.connection == nil })
    }

    func testNicknamesDoNotCountAsArtists() throws {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "onthisday-10-21", withExtension: "json"))
        let moments = OnThisDay.parse(try Data(contentsOf: url), artists: ["Queen", "Otis Redding"])
        XCTAssertFalse(moments.contains { $0.connection == "Queen" }, "\"Queen of Salsa\" and \"Queen Elizabeth\" are not the band")
        XCTAssertTrue(moments.contains { $0.text.contains("Steve Cropper") && $0.connection == "Otis Redding" })
    }
}

final class FeedbackTests: XCTestCase {
    func testStatusLabels() throws {
        let json = #"[{"id":3,"created_at":"2026-10-21T17:10:33.586333+00:00","text":"x","status":"shipped","reply":"Done","build":"4"}]"#
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { d in
            let f = ISO8601DateFormatter()
            f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            return f.date(from: try d.singleValueContainer().decode(String.self))!
        }
        let items = try decoder.decode([FeedbackItem].self, from: Data(json.utf8))
        XCTAssertEqual(items[0].statusLabel, "In TestFlight build 4")
        XCTAssertTrue(items[0].isDone)
    }
}
