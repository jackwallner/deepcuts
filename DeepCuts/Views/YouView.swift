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

                    stats
                    crates
                    suggestions
                    about
                }
                .padding(.horizontal, Theme.gutter)
                .padding(.bottom, 32)
            }
            .background(Theme.paper.ignoresSafeArea())
            .task { await app.refreshFeedback() }
            .refreshable { await app.refreshFeedback() }
            .sheet(isPresented: $editingFocus) {
                FocusPicker(title: "Your crates", subtitle: "Today's mix, clips and stories come from these.",
                            action: "Save", initial: app.progress.focus) { picked in
                    app.progress.setFocus(picked); Task { await app.loadMoments(force: true) }
                    editingFocus = false
                }
            }
        }
    }

    private var stats: some View {
        let overall = app.progress.overall
        return HStack(spacing: 0) {
            stat("\(app.progress.streak())", "days in a row")
            Divider().frame(height: 44).overlay(Theme.rule)
            stat("\(overall.answered)", "answered")
            Divider().frame(height: 44).overlay(Theme.rule)
            stat(overall.accuracy.map { "\(Int(($0 * 100).rounded()))%" } ?? "–", "right")
        }
        .padding(.vertical, 16)
        .card()
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(Theme.serif(.title, weight: .bold)).foregroundStyle(Theme.ink).monospacedDigit()
            Text(label).font(.caption).foregroundStyle(Theme.inkSoft)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    private var crates: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                SectionHeader(title: "Your Crates")
            }
            ForEach(app.focusGenres) { genre in
                let tally = app.progress.tally(crate: genre.id)
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(genre.name).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ink)
                        Spacer()
                        Text(tally.accuracy.map { "\(Int(($0 * 100).rounded()))% of \(tally.answered)" } ?? "Not played yet")
                            .font(.caption).foregroundStyle(Theme.inkSoft)
                    }
                    Meter(value: tally.accuracy ?? 0, color: Theme.crate(genre.id))
                }
            }
            Button("Change crates") { editingFocus = true }
                .font(.subheadline.weight(.semibold))
                .accessibilityIdentifier("change-crates")
        }
    }

    private var suggestions: some View {
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
            Text("Song previews and artwork courtesy of Apple Music. On This Day from Wikipedia.")
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
