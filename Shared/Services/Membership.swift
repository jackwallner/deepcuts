import Foundation
import Observation
import RevenueCat
import StoreKit

enum RevenueCatConfig {
    #if DEBUG
    /// Test Store: simulated purchases, a separate RevenueCat app, never App Store customers.
    static let apiKey = "test_mgbJdFtXYwROTrNhfCMzRgZriIZ"
    #else
    static let apiKey = "appl_ffHYRTitCIWcyqAEPjPVMslajFz"
    #endif
    static let entitlement = "pro"
}

/// What happened at Apple's sheet. Backing out is an outcome, not an error.
enum PurchaseOutcome: Sendable {
    case purchased
    case cancelled
}

enum PurchaseError: LocalizedError {
    case productsUnavailable

    var errorDescription: String? {
        "The App Store isn't reachable right now. Check your connection and try again."
    }
}

enum PlusPlan: String, CaseIterable, Identifiable, Sendable {
    case yearly, monthly, lifetime

    var id: String { rawValue }
}

struct PlusPrice: Sendable {
    let amount: Decimal
    let localized: String
    let locale: Locale
    /// The storefront's currency, which can differ from the device region's.
    let currencyCode: String?
}

/// Deep Cuts+, through RevenueCat. The daily ritual is free; Plus is unlimited rounds and every story.
@MainActor
@Observable
final class Membership {
    private(set) var isPlus = false
    /// False until a customer record has been read. Nobody is sold a trial before this.
    private(set) var resolved = false
    private(set) var isTrialing = false
    private(set) var expirationDate: Date?
    private(set) var willRenew = false
    private(set) var offerings: Offerings?

    private var isConfigured = false
    private var localOverride = false
    private var impressions: Set<String> = []
    private let reinstallSyncKey = "membership.reinstallSyncDone"

    init() {
        #if DEBUG
        localOverride = ProcessInfo.processInfo.arguments.contains("-ui-plus")
        isPlus = localOverride
        #endif
    }

    func start() {
        configureIfNeeded()
        guard isConfigured else {
            // No store to ask (simulator without the Test Store key): this is the answer.
            resolved = true
            return
        }
        if let cached = Purchases.shared.cachedCustomerInfo { apply(cached) }
        Task {
            await refresh()
            async let recovered: Void = recoverReinstalledMembership()
            await loadOfferings()
            await recovered
        }
        Task {
            for await info in Purchases.shared.customerInfoStream { apply(info) }
        }
    }

    private func configureIfNeeded() {
        guard !isConfigured else { return }
        #if targetEnvironment(simulator)
        // The production key never runs on a simulator: it would create App Store customers.
        guard RevenueCatConfig.apiKey.hasPrefix("test_") else { return }
        #endif
        var configuration = Configuration.Builder(withAPIKey: RevenueCatConfig.apiKey)
        if RevenueCatConfig.apiKey.hasPrefix("test_") {
            // Test installs share one customer instead of inflating the charts with one each.
            configuration = configuration.with(appUserID: ProcessInfo.processInfo.environment["RC_APP_USER_ID"] ?? "qa-ios")
        }
        Purchases.configure(with: configuration.build())
        Purchases.shared.attribution.enableAdServicesAttributionTokenCollection()
        isConfigured = true
    }

    /// RevenueCat's paywall encounter; a custom paywall sends none of its own.
    func trackImpression(_ id: String) {
        guard isConfigured, !impressions.contains(id) else { return }
        impressions.insert(id)
        Purchases.shared.trackCustomPaywallImpression(CustomPaywallImpressionParams(paywallId: id))
    }

    func refresh(fetchCurrent: Bool = false) async {
        guard isConfigured else { return }
        if let info = try? await Purchases.shared.customerInfo(fetchPolicy: fetchCurrent ? .fetchCurrent : .cachedOrFetched) {
            apply(info)
        }
    }

    func loadOfferings() async {
        guard isConfigured else { return }
        offerings = try? await Purchases.shared.offerings()
    }

    /// One more try when someone reaches a purchase button before offerings landed.
    @discardableResult
    func ensureOfferings() async -> Bool {
        guard isConfigured else { return false }
        if offerings?.current != nil { return true }
        await loadOfferings()
        return offerings?.current != nil
    }

    func package(for plan: PlusPlan) -> Package? {
        guard let offering = offerings?.current else { return nil }
        switch plan {
        case .yearly: return offering.annual
        case .monthly: return offering.monthly
        case .lifetime: return offering.lifetime
        }
    }

    func price(for plan: PlusPlan) -> PlusPrice? {
        guard let product = package(for: plan)?.storeProduct else { return nil }
        return PlusPrice(amount: product.price, localized: product.localizedPriceString,
                         locale: product.priceFormatter?.locale ?? .current, currencyCode: product.currencyCode)
    }

    /// Apple gives the free week once per subscription group. Unknown reads as eligible.
    func isTrialEligible(for plan: PlusPlan) async -> Bool {
        guard plan != .lifetime else { return false }
        guard let subscription = package(for: plan)?.storeProduct.sk2Product?.subscription else { return true }
        guard subscription.introductoryOffer != nil else { return false }
        return await subscription.isEligibleForIntroOffer
    }

    func purchase(_ plan: PlusPlan) async throws -> PurchaseOutcome {
        await ensureOfferings()
        guard isConfigured, let package = package(for: plan) else { throw PurchaseError.productsUnavailable }
        let result = try await Purchases.shared.purchase(package: package)
        if result.userCancelled { return .cancelled }
        apply(result.customerInfo)
        return .purchased
    }

    /// StoreKit can report the sale a moment before RevenueCat grants it.
    func confirmEntitlement() async -> Bool {
        guard isConfigured else { return isPlus }
        for attempt in 0..<3 {
            await refresh(fetchCurrent: true)
            if isPlus { return true }
            if attempt < 2 { try? await Task.sleep(for: .milliseconds(1200)) }
        }
        return isPlus
    }

    func restore() async throws {
        guard isConfigured else { return }
        apply(try await Purchases.shared.restorePurchases())
    }

    /// A reinstall is a new anonymous customer. If this Apple Account already owns Plus,
    /// sync once so a member is never offered a trial.
    private func recoverReinstalledMembership() async {
        guard !isPlus, !UserDefaults.standard.bool(forKey: reinstallSyncKey) else { return }
        var ownsSomething = false
        for await result in Transaction.currentEntitlements {
            if case .verified = result { ownsSomething = true; break }
        }
        guard ownsSomething, let info = try? await Purchases.shared.syncPurchases() else { return }
        UserDefaults.standard.set(true, forKey: reinstallSyncKey)
        apply(info)
    }

    private func apply(_ info: CustomerInfo) {
        let entitlement = info.entitlements[RevenueCatConfig.entitlement]
        let active = entitlement?.isActive == true
        isPlus = active || localOverride
        resolved = true
        isTrialing = active && entitlement?.periodType == .trial
        expirationDate = active ? entitlement?.expirationDate : nil
        willRenew = active && entitlement?.willRenew == true
    }
}
