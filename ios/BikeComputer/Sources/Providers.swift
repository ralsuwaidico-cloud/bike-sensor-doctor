import Foundation

/// Cloud providers that are NOT implemented in 1.0 (each needs a developer app, credentials and approval the project does
/// not have yet). They are listed honestly as planned: never connected, never available, no live data claimed. Capability
/// notes and official sources: docs/INTEGRATIONS.md.
struct PlannedProvider: Identifiable, Equatable {
    var id: String
    var name: String
    var icon: String
    /// What the integration will provide once built (after the activity — none of these APIs streams live data).
    var willProvide: String
    /// What works today without the integration.
    var liveNow: String
    var descriptor: SourceDescriptor { SourceDescriptor(id: "cloud:" + id, name: name, method: .cloudAPI, timing: .imported) }
    var status: SourceStatus {
        SourceStatus(descriptor: descriptor, state: .planned, metrics: [], provides: willProvide, lastUpdate: nil, quality: nil, configured: false, detail: "Planned — not available yet")
    }
}

enum ProviderCatalog {
    static let garmin = PlannedProvider(
        id: "garmin", name: "Garmin", icon: "arrow.triangle.2.circlepath",
        willProvide: "Activities and daily health summaries (heart rate, sleep, stress) after your Garmin syncs with Garmin Connect.",
        liveNow: "Live heart rate works now if your Garmin watch can broadcast heart rate: turn on Broadcast Heart Rate on the watch, then add it under Bluetooth sensors.")
    static let whoop = PlannedProvider(
        id: "whoop", name: "WHOOP", icon: "waveform.path.ecg",
        willProvide: "Recovery, strain, sleep and workouts from your WHOOP account, after they are recorded.",
        liveNow: "Live heart rate works now: turn on Heart Rate Broadcast in the WHOOP app, then add \"WHOOP\" under Bluetooth sensors.")
    static let oura = PlannedProvider(
        id: "oura", name: "Oura", icon: "circle.circle",
        willProvide: "Daily readiness, sleep and activity, and heart-rate history from your Oura account, after the ring syncs.",
        liveNow: "Oura does not stream live heart rate to other apps. During rides use the Apple Watch, a strap or another broadcasting device.")
    static let planned: [PlannedProvider] = [garmin, whoop, oura]
}
