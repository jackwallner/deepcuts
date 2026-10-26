import SwiftUI

/// The order of the Today screen, and how far the Live tab looks for venues.
struct SettingsView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                VStack(alignment: .leading, spacing: 6) {
                    Kicker(text: "Make it yours")
                    Text("Settings").font(Theme.display(40)).foregroundStyle(Theme.ink)
                }
                .padding(.top, 12)

                todayOrder
                venueDistance
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.bottom, 32)
        }
        .paperPage()
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: Today order

    private var todayOrder: some View {
        let order = app.progress.todayOrder
        return VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Today Screen")
            note("Top to bottom. Move a section up or down.")
            VStack(spacing: 0) {
                ForEach(Array(order.enumerated()), id: \.element) { index, section in
                    orderRow(section, index: index, count: order.count)
                    if index < order.count - 1 { Divider().overlay(Theme.rule) }
                }
            }
            .padding(.horizontal, 16)
            .card()
            if order != TodaySection.allCases {
                Button("Restore the original order") { move { $0 = TodaySection.allCases } }
                    .font(.subheadline.weight(.semibold))
                    .accessibilityIdentifier("today-order-reset")
            }
        }
    }

    private func orderRow(_ section: TodaySection, index: Int, count: Int) -> some View {
        HStack(spacing: 12) {
            Text("\(index + 1)")
                .font(Theme.serif(.headline, weight: .bold)).foregroundStyle(Theme.accent)
                .frame(minWidth: 20, alignment: .leading)
            Text(section.title).font(.headline).foregroundStyle(Theme.ink)
            Spacer(minLength: 8)
            arrow("chevron.up", "Move \(section.title) up", id: "move-up-\(section.rawValue)", enabled: index > 0) {
                move { $0.swapAt(index, index - 1) }
            }
            arrow("chevron.down", "Move \(section.title) down", id: "move-down-\(section.rawValue)", enabled: index < count - 1) {
                move { $0.swapAt(index, index + 1) }
            }
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("today-row-\(section.rawValue)")
    }

    private func arrow(_ symbol: String, _ label: String, id: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.footnote.weight(.bold))
                .foregroundStyle(enabled ? Theme.accent : Theme.rule)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .disabled(!enabled)
        .accessibilityLabel(label)
        .accessibilityIdentifier(id)
    }

    private func move(_ change: (inout [TodaySection]) -> Void) {
        var order = app.progress.todayOrder
        change(&order)
        withAnimation(.snappy) { app.progress.setTodayOrder(order) }
    }

    // MARK: Venue distance

    private var venueDistance: some View {
        let miles = Binding(get: { app.progress.venueMiles }, set: { app.progress.setVenueMiles($0) })
        return VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Near You")
            note("How far the Live tab looks for clubs, theaters and amphitheaters.")
            Picker("Distance", selection: miles) {
                ForEach(VenueFinder.distanceOptions, id: \.self) { Text("\($0) mi").tag($0) }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("venue-distance")
        }
    }

    private func note(_ text: String) -> some View {
        Text(text).font(.subheadline).foregroundStyle(Theme.inkSoft)
            .fixedSize(horizontal: false, vertical: true)
    }
}
