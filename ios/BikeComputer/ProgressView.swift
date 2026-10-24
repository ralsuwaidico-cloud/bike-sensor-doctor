import SwiftUI
import Charts
import MapKit

/// Progress tab: weekly totals, FTP with its label, ride history, ride detail with interactive graphs.
/// Only rides this phone recorded or mirrored are listed; the BikeComputer's own history stays on the board until the
/// sync characteristic is implemented in the app (shown as a note, never fabricated).
struct ProgressTabView: View {
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var device: DeviceLink
    @State private var range = 8

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    weekly
                    ftpCard
                    history
                }.padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Progress")
        }
    }

    private var weekly: some View {
        let totals = store.weekTotals(weeks: range)
        return Card {
            HStack { Eyebrow(t: "Weekly riding time"); Spacer(); Picker("", selection: $range) { Text("8 wk").tag(8); Text("16 wk").tag(16) }.pickerStyle(.segmented).frame(width: 130) }
            if store.rides.isEmpty {
                Text("no data yet").font(.footnote).foregroundStyle(BC.stale)
                Text("Your first saved ride appears here. Weekly hours, distance and the FTP history build up from real rides only.").font(.footnote).foregroundStyle(.secondary)
            } else {
                Chart(totals) { w in
                    BarMark(x: .value("Week", w.monday, unit: .weekOfYear), y: .value("Minutes", w.minutes)).foregroundStyle(BC.accent)
                    RuleMark(y: .value("Target", store.profile.hoursPerWeek * 60)).foregroundStyle(BC.stale).lineStyle(StrokeStyle(lineWidth: 1, dash: [4]))
                }
                .chartYAxis { AxisMarks { v in AxisGridLine(); AxisValueLabel { if let m = v.as(Int.self) { Text(m >= 60 ? String(format: "%g h", Double(m) / 60) : "\(m)′") } } } }
                .chartXAxis { AxisMarks(values: .stride(by: .weekOfYear)) { _ in AxisValueLabel(format: .dateTime.day().month(.abbreviated), centered: true) } }
                .frame(height: 160)
                Text(weekText(totals.last)).font(.footnote).foregroundStyle(.secondary)
            }
        }
    }

    private func weekText(_ w: Store.WeekTotal?) -> String {
        guard let last = w else { return "" }
        let rides = last.rides == 1 ? "1 ride" : "\(last.rides) rides"
        return "This week: \(last.minutes / 60) h \(last.minutes % 60) min · \(String(format: "%.1f", last.km)) km · \(rides). Dashed line = your \(store.profile.hoursPerWeek) h limit."
    }
    private var ftpCard: some View {
        Card {
            HStack { Eyebrow(t: "FTP"); Spacer(); Pill(text: store.profile.ftpLabel, color: store.profile.ftpHow == .assumed ? BC.stale : BC.live) }
            HStack(alignment: .firstTextBaseline) { Text("\(store.profile.ftpW)").font(BC.bigNum); Text("W · \(String(format: "%.1f", Double(store.profile.ftpW) / store.profile.weightKg)) W/kg").foregroundStyle(.secondary) }
            Text(store.profile.ftpHow == .assumed
                 ? "Starting assumption: \(String(format: "%.0f", store.profile.weightKg)) kg × \(String(format: "%.2f", store.profile.level.wkg)) W/kg for \(store.profile.level.title.lowercased()) riders. It becomes a measurement after a steady 20-minute effort recorded with the BikeComputer, or when you enter a tested value in Profile."
                 : store.profile.ftpHow == .entered ? "Entered by you in Profile." : "Estimated as 95 % of the best 20-minute power of a recorded ride.").font(.footnote).foregroundStyle(.secondary)
            if store.ftpSuggestion != nil { FTPSuggestionCard() }
            Divider()
            Eyebrow(t: "Fitness and form")
            Text("Not enough data yet").font(.subheadline.weight(.semibold)).foregroundStyle(BC.stale)
            Text("Training load and form need about six weeks of rides with power. Nothing is shown before that.").font(.footnote).foregroundStyle(.secondary)
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
