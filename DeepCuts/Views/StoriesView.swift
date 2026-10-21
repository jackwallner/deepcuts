import SwiftUI

struct StoriesView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 6) {
                        Kicker(text: "Liner notes")
                        Text("Stories").font(Theme.display(40)).foregroundStyle(Theme.ink)
                        Text("How the records got made, and the people who made them.")
                            .font(.subheadline).foregroundStyle(Theme.inkSoft)
                    }
                    .padding(.top, 12)

                    let all = app.library.stories(focus: app.progress.focus)
                    VStack(alignment: .leading, spacing: 16) {
                        ForEach(all, id: \.story.id) { pair in
                            NavigationLink(value: pair.story) { StoryRow(story: pair.story, genre: pair.genre) }
                                .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.horizontal, Theme.gutter)
                .padding(.bottom, 32)
            }
            .background(Theme.paper.ignoresSafeArea())
            .navigationDestination(for: Story.self) { StoryView(story: $0) }
        }
    }
}

struct StoryRow: View {
    @Environment(AppModel.self) private var app
    let story: Story
    let genre: Genre

    var body: some View {
        let read = app.progress.data.readStories.contains(story.id)
        HStack(alignment: .top, spacing: 14) {
            ArtworkView(songID: story.songs.first, size: 76, corner: 4)
            VStack(alignment: .leading, spacing: 4) {
                Kicker(text: "\(genre.name) · \(String(story.year))", color: Theme.crate(genre.id))
                Text(story.title).font(Theme.serif(.headline, weight: .bold)).foregroundStyle(Theme.ink)
                    .multilineTextAlignment(.leading)
                Text(story.dek).font(.subheadline).foregroundStyle(Theme.inkSoft).lineLimit(2)
                    .multilineTextAlignment(.leading)
                Text(read ? "Read" : "\(story.readingMinutes) min read")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(read ? Theme.correct : Theme.inkSoft)
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
        .accessibilityIdentifier("story-\(story.id)")
    }
}

struct StoryView: View {
    @Environment(AppModel.self) private var app
    let story: Story

    var body: some View {
        let genre = app.library.genre(forSong: story.songs.first ?? "")
        let songs = story.songs.compactMap { app.library.song($0) }
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                ArtworkView(songID: story.songs.first, size: 300, corner: 6)
                    .frame(maxWidth: .infinity)
                    .shadow(color: .black.opacity(0.18), radius: 16, y: 8)
                    .padding(.top, 8)
                VStack(alignment: .leading, spacing: 8) {
                    if let genre {
                        Kicker(text: "\(genre.name) · \(String(story.year))", color: Theme.crate(genre.id))
                    }
                    Text(story.title).font(Theme.display(32)).foregroundStyle(Theme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(story.dek).font(Theme.serif(.title3, weight: .regular)).italic().foregroundStyle(Theme.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Rectangle().fill(Theme.ink).frame(width: 40, height: 2)
                ForEach(Array(story.paragraphs.enumerated()), id: \.offset) { _, paragraph in
                    Text(paragraph)
                        .font(.system(.body, design: .serif))
                        .lineSpacing(5)
                        .foregroundStyle(Theme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !songs.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        SectionHeader(title: "Listen")
                        ForEach(songs) { song in
                            SongRow(song: song)
                            if let link = app.library.catalog[song.id]?.trackViewUrl.flatMap(URL.init(string:)) {
                                Link(destination: link) {
                                    Label("Open in Apple Music", systemImage: "arrow.up.right.square")
                                        .font(.footnote.weight(.semibold))
                                }
                                .padding(.leading, 68)
                                .padding(.bottom, 6)
                            }
                            Divider().overlay(Theme.rule)
                        }
                    }
                    .padding(.top, 8)
                }
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.bottom, 40)
        }
        .background(Theme.paper.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { app.progress.markRead(story) }
        .onDisappear { app.player.stop() }
    }
}
