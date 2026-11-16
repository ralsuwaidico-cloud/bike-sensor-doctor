import SwiftUI
import UIKit

// Navigation v1.2, revision 1.1 (approved visual baseline, 15 Nov 2026 — product/profile/nav-v12/final/
// NAVIGATION_V12_FINAL_VISUAL_SPECIFICATION.md). Train ball at the physical far left; Home, Plan, Progress in one
// sculpted capsule whose left end is a concave cradle around the ball. Profile has no tab.
//
// Used by Cyclift Lab only (ContentView, `#if CYCLIFT_LAB`). The production app keeps CyLiquidDock.
//
// Geometry is the specification's (points): ball 72, capsule 56, ring gap 5, ball-to-tabs 15, capsule end inset 6,
// side margin 14 (applied by the caller), silhouette about 90 high, three equal tab regions 48 high.
// PROVISIONAL, stated on screen where it matters: the Train emblem is not selected (the dashed ring is the labelled
// placeholder); the specification names the Inter typeface, which the app does not bundle — the system face is used.
// NOT IMPLEMENTED here: minimised-session timer states other than "active", Arabic ordering, the compact panel (the
// ball opens the existing hub until Training Hub v1.4 is built).

enum CyCradleMetrics {
    static let ball: CGFloat = 72
    static let capsule: CGFloat = 56
    static let gap: CGFloat = 5
    static let ballToTabs: CGFloat = 15
    static let endInset: CGFloat = 6
    static let sideMargin: CGFloat = 14
    static let height: CGFloat = 92
    static let regionHeight: CGFloat = 48
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

/// What the Train ball shows. Position and size never change; states differ by ring and badge, never by colour alone.
enum CyTrainBallState: Equatable {
    case idle
    /// A strength session is in progress: elapsed seconds.
    case active(Int)
    /// A ride is being recorded (the ball returns to the Ride screen; ride minimisation is blocked by the safety gate).
    case recording

    /// MM:SS under one hour, "1h04" style from one hour (approved timer rule).
    static func clock(_ s: Int) -> String {
        let s = max(0, s)
        return s < 3600 ? String(format: "%02d:%02d", s / 60, s % 60) : String(format: "%dh%02d", s / 3600, (s % 3600) / 60)
    }
    var spoken: String {
        switch self {
        case .idle: return "Train, no active session"
        case .active(let s): return "Strength workout in progress, \(max(1, s / 60)) minutes elapsed"
        case .recording: return "Ride recording"
        }
    }
}

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
                Circle().fill(BC.accent)
                switch ball {
                case .idle:
                    // emblem: Pending Selection — the dashed ring is the labelled placeholder from the specification
                    Circle().stroke(BC.onAccent, style: StrokeStyle(lineWidth: 2.2, dash: [4.5, 3.5])).frame(width: 20, height: 20)
                case .active(let s):
                    Text(CyTrainBallState.clock(s)).font(.system(size: 16.5, weight: .bold, design: .rounded)).monospacedDigit().foregroundStyle(BC.onAccent)
                    Circle().stroke(CyTheme.ink, style: StrokeStyle(lineWidth: 2.6, dash: [9, 4])).padding(-2.7)      // segmented ring in the 5-pt gap
                case .recording:
                    Image(systemName: "bicycle").font(.system(size: 20, weight: .bold)).foregroundStyle(BC.onAccent)
                    Circle().stroke(CyTheme.ink, lineWidth: 2.6).padding(-2.7)                                        // solid ring
                }
            }
            .overlay(alignment: .topLeading) {
                if ball != .idle {
                    Circle().fill(CyTheme.canvas).frame(width: 20, height: 20)
                        .overlay(Circle().stroke(CyTheme.ink, lineWidth: 1.5))
                        .overlay(Circle().fill(CyTheme.ink).frame(width: 8, height: 8))
                        .offset(x: -4, y: -4)
                }
            }
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(ball.spoken)
        .accessibilityHint("Opens training")
        .accessibilityIdentifier("centreButton")               // the Train control keeps the identifier the tests know
        .accessibilitySortPriority(0)
        .accessibilityShowsLargeContentViewer { Label("Train", systemImage: "figure.strengthtraining.traditional") }
    }
}
