import SwiftUI

struct StoriesView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        @Bindable var app = app
        NavigationStack(path: $app.storyPath) {
            StoriesShelf()
                .navigationDestination(for: Story.self) { StoryView(story: $0) }
        }
    }
}

/// The trailing pane of the unfolded split: the shelf, or the story opened from any pane.
/// It has no navigation bar of its own, so its back button stays inside the pane.
struct StoriesPane: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        ZStack {
            StoriesShelf()
                .accessibilityHidden(!app.storyPath.isEmpty)
            if let story = app.storyPath.last {
                VStack(alignment: .leading, spacing: 0) {
                    Button {
                        withAnimation(.snappy) { app.storyPath.removeAll() }
                    } label: {
                        Label("Stories", systemImage: "chevron.left")
                            .font(.body.weight(.semibold))
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .padding(.horizontal, Theme.gutter - 4)
                    .accessibilityIdentifier("pane-back")
                    StoryView(story: story)
                        .id(story.id)
                }
                .background(Theme.paper.ignoresSafeArea())
                .transition(.move(edge: .trailing))
            }
        }
        .animation(.snappy, value: app.storyPath.last?.id)
    }
}

/// Every story from your crates, concerts first.
struct StoriesShelf: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 6) {
                    Kicker(text: "Liner notes")
                    Text("Stories").font(Theme.display(40)).foregroundStyle(Theme.ink)
                    Text("How the records got made, the people who made them, and the nights they played live.")
                        .font(.subheadline).foregroundStyle(Theme.inkSoft)
                }
                .padding(.top, 12)

                let all = app.library.stories(focus: app.progress.focus)
                let concerts = all.filter { $0.story.isConcert }
                if !concerts.isEmpty {
                    shelf("Concerts", concerts)
                }
                shelf(concerts.isEmpty ? nil : "Records & People", all.filter { !$0.story.isConcert })
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.bottom, 32)
        }
        .paperPage()
    }

    private func shelf(_ title: String?, _ stories: [(story: Story, genre: Genre)]) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            if let title { SectionHeader(title: title) }
            ForEach(stories, id: \.story.id) { pair in
                StoryLink(story: pair.story) { StoryRow(story: pair.story, genre: pair.genre) }
            }
        }
    }
}

/// Opens a story: pushed on the phone, in the reading pane when unfolded.
struct StoryLink<Label: View>: View {
    @Environment(AppModel.self) private var app
    @Environment(\.isUnfoldedPane) private var inPane
    let story: Story
    @ViewBuilder let label: Label

    var body: some View {
        Group {
            if inPane {
                Button {
                    withAnimation(.snappy) { app.storyPath = [story] }
                } label: { label }
            } else {
                NavigationLink(value: story) { label }
            }
        }
        .buttonStyle(PressableStyle())
    }
}

struct StoryRow: View {
    @Environment(AppModel.self) private var app
    let story: Story
    let genre: Genre

    var body: some View {
        let read = app.progress.data.readStories.contains(story.id)
        HStack(alignment: .top, spacing: 14) {
            ArtworkView(songID: app.library.artKey(for: story), size: 76, corner: 4)
            VStack(alignment: .leading, spacing: 4) {
                Kicker(text: "\(genre.name) · \(String(story.year))", color: Theme.accent)
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
                ArtworkView(songID: app.library.artKey(for: story), size: 300, corner: 6)
                    .frame(maxWidth: .infinity)
                    .shadow(color: .black.opacity(0.18), radius: 16, y: 8)
                    .padding(.top, 8)
                VStack(alignment: .leading, spacing: 8) {
                    if let genre {
                        Kicker(text: "\(genre.name) · \(String(story.year))", color: Theme.accent)
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
        .paperPage()
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .onAppear { app.progress.markRead(story) }
        .onDisappear { app.player.stop() }
    }
}
