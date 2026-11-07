import Foundation

/// Checkpoint F slice 3 (RA-21…RA-23): everything the results page and the saved-ride page show, computed from ONE
/// stored RideRecord (and, for records and comparisons, the other stored rides). Pure Foundation, unit-tested.
/// Honesty rules: a value appears only when the record carries the samples or totals for it; nothing is estimated,
/// smoothed in, or taken from a demo ride; records need real history and say so when there is not enough.
struct RideResultsModel: Equatable {
    struct Stat: Equatable { var key: String; var label: String; var value: String; var unit: String; var source: String }
    struct Step: Equatable { var name: String; var planned: String; var actual: String; var mark: String }   // mark ✓ ! – ·
    struct Record: Equatable { var kind: String; var text: String; var isRecord: Bool }
    struct Input: Equatable {
        var id: UUID; var start: Date; var durationS: Int; var distanceM: Int; var demo = false; var recorder: String
        var avgPower: Int?; var maxPower: Int?; var normalizedPower: Int?; var avgHR: Int?; var maxHR: Int?; var avgCadence: Int?
        var energyValue: Int?; var energyUnit: String?; var energySource: String?
        var sources: [String] = []
        var samples: [RidePerformanceModel.Sample] = []
        var altitudes: [(t: Int, alt: Double)] = []        // only samples that carried an altitude
        var zoneSeconds: [Int] = []                          // Z1… from the board when it sent them, else computed
        var hrSource: String? = nil; var powerSource: String? = nil; var cadenceSource: String? = nil
        var title: String = "Ride"
        static func == (a: Input, b: Input) -> Bool { a.id == b.id && a.durationS == b.durationS && a.distanceM == b.distanceM }
    }
    struct Zones { var ftpKnown: Bool; var ftp: Int; var hrZones: [(lo: Int, hi: Int?)]?; var maxHr: Int }
    struct PlanStep { var name: String; var minutes: Int; var hrZone: Int?; var rpe: ClosedRange<Int> }

    var headline: [Stat]            // distance, moving time, average speed, ascent (ascent only when computable)
    var analysis: [Stat]            // power / heart rate / cadence / energy — only what was recorded
    var zoneSeconds: [Int]; var zoneBasis: String?
    var steps: [Step]; var stepBasis: String
    var records: [Record]; var recordBasis: String
    var coachSummary: String
    var notes: [String]             // honesty notes: gaps, unverified meter, ended without the board …

    // MARK: ascent (RA-21): GPS altitude is noisy, so climbs count only above a threshold and only with usable accuracy
    static func ascentM(_ alts: [(t: Int, alt: Double)], thresholdM: Double = 3, smoothN: Int = 15) -> Int? {
        guard alts.count >= 30 else { return nil }
        // 1) moving average over `smoothN` samples removes the per-second GPS jitter; 2) hysteresis: a gain is counted
        //    only once the smoothed altitude has risen `thresholdM` above the last confirmed level, and a descent of the
        //    same size moves that level down without counting anything.
        var smooth: [Double] = []; var window: [Double] = []
        for a in alts { window.append(a.alt); if window.count > smoothN { window.removeFirst() }; smooth.append(window.reduce(0, +) / Double(window.count)) }
        var total = 0.0; var base = smooth[0]
        for v in smooth.dropFirst() {
            if v - base >= thresholdM { total += v - base; base = v } else if base - v >= thresholdM { base = v }
        }
        return Int(total.rounded())
    }

    static func make(ride r: Input, others: [Input], zones z: Zones, plan: [PlanStep], imperial: Bool) -> RideResultsModel {
        let km = Double(r.distanceM) / 1000, mi = km / 1.609
        let distText = String(format: "%.1f", imperial ? mi : km), distUnit = imperial ? "mi" : "km"
        let hours = Double(r.durationS) / 3600
        let avgSpeed = r.durationS > 0 ? (imperial ? mi : km) / hours : 0
        var headline = [Stat(key: "dist", label: "DISTANCE", value: distText, unit: distUnit, source: "GPS"),
                        Stat(key: "time", label: "MOVING", value: RideCockpitModel.clock(r.durationS), unit: "", source: r.recorder),
                        Stat(key: "speed", label: "AVG SPEED", value: r.durationS > 0 && r.distanceM > 0 ? String(format: "%.1f", avgSpeed) : "—", unit: imperial ? "mph" : "km/h", source: "GPS")]
        if let asc = ascentM(r.altitudes) { headline.append(Stat(key: "ascent", label: "ASCENT", value: imperial ? "\(Int((Double(asc) * 3.281).rounded()))" : "\(asc)", unit: imperial ? "ft" : "m", source: "GPS altitude")) }
        else { headline.append(Stat(key: "ascent", label: "ASCENT", value: "—", unit: "", source: "no usable altitude")) }

        var analysis: [Stat] = []
        if let p = r.avgPower { analysis.append(Stat(key: "power", label: "AVG POWER", value: "\(p)", unit: "W", source: [r.powerSource ?? "Power meter", r.normalizedPower.map { "NP \($0) W" }, r.maxPower.map { "max \($0)" }].compactMap { $0 }.joined(separator: " · "))) }
        else { analysis.append(Stat(key: "power", label: "POWER", value: "—", unit: "", source: "No power meter on this ride")) }
        if let h = r.avgHR { analysis.append(Stat(key: "hr", label: "AVG HR", value: "\(h)", unit: "bpm", source: [r.hrSource ?? "Heart rate", r.maxHR.map { "max \($0)" }].compactMap { $0 }.joined(separator: " · "))) }
        else { analysis.append(Stat(key: "hr", label: "HEART RATE", value: "—", unit: "", source: "No heart-rate source on this ride")) }
        if let c = r.avgCadence { analysis.append(Stat(key: "cad", label: "AVG CADENCE", value: "\(c)", unit: "rpm", source: r.cadenceSource ?? "Cadence")) }
        if let e = r.energyValue, let u = r.energyUnit { analysis.append(Stat(key: "energy", label: "ENERGY", value: "\(e)", unit: u, source: r.energySource ?? "")) }

        // zones: the board's own seconds when present, else from the samples with the same bounds as the live view
        var zoneSeconds = r.zoneSeconds.prefix(5).map { $0 }; var zoneBasis: String? = nil
        if zoneSeconds.reduce(0, +) > 0 { zoneBasis = r.avgPower != nil ? "POWER ZONES · BIKECOMPUTER" : "HEART-RATE ZONES · BIKECOMPUTER" }
        else {
            let perf = RidePerformanceModel.make(samples: r.samples, windowS: Int.max / 2, elapsedS: r.durationS, lapStartS: 0, ftpKnown: z.ftpKnown, ftp: z.ftp, hrZones: z.hrZones, maxHr: z.maxHr, steps: [])
            zoneSeconds = perf.zoneSeconds; zoneBasis = perf.zoneBasis
        }
        if zoneSeconds.count < 5 { zoneSeconds = [] ; zoneBasis = nil }

        // plan vs ride: per step, the lead metric average inside the step window
        let hasPower = r.samples.contains { $0.w != nil }, hasHR = r.samples.contains { $0.hr != nil }
        var steps: [Step] = []; var t0 = 0
        for st in plan {
            let t1 = t0 + st.minutes * 60
            let win = r.samples.filter { $0.t > t0 && $0.t <= t1 }
            let covered = min(r.durationS, t1) - min(r.durationS, t0)
            var planned = st.rpe.lowerBound == st.rpe.upperBound ? "effort \(st.rpe.lowerBound)" : "effort \(st.rpe.lowerBound)–\(st.rpe.upperBound)"
            var actual = covered <= 0 ? "not reached" : (covered < st.minutes * 60 ? "\(RideCockpitModel.clock(covered)) · ended early" : RideCockpitModel.clock(covered))
            var mark = covered <= 0 ? "·" : (covered < st.minutes * 60 ? "–" : "✓")
            if covered > 0, hasPower, z.ftpKnown, z.ftp > 0, let zone = st.hrZone {
                let band = RidePerformanceModel.powerRange(zone, ftp: z.ftp); planned = band.hi.map { "\(band.lo)–\($0) W" } ?? "≥ \(band.lo) W"
                let ws = win.compactMap { $0.w }
                if !ws.isEmpty { let a = ws.reduce(0, +) / ws.count; actual += " · \(a) W"; if mark == "✓" { mark = (a >= band.lo && (band.hi.map { a <= $0 } ?? true)) ? "✓" : "!" } }
            } else if covered > 0, hasHR, let zs = z.hrZones, !zs.isEmpty, let zone = st.hrZone {
                let i = min(zs.count - 1, max(0, zone - 1)); let lo = zs[i].lo, hi = zs[i].hi ?? z.maxHr
                planned = "\(lo)–\(hi) bpm"
                let hs = win.compactMap { $0.hr }
                if !hs.isEmpty { let a = hs.reduce(0, +) / hs.count; actual += " · \(a) bpm"; if mark == "✓" { mark = (a >= lo && a <= hi) ? "✓" : "!" } }
            }
            steps.append(Step(name: st.name, planned: planned, actual: actual, mark: mark)); t0 = t1
        }
        let stepBasis = plan.isEmpty ? "FREE RIDE" : (hasPower && z.ftpKnown ? "TARGET VS ACTUAL · POWER" : hasHR && z.hrZones != nil ? "TARGET VS ACTUAL · HEART RATE" : "TIME ONLY")

        // records and comparisons: stored, non-demo rides only; honest below the thresholds
        let history = others.filter { !$0.demo && $0.id != r.id }
        var records: [Record] = []
        let recordBasis = "\(history.count + 1) RIDE\(history.count == 0 ? "" : "S") ON RECORD"
        if r.demo { records.append(Record(kind: "demo", text: "Demo ride: no records or comparisons.", isRecord: false)) }
        else {
            if !history.isEmpty {
                let longest = history.map(\.distanceM).max() ?? 0
                if r.distanceM > longest, r.distanceM > 0 { records.append(Record(kind: "distance", text: "Longest ride so far: \(distText) \(distUnit) (previous \(String(format: "%.1f", imperial ? Double(longest) / 1609.34 : Double(longest) / 1000)) \(distUnit))", isRecord: true)) }
                if let p20 = best20(r.samples) {
                    let prev = history.compactMap { best20($0.samples) }.max()
                    if let pv = prev { records.append(Record(kind: "power20", text: p20 > pv ? "Best 20 min power: \(p20) W (previous best \(pv) W)" : "20 min power \(p20) W · best so far \(pv) W", isRecord: p20 > pv)) }
                    else { records.append(Record(kind: "power20", text: "20 min power \(p20) W · first ride with a power meter, nothing to compare yet", isRecord: false)) }
                }
                if let h = r.avgHR, let last = history.filter({ $0.title == r.title && $0.avgHR != nil }).max(by: { $0.start < $1.start }), let lh = last.avgHR {
                    let sameSpeed = abs(Self.kmh(r) - Self.kmh(last)) < 2
                    records.append(Record(kind: "hr", text: "Compared with your last \(r.title.lowercased()): avg HR \(h) vs \(lh) bpm" + (sameSpeed ? " at a similar speed" : " (different speed, not comparable)"), isRecord: false))
                }
            }
            let sameType = history.filter { $0.title == r.title }.count + 1
            if sameType < 5 { records.append(Record(kind: "threshold", text: "More comparisons unlock after 5 rides of the same type (\(sameType) on record)", isRecord: false)) }
            if records.isEmpty { records.append(Record(kind: "none", text: "No records yet: this is your first ride on record.", isRecord: false)) }
        }

        // coach summary: rules, from this ride only
        var summary: [String] = []
        if !plan.isEmpty {
            let done = steps.filter { $0.mark == "✓" }.count, over = steps.filter { $0.mark == "!" }.count, short = steps.filter { $0.mark == "–" || $0.mark == "·" }.count
            summary.append("\(done) of \(steps.count) steps completed in their target" + (over > 0 ? ", \(over) outside the band" : "") + (short > 0 ? ", \(short) cut short or not reached" : "") + ".")
        } else { summary.append("Free ride of \(RideCockpitModel.clock(r.durationS)) and \(distText) \(distUnit).") }
        if r.avgPower == nil { summary.append("No power meter was connected, so watts and FTP are not estimated.") }
        if r.avgHR == nil { summary.append("No heart-rate source was connected, so effort is not judged.") }
        if let mh = r.maxHR, let zs = z.hrZones, let top = zs.last?.lo, mh >= top { summary.append("Heart rate reached \(mh) bpm (Zone 5) — plan an easier day next.") }

        var notes: [String] = []
        if r.sources.contains(where: { $0.contains("link was lost") }) { notes.append("Ended on the phone while the BikeComputer was unreachable; the board keeps its own full record.") }
        if r.sources.contains(where: { $0.contains("mirror incomplete") }) { notes.append("The phone's copy of the board ride is incomplete; the BikeComputer history has the full numbers.") }
        if r.samples.contains(where: { $0.w != nil }) && (r.powerSource ?? "").contains("unverified") { notes.append("Power meter not yet verified: watts are advisory.") }

        return RideResultsModel(headline: headline, analysis: analysis, zoneSeconds: zoneSeconds, zoneBasis: zoneBasis, steps: steps, stepBasis: stepBasis,
                                records: records, recordBasis: recordBasis, coachSummary: summary.joined(separator: " "), notes: notes)
    }

    static func kmh(_ r: Input) -> Double { r.durationS > 0 ? Double(r.distanceM) / 1000 / (Double(r.durationS) / 3600) : 0 }
    /// Best 20-minute mean power from 1 Hz samples (needs 1200 s with power).
    static func best20(_ s: [RidePerformanceModel.Sample]) -> Int? {
        let ws = s.map { $0.w }
        guard ws.count >= 1200 else { return nil }
        var best = 0; var sum = 0; var n = 0
        for i in 0..<ws.count {
            if let w = ws[i] { sum += w; n += 1 }
            if i >= 1200, let w = ws[i - 1200] { sum -= w; n -= 1 }
            if i >= 1199, n >= 1080 { best = max(best, sum / max(1, n)) }   // ≥ 90 % of the window must carry power
        }
        return best > 0 ? best : nil
    }
}

/// Ride history (RA-24): search over title, date words, distance and sources; newest first; demo rides never listed.
enum RideHistorySearch {
    static func filter<T>(_ rides: [T], query: String, text: (T) -> String) -> [T] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return rides }
        let terms = q.split(separator: " ").map(String.init)
        return rides.filter { r in let t = text(r).lowercased(); return terms.allSatisfy { t.contains($0) } }
    }
}

/// Apple Health writer decision (owner 7 Nov, RA-25): at most one HealthKit workout per ride.
enum RideHealthWriter: Equatable {
    case watch, phone, none
    /// `watchWorkoutExists`: the Watch recorded (or is recording) its own HealthKit workout for this ride.
    /// `phoneAuthorized`: HealthKit write permission granted on the phone. Denied → .none, and the ride still saves in Cyclift.
    static func decide(recorder: String, watchWorkoutExists: Bool, phoneAuthorized: Bool, alreadyWritten: Bool, demo: Bool) -> RideHealthWriter {
        if demo || alreadyWritten { return .none }
        if watchWorkoutExists { return .watch }
        return phoneAuthorized ? .phone : .none
    }
}
