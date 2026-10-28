import SwiftUI

/// The last onboarding page: one yearly trial, one tap. Its button sits exactly where
/// Continue was, and Get Started is the free way in.
struct TrialPage: View {
    @Environment(AppModel.self) private var app
    let crates: [String]
    let onFinish: () -> Void

    @State private var trialEligible = true
    @State private var purchasing = false
    @State private var restoring = false
    @State private var showingPlans = false
    @State private var message: String?

    private var membership: Membership { app.membership }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 10) {
                    Kicker(text: "Deep Cuts+", color: Theme.accent)
                    Text("Play as much\nas you want").font(Theme.display(38)).foregroundStyle(Theme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("trial-headline")
                }
                .padding(.top, 24)
                VStack(alignment: .leading, spacing: 14) {
                    benefit(unlimitedLine)
                    benefit("Every story, from the studio to the stage")
                    benefit("Today's Mix stays free, always")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Theme.gutter)
            .padding(.bottom, 24)
        }
        .background(Theme.paper.ignoresSafeArea())
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 8) {
                Button("Get Started", action: onFinish)
                    .font(.headline)
                    .foregroundStyle(Theme.inkSoft)
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("trial-skip")
                Text(PlusPricing.terms(membership, .yearly, trial: trialEligible))
                    .font(.footnote).foregroundStyle(Theme.inkSoft)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("trial-terms")
                Button {
                    Task { await start() }
                } label: {
                    if purchasing { ProgressView().tint(.white) } else { Text(PlusPricing.cta(.yearly, trial: trialEligible)) }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(purchasing || restoring)
                .accessibilityIdentifier("trial-start")
                PlusLegalFooter(restore: { Task { await restore() } }, disabled: purchasing || restoring)
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.vertical, 12)
            .background(Theme.paper)
            .overlay(alignment: .top) { Rectangle().fill(Theme.rule).frame(height: 1) }
        }
        .sheet(isPresented: $showingPlans) {
            PaywallView(reason: .you).environment(app)
        }
        .alert("Deep Cuts+", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(message ?? "")
        }
        .onChange(of: membership.isPlus) { _, isPlus in if isPlus { onFinish() } }
        .task {
            membership.trackImpression("deepcuts_onboarding_trial")
            if membership.package(for: .yearly) == nil { await membership.loadOfferings() }
            trialEligible = await membership.isTrialEligible(for: .yearly)
        }
    }

    private var unlimitedLine: String {
        let names = app.library.genres.filter { crates.contains($0.id) }.map(\.name)
        return names.count <= 2 ? "Unlimited rounds of \(names.joined(separator: " and "))" : "Unlimited rounds in every crate"
    }

    private func benefit(_ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: "checkmark").font(.subheadline.weight(.bold)).foregroundStyle(Theme.accent)
            Text(text).font(.body).foregroundStyle(Theme.ink).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func start() async {
        purchasing = true
        defer { purchasing = false }
        // No product to sell (offline, store down): the full plan picker can retry.
        guard await membership.ensureOfferings(), membership.package(for: .yearly) != nil else {
            showingPlans = true
            return
        }
        do {
            guard try await membership.purchase(.yearly) == .purchased else { return }
            if await membership.confirmEntitlement() {
                onFinish()
            } else {
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
