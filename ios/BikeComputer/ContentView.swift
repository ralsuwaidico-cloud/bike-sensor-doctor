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
        // The Ride screen is always dark: show it with a dark window so the status bar (clock, battery) stays readable.
        .preferredColorScheme(store.onboarded && tab == 2 ? .dark : (store.settings.appearance == .light ? .light : store.settings.appearance == .dark ? .dark : nil))
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
                HomeView(tab: $tab).tabPage(0, tab)
                PlanView().tabPage(1, tab)
                RideTabView().tabPage(2, tab)
                ProgressTabView().tabPage(3, tab)
                ProfileTabView().tabPage(4, tab)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // the raised centre button overlaps the content by ~20 pt: scrollable content ends above it
            .safeAreaInset(edge: .bottom, spacing: 0) { Color.clear.frame(height: 22).allowsHitTesting(false) }
            .undoSnackbar()
            RideTabBar(selected: $tab, recording: recorder.isActive, action: store.todayAction(now: max(Date(), day)), onCentre: centreTapped)
        }
        .ignoresSafeArea(.keyboard)
        .tint(BC.accent)
        .sheet(item: $trainSheet) { a in TrainNowSheet(action: a, openRide: { tab = 2 }, openStrength: { strengthWorkout = $0.id }) }
        .sheet(item: $strengthWorkout) { id in StrengthWorkoutScreen(workoutId: id) }
        .fullScreenCover(isPresented: $resumeSession) { StrengthSessionView() }
    }

    /// The centre button adapts to today: a ride opens the cycling dashboard; a strength day opens the scheduled
    /// workout with its routine; both → a choice; rest / done → an optional-session sheet. It never starts recording.
    private func centreTapped() {
        let a = store.todayAction()
        switch a {
        case .ride: tab = 2
        case .train(let w): strengthWorkout = w.id
        case .inProgress: resumeSession = true
        case .choose, .rest, .doneToday: trainSheet = a
        }
    }

    private func idleTimer(_ s: RideRecorder.State) {
        let active = s == .running || s == .paused
        UIApplication.shared.isIdleTimerDisabled = store.settings.keepScreenOn && active
    }
}

/// Five tabs; the centre one is a raised circular "Ride now" button. Sized for Dynamic Type and the home indicator.
struct RideTabBar: View {
    @Binding var selected: Int
    let recording: Bool
    var action: Store.TodayAction = .rest
    var onCentre: (() -> Void)? = nil
    @Environment(\.dynamicTypeSize) private var dts

    /// Icon and label from today's scheduled activities (local calendar date). "Ride now" only on a cycling day.
    private var centre: (icon: String, label: String, hint: String) {
        if recording { return ("bicycle", "Riding", "Ride in progress, open Ride") }
        switch action {
        case .ride: return ("bicycle", "Ride now", "Ride now, open the Ride screen")
        case .train: return ("dumbbell.fill", "Train now", "Train now, open today's strength workout")
        case .choose: return ("figure.mixed.cardio", "Train now", "Train now, choose between today's ride and strength session")
        case .inProgress: return ("dumbbell.fill", "In progress", "Strength workout in progress, resume it")
        case .doneToday: return ("checkmark", "Done today", "Today's training is done, see the next step")
        case .rest: return ("dumbbell.fill", "Train now", "Rest day, optional session")
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

    private var rideButton: some View {
        let c = centre
        return Button { if let onCentre, !recording { onCentre() } else { selected = 2 } } label: {
            VStack(spacing: 3) {
                ZStack {
                    Circle().fill(recording ? BC.live : BC.accent).frame(width: 58, height: 58).shadow(color: .black.opacity(0.18), radius: 6, y: 3)
                    Image(systemName: c.icon).font(.system(size: 26, weight: .bold)).foregroundStyle(.white)
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
