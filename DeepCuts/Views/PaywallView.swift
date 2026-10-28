import SwiftUI

enum PlusLinks {
    /// Apple's standard EULA. App Review needs a working Terms link wherever Plus is sold.
    static let terms = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!
    static let privacy = URL(string: "https://jackwallner.com/ios/deepcuts/privacy-policy.html")!
    static let manage = URL(string: "https://apps.apple.com/account/subscriptions")!
}

/// Prices and the point-of-purchase terms, always from StoreKit. A price the store
/// didn't give us is never shown: an unresolved plan reads "Loading price…".
@MainActor
enum PlusPricing {
    static let placeholder = "Loading price…"

    static func price(_ membership: Membership, _ plan: PlusPlan) -> String? {
        guard let base = membership.price(for: plan)?.localized else { return nil }
        switch plan {
        case .yearly: return "\(base)/year"
        case .monthly: return "\(base)/month"
        case .lifetime: return base
        }
    }

    /// The yearly price restated per month, beside the monthly price it discounts.
    static func yearlyPerMonth(_ membership: Membership) -> String? {
        guard let yearly = membership.price(for: .yearly) else { return nil }
        let format = NumberFormatter()
        format.numberStyle = .currency
        format.locale = yearly.locale
        if let code = yearly.currencyCode { format.currencyCode = code }
        return format.string(from: (yearly.amount / 12) as NSDecimalNumber).map { "\($0)/mo" }
    }

    /// Whole-percent saving of yearly against twelve months of monthly, or nil when there is none.
    static func savings(_ membership: Membership) -> Int? {
        guard let yearly = membership.price(for: .yearly), let monthly = membership.price(for: .monthly) else { return nil }
        let twelve = monthly.amount * 12
        guard twelve > 0, yearly.amount < twelve else { return nil }
        let percent = NSDecimalNumber(decimal: (twelve - yearly.amount) / twelve * 100).doubleValue.rounded()
        return percent >= 1 ? Int(percent) : nil
    }

    static func terms(_ membership: Membership, _ plan: PlusPlan, trial: Bool) -> String {
        let amount = price(membership, plan)
        switch plan {
        case .lifetime:
            return amount.map { "\($0) once. Not a subscription, nothing renews." } ?? "One payment. Not a subscription, nothing renews."
        case .yearly, .monthly:
            guard trial else {
                return amount.map { "\($0), billed today. Auto-renews until canceled." } ?? "Billed today. Auto-renews until canceled."
            }
            return amount.map { "7 days free, then \($0). Auto-renews until canceled." } ?? "7 days free. Auto-renews until canceled."
        }
    }

    static func cta(_ plan: PlusPlan, trial: Bool) -> String {
        if plan == .lifetime { return "Unlock Deep Cuts+ Forever" }
        return trial ? "Start 7-Day Free Trial" : "Subscribe"
    }
}

/// Restore, Terms of Use and Privacy Policy: on every surface that sells Plus.
struct PlusLegalFooter: View {
    let restore: () -> Void
    var disabled = false
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 4)) : AnyLayout(HStackLayout(spacing: 20))
        layout {
            Button(action: restore) { Text("Restore") }.footerTarget().disabled(disabled)
                .accessibilityIdentifier("plus-restore")
            Link("Terms of Use", destination: PlusLinks.terms).footerTarget()
            Link("Privacy Policy", destination: PlusLinks.privacy).footerTarget()
        }
        .font(.footnote)
        .foregroundStyle(Theme.inkSoft)
    }
}

private extension View {
    /// Pads a footer link to a 44 pt tap target.
    func footerTarget() -> some View {
        frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
    }
}

/// The plan picker: locked rounds and stories, and You.
struct PaywallView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    let reason: PaywallReason

    @State private var plan: PlusPlan = .yearly
    @State private var trialEligible = true
    @State private var purchasing = false
    @State private var restoring = false
    @State private var loading = false
    @State private var loadAttempted = false
    @State private var message: String?

    private var membership: Membership { app.membership }
    private var priceReady: Bool { PlusPricing.price(membership, plan) != nil }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    header
                    benefits
                    plans
                    if typeSize.isAccessibilitySize { purchaseArea }
                }
                .padding(.horizontal, Theme.gutter)
                .padding(.bottom, 24)
            }
            .background(Theme.paper.ignoresSafeArea())
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if !typeSize.isAccessibilitySize {
                    purchaseArea
                        .padding(.horizontal, Theme.gutter)
                        .padding(.top, 12)
                        .background(Theme.paper)
                        .overlay(alignment: .top) { Rectangle().fill(Theme.rule).frame(height: 1) }
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                        .foregroundStyle(Theme.inkSoft)
                        .accessibilityIdentifier("paywall-close")
                }
            }
            .toolbarBackground(Theme.paper, for: .navigationBar)
            .alert("Deep Cuts+", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(message ?? "")
            }
        }
        .onChange(of: membership.isPlus) { _, isPlus in if isPlus { dismiss() } }
        .onChange(of: plan) { _, _ in Task { await checkTrial() } }
        .task {
            membership.trackImpression(reason.impressionID)
            if !priceReady { await loadPrices() }
            await checkTrial()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Kicker(text: "Deep Cuts+", color: Theme.accent)
            Text(reason.headline).font(Theme.display(34)).foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("paywall-headline")
        }
        .padding(.top, 8)
    }

    private var benefits: some View {
        VStack(alignment: .leading, spacing: 12) {
            benefit("Unlimited rounds in every game")
            benefit("Every story, from the studio to the stage")
            benefit("Today's Mix stays free, always")
        }
    }

    private func benefit(_ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: "checkmark").font(.subheadline.weight(.bold)).foregroundStyle(Theme.accent)
            Text(text).font(.body).foregroundStyle(Theme.ink).fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Yearly, then the monthly price it discounts, then lifetime: a different decision.
    private var plans: some View {
        VStack(spacing: 10) {
            planCard(.yearly, title: "Yearly", detail: PlusPricing.yearlyPerMonth(membership),
                     badge: PlusPricing.savings(membership).map { "SAVE \($0)%" })
            planCard(.monthly, title: "Monthly", detail: nil, badge: nil)
            planCard(.lifetime, title: "Lifetime", detail: "One payment", badge: nil)
        }
    }

    private func planCard(_ option: PlusPlan, title: String, detail: String?, badge: String?) -> some View {
        let selected = plan == option
        let price = PlusPricing.price(membership, option) ?? PlusPricing.placeholder
        return Button {
            plan = option
        } label: {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                    .font(.title3)
                    .foregroundStyle(selected ? Theme.accent : Theme.rule)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text(title).font(.headline).foregroundStyle(Theme.ink)
                        if let badge {
                            Text(badge).font(.caption2.weight(.bold)).tracking(0.6)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .foregroundStyle(.white)
                                .background(Theme.accent, in: Capsule())
                        }
                    }
                    if let detail { Text(detail).font(.subheadline).foregroundStyle(Theme.inkSoft) }
                }
                Spacer(minLength: 8)
                Text(price).font(.headline).foregroundStyle(Theme.ink).multilineTextAlignment(.trailing)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                .strokeBorder(selected ? Theme.accent : Theme.rule, lineWidth: selected ? 2 : 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .sensoryFeedback(.selection, trigger: selected)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
        .accessibilityIdentifier("plan-\(option.rawValue)")
    }

    private var purchaseArea: some View {
        VStack(spacing: 8) {
            if loadAttempted && !priceReady && !loading {
                Button("Prices didn't load. Try again") { Task { await loadPrices() } }
                    .font(.subheadline.weight(.semibold))
            }
            Text(PlusPricing.terms(membership, plan, trial: trialEligible))
                .font(.footnote).foregroundStyle(Theme.inkSoft)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("paywall-terms")
            Button {
                Task { await buy() }
            } label: {
                if purchasing || loading || (!loadAttempted && !priceReady) {
                    ProgressView().tint(.white)
                } else {
                    Text(PlusPricing.cta(plan, trial: trialEligible))
                }
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(purchasing || restoring || !priceReady)
            .accessibilityIdentifier("paywall-buy")
            PlusLegalFooter(restore: { Task { await restore() } }, disabled: purchasing || restoring)
        }
    }

    private func loadPrices() async {
        guard !loading else { return }
        loading = true
        await membership.loadOfferings()
        loading = false
        loadAttempted = true
    }

    private func checkTrial() async {
        trialEligible = await membership.isTrialEligible(for: plan)
    }

    private func buy() async {
        purchasing = true
        defer { purchasing = false }
        do {
            guard try await membership.purchase(plan) == .purchased else { return }
            if await !membership.confirmEntitlement() {
                message = "Your purchase went through, but Deep Cuts+ hasn't unlocked yet. Give it a moment, then tap Restore. You won't be charged twice."
            }
        } catch {
            message = error.localizedDescription
        }
    }

    private func restore() async {
        restoring = true
        defer { restoring = false }
        do {
            try await membership.restore()
            if !membership.isPlus { message = "No Deep Cuts+ purchase found on this Apple Account." }
        } catch {
            message = error.localizedDescription
        }
    }
}
