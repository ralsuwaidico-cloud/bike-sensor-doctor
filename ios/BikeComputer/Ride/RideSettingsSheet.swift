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
                    ForEach(RideLayout.allCases) { l in
                        Button { RideLayoutSwitch.select(l, store: store) } label: {
                            HStack(spacing: 12) {
                                Image(systemName: l.icon).frame(width: 28).foregroundStyle(BC.accent)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(l.title).font(.body.weight(.semibold)).foregroundStyle(.primary)
                                    Text(l.blurb).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if store.settings.rideLayout == l { Image(systemName: "checkmark").font(.body.weight(.bold)).foregroundStyle(BC.accent) }
                            }
                        }
                        .accessibilityIdentifier("rideLayoutOption.\(l.rawValue)")
                        .accessibilityAddTraits(store.settings.rideLayout == l ? .isSelected : [])
                    }
                } header: { Text(RideLabels.layoutMenu) } footer: {
                    Text("Every layout shows the same ride, sensors and coach. You can switch during a ride; recording and sensors are not interrupted.")
                }
                Section("Coach") {
                    Toggle("Coach instructions during rides", isOn: $store.settings.coachEnabled)
                    Picker("How much it talks", selection: $store.settings.coachTalk) { ForEach(AppSettings.CoachTalk.allCases, id: \.self) { Text($0.title).tag($0) } }.pickerStyle(.segmented)
                    Text("Rule-based coach: it uses only the sensors that are live, keeps each instruction on screen for at least 15 seconds unless something important changes, and marks advice from unverified power as provisional.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("Classic layout") {
                    Button("Choose the six tiles") { showTiles = true }
                }
            }
            .navigationTitle(RideLabels.settings).navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .sheet(isPresented: $showTiles) { TilePicker() }
        }
    }
}
