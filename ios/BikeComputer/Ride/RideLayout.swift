import Foundation

/// Cyclift 1.0 — the selectable live ride layouts (docs/briefs/CYCLIFT_CONTRACTS.md, "Ride layout contract").
/// Presentation only: every layout reads the same SensorHub readings, the same RideCoach and the same RideRecorder.
/// Choosing one writes `AppSettings.rideLayout` and nothing else, so it can change in the middle of a ride.
/// History of each layout (Nokia app and earlier iOS builds): ios/RIDE_LAYOUTS.md.
/// Checkpoint F (owner decision 3, 7 Nov 2026): the five manual layouts are gone — the ride screen has three adaptive
/// views (RideViewKind). This enum stays ONLY so stored settings from builds ≤ 176 keep decoding (`AppSettings.rideLayout`
/// is read and ignored; migration note in ios/RIDE_LAYOUTS.md). Nothing in the UI uses it any more.
enum RideLayout: String, Codable, CaseIterable, Identifiable {
    case coach, gauges, classic, rings, analytics
    var id: String { rawValue }
}

enum RideLabels {
    static let power = "POWER · W"
    static let heartRate = "BPM"
    static let cadence = "RPM"
    static let powerUnverified = "POWER UNVERIFIED"
    static let ftpProvisional = "FTP PROVISIONAL"
    /// RC3 / ENG-E1: the FTP is Unknown — watts are shown, no power zone or target is claimed.
    static let ftpUnknown = "FTP UNKNOWN"
    static let provisional = "PROVISIONAL"
    static let coach = "COACH"
    static let details = "DETAILS ›"
    static let layoutMenu = "Ride layout"
    static let settings = "Ride settings"
    static let demo = "DEMO — NOT SAVED"
    static let unverifiedSuffix = "unverified"
    static let estimatedSuffix = "estimated"
    static let tileTitles = ["Power", "Cadence", "Heart rate", "Speed", "Time", "Distance", "Lap", "Zone", "Normalized", "Board battery"]

    static var all: [String] {
        [power, heartRate, cadence, powerUnverified, ftpProvisional, ftpUnknown, provisional, coach, details, layoutMenu, settings, demo, unverifiedSuffix, estimatedSuffix]
            + tileTitles + RideLayout.allCases.flatMap { [$0.title, $0.blurb] } + MetricKind.allCases.map(\.missingText)
    }
}
