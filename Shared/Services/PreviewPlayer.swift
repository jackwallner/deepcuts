import AVFoundation
import Foundation
import Observation

/// Plays Apple Music's 30-second previews. One clip at a time, app-wide.
@MainActor
@Observable
final class PreviewPlayer {
    enum State: Equatable {
        case idle, loading, playing, failed
    }

    private(set) var songID: String?
    private(set) var state: State = .idle
    private(set) var progress: Double = 0

    private let library: ContentLibrary
    private var player: AVPlayer?
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?
    private var loadTask: Task<Void, Never>?

    init(library: ContentLibrary) {
        self.library = library
    }

    func isPlaying(_ id: String) -> Bool { songID == id && (state == .playing || state == .loading) }

    func toggle(_ id: String) {
        isPlaying(id) ? stop() : play(id)
    }

    func play(_ id: String) {
        stop()
        songID = id
        state = .loading
        loadTask = Task { [weak self] in
            guard let self else { return }
            guard let url = await self.previewURL(for: id), !Task.isCancelled else {
                if self.songID == id { self.state = .failed }
                return
            }
            self.start(url, id: id)
        }
    }

    func stop() {
        loadTask?.cancel()
        loadTask = nil
        if let timeObserver { player?.removeTimeObserver(timeObserver) }
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        timeObserver = nil
        endObserver = nil
        player?.pause()
        player = nil
        songID = nil
        state = .idle
        progress = 0
    }

    private func start(_ url: URL, id: String) {
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
        try? AVAudioSession.sharedInstance().setActive(true)
        let item = AVPlayerItem(url: url)
        let player = AVPlayer(playerItem: item)
        self.player = player
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.2, preferredTimescale: 600), queue: .main) { [weak self] time in
            MainActor.assumeIsolated {
                guard let self, self.songID == id else { return }
                let duration = item.duration.seconds
                if item.status == .failed { self.state = .failed }
                if duration.isFinite, duration > 0 {
                    self.progress = min(1, time.seconds / duration)
                    if self.state == .loading, time.seconds > 0 { self.state = .playing }
                }
            }
        }
        endObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.songID == id else { return }
                self.stop()
            }
        }
        player.play()
    }

    /// The bundled preview URL, refreshed from the iTunes lookup API when the bundled one is gone.
    private func previewURL(for id: String) async -> URL? {
        guard let entry = library.catalog[id] else { return nil }
        if let raw = entry.previewUrl, let url = URL(string: raw), await reachable(url) { return url }
        guard let lookup = URL(string: "https://itunes.apple.com/lookup?id=\(entry.trackId)&country=US") else { return nil }
        struct Response: Decodable { struct Result: Decodable { let previewUrl: String? }; let results: [Result] }
        guard let (data, _) = try? await URLSession.shared.data(from: lookup),
              let fresh = try? JSONDecoder().decode(Response.self, from: data).results.first?.previewUrl else { return nil }
        return URL(string: fresh)
    }

    private func reachable(_ url: URL) async -> Bool {
        var request = URLRequest(url: url, timeoutInterval: 8)
        request.httpMethod = "HEAD"
        guard let (_, response) = try? await URLSession.shared.data(for: request) else { return false }
        return (response as? HTTPURLResponse)?.statusCode == 200
    }
}
