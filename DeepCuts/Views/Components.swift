import SwiftUI

/// Album art from Apple Music, or the crate's color and symbol while it loads or when offline.
struct ArtworkView: View {
    @Environment(AppModel.self) private var app
    let songID: String?
    var size: CGFloat = 56
    var corner: CGFloat = 6

    var body: some View {
        let genreID = songID.flatMap { app.library.genre(forSong: $0)?.id } ?? ""
        AsyncImage(url: songID.flatMap { app.library.artworkURL(for: $0, size: size > 120 ? 600 : 300) }, transaction: Transaction(animation: .easeOut(duration: 0.25))) { phase in
            if let image = phase.image {
                image.resizable().scaledToFill()
            } else {
                ZStack {
                    Theme.crate(genreID).opacity(0.85)
                    Image(systemName: Theme.crateSymbol(genreID))
                        .font(.system(size: size * 0.32, weight: .medium))
                        .foregroundStyle(.white.opacity(0.85))
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: corner, style: .continuous).strokeBorder(.black.opacity(0.08), lineWidth: 0.5))
        .accessibilityHidden(true)
    }
}

/// A 7-inch single: grooves, a label, and the spindle hole. Spins while its clip plays.
struct VinylView: View {
    let labelSongID: String?
    var revealed: Bool
    var spinning: Bool
    var size: CGFloat = 240
    var labelColor: Color = Theme.accent

    @State private var angle: Double = 0

    var body: some View {
        ZStack {
            Circle().fill(Color(hex: 0x111111))
            ForEach(0..<14, id: \.self) { ring in
                Circle()
                    .stroke(Color.white.opacity(ring.isMultiple(of: 3) ? 0.07 : 0.035), lineWidth: 1)
                    .padding(size * 0.04 + CGFloat(ring) * size * 0.022)
            }
            // Sheen.
            Circle()
                .fill(AngularGradient(colors: [.clear, .white.opacity(0.10), .clear, .clear, .white.opacity(0.07), .clear], center: .center))
            ZStack {
                if revealed, let labelSongID {
                    ArtworkView(songID: labelSongID, size: size * 0.38, corner: size)
                } else {
                    Circle().fill(labelColor)
                    VStack(spacing: 2) {
                        Text("DEEP CUTS").font(.system(size: size * 0.035, weight: .heavy)).tracking(1.5)
                        Text("33⅓").font(.system(size: size * 0.03, weight: .medium))
                    }
                    .foregroundStyle(.white.opacity(0.9))
                    .offset(y: -size * 0.09)
                }
                Circle().fill(Theme.paper).frame(width: size * 0.035)
            }
            .frame(width: size * 0.38, height: size * 0.38)
            .clipShape(Circle())
        }
        .frame(width: size, height: size)
        .rotationEffect(.degrees(angle))
        .shadow(color: .black.opacity(0.25), radius: 12, y: 6)
        .onChange(of: spinning, initial: true) { _, isSpinning in
            if isSpinning {
                withAnimation(.linear(duration: 1.8).repeatForever(autoreverses: false)) { angle += 360 }
            } else {
                withAnimation(.easeOut(duration: 0.6)) { angle = angle.truncatingRemainder(dividingBy: 360) + 20 }
            }
        }
        .accessibilityHidden(true)
    }
}

/// A song with its artwork, a one-line note and a preview button.
struct SongRow: View {
    @Environment(AppModel.self) private var app
    let song: Song
    var showNote = true

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ArtworkView(songID: song.id, size: 56)
            VStack(alignment: .leading, spacing: 2) {
                Text(song.title).font(.headline).foregroundStyle(Theme.ink)
                Text("\(song.artist) · \(String(song.year))").font(.subheadline).foregroundStyle(Theme.inkSoft)
                if showNote {
                    Text(song.note).font(.footnote).foregroundStyle(Theme.inkSoft).padding(.top, 2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            if app.library.hasPreview(song.id) {
                PlayButton(songID: song.id, label: "\(song.title) by \(song.artist)")
            }
        }
        .padding(.vertical, 6)
    }
}

struct PlayButton: View {
    @Environment(AppModel.self) private var app
    let songID: String
    let label: String

    var body: some View {
        let player = app.player
        let active = player.songID == songID
        Button {
            player.toggle(songID)
        } label: {
            ZStack {
                Circle().strokeBorder(Theme.rule, lineWidth: 2)
                if active {
                    Circle().trim(from: 0, to: player.progress)
                        .stroke(Theme.accent, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .padding(1)
                }
                if active && player.state == .loading {
                    ProgressView().controlSize(.small)
                } else if active && player.state == .failed {
                    Image(systemName: "exclamationmark").font(.footnote.weight(.bold)).foregroundStyle(Theme.inkSoft)
                } else {
                    Image(systemName: active ? "stop.fill" : "play.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Theme.accent)
                        .offset(x: active ? 0 : 1)
                }
            }
            .frame(width: 40, height: 40)
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(active ? "Stop preview" : "Play preview of \(label)")
    }
}

/// Thin progress bar, used for accuracy by crate.
struct Meter: View {
    let value: Double
    var color: Color = Theme.accent

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.rule)
                Capsule().fill(color).frame(width: max(4, geo.size.width * value))
            }
        }
        .frame(height: 6)
    }
}
