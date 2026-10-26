import SwiftUI
import UIKit

/// Live music for the listener's crates: venues nearby, and tour dates for acts still on the road.
struct LiveView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.openURL) private var openURL
    @State private var locator = LocationProvider()
    @State private var venues: [Venue]?
    @State private var searchFailed = false
    private let stubVenues = ProcessInfo.processInfo.arguments.contains("-ui-venues-stub")

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    VStack(alignment: .leading, spacing: 6) {
                        Kicker(text: "On the road")
                        Text("Live").font(Theme.display(40)).foregroundStyle(Theme.ink)
                        Text("Music venues near you, and tour dates for the artists in your crates.")
                            .font(.subheadline).foregroundStyle(Theme.inkSoft)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.top, 12)

                    nearby
                    onTour
                }
                .padding(.horizontal, Theme.gutter)
                .padding(.bottom, 32)
            }
            .paperPage()
            .task {
                if stubVenues { venues = VenueFinder.sample } else { locator.resume() }
            }
            .task(id: locator.location) { await search() }
            .onChange(of: app.progress.venueMiles) { Task { await search() } }
        }
    }

    private func search() async {
        guard let location = locator.location else { return }
        do {
            venues = try await VenueFinder.nearby(location, miles: app.progress.venueMiles)
            searchFailed = false
        } catch {
            searchFailed = venues == nil
        }
    }

    // MARK: Near you

    private var nearby: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Near You", trailing: "Within \(app.progress.venueMiles) mi")
            if let venues {
                if venues.isEmpty {
                    note("No music venues turned up within \(app.progress.venueMiles) miles. You can look farther in You > Settings.")
                } else {
                    VStack(spacing: 0) {
                        ForEach(venues) { venue in
                            venueRow(venue)
                            if venue != venues.last { Divider().overlay(Theme.rule) }
                        }
                    }
                    note("Clubs, theaters and amphitheaters that book touring acts. Tap one for its calendar, or the map when it has no website. Change the distance in You > Settings.")
                }
            } else {
                locationState
            }
        }
    }

    @ViewBuilder
    private var locationState: some View {
        switch locator.status {
        case .notAsked:
            VStack(alignment: .leading, spacing: 12) {
                note("Deep Cuts can look up concert halls, clubs and theaters around you on Apple Maps. Your location is only used for this search and is never stored or shared.")
                Button("Find venues near me") { locator.request() }
                    .buttonStyle(PrimaryButtonStyle())
                    .accessibilityIdentifier("live-locate")
            }
        case .locating, .located where !searchFailed:
            HStack(spacing: 10) {
                ProgressView()
                Text("Finding venues near you").font(.subheadline).foregroundStyle(Theme.inkSoft)
            }
            .padding(.vertical, 8)
        case .denied:
            VStack(alignment: .leading, spacing: 10) {
                note("Location is off for Deep Cuts, so it can't look up venues near you. You can turn it on in Settings, or use the tour dates below.")
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                }
                .font(.subheadline.weight(.semibold))
            }
        case .failed, .located:
            VStack(alignment: .leading, spacing: 10) {
                note("Couldn't find venues right now. Check your connection and try again.")
                Button("Try again") {
                    searchFailed = false
                    if locator.location == nil { locator.request() } else { Task { await search() } }
                }
                    .font(.subheadline.weight(.semibold))
            }
        }
    }

    private func venueRow(_ venue: Venue) -> some View {
        Button {
            if let url = venue.website ?? venue.mapURL { openURL(url) }
        } label: {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(venue.name).font(.headline).foregroundStyle(Theme.ink)
                        .multilineTextAlignment(.leading)
                    Text([venue.area, venue.distanceLabel].compactMap { $0 }.joined(separator: " · "))
                        .font(.subheadline).foregroundStyle(Theme.inkSoft)
                }
                Spacer(minLength: 8)
                Label(venue.website == nil ? "Map" : "Calendar", systemImage: "arrow.up.right")
                    .labelStyle(TrailingIconLabelStyle())
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.accent)
            }
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .accessibilityIdentifier("venue-\(venue.name)")
    }

    // MARK: On tour

    private var onTour: some View {
        let acts = LiveMusic.acts(in: app.focusGenres)
        return VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Your Artists Live")
            if acts.isEmpty {
                note("None of the artists in your crates are on the road right now.")
            } else {
                note("Acts from your crates who still play shows. Tap one to see upcoming dates on Ticketmaster.")
                VStack(spacing: 0) {
                    ForEach(acts) { act in
                        actRow(act)
                        if act != acts.last { Divider().overlay(Theme.rule) }
                    }
                }
            }
        }
    }

    private func actRow(_ act: LiveMusic.Act) -> some View {
        Button {
            if let url = LiveMusic.tourDatesURL(for: act.name) { openURL(url) }
        } label: {
            HStack(alignment: .center, spacing: 12) {
                ArtworkView(songID: act.songID, size: 48, corner: 4)
                VStack(alignment: .leading, spacing: 2) {
                    Text(act.name).font(.headline).foregroundStyle(Theme.ink)
                        .multilineTextAlignment(.leading)
                    Kicker(text: act.genre.name, color: Theme.crate(act.genre.id))
                }
                Spacer(minLength: 8)
                Label("Dates", systemImage: "arrow.up.right")
                    .labelStyle(TrailingIconLabelStyle())
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.accent)
            }
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel("\(act.name), tour dates")
        .accessibilityIdentifier("act-\(act.name)")
    }

    private func note(_ text: String) -> some View {
        Text(text).font(.subheadline).foregroundStyle(Theme.inkSoft)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// "Dates ↗": the title, then the icon.
private struct TrailingIconLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 3) {
            configuration.title
            configuration.icon.imageScale(.small)
        }
    }
}
