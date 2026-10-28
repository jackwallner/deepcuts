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
        let model = AppModel(library: library, progress: progress, feedback: feedback, content: live ? .live : .off)
        #if DEBUG
        ScreenshotScene.current?.apply(to: model)
        #endif
        model.membership.start()
        _app = State(initialValue: model)
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
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var tab = Self.launchTab
    /// The container's width and fold, so the unfolded iPhone Duo can put the tabs and
    /// the reading pane on opposite sides of the fold.
    @State private var panes = PaneGeometry()

    enum Tab: String, Hashable { case today, play, stories, live, you }

    /// `-ui-tab play` (or a `-ui-screen` scene) opens on that tab, for screenshots (DEBUG only).
    private static var launchTab: Tab {
        #if DEBUG
        if let scene = ScreenshotScene.current { return scene.tab }
        let args = ProcessInfo.processInfo.arguments
        if let index = args.firstIndex(of: "-ui-tab"), index + 1 < args.count, let tab = Tab(rawValue: args[index + 1]) {
            return tab
        }
        #endif
        return .today
    }

    /// Unfolded, Stories is the trailing pane rather than a tab.
    private var split: UnfoldedSplit? {
        UnfoldedSplit.make(width: panes.width, isRegularWidth: sizeClass == .regular, fold: panes.fold)
    }

    /// Each pane is phone-width, so its screen lays out as on a phone.
    private var paneSizeClass: UserInterfaceSizeClass? { split == nil ? sizeClass : .compact }

    var body: some View {
        @Bindable var app = app
        Group {
            if app.progress.data.onboarded {
                panesView
            } else {
                OnboardingView()
                    .environment(\.horizontalSizeClass, paneSizeClass)
                    .frame(maxWidth: split?.primaryWidth ?? .infinity, maxHeight: .infinity, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .background(Theme.paper.ignoresSafeArea())
        .measuringPanes(into: $panes)
        // Presented views get the model again: as an iPhone app on a Mac they can lose it,
        // and the first @Environment(AppModel.self) read crashed (TestFlight, build 8).
        .fullScreenCover(item: $app.activeQuiz) { spec in
            QuizView(spec: spec).environment(app)
        }
        .sheet(item: $app.paywall) { reason in
            PaywallView(reason: reason).environment(app)
        }
        .onChange(of: app.activeQuiz) { _, quiz in
            if quiz == nil {
                app.player.stop()
                app.applyPendingContent()
            }
        }
        .onChange(of: split != nil, initial: true) { _, isSplit in
            if isSplit, tab == .stories { tab = .today }
            // Folding with a story open in the reading pane keeps it on screen.
            if !isSplit, !app.storyPath.isEmpty, tab == .today { tab = .stories }
        }
        .onChange(of: tab) { _, new in
            // Launch scenes and the tour still ask for the Stories tab.
            if new == .stories, split != nil { tab = .today }
        }
        .onChange(of: scenePhase, initial: true) { _, phase in
            if phase == .active { Task { await app.refreshContent() } }
        }
        #if DEBUG
        .task { await runScreenshotTour() }
        #endif
    }

    /// The tabs, and unfolded, the reading pane beside them. Folding only moves frames,
    /// so neither side is rebuilt and both keep their scroll and navigation.
    private var panesView: some View {
        @Bindable var app = app
        let floatingTabs = split != nil || ProcessInfo.processInfo.isOperatingSystemAtLeast(
            OperatingSystemVersion(majorVersion: 26, minorVersion: 0, patchVersion: 0))
        return ZStack(alignment: .topLeading) {
            TabView(selection: $tab) {
                TodayView(tab: $tab)
                    .tabBarBackdrop(floatingTabs)
                    .tabItem { Label("Today", systemImage: "sun.horizon") }.tag(Tab.today)
                PlayView()
                    .tabBarBackdrop(floatingTabs)
                    .tabItem { Label("Play", systemImage: "opticaldisc") }.tag(Tab.play)
                if split == nil {
                    StoriesView()
                        .tabBarBackdrop(floatingTabs)
                        .tabItem { Label("Stories", systemImage: "book") }.tag(Tab.stories)
                }
                LiveView()
                    .tabBarBackdrop(floatingTabs)
                    .tabItem { Label("Live", systemImage: "ticket") }.tag(Tab.live)
                YouView()
                    .tabBarBackdrop(floatingTabs)
                    .tabItem { Label("You", systemImage: "person.crop.circle") }.tag(Tab.you)
            }
            .environment(\.horizontalSizeClass, paneSizeClass)
            .environment(\.isUnfoldedPane, split != nil)
            .paneSheet(isPresented: $app.showingFeedback, inPane: split != nil) { close in
                FeedbackView(context: app.feedbackContext, onClose: close).environment(app)
            }
            .frame(maxWidth: split?.primaryWidth ?? .infinity, maxHeight: .infinity)

            if let split {
                StoriesPane()
                    .paneBottomFade(true)
                    .environment(\.horizontalSizeClass, .compact)
                    .environment(\.isUnfoldedPane, true)
                    .frame(width: split.secondaryWidth)
                    .frame(maxHeight: .infinity)
                    .padding(.leading, split.secondaryX)
            }
        }
    }

    #if DEBUG
    /// `-ui-tour`: walks a story, Play and a round every two seconds, so a native recording
    /// shows real transitions. Off when a `-ui-screen` scene is set.
    private func runScreenshotTour() async {
        guard ProcessInfo.processInfo.arguments.contains("-ui-tour"), ScreenshotScene.current == nil else { return }
        let story = app.library.genre("classic-rock")?.stories.first { $0.isConcert }
        try? await Task.sleep(for: .seconds(2))
        if let story {
            tab = .stories
            withAnimation(.snappy) { app.storyPath = [story] }
        }
        try? await Task.sleep(for: .seconds(2))
        tab = .play
        try? await Task.sleep(for: .seconds(2))
        app.start(mode: .trivia, crate: nil)
        try? await Task.sleep(for: .seconds(3))
        app.activeQuiz = nil
        try? await Task.sleep(for: .seconds(1))
        tab = .today
    }
    #endif
}
