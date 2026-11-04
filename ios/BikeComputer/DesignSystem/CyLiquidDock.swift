import SwiftUI
import UIKit

/// Cyclift Liquid Dock (owner-approved prototype, 4 Nov): the one floating navigation capsule used by RootView.
/// Five slots in the existing order (Home, Plan, centre, Progress, Profile); the selection pill flows to the tapped
/// slot with a short spring and a slight stretch, then settles. One light haptic per tab change (none while a ride is
/// recording). Reduce Motion: the pill jumps and the centre glow is a static ring. Labels stop growing at xxLarge like the
/// system tab bar; every target is at least 44 pt. Identifiers and labels are the ones the existing tests use
/// (tab titles, `centreButton`); the centre button's destination is decided by the caller, exactly as before.
struct CyLiquidDock: View {
    @Binding var selection: Int
    let state: CyCentreState
    /// True when a planned session of the last 7 days was missed (small amber dot under the centre button).
    var missed = false
    let centreIcon: String
    let centreLabel: String
    let centreHint: String
    let onCentre: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var scheme
    /// The pulse stops once the centre button has been opened on this calendar day (no model change).
    @AppStorage("cyDockAcknowledgedDay") private var acknowledgedDay = ""
    @State private var stretch = false
    @State private var pulse = false

    private let items: [(id: Int, title: String, icon: String)] = [(0, "Home", "house.fill"), (1, "Plan", "calendar"), (3, "Progress", "chart.xyaxis.line"), (4, "Profile", "person.crop.circle")]
    private var slot: Int { [0, 1, 2, 3, 4].firstIndex(of: selection) ?? 0 }
    private var todayKey: String { ISO8601DateFormatter().string(from: Calendar.current.startOfDay(for: Date())).prefix(10).description }
    private var glowing: Bool { state.pulses && acknowledgedDay != todayKey }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, slotW = w / 5
            ZStack(alignment: .leading) {
                Capsule().fill(.ultraThinMaterial)
                    .overlay(Capsule().stroke(CyTheme.line.opacity(scheme == .dark ? 0.6 : 1), lineWidth: 1))
                    .shadow(color: Color.black.opacity(scheme == .dark ? 0.45 : 0.14), radius: 16, y: 8)
                // the liquid selection pill (not on the centre slot: the raised button is its own highlight)
                if selection != 2 {
                    Capsule().fill(CyTheme.cycling.bg.opacity(0.9))
                        .frame(width: slotW - 10, height: 48)
                        .scaleEffect(x: stretch ? 1.18 : 1, y: 1)
                        .offset(x: CGFloat(slot) * slotW + 5, y: 0)
                        .animation(reduceMotion ? nil : .spring(response: 0.5, dampingFraction: 0.72), value: slot)
                        .accessibilityHidden(true)
                }
                HStack(spacing: 0) {
                    tab(items[0]); tab(items[1])
                    centre.frame(width: slotW)
                    tab(items[2]); tab(items[3])
                }
            }
        }
        .frame(height: 64)
        .padding(.horizontal, 14)
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("liquidDock")
        .onAppear { pulse = true }
    }

    private func select(_ i: Int) {
        guard i != selection else { return }
        if !reduceMotion { stretch = true; DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) { stretch = false } }
        if state != .recording { UISelectionFeedbackGenerator().selectionChanged() }
        selection = i
    }

    private func tab(_ t: (id: Int, title: String, icon: String)) -> some View {
        let on = selection == t.id
        return Button { select(t.id) } label: {
            VStack(spacing: 3) {
                Image(systemName: t.icon).font(.system(size: 18, weight: .semibold))
                Text(t.title).font(.caption2.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.8)
            }
            .foregroundStyle(on ? CyTheme.cycling.tint : CyTheme.ink3)
            .frame(maxWidth: .infinity, minHeight: 64)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(t.title)
        .accessibilityAddTraits(on ? [.isSelected, .isButton] : .isButton)
        .accessibilityShowsLargeContentViewer { Label(t.title, systemImage: t.icon) }
    }

    // MARK: centre button — six looks, one destination (the caller's, unchanged)
    private var fill: Color {
        switch state {
        case .pending, .multiple: return CyTheme.cycling.tint
        case .active: return CyTheme.insight.tint
        case .done: return CyTheme.recovery.tint
        case .rest: return CyTheme.card2
        case .hold: return Color(.systemGray5)
        case .recording: return BC.live
        }
    }
    private var multipleCount: Int? { if case .multiple(let n) = state { return n }; return nil }
    private var iconColor: Color {
        switch state { case .rest: return CyTheme.ink2; case .hold: return BC.warn; default: return .white }
    }
    private var centre: some View {
        Button {
            acknowledgedDay = todayKey
            onCentre()
        } label: {
            VStack(spacing: 2) {
                ZStack {
                    if glowing {
                        Circle().stroke(CyTheme.cycling.tint, lineWidth: 2)
                            .frame(width: 54, height: 54)
                            .scaleEffect(reduceMotion ? 1.12 : (pulse ? 1.22 : 1.0))
                            .opacity(reduceMotion ? 0.5 : (pulse ? 0 : 0.7))
                            .animation(reduceMotion ? nil : .easeInOut(duration: 1.6).repeatForever(autoreverses: true), value: pulse)
                            .accessibilityHidden(true)
                    }
                    Circle().fill(fill).frame(width: 54, height: 54)
                        .shadow(color: fill.opacity(state == .rest || state == .hold ? 0 : 0.35), radius: 10, y: 5)
                        .overlay(Circle().stroke(state == .hold ? BC.warn.opacity(0.6) : Color.clear, lineWidth: 1.5))
                    Image(systemName: centreIcon).font(.system(size: state == .hold ? 20 : 23, weight: .bold)).foregroundStyle(iconColor)
                    if let n = multipleCount {
                        Text("\(n)").font(.system(size: 10, weight: .heavy)).foregroundStyle(CyTheme.canvas)
                            .padding(.horizontal, 5).frame(minWidth: 18, minHeight: 18).background(CyTheme.ink, in: Capsule())
                            .offset(x: 20, y: -20).accessibilityHidden(true)
                    }
                }
                .overlay(alignment: .bottom) {
                    if missed { Circle().fill(BC.warn).frame(width: 6, height: 6).offset(y: 9).accessibilityHidden(true) }
                }
                .offset(y: -12)
                Text(centreLabel).font(.caption2.weight(.bold)).foregroundStyle(selection == 2 ? CyTheme.cycling.tint : CyTheme.ink3)
                    .offset(y: -10).lineLimit(1).minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, minHeight: 64)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(centreHint)
        .accessibilityIdentifier("centreButton")
    }
}
