import CoreLocation
import Foundation
import MapKit
import Observation

/// Live music: acts from each crate who still play shows, and music venues near the listener.
/// No concert listing API is free without an account, so tour dates open on Ticketmaster and
/// venues come from Apple Maps, whose sites carry their calendars.
enum LiveMusic {
    /// Acts in each crate still playing shows as of 2025-26. Names match the crate's song artists.
    static let touring: [String: [String]] = [
        "classic-rock": ["Eagles", "Journey", "Heart", "Styx", "Kansas", "Santana", "Foghat", "Blue Öyster Cult"],
        "southern-rock": ["Lynyrd Skynyrd", "ZZ Top", "38 Special", "The Marshall Tucker Band",
                          "Molly Hatchet", "Atlanta Rhythm Section"],
        "british-invasion": ["Herman's Hermits"],
        "heavy-metal": ["Metallica", "Iron Maiden", "Judas Priest", "AC/DC", "Scorpions", "Deep Purple"],
        "prog-rock": ["Yes", "Jethro Tull", "Kansas"],
        "motown-soul": ["Stevie Wonder", "The Temptations", "Gladys Knight & The Pips"],
        "folk-singer-songwriter": ["Bob Dylan", "Neil Young", "James Taylor", "Bruce Springsteen"],
        "yacht-rock": ["The Doobie Brothers", "Toto", "Michael McDonald", "Boz Scaggs", "Christopher Cross", "Air Supply"],
        "punk-new-wave": ["Duran Duran", "Devo", "New Order", "The Human League", "Echo & the Bunnymen"],
        "eighties": ["Journey", "Guns N' Roses", "Bruce Springsteen"],
        "grunge-alt": ["Pearl Jam", "Green Day", "Weezer", "The Smashing Pumpkins", "Pixies", "Nine Inch Nails",
                       "Alanis Morissette"],
        "pop": ["The Beach Boys"],
        "modern-pop": ["Lady Gaga", "Billie Eilish", "Dua Lipa", "The Weeknd", "Olivia Rodrigo", "Ariana Grande", "Mariah Carey"],
        "country": ["George Strait", "Willie Nelson", "Alan Jackson", "Shania Twain"],
        "blues": ["Buddy Guy"],
        "disco-funk": ["Earth, Wind & Fire", "KC and the Sunshine Band", "Chic", "Diana Ross"],
        "hip-hop": ["Kendrick Lamar", "Cardi B"],
    ]

    struct Act: Identifiable, Hashable {
        let name: String
        let genre: Genre
        /// A song of theirs in the crate, for the album art.
        let songID: String?

        var id: String { name }

        static func == (a: Act, b: Act) -> Bool { a.name == b.name }
        func hash(into hasher: inout Hasher) { hasher.combine(name) }
    }

    /// Touring acts across the given crates, each once, in crate order.
    static func acts(in genres: [Genre]) -> [Act] {
        var seen = Set<String>()
        return genres.flatMap { genre in
            (touring[genre.id] ?? []).compactMap { name in
                guard seen.insert(name).inserted else { return nil }
                return Act(name: name, genre: genre, songID: genre.songs.first { $0.artist == name }?.id)
            }
        }
    }

    /// Ticketmaster's search, which lists the act's upcoming dates near the listener first.
    static func tourDatesURL(for artist: String) -> URL? {
        var parts = URLComponents(string: "https://www.ticketmaster.com/search")
        parts?.queryItems = [URLQueryItem(name: "q", value: artist)]
        return parts?.url
    }
}

struct Venue: Identifiable, Hashable, Sendable {
    let name: String
    let area: String?
    let miles: Double
    let latitude: Double
    let longitude: Double
    /// The venue's own site, where its calendar lives.
    let website: URL?

    var id: String { "\(name)-\(latitude)-\(longitude)" }

    var mapURL: URL? {
        var parts = URLComponents(string: "https://maps.apple.com/")
        parts?.queryItems = [URLQueryItem(name: "q", value: name), URLQueryItem(name: "ll", value: "\(latitude),\(longitude)")]
        return parts?.url
    }

    var distanceLabel: String {
        miles < 10 ? String(format: "%.1f mi", miles) : "\(Int(miles.rounded())) mi"
    }
}

enum VenueFinder {
    static let radiusMeters: CLLocationDistance = 40_000

    @MainActor
    static func nearby(_ location: CLLocation) async throws -> [Venue] {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = "live music venue"
        request.region = MKCoordinateRegion(center: location.coordinate, latitudinalMeters: radiusMeters * 2, longitudinalMeters: radiusMeters * 2)
        request.resultTypes = .pointOfInterest
        if #available(iOS 18, *) {
            request.pointOfInterestFilter = MKPointOfInterestFilter(including: [.musicVenue, .nightlife, .theater])
        }
        let response = try await MKLocalSearch(request: request).start()
        let venues = response.mapItems.compactMap { item -> Venue? in
            guard let name = item.name else { return nil }
            let coordinate = item.placemark.coordinate
            let meters = location.distance(from: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude))
            guard meters <= radiusMeters else { return nil }
            return Venue(name: name, area: item.placemark.locality, miles: meters / 1609.344,
                         latitude: coordinate.latitude, longitude: coordinate.longitude, website: item.url)
        }
        return closestUnique(venues)
    }

    /// Nearest first, one row per name (chains and duplicate pins collapse), at most 12.
    static func closestUnique(_ venues: [Venue]) -> [Venue] {
        var seen = Set<String>()
        return Array(venues.sorted { $0.miles < $1.miles }.filter { seen.insert($0.name.lowercased()).inserted }.prefix(12))
    }

    /// Screenshots and UI tests: two sample rows instead of a live search.
    static let sample = [
        Venue(name: "The Old Mill Ballroom", area: "Riverside", miles: 2.4, latitude: 0, longitude: 0, website: URL(string: "https://example.com")),
        Venue(name: "Crossroads Amphitheater", area: "Lakeview", miles: 11.8, latitude: 0, longitude: 0, website: nil),
    ]
}

/// Asks for the listener's location only when they tap, once, at city accuracy.
@MainActor
@Observable
final class LocationProvider: NSObject, CLLocationManagerDelegate {
    enum Status { case notAsked, locating, denied, failed, located }

    private(set) var status = Status.notAsked
    private(set) var location: CLLocation?
    private let manager = CLLocationManager()

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    /// Locates right away when already allowed; otherwise waits for `request()`.
    func resume() {
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways: if location == nil { locate() }
        case .denied, .restricted: status = .denied
        default: break
        }
    }

    func request() {
        if manager.authorizationStatus == .notDetermined {
            status = .locating
            manager.requestWhenInUseAuthorization()
        } else {
            resume()
        }
    }

    private func locate() {
        status = .locating
        manager.requestLocation()
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let auth = manager.authorizationStatus
        Task { @MainActor in
            switch auth {
            case .authorizedWhenInUse, .authorizedAlways: if self.location == nil { self.locate() }
            case .denied, .restricted: self.status = .denied
            default: break
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let last = locations.last else { return }
        Task { @MainActor in
            self.location = last
            self.status = .located
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            if self.location == nil { self.status = .failed }
        }
    }
}
