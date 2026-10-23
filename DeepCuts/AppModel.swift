import Foundation
import Observation

/// App-wide state handed to every screen through the environment.
@MainActor
@Observable
final class AppModel {
    /// Bundled crates plus live content; swapped between rounds when new content arrives.
    private(set) var library: ContentLibrary
    let progress: ProgressStore
    let player: PreviewPlayer
    let feedback: FeedbackService
    let content: RemoteContentService
    private var pendingLibrary: ContentLibrary?
    private var contentCheckedAt = Date.distantPast

    /// The round on screen, if any. Set to start a quiz from anywhere.
    var activeQuiz: QuizSpec?
    var showingFeedback = false
    var feedbackContext = ""
    var moments: [MusicMoment] = []
    var momentsDay = ""
    var momentsFailed = false
    var myFeedback: [FeedbackItem] = []

    init(library: ContentLibrary = .shared, progress: ProgressStore = ProgressStore(), feedback: FeedbackService = .live,
         content: RemoteContentService = .off) {
        self.library = library
        self.progress = progress
        self.player = PreviewPlayer(library: library)
        self.feedback = feedback
        self.content = content
    }

    var focusGenres: [Genre] {
        let focus = progress.focus
        let picked = library.genres.filter { focus.contains($0.id) }
        return picked.isEmpty ? library.genres : picked
    }

    private var builder: QuizBuilder { QuizBuilder(library: library) }

    // MARK: Starting rounds

    func startDaily() {
        let day = ProgressStore.dayKey()
        let names = focusGenres.map(\.name)
        let title = names.count <= 2 ? names.joined(separator: " & ") : "Today's Mix"
        activeQuiz = QuizSpec(source: .daily(day: day), mode: nil, title: title, items: builder.daily(day: day, genres: focusGenres, seen: progress.seenQuestions))
    }

    func dailyPreviewSongs() -> [String] {
        builder.daily(day: ProgressStore.dayKey(), genres: focusGenres).compactMap { $0.audioSongID ?? $0.choices.compactMap(\.songID).first }
    }

    func coverOfTheDay() -> (cover: CoverSong, genre: Genre)? {
        builder.coverOfTheDay(day: ProgressStore.dayKey(), genres: focusGenres)
    }

    /// Words in a Wikipedia description that tie a musician to a crate.
    static let genreWords: [String: [String]] = [
        "classic-rock": ["rock"], "british-invasion": ["rock", "english singer", "english musician"],
        "southern-rock": ["rock", "southern"], "heavy-metal": ["metal", "hard rock"], "prog-rock": ["rock", "progressive"],
        "motown-soul": ["soul", "r&b", "rhythm and blues", "motown"], "folk-singer-songwriter": ["folk", "singer-songwriter"],
        "yacht-rock": ["soft rock", "rock"], "punk-new-wave": ["punk", "new wave"], "eighties": ["pop", "rock", "new wave"],
        "grunge-alt": ["grunge", "alternative", "indie"], "pop": ["pop"], "modern-pop": ["pop", "r&b"],
        "country": ["country"], "blues": ["blues"], "disco-funk": ["disco", "funk"], "psychedelic-rock": ["psychedelic", "rock"], "hip-hop": ["rapper", "hip hop", "hip-hop"],
    ]

    func offers(_ mode: QuizMode, crate: Genre?) -> Bool {
        builder.offers(mode, genres: crate.map { [$0] } ?? focusGenres)
    }

    func start(mode: QuizMode, crate: Genre?) {
        var rng = SystemRandomNumberGenerator()
        let genres = crate.map { [$0] } ?? focusGenres
        let items = builder.round(mode: mode, genres: genres, seen: progress.seenQuestions, rng: &rng)
        guard !items.isEmpty else { return }
        activeQuiz = QuizSpec(source: crate.map { .crate($0.id) } ?? .mix, mode: mode, title: crate?.name ?? "Your Crates", items: items)
    }

    func requestFeedback(context: String) {
        feedbackContext = context
        showingFeedback = true
    }

    // MARK: Story of the day

    func storyOfTheDay() -> (story: Story, genre: Genre)? {
        let pool = focusGenres.flatMap { genre in genre.stories.map { ($0, genre) } }
        guard !pool.isEmpty else { return nil }
        var rng = SeededRandom(string: "story-\(ProgressStore.dayKey())")
        let unread = pool.filter { !progress.data.readStories.contains($0.0.id) }
        let choices = unread.isEmpty ? pool : unread
        return choices[Int(rng.next() % UInt64(choices.count))]
    }

    // MARK: On this day

    func loadMoments(force: Bool = false) async {
        let today = ProgressStore.dayKey()
        guard force || momentsDay != today else { return }
        let parts = Calendar.current.dateComponents([.month, .day], from: .now)
        let artists = Array(Set(focusGenres.flatMap { $0.songs.map(\.artist) }))
        do {
            let all = try await OnThisDay.moments(month: parts.month ?? 1, day: parts.day ?? 1, artists: artists)
            // Births only when tied to your crates by artist or by genre ("American rock guitarist").
            let words = Set(focusGenres.flatMap { Self.genreWords[$0.id] ?? [] })
            moments = all.filter { moment in
                moment.connection != nil || moment.kind == .event
                    || words.contains { (moment.detail ?? "").lowercased().contains($0) }
            }
            momentsDay = today
            momentsFailed = false
        } catch {
            momentsFailed = moments.isEmpty
        }
    }

    // MARK: Live content

    /// Pulls new and corrected questions at most hourly, saves them for the next launch,
    /// and swaps them in now unless a round is on screen.
    func refreshContent() async {
        guard content.isConfigured, Date.now.timeIntervalSince(contentCheckedAt) > 3600 else { return }
        contentCheckedAt = .now
        var cache = RemoteContentCache.load()
        guard let rows = try? await content.changes(since: cache.rev), !rows.isEmpty else { return }
        cache.merge(rows)
        cache.save()
        pendingLibrary = ContentLibrary.shared.applying(cache.all)
        applyPendingContent()
    }

    func applyPendingContent() {
        guard activeQuiz == nil, let pending = pendingLibrary else { return }
        library = pending
        pendingLibrary = nil
    }

    // MARK: Feedback

    func refreshFeedback() async {
        guard feedback.isConfigured else { return }
        if let items = try? await feedback.mine(installID: progress.data.installID) {
            myFeedback = items
        }
    }
}
