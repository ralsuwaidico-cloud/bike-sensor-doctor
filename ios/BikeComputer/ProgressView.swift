import SwiftUI
import Charts
import MapKit

/// Progress tab: weekly totals, FTP with its label, ride history, ride detail with interactive graphs.
/// Only rides this phone recorded or mirrored are listed; the BikeComputer's own history stays on the board until the
/// sync characteristic is implemented in the app (shown as a note, never fabricated).
struct ProgressTabView: View {
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var device: DeviceLink
    @State private var rideRange: ChartRange = .w8
    @State private var liftRange: ChartRange = .w8
    /// Two years of weeks to scroll through (cheap: one ledger pass per week).
    private let historyWeeks = 104

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: DS.m) {
                    if store.profile.trainingMode.includesCycling || !store.rides.isEmpty { weekly }
                    if store.profile.trainingMode.includesLifting || !store.strength.isEmpty { lifting }
                    ftpCard
                    history
                }.padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Progress")
        }
    }

    private var weekly: some View {
        Card {
            if store.rides.isEmpty && store.ledger.riding(weekOf: TrainingLedger.monday(of: Date())).completed == 0 {
                Eyebrow(t: "Weekly riding time")
                Text("No rides yet").font(.headline).foregroundStyle(BC.stale)
                Text("Your saved rides appear here, week by week. Nothing is estimated.").font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            } else {
                WeeklyTrendChart(title: "Weekly riding time", buckets: TrendChartMath.buckets(store.ledger, riding: true, weeks: historyWeeks, now: Date()), color: BC.accent,
                                 singular: "ride", plural: "rides", target: store.profile.hoursPerWeek * 60, targetLabel: "Target", identifier: "ridingChart", range: $rideRange)
                definitions(riding: true)
            }
        }
    }

    private var lifting: some View {
        let l = store.ledger
        let any = !l.logs.isEmpty || l.plan.contains { $0.kind == .strength && $0.completion == .marked }
        return Card {
            if !any {
                Eyebrow(t: "Weekly lifting time")
                Text("No sessions logged yet").font(.headline).foregroundStyle(BC.stale)
                Text("Log a session from Home or Plan (Log), mark one done, or import from Apple Health in Connections.").font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            } else {
                WeeklyTrendChart(title: "Weekly lifting time", buckets: TrendChartMath.buckets(l, riding: false, weeks: historyWeeks, now: Date()), color: BC.zone(5),
                                 singular: "session", plural: "sessions", target: store.profile.liftingHoursPerWeek > 0 ? store.profile.liftingHoursPerWeek * 60 : nil, targetLabel: "Budget", identifier: "liftingChart", range: $liftRange)
                definitions(riding: false)
            }
        }
    }

    /// One definition for every screen (Home, Plan, History, Progress).
    private func definitions(riding: Bool) -> some View {
        let w = riding ? store.ledger.riding(weekOf: TrainingLedger.monday(of: Date())) : store.ledger.lifting(weekOf: TrainingLedger.monday(of: Date()))
        return HStack(alignment: .firstTextBaseline, spacing: DS.xs) {
            Text("This week: \(w.completed) done (\(w.logged) logged · \(w.manual) marked/quick · \(w.imported) imported) of \(w.planned) planned.")
                .font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier(riding ? "ridingWeekCounts" : "liftingWeekCounts")
            Spacer(minLength: 0)
            InfoButton(title: "How sessions are counted", text: riding
                ? "Done = rides recorded in Cyclift or imported from Apple Health, plus planned rides you marked done. Time adds only recorded rides and durations you typed. Planned rides that are not done are never counted. The dashed line is your weekly cycling target."
                : "Done = detailed logs (exercises and sets), quick logs and sessions marked done, and Apple Health imports. Time adds only measured or typed durations — a session without a duration counts as a session with no minutes. Planned sessions are never counted until done. The dashed line is your lifting budget.")
        }
    }

    private var ftpCard: some View {
        let p = store.profile
        return Card {
            HStack(alignment: .firstTextBaseline) { Eyebrow(t: "FTP"); Spacer(minLength: DS.s); FTPConfidencePill(profile: p) }
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: DS.s) { Text("\(p.ftpW)").font(DS.number).monospacedDigit(); Text("W · \(String(format: "%.1f", Double(p.ftpW) / max(1, p.weightKg))) W/kg").foregroundStyle(.secondary) }
                VStack(alignment: .leading) { Text("\(p.ftpW) W").font(DS.number).monospacedDigit(); Text("\(String(format: "%.1f", Double(p.ftpW) / max(1, p.weightKg))) W/kg").foregroundStyle(.secondary) }
            }
            Text(p.ftpConfidence.title).font(.subheadline.weight(.semibold)).accessibilityIdentifier("ftpConfidenceTitle")
            Text(p.ftpSourceText).font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("ftpSource")
            if let c = p.ftpCaution { Text(c).font(.footnote).foregroundStyle(BC.warn).fixedSize(horizontal: false, vertical: true) }
            if store.ftpSuggestion != nil { FTPSuggestionCard() }
            Divider()
            Eyebrow(t: "Fitness and form")
            Text("Not enough data yet").font(.subheadline.weight(.semibold)).foregroundStyle(BC.stale)
            Text("Training load and form need about six weeks of rides with power. Nothing is shown before that.").font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
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
            if store.rides.isEmpty { Text("no data yet").font(.footnote).foregroundStyle(BC.stale) }
            ForEach(store.rides) { r in
                NavigationLink { RideDetailView(ride: r) } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) { Text(r.start.dayAndDate).font(.subheadline.weight(.bold)); Pill(text: r.recorder == .board ? "BikeComputer" : "phone only", color: r.recorder == .board ? BC.accent : .secondary) }
                            Text(rowText(r)).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer(); Image(systemName: "chevron.right").foregroundStyle(.secondary)
                    }.padding(.vertical, 4)
                }.buttonStyle(.plain)
                if r.id != store.rides.last?.id { Divider() }
            }
            Divider()
            Text("Board history: \(device.syncStatus). Rides recorded on the BikeComputer while the phone was away stay on the board until its firmware serves them (see SYNC_PROPOSAL); nothing is invented here.").font(.caption2).foregroundStyle(.secondary)
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
                HStack { Text(ride.start.dayAndDate).font(.system(size: 26, weight: .bold, design: .rounded)); Spacer(); Pill(text: "recorded by \(ride.recordedBy)", color: BC.accent) }
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
                    Button(k.capitalized) { if series.contains(k) { series.remove(k) } else { series.insert(k) } }.font(.caption2.bold()).buttonStyle(.bordered).controlSize(.mini).tint(series.contains(k) ? color(k) : .secondary).disabled(!ok)
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
