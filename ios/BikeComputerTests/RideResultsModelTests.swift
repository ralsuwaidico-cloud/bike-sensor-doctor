import XCTest
@testable import BikeComputer

/// RA-21…RA-25 and owner regression items 5 and 6: results come from stored samples only; records need history;
/// one Apple Health workout per ride.
final class RideResultsModelTests: XCTestCase {
    private let zones: [(lo: Int, hi: Int?)] = [(0, 120), (121, 140), (141, 152), (153, 165), (166, nil)]
    private let plan: [RideResultsModel.PlanStep] = [.init(name: "Warm-up", minutes: 10, hrZone: 2, rpe: 3...4), .init(name: "Interval 1", minutes: 10, hrZone: 3, rpe: 6...7), .init(name: "Cool-down", minutes: 10, hrZone: 1, rpe: 2...3)]

    private func ride(id: UUID = UUID(), title: String = "Tempo ride", dur: Int, dist: Int, w: ((Int) -> Int?)? = nil, hr: ((Int) -> Int?)? = nil, alt: ((Int) -> Double)? = nil, daysAgo: Int = 0, demo: Bool = false) -> RideResultsModel.Input {
        let samples = (1...dur).map { t in RidePerformanceModel.Sample(t: t, w: w?(t), cad: 88, hr: hr?(t), speedCms: 800) }
        let ws = samples.compactMap { $0.w }, hs = samples.compactMap { $0.hr }
        var r = RideResultsModel.Input(id: id, start: Date().addingTimeInterval(-Double(daysAgo) * 86400), durationS: dur, distanceM: dist, demo: demo, recorder: "this phone",
                                       avgPower: ws.isEmpty ? nil : ws.reduce(0, +) / ws.count, maxPower: ws.max(), normalizedPower: nil, avgHR: hs.isEmpty ? nil : hs.reduce(0, +) / hs.count, maxHR: hs.max(), avgCadence: 88,
                                       energyValue: nil, energyUnit: nil, energySource: nil)
        r.samples = samples; r.title = title
        if let alt { r.altitudes = (1...dur).map { (t: $0, alt: alt($0)) } }
        return r
    }
    private var z: RideResultsModel.Zones { .init(ftpKnown: false, ftp: 0, hrZones: zones, maxHr: 185) }

    func testAscentNeedsSamplesIgnoresNoiseAndCountsRealClimbs() {
        XCTAssertNil(RideResultsModel.ascentM([(1, 10), (2, 12)]), "too few altitude samples → no ascent claimed")
        let flatNoise = (1...100).map { (t: $0, alt: 10 + ($0 % 2 == 0 ? 1.5 : -1.5)) }
        XCTAssertEqual(RideResultsModel.ascentM(flatNoise), 0, "±1.5 m jitter is below the threshold")
        let climb = (1...100).map { (t: $0, alt: Double($0) * 0.5) }          // 50 m steady climb
        XCTAssertTrue((44...50).contains(RideResultsModel.ascentM(climb) ?? -1), "a steady climb counts: \(String(describing: RideResultsModel.ascentM(climb)))")
        let upDown = (1...100).map { (t: $0, alt: $0 <= 50 ? Double($0) : Double(100 - $0)) }
        XCTAssertTrue((40...50).contains(RideResultsModel.ascentM(upDown) ?? -1), "descents are not counted as ascent: \(String(describing: RideResultsModel.ascentM(upDown)))")
    }

    func testHeadlineAndAnalysisOnlyShowRecordedMetrics() {
        let r = ride(dur: 1800, dist: 15000, hr: { _ in 140 })
        let m = RideResultsModel.make(ride: r, others: [], zones: z, plan: [], imperial: false)
        XCTAssertEqual(m.headline.map(\.key), ["dist", "time", "speed", "ascent"])
        XCTAssertEqual(m.headline[0].value, "15.0"); XCTAssertEqual(m.headline[1].value, "30:00"); XCTAssertEqual(m.headline[2].value, "30.0")
        XCTAssertEqual(m.headline[3].value, "—"); XCTAssertEqual(m.headline[3].source, "no usable altitude")
        XCTAssertEqual(m.analysis.first { $0.key == "power" }?.value, "—", "no power meter → no number, a plain statement")
        XCTAssertEqual(m.analysis.first { $0.key == "hr" }?.value, "140")
        XCTAssertFalse(m.analysis.contains { $0.key == "energy" }, "no energy without a source")
        XCTAssertTrue(m.coachSummary.contains("No power meter"))
        XCTAssertEqual(m.stepBasis, "FREE RIDE")
    }

    func testZonesComeFromSamplesWhenTheBoardSentNone() {
        let r = ride(dur: 600, dist: 5000, hr: { $0 <= 300 ? 130 : 147 })
        let m = RideResultsModel.make(ride: r, others: [], zones: z, plan: [], imperial: false)
        XCTAssertEqual(m.zoneSeconds, [0, 300, 300, 0, 0]); XCTAssertEqual(m.zoneBasis, "HEART-RATE ZONES")
    }

    func testBoardZoneSecondsAreUsedAsSent() {
        var r = ride(dur: 600, dist: 5000, w: { _ in 200 }); r.zoneSeconds = [100, 200, 300, 0, 0]
        let m = RideResultsModel.make(ride: r, others: [], zones: .init(ftpKnown: true, ftp: 240, hrZones: nil, maxHr: 0), plan: [], imperial: false)
        XCTAssertEqual(m.zoneSeconds, [100, 200, 300, 0, 0]); XCTAssertEqual(m.zoneBasis, "POWER ZONES · BIKECOMPUTER")
    }

    func testPlanVsRideMarksEachStepFromItsOwnWindow() {
        // 25 min ride: warm-up in Z2, interval at 148 (in band), cool-down cut short after 5 min
        let r = ride(dur: 1500, dist: 12000, hr: { $0 <= 600 ? 130 : ($0 <= 1200 ? 148 : 110) })
        let m = RideResultsModel.make(ride: r, others: [], zones: z, plan: plan, imperial: false)
        XCTAssertEqual(m.steps.map(\.mark), ["✓", "✓", "–"])
        XCTAssertEqual(m.steps[0].planned, "121–140 bpm"); XCTAssertTrue(m.steps[0].actual.contains("130 bpm"))
        XCTAssertTrue(m.steps[2].actual.contains("ended early"))
        XCTAssertEqual(m.stepBasis, "TARGET VS ACTUAL · HEART RATE")
        XCTAssertTrue(m.coachSummary.hasPrefix("2 of 3 steps completed in their target, 1 cut short or not reached."))
        // out of band
        let hot = ride(dur: 1800, dist: 14000, hr: { $0 <= 600 ? 130 : ($0 <= 1200 ? 160 : 110) })
        XCTAssertEqual(RideResultsModel.make(ride: hot, others: [], zones: z, plan: plan, imperial: false).steps[1].mark, "!")
    }

    func testRecordsNeedHistoryAndNeverComeFromDemoRides() {
        let first = ride(dur: 1800, dist: 15000, hr: { _ in 140 })
        let alone = RideResultsModel.make(ride: first, others: [], zones: z, plan: [], imperial: false)
        XCTAssertEqual(alone.recordBasis, "1 RIDE ON RECORD")
        XCTAssertFalse(alone.records.contains { $0.isRecord }, "a first ride is never a record")
        XCTAssertTrue(alone.records.contains { $0.kind == "threshold" })

        let older = ride(dur: 3000, dist: 24100, hr: { _ in 146 }, daysAgo: 4)
        let demo = ride(dur: 9000, dist: 99000, daysAgo: 2, demo: true)
        let now = ride(dur: 3600, dist: 27900, hr: { _ in 143 })
        let m = RideResultsModel.make(ride: now, others: [older, demo], zones: z, plan: [], imperial: false)
        XCTAssertEqual(m.recordBasis, "2 RIDES ON RECORD", "the demo ride is not history")
        let longest = m.records.first { $0.kind == "distance" }
        XCTAssertEqual(longest?.isRecord, true); XCTAssertTrue(longest?.text.contains("previous 24.1 km") ?? false, "99 km demo ride never becomes the previous best")
        XCTAssertTrue(m.records.contains { $0.kind == "hr" && $0.text.contains("143 vs 146") })
        XCTAssertTrue(m.records.contains { $0.kind == "threshold" && $0.text.contains("(2 on record)") })
        let onDemo = RideResultsModel.make(ride: demo, others: [older], zones: z, plan: [], imperial: false)
        XCTAssertEqual(onDemo.records.map(\.kind), ["demo"])
    }

    func testBest20NeedsTwentyMinutesOfPower() {
        XCTAssertNil(RideResultsModel.best20((1...1000).map { RidePerformanceModel.Sample(t: $0, w: 200, cad: nil, hr: nil, speedCms: nil) }))
        let s = (1...1800).map { RidePerformanceModel.Sample(t: $0, w: $0 <= 600 ? 150 : 230, cad: nil, hr: nil, speedCms: nil) }
        XCTAssertEqual(RideResultsModel.best20(s), 230)
        let gappy = (1...1800).map { RidePerformanceModel.Sample(t: $0, w: $0 % 3 == 0 ? nil : 200, cad: nil, hr: nil, speedCms: nil) }
        XCTAssertNil(RideResultsModel.best20(gappy), "a window with a third of its seconds missing is not a best effort")
    }

    func testHistorySearchMatchesEveryTerm() {
        let rows = ["Tempo ride · Thu 5 Nov · 27.9 km", "Endurance ride · Tue 3 Nov · 24.1 km", "Tempo ride · Thu 29 Oct · 22.6 km"]
        XCTAssertEqual(RideHistorySearch.filter(rows, query: "tempo", text: { $0 }).count, 2)
        XCTAssertEqual(RideHistorySearch.filter(rows, query: "tempo oct", text: { $0 }), ["Tempo ride · Thu 29 Oct · 22.6 km"])
        XCTAssertEqual(RideHistorySearch.filter(rows, query: "  ", text: { $0 }).count, 3)
        XCTAssertEqual(RideHistorySearch.filter(rows, query: "zwift", text: { $0 }).count, 0)
    }

    func testOneHealthWorkoutPerRide() {
        XCTAssertEqual(RideHealthWriter.decide(recorder: "phone", watchWorkoutExists: true, phoneAuthorized: true, alreadyWritten: false, demo: false), .watch, "the Watch stays the writer")
        XCTAssertEqual(RideHealthWriter.decide(recorder: "phone", watchWorkoutExists: false, phoneAuthorized: true, alreadyWritten: false, demo: false), .phone)
        XCTAssertEqual(RideHealthWriter.decide(recorder: "phone", watchWorkoutExists: false, phoneAuthorized: false, alreadyWritten: false, demo: false), .none, "denied permission: no Health write, Cyclift still saves")
        XCTAssertEqual(RideHealthWriter.decide(recorder: "board", watchWorkoutExists: false, phoneAuthorized: true, alreadyWritten: true, demo: false), .none, "never twice")
        XCTAssertEqual(RideHealthWriter.decide(recorder: "phone", watchWorkoutExists: false, phoneAuthorized: true, alreadyWritten: false, demo: true), .none, "demo rides never reach Health")
    }
}
