import XCTest

// Home v2.2 — automated interaction checks for the UI Lab PROTOTYPE (sample data only).
// These tests drive the prototype in the iOS Simulator. A pass here is evidence about the prototype's
// interactions on a simulator; it is NOT validation of the production Cyclift app and NOT a real-device test.
// Rule: an assertion is never loosened to get a pass — a failure means the prototype is fixed.

final class HomeInteractionTests: XCTestCase {
    var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
    }

    // MARK: helpers

    @discardableResult
    private func launch(_ env: [String: String] = [:], args: [String] = []) -> XCUIApplication {
        app = XCUIApplication()
        var e = ["LAB_THEME": "obsidian", "LAB_SCREEN": "home"]
        env.forEach { e[$0.key] = $0.value }
        app.launchEnvironment = e
        app.launchArguments = args
        app.launch()
        XCTAssertTrue(el("indicatorConsistency").waitForExistence(timeout: 20), "Home did not appear")
        return app
    }

    private func el(_ id: String) -> XCUIElement { app.descendants(matching: .any).matching(identifier: id).firstMatch }

    private var window: CGRect { app.windows.firstMatch.frame }
    /// The part of the screen that is neither under the status bar nor under the floating dock.
    private var safeTop: CGFloat { 70 }
    private var safeBottom: CGFloat {
        let dock = el("dockCentre")
        return (dock.exists ? dock.frame.minY : window.maxY - 110) - 8
    }

    /// Scrolls the Home column until the element's centre is in the clear part of the screen.
    private func bring(_ e: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(e.waitForExistence(timeout: 8), "Missing element \(e)", file: file, line: line)
        let x = window.minX + 6          // left margin: never starts a gesture on a control or on the graph
        for _ in 0..<14 {
            let f = e.frame
            if f.midY >= safeTop && f.midY <= safeBottom { return }
            let up = f.midY > safeBottom
            let dist = min(abs(f.midY - (safeTop + safeBottom) / 2), 320)
            let a = app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: x, dy: window.midY + (up ? dist / 2 : -dist / 2)))
            let b = app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: x, dy: window.midY + (up ? -dist / 2 : dist / 2)))
            a.press(forDuration: 0.05, thenDragTo: b, withVelocity: .slow, thenHoldForDuration: 0.3)
        }
        XCTFail("Could not scroll \(e) into the clear part of the screen (frame \(e.frame))", file: file, line: line)
    }

    private func tapOn(_ e: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        bring(e, file: file, line: line)
        e.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
    }

    private func expectSheet(_ title: String, file: StaticString = #filePath, line: UInt = #line) {
        let t = el("sheetTitle")
        XCTAssertTrue(t.waitForExistence(timeout: 6), "No sheet opened (expected \"\(title)\")", file: file, line: line)
        XCTAssertEqual(t.label, title, "Wrong sheet opened", file: file, line: line)
    }

    private func closeSheet(file: StaticString = #filePath, line: UInt = #line) {
        let c = el("sheetClose")
        XCTAssertTrue(c.waitForExistence(timeout: 4), "Sheet has no close button", file: file, line: line)
        c.tap()
        let gone = NSPredicate(format: "exists == false")
        expectation(for: gone, evaluatedWith: el("sheetTitle"))
        waitForExpectations(timeout: 6)
    }

    private func value(_ id: String) -> String { (el(id).value as? String) ?? "" }
    private func label(_ id: String, timeout: TimeInterval = 5) -> String {
        let e = el(id)
        _ = e.waitForExistence(timeout: timeout)
        return e.exists ? e.label : "<missing \(id)>"
    }
    private func waitLabel(_ id: String, equals text: String, file: StaticString = #filePath, line: UInt = #line) {
        let e = el(id)
        let p = NSPredicate(format: "exists == true AND label == %@", text)
        let x = XCTNSPredicateExpectation(predicate: p, object: e)
        let r = XCTWaiter().wait(for: [x], timeout: 6)
        XCTAssertEqual(r, .completed, "\(id): expected \"\(text)\", found \"\(e.exists ? e.label : "<missing>")\"", file: file, line: line)
    }
    private func labels(_ id: String) -> [String] {
        app.descendants(matching: .any).matching(identifier: id).allElementsBoundByIndex.map(\.label)
    }

    // MARK: 1 — every circle opens its own sheet

    func test01_EachIndicatorOpensItsOwnSheet() {
        launch()
        tapOn(el("indicatorConsistency")); expectSheet("Consistency"); closeSheet()
        tapOn(el("indicatorMix")); expectSheet("Training Mix"); closeSheet()
        tapOn(el("indicatorRecovery")); expectSheet("Recovery"); closeSheet()
    }

    // MARK: 2 — Training Mix centre ratio comes from the sample minutes

    /// The documented prototype formula, recomputed independently here.
    private func ratio(_ e: Int, _ s: Int) -> String {
        let p = Int((Double(e) / Double(e + s) * 100).rounded())
        return "\(p):\(100 - p)"
    }

    func test02_MixRatioMatchesCompletedMinutes() {
        launch()
        tapOn(el("indicatorMix")); expectSheet("Training Mix")
        // the sheet states the completed minutes the ratio is built from
        let rows = labels("mixRatios").joined(separator: " | ")
        XCTAssertTrue(rows.contains("77 endurance · 40 strength"), "Completed minutes not shown in the sheet: \(rows)")
        let expected = ratio(77, 40)
        XCTAssertEqual(expected, "66:34")
        XCTAssertTrue(rows.contains(expected), "Sheet does not show the completed-time ratio \(expected): \(rows)")
        closeSheet()
        XCTAssertTrue(value("indicatorMix").hasPrefix("\(expected)."), "Circle centre is not \(expected): \(value("indicatorMix"))")
    }

    func test03_MixRatioSingleSportAndNoTraining() {
        launch(["LAB_SCENARIO": "cyclingOnly"])
        XCTAssertTrue(value("indicatorMix").hasPrefix("100:0."), value("indicatorMix"))
        app.terminate()
        launch(["LAB_SCENARIO": "strengthOnly"])
        XCTAssertTrue(value("indicatorMix").hasPrefix("0:100."), value("indicatorMix"))
        app.terminate()
        launch(["LAB_SCENARIO": "newUser"])
        let v = value("indicatorMix")
        XCTAssertTrue(v.hasPrefix("No ratio."), "With no completed training the circle must show no ratio: \(v)")
        XCTAssertFalse(v.contains(":0") || v.contains("0:"), "A ratio is shown without completed training: \(v)")
    }

    // MARK: 3 — Recovery states

    func test04_RecoveryNumericSampleIsMarkedAsSample() {
        launch()
        let v = value("indicatorRecovery")
        XCTAssertTrue(v.hasPrefix("68%."), v)
        XCTAssertTrue(v.localizedCaseInsensitiveContains("sample"), "The percentage is not announced as sample data: \(v)")
        tapOn(el("indicatorRecovery")); expectSheet("Recovery")
        XCTAssertTrue(el("recoverySampleTag").waitForExistence(timeout: 4), "Sheet does not mark the score as a sample")
        XCTAssertTrue(label("recoveryHeadline").contains("68%"))
    }

    func test05_RecoveryQualitativeShowsNoPercentage() {
        launch(["LAB_SCENARIO": "qualitativeRecovery"])
        let v = value("indicatorRecovery")
        XCTAssertTrue(v.hasPrefix("Status only."), v)
        XCTAssertFalse(v.contains("%"), "A percentage is shown in the qualitative state: \(v)")
        tapOn(el("indicatorRecovery")); expectSheet("Recovery")
        XCTAssertEqual(label("recoveryHeadline"), "In your usual range")
        XCTAssertFalse(el("recoverySampleTag").exists)
    }

    func test06_RecoveryUnavailableAndPartial() {
        launch(["LAB_SCENARIO": "noRecovery"])
        var v = value("indicatorRecovery")
        XCTAssertTrue(v.hasPrefix("No value."), v)
        XCTAssertFalse(v.contains("%"), v)
        tapOn(el("indicatorRecovery")); expectSheet("Recovery")
        XCTAssertEqual(label("recoveryHeadline"), "Awaiting data")
        let missing = labels("recoveryMissing").joined(separator: " ")
        XCTAssertTrue(missing.contains("Sleep") && missing.contains("HRV") && missing.contains("Resting heart rate"), "Missing inputs are not listed: \(missing)")
        app.terminate()

        launch(["LAB_SCENARIO": "partialData"])
        v = value("indicatorRecovery")
        XCTAssertTrue(v.hasPrefix("Partial."), v)
        XCTAssertFalse(v.contains("%"), v)
        tapOn(el("indicatorRecovery")); expectSheet("Recovery")
        let m2 = labels("recoveryMissing").joined(separator: " ")
        XCTAssertTrue(m2.contains("Sleep") && m2.contains("HRV"), m2)
        XCTAssertFalse(m2.contains("Resting heart rate"), "Resting heart rate has a reading and must not be listed as missing: \(m2)")
    }

    // MARK: 4 — schedule

    func test07_EachScheduleDayOpensThatDay() {
        launch()
        let days = ["Monday 9 Nov", "Tuesday 10 Nov", "Wednesday 11 Nov", "Thursday 12 Nov", "Friday 13 Nov", "Saturday 14 Nov", "Sunday 15 Nov"]
        for (i, title) in days.enumerated() {
            tapOn(el("scheduleDay-\(i)")); expectSheet(title); closeSheet()
        }
        // a two-session day announces both sessions and their states (not colour alone)
        let wed = value("scheduleDay-2")
        XCTAssertTrue(wed.contains("Recovery spin, completed") && wed.contains("Strength · upper body, planned"), wed)
        XCTAssertEqual(value("scheduleDay-3"), "Rest day")
    }

    // MARK: 5 — sleep

    func test08_SleepOpensSleepSheet() {
        launch()
        let v = value("sleepBar")
        XCTAssertTrue(v.contains("7h 10m"), "Last night is not announced: \(v)")
        tapOn(el("sleepBar")); expectSheet("Sleep"); closeSheet()
        app.terminate()
        launch(["LAB_SCENARIO": "noSleep"])
        tapOn(el("sleepBar")); expectSheet("Sleep")
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS 'No record'")).firstMatch.waitForExistence(timeout: 4),
                      "With no sleep source the sheet must say there is no record")
    }

    // MARK: 6 — coach

    func test09_CoachWhyReviewNotNow() {
        launch()
        tapOn(el("coachWhy")); expectSheet("Why this suggestion?"); closeSheet()
        tapOn(el("coachReview")); expectSheet("Review the suggestion")
        XCTAssertTrue(el("reviewApprove").exists && el("reviewPostpone").exists && el("reviewDecline").exists, "Review sheet is missing a decision")
        el("reviewPostpone").tap()
        waitLabel("coachDecisionNote", equals: "Postponed — still waiting for your decision")
        XCTAssertTrue(el("coachReview").exists, "A postponed suggestion must stay reviewable")
        app.terminate()

        launch()
        tapOn(el("coachNotNow"))
        waitLabel("coachDecisionNote", equals: "Postponed — still waiting for your decision")
        XCTAssertTrue(el("coachReview").exists, "\"Not now\" must postpone, not decline")
    }

    func test10_CoachApproveAndDecline() {
        launch()
        tapOn(el("coachReview")); expectSheet("Review the suggestion")
        el("reviewApprove").tap()
        waitLabel("coachDecisionNote", equals: "Accepted — applied to the sample plan")
        XCTAssertFalse(el("coachReview").exists, "An accepted suggestion must not ask again")
        XCTAssertFalse(el("sheetTitle").exists, "Review sheet stayed on screen after approval")
        app.terminate()

        launch()
        tapOn(el("coachReview")); expectSheet("Review the suggestion")
        el("reviewDecline").tap()
        waitLabel("coachDecisionNote", equals: "Declined — this suggestion will not be repeated")
        XCTAssertFalse(el("coachReview").exists, "A declined suggestion must not ask again")
    }

    // MARK: 7 — graph: tapping a day

    func test11_GraphDayTapChangesPanelValues() {
        launch()
        bring(el("trendsChart"))
        XCTAssertTrue(el("trendsHint").exists, "Before a selection the hint should be shown")
        tapOn(el("trendsDay-0"))
        waitLabel("trendsPanelDate", equals: "Monday 9 Nov")
        waitLabel("trendsValue-load", equals: "240 RPE×min")
        waitLabel("trendsValue-recovery", equals: "72 %")
        tapOn(el("trendsDay-1"))
        waitLabel("trendsPanelDate", equals: "Tuesday 10 Nov")
        waitLabel("trendsValue-load", equals: "225 RPE×min")
        waitLabel("trendsValue-recovery", equals: "61 %")
        // a day without measurements says so — nothing is carried over or interpolated
        tapOn(el("trendsDay-4"))
        waitLabel("trendsPanelDate", equals: "Friday 13 Nov")
        waitLabel("trendsValue-load", equals: "No data")
        waitLabel("trendsValue-recovery", equals: "No data")
        // the daily sheet opens for the selected date
        tapOn(el("trendsDay-1"))
        waitLabel("trendsPanelDate", equals: "Tuesday 10 Nov")
        tapOn(el("trendsOpenDay")); expectSheet("Tuesday 10 Nov")
        let rows = labels("graphDayRows").joined(separator: " | ")
        XCTAssertTrue(rows.contains("225 RPE×min"), rows)
    }

    // MARK: 8 — graph: scrubbing

    func test12_GraphScrubSelectsTheDayUnderTheFinger() {
        launch()
        bring(el("trendsChart"))
        bring(el("trendsDay-0"))
        let a = el("trendsDay-0").coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let mid = el("trendsDay-2").coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        a.press(forDuration: 0.1, thenDragTo: mid, withVelocity: .slow, thenHoldForDuration: 0.4)
        waitLabel("trendsPanelDate", equals: "Wednesday 11 Nov")
        waitLabel("trendsValue-load", equals: "96 RPE×min")
        let end = el("trendsDay-5").coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        mid.press(forDuration: 0.1, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.4)
        waitLabel("trendsPanelDate", equals: "Saturday 14 Nov")
        // and back again, right to left
        end.press(forDuration: 0.1, thenDragTo: a, withVelocity: .slow, thenHoldForDuration: 0.4)
        waitLabel("trendsPanelDate", equals: "Monday 9 Nov")
    }

    /// The graph must not trap the page: a vertical swipe that starts on the graph still scrolls Home.
    func test13_VerticalSwipeOnGraphStillScrollsThePage() {
        launch()
        let chart = el("trendsChart")
        bring(chart)
        let before = chart.frame.midY
        let start = chart.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.6))
        let stop = start.withOffset(CGVector(dx: 0, dy: -160))
        start.press(forDuration: 0.05, thenDragTo: stop, withVelocity: .default, thenHoldForDuration: 0.3)
        let after = chart.frame.midY
        XCTAssertLessThan(after, before - 60, "The page did not scroll when swiping up over the graph (before \(before), after \(after))")
    }

    // MARK: 9 — graph: series switching

    func test14_SeriesSwitchingChangesWhatIsShown() {
        launch()
        bring(el("trendsChart"))
        tapOn(el("trendsDay-1"))
        XCTAssertTrue(el("trendsValue-recovery").waitForExistence(timeout: 4))
        XCTAssertEqual(value("trendsSeries-recovery"), "shown")
        tapOn(el("trendsSeries-recovery"))
        XCTAssertEqual(value("trendsSeries-recovery"), "hidden")
        XCTAssertFalse(el("trendsValue-recovery").exists, "A hidden series is still listed in the value panel")
        XCTAssertTrue(el("trendsValue-load").exists)
        // the last visible series cannot be switched off (the graph is never left empty by a tap)
        tapOn(el("trendsSeries-load"))
        XCTAssertEqual(value("trendsSeries-load"), "shown")
        tapOn(el("trendsSeries-recovery"))
        XCTAssertEqual(value("trendsSeries-recovery"), "shown")

        // Activity: three series in minutes
        tapOn(el("trendsMode-activity"))
        XCTAssertTrue(el("trendsSeries-endurance").waitForExistence(timeout: 4))
        XCTAssertFalse(el("trendsSeries-load").exists, "Switching the view left the previous view's series on screen")
        tapOn(el("trendsDay-1"))
        waitLabel("trendsValue-endurance", equals: "45 min")
        waitLabel("trendsValue-strength", equals: "0 min")
        waitLabel("trendsValue-planned", equals: "45 min")

        // Recovery trends: one metric at a time, each in its own unit
        tapOn(el("trendsMode-trends"))
        XCTAssertTrue(el("trendsSeries-rhr").waitForExistence(timeout: 4))
        tapOn(el("trendsDay-1"))
        waitLabel("trendsValue-rhr", equals: "54 bpm")
        XCTAssertFalse(el("trendsValue-hrv").exists || el("trendsValue-sleep").exists, "More than one unit is shown at once")
        tapOn(el("trendsSeries-hrv"))
        waitLabel("trendsValue-hrv", equals: "58 ms")
        XCTAssertFalse(el("trendsValue-rhr").exists)
        tapOn(el("trendsSeries-sleep"))
        waitLabel("trendsValue-sleep", equals: "6.8 h")
        XCTAssertFalse(el("trendsValue-hrv").exists)
    }

    // MARK: 10 — graph: 7 days / 4 weeks

    func test15_RangeSwitching() {
        launch()
        bring(el("trendsChart"))
        XCTAssertTrue(el("trendsDay-6").exists)
        XCTAssertFalse(el("trendsDay-7").exists, "The 7-day view has more than seven days")
        tapOn(el("trendsRange-4w"))
        XCTAssertTrue(el("trendsDay-27").waitForExistence(timeout: 4), "The 4-week view does not have 28 days")
        XCTAssertFalse(el("trendsDay-28").exists)
        XCTAssertFalse(el("trendsPanelDate").exists, "A selection from the other range was kept")
        tapOn(el("trendsDay-27"))
        waitLabel("trendsPanelDate", equals: "Wednesday 11 Nov")
        waitLabel("trendsValue-load", equals: "96 RPE×min")
        tapOn(el("trendsDay-0"))
        waitLabel("trendsPanelDate", equals: "Thursday 15 Oct")
        // a missing recovery reading inside the range is reported as missing (Wed 21 Oct in the sample)
        tapOn(el("trendsDay-6"))
        waitLabel("trendsPanelDate", equals: "Wednesday 21 Oct")
        waitLabel("trendsValue-recovery", equals: "No data")
        tapOn(el("trendsRange-7d"))
        XCTAssertFalse(el("trendsDay-7").waitForExistence(timeout: 1.5))
        XCTAssertTrue(el("trendsDay-6").exists)
    }

    func test16_GraphEmptyAndInfo() {
        launch(["LAB_SCENARIO": "newUser"])
        bring(el("trendsEmpty"))
        XCTAssertFalse(el("trendsChart").exists, "A graph is drawn for an athlete with no history")
        tapOn(el("trendsInfo")); expectSheet("How Trends works"); closeSheet()
        app.terminate()
        // no recovery source: the recovery-trend metrics say "no data" instead of drawing anything
        launch(["LAB_SCENARIO": "noRecovery"])
        bring(el("trendsMode-trends"))
        tapOn(el("trendsMode-trends"))
        XCTAssertTrue(el("trendsEmpty").waitForExistence(timeout: 4), "Missing recovery metrics must show an empty state")
        XCTAssertFalse(el("trendsChart").exists)
    }

    // MARK: 11 — key metric rows

    func test17_MetricRowsOpenTheirDetails() {
        launch()
        let rows = [("rhr", "Resting HR"), ("hrv", "HRV"), ("time", "Training time"), ("load", "Weekly load"), ("power", "Avg ride power"), ("volume", "Strength volume")]
        for (id, title) in rows {
            tapOn(el("metricRow-\(id)")); expectSheet(title); closeSheet()
        }
        // weekly load keeps its documented unit
        let load = el("metricRow-load")
        let spoken = load.label + " " + ((load.value as? String) ?? "")
        XCTAssertTrue(spoken.contains("RPE×min"), "Weekly load lost its unit: \(spoken)")
    }

    // MARK: 12 — floating dock

    func test18_DockSwitchesDestinations() {
        launch()
        el("dock-1").tap()
        XCTAssertTrue(app.staticTexts["Plan is not prototyped yet"].waitForExistence(timeout: 5))
        XCTAssertFalse(el("indicatorConsistency").exists)
        el("dock-3").tap()
        XCTAssertTrue(app.staticTexts["Progress is not prototyped yet"].waitForExistence(timeout: 5))
        el("dock-4").tap()
        XCTAssertTrue(el("labTitle").waitForExistence(timeout: 5))
        el("dock-0").tap()
        XCTAssertTrue(el("indicatorConsistency").waitForExistence(timeout: 5))
        el("dockCentre").tap(); expectSheet("Train now"); closeSheet()
        tapOn(el("homeAvatar")); expectSheet("Profile"); closeSheet()
    }

    func test19_DockNeverCoversTheLastRows() {
        launch()
        let last = el("metricRow-volume")
        XCTAssertTrue(last.waitForExistence(timeout: 5))
        for _ in 0..<6 { app.swipeUp(velocity: .fast) }
        let dockTop = el("dockCentre").frame.minY
        XCTAssertLessThanOrEqual(last.frame.maxY, dockTop, "At the end of the page the last metric row sits under the dock (row bottom \(last.frame.maxY), dock top \(dockTop))")
        let end = el("setupComplete")
        XCTAssertTrue(end.exists)
        XCTAssertLessThanOrEqual(end.frame.maxY, dockTop, "The final line of the page sits under the dock (bottom \(end.frame.maxY), dock top \(dockTop))")
        XCTAssertTrue(last.isHittable, "The last metric row cannot be tapped at the end of the page")
        last.tap(); expectSheet("Strength volume")
    }

    // MARK: 13 — Getting Started placement

    func test20_GettingStartedMovesWhenRequiredStepsAreDone() {
        launch(["LAB_SCENARIO": "newUser"])
        let next = el("setupNext")
        XCTAssertTrue(next.waitForExistence(timeout: 5), "A new athlete with an open required step sees no Getting Started card")
        XCTAssertGreaterThan(next.frame.minY, el("indicatorConsistency").frame.maxY - 1, "Getting Started is not below the indicators")
        XCTAssertLessThan(next.frame.maxY, el("scheduleDay-2").frame.minY + 1, "Getting Started is not above the schedule")
        XCTAssertFalse(el("setupComplete").exists)
        tapOn(next)                                  // local mock: completes the required step
        let done = el("setupComplete")
        XCTAssertTrue(done.waitForExistence(timeout: 5), "After the required step nothing confirms setup")
        XCTAssertFalse(el("setupNext").exists, "The required-step card stayed after completion")
        XCTAssertGreaterThan(done.frame.minY, el("metricRow-load").frame.maxY - 1, "The completed setup line did not move below the key metrics")
        app.terminate()
        // an established athlete never has it at the top
        launch()
        XCTAssertFalse(el("setupNext").exists)
        XCTAssertTrue(el("setupComplete").exists)
        XCTAssertGreaterThan(el("setupComplete").frame.minY, el("metricRow-volume").frame.maxY - 1)
    }

    // MARK: extra — large accessibility text and loading

    func test21_LargeTextKeepsIndicatorsSeparateAndUsable() {
        launch(args: ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityL"])
        let c = el("indicatorConsistency").frame, m = el("indicatorMix").frame, r = el("indicatorRecovery").frame
        XCTAssertFalse(c.intersects(m) || m.intersects(r) || c.intersects(r), "Indicators overlap at large text: \(c) \(m) \(r)")
        XCTAssertLessThanOrEqual(c.maxX, window.maxX); XCTAssertLessThanOrEqual(r.maxX, window.maxX)
        tapOn(el("indicatorMix")); expectSheet("Training Mix"); closeSheet()
        tapOn(el("indicatorRecovery")); expectSheet("Recovery"); closeSheet()
        tapOn(el("scheduleDay-2")); expectSheet("Wednesday 11 Nov"); closeSheet()
        tapOn(el("coachReview")); expectSheet("Review the suggestion")
    }

    func test22_LoadingShowsNoValues() {
        launch(["LAB_SCENARIO": "loading"])
        XCTAssertFalse(value("indicatorMix").contains(":"), "A ratio is shown while loading")
        XCTAssertFalse(value("indicatorRecovery").contains("%"), "A percentage is shown while loading")
        XCTAssertFalse(el("trendsChart").exists)
        XCTAssertFalse(el("coachReview").exists)
    }
}
