import XCTest

/// Adaptive coach smoke test (ios/ADAPTIVE_COACH.md): a phone updated from build 40 with a strength session today logs
/// it with the quick log from Home → the post-workout check-in appears → Save → the Coach adjustments view opens →
/// Done → back on Home, app alive. Uses the build-40 seed of LaunchSmokeTests (read only, that file is not edited).
final class AdaptiveSmokeTests: XCTestCase {

    override func setUpWithError() throws { continueAfterFailure = false }

    func testQuickStrengthLogShowsCheckInThenAdjustments() {
        let app = XCUIApplication()
        app.launchEnvironment["BC_UITEST_SEED_JSON"] = LaunchSmokeTests.build40Store()
        app.launch()
        XCTAssertTrue(app.navigationBars["Hi Rashed"].waitForExistence(timeout: 25) || app.staticTexts["Hi Rashed"].waitForExistence(timeout: 5), "seeded rider lands on Home")

        // Home › Log strength (the hybrid coach card) → quick log for today's session
        let log = app.buttons["Log strength"].firstMatch
        XCTAssertTrue(log.waitForExistence(timeout: 10), "Log strength on Home")
        log.tap()
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
        XCTAssertTrue(app.navigationBars["Coach adjustments"].waitForExistence(timeout: 10), "Adjustments view opens after the check-in")
        XCTAssertEqual(app.state, .runningForeground)
        let done = app.buttons["adjustmentsDone"].firstMatch
        XCTAssertTrue(done.waitForExistence(timeout: 5))
        done.tap()
        XCTAssertTrue(app.navigationBars["Hi Rashed"].waitForExistence(timeout: 10) || app.staticTexts["Hi Rashed"].waitForExistence(timeout: 5), "back on Home")
        XCTAssertEqual(app.state, .runningForeground)
    }
}
