import SwiftUI

/// First run: pick the crates you want questions and stories from.
struct OnboardingView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        FocusPicker(
            title: "What do you\nlisten to?",
            subtitle: "Pick your crates. Your daily mix, clips and stories come from these. Change them anytime.",
            action: "Start digging",
            initial: []
        ) { picked in
            app.progress.setFocus(picked)
        }
    }
}

/// Multi-select list of crates. Used for onboarding and for editing focus areas later.
struct FocusPicker: View {
    @Environment(AppModel.self) private var app
    let title: String
    let subtitle: String
    let action: String
    let initial: [String]
    let onDone: ([String]) -> Void

    @State private var picked: [String] = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 10) {
                    Kicker(text: "Deep Cuts", color: Theme.accent)
                    Text(title).font(Theme.display(38)).foregroundStyle(Theme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(subtitle).font(.body).foregroundStyle(Theme.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 24)

                VStack(spacing: 0) {
                    ForEach(app.library.genres) { genre in
                        row(genre)
                        if genre.id != app.library.genres.last?.id { Divider().overlay(Theme.rule).padding(.leading, 64) }
                    }
                }
                .card()
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.bottom, 120)
        }
        .background(Theme.paper.ignoresSafeArea())
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 8) {
                Button(picked.isEmpty ? "Pick at least one" : "\(action) (\(picked.count))") {
                    onDone(app.library.genres.map(\.id).filter(picked.contains))
                }
                .buttonStyle(PrimaryButtonStyle(fill: picked.isEmpty ? Theme.rule : Theme.accent, text: picked.isEmpty ? Theme.inkSoft : .white))
                .disabled(picked.isEmpty)
                .accessibilityIdentifier("focus-done")
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.vertical, 12)
            .background(Theme.paper.opacity(0.97))
            .overlay(alignment: .top) { Rectangle().fill(Theme.rule).frame(height: 1) }
        }
        .onAppear { picked = initial }
    }

    private func row(_ genre: Genre) -> some View {
        let on = picked.contains(genre.id)
        return Button {
            if on { picked.removeAll { $0 == genre.id } } else { picked.append(genre.id) }
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Theme.crate(genre.id))
                    Image(systemName: Theme.crateSymbol(genre.id)).font(.system(size: 17, weight: .semibold)).foregroundStyle(.white)
                }
                .frame(width: 38, height: 38)
                VStack(alignment: .leading, spacing: 2) {
                    Text(genre.name).font(.headline).foregroundStyle(Theme.ink)
                    Text(genre.eraLabel).font(.subheadline).foregroundStyle(Theme.inkSoft)
                }
                Spacer()
                Image(systemName: on ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(on ? Theme.accent : Theme.rule)
                    .contentTransition(.symbolEffect(.replace))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: on)
        .accessibilityAddTraits(on ? .isSelected : [])
        .accessibilityIdentifier("crate-\(genre.id)")
    }
}
