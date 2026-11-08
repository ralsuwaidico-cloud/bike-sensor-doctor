import SwiftUI
import OSLog

// MARK: - Checkpoint C (owner 5 Nov): the Premium Home Dashboard and the Training Hub
// Home reads one `HomeDashboard` (HomeDashboardModel.swift) and shows it with the design-system cards; it no longer
// holds the Today execution card — that card, its actions and the missed-session row moved into the Training Hub,
// which the dock's centre button opens. Every card leads to an existing screen or says which checkpoint adds its page.

/// The dashboard page used by `HomeView` (which keeps the coach-sheet routing and the `perform` wiring).
struct HomeDashboardScreen: View {
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var recorder: RideRecorder
    let dash: HomeDashboard
    let today: HomeToday
    let coach: HomeCoachItem?
    var openTab: (Int) -> Void
    var openHub: () -> Void
    /// Correction pass (6 Nov): every card pushes its own page on Home's stack; prescriptions open as sheets.
    var open: (HomeRoute) -> Void
    var openPrescription: (Workout) -> Void
    var coachTapped: (HomeCoachItem) -> Void
    @Environment(\.dynamicTypeSize) private var dts

    var body: some View {
        VStack(alignment: .leading, spacing: CyTheme.sp3) {
            header
            if let r = dash.ring { ringCard(r) }
            sportTiles
            weekCard
            if let c = coach, today.showCoach, !recorder.isActive { coachCard(c) }
            lowerGrid
            if let r = dash.reminder { reminderCard(r) }
        }
    }

    // MARK: header — date, greeting, context; the avatar opens Profile
    private var header: some View {
        // B1 (6 Nov): the date and the avatar live in the (transparent) navigation bar, so the content never sits under
        // the status bar — the bar keeps the top safe area on every device and after every push/pop.
        VStack(alignment: .leading, spacing: 2) {
            Text(dash.header.greeting).font(CyType.largeTitle).foregroundStyle(CyTheme.ink).fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader).accessibilityIdentifier("homeGreeting")
            Text(dash.header.context).font(CyType.secondary).foregroundStyle(CyTheme.ink2).fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("homeContext")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: weekly ring → Training overview (counts from the ledger, nothing more)
    private func ringCard(_ r: HomeDashboard.Ring) -> some View {
        Button { open(.weekOverview(Date())) } label: {
            let id = CyTheme.recovery
            let ring = CyProgressRing(fraction: r.fraction, size: 84, lineWidth: 10, tint: id.tint, track: id.soft) {
                CyRingLabel(fraction: r.fraction, caption: "\(r.done) of \(r.planned)", tint: id.tint)
            }
            let text = VStack(alignment: .leading, spacing: 4) {
                CyCaption(text: "This week", color: id.tint.opacity(0.85))
                Text(r.planned == 0 ? "Nothing planned" : "\(r.done) of \(r.planned) sessions").font(CyType.numeralSmall).foregroundStyle(id.tint).fixedSize(horizontal: false, vertical: true)
                Text(r.sub).font(CyType.secondary).foregroundStyle(id.tint.opacity(0.9)).fixedSize(horizontal: false, vertical: true)
                if let n = r.countedNote { Text(n).font(CyType.captionSmall).foregroundStyle(CyTheme.ink3).fixedSize(horizontal: false, vertical: true) }
            }
            Group {
                if dts.isAccessibilitySize { VStack(alignment: .leading, spacing: 12) { ring; text } }
                else { HStack(spacing: 16) { ring; text.frame(maxWidth: .infinity, alignment: .leading); chevron } }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .cyCard(tinted: id.bg, radius: CyTheme.rHero)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("This week: \(r.done) of \(r.planned) planned sessions done, \(CyDesign.percentText(r.fraction)). \(r.sub).\(r.countedNote.map { " \($0)" } ?? "") Opens the weekly overview")
        .accessibilityIdentifier("cyHeroRing")
    }

    private var chevron: some View { Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(CyTheme.ink3).accessibilityHidden(true) }

    // MARK: sport tiles → Progress (its analytics pages are Checkpoint D; the tab exists today)
    @ViewBuilder private var sportTiles: some View {
        let tiles: [TileItem] = [dash.cycling.map { TileItem(id: "homeCycling", sport: .cycling, tile: $0) }, dash.strength.map { TileItem(id: "homeStrength", sport: .strength, tile: $0) }].compactMap { $0 }
        if !tiles.isEmpty {
            let layout = dts.isAccessibilitySize || tiles.count == 1 ? AnyLayout(VStackLayout(spacing: CyTheme.sp3)) : AnyLayout(HStackLayout(alignment: .top, spacing: CyTheme.sp3))
            layout {
                ForEach(tiles) { item in
                    Button { open(item.sport == .cycling ? .cycling : .strength) } label: {
                        CyMetricTile(title: item.sport == .cycling ? "Cycling" : "Strength", systemImage: "chevron.right", sport: item.sport, value: item.tile.value, unit: item.tile.unit, sub: item.tile.sub, tag: item.tile.tag) {
                            miniChart(item.sport, item.tile.series)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint(item.sport == .cycling ? "Opens the cycling summary" : "Opens the strength summary")
                    .accessibilityIdentifier(item.id)
                }
            }
        }
    }
    private struct TileItem: Identifiable { let id: String; let sport: CySport; let tile: HomeDashboard.Tile }
    @ViewBuilder private func miniChart(_ sport: CySport, _ series: [Double?]) -> some View {
        let id = CyTheme.identity(sport)
        let real = series.compactMap { $0 }
        if real.count >= 2 {
            if sport == .cycling {
                CySparkline(values: real, tint: id.tint, fill: id.mid).frame(height: 28)
            } else {
                HStack(alignment: .bottom, spacing: 3) {
                    ForEach(Array(series.enumerated()), id: \.offset) { _, v in
                        RoundedRectangle(cornerRadius: 2).fill(v == nil ? CyTheme.line2 : id.mid)
                            .frame(height: v.map { CGFloat(3 + 25 * ($0 / max(real.max() ?? 1, 1))) } ?? 3)
                    }
                }
                .frame(height: 28, alignment: .bottom)
            }
        } else {
            Text("Weekly chart after 2 weeks of activity").font(CyType.captionSmall).foregroundStyle(CyTheme.ink3).frame(height: 28, alignment: .bottomLeading)
        }
    }

    // MARK: week calendar — the shared day states; a day opens its session, an empty day opens Plan
    private var weekCard: some View {
        VStack(alignment: .leading, spacing: CyTheme.sp2) {
            HStack {
                Text(dash.weekTitle).font(CyType.caption).foregroundStyle(CyTheme.ink3)
                Spacer()
                Button { openTab(1) } label: { HStack(spacing: 2) { Text("Plan"); Image(systemName: "chevron.right").font(.caption2.weight(.bold)) }.font(CyType.secondary.weight(.semibold)).foregroundStyle(CyTheme.ink).cyMinTap() }
                    .buttonStyle(.plain).accessibilityLabel("Open Plan").accessibilityIdentifier("homeWeekPlan")
            }
            CyCalendarStrip(days: dash.days, idPrefix: "homeWeekDay", containerId: "homeWeek") { d in
                // A4 (6 Nov): one planned session → its prescription; one recorded session → the recording; anything
                // else (several sessions, rest, before the plan, nothing planned) → the day page with its explanation
                let cal = Calendar.current
                let date = cal.date(byAdding: .day, value: d.id, to: TrainingLedger.monday(of: Date(), calendar: cal)) ?? Date()
                let day = store.homeDayDetail(date)
                if day.items.count == 1, let item = day.items.first {
                    switch item.record {
                    case .ride(let id): open(.ride(id))
                    case .strength(let id): open(.log(id))
                    case .none: if let w = item.session?.workout { openPrescription(w) } else { open(.day(date)) }
                    }
                } else { open(.day(date)) }
            }
            legend
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cyCard()
    }
    private var legend: some View {
        let items: [(String, String, Color)] = [("—", "before this plan started", CyTheme.ink3), ("●", "done", CyTheme.recovery.mid), ("○", "planned", CyTheme.ink3), ("●", "missed", CyTheme.bad)]
        return HStack(spacing: 10) {
            ForEach(items.indices, id: \.self) { i in
                HStack(spacing: 3) { Text(items[i].0).foregroundStyle(items[i].2); Text(items[i].1).foregroundStyle(CyTheme.ink3) }.font(CyType.captionSmall).lineLimit(1).minimumScaleFactor(0.7)
            }
        }
        .accessibilityHidden(true)
    }

    // MARK: coach — the engine's own finding, first sentence; opening it never changes the plan
    private func coachCard(_ c: HomeCoachItem) -> some View {
        Button { coachTapped(c) } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    CyIconBox(systemName: "sparkles", sport: .insight)
                    CyCaption(text: "Coach", color: CyTheme.insight.tint)
                    Spacer()
                    Text("suggestion").font(CyType.captionSmall).foregroundStyle(CyTheme.insight.tint).padding(.horizontal, 7).padding(.vertical, 4).background(CyTheme.insight.bg, in: Capsule())
                }
                Text(c.title).font(CyType.bodyStrong).foregroundStyle(CyTheme.ink).fixedSize(horizontal: false, vertical: true).multilineTextAlignment(.leading)
                if let e = c.evidence { Text(e).font(CyType.secondary).foregroundStyle(CyTheme.ink2).fixedSize(horizontal: false, vertical: true).multilineTextAlignment(.leading) }
                HStack(spacing: 4) { Text(c.actionLabel ?? "Details"); Image(systemName: "chevron.right").font(.caption2.weight(.bold)) }
                    .font(CyType.secondary.weight(.semibold)).foregroundStyle(CyTheme.insight.tint).frame(minHeight: CyTheme.minTap)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .cyCard()
            .overlay(RoundedRectangle(cornerRadius: CyTheme.rCard, style: .continuous).stroke(CyTheme.insight.soft, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Coach: \(c.title). \(c.evidence ?? "") \(c.actionLabel ?? "Details")")
        .accessibilityIdentifier("homeCoachAction")
    }

    // MARK: recovery + goal
    @ViewBuilder private var lowerGrid: some View {
        let layout = dts.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: CyTheme.sp3)) : AnyLayout(HStackLayout(alignment: .top, spacing: CyTheme.sp3))
        layout {
            recoveryCard
            if let g = dash.goal { goalCard(g) }
        }
    }
    private var recoveryCard: some View {
        let id = CyTheme.recovery
        return Button { open(.recovery) } label: {
            VStack(alignment: .leading, spacing: 6) {
                CyCaption(text: "Recovery", color: id.tint.opacity(0.85))
                if dash.recovery.hasData {
                    ForEach(dash.recovery.readings, id: \.title) { r in
                        HStack(alignment: .firstTextBaseline, spacing: 3) {
                            Text(r.title).font(CyType.captionSmall).foregroundStyle(id.tint.opacity(0.85)); Spacer(minLength: 2)
                            Text(r.value).font(CyType.numeralSmall).monospacedDigit().foregroundStyle(id.tint); Text(r.unit).font(CyType.captionSmall).foregroundStyle(id.tint.opacity(0.8))
                        }
                    }
                    if let a = dash.recovery.adviceTitle { Text(a).font(CyType.captionSmall).foregroundStyle(CyTheme.ink).fixedSize(horizontal: false, vertical: true) }
                    Text("Apple Health · \(dash.recovery.readings.map(\.date).max()?.formatted(date: .abbreviated, time: .omitted) ?? "")" + (dash.recovery.fresh ? "" : " · older than a day")).font(CyType.captionSmall).foregroundStyle(dash.recovery.fresh ? CyTheme.ink3 : CyTheme.warn)
                } else {
                    Text(dash.recovery.emptyTitle).font(CyType.bodyStrong).foregroundStyle(CyTheme.ink)
                    Text(dash.recovery.emptySub + " ›").font(CyType.captionSmall).foregroundStyle(CyTheme.ink3).fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 120, alignment: .topLeading)
            .cyCard(tinted: id.bg)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(dash.recovery.hasData ? "Recovery: " + dash.recovery.readings.map { "\($0.title) \($0.value) \($0.unit)" }.joined(separator: ", ") + (dash.recovery.adviceTitle.map { ". \($0)" } ?? "") + (dash.recovery.fresh ? "" : ". Readings older than a day") + ". Opens Recovery" : "Recovery: no readings yet. Opens Recovery")
        .accessibilityIdentifier("homeRecovery")
    }
    private func goalCard(_ g: HomeDashboard.Goal) -> some View {
        let id = CyTheme.goal
        return Button { open(.goal) } label: {
            VStack(alignment: .leading, spacing: 6) {
                CyCaption(text: (g.isMain ? "★ Goal · " : "Goal · ") + g.title, color: id.tint)
                Text(g.measured).font(CyType.bodyStrong).foregroundStyle(CyTheme.ink).fixedSize(horizontal: false, vertical: true).multilineTextAlignment(.leading)
                if let n = g.next { Text(n + " ›").font(CyType.captionSmall).foregroundStyle(CyTheme.ink3).fixedSize(horizontal: false, vertical: true).multilineTextAlignment(.leading) }
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 120, alignment: .topLeading)
            .cyCard(tinted: id.bg)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(g.isMain ? "Main goal" : "Goal") \(g.title). \(g.measured). Opens Goal details")
        .accessibilityIdentifier("homeGoal-\(g.id.rawValue)")
    }

    // MARK: compact Today reminder → Training Hub
    private func reminderCard(_ r: HomeDashboard.Reminder) -> some View {
        Button(action: openHub) {
            HStack(spacing: CyTheme.sp3) {
                VStack(alignment: .leading, spacing: 2) {
                    CyCaption(text: "Today", color: CyTheme.recovery.tint)
                    Text(r.title).font(CyType.section).foregroundStyle(CyTheme.ink).fixedSize(horizontal: false, vertical: true).multilineTextAlignment(.leading)
                    Text(r.sub).font(CyType.secondary).foregroundStyle(CyTheme.ink2)
                }
                Spacer(minLength: 4)
                chevron
            }
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: CyTheme.minTap, alignment: .leading)
            .cyCard(tinted: CyTheme.recovery.bg)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Today: \(r.title). \(r.sub)")
        .accessibilityIdentifier("homeTodayReminder")
    }
}

// MARK: - Recovery (latest readings with source and date, or the empty state; history pages are Checkpoint E)
// HomeRecoveryView moved to RecoveryView.swift (Checkpoint E).

// MARK: - Goal details: what the goal tracks, what is measured so far, the next step (no promised outcome)
struct HomeGoalDetailView: View {
    let goal: HomeDashboard.Goal
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: CyTheme.sp3) {
                section("What this goal tracks", goal.detail)
                section("Measured so far", goal.measured)
                if let n = goal.next { section("Next step", n) }
                Text("Goal progress pages with trends arrive with Progress analytics (Checkpoint D).").font(CyType.captionSmall).foregroundStyle(CyTheme.ink3).padding(.horizontal, 4)
            }
            .padding(.horizontal, CyTheme.margin).padding(.vertical, CyTheme.sp3).padding(.bottom, CyTheme.dockClearance)
        }
        .background(CyTheme.canvas)
        .navigationTitle((goal.isMain ? "★ " : "") + "Goal · \(goal.title)").navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("homeGoalPage")
    }
    private func section(_ t: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            CyCaption(text: t, color: CyTheme.goal.tint)
            Text(body).font(CyType.body).foregroundStyle(CyTheme.ink).fixedSize(horizontal: false, vertical: true)
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading).cyCard()
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Training Hub: today's session(s) with the existing Today cards and routes, over the current tab
struct TrainingHubView: View {
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var device: DeviceLink
    @EnvironmentObject private var recorder: RideRecorder
    var perform: (HomeAction) -> Void
    var openTab: (Int) -> Void
    var otherSession: () -> Void
    var close: () -> Void
    @State private var why: Workout? = nil
    @State private var detail: Workout? = nil
    @State private var swap: Workout? = nil
    @State private var showAdjustments = false
    @Environment(\.dynamicTypeSize) private var dts

    var body: some View {
        let h = store.homeToday(recorderActive: recorder.isActive)
        let dash = store.homeDashboard(recorderActive: recorder.isActive)
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: CyTheme.sp3) {
                    // run 167: at accessibility sizes on an iPhone SE the full header pushed the first session's button below
                    // the fold — the large sizes get one short title line (the date is on Home) and the state line
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 2) {
                            if !dts.isAccessibilitySize { Text("TRAINING HUB").font(CyType.caption).foregroundStyle(CyTheme.ink3) }
                            Text(dts.isAccessibilitySize ? "Today" : "Today · \(dash.header.dateLine)").font(dts.isAccessibilitySize ? CyType.section : CyType.title).foregroundStyle(CyTheme.ink).accessibilityAddTraits(.isHeader)
                                .accessibilityLabel("Training hub, today, \(dash.header.dateLine)")
                            Text(stateLine(dash.hub)).font(dts.isAccessibilitySize ? CyType.captionSmall : CyType.secondary).foregroundStyle(CyTheme.ink2).accessibilityIdentifier("hubState")
                        }
                        Spacer()
                    }
                    .padding(.top, dts.isAccessibilitySize ? 0 : CyTheme.sp2)
                    if let c = h.caution { HomeCautionLine(caution: c) { perform(.reviewHealth) } }
                    todayCard(h)
                    if let m = h.missed, h.layoutShowsMissed {
                        HomeMissedRow(missed: m, more: h.moreMissed, todayFree: h.isRestOrFree, perform: perform, openPlan: { openTab(1) })
                    }
                    if let t = store.undoToast { UndoToastBar(toast: t).transition(.opacity) }
                    alsoToday(h)
                    optional(h)
                }
                .padding(.horizontal, CyTheme.margin)
                .padding(.bottom, CyTheme.dockClearance)     // B2 (6 Nov): the Optional card scrolls fully above the dock
                .animation(.easeOut(duration: 0.2), value: store.undoToast)
            }
            .background(CyTheme.canvas)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close", action: close).accessibilityIdentifier("hubClose") } }
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(isPresented: $showAdjustments) { AdjustmentsView() }
            .sheet(item: $why) { w in HomeWhySheet(workout: w) }
            .sheet(item: $detail) { w in WorkoutDetail(workout: w) }
            .sheet(item: $swap) { w in HomeSwapSheet(workout: w) }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("trainingHub")
        .onAppear { Logger(subsystem: "com.ralsuwaidico.bikecomputer", category: "hub").notice("training hub appeared") }
        .onDisappear { Logger(subsystem: "com.ralsuwaidico.bikecomputer", category: "hub").notice("training hub disappeared") }
    }

    private func stateLine(_ s: HomeDashboard.HubState) -> String {
        switch s {
        case .pending: return "One workout pending"
        case .active: return "Workout in progress"
        case .completed: return "Today's training is done"
        case .missed: return "A planned session was missed"
        case .rest: return "Rest day"
        case .multiple: return "More than one session today"
        case .hold: return "Training is paused"
        case .first: return "No plan yet"
        }
    }

    @ViewBuilder private func todayCard(_ h: HomeToday) -> some View {
        switch h.layout {
        case .first(let liftFirst): HomeFirstCard(liftFirst: liftFirst, mode: store.profile.trainingMode, perform: perform)
        case .hold(let hold): HomeHoldCard(hold: hold, perform: perform)
        case .freeSession: HomeFreeSessionCard(perform: perform)
        case .rest(let w): HomeRestCard(rest: w, hasMissed: h.missed != nil, perform: perform)
        case .single(let s):
            HomeSingleCard(session: s, elapsed: recorder.elapsedS, sensorLine: sensorLine(s),
                           perform: perform, open: { detail = s.workout }, why: { why = s.workout }, swap: { swap = s.workout },
                           seeChange: { showAdjustments = true }, openConnections: { openTab(4) })
        case .multi(let rows):
            HomeMultiCard(rows: rows, elapsed: recorder.elapsedS, perform: perform,
                          open: { w in detail = w }, why: { w in why = w }, swap: { w in swap = w })
        }
    }
    private func sensorLine(_ s: HomeSession) -> String? {
        guard s.isRide, s.status == .planned, device.remembered, store.settings.autoConnectBoard, !store.settings.phoneOnlyMode, device.state != .ready else { return nil }
        return "BikeComputer not connected — the phone can record with GPS"
    }

    /// "Also today" / "Remaining today": what else the week holds, from the same week model as Home.
    @ViewBuilder private func alsoToday(_ h: HomeToday) -> some View {
        let w = store.homeWeek()
        let done: Bool = { if case .single(let s) = h.layout { return [.done, .marked, .imported].contains(s.status) }; if case .multi(let ss) = h.layout { return ss.allSatisfy { [.done, .marked, .imported].contains($0.status) } }; return false }()
        VStack(alignment: .leading, spacing: 4) {
            CyCaption(text: done ? "Remaining today" : "Also today", color: CyTheme.ink3)
            Text(done ? "Everything planned is done." : "Nothing else planned.").font(CyType.bodyStrong).foregroundStyle(CyTheme.ink)
            Text(w.upNext.map { "Next: \($0)." } ?? "Nothing else is planned this week.").font(CyType.secondary).foregroundStyle(CyTheme.ink2).fixedSize(horizontal: false, vertical: true)
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading).cyCard()
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("hubAlsoToday")
    }

    /// Optional sessions: a free ride (Ride tab) or another session (the existing Train now chooser).
    @ViewBuilder private func optional(_ h: HomeToday) -> some View {
        if case .hold = h.layout {} else {
            VStack(alignment: .leading, spacing: 8) {
                CyCaption(text: "Optional", color: CyTheme.ink3)
                let layout = dts.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 8)) : AnyLayout(HStackLayout(spacing: 8))
                layout {
                    if store.profile.trainingMode != .strength { CySecondaryButton(title: "Free ride", systemImage: "bicycle") { close(); openTab(2) }.accessibilityIdentifier("hubFreeRide") }
                    CySecondaryButton(title: "Other session", systemImage: "plus") { otherSession() }.accessibilityIdentifier("hubOtherSession")
                }
            }
            .padding(16).frame(maxWidth: .infinity, alignment: .leading).cyCard()
        }
    }
}
