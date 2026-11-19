import SwiftUI
import OSLog

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
    /// Redesign: false = the compact Train panel, true = the full Hub. Reset whenever the Hub opens.
    @State private var hubExpanded = false
    @State private var cyclingDemo = false
    /// Redesign: the compact panel's Strength shortcut (Shell/CyStrengthPicker.swift).
    @State private var strengthPicker = false
    /// Rest, Undo and the facts the Train ball needs that are not in the store (a save not confirmed, a session
    /// restored after the app ended). The same object the recorder uses — not a second session.
    @ObservedObject private var trainMemory = CyRecorderMemory.shared
    /// The device's bottom safe-area inset, read from the window (Navigation v1.2 places the dock from the screen's bottom edge).
    @State private var deviceBottom: CGFloat = 34
    @State private var lastCentreTap = Date.distantPast
    private let hubLog = Logger(subsystem: "com.ralsuwaidico.bikecomputer", category: "hub")
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// A5: the local calendar day; when it changes (midnight, or back from the background) the centre button is
    /// re-evaluated and missing plan weeks are generated.
    @State private var day = Calendar.current.startOfDay(for: Date())
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        Group {
            // E1: an unreadable or newer store is never shown as "no athlete" (which would start onboarding and write)
            if !store.storage.isWritable { StorageRecoveryView() } else if store.onboarded { tabs } else if CyProduct.redesign { OnboardingV34View() } else { OnboardingView() }
        }
        // E1: what the launch found (records set aside, a restored copy) and any write that is failing are said on every
        // screen, not only in Settings. Nothing is shown when storage is healthy.
        .safeAreaInset(edge: .top, spacing: 0) { StorageBanner() }
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
                Group {
                    if CyProduct.redesign { PlanV2Host() }          // Plan v2.0, schedule-first (Redesign/PlanV2Host.swift)
                    else { PlanView(perform: perform) }
                }.tabPage(1, tab)
                RideTabView().tabPage(2, tab)
                ProgressTabView().tabPage(3, tab)
                Group {
                    if CyProduct.redesign { CyProfileLanding(onBack: { tab = 0 }) }      // Profile v2.0; reached from the Home avatar only
                    else { ProfileTabView() }
                }.tabPage(4, tab)
                if showHub {
                    // Run 200 (HubTapReliabilityTests, 4 of 48 cycles): the hub opened every time, but a Close tapped while the
                    // panel was still sliding in landed on the stale frame and missed, so the hub stayed open. The hub now
                    // fades in place — its controls have their final frames from the first frame — and closes without an
                    // animation, so no tap can hit a moving control. Root cause, not a retry.
                    // Run 206 (quick, SE AX3) and run 204: in 3–4 of 48 cycles the hub's Close vanished while the `trainingHub`
                    // element stayed — the signature of a view removed while its insertion transition was still running
                    // (a Close tapped within ~0.2 s of opening). The hub is now inserted and removed with NO transition and
                    // NO animation at all: its controls have final frames from the first frame and removal is immediate,
                    // whatever the timing of the taps.
                    if CyProduct.redesign && !hubExpanded {
                        // Training Hub v1.4: the compact panel first (Shell/CyTrainPanel.swift); "All training" expands it
                        // into the full Hub below. Same no-animation rule as the Hub (runs 200–206).
                        ZStack(alignment: .bottom) {
                            Color.black.opacity(0.45).ignoresSafeArea()
                                .contentShape(Rectangle()).onTapGesture { closeHub() }
                                .accessibilityHidden(true)
                            CyTrainPanel(perform: { a in closeHub(); perform(a) },
                                         freeRide: { closeHub(); openRide() },
                                         strength: { closeHub(); strengthPicker = true },
                                         expand: { var t = Transaction(); t.disablesAnimations = true; withTransaction(t) { hubExpanded = true } },
                                         close: { closeHub() })
                                .padding(.bottom, 8)
                        }
                        .transition(.identity)
                        .zIndex(1)
                    } else {
                    TrainingHubView(perform: perform, openTab: { showHub = false; tab = $0 }, otherSession: { trainSheet = store.todayAction() }, close: { closeHub() })
                        .transition(.identity)
                        .zIndex(1)
                    }
                }
            }
            .onChange(of: tab) { _, _ in showHub = false }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // Checkpoint B (owner 4 Nov): the floating Liquid Dock replaces the fixed bar. It is a bottom safe-area inset,
            // so scrollable content ends above it and scrolls under its translucent capsule; the destinations, the
            // centre button's routing and its labels are unchanged.
            // Checkpoint F (owner 7 Nov, RA-01): while a ride is being recorded or paused the Ride screen owns the bottom of
            // the display — the dock is removed (not just hidden) so the coach card and the controls are never covered.
            // Navigation v1.2 (sheet F1): in the redesign the Train ball sits 34 pt above the bottom of the screen (16 pt
            // without a home indicator); it was 18 pt too high. The production dock keeps its 8 pt.
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if !rideOwnsBottom {
                    dock.padding(.bottom, CyProduct.redesign ? CyCradleMetrics.dockBottomPadding(deviceBottomInset: deviceBottom) : 8)
                        // Owner's iPhone review of build 4 (18 Nov 2026): page content showed through under the dock and looked
                        // obscured. In the redesign the page now fades into its own background just above the dock and is not
                        // visible beneath it; every page still ends above the dock (see the scroll margins below).
                        .background(alignment: .bottom) { if CyProduct.redesign { CyDockBackdrop() } }
                }
            }
            .environment(\.cyDeviceBottomInset, deviceBottom)
            .task {
                guard CyProduct.redesign else { return }
                // Training Hub v1.4 (sheet 08): a strength session found at launch was interrupted by the app ending;
                // it is kept as stored and paused until the athlete resumes it (the ball shows "restored").
                trainMemory.noteLaunch(store)
                deviceBottom = CyCradleMetrics.deviceBottomInset
                try? await Task.sleep(nanoseconds: 400_000_000)          // the window's insets can settle after the first frame
                deviceBottom = CyCradleMetrics.deviceBottomInset
            }
            // Run 157: a page whose content lives in its own NavigationStack (Plan, Progress, Profile, Home) does not take
            // the inset above for its scroll content, so Plan's last row ended under the dock. Scroll-content margins
            // reach every scroll view in the subtree; Ride (no scroll view) is placed by the safe-area inset.
            .contentMargins(.bottom, 80, for: .scrollContent)
            .undoSnackbar(hidden: showHub)      // Checkpoint C: the hub shows the Undo bar inline under the card it changed
        }
        .ignoresSafeArea(.keyboard)
        .tint(BC.accent)
        .sheet(item: $trainSheet) { a in TrainNowSheet(action: a, openRide: { tab = 2 }, openStrength: { strengthWorkout = $0.id }) }
        // Training Hub v1.4 (sheet 01a J2): from the Train button the preparation screen is a full page in the redesign;
        // the existing interface keeps its sheet.
        .sheet(item: CyProduct.redesign ? Binding<UUID?>.constant(nil) : $strengthWorkout) { id in StrengthWorkoutScreen(workoutId: id) }
        .fullScreenCover(item: CyProduct.redesign ? $strengthWorkout : Binding<UUID?>.constant(nil)) { id in StrengthWorkoutScreen(workoutId: id) }
        .fullScreenCover(isPresented: $resumeSession) { StrengthSessionView() }
        .fullScreenCover(isPresented: $cyclingDemo) { CyclingDemoRide().cyThemeRoot() }
        .sheet(isPresented: $strengthPicker) { CyStrengthPicker(open: { strengthWorkout = $0 }).cyThemeRoot() }
        .sheet(item: $homeSheet) { a in homeSheetView(a) }
        .sheet(isPresented: $holdSheet) { HealthHoldSheet() }
    }

    /// Where a ride opens. Cyclift Lab cannot record (no sensors, no GPS), so with the redesign on it opens the labelled
    /// demonstration of the v1.4 cycling screen; everywhere else it is the existing Ride screen, unchanged.
    private func openRide() { if CyProduct.redesign && CycliftLab.isLab { cyclingDemo = true } else { tab = 2 } }

    /// Performs a Home action: the card's buttons and the centre button share it, so both reach the same destination.
    private func perform(_ a: HomeAction) {
        switch a {
        case .startStrength(let id): strengthWorkout = id
        case .openRideScreen, .openLiveRide: openRide()
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
    @ViewBuilder private var dock: some View {
        if CyProduct.redesign {
            // Navigation v1.2 rev 1.1 (Shell/CyCradleDock.swift). Destinations and the Train routing are the existing
            // ones; Profile (page 4) is reached from the Home avatar and has no tab.
            // The ball is drawn from the real session (Shell/CyTrainBallState.swift). While a session exists the dock is
            // redrawn once a second so the time in the ball moves; otherwise it is drawn once.
            if ballInput(now: Date()).strength != nil || recorder.isActive {
                TimelineView(.periodic(from: .now, by: 1)) { c in
                    CyCradleDock(selection: $tab, hubOpen: showHub, ball: CyTrainBallState.make(ballInput(now: c.date)), onTrain: centreTapped)
                }
            } else {
                CyCradleDock(selection: $tab, hubOpen: showHub, ball: CyTrainBallState.make(ballInput(now: Date())), onTrain: centreTapped)
            }
        } else {
            let action = store.todayAction(now: max(Date(), day))
            let copy = RideTabBar.centreCopy(recording: recorder.isActive, action: action)
            let missed = store.homeToday(recorderActive: recorder.isActive).missed != nil
            CyLiquidDock(selection: $tab, state: CyCentreState.from(action: action, recording: recorder.isActive), missed: missed,
                         centreIcon: copy.icon, centreLabel: copy.label, centreHint: copy.hint, onCentre: centreTapped)
        }
    }
    /// The Train ball's facts, read from the one strength session (Store.activeSession), the one ride recorder and the
    /// recorder's memory. Nothing is kept here. `showPanel` is the compact panel, not the expanded Hub.
    /// CYCLING HOOK: `CyTrainBallInput.Cycling(elapsed:paused:simulated:)` is what the v1.4 cycling screen can feed
    /// later; today it is fed by the existing ride recorder only (the Lab demonstration ride is a full-screen page
    /// with its own clock and is not minimised — ride minimisation stays blocked by the safety gate).
    private func ballInput(now: Date) -> CyTrainBallInput {
        var i = CyTrainBallInput()
        i.panelOpen = showHub && !hubExpanded
        i.saveUnconfirmed = trainMemory.unconfirmed != nil
        if recorder.isActive { i.cycling = .init(elapsed: recorder.elapsedS, paused: recorder.state == .paused, simulated: false) }
        if let s = store.activeSession {
            i.strength = .init(elapsed: s.elapsedSeconds(now: now), paused: s.pausedAt != nil,
                               allSetsLogged: NextSet.pick(s.exercises ?? []) == nil,
                               saveFailed: trainMemory.saveFailedSession == s.id,
                               restored: trainMemory.restoredSession == s.id)
        }
        return i
    }

    /// Checkpoint C (owner-approved prototype §2.2): the centre button always opens the Training Hub, whose card carries
    /// today's Start / Resume / Results / Why / More with the same routes as before. While a ride is being recorded the
    /// button opens the Ride screen (the dock is the ride's own control then). Tapping it with the hub open closes it.
    /// Hub-tap reliability (owner 8 Nov 14:32; misses in runs 176 and 198): every tap is logged with the state it found
    /// (`log stream --predicate 'subsystem == "com.ralsuwaidico.bikecomputer"'`; CI keeps the app log of failed jobs), and
    /// a second tap within 350 ms of the first is treated as the same gesture — a double-delivered press must never
    /// toggle the hub straight back shut. The approved behaviour is unchanged: open when closed, close when open.
    private func centreTapped() {
        let now = Date()
        if now.timeIntervalSince(lastCentreTap) < 0.35 { hubLog.notice("centre tap ignored: \(Int(now.timeIntervalSince(lastCentreTap) * 1000)) ms after the previous one (hub \(showHub ? "open" : "closed"))"); return }
        lastCentreTap = now
        if recorder.isActive { hubLog.notice("centre tap → Ride (recording)"); tab = 2; return }
        // Navigation v1.2 (F9: Minimised → Resumed): with a strength session in progress — or a save that is not
        // confirmed — the ball returns to that workout's own screen. One session at a time; nothing new is started.
        if CyProduct.redesign, store.activeSession != nil || trainMemory.unconfirmed != nil {
            hubLog.notice("centre tap → strength recorder (session in progress)")
            if showHub { closeHub() }
            resumeSession = true
            return
        }
        if showHub { hubLog.notice("centre tap → close hub"); closeHub() } else { hubLog.notice("centre tap → open hub (tab \(tab))"); openHub() }
    }
    private func openHub() {
        var t = Transaction(); t.disablesAnimations = true
        withTransaction(t) { hubExpanded = false; showHub = true }
    }
    private func closeHub() { hubLog.notice("hub Close"); var t = Transaction(); t.disablesAnimations = true; withTransaction(t) { showHub = false } }

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
