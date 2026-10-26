import Foundation

/// Cyclift 1.0 — the selectable live ride layouts (docs/briefs/CYCLIFT_CONTRACTS.md, "Ride layout contract").
/// Presentation only: every layout reads the same SensorHub readings, the same RideCoach and the same RideRecorder.
/// Choosing one writes `AppSettings.rideLayout` and nothing else, so it can change in the middle of a ride.
/// History of each layout (Nokia app and earlier iOS builds): ios/RIDE_LAYOUTS.md.
enum RideLayout: String, Codable, CaseIterable, Identifiable {
    case coach, gauges, classic, rings, analytics
    var id: String { rawValue }

    var title: String {
        switch self {
        case .coach: return "Ride Coach"
        case .gauges: return "Large gauges"
        case .classic: return "Classic"
        case .rings: return "Rings"
        case .analytics: return "Analytics"
        }
    }
    var blurb: String {
        switch self {
        case .coach: return "Power Focus: large power gauge, cadence and heart rate below, live graph and stats."
        case .gauges: return "Three big gauges for power, heart rate and cadence — readable at a glance."
        case .classic: return "The metric tile grid from the first app versions; choose the six tiles."
        case .rings: return "Compact three-ring dashboard with zone bars and a small live graph."
        case .analytics: return "The combined live graph of watts, BPM and RPM is the main element."
        }
    }
    var icon: String {
        switch self {
        case .coach: return "figure.outdoor.cycle"
        case .gauges: return "speedometer"
        case .classic: return "square.grid.2x2"
        case .rings: return "circle.circle"
        case .analytics: return "chart.xyaxis.line"
        }
    }
    /// UI-test / accessibility identifier of the layout's content container.
    var accessibilityId: String { "rideLayout.\(rawValue)" }
}

/// The only way the ride screen changes layout: one settings write. It never touches the recorder, the hub or BLE
/// (RideLayoutTests checks this), so recording, sensors and the coach carry on uninterrupted.
enum RideLayoutSwitch {
    static func select(_ layout: RideLayout, store: Store) {
        guard store.settings.rideLayout != layout else { return }
        store.settings.rideLayout = layout
    }
}

/// Every fixed label the ride screens print. Labels name the metric, never a brand; the source is printed separately
/// from `MetricReading.sourceLabel`. RideLayoutTests asserts none of these contains a manufacturer name.
enum RideLabels {
    static let power = "POWER · W"
    static let heartRate = "BPM"
    static let cadence = "RPM"
    static let powerUnverified = "POWER UNVERIFIED"
    static let ftpProvisional = "FTP PROVISIONAL"
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
        [power, heartRate, cadence, powerUnverified, ftpProvisional, provisional, coach, details, layoutMenu, settings, demo, unverifiedSuffix, estimatedSuffix]
            + tileTitles + RideLayout.allCases.flatMap { [$0.title, $0.blurb] } + MetricKind.allCases.map(\.missingText)
    }
}
