import CoreLocation
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

    /// Feedback #8: a file from an older build, with no settings saved, still loads.
    func testOldProgressFileLoadsWithDefaultSettings() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("progress-\(UUID()).json")
        try Data(#"{"installID":"abc","onboarded":true,"focus":["classic-rock"],"answered":{"q":true}}"#.utf8).write(to: url)
        let store = ProgressStore(url: url)
        XCTAssertEqual(store.data.installID, "abc")
        XCTAssertEqual(store.focus, ["classic-rock"])
        XCTAssertEqual(store.data.answered["q"], true)
        XCTAssertEqual(store.todayOrder, TodaySection.allCases)
        XCTAssertEqual(store.venueMiles, 25)
    }

    func testTodayOrderAndDistancePersistAndRepair() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("progress-\(UUID()).json")
        let store = ProgressStore(url: url)
        store.setTodayOrder([.dailyMix, .onThisDay])
        store.setVenueMiles(100)
        let reloaded = ProgressStore(url: url)
        XCTAssertEqual(reloaded.todayOrder, [.dailyMix, .onThisDay, .linerNotes, .covered])
        XCTAssertEqual(reloaded.venueMiles, 100)
        reloaded.setVenueMiles(7)
        XCTAssertEqual(reloaded.venueMiles, 25, "only offered distances")
        reloaded.setVenueCity("  Seattle, WA ")
        XCTAssertEqual(ProgressStore(url: url).venueCity, "Seattle, WA")
        reloaded.setVenueCity(" ")
        XCTAssertNil(ProgressStore(url: url).venueCity)
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

    func testCommonWordBandsDoNotCountAsArtists() throws {
        let json = #"{"births":[{"text":"Ellie Greenwich, American singer-songwriter","year":1940,"pages":[{"description":"American singer-songwriter","extract":"She wrote \"Then He Kissed Me\" and songs about Love with Jeff Barry."}]}]}"#
        let moments = OnThisDay.parse(Data(json.utf8), artists: ["Love", "Spirit", "Jeff Barry"])
        XCTAssertEqual(moments.first?.connection, "Jeff Barry")
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

final class LiveContentTests: XCTestCase {
    static func genre(_ id: String, questions: [Question]) -> Genre {
        Genre(id: id, name: id, blurb: "b", era: "1960-1970", questions: questions, songs: [], stories: [], covers: nil)
    }

    static func row(_ q: Question, crate: String, status: String = "live", rev: Int) -> RemoteItem {
        RemoteItem(id: q.id, crate: crate, kind: "question", status: status, rev: rev, payload: .question(q))
    }

    func testRowsFixRetireAndAddQuestions() {
        let q = QuizBuilderTests.question
        let library = ContentLibrary(genres: [Self.genre("rock", questions: [q("r1", 1, 2), q("r2", 1, 2), q("r3", 1, 2)]),
                                              Self.genre("soul", questions: [q("s1", 1, 2)])], catalog: [:])
        let fixed = Question(id: "r1", prompt: "Fixed?", choices: ["a", "b", "c", "d"], answer: 0, fact: "f", difficulty: 2)
        let merged = library.applying([
            Self.row(fixed, crate: "rock", rev: 1),
            Self.row(q("r2", 1, 2), crate: "rock", status: "retired", rev: 2),
            Self.row(q("r9", 1, 2), crate: "rock", rev: 3),
            Self.row(q("x1", 1, 2), crate: "jazz", rev: 4),
        ])
        let rock = merged.genre("rock")!.questions
        XCTAssertEqual(rock.map(\.id), ["r1", "r3", "r9"])
        XCTAssertEqual(rock.first?.prompt, "Fixed?")
        XCTAssertEqual(merged.genre("soul")!.questions.map(\.id), ["s1"])
        XCTAssertNil(merged.genre("jazz"))
    }

    func testBrokenBodiesAreIgnoredNotApplied() throws {
        let raw = """
        {"items": [
          {"id": "rock-q1", "crate": "rock", "kind": "question", "status": "live", "rev": 5,
           "body": {"id": "rock-q1", "prompt": "Bad?", "choices": ["a", "b"], "answer": 0, "fact": "f", "difficulty": 1}},
          {"id": "rock-q2", "crate": "rock", "kind": "question", "status": "live", "rev": 6,
           "body": {"id": "rock-q2", "prompt": "Good?", "choices": ["a", "b", "c", "d"], "answer": 3, "fact": "f", "difficulty": 3}}
        ]}
        """
        struct Page: Decodable { let items: [RemoteItem] }
        let rows = try JSONDecoder().decode(Page.self, from: Data(raw.utf8)).items
        XCTAssertNil(rows[0].payload)
        XCTAssertNotNil(rows[1].payload)
        let q = QuizBuilderTests.question
        let library = ContentLibrary(genres: [Self.genre("rock", questions: [q("rock-q1", 1, 2)])], catalog: [:])
        XCTAssertEqual(library.applying(rows).genre("rock")!.questions.map(\.prompt), ["Q rock-q1?", "Good?"])

        var cache = RemoteContentCache()
        cache.merge(rows)
        let reloaded = try JSONDecoder().decode(RemoteContentCache.self, from: JSONEncoder().encode(cache))
        XCTAssertEqual(reloaded.rev, 6)
        XCTAssertEqual(reloaded.all.compactMap(\.payload).count, 1)
    }
}

/// Feedback #6: the Live tab's touring acts and venue list.
final class LiveMusicTests: XCTestCase {
    func testTouringActsAreArtistsInTheirCrates() {
        let library = ContentLibrary.shared
        for (crate, names) in LiveMusic.touring {
            let genre = library.genres.first { $0.id == crate }
            XCTAssertNotNil(genre, crate)
            let artists = Set(genre?.songs.map(\.artist) ?? [])
            for name in names { XCTAssertTrue(artists.contains(name), "\(crate): \(name)") }
        }
    }

    func testActsFollowCrateOrderOnceEachWithArt() {
        let library = ContentLibrary.shared
        let genres = ["classic-rock", "eighties"].compactMap { id in library.genres.first { $0.id == id } }
        let acts = LiveMusic.acts(in: genres)
        XCTAssertEqual(acts.first?.name, "Eagles")
        XCTAssertEqual(acts.filter { $0.name == "Journey" }.count, 1)
        XCTAssertEqual(acts.first { $0.name == "Journey" }?.genre.id, "classic-rock")
        XCTAssertTrue(acts.allSatisfy { $0.songID != nil })
    }

    func testTourDatesURLEncodesTheName() {
        XCTAssertEqual(LiveMusic.tourDatesURL(for: "Earth, Wind & Fire")?.absoluteString,
                       "https://www.ticketmaster.com/search?q=Earth,%20Wind%20%26%20Fire")
    }

    func testVenuesNearestFirstWithoutDuplicates() {
        func venue(_ name: String, _ miles: Double) -> Venue {
            Venue(name: name, area: nil, miles: miles, latitude: 0, longitude: 0, website: nil)
        }
        let hits = [venue("Far", 20), venue("Near", 1), venue("near", 3), venue("Mid", 5)].map { VenueFinder.Hit(venue: $0, musicVenue: false) }
        XCTAssertEqual(VenueFinder.best(hits).map(\.name), ["Near", "Mid", "Far"])
        XCTAssertEqual(venue("x", 3.25).distanceLabel, "3.2 mi")
        XCTAssertEqual(venue("x", 12.6).distanceLabel, "13 mi")
    }

    /// Feedback #10: real music venues make the list ahead of the bars and theaters closer by.
    func testMusicVenuesOutrankCloserBars() {
        func hit(_ name: String, _ miles: Double, music: Bool = false) -> VenueFinder.Hit {
            VenueFinder.Hit(venue: Venue(name: name, area: nil, miles: miles, latitude: 0, longitude: 0, website: nil), musicVenue: music)
        }
        var hits = (0..<40).map { hit("Corner Bar \($0)", 0.1 + Double($0) / 100) }
        hits += [hit("The Showbox", 9, music: true), hit("Tractor Tavern", 12), hit("Tractor Tavern", 12), hit("Tractor Tavern", 12)]
        let list = VenueFinder.best(hits)
        XCTAssertEqual(list.count, VenueFinder.limit)
        XCTAssertTrue(list.contains { $0.name == "The Showbox" })
        XCTAssertTrue(list.contains { $0.name == "Tractor Tavern" }, "found by several music searches")
        XCTAssertEqual(list.last?.name, "Tractor Tavern", "shown nearest first")
    }

    /// Feedback #10: Apple Maps' answer for Seattle has the rooms a Seattle fan would name.
    @MainActor
    func testSeattleVenuesFromAppleMaps() async throws {
        let seattle: (name: String, location: CLLocation)?
        let venues: [Venue]
        do {
            seattle = try await VenueFinder.place("Seattle, WA")
            venues = try await VenueFinder.nearby(CLLocation(latitude: 47.6062, longitude: -122.3321))
        } catch {
            throw XCTSkip("Apple Maps unreachable: \(error)")
        }
        print("SEATTLE VENUES:", venues.map { "\($0.name) (\($0.distanceLabel))" }.joined(separator: "; "))
        XCTAssertEqual(seattle?.name, "Seattle")
        let names = venues.map { $0.name.lowercased() }
        for expected in ["showbox", "crocodile", "tractor tavern"] {
            XCTAssertTrue(names.contains { $0.contains(expected) }, expected)
        }
    }

    /// Feedback #8: venues are rooms a touring band plays, not cinemas, stadiums or karaoke bars.
    func testVenueFilterKeepsMusicRooms() {
        for name in ["The Crocodile", "Neptune Theatre", "Showbox SoDo", "White River Amphitheatre", "Brixton Academy", "Studio 7"] {
            XCTAssertTrue(VenueFinder.isVenue(name: name, category: .theater), name)
        }
        for name in ["Regal Cinemas", "Lumen Field Stadium", "Rock Star Karaoke", "Seattle Music Lessons", "Climate Pledge Arena"] {
            XCTAssertFalse(VenueFinder.isVenue(name: name, category: nil), name)
        }
        XCTAssertFalse(VenueFinder.isVenue(name: "The Paramount", category: .movieTheater))
    }
}

/// The unfolded iPhone Duo's two panes: fold-aligned when the system reports a fold.
final class UnfoldedSplitTests: XCTestCase {
    func testCompactWidthKeepsOneColumn() {
        XCTAssertNil(UnfoldedSplit.make(width: 466, isRegularWidth: false, fold: nil))
        // The folded outer display, and an unfolded phone held in portrait.
        XCTAssertNil(UnfoldedSplit.make(width: 951, isRegularWidth: false, fold: 472...479))
        XCTAssertNil(UnfoldedSplit.make(width: 669, isRegularWidth: true, fold: nil))
    }

    func testPanesMeetTheFoldEdges() {
        let split = UnfoldedSplit.make(width: 951, isRegularWidth: true, fold: 472...479)
        XCTAssertEqual(split, UnfoldedSplit(primaryWidth: 472, secondaryX: 479, secondaryWidth: 472))
    }

    func testNoFoldSplitsEvenly() {
        let split = UnfoldedSplit.make(width: 951, isRegularWidth: true, fold: nil)
        XCTAssertEqual(split, UnfoldedSplit(primaryWidth: 475, secondaryX: 475, secondaryWidth: 476))
    }

    func testFoldThatLeavesANarrowPaneSplitsEvenly() {
        let split = UnfoldedSplit.make(width: 951, isRegularWidth: true, fold: 300...310)
        XCTAssertEqual(split?.primaryWidth, 475)
        XCTAssertEqual(split?.secondaryWidth, 476)
    }

    func testEveryPaneFitsThePhoneLayout() {
        for width in stride(from: CGFloat(720), through: 1400, by: 37) {
            guard let split = UnfoldedSplit.make(width: width, isRegularWidth: true, fold: nil) else {
                return XCTFail("no split at \(width)")
            }
            XCTAssertGreaterThanOrEqual(split.primaryWidth, UnfoldedSplit.minimumPaneWidth)
            XCTAssertGreaterThanOrEqual(split.secondaryWidth, UnfoldedSplit.minimumPaneWidth)
            XCTAssertEqual(split.secondaryX + split.secondaryWidth, width)
        }
    }
}

@MainActor
final class PlusTests: XCTestCase {
    func model() -> AppModel {
        let store = ProgressStore(url: FileManager.default.temporaryDirectory.appendingPathComponent("progress-\(UUID()).json"))
        store.setFocus(["classic-rock"])
        return AppModel(progress: store)
    }

    func testOneFreeRoundADayInEachMode() {
        let app = model()
        XCTAssertFalse(app.isLocked(.trivia))
        app.start(mode: .trivia, crate: nil)
        XCTAssertNotNil(app.activeQuiz)
        XCTAssertNil(app.paywall)
        app.activeQuiz = nil

        XCTAssertTrue(app.isLocked(.trivia))
        app.start(mode: .trivia, crate: app.library.genre("classic-rock"))
        XCTAssertNil(app.activeQuiz, "the second round is Deep Cuts+, in any crate")
        XCTAssertEqual(app.paywall, .round(.trivia))
        XCTAssertFalse(app.isLocked(.hard), "each mode has its own free round")
    }

    func testFreeRoundComesBackTomorrow() {
        let store = ProgressStore(url: FileManager.default.temporaryDirectory.appendingPathComponent("progress-\(UUID()).json"))
        let today = Date(timeIntervalSince1970: 1_793_000_000)
        store.useFreeRound(.tune, today: today)
        XCTAssertFalse(store.hasFreeRound(.tune, today: today))
        XCTAssertTrue(store.hasFreeRound(.tune, today: today.addingTimeInterval(86_400)))
        XCTAssertTrue(store.hasFreeRound(.covers, today: today))
    }

    func testTodaysStoryStaysReadableAndStillAfterReading() throws {
        let app = model()
        let pick = try XCTUnwrap(app.storyOfTheDay())
        XCTAssertTrue(app.canRead(pick.story))
        let other = try XCTUnwrap(app.focusGenres.flatMap(\.stories).first { $0.id != pick.story.id })
        XCTAssertFalse(app.canRead(other), "the archive is Deep Cuts+")

        app.progress.markRead(pick.story)
        XCTAssertEqual(app.storyOfTheDay()?.story.id, pick.story.id, "reading today's story doesn't open another")
        XCTAssertTrue(app.canRead(pick.story))
        XCTAssertFalse(app.canRead(other))
    }

    func testOnboardingWaitsForTheTrialPage() {
        let store = ProgressStore(url: FileManager.default.temporaryDirectory.appendingPathComponent("progress-\(UUID()).json"))
        store.setFocus(["blues"], onboarded: false)
        XCTAssertFalse(store.data.onboarded)
        XCTAssertEqual(store.focus, ["blues"])
        store.finishOnboarding()
        XCTAssertTrue(store.data.onboarded)
    }

    func testTermsNameTheTrialAndRenewal() {
        let membership = Membership()
        XCTAssertEqual(PlusPricing.terms(membership, .yearly, trial: true), "7 days free. Auto-renews until canceled.")
        XCTAssertEqual(PlusPricing.terms(membership, .monthly, trial: false), "Billed today. Auto-renews until canceled.")
        XCTAssertEqual(PlusPricing.cta(.yearly, trial: true), "Start 7-Day Free Trial")
        XCTAssertEqual(PlusPricing.cta(.lifetime, trial: true), "Unlock Deep Cuts+ Forever")
        XCTAssertNil(PlusPricing.price(membership, .yearly), "no price until StoreKit gives one")
    }
}
