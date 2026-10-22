import SwiftUI

struct PlayView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    VStack(alignment: .leading, spacing: 6) {
                        Kicker(text: "All your crates")
                        Text("Play").font(Theme.display(40)).foregroundStyle(Theme.ink)
                    }
                    .padding(.top, 12)

                    VStack(spacing: 10) {
                        ForEach(QuizMode.allCases.filter { app.offers($0, crate: nil) }) { mode in
                            ModeRow(mode: mode) { app.start(mode: mode, crate: nil) }
                        }
                    }

                    crateList(title: "Your Crates", genres: app.library.genres.filter { app.progress.focus.contains($0.id) })
                    let others = app.library.genres.filter { !app.progress.focus.contains($0.id) }
                    if !others.isEmpty {
                        crateList(title: "More Crates", genres: others)
                    }
                }
                .padding(.horizontal, Theme.gutter)
                .padding(.bottom, 32)
            }
            .paperPage()
            .navigationDestination(for: String.self) { id in
                if let genre = app.library.genre(id) { CrateView(genre: genre) }
            }
            .navigationDestination(for: Story.self) { StoryView(story: $0) }
        }
    }

    private func crateList(title: String, genres: [Genre]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            SectionHeader(title: title)
            ForEach(genres) { genre in
                NavigationLink(value: genre.id) { CrateRow(genre: genre) }
                    .buttonStyle(PressableStyle())
                    .accessibilityIdentifier("open-\(genre.id)")
                Divider().overlay(Theme.rule)
            }
        }
    }
}

struct ModeRow: View {
    let mode: QuizMode
    var compact = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: mode.symbol)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 44, height: 44)
                    .background(Theme.accent.opacity(0.1), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(mode.title).font(.headline).foregroundStyle(Theme.ink)
                    Text(mode.pitch).font(.subheadline).foregroundStyle(Theme.inkSoft)
                }
                Spacer()
                Image(systemName: "play.fill").font(.footnote).foregroundStyle(Theme.inkSoft)
            }
            .padding(12)
            .card()
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .accessibilityIdentifier("mode-\(mode.rawValue)")
    }
}

struct CrateRow: View {
    @Environment(AppModel.self) private var app
    let genre: Genre

    var body: some View {
        let tally = app.progress.tally(crate: genre.id)
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Theme.crate(genre.id))
                Image(systemName: Theme.crateSymbol(genre.id)).font(.system(size: 17, weight: .semibold)).foregroundStyle(.white)
            }
            .frame(width: 40, height: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(genre.name).font(.headline).foregroundStyle(Theme.ink)
                Text(subtitle(tally)).font(.subheadline).foregroundStyle(Theme.inkSoft)
            }
            Spacer()
            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Theme.inkSoft)
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }

    private func subtitle(_ tally: Tally) -> String {
        let seen = app.progress.seenCount(in: genre)
        guard let accuracy = tally.accuracy else { return genre.eraLabel }
        return "\(Int((accuracy * 100).rounded()))% right · \(seen) of \(genre.questions.count) questions seen"
    }
}

/// One crate: what it is, how you're doing, three ways to play, and its records and stories.
struct CrateView: View {
    @Environment(AppModel.self) private var app
    let genre: Genre

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                header
                VStack(spacing: 10) {
                    ForEach(QuizMode.allCases.filter { app.offers($0, crate: genre) }) { mode in
                        ModeRow(mode: mode) { app.start(mode: mode, crate: genre) }
                    }
                }
                if !genre.stories.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        SectionHeader(title: "Stories")
                        ForEach(genre.stories) { story in
                            NavigationLink(value: story) { StoryRow(story: story, genre: genre) }
                                .buttonStyle(PressableStyle())
                        }
                    }
                }
                VStack(alignment: .leading, spacing: 4) {
                    SectionHeader(title: "The Essentials", trailing: "\(genre.songs.count) records")
                    ForEach(genre.songs.sorted { $0.year < $1.year }) { song in
                        SongRow(song: song)
                        Divider().overlay(Theme.rule)
                    }
                    Text("Previews courtesy of Apple Music").font(.caption2).foregroundStyle(Theme.inkSoft).padding(.top, 6)
                }
                if !genre.coverSongs.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        SectionHeader(title: "Famous Covers", trailing: "\(genre.coverSongs.count) records")
                        ForEach(genre.coverSongs.sorted { $0.year < $1.year }) { cover in
                            SongRow(song: cover.asSong)
                            Divider().overlay(Theme.rule)
                        }
                    }
                }
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.bottom, 32)
        }
        .paperPage()
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear { app.player.stop() }
    }

    private var header: some View {
        let tally = app.progress.tally(crate: genre.id)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: Theme.crateSymbol(genre.id))
                Kicker(text: genre.eraLabel, color: .white.opacity(0.85))
            }
            .font(.caption.weight(.bold))
            .foregroundStyle(.white.opacity(0.85))
            Text(genre.name).font(Theme.display(36)).foregroundStyle(.white)
            Text(genre.blurb).font(.body).foregroundStyle(.white.opacity(0.9))
                .fixedSize(horizontal: false, vertical: true)
            if let accuracy = tally.accuracy {
                HStack(spacing: 18) {
                    stat("\(Int((accuracy * 100).rounded()))%", "right")
                    stat("\(app.progress.seenCount(in: genre))/\(genre.questions.count)", "questions seen")
                }
                .padding(.top, 4)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.crate(genre.id), in: RoundedRectangle(cornerRadius: Theme.radius + 4, style: .continuous))
        .padding(.top, 8)
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(value).font(Theme.serif(.title3, weight: .bold)).foregroundStyle(.white)
            Text(label).font(.caption).foregroundStyle(.white.opacity(0.8))
        }
    }
}
