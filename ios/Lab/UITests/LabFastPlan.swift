import XCTest

/// Cyclift Lab — focused Plan checks: the Recurring Plan (sheet B2) and Add a goal → set-up → program preview →
/// approval (sheets B3 / B4). One theme, the plain demo athlete (hybrid, one goal: Fitness). Required controls fail the
/// check when absent, and each step checks the real destination is on screen.
final class LabFastPlan: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = true }

    private func shot(_ name: String) {
        let dir = ProcessInfo.processInfo.environment["LAYOUT_DIR"] ?? ""
        guard !dir.isEmpty else { return }
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent("fast-\(name).png"))
    }
    private func launch(_ extra: [String: String] = [:]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["LAB_FRESH_DEMO"] = "1"
        app.launchEnvironment["LAB_THEME"] = "obsidian"
        for (k, v) in extra { app.launchEnvironment[k] = v }
        app.launch()
        XCTAssertTrue(app.waitForHome(name: "Demo", timeout: 30), "required: Home with the demo athlete")
        return app
    }
    private func tab(_ app: XCUIApplication, _ name: String) {
        let b = app.buttons[name].firstMatch
        XCTAssertTrue(b.waitForExistence(timeout: 8), "required: tab \(name)")
        if b.exists { b.tap(); app.settleForScreenshot(1) }
    }
    private func el(_ app: XCUIApplication, _ id: String) -> XCUIElement { app.descendants(matching: .any).matching(identifier: id).firstMatch }

    /// Requires the element, brings it clear of the sheet edges and taps it.
    private func press(_ app: XCUIApplication, _ id: String, _ what: String) {
        let e = el(app, id)
        XCTAssertTrue(e.waitForExistence(timeout: 8), "required: \(what) (\(id))")
        guard e.exists else { return }
        if !e.isHittable { _ = app.reveal(e) }
        e.tap(); app.settleForScreenshot(1)
    }
    private func openPlan(_ app: XCUIApplication) {
        tab(app, "Plan")
        XCTAssertTrue(app.staticTexts["planTitle"].firstMatch.waitForExistence(timeout: 8), "required: Plan is shown")
        XCTAssertTrue(el(app, "planAddGoal").waitForExistence(timeout: 8), "required: Add a goal on the program row")
        XCTAssertTrue(el(app, "planSection-recurring").exists, "required: the Weekly / Recurring control")
    }
    /// The words of Plan's goal line (the program row).
    private func goalLine(_ app: XCUIApplication) -> String {
        let row = el(app, "planProgram")
        XCTAssertTrue(row.waitForExistence(timeout: 8), "required: Plan's goal row")
        return row.exists ? row.label : ""
    }

    /// From Plan to the program preview for "Strength" as the main goal. Checks every step on the way.
    private func openPreviewForStrengthAsMain(_ app: XCUIApplication, shots: String?) {
        press(app, "planAddGoal", "Add a goal")
        XCTAssertTrue(el(app, "planGoalSheet").waitForExistence(timeout: 8), "required: the Add a goal sheet (B3) opens — not the old Goals page")
        XCTAssertFalse(app.buttons["goalsSave"].firstMatch.exists, "the old Goals page must not be what opens in the redesign")
        XCTAssertTrue(app.staticTexts["planGoalSheetTitle"].firstMatch.exists, "required: the sheet title")
        let sub = el(app, "planGoalSubtitle")
        XCTAssertTrue(sub.exists, "required: the sheet says which goals the athlete has")
        XCTAssertTrue(sub.label.contains("1 goal") && sub.label.contains("Fitness"), "required: the demo athlete's one goal is named (\(sub.label))")
        for id in ["planGoalCategory-fitness", "planGoalCategory-strength", "planGoalCategory-cycling"] {
            XCTAssertTrue(el(app, id).exists, "required: a hybrid athlete is offered \(id)")
        }
        XCTAssertTrue(el(app, "planGoalNotOffered").exists, "required: the sheet says what is not offered yet")
        if let s = shots { shot("\(s)-1-add-a-goal-sheet") }

        press(app, "planGoalCategory-strength", "Build strength or muscle")
        XCTAssertTrue(el(app, "planGoalSetup").waitForExistence(timeout: 8), "required: goal set-up (B4 step 1)")
        XCTAssertTrue(el(app, "planGoalStep").label.contains("1 of 2"), "required: step 1 of 2")
        for id in ["planGoalType-strength", "planGoalType-muscle", "planGoalType-stamina", "planGoalType-maintain"] {
            XCTAssertTrue(el(app, id).exists, "required: goal type \(id)")
        }
        for id in ["planGoalPriority-primary", "planGoalPriority-secondary", "planGoalUsesType", "planGoalUsesTime", "planGoalUsesRecent", "planGoalContinue"] {
            XCTAssertTrue(el(app, id).exists, "required: \(id) on the set-up step")
        }
        press(app, "planGoalType-strength", "goal type Strength")
        press(app, "planGoalPriority-primary", "Primary")
        XCTAssertTrue(el(app, "planGoalPriority-primary").isSelected, "required: Primary is selected")
        if let s = shots { shot("\(s)-2-goal-setup") }

        press(app, "planGoalContinue", "Preview plan changes")
        XCTAssertTrue(el(app, "planGoalProgramPreview").waitForExistence(timeout: 12), "required: the program preview (B4 step 2)")
        XCTAssertTrue(el(app, "planGoalStep").label.contains("2 of 2"), "required: step 2 of 2")
        let before = el(app, "planGoalBefore"), after = el(app, "planGoalAfter")
        XCTAssertTrue(before.exists && after.exists, "required: the preview shows now and after approval")
        let b = before.value as? String ?? "", a = after.value as? String ?? ""
        XCTAssertEqual(b, "Fitness", "required: 'Now' is the athlete's current goal")
        XCTAssertTrue(a.contains("Strength (main)") && a.contains("Fitness"), "required: 'After approval' has Strength as the main goal and keeps Fitness (\(a))")
        XCTAssertTrue(el(app, "planGoalHeadline").exists, "required: the planner's headline")
        XCTAssertTrue(el(app, "planGoalSessions").exists, "required: what happens to the planned sessions")
        for id in ["planGoalApprove", "planGoalAdjust", "planGoalNotNow", "planGoalPreviewNote"] {
            XCTAssertTrue(el(app, id).exists, "required: \(id) on the preview")
        }
        print("LAB-NOTE plan goal preview: now '\(b)' → after '\(a)'; headline '\(el(app, "planGoalHeadline").label)'")
        if let s = shots { shot("\(s)-3-program-preview") }
    }

    /// Recurring Plan (sheet B2): seven weekday rows Mon–Sun and the availability row.
    func testRecurringPlan() {
        let app = launch()
        openPlan(app)
        press(app, "planSection-recurring", "Recurring Plan")
        XCTAssertTrue(el(app, "planSection-recurring").isSelected, "required: Recurring Plan is the selected section")
        var words: [String] = []
        for d in ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"] {
            let row = el(app, "planRecurring-\(d)")
            XCTAssertTrue(row.waitForExistence(timeout: 8), "required: the \(d) row")
            if row.exists { words.append(row.label) }
        }
        XCTAssertEqual(words.count, 7, "required: seven weekday rows")
        XCTAssertTrue(words.contains { $0.contains("Ride") || $0.contains("Strength") || $0.contains("min") }, "required: the demo athlete's week has training days (\(words))")
        let avail = el(app, "planAvailability")
        XCTAssertTrue(avail.exists, "required: the Availability & preferences row")
        XCTAssertTrue(avail.label.contains("Availability & preferences") && avail.label.contains("day"), "required: the row names the training days (\(avail.label))")
        XCTAssertFalse(avail.label.contains("recorded"), "the row summarises the normal week, not this week's recordings (\(avail.label))")
        print("LAB-NOTE recurring plan rows: \(words.joined(separator: " | ")) || \(avail.label) || warning: '\(avail.value as? String ?? "")'")
        shot("plan-recurring")
        // a weekday row opens the existing week editor
        press(app, "planRecurring-Mon", "the Monday row")
        XCTAssertTrue(app.buttons["weekSave"].firstMatch.waitForExistence(timeout: 8), "required: a weekday row opens the week editor")
        shot("plan-recurring-weekday-editor")
    }

    /// Add a goal → B3 → B4 set-up → preview with now / after → Not now: nothing changed. The same again through the
    /// Adjust and back buttons: still nothing changed.
    func testAddGoalCancelLeavesGoalUnchanged() {
        let app = launch()
        openPlan(app)
        let start = goalLine(app)
        XCTAssertTrue(start.contains("Fitness"), "required: the demo athlete's goal line names Fitness (\(start))")
        openPreviewForStrengthAsMain(app, shots: "plan-goal")
        press(app, "planGoalNotNow", "Not now")
        XCTAssertTrue(app.staticTexts["planTitle"].firstMatch.waitForExistence(timeout: 8), "required: back on Plan")
        XCTAssertFalse(el(app, "planGoalProgramPreview").exists, "required: the goal sheet closed")
        XCTAssertEqual(goalLine(app), start, "required: Not now leaves the goal line unchanged")
        // Adjust returns to the set-up step; back from there returns to the sheet; nothing is saved on the way
        openPreviewForStrengthAsMain(app, shots: nil)
        press(app, "planGoalAdjust", "Adjust")
        XCTAssertTrue(el(app, "planGoalSetup").waitForExistence(timeout: 8), "required: Adjust returns to the set-up step")
        press(app, "planGoalBack", "back to Goals")
        XCTAssertTrue(el(app, "planGoalSheet").waitForExistence(timeout: 8), "required: back on the Add a goal sheet")
        let sub = el(app, "planGoalSubtitle")
        XCTAssertTrue(sub.label.contains("1 goal") && sub.label.contains("Fitness"), "required: still one goal, Fitness (\(sub.label))")
        shot("plan-goal-4-after-cancel")
    }

    /// The same journey with Approve: Plan's goal line shows the new main goal, and it is still there after a relaunch.
    func testAddGoalApprovePersists() {
        let app = launch()
        openPlan(app)
        let start = goalLine(app)
        openPreviewForStrengthAsMain(app, shots: nil)
        press(app, "planGoalApprove", "Approve these changes")
        XCTAssertTrue(app.staticTexts["planTitle"].firstMatch.waitForExistence(timeout: 8), "required: back on Plan after approval")
        XCTAssertFalse(el(app, "planGoalProgramPreview").exists, "required: the goal sheet closed after approval")
        let now = goalLine(app)
        XCTAssertTrue(now.contains("Strength +1"), "required: the goal line shows the new main goal and one more (\(now))")
        XCTAssertNotEqual(now, start, "required: the goal line changed")
        shot("plan-goal-5-approved")
        // the sheet now knows both goals
        press(app, "planAddGoal", "Add a goal")
        let sub = el(app, "planGoalSubtitle")
        XCTAssertTrue(sub.waitForExistence(timeout: 8), "required: the sheet opens again")
        XCTAssertTrue(sub.label.contains("2 goals") && sub.label.contains("Strength"), "required: two goals, main Strength (\(sub.label))")
        // relaunch without the fresh-demo switch: the stored athlete is read back
        app.terminate()
        app.launchEnvironment["LAB_FRESH_DEMO"] = nil
        app.launch()
        XCTAssertTrue(app.waitForHome(name: "Demo", timeout: 30), "required: Home after the relaunch")
        openPlan(app)
        let again = goalLine(app)
        XCTAssertTrue(again.contains("Strength +1"), "required: the approved goal is still there after a relaunch (\(again))")
        shot("plan-goal-6-after-relaunch")
    }
}
