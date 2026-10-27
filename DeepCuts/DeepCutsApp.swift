import SwiftUI

@main
struct DeepCutsApp: App {
    @State private var app: AppModel

    init() {
        let progress = ProgressStore()
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        if args.contains("-ui-reset") { progress.reset() }
        if let index = args.firstIndex(of: "-ui-focus"), index + 1 < args.count {
            progress.setFocus(args[index + 1].split(separator: ",").map(String.init))
        }
        let feedback: FeedbackService = args.contains("-ui-feedback-stub") ? .stub : .live
        // UI tests play the bundled crates only, so rounds don't change under them.
        let live = !args.contains("-ui-reset")
        #else
        let feedback: FeedbackService = .live
        let live = true
        #endif
        let library = live ? ContentLibrary.shared.applying(RemoteContentCache.load().all) : .shared
        _app = State(initialValue: AppModel(library: library, progress: progress, feedback: feedback,
                                            content: live ? .live : .off))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(app)
                .tint(Theme.accent)
        }
    }
}

struct RootView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.scenePhase) private var scenePhase
    @State private var tab = Tab.today

    enum Tab: Hashable { case today, play, stories, live, you }

    var body: some View {
        @Bindable var app = app
        Group {
            if app.progress.data.onboarded {
                TabView(selection: $tab) {
                    TodayView(tab: $tab)
                        .tabItem { Label("Today", systemImage: "sun.horizon") }.tag(Tab.today)
                    PlayView()
                        .tabItem { Label("Play", systemImage: "opticaldisc") }.tag(Tab.play)
                    StoriesView()
                        .tabItem { Label("Stories", systemImage: "book") }.tag(Tab.stories)
                    LiveView()
                        .tabItem { Label("Live", systemImage: "ticket") }.tag(Tab.live)
                    YouView()
                        .tabItem { Label("You", systemImage: "person.crop.circle") }.tag(Tab.you)
                }
            } else {
                OnboardingView()
            }
        }
        // Presented views get the model again: as an iPhone app on a Mac they can lose it,
        // and the first @Environment(AppModel.self) read crashed (TestFlight, build 8).
        .fullScreenCover(item: $app.activeQuiz) { spec in
            QuizView(spec: spec).environment(app)
        }
        .sheet(isPresented: $app.showingFeedback) {
            FeedbackView(context: app.feedbackContext).environment(app)
        }
        .onChange(of: app.activeQuiz) { _, quiz in
            if quiz == nil {
                app.player.stop()
                app.applyPendingContent()
            }
        }
        .onChange(of: scenePhase, initial: true) { _, phase in
            if phase == .active { Task { await app.refreshContent() } }
        }
    }
}
