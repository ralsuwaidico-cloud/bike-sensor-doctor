import SwiftUI
import UIKit

// Navigation v1.2, revision 1.1 (approved visual baseline, 15 Nov 2026 — product/profile/nav-v12/final/
// NAVIGATION_V12_FINAL_VISUAL_SPECIFICATION.md). Train ball at the physical far left; Home, Plan, Progress in one
// sculpted capsule whose left end is a concave cradle around the ball. Profile has no tab.
//
// Shared code for both apps; switched on by `CyProduct.redesign` (on in Cyclift Lab; production keeps CyLiquidDock
// until the redesign is promoted).
//
// Geometry is the specification's (points): ball 72, capsule 56, ring gap 5, ball-to-tabs 15, capsule end inset 6,
// side margin 14 (applied by the caller), silhouette about 90 high, three equal tab regions 48 high.
// PROVISIONAL, stated on screen where it matters: the Train emblem is not selected (the dashed ring is the labelled
// placeholder); the specification names the Inter typeface, which the app does not bundle — the system face is used.
// Train ball states (sheet F4): idle, panel open, strength recording, ride recording, paused, completion pending,
// save unsuccessful or uncertain, interrupted and restored — drawn below from `CyTrainBallState` by ring and badge in
// the ordinary text colour (shape and line, never hue; the same drawing serves High Contrast). Rings never animate.
// NOT IMPLEMENTED here: Arabic ordering.

enum CyCradleMetrics {
    static let ball: CGFloat = 72
    static let capsule: CGFloat = 56
    static let gap: CGFloat = 5
    static let ballToTabs: CGFloat = 15
    static let endInset: CGFloat = 6
    static let sideMargin: CGFloat = 14
    static let height: CGFloat = 92
    static let regionHeight: CGFloat = 48

    // Position on the screen (final visual specification §1, sheet F1): the ball's bottom edge is 34 pt above the bottom
    // of the screen on phones with a home indicator and 16 pt on phones without one (capsule bottom 42 / 24 pt).
    // The ball is 72 pt in a 92 pt frame, so 10 pt of the frame lies below the ball.
    static let ballBottomWithIndicator: CGFloat = 34
    static let ballBottomWithoutIndicator: CGFloat = 16
    /// The bottom safe-area inset of the device (the home-indicator zone); 0 on phones without one. 34 until a window exists.
    /// NEVER call this while a view's body is being evaluated: asking the window for its insets during rendering left Home
    /// permanently un-redrawn (Lab runs 20–31). The shell reads it in a task and hands it down as `\.cyDeviceBottomInset`.
    static var deviceBottomInset: CGFloat {
        let w = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap { $0.windows }.first
        return w?.safeAreaInsets.bottom ?? 34
    }
    /// Padding under the dock's frame when it is placed as a bottom safe-area inset. Negative on home-indicator phones:
    /// the frame's empty 10 pt below the ball reaches into the indicator zone so the ball sits where F1 draws it.
    static func dockBottomPadding(deviceBottomInset s: CGFloat) -> CGFloat {
        let frameBelowBall = (height - ball) / 2
        return s > 0 ? ballBottomWithIndicator - frameBelowBall - s : ballBottomWithoutIndicator - frameBelowBall
    }
    /// Scrolling inset from the bottom of the screen (C2): 128 pt with a home indicator, 110 pt without.
    static func scrollInset(deviceBottomInset s: CGFloat) -> CGFloat { s > 0 ? 128 : 110 }
    /// What a redesigned page adds under its last item so the page ends at the scrolling inset. The shell already gives
    /// every scroll view 80 pt of bottom margin above the device's own bottom inset (ContentView).
    static func pageEndPadding(deviceBottomInset s: CGFloat) -> CGFloat { max(0, scrollInset(deviceBottomInset: s) - 80 - s) }
}

/// The device's bottom inset, read once by the shell outside any view's body (ContentView's task) and handed down.
/// A page must not ask the window for it while its body is being evaluated (see HomeView, Lab runs 29–31).
private struct CyDeviceBottomInsetKey: EnvironmentKey { static let defaultValue: CGFloat = 34 }
extension EnvironmentValues {
    var cyDeviceBottomInset: CGFloat {
        get { self[CyDeviceBottomInsetKey.self] }
        set { self[CyDeviceBottomInsetKey.self] = newValue }
    }
}

/// The capsule with its cradle: one continuous outline. Local coordinates: the ball's centre is (36, height / 2).
struct CyCradleShape: Shape {
    func path(in r: CGRect) -> Path {
        let cy = r.midY
        let B = CGPoint(x: r.minX + 36, y: cy)                     // ball centre
        let O = CGPoint(x: B.x + 5, y: cy)                         // centre of the arms' outer arc
        let inner: CGFloat = 41, outer: CGFloat = 46.3, half = CyCradleMetrics.capsule / 2
        let top = cy - half, bottom = cy + half
        func pt(_ c: CGPoint, _ radius: CGFloat, _ deg: CGFloat) -> CGPoint {       // deg: 0 = towards the tabs, negative = up
            let a = deg * .pi / 180; return CGPoint(x: c.x + radius * cos(a), y: c.y + radius * sin(a))
        }
        let tipInner: CGFloat = 70, tipOuter: CGFloat = 75.8, root: CGFloat = 45
        var p = Path()
        let shoulderX = r.minX + 104
        p.move(to: CGPoint(x: shoulderX, y: top))
        p.addLine(to: CGPoint(x: r.maxX - half, y: top))
        p.addArc(center: CGPoint(x: r.maxX - half, y: cy), radius: half, startAngle: .degrees(-90), endAngle: .degrees(90), clockwise: false)
        p.addLine(to: CGPoint(x: shoulderX, y: bottom))
        // lower shoulder: one eased curve from the capsule edge into the arm
        let lowRoot = pt(O, outer, root)
        p.addCurve(to: lowRoot, control1: CGPoint(x: shoulderX - 14, y: bottom), control2: CGPoint(x: lowRoot.x + 7.1, y: lowRoot.y - 7.1))
        var d = root
        while d < tipOuter { d = min(tipOuter, d + 2); p.addLine(to: pt(O, outer, d)) }           // lower arm, outer edge
        let lowTipOuter = pt(O, outer, tipOuter), lowTipInner = pt(B, inner, tipInner)
        p.addQuadCurve(to: lowTipInner, control: CGPoint(x: (lowTipOuter.x + lowTipInner.x) / 2 - 4.2, y: (lowTipOuter.y + lowTipInner.y) / 2 + 2.4))   // rounded tip
        d = tipInner
        while d > -tipInner { d = max(-tipInner, d - 2); p.addLine(to: pt(B, inner, d)) }          // the cradle, concentric with the ball
        let upTipOuter = pt(O, outer, -tipOuter), upTipInner = pt(B, inner, -tipInner)
        p.addQuadCurve(to: upTipOuter, control: CGPoint(x: (upTipOuter.x + upTipInner.x) / 2 - 4.2, y: (upTipOuter.y + upTipInner.y) / 2 - 2.4))
        d = -tipOuter
        while d < -root { d = min(-root, d + 2); p.addLine(to: pt(O, outer, d)) }                  // upper arm, outer edge
        let upRoot = pt(O, outer, -root)
        p.addCurve(to: CGPoint(x: shoulderX, y: top), control1: CGPoint(x: upRoot.x + 7.1, y: upRoot.y + 7.1), control2: CGPoint(x: shoulderX - 14, y: top))
        p.closeSubpath()
        return p
    }
}

// What the Train ball shows is the pure `CyTrainBallState` (Shell/CyTrainBallState.swift), built from the real session.

struct CyCradleDock: View {
    /// The app's numbered pages (unchanged): 0 Home, 1 Plan, 3 Progress. Profile (4) and Ride (2) have no tab; Home stays
    /// marked while Profile is shown, and nothing is marked while the hub is open.
    @Binding var selection: Int
    var hubOpen = false
    let ball: CyTrainBallState
    let onTrain: () -> Void

    @Environment(\.dynamicTypeSize) private var dts
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let tabs: [(id: Int, title: String, icon: String)] = [(0, "Home", "house.fill"), (1, "Plan", "calendar"), (3, "Progress", "chart.xyaxis.line")]
    private var marked: Int? { hubOpen ? nil : (selection == 4 ? 0 : selection) }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = CyCradleMetrics.height, cy = h / 2
            let tabsX = CyCradleMetrics.ball + CyCradleMetrics.ballToTabs
            let regionW = max(0, (w - tabsX - CyCradleMetrics.endInset) / 3)
            ZStack(alignment: .topLeading) {
                CyCradleShape()
                    .fill(CyTheme.card2)
                    .overlay(CyCradleShape().stroke(CyTheme.line, lineWidth: 1))
                    .shadow(color: Color.black.opacity(0.22), radius: 12, y: 6)
                    .frame(width: w, height: h)
                    .accessibilityHidden(true)
                    .allowsHitTesting(false)                    // the arms take no touches
                ForEach(Array(tabs.enumerated()), id: \.element.id) { i, t in
                    tab(t)
                        .frame(width: regionW, height: CyCradleMetrics.regionHeight)
                        .contentShape(Rectangle())
                        .offset(x: tabsX + CGFloat(i) * regionW, y: cy - CyCradleMetrics.regionHeight / 2)
                }
                trainBall
                    .frame(width: CyCradleMetrics.ball, height: CyCradleMetrics.ball)
                    .offset(x: 0, y: cy - CyCradleMetrics.ball / 2)
            }
        }
        .frame(height: CyCradleMetrics.height)
        .padding(.horizontal, CyCradleMetrics.sideMargin)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("cradleDock")
    }

    private func tab(_ t: (id: Int, title: String, icon: String)) -> some View {
        let on = marked == t.id
        let big = dts.isAccessibilitySize
        return Button {
            guard selection != t.id || hubOpen else { return }
            UISelectionFeedbackGenerator().selectionChanged()
            selection = t.id
        } label: {
            VStack(spacing: 4) {
                if big && !on { Image(systemName: t.icon).font(.system(size: 19, weight: .medium)) }
                else { Text(t.title).font(.system(size: big ? 20 : 13.5, weight: on ? .semibold : .medium)).lineLimit(1).minimumScaleFactor(0.85) }
                Capsule().fill(on ? CyTheme.ink : Color.clear).frame(width: 14, height: 2.5)       // the one selection indicator
            }
            .foregroundStyle(on ? CyTheme.ink : CyTheme.ink2)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(t.title)
        .accessibilityAddTraits(on ? [.isSelected, .isButton] : .isButton)
        .accessibilityShowsLargeContentViewer { Label(t.title, systemImage: t.icon) }
        .accessibilitySortPriority(Double(10 - t.id))          // read order: Home, Plan, Progress, then Train
    }

    private var trainBall: some View {
        Button(action: onTrain) {
            ZStack {
                ballFace
                ballRing
            }
            .overlay(alignment: .topLeading) { ballBadge }
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(ball.spoken)
        .accessibilityValue(ball.timerText ?? "")
        .accessibilityHint(ball.hint)
        .accessibilityIdentifier("centreButton")               // the Train control keeps the identifier the tests know
        .accessibilitySortPriority(0)
        .accessibilityShowsLargeContentViewer { Label(ball.timerText ?? "Train", systemImage: "figure.strengthtraining.traditional") }
    }

    /// The ball itself: filled, or an outline while the panel is open; inside it the time or the placeholder mark.
    @ViewBuilder private var ballFace: some View {
        if ball == .panelOpen {
            Circle().fill(CyTheme.canvas)
            Circle().strokeBorder(CyTheme.ink, lineWidth: 2)
            placeholder(CyTheme.ink)
        } else {
            Circle().fill(BC.accent)
            if let t = ball.timerText { timerText(t) } else { placeholder(BC.onAccent) }
        }
    }
    /// Emblem: Pending Selection — the dashed ring is the labelled placeholder from the specification.
    private func placeholder(_ c: Color) -> some View {
        Circle().stroke(c, style: StrokeStyle(lineWidth: 2.2, dash: [4.5, 3.5])).frame(width: 20, height: 20)
    }
    /// 16.5 pt in both formats; the text never shrinks. From one hour the "h" is drawn small ("1h04").
    private func timerText(_ t: String) -> some View {
        let big = Font.system(size: 16.5, weight: .bold, design: .rounded)
        let small = Font.system(size: 11, weight: .bold, design: .rounded)
        let parts = t.components(separatedBy: "h")
        let text: Text = parts.count == 2 ? Text(parts[0]).font(big) + Text("h").font(small) + Text(parts[1]).font(big) : Text(t).font(big)
        return text.monospacedDigit().foregroundStyle(BC.onAccent).lineLimit(1).fixedSize()
    }
    private var ringLine: StrokeStyle { StrokeStyle(lineWidth: 2.6, lineCap: .butt) }
    /// The state ring, radius 38.7 pt, wholly inside the 5 pt gap between the ball and the cradle.
    @ViewBuilder private var ballRing: some View {
        switch ball.ring {
        case .none:
            EmptyView()
        case .segmented:
            Circle().stroke(CyTheme.ink, style: StrokeStyle(lineWidth: 2.6, dash: [9, 4])).padding(-2.7)
        case .solid:
            Circle().stroke(CyTheme.ink, lineWidth: 2.6).padding(-2.7)
        case .split:
            ZStack {
                Circle().trim(from: 0.04, to: 0.46).stroke(CyTheme.ink, style: ringLine)
                Circle().trim(from: 0.54, to: 0.96).stroke(CyTheme.ink, style: ringLine)
            }
            .rotationEffect(.degrees(-45)).padding(-2.7)
        case .threeQuarter:
            Circle().trim(from: 0, to: 0.75).stroke(CyTheme.ink, style: ringLine).rotationEffect(.degrees(-90)).padding(-2.7)
        case .dotted:
            Circle().stroke(CyTheme.ink, style: StrokeStyle(lineWidth: 2.6, lineCap: .round, dash: [0.1, 6])).padding(-2.7)
        }
    }
    /// The badge at the ball's outer top-left: dot, pause bars, "…", "!" or "↺".
    @ViewBuilder private var ballBadge: some View {
        if ball.badge != .none {
            ZStack {
                Circle().fill(CyTheme.canvas)
                Circle().stroke(CyTheme.ink, lineWidth: 1.5)
                badgeMark
            }
            .frame(width: 20, height: 20)
            .offset(x: -4, y: -4)
            .accessibilityHidden(true)
        }
    }
    @ViewBuilder private var badgeMark: some View {
        switch ball.badge {
        case .none:
            EmptyView()
        case .dot:
            Circle().fill(CyTheme.ink).frame(width: 8, height: 8)
        case .pauseBars:
            HStack(spacing: 2.5) {
                Capsule().fill(CyTheme.ink).frame(width: 2.5, height: 9)
                Capsule().fill(CyTheme.ink).frame(width: 2.5, height: 9)
            }
        case .ellipsis:
            Image(systemName: "ellipsis").font(.system(size: 9, weight: .heavy)).foregroundStyle(CyTheme.ink)
        case .exclamation:
            Text("!").font(.system(size: 13, weight: .heavy, design: .rounded)).foregroundStyle(CyTheme.ink)
        case .restore:
            Image(systemName: "arrow.counterclockwise").font(.system(size: 10, weight: .heavy)).foregroundStyle(CyTheme.ink)
        }
    }
}


/// The page's own background behind the dock: solid under it, fading out over the 12 pt above it, down to the bottom
/// edge of the screen. 12 pt, because pages end 13 pt or more above the dock (Home: 128 pt scrolling inset, sheet F1),
/// so the last control of a page is never inside the fade. It takes no touches.
struct CyDockBackdrop: View {
    @ObservedObject private var theme = CyThemeState.shared      // redraws with the theme
    var body: some View {
        let c = CyTheme.canvas
        VStack(spacing: 0) {
            LinearGradient(colors: [c.opacity(0), c], startPoint: .top, endPoint: .bottom).frame(height: 12)
            c
        }
            .padding(.top, -12)
            .ignoresSafeArea(edges: .bottom)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}
