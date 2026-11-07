import SwiftUI

/// Ride settings (gear icon on the ride screen): the ride layout, the coach and the classic tiles. Changing anything
/// here only writes AppSettings / the tile list — it can be opened during a ride without touching the recording.
struct RideSettingsSheet: View {
    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss
    @State private var showTiles = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("The ride screen has three views — Cockpit, Map and Performance — and adapts to the sensors that are live. Switch with the buttons at the top of the ride screen.")
                        .font(.footnote).foregroundStyle(.secondary)
                } header: { Text("Ride views") }
                Section {
                    Picker("Display", selection: $store.settings.rideDisplay) { ForEach(AppSettings.RideDisplay.allCases, id: \.self) { Text($0.title).tag($0) } }
                        .pickerStyle(.segmented).accessibilityIdentifier("rideDisplayPicker")
                    Text("Daylight is the high-contrast display for strong sunlight: dark numbers, instructions, targets and controls on a light background. Night is the dark cockpit. Auto follows the app appearance.")
                        .font(.footnote).foregroundStyle(.secondary)
                } header: { Text("Display") }
                Section("Coach") {
                    Toggle("Coach instructions during rides", isOn: $store.settings.coachEnabled)
                    Picker("How much it talks", selection: $store.settings.coachTalk) { ForEach(AppSettings.CoachTalk.allCases, id: \.self) { Text($0.title).tag($0) } }.pickerStyle(.segmented)
                    Text("Rule-based coach: it uses only the sensors that are live, keeps each instruction on screen for at least 15 seconds unless something important changes, and marks advice from unverified power as provisional.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("Ride details tiles") {
                    Button("Choose the six tiles") { showTiles = true }
                }
            }
            .navigationTitle(RideLabels.settings).navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .sheet(isPresented: $showTiles) { TilePicker() }
        }
    }
}
