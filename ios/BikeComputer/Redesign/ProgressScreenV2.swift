import SwiftUI

// Progress — approved compact hero (decision 13 Nov 2026: PROGRESS_V23_COMPACT_HERO): the singularity that travels into
// the header as the page scrolls, the athlete's stage identity, and the Evolution Track. Brought from the UI Lab proof
// of concept into the one app; shown where CyProduct.redesign is on.
//
// HONESTY RULES
// • There is NO stage engine: the criteria for G0–G5 are not approved (baseline register, item 7). The app therefore
//   always shows the approved "no evaluation yet" state. The other states stay in the code for the day criteria exist,
//   and nothing here calculates or claims a stage.
// • The singularity is a FLAT, STATIC PLACEHOLDER drawn with ordinary shapes: no shader, no motion of its own.
// • The analysis under the track is the app's real Progress content, supplied by the caller.

// MARK: - Sample model

enum ProgressHeroState: String, CaseIterable {
    case g0, g2, g2prov, g5, first, returning
}

enum ProgressGen {
    static let names = ["The Initiate", "The Builder", "The Ascendant", "The Proven", "The Refined", "The Apex"]
    static func name(_ g: Int) -> String { names[min(max(g, 0), 5)] }
}

struct ProgressSample {
    var state: ProgressHeroState
    /// The current supported evaluation; nil when there is none (first-time or returning athlete).
    var current: Int?
    /// The highest generation ever achieved; nil when none.
    var highest: Int?
    var provisional = false
    var profile: String
    var evidence: String

    static func make(_ s: ProgressHeroState) -> ProgressSample {
        switch s {
        case .g0: return ProgressSample(state: s, current: 0, highest: 0, profile: "Developing Hybrid", evidence: "Evidence-supported · Evaluated 9 Nov")
        case .g2: return ProgressSample(state: s, current: 2, highest: 2, profile: "Developing Hybrid", evidence: "Evidence-supported · Evaluated 9 Nov")
        case .g2prov: return ProgressSample(state: s, current: 2, highest: 2, provisional: true, profile: "Developing Hybrid", evidence: "Provisional · Evaluated 9 Nov")
        case .g5: return ProgressSample(state: s, current: 5, highest: 5, profile: "Balanced Hybrid", evidence: "Evidence-supported · Evaluated 9 Nov")
        case .first: return ProgressSample(state: s, current: nil, highest: nil, profile: "No stage yet — not enough evidence to evaluate", evidence: "")
        case .returning: return ProgressSample(state: s, current: nil, highest: 3, profile: "Highest achieved: G3 · The Proven · 14 Mar 2027", evidence: "Last evaluated 2 May 2027 · training resumed this week")
        }
    }

    /// What the app shows today: no stage, because Cyclift does not evaluate stages yet.
    static let notEvaluated = ProgressSample(state: .first, current: nil, highest: nil,
                                             profile: "No stage yet. Cyclift does not evaluate stages in this version.", evidence: "")

    var headline: String {
        if let g = current { return ProgressGen.name(g).uppercased() }
        return highest == nil ? "ESTABLISHING YOUR BASELINE" : "NOT CURRENTLY EVALUATED"
    }
    var identityLabel: String {
        if let g = current { return "Athlete Evolution. G\(g), \(ProgressGen.name(g)). \(profile). \(evidence)." }
        return "Athlete Evolution. \(headline.capitalized). \(profile). \(evidence)"
    }
    /// One VoiceOver sentence for the whole track.
    var trackLabel: String {
        if let g = current {
            var s = "Evolution track. Current generation G\(g), \(ProgressGen.name(g))\(provisional ? ", provisional" : "")."
            s += " Highest achieved G\(highest ?? g)."
            if g > 0 { s += " Previous G\(g - 1), \(ProgressGen.name(g - 1))." }
            if g < 5 { s += " Next G\(g + 1), \(ProgressGen.name(g + 1))." } else { s += " Highest generation. Development continues." }
            return s
        }
        if let h = highest {
            var s = "Evolution track. Not currently evaluated. Highest achieved G\(h), \(ProgressGen.name(h))."
            if h > 0 { s += " Previous G\(h - 1), \(ProgressGen.name(h - 1))." }
            if h < 5 { s += " Next G\(h + 1), \(ProgressGen.name(h + 1))." }
            return s
        }
        return "Evolution track. Establishing your baseline. No generation yet."
    }
}

// MARK: - Flat placeholder singularity

/// Flat, static stand-in for the future rendered singularity. `diameter` is the lensed body (the size the approved
/// design measures as "black hole including lensing ring"); `detail` runs from 1 (hero) to 0 (header symbol).
struct SingularityPlaceholder: View {
    let diameter: CGFloat
    let detail: CGFloat
    @Environment(\.cyTheme) private var theme

    private var flat: Bool { theme.id == .highContrast }
    private var discWidth: CGFloat { diameter * 1.31 }          // 180 pt at a 137 pt body
    private var shadow: CGFloat { diameter * 0.63 }             // 86 pt at a 137 pt body
    private var line: CGFloat { max(1, diameter * 0.014) }

    var body: some View {
        ZStack {
            if !flat {
                // Localised halo: drawn outside the layout frame, so it can never change the hero's height.
                Circle()
                    .fill(RadialGradient(colors: [theme.accent.opacity(0.20 * Double(detail)), theme.accent.opacity(0)],
                                         center: .center, startRadius: diameter * 0.34, endRadius: diameter * 0.60))
                    .frame(width: diameter * 1.2, height: diameter * 1.2)
            }
            Ellipse().stroke(theme.accent.opacity(0.45 * Double(detail)), lineWidth: line)
                .frame(width: discWidth, height: discWidth * 0.27).rotationEffect(.degrees(-7))
            Circle().fill(flat ? Color.clear : theme.accent.opacity(0.30))
                .frame(width: diameter, height: diameter)
            Circle().stroke(flat ? theme.textPrimary : theme.accent.opacity(0.55), lineWidth: line)
                .frame(width: diameter, height: diameter)
            Circle().fill(theme.isDark ? Color.black : theme.textPrimary)
                .frame(width: shadow, height: shadow)
            Circle().stroke(flat ? theme.accent : theme.textPrimary.opacity(theme.isDark ? 0.9 : 0.0), lineWidth: max(1, line * 1.2))
                .frame(width: shadow, height: shadow)
            Ellipse().trim(from: 0, to: 0.5).stroke(flat ? theme.textPrimary : theme.accent, style: StrokeStyle(lineWidth: line * 1.6, lineCap: .round))
                .frame(width: discWidth, height: discWidth * 0.27).rotationEffect(.degrees(-7))
                .opacity(0.35 + 0.65 * Double(detail))
        }
        .frame(width: diameter, height: diameter)
    }
}

// MARK: - Evolution Track

private enum TrackMarker { case done, current, provisional, next, highest, baseline }

private struct TrackNode {
    var marker: TrackMarker
    var title: String
    var lines: [String]
    var emphasised = false
    var accentLines = false
}

private struct TrackSegment: Identifiable {
    let id: Int
    var from: Int
    var to: Int            // 3 = runs to the trailing edge
    var dotted: Bool
}

private struct TrackPressStyle: ButtonStyle {
    let pressed: Color
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.background(configuration.isPressed ? pressed : Color.clear)
    }
}

/// A sequence of stages, never a progress bar: nothing is filled or positioned by a calculated amount.
struct ProgressEvolutionTrack: View {
    let sample: ProgressSample
    let onOpen: () -> Void
    @Environment(\.cyTheme) private var theme
    @Environment(\.dynamicTypeSize) private var typeSize

    private let markerBox: CGFloat = 30

    private var nodes: [TrackNode?] {
        if let g = sample.current {
            let prev: TrackNode? = g > 0 ? TrackNode(marker: .done, title: "G\(g - 1)", lines: [ProgressGen.name(g - 1)]) : nil
            var here = ["YOU ARE HERE"]
            if sample.provisional { here.append("PROVISIONAL") }
            let cur = TrackNode(marker: sample.provisional ? .provisional : .current, title: "G\(g)", lines: here, emphasised: true, accentLines: true)
            let next: TrackNode? = g < 5 ? TrackNode(marker: .next, title: "G\(g + 1)", lines: [ProgressGen.name(g + 1)]) : nil
            return [prev, cur, next]
        }
        if let h = sample.highest {
            let prev: TrackNode? = h > 0 ? TrackNode(marker: .done, title: "G\(h - 1)", lines: [ProgressGen.name(h - 1)]) : nil
            let cur = TrackNode(marker: .highest, title: "G\(h)", lines: ["HIGHEST ACHIEVED"], emphasised: true)
            let next: TrackNode? = h < 5 ? TrackNode(marker: .next, title: "G\(h + 1)", lines: [ProgressGen.name(h + 1)]) : nil
            return [prev, cur, next]
        }
        return [nil, TrackNode(marker: .baseline, title: "Baseline", lines: ["being established"]), nil]
    }

    private var segments: [TrackSegment] {
        let n = nodes
        var out: [TrackSegment] = []
        if n[0] != nil { out.append(TrackSegment(id: 0, from: 0, to: 1, dotted: false)) }
        if n[2] != nil { out.append(TrackSegment(id: 1, from: 1, to: 2, dotted: true)) }
        if sample.current == nil && sample.highest == nil { out.append(TrackSegment(id: 2, from: 1, to: 3, dotted: true)) }
        return out
    }

    var body: some View {
        Button(action: onOpen) {
            Group {
                if typeSize.isAccessibilitySize { stacked } else { row }
            }
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, minHeight: CyHit.min)
            .contentShape(Rectangle())
        }
        .buttonStyle(TrackPressStyle(pressed: theme.pressedOverlay))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(sample.trackLabel)
        .accessibilityHint("Opens Athlete Evolution details")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { onOpen() }
        .accessibilityIdentifier("evolutionTrack")
    }

    // Default text sizes: three columns joined by a thin line.
    private var row: some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(0..<3, id: \.self) { i in
                column(nodes[i], trailingNote: i == 2 && sample.current == 5)
                    .frame(maxWidth: .infinity)
            }
        }
        .background(alignment: .top) { lines.frame(height: markerBox) }
    }

    // Accessibility text sizes: one stage per row so nothing is truncated.
    private var stacked: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(0..<3, id: \.self) { i in
                if let n = nodes[i] {
                    HStack(alignment: .center, spacing: 12) {
                        markerView(n.marker).frame(width: markerBox, height: markerBox)
                        VStack(alignment: .leading, spacing: 2) { labels(n, alignment: .leading) }
                        Spacer(minLength: 0)
                    }
                }
            }
            if sample.current == 5 {
                Text("Highest generation · keeps developing").font(.caption2).foregroundStyle(theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 16)
    }

    @ViewBuilder private func column(_ node: TrackNode?, trailingNote: Bool) -> some View {
        if let n = node {
            VStack(spacing: 2) {
                markerView(n.marker).frame(height: markerBox)
                labels(n, alignment: .center)
            }
        } else if trailingNote {
            VStack(spacing: 2) {
                Color.clear.frame(height: markerBox)
                Text("Highest generation").font(.caption2).foregroundStyle(theme.textSecondary)
                    .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                Text("keeps developing").font(.caption2).foregroundStyle(theme.textSecondary)
                    .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            }
        } else {
            Color.clear.frame(height: markerBox)
        }
    }

    @ViewBuilder private func labels(_ n: TrackNode, alignment: TextAlignment) -> some View {
        Text(n.title)
            .font(n.emphasised ? Font.system(.headline, design: .rounded).weight(.heavy) : Font.system(.footnote).weight(.semibold))
            .foregroundStyle(n.emphasised ? theme.textPrimary : theme.textSecondary)
        ForEach(n.lines, id: \.self) { l in
            Text(l)
                .font(n.emphasised ? Font.system(.caption2).weight(.bold) : Font.system(.caption2))
                .tracking(n.emphasised ? 1.2 : 0)
                .foregroundStyle(n.accentLines ? theme.accent : theme.textSecondary)
                .multilineTextAlignment(alignment)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder private func markerView(_ m: TrackMarker) -> some View {
        switch m {
        case .done:
            Circle().fill(theme.textSecondary).frame(width: 10, height: 10)
        case .current:
            ZStack {
                Circle().stroke(theme.accent, lineWidth: 1.6).frame(width: 26, height: 26)
                Circle().fill(theme.accent).frame(width: 16, height: 16)
            }
        case .provisional:
            ZStack {
                Circle().stroke(theme.accent, style: StrokeStyle(lineWidth: 1.6, dash: [3, 4])).frame(width: 26, height: 26)
                Circle().stroke(theme.accent, lineWidth: 2.6).frame(width: 14, height: 14)
            }
        case .next:
            Circle().stroke(theme.textSecondary, lineWidth: 1.8).frame(width: 16, height: 16)
        case .highest:
            ZStack {
                Circle().stroke(theme.textSecondary, lineWidth: 1.6).frame(width: 24, height: 24)
                Circle().fill(theme.textSecondary).frame(width: 14, height: 14)
            }
        case .baseline:
            RoundedRectangle(cornerRadius: 3.5).stroke(theme.textSecondary, lineWidth: 1.8).frame(width: 15, height: 15)
        }
    }

    private var lines: some View {
        GeometryReader { g in
            let w = g.size.width
            let y = g.size.height / 2
            ForEach(segments) { s in
                Path { p in
                    let x0 = w * (CGFloat(s.from) * 2 + 1) / 6 + 16
                    let x1 = s.to == 3 ? w - 8 : w * (CGFloat(s.to) * 2 + 1) / 6 - 14
                    p.move(to: CGPoint(x: x0, y: y))
                    p.addLine(to: CGPoint(x: max(x1, x0), y: y))
                }
                .stroke(theme.textSecondary.opacity(0.8),
                        style: StrokeStyle(lineWidth: 1.4, lineCap: .round, dash: s.dotted ? [1.5, 5] : []))
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Screen

private struct HeroMetrics {
    var body: CGFloat          // lensed body diameter
    var slot: CGFloat          // layout height reserved for the singularity
    static func make(narrow: Bool) -> HeroMetrics {
        narrow ? HeroMetrics(body: 115, slot: 128) : HeroMetrics(body: 137, slot: 150)
    }
}

struct ProgressScreen<Analysis: View>: View {
    let sample: ProgressSample
    var bottomInset: CGFloat = 0
    /// The real analysis under the hero. It receives the page's scroll proxy so its own "jump to" buttons keep working.
    let analysis: (ScrollViewProxy) -> Analysis
    var launchScroll: String? = nil          // expanded | mid | collapsed (screenshots only)
    var forceReduceMotion = false            // prototype override, so the Reduce Motion path can be exercised
    var showProbe = false                    // exposes the measured geometry to the interaction tests

    @Environment(\.cyTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @ScaledMetric(relativeTo: .largeTitle) private var generationSize: CGFloat = 36

    @State private var frames: [String: CGRect] = [:]
    @State private var rmCollapsed = false
    @State private var path: [String] = []
    @State private var anchorOffset: CGFloat = 0

    /// A page the content asks for by name (the host sets it; this screen pushes it and clears it).
    var route: Binding<String?> = .constant(nil)
    /// The host's own pages by name; nil = the Athlete Evolution page.
    var destination: (String) -> AnyView? = { _ in nil }

    init(sample: ProgressSample, bottomInset: CGFloat = 0, launchScroll: String? = nil, forceReduceMotion: Bool = false,
         showProbe: Bool = false, route: Binding<String?> = .constant(nil), destination: @escaping (String) -> AnyView? = { _ in nil },
         @ViewBuilder analysis: @escaping (ScrollViewProxy) -> Analysis) {
        self.sample = sample; self.bottomInset = bottomInset; self.launchScroll = launchScroll
        self.forceReduceMotion = forceReduceMotion; self.showProbe = showProbe; self.analysis = analysis
        self.route = route; self.destination = destination
    }

    private let space = "progressRoot"
    private let headerHeight: CGFloat = 48
    private let symbolSize: CGFloat = 30
    private var reduceMotion: Bool { forceReduceMotion || systemReduceMotion }

    var body: some View {
        NavigationStack(path: $path) {
            GeometryReader { root in
                page(HeroMetrics.make(narrow: root.size.width <= 380), safeTop: root.safeAreaInsets.top, width: root.size.width)
            }
            .navigationTitle("Progress")
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: String.self) { name in
                routed(name)
            }
            .onChange(of: route.wrappedValue) { _, r in if let r { path.append(r); route.wrappedValue = nil } }
        }
    }

    /// The page for a route: the redesigned Progress pages first (Redesign/ProgressDetailV2.swift), then a page the
    /// host supplies under another name, else Athlete Evolution.
    @ViewBuilder private func routed(_ name: String) -> some View {
        if let page = ProgressRoute.page(name) { page }
        else if let page = destination(name) { page }
        else { EvolutionDetailsPage(sample: sample, bottomInset: bottomInset) }
    }

    /// Sheet PH4: the "•••" button at the top right. Every entry opens a page that exists; nothing here is a placeholder.
    private var moreMenu: some View {
        Menu {
            Button("Detailed analytics") { path.append(ProgressRoute.analytics) }.accessibilityIdentifier("progressMenuAnalytics")
            Button("Records & history") { path.append(ProgressRoute.history) }.accessibilityIdentifier("progressMenuHistory")
            Button("Athlete Evolution") { path.append(ProgressRoute.evolution) }.accessibilityIdentifier("progressMenuEvolution")
            Button("Power settings") { path.append(ProgressRoute.power) }.accessibilityIdentifier("progressMenuPower")
            Button("Heart-rate settings") { path.append(ProgressRoute.heartRate) }.accessibilityIdentifier("progressMenuHeartRate")
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(theme.textPrimary)
                .frame(width: 32, height: 32)
                .background(Circle().fill(theme.surface2))
                .overlay(Circle().stroke(theme.cardStroke, lineWidth: 1))
                .frame(width: CyHit.min, height: CyHit.min)
                .contentShape(Rectangle())
        }
        .accessibilityLabel("More")
        .accessibilityIdentifier("progressMenu")
    }

    // MARK: geometry

    private func frame(_ name: String) -> CGRect { frames[name] ?? .zero }
    private func record(_ name: String, _ f: CGRect) {
        frames[name] = f
        guard reduceMotion, name == "slot" else { return }
        // Reduce Motion: two states only, exchanged at one threshold with a gap so it cannot flicker.
        if !rmCollapsed && f.maxY <= headerHeight + 4 { rmCollapsed = true }
        else if rmCollapsed && f.maxY >= headerHeight + 36 { rmCollapsed = false }
    }
    private func measure(_ name: String) -> some View {
        GeometryReader { g in
            let f = g.frame(in: .named(space))
            Color.clear
                .onAppear { record(name, f) }
                .onChange(of: f) { _, new in record(name, new) }
        }
    }

    /// Scroll offset in points (0 at rest, positive when scrolled up).
    private var offset: CGFloat { frames["content"] == nil ? 0 : headerHeight - frame("content").minY }
    /// Distance over which the transformation happens: from the singularity's resting centre to the header centre.
    private var distance: CGFloat { max(frame("slot").midY + offset - headerHeight / 2, 1) }
    /// 0 expanded … 1 collapsed. A function of scroll position only.
    private var progress: CGFloat {
        if reduceMotion { return rmCollapsed ? 1 : 0 }
        return min(max(offset / distance, 0), 1)
    }
    private func lerp(_ a: CGFloat, _ b: CGFloat, _ t: CGFloat) -> CGFloat { a + (b - a) * t }

    // MARK: page

    private func page(_ m: HeroMetrics, safeTop: CGFloat, width: CGFloat) -> some View {
        let p = progress
        return ZStack(alignment: .topLeading) {
            ScrollViewReader { proxy in
                ScrollView {
                    content(m, proxy: proxy)
                        .background(measure("content"))
                        .overlay(alignment: .top) { launchAnchor }
                }
                .accessibilityIdentifier("progressScroll")
                .safeAreaInset(edge: .top, spacing: 0) { Color.clear.frame(height: headerHeight) }
                .task { await applyLaunchScroll(proxy) }
            }
            header(p, hole: holeSize(m, p), safeTop: safeTop, width: width)
            if !reduceMotion && frames["slot"] != nil {
                // ONE singularity for the whole journey: it follows its slot while the page scrolls, shrinks with
                // the scroll position, and stops in the header. There is no second copy to cross-fade with.
                SingularityPlaceholder(diameter: holeSize(m, p), detail: 1 - p)
                    .accessibilityElement()
                    .accessibilityLabel("Athlete singularity")
                    .accessibilityAddTraits(.isImage)
                    .accessibilityIdentifier("singularity")
                    .position(x: lerp(frame("slot").midX, 16 + symbolSize / 2, p),
                              y: max(frame("slot").midY, headerHeight / 2))
                    .allowsHitTesting(false)
            }
        }
        .coordinateSpace(name: space)
        .background(theme.background.ignoresSafeArea())
    }

    private func holeSize(_ m: HeroMetrics, _ p: CGFloat) -> CGFloat { lerp(m.body, symbolSize, p) }

    private var launchAnchor: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: max(anchorOffset, 0))
            Color.clear.frame(height: 1).id("launchAnchor")
            Spacer(minLength: 0)
        }
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }

    @MainActor private func applyLaunchScroll(_ proxy: ScrollViewProxy) async {
        guard let target = launchScroll, target != "expanded" else { return }
        try? await Task.sleep(nanoseconds: 700_000_000)
        let d = max(frame("slot").midY - headerHeight / 2, 1)
        anchorOffset = target == "mid" ? d * 0.5 : d + 70
        try? await Task.sleep(nanoseconds: 200_000_000)
        proxy.scrollTo("launchAnchor", anchor: .top)
    }

    // MARK: header

    private func header(_ p: CGFloat, hole: CGFloat, safeTop: CGFloat, width: CGFloat) -> some View {
        let solid: CGFloat = reduceMotion ? (offset > 2 ? 1 : 0) : min(max((p - 0.15) / 0.45, 0), 1)
        return HStack(spacing: 6) {
            Text("Progress")
                .font(.system(size: lerp(27, 20, p), weight: .heavy, design: .rounded))
                .foregroundStyle(theme.textPrimary)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("progressTitle")
            if let g = sample.current {
                Text("· G\(g)")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(theme.textSecondary)
                    .opacity(Double(min(max((p - 0.8) / 0.2, 0), 1)))
                    .accessibilityHidden(p < 0.95)
                    .accessibilityLabel("Generation \(g)")
                    .accessibilityIdentifier("headerGeneration")
            }
            Spacer(minLength: 0)
            if showProbe { probe(p, hole: hole, safeTop: safeTop, width: width) }
            moreMenu
        }
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .padding(.leading, lerp(16, 16 + symbolSize + 8, p))
        .padding(.trailing, 10)          // the 32 pt button inside its 44 pt target ends 16 pt from the edge (sheet PH4)
        .frame(height: headerHeight)
        .background(alignment: .leading) {
            if reduceMotion {
                // Reduce Motion: the compact symbol simply appears; nothing travels or shrinks.
                SingularityPlaceholder(diameter: symbolSize, detail: 0)
                    .accessibilityElement()
                    .accessibilityLabel("Athlete singularity")
                    .accessibilityAddTraits(.isImage)
                    .accessibilityHidden(!rmCollapsed)
                    .accessibilityIdentifier("singularity")
                    .opacity(rmCollapsed ? 1 : 0)
                    .animation(.easeInOut(duration: 0.18), value: rmCollapsed)
                    .padding(.leading, 16)
            }
        }
        .background(theme.background.opacity(Double(solid)).ignoresSafeArea(edges: .top))
        .overlay(alignment: .bottom) {
            Rectangle().fill(theme.separator).frame(height: 1).opacity(Double(solid)).accessibilityHidden(true)
        }
    }

    private func probe(_ p: CGFloat, hole: CGFloat, safeTop: CGFloat, width: CGFloat) -> some View {
        let v = String(format: "offset=%.1f;p=%.3f;hole=%.1f;hero=%.1f;track=%.1f;slotMidY=%.1f;trackMinY=%.1f;safeTop=%.1f;width=%.0f;mode=%@;collapsed=%ld",
                       Double(offset), Double(p), Double(hole), Double(frame("hero").height), Double(frame("track").height),
                       Double(frame("slot").midY), Double(frame("track").minY), Double(safeTop), Double(width),
                       reduceMotion ? "reduceMotion" : "scroll", (reduceMotion ? rmCollapsed : p >= 1) ? 1 : 0)
        return Color.clear.frame(width: 2, height: 2)
            .accessibilityElement()
            .accessibilityLabel("Layout probe")
            .accessibilityValue(v)
            .accessibilityIdentifier("progressProbe")
    }

    // MARK: content

    private func content(_ m: HeroMetrics, proxy: ScrollViewProxy) -> some View {
        let fade = Double(1 - min(max(progress / 0.6, 0), 1))
        return VStack(spacing: 0) {
            VStack(spacing: 0) {
                // The space the singularity occupies when expanded. With motion it is empty and the single travelling
                // singularity is drawn over it; with Reduce Motion the static singularity sits here and scrolls away.
                ZStack {
                    if reduceMotion && !rmCollapsed {
                        SingularityPlaceholder(diameter: m.body, detail: 1)
                            .accessibilityElement()
                            .accessibilityLabel("Athlete singularity")
                            .accessibilityAddTraits(.isImage)
                            .accessibilityIdentifier("singularity")
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: m.slot)
                .background(measure("slot"))
                identity.opacity(reduceMotion ? 1 : fade)
                ProgressEvolutionTrack(sample: sample) { path.append("evolution") }
                    .padding(.horizontal, -16)
                    .padding(.top, 8)
                    .background(measure("track"))
            }
            .background(measure("hero"))
            analysis(proxy).padding(.top, 22)
                .environment(\.progressOpen, { name in path.append(name) })
        }
        .padding(.horizontal, 16)
        .padding(.bottom, bottomInset + 24)
    }

    private var identity: some View {
        VStack(spacing: 3) {
            if let g = sample.current {
                Text("G\(g)")
                    .font(.system(size: generationSize, weight: .heavy, design: .rounded))
                    .foregroundStyle(theme.textPrimary)
                    .accessibilityIdentifier("heroGeneration")
            }
            Text(sample.headline)
                .font(Font.system(.subheadline, design: .rounded).weight(.heavy))
                .tracking(2.4)
                .foregroundStyle(theme.textPrimary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("heroStage")
            Text(sample.profile)
                .font(.footnote)
                .foregroundStyle(theme.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if !sample.evidence.isEmpty {
                HStack(spacing: 5) {
                    if sample.current != nil { Circle().fill(theme.accent).frame(width: 7, height: 7) }
                    Text(sample.evidence)
                        .font(Font.system(.caption).weight(.semibold))
                        .foregroundStyle(theme.textSecondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(sample.identityLabel)
        .accessibilityIdentifier("heroIdentity")
    }
}

// MARK: - Athlete Evolution

/// What the Evolution Track opens. The approved details design needs approved stage criteria; until they exist this
/// page says plainly what is and is not evaluated, and never shows a stage the app did not work out.
struct EvolutionDetailsPage: View {
    let sample: ProgressSample
    var bottomInset: CGFloat = 0
    @Environment(\.cyTheme) private var theme
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Athlete Evolution")
                    .font(Font.system(.title, design: .rounded).weight(.heavy)).foregroundStyle(theme.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("evolutionDetailsTitle")
                Text(sample.current.map { "Current evaluation: G\($0) · \(ProgressGen.name($0))" } ?? "Current evaluation: none")
                    .font(.body).foregroundStyle(theme.textPrimary)
                Text(sample.highest.map { "Highest achieved: G\($0) · \(ProgressGen.name($0))" } ?? "Highest achieved: none yet")
                    .font(.body).foregroundStyle(theme.textPrimary)
                Text("Cyclift does not assign a stage yet. The evidence each stage needs has not been defined and approved, so no stage is worked out or shown, and there is no next stage or timeline of stages. Your measured progress is on the Progress page: riding time, logged strength sets, consistency and time in zones.")
                    .font(.footnote).foregroundStyle(theme.textSecondary).fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("evolutionNotEvaluated")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .padding(.bottom, bottomInset)
        }
        .background(theme.background.ignoresSafeArea())
        .navigationTitle("Athlete Evolution")
        .navigationBarTitleDisplayMode(.inline)
    }
}
