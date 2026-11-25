import Foundation
import RevenueCat

/// What RevenueCat can change without a release, read from the current offering's metadata
/// (a running Experiment's variant included). Every variant ships in the binary; a missing or
/// unknown value is the control, which is what 1.0.1 shipped. Keys a switch reads must be set
/// the same on every offering, or an Experiment arm would flip them as a side effect.
///
/// DEBUG builds can pin any key for captures: `-deepcuts.rc.<key> <value>`.

/// The trial button's wording, on the onboarding trial page and the paywall (both title case).
enum TrialCTA: String, CaseIterable, Sendable {
    static let metadataKey = "trial_cta"

    /// Control: "Start 7-Day Free Trial", as shipped since 1.0.
    case sevenDay = "seven_day"
    case my
    case your

    enum Surface: CaseIterable {
        case onboarding, paywall
    }

    static func from(metadata: [String: Any]?) -> TrialCTA {
        RemoteConfig.value(metadataKey, in: metadata, default: .sevenDay)
    }

    /// Both surfaces have always used the same title-case button, so every arm reads the same on each.
    func title(_ surface: Surface) -> String {
        switch self {
        case .sevenDay: "Start 7-Day Free Trial"
        case .my: "Start My Free Trial"
        case .your: "Start Your Free Trial"
        }
    }
}

/// Remote off switches, for what is worth pausing without a release. On unless the metadata says "off".
enum RemoteSwitch: String, CaseIterable, Sendable {
    /// Apple's rating prompt. The app has no automatic ask yet; the star prompt reads this when it lands.
    case ratingPrompt = "rating_prompt"
}

enum RemoteConfig {
    /// The value for `key`, or `fallback` when it is missing, not a string, or not a shipped variant.
    static func value<T: RawRepresentable>(_ key: String, in metadata: [String: Any]?, default fallback: T) -> T
    where T.RawValue == String {
        #if DEBUG
        if let pinned = launchOverride(key).flatMap(T.init(rawValue:)) { return pinned }
        #endif
        guard let raw = metadata?[key] as? String else { return fallback }
        return T(rawValue: raw) ?? fallback
    }

    static func isOn(_ remoteSwitch: RemoteSwitch, in metadata: [String: Any]?) -> Bool {
        #if DEBUG
        if let pinned = launchOverride(remoteSwitch.rawValue) { return pinned != "off" }
        #endif
        return (metadata?[remoteSwitch.rawValue] as? String) != "off"
    }

    #if DEBUG
    private static func launchOverride(_ key: String) -> String? {
        let args = ProcessInfo.processInfo.arguments
        guard let index = args.firstIndex(of: "-deepcuts.rc.\(key)"), index + 1 < args.count else { return nil }
        return args[index + 1]
    }
    #endif
}

extension Membership {
    private var remoteMetadata: [String: Any]? { offerings?.current?.metadata }

    var trialCTA: TrialCTA { TrialCTA.from(metadata: remoteMetadata) }

    func isOn(_ remoteSwitch: RemoteSwitch) -> Bool { RemoteConfig.isOn(remoteSwitch, in: remoteMetadata) }
}
