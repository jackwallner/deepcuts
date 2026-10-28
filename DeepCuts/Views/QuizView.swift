import SwiftUI

/// Runs one round: trivia, clips and matchups share this screen.
struct QuizView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var sizeClass
    let spec: QuizSpec

    @State private var index = 0
    @State private var picked: Int?
    @State private var outcomes: [Bool?] = []
    @State private var finished = false
    @State private var reporting = false
    @State private var panes = PaneGeometry()

    private var item: QuizItem { spec.items[index] }

    /// Unfolded, the round sits on the leading side of the fold and its sheet on the trailing side.
    private var split: UnfoldedSplit? {
        UnfoldedSplit.make(width: panes.width, isRegularWidth: sizeClass == .regular, fold: panes.fold)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            round
                .environment(\.horizontalSizeClass, split == nil ? sizeClass : .compact)
                .paneSheet(isPresented: $reporting, inPane: split != nil) { close in
                    FeedbackView(
                        context: "question \(item.id): \(item.prompt) | answer shown: \(item.choices[item.correctIndex].label)",
                        title: "Report a problem",
                        pitch: Distribution.isTestFlight
                            ? "A wrong answer, a typo, a fact that doesn't sound right. It goes straight to Jack's build assistant with this question attached."
                            : nil,
                        placeholder: "What's wrong with this one?",
                        reported: (item.prompt, item.choices[item.correctIndex].label),
                        onClose: close)
                    .environment(app)
                }
                // After the bottom inset inside `round`, which fills its proposal and would
                // centre a narrower pane across the fold.
                .frame(maxWidth: split?.primaryWidth ?? .infinity, maxHeight: .infinity)
            if let split {
                RoundSheet(spec: spec, index: index, outcomes: outcomes, finished: finished) { answerPanel }
                    .environment(\.horizontalSizeClass, .compact)
                    .frame(width: split.secondaryWidth)
                    .frame(maxHeight: .infinity)
                    .padding(.leading, split.secondaryX)
            }
        }
        .background(Theme.paper.ignoresSafeArea())
        .measuringPanes(into: $panes)
        .onAppear {
            outcomes = Array(repeating: nil, count: spec.items.count)
            if let preset = app.quizPreset, preset.outcomes.count == spec.items.count {
                app.quizPreset = nil
                index = preset.index
                outcomes = preset.outcomes
                picked = preset.picked
            }
        }
        .onChange(of: index, initial: true) { _, _ in autoplay() }
        .onDisappear { app.player.stop() }
    }

    private var round: some View {
        VStack(spacing: 0) {
            topBar
            if finished {
                ResultView(spec: spec, outcomes: outcomes, showsRecap: split == nil) { dismiss() }
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 20) {
                            question
                            // Unfolded, the answer sits in the round's sheet beside the question.
                            if let picked, split == nil { reveal(picked).id("reveal") }
                        }
                        .padding(.horizontal, Theme.gutter)
                        .padding(.top, 12)
                        .padding(.bottom, 24)
                        .id(index)
                        .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .opacity))
                    }
                    .scrollBounceBehavior(.basedOnSize)
                    // On small screens the clip's record pushes the answer card under Next.
                    .onChange(of: picked) { _, new in
                        guard new != nil, split == nil else { return }
                        // Wait for the card to lay out, or there is nothing to scroll to yet.
                        Task {
                            try? await Task.sleep(for: .milliseconds(120))
                            withAnimation(.snappy) { proxy.scrollTo("reveal", anchor: .bottom) }
                        }
                    }
                }
                .safeAreaInset(edge: .bottom) { if split == nil { bottomBar } }
                .paneBottomFade(split != nil)
            }
        }
        .background(Theme.paper.ignoresSafeArea())
    }

    /// Unfolded: the answer and Next, at the top of the round's sheet.
    @ViewBuilder
    private var answerPanel: some View {
        if !finished, picked != nil || clipFailed {
            VStack(spacing: 12) {
                if let picked { reveal(picked) }
                nextButton
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.top, 12)
            .padding(.bottom, 4)
        }
    }

    private var nextButton: some View {
        Button(index + 1 < spec.items.count ? "Next" : "See results") { advance() }
            .buttonStyle(PrimaryButtonStyle(fill: Theme.ink, text: Theme.paper))
            .accessibilityIdentifier("quiz-next")
    }

    // MARK: Chrome

    private var topBar: some View {
        HStack(spacing: 14) {
            Button { dismiss() } label: {
                Image(systemName: "xmark").font(.body.weight(.semibold)).foregroundStyle(Theme.ink)
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("Close")
            .accessibilityIdentifier("quiz-close")
            HStack(spacing: 4) {
                ForEach(outcomes.indices, id: \.self) { i in
                    Capsule()
                        .fill(segmentColor(i))
                        .frame(height: 5)
                }
            }
            .accessibilityHidden(true)
            Text(finished ? "Done" : "\(index + 1)/\(spec.items.count)")
                .font(.subheadline.monospacedDigit().weight(.semibold))
                .foregroundStyle(Theme.inkSoft)
                .frame(minWidth: 44)
                .accessibilityLabel(finished ? "Round finished" : "Question \(index + 1) of \(spec.items.count)")
        }
        .padding(.horizontal, 8)
        .padding(.top, 4)
    }

    private func segmentColor(_ i: Int) -> Color {
        if let outcome = outcomes[i] { return outcome ? Theme.correct : Theme.accent }
        return i == index && !finished ? Theme.ink.opacity(0.5) : Theme.rule
    }

    @ViewBuilder
    private var bottomBar: some View {
        if picked != nil || clipFailed {
            nextButton
                .padding(.horizontal, Theme.gutter)
                .padding(.vertical, 10)
                .background(Theme.paper.opacity(0.96))
        }
    }

    // MARK: Question

    @ViewBuilder
    private var question: some View {
        let genre = app.library.genre(item.genreID)
        VStack(alignment: .leading, spacing: 10) {
            Kicker(text: [genre?.name, item.mode == .trivia ? nil : item.mode.title].compactMap { $0 }.joined(separator: " · "),
                   color: Theme.accent)
            Text(item.prompt)
                .font(Theme.serif(item.mode == .trivia || item.mode == .covers ? .title2 : .title, weight: .bold))
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("quiz-prompt")
        }
        switch item.mode {
        case .tune, .covers:
            turntable
            choiceList
        case .firstOf:
            matchup
        case .trivia, .hard:
            choiceList
        }
    }

    private var choiceList: some View {
        VStack(spacing: 10) {
            ForEach(item.choices.indices, id: \.self) { i in
                Button { answer(i) } label: { ChoiceLabel(choice: item.choices[i], state: state(of: i)) }
                    .buttonStyle(PressableStyle())
                    .disabled(picked != nil || clipFailed)
                    .accessibilityIdentifier("choice-\(i)")
            }
        }
        .sensoryFeedback(trigger: picked) { _, new in
            guard let new else { return nil }
            return new == item.correctIndex ? .success : .error
        }
    }

    private func state(of i: Int) -> ChoiceLabel.State {
        guard let picked else { return .open }
        if i == item.correctIndex { return .right }
        if i == picked { return .wrong }
        return .dimmed
    }

    // MARK: Name That Tune

    private var clipFailed: Bool {
        item.audioSongID != nil && app.player.songID == item.audioSongID && app.player.state == .failed && picked == nil
    }

    private var turntable: some View {
        let playing = app.player.songID == item.audioSongID && app.player.state == .playing
        return VStack(spacing: 14) {
            VinylView(labelSongID: item.audioSongID, revealed: picked != nil, spinning: playing, size: split == nil ? 210 : 160,
                      labelColor: Theme.crate(item.genreID))
                .frame(maxWidth: .infinity)
            if clipFailed {
                Text("The clip didn't load. Check your connection, or skip this one.")
                    .font(.subheadline).foregroundStyle(Theme.inkSoft).multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            } else if let id = item.audioSongID {
                Button {
                    app.player.toggle(id)
                } label: {
                    Label(playing ? "Stop" : (app.player.state == .loading && app.player.songID == id ? "Loading" : "Play clip"),
                          systemImage: playing ? "stop.fill" : "play.fill")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 18).frame(minHeight: 40)
                        .background(Theme.card, in: Capsule())
                        .overlay(Capsule().strokeBorder(Theme.rule))
                }
                .buttonStyle(PressableStyle())
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier("clip-toggle")
            }
        }
        .padding(.vertical, 4)
    }

    private func autoplay() {
        guard index < spec.items.count, let id = spec.items[index].audioSongID else {
            app.player.stop()
            return
        }
        app.player.play(id)
    }

    // MARK: Which came first

    private var matchup: some View {
        HStack(alignment: .top, spacing: 12) {
            ForEach(item.choices.indices, id: \.self) { i in
                Button { answer(i) } label: { MatchupTile(choice: item.choices[i], state: state(of: i)) }
                    .buttonStyle(PressableStyle())
                    .disabled(picked != nil)
                    .accessibilityIdentifier("choice-\(i)")
            }
        }
        .sensoryFeedback(trigger: picked) { _, new in
            guard let new else { return nil }
            return new == item.correctIndex ? .success : .error
        }
    }

    // MARK: Answering

    private func reveal(_ choice: Int) -> some View {
        let right = choice == item.correctIndex
        let answer = item.choices[item.correctIndex]
        return VStack(alignment: .leading, spacing: 8) {
            Label(right ? "Right" : "Not quite", systemImage: right ? "checkmark.circle.fill" : "xmark.circle.fill")
                .font(.headline)
                .foregroundStyle(right ? Theme.correct : Theme.accent)
            if !right {
                Text(answer.label)
                    .font(.body.weight(.semibold)).foregroundStyle(Theme.ink)
            }
            Text(item.fact).font(.body).foregroundStyle(Theme.ink.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 18) {
                if let id = item.audioSongID, let link = app.library.catalog[id]?.trackViewUrl.flatMap(URL.init(string:)) {
                    Link(destination: link) {
                        Label("Full song", systemImage: "arrow.up.right.square")
                            .frame(minHeight: 44)
                    }
                }
                Button { reporting = true } label: {
                    Label("Report a problem", systemImage: "flag")
                        .frame(minHeight: 44)
                }
                .foregroundStyle(Theme.inkSoft)
                .accessibilityIdentifier("quiz-report")
            }
            .font(.subheadline.weight(.semibold))
            .padding(.top, 4)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("quiz-reveal")
    }

    private func answer(_ choice: Int) {
        guard picked == nil else { return }
        let right = choice == item.correctIndex
        withAnimation(.spring(duration: 0.35)) {
            picked = choice
            outcomes[index] = right
        }
        app.progress.record(item: item, correct: right)
    }

    private func advance() {
        if picked == nil { outcomes[index] = nil }  // a skipped clip doesn't count
        guard index + 1 < spec.items.count else {
            app.player.stop()
            let counted = outcomes.compactMap { $0 }
            app.progress.finish(spec: spec, result: QuizResult(correct: counted.filter { $0 }.count, total: counted.count))
            withAnimation(.snappy) { finished = true }
            return
        }
        withAnimation(.snappy) {
            picked = nil
            index += 1
        }
    }
}

struct ChoiceLabel: View {
    enum State { case open, right, wrong, dimmed }
    let choice: Choice
    let state: State

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(choice.title).font(.body.weight(.semibold)).foregroundStyle(Theme.ink)
                    .multilineTextAlignment(.leading)
                if let subtitle = choice.subtitle {
                    Text(subtitle).font(.subheadline).foregroundStyle(Theme.inkSoft)
                }
            }
            Spacer(minLength: 8)
            switch state {
            case .right: Image(systemName: "checkmark.circle.fill").font(.title3).foregroundStyle(Theme.correct)
            case .wrong: Image(systemName: "xmark.circle.fill").font(.title3).foregroundStyle(Theme.accent)
            default: EmptyView()
            }
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
        .padding(.vertical, 4)
        .background(background, in: RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous).strokeBorder(border, lineWidth: state == .open || state == .dimmed ? 1 : 2))
        .opacity(state == .dimmed ? 0.45 : 1)
        .contentShape(Rectangle())
    }

    private var background: Color {
        switch state {
        case .right: Theme.correct.opacity(0.10)
        case .wrong: Theme.accent.opacity(0.10)
        default: Theme.card
        }
    }

    private var border: Color {
        switch state {
        case .right: Theme.correct
        case .wrong: Theme.accent
        default: Theme.rule
        }
    }
}

struct MatchupTile: View {
    @Environment(AppModel.self) private var app
    let choice: Choice
    let state: ChoiceLabel.State

    var body: some View {
        let song = choice.songID.flatMap { app.library.song($0) }
        VStack(alignment: .leading, spacing: 10) {
            ArtworkView(songID: choice.songID, size: 140, corner: 4)
                .frame(maxWidth: .infinity)
            VStack(alignment: .leading, spacing: 2) {
                Text(choice.title).font(.headline).foregroundStyle(Theme.ink).lineLimit(3)
                    .multilineTextAlignment(.leading)
                if let subtitle = choice.subtitle {
                    Text(subtitle).font(.subheadline).foregroundStyle(Theme.inkSoft).lineLimit(2)
                }
            }
            if state != .open, let song {
                Text(String(song.year))
                    .font(Theme.serif(.title2, weight: .bold))
                    .foregroundStyle(state == .right ? Theme.correct : Theme.inkSoft)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
            .strokeBorder(state == .right ? Theme.correct : state == .wrong ? Theme.accent : Theme.rule, lineWidth: state == .open || state == .dimmed ? 1 : 2))
        .opacity(state == .dimmed ? 0.6 : 1)
        .contentShape(Rectangle())
    }
}

/// The unfolded round's trailing pane: every question so far with its answer, the one
/// on screen, and how many are left.
struct RoundSheet<Answer: View>: View {
    @Environment(AppModel.self) private var app
    let spec: QuizSpec
    let index: Int
    let outcomes: [Bool?]
    let finished: Bool
    @ViewBuilder let answer: Answer

    var body: some View {
        let answered = outcomes.compactMap { $0 }
        let right = answered.filter { $0 }.count
        let shown = finished ? spec.items.count : min(index + 1, spec.items.count)
        let left = spec.items.count - shown
        VStack(spacing: 0) {
            answer
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        VStack(alignment: .leading, spacing: 6) {
                            Kicker(text: spec.isDaily ? "Today's Mix" : "\(spec.title) · \(spec.mode?.title ?? "")", color: Theme.accent)
                            Text("This Round").font(Theme.display(34)).foregroundStyle(Theme.ink)
                            if !answered.isEmpty {
                                Text("\(right) of \(answered.count) right")
                                    .font(.subheadline.weight(.semibold)).foregroundStyle(Theme.inkSoft)
                                    .monospacedDigit()
                            }
                        }
                        .padding(.top, 16)
    
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(Array(spec.items.prefix(shown).enumerated()), id: \.offset) { i, item in
                                row(i, item).id(i)
                                Divider().overlay(Theme.rule)
                            }
                        }
                        .overlay(alignment: .top) { Rectangle().fill(Theme.ink).frame(height: 1.5) }
                        if left > 0 {
                            Text(left == 1 ? "1 to go" : "\(left) to go")
                                .font(.subheadline).foregroundStyle(Theme.inkSoft)
                        }
                    }
                    .padding(.horizontal, Theme.gutter)
                    .padding(.bottom, 32)
                }
                // Not on appear: a round opened partway through starts at the top.
                .onChange(of: index) { _, new in
                    withAnimation(.snappy) { proxy.scrollTo(new, anchor: .bottom) }
                }
                .paneBottomFade(true)
            }
        }
        .background(Theme.paper.ignoresSafeArea())
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("round-sheet")
    }

    private func row(_ i: Int, _ item: QuizItem) -> some View {
        let outcome = outcomes[safe: i] ?? nil
        let current = i == index && !finished
        let genre = app.library.genre(item.genreID)
        return HStack(alignment: .firstTextBaseline, spacing: 14) {
            Text("\(i + 1)")
                .font(Theme.serif(.headline, weight: .bold))
                .foregroundStyle(current ? Theme.accent : Theme.inkSoft)
                .frame(width: 24, alignment: .leading)
                .monospacedDigit()
            VStack(alignment: .leading, spacing: 3) {
                Kicker(text: [genre?.name, item.mode == .trivia ? nil : item.mode.title].compactMap { $0 }.joined(separator: " · "),
                       color: Theme.accent)
                if let outcome {
                    if item.mode == .trivia || item.mode == .hard || item.mode == .covers {
                        Text(item.prompt).font(.subheadline).foregroundStyle(Theme.inkSoft)
                    }
                    Text(item.choices[item.correctIndex].label)
                        .font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ink)
                        .accessibilityValue(outcome ? "Right" : "Missed")
                } else {
                    Text(item.audioSongID == nil ? "Your turn" : "Now playing")
                        .font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ink)
                }
            }
            Spacer(minLength: 8)
            if let outcome {
                Image(systemName: outcome ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .font(.body)
                    .foregroundStyle(outcome ? Theme.correct : Theme.accent)
                    .accessibilityHidden(true)
            }
        }
        .padding(.vertical, 12)
        .accessibilityElement(children: .combine)
    }
}

/// End of a round: the score, a recap of every question, and what to do next.
struct ResultView: View {
    @Environment(AppModel.self) private var app
    let spec: QuizSpec
    let outcomes: [Bool?]
    /// Off when the round's sheet already lists every answer beside the score.
    var showsRecap = true
    let onDone: () -> Void

    var body: some View {
        let correct = outcomes.compactMap { $0 }.filter { $0 }.count
        let total = outcomes.compactMap { $0 }.count
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Kicker(text: spec.isDaily ? "Today's Mix" : "\(spec.title) · \(spec.mode?.title ?? "")", color: Theme.accent)
                    Text("\(correct) of \(total)").font(Theme.display(64)).foregroundStyle(Theme.ink)
                        .accessibilityIdentifier("result-score")
                }
                .padding(.top, 8)

                if showsRecap {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(spec.items.enumerated()), id: \.offset) { i, item in
                            recapRow(item, outcome: outcomes[safe: i] ?? nil)
                            if i < spec.items.count - 1 { Divider().overlay(Theme.rule) }
                        }
                    }
                    .padding(.horizontal, 16)
                    .card()
                }

                VStack(spacing: 10) {
                    if !spec.isDaily, let mode = spec.mode {
                        Button("Play another round") {
                            let crate: Genre? = if case .crate(let id) = spec.source { app.library.genre(id) } else { nil }
                            onDone()
                            Task { @MainActor in
                                try? await Task.sleep(for: .milliseconds(450))
                                app.start(mode: mode, crate: crate)
                            }
                        }
                        .buttonStyle(PrimaryButtonStyle())
                        .accessibilityIdentifier("play-again")
                    }
                    ShareLink(item: shareText(correct: correct, total: total)) {
                        Label("Share score", systemImage: "square.and.arrow.up").font(.headline)
                            .frame(maxWidth: .infinity, minHeight: 52)
                    }
                    .buttonStyle(PressableStyle())
                    .foregroundStyle(Theme.ink)
                    .card()
                    // The frame goes on the label so the whole row is tappable, not just the word.
                    Button(action: onDone) {
                        Text("Done").font(.headline)
                            .frame(maxWidth: .infinity, minHeight: 52)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(PressableStyle())
                    .foregroundStyle(Theme.inkSoft)
                        .accessibilityIdentifier("result-done")
                }
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.bottom, 32)
        }
    }

    private func recapRow(_ item: QuizItem, outcome: Bool?) -> some View {
        let answer = item.choices[item.correctIndex]
        return HStack(alignment: .top, spacing: 12) {
            Image(systemName: outcome == nil ? "minus.circle" : (outcome! ? "checkmark.circle.fill" : "xmark.circle.fill"))
                .foregroundStyle(outcome == nil ? Theme.inkSoft : (outcome! ? Theme.correct : Theme.accent))
                .font(.body)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 3) {
                Text(item.mode == .trivia || item.mode == .covers ? item.prompt : item.mode.title)
                    .font(.subheadline).foregroundStyle(Theme.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
                Text(answer.label)
                    .font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ink)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 12)
    }

    private func shareText(correct: Int, total: Int) -> String {
        let marks = outcomes.map { $0 == nil ? "▫️" : ($0! ? "🟩" : "🟥") }.joined()
        let what = spec.isDaily ? "today's Deep Cuts mix" : "Deep Cuts \(spec.mode?.title ?? "") (\(spec.title))"
        return "\(correct)/\(total) on \(what)\n\(marks)"
    }
}

extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}
