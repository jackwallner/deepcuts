import SwiftUI

/// Runs one round: trivia, clips and matchups share this screen.
struct QuizView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    let spec: QuizSpec

    @State private var index = 0
    @State private var picked: Int?
    @State private var outcomes: [Bool?] = []
    @State private var finished = false

    private var item: QuizItem { spec.items[index] }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            if finished {
                ResultView(spec: spec, outcomes: outcomes) { dismiss() }
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 20) {
                            question
                            if let picked { reveal(picked).id("reveal") }
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
                        guard new != nil else { return }
                        withAnimation(.snappy.delay(0.15)) { proxy.scrollTo("reveal", anchor: .bottom) }
                    }
                }
                .safeAreaInset(edge: .bottom) { bottomBar }
            }
        }
        .background(Theme.paper.ignoresSafeArea())
        .onAppear { outcomes = Array(repeating: nil, count: spec.items.count) }
        .onChange(of: index, initial: true) { _, _ in autoplay() }
        .onDisappear { app.player.stop() }
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
            Button(index + 1 < spec.items.count ? "Next" : "See results") { advance() }
                .buttonStyle(PrimaryButtonStyle(fill: Theme.ink, text: Theme.paper))
                .padding(.horizontal, Theme.gutter)
                .padding(.vertical, 10)
                .background(Theme.paper.opacity(0.96))
                .accessibilityIdentifier("quiz-next")
        }
    }

    // MARK: Question

    @ViewBuilder
    private var question: some View {
        let genre = app.library.genre(item.genreID)
        VStack(alignment: .leading, spacing: 10) {
            Kicker(text: [genre?.name, item.mode == .trivia ? nil : item.mode.title].compactMap { $0 }.joined(separator: " · "),
                   color: Theme.crate(item.genreID))
            Text(item.prompt)
                .font(Theme.serif(item.mode == .trivia ? .title2 : .title, weight: .bold))
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("quiz-prompt")
        }
        switch item.mode {
        case .tune:
            turntable
            choiceList
        case .firstOf:
            matchup
        case .trivia:
            choiceList
        }
    }

    private var choiceList: some View {
        VStack(spacing: 10) {
            ForEach(item.choices.indices, id: \.self) { i in
                Button { answer(i) } label: { ChoiceLabel(choice: item.choices[i], state: state(of: i)) }
                    .buttonStyle(.plain)
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
        item.mode == .tune && app.player.songID == item.audioSongID && app.player.state == .failed && picked == nil
    }

    private var turntable: some View {
        let playing = app.player.songID == item.audioSongID && app.player.state == .playing
        return VStack(spacing: 14) {
            VinylView(labelSongID: item.audioSongID, revealed: picked != nil, spinning: playing, size: 210,
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
                .buttonStyle(.plain)
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
                    .buttonStyle(.plain)
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
            if !right && item.mode != .firstOf {
                Text("It's \(answer.title)\(answer.subtitle.map { " by \($0)" } ?? "").")
                    .font(.body.weight(.semibold)).foregroundStyle(Theme.ink)
            }
            Text(item.fact).font(.body).foregroundStyle(Theme.ink.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .accessibilityElement(children: .combine)
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

/// End of a round: the score, a recap of every question, and what to do next.
struct ResultView: View {
    @Environment(AppModel.self) private var app
    let spec: QuizSpec
    let outcomes: [Bool?]
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
                    if spec.isDaily {
                        let streak = app.progress.streak()
                        Label(streak == 1 ? "Streak started" : "\(streak) day streak", systemImage: "flame.fill")
                            .font(.headline).foregroundStyle(Color(hex: 0xD9822B))
                    }
                }
                .padding(.top, 8)

                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(spec.items.enumerated()), id: \.offset) { i, item in
                        recapRow(item, outcome: outcomes[safe: i] ?? nil)
                        if i < spec.items.count - 1 { Divider().overlay(Theme.rule) }
                    }
                }
                .padding(.horizontal, 16)
                .card()

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
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.ink)
                    .card()
                    Button("Done", action: onDone)
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 44)
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
                Text(item.mode == .trivia ? item.prompt : item.mode.title)
                    .font(.subheadline).foregroundStyle(Theme.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
                Text(answer.title + (answer.subtitle.map { ", \($0)" } ?? ""))
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
