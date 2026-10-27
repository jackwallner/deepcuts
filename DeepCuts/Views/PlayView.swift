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

                    ModeList(modes: QuizMode.allCases.filter { app.offers($0, crate: nil) }) {
                        app.start(mode: $0, crate: nil)
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

/// The ways to play, as a ruled menu: name on the left, length on the right.
struct ModeList: View {
    let modes: [QuizMode]
    let start: (QuizMode) -> Void

    var body: some View {
        VStack(spacing: 0) {
            ForEach(modes) { mode in
                ModeRow(mode: mode) { start(mode) }
                Divider().overlay(Theme.rule)
            }
        }
        .overlay(alignment: .top) { Rectangle().fill(Theme.ink).frame(height: 1.5) }
    }
}

struct ModeRow: View {
    let mode: QuizMode
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(mode.title).font(Theme.serif(.title3, weight: .bold)).foregroundStyle(Theme.ink)
                    if let detail = mode.detail {
                        Text(detail).font(.subheadline).foregroundStyle(Theme.inkSoft)
                    }
                }
                Spacer(minLength: 8)
                Text(mode.length).font(.subheadline).foregroundStyle(Theme.inkSoft)
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Theme.inkSoft)
            }
            .padding(.vertical, 14)
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
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(genre.name).font(.headline).foregroundStyle(Theme.ink)
                Text(subtitle).font(.subheadline).foregroundStyle(Theme.inkSoft)
            }
            Spacer()
            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Theme.inkSoft)
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }

    private var subtitle: String {
        let seen = app.progress.seenCount(in: genre)
        return seen == 0 ? genre.eraLabel : "\(genre.eraLabel) · \(seen) of \(genre.questions.count) played"
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
                ModeList(modes: QuizMode.allCases.filter { app.offers($0, crate: genre) }) {
                    app.start(mode: $0, crate: genre)
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
        VStack(alignment: .leading, spacing: 10) {
            Kicker(text: genre.eraLabel, color: Theme.onSleeve.opacity(0.7))
            Text(genre.name).font(Theme.display(36)).foregroundStyle(Theme.onSleeve)
            Text(genre.blurb).font(.body).foregroundStyle(Theme.onSleeve.opacity(0.9))
                .fixedSize(horizontal: false, vertical: true)
            let seen = app.progress.seenCount(in: genre)
            if seen > 0 {
                Text("\(seen) of \(genre.questions.count) played")
                    .font(.subheadline.weight(.semibold)).foregroundStyle(Theme.onSleeve.opacity(0.7))
                    .padding(.top, 4)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.sleeve, in: RoundedRectangle(cornerRadius: Theme.radius + 4, style: .continuous))
        .padding(.top, 8)
    }
}
