import SwiftUI
import UniformTypeIdentifiers

/// Ride settings (gear icon on the ride screen): the ride layout, the coach and the classic tiles. Changing anything
/// here only writes AppSettings / the tile list — it can be opened during a ride without touching the recording.
struct RideSettingsSheet: View {
    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss
    @State private var showTiles = false
    @EnvironmentObject private var routes: RouteStore
    @State private var importing = false
    @State private var importError: String? = nil

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
                    Text("Night is the dark cockpit (default). Daylight is the high-contrast display for strong sunlight: dark numbers, instructions, targets and controls on a light background. Auto follows the app appearance.")
                        .font(.footnote).foregroundStyle(.secondary)
                } header: { Text("Display") }
                Section("Coach") {
                    Toggle("Coach instructions during rides", isOn: $store.settings.coachEnabled)
                    Picker("How much it talks", selection: $store.settings.coachTalk) { ForEach(AppSettings.CoachTalk.allCases, id: \.self) { Text($0.title).tag($0) } }.pickerStyle(.segmented)
                    Text("Rule-based coach: it uses only the sensors that are live, keeps each instruction on screen for at least 15 seconds unless something important changes, and marks advice from unverified power as provisional.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section {
                    if let r = routes.loaded {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(r.name).font(.body.weight(.semibold)).accessibilityIdentifier("routeName")
                            Text("\(RouteGuidance.km(r.totalM)) · \(max(0, r.turns.count - 1)) turn cues · \(r.points.count) points").font(.footnote).foregroundStyle(.secondary)
                        }
                        Button("Remove route", role: .destructive) { routes.set(nil) }.accessibilityIdentifier("routeRemove")
                    } else {
                        Text("No route loaded. Import a GPX file to see the route, the next turn and off-route warnings on the Map view. Recording never depends on a route.").font(.footnote).foregroundStyle(.secondary)
                    }
                    Button("Import GPX route…") { importError = nil; importing = true }.accessibilityIdentifier("routeImport")
                    if let e = importError { Text(e).font(.footnote).foregroundStyle(.red) }
                } header: { Text("Route") }
                Section("Ride details tiles") {
                    Button("Choose the six tiles") { showTiles = true }
                }
            }
            .navigationTitle(RideLabels.settings).navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .sheet(isPresented: $showTiles) { TilePicker() }
            .fileImporter(isPresented: $importing, allowedContentTypes: [UTType(filenameExtension: "gpx") ?? .xml, .xml, .data], allowsMultipleSelection: false) { res in
                switch res {
                case .success(let urls): guard let u = urls.first else { return }; do { _ = try routes.importGPX(at: u) } catch { importError = error.localizedDescription }
                case .failure(let e): importError = e.localizedDescription
                }
            }
        }
    }
}
