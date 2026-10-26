import XCTest
import Combine
@testable import BikeComputer

/// Cyclift ride layouts + the embedded coach panel (docs/briefs/CYCLIFT_CONTRACTS.md, "Ride layout contract").
final class RideLayoutTests: XCTestCase {

    private func tempStore() -> (Store, URL) {
        let u = FileManager.default.temporaryDirectory.appendingPathComponent("ridelayout-\(UUID().uuidString)", isDirectory: true)
        return (Store(directory: u, generatePlan: false), u)
    }

    // MARK: persistence

    func testLayoutRoundTripsAndDefaultsToCoach() throws {
        var s = AppSettings()
        XCTAssertEqual(s.rideLayout, .coach, "new installs start on the Ride Coach layout")
        for l in RideLayout.allCases {
            s.rideLayout = l
            let back = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(s))
            XCTAssertEqual(back.rideLayout, l)
        }
        // a store from an older build has no key → default, everything else intact
        let old = #"{"units":"imperial","phoneOnlyMode":false,"hrPref":"watch","keepScreenOn":true,"coachTalk":"quiet","coachEnabled":true}"#
        let d = try JSONDecoder().decode(AppSettings.self, from: Data(old.utf8))
        XCTAssertEqual(d.rideLayout, .coach); XCTAssertEqual(d.units, .imperial); XCTAssertEqual(d.coachTalk, .quiet); XCTAssertEqual(d.hrPref, .watch)
        // an unknown value written by a newer build must not lose the other settings
        let future = #"{"units":"metric","rideLayout":"hologram","coachEnabled":false}"#
        let f = try JSONDecoder().decode(AppSettings.self, from: Data(future.utf8))
        XCTAssertEqual(f.rideLayout, .coach); XCTAssertFalse(f.coachEnabled)
    }

    func testLayoutIsRememberedBetweenLaunches() {
        let (s1, dir) = tempStore()
        RideLayoutSwitch.select(.analytics, store: s1)
        let s2 = Store(directory: dir, generatePlan: false)
        XCTAssertEqual(s2.settings.rideLayout, .analytics)
        RideLayoutSwitch.select(.rings, store: s2)
        XCTAssertEqual(Store(directory: dir, generatePlan: false).settings.rideLayout, .rings)
    }

    func testRawValuesMatchTheContract() {
        XCTAssertEqual(RideLayout.allCases.map(\.rawValue), ["coach", "gauges", "classic", "rings", "analytics"])
        XCTAssertEqual(Set(RideLayout.allCases.map(\.title)).count, 5, "distinct titles for the selector")
    }

    // MARK: switching never touches the recorder, the hub or BLE

    func testSwitchingLayoutDoesNotTouchRecorderOrHub() {
        let (store, _) = tempStore()
        let recorder = RideRecorder(autoTick: false)
        let hub = SensorHub()
        let t = Date()
        hub.now = { t }
        hub.offer(MetricReading(kind: .heartRate, value: 141, at: t, source: SensorHub.watch, quality: .good))
        let before = (recorder.state, recorder.owner, recorder.elapsedS, recorder.distanceM, recorder.samples.count, recorder.lapCount)
        let hubBefore = hub.candidates
        var recorderChanges = 0, hubChanges = 0
        let c1 = recorder.objectWillChange.sink { recorderChanges += 1 }
        let c2 = hub.objectWillChange.sink { hubChanges += 1 }
        for l in RideLayout.allCases + RideLayout.allCases.reversed() {
            RideLayoutSwitch.select(l, store: store)
            XCTAssertEqual(store.settings.rideLayout, l)
        }
        c1.cancel(); c2.cancel()
        XCTAssertEqual(recorderChanges, 0, "the recorder must not even be notified")
        XCTAssertEqual(hubChanges, 0, "the hub must not be touched")
        XCTAssertTrue(before == (recorder.state, recorder.owner, recorder.elapsedS, recorder.distanceM, recorder.samples.count, recorder.lapCount))
        XCTAssertEqual(hub.candidates[.heartRate]?.count, hubBefore[.heartRate]?.count)
        XCTAssertEqual(hub.reading(.heartRate)?.intValue, 141)
    }

    // MARK: labels: the metric, never a brand

    func testNoBrandInAnyLabelConstant() {
        let brands = ["XDS", "Garmin", "Wahoo", "Polar", "WHOOP", "Oura", "Favero", "Stages"]
        for label in RideLabels.all { for b in brands { XCTAssertFalse(label.localizedCaseInsensitiveContains(b), "label '\(label)' names \(b)") } }
        XCTAssertEqual(RideLabels.power, "POWER · W")
        // the panel text for every sensor subset is brand-free too
        for m in subsetModels() { for b in brands { XCTAssertFalse((m.headline + m.detail + m.why + m.tags.joined()).contains(b)) } }
    }

    func testMissingMetricsSayNoSourceAndSourcesComeFromTheHub() {
        let t = Date()
        var meter = SensorHub.bikeComputer; meter.name = "Power meter"; meter.relayedBy = "BikeComputer"
        let live = RideLive(power: MetricReading(kind: .power, value: 180, at: t, source: meter, quality: .unverified), hr: nil,
                            cadence: nil, speed: MetricReading(kind: .speed, value: 28.4, at: t, source: SensorHub.phoneGPS, quality: .estimated),
                            profile: RiderProfile(), imperial: false, targetZone: 2)
        XCTAssertEqual(live.power.sourceLine, "Power meter via BikeComputer · unverified")
        XCTAssertTrue(live.power.unverified); XCTAssertTrue(live.power.warning)
        XCTAssertEqual(live.statusText(live.hr), "NO HEART-RATE SOURCE")
        XCTAssertEqual(live.statusText(live.cadence), "NO CADENCE SOURCE")
        XCTAssertNil(live.hr.value)
        XCTAssertEqual(live.speed.sourceLine, "Phone GPS · estimated")
        let none = RideLive(power: nil, hr: nil, cadence: nil, speed: nil, profile: RiderProfile(), imperial: false, targetZone: 2)
        XCTAssertEqual(none.power.sourceOrMissing, "No power source")
        XCTAssertEqual(none.speedText, "—")
        // a stale reading is never shown as live
        let stale = RideLive(power: MetricReading(kind: .power, value: 200, at: t, source: meter, quality: .stale), hr: nil, cadence: nil, speed: nil, profile: RiderProfile(), imperial: false, targetZone: 2)
        XCTAssertNil(stale.power.value); XCTAssertEqual(stale.statusText(stale.power), "NO POWER SOURCE")
    }

    // MARK: coach panel per sensor subset

    private func riding(_ f: (inout CoachPanelModel.Inputs) -> Void) -> CoachPanelModel {
        var i = CoachPanelModel.Inputs(); i.recording = true; i.phase = .MAIN; i.hrBand = (130, 148); i.powerBand = (115, 157)
        f(&i); return CoachPanelModel.make(i)
    }
    private func subsetModels() -> [CoachPanelModel] {
        [riding { _ in }, riding { $0.hr = 140 }, riding { $0.cadence = 88 }, riding { $0.speedKmh = 27; $0.speedSource = "Phone GPS" },
         riding { $0.power = 150; $0.powerUnverified = true }, riding { $0.power = 150; $0.hr = 140; $0.cadence = 90 }]
    }

    func testCoachPanelWithNoSensorsGuidesByFeel() {
        let m = riding { _ in }
        XCTAssertEqual(m.headline, "Ride by feel")
        XCTAssertTrue(m.detail.contains("RPE"), m.detail)
        XCTAssertTrue(m.why.contains("heart-rate source") && m.why.contains("power meter"), "says which sensors would help: \(m.why)")
        XCTAssertFalse(m.detail.contains(" W") || m.detail.contains("bpm"), "no invented values")
    }

    func testCoachPanelHeartRateOnly() {
        let m = riding { $0.hr = 140 }
        XCTAssertEqual(m.headline, "Maintain current effort")
        XCTAssertTrue(m.detail.contains("heart rate")); XCTAssertFalse(m.detail.contains("power"))
        XCTAssertTrue(m.why.contains("130–148 bpm") && m.why.contains("now 140"), m.why)
        XCTAssertFalse(m.why.contains("Power 115"), "no power target claimed without power")
    }

    func testCoachPanelCadenceOnly() {
        let m = riding { $0.cadence = 78 }
        XCTAssertTrue(m.headline.contains("85–95 rpm"), m.headline)
        XCTAssertTrue(m.detail.contains("78 rpm") && m.detail.contains("RPE"), m.detail)
        XCTAssertTrue(m.why.contains("heart-rate source"))
    }

    func testCoachPanelSpeedOnly() {
        let m = riding { $0.speedKmh = 27.3; $0.speedSource = "Phone GPS" }
        XCTAssertTrue(m.headline.contains("steady pace"))
        XCTAssertTrue(m.detail.contains("27.3 km/h"))
        XCTAssertTrue(m.why.contains("Phone GPS"))
    }

    func testUnverifiedPowerAdviceIsProvisional() {
        var cue = CoachCue(type: .EASE_OFF, headline: "REDUCE PRESSURE ON THE PEDALS", detail: "Power above target — zone 4, aim for 2", spoken: "", reason: "PW_ABOVE",
                           action: .REDUCE_PRESSURE, sources: "power", live: "190 W", short: "Ease off — power above target", why: "190 W vs zone 2")
        let m = riding { $0.power = 190; $0.powerUnverified = true; $0.ftpProvisional = true; $0.cue = cue; $0.cueActive = true }
        XCTAssertEqual(m.headline, "Reduce intensity to return to Zone 2")
        XCTAssertTrue(m.tags.contains(RideLabels.provisional)); XCTAssertTrue(m.tags.contains(RideLabels.ftpProvisional))
        XCTAssertTrue(m.detail.hasPrefix("Provisional"))
        XCTAssertTrue(m.why.contains("190 W") && m.why.contains("provisional"), m.why)
        // verified power + entered FTP → no provisional marks
        cue.live = "190 W"
        let v = riding { $0.power = 190; $0.cue = cue; $0.cueActive = true }
        XCTAssertTrue(v.tags.isEmpty); XCTAssertFalse(v.detail.hasPrefix("Provisional"))
        // an HR-based cue is not marked provisional just because the meter is unverified
        let hrCue = CoachCue(type: .PUSH_HARDER, headline: "INCREASE YOUR EFFORT SLIGHTLY", detail: "Heart rate 120 below target zone 2", spoken: "", reason: "HR_BELOW", action: .INCREASE_EFFORT, sources: "HR", live: "HR 120", short: "Push a little — HR below target", why: "HR 120 vs zone 2")
        let h = riding { $0.hr = 120; $0.power = 150; $0.powerUnverified = true; $0.cue = hrCue; $0.cueActive = true }
        XCTAssertEqual(h.headline, "Increase effort slightly")
        XCTAssertFalse(h.tags.contains(RideLabels.provisional))
    }

    func testPanelStatesBeforeAndOutsideTheRide() {
        var i = CoachPanelModel.Inputs(); i.startHint = "this phone records"
        XCTAssertEqual(CoachPanelModel.make(i).headline, "Ready")
        i.coachEnabled = false
        XCTAssertEqual(CoachPanelModel.make(i).headline, "Coach off")
        i.coachEnabled = true; i.recording = true; i.paused = true
        XCTAssertEqual(CoachPanelModel.make(i).headline, "Paused")
        i.paused = false; i.phase = .RECOVERY
        XCTAssertEqual(CoachPanelModel.make(i).headline, "Recover for the next interval")
    }

    func testWordingCoversTheBriefInstructions() {
        func w(_ a: CoachAction) -> String { CoachWording.instruction(CoachCue(type: .KEEP_IT_UP, headline: "", detail: "", spoken: "", action: a), targetZone: 2) }
        XCTAssertEqual(w(.STABLE_MAINTAIN), "Maintain current effort")
        XCTAssertEqual(w(.PEDAL_FASTER), "Increase cadence slightly")
        XCTAssertEqual(w(.EASIER_GEAR), "Shift to an easier gear")
        XCTAssertEqual(w(.REDUCE_PRESSURE), "Reduce intensity to return to Zone 2")
        XCTAssertEqual(w(.RECOVER), "Recover for the next interval")
    }

    // MARK: cue rate limit (≥ 15 s on screen unless clearly necessary)

    private func cue(_ t: CueType, _ reason: String = "") -> CoachCue { CoachCue(type: t, headline: t.rawValue, detail: "", spoken: "", reason: reason) }

    func testCueGateHoldsEachCueFifteenSeconds() {
        var g = CueGate()
        XCTAssertTrue(g.offer(cue(.PUSH_HARDER, "HR_BELOW"), nowMs: 0))
        XCTAssertFalse(g.offer(cue(.PEDAL_FASTER, "CAD_LOW"), nowMs: 10_000), "a different cue 10 s later waits")
        XCTAssertEqual(g.shown.type, .PUSH_HARDER)
        for s in 11...14 { XCTAssertFalse(g.offer(.none, nowMs: Int64(s) * 1000)) }
        XCTAssertTrue(g.offer(.none, nowMs: 15_000), "the waiting cue appears when the hold ends")
        XCTAssertEqual(g.shown.type, .PEDAL_FASTER)
        // a pending cue that waited too long is dropped (the engine repeats it if it still applies)
        var h = CueGate(); h.pendingMaxAgeMs = 3_000
        _ = h.offer(cue(.PUSH_HARDER), nowMs: 0); _ = h.offer(cue(.EASE_OFF), nowMs: 1_000)
        XCTAssertFalse(h.offer(.none, nowMs: 15_000)); XCTAssertEqual(h.shown.type, .PUSH_HARDER)
    }

    func testCueGateLetsNecessaryCuesThrough() {
        var g = CueGate()
        _ = g.offer(cue(.KEEP_IT_UP, "ALL_GOOD"), nowMs: 0)
        XCTAssertTrue(g.offer(cue(.EASE_OFF, "HR_SAFETY"), nowMs: 2_000), "safety ease-off is never held back")
        XCTAssertTrue(g.offer(cue(.SENSOR_LOST, "POWER_LOST"), nowMs: 3_000), "a lost sensor is said at once")
        XCTAssertTrue(g.offer(cue(.RECOVER, "PHASE_RECOVERY"), nowMs: 4_000), "phase changes are said at once")
        XCTAssertFalse(g.offer(cue(.PUSH_HARDER, "HR_BELOW"), nowMs: 5_000))
    }

    func testRideCoachShowsAtMostOneCueChangePerFifteenSeconds() {
        let c = RideCoach()
        var p = RiderProfile(); p.ftpW = 200; p.ftpHow = .entered
        var s = AppSettings(); s.coachTalk = .frequent
        c.configure(profile: p, settings: s, workout: nil, powerTrusted: true)
        var changes: [(Int, CoachCue)] = []; var last = CoachCue.none
        // warm-up then a main block where the effort swings every 9 s between far below and far above target
        for t in 0..<900 {
            let hi = (t / 9) % 2 == 0
            c.tick(elapsedS: t, cadence: hi ? 105 : 70, hr: hi ? 175 : 100, power: hi ? 300 : 90, speedKmh: 28)
            if c.cue != last { changes.append((t, c.cue)); last = c.cue }
        }
        XCTAssertGreaterThanOrEqual(changes.count, 2, "the coach said something")
        for (x, y) in zip(changes, changes.dropFirst()) where y.0 - x.0 < 15 {
            XCTAssertTrue(CueGate.isUrgent(y.1), "\(y.1.type) replaced \(x.1.type) after only \(y.0 - x.0) s")
        }
    }

    // MARK: geometry: bounded, fits from small to large

    func testLayoutSizingFitsAndIsBounded() {
        for w in stride(from: 160.0, through: 440.0, by: 20) {
            for h in stride(from: 120.0, through: 620.0, by: 25) {
                let g = RideFit.largeGauges(width: w, height: h, chip: 40)
                XCTAssertTrue(g.power.isFinite && g.small.isFinite)
                XCTAssertLessThanOrEqual(g.small * 2 + 12, max(w, 112), "\(w)×\(h)")
                let r = RideFit.rings(width: w, height: h, chip: 37, statsH: 36, gap: 8)
                XCTAssertTrue(r.graph.isFinite && r.ring.isFinite)
                if h >= 320 { XCTAssertGreaterThanOrEqual(r.graph, 40) }
            }
        }
        // iPhone SE content area (~347 × 320): large gauges fill it without exceeding it
        let se = RideFit.largeGauges(width: 347, height: 320 - 22 - 16, chip: 40)
        XCTAssertLessThanOrEqual(se.power + se.small + 2 * 40 + 3 * 8 + 22, 320.5)
        XCTAssertEqual(RideFit.clamp(.nan, 1, 2), 1, "a non-finite size never reaches a layout")
    }
}
