import SwiftUI

// Checkpoint D — Progress analytics cards (cycling · strength · records · goals). Every number says what it was measured
// from; a value without records is described, not drawn. Period selector shared by the cards; charts only with ≥ 3 points.
struct ProgressAnalyticsSection: View {
    @EnvironmentObject private var store: Store
    @State private var period: ProgressPeriod = .month
    @State private var sport = 0   // 0 cycling, 1 strength
    let showRiding: Bool
    let showLifting: Bool

    private var cycling: CyclingAnalytics { ProgressAnalytics.cycling(rides: store.rides, period: period, ftpW: store.profile.ftpKnown ? store.profile.ftpW : nil, hrZones: store.profile.hrZones) }
    private var strength: StrengthAnalytics { ProgressAnalytics.strength(sessions: store.strength, period: period) }
    private var goals: [GoalProgress] {
        let m = TrainingLedger.monday(of: Date())
        return ProgressAnalytics.goals(riding: store.ledger.riding(weekOf: m), lifting: store.ledger.lifting(weekOf: m), hoursPerWeek: store.profile.hoursPerWeek, liftingHoursPerWeek: store.profile.liftingHoursPerWeek, includesCycling: store.profile.trainingMode.includesCycling, includesStrength: store.profile.trainingMode.includesLifting)
    }

    var body: some View {
        VStack(spacing: DS.m) {
            if !goals.isEmpty { goalsCard }
            Card {
                VStack(alignment: .leading, spacing: DS.s) {
                    HStack { Eyebrow(t: "Analytics"); Spacer(); Picker("Period", selection: $period) { ForEach(ProgressPeriod.allCases, id: \.self) { Text($0.title).tag($0) } }.pickerStyle(.menu).accessibilityIdentifier("progressPeriod") }
                    if showRiding && showLifting { Picker("Sport", selection: $sport) { Text("Cycling").tag(0); Text("Strength").tag(1) }.pickerStyle(.segmented).accessibilityIdentifier("progressSport") }
                    if (showRiding && sport == 0) || !showLifting { cyclingBody(cycling) } else { strengthBody(strength) }
                }
            }
            recordsCard
        }
    }

    // MARK: goals
    private var goalsCard: some View {
        Card {
            VStack(alignment: .leading, spacing: DS.s) {
                Eyebrow(t: "Goals · this week")
                ForEach(goals, id: \.title) { g in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack { Text(g.title).font(.subheadline.weight(.semibold)); Spacer(); Text(CyDesign.percentText(g.fraction)).font(.caption.weight(.heavy)).monospacedDigit() }
                        ProgressView(value: g.fraction).tint(CyTheme.cycling.tint)
                        Text(g.detail).font(.caption).foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine).accessibilityLabel("\(g.title): \(g.detail)")
                }
                Text("Recorded time comes from saved rides and logged sessions; the goal is the weekly time in your profile.").font(.caption2).foregroundStyle(.secondary)
            }
        }
        .accessibilityIdentifier("progressGoals")
    }

    // MARK: cycling
    @ViewBuilder private func cyclingBody(_ a: CyclingAnalytics) -> some View {
        if a.rides == 0 {
            Text("No rides saved in this period. Rides recorded with the phone or the BikeComputer, and Apple Health rides you import, appear here once saved.").font(.footnote).foregroundStyle(.secondary)
        } else {
            tiles([("Rides", "\(a.rides)", nil), ("Time", Fmt.duration(minutes: a.minutes), nil),
                   ("Distance", a.distanceKm.map { String(format: "%.1f km", $0.value) } ?? "—", a.distanceKm.map { "\($0.records) of \(a.rides) rides had distance" } ?? "no ride recorded a distance"),
                   ("Avg speed", a.avgSpeedKmh.map { String(format: "%.1f km/h", $0.value) } ?? "—", nil),
                   ("Avg power", a.avgPower.map { "\($0.value) W" } ?? "—", a.avgPower.map { "\($0.records) rides with a power meter" } ?? "no power measured"),
                   ("Avg HR", a.avgHR.map { "\($0.value) bpm" } ?? "—", a.avgHR.map { "\($0.records) rides with heart rate" } ?? "no heart rate measured")])
            if let c = a.comparison { Text(c).font(.caption).foregroundStyle(.secondary) }
            Text("Consistency: rides in \(a.consistency.active) of \(a.consistency.weeks) weeks").font(.caption).foregroundStyle(.secondary)
            trend("Weekly average power", a.powerTrend.map { Double($0.w) }, a.powerTrend.map { short($0.week) }, "W", "duration-weighted average of rides that measured power")
            trend("Weekly average heart rate", a.hrTrend.map { Double($0.bpm) }, a.hrTrend.map { short($0.week) }, "bpm", "rides with a heart-rate source")
            trend("Weekly average cadence", a.cadenceTrend.map { Double($0.rpm) }, a.cadenceTrend.map { short($0.week) }, "rpm", "rides with a cadence sensor")
            zoneBars(a)
        }
    }
    private func zoneBars(_ a: CyclingAnalytics) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Time in zones").font(.subheadline.weight(.semibold))
            if a.zoneSeconds.isEmpty || a.zoneSeconds.reduce(0, +) == 0 { Text("Not measurable: " + a.zoneBasis.replacingOccurrences(of: "not measurable: ", with: "") + ".").font(.caption).foregroundStyle(.secondary) }
            else {
                let total = Double(a.zoneSeconds.reduce(0, +))
                HStack(spacing: 2) { ForEach(Array(a.zoneSeconds.enumerated()), id: \.offset) { i, s in RoundedRectangle(cornerRadius: 3).fill(BC.zone(min(7, i + 1)).opacity(0.85)).frame(width: max(2, CGFloat(Double(s) / total) * 280), height: 10) } }
                Text(a.zoneSeconds.enumerated().map { "Z\($0.offset + 1) \(Int((Double($0.element) / total * 100).rounded())) %" }.joined(separator: " · ")).font(.caption2).foregroundStyle(.secondary).monospacedDigit()
                Text("From \(a.zoneBasis).").font(.caption2).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: strength
    @ViewBuilder private func strengthBody(_ a: StrengthAnalytics) -> some View {
        if a.sessions == 0 {
            Text("No strength sessions in this period. Logged sessions and Apple Health imports appear here once saved.").font(.footnote).foregroundStyle(.secondary)
        } else {
            tiles([("Sessions", "\(a.sessions)", a.detailedSessions < a.sessions ? "\(a.sessions - a.detailedSessions) quick logs without sets" : nil), ("Sets", "\(a.sets)", nil), ("Reps", "\(a.reps)", nil),
                   ("Volume", a.tonnageKg.map { String(format: "%.0f kg", $0.value) } ?? "—", a.tonnageKg.map { "reps × weight over \($0.records) weighted sets; bodyweight sets excluded" } ?? "no weighted sets logged")])
            Text("Consistency: sessions in \(a.consistency.active) of \(a.consistency.weeks) weeks").font(.caption).foregroundStyle(.secondary)
            if !a.exercises.isEmpty {
                Text("Exercises").font(.subheadline.weight(.semibold))
                ForEach(a.exercises.prefix(8)) { e in
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 1) { Text(e.name).font(.subheadline); Text("\(e.sessions) sessions · \(e.sets) sets · \(e.trend)").font(.caption).foregroundStyle(.secondary) }
                        Spacer()
                        Text(e.topWeightKg.map { WeightFmt.text($0, store.settings.units) + " × \(e.topReps)" } ?? "bodyweight × \(e.topReps)").font(.caption.weight(.semibold)).monospacedDigit()
                    }
                    .accessibilityElement(children: .combine)
                }
                Text("Top set = heaviest logged set in the period. Trends compare the first and last top sets, nothing is estimated.").font(.caption2).foregroundStyle(.secondary)
            }
            if !a.muscleCoverage.isEmpty {
                Text("Muscle groups (logged sets)").font(.subheadline.weight(.semibold))
                Text(a.muscleCoverage.prefix(8).map { "\($0.group) \($0.sets)" }.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary)
                Text("From the exercise catalogue's muscle tags; your own exercises without tags are not counted.").font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: records
    private var recordsCard: some View {
        let recs = (showRiding ? cycling.records : []) + (showLifting ? strength.records : [])
        return Card {
            VStack(alignment: .leading, spacing: DS.s) {
                Eyebrow(t: "Personal records")
                if recs.isEmpty { Text("Records appear from saved rides and logged sets — none yet.").font(.footnote).foregroundStyle(.secondary) }
                ForEach(recs) { r in
                    HStack { VStack(alignment: .leading, spacing: 1) { Text(r.kind).font(.subheadline); Text(r.date, style: .date).font(.caption).foregroundStyle(.secondary) }; Spacer(); Text(r.value).font(.subheadline.weight(.bold)).monospacedDigit() }
                        .accessibilityElement(children: .combine)
                }
                if !recs.isEmpty { Text("From every saved ride and logged set, not estimates.").font(.caption2).foregroundStyle(.secondary) }
            }
        }
        .accessibilityIdentifier("progressRecords")
    }

    // MARK: pieces
    private func tiles(_ items: [(String, String, String?)]) -> some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, t in
                VStack(alignment: .leading, spacing: 1) {
                    Text(t.0.uppercased()).font(.caption2.weight(.heavy)).foregroundStyle(.secondary).tracking(0.4)
                    Text(t.1).font(.title3.weight(.bold)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
                    if let n = t.2 { Text(n).font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
                }
                .frame(maxWidth: .infinity, alignment: .leading).padding(10)
                .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10))
                .accessibilityElement(children: .combine).accessibilityLabel("\(t.0) \(t.1)" + (t.2.map { ", " + $0 } ?? ""))
            }
        }
    }
    @ViewBuilder private func trend(_ title: String, _ values: [Double], _ labels: [String], _ unit: String, _ basis: String) -> some View {
        if values.count >= 3 {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.subheadline.weight(.semibold))
                CyBarChart(values: values.map { Optional($0) }, labels: labels, unit: unit, height: 80)
                Text("Measured from \(basis).").font(.caption2).foregroundStyle(.secondary)
            }
        } else if !values.isEmpty {
            Text("\(title): \(values.count) week\(values.count == 1 ? "" : "s") with data — a trend needs at least 3.").font(.caption).foregroundStyle(.secondary)
        }
    }
    private func short(_ d: Date) -> String { let f = DateFormatter(); f.dateFormat = "d MMM"; return f.string(from: d) }
}
