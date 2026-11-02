import XCTest
@testable import BikeComputer

/// Pure design-system logic (DesignSystem/PureDesign.swift): runs on the Linux harness and on the CI simulator.
final class DesignSystemPureTests: XCTestCase {
    func testTagLabelsNeverSayMeasuredForEstimatesOrUnknowns() {
        XCTAssertEqual(SourceTag.measured.label, "Measured")
        XCTAssertEqual(SourceTag.logged.label, "Logged")
        XCTAssertEqual(SourceTag.estimated.label, "Estimated")
        XCTAssertEqual(SourceTag.unknown.label, "Unknown")
        XCTAssertEqual(SourceTag.needsData.label, "Needs data")
        for t in SourceTag.allCases where t != .measured { XCTAssertFalse(t.label.contains("Measured"), "\(t) must not read as measured") }
    }

    func testFractionClampsAndNeverDivides() {
        XCTAssertEqual(CyDesign.clampFraction(-1), 0)
        XCTAssertEqual(CyDesign.clampFraction(1.7), 1)
        XCTAssertEqual(CyDesign.clampFraction(.nan), 0)
        XCTAssertEqual(CyDesign.clampFraction(.infinity), 0)
        XCTAssertEqual(CyDesign.ringFraction(done: 3, planned: 5), 0.6, accuracy: 1e-9)
        XCTAssertEqual(CyDesign.ringFraction(done: 0, planned: 0), 0)
        XCTAssertEqual(CyDesign.ringFraction(done: 7, planned: 5), 1)
        XCTAssertEqual(CyDesign.percentText(0.6), "60%")
        XCTAssertEqual(CyDesign.percentText(2), "100%")
    }

    func testBarNormalisationKeepsMissingAndFitsPlanLine() {
        let n = CyDesign.normalise([1, nil, 2, 4], planLine: 8)
        XCTAssertEqual(n[0], 0.125); XCTAssertNil(n[1]); XCTAssertEqual(n[3], 0.5)
        XCTAssertEqual(CyDesign.normalise([nil, nil]), [nil, nil])
        XCTAssertEqual(CyDesign.normalise([0, 0]), [0, 0])
        XCTAssertTrue(CyDesign.hasEnoughData([1, nil, 2, 3], minimum: 3))
        XCTAssertFalse(CyDesign.hasEnoughData([1, nil, nil], minimum: 3))
    }

    func testInsufficientDataWording() {
        XCTAssertEqual(CyDesign.needsMoreText(missing: 1, unit: "ride"), "Needs 1 more ride")
        XCTAssertEqual(CyDesign.needsMoreText(missing: 2, unit: "ride"), "Needs 2 more rides")
        XCTAssertEqual(CyDesign.needsMoreText(missing: 0, unit: "week"), "Needs 1 more week")
        XCTAssertEqual(CyDesign.needsMoreText(missing: 3, unit: "logged sessions"), "Needs 3 more logged sessions")
    }

    func testMinutesAndTimerText() {
        XCTAssertEqual(CyDesign.minutesText(58), "58 min")
        XCTAssertEqual(CyDesign.minutesText(93), "1h 33m")
        XCTAssertEqual(CyDesign.minutesText(120), "2h")
        XCTAssertEqual(CyDesign.minutesText(-5), "0 min")
        XCTAssertEqual(CyDesign.timerText(48), "0:48")
        XCTAssertEqual(CyDesign.timerText(125), "2:05")
        XCTAssertEqual(CyDesign.timerFraction(remaining: 45, total: 90), 0.5)
        XCTAssertEqual(CyDesign.timerFraction(remaining: 45, total: 0), 0)
    }

    func testDaySportTapOrderAndVoiceOverLabel() {
        XCTAssertEqual(CyDaySport.cycling.next(allowBoth: false), .strength)
        XCTAssertEqual(CyDaySport.strength.next(allowBoth: false), .rest)
        XCTAssertEqual(CyDaySport.strength.next(allowBoth: true), .both)
        XCTAssertEqual(CyDaySport.both.next(allowBoth: true), .rest)
        XCTAssertEqual(CyDaySport.rest.next(allowBoth: true), .cycling)
        let d = CyDay(id: 2, shortName: "Wed", longName: "Wednesday", sport: .strength, status: .done, isToday: true)
        XCTAssertEqual(d.accessibilityLabel, "Today, Wednesday, strength, done")
        let r = CyDay(id: 3, shortName: "Thu", longName: "Thursday", sport: .rest, status: .none)
        XCTAssertEqual(r.accessibilityLabel, "Thursday, rest")
        XCTAssertEqual(CyDaySport.both.icons, ["bicycle", "dumbbell"])
    }

    func testDeviceStatesAreDistinct() {
        XCTAssertEqual(CyDeviceState.paired.label, "Paired")
        XCTAssertEqual(CyDeviceState.connected.label, "Connected")
        XCTAssertEqual(CyDeviceState.receiving.label, "Receiving live data")
        XCTAssertNotEqual(CyDeviceState.paired.label, CyDeviceState.receiving.label)
        XCTAssertEqual(Set(CyDeviceState.allCases.map(\.label)).count, CyDeviceState.allCases.count)
    }

    func testMonthGridMondayFirstAndPadding() {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!
        // November 2026 starts on a Sunday → 6 leading cells (Mon…Sat), 30 days, padded to 42
        let g = CyDesign.monthGrid(year: 2026, month: 11, calendar: cal, sportFor: { $0 == 4 ? .strength : .rest }, statusFor: { $0 == 4 ? .done : .none })
        XCTAssertEqual(g.count, 42)
        XCTAssertEqual(g.prefix(6).filter { !$0.inMonth }.count, 6)
        XCTAssertEqual(g[6].number, 1)
        XCTAssertEqual(g[9].sport, .strength); XCTAssertEqual(g[9].status, .done)
        XCTAssertEqual(g.filter(\.inMonth).count, 30)
        XCTAssertEqual(Set(g.map(\.id)).count, g.count, "cell ids unique")
        var c = DateComponents(); c.year = 2026; c.month = 11; c.day = 2
        let monday = cal.date(from: c)!
        XCTAssertEqual(CyDesign.mondayFirstIndex(monday, calendar: cal), 0)
        let withToday = CyDesign.monthGrid(year: 2026, month: 11, today: monday, calendar: cal)
        XCTAssertTrue(withToday.first { $0.number == 2 }!.isToday)
    }

    func testBarHeightHasMinimum() {
        XCTAssertEqual(CyDesign.barHeight(intensity: 0, maxHeight: 40), 6)
        XCTAssertEqual(CyDesign.barHeight(intensity: 1, maxHeight: 40), 40)
        XCTAssertEqual(CyDesign.barHeight(intensity: 0.5, maxHeight: 40), 20)
    }
}
