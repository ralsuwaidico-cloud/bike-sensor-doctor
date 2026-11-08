import XCTest

/// Adaptive coach smoke test (ios/ADAPTIVE_COACH.md): a phone updated from build 40 with a strength session today logs
/// it with the quick log from Plan → the post-workout check-in appears → Save → the Coach adjustments view opens →
/// Done → back on Home, app alive. Uses the build-40 seed of LaunchSmokeTests (read only, that file is not edited).
final class AdaptiveSmokeTests: XCTestCase {

    override func setUpWithError() throws { continueAfterFailure = false }

    func testQuickStrengthLogShowsCheckInThenAdjustments() {
        let app = XCUIApplication()
        app.launchEnvironment["BC_UITEST_SEED_JSON"] = LaunchSmokeTests.build40Store()
        app.launch()
        XCTAssertTrue(app.waitForHome(name: "Rashed", timeout: 25), "seeded rider lands on Home")

        // Plan › Log strength › Quick log for today's session (Home B: Home keeps one primary action; the quick log lives
        // in Plan's toolbar and in Train now)
        app.buttons["Plan"].firstMatch.tap()
        // run 150: the tab tap during launch did not register (Home stayed) — confirm Plan, tap again once if needed
        if !app.descendants(matching: .any)["planDayStrip"].firstMatch.waitForExistence(timeout: 10) { _ = app.buttons["Plan"].firstMatch.tapWhenSettled() }
        XCTAssertTrue(app.descendants(matching: .any)["planDayStrip"].firstMatch.waitForExistence(timeout: 15), "Plan opens")
        let log = app.buttons["Log strength"].firstMatch
        // run 131: the first test of a cold Release build (seed migrated at launch) took > 10 s to show Plan's toolbar; the
        // rest of this test then passed, so this is launch timing, not a missing control — wait like the other smoke tests.
        // run 157: first test on a cold Release build — the toolbar appeared after the 30 s wait; give it 60 s and one re-tap
        if !log.waitForExistence(timeout: 30) { _ = app.buttons["Plan"].firstMatch.tapWhenSettled() }
        XCTAssertTrue(log.waitForExistence(timeout: 30), "Log strength on Plan")
        var opened = false
        for _ in 0..<3 where !opened {
            if !app.buttons["Quick log"].firstMatch.exists { log.tap() }
            let quick = app.buttons["Quick log"].firstMatch
            if quick.waitForExistence(timeout: 5) {
                quick.tapWhenSettled()   // run 117: isHittable throws while the menu animates — wait for a settled frame (UITestWaits)
            }
            opened = app.navigationBars["Log strength"].waitForExistence(timeout: 10)
        }
        let logBar = app.navigationBars["Log strength"]
        XCTAssertTrue(logBar.waitForExistence(timeout: 10), "quick strength log opens")
        let save = logBar.buttons["Save"].firstMatch
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        save.tap()

        // the check-in replaces the log sheet
        let submit = app.buttons["checkInSubmit"].firstMatch
        XCTAssertTrue(submit.waitForExistence(timeout: 10), "post-workout check-in appears after the log")
        XCTAssertTrue(app.navigationBars["Check-in"].exists)
        XCTAssertTrue(app.buttons["checkInSkip"].firstMatch.exists, "the check-in can be skipped")
        submit.tap()

        // the coach runs and shows what changed (and why) in the Adjustments view
        // runs 194/195 (Sunday, cold Release build): the check-in's coach run + the pushed Adjustments view took > 10 s
        // once and once left the snapshot timing out; give it 40 s and, on failure, say what is on screen instead
        let adjustments = app.navigationBars["Coach adjustments"]
        if !adjustments.waitForExistence(timeout: 40) {
            let bars = app.navigationBars.allElementsBoundByIndex.map { $0.identifier }.joined(separator: " | ")
            let sheets = app.sheets.count
            XCTFail("Adjustments view did not open within 40 s after the check-in — navigation bars: [\(bars)], sheets: \(sheets), app state: \(app.state.rawValue)")
        }
        XCTAssertEqual(app.state, .runningForeground)
        let done = app.buttons["adjustmentsDone"].firstMatch
        XCTAssertTrue(done.waitForExistence(timeout: 5))
        done.tap()
        app.buttons["Home"].firstMatch.tap()
        XCTAssertTrue(app.waitForHome(name: "Rashed", timeout: 10), "back on Home")
        XCTAssertEqual(app.state, .runningForeground)
    }
}
