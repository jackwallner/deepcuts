import SwiftUI

struct TodayView: View {
    @Environment(AppModel.self) private var app
    @Binding var tab: RootView.Tab
    @State private var showAllMoments = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    header
                    DailyMixCard()
                    if let pick = app.storyOfTheDay() {
                        storyCard(pick.story, genre: pick.genre)
                    }
                    moments
                    suggest
                }
                .padding(.horizontal, Theme.gutter)
                .padding(.bottom, 32)
            }
            .paperPage()
            .navigationDestination(for: Story.self) { StoryView(story: $0) }
            .task { await app.loadMoments() }
            .refreshable { await app.loadMoments(force: true) }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Kicker(text: Date.now.formatted(.dateTime.weekday(.wide).month(.wide).day()))
            Text("Deep Cuts").font(Theme.display(40)).foregroundStyle(Theme.ink)
        }
        .padding(.top, 12)
        .accessibilityElement(children: .combine)
    }

    private func storyCard(_ story: Story, genre: Genre) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Liner Notes", trailing: "\(story.readingMinutes) min read")
            NavigationLink(value: story) {
                HStack(alignment: .top, spacing: 14) {
                    ArtworkView(songID: app.library.artKey(for: story), size: 92, corner: 4)
                    VStack(alignment: .leading, spacing: 6) {
                        Kicker(text: "\(genre.name) · \(String(story.year))", color: Theme.crate(genre.id))
                        Text(story.title).font(Theme.serif(.title3, weight: .bold)).foregroundStyle(Theme.ink)
                            .multilineTextAlignment(.leading)
                        Text(story.dek).font(.subheadline).foregroundStyle(Theme.inkSoft)
                            .multilineTextAlignment(.leading).lineLimit(3)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("story-of-the-day")
        }
    }

    @ViewBuilder
    private var moments: some View {
        let all = app.moments
        if !all.isEmpty || app.momentsFailed {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "On This Day", trailing: Date.now.formatted(.dateTime.month(.abbreviated).day()))
                if all.isEmpty {
                    Text("Music history needs a connection. Pull down to try again.")
                        .font(.subheadline).foregroundStyle(Theme.inkSoft)
                }
                ForEach(showAllMoments ? all : Array(all.prefix(5))) { moment in
                    MomentRow(moment: moment)
                }
                if all.count > 5 {
                    Button(showAllMoments ? "Show fewer" : "Show all \(all.count)") {
                        withAnimation(.snappy) { showAllMoments.toggle() }
                    }
                    .font(.subheadline.weight(.semibold))
                }
                Text("From Wikipedia").font(.caption2).foregroundStyle(Theme.inkSoft)
            }
        }
    }

    private var suggest: some View {
        Button {
            app.requestFeedback(context: "Today screen")
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "lightbulb").font(.title3).foregroundStyle(Theme.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Got an idea for Deep Cuts?").font(.headline).foregroundStyle(Theme.ink)
                    Text("Tell Jack. Suggestions turn into new test builds.").font(.subheadline).foregroundStyle(Theme.inkSoft)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Theme.inkSoft)
            }
            .padding(16)
            .card()
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("suggest-today")
    }
}

struct MomentRow: View {
    let moment: MusicMoment

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            Text(String(moment.year))
                .font(Theme.serif(.headline, weight: .bold))
                .foregroundStyle(Theme.accent)
                .frame(width: 48, alignment: .leading)
            VStack(alignment: .leading, spacing: 3) {
                Text(moment.kind == .born ? "Born: \(moment.displayText)" : moment.displayText)
                    .font(.subheadline).foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                if let connection = moment.connection {
                    Label("In your crates: \(connection)", systemImage: "opticaldisc").font(.caption.weight(.semibold)).foregroundStyle(Theme.inkSoft)
                }
            }
            Spacer(minLength: 0)
            if let link = moment.link {
                Link(destination: link) {
                    Image(systemName: "arrow.up.right").font(.caption.weight(.bold)).foregroundStyle(Theme.inkSoft)
                        .frame(width: 32, height: 32)
                }
                .accessibilityLabel("Read on Wikipedia")
            }
        }
    }
}

/// The inverted "sleeve" card with today's mix: play it, or see how you did.
struct DailyMixCard: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        let result = app.progress.dailyResult()
        let streak = app.progress.streak()
        let songs = Array(app.dailyPreviewSongs().prefix(3))
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Kicker(text: "Today's Mix", color: Theme.onSleeve.opacity(0.7))
                    if let result {
                        Text("\(result.correct) of \(result.total)").font(Theme.display(44)).foregroundStyle(Theme.onSleeve)
                    } else {
                        Text("10 questions").font(Theme.display(32)).foregroundStyle(Theme.onSleeve)
                        Text(crateLine).font(.subheadline).foregroundStyle(Theme.onSleeve.opacity(0.8))
                            .lineLimit(2)
                    }
                }
                Spacer(minLength: 8)
                fan(songs)
            }
            if streak > 1 {
                Text("\(streak) days in a row")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.onSleeve.opacity(0.8))
            }
            if result == nil {
                Button("Play today's mix") { app.startDaily() }
                    .buttonStyle(PrimaryButtonStyle())
                    .accessibilityIdentifier("play-daily")
            } else {
                Text("A new mix lands tomorrow. Keep going in Play.")
                    .font(.footnote).foregroundStyle(Theme.onSleeve.opacity(0.7))
            }
        }
        .padding(20)
        .background(Theme.sleeve, in: RoundedRectangle(cornerRadius: Theme.radius + 4, style: .continuous))
    }

    private var crateLine: String {
        let names = app.focusGenres.map(\.name)
        if names.count <= 3 { return "From " + names.formatted(.list(type: .and)) }
        return "From \(names.prefix(2).joined(separator: ", ")) and \(names.count - 2) more"
    }

    private func verdict(_ r: QuizResult) -> String {
        switch Double(r.correct) / Double(max(1, r.total)) {
        case 0.9...: "Liner-note level. Nicely done."
        case 0.7..<0.9: "Solid. You know your records."
        case 0.4..<0.7: "Respectable. Some deep cuts got you."
        default: "Tough mix today. Tomorrow's yours."
        }
    }

    /// Record sleeves fanned out like the front of a crate.
    private func fan(_ songs: [String]) -> some View {
        ZStack {
            ForEach(Array(songs.enumerated()), id: \.offset) { index, id in
                ArtworkView(songID: id, size: 64, corner: 3)
                    .rotationEffect(.degrees(Double(index - 1) * 9))
                    .offset(x: CGFloat(index - 1) * 16, y: CGFloat(abs(index - 1)) * 4)
                    .shadow(color: .black.opacity(0.35), radius: 4, y: 2)
            }
        }
        .frame(width: 104, height: 84)
    }
}
