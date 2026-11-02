import SwiftUI
import Charts
import MapKit

/// Progress tab: "Am I improving?" (RC3, owner decisions 1 Nov)
/// 1. Consistency first: this week and done vs planned per week (the only place with the full weekly figures).
/// 2. Cycling: FTP with its source (Unknown / Entered / Estimated / Tested); performance only from valid data.
/// 3. Strength: the top working set per main lift (logged); "Est. 1RM" is secondary and only where reliable.
/// 4. Checkpoints at 4 / 8 / 12 weeks from the first completed session, with what evidence is still missing.
/// 5. Sessions: the history (moved here from Plan), each ride with its analysis.
/// Every figure comes from the one query layer (TrainingLedger / Store progress inputs), the same data as Plan and Home.
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
                        if showRiding { ftpCard.id("ftp") }
                        if showLifting { StrengthProgressCard() }
                        CheckpointsCard(showRiding: showRiding, showLifting: showLifting)
                        sessions
                    }.padding()
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Progress")
            .onAppear { if !positioned { positioned = true; if !showRiding && showLifting { metric = .strength } } }
        }
    }

    // MARK: consistency — this week at a glance
    private func glance(riding: [WeekBucket], lifting: [WeekBucket], proxy: ScrollViewProxy) -> some View {
        let p = store.profile
        let monday = TrainingLedger.monday(of: Date())
        let sets = store.ledger.logs.filter { $0.date >= monday }.reduce(0) { $0 + $1.setCount }
        let trend = ProgressGlance.best20Trend(store.rides)
        let g = ProgressGlance.make(.init(riding: riding, lifting: lifting, showRiding: showRiding, showLifting: showLifting, setsThisWeek: sets,
                                          ridingTargetMinutes: p.hoursPerWeek * 60, ftpW: p.ftpValue ?? 0, ftpBadge: p.ftpBadge,
                                          best20Recent: trend.recent, best20Before: trend.before))
        return VStack(alignment: .leading, spacing: DS.s) {
            Eyebrow(t: "This week")
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

    // MARK: cycling — FTP with its source; no number when unknown
    private var ftpCard: some View {
        let p = store.profile
        return Card {
            HStack(alignment: .firstTextBaseline) { Eyebrow(t: "Cycling · FTP"); Spacer(minLength: DS.s); Pill(text: p.ftpSource.title, color: p.ftpSource == .tested ? BC.live : p.ftpSource == .unknown ? .secondary : BC.accent) }
            if let w = p.ftpValue {
                ViewThatFits(in: .horizontal) {
                    // S2-0: W/kg only with a real weight
                    HStack(alignment: .firstTextBaseline, spacing: DS.s) { Text("\(w)").font(DS.number).monospacedDigit(); Text("W" + (p.wattsPerKg.map { " · \(String(format: "%.1f", $0)) W/kg" } ?? " · W/kg needs your weight")).foregroundStyle(.secondary) }
                    VStack(alignment: .leading) { Text("\(w) W").font(DS.number).monospacedDigit(); Text(p.wattsPerKg.map { "\(String(format: "%.1f", $0)) W/kg" } ?? "W/kg needs your weight").foregroundStyle(.secondary) }
                }
                Text(p.ftpSourceText).font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("ftpSource")
            } else {
                Text("Unknown").font(DS.number).accessibilityIdentifier("ftpConfidenceTitle")
                Text("Not enough data yet: do an FTP test with a power meter, or enter your FTP in Profile. Rides use heart rate and effort until then.").font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("ftpSource")
            }
            if store.ftpSuggestion != nil { FTPSuggestionCard() }
        }
    }

    // MARK: sessions — history (moved here from Plan)
    private var sessions: some View {
        VStack(alignment: .leading, spacing: DS.s) {
            TimelineSection()
            Text("Board history: \(device.syncStatus). Rides recorded on the BikeComputer while the phone was away stay on the board until its firmware serves them; nothing is invented here.").font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .id("sessions")
    }
}

/// Strength: the top working set per main lift from logged sets (primary). "Est. 1RM" is an optional second line, shown
/// only for sets that qualify (RPE ≥ 8, effective reps 1–10; ENG-D6) and always labelled as an estimate.
struct StrengthProgressCard: View {
    @EnvironmentObject private var store: Store
    @State private var showEstimate = false
    var body: some View {
        let lifts = store.liftSummaries().filter { $0.latest != nil }.sorted { $0.topSets.count > $1.topSets.count }.prefix(6)
        let units = store.settings.units
        Card {
            HStack { Eyebrow(t: "Strength · top set"); Spacer()
                if lifts.contains(where: { $0.latest?.e1RM != nil }) {
                    Toggle("Est. 1RM", isOn: $showEstimate).toggleStyle(.button).font(.caption.bold()).controlSize(.small).accessibilityIdentifier("progressE1RM")
                }
            }
            if lifts.isEmpty {
                Text("Not enough data yet: log the weight and reps of your lifts to see progress here.").font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            ForEach(Array(lifts)) { l in
                if let last = l.latest {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(l.name).font(.subheadline.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: DS.s)
                            Text("\(WeightFmt.text(last.weightKg, units)) × \(last.reps)").font(.subheadline).monospacedDigit()
                        }
                        HStack(spacing: DS.s) {
                            Text(change(l, units: units)).font(.caption).foregroundStyle(.secondary)
                            if showEstimate, let e = last.e1RM {
                                Text("Est. 1RM \(WeightFmt.text(e, units))").font(.caption.weight(.semibold)).foregroundStyle(BC.accent)
                            }
                        }
                    }
                    .padding(.vertical, 2)
                    .accessibilityElement(children: .combine)
                }
            }
            if showEstimate {
                Text("Est. = estimated from a hard logged set, not a measured max.").font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityIdentifier("progressStrength")
    }
    /// "Logged · 4 sessions · +5 kg since 12 Oct" (first vs latest top set).
    private func change(_ l: LiftSummary, units: AppSettings.Units) -> String {
        let n = l.topSets.count
        guard let first = l.topSets.first, let last = l.latest, n >= 2 else { return "Logged · 1 session" }
        let d = last.weightKg - first.weightKg
        let sign = d > 0 ? "+" : d < 0 ? "−" : "±"
        return "Logged · \(n) sessions · \(sign)\(WeightFmt.text(abs(d), units)) since \(first.date.formatted(.dateTime.day().month(.abbreviated)))"
    }
}

/// Checkpoints at 4 / 8 / 12 weeks, counted from the first completed session of each sport. A checkpoint needs both the
/// weeks and the sessions; otherwise it says what is still missing. Reviews, not promises.
struct CheckpointsCard: View {
    @EnvironmentObject private var store: Store
    let showRiding: Bool
    let showLifting: Bool
    var body: some View {
        Card {
            Eyebrow(t: "Checkpoints")
            if showRiding { sport("Cycling", store.checkpoints(.cycling)) }
            if showLifting { sport("Strength", store.checkpoints(.strength)) }
            Text("Reviews at 4, 8 and 12 weeks — not promises.").font(.caption2).foregroundStyle(.secondary)
        }
        .accessibilityIdentifier("progressCheckpoints")
    }
    @ViewBuilder private func sport(_ title: String, _ cps: [Checkpoint]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.subheadline.weight(.semibold))
            if cps.isEmpty {
                Text("Starts with your first completed session.").font(.caption).foregroundStyle(.secondary)
            }
            ForEach(cps, id: \.weeks) { c in
                HStack(alignment: .firstTextBaseline, spacing: DS.s) {
                    Image(systemName: c.reached ? "checkmark.circle.fill" : "circle").foregroundStyle(c.reached ? BC.live : .secondary).accessibilityHidden(true)
                    Text("Week \(c.weeks)").font(.footnote.weight(.semibold)).monospacedDigit()
                    Text(line(c)).font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }
    private func line(_ c: Checkpoint) -> String {
        if !c.reached { return "Not enough evidence yet" + (c.missing.map { ": \($0)" } ?? "") }
        switch c.performance {
        case .improved: return "\(c.sessions) sessions · improving"
        case .flat: return "\(c.sessions) sessions · holding steady"
        case .declined: return "\(c.sessions) sessions · lower than before"
        case .notEnoughData: return "\(c.sessions) sessions · consistent; performance needs more data"
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
                HStack(alignment: .firstTextBaseline) { Text("\(s.watts)").font(BC.numFont); Text(store.profile.ftpKnown ? "W · was \(s.previousFTP) W" : "W · FTP unknown until now").foregroundStyle(.secondary) }
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
            if total == 0 || !store.profile.ftpKnown { Text(store.profile.ftpKnown ? "no data yet · needs power" : "power zones need a known FTP").font(.footnote).foregroundStyle(BC.stale) }
            else {
                HStack(spacing: 2) { ForEach(0..<7, id: \.self) { z in if secs[z] > 0 { RoundedRectangle(cornerRadius: 3).fill(BC.zone(z + 1)).frame(width: max(4, CGFloat(secs[z]) / CGFloat(total) * 300), height: 14) } } }
                Text(zoneText(secs)).font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    private func zoneText(_ secs: [Int]) -> String {
        var parts: [String] = []
        for z in 0..<7 where secs[z] > 0 { parts.append("Z\(z + 1) \(secs[z] / 60) min") }
        return parts.joined(separator: " · ") + (store.profile.ftpKnown ? " · FTP \(store.profile.ftpW) W (\(store.profile.ftpLabel))" : "")
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
