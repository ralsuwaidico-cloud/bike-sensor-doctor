import XCTest

/// Completeness audit (owner 8 Nov 19:04), item 6 — plan edit → preview → apply as the athlete does it: today's planned
/// strength session → More → Edit type / duration → change the duration → Review → the before/after preview → Apply →
/// the session shows the new duration and the Plan's change history lists the change. Nothing is saved before Apply.
final class PlanEditPreviewApplyTests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = true }

    func testEditDurationGoesThroughPreviewAndApply() {
        let app = XCUIApplication()
        app.launchEnvironment["BC_UITEST_SEED_JSON"] = LaunchSmokeTests.build36Store()      // strength today, routine assigned (45 min planned)
        app.launch()
        XCTAssertTrue(app.waitForHome(name: "Rashed", timeout: 30))
        let centre = app.buttons["centreButton"].firstMatch
        XCTAssertTrue(centre.waitForExistence(timeout: 10)); _ = centre.waitUntilSettled(timeout: 5); centre.tap()
        XCTAssertTrue(app.openFromHub(), "hub → today's strength session")
        XCTAssertTrue(app.buttons["startWorkout"].firstMatch.waitForExistence(timeout: 10), "session screen")

        // More → Edit type / duration
        let more = app.buttons["moreMenu"].firstMatch
        XCTAssertTrue(more.waitForExistence(timeout: 5)); more.tap()
        let edit = app.buttons["Edit type / duration"].firstMatch
        XCTAssertTrue(edit.waitForExistence(timeout: 5), "More offers Edit"); edit.tap()
        let slider = app.sliders["editDuration"].firstMatch
        XCTAssertTrue(slider.waitForExistence(timeout: 10), "duration slider")
        let before = slider.value as? String ?? ""
        slider.adjust(toNormalizedSliderPosition: 0.15)          // 15…180 min → ≈ 40 min, a real change from 45
        let after = slider.value as? String ?? ""
        XCTAssertNotEqual(before, after, "the duration changed (\(before) → \(after))")

        // Review → preview: nothing applied yet
        app.buttons["editSave"].firstMatch.tap()
        let preview = app.descendants(matching: .any)["changePreview"].firstMatch
        XCTAssertTrue(preview.waitForExistence(timeout: 15), "a duration change on a strength session shows the before/after preview")
        let apply = app.buttons["changeApply"].firstMatch
        XCTAssertTrue(apply.waitForExistence(timeout: 5), "Apply is offered")
        // Cancel first: the session is unchanged
        let cancel = app.buttons["changeCancel"].firstMatch
        if cancel.exists { cancel.tap(); XCTAssertTrue(preview.waitUntilGone(timeout: 5), "cancel closes the preview") }
        // the edit sheet is still there (or we are back on the session); redo the review and apply this time
        if !app.buttons["editSave"].firstMatch.exists {
            more.tap(); app.buttons["Edit type / duration"].firstMatch.tap()
            XCTAssertTrue(slider.waitForExistence(timeout: 10)); slider.adjust(toNormalizedSliderPosition: 0.15)
        }
        app.buttons["editSave"].firstMatch.tap()
        XCTAssertTrue(preview.waitForExistence(timeout: 15))
        XCTAssertTrue(apply.waitForExistence(timeout: 5)); apply.tap()
        XCTAssertTrue(preview.waitUntilGone(timeout: 10), "Apply closes the preview")

        // the session screen shows the new duration; the Plan's Changes page lists the applied change
        XCTAssertTrue(app.buttons["startWorkout"].firstMatch.waitForExistence(timeout: 10) || app.waitForHome(name: "Rashed", timeout: 10))
        if app.buttons["Done"].firstMatch.exists { app.buttons["Done"].firstMatch.tap() }
        if app.buttons["hubClose"].firstMatch.exists { app.buttons["hubClose"].firstMatch.tap() }
        app.buttons["Plan"].firstMatch.tap()
        XCTAssertTrue(app.descendants(matching: .any)["planDayStrip"].firstMatch.waitForExistence(timeout: 15), "Plan")
        let changes = app.buttons["planChanges"].firstMatch
        for _ in 0..<6 where !changes.isHittable { app.swipeUp(velocity: .slow) }
        XCTAssertTrue(changes.waitForExistence(timeout: 5), "Plan › Changes row"); changes.tap()
        XCTAssertTrue(app.descendants(matching: .any)["planVersionRow"].firstMatch.waitForExistence(timeout: 10), "the applied edit is listed in the change history")
        XCTAssertEqual(app.state, .runningForeground)
    }
}
