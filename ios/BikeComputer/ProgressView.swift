import SwiftUI
import Charts
import MapKit

/// Progress tab (RC2-UX milestone 1, owner §5), three levels:
/// 1. At a glance: this week's riding, strength, sessions, the riding target and FTP — each card opens its detail.
/// 2. Trends: one detailed chart (riding / strength; 4–16 weeks, 1 year with older data), tappable weeks, done vs planned.
/// 3. FTP with its honest badge, and the ride history with each ride's analysis.
/// Every figure comes from the one query layer (TrainingLedger via ProgressMetrics), the same numbers as Plan and Home.
/// Only rides this phone recorded, mirrored or imported are listed; the BikeComputer's own history stays on the board until
/// its firmware serves it (shown as a note, never fabricated).
struct ProgressTabView: View {
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var device: DeviceLink
    @State private var metric: TrendMetric = .riding
    @State private var range: ChartRange = .w8
    @State private var positioned = false
    @Environment(\.dynamicTypeSize) private var dts
    /// Two years of weeks (cheap: one ledger pass per week).
    private let historyWeeks = 104

    private var showRiding: Bool { store.profile.trainingMode.includesCycling || !store.rides.isEmpty }
    private var showLifting: Bool {
        let l = store.ledger
        return store.profile.trainingMode.includesLifting || !l.logs.isEmpty || l.plan.contains { $0.kind == .strength && $0.completion == .marked }
    }
    private var metrics: [TrendMetric] { (showRiding ? [TrendMetric.riding] : []) + (showLifting ? [.strength] : []) }

    var body: some View {
        let ledger = store.ledger
        let riding = TrendChartMath.buckets(ledger, riding: true, weeks: historyWeeks, now: Date())
        let lifting = TrendChartMath.buckets(ledger, riding: false, weeks: historyWeeks, now: Date())
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: DS.m) {
                        if !metrics.isEmpty { glance(riding: riding, lifting: lifting, proxy: proxy) }
                        if !metrics.isEmpty {
                            Card { WeeklyTrendChart(riding: riding, lifting: lifting, metrics: metrics, metric: $metric, range: $range) }
                                .id("trends")
                        }
                        ftpCard.id("ftp")
                        history
                    }.padding()
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Progress")
            .onAppear { if !positioned { positioned = true; if !showRiding && showLifting { metric = .strength } } }
        }
    }

    // MARK: level 1 — at a glance
    private func glance(riding: [WeekBucket], lifting: [WeekBucket], proxy: ScrollViewProxy) -> some View {
        let p = store.profile
        let monday = TrainingLedger.monday(of: Date())
        let sets = store.ledger.logs.filter { $0.date >= monday }.reduce(0) { $0 + $1.setCount }
        let trend = ProgressGlance.best20Trend(store.rides)
        let g = ProgressGlance.make(.init(riding: riding, lifting: lifting, showRiding: showRiding, showLifting: showLifting, setsThisWeek: sets,
                                          ridingTargetMinutes: p.hoursPerWeek * 60, ftpW: p.ftpW, ftpBadge: p.ftpBadge,
                                          best20Recent: trend.recent, best20Before: trend.before))
        return VStack(alignment: .leading, spacing: DS.s) {
            Eyebrow(t: "At a glance")
            // two equal-height cards per row (one per row at accessibility sizes); an odd last card spans the row
            let cols = dts.isAccessibilitySize ? 1 : 2
            Grid(horizontalSpacing: DS.s, verticalSpacing: DS.s) {
                ForEach(Array(Swift.stride(from: 0, to: g.cards.count, by: cols)), id: \.self) { start in
                    let row = Array(g.cards[start..<min(start + cols, g.cards.count)])
                    GridRow {
                        ForEach(row) { c in glanceButton(c, proxy: proxy).gridCellColumns(row.count < cols ? cols : 1) }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    private func glanceButton(_ c: ProgressGlance.Card, proxy: ScrollViewProxy) -> some View {
        Button {
            if let m = c.opens { metric = m }
            withAnimation { proxy.scrollTo(c.opens == nil ? "ftp" : "trends", anchor: .top) }
        } label: { glanceCard(c) }
        .buttonStyle(.plain)
        .accessibilityIdentifier(c.id)
        .accessibilityHint(c.opens.map { "Shows the \($0.rawValue.lowercased()) chart" } ?? "Shows the FTP details")
    }
    private func glanceCard(_ c: ProgressGlance.Card) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(c.title).font(.caption.weight(.semibold)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Text(c.value).font(.title2.weight(.bold)).monospacedDigit().fixedSize(horizontal: false, vertical: true)
            Text(c.detail).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(DS.m)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: DS.corner))
        .contentShape(RoundedRectangle(cornerRadius: DS.corner))
        .accessibilityElement(children: .combine)
    }

    // MARK: level 2/3 — FTP with its badge (tested / entered / estimated)
    private var ftpCard: some View {
        let p = store.profile
        return Card {
            HStack(alignment: .firstTextBaseline) { Eyebrow(t: "FTP"); Spacer(minLength: DS.s); FTPConfidencePill(profile: p) }
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: DS.s) { Text("\(p.ftpW)").font(DS.number).monospacedDigit(); Text("W · \(String(format: "%.1f", Double(p.ftpW) / max(1, p.weightKg))) W/kg").foregroundStyle(.secondary) }
                VStack(alignment: .leading) { Text("\(p.ftpW) W").font(DS.number).monospacedDigit(); Text("\(String(format: "%.1f", Double(p.ftpW) / max(1, p.weightKg))) W/kg").foregroundStyle(.secondary) }
            }
            Text(p.ftpLabel).font(.subheadline.weight(.semibold)).accessibilityIdentifier("ftpConfidenceTitle")
            Text(p.ftpSourceText).font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("ftpSource")
            if let c = p.ftpCaution { Text(c).font(.footnote).foregroundStyle(BC.stale).fixedSize(horizontal: false, vertical: true) }
            if store.ftpSuggestion != nil { FTPSuggestionCard() }
            Text("Training load and form appear after about six weeks of rides with power; nothing is shown before that.").font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func rowText(_ r: RideRecord) -> String {
        var t = "\(r.durationS.asDuration) · \(String(format: "%.1f", Double(r.distanceM) / 1000)) km"
        if let p = r.avgPower { t += " · \(p) W" }
        if let h = r.avgHR { t += " · \(h) bpm" }
        return t
    }
    private var history: some View {
        Card {
            HStack { Eyebrow(t: "Rides"); Spacer(); Text("\(store.rides.count)").font(.caption.bold()).foregroundStyle(.secondary) }
            if store.rides.isEmpty { Text("No rides yet. Recorded and imported rides appear here, newest first.").font(.footnote).foregroundStyle(BC.stale).fixedSize(horizontal: false, vertical: true) }
            ForEach(store.rides.sorted { $0.start > $1.start }) { r in
                NavigationLink { RideDetailView(ride: r) } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            FlowRow(spacing: 6) { Text(r.start.dayAndDate).font(.subheadline.weight(.bold)); Pill(text: r.recorder == .board ? "BikeComputer" : r.recorder == .health ? "Apple Health" : "phone only", color: r.recorder == .board ? BC.accent : .secondary) }
                            Text(rowText(r)).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(); Image(systemName: "chevron.right").foregroundStyle(.secondary)
                    }.padding(.vertical, 4).frame(minHeight: DS.minTap).contentShape(Rectangle())
                }.buttonStyle(.plain)
                if r.id != store.rides.min(by: { $0.start < $1.start })?.id { Divider() }
            }
            Divider()
            Text("Board history: \(device.syncStatus). Rides recorded on the BikeComputer while the phone was away stay on the board until its firmware serves them; nothing is invented here.").font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// FTP proposal from a real ride. Nothing changes until the rider taps Accept.
struct FTPSuggestionCard: View {
    @EnvironmentObject private var store: Store
    var body: some View {
        if let s = store.ftpSuggestion {
            VStack(alignment: .leading, spacing: 6) {
                Divider()
                HStack { Eyebrow(t: "Suggested FTP"); Spacer(); Pill(text: "from \(s.rideDate.dayAndDate) ride", color: BC.accent) }
                HStack(alignment: .firstTextBaseline) { Text("\(s.watts)").font(BC.numFont); Text("W · was \(s.previousFTP) W").foregroundStyle(.secondary) }
                Text("95 % of the best 20-minute power (\(s.best20) W)" + (s.best60.map { " · best 60 min \($0) W" } ?? "") + (store.profile.ftpHow == .entered ? ". Your entered FTP is kept unless you accept." : ".")).font(.footnote).foregroundStyle(.secondary)
                HStack { Button("Accept \(s.watts) W") { store.acceptFTPSuggestion() }.buttonStyle(.borderedProminent).tint(BC.live); Button("Not now") { store.dismissFTPSuggestion() }.buttonStyle(.bordered) }
            }
        }
    }
}

/// One ride: summary tiles, interactive graph (power / HR / cadence / speed from the 1 Hz samples), zones, map, coach note.
struct RideDetailView: View {
    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss
    let ride: RideRecord
    @State private var series: Set<String> = ["power", "hr"]
    @State private var selectedT: Int?
    @State private var confirmDelete = false

    private var hasW: Bool { ride.samples.contains { $0.w != nil } }
    private var hasHR: Bool { ride.samples.contains { $0.hr != nil } }
    private var hasCad: Bool { ride.samples.contains { $0.cad != nil } }
    private var hasSpd: Bool { ride.samples.contains { $0.speedCms != nil } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                FlowRow(spacing: DS.s) { Text(ride.start.dayAndDate).font(DS.screenTitle); Pill(text: "recorded by \(ride.recordedBy)", color: BC.accent) }
                RideSummaryTiles(ride: ride, units: store.settings.units)
                graph
                zones
                map
                Card { Eyebrow(t: "Coach (rules)"); Text(Coach.rideSummary(ride, profile: store.profile)) }
                if let b = ride.best20 { Text("Best 20 min \(b) W" + (ride.best60.map { " · best 60 min \($0) W" } ?? "")).font(.footnote).foregroundStyle(.secondary) }
                Text("Sources: \(ride.sources.joined(separator: " · ")) · \(ride.samples.count) samples at 1 Hz").font(.footnote).foregroundStyle(.secondary)
                if let g = ride.gapSeconds, g > 0 { Text("\(g) s not observed by the phone (app suspended in the background); those seconds count as time but hold no values.").font(.footnote).foregroundStyle(BC.stale) }
                Button("Delete this ride", role: .destructive) { confirmDelete = true }.frame(maxWidth: .infinity)
            }.padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Ride").navigationBarTitleDisplayMode(.inline)
        .alert("Delete this ride from the phone?", isPresented: $confirmDelete) { Button("Delete", role: .destructive) { store.deleteRide(ride); dismiss() }; Button("Keep", role: .cancel) {} } message: { Text(ride.recorder == .board ? "The copy on the BikeComputer is not affected." : "This cannot be undone.") }
    }

    // MARK: graph
    private struct Pt: Identifiable { let id: String; let t: Int; let v: Double; let nv: Double; let s: String }
    private func points(_ key: String) -> [Pt] {
        // 1 Hz → at most ~600 points on screen: average into buckets so the chart stays smooth and fast
        let n = ride.samples.count; let bucket = max(1, n / 600)
        var out: [Pt] = []
        var i = 0
        while i < n {
            let slice = ride.samples[i..<min(n, i + bucket)]
            let vals: [Double] = slice.compactMap { s in
                switch key { case "power": return s.w.map(Double.init); case "hr": return s.hr.map(Double.init); case "cadence": return s.cad.map(Double.init); case "speed": return s.speedCms.map { Double($0) * 0.036 }; default: return nil }
            }
            if !vals.isEmpty { out.append(Pt(id: "\(key)-\(i)", t: slice.first!.t, v: vals.reduce(0, +) / Double(vals.count), nv: 0, s: key)) }
            i += bucket
        }
        // each series on its own 0–1 scale so they share one chart; the legend shows real values
        let lo = out.map { $0.v }.min() ?? 0, hi = out.map { $0.v }.max() ?? 1
        return out.map { Pt(id: $0.id, t: $0.t, v: $0.v, nv: hi > lo ? ($0.v - lo) / (hi - lo) : 0.5, s: $0.s) }
    }
    private func color(_ k: String) -> Color { switch k { case "power": return BC.accent; case "hr": return BC.warn; case "cadence": return BC.zone(3); default: return BC.live } }
    private func label(_ k: String) -> String { switch k { case "power": return "W"; case "hr": return "bpm"; case "cadence": return "rpm"; default: return "km/h" } }

    private var graph: some View {
        Card {
            HStack { Eyebrow(t: "Graph"); Spacer()
                ForEach([("power", hasW), ("hr", hasHR), ("cadence", hasCad), ("speed", hasSpd)], id: \.0) { k, ok in
                    Button(k.capitalized) { if series.contains(k) { series.remove(k) } else { series.insert(k) } }.font(.caption2.bold()).buttonStyle(.bordered).controlSize(.large).tint(series.contains(k) ? color(k) : .secondary).disabled(!ok)
                }
            }
            let shown = series.filter { k in (k == "power" && hasW) || (k == "hr" && hasHR) || (k == "cadence" && hasCad) || (k == "speed" && hasSpd) }
            if shown.isEmpty || ride.samples.isEmpty {
                Text("no data yet").font(.footnote).foregroundStyle(BC.stale)
                Text(ride.recorder == .phone ? "Phone-only rides have GPS speed and watch heart rate when a watch was worn; power needs the BikeComputer." : "The phone mirror has no samples for this ride (link lost or app in background).").font(.footnote).foregroundStyle(.secondary)
            } else {
                let perSeries = shown.sorted().map { points($0) }
                let data = perSeries.flatMap { $0 }
                Chart(data) { p in
                    LineMark(x: .value("Time", p.t), y: .value("Value", p.nv), series: .value("S", p.s)).foregroundStyle(color(p.s)).interpolationMethod(.monotone).lineStyle(StrokeStyle(lineWidth: 1.5))
                    if let st = selectedT, abs(p.t - st) < max(1, ride.samples.count / 600) { PointMark(x: .value("Time", p.t), y: .value("Value", p.nv)).foregroundStyle(color(p.s)) }
                }
                .chartYAxis(.hidden)
                .chartXAxis { AxisMarks(values: .automatic(desiredCount: 5)) { v in AxisGridLine(); AxisValueLabel { if let t = v.as(Int.self) { Text(t.asDuration) } } } }
                .chartXSelection(value: $selectedT)
                .frame(height: 200)
                HStack(spacing: 10) {
                    ForEach(Array(shown.sorted().enumerated()), id: \.element) { idx, k in
                        let v = selectedT.flatMap { t in perSeries[idx].min { abs($0.t - t) < abs($1.t - t) } }
                        HStack(spacing: 4) { Circle().fill(color(k)).frame(width: 7, height: 7); Text(v.map { String(format: "%.0f", $0.v) } ?? "—").font(.caption.bold()).monospacedDigit(); Text(label(k)).font(.caption2).foregroundStyle(.secondary) }
                    }
                    Spacer(); Text(selectedT.map { $0.asDuration } ?? "touch the graph").font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
    }
    private var zones: some View {
        Card {
            Eyebrow(t: "Time in zones")
            let secs = zoneSeconds
            let total = secs.reduce(0, +)
            if total == 0 { Text("no data yet · needs power").font(.footnote).foregroundStyle(BC.stale) }
            else {
                HStack(spacing: 2) { ForEach(0..<7, id: \.self) { z in if secs[z] > 0 { RoundedRectangle(cornerRadius: 3).fill(BC.zone(z + 1)).frame(width: max(4, CGFloat(secs[z]) / CGFloat(total) * 300), height: 14) } } }
                Text(zoneText(secs)).font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    private func zoneText(_ secs: [Int]) -> String {
        var parts: [String] = []
        for z in 0..<7 where secs[z] > 0 { parts.append("Z\(z + 1) \(secs[z] / 60) min") }
        return parts.joined(separator: " · ") + " · FTP \(store.profile.ftpW) W (\(store.profile.ftpLabel))"
    }
    private var zoneSeconds: [Int] { var secs = Array(repeating: 0, count: 7); for w in ride.samples.compactMap({ $0.w }) { secs[store.profile.zone(forWatts: w) - 1] += 1 }; return secs }

    private var map: some View {
        let coords = ride.samples.compactMap { s -> CLLocationCoordinate2D? in if let la = s.lat, let lo = s.lon { return CLLocationCoordinate2D(latitude: la, longitude: lo) }; return nil }
        return Card {
            Eyebrow(t: "Route")
            if coords.count >= 2 {
                Map { MapPolyline(coordinates: coords).stroke(BC.accent, lineWidth: 4) }.frame(height: 220).clipShape(RoundedRectangle(cornerRadius: 12)).allowsHitTesting(false)
                Text("\(coords.count) GPS points from the phone").font(.caption2).foregroundStyle(.secondary)
            } else { Text("no data yet · no GPS track for this ride").font(.footnote).foregroundStyle(BC.stale) }
        }
    }
}
