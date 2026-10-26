import SwiftUI

/// One live metric as the ride layouts show it: the hub's reading (or nil → `kind.missingText`), its source line and
/// whether its quality must be marked. Built ONLY from `SensorHub.reading(_:)` — never from a device link directly.
struct RideMetric: Equatable {
    let kind: MetricKind
    let reading: MetricReading?
    /// Why there is no value although a source is set up ("Connected — waiting for data", "No power data", "Data stale"),
    /// from the pipeline monitor; nil → the plain `kind.missingText`.
    var missing: String? = nil
    var missingText: String { missing ?? kind.missingText }

    /// A stale reading is never shown or coached as live.
    var usable: Bool { reading.map { $0.quality != .stale } ?? false }
    var value: Int? { usable ? reading?.intValue : nil }
    var unverified: Bool { usable && reading?.quality == .unverified }
    /// Amber source line: the value is shown but not fully trusted (unverified / estimated).
    var warning: Bool { usable && (reading?.quality == .unverified || reading?.quality == .estimated) }
    /// "Apple Watch", "Power meter via BikeComputer · unverified", … ; nil when nothing provides the metric.
    var sourceLine: String? {
        guard usable, let r = reading else { return nil }
        switch r.quality {
        case .good: return r.sourceLabel
        case .unverified: return "\(r.sourceLabel) · \(RideLabels.unverifiedSuffix)"
        case .estimated: return "\(r.sourceLabel) · \(RideLabels.estimatedSuffix)"
        case .stale: return nil
        }
    }
    var sourceOrMissing: String { sourceLine ?? missingText }
}

/// Everything a layout draws, computed once per render from the hub, the profile and the coach's targets.
struct RideLive {
    var power: RideMetric, hr: RideMetric, cadence: RideMetric, speed: RideMetric
    var ftp: Int, maxHr: Int, cadLo: Int, cadHi: Int
    var targetZone: Int, targetHrZone: Int
    var hrZoneRanges: [(lo: Int, hi: Int?)]
    var imperial: Bool
    var ftpProvisional: Bool

    init(power: MetricReading?, hr: MetricReading?, cadence: MetricReading?, speed: MetricReading?, profile: RiderProfile, imperial: Bool, targetZone: Int, targetHrZone: Int? = nil, missing: [MetricKind: String] = [:]) {
        self.power = RideMetric(kind: .power, reading: power, missing: missing[.power]); self.hr = RideMetric(kind: .heartRate, reading: hr, missing: missing[.heartRate])
        self.cadence = RideMetric(kind: .cadence, reading: cadence, missing: missing[.cadence]); self.speed = RideMetric(kind: .speed, reading: speed, missing: missing[.speed])
        ftp = profile.ftpW; maxHr = profile.estimatedMaxHR; cadLo = profile.cadenceLow; cadHi = profile.cadenceHigh
        self.targetZone = targetZone; self.targetHrZone = targetHrZone ?? targetZone
        hrZoneRanges = profile.hrZones; self.imperial = imperial
        ftpProvisional = profile.ftpHow == .assumed
    }
    static func from(hub: SensorHub, profile: RiderProfile, settings: AppSettings, coach: RideCoach) -> RideLive {
        RideLive(power: hub.reading(.power), hr: hub.reading(.heartRate), cadence: hub.reading(.cadence), speed: hub.reading(.speed),
                 profile: profile, imperial: settings.units == .imperial, targetZone: coach.targetZone, targetHrZone: coach.targetHrZone, missing: hub.missingReason)
    }

    // MARK: derived (CoachCore rules; the UI only draws)
    var powerZone: Int { PowerZones.zone(power.value, ftp: ftp) }
    var hrZone: Int { HrZones.zone(hr.value, maxHr: maxHr) }
    var powerStatus: TargetStatus { Targets.power(power.value, ftp: ftp, targetZone: targetZone) }
    var hrStatus: TargetStatus { Targets.hr(hr.value, maxHr: maxHr, targetZone: targetHrZone) }
    var cadStatus: TargetStatus { Targets.cadence(cadence.value, low: cadLo, high: cadHi) }
    var speedKmh: Double? { speed.usable ? speed.reading?.value : nil }
    var speedText: String { speedKmh.map { String(format: imperial ? "%.1f mph" : "%.1f km/h", imperial ? $0 / 1.609 : $0) } ?? "—" }

    /// Pill text: a missing source says so in plain words ("NO POWER SOURCE"); a valid zero is named (COASTING …).
    func statusText(_ m: RideMetric) -> String {
        guard m.usable else { return m.missingText.uppercased() }
        switch m.kind {
        case .power: return GaugeText.status(powerStatus, kind: "pow")
        case .cadence: return GaugeText.status(cadStatus, kind: "cad")
        case .heartRate: return GaugeText.status(hrStatus, kind: "hr")
        case .speed: return speedText
        }
    }
    var powerBand: (Double, Double) {
        let r = PowerZones.range(targetZone, ftp: ftp); let m = Double(Targets.powerGaugeMaxW(ftp: ftp))
        return (Double(r.lo) / m, Double(r.hi ?? Int(m)) / m)
    }
    var hrBand: (Double, Double) {
        let z = hrZoneRanges; let i = min(z.count - 1, max(0, targetHrZone - 1)); let m = Double(max(1, maxHr))
        return (Double(z[i].lo) / m, Double(z[i].hi ?? maxHr) / m)
    }
    var hrBandBpm: (Int, Int) { let z = hrZoneRanges; let i = min(z.count - 1, max(0, targetHrZone - 1)); return (z[i].lo, z[i].hi ?? maxHr) }
    var powerBandW: (Int, Int?) { let r = PowerZones.range(targetZone, ftp: ftp); return (r.lo, r.hi) }
}

/// The three gauges, built once here and reused by every layout (Ride Coach, Large gauges, Rings).
enum RideGauges {
    static func power(_ l: RideLive, big: Bool, showTgtLabel: Bool = true) -> TargetGauge {
        TargetGauge(value: l.power.value, maxValue: Targets.powerGaugeMaxW(ftp: l.ftp), color: l.powerZone > 0 ? D7.powerZone(l.powerZone) : D7.grey,
                    targetFraction: Targets.powerTargetFraction(targetZone: l.targetZone, ftp: l.ftp), zoneTicks: Targets.powerZoneTicks(ftp: l.ftp),
                    band: l.powerBand, sub: l.powerZone > 0 ? "Z\(l.powerZone) · \(Targets.powerZonePercent(l.power.value, ftp: l.ftp) ?? 0)%" : nil,
                    unit: RideLabels.power, big: big, status: l.power.usable ? l.powerStatus : .unknown, statusText: l.statusText(l.power), showTgtLabel: showTgtLabel,
                    source: l.power.sourceLine ?? " ", sourceWarning: l.power.warning)
    }
    static func cadence(_ l: RideLive, big: Bool) -> TargetGauge {
        TargetGauge(value: l.cadence.value, maxValue: Targets.cadenceGaugeMax, color: D7.violet, targetFraction: nil, zoneTicks: [],
                    band: (Double(l.cadLo) / Double(Targets.cadenceGaugeMax), Double(l.cadHi) / Double(Targets.cadenceGaugeMax)),
                    sub: "\(l.cadLo)–\(l.cadHi)", unit: RideLabels.cadence, big: big, status: l.cadence.usable ? l.cadStatus : .unknown,
                    statusText: l.statusText(l.cadence), showTgtLabel: false, source: l.cadence.sourceLine ?? " ", sourceWarning: l.cadence.warning)
    }
    static func heartRate(_ l: RideLive, big: Bool) -> TargetGauge {
        TargetGauge(value: l.hr.value, maxValue: l.maxHr, color: l.hr.value != nil && l.hrZone > 0 ? D7.hrZone(l.hrZone) : D7.faint,
                    targetFraction: Targets.hrTargetFraction(targetZone: l.targetHrZone), zoneTicks: Targets.hrZoneTicks, band: l.hrBand,
                    sub: l.hr.value != nil && l.hrZone > 0 ? "Z\(l.hrZone) · \(Targets.hrZonePercent(l.hr.value, maxHr: l.maxHr) ?? 0)%" : nil,
                    unit: RideLabels.heartRate, big: big, status: l.hr.usable ? l.hrStatus : .unknown, statusText: l.statusText(l.hr), showTgtLabel: false,
                    source: l.hr.sourceLine ?? " ", sourceWarning: l.hr.warning)
    }
    /// Height of a gauge's pill + source line under its square ring (StatusPill ≈ 22, source 11, spacing 2 × 4).
    static func chipHeight(big: Bool) -> Double { big ? 40 : 37 }
}

/// The classic metric tiles (iOS builds 17–24 tile grid; Details sheet). One builder for both places.
enum RideTiles {
    static func tile(_ key: String, live l: RideLive, recorder: RideRecorder, profile: RiderProfile, boardBattery: Int?, big: Bool = false) -> MetricTile {
        let active = recorder.isActive || recorder.state == .ended
        switch key {
        case "power": return MetricTile(title: "Power", value: l.power.value.map { "\($0)" }, unit: "W", source: l.power.sourceOrMissing, big: big, missing: l.power.missingText)
        case "cadence": return MetricTile(title: "Cadence", value: l.cadence.value.map { "\($0)" }, unit: "rpm", source: l.cadence.sourceOrMissing, big: big, missing: l.cadence.missingText)
        case "hr": return MetricTile(title: "Heart rate", value: l.hr.value.map { "\($0)" }, unit: "bpm", source: l.hr.sourceOrMissing, big: big, missing: l.hr.missingText)
        case "speed": return MetricTile(title: "Speed", value: l.speedKmh.map { String(format: "%.1f", l.imperial ? $0 / 1.609 : $0) }, unit: l.imperial ? "mph" : "km/h", source: l.speed.sourceOrMissing, big: big, missing: l.speed.missingText)
        case "time": return MetricTile(title: "Time", value: active ? recorder.elapsedS.asDuration : nil, unit: "", source: recorder.owner.label, big: big, missing: "starts with the ride")
        case "dist": return MetricTile(title: "Distance", value: active ? String(format: "%.2f", l.imperial ? Double(recorder.distanceM) / 1609.34 : Double(recorder.distanceM) / 1000) : nil, unit: l.imperial ? "mi" : "km", source: recorder.owner == .board ? "BikeComputer (GPS)" : "Phone GPS", big: big, missing: "starts with the ride")
        case "lap": return MetricTile(title: "Lap \(recorder.lapCount)", value: recorder.isActive ? (recorder.elapsedS - recorder.lapStartS).asDuration : nil, unit: "", source: recorder.owner.label, big: big, missing: "starts with the ride")
        case "zone": return MetricTile(title: "Zone", value: l.power.value.map { "Z\(profile.zone(forWatts: $0))" }, unit: "", source: "from FTP \(profile.ftpW) W (\(profile.ftpLabel))", big: big, missing: MetricKind.power.missingText)
        case "np": return MetricTile(title: "Normalized", value: RideRecorder.normalized(recorder.samples.compactMap { $0.w }).map { "\($0)" }, unit: "W", source: "from this ride's power", big: big, missing: "needs power")
        case "battery": return MetricTile(title: "Board battery", value: boardBattery.map { "≈\($0)" }, unit: "%", source: "estimate from voltage", big: big, missing: "no BikeComputer")
        default: return MetricTile(title: key, value: nil, unit: "", source: "", big: big)
        }
    }
}
