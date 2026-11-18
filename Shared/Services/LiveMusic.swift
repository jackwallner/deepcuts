import CoreLocation
import Foundation
import MapKit
import Observation

/// Live music: acts from each crate who still play shows, and music venues near the listener.
/// No concert listing API is free without an account, so tour dates open on Ticketmaster and
/// venues come from Apple Maps, whose sites carry their calendars.
enum LiveMusic {
    /// Acts in each crate with dates on sale on their own Ticketmaster page, checked 2026-11-18 with
    /// `scripts/check-touring.py`. Names match the crate's song artists. A band stays only while someone
    /// who played on its hits is still in it: Lynyrd Skynyrd, Molly Hatchet and Atlanta Rhythm Section
    /// tour with none, which a fan hears as a tribute act.
    static let touring: [String: [String]] = [
        "classic-rock": ["Eagles", "Journey", "Heart", "Styx", "Kansas", "Santana", "Foghat", "Blue Öyster Cult"],
        "southern-rock": ["38 Special", "The Marshall Tucker Band"],
        "british-invasion": ["Herman's Hermits"],
        "heavy-metal": ["Metallica", "Iron Maiden", "Judas Priest", "Scorpions", "Deep Purple"],
        "prog-rock": ["Yes", "Jethro Tull", "Kansas"],
        "motown-soul": ["Stevie Wonder", "The Temptations"],
        "folk-singer-songwriter": ["Bob Dylan"],
        "yacht-rock": ["The Doobie Brothers", "Toto", "Air Supply"],
        "punk-new-wave": ["New Order", "The Human League", "Echo & the Bunnymen"],
        "eighties": ["Journey", "Guns N' Roses"],
        "grunge-alt": ["Weezer", "Pixies", "Alanis Morissette"],
        "pop": ["The Beach Boys"],
        "modern-pop": ["Olivia Rodrigo", "Mariah Carey"],
        "country": ["Shania Twain"],
        "disco-funk": ["Earth, Wind & Fire", "KC and the Sunshine Band", "Chic", "Diana Ross"],
    ]

    /// Bands that tour under the name with nobody from the records. Never listed.
    static let withoutOriginalMembers: Set<String> = ["Lynyrd Skynyrd", "Molly Hatchet", "Atlanta Rhythm Section"]

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

    /// Each act's own Ticketmaster artist page, checked by name 2026-11-18. A name search mixes in
    /// tribute bands ("Devo" returns Devolucion), so every listed act needs one. Acts between tours
    /// stay here so `scripts/check-touring.py` can spot their next dates.
    static let ticketmasterIDs: [String: Int] = [
        "Eagles": 734977, "Journey": 735415, "Heart": 735257, "Styx": 736216, "Kansas": 735426,
        "Santana": 741473, "Foghat": 735102, "Blue Öyster Cult": 734593,
        "ZZ Top": 736523, "38 Special": 767057, "The Marshall Tucker Band": 735594,
        "Herman's Hermits": 821381, "Metallica": 735647,
        "Iron Maiden": 735341, "Judas Priest": 807246, "AC/DC": 1170951, "Scorpions": 736062,
        "Deep Purple": 734897, "Yes": 736506, "Jethro Tull": 735387, "Stevie Wonder": 772848,
        "The Temptations": 736274, "Gladys Knight & The Pips": 735460, "Bob Dylan": 734972,
        "Neil Young": 736511, "James Taylor": 736262, "Bruce Springsteen": 736179,
        "The Doobie Brothers": 734946, "Toto": 736321, "Michael McDonald": 735614, "Boz Scaggs": 736052,
        "Christopher Cross": 734843, "Air Supply": 734403, "Duran Duran": 734969, "New Order": 735746,
        "The Human League": 735308, "Echo & the Bunnymen": 734986, "Guns N' Roses": 735218,
        "Pearl Jam": 735836, "Green Day": 768353, "Weezer": 766591, "The Smashing Pumpkins": 736143,
        "Pixies": 906179, "Nine Inch Nails": 735762, "Alanis Morissette": 775998, "The Beach Boys": 734518,
        "Lady Gaga": 1249444, "Billie Eilish": 2257710, "Dua Lipa": 2179476, "The Weeknd": 1697014,
        "Olivia Rodrigo": 2836194, "Ariana Grande": 1688071, "Mariah Carey": 767870,
        "George Strait": 732947, "Willie Nelson": 732878, "Alan Jackson": 769574, "Shania Twain": 764367,
        "Buddy Guy": 731721, "Earth, Wind & Fire": 734980, "KC and the Sunshine Band": 769791,
        "Chic": 734745, "Diana Ross": 736009, "Kendrick Lamar": 1480454, "Cardi B": 2223707,
    ]

    /// The act's Ticketmaster artist page, which lists only their own dates. No name search: that
    /// is where the tribute bands are.
    static func tourDatesURL(for artist: String) -> URL? {
        ticketmasterIDs[artist].flatMap { URL(string: "https://www.ticketmaster.com/artist/\($0)") }
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
    static let distanceOptions = [10, 25, 50, 100]
    static let defaultMiles = 25
    static let limit = 30

    /// Clubs, theaters, ballrooms and amphitheaters: the rooms a club or theater tour plays.
    /// Each query is searched separately, since one Apple Maps search returns only about 25 places.
    private static let queries: [(text: String, barsToo: Bool)] = [
        ("live music venue", true),
        ("concert venue", true),
        ("music club", true),
        ("live music", true),
        ("concert hall", false),
        ("theater live music", false),
        ("amphitheater", false),
        ("ballroom concerts", false),
    ]

    /// Places that come back for music searches but never host a touring band.
    private static var excludedCategories: [MKPointOfInterestCategory] {
        [.movieTheater, .stadium, .school, .university, .library, .museum, .store]
    }
    private static let excludedWords = [
        "karaoke", "cinema", "cinemas", "movie", "movies", "imax", "stadium", "arena", "school",
        "lessons", "music store", "guitar center", "dance studio", "comedy", "improv", "escape room",
        "bowling", "kids", "children's", "climbing", "office",
    ]

    /// One search result: the place, and whether Apple Maps files it under music venues.
    struct Hit {
        let venue: Venue
        let musicVenue: Bool
    }

    @MainActor
    static func nearby(_ location: CLLocation, miles: Int = defaultMiles) async throws -> [Venue] {
        let radius = Double(miles) * 1609.344
        var hits: [Hit] = []
        var failures = 0
        for query in queries {
            do {
                hits += try await search(query.text, barsToo: query.barsToo, around: location, radius: radius)
            } catch {
                failures += 1
            }
        }
        if failures == queries.count { throw URLError(.cannotLoadFromNetwork) }
        return best(hits)
    }

    /// A typed city or ZIP code: its name and center, for searching away from home.
    @MainActor
    static func place(_ text: String) async throws -> (name: String, location: CLLocation)? {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = text
        request.resultTypes = .address
        guard let item = try await MKLocalSearch(request: request).start().mapItems.first else { return nil }
        let coordinate = item.placemark.coordinate
        let name = item.placemark.locality ?? item.name ?? text
        return (name, CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude))
    }

    @MainActor
    private static func search(_ text: String, barsToo: Bool, around location: CLLocation, radius: CLLocationDistance) async throws -> [Hit] {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = text
        request.region = MKCoordinateRegion(center: location.coordinate, latitudinalMeters: radius * 2, longitudinalMeters: radius * 2)
        request.resultTypes = .pointOfInterest
        if #available(iOS 18, *) {
            request.pointOfInterestFilter = MKPointOfInterestFilter(including: barsToo ? [.musicVenue, .theater, .nightlife] : [.musicVenue, .theater])
        }
        let response = try await MKLocalSearch(request: request).start()
        return response.mapItems.compactMap { item -> Hit? in
            guard let name = item.name, isVenue(name: name, category: item.pointOfInterestCategory) else { return nil }
            let coordinate = item.placemark.coordinate
            let meters = location.distance(from: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude))
            guard meters <= radius else { return nil }
            var musicVenue = false
            if #available(iOS 18, *) { musicVenue = item.pointOfInterestCategory == .musicVenue }
            let venue = Venue(name: name, area: item.placemark.locality, miles: meters / 1609.344,
                              latitude: coordinate.latitude, longitude: coordinate.longitude, website: item.url)
            return Hit(venue: venue, musicVenue: musicVenue)
        }
    }

    /// Drops cinemas, stadiums, schools, karaoke bars and the like.
    static func isVenue(name: String, category: MKPointOfInterestCategory?) -> Bool {
        if let category, excludedCategories.contains(category) { return false }
        let words = name.lowercased()
        return !excludedWords.contains { words.range(of: "\\b\($0)\\b", options: .regularExpression) != nil }
    }

    /// The real rooms first, then nearest first: a place Apple Maps files as a music venue, or one that
    /// several music searches agree on, beats the bar or community theater down the street.
    /// One row per name (chains and duplicate pins collapse), at most `limit`.
    static func best(_ hits: [Hit]) -> [Venue] {
        var byName: [String: (venue: Venue, musicVenue: Bool, hits: Int)] = [:]
        for hit in hits {
            let key = hit.venue.name.lowercased()
            var entry = byName[key] ?? (hit.venue, false, 0)
            if hit.venue.miles < entry.venue.miles { entry.venue = hit.venue }
            entry.musicVenue = entry.musicVenue || hit.musicVenue
            entry.hits += 1
            byName[key] = entry
        }
        let ranked = byName.values.sorted {
            if $0.musicVenue != $1.musicVenue { return $0.musicVenue }
            if $0.hits != $1.hits { return $0.hits > $1.hits }
            return $0.venue.miles < $1.venue.miles
        }
        return ranked.prefix(limit).map(\.venue).sorted { $0.miles < $1.miles }
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
