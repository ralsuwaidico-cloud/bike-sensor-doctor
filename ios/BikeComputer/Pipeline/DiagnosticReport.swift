import Foundation

/// One diagnostic event (ring buffer of the last 50, persisted across launches). Text is technical, never personal.
struct DiagEvent: Codable, Equatable, Identifiable {
    var id = UUID()
    var at: Date
    var kind: String          /* "trigger" | "health" | "recovery" | "board" | "watch" | "sensor" */
    var text: String
}

/// One SENSOR_DIAG as received (history ring of the last 50, persisted).
struct SensorDiagRecord: Codable, Equatable {
    var at: Date
    var sensor: String
    var stage: String
    var packets: UInt32?
    var rejected: UInt16?
    var packetAgeS: Double?
    var validAgeS: Double?
    var lastError: String?
    init(_ d: BCLink.SensorDiag, at: Date) {
        self.at = at
        sensor = d.sensor?.title ?? "sensor \(d.sensorRaw)"
        stage = d.stage.map { "\($0.rawValue) \($0.words)" } ?? "unknown \(d.stageRaw)"
        packets = d.packets; rejected = d.rejected; packetAgeS = d.packetAgeS; validAgeS = d.validAgeS; lastError = d.lastError
    }
}

/// Fixed-size ring buffer helper (pure, tested through the monitor's rules).
enum Ring {
    static func append<T>(_ x: T, to a: inout [T], max: Int = 50) { a.append(x); if a.count > max { a.removeFirst(a.count - max) } }
}

/// "Export diagnostic report" (Connections › Diagnostics): a JSON file the rider can share. Contents: app / watch /
/// firmware versions and protocol, every path's stages, BLE characteristics seen, notification status, packet counts,
/// parser errors, the last 50 events and the SENSOR_DIAG history. Never: names, e-mail addresses, locations, board
/// addresses or health history beyond counts — and the finished text is scrubbed once more (`scrub`).
struct DiagnosticReport: Codable {
    var format = "cyclift-diagnostics/1"
    var generatedAt: Date
    var app: String
    var system: String
    var watchApp: String?
    var watchVersionCheck: String
    var topMessage: String?
    var pipelines: [PipelineReport]
    var board: Board?
    var watch: Watch
    var directSensors: [Direct]
    var recentEvents: [DiagEvent]
    var sensorDiagHistory: [SensorDiagRecord]
    var boardStageLog: [String]

    struct Board: Codable {
        var firmware: String?
        var protocolVersion: String?
        var caps: String?
        var stage: String
        var linkUsable: Bool
        var connectedForS: Int?
        var liveAgeS: Double?
        var maxNotifyBytes: Int?
        var characteristics: [String]
        var notifying: [String: Bool]
        var notifyErrors: [String: String]
        var counters: [String: Int]
        var parseErrors: [String]
        var lastFailure: String?
        var liveResubscribes: Int
        var latestSensorDiag: [SensorDiagRecord]
    }
    struct Watch: Codable {
        var enabled: Bool
        var paired: Bool
        var appInstalled: Bool
        var reachable: Bool
        var mirrorActive: Bool
        var mirrorRemoteState: String
        var mirrorSessions: Int
        var mirrorPayloads: Int
        var mirrorBadPayloads: Int
        var lastMirrorDisconnect: String?
        var workoutState: String
        var workoutAuthOnWatch: String?
        var hrAcceptedMirror: Int
        var hrAcceptedConnectivity: Int
        var hrDuplicates: Int
        var hrDropped: Int
        var lastDeliveryAgeS: Double?
        var hrSentToBoard: Int
    }
    struct Direct: Codable {
        var index: Int
        var kind: String
        var link: String
        var subscribed: Bool?
        var services: [String]
        var characteristics: [String]
        var packets: Int
        var rejected: Int
        var lastPacketAgeS: Double?
        var lastValidAgeS: Double?
    }

    // MARK: privacy scrub
    private static let email = try! NSRegularExpression(pattern: "[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}")
    private static let mac = try! NSRegularExpression(pattern: "([0-9A-Fa-f]{2}[:-]){5}[0-9A-Fa-f]{2}")
    /// Removes e-mail addresses, hardware addresses and every given personal string (the rider's name, sensor names).
    static func scrub(_ text: String, personal: [String]) -> String {
        var t = text
        let all = NSRange(t.startIndex..., in: t)
        t = email.stringByReplacingMatches(in: t, range: all, withTemplate: "<e-mail removed>")
        t = mac.stringByReplacingMatches(in: t, range: NSRange(t.startIndex..., in: t), withTemplate: "<address removed>")
        // longest first so "Rashed’s HRM" goes before "Rashed"
        for p in personal.map({ $0.trimmingCharacters(in: .whitespacesAndNewlines) }).filter({ $0.count >= 2 }).sorted(by: { $0.count > $1.count }) {
            t = t.replacingOccurrences(of: p, with: "<removed>", options: [.caseInsensitive])
            // the same string as JSON escapes it
            if let enc = try? JSONEncoder().encode(p), let s = String(data: enc, encoding: .utf8), s.count > 2 {
                let inner = String(s.dropFirst().dropLast())
                if inner != p { t = t.replacingOccurrences(of: inner, with: "<removed>", options: [.caseInsensitive]) }
            }
        }
        return t
    }

    /// Pretty JSON, scrubbed.
    func json(personal: [String]) -> Data {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        enc.dateEncodingStrategy = .iso8601
        let raw = (try? enc.encode(self)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        return Data(DiagnosticReport.scrub(raw, personal: personal).utf8)
    }
}
