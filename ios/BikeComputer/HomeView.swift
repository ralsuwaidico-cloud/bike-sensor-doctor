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
                // UI refinement 28 Oct: Apple-Fitness-style sections (title outside the card), one card per job, the missed
                // session as its own quiet row under Today, and room under the last card for the tab bar's centre button
                VStack(alignment: .leading, spacing: 0) {
                    HomeHeader(name: store.profile.name)
                    VStack(alignment: .leading, spacing: DS.s) {
                        banner
                        if let c = h.caution { HomeCautionLine(caution: c) { perform(.reviewHealth) } }
                    }
                    HomeSectionTitle(text: "Today")
                    todayCard(h)
                    if let m = h.missed, h.layoutShowsMissed {
                        HomeMissedRow(missed: m, more: h.moreMissed, todayFree: h.isRestOrFree, perform: perform, openPlan: { tab = 1 })
                            .padding(.top, DS.s)
                    }
                    // the Undo bar for a Move / Skip / Do today sits in the page, under the card it changed
                    if let t = store.undoToast {
                        UndoToastBar(toast: t).padding(.top, DS.s).transition(.opacity)
                    }
                    if h.showCoach, !recorder.isActive, let item = store.homeCoach() {
                        HomeSectionTitle(text: "Coach")
                        HomeCoachCard(item: item) { coachTapped(item) }
                    }
                    if h.showWeek {
                        HomeSectionTitle(text: "This week")
                        weekCard(h)
                    }
                }
                .padding(.horizontal, DS.l)
                .padding(.bottom, 120)
                .animation(.easeOut(duration: 0.2), value: store.undoToast)      // the tab bar and its raised centre button never cover the last card
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
        case .rest(let w): HomeRestCard(rest: w, hasMissed: h.missed != nil, perform: perform)
        case .single(let s):
            HomeSingleCard(session: s, elapsed: recorder.elapsedS, sensorLine: sensorLine(s),
                           perform: perform, open: { detail = s.workout }, why: { why = s.workout }, swap: { swap = s.workout },
                           seeChange: { showAdjustments = true }, openConnections: { tab = 4 })
        case .multi(let rows):
            HomeMultiCard(rows: rows, elapsed: recorder.elapsedS, perform: perform,
                          open: { w in detail = w }, why: { w in why = w }, swap: { w in swap = w })
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

// MARK: - pieces (UI refinement 28 Oct: one card frame, one button system, sections outside the cards)

extension HomeToday {
    /// The missed-session row is shown under Today on training, rest and multi-session days — never during a health hold,
    /// on the first-run card or while a free strength session runs.
    var layoutShowsMissed: Bool {
        switch layout { case .single, .multi, .rest: return true; case .hold, .first, .freeSession: return false }
    }
    /// A rest day: a missed session can be moved to today itself.
    var isRestOrFree: Bool { if case .rest = layout { return true }; return false }
}

/// Section title above a card (Apple Fitness "Activity", "Workouts"): the card itself carries no eyebrow.
struct HomeSectionTitle: View {
    let text: String
    var body: some View {
        Text(text).font(.title3.weight(.bold)).foregroundStyle(.primary)
            .padding(.top, DS.xl).padding(.bottom, DS.s)
            .accessibilityAddTraits(.isHeader)
    }
}

struct HomeHeader: View {
    let name: String
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(HomeText.longDate(Date()).uppercased()).font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
            Text(name.isEmpty ? "Hi" : "Hi \(name)").font(.title.weight(.bold)).fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
        }
        .padding(.top, DS.s)
        .padding(.bottom, DS.xs)
    }
}

/// A one-line tappable row inside a card (eased by coach, sensor line): icon, text, chevron; 44 pt tall.
struct HomeLineRow: View {
    let icon: String
    let tint: Color
    let text: String
    var body: some View {
        HStack(spacing: DS.s) {
            Image(systemName: icon).font(.subheadline.weight(.semibold)).foregroundStyle(tint).frame(width: 20).accessibilityHidden(true)
            Text(text).font(.subheadline).foregroundStyle(.primary).multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: DS.xs)
            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary).accessibilityHidden(true)
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
            HStack(alignment: .center, spacing: DS.m) {
                Image(systemName: "heart.text.square.fill").font(.title3).foregroundStyle(BC.stale).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(caution.title).font(.subheadline.weight(.semibold)).foregroundStyle(.primary).fixedSize(horizontal: false, vertical: true)
                    Text(caution.detail).font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary).accessibilityHidden(true)
            }
            .padding(DS.l)
            .frame(maxWidth: .infinity, minHeight: DS.minTap, alignment: .leading)
            .background(BC.stale.opacity(0.12), in: RoundedRectangle(cornerRadius: 18))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens the health check")
        .accessibilityIdentifier("homeCaution")
        .padding(.top, DS.m)
    }
}

/// The card every Home section uses: one fill, one corner radius, one inner padding.
struct HomeCardFrame<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: DS.m) { content }
            .padding(DS.l)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20))
    }
}

/// Status chip (Done, Skipped, Paused …): small, tinted, never the loudest thing on the card.
struct HomeChip: View {
    let text: String
    let color: Color
    var body: some View {
        Text(text).font(.caption.weight(.semibold)).foregroundStyle(color)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(color.opacity(0.16), in: Capsule())
            .fixedSize()
    }
}

/// Title block of a session: sport icon, name, "40 min · Moderate", status chip.
struct HomeSessionTitle: View {
    let session: HomeSession
    var large = true
    private var icon: String {
        if session.isRide { return "bicycle" }
        switch session.workout.kind { case .strength: return "dumbbell.fill"; case .mobility: return "figure.yoga"; default: return "figure.mixed.cardio" }
    }
    @Environment(\.dynamicTypeSize) private var dts
    var body: some View {
        HStack(alignment: .top, spacing: DS.m) {
            // largest text: no icon tile (it crowded the title on small iPhones and only repeats the title)
            if !dts.isAccessibilitySize {
                Image(systemName: icon).font((large ? Font.title3 : .body).weight(.semibold)).foregroundStyle(BC.accent)
                    .frame(width: large ? 40 : 32, height: large ? 40 : 32)
                    .background(BC.accent.opacity(0.14), in: RoundedRectangle(cornerRadius: 10))
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(session.title).font(large ? .title2.weight(.bold) : .headline).foregroundStyle(.primary)
                    .multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                let subtitle = session.subtitle.isEmpty ? nil : Text(session.subtitle).font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                let chip = session.status.chip.map { HomeChip(text: $0, color: chipColor(session.status)) }
                // rows next to buttons (and large text): status chip on its own line so the subtitle wraps by words, not letters
                if large && dts <= .large {
                    HStack(spacing: DS.s) { subtitle; chip }
                } else {
                    subtitle
                    chip
                }
            }
            Spacer(minLength: 0)
        }
    }
}

func chipColor(_ s: HomeStatus) -> Color {
    switch s {
    case .done, .marked, .imported: return BC.live
    case .inProgress: return BC.accent
    case .skipped, .missed: return BC.stale
    case .planned: return .secondary
    }
}

/// Button system: `.primary` = full width, 50 pt, accent (or neutral for review actions); `.compact` = capsule, one line,
/// short label, 44 pt hit area — used in rows (multi-session, missed) so no label ever wraps to three lines.
enum HomeButtonKind { case primary, compact }

extension HomeAction {
    /// One or two words for compact row buttons; the full label stays the spoken name (VoiceOver).
    var shortLabel: String {
        switch self {
        case .startStrength, .openRideScreen: return "Start"
        case .resumeStrength: return "Resume"
        case .openLiveRide: return "Open ride"
        case .rideResults, .strengthResults: return "Results"
        case .addDetails: return "Add details"
        case .reschedule: return "Move"
        case .moveToToday: return "Do today"
        case .openDetails: return "Open"
        default: return label()
        }
    }
}

struct HomePrimaryButton: View {
    let action: HomeAction
    var isRide = false
    var elapsed: Int? = nil
    var identifier = "homePrimary"
    var kind: HomeButtonKind = .primary
    var perform: (HomeAction) -> Void
    private var full: String { action.label(isRide: isRide, elapsed: action == .openLiveRide ? elapsed : nil) }
    var body: some View {
        Button { perform(action) } label: {
            Group {
                if kind == .primary {
                    Text(full).font(.headline).lineLimit(2).multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity, minHeight: 50)
                } else {
                    Text(action.shortLabel).font(.subheadline.weight(.semibold)).lineLimit(1)
                        .padding(.horizontal, DS.l).frame(minHeight: 36)
                        .fixedSize()
                }
            }
            .foregroundStyle(action.prominent ? Color.black : Color.primary)
            .background(action.prominent ? BC.accent : Color(.tertiarySystemFill), in: Capsule())
            .frame(minHeight: DS.minTap)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(full)
        .accessibilityHint(action.hint)
        .accessibilityIdentifier(identifier)
    }
}

/// "Why this workout?" (left) and "More ⋯" (right): the supporting actions, quiet and evenly placed.
struct HomeSupportRow: View {
    let whyLabel: String
    var why: () -> Void
    let more: HomeMoreMenu
    @Environment(\.dynamicTypeSize) private var dts
    var body: some View {
        let whyButton = Button(action: why) {
            Label(whyLabel, systemImage: "questionmark.circle").font(.subheadline.weight(.semibold)).foregroundStyle(BC.accent)
                .frame(minHeight: DS.minTap).contentShape(Rectangle())
        }
        .buttonStyle(.plain).accessibilityIdentifier("homeWhy")
        // largest text: one link per line (side by side squeezed "Why this workout?" into a 4-line column; independent QA, run 111)
        if dts.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 0) { whyButton; more }
        } else {
            HStack(spacing: DS.s) { whyButton; Spacer(minLength: DS.s); more }
        }
    }
}

/// Today: one session.
struct HomeSingleCard: View {
    let session: HomeSession
    let elapsed: Int
    let sensorLine: String?
    var perform: (HomeAction) -> Void
    var open: () -> Void
    var why: () -> Void
    var swap: () -> Void
    var seeChange: () -> Void
    var openConnections: () -> Void

    private var a11yTitle: String { "Today's training: " + session.title + ", " + session.subtitle + ", " + (session.status.chip ?? "planned") }

    var body: some View {
        HomeCardFrame {
            Button(action: open) {
                HStack(alignment: .center, spacing: DS.s) {
                    HomeSessionTitle(session: session)
                    Image(systemName: "chevron.right").font(.subheadline.weight(.semibold)).foregroundStyle(.tertiary).accessibilityHidden(true)
                }
                .frame(minHeight: DS.minTap).contentShape(Rectangle())
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
            HomeSupportRow(whyLabel: "Why this workout?", why: why, more: HomeMoreMenu(session: session, perform: perform, edit: open, swap: swap))
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("homeTodayCard")
    }
}

/// "More ⋯": Details and edit, Swap, Move to another day, Skip / Unskip (N10: only while the session can change).
struct HomeMoreMenu: View {
    @EnvironmentObject private var store: Store
    let session: HomeSession
    var perform: (HomeAction) -> Void
    var edit: () -> Void
    var swap: () -> Void
    var identifier = "homeMore"
    var iconOnly = false
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
            Group {
                if iconOnly {
                    Image(systemName: "ellipsis").font(.subheadline.weight(.bold)).foregroundStyle(.primary)
                        .frame(width: 36, height: 36).background(Color(.tertiarySystemFill), in: Circle())
                } else {
                    HStack(spacing: 4) { Text("More"); Image(systemName: "ellipsis") }
                        .font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                }
            }
            .frame(minWidth: DS.minTap, minHeight: DS.minTap)
            .contentShape(Rectangle())
        }
        .accessibilityLabel("More actions for \(session.title)")
        .accessibilityIdentifier(identifier)
    }
}

/// The most recent missed session, under Today: a quiet row, one compact action. Never louder than today's workout.
struct HomeMissedRow: View {
    let missed: HomeSession
    let more: Int
    let todayFree: Bool
    var perform: (HomeAction) -> Void
    var openPlan: () -> Void
    @Environment(\.dynamicTypeSize) private var dts
    var body: some View {
        // from XX-large text the Move button goes under the text, so the session name wraps by words (run 111, XXXL)
        let layout = dts >= .xxLarge ? AnyLayout(VStackLayout(alignment: .leading, spacing: DS.s)) : AnyLayout(HStackLayout(alignment: .center, spacing: DS.m))
        layout {
            Button(action: openPlan) {
                HStack(alignment: .center, spacing: DS.m) {
                    Image(systemName: "clock.badge.exclamationmark").font(.body.weight(.semibold)).foregroundStyle(BC.stale).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Missed \(HomeText.weekday(missed.workout.date)) · \(missed.title)").font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                            .multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                        Text(missed.subtitle + (more > 0 ? " · +\(more) more in Plan" : "")).font(.footnote).foregroundStyle(.secondary)
                            .multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
                .frame(minHeight: DS.minTap).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityHint("Opens Plan")
            .accessibilityIdentifier("homeMissedMore")
            HomePrimaryButton(action: todayFree ? .moveToToday(missed.id) : .reschedule(missed.id), identifier: "homeMissedMove", kind: .compact, perform: perform)
        }
        .padding(.horizontal, DS.l).padding(.vertical, DS.s)
        .background(Color(.secondarySystemGroupedBackground).opacity(0.6), in: RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .contain)
    }
}

/// Today: two or more sessions. One row each: icon, name, details, one compact action and its own ⋯ menu.
struct HomeMultiCard: View {
    let rows: [HomeSession]
    let elapsed: Int
    var perform: (HomeAction) -> Void
    var open: (Workout) -> Void
    var why: (Workout) -> Void
    var swap: (Workout) -> Void
    @Environment(\.dynamicTypeSize) private var dts
    var body: some View {
        HomeCardFrame {
            Text("\(rows.count) sessions today").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
            ForEach(Array(rows.enumerated()), id: \.element.id) { pair in
                if pair.offset > 0 { Divider() }
                row(pair.element, index: pair.offset)
            }
            if let firstOpen = rows.first(where: { $0.status == .planned || $0.status == .inProgress }) ?? rows.first {
                Button { why(firstOpen.workout) } label: {
                    Label("Why these sessions?", systemImage: "questionmark.circle").font(.subheadline.weight(.semibold)).foregroundStyle(BC.accent)
                        .frame(minHeight: DS.minTap).contentShape(Rectangle())
                }
                .buttonStyle(.plain).accessibilityIdentifier("homeWhy")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("homeTodayCard")
    }
    @ViewBuilder private func row(_ s: HomeSession, index: Int) -> some View {
        let title = Button { open(s.workout) } label: {
            HomeSessionTitle(session: s, large: false).frame(maxWidth: .infinity, minHeight: DS.minTap, alignment: .leading).contentShape(Rectangle())
        }
        .buttonStyle(.plain).accessibilityElement(children: .combine).accessibilityHint("Opens the session details")
        let actions = HStack(spacing: DS.s) {
            HomePrimaryButton(action: s.action, isRide: s.isRide, elapsed: elapsed, identifier: "homeRow-\(index)", kind: .compact, perform: perform)
            HomeMoreMenu(session: s, perform: perform, edit: { open(s.workout) }, swap: { swap(s.workout) }, identifier: "homeRowMore-\(index)", iconOnly: true)
        }
        // from XX-large text the buttons go under the session text so the title and details keep the full width
        if dts >= .xxLarge {
            VStack(alignment: .leading, spacing: DS.s) { title; actions }
        } else {
            HStack(alignment: .center, spacing: DS.s) { title; actions }
        }
    }
}

struct HomeRestCard: View {
    let rest: Workout?
    let hasMissed: Bool
    var perform: (HomeAction) -> Void
    var body: some View {
        HomeCardFrame {
            HStack(alignment: .top, spacing: DS.m) {
                Image(systemName: rest?.kind == .recoveryDay ? "leaf.fill" : "moon.zzz.fill").font(.title3.weight(.semibold)).foregroundStyle(BC.accent)
                    .frame(width: 40, height: 40).background(BC.accent.opacity(0.14), in: RoundedRectangle(cornerRadius: 10)).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(rest?.kind == .recoveryDay ? "Recovery day" : "Rest day").font(.title2.weight(.bold)).accessibilityAddTraits(.isHeader)
                    Text(rest?.kind == .recoveryDay ? "Light movement and an early night." : "No training planned today.").font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            // with a missed session, its "Do today" (the row under this card) is today's one action
            if !hasMissed { HomePrimaryButton(action: .recoveryGuidance, perform: perform) }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("homeTodayCard")
    }
}

struct HomeHoldCard: View {
    let hold: HomeHold
    var perform: (HomeAction) -> Void
    @Environment(\.dynamicTypeSize) private var dts
    var body: some View {
        HomeCardFrame {
            if dts.isAccessibilitySize {
                // largest text: the title alone (the icon and the chip only repeat it) so Review health check stays on screen
                Text(hold.title).font(.title2.weight(.bold)).fixedSize(horizontal: false, vertical: true).accessibilityAddTraits(.isHeader)
            } else {
                HStack(alignment: .top, spacing: DS.m) {
                    Image(systemName: "cross.case.fill").font(.title3.weight(.semibold)).foregroundStyle(BC.warn)
                        .frame(width: 40, height: 40).background(BC.warn.opacity(0.14), in: RoundedRectangle(cornerRadius: 10)).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(hold.title).font(.title2.weight(.bold)).fixedSize(horizontal: false, vertical: true).accessibilityAddTraits(.isHeader)
                        HomeChip(text: "Training paused", color: BC.warn)
                    }
                }
            }
            Button { perform(.reviewHealth) } label: {
                Text(hold.button).font(.headline).foregroundStyle(Color.black).frame(maxWidth: .infinity, minHeight: 50)
                    .background(BC.accent, in: Capsule()).frame(minHeight: DS.minTap).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens the health check").accessibilityIdentifier("homePrimary")
            Text(hold.detail).font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Button { perform(.holdInfo) } label: {
                Label("What this means", systemImage: "info.circle").font(.subheadline.weight(.semibold)).foregroundStyle(BC.accent)
                    .frame(minHeight: DS.minTap).contentShape(Rectangle())
            }
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
        HomeCardFrame {
            Text("Build your first week").font(.title2.weight(.bold)).accessibilityAddTraits(.isHeader)
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
        Button { perform(.openRideScreen) } label: { Label("Just record a ride", systemImage: "bicycle").font(.subheadline.weight(.semibold)).foregroundStyle(BC.accent).frame(minHeight: DS.minTap).contentShape(Rectangle()) }.buttonStyle(.plain).accessibilityIdentifier("homeFirstRide")
    }
    private var lift: some View {
        Button { perform(.quickLog) } label: { Label("Log a lift", systemImage: "dumbbell") .font(.subheadline.weight(.semibold)).foregroundStyle(BC.accent).frame(minHeight: DS.minTap).contentShape(Rectangle()) }.buttonStyle(.plain).accessibilityIdentifier("homeFirstLift")
    }
}

struct HomeFreeSessionCard: View {
    var perform: (HomeAction) -> Void
    var body: some View {
        HomeCardFrame {
            HStack(spacing: DS.s) {
                Text("Strength session").font(.title2.weight(.bold))
                HomeChip(text: "In progress", color: BC.accent)
            }
            HomePrimaryButton(action: .resumeStrength(nil), perform: perform)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("homeTodayCard")
    }
}

/// Coach: one recommendation (WHOOP-style insight): what, why (the engine's own words), one action.
struct HomeCoachCard: View {
    let item: HomeCoachItem
    var action: () -> Void
    var body: some View {
        HomeCardFrame {
            HStack(alignment: .top, spacing: DS.m) {
                Image(systemName: "sparkles").font(.body.weight(.semibold)).foregroundStyle(BC.accent).frame(width: 24).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: DS.xs) {
                    Text(item.title).font(.body.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
                    if let e = item.evidence { Text(e).font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
                    if let l = item.actionLabel {
                        Button(action: action) {
                            HStack(spacing: 4) { Text(l); Image(systemName: "chevron.right").font(.caption.weight(.bold)) }
                                .font(.subheadline.weight(.semibold)).foregroundStyle(BC.accent)
                                .frame(minHeight: DS.minTap).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("homeCoachAction")
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("homeCoach")
    }
}

/// This week: the number first (Apple Fitness "Move 228/380"), the segmented bar, the per-sport split, then Up next.
struct HomeWeekCard: View {
    let week: HomeWeek
    var openPlan: () -> Void
    private var a11y: String {
        var parts: [String] = ["This week: " + week.line + "."]
        if let s = week.split { parts.append(s + ".") }
        if let t = week.targetLine { parts.append(t + ".") }
        if let n = week.upNext { parts.append("Up next " + n + ".") } else { parts.append("Nothing else scheduled this week.") }
        return parts.joined(separator: " ")
    }
    var body: some View {
        Button(action: openPlan) {
            HomeCardFrame {
                HStack(alignment: .firstTextBaseline, spacing: DS.s) {
                    if week.total.planned > 0 {
                        Text("\(week.total.plannedDone)").font(DS.number).foregroundStyle(BC.accent).monospacedDigit()
                        Text("of \(week.total.planned) scheduled \(week.total.planned == 1 ? "session" : "sessions") done").font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        Text(week.line).font(.headline).foregroundStyle(.primary).fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: DS.s)
                    Image(systemName: "chevron.right").font(.subheadline.weight(.semibold)).foregroundStyle(.tertiary)
                }
                HomeWeekBar(week: week).accessibilityHidden(true)
                let extras = [week.total.extra > 0 ? "+\(week.total.extra) extra" : nil, week.total.skipped > 0 ? "\(week.total.skipped) skipped" : nil].compactMap { $0 }
                if week.split != nil || !extras.isEmpty {
                    HStack(spacing: DS.l) {
                        if let r = week.riding, week.lifting != nil { sport("bicycle", "Rides", r) }
                        if let l = week.lifting, week.riding != nil { sport("dumbbell.fill", "Lifts", l) }
                        if !extras.isEmpty { Text(extras.joined(separator: " · ")).font(.footnote).foregroundStyle(.secondary) }
                    }
                }
                if let t = week.targetLine {
                    HStack(spacing: DS.s) {
                        Image(systemName: "target").font(.footnote).foregroundStyle(.secondary).accessibilityHidden(true)
                        Text(t).font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                    .accessibilityIdentifier("homeWeekTarget")
                }
                HStack(spacing: DS.s) {
                    Image(systemName: "calendar").font(.footnote).foregroundStyle(.secondary).accessibilityHidden(true)
                    Text(week.upNext.map { "Up next: \($0)" } ?? "Nothing else scheduled this week").font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(a11y)
        .accessibilityHint("Opens Plan")
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("homeWeek")
    }
    private func sport(_ icon: String, _ name: String, _ w: TrainingLedger.SportWeek) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon).font(.footnote).foregroundStyle(.secondary)
            Text("\(name) \(w.plannedDone)/\(w.planned)").font(.footnote.weight(.semibold)).foregroundStyle(.primary).monospacedDigit()
        }
    }
}

/// One segment per scheduled session: done (accent), open (grey); a plain bar above 7.
struct HomeWeekBar: View {
    let week: HomeWeek
    var body: some View {
        let done = week.total.plannedDone, planned = week.total.planned
        if let n = week.segments {
            HStack(spacing: 4) {
                ForEach(0..<n, id: \.self) { i in Capsule().fill(i < done ? BC.accent : Color.secondary.opacity(0.25)).frame(height: 8) }
            }
        } else if planned > 0 {
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.secondary.opacity(0.25))
                    Capsule().fill(BC.accent).frame(width: g.size.width * CGFloat(min(done, planned)) / CGFloat(planned))
                }
            }.frame(height: 8)
        }
    }
}

struct HomeWeekPausedCard: View {
    var openPlan: () -> Void
    var body: some View {
        Button(action: openPlan) {
            HomeCardFrame {
                Text("No sessions scheduled while training is paused").font(.subheadline).foregroundStyle(.secondary).frame(maxWidth: .infinity, minHeight: DS.minTap, alignment: .leading)
            }
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens Plan")
        .accessibilityIdentifier("homeWeek")
    }
}
