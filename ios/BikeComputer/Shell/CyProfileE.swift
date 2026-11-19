import SwiftUI

// Profile v2.0, sheet P07 (visual design "Pending Review" on the sheet) — App Preferences pages:
//   E1 Units                   — the one units setting
//   E2 Notifications & display — the ride recording notice, keep-screen-on, ride tiles, ride display
//   E3 Coach                   — coach during rides, how much it talks, plan adjustments
// Each control writes the same setting as the pages it replaces in the redesign (SettingsPage, RideCoachSettingsPage,
// AdjustmentsView's switch), which the existing app keeps. Only what the app really does is offered.

/// A switch row of sheet P07: title, one line of explanation, the switch, a hairline.
struct CyToggleRow: View {
    let title: String
    let note: String
    @Binding var isOn: Bool
    var id: String
    var body: some View {
        VStack(spacing: 0) {
            Toggle(isOn: $isOn) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(CyDyn.f(16.5, .semibold)).foregroundStyle(CyTheme.ink)
                    Text(note).font(CyDyn.f(13.5)).foregroundStyle(CyTheme.ink2).fixedSize(horizontal: false, vertical: true)
                }
            }
            .tint(CyTheme.ink2).frame(minHeight: 60).accessibilityIdentifier(id)
            Rectangle().fill(CyTheme.line).frame(height: 1).accessibilityHidden(true)
        }
    }
}

private struct CyNote: View {
    let text: String
    var body: some View {
        Text(text).font(CyDyn.f(13.5)).foregroundStyle(CyTheme.ink2).fixedSize(horizontal: false, vertical: true).padding(.top, 14)
    }
}

struct CyProfileUnits: View {
    @EnvironmentObject private var store: Store
    var body: some View {
        CyProfilePage(title: "Units") {
            CyGroupLabel(text: "UNITS")
            CyChoiceBar(options: [(AppSettings.Units.metric, "Metric"), (AppSettings.Units.imperial, "Imperial")], selection: $store.settings.units)
                .accessibilityIdentifier("unitsChoice")
            CyNote(text: "Units are set once here. The BikeComputer follows this setting.")
        }
        .accessibilityIdentifier("profileUnitsPage")
    }
}

struct CyProfileNotificationsDisplay: View {
    @EnvironmentObject private var store: Store
    var body: some View {
        CyProfilePage(title: "Notifications & display") {
            CyGroupLabel(text: "NOTIFICATIONS")
            CyToggleRow(title: "Ride recording notice", note: "Shown while a ride records in the background", isOn: $store.settings.backgroundNotice, id: "settingsNotifications")
            CyProfileRows { CyProfileRow(title: "Other notifications", summary: "Reminders, Coach, weekly summary", kind: .notAvailable, id: "otherNotifications") }
            CyGroupLabel(text: "TRAINING DISPLAY")
            CyToggleRow(title: "Keep the screen on", note: "During workouts", isOn: $store.settings.keepScreenOn, id: "keepScreenOn")
            CyToggleRow(title: "Phone records every ride", note: "Even when a BikeComputer is connected", isOn: $store.settings.phoneOnlyMode, id: "phoneOnlyMode")
            CyProfileRows { CyProfileRow(title: "Ride tiles", summary: "\(store.tiles.count) shown on the ride screen", id: "rideTiles") { TilePicker() } }
            CyGroupLabel(text: "RIDE DISPLAY")
            CyChoiceBar(options: AppSettings.RideDisplay.allCases.map { ($0, $0.title) }, selection: $store.settings.rideDisplay)
                .accessibilityIdentifier("rideDisplay")
            CyGroupLabel(text: "ACCESSIBILITY")
            Text("Text size, contrast, motion").font(CyDyn.f(16.5, .semibold)).foregroundStyle(CyTheme.ink)
            Text("Cyclift follows your iPhone settings").font(CyDyn.f(13.5)).foregroundStyle(CyTheme.ink2)
        }
        .accessibilityIdentifier("profileNotificationsPage")
    }
}

struct CyProfileCoachPreferences: View {
    @EnvironmentObject private var store: Store
    var body: some View {
        CyProfilePage(title: "Coach") {
            CyGroupLabel(text: "DURING RIDES")
            CyToggleRow(title: "Coach during rides", note: "Spoken and on-screen cues", isOn: $store.settings.coachEnabled, id: "coachDuringRides")
            CyGroupLabel(text: "HOW MUCH IT TALKS")
            CyChoiceBar(options: AppSettings.CoachTalk.allCases.map { ($0, $0.title) }, selection: $store.settings.coachTalk)
                .disabled(!store.settings.coachEnabled).opacity(store.settings.coachEnabled ? 1 : 0.45)
                .accessibilityIdentifier("coachTalk")
            CyGroupLabel(text: "PLAN ADJUSTMENTS")
            // the app's own wording and meaning for this switch (AdjustmentsView): it is not renamed here
            CyToggleRow(title: "Adjust future sessions automatically", note: "By the Coach's written rules. Increases wait for your approval.", isOn: $store.settings.autoAdapt, id: "coachAutoAdapt")
            CyProfileRows {
                CyProfileRow(title: "Current adjustments", summary: store.activeAdaptations.isEmpty ? "None" : "\(store.activeAdaptations.count) in force", id: "coachAdjustments") { AdjustmentsView() }
            }
            CyNote(text: "Coach guidance is rules-based. AI chat is not connected.")
        }
        .accessibilityIdentifier("profileCoachPage")
        .onChange(of: store.settings.autoAdapt) { _, _ in _ = store.runAdaptation() }
    }
}
