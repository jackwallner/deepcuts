import SwiftUI

/// Pane frames for the unfolded iPhone Duo: the tabs on the leading side of the fold, the
/// reading pane (Stories, or a round's sheet) on the trailing side. `nil` keeps the single
/// column: every ordinary iPhone, the folded Duo, and the unfolded Duo held in portrait.
struct UnfoldedSplit: Equatable, Sendable {
    var primaryWidth: CGFloat
    var secondaryX: CGFloat
    var secondaryWidth: CGFloat

    /// Narrowest pane that still fits the phone layouts.
    static let minimumPaneWidth: CGFloat = 360

    /// The floating tab bar's top, above the unfolded display's bottom edge (83 pt in the
    /// iOS 27.1 captures), plus a little air.
    static let tabBarClearance: CGFloat = 92

    /// - Parameters:
    ///   - width: the container's width.
    ///   - fold: the vertical fold's leading and trailing edge in the same coordinate space,
    ///     or `nil` when the system reports none.
    static func make(width: CGFloat, isRegularWidth: Bool, fold: ClosedRange<CGFloat>?) -> UnfoldedSplit? {
        guard isRegularWidth, width >= minimumPaneWidth * 2 else { return nil }
        if let fold, fold.lowerBound >= minimumPaneWidth, width - fold.upperBound >= minimumPaneWidth {
            return UnfoldedSplit(primaryWidth: fold.lowerBound, secondaryX: fold.upperBound,
                                 secondaryWidth: width - fold.upperBound)
        }
        let half = (width / 2).rounded(.down)
        return UnfoldedSplit(primaryWidth: half, secondaryX: half, secondaryWidth: width - half)
    }
}

/// A container's width and vertical fold, measured together.
struct PaneGeometry: Equatable, Sendable {
    var width: CGFloat = 0
    var fold: ClosedRange<CGFloat>?
}

extension EnvironmentValues {
    /// True inside one pane of the unfolded split: a story opens in the reading pane
    /// instead of being pushed, and sheets cover only their pane.
    @Entry var isUnfoldedPane = false
}

extension GeometryProxy {
    /// The vertical fold's horizontal extent in this proxy's space. Inactive folds count
    /// too, so the panes don't jump while the device opens.
    func verticalFold() -> ClosedRange<CGFloat>? {
        guard #available(iOS 27.1, *) else { return nil }
        let fold = reservedRegions(kind: .division, options: .includeInactive)
            .map(\.frame)
            .first { $0.height > $0.width && $0.minX > 0 && $0.maxX < size.width }
        guard let fold else { return nil }
        return fold.minX...fold.maxX
    }
}

extension View {
    /// Measures the container for `UnfoldedSplit`.
    func measuringPanes(into geometry: Binding<PaneGeometry>) -> some View {
        onGeometryChange(for: PaneGeometry.self) { proxy in
            PaneGeometry(width: proxy.size.width, fold: proxy.verticalFold())
        } action: { geometry.wrappedValue = $0 }
    }

    /// Unfolded, a pane scrolls off the display's bottom edge: fading the last few points
    /// keeps a line from being sliced there. No effect when `on` is false.
    func paneBottomFade(_ on: Bool) -> some View {
        mask {
            VStack(spacing: 0) {
                Color.black
                LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom)
                    .frame(height: on ? 28 : 0)
            }
            .ignoresSafeArea()
        }
    }

    /// Keep scrolling content clear of the floating tab bar.
    func tabBarBackdrop(_ on: Bool) -> some View {
        contentMargins(.bottom, on ? UnfoldedSplit.tabBarClearance : 0, for: .scrollContent)
            .overlay(alignment: .bottom) {
                Theme.paper.frame(height: UnfoldedSplit.tabBarClearance)
                // Measured from the display's bottom edge: the floating bar isn't part of the
                // content's bottom safe area there.
                .ignoresSafeArea(.container, edges: .bottom)
                .opacity(on ? 1 : 0)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
    }

    /// A sheet on the phone. Unfolded, it covers only the pane it came from, so nothing
    /// sits across the fold. `close` dismisses it either way.
    func paneSheet<Sheet: View>(isPresented: Binding<Bool>, inPane: Bool,
                                @ViewBuilder content: @escaping (_ close: @escaping () -> Void) -> Sheet) -> some View {
        modifier(PaneSheet(isPresented: isPresented, inPane: inPane, sheet: content))
    }
}

private struct PaneSheet<Sheet: View>: ViewModifier {
    @Binding var isPresented: Bool
    let inPane: Bool
    let sheet: (_ close: @escaping () -> Void) -> Sheet

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: inPane ? .constant(false) : $isPresented) {
                sheet { isPresented = false }
            }
            .overlay {
                if inPane && isPresented {
                    sheet { isPresented = false }
                        .ignoresSafeArea(.container, edges: .bottom)
                        .clipShape(UnevenRoundedRectangle(topLeadingRadius: 18, topTrailingRadius: 18, style: .continuous))
                        .shadow(color: .black.opacity(0.12), radius: 12, y: -2)
                        .padding(.top, 8)
                        .transition(.move(edge: .bottom))
                }
            }
            .motion(.snappy, value: inPane && isPresented)
    }
}
