import Foundation

/// Checkpoint F (owner-approved Ride prototype, 7 Nov 2026). Pure, Foundation-only models behind the three adaptive
/// ride views, so the sensor-matrix rules are unit-tested on Linux and in CI without a simulator (RA-14, RA-19).
///
/// Rules that never bend (RA-14):
///  - the lead metric follows the LIVE sensors: power with a known FTP → power; power without FTP → heart rate leads
///    and watts are shown without a watt target; heart rate only → heart rate; nothing → speed, target by effort;
///  - a missing meter is never shown as "0 W" and FTP is never estimated here; a stale reading is not live.
struct RideCockpitModel: Equatable {
    enum LeadKind: Equatable { case power, heartRate, speed }
    struct Lead: Equatable { var kind: LeadKind; var label: String; var value: String; var unit: String; var target: String; var targetKnown: Bool }
    struct Tile: Equatable { var key: String; var label: String; var value: String; var unit: String; var note: String }
    struct Inputs: Equatable {
        var power: Int? = nil; var powerLive = false; var powerUnverified = false
        var ftpKnown = false; var ftp = 0
        var hr: Int? = nil; var hrLive = false; var hrZonesKnown = false
        var cadence: Int? = nil; var cadenceLive = false; var cadLo = 85; var cadHi = 95
        var speedKmh: Double? = nil; var gpsLive = false
        /// Wording for the GPS note when no fix is live: "GPS lost" only during a ride that had one; "no GPS" before a ride / when location is off.
        var gpsLostText = "GPS lost"
        var distanceM = 0; var elapsedS = 0; var imperial = false
        var targetZone = 2; var powerBand: (lo: Int, hi: Int?)? = nil; var hrBand: (lo: Int, hi: Int)? = nil
        var rpe: ClosedRange<Int>? = nil
        var hrSource: String = "Heart rate"; var powerSource: String = "Power meter"; var cadenceSource: String = "Cadence sensor"
        static func == (a: Inputs, b: Inputs) -> Bool { a.power == b.power && a.hr == b.hr && a.cadence == b.cadence && a.speedKmh == b.speedKmh && a.elapsedS == b.elapsedS && a.distanceM == b.distanceM && a.ftpKnown == b.ftpKnown && a.hrZonesKnown == b.hrZonesKnown && a.powerLive == b.powerLive && a.hrLive == b.hrLive }
    }
    var lead: Lead
    var tiles: [Tile]
    /// Zone rail under the lead number: only when the lead has real zones (power with FTP, or HR with zones).
    var zonesShown: Bool
    var zoneNote: String?
    /// 0…1 position of the lead value on the Z1…Z5 rail (nil when zones are not shown).
    var railPosition: Double?

    static func make(_ i: Inputs) -> RideCockpitModel {
        let p = i.powerLive ? i.power : nil, h = i.hrLive ? i.hr : nil, c = i.cadenceLive ? i.cadence : nil
        let speedText = i.speedKmh.map { String(format: "%.1f", i.imperial ? $0 / 1.609 : $0) } ?? "—"
        let speedUnit = i.imperial ? "mph" : "km/h"
        let distText = String(format: i.imperial ? "%.1f" : "%.1f", i.imperial ? Double(i.distanceM) / 1609.34 : Double(i.distanceM) / 1000)
        let distUnit = i.imperial ? "mi" : "km"
        let effort = i.rpe.map { r in r.lowerBound == r.upperBound ? "effort \(r.lowerBound) of 10" : "effort \(r.lowerBound)–\(r.upperBound) of 10" } ?? "by effort"
        let cadNote = "target \(i.cadLo)–\(i.cadHi)"
        var lead: Lead; var tiles: [Tile] = []; var zones = false; var note: String? = nil; var rail: Double? = nil

        if p != nil, i.ftpKnown, let band = i.powerBand {
            lead = Lead(kind: .power, label: i.powerUnverified ? "POWER · 3 S · UNVERIFIED" : "POWER · 3 S", value: "\(p!)", unit: "W",
                        target: band.hi.map { "\(band.lo)–\($0) W" } ?? "≥ \(band.lo) W", targetKnown: true)
            zones = true; rail = Self.rail(value: Double(p!), ftpOrMax: Double(i.ftp), kind: .power)
            if h != nil { tiles.append(Tile(key: "hr", label: "HEART RATE", value: "\(h!)", unit: "bpm", note: i.hrSource)) }
            tiles.append(Tile(key: "cad", label: "CADENCE", value: c.map(String.init) ?? "—", unit: "rpm", note: c == nil ? "no cadence" : cadNote))
            tiles.append(Tile(key: "speed", label: "SPEED", value: speedText, unit: speedUnit, note: i.gpsLive ? "GPS" : i.gpsLostText))
            if h == nil { tiles.append(Tile(key: "dist", label: "DISTANCE", value: distText, unit: distUnit, note: "GPS")) }
        } else if h != nil, i.hrZonesKnown, let band = i.hrBand {
            lead = Lead(kind: .heartRate, label: "HEART RATE", value: "\(h!)", unit: "bpm", target: "\(band.lo)–\(band.hi) bpm", targetKnown: true)
            zones = true; rail = Self.rail(value: Double(h!), ftpOrMax: Double(band.hi) / Self.hrZoneTop(i.targetZone), kind: .heartRate)
            if p != nil { tiles.append(Tile(key: "power", label: "POWER", value: "\(p!)", unit: "W", note: "no FTP: no watt target")) }
            tiles.append(Tile(key: "cad", label: "CADENCE", value: c.map(String.init) ?? "—", unit: "rpm", note: c == nil ? "no cadence" : cadNote))
            tiles.append(Tile(key: "speed", label: "SPEED", value: speedText, unit: speedUnit, note: i.gpsLive ? "GPS" : i.gpsLostText))
            if p == nil { tiles.append(Tile(key: "dist", label: "DISTANCE", value: distText, unit: distUnit, note: "GPS")) }
        } else if p != nil {
            // power meter but no FTP and no usable heart-rate zones: watts are shown, the target is by effort, no zones
            lead = Lead(kind: .power, label: "POWER · 3 S", value: "\(p!)", unit: "W", target: effort, targetKnown: false)
            note = "FTP not set: no watt target. Targets are by effort; nothing is estimated."
            if h != nil { tiles.append(Tile(key: "hr", label: "HEART RATE", value: "\(h!)", unit: "bpm", note: "no zones yet")) }
            tiles.append(Tile(key: "cad", label: "CADENCE", value: c.map(String.init) ?? "—", unit: "rpm", note: c == nil ? "no cadence" : cadNote))
            tiles.append(Tile(key: "speed", label: "SPEED", value: speedText, unit: speedUnit, note: i.gpsLive ? "GPS" : i.gpsLostText))
        } else if h != nil {
            lead = Lead(kind: .heartRate, label: "HEART RATE", value: "\(h!)", unit: "bpm", target: effort, targetKnown: false)
            note = "Heart-rate zones are not set yet: targets are by effort."
            tiles.append(Tile(key: "cad", label: "CADENCE", value: c.map(String.init) ?? "—", unit: "rpm", note: c == nil ? "no cadence" : cadNote))
            tiles.append(Tile(key: "speed", label: "SPEED", value: speedText, unit: speedUnit, note: i.gpsLive ? "GPS" : i.gpsLostText))
            tiles.append(Tile(key: "dist", label: "DISTANCE", value: distText, unit: distUnit, note: "GPS"))
        } else {
            lead = Lead(kind: .speed, label: "SPEED", value: speedText, unit: speedUnit, target: effort, targetKnown: false)
            note = "No heart-rate or power source live. Targets are by effort; nothing is estimated."
            tiles.append(Tile(key: "cad", label: "CADENCE", value: c.map(String.init) ?? "—", unit: "rpm", note: c == nil ? "no cadence" : cadNote))
            tiles.append(Tile(key: "dist", label: "DISTANCE", value: distText, unit: distUnit, note: i.gpsLive ? "GPS" : i.gpsLostText))
            tiles.append(Tile(key: "time", label: "TIME", value: Self.clock(i.elapsedS), unit: "", note: "moving"))
        }
        // Owner 8 Nov 19:04 — the Cockpit answers one question: the lead metric, at most TWO secondary metrics, the current
        // interval, one coaching instruction and an optional compact map. A sensor that is not there is not a tile ("—");
        // its absence is one line under the lead and in Details. Priority: heart rate / power → cadence → speed → distance → time.
        tiles.removeAll { $0.key == "cad" && c == nil }
        if tiles.count > 2 { tiles = Array(tiles.prefix(2)) }
        return RideCockpitModel(lead: lead, tiles: Array(tiles.prefix(3)), zonesShown: zones, zoneNote: note, railPosition: rail)
    }
    /// Position on a Z1…Z5 rail. Power: 0–120 % FTP maps to 0…1 (Coggan boundaries 55/75/90/105 %). HR: value / zone top.
    static func rail(value: Double, ftpOrMax: Double, kind: LeadKind) -> Double {
        guard ftpOrMax > 0 else { return 0 }
        let pct = value / ftpOrMax
        return min(1, max(0, kind == .power ? pct / 1.2 : pct))
    }
    private static func hrZoneTop(_ zone: Int) -> Double { [0.6, 0.7, 0.8, 0.9, 1.0][min(4, max(0, zone - 1))] }
    static func clock(_ s: Int) -> String { s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60) : String(format: "%d:%02d", s / 60, s % 60) }
}

/// Performance view maths (RA-19): everything from the recorder's 1 Hz samples and the known zones; nothing is
/// interpolated and no metric appears without samples that carry it.
struct RidePerformanceModel: Equatable {
    struct Sample: Equatable { var t: Int; var w: Int?; var cad: Int?; var hr: Int?; var speedCms: Int? }
    struct Series: Equatable { var key: String; var points: [Double?] }   // nil = no sample that second
    struct Rolling: Equatable { var key: String; var label: String; var value: String; var unit: String }
    struct IntervalRow: Equatable { var name: String; var target: String; var actual: String; var done: Bool; var inBand: Bool? }

    var series: [Series]
    var zoneSeconds: [Int]      // Z1…Z5 of the lead metric (power with FTP, else HR with zones), else empty
    var zoneBasis: String?
    var rolling: [Rolling]
    var intervals: [IntervalRow]

    static func make(samples: [Sample], windowS: Int = 1200, elapsedS: Int, lapStartS: Int, ftpKnown: Bool, ftp: Int,
                     hrZones: [(lo: Int, hi: Int?)]?, maxHr: Int, steps: [(name: String, minutes: Int, hrZone: Int?, rpe: ClosedRange<Int>)]) -> RidePerformanceModel {
        let recent = samples.filter { $0.t > elapsedS - windowS }
        var series: [Series] = []
        if recent.contains(where: { $0.w != nil }) { series.append(Series(key: "power", points: recent.map { $0.w.map(Double.init) })) }
        if recent.contains(where: { $0.hr != nil }) { series.append(Series(key: "hr", points: recent.map { $0.hr.map(Double.init) })) }
        if recent.contains(where: { $0.cad != nil }) { series.append(Series(key: "cad", points: recent.map { $0.cad.map(Double.init) })) }
        if series.isEmpty, recent.contains(where: { $0.speedCms != nil }) { series.append(Series(key: "speed", points: recent.map { $0.speedCms.map { Double($0) * 0.036 } })) }

        var zones: [Int] = []; var basis: String? = nil
        let hasPower = samples.contains { $0.w != nil }, hasHR = samples.contains { $0.hr != nil }
        if hasPower, ftpKnown, ftp > 0 {
            zones = Array(repeating: 0, count: 5); basis = "POWER ZONES · FTP \(ftp) W"
            for s in samples { if let w = s.w { zones[powerZoneIndex(w, ftp: ftp)] += 1 } }
        } else if hasHR, let z = hrZones, !z.isEmpty {
            zones = Array(repeating: 0, count: 5); basis = "HEART-RATE ZONES"
            for s in samples { if let h = s.hr { zones[hrZoneIndex(h, zones: z)] += 1 } }
        }

        var rolling: [Rolling] = []
        if hasPower {
            let ws = samples.compactMap { $0.w }
            rolling = [Rolling(key: "3s", label: "3 S", value: avgText(samples.suffix(3).compactMap { $0.w }), unit: "W"),
                       Rolling(key: "30s", label: "30 S", value: avgText(samples.suffix(30).compactMap { $0.w }), unit: "W"),
                       Rolling(key: "lap", label: "LAP", value: avgText(samples.filter { $0.t > lapStartS }.compactMap { $0.w }), unit: "W"),
                       Rolling(key: "np", label: "NORM.", value: normalizedPower(ws).map(String.init) ?? "—", unit: "W")]
        } else if hasHR {
            let hs = samples.compactMap { $0.hr }
            rolling = [Rolling(key: "now", label: "HR NOW", value: samples.last?.hr.map(String.init) ?? "—", unit: "bpm"),
                       Rolling(key: "1m", label: "HR 1 MIN", value: avgText(samples.suffix(60).compactMap { $0.hr }), unit: "bpm"),
                       Rolling(key: "lap", label: "HR LAP", value: avgText(samples.filter { $0.t > lapStartS }.compactMap { $0.hr }), unit: "bpm"),
                       Rolling(key: "max", label: "HR MAX", value: hs.max().map(String.init) ?? "—", unit: "bpm")]
        } else {
            let sp = samples.compactMap { $0.speedCms }.map { Double($0) * 0.036 }
            let f = { (v: Double?) in v.map { String(format: "%.1f", $0) } ?? "—" }
            rolling = [Rolling(key: "now", label: "SPEED", value: f(samples.last?.speedCms.map { Double($0) * 0.036 }), unit: "km/h"),
                       Rolling(key: "avg", label: "AVG", value: f(sp.isEmpty ? nil : sp.reduce(0, +) / Double(sp.count)), unit: "km/h"),
                       Rolling(key: "lap", label: "LAP", value: { let l = samples.filter { $0.t > lapStartS }.compactMap { $0.speedCms }.map { Double($0) * 0.036 }; return f(l.isEmpty ? nil : l.reduce(0, +) / Double(l.count)) }(), unit: "km/h"),
                       Rolling(key: "max", label: "MAX", value: f(sp.max()), unit: "km/h")]
        }

        // intervals: each step's window on the ride clock; actual = average of the lead metric inside it (only once the step has started)
        var rows: [IntervalRow] = []; var t0 = 0
        for st in steps {
            let t1 = t0 + st.minutes * 60
            let inWin = samples.filter { $0.t > t0 && $0.t <= t1 }
            let started = elapsedS > t0, done = elapsedS >= t1
            var target = st.rpe.lowerBound == st.rpe.upperBound ? "effort \(st.rpe.lowerBound)" : "effort \(st.rpe.lowerBound)–\(st.rpe.upperBound)"
            var actual = started ? "—" : "—"; var inBand: Bool? = nil
            if hasPower, ftpKnown, ftp > 0, let z = st.hrZone {
                let r = powerRange(z, ftp: ftp); target = r.hi.map { "\(r.lo)–\($0) W" } ?? "≥ \(r.lo) W"
                let ws = inWin.compactMap { $0.w }
                if started, !ws.isEmpty { let a = ws.reduce(0, +) / ws.count; actual = "\(a) W"; inBand = a >= r.lo && (r.hi.map { a <= $0 } ?? true) }
            } else if hasHR, let zs = hrZones, !zs.isEmpty, let z = st.hrZone {
                let i = min(zs.count - 1, max(0, z - 1)); let lo = zs[i].lo, hi = zs[i].hi ?? maxHr
                target = "\(lo)–\(hi) bpm"
                let hs = inWin.compactMap { $0.hr }
                if started, !hs.isEmpty { let a = hs.reduce(0, +) / hs.count; actual = "\(a) bpm"; inBand = a >= lo && a <= hi }
            } else if started, !inWin.isEmpty { actual = done ? "done" : "running" }
            rows.append(IntervalRow(name: st.name, target: target, actual: actual, done: done, inBand: inBand))
            t0 = t1
        }
        return RidePerformanceModel(series: series, zoneSeconds: zones, zoneBasis: basis, rolling: rolling, intervals: rows)
    }

    // MARK: helpers (same boundaries as CoachCore's PowerZones / HrZones; duplicated here so this file has no dependency)
    static func powerRange(_ zone: Int, ftp: Int) -> (lo: Int, hi: Int?) {
        let b: [(Double, Double?)] = [(0, 0.55), (0.55, 0.75), (0.75, 0.90), (0.90, 1.05), (1.05, nil)]
        let z = b[min(4, max(0, zone - 1))]
        return (Int((Double(ftp) * z.0).rounded()), z.1.map { Int((Double(ftp) * $0).rounded()) })
    }
    /// Same inclusive upper bounds as CoachCore.PowerZones (Z5–Z7 collapsed into the fifth bar).
    static func powerZoneIndex(_ w: Int, ftp: Int) -> Int { let p = Double(w) / Double(ftp); return p <= 0.55 ? 0 : p <= 0.75 ? 1 : p <= 0.90 ? 2 : p <= 1.05 ? 3 : 4 }
    static func hrZoneIndex(_ hr: Int, zones: [(lo: Int, hi: Int?)]) -> Int {
        for (i, z) in zones.prefix(5).enumerated() where hr >= z.lo && (z.hi.map { hr <= $0 } ?? true) { return i }
        return hr < (zones.first?.lo ?? 0) ? 0 : min(4, zones.count - 1)
    }
    static func avgText(_ v: [Int]) -> String { v.isEmpty ? "—" : "\(v.reduce(0, +) / v.count)" }
    /// Normalized power (Coggan): 30 s rolling average, 4th-power mean, 4th root; needs ≥ 30 s of power.
    static func normalizedPower(_ w: [Int]) -> Int? {
        guard w.count >= 30 else { return nil }
        var sum = 0.0; var n = 0; var window = 0
        for i in 0..<w.count { window += w[i]; if i >= 30 { window -= w[i - 30] }; if i >= 29 { let a = Double(window) / 30; sum += a * a * a * a; n += 1 } }
        return n > 0 ? Int(pow(sum / Double(n), 0.25).rounded()) : nil
    }
}

/// Map view state (RA-17, RA-18): GPS is "lost" when the last fix is older than `staleAfterS`; recording continues
/// and distance holds (the recorder already ignores old fixes), so this only decides what the screen says.
enum RideGPSState: Equatable {
    case off, searching, good, lost
    static func make(sharing: Bool, lastFixAgeS: Double?, authorized: Bool, staleAfterS: Double = 10) -> RideGPSState {
        guard authorized, sharing else { return .off }
        guard let a = lastFixAgeS else { return .searching }
        return a <= staleAfterS ? .good : .lost
    }
    var label: String { switch self { case .off: return "GPS OFF"; case .searching: return "GPS …"; case .good: return "GPS"; case .lost: return "GPS LOST" } }
    var banner: String? { self == .lost ? "GPS signal lost · recording continues · distance holds until it returns" : nil }
}
