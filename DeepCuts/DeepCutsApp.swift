import SwiftUI

@main
struct DeepCutsApp: App {
    @State private var app: AppModel

    init() {
        let args = ProcessInfo.processInfo.arguments
        let progress = ProgressStore()
        if args.contains("-ui-reset") { progress.reset() }
        if let index = args.firstIndex(of: "-ui-focus"), index + 1 < args.count {
            progress.setFocus(args[index + 1].split(separator: ",").map(String.init))
        }
        let feedback: FeedbackService = args.contains("-ui-feedback-stub") ? .stub : .live
        _app = State(initialValue: AppModel(progress: progress, feedback: feedback))
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
    @State private var tab = Tab.today

    enum Tab: Hashable { case today, play, stories, you }

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
                    YouView()
                        .tabItem { Label("You", systemImage: "person.crop.circle") }.tag(Tab.you)
                }
            } else {
                OnboardingView()
            }
        }
        .fullScreenCover(item: $app.activeQuiz) { spec in
            QuizView(spec: spec)
        }
        .sheet(isPresented: $app.showingFeedback) {
            FeedbackView(context: app.feedbackContext)
        }
        .onChange(of: app.activeQuiz) { _, quiz in
            if quiz == nil { app.player.stop() }
        }
    }
}
