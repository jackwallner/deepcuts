import SwiftUI

struct YouView: View {
    @Environment(AppModel.self) private var app
    @State private var editingFocus = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    VStack(alignment: .leading, spacing: 6) {
                        Kicker(text: "Your record")
                        Text("You").font(Theme.display(40)).foregroundStyle(Theme.ink)
                    }
                    .padding(.top, 12)

                    crates
                    settings
                    suggestions
                    about
                }
                .padding(.horizontal, Theme.gutter)
                .padding(.bottom, 32)
            }
            .paperPage()
            .task { await app.refreshFeedback() }
            .refreshable { await app.refreshFeedback() }
            .sheet(isPresented: $editingFocus) {
                FocusPicker(title: "Your crates", subtitle: "Today's mix, clips and stories come from these.",
                            action: "Save", initial: app.progress.focus) { picked in
                    app.progress.setFocus(picked); Task { await app.loadMoments(force: true) }
                    editingFocus = false
                }
                .environment(app)
            }
        }
    }

    private var crates: some View {
        VStack(alignment: .leading, spacing: 4) {
            SectionHeader(title: "Your Crates")
            ForEach(app.focusGenres) { genre in
                let seen = app.progress.seenCount(in: genre)
                HStack(alignment: .firstTextBaseline) {
                    Text(genre.name).font(.headline).foregroundStyle(Theme.ink)
                    Spacer()
                    Text("\(seen) of \(genre.questions.count) played")
                        .font(.subheadline).foregroundStyle(Theme.inkSoft).monospacedDigit()
                }
                .padding(.vertical, 10)
                .accessibilityElement(children: .combine)
                Divider().overlay(Theme.rule)
            }
            Button("Change crates") { editingFocus = true }
                .font(.subheadline.weight(.semibold))
                .padding(.top, 8)
                .accessibilityIdentifier("change-crates")
        }
    }

    private var settings: some View {
        NavigationLink {
            SettingsView()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "slider.horizontal.3").font(.title3).foregroundStyle(Theme.accent)
                Text("Settings").font(.headline).foregroundStyle(Theme.ink)
                Spacer()
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Theme.inkSoft)
            }
            .padding(16)
            .card()
        }
        .buttonStyle(PressableStyle())
        .accessibilityIdentifier("open-settings")
    }

    @ViewBuilder
    private var suggestions: some View {
        if Distribution.isTestFlight {
            testerSuggestions
        } else {
            Button("Send feedback") { app.requestFeedback(context: "You tab") }
                .buttonStyle(PrimaryButtonStyle(fill: Theme.ink, text: Theme.paper))
                .accessibilityIdentifier("suggest-you")
        }
    }

    /// TestFlight only: each suggestion becomes a build, and its status shows here.
    private var testerSuggestions: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Suggestions")
            Text("Ideas, fixes, anything you'd change. Each one goes to Jack's build assistant, which works on it and sends a new TestFlight build.")
                .font(.subheadline).foregroundStyle(Theme.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
            Button("Suggest a change") { app.requestFeedback(context: "You tab") }
                .buttonStyle(PrimaryButtonStyle())
                .accessibilityIdentifier("suggest-you")
            ForEach(app.myFeedback) { item in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Label(item.statusLabel, systemImage: icon(item.status))
                            .font(.caption.weight(.bold))
                            .foregroundStyle(item.status == "shipped" ? Theme.correct : Theme.accent)
                        Spacer()
                        Text(item.createdAt.formatted(.relative(presentation: .named))).font(.caption).foregroundStyle(Theme.inkSoft)
                    }
                    Text(item.text).font(.subheadline).foregroundStyle(Theme.ink).lineLimit(4)
                    if let reply = item.reply, !reply.isEmpty {
                        Text(reply).font(.footnote).foregroundStyle(Theme.inkSoft)
                            .padding(.leading, 10)
                            .overlay(alignment: .leading) { Rectangle().fill(Theme.rule).frame(width: 2) }
                    }
                }
                .padding(14)
                .card()
            }
        }
    }

    private func icon(_ status: String) -> String {
        switch status {
        case "shipped": "checkmark.seal.fill"
        case "working": "hammer.fill"
        case "needs_jack": "person.fill.questionmark"
        case "declined": "xmark.circle"
        default: "tray.and.arrow.down.fill"
        }
    }

    private var about: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionHeader(title: "About")
            Text("Song previews and artwork courtesy of Apple Music. On This Day from Wikipedia. Venues from Apple Maps.")
                .font(.footnote).foregroundStyle(Theme.inkSoft)
            Text(versionLine).font(.footnote).foregroundStyle(Theme.inkSoft)
        }
    }

    private var versionLine: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "Deep Cuts \(version) (\(build))"
    }
}
