import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var watch: WatchLink

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("BikeComputer")
                            .font(.largeTitle.bold())
                        Text("Companion app · test build \(AppInfo.label)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text("This first build only checks that the iPhone and Apple Watch apps install and talk to each other. Ride features come next.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .padding(.top, 4)
                    }
                    .padding(.vertical, 6)
                }

                Section("Apple Watch") {
                    StatusRow(title: "Watch connection supported", ok: watch.supported)
                    StatusRow(title: "Connection active", ok: watch.activated)
                    StatusRow(title: "Watch paired", ok: watch.paired)
                    StatusRow(title: "Watch app installed", ok: watch.appInstalled)
                    StatusRow(title: "Watch app reachable now", ok: watch.reachable)
                    if let build = watch.watchBuild {
                        LabeledContent("Watch app build", value: build)
                    }
                    Button("Test connection to Watch") { watch.ping() }
                    Text(watch.lastResult)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("Waveshare cycling computer") {
                    Text("Not connected in this build. The BLE link to the ESP32 is added in the next step.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .refreshable { watch.activate() }
        }
    }
}

private struct StatusRow: View {
    let title: String
    let ok: Bool

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Image(systemName: ok ? "checkmark.circle.fill" : "xmark.circle")
                .foregroundStyle(ok ? .green : .secondary)
                .accessibilityLabel(ok ? "Yes" : "No")
        }
    }
}
