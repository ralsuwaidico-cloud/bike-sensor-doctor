import SwiftUI
import MapKit

/// Checkpoint F slice 3 (RA-21…RA-24): the Strava-like results page, shared by the post-ride sheet and the saved-ride
/// page. Everything shown comes from `RideResultsModel` (pure, unit-tested) built from the stored RideRecord — no
/// simulated or estimated figure ever reaches this view. Follows the system light/dark appearance (Theme.swift), unlike
/// the live cockpit which is always dark.
struct RideResultsContent: View {
    let ride: RideRecord
    let model: RideResultsModel
    let units: AppSettings.Units
    var showGraph = false

    private var coords: [CLLocationCoordinate2D] {
        ride.samples.compactMap { s in if let la = s.lat, let lo = s.lon { return CLLocationCoordinate2D(latitude: la, longitude: lo) }; return nil }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            routeCard
            headline
            analysisCard
            zonesCard
            if !model.steps.isEmpty { stepsCard } else { freeRideCard }
            recordsCard
            Card { Eyebrow(t: "Coach summary (rules)"); Text(model.coachSummary).font(.subheadline).fixedSize(horizontal: false, vertical: true) }
                .accessibilityIdentifier("rideCoachSummary")
            ForEach(model.notes, id: \.self) { n in Text(n).font(.footnote).foregroundStyle(BC.stale).fixedSize(horizontal: false, vertical: true) }
        }
    }

    // MARK: route
    private var routeCard: some View {
        Card {
            Eyebrow(t: "Route")
            let c = coords
            if c.count >= 2 {
                Map { MapPolyline(coordinates: c).stroke(BC.accent, lineWidth: 4) }
                    .frame(height: 200).clipShape(RoundedRectangle(cornerRadius: 12)).allowsHitTesting(false)
                    .accessibilityLabel("Route map, \(c.count) GPS points").accessibilityIdentifier("rideResultMap")
                Text("\(c.count) GPS points from the phone").font(.caption2).foregroundStyle(.secondary)
            } else {
                Text("No GPS track for this ride").font(.footnote).foregroundStyle(BC.stale)
                Text(ride.recorder == .health ? "Imported from Apple Health without a route." : "Location was off or had no fix; distance and time still count.").font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: headline
    private var headline: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
            ForEach(model.headline, id: \.key) { s in statTile(s) }
        }
        .accessibilityIdentifier("rideResultHeadline")
    }
    private func statTile(_ s: RideResultsModel.Stat) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Eyebrow(t: s.label)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(s.value).font(BC.numFont).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
                if !s.unit.isEmpty { Text(s.unit).font(.footnote).foregroundStyle(.secondary) }
            }
            Text(s.source).font(.caption2).foregroundStyle(s.value == "—" ? BC.stale : .secondary).lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(12)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(s.label) \(s.value) \(s.unit), \(s.source)")
    }

    // MARK: analysis
    private var analysisCard: some View {
        Card {
            Eyebrow(t: "Analysis")
            ForEach(model.analysis, id: \.key) { s in
                HStack(alignment: .firstTextBaseline) {
                    Text(s.label).font(.caption.weight(.semibold)).foregroundStyle(.secondary).frame(width: 96, alignment: .leading)
                    Text(s.value).font(.title3.weight(.bold)).monospacedDigit()
                    Text(s.unit).font(.caption).foregroundStyle(.secondary)
                    Spacer(minLength: 4)
                    Text(s.source).font(.caption2).foregroundStyle(s.value == "—" ? BC.stale : .secondary).multilineTextAlignment(.trailing).lineLimit(2)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .accessibilityIdentifier("rideResultAnalysis")
    }

    // MARK: zones
    private var zonesCard: some View {
        Card {
            Eyebrow(t: model.zoneBasis ?? "Zones")
            if model.zoneSeconds.isEmpty || model.zoneSeconds.reduce(0, +) == 0 {
                Text(ride.hasPower ? "Power zones need a known FTP." : "Zones need power with a known FTP, or heart rate with zones.").font(.footnote).foregroundStyle(BC.stale)
            } else {
                let total = max(1, model.zoneSeconds.reduce(0, +))
                let power = (model.zoneBasis ?? "").hasPrefix("POWER")
                GeometryReader { g in
                    HStack(spacing: 2) {
                        ForEach(Array(model.zoneSeconds.enumerated()), id: \.offset) { z, s in
                            if s > 0 { RoundedRectangle(cornerRadius: 3).fill(power ? BC.zone(z + 1) : D7.hrZone(z + 1)).frame(width: max(4, g.size.width * CGFloat(s) / CGFloat(total))) }
                        }
                    }
                }
                .frame(height: 14)
                Text(zoneText(model.zoneSeconds)).font(.caption2).foregroundStyle(.secondary)
            }
        }
        .accessibilityIdentifier("rideResultZones")
    }
    private func zoneText(_ secs: [Int]) -> String {
        var parts: [String] = []
        for (i, s) in secs.enumerated() where s > 0 { parts.append("Z\(i + 1) \(s / 60) min") }
        return parts.joined(separator: " · ")
    }

    // MARK: plan vs ride
    private var stepsCard: some View {
        Card {
            Eyebrow(t: model.stepBasis)
            ForEach(Array(model.steps.enumerated()), id: \.offset) { _, st in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(st.mark).font(.subheadline.weight(.heavy)).foregroundStyle(markColor(st.mark)).frame(width: 14).accessibilityLabel(markLabel(st.mark))
                    VStack(alignment: .leading, spacing: 1) {
                        Text(st.name).font(.subheadline.weight(.semibold))
                        Text("target \(st.planned)").font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 4)
                    Text(st.actual).font(.caption).monospacedDigit().multilineTextAlignment(.trailing)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .accessibilityIdentifier("rideResultSteps")
    }
    /// Honest state for a ride with no stored plan steps: a free ride, or one saved by a build that kept no plan.
    private var freeRideCard: some View {
        Card {
            Eyebrow(t: "Free ride")
            Text(ride.planSteps == nil ? "No plan steps are stored for this ride — it was a free ride, or it was saved before Cyclift kept the plan with the ride. Nothing is compared against a target." : "This ride had no planned steps, so there is nothing to compare against a target.")
                .font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityIdentifier("rideResultFreeRide")
    }
    private func markColor(_ m: String) -> Color { m == "✓" ? BC.live : m == "!" ? BC.stale : .secondary }
    private func markLabel(_ m: String) -> String { m == "✓" ? "completed in target" : m == "!" ? "outside the target band" : m == "–" ? "cut short" : "not reached" }

    // MARK: records
    private var recordsCard: some View {
        Card {
            Eyebrow(t: "Records · \(model.recordBasis)")
            ForEach(Array(model.records.enumerated()), id: \.offset) { _, r in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Image(systemName: r.isRecord ? "trophy.fill" : "circle").foregroundStyle(r.isRecord ? BC.stale : .secondary).font(.caption).accessibilityHidden(true)
                    Text(r.text).font(.footnote).fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .accessibilityIdentifier("rideResultRecords")
    }
}

// MARK: - RideRecord → results model (bridge lives here so the pure model stays Foundation-only)
extension RideResultsModel.Input {
    init(_ r: RideRecord) {
        let e = r.energyShown
        self.init(id: r.id, start: r.start, durationS: r.durationS, distanceM: r.distanceM, demo: r.demo, recorder: r.recordedBy,
                  avgPower: r.avgPower, maxPower: r.maxPower, normalizedPower: r.normalizedPower, avgHR: r.avgHR, maxHR: r.maxHR, avgCadence: r.avgCadence,
                  energyValue: e?.value, energyUnit: e?.unit, energySource: e?.sourceText)
        sources = r.sources
        samples = r.samples.map { RidePerformanceModel.Sample(t: $0.t, w: $0.w, cad: $0.cad, hr: $0.hr, speedCms: $0.speedCms) }
        altitudes = r.samples.compactMap { s in s.alt.map { (t: s.t, alt: $0) } }
        zoneSeconds = r.recorder == .board ? r.zoneSeconds : []
        hrSource = r.sources.contains("Apple Watch") ? "Apple Watch" : (r.sources.contains("Heart rate") ? "Heart-rate sensor" : nil)
        powerSource = r.avgPower == nil ? nil : (r.powerVerified == true ? "Power meter" : "Power meter (unverified)")
        title = r.title
    }
}

extension RideResultsModel.PlanStep {
    init(_ s: RideRecord.PlanStep) { self.init(name: s.name, minutes: s.minutes, hrZone: s.hrZone, rpe: s.rpeLo...max(s.rpeLo, s.rpeHi)) }
    init(_ s: RideStep) { self.init(name: s.name, minutes: s.minutes, hrZone: s.hrZone, rpe: s.rpe) }
}

extension RideResultsModel {
    /// The model for one stored ride, against the rest of the rider's history and the profile's zones.
    static func make(ride r: RideRecord, store: Store) -> RideResultsModel {
        let p = store.profile
        let zones = Zones(ftpKnown: p.ftpKnown, ftp: p.ftpW, hrZones: p.hrZones, maxHr: p.maxHRForZones ?? 0)
        let plan = (r.planSteps ?? []).map(PlanStep.init)
        return make(ride: Input(r), others: store.rides.map(Input.init), zones: zones, plan: plan, imperial: store.settings.units == .imperial)
    }
}

// MARK: - Ride history (RA-24): searchable, newest first, demo rides never listed; a row reopens the saved results page
struct RideHistoryView: View {
    @EnvironmentObject private var store: Store
    @State private var query = ""
    private var rows: [RideRecord] {
        let all = store.rides.filter { !$0.demo }.sorted { $0.start > $1.start }
        return RideHistorySearch.filter(all, query: query) { Self.searchText($0, units: store.settings.units) }
    }
    static func searchText(_ r: RideRecord, units: AppSettings.Units) -> String {
        let f = DateFormatter(); f.dateFormat = "EEEE d MMMM yyyy"
        return [r.title, r.dateKnown ? f.string(from: r.start) : "", Self.distance(r, units: units), r.recordedBy, r.sources.joined(separator: " "), r.hasPower ? "power" : "", r.avgHR != nil ? "heart rate" : ""].joined(separator: " · ")
    }
    static func distance(_ r: RideRecord, units: AppSettings.Units) -> String {
        units == .imperial ? String(format: "%.1f mi", Double(r.distanceM) / 1609.34) : String(format: "%.1f km", Double(r.distanceM) / 1000)
    }
    var body: some View {
        List {
            if rows.isEmpty {
                Text(query.isEmpty ? "No rides saved yet. Finished rides appear here with their route, numbers and records." : "No ride matches “\(query)”.").font(.footnote).foregroundStyle(.secondary)
                    .accessibilityIdentifier("rideHistoryEmpty")
            }
            ForEach(rows) { r in
                NavigationLink { RideDetailView(ride: r) } label: { row(r) }
                    .accessibilityIdentifier("rideHistoryRow")
            }
        }
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search rides: type, date, distance, source")
        .navigationTitle("Ride history").navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("rideHistory")
    }
    private func row(_ r: RideRecord) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack { Text(r.title).font(.subheadline.weight(.semibold)); Spacer(); Text(r.dateKnown ? r.start.dayAndDate : "date unknown").font(.caption).foregroundStyle(.secondary) }
            HStack(spacing: 8) {
                Text(Self.distance(r, units: store.settings.units)).font(.caption).monospacedDigit()
                Text(r.durationS.asDuration).font(.caption).monospacedDigit()
                if let p = r.avgPower { Text("\(p) W").font(.caption).monospacedDigit() }
                if let h = r.avgHR { Text("\(h) bpm").font(.caption).monospacedDigit() }
                Spacer(); Text(r.recordedBy).font(.caption2).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
