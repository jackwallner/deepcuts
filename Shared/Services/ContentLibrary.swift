import Foundation

/// The bundled music library: every crate, plus the Apple Music catalog lookups.
/// Loaded once from `Content/` in the app bundle; read-only afterwards.
final class ContentLibrary: Sendable {
    /// Display order for crates. Files not listed sort after these by name.
    static let order = [
        "classic-rock", "british-invasion", "southern-rock", "heavy-metal", "prog-rock",
        "motown-soul", "folk-singer-songwriter", "yacht-rock", "punk-new-wave", "eighties",
        "grunge-alt", "pop", "modern-pop", "country", "blues", "disco-funk", "hip-hop",
    ]

    let genres: [Genre]
    let catalog: [String: CatalogEntry]
    private let songsByID: [String: Song]
    private let genreBySongID: [String: String]
    private let genresByID: [String: Genre]

    init(genres: [Genre], catalog: [String: CatalogEntry]) {
        let rank = Dictionary(uniqueKeysWithValues: Self.order.enumerated().map { ($1, $0) })
        self.genres = genres.sorted { (rank[$0.id] ?? 99, $0.name) < (rank[$1.id] ?? 99, $1.name) }
        self.catalog = catalog
        var songs: [String: Song] = [:]
        var owner: [String: String] = [:]
        for genre in genres {
            for song in genre.songs {
                songs[song.id] = song
                owner[song.id] = genre.id
            }
        }
        songsByID = songs
        genreBySongID = owner
        genresByID = Dictionary(uniqueKeysWithValues: genres.map { ($0.id, $0) })
    }

    convenience init(bundle: Bundle) {
        let decoder = JSONDecoder()
        let urls = bundle.urls(forResourcesWithExtension: "json", subdirectory: "Content/genres") ?? []
        let genres = urls.compactMap { url -> Genre? in
            guard let data = try? Data(contentsOf: url) else { return nil }
            return try? decoder.decode(Genre.self, from: data)
        }
        var catalog: [String: CatalogEntry] = [:]
        if let url = bundle.url(forResource: "catalog", withExtension: "json", subdirectory: "Content"),
           let data = try? Data(contentsOf: url) {
            catalog = (try? decoder.decode([String: CatalogEntry].self, from: data)) ?? [:]
        }
        self.init(genres: genres, catalog: catalog)
    }

    static let shared = ContentLibrary(bundle: .main)

    /// These crates with live rows layered on: a row with a bundled id replaces that item,
    /// a retired row drops it, and new rows join their crate. Rows for unknown crates are ignored.
    func applying(_ rows: [RemoteItem]) -> ContentLibrary {
        let crates = Set(genres.map(\.id))
        var latest: [String: RemoteItem] = [:]
        for row in rows where crates.contains(row.crate) && (row.payload != nil || !row.isLive) {
            if row.rev >= latest[row.id]?.rev ?? .min { latest[row.id] = row }
        }
        guard !latest.isEmpty else { return self }
        let added = latest.values.filter(\.isLive).sorted { $0.rev < $1.rev }

        func layer<T: Identifiable>(_ items: [T], crate: String, _ pick: (RemoteItem.Payload) -> T?) -> [T] where T.ID == String {
            var out = items.compactMap { item -> T? in
                guard let row = latest[item.id] else { return item }
                return row.isLive && row.crate == crate ? row.payload.flatMap(pick) : nil
            }
            let present = Set(out.map(\.id))
            out += added.filter { $0.crate == crate && !present.contains($0.id) }.compactMap { $0.payload.flatMap(pick) }
            return out
        }

        let merged = genres.map { g in
            Genre(
                id: g.id, name: g.name, blurb: g.blurb, era: g.era,
                questions: layer(g.questions, crate: g.id) { if case .question(let v) = $0 { v } else { nil } },
                songs: layer(g.songs, crate: g.id) { if case .song(let v) = $0 { v } else { nil } },
                stories: layer(g.stories, crate: g.id) { if case .story(let v) = $0 { v } else { nil } },
                covers: layer(g.coverSongs, crate: g.id) { if case .cover(let v) = $0 { v } else { nil } })
        }
        return ContentLibrary(genres: merged, catalog: catalog)
    }

    func genre(_ id: String) -> Genre? { genresByID[id] }
    func song(_ id: String) -> Song? { songsByID[id] }
    func genre(forSong id: String) -> Genre? { genreBySongID[id].flatMap { genresByID[$0] } }

    func artworkURL(for songID: String, size: Int = 600) -> URL? {
        guard let raw = catalog[songID]?.artworkUrl else { return nil }
        return URL(string: raw.replacingOccurrences(of: "600x600", with: "\(size)x\(size)"))
    }

    /// Catalog key for a story's art: its album cover, else its first song's sleeve.
    func artKey(for story: Story) -> String? {
        catalog[story.coverKey]?.artworkUrl != nil ? story.coverKey : story.songs.first
    }

    func hasPreview(_ songID: String) -> Bool { catalog[songID]?.previewUrl != nil }

    /// Stories, focus crates first, each crate in file order.
    func stories(focus: [String]) -> [(story: Story, genre: Genre)] {
        let ordered = genres.filter { focus.contains($0.id) } + genres.filter { !focus.contains($0.id) }
        return ordered.flatMap { genre in genre.stories.map { ($0, genre) } }
    }
}
