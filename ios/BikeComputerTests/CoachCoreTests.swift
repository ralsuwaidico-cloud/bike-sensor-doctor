import XCTest
@testable import BikeComputer

/// Runs every shared coach vector (testvectors/coach, copied into the test bundle) through the Swift CoachEngine —
/// the same files the Kotlin (Nokia) engine and the firmware port must pass. Plus the Targets / zone rules from
/// TargetsTest.kt and the live-graph scaling rules from LiveGraphTest.kt.
final class CoachCoreTests: XCTestCase {
    private func config(_ line: String) -> CoachConfig {
        let kv = line.replacingOccurrences(of: "# config:", with: "").split(separator: " ").filter { $0.contains("=") }
            .reduce(into: [String: String]()) { d, s in let p = s.split(separator: "=", maxSplits: 1); d[String(p[0])] = String(p[1]) }
        var c = CoachConfig()
        c.mode = kv["mode"].flatMap { CoachMode(rawValue: $0) } ?? .ZONE2
        c.ftpW = kv["ftp"].flatMap { Int($0) } ?? 200; c.maxHr = kv["maxHr"].flatMap { Int($0) } ?? 185
        c.cadenceEnabled = (kv["cadence"] ?? "on") == "on"
        c.cadenceLow = kv["cadLow"].flatMap { Int($0) } ?? 85; c.cadenceHigh = kv["cadHigh"].flatMap { Int($0) } ?? 95
        c.effortSource = kv["source"] == "HR" ? .heartRate : kv["source"] == "POWER" ? .power : .auto
        func ms(_ k: String, _ d: Int64) -> Int64 { kv[k].flatMap { Int64($0) } ?? d }
        c.effortHoldMs = ms("hrHoldMs", c.effortHoldMs); c.powerHoldMs = ms("powerHoldMs", c.powerHoldMs)
        c.surgeHoldMs = ms("surgeHoldMs", c.surgeHoldMs); c.cadenceHoldMs = ms("cadHoldMs", c.cadenceHoldMs)
        c.minAlertMs = ms("minAlertMs", c.minAlertMs); c.sameRepeatMs = ms("sameRepeatMs", c.sameRepeatMs)
        c.keepRepeatMs = ms("keepRepeatMs", c.keepRepeatMs); c.smoothingMs = ms("smoothingMs", c.smoothingMs)
        return c
    }

    func testAllCoachVectorsPass() throws {
        let b = Bundle(for: CoachCoreTests.self)
        let urls = (b.urls(forResourcesWithExtension: "txt", subdirectory: "coach") ?? []) + (b.urls(forResourcesWithExtension: "txt", subdirectory: nil) ?? [])
        let files = urls.filter { $0.lastPathComponent != "README.txt" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
        XCTAssertFalse(files.isEmpty, "no coach vectors in the test bundle")
        var failures: [String] = []; var asserted = 0
        for f in files {
            let lines = try String(contentsOf: f).components(separatedBy: "\n")
            var cfg = CoachConfig(); cfg.mode = .ZONE2
            if let cl = lines.first(where: { $0.hasPrefix("# config:") }) { cfg = config(cl) }
            let engine = CoachEngine(config: cfg)
            var lastT: Int64 = -1
            for l in lines {
                let line = l.trimmingCharacters(in: .whitespaces)
                if line.isEmpty || line.hasPrefix("#") { continue }
                let p = line.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                let t = Int64(p[0])!; XCTAssertGreaterThan(t, lastT, "\(f.lastPathComponent): ticks must increase"); lastT = t
                let phase = Phase(rawValue: p[1])!
                func sig(_ s: String) -> Signal { Int(s).map { Signal(value: $0, fresh: true) } ?? .none }
                let cue = engine.update(CoachInput(nowMs: t, phase: phase, cadence: sig(p[2]), hr: sig(p[3]), power: sig(p[4])))
                let expect = p.count > 5 ? p[5] : ""
                if expect.isEmpty { continue }
                asserted += 1
                if cue.type.rawValue != expect { failures.append("\(f.lastPathComponent) t=\(t): expected \(expect), got \(cue.type.rawValue) (\(cue.reason))") }
            }
        }
        XCTAssertGreaterThan(asserted, 100)
        XCTAssertTrue(failures.isEmpty, "\(failures.count) of \(asserted) vector assertions failed:\n" + failures.prefix(25).joined(separator: "\n"))
    }

    // MARK: Targets (TargetsTest.kt)
    func testPowerStatusAgainstZone2() {
        XCTAssertEqual(Targets.power(80, ftp: 200, targetZone: 2), .below)
        XCTAssertEqual(Targets.power(130, ftp: 200, targetZone: 2), .on)
        XCTAssertEqual(Targets.power(170, ftp: 200, targetZone: 2), .above)
        XCTAssertEqual(Targets.power(0, ftp: 200, targetZone: 2), .unknown)
        XCTAssertEqual(Targets.power(nil, ftp: 200, targetZone: 2), .unknown)
    }
    func testHRAndCadenceStatus() {
        XCTAssertEqual(Targets.hr(100, maxHr: 185, targetZone: 2), .below)
        XCTAssertEqual(Targets.hr(120, maxHr: 185, targetZone: 2), .on)
        XCTAssertEqual(Targets.hr(150, maxHr: 185, targetZone: 2), .above)
        XCTAssertEqual(Targets.hr(nil, maxHr: 185, targetZone: 2), .unknown)
        XCTAssertEqual(Targets.cadence(72, low: 85, high: 95), .below)
        XCTAssertEqual(Targets.cadence(85, low: 85, high: 95), .on)
        XCTAssertEqual(Targets.cadence(95, low: 85, high: 95), .on)
        XCTAssertEqual(Targets.cadence(96, low: 85, high: 95), .above)
        XCTAssertEqual(Targets.cadence(0, low: 85, high: 95), .unknown)
    }
    func testGaugeScaleAndFractions() {
        XCTAssertEqual(Targets.powerGaugeMaxW(ftp: 200), 300)
        XCTAssertEqual(Targets.powerGaugeMaxW(ftp: 210), 315)
        XCTAssertEqual(Targets.powerGaugeMaxW(ftp: 150), 300)
        XCTAssertEqual(Targets.gaugeFraction(150, max: 300), 0.5, accuracy: 1e-6)
        XCTAssertEqual(Targets.gaugeFraction(900, max: 300), 1, accuracy: 1e-6)
        XCTAssertEqual(Targets.gaugeFraction(nil, max: 300), 0, accuracy: 1e-6)
        XCTAssertEqual(Targets.powerTargetFraction(targetZone: 2, ftp: 200), 130.0 / 300.0, accuracy: 1e-4)
        XCTAssertEqual(Targets.hrTargetFraction(targetZone: 2), 0.65, accuracy: 1e-6)
        XCTAssertEqual(Targets.hrTargetFraction(targetZone: 3), 0.75, accuracy: 1e-6)
        let t = Targets.powerZoneTicks(ftp: 200)
        XCTAssertEqual(t.count, 6); for i in 1..<t.count { XCTAssertGreaterThanOrEqual(t[i], t[i - 1]) }
        XCTAssertEqual(t[0], 0.55 * 200 / 300, accuracy: 1e-5)
    }
    func testZonePercentAndShapes() {
        XCTAssertEqual(Targets.powerZonePercent(110, ftp: 200), 100)
        XCTAssertEqual(Targets.powerZonePercent(130, ftp: 200), 50)
        XCTAssertEqual(Targets.powerZonePercent(150, ftp: 200), 100)
        XCTAssertNil(Targets.powerZonePercent(0, ftp: 200))
        XCTAssertEqual(Targets.coachShape(.PEDAL_FASTER), .up); XCTAssertEqual(Targets.coachDirection(.PEDAL_FASTER), 1)
        XCTAssertEqual(Targets.coachShape(.KEEP_IT_UP), .check); XCTAssertEqual(Targets.coachDirection(.KEEP_IT_UP), 0)
        XCTAssertEqual(Targets.coachShape(.EASE_OFF), .down); XCTAssertEqual(Targets.coachDirection(.EASE_OFF), -1)
        XCTAssertEqual(Targets.coachShape(.NO_HR), .none)
        XCTAssertEqual(Targets.targetZone(.ZONE2), 2); XCTAssertEqual(Targets.targetZone(.ENDURANCE), 3)
    }
    func testZoneRanges() {
        XCTAssertEqual(PowerZones.range(2, ftp: 200).lo, 110); XCTAssertEqual(PowerZones.range(2, ftp: 200).hi, 150)
        XCTAssertNil(PowerZones.range(7, ftp: 200).hi)
        XCTAssertEqual(PowerZones.zone(151, ftp: 200), 3); XCTAssertEqual(HrZones.zone(120, maxHr: 185), 2)
    }

    // MARK: Live graph scaling (LiveGraphTest.kt)
    func testNormalisationIsPerSignalAgainstItsOwnBand() {
        XCTAssertEqual(GraphScale.norm(150, lo: 100, hi: 200), 0.5)
        XCTAssertEqual(GraphScale.norm(100, lo: 100, hi: 200), 0)
        XCTAssertEqual(GraphScale.norm(250, lo: 100, hi: 200), 1.5)
        XCTAssertNil(GraphScale.norm(nil, lo: 100, hi: 200)); XCTAssertNil(GraphScale.norm(5, lo: nil, hi: 200)); XCTAssertNil(GraphScale.norm(5, lo: 200, hi: 100))
        // band edges map to the same plot height for every signal
        XCTAssertEqual(GraphScale.yFrac(1), GraphScale.bandTop); XCTAssertEqual(GraphScale.yFrac(0), GraphScale.bandBot)
        XCTAssertLessThan(GraphScale.bandTop, GraphScale.bandBot)
        XCTAssertEqual(GraphScale.yFrac(0.5), 0.5, accuracy: 1e-9)
        XCTAssertLessThan(GraphScale.yFrac(5), GraphScale.yFrac(2)); XCTAssertGreaterThanOrEqual(GraphScale.yFrac(100), 0.01)
    }
    func testStatusKeepsZeroAsAValue() {
        XCTAssertEqual(GraphScale.status(nil, lo: 100, hi: 200), .none)
        XCTAssertEqual(GraphScale.status(0, lo: 100, hi: 200), .zero)
        XCTAssertEqual(GraphScale.status(90, lo: 100, hi: 200), .below)
        XCTAssertEqual(GraphScale.status(150, lo: 100, hi: 200), .on)
        XCTAssertEqual(GraphScale.status(210, lo: 100, hi: 200), .above)
    }
    func testFallbackBandsComeFromZones() {
        let b = GraphBands.resolve(targets: nil, ftpW: 200, powerTrusted: true, maxHr: 185, targetZone: 2, cadLo: 85, cadHi: 95)
        XCTAssertEqual(b.pwLo, 111); XCTAssertEqual(b.pwHi, 150); XCTAssertEqual(b.hrLo, 112); XCTAssertEqual(b.hrHi, 129); XCTAssertFalse(b.pwReference)
        let u = GraphBands.resolve(targets: nil, ftpW: 200, powerTrusted: false, maxHr: 185, targetZone: 2, cadLo: 85, cadHi: 95)
        XCTAssertTrue(u.pwReference)
        let t = ActiveTargets(hrLo: 120, hrHi: 140, pwLo: 130, pwHi: 160, cadLo: 85, cadHi: 95, label: "MAIN")
        let w = GraphBands.resolve(targets: t, ftpW: 200, powerTrusted: true, maxHr: 185, targetZone: 2, cadLo: 85, cadHi: 95)
        XCTAssertEqual(w.pwLo, 130); XCTAssertEqual(w.hrHi, 140)
    }
    func testSessionPhasesAndWorkoutRamps() {
        let plan = SessionPlan(warmupSec: 300, cooldownSec: 300, plannedSec: 3600)
        XCTAssertEqual(Session.phaseAt(plan, elapsedMs: 10_000, cooldownRequestedAtMs: nil), .WARMUP)
        XCTAssertEqual(Session.phaseAt(plan, elapsedMs: 400_000, cooldownRequestedAtMs: nil), .MAIN)
        XCTAssertEqual(Session.phaseAt(plan, elapsedMs: 3_400_000, cooldownRequestedAtMs: nil), .COOLDOWN)
        XCTAssertEqual(Session.phaseAt(plan, elapsedMs: 1_000_000, cooldownRequestedAtMs: 900_000), .COOLDOWN)
        let wp = WorkoutPlan(hrLo: 120, hrHi: 140, pwLo: 130, pwHi: 160, cadLo: 85, cadHi: 95, ftp: 200, warmupSec: 300, cooldownSec: 300)
        let w0 = WorkoutTargets.forPhase(wp, phase: .WARMUP, elapsedSec: 0, cooldownStartSec: nil)
        XCTAssertEqual(w0.hrHi, 110); XCTAssertEqual(w0.pwHi, 100); XCTAssertEqual(w0.hrLo, 105)
        let w1 = WorkoutTargets.forPhase(wp, phase: .WARMUP, elapsedSec: 300, cooldownStartSec: nil)
        XCTAssertEqual(w1.hrHi, 140); XCTAssertEqual(w1.pwHi, 160)
        XCTAssertEqual(WorkoutTargets.forPhase(wp, phase: .MAIN, elapsedSec: 600, cooldownStartSec: nil).label, "MAIN")
        XCTAssertEqual(WorkoutTargets.forPhase(wp, phase: .RECOVERY, elapsedSec: 600, cooldownStartSec: nil).hrHi, 119)
    }

    // MARK: Power-Focus geometry (DashLayoutTest.kt)
    @discardableResult private func check(_ w: Double, _ maxH: Double, _ labelH: Double, _ chipH: Double, _ chipW: Double) -> PowerFocusGeometry {
        let g = PowerFocus.compute(contentW: w, maxBlockH: maxH, labelH: labelH, chipH: chipH, chipW: chipW)
        XCTAssertTrue(PowerFocus.ringsClear(g), "rings clear \(g)")
        XCTAssertGreaterThanOrEqual(g.power, g.small * 1.35)
        XCTAssertTrue(g.xRight + g.colSmall <= w + 0.5 && g.xLeft >= 0 && g.xPower >= 0 && g.xPower + g.colPower <= w + 0.5, "fits width \(g)")
        XCTAssertTrue(g.blockHeight <= maxH + 1 || g.power <= w * 0.44 * 0.56, "fits height \(g) max \(maxH)")
        XCTAssertGreaterThanOrEqual(g.powerCenter.y - g.power / 2, labelH - 0.5)
        return g
    }
    func testGeometryNormalFontGivesALargePowerRing() {
        let g = check(340, 240, 13, 20, 96)
        XCTAssertGreaterThanOrEqual(g.power, 140); XCTAssertGreaterThanOrEqual(g.small, 96)
    }
    func testGeometryLargeFontShrinksButNeverOverlaps() {
        let g = check(340, 190, 17, 25, 110)
        XCTAssertLessThanOrEqual(g.blockHeight, 191)
    }
    func testGeometryIPhoneSizesNeverOverlap() {
        // iPhone SE (375 − 28 pad), 13 mini, 14/15, Plus/Max widths × the heights the Ride screen can offer
        for w in [347.0, 362.0, 365.0, 402.0, 416.0] { for h in [150.0, 190.0, 230.0, 280.0, 320.0] { check(w, h, 0, 24, 112) } }
    }
    func testGaugeTextNeverDressesUpMissingData() {
        XCTAssertEqual(GaugeText.status(.unknown, kind: "pow", signal: .fresh), "COASTING")
        XCTAssertEqual(GaugeText.status(.unknown, kind: "pow", signal: .none), "NO SENSOR")
        XCTAssertEqual(GaugeText.status(.unknown, kind: "pow", signal: .stale), "NO SIGNAL")
        XCTAssertEqual(GaugeText.status(.unknown, kind: "cad", signal: .fresh), "NOT TURNING")
        XCTAssertEqual(GaugeText.status(.unknown, kind: "hr"), "NO HR SOURCE")
        XCTAssertEqual(GaugeText.status(.on, kind: "hr"), "ON TARGET")
        XCTAssertEqual(GaugeText.status(.below, kind: "cad"), "BELOW RANGE"); XCTAssertEqual(GaugeText.status(.above, kind: "pow"), "ABOVE TGT")
    }
    func testRideCoachTicksOnlyRealSignalsAndKeepsAWindow() {
        let rc = RideCoach()
        var p = RiderProfile(); p.ftpW = 200; p.maxHR = 185; p.ftpHow = .tested
        var s = AppSettings(); s.coachEnabled = true
        rc.configure(profile: p, settings: s, workout: Workout(date: Date(), kind: .endurance, minutes: 60), powerTrusted: false)
        XCTAssertEqual(rc.targetZone, 2); XCTAssertTrue(rc.bands.pwReference)
        for t in 0..<400 { rc.tick(elapsedS: t, cadence: nil, hr: nil, power: nil, speedKmh: nil) }
        XCTAssertEqual(rc.samples.count, RideCoach.keepSeconds)
        XCTAssertTrue(rc.samples.allSatisfy { $0.powerW == nil && $0.hr == nil })
        XCTAssertEqual(rc.phase, .MAIN)
        // warm-up announced once, nothing invented afterwards without sensors
        XCTAssertTrue([CueType.WARMUP, .NO_HR, .WORK, .KEEP_IT_UP].contains(rc.cue.type))
        s.coachEnabled = false; rc.configure(profile: p, settings: s, workout: nil, powerTrusted: false)
        rc.reset(); rc.tick(elapsedS: 0, cadence: 90, hr: 150, power: 300, speedKmh: 30)
        XCTAssertEqual(rc.cue.type, .NONE)                                       // FREE mode never speaks
    }
}
