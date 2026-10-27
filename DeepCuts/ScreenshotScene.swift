#if DEBUG
import Foundation

/// `-ui-screen <scene>` opens a store surface with seeded state, read once at launch.
/// Unfolded, every scene shows the tabs beside the reading pane (or a round beside its sheet).
enum ScreenshotScene: String {
    /// Today, with Stories in the reading pane.
    case today
    /// The Last Waltz: on the Stories tab, or beside Today when unfolded.
    case story
    /// Play, with The Making of Rumours open beside it when unfolded.
    case play
    /// Live with sample venues (pass `-ui-venues-stub` too).
    case live
    /// Trivia, five questions in, the Rumours question answered.
    case trivia
    /// Name That Tune, five clips in, "Another One Bites the Dust" answered.
    case tune
    /// The same clip playing, not yet answered.
    case listen

    static let current: ScreenshotScene? = {
        let args = ProcessInfo.processInfo.arguments
        guard let index = args.firstIndex(of: "-ui-screen"), index + 1 < args.count else { return nil }
        return ScreenshotScene(rawValue: args[index + 1])
    }()

    var tab: RootView.Tab {
        switch self {
        case .story: .stories
        case .play: .play
        case .live: .live
        case .today, .trivia, .tune, .listen: .today
        }
    }

    @MainActor
    func apply(to app: AppModel) {
        switch self {
        case .today, .live: break
        case .story: openStory("classic-rock-st7", app)
        case .play: openStory("classic-rock-st1", app)
        case .trivia: openTrivia(app)
        case .tune: openTune(app, answered: true)
        case .listen: openTune(app, answered: false)
        }
    }

    @MainActor
    private func openStory(_ id: String, _ app: AppModel) {
        guard let story = app.library.genres.flatMap(\.stories).first(where: { $0.id == id }) else { return }
        app.storyPath = [story]
    }

    @MainActor
    private func openTrivia(_ app: AppModel) {
        guard let genre = app.library.genre("classic-rock"),
              let question = genre.questions.first(where: { $0.id == "classic-rock-q01" }) else { return }
        let builder = QuizBuilder(library: app.library)
        var rng = SeededRandom(string: "screenshot-trivia")
        var items = builder.round(mode: .trivia, genres: app.focusGenres, seen: [], rng: &rng)
        items.removeAll { $0.id == question.id }
        let at = min(4, items.count)
        let featured = builder.item(for: question, genre: genre, rng: &rng)
        items.insert(featured, at: at)
        items = Array(items.prefix(QuizBuilder.triviaCount))
        open(QuizSpec(source: .mix, mode: .trivia, title: "Your Crates", items: items), at: at, missed: 2,
             picked: featured.correctIndex, app)
    }

    @MainActor
    private func openTune(_ app: AppModel, answered: Bool) {
        let songs = ["classic-rock-s10", "classic-rock-s14", "classic-rock-s04", "classic-rock-s21"].compactMap { app.library.song($0) }
        guard songs.count == 4 else { return }
        let song = songs[1]
        let featured = QuizItem(
            id: "tune-\(song.id)", mode: .tune, genreID: "classic-rock", prompt: "Name that tune",
            choices: songs.map { Choice(title: $0.title, subtitle: $0.artist) }, correctIndex: 1,
            fact: "\(song.artist), \(song.year). \(song.note)", audioSongID: song.id)
        var rng = SeededRandom(string: "screenshot-tune")
        var items = QuizBuilder(library: app.library).tunes(genres: app.focusGenres, count: QuizBuilder.tuneCount, rng: &rng)
        items.removeAll { $0.id == featured.id || $0.choices[$0.correctIndex].subtitle == song.artist }
        let at = min(4, items.count)
        items.insert(featured, at: at)
        items = Array(items.prefix(QuizBuilder.tuneCount))
        open(QuizSpec(source: .mix, mode: .tune, title: "Your Crates", items: items), at: at, missed: 1,
             picked: answered ? featured.correctIndex : nil, app)
    }

    /// Opens the round at `index` with every earlier answer right except `missed`.
    @MainActor
    private func open(_ spec: QuizSpec, at index: Int, missed: Int?, picked: Int?, _ app: AppModel) {
        let outcomes: [Bool?] = spec.items.indices.map { i -> Bool? in
            i < index || (i == index && picked != nil) ? i != missed : nil
        }
        app.quizPreset = QuizPreset(index: index, outcomes: outcomes, picked: picked)
        app.activeQuiz = spec
    }
}
#endif
