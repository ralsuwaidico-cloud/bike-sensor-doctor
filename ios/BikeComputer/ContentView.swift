import SwiftUI

/// 0.4.0: first run shows the two-stage onboarding; afterwards Home / Plan / Ride / Progress / Profile with a custom
/// tab bar whose middle "Ride now" button is larger and raised. Tapping it only opens the Ride screen — recording
/// starts solely from the Start button there.
struct RootView: View {
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var recorder: RideRecorder
    @EnvironmentObject private var device: DeviceLink
    @State private var tab = 0
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        Group {
            if store.onboarded { tabs } else { OnboardingView() }
        }
        .onReceive(timer) { _ in recorder.phoneOnlyMode = store.settings.phoneOnlyMode; recorder.backgroundNoticeEnabled = store.settings.backgroundNotice }
        .preferredColorScheme(store.settings.appearance == .light ? .light : store.settings.appearance == .dark ? .dark : nil)
        .onChange(of: recorder.state) { _, s in idleTimer(s) }
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
            RideTabBar(selected: $tab, recording: recorder.isActive)
        }
        .ignoresSafeArea(.keyboard)
        .tint(BC.accent)
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
    @Environment(\.dynamicTypeSize) private var dts

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
    }

    private func item(_ i: Int, _ title: String, _ icon: String) -> some View {
        Button { selected = i } label: {
            VStack(spacing: 3) {
                Image(systemName: icon).font(.system(size: 20, weight: .medium))
                Text(title).font(.caption2).lineLimit(1).minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 6)
            .foregroundStyle(selected == i ? BC.accent : Color.secondary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title).accessibilityAddTraits(selected == i ? [.isSelected, .isButton] : .isButton)
    }

    private var rideButton: some View {
        Button { selected = 2 } label: {
            VStack(spacing: 3) {
                ZStack {
                    Circle().fill(recording ? BC.live : BC.accent).frame(width: 58, height: 58).shadow(color: .black.opacity(0.18), radius: 6, y: 3)
                    Image(systemName: "bicycle").font(.system(size: 26, weight: .bold)).foregroundStyle(.white)
                }
                .overlay(Circle().stroke(selected == 2 ? Color.primary.opacity(0.35) : Color.clear, lineWidth: 2))
                .offset(y: -14)
                Text(recording ? "Riding" : "Ride now").font(.caption2.weight(.bold)).foregroundStyle(selected == 2 ? BC.accent : .secondary).offset(y: -12)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(recording ? "Ride in progress, open Ride" : "Ride now, open the Ride screen")
    }
}

private extension View {
    func tabPage(_ i: Int, _ selected: Int) -> some View { opacity(i == selected ? 1 : 0).allowsHitTesting(i == selected).accessibilityHidden(i != selected).zIndex(i == selected ? 1 : 0) }
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
