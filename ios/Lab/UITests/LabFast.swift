import XCTest

/// Cyclift Lab — FAST focused screen checks (ios/ci/lab-fast.sh). Each check launches once, in one theme, from a ready
/// demo athlete, and goes straight to the screens it is about. Required controls still fail the check when absent.
/// These are for routine screen work; the full journeys stay in LabChecks and run in the full Lab run.
final class LabFast: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = true }

    private func shot(_ name: String) {
        let dir = ProcessInfo.processInfo.environment["LAYOUT_DIR"] ?? ""
        guard !dir.isEmpty else { return }
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent("fast-\(name).png"))
    }
    private func launch(_ extra: [String: String] = [:], arguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += arguments
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

    /// Home, Plan, Progress and the Coach page, one theme, one launch.
    func testScreens() {
        let app = launch()
        XCTAssertTrue(app.staticTexts["CYCLIFT LAB · DEMO DATA"].firstMatch.waitForExistence(timeout: 10), "required: the demo banner")
        shot("1-home")
        tab(app, "Plan")
        XCTAssertTrue(app.staticTexts["planTitle"].firstMatch.waitForExistence(timeout: 8), "required: Plan is shown")
        XCTAssertTrue(app.staticTexts["planDayHeader"].firstMatch.exists, "required: today's day is selected")
        shot("2-plan")
        let row = el(app, "planCoachRow")
        if row.exists {
            row.tap()
            XCTAssertTrue(el(app, "coachTimeline").waitForExistence(timeout: 8), "required: the Plan row opens the Coach page")
            shot("3-coach")
            app.buttons["coachClose"].firstMatch.tap(); app.settleForScreenshot(1)
        }
        tab(app, "Progress")
        XCTAssertTrue(el(app, "evolutionTrack").waitForExistence(timeout: 8), "required: Progress shows the Evolution Track")
        shot("4-progress")
    }

    /// Plan with an open Coach suggestion (fixture LAB_DEMO_PROPOSAL): the row and the Coach page with Not now · Review.
    func testOpenSuggestion() {
        let app = launch(["LAB_DEMO_PROPOSAL": "1"])
        tab(app, "Plan")
        let row = el(app, "planCoachRow")
        XCTAssertTrue(row.waitForExistence(timeout: 8), "required: Plan shows the Coach row")
        XCTAssertTrue(row.label.hasPrefix("Coach Suggests") && row.label.hasSuffix("Review"), "required: an open suggestion offers Review (\(row.label))")
        shot("5-plan-open-suggestion")
        row.tap()
        XCTAssertTrue(el(app, "coachTimeline").waitForExistence(timeout: 8), "required: the Coach page opens")
        let notNow = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'coachNotNow-'")).firstMatch
        XCTAssertTrue(notNow.waitForExistence(timeout: 8), "required: Not now is offered")
        _ = app.reveal(notNow)
        shot("6-coach-open-suggestion")
    }

    /// Profile sheet P03: Athlete Profile, Personal details (edit the name, Save lights, the name is stored) and
    /// Type & experience (the four controls; Save stays unlit until something changes).
    func testProfileAthletePages() {
        let app = launch()
        let avatar = app.buttons["homeAvatar"].firstMatch
        XCTAssertTrue(avatar.waitForExistence(timeout: 8), "required: the Home avatar"); avatar.tap(); app.settleForScreenshot(1)
        let a = el(app, "profileSectionA")
        XCTAssertTrue(a.waitForExistence(timeout: 8), "required: Profile landing"); a.tap(); app.settleForScreenshot(1)
        shot("p03-A-athlete-profile")
        let personal = el(app, "profilePersonal")
        XCTAssertTrue(personal.waitForExistence(timeout: 8), "required: Personal details row"); personal.tap(); app.settleForScreenshot(1)
        let name = app.textFields["personalName"].firstMatch
        XCTAssertTrue(name.waitForExistence(timeout: 8), "required: the name field")
        XCTAssertTrue(el(app, "personalDOB").exists, "required: date of birth"); XCTAssertTrue(app.textFields["personalWeight"].firstMatch.exists, "required: weight")
        let save = app.buttons["personalSave"].firstMatch
        XCTAssertTrue(save.exists, "required: Save in the bar"); XCTAssertFalse(save.isEnabled, "Save is unlit until something changes")
        shot("p03-A1-personal-details")
        name.tap(); name.typeText(" Lab")
        XCTAssertTrue(save.isEnabled, "required: Save lights after a change")
        shot("p03-A1-personal-details-changed")
        save.tap(); app.settleForScreenshot(1)
        XCTAssertTrue(personal.waitForExistence(timeout: 8), "required: back on Athlete Profile after Save")
        XCTAssertTrue(personal.label.contains("Demo Lab"), "required: the saved name is shown (\(personal.label))")
        let type = el(app, "profileType")
        XCTAssertTrue(type.waitForExistence(timeout: 8), "required: Athlete type row"); type.tap(); app.settleForScreenshot(1)
        for id in ["typeMode", "typeBalance", "typeRiding", "typeLifting"] { XCTAssertTrue(el(app, id).waitForExistence(timeout: 8), "required: \(id)") }
        XCTAssertFalse(app.buttons["typeSave"].firstMatch.isEnabled, "Save is unlit until something changes")
        shot("p03-A3-type-experience")
    }

    /// Profile sheet P04: Training Setup, Equipment & restrictions (chips and the restriction rows) and
    /// Recovery & pauses (the three-way recovery control and the pause row). Nothing is changed.
    func testProfileTrainingSetupPages() {
        let app = launch()
        let avatar = app.buttons["homeAvatar"].firstMatch
        XCTAssertTrue(avatar.waitForExistence(timeout: 8), "required: the Home avatar"); avatar.tap(); app.settleForScreenshot(1)
        let b = el(app, "profileSectionB")
        XCTAssertTrue(b.waitForExistence(timeout: 8), "required: Training Setup on the landing"); b.tap(); app.settleForScreenshot(1)
        shot("p04-B-training-setup")
        let equipment = el(app, "profileEquipment")
        XCTAssertTrue(equipment.waitForExistence(timeout: 8), "required: Equipment row"); equipment.tap(); app.settleForScreenshot(1)
        XCTAssertTrue(el(app, "profileEquipmentPage").waitForExistence(timeout: 8) || el(app, "equipmentChips").exists, "required: the Equipment page")
        let chips = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'equip-'"))
        XCTAssertGreaterThanOrEqual(chips.count, 4, "required: equipment is offered as chips")
        XCTAssertTrue(el(app, "equipExcluded").exists, "required: the restrictions row")
        shot("p04-B1-equipment")
        app.navigationBars.buttons.firstMatch.tap(); app.settleForScreenshot(1)
        let recovery = el(app, "profileHealthSafety")
        XCTAssertTrue(recovery.waitForExistence(timeout: 8), "required: Recovery & pauses row"); recovery.tap(); app.settleForScreenshot(1)
        XCTAssertTrue(el(app, "recoveryCapacity").waitForExistence(timeout: 8), "required: the recovery control")
        XCTAssertTrue(el(app, "healthPause").exists, "required: Pause training row")
        shot("p04-B3-recovery-pauses")
    }

    /// Profile sheet P05: Performance Settings, Heart rate (values with sources, zone method, zones or "unknown") and
    /// Power (FTP with its source, the meter's state, zones or "not shown"). Edit opens the existing editor.
    func testProfilePerformancePages() {
        let app = launch()
        let avatar = app.buttons["homeAvatar"].firstMatch
        XCTAssertTrue(avatar.waitForExistence(timeout: 8), "required: the Home avatar"); avatar.tap()
        let c = el(app, "profileSectionC")
        XCTAssertTrue(c.waitForExistence(timeout: 8), "required: Performance Settings on the landing"); c.tap()
        let hr = el(app, "profileHR")
        XCTAssertTrue(hr.waitForExistence(timeout: 8), "required: Heart rate row"); shot("p05-C-performance"); hr.tap()
        for id in ["hrResting", "hrMaximum", "hrThreshold", "hrZoneMethod"] { XCTAssertTrue(el(app, id).waitForExistence(timeout: 8), "required: \(id)") }
        XCTAssertTrue(app.buttons["hrEdit"].firstMatch.exists, "required: Edit in the bar")
        shot("p05-C1-heart-rate")
        app.buttons["hrEdit"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Heart rate"].firstMatch.waitForExistence(timeout: 8), "required: Edit opens the heart-rate editor")
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(el(app, "hrResting").waitForExistence(timeout: 8), "back on Heart rate")
        app.navigationBars.buttons.firstMatch.tap()
        let ftp = el(app, "profileFTP")
        XCTAssertTrue(ftp.waitForExistence(timeout: 8), "required: Power row"); ftp.tap()
        XCTAssertTrue(el(app, "ftpValue").waitForExistence(timeout: 8), "required: the FTP value row")
        XCTAssertTrue(el(app, "powerMeter").exists, "required: the power-meter row")
        XCTAssertTrue(app.buttons["powerEdit"].firstMatch.exists, "required: Edit in the bar")
        shot("p05-C2-power")
    }

    private func openProfileSection(_ app: XCUIApplication, _ id: String) {
        let avatar = app.buttons["homeAvatar"].firstMatch
        XCTAssertTrue(avatar.waitForExistence(timeout: 8), "required: the Home avatar"); avatar.tap()
        let s = el(app, id)
        XCTAssertTrue(s.waitForExistence(timeout: 8), "required: \(id) on the Profile landing"); s.tap()
    }
    private func back(_ app: XCUIApplication) { app.navigationBars.buttons.firstMatch.tap() }
    /// The two restriction rows must not run into each other.
    private func restrictionRowsAreSeparate(_ app: XCUIApplication, _ tag: String) {
        let a = el(app, "equipExcluded"), b = el(app, "equipPrefs")
        XCTAssertTrue(a.waitForExistence(timeout: 8) && b.exists, "required (\(tag)): both restriction rows")
        _ = app.reveal(b, top: 120, bottomMargin: 130)
        print("LAB-NOTE equipment rows \(tag): first \(Int(a.frame.minY))–\(Int(a.frame.maxY)), second \(Int(b.frame.minY))–\(Int(b.frame.maxY))")
        XCTAssertLessThanOrEqual(a.frame.maxY, b.frame.minY + 1, "required (\(tag)): the restriction rows do not overlap")
    }

    /// Edits that change training go through the existing preview and approval, and nothing changes when it is
    /// cancelled: equipment (sheet P04 B1), recovery preference (B3), athlete type (P03 A3).
    func testProfileEditsNeedApproval() {
        let app = launch()
        openProfileSection(app, "profileSectionB")
        let equipment = el(app, "profileEquipment")
        XCTAssertTrue(equipment.waitForExistence(timeout: 8), "required: Equipment row"); equipment.tap()
        restrictionRowsAreSeparate(app, "normal text")
        shot("p04-B1-equipment-rows")
        let chip = app.buttons["equip-barbell"].firstMatch
        XCTAssertTrue(chip.waitForExistence(timeout: 8), "required: the Barbell chip")
        let before = chip.isSelected
        chip.tap()
        XCTAssertNotEqual(chip.isSelected, before, "the chip shows the choice")
        back(app)
        let apply = app.buttons["planChangeApply"].firstMatch, cancel = app.buttons["planChangeCancel"].firstMatch
        XCTAssertTrue(apply.waitForExistence(timeout: 10), "required: an equipment change is previewed for approval")
        shot("p04-B1-equipment-preview")
        cancel.tap()
        XCTAssertTrue(equipment.waitForExistence(timeout: 8), "back on Training Setup"); equipment.tap()
        XCTAssertTrue(chip.waitForExistence(timeout: 8)); XCTAssertEqual(chip.isSelected, before, "required: cancelled means the equipment is unchanged")
        back(app)
        if apply.waitForExistence(timeout: 2) { cancel.tap() }      // leaving unchanged must not propose anything
        let recovery = el(app, "profileHealthSafety")
        XCTAssertTrue(recovery.waitForExistence(timeout: 8), "required: Recovery & pauses row"); recovery.tap()
        let slower = app.buttons["Slower"].firstMatch, normal = app.buttons["Normal"].firstMatch
        XCTAssertTrue(slower.waitForExistence(timeout: 8) && normal.isSelected, "required: recovery control, Normal chosen in the demo")
        slower.tap()
        XCTAssertTrue(apply.waitForExistence(timeout: 10), "required: a recovery change is previewed for approval")
        shot("p04-B3-recovery-preview")
        cancel.tap()
        XCTAssertTrue(normal.waitForExistence(timeout: 8) && normal.isSelected, "required: cancelled means recovery is unchanged")
        back(app); back(app)
        let a = el(app, "profileSectionA")
        XCTAssertTrue(a.waitForExistence(timeout: 8), "back on the landing"); a.tap()
        let type = el(app, "profileType")
        XCTAssertTrue(type.waitForExistence(timeout: 8), "required: Athlete type row"); type.tap()
        let strength = el(app, "typeMode").buttons["Strength"].firstMatch, save = app.buttons["typeSave"].firstMatch
        XCTAssertTrue(strength.waitForExistence(timeout: 8), "required: the Strength option"); strength.tap()
        XCTAssertTrue(save.isEnabled, "required: Save lights after a change"); save.tap()
        XCTAssertTrue(apply.waitForExistence(timeout: 10), "required: an athlete-type change is previewed for approval")
        shot("p03-A3-type-preview")
        cancel.tap()
    }

    /// The Equipment page at a large accessibility text size: chips wrap, the restriction rows stay separate.
    func testEquipmentAtLargeText() {
        let app = launch(arguments: ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityL"])
        openProfileSection(app, "profileSectionB")
        let equipment = el(app, "profileEquipment")
        XCTAssertTrue(equipment.waitForExistence(timeout: 8), "required: Equipment row"); equipment.tap()
        XCTAssertGreaterThanOrEqual(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'equip-'")).count, 4, "required: the chips")
        shot("p04-B1-equipment-large-text")
        restrictionRowsAreSeparate(app, "large text")
        shot("p04-B1-equipment-large-text-rows")
    }
}
