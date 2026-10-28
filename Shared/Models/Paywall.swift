import Foundation

/// What opened the Deep Cuts+ sheet. It sets the headline and the RevenueCat impression id.
enum PaywallReason: Identifiable, Hashable, Sendable {
    case round(QuizMode)
    case story
    case you

    var id: String { impressionID }

    var impressionID: String {
        switch self {
        case .round: "deepcuts_paywall_round"
        case .story: "deepcuts_paywall_story"
        case .you: "deepcuts_paywall_you"
        }
    }

    var headline: String {
        switch self {
        case .round: "Keep playing"
        case .story: "Read every story"
        case .you: "Play as much as you want"
        }
    }
}
