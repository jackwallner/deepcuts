import SwiftUI
import UIKit

/// Warm paper, black ink and one record-label red. Serif for headlines, system sans for reading.
enum Theme {
    static let paper = dynamic(light: 0xF4EFE6, dark: 0x15130F)
    static let card = dynamic(light: 0xFFFCF6, dark: 0x211E19)
    static let ink = dynamic(light: 0x1D1A16, dark: 0xF2ECE1)
    static let inkSoft = dynamic(light: 0x6E665B, dark: 0xA79F92)
    static let rule = dynamic(light: 0xE2D9C9, dark: 0x35302A)
    static let accent = dynamic(light: 0xC8452C, dark: 0xE0603F)
    static let correct = dynamic(light: 0x2F7A4A, dark: 0x67B57F)
    /// The inverted "sleeve" used for the daily mix card.
    static let sleeve = dynamic(light: 0x1D1A16, dark: 0x2B2722)
    static let onSleeve = Color(hex: 0xF4EFE6)

    static let space: CGFloat = 8
    static let radius: CGFloat = 14
    static let gutter: CGFloat = 20

    static func display(_ size: CGFloat) -> Font {
        let scaled = UIFontMetrics(forTextStyle: .largeTitle).scaledValue(for: size)
        return .system(size: min(scaled, size * 2), weight: .bold, design: .serif)
    }

    static func serif(_ style: Font.TextStyle, weight: Font.Weight = .semibold) -> Font {
        .system(style, design: .serif, weight: weight)
    }

    /// Small caps label: "SOUTHERN ROCK · 1973".
    static let kicker = Font.system(.caption, design: .default, weight: .semibold)

    private static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light) })
    }

    /// One muted color per crate, for the record labels and art in a round.
    static func crate(_ id: String) -> Color {
        let palette: [String: UInt32] = [
            "classic-rock": 0xB5532F, "british-invasion": 0x2F5D8A, "southern-rock": 0x8C5A2B,
            "heavy-metal": 0x4A4A4F, "prog-rock": 0x5E4B8B, "motown-soul": 0xA8742A,
            "folk-singer-songwriter": 0x5B7A4A, "yacht-rock": 0x2E7C86, "punk-new-wave": 0xC23B5B,
            "eighties": 0xB0457F, "grunge-alt": 0x5F6B4E, "pop": 0xD0703C, "modern-pop": 0x2F8F9D, "country": 0x9A6B3F,
            "blues": 0x2C4E7A, "disco-funk": 0xB8862E, "hip-hop": 0x3B3B3B, "psychedelic-rock": 0x7A3E5E,
        ]
        return Color(hex: palette[id] ?? 0x7A6F60)
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }
}

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}

struct Kicker: View {
    let text: String
    var color: Color = Theme.inkSoft

    var body: some View {
        Text(text.uppercased())
            .font(Theme.kicker)
            .tracking(1.2)
            .foregroundStyle(color)
    }
}

struct SectionHeader: View {
    let title: String
    var trailing: String? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(Theme.serif(.title2, weight: .bold)).foregroundStyle(Theme.ink)
            Spacer()
            if let trailing { Text(trailing).font(.subheadline).foregroundStyle(Theme.inkSoft) }
        }
        .padding(.bottom, 4)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.ink).frame(height: 1.5) }
    }
}

/// Full-width primary action, ink on paper.
struct PrimaryButtonStyle: ButtonStyle {
    var fill: Color = Theme.accent
    var text: Color = .white

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .frame(maxWidth: .infinity, minHeight: 52)
            .foregroundStyle(text)
            .background(fill, in: RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
            .opacity(configuration.isPressed ? 0.85 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

/// Plain look with a small press-down, so cards and answers answer the finger.
struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.8 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

struct CardBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous).strokeBorder(Theme.rule, lineWidth: 1))
    }
}

extension View {
    func card() -> some View { modifier(CardBackground()) }

    /// Paper behind the page, and behind the status bar once text scrolls under it.
    func paperPage() -> some View {
        background(Theme.paper.ignoresSafeArea())
            .toolbarBackground(Theme.paper, for: .navigationBar)
    }
}
