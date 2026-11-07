import SwiftUI

/// 0.4.0: first run shows the two-stage onboarding; afterwards Home / Plan / Ride / Progress / Profile with a custom
/// tab bar whose middle "Ride now" button is larger and raised. Tapping it only opens the Ride screen — recording
/// starts solely from the Start button there.
struct RootView: View {
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var recorder: RideRecorder
    @EnvironmentObject private var device: DeviceLink
    @EnvironmentObject private var watch: WatchLink
    @EnvironmentObject private var location: LocationService
    @EnvironmentObject private var hub: SensorHub
    @State private var tab = 0
    @State private var trainSheet: Store.TodayAction? = nil
    @State private var strengthWorkout: UUID? = nil
    @State private var resumeSession = false
    /// Home B: destinations opened by Home's buttons and the centre button (one router for both, spec P2-20).
    @State private var homeSheet: HomeAction? = nil
    @State private var holdSheet = false
    /// Checkpoint C: the Training Hub is a page over the current tab (closing returns to that tab with its scroll
    /// position); the centre button always opens it, a tab tap or Close dismisses it.
    @State private var showHub = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// A5: the local calendar day; when it changes (midnight, or back from the background) the centre button is
    /// re-evaluated and missing plan weeks are generated.
    @State private var day = Calendar.current.startOfDay(for: Date())
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        Group {
            if store.onboarded { tabs } else { OnboardingView() }
        }
        .onReceive(timer) { _ in hub.refresh(device: device, watch: watch, location: location, powerVerified: PowerTrust.meterVerified); recorder.phoneOnlyMode = store.settings.phoneOnlyMode; recorder.backgroundNoticeEnabled = store.settings.backgroundNotice
            let d = Calendar.current.startOfDay(for: Date()); if d != day { day = d; store.ensurePlan(); store.refreshRideSafety() } }
        // Checkpoint F: the Ride screen follows Ride settings › Display (Daylight / Night / Auto = the app appearance).
        .preferredColorScheme(store.onboarded && tab == 2 ? rideScheme : appScheme)
        .onChange(of: recorder.state) { old, s in
            idleTimer(s)
            if old != .running, old != .paused, s == .running, store.settings.enabledConnections.contains("watch") { watch.startWatchWorkout() }
        }
        .onAppear { device.autoConnect = store.settings.autoConnectBoard }
    }

    private var tabs: some View {
        VStack(spacing: 0) {
            // all five stay alive (like TabView) so navigation and scroll positions survive switching
            ZStack {
                HomeView(tab: $tab, perform: perform, openHub: { openHub() }).tabPage(0, tab)
                PlanView().tabPage(1, tab)
                RideTabView().tabPage(2, tab)
                ProgressTabView().tabPage(3, tab)
                ProfileTabView().tabPage(4, tab)
                if showHub {
                    TrainingHubView(perform: perform, openTab: { showHub = false; tab = $0 }, otherSession: { trainSheet = store.todayAction() }, close: { showHub = false })
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .zIndex(1)
                }
            }
            .onChange(of: tab) { _, _ in showHub = false }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // Checkpoint B (owner 4 Nov): the floating Liquid Dock replaces the fixed bar. It is a bottom safe-area inset,
            // so scrollable content ends above it and scrolls under its translucent capsule; the destinations, the
            // centre button's routing and its labels are unchanged.
            // Checkpoint F (owner 7 Nov, RA-01): while a ride is being recorded or paused the Ride screen owns the bottom of
            // the display — the dock is removed (not just hidden) so the coach card and the controls are never covered.
            .safeAreaInset(edge: .bottom, spacing: 0) { if !rideOwnsBottom { dock.padding(.bottom, 8) } }
            // Run 157: a page whose content lives in its own NavigationStack (Plan, Progress, Profile, Home) does not take
            // the inset above for its scroll content, so Plan's last row ended under the dock. Scroll-content margins
            // reach every scroll view in the subtree; Ride (no scroll view) is placed by the safe-area inset.
            .contentMargins(.bottom, 80, for: .scrollContent)
            .undoSnackbar(hidden: showHub)      // Checkpoint C: the hub shows the Undo bar inline under the card it changed
        }
        .ignoresSafeArea(.keyboard)
        .tint(BC.accent)
        .sheet(item: $trainSheet) { a in TrainNowSheet(action: a, openRide: { tab = 2 }, openStrength: { strengthWorkout = $0.id }) }
        .sheet(item: $strengthWorkout) { id in StrengthWorkoutScreen(workoutId: id) }
        .fullScreenCover(isPresented: $resumeSession) { StrengthSessionView() }
        .sheet(item: $homeSheet) { a in homeSheetView(a) }
        .sheet(isPresented: $holdSheet) { HealthHoldSheet() }
    }

    /// Performs a Home action: the card's buttons and the centre button share it, so both reach the same destination.
    private func perform(_ a: HomeAction) {
        switch a {
        case .startStrength(let id): strengthWorkout = id
        case .openRideScreen, .openLiveRide: tab = 2
        case .resumeStrength(let id):
            if let id { strengthWorkout = id } else { resumeSession = true }
        case .moveToToday(let id): _ = store.reschedule(id, to: Date())
        case .holdInfo: holdSheet = true
        default: homeSheet = a
        }
    }

    @ViewBuilder private func homeSheetView(_ a: HomeAction) -> some View {
        switch a {
        case .rideResults(let id):
            if let r = store.rides.first(where: { $0.id == id }) { HomeSheetWrap(title: "Ride") { RideDetailView(ride: r) } }
        case .strengthResults(let id):
            if let s = store.strength.first(where: { $0.id == id }) { HomeSheetWrap(title: "Strength") { StrengthSessionDetail(session: s) } }
        case .addDetails(let id):
            if let w = store.plan.first(where: { $0.id == id }) {
                if w.kind.isRide { RideDurationSheet(workoutId: id) }
                else { DetailedStrengthLogSheet(date: w.date, presetFocus: w.strengthFocus ?? .custom, workoutId: w.id) }
            }
        case .reschedule(let id): RescheduleSheet(workoutId: id)
        case .openDetails(let id):
            if let w = store.plan.first(where: { $0.id == id }) { WorkoutDetail(workout: w) }
        case .recoveryGuidance: RecoveryGuidanceSheet()
        case .reviewHealth: HealthCheckSheet()
        case .createPlan: HybridPlanEditor(asSheet: true)
        case .quickLog: QuickStrengthLogSheet()
        default: EmptyView()
        }
    }

    /// The dock reads today's action (the same `todayAction` the old bar used) and the missed-session flag from Home's
    /// model; it never decides a destination — `centreTapped` does, exactly as before.
    /// RA-01: the dock leaves while the Ride tab is showing a recorded or paused ride.
    private var appScheme: ColorScheme? { store.settings.appearance == .light ? .light : store.settings.appearance == .dark ? .dark : nil }
    private var rideScheme: ColorScheme? { store.settings.rideDisplay == .daylight ? .light : store.settings.rideDisplay == .night ? .dark : appScheme }
    private var rideOwnsBottom: Bool { tab == 2 && recorder.isActive }
    private var dock: some View {
        let action = store.todayAction(now: max(Date(), day))
        let copy = RideTabBar.centreCopy(recording: recorder.isActive, action: action)
        let missed = store.homeToday(recorderActive: recorder.isActive).missed != nil
        return CyLiquidDock(selection: $tab, state: CyCentreState.from(action: action, recording: recorder.isActive), missed: missed,
                            centreIcon: copy.icon, centreLabel: copy.label, centreHint: copy.hint, onCentre: centreTapped)
    }

    /// Checkpoint C (owner-approved prototype §2.2): the centre button always opens the Training Hub, whose card carries
    /// today's Start / Resume / Results / Why / More with the same routes as before. While a ride is being recorded the
    /// button opens the Ride screen (the dock is the ride's own control then). Tapping it with the hub open closes it.
    private func centreTapped() {
        if recorder.isActive { tab = 2; return }
        if showHub { showHub = false } else { openHub() }
    }
    private func openHub() {
        withAnimation(CyMotion.animation(0.22, reduce: reduceMotion)) { showHub = true }
    }

    /// The pre-Checkpoint-C routing (build 161): kept as the reference for what each hub action reaches.
    private func centreTappedDirect() {
        switch store.homeToday(recorderActive: recorder.isActive).centre {
        case .hold: holdSheet = true
        case .perform(let a): perform(a)
        case .sheet:
            let a = store.todayAction()
            switch a {
            case .ride: tab = 2
            case .train(let w): strengthWorkout = w.id
            case .inProgress: if let id = store.activeSession?.workoutId { strengthWorkout = id } else { resumeSession = true }
            case .healthHold: holdSheet = true
            case .choose, .rest, .doneToday: trainSheet = a
            }
        }
    }

    private func idleTimer(_ s: RideRecorder.State) {
        let active = s == .running || s == .paused
        UIApplication.shared.isIdleTimerDisabled = store.settings.keepScreenOn && active
    }
}

/// The pre-Checkpoint-B fixed bar. No longer shown (RootView uses CyLiquidDock); kept for its centre copy and as the
/// rollback reference for build 153.
struct RideTabBar: View {
    @Binding var selected: Int
    let recording: Bool
    var action: Store.TodayAction = .rest
    var onCentre: (() -> Void)? = nil
    @Environment(\.dynamicTypeSize) private var dts

    /// Icon and label from today's scheduled activities (local calendar date). "Ride now" only on a cycling day.
    private var centre: (icon: String, label: String, hint: String) { Self.centreCopy(recording: recording, action: action) }
    static func centreCopy(recording: Bool, action: Store.TodayAction) -> (icon: String, label: String, hint: String) {
        if recording { return ("bicycle", "Riding", "Ride in progress, open Ride") }
        switch action {
        case .ride: return ("bicycle", "Ride now", "Ride now, open the Ride screen")
        case .train: return ("dumbbell.fill", "Train now", "Train now, open today's strength workout")
        case .choose: return ("figure.mixed.cardio", "Train now", "Train now, choose between today's ride and strength session")
        case .inProgress: return ("dumbbell.fill", "In progress", "Strength workout in progress, resume it")
        case .doneToday: return ("checkmark", "Done today", "Today's training is done, see the next step")
        case .rest: return ("dumbbell.fill", "Train now", "Rest day, optional session")
        // owner 29 Oct: while training is paused the button looks paused (neutral, health icon, "Paused") and still only
        // opens the hold sheet (health guidance) — it never starts training
        case .healthHold: return ("cross.case.fill", "Paused", "Training paused by your health check, opens what this means")
        }
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 0) {
            item(0, "Home", "house.fill")
            item(1, "Plan", "calendar")
            rideButton
            item(3, "Progress", "chart.xyaxis.line")
            item(4, "Profile", "person.crop.circle")
        }
        .padding(.horizontal, 6)
        .padding(.top, 6)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
        // like the system tab bar: labels stop growing at xxLarge; long-press shows the large content viewer
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
    }

    private func item(_ i: Int, _ title: String, _ icon: String) -> some View {
        Button { selected = i } label: {
            VStack(spacing: 3) {
                Image(systemName: icon).font(.system(size: 20, weight: .medium))
                Text(title).font(.caption2).lineLimit(1)
            }
            .frame(maxWidth: .infinity, minHeight: 48).padding(.vertical, 2)
            .contentShape(Rectangle())
            .foregroundStyle(selected == i ? BC.accent : Color.secondary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title).accessibilityAddTraits(selected == i ? [.isSelected, .isButton] : .isButton)
        .accessibilityShowsLargeContentViewer { Label(title, systemImage: icon) }
    }

    private var paused: Bool { !recording && action == .healthHold }

    private var rideButton: some View {
        let c = centre
        return Button { if let onCentre, !recording { onCentre() } else { selected = 2 } } label: {
            VStack(spacing: 3) {
                ZStack {
                    Circle().fill(paused ? Color(.systemGray5) : recording ? BC.live : BC.accent).frame(width: 58, height: 58).shadow(color: .black.opacity(0.18), radius: 6, y: 3)
                        .overlay(Circle().stroke(paused ? BC.warn.opacity(0.6) : Color.clear, lineWidth: 1.5))
                    Image(systemName: c.icon).font(.system(size: paused ? 22 : 26, weight: .bold)).foregroundStyle(paused ? BC.warn : .white)
                }
                .overlay(Circle().stroke(selected == 2 ? Color.primary.opacity(0.35) : Color.clear, lineWidth: 2))
                .offset(y: -14)
                Text(c.label).font(.caption2.weight(.bold)).foregroundStyle(selected == 2 ? BC.accent : .secondary).offset(y: -12).lineLimit(1).minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(c.hint)
        .accessibilityIdentifier("centreButton")
    }
}

private extension View {
    /// One tab's page. The container identifier "tabPage-<i>" lets the layout audit look at the visible page only (the hidden
    /// pages stay alive and, in XCUITest snapshots, still report their frames — run 93 counted Plan's buttons on Connections).
    func tabPage(_ i: Int, _ selected: Int) -> some View { opacity(i == selected ? 1 : 0).allowsHitTesting(i == selected).accessibilityElement(children: .contain).accessibilityIdentifier("tabPage-\(i)").accessibilityHidden(i != selected).zIndex(i == selected ? 1 : 0) }
}

struct StatusRow: View {
    let title: String
    let ok: Bool
    var body: some View {
        HStack {
            Text(title); Spacer()
            Image(systemName: ok ? "checkmark.circle.fill" : "xmark.circle").foregroundStyle(ok ? .green : .secondary).accessibilityLabel(ok ? "Yes" : "No")
        }
    }
}
