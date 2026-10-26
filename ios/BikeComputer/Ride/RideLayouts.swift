import SwiftUI

/// The content area of the live ride screen for the selected layout. The header, the CoachPanel and the controls are
/// shared (RideTabView); this view draws only the metrics part and is always given a real, non-zero size (the
/// 0.5.1 rule: nothing is laid out from a 0 × 0 first pass, every fitting computation is bounded).
/// Sizes are computed from `size` so every layout fits one screen without scrolling, iPhone SE (375 × 667) to Pro Max.
struct RideLayoutContent: View {
    let layout: RideLayout
    let live: RideLive
    let size: CGSize
    @ObservedObject var coach: RideCoach
    @ObservedObject var recorder: RideRecorder
    let tiles: [String]
    let profile: RiderProfile
    let boardBattery: Int?

    static let gap = 8.0
    static let statsH = 36.0

    var body: some View {
        content
            .frame(width: size.width, height: size.height, alignment: .top)
            .clipped()
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier(layout.accessibilityId)
    }

    @ViewBuilder private var content: some View {
        switch layout {
        case .coach: coachLayout
        case .gauges: gaugesLayout
        case .classic: classicLayout
        case .rings: ringsLayout
        case .analytics: analyticsLayout
        }
    }

    // MARK: Ride Coach — the Power-Focus port (Nokia Design 7 / DashLayout POWER_FOCUS, iOS 0.5.x)
    private var coachLayout: some View {
        let w = Double(size.width), h = Double(size.height)
        let graphH = RideFit.clamp(h * 0.2, 52, 120)
        let chip = RideGauges.chipHeight(big: true)
        let geo = PowerFocus.compute(contentW: w, maxBlockH: max(120, h - Self.statsH - graphH - 2 * Self.gap), labelH: 0, chipH: chip, chipW: 112)
        return VStack(spacing: Self.gap) {
            ZStack(alignment: .topLeading) {
                RideGauges.power(live, big: true).frame(width: geo.colPower).offset(x: geo.xPower, y: geo.yPower)
                RideGauges.cadence(live, big: false).frame(width: geo.colSmall).offset(x: geo.xLeft, y: geo.yLower)
                RideGauges.heartRate(live, big: false).frame(width: geo.colSmall).offset(x: geo.xRight, y: geo.yLower)
            }
            .frame(width: w, height: min(geo.blockHeight, max(0, h - Self.statsH - graphH - 2 * Self.gap)), alignment: .topLeading)
            LiveGraphView(samples: coach.samples, seconds: RideCoach.keepSeconds).frame(height: graphH)
            RideStatsRow(live: live, recorder: recorder)
        }
    }

    // MARK: Large gauges — power, heart rate and cadence as big as the screen allows (Nokia Design 7 gauges row)
    private var gaugesLayout: some View {
        let f = RideFit.largeGauges(width: Double(size.width), height: Double(size.height) - 22 - Self.gap, chip: RideGauges.chipHeight(big: true))
        return VStack(spacing: Self.gap) {
            RideGauges.power(live, big: true).frame(width: f.power)
            HStack(spacing: 12) {
                RideGauges.heartRate(live, big: f.small >= 140).frame(width: f.small)
                RideGauges.cadence(live, big: f.small >= 140).frame(width: f.small)
            }
            Spacer(minLength: 0)
            RideStatsLine(live: live, recorder: recorder).frame(height: 22)
        }
    }

    // MARK: Classic — the metric tile grid of iOS builds 17–24 (and the Nokia COMPACT number cards)
    private var classicLayout: some View {
        let keys = Array((tiles.isEmpty ? Store.defaultTiles : tiles).prefix(6))
        let rows = max(1, (keys.count + 1) / 2)
        let rowH = max(60, (Double(size.height) - Double(rows - 1) * 6) / Double(rows))
        return LazyVGrid(columns: [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)], spacing: 6) {
            ForEach(Array(keys.enumerated()), id: \.offset) { i, key in
                RideTiles.tile(key, live: live, recorder: recorder, profile: profile, boardBattery: boardBattery, big: i == 0 && rowH >= 120)
                    .frame(height: rowH).clipped()
            }
        }
        .environment(\.colorScheme, .dark)
    }

    // MARK: Rings — three equal compact rings in one row (Nokia v0.10–0.12 hybrid dashboard, "Classic Three Gauges")
    private var ringsLayout: some View {
        let w = Double(size.width), h = Double(size.height)
        let f = RideFit.rings(width: w, height: h, chip: RideGauges.chipHeight(big: false), statsH: Self.statsH, gap: Self.gap)
        return VStack(spacing: Self.gap) {
            HStack(spacing: 6) {
                RideGauges.power(live, big: false, showTgtLabel: false).frame(width: f.ring)
                RideGauges.heartRate(live, big: false).frame(width: f.ring)
                RideGauges.cadence(live, big: false).frame(width: f.ring)
            }
            if f.powerBand { ZoneBandView(labels: ["Z1", "Z2", "Z3", "Z4", "Z5", "Z6", "Z7"], colors: D7.powerZoneColors, currentFraction: live.power.value.map { Targets.gaugeFraction($0, max: Targets.powerGaugeMaxW(ftp: live.ftp)) }, targetFraction: Targets.powerTargetFraction(targetZone: live.targetZone, ftp: live.ftp)) }
            if f.hrBand { ZoneBandView(labels: ["Z1", "Z2", "Z3", "Z4", "Z5"], colors: D7.hrZoneColors, currentFraction: live.hr.value.map { Targets.gaugeFraction($0, max: live.maxHr) }, targetFraction: Targets.hrTargetFraction(targetZone: live.targetHrZone)) }
            LiveGraphView(samples: coach.samples, seconds: RideCoach.keepSeconds).frame(height: f.graph)
            RideStatsRow(live: live, recorder: recorder)
        }
    }

    // MARK: Analytics — the combined live graph of watts, BPM and RPM as the main element (Nokia LiveGraph CombinedGraph)
    private var analyticsLayout: some View {
        let h = Double(size.height)
        let graphH = max(60, h - 50 - 26 - Self.statsH - 3 * Self.gap)
        return VStack(spacing: Self.gap) {
            HStack(spacing: 8) {
                AnalyticsNumber(metric: live.power, label: RideLabels.power, color: D7.cyan)
                AnalyticsNumber(metric: live.hr, label: RideLabels.heartRate, color: D7.red)
                AnalyticsNumber(metric: live.cadence, label: RideLabels.cadence, color: D7.violet)
            }.frame(height: 50)
            LiveGraphView(samples: coach.samples, seconds: RideCoach.keepSeconds).frame(height: graphH)
            ZoneBandView(labels: ["Z1", "Z2", "Z3", "Z4", "Z5", "Z6", "Z7"], colors: D7.powerZoneColors, currentFraction: live.power.value.map { Targets.gaugeFraction($0, max: Targets.powerGaugeMaxW(ftp: live.ftp)) }, targetFraction: Targets.powerTargetFraction(targetZone: live.targetZone, ftp: live.ftp))
            RideStatsRow(live: live, recorder: recorder)
        }
    }
}

/// Pure sizing rules for the layouts (unit-tested: everything fits from 320 × 200 up, no loops).
enum RideFit {
    static func clamp(_ v: Double, _ lo: Double, _ hi: Double) -> Double { v.isFinite ? min(hi, max(lo, v)) : lo }

    /// Large gauges: power ring on its own row, heart rate + cadence side by side below; both rows plus pills fit `height`.
    static func largeGauges(width w: Double, height h: Double, chip: Double) -> (power: Double, small: Double) {
        let avail = max(0, h - 2 * chip - 8)
        let small = clamp(min((w - 12) / 2, avail * 0.45), 50, 400)
        let power = clamp(min(w * 0.72, avail - small), 60, 500)
        return (power, small)
    }

    /// Rings: three equal rings; zone bars are dropped (HR first, then power) when the graph would get too small.
    static func rings(width w: Double, height h: Double, chip: Double, statsH: Double, gap: Double) -> (ring: Double, graph: Double, powerBand: Bool, hrBand: Bool) {
        let ring = clamp((w - 12) / 3, 40, 200)
        let fixed = ring + chip + statsH + 3 * gap
        var graph = h - fixed
        var hrBand = true, powerBand = true
        if graph - 2 * (26 + gap) >= 60 { graph -= 2 * (26 + gap) }
        else if graph - (26 + gap) >= 56 { graph -= 26 + gap; hrBand = false }
        else { hrBand = false; powerBand = false }
        return (ring, max(40, graph), powerBand, hrBand)
    }
}

/// Distance, speed, normalized power and lap — the stats row shared by the gauge layouts.
struct RideStatsRow: View {
    let live: RideLive
    @ObservedObject var recorder: RideRecorder
    var body: some View {
        HStack(spacing: 6) {
            DashStat(value: RideStatsText.distance(live, recorder), label: recorder.owner == .board ? "DISTANCE · BOARD" : "DISTANCE")
            DashStat(value: live.speedText, label: live.speed.usable ? "SPEED" : MetricKind.speed.missingText.uppercased(), color: live.speed.warning ? D7.amber : D7.fg)
            DashStat(value: RideRecorder.normalized(recorder.samples.compactMap { $0.w }).map { "\($0) W" } ?? "—", label: "NORMALIZED")
            DashStat(value: recorder.isActive ? "L\(recorder.lapCount) \((recorder.elapsedS - recorder.lapStartS).asDuration)" : "—", label: "LAP")
        }.frame(height: RideLayoutContent.statsH)
    }
}

/// One-line stats for the Large gauges layout.
struct RideStatsLine: View {
    let live: RideLive
    @ObservedObject var recorder: RideRecorder
    var body: some View {
        HStack(spacing: 10) {
            Text("SPEED \(live.speed.usable ? live.speedText : MetricKind.speed.missingText)")
            Text("DIST \(RideStatsText.distance(live, recorder))")
            Spacer(minLength: 0)
            Text(recorder.isActive ? "LAP \(recorder.lapCount) \((recorder.elapsedS - recorder.lapStartS).asDuration)" : "")
        }
        .font(.system(size: 11, weight: .semibold, design: .monospaced)).foregroundStyle(D7.mut).lineLimit(1).minimumScaleFactor(0.6)
    }
}

enum RideStatsText {
    static func distance(_ l: RideLive, _ r: RideRecorder) -> String {
        guard r.isActive || r.state == .ended else { return "—" }
        let km = Double(r.distanceM) / 1000
        return String(format: l.imperial ? "%.2f mi" : "%.2f km", l.imperial ? km / 1.60934 : km)
    }
}

/// A big number with its metric label and, separately, its source (Analytics layout).
struct AnalyticsNumber: View {
    let metric: RideMetric; let label: String; let color: Color
    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 4) { Circle().fill(color).frame(width: 6, height: 6); Text(label).font(.system(size: 8, design: .monospaced)).tracking(1).foregroundStyle(D7.mut).lineLimit(1) }
            Text(metric.value.map(String.init) ?? "—").font(.system(size: 24, weight: .semibold, design: .rounded)).monospacedDigit().foregroundStyle(metric.value == nil ? D7.faint : D7.fg).lineLimit(1).minimumScaleFactor(0.6)
            Text(metric.sourceOrMissing).font(.system(size: 8, design: .monospaced)).foregroundStyle(metric.warning || !metric.usable ? D7.amber : D7.mut).lineLimit(1).minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
