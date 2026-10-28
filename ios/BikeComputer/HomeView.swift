import SwiftUI

/// Home, Option B (coord/specs/HOME_B_SPEC.md v2.1). Three jobs: what am I doing today, what does the coach recommend,
/// am I making progress this week. Everything is read from `HomeToday` / `HomeCoachItem` / `HomeWeek` (HomeModel.swift);
/// every button goes through `perform`, which RootView owns, so the card and the tab-bar Train now reach the same place.
/// Moved off Home (spec "Moved items"): connections → Profile › Connections, next days → Plan, FTP → Progress,
/// last-week review and movement coverage → Progress / Plan, proposals and insights → the coach slot.
struct HomeView: View {
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var device: DeviceLink
    @EnvironmentObject private var recorder: RideRecorder
    @EnvironmentObject private var sync: ProfileSync
    @EnvironmentObject private var diag: DiagReportCenter
    @Binding var tab: Int
    var perform: (HomeAction) -> Void
    @State private var why: Workout? = nil
    @State private var detail: Workout? = nil
    @State private var swap: Workout? = nil
    @State private var coachSheet: HomeCoachSheet? = nil
    @State private var showAdjustments = false

    var body: some View {
        let h = store.homeToday(recorderActive: recorder.isActive)
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DS.m) {
                    HomeHeader(name: store.profile.name)
                    banner
                    if let c = h.caution { HomeCautionLine(caution: c) { perform(.reviewHealth) } }
                    todayCard(h)
                    if h.showCoach, !recorder.isActive, let item = store.homeCoach() { HomeCoachCard(item: item) { coachTapped(item) } }
                    if h.showWeek { weekCard(h) }
                }
                .padding(.horizontal, DS.l)
                .padding(.bottom, DS.l)
            }
            .background(Color(.systemGroupedBackground))
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(isPresented: $showAdjustments) { AdjustmentsView() }
            .sheet(item: $why) { w in HomeWhySheet(workout: w) }
            .sheet(item: $detail) { w in WorkoutDetail(workout: w) }
            .sheet(item: $swap) { w in HomeSwapSheet(workout: w) }
            .sheet(item: $coachSheet) { s in coachSheetView(s) }
        }
    }

    // MARK: banner — never more than one; the crash report wins (spec 2)
    @ViewBuilder private var banner: some View {
        if diag.unseenCrash != nil {
            DiagCrashBanner()
        } else if sync.state == .needsConfirmation, store.today?.kind.isRide == true {
            NavigationLink { SyncStatusView() } label: {
                HomeLineRow(icon: "exclamationmark.circle.fill", tint: BC.warn, text: "Phone and BikeComputer profiles differ — choose one")
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("homeSyncBanner")
        }
    }

    // MARK: TODAY
    @ViewBuilder private func todayCard(_ h: HomeToday) -> some View {
        switch h.layout {
        case .first(let liftFirst): HomeFirstCard(liftFirst: liftFirst, mode: store.profile.trainingMode, perform: perform)
        case .hold(let hold): HomeHoldCard(hold: hold, perform: perform)
        case .freeSession: HomeFreeSessionCard(perform: perform)
        case .rest(let w): HomeRestCard(rest: w, missed: h.missed, moreMissed: h.moreMissed, perform: perform, openPlan: { tab = 1 })
        case .single(let s):
            HomeSingleCard(session: s, missed: h.missed, moreMissed: h.moreMissed, elapsed: recorder.elapsedS, sensorLine: sensorLine(s),
                           perform: perform, open: { detail = s.workout }, why: { why = s.workout }, swap: { swap = s.workout },
                           seeChange: { showAdjustments = true }, openPlan: { tab = 1 }, openConnections: { tab = 4 })
        case .multi(let rows):
            HomeMultiCard(rows: rows, missed: h.missed, moreMissed: h.moreMissed, elapsed: recorder.elapsedS, perform: perform,
                          open: { w in detail = w }, why: { w in why = w }, swap: { w in swap = w }, openPlan: { tab = 1 })
        }
    }

    /// Rides only, and only when the rider uses a BikeComputer that is not connected now (P1-9: never a power-meter claim).
    private func sensorLine(_ s: HomeSession) -> String? {
        guard s.isRide, s.status == .planned, device.remembered, store.settings.autoConnectBoard, !store.settings.phoneOnlyMode, device.state != .ready else { return nil }
        return "BikeComputer not connected — the phone can record with GPS"
    }

    // MARK: THIS WEEK
    @ViewBuilder private func weekCard(_ h: HomeToday) -> some View {
        if case .hold = h.layout {
            HomeWeekPausedCard { tab = 1 }
        } else {
            HomeWeekCard(week: store.homeWeek()) { tab = 1 }
        }
    }

    // MARK: COACH actions (existing destinations only)
    private func coachTapped(_ item: HomeCoachItem) {
        switch item.source {
        case .adaptiveProposal(let id): if store.adaptiveProposals.contains(where: { $0.id == id }) { coachSheet = .adaptive(id) }
        case .hybridProposal(let id): coachSheet = .hybrid(id)
        case .adjustment: showAdjustments = true
        case .ftp: coachSheet = .ftp
        case .gap, .revise: tab = 1
        case .insight(let w): perform(.startStrength(w))
        case .rate(let t): coachSheet = .rate(t)
        }
    }
    @ViewBuilder private func coachSheetView(_ s: HomeCoachSheet) -> some View {
        switch s {
        case .adaptive(let id): HomeProposalSheet(adaptiveId: id, hybridId: nil)
        case .hybrid(let id): HomeProposalSheet(adaptiveId: nil, hybridId: id)
        case .ftp: HomeFTPSheet()
        case .rate(let t):
            switch t {
            case .ride(let id): CheckInFlow(target: .ride(id)) { coachSheet = nil }
            case .strength(let id): CheckInFlow(target: .strength(id)) { coachSheet = nil }
            }
        }
    }
}

enum HomeCoachSheet: Identifiable, Equatable {
    case adaptive(String), hybrid(String), ftp, rate(HomeCoachItem.CheckInTargetID)
    var id: String {
        switch self {
        case .adaptive(let i): return "a-\(i)"
        case .hybrid(let i): return "h-\(i)"
        case .ftp: return "ftp"
        case .rate(let t): switch t { case .ride(let u): return "r-\(u)"; case .strength(let u): return "s-\(u)" }
        }
    }
}

// MARK: - pieces

struct HomeHeader: View {
    let name: String
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(HomeText.longDate(Date()).uppercased()).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            Text(name.isEmpty ? "Hi" : "Hi \(name)").font(.title2.weight(.bold)).fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
        }
        .padding(.top, DS.s)
    }
}

/// A one-line tappable row (banner, sensor line, eased line): 44 pt tall (N9).
struct HomeLineRow: View {
    let icon: String
    let tint: Color
    let text: String
    var body: some View {
        HStack(spacing: DS.s) {
            Image(systemName: icon).foregroundStyle(tint).accessibilityHidden(true)
            Text(text).font(.subheadline).foregroundStyle(.primary).multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: DS.xs)
            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.secondary).accessibilityHidden(true)
        }
        .frame(minHeight: DS.minTap)
        .contentShape(Rectangle())
    }
}

struct HomeCautionLine: View {
    let caution: HomeCaution
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: DS.s) {
                Image(systemName: "heart.text.square").foregroundStyle(BC.stale).imageScale(.large).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(caution.title).font(.subheadline.weight(.semibold)).foregroundStyle(.primary).fixedSize(horizontal: false, vertical: true)
                    Text(caution.detail).font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").foregroundStyle(.secondary).accessibilityHidden(true)
            }
            .padding(DS.m)
            .frame(maxWidth: .infinity, minHeight: DS.minTap, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens the health check")
        .accessibilityIdentifier("homeCaution")
    }
}

/// The card frame every Home card uses.
struct HomeCardFrame<Content: View>: View {
    let eyebrow: String
    var chip: String? = nil
    var chipColor: Color = .secondary
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: DS.s) {
            HStack(alignment: .firstTextBaseline) {
                Eyebrow(t: eyebrow)
                Spacer(minLength: DS.s)
                if let chip { Pill(text: chip, color: chipColor) }
            }
            content
        }
        .padding(DS.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
    }
}

/// The one primary button of a card.
struct HomePrimaryButton: View {
    let action: HomeAction
    var isRide = false
    var elapsed: Int? = nil
    var identifier = "homePrimary"
    var compact = false
    var perform: (HomeAction) -> Void
    var body: some View {
        Button { perform(action) } label: {
            Text(action.label(isRide: isRide, elapsed: action == .openLiveRide ? elapsed : nil))
                .font(compact ? .subheadline.weight(.bold) : .headline)
                .lineLimit(2).minimumScaleFactor(0.8).multilineTextAlignment(.center)
                .frame(maxWidth: compact ? nil : .infinity, minHeight: DS.minTap)
                .padding(.horizontal, compact ? DS.m : 0)
        }
        .buttonStyle(.borderedProminent)
        .tint(action.prominent ? BC.accent : Color(.tertiarySystemFill))
        .foregroundStyle(action.prominent ? Color.black : Color.primary)
        .accessibilityHint(action.hint)
        .accessibilityIdentifier(identifier)
    }
}

private func chipColor(_ s: HomeStatus) -> Color {
    switch s {
    case .done, .marked, .imported: return BC.live
    case .inProgress: return BC.accent
    case .skipped, .missed: return BC.stale
    case .planned: return .secondary
    }
}

/// Planned sessions of a single-session day.
struct HomeSingleCard: View {
    let session: HomeSession
    let missed: HomeSession?
    let moreMissed: Int
    let elapsed: Int
    let sensorLine: String?
    var perform: (HomeAction) -> Void
    var open: () -> Void
    var why: () -> Void
    var swap: () -> Void
    var seeChange: () -> Void
    var openPlan: () -> Void
    var openConnections: () -> Void

    private var a11yTitle: String {
        let state = session.status.chip ?? "planned"
        return "Today's training: " + session.title + ", " + session.subtitle + ", " + state
    }

    var body: some View {
        HomeCardFrame(eyebrow: "Today's training", chip: session.status.chip, chipColor: chipColor(session.status)) {
            Button(action: open) {
                HStack(alignment: .top, spacing: DS.s) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(session.title).font(.title3.weight(.bold)).foregroundStyle(.primary).multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                        if !session.subtitle.isEmpty { Text(session.subtitle).font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
                    }
                    Spacer(minLength: DS.s)
                    Image(systemName: "chevron.right").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary).padding(.top, 4).accessibilityHidden(true)
                }
                .frame(minHeight: DS.minTap)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(a11yTitle)
            .accessibilityHint("Opens the session details")
            .accessibilityIdentifier("homeTodayTitle")
            if let a = session.adjustment {
                Button(action: seeChange) { HomeLineRow(icon: "wand.and.stars", tint: BC.accent, text: a) }
                    .buttonStyle(.plain).accessibilityIdentifier("homeAdjusted")
            }
            if let s = sensorLine {
                Button(action: openConnections) { HomeLineRow(icon: "antenna.radiowaves.left.and.right", tint: BC.stale, text: s) }
                    .buttonStyle(.plain).accessibilityIdentifier("homeSensorLine")
            }
            HomePrimaryButton(action: session.action, isRide: session.isRide, elapsed: elapsed, perform: perform)
            HStack(spacing: DS.s) {
                Button(action: why) { Text("Why this workout?").font(.subheadline.weight(.semibold)).foregroundStyle(BC.accent).frame(minHeight: DS.minTap).contentShape(Rectangle()) }
                    .buttonStyle(.plain).accessibilityIdentifier("homeWhy")
                Spacer(minLength: DS.s)
                HomeMoreMenu(session: session, perform: perform, edit: open, swap: swap)
            }
            if let m = missed { HomeMissedRow(missed: m, more: moreMissed, todayFree: false, perform: perform, openPlan: openPlan) }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("homeTodayCard")
    }
}

/// "More ⋯": Edit, Swap, Move to another day, Skip / Unskip (N10: only while the session can change).
struct HomeMoreMenu: View {
    @EnvironmentObject private var store: Store
    let session: HomeSession
    var perform: (HomeAction) -> Void
    var edit: () -> Void
    var swap: () -> Void
    var identifier = "homeMore"
    var body: some View {
        Menu {
            if session.status == .skipped {
                Button { store.setSkipped(session.id, false) } label: { Label("Unskip", systemImage: "arrow.uturn.backward") }
            }
            Button(action: edit) { Label("Details and edit", systemImage: "pencil") }
            if session.canChange {
                if session.status != .skipped { Button(action: swap) { Label("Swap", systemImage: "arrow.triangle.2.circlepath") } }
                Button { perform(.reschedule(session.id)) } label: { Label("Move to another day", systemImage: "calendar") }
                if session.status != .skipped {
                    Button(role: .destructive) { store.setSkipped(session.id, true) } label: { Label("Skip", systemImage: "forward.end") }
                }
            }
        } label: {
            HStack(spacing: 4) { Text("More"); Image(systemName: "ellipsis") }
                .font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                .frame(minWidth: DS.minTap, minHeight: DS.minTap)
                .contentShape(Rectangle())
        }
        .accessibilityLabel("More actions for \(session.title)")
        .accessibilityIdentifier(identifier)
    }
}

/// One missed session (most recent), with Move.
struct HomeMissedRow: View {
    let missed: HomeSession
    let more: Int
    let todayFree: Bool
    var perform: (HomeAction) -> Void
    var openPlan: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Divider()
            HStack(alignment: .center, spacing: DS.s) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Missed \(HomeText.weekday(missed.workout.date)) · \(missed.title)").font(.subheadline.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
                    Text(missed.subtitle).font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: DS.s)
                HomePrimaryButton(action: todayFree ? .moveToToday(missed.id) : .reschedule(missed.id), identifier: "homeMissedMove", compact: true, perform: perform)
            }
            if more > 0 {
                Button(action: openPlan) { Text("+\(more) more in Plan").font(.footnote.weight(.semibold)).foregroundStyle(BC.accent).frame(minHeight: DS.minTap).contentShape(Rectangle()) }
                    .buttonStyle(.plain).accessibilityIdentifier("homeMissedMore")
            }
        }
        .accessibilityElement(children: .contain)
    }
}

struct HomeMultiCard: View {
    let rows: [HomeSession]
    let missed: HomeSession?
    let moreMissed: Int
    let elapsed: Int
    var perform: (HomeAction) -> Void
    var open: (Workout) -> Void
    var why: (Workout) -> Void
    var swap: (Workout) -> Void
    var openPlan: () -> Void
    var body: some View {
        HomeCardFrame(eyebrow: "Today · \(rows.count) sessions") {
            ForEach(Array(rows.enumerated()), id: \.element.id) { pair in
                if pair.offset > 0 { Divider() }
                row(pair.element, index: pair.offset)
            }
            if let firstOpen = rows.first(where: { $0.status == .planned || $0.status == .inProgress }) ?? rows.first {
                Button { why(firstOpen.workout) } label: { Text("Why these sessions?").font(.subheadline.weight(.semibold)).foregroundStyle(BC.accent).frame(minHeight: DS.minTap).contentShape(Rectangle()) }
                    .buttonStyle(.plain).accessibilityIdentifier("homeWhy")
            }
            if let m = missed { HomeMissedRow(missed: m, more: moreMissed, todayFree: false, perform: perform, openPlan: openPlan) }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("homeTodayCard")
    }
    private func row(_ s: HomeSession, index: Int) -> some View {
        HStack(alignment: .center, spacing: DS.s) {
            Button { open(s.workout) } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(s.title).font(.headline).foregroundStyle(.primary).multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                    Text(s.subtitle + (s.status.chip.map { " · \($0)" } ?? "")).font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, minHeight: DS.minTap, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityHint("Opens the session details")
            HomePrimaryButton(action: s.action, isRide: s.isRide, elapsed: elapsed, identifier: "homeRow-\(index)", compact: true, perform: perform)
            HomeMoreMenu(session: s, perform: perform, edit: { open(s.workout) }, swap: { swap(s.workout) }, identifier: "homeRowMore-\(index)")
        }
    }
}

struct HomeRestCard: View {
    let rest: Workout?
    let missed: HomeSession?
    let moreMissed: Int
    var perform: (HomeAction) -> Void
    var openPlan: () -> Void
    var body: some View {
        HomeCardFrame(eyebrow: "Today's training", chip: "Rest day", chipColor: .secondary) {
            Text(rest?.kind == .recoveryDay ? "Recovery day" : "Rest day").font(.title3.weight(.bold)).accessibilityAddTraits(.isHeader)
            Text(rest?.kind == .recoveryDay ? "Light movement and an early night." : "No training planned today.").font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if let m = missed {
                HomeMissedRow(missed: m, more: moreMissed, todayFree: true, perform: perform, openPlan: openPlan)
            } else {
                HomePrimaryButton(action: .recoveryGuidance, perform: perform)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("homeTodayCard")
    }
}

struct HomeHoldCard: View {
    let hold: HomeHold
    var perform: (HomeAction) -> Void
    var body: some View {
        HomeCardFrame(eyebrow: "Today's training", chip: "Paused", chipColor: BC.warn) {
            Text(hold.title).font(.title3.weight(.bold)).fixedSize(horizontal: false, vertical: true).accessibilityAddTraits(.isHeader)
            Text(hold.detail).font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Button { perform(.reviewHealth) } label: {
                Text(hold.button).font(.headline).frame(maxWidth: .infinity, minHeight: DS.minTap)
            }
            .buttonStyle(.borderedProminent).tint(BC.accent).foregroundStyle(Color.black)
            .accessibilityHint("Opens the health check").accessibilityIdentifier("homePrimary")
            Button { perform(.holdInfo) } label: { Text("What this means").font(.subheadline.weight(.semibold)).foregroundStyle(BC.accent).frame(minHeight: DS.minTap).contentShape(Rectangle()) }
                .buttonStyle(.plain).accessibilityIdentifier("homeHoldInfo")
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("homeTodayCard")
    }
}

struct HomeFirstCard: View {
    let liftFirst: Bool
    let mode: TrainingMode
    var perform: (HomeAction) -> Void
    var body: some View {
        HomeCardFrame(eyebrow: "Get started") {
            Text("Build your first week").font(.title3.weight(.bold)).accessibilityAddTraits(.isHeader)
            Text("Tell Cyclift your days and time; it plans the week and adapts from what you log.").font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HomePrimaryButton(action: .createPlan, perform: perform)
            HStack(spacing: DS.l) {
                if liftFirst {
                    lift
                    if mode != .strength { ride }
                } else {
                    if mode != .strength { ride }
                    if mode != .cycling { lift }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("homeTodayCard")
    }
    private var ride: some View {
        Button { perform(.openRideScreen) } label: { Text("Just record a ride").font(.subheadline.weight(.semibold)).foregroundStyle(BC.accent).frame(minHeight: DS.minTap).contentShape(Rectangle()) }.buttonStyle(.plain).accessibilityIdentifier("homeFirstRide")
    }
    private var lift: some View {
        Button { perform(.quickLog) } label: { Text("Log a lift").font(.subheadline.weight(.semibold)).foregroundStyle(BC.accent).frame(minHeight: DS.minTap).contentShape(Rectangle()) }.buttonStyle(.plain).accessibilityIdentifier("homeFirstLift")
    }
}

struct HomeFreeSessionCard: View {
    var perform: (HomeAction) -> Void
    var body: some View {
        HomeCardFrame(eyebrow: "Today's training", chip: "In progress", chipColor: BC.accent) {
            Text("Strength session in progress").font(.title3.weight(.bold))
            HomePrimaryButton(action: .resumeStrength(nil), perform: perform)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("homeTodayCard")
    }
}

struct HomeCoachCard: View {
    let item: HomeCoachItem
    var action: () -> Void
    var body: some View {
        HomeCardFrame(eyebrow: "Coach") {
            Text(item.title).font(.headline).fixedSize(horizontal: false, vertical: true)
            if let e = item.evidence { Text(e).font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
            if let l = item.actionLabel {
                Button(action: action) {
                    HStack(spacing: 4) { Text(l); Image(systemName: "chevron.right").font(.caption.weight(.bold)) }
                        .font(.subheadline.weight(.semibold)).foregroundStyle(BC.accent)
                        .frame(minHeight: DS.minTap)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("homeCoachAction")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("homeCoach")
    }
}

struct HomeWeekCard: View {
    let week: HomeWeek
    var openPlan: () -> Void
    private var a11y: String {
        var parts: [String] = ["This week: " + week.line + "."]
        if let s = week.split { parts.append(s + ".") }
        if let n = week.upNext { parts.append("Up next " + n + ".") } else { parts.append("Nothing else planned this week.") }
        return parts.joined(separator: " ")
    }
    var body: some View {
        Button(action: openPlan) {
            HomeCardFrame(eyebrow: "This week") {
                HStack(alignment: .firstTextBaseline) {
                    Text(week.line).font(.headline).foregroundStyle(.primary).multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: DS.s)
                    Image(systemName: "chevron.right").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                }
                HomeWeekBar(week: week).accessibilityHidden(true)
                if let s = week.split { Text(s).font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
                Divider()
                Text(week.upNext.map { "Up next: \($0)" } ?? "Nothing else planned this week").font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(a11y)
        .accessibilityHint("Opens Plan")
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("homeWeek")
    }
}

/// One segment per planned session: done (accent), open (grey); a plain bar above 7.
struct HomeWeekBar: View {
    let week: HomeWeek
    var body: some View {
        let done = week.total.plannedDone, planned = week.total.planned
        if let n = week.segments {
            HStack(spacing: 4) {
                ForEach(0..<n, id: \.self) { i in Capsule().fill(i < done ? BC.accent : Color.secondary.opacity(0.25)).frame(height: 6) }
            }
        } else if planned > 0 {
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.secondary.opacity(0.25))
                    Capsule().fill(BC.accent).frame(width: g.size.width * CGFloat(min(done, planned)) / CGFloat(planned))
                }
            }.frame(height: 6)
        }
    }
}

struct HomeWeekPausedCard: View {
    var openPlan: () -> Void
    var body: some View {
        Button(action: openPlan) {
            HomeCardFrame(eyebrow: "This week") {
                Text("No sessions planned while paused").font(.subheadline).foregroundStyle(.secondary).frame(maxWidth: .infinity, minHeight: DS.minTap, alignment: .leading)
            }
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens Plan")
        .accessibilityIdentifier("homeWeek")
    }
}
