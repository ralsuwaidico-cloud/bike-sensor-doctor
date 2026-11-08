import XCTest

/// Owner 8 Nov 18:33 (verification 3): "Delete All Data genuinely removes all local and synced Cyclift data" — the UI path,
/// end to end, on a store seeded with a profile, a plan and history (build-40 upgrade seed). Cancel is covered by
/// LaunchSmokeTests; this test confirms the Delete choice: the app returns to the Welcome screen at once, and a plain
/// relaunch (no seed, no reset) still starts at Welcome — nothing came back from disk. The Apple Health choice is a
/// physical-device check (permission prompt and HealthKit records do not exist in the simulator's CI run).
final class DeleteAllDataJourneyTests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testDeleteAllDataReturnsToWelcomeAndStaysEmptyAfterRelaunch() {
        let app = XCUIApplication()
        app.launchEnvironment["BC_UITEST_SEED_JSON"] = LaunchSmokeTests.build40Store()
        app.launch()
        XCTAssertTrue(app.waitForHome(name: "Rashed", timeout: 25), "seeded rider lands on Home")

        let profileTab = app.buttons["Profile"].firstMatch
        XCTAssertTrue(profileTab.waitForExistence(timeout: 10)); profileTab.tap()
        XCTAssertTrue(app.staticTexts["Profile"].firstMatch.waitForExistence(timeout: 10))
        let settingsRow = app.buttons["profileSettings"].firstMatch
        var tries = 0
        while !(settingsRow.exists && settingsRow.isHittable) && tries < 10 { app.swipeUp(); tries += 1 }
        XCTAssertTrue(settingsRow.waitForExistence(timeout: 10), "Profile › Settings row"); settingsRow.tap()

        let delete = app.buttons["deleteAllData"].firstMatch
        tries = 0
        while !(delete.exists && delete.isHittable) && tries < 10 { app.swipeUp(); tries += 1 }
        XCTAssertTrue(delete.waitForExistence(timeout: 10), "Your data › Delete all data")
        delete.tap()
        let alert = app.alerts["Delete everything on this phone?"].firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 10), "deletion asks first")
        // the alert names what goes and offers the Health records as a separate, explicit choice
        XCTAssertTrue(alert.buttons["Delete"].exists, "plain Delete")
        XCTAssertTrue(alert.buttons["Delete, including Cyclift's Apple Health workouts"].exists, "Health records are a separate choice")
        XCTAssertTrue(alert.buttons["Cancel"].exists)
        alert.buttons["Delete"].tap()

        // Everything local is gone: the app is back at Welcome (guest), nothing of the rider remains on screen
        let start = app.buttons["onboardingContinue"].firstMatch
        XCTAssertTrue(start.waitForExistence(timeout: 15), "after Delete the app returns to the Welcome screen")
        XCTAssertFalse(app.staticTexts["Rashed"].firstMatch.exists, "the rider's name is gone")
        XCTAssertFalse(app.buttons["centreButton"].firstMatch.exists, "no dock / plan behind Welcome")

        // A plain relaunch (no seed, no reset) reads the store from disk: still Welcome — the deletion was persisted
        app.terminate()
        let again = XCUIApplication()
        again.launch()
        XCTAssertTrue(again.buttons["onboardingContinue"].firstMatch.waitForExistence(timeout: 30), "relaunch starts at Welcome: nothing came back from disk")
        XCTAssertFalse(again.waitForHome(name: "Rashed", timeout: 3), "the deleted rider must not reappear")
        XCTAssertEqual(again.state, .runningForeground)
    }
}
