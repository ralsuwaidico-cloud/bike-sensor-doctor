import SwiftUI

// Progress v2.3 — the pages the Progress landing opens (direction: sheet PG5 "detail screens", illustrative sample
// data; open editorial base: no cards, hairline rows, one large figure per block).
//
//   analytics    Detailed analytics      period figures for cycling and strength, FTP with its source, records, checkpoints
//   history      Records & history       every recorded ride and logged session, newest first; a row opens the record
//   endurance    Endurance development   20-minute power (when measured), riding time per week, zones
//   strength     Strength development    the main lift, every lift first → latest, records, coverage, exposure
//   consistency  Training consistency    week by week: sessions done, and done against planned
//   zones        Time in zones           recorded time per zone, what it is calculated from, the settings behind it
//
// HONESTY RULES
// • Every figure is read from the store (saved rides, logged sessions, the plan, the athlete's settings) through the
//   app's existing calculations (ProgressAnalytics, ProgressDevelopment, TrendChartMath, Timeline, lift summaries).
//   Nothing is calculated in a new way here, and nothing is shown when it was not recorded ("—" with the reason).
// • Provenance is printed where a value could be mistaken for a measurement: Measured / Logged / Entered / Estimated /
//   Unavailable.
// • No stage, threshold, "verified achievement", "stage evidence" or timeline event of sheet PG5 is built: the stage
//   criteria are not approved. Those parts of the sheet are absent, not imitated.

// MARK: - Routes

private struct ProgressOpenKey: EnvironmentKey {
    static let defaultValue: (ProgressRoute) -> Void = { _ in }
}
extension EnvironmentValues {
    /// Pushes a Progress page on the Progress screen's own navigation stack: appends one route to the stack's path, so
    /// Back returns to the page the control was on. ProgressScreen sets it for the landing page AND for every pushed
    /// page. (Fast check 17: it was set on the landing content only. A pushed page does not inherit the environment
    /// of the view that pushed it, so the links on the detail pages called the empty default and did nothing.)
    var progressOpen: (ProgressRoute) -> Void {
        get { self[ProgressOpenKey.self] }
        set { self[ProgressOpenKey.self] = newValue }
    }
}

/// Every page Progress can push. The one element type of the Progress navigation path.
enum ProgressRoute: String, Hashable, CaseIterable {
    case analytics, history, endurance, strength, consistency, zones, evolution, power, heartRate

    /// The redesigned page for a route; nil = Athlete Evolution (ProgressScreen builds it: it needs the shown sample).
    static func page(_ route: ProgressRoute) -> AnyView? {
        switch route {
        case .analytics: return AnyView(ProgressAnalyticsV2Page())
        case .history: return AnyView(ProgressHistoryV2Page())
        case .endurance: return AnyView(ProgressEnduranceV2Page())
        case .strength: return AnyView(ProgressStrengthV2Page())
        case .consistency: return AnyView(ProgressConsistencyV2Page())
        case .zones: return AnyView(ProgressZonesV2Page())
        case .power: return AnyView(CyProfilePower())             // the existing Profile › Performance › Power page
        case .heartRate: return AnyView(CyProfileHeartRate())     // the existing Profile › Performance › Heart rate page
        case .evolution: return nil
        }
    }
}

// MARK: - Shared pieces

/// A Progress detail page. `barTitle` = the title is in the navigation bar (Detailed analytics, Records & history: the
/// Lab checks look for those bars); otherwise the title is the large heading of the page, as on sheet PG5.
struct PgPage<Content: View>: View {
    let title: String
    var subtitle: String? = nil
    let id: String
    var barTitle = false
    @ViewBuilder var content: () -> Content
    @Environment(\.cyTheme) private var theme

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if !barTitle {
                    Text(title)
                        .font(.system(.title2, design: .rounded).weight(.heavy))
                        .foregroundStyle(theme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityIdentifier(id + "Title")
                }
                if let subtitle {
                    Text(subtitle)
                        .font(.system(.footnote))
                        .foregroundStyle(theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 2)
                }
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 120)
        }
        .background(theme.background.ignoresSafeArea())
        .navigationTitle(barTitle ? title : "")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(id)
    }
}

/// Section overline with an optional right-hand note ("PERFORMANCE" … "12 weeks").
struct PgOverline: View {
    let text: String
    var trailing: String? = nil
    @Environment(\.cyTheme) private var theme
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(text).font(CyFont.overline).tracking(1.4).foregroundStyle(theme.textSecondary).accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            if let trailing {
                Text(trailing).font(.caption.weight(.semibold)).foregroundStyle(theme.textPrimary)
            }
        }
        .padding(.top, 26)
        .padding(.bottom, 6)
    }
}

/// Where a value came from, as one word in a thin outline.
struct PgTag: View {
    let text: String
    @Environment(\.cyTheme) private var theme
    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(theme.textSecondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .overlay(RoundedRectangle(cornerRadius: 5).stroke(theme.border, lineWidth: 1))
            .accessibilityLabel("Source: \(text)")
    }
}

/// The large figure of a block ("221 W").
struct PgFigure: View {
    let value: String
    let unit: String
    @Environment(\.cyTheme) private var theme
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Text(value)
                .font(.system(size: 34, weight: .heavy, design: .rounded)).monospacedDigit()
                .foregroundStyle(theme.textPrimary).lineLimit(1).minimumScaleFactor(0.6)
            Text(unit).font(.system(.subheadline).weight(.semibold)).foregroundStyle(theme.textSecondary)
        }
        .accessibilityElement(children: .combine)
    }
}

/// One line of secondary text.
struct PgNote: View {
    let text: String
    var id: String = ""
    @Environment(\.cyTheme) private var theme
    var body: some View {
        Text(text)
            .font(.system(.footnote))
            .foregroundStyle(theme.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.vertical, 4)
            .accessibilityIdentifier(id)
    }
}

/// A fact row: label on the left; the value in bold and a quiet note on the right; an optional source tag; a hairline.
struct PgFact: View {
    let label: String
    let value: String
    var note: String? = nil
    var tag: String? = nil
    var id: String = ""
    @Environment(\.cyTheme) private var theme
    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(label)
                    .font(CyDyn.f(14.5, .semibold))
                    .foregroundStyle(theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                if let tag { PgTag(text: tag) }
                Spacer(minLength: 8)
                right
                    .multilineTextAlignment(.trailing)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 10)
            .frame(minHeight: 40)
            Rectangle().fill(theme.separator).frame(height: 1).accessibilityHidden(true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(id)
    }
    private var right: Text {
        let v = Text(value).font(CyDyn.f(14.5, .bold)).monospacedDigit().foregroundColor(theme.textPrimary)
        guard let note, !note.isEmpty else { return v }
        return v + Text(" · " + note).font(CyDyn.f(13)).foregroundColor(theme.textSecondary)
    }
}

/// The label of a row that opens a page (title, one line under it, chevron).
struct PgLinkLabel: View {
    let title: String
    var sub: String = ""
    @Environment(\.cyTheme) private var theme
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: CySpace.s) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(.callout, design: .rounded).weight(.semibold)).foregroundStyle(theme.textPrimary)
                        .multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                    if !sub.isEmpty {
                        Text(sub).font(.caption).foregroundStyle(theme.textSecondary)
                            .multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: CySpace.s)
                Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(theme.textTertiary).accessibilityHidden(true)
            }
            .frame(minHeight: 52)
            .contentShape(Rectangle())
            Rectangle().fill(theme.separator).frame(height: 1).accessibilityHidden(true)
        }
        .accessibilityElement(children: .combine)
    }
}

/// A row that pushes one of the Progress routes.
struct PgRouteRow: View {
    let title: String
    var sub: String = ""
    let route: ProgressRoute
    let id: String
    @Environment(\.progressOpen) private var open
    var body: some View {
        Button { open(route) } label: { PgLinkLabel(title: title, sub: sub) }
            .buttonStyle(.plain)
            .accessibilityIdentifier(id)
    }
}

/// Weekly values as bars; a week with nothing recorded is a short mark on the baseline, never an invented bar.
struct PgWeekBars: View {
    let values: [Int]
    let color: Color
    let empty: Color
    var body: some View {
        GeometryReader { g in
            let top = CGFloat(max(values.max() ?? 1, 1))
            HStack(alignment: .bottom, spacing: 4) {
                ForEach(Array(values.enumerated()), id: \.offset) { _, v in
                    RoundedRectangle(cornerRadius: 2.5)
                        .fill(v > 0 ? color : empty)
                        .frame(maxWidth: .infinity)
                        .frame(height: v > 0 ? max(4, g.size.height * CGFloat(v) / top) : 2)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        }
        .accessibilityHidden(true)
    }
}

/// A labelled horizontal bar ("Quads ▬▬▬▬ 142").
struct PgCountBar: View {
    let label: String
    let count: Int
    let top: Int
    let color: Color
    @Environment(\.cyTheme) private var theme
    var body: some View {
        HStack(spacing: 10) {
            Text(label).font(CyDyn.f(13.5, .semibold)).foregroundStyle(theme.textPrimary).lineLimit(1).minimumScaleFactor(0.7)
                .frame(width: 96, alignment: .leading)
            GeometryReader { g in
                Capsule().fill(color)
                    .frame(width: max(4, g.size.width * CGFloat(count) / CGFloat(max(top, 1))), height: 5)
                    .frame(maxHeight: .infinity, alignment: .center)
            }
            .frame(height: 18)
            Text("\(count)").font(CyDyn.f(13.5, .bold)).monospacedDigit().foregroundStyle(theme.textPrimary)
                .frame(minWidth: 34, alignment: .trailing)
        }
        .frame(minHeight: 28)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label), \(count) sets")
    }
}

/// The zone strip and its legend (the same drawing as on the landing page), with the recorded time per zone.
struct PgZoneStrip: View {
    let zones: ProgressDevelopment.Zones
    @Environment(\.cyTheme) private var theme
    var body: some View {
        GeometryReader { g in
            HStack(spacing: 2) {
                ForEach(Array(zones.shares.enumerated()), id: \.offset) { i, s in
                    if s > 0 {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(theme.endurance.opacity(0.35 + 0.65 * Double(i) / Double(max(zones.shares.count - 1, 1))))
                            .frame(width: max(3, (g.size.width - CGFloat(zones.shares.count - 1) * 2) * CGFloat(s) / 100))
                    }
                }
            }
        }
        .frame(height: 12)
        .accessibilityHidden(true)
    }
}

private enum PgText {
    static func day(_ d: Date) -> String { let f = DateFormatter(); f.dateFormat = "d MMM"; return f.string(from: d) }
    static func dayYear(_ d: Date) -> String { let f = DateFormatter(); f.dateFormat = "d MMM yyyy"; return f.string(from: d) }
    static func km(_ m: Int) -> String { String(format: "%.1f km", Double(m) / 1000) }
}

private extension Store {
    var pgShowRiding: Bool { profile.trainingMode.includesCycling || !rides.isEmpty }
    var pgShowLifting: Bool { profile.trainingMode.includesLifting || !strength.isEmpty }
    /// Time in zones for the Progress pages: samples first, then the totals saved with the rides, else the exact reason.
    var pgZones: (zones: ProgressDevelopment.Zones?, unavailable: ProgressDevelopment.ZonesUnavailable?) {
        let a = ProgressAnalytics.cycling(rides: rides, period: .quarter, ftpW: profile.ftpKnown ? profile.ftpW : nil, hrZones: profile.hrZones)
        return ProgressDevelopment.zonesResolved(sampled: ProgressDevelopment.zones(a).zones, rides: rides, ftpKnown: profile.ftpKnown, hrZonesKnown: profile.hrZonesKnown)
    }
}

/// The two settings zones are calculated from, each opening its existing Profile page.
struct PgZoneSettingsRows: View {
    var only: [ProgressDevelopment.ZoneSetting] = [.power, .heartRate]
    @EnvironmentObject private var store: Store
    var body: some View {
        let p = store.profile
        VStack(spacing: 0) {
            if only.contains(.power) {
                PgRouteRow(title: "Power settings", sub: "FTP \(p.ftpDisplay) · \(p.ftpSource.title)", route: ProgressRoute.power, id: "progressOpenPowerSettings")
            }
            if only.contains(.heartRate) {
                PgRouteRow(title: "Heart-rate settings",
                           sub: p.maxHRForZones.map { "Maximum \($0) bpm · \(p.maxHRIsEstimate ? "estimated from age" : "entered")" } ?? "Maximum heart rate not set",
                           route: ProgressRoute.heartRate, id: "progressOpenHeartRateSettings")
            }
        }
    }
}

// MARK: - Detailed analytics

struct ProgressAnalyticsV2Page: View {
    @EnvironmentObject private var store: Store
    @Environment(\.cyTheme) private var theme
    @State private var period: ProgressPeriod = .month

    private var cycling: CyclingAnalytics {
        ProgressAnalytics.cycling(rides: store.rides, period: period, ftpW: store.profile.ftpKnown ? store.profile.ftpW : nil, hrZones: store.profile.hrZones)
    }
    private var strength: StrengthAnalytics { ProgressAnalytics.strength(sessions: store.strength, period: period) }
    private var goals: [GoalProgress] {
        let m = TrainingLedger.monday(of: Date())
        let p = store.profile
        return ProgressAnalytics.goals(riding: store.ledger.riding(weekOf: m), lifting: store.ledger.lifting(weekOf: m), hoursPerWeek: p.hoursPerWeek,
                                       liftingHoursPerWeek: p.liftingHoursPerWeek, includesCycling: p.trainingMode.includesCycling, includesStrength: p.trainingMode.includesLifting)
    }

    var body: some View {
        PgPage(title: "Detailed analytics", id: "progressAnalyticsPage", barTitle: true) {
            goalsBlock
            PgOverline(text: "PERIOD")
            CyChoiceBar(options: ProgressPeriod.allCases.map { ($0, $0.title) }, selection: $period)
                .accessibilityIdentifier("progressPeriod")
            if store.pgShowRiding {
                cyclingBlock(cycling)
                ftpBlock
            }
            if store.pgShowLifting { strengthBlock(strength) }
            recordsBlock
            checkpointsBlock
            PgNote(text: "Counted from saved rides and logged sessions only. A value that was not recorded is shown as —, never estimated.")
                .padding(.top, 18)
        }
    }

    @ViewBuilder private var goalsBlock: some View {
        if !goals.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                PgOverline(text: "THIS WEEK", trailing: "Against your week")
                ForEach(goals, id: \.title) { g in
                    PgFact(label: g.title, value: CyDesign.percentText(g.fraction), note: g.detail)
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("progressGoals")
        }
    }

    @ViewBuilder private func cyclingBlock(_ a: CyclingAnalytics) -> some View {
        PgOverline(text: "ENDURANCE", trailing: "Cycling · \(period.title.lowercased())")
        if a.rides == 0 {
            PgNote(text: "No rides saved in this period.", id: "analyticsNoRides")
        } else {
            PgFact(label: "Rides", value: "\(a.rides)", note: "in \(a.consistency.active) of \(a.consistency.weeks) weeks")
            PgFact(label: "Time", value: Fmt.duration(minutes: a.minutes), note: "recorded")
            PgFact(label: "Distance", value: a.distanceKm.map { String(format: "%.1f km", $0.value) } ?? "—",
                   note: a.distanceKm.map { "\($0.records) of \(a.rides) rides had distance" } ?? "no ride recorded a distance")
            PgFact(label: "Average speed", value: a.avgSpeedKmh.map { String(format: "%.1f km/h", $0.value) } ?? "—",
                   note: a.avgSpeedKmh == nil ? "needs distance and time" : "distance ÷ time")
            PgFact(label: "Average power", value: a.avgPower.map { "\($0.value) W" } ?? "—",
                   note: a.avgPower.map { "\($0.records) rides with a power meter" } ?? "no power measured",
                   tag: a.avgPower == nil ? "Unavailable" : "Measured")
            PgFact(label: "Average heart rate", value: a.avgHR.map { "\($0.value) bpm" } ?? "—",
                   note: a.avgHR.map { "\($0.records) rides with heart rate" } ?? "no heart rate measured",
                   tag: a.avgHR == nil ? "Unavailable" : "Measured")
            PgFact(label: "Average cadence", value: a.avgCadence.map { "\($0.value) rpm" } ?? "—",
                   note: a.avgCadence.map { "\($0.records) rides with cadence" } ?? "no cadence measured")
            if let c = a.comparison { PgNote(text: c) }
        }
        PgRouteRow(title: "Endurance development", sub: "Riding time per week · 20-minute power · zones", route: ProgressRoute.endurance, id: "analyticsOpenEndurance")
    }

    @ViewBuilder private var ftpBlock: some View {
        let p = store.profile
        PgOverline(text: "FTP", trailing: p.ftpSource.title)
        PgFact(label: "Functional threshold power", value: p.ftpValue.map { "\($0) W" } ?? "Unknown",
               note: p.ftpValue == nil ? nil : (p.wattsPerKg.map { String(format: "%.1f W/kg", $0) } ?? "W/kg needs your weight"),
               tag: p.ftpSource.title, id: "analyticsFTP")
        PgNote(text: p.ftpKnown ? p.ftpSourceText : "Not enough data yet: do an FTP test with a power meter, or enter your FTP in Profile. Rides use heart rate and effort until then.", id: "ftpSource")
        if let s = store.ftpSuggestion {
            VStack(alignment: .leading, spacing: 6) {
                PgFact(label: "Suggested FTP", value: "\(s.watts) W", note: store.profile.ftpKnown ? "was \(s.previousFTP) W" : "FTP unknown until now", tag: "Estimated")
                PgNote(text: "95 % of the best 20-minute power (\(s.best20) W) of your ride on \(PgText.day(s.rideDate)). Nothing changes until you accept.")
                HStack(spacing: 10) {
                    Button("Accept \(s.watts) W") { store.acceptFTPSuggestion() }
                        .font(CyDyn.f(15, .semibold)).foregroundStyle(theme.background)
                        .padding(.horizontal, 16).frame(minHeight: 44)
                        .background(theme.textPrimary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .accessibilityIdentifier("ftpSuggestionAccept")
                    Button("Not now") { store.dismissFTPSuggestion() }
                        .font(CyDyn.f(15, .semibold)).foregroundStyle(theme.textPrimary)
                        .padding(.horizontal, 16).frame(minHeight: 44)
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(theme.border, lineWidth: 1))
                        .accessibilityIdentifier("ftpSuggestionNotNow")
                }
                .buttonStyle(.plain)
            }
        }
        PgRouteRow(title: "Power settings", sub: "FTP, power meter and the zones calculated from FTP", route: ProgressRoute.power, id: "analyticsOpenPowerSettings")
    }

    @ViewBuilder private func strengthBlock(_ a: StrengthAnalytics) -> some View {
        PgOverline(text: "STRENGTH", trailing: "Resistance training · \(period.title.lowercased())")
        if a.sessions == 0 {
            PgNote(text: "No strength sessions logged in this period.", id: "analyticsNoStrength")
        } else {
            PgFact(label: "Sessions", value: "\(a.sessions)",
                   note: a.detailedSessions < a.sessions ? "\(a.sessions - a.detailedSessions) quick logs without sets" : "in \(a.consistency.active) of \(a.consistency.weeks) weeks", tag: "Logged")
            PgFact(label: "Sets", value: "\(a.sets)", note: "\(a.reps) reps")
            PgFact(label: "Volume", value: a.tonnageKg.map { String(format: "%.0f kg", $0.value) } ?? "—",
                   note: a.tonnageKg.map { "reps × weight over \($0.records) weighted sets" } ?? "no weighted sets logged")
            ForEach(Array(a.exercises.prefix(6))) { e in
                PgFact(label: e.name,
                       value: e.topWeightKg.map { WeightFmt.text($0, store.settings.units) + " × \(e.topReps)" } ?? "bodyweight × \(e.topReps)",
                       note: "\(e.sessions) sessions · \(e.trend)")
            }
        }
        PgRouteRow(title: "Strength development", sub: "Every lift, first to latest · records · coverage", route: ProgressRoute.strength, id: "analyticsOpenStrength")
    }

    @ViewBuilder private var recordsBlock: some View {
        let recs = (store.pgShowRiding ? cycling.records : []) + (store.pgShowLifting ? strength.records : [])
        VStack(alignment: .leading, spacing: 0) {
            PgOverline(text: "PERSONAL RECORDS", trailing: "All time")
            if recs.isEmpty {
                PgNote(text: "Records appear from saved rides and logged sets. None yet.")
            }
            ForEach(recs) { r in
                PgFact(label: r.kind, value: r.value, note: PgText.dayYear(r.date))
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("progressRecords")
    }

    @ViewBuilder private var checkpointsBlock: some View {
        VStack(alignment: .leading, spacing: 0) {
            PgOverline(text: "CHECKPOINTS", trailing: "Reviews, not promises")
            if store.pgShowRiding { checkpoints("Cycling", store.checkpoints(.cycling)) }
            if store.pgShowLifting { checkpoints("Strength", store.checkpoints(.strength)) }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("progressCheckpoints")
    }
    @ViewBuilder private func checkpoints(_ sport: String, _ cps: [Checkpoint]) -> some View {
        if cps.isEmpty {
            PgFact(label: sport, value: "—", note: "starts with your first completed session")
        }
        ForEach(cps, id: \.weeks) { c in
            PgFact(label: "\(sport) · week \(c.weeks)", value: c.reached ? "Reached" : "Not yet", note: checkpointLine(c))
        }
    }
    private func checkpointLine(_ c: Checkpoint) -> String {
        if !c.reached { return c.missing ?? "not enough evidence yet" }
        switch c.performance {
        case .improved: return "\(c.sessions) sessions · improving"
        case .flat: return "\(c.sessions) sessions · holding steady"
        case .declined: return "\(c.sessions) sessions · lower than before"
        case .notEnoughData: return "\(c.sessions) sessions · performance needs more data"
        }
    }
}

// MARK: - Records & history

struct ProgressHistoryV2Page: View {
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var device: DeviceLink
    @Environment(\.cyTheme) private var theme
    @State private var showAll = false

    private var entries: [TimelineEntry] {
        Timeline.build(rides: store.rides, plan: store.plan, ftp: store.profile.ftpValue ?? 0, strength: store.strength)
    }

    var body: some View {
        let all = entries
        let shown = showAll ? all : Array(all.prefix(20))
        let done = all.filter { $0.status == .completed || $0.status == .imported }.count
        let missed = all.filter { $0.status == .missed }.count
        PgPage(title: "Records & history", id: "progressHistoryPage", barTitle: true) {
            PgOverline(text: "HISTORY", trailing: "\(done) done · \(missed) missed")
            if all.isEmpty {
                PgNote(text: "No rides, logged strength sessions or completed sessions yet. They appear here as soon as they are saved.", id: "progressHistoryEmpty")
            }
            ForEach(shown) { e in row(e) }
            if all.count > 20 {
                Button(showAll ? "Show fewer" : "Show all \(all.count)") { showAll.toggle() }
                    .font(CyDyn.f(15, .semibold)).foregroundStyle(theme.textPrimary)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("progressHistoryShowAll")
            }
            PgNote(text: "BikeComputer history: \(device.syncStatus). Rides recorded on the BikeComputer while the phone was away stay on it until its firmware serves them; nothing is invented here.")
                .padding(.top, 14)
        }
    }

    @ViewBuilder private func row(_ e: TimelineEntry) -> some View {
        if let rid = e.rideId, let r = store.rides.first(where: { $0.id == rid }) {
            NavigationLink { ProgressRideV2Page(ride: r) } label: { PgHistoryRow(entry: e, opens: true) }
                .buttonStyle(.plain)
                .accessibilityIdentifier("historyRow-ride")
        } else if let sid = e.strengthId, let s = store.strength.first(where: { $0.id == sid }) {
            NavigationLink { ProgressSessionV2Page(session: s) } label: { PgHistoryRow(entry: e, opens: true) }
                .buttonStyle(.plain)
                .accessibilityIdentifier("historyRow-strength")
        } else {
            PgHistoryRow(entry: e, opens: false)
                .accessibilityIdentifier("historyRow-plan")
        }
    }
}

/// One history entry: date and state, the session's name, and only what was recorded for it.
struct PgHistoryRow: View {
    let entry: TimelineEntry
    let opens: Bool
    @Environment(\.cyTheme) private var theme

    private var stateWord: String {
        switch entry.status {
        case .completed: return "Completed"
        case .imported: return "Imported"
        case .missed: return "Missed"
        case .skipped: return "Skipped"
        case .planned: return "Planned"
        case .review: return "Needs review"
        }
    }
    private var facts: String {
        var parts: [String] = []
        if entry.minutes > 0 { parts.append(Fmt.duration(minutes: entry.minutes)) }
        if let d = entry.distanceM, d > 0 { parts.append(PgText.km(d)) }
        if let w = entry.avgPower { parts.append("\(w) W avg") }
        if let h = entry.avgHR { parts.append("\(h) bpm avg") }
        if let d = entry.detail { parts.append(d) }
        if let r = entry.recorder { parts.append(r) }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: CySpace.s) {
                Image(systemName: entry.rideId != nil ? "bicycle" : (entry.isStrength ? "dumbbell" : "calendar"))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(entry.rideId != nil ? theme.endurance : (entry.isStrength ? theme.strength : theme.textSecondary))
                    .frame(width: 26)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(entry.date.dayAndDate) · \(stateWord)")
                        .font(.caption.weight(.semibold)).foregroundStyle(theme.textSecondary)
                    Text(entry.title)
                        .font(.system(.callout, design: .rounded).weight(.semibold)).foregroundStyle(theme.textPrimary)
                        .multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                    if !facts.isEmpty {
                        Text(facts).font(.caption).foregroundStyle(theme.textSecondary)
                            .multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: CySpace.s)
                if opens {
                    Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(theme.textTertiary).accessibilityHidden(true)
                }
            }
            .padding(.vertical, 9)
            .frame(minHeight: 56)
            .contentShape(Rectangle())
            Rectangle().fill(theme.separator).frame(height: 1).accessibilityHidden(true)
        }
        .accessibilityElement(children: .combine)
    }
}

/// A saved ride: what was recorded, with its source. The graph, the map and Delete stay on the full record.
struct ProgressRideV2Page: View {
    let ride: RideRecord
    @EnvironmentObject private var store: Store

    var body: some View {
        PgPage(title: "Ride", subtitle: "\(ride.start.dayAndDate) · recorded by \(ride.recordedBy)", id: "progressRidePage") {
            recorded
            source
            PgOverline(text: "MORE")
            NavigationLink { RideDetailView(ride: ride) } label: {
                PgLinkLabel(title: "Full ride record", sub: "Graph, route, plan against ride, delete")
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("progressRideFullRecord")
        }
    }

    @ViewBuilder private var recorded: some View {
        PgOverline(text: "RECORDED", trailing: ride.recorder == .health ? "Imported" : "Measured")
        PgFact(label: "Time", value: ride.durationS.asDuration)
        PgFact(label: "Distance", value: ride.distanceM > 0 ? PgText.km(ride.distanceM) : "—", note: ride.distanceM > 0 ? nil : "not recorded")
        PgFact(label: "Average power", value: ride.avgPower.map { "\($0) W" } ?? "—", note: powerNote, tag: ride.avgPower == nil ? "Unavailable" : "Measured")
        if let np = ride.normalizedPower { PgFact(label: "Normalized power", value: "\(np) W", tag: "Calculated") }
        if let b = ride.best20 { PgFact(label: "Best 20 minutes", value: "\(b) W", note: ride.best60.map { "best 60 min \($0) W" }, tag: "Measured") }
        PgFact(label: "Average heart rate", value: ride.avgHR.map { "\($0) bpm" } ?? "—", note: heartNote, tag: ride.avgHR == nil ? "Unavailable" : "Measured")
        PgFact(label: "Average cadence", value: ride.avgCadence.map { "\($0) rpm" } ?? "—", note: ride.avgCadence == nil ? "not recorded" : nil)
    }
    private var powerNote: String {
        if ride.avgPower == nil { return "no power meter on this ride" }
        return ride.powerVerified == true ? "power verified" : "power not verified"
    }
    private var heartNote: String? {
        if ride.avgHR == nil { return "no heart-rate source on this ride" }
        return ride.maxHR.map { "max \($0) bpm" }
    }

    @ViewBuilder private var source: some View {
        PgOverline(text: "SOURCE")
        PgFact(label: "Recorded by", value: ride.recordedBy)
        if !ride.sources.isEmpty { PgFact(label: "Sources", value: ride.sources.joined(separator: ", ")) }
        PgFact(label: "Samples", value: "\(ride.samples.count)", note: ride.samples.isEmpty ? "summary only, no graph" : "one per second")
    }
}

/// A logged strength session: the sets as logged. Editing and Delete stay on the full record.
struct ProgressSessionV2Page: View {
    let session: StrengthSession
    @EnvironmentObject private var store: Store

    var body: some View {
        PgPage(title: session.title, subtitle: "\(session.date.dayAndDate) · \(sourceText)", id: "progressSessionPage") {
            logged
            notes
            PgOverline(text: "MORE")
            NavigationLink { StrengthSessionDetail(session: session) } label: {
                PgLinkLabel(title: "Full session record", sub: "Every set, notes, edit, delete")
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("progressSessionFullRecord")
        }
    }
    private var sourceText: String { session.isImported ? session.source : (session.isDetailed ? "detailed log" : "quick log") }

    @ViewBuilder private var logged: some View {
        let units = store.settings.units
        PgOverline(text: "LOGGED", trailing: session.isImported ? "Imported" : "Logged by you")
        PgFact(label: "Time", value: session.minutes > 0 ? Fmt.duration(minutes: session.minutes) : "—", note: session.minutes > 0 ? nil : "not recorded")
        PgFact(label: "Effort", value: session.rpe.map { "RPE \($0)" } ?? "—", note: session.rpe == nil ? "not stated" : "as you rated it")
        if session.isDetailed {
            PgFact(label: "Sets", value: "\(session.setCount)", note: "\(session.exerciseCount) exercise\(session.exerciseCount == 1 ? "" : "s")")
            PgOverline(text: "EXERCISES", trailing: "As logged")
            ForEach(session.exercises ?? []) { e in
                PgFact(label: e.name, value: e.summary(units: units), note: e.skippedSets.map { "\($0) planned set\($0 == 1 ? "" : "s") skipped" })
            }
        } else {
            PgNote(text: "A quick log: counted as a session, with no sets to analyse.")
        }
    }

    @ViewBuilder private var notes: some View {
        if let skipped = session.skippedExercises, !skipped.isEmpty {
            PgNote(text: "Skipped, not counted: " + skipped.joined(separator: ", ") + ".")
        }
        if session.awaitingReview {
            PgNote(text: "Not counted until you confirm it on the full record.")
        }
    }
}

// MARK: - Endurance development

struct ProgressEnduranceV2Page: View {
    @EnvironmentObject private var store: Store
    @Environment(\.cyTheme) private var theme

    var body: some View {
        let buckets = TrendChartMath.buckets(store.ledger, riding: true, weeks: 13, now: Date())
        let best = ProgressGlance.best20Trend(store.rides)
        let e = ProgressDevelopment.endurance(buckets, best20: best, show: true)
        let a = ProgressAnalytics.cycling(rides: store.rides, period: .quarter, ftpW: store.profile.ftpKnown ? store.profile.ftpW : nil, hrZones: store.profile.hrZones)
        let z = store.pgZones
        let p = store.profile
        PgPage(title: "Endurance development", subtitle: "Cycling · the last 12 full weeks and this week", id: "progressEndurancePage") {
            performance(best)
            ridingTime(e)
            quarter(a)
            distribution(z.zones, z.unavailable)
            measurement(p)
            PgOverline(text: "MORE")
            PgRouteRow(title: "Records & history", sub: "Every recorded ride", route: ProgressRoute.history, id: "enduranceOpenHistory")
        }
    }

    @ViewBuilder private func performance(_ best: (recent: Int?, before: Int?)) -> some View {
        PgOverline(text: "PERFORMANCE", trailing: "20-minute power")
        if let r = best.recent {
            PgFigure(value: "\(r)", unit: "W")
            PgNote(text: "Best 20-minute power in the last 7 weeks, from recorded power samples.")
            PgFact(label: "Weeks 8 to 15 ago", value: best.before.map { "\($0) W" } ?? "—",
                   note: best.before == nil ? "no 20-minute effort with power then" : "best 20 minutes",
                   tag: best.before == nil ? "Unavailable" : "Measured")
        } else {
            PgFact(label: "20-minute power", value: "—", note: "needs a ride of 20 minutes or more recorded with a power meter",
                   tag: "Unavailable", id: "endurancePowerUnavailable")
        }
    }

    @ViewBuilder private func ridingTime(_ e: ProgressDevelopment.Endurance?) -> some View {
        PgOverline(text: "RIDING TIME", trailing: "Per week")
        if let e {
            PgFigure(value: clock(e.averageMinutes), unit: "a week")
            PgNote(text: ridingNote(e))
            PgWeekBars(values: e.weeks, color: theme.endurance, empty: theme.separator)
                .frame(height: 70).padding(.top, 6)
            HStack {
                Text(e.firstLabel)
                Spacer(minLength: 4)
                Text("this week is not finished")
                Spacer(minLength: 4)
                Text(e.lastLabel)
            }
            .font(.caption2).foregroundStyle(theme.textTertiary)
        } else {
            PgNote(text: "No riding time recorded in these weeks.", id: "enduranceNoRiding")
        }
    }
    private func ridingNote(_ e: ProgressDevelopment.Endurance) -> String {
        var t = "Average of the last \(e.fullWeeks) full week\(e.fullWeeks == 1 ? "" : "s"), from saved rides."
        if let d = e.direction { t += " " + d.text("\(e.fullWeeks) weeks") + "." }
        return t
    }

    @ViewBuilder private func quarter(_ a: CyclingAnalytics) -> some View {
        PgOverline(text: "LAST 3 MONTHS", trailing: "From saved rides")
        PgFact(label: "Rides", value: "\(a.rides)", note: "in \(a.consistency.active) of \(a.consistency.weeks) weeks")
        PgFact(label: "Time", value: Fmt.duration(minutes: a.minutes))
        PgFact(label: "Distance", value: a.distanceKm.map { String(format: "%.1f km", $0.value) } ?? "—",
               note: a.distanceKm == nil ? "no ride recorded a distance" : nil)
        PgFact(label: "Average power", value: a.avgPower.map { "\($0.value) W" } ?? "—",
               note: a.avgPower.map { "\($0.records) rides with a power meter" } ?? "no power measured",
               tag: a.avgPower == nil ? "Unavailable" : "Measured")
        PgFact(label: "Average heart rate", value: a.avgHR.map { "\($0.value) bpm" } ?? "—",
               note: a.avgHR.map { "\($0.records) rides with heart rate" } ?? "no heart rate measured",
               tag: a.avgHR == nil ? "Unavailable" : "Measured")
    }

    @ViewBuilder private func distribution(_ zones: ProgressDevelopment.Zones?, _ unavailable: ProgressDevelopment.ZonesUnavailable?) -> some View {
        PgOverline(text: "TRAINING DISTRIBUTION", trailing: "Last 3 months")
        if let zones {
            PgFact(label: zones.title, value: "\(zones.easyPercent) %", note: "in zones 1–2 · \(zones.hours) recorded",
                   tag: zones.fromRideTotals ? "Ride totals" : "Measured")
            PgZoneStrip(zones: zones).padding(.top, 8)
        } else {
            PgFact(label: "Time in zones", value: "—", note: unavailable?.text ?? "no rides in the last 3 months", tag: "Unavailable")
        }
        PgRouteRow(title: "Time in zones", sub: "Each zone, and what the zones are calculated from", route: ProgressRoute.zones, id: "enduranceOpenZones")
    }

    @ViewBuilder private func measurement(_ p: RiderProfile) -> some View {
        PgOverline(text: "MEASUREMENT")
        PgFact(label: "FTP", value: p.ftpValue.map { "\($0) W" } ?? "Unknown",
               note: p.ftpKnown ? nil : "rides use heart rate and effort until it is known", tag: p.ftpSource.title, id: "enduranceFTP")
        PgNote(text: p.ftpSourceText)
    }
    private func clock(_ minutes: Int) -> String {
        minutes >= 60 ? String(format: "%d h %02d", minutes / 60, minutes % 60) : "\(minutes) min"
    }
}

// MARK: - Strength development

struct ProgressStrengthV2Page: View {
    @EnvironmentObject private var store: Store
    @Environment(\.cyTheme) private var theme

    var body: some View {
        let units = store.settings.units
        let lifts = store.liftSummaries().filter { $0.latest != nil }.sorted { $0.topSets.count > $1.topSets.count }
        let main = ProgressDevelopment.strength(lifts) { AdaptationExplainer.kg($0, units) }
        let a = ProgressAnalytics.strength(sessions: store.strength, period: .quarter)
        let topSets = a.muscleCoverage.map(\.sets).max() ?? 1
        PgPage(title: "Strength development", subtitle: "Resistance training · logged sets", id: "progressStrengthPage") {
            progression(main, lifts)
            PgOverline(text: "ALL LIFTS", trailing: "First → latest")
            if lifts.isEmpty { PgNote(text: "No lifts with a logged weight yet.") }
            ForEach(Array(lifts.prefix(12))) { l in liftRow(l, units) }
            records(a)
            coverage(a, top: topSets)
            exposure(a)
            PgOverline(text: "MORE")
            PgRouteRow(title: "Records & history", sub: "Every logged session, with its sets", route: ProgressRoute.history, id: "strengthOpenHistory")
        }
    }

    @ViewBuilder private func progression(_ main: ProgressDevelopment.Strength?, _ lifts: [LiftSummary]) -> some View {
        let units = store.settings.units
        PgOverline(text: "PROGRESSION", trailing: "Most logged lift")
        if let m = main {
            Text(m.liftName).font(CyDyn.f(14.5, .semibold)).foregroundStyle(theme.textPrimary).padding(.top, 2)
            PgFigure(value: WeightFmt.number(m.latestKg, units), unit: WeightFmt.unit(units))
            PgNote(text: progressionNote(m))
            ForEach(Array(m.ranges.enumerated()), id: \.offset) { _, r in
                PgFact(label: r.title, value: r.from == r.to ? r.toText : "\(r.fromText) → \(r.toText)", note: r.note,
                       tag: r.title.hasPrefix("Estimated") ? "Estimated" : "Logged")
            }
            PgNote(text: "One lift, not your whole strength.")
        } else {
            PgNote(text: ProgressDevelopment.strengthPending(lifts: lifts, sessions: store.strength.count)
                         ?? "No strength sessions logged yet. A lift appears here after two logged sessions of the same exercise.", id: "strengthPending")
        }
    }
    private func progressionNote(_ m: ProgressDevelopment.Strength) -> String {
        var t = "Recorded top set \(m.latestText) · \(m.sessions) sessions. "
        if let d = m.direction { t += d.text("2 sessions") + "." } else { t += "Not enough sessions to compare yet." }
        return t
    }

    @ViewBuilder private func records(_ a: StrengthAnalytics) -> some View {
        PgOverline(text: "PERSONAL RECORDS", trailing: "All time")
        if a.records.isEmpty { PgNote(text: "Records appear from logged weighted sets. None yet.") }
        ForEach(a.records) { r in PgFact(label: r.kind, value: r.value, note: PgText.dayYear(r.date), tag: "Logged") }
    }

    @ViewBuilder private func coverage(_ a: StrengthAnalytics, top: Int) -> some View {
        PgOverline(text: "COVERAGE", trailing: "Last 3 months")
        if a.muscleCoverage.isEmpty {
            PgNote(text: "No logged sets with catalogue exercises in the last 3 months.")
        } else {
            PgNote(text: "Logged sets per muscle group, from the exercise catalogue's tags. Your own exercises without tags are not counted.")
            ForEach(Array(a.muscleCoverage.prefix(8).enumerated()), id: \.offset) { _, g in
                PgCountBar(label: g.group, count: g.sets, top: top, color: theme.strength)
            }
        }
    }

    @ViewBuilder private func exposure(_ a: StrengthAnalytics) -> some View {
        PgOverline(text: "TRAINING EXPOSURE", trailing: "Not capability")
        PgFact(label: "Sessions", value: "\(a.sessions)", note: "\(a.detailedSessions) detailed · \(a.sessions - a.detailedSessions) quick logs, participation only")
        PgFact(label: "Sets", value: "\(a.sets)", note: "\(a.reps) reps")
        PgFact(label: "Volume", value: a.tonnageKg.map { String(format: "%.0f kg", $0.value) } ?? "—",
               note: a.tonnageKg.map { "reps × weight over \($0.records) weighted sets" } ?? "no weighted sets logged")
    }

    @ViewBuilder private func liftRow(_ l: LiftSummary, _ units: AppSettings.Units) -> some View {
        if let last = l.latest {
            PgFact(label: l.name, value: "\(WeightFmt.text(last.weightKg, units)) × \(last.reps)", note: liftNote(l, units), tag: "Logged")
        }
    }
    private func liftNote(_ l: LiftSummary, _ units: AppSettings.Units) -> String {
        let n = l.topSets.count
        guard let first = l.topSets.first, let last = l.latest, n > 1 else { return "1 session" }
        var t = "\(n) sessions"
        if first.weightKg == last.weightKg && first.reps == last.reps { t += " · unchanged" }
        else { t += " · was \(WeightFmt.text(first.weightKg, units)) × \(first.reps)" }
        if l.e1RMTrendAvailable, let e = last.e1RM { t += " · est. 1RM \(WeightFmt.text(e, units))" }
        return t
    }
}

// MARK: - Training consistency

struct ProgressConsistencyV2Page: View {
    @EnvironmentObject private var store: Store
    @Environment(\.cyTheme) private var theme

    private struct Week: Identifiable {
        let id: Date
        var rides: Int
        var lifts: Int
        var planned: Int
        var plannedDone: Int
    }

    var body: some View {
        let riding = TrendChartMath.buckets(store.ledger, riding: true, weeks: 14, now: Date())
        let lifting = TrendChartMath.buckets(store.ledger, riding: false, weeks: 14, now: Date())
        let c = ProgressDevelopment.consistency(riding: store.pgShowRiding ? riding : [], lifting: store.pgShowLifting ? lifting : [])
        let weeks = rows(riding: riding, lifting: lifting)
        PgPage(title: "Training consistency", subtitle: "Participation, not performance · the last 14 weeks", id: "progressConsistencyPage") {
            PgOverline(text: "WEEKS WITH A SESSION")
            if let c {
                PgFigure(value: "\(c.active)", unit: "of \(c.total) weeks")
                PgNote(text: "A week counts when at least one ride or strength session was saved in it.")
            } else {
                PgNote(text: "Nothing recorded in the last 14 weeks.", id: "consistencyEmpty")
            }
            PgOverline(text: "WEEK BY WEEK", trailing: "Newest first")
            ForEach(weeks) { w in
                PgFact(label: "Week of \(PgText.day(w.id))", value: done(w),
                       note: w.planned > 0 ? "\(w.plannedDone) of \(w.planned) planned done" : "nothing planned")
            }
            PgOverline(text: "MORE")
            PgRouteRow(title: "Records & history", sub: "Every session behind these weeks", route: ProgressRoute.history, id: "consistencyOpenHistory")
        }
    }
    private func rows(riding: [WeekBucket], lifting: [WeekBucket]) -> [Week] {
        let l = Dictionary(lifting.map { ($0.start, $0) }, uniquingKeysWith: { a, _ in a })
        return riding.reversed().map { r in
            let s = l[r.start]
            return Week(id: r.start, rides: store.pgShowRiding ? r.sessions : 0, lifts: store.pgShowLifting ? (s?.sessions ?? 0) : 0,
                        planned: r.plannedSessions + (s?.plannedSessions ?? 0), plannedDone: r.plannedDone + (s?.plannedDone ?? 0))
        }
    }
    private func done(_ w: Week) -> String {
        if w.rides + w.lifts == 0 { return "No session" }
        var parts: [String] = []
        if w.rides > 0 { parts.append("\(w.rides) ride\(w.rides == 1 ? "" : "s")") }
        if w.lifts > 0 { parts.append("\(w.lifts) strength") }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Time in zones

struct ProgressZonesV2Page: View {
    @EnvironmentObject private var store: Store
    @Environment(\.cyTheme) private var theme

    var body: some View {
        let z = store.pgZones
        PgPage(title: z.zones?.title ?? "Time in zones", subtitle: "Cycling · the last 3 months", id: "progressZonesPage") {
            if let zones = z.zones {
                PgOverline(text: "EASY TIME", trailing: zones.fromRideTotals ? "Ride totals" : "Measured")
                PgFigure(value: "\(zones.easyPercent)", unit: "%")
                PgNote(text: "in zones 1–2 · \(zones.hours) recorded · \(zones.basis)")
                PgZoneStrip(zones: zones).padding(.top, 6)
                PgOverline(text: "EACH ZONE", trailing: "Share · recorded time")
                ForEach(Array(zones.shares.enumerated()), id: \.offset) { i, s in
                    PgFact(label: name(i, zones.kind), value: "\(s) %", note: i < zones.times.count ? zones.times[i] : nil)
                }
                if zones.fromRideTotals {
                    PgNote(text: "These rides have no per-second samples, so the zone totals saved with each ride are added up as they are. The zone limits are the ones in use when each ride was saved.", id: "zonesFromTotals")
                }
            } else {
                PgOverline(text: "NOT AVAILABLE", trailing: "Unavailable")
                PgNote(text: z.unavailable?.text ?? "No rides were saved in the last 3 months, so there is no time to place in zones.", id: "zonesUnavailable")
            }
            PgOverline(text: "CALCULATED FROM", trailing: "Your settings")
            PgZoneSettingsRows()
        }
    }
    private func name(_ i: Int, _ kind: ProgressDevelopment.ZoneSetting?) -> String {
        let names = kind == .power ? PowerZones.names : (kind == .heartRate ? HrZones.names : [])
        return i < names.count ? names[i] : "Z\(i + 1)"
    }
}
