import Foundation
import Observation

/// App-wide state handed to every screen through the environment.
@MainActor
@Observable
final class AppModel {
    let library: ContentLibrary
    let progress: ProgressStore
    let player: PreviewPlayer
    let feedback: FeedbackService

    /// The round on screen, if any. Set to start a quiz from anywhere.
    var activeQuiz: QuizSpec?
    var showingFeedback = false
    var feedbackContext = ""
    var moments: [MusicMoment] = []
    var momentsDay = ""
    var momentsFailed = false
    var myFeedback: [FeedbackItem] = []

    init(library: ContentLibrary = .shared, progress: ProgressStore = ProgressStore(), feedback: FeedbackService = .live) {
        self.library = library
        self.progress = progress
        self.player = PreviewPlayer(library: library)
        self.feedback = feedback
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
            // Births of strangers are noise; keep them only to fill a quiet day.
            let relevant = all.filter { $0.connection != nil || $0.kind == .event }
            moments = relevant.count >= 3 ? relevant : relevant + all.filter { !relevant.contains($0) }.prefix(3 - relevant.count)
            momentsDay = today
            momentsFailed = false
        } catch {
            momentsFailed = moments.isEmpty
        }
    }

    // MARK: Feedback

    func refreshFeedback() async {
        guard feedback.isConfigured else { return }
        if let items = try? await feedback.mine(installID: progress.data.installID) {
            myFeedback = items
        }
    }
}
