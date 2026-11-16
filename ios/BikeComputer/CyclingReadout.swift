import Foundation

// Training Hub v1.4 — cycling recorder: what the screen shows, as plain values (Foundation only, tested on Linux).
//
// The screen draws a `CyclingReadout`. Where the readout comes from is a separate matter:
//   • Cyclift Lab: `CyclingDemoScript` — a fixed, deterministic script. SIMULATED. No sensor, no GPS, nothing recorded.
//   • Production: not connected. The existing Ride screen stays in use until the cycling safety gate is passed.
//
// Sensor truth (v1.4 correction A): a zero is shown only when it was measured. Everything else is "—" with its reason,
// or the last value dimmed with its age. A pause never turns into a zero.

/// One sensor value and how true it is right now.
enum SensorTruth: Equatable {
    case measured(Int)                  // includes a real, measured zero
    case stale(last: Int, ageSeconds: Int)
    case disconnected                   // the link dropped: "—" and the reason; nothing recorded for these seconds
    case unavailable                    // no such sensor for this ride

    /// The big figure: a number, or "—" when there is none to show.
    var figure: String {
        switch self {
        case .measured(let v): return "\(v)"
        case .stale(let v, _): return "\(v)"
        case .disconnected, .unavailable: return "—"
        }
    }
    var dimmed: Bool { if case .measured = self { return false }; return true }
    var recorded: Bool { if case .measured = self { return true }; return false }
}

enum CyclingPhase: String { case recording, paused, ended }

struct CyclingReadout: Equatable {
    var title: String
    var phase: CyclingPhase
    var elapsedSeconds: Int
    var movingSeconds: Int
    var power: SensorTruth
    var heartRate: SensorTruth
    var cadence: SensorTruth
    var speedKmh: Double?
    var distanceKm: Double
    var targetLow: Int?
    var targetHigh: Int?
    var laps: Int

    /// Under the power figure: "In range", "Coasting", "Last reading 6 s ago", "No signal", "No power meter".
    var powerLine: String {
        switch power {
        case .measured(0): return "Coasting"
        case .measured(let w):
            guard let lo = targetLow, let hi = targetHigh else { return "Measured" }
            return w < lo ? "Below target" : w > hi ? "Above target" : "In range"
        case .stale(_, let age): return "Last reading \(age) s ago"
        case .disconnected: return "No signal"
        case .unavailable: return "No power meter"
        }
    }
    var powerLabel: String {
        switch power {
        case .measured: return "POWER · 3 S"
        case .stale: return "POWER · NO UPDATE"
        case .disconnected, .unavailable: return "POWER"
        }
    }
    /// The warning box; nil while every sensor is reporting.
    var warning: String? {
        switch power {
        case .stale: return "Power meter is not updating"
        case .disconnected: return "Power meter lost. Power and cadence are not being recorded."
        default: return nil
        }
    }
    static func clock(_ s: Int) -> String { let v = max(0, s); return v >= 3600 ? String(format: "%d:%02d:%02d", v / 3600, v / 60 % 60, v % 60) : String(format: "%02d:%02d", v / 60, v % 60) }
}

/// The Lab demonstration: a fixed script over ride time, so every screenshot and test sees the same thing. It walks
/// through the sensor states on purpose: riding in range, a measured zero while coasting, a stale meter, a lost meter,
/// and back. All of it is invented for the demonstration and labelled so on screen.
enum CyclingDemoScript {
    static let title = "Tempo intervals"
    /// `t` = ride seconds (pauses excluded).
    static func readout(at t: Int, phase: CyclingPhase, laps: Int) -> CyclingReadout {
        let c = t % 90                                   // the script repeats every 90 ride seconds
        let wobble = [0, 3, -2, 5, -4, 1, 4, -3][t % 8]
        var power: SensorTruth = .measured(230 + wobble)
        var cadence: SensorTruth = .measured(88 + wobble / 2)
        var speed: Double? = 31.4 + Double(wobble) / 10
        switch c {
        case 30..<40: power = .measured(0); cadence = .measured(0); speed = 27.0            // coasting: a real zero
        case 50..<60: power = .stale(last: 231, ageSeconds: c - 49); cadence = .stale(last: 88, ageSeconds: c - 49)
        case 60..<72: power = .disconnected; cadence = .disconnected
        default: break
        }
        return CyclingReadout(title: title, phase: phase, elapsedSeconds: t, movingSeconds: t, power: power,
                              heartRate: .measured(150 + min(8, t / 20) + wobble / 3), cadence: cadence, speedKmh: speed,
                              distanceKm: Double(t) * 31.4 / 3600, targetLow: 220, targetHigh: 240, laps: laps)
    }
}
