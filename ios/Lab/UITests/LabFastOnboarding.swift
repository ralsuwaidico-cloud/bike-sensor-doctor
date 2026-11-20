import XCTest

/// Cyclift Lab — FAST checks of the seven-page onboarding (reference sheets Y1, Y4, Y5 of onboarding v3.3; page 2 is
/// the v3.4 Athletic Roster). Starts with no athlete (fixture LAB_NEW_ATHLETE). Every required element fails the check
/// when it is absent, and the journey ends on the app's own Home and Plan showing what was approved.
final class LabFastOnboarding: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = true }

    private func shot(_ name: String) {
        let dir = ProcessInfo.processInfo.environment["LAYOUT_DIR"] ?? ""
        guard !dir.isEmpty else { return }
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent("fast-\(name).png"))
    }
    private func launch(arguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += arguments
        app.launchEnvironment["LAB_NEW_ATHLETE"] = "1"
        app.launchEnvironment["LAB_THEME"] = "obsidian"
        app.launch()
        return app
    }
    private func el(_ app: XCUIApplication, _ id: String) -> XCUIElement { app.descendants(matching: .any).matching(identifier: id).firstMatch }
    /// Required element: fails when absent. Returns it for further checks.
    @discardableResult private func need(_ app: XCUIApplication, _ id: String, _ what: String, timeout: TimeInterval = 8) -> XCUIElement {
        let e = el(app, id)
        XCTAssertTrue(e.waitForExistence(timeout: timeout), "required: \(what) (\(id))")
        return e
    }
    /// Brings a required control into view above the fixed bottom zone, then taps it.
    private func tap(_ app: XCUIApplication, _ e: XCUIElement, _ what: String) {
        XCTAssertTrue(e.waitForExistence(timeout: 8), "required: \(what)")
        guard e.exists else { return }
        _ = app.reveal(e, top: 110, bottomMargin: 230)
        e.tap()
    }
    private func page(_ app: XCUIApplication, _ n: Int) {
        let p = app.staticTexts["onboardingProgress"].firstMatch
        XCTAssertTrue(p.waitForExistence(timeout: 8), "required: the page counter")
        let ok = NSPredicate(format: "label BEGINSWITH %@", "\(n) of 7")
        let reached = XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: ok, object: p)], timeout: 6) == .completed
        XCTAssertTrue(reached, "required: onboarding page \(n) (shown: \(p.label))")
    }
    private func hideKeyboard(_ app: XCUIApplication) {
        let done = app.buttons["keyboardDone"].firstMatch
        if done.waitForExistence(timeout: 2) { done.tap() }
    }
    /// Welcome → page 1 with a name → page 2 with road cycling and gym training → page 3 with Endurance. Ends on page 3.
    private func reachGoals(_ app: XCUIApplication, name: String) {
        let start = app.buttons["onboardingContinue"].firstMatch
        XCTAssertTrue(start.waitForExistence(timeout: 30), "required: a new athlete starts at Welcome")
        // Owner's Screen 1 decision, 20 Nov 2026: hero, headline, one line, and a control HELD for three seconds.
        // The earlier check tapped "Get started"; a tap must now do nothing, and so must a hold released early.
        XCTAssertTrue(app.staticTexts["onbWelcomeHeadline"].firstMatch.exists, "required: the welcome headline")
        XCTAssertEqual(app.staticTexts["onbWelcomeHeadline"].firstMatch.label, "Your evolution starts here.")
        XCTAssertEqual(app.staticTexts["onbWelcomeLine"].firstMatch.label, "Your goals. Your training. A better you, every day.")
        XCTAssertEqual(start.label, "Hold to begin", "the approved control label")
        XCTAssertTrue(app.staticTexts["onbWelcomeLine"].firstMatch.exists, "required: the supporting line")
        XCTAssertFalse(app.staticTexts["Cyclift"].exists, "the app name is not on the welcome screen")
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] 'Seven short pages' OR label CONTAINS[c] 'declared by you'")).firstMatch.exists, "the old paragraph and legend are gone")
        shot("onb-0-welcome")
        start.tap()
        XCTAssertFalse(app.textFields["onbName"].firstMatch.waitForExistence(timeout: 2), "required: a tap does not start onboarding")
        start.press(forDuration: 1.2)
        XCTAssertFalse(app.textFields["onbName"].firstMatch.waitForExistence(timeout: 2), "required: a hold released early does not start onboarding")
        XCTAssertTrue(start.exists, "still on Welcome after the early release")
        XCTAssertEqual(start.value as? String, "Not started", "required: the ring is empty again after an early release")
        // a finger that drifts a little during the hold must not cancel it: press, move about 10 pt, keep holding
        let finger = start.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3))
        finger.press(forDuration: 1.0, thenDragTo: finger.withOffset(CGVector(dx: 8, dy: 6)), withVelocity: .slow, thenHoldForDuration: 3.0)
        page(app, 1)
        let field = app.textFields["onbName"].firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 8), "required: the name field"); field.tap(); field.typeText(name)
        XCTAssertEqual(field.value as? String, name, "required: the field holds what was typed")
        hideKeyboard(app)
    }
    private func rosterAndGoal(_ app: XCUIApplication) {
        let next = app.buttons["onboardingNext"].firstMatch
        page(app, 2)
        tap(app, app.buttons["rosterAdd-roadCycling"].firstMatch, "add road cycling")
        tap(app, app.buttons["rosterAdd-strength"].firstMatch, "add gym training")
        need(app, "rosterLead", "the lead control for two domains")
        XCTAssertTrue(next.isEnabled, "required: Continue with a planned sport"); next.tap()
        page(app, 3)
        tap(app, el(app, "goal-endurance"), "the Endurance goal")
        XCTAssertTrue(app.buttons["goalStar-endurance"].firstMatch.waitForExistence(timeout: 5), "required: the chosen goal has its star")
        for id in ["onbCyclingLevel", "onbStrengthLevel"] { need(app, id, "level row") }
    }

    private func retype(_ app: XCUIApplication, _ f: XCUIElement, _ text: String) {
        XCTAssertTrue(f.waitForExistence(timeout: 6), "required: field \(f.identifier)")
        f.tap()
        let n = (f.value as? String).map { $0 == f.placeholderValue ? 0 : $0.count } ?? 0
        if n > 0 { f.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: n)) }
        f.typeText(text)
    }
    /// Screen 2, owner decision of 20 Nov 2026: four fields (name, date of birth, weight, height); the date is typed as
    /// day, month and year in a short sheet (no wheel); height in cm or feet/inches; units never change what is stored;
    /// Back and Continue keep the answers; they are still there after the app is closed and opened again.
    func testAboutYouMeasurements() {
        let app = launch()
        let start = app.buttons["onboardingContinue"].firstMatch
        XCTAssertTrue(start.waitForExistence(timeout: 30), "required: a new athlete starts at Welcome")
        start.press(forDuration: 3.6)
        page(app, 1)
        let next = app.buttons["onboardingNext"].firstMatch
        XCTAssertFalse(next.isEnabled, "required: Continue waits for a name")
        let name = app.textFields["onbName"].firstMatch
        XCTAssertTrue(name.waitForExistence(timeout: 8), "required: the name field"); name.tap(); name.typeText("Sam"); hideKeyboard(app)
        XCTAssertTrue(next.isEnabled, "required: a name alone is enough to continue")

        // date of birth: a short sheet with three typed parts, no wheel anywhere
        let dob = need(app, "onbDOB", "date of birth row")
        XCTAssertTrue(dob.label.lowercased().contains("not set"), "required: no date is pre-filled (\(dob.label))")
        dob.tap()
        let d = app.textFields["onbDOBDay"].firstMatch, m = app.textFields["onbDOBMonth"].firstMatch, y = app.textFields["onbDOBYear"].firstMatch
        let done = app.buttons["onbDOBDone"].firstMatch
        XCTAssertTrue(d.waitForExistence(timeout: 6) && m.exists && y.exists, "required: day, month and year fields")
        XCTAssertEqual(app.pickerWheels.count, 0, "required: no date wheel")
        XCTAssertTrue(app.staticTexts["onbTitle"].firstMatch.exists, "required: the sheet does not cover the whole page")
        retype(app, d, "31"); retype(app, m, "4"); retype(app, y, "1990")
        XCTAssertFalse(done.isEnabled, "required: 31 April cannot be saved")
        XCTAssertTrue(el(app, "onbDOBIssue").label.contains("does not exist"), "required: the reason is shown (\(el(app, "onbDOBIssue").label))")
        retype(app, d, "29"); retype(app, m, "2"); retype(app, y, "1999")
        XCTAssertFalse(done.isEnabled, "required: 29 February 1999 cannot be saved")
        retype(app, y, "2090")
        XCTAssertFalse(done.isEnabled, "required: a future birthday cannot be saved")
        app.settleForScreenshot(1); shot("onb-1-dob-sheet-invalid")
        app.buttons["onbDOBCancel"].firstMatch.tap()
        XCTAssertTrue(dob.waitForExistence(timeout: 6) && dob.label.lowercased().contains("not set"), "required: Cancel stores nothing (\(dob.label))")
        dob.tap()
        XCTAssertTrue(d.waitForExistence(timeout: 6), "required: the sheet opens again")
        retype(app, d, "29"); retype(app, m, "2"); retype(app, y, "2000")
        XCTAssertTrue(done.isEnabled, "required: 29 February 2000 is a real date")
        app.settleForScreenshot(1); shot("onb-1-dob-sheet")
        done.tap()
        XCTAssertTrue(dob.waitForExistence(timeout: 6) && dob.label.contains("2000") && dob.label.contains("29"), "required: the chosen date is shown on the page (\(dob.label))")

        // weight and height, Metric then Imperial and back
        let weight = app.textFields["onbWeight"].firstMatch, height = app.textFields["onbHeight"].firstMatch
        XCTAssertTrue(weight.exists && height.exists, "required: weight and height fields")
        weight.tap(); weight.typeText("70"); hideKeyboard(app)
        height.tap(); height.typeText("175"); hideKeyboard(app)
        XCTAssertEqual(el(app, "onbHeightUnit").label, "cm", "required: height is asked in centimetres on Metric")
        app.settleForScreenshot(1); shot("onb-1-about")
        let units = need(app, "onbUnits", "the units choice")
        units.buttons["Imperial"].firstMatch.tap()
        let feet = app.textFields["onbHeightFeet"].firstMatch, inches = app.textFields["onbHeightInches"].firstMatch
        XCTAssertTrue(feet.waitForExistence(timeout: 6) && inches.exists, "required: Imperial asks for feet and inches")
        XCTAssertEqual(feet.value as? String, "5", "required: 175 cm is shown as 5 ft"); XCTAssertEqual(inches.value as? String, "9", "required: … 9 in")
        XCTAssertEqual(weight.value as? String, "154", "required: 70 kg is shown as 154 lb")
        app.settleForScreenshot(1); shot("onb-1-about-imperial")
        units.buttons["Metric"].firstMatch.tap()
        XCTAssertTrue(height.waitForExistence(timeout: 6), "required: Metric shows centimetres again")
        XCTAssertEqual(height.value as? String, "175", "required: changing units never changes the height itself")
        XCTAssertEqual(weight.value as? String, "70", "required: changing units never changes the weight itself")

        // Continue and Back keep everything
        next.tap(); page(app, 2)
        app.buttons["onboardingBack"].firstMatch.tap(); page(app, 1)
        XCTAssertEqual(name.value as? String, "Sam"); XCTAssertEqual(weight.value as? String, "70"); XCTAssertEqual(height.value as? String, "175")
        XCTAssertTrue(dob.label.contains("2000"), "required: the date is still shown after Back (\(dob.label))")

        // closed and opened again (no new-athlete fixture this time): the same answers are read back from storage
        app.terminate()
        let again = XCUIApplication(); again.launchEnvironment["LAB_THEME"] = "obsidian"; again.launch()
        let name2 = again.textFields["onbName"].firstMatch
        XCTAssertTrue(name2.waitForExistence(timeout: 30), "required: onboarding resumes on About you after reopening")
        XCTAssertEqual(name2.value as? String, "Sam", "required: the name was saved")
        XCTAssertEqual(again.textFields["onbWeight"].firstMatch.value as? String, "70", "required: the weight was saved")
        XCTAssertEqual(again.textFields["onbHeight"].firstMatch.value as? String, "175", "required: the height was saved")
        let dob2 = el(again, "onbDOB")
        XCTAssertTrue(dob2.label.contains("2000") && dob2.label.contains("29"), "required: the date of birth was saved (\(dob2.label))")
        again.settleForScreenshot(1); shot("onb-1-about-reopened")
    }

    /// All seven pages: each page's required elements, the units choice, a day edit on page 4, a Blueprint group opened
    /// and returned from, then Approve → Home with the entered name → Plan with the approved sessions.
    func testSevenPagesApproveHomePlan() {
        let app = launch()
        let next = app.buttons["onboardingNext"].firstMatch
        reachGoals(app, name: "Sam")

        // 1 · About you: name, date of birth, weight, units
        XCTAssertEqual(app.staticTexts["onbTitle"].firstMatch.label, "About you", "required: page 1 title")
        need(app, "onbDOB", "date of birth row")
        XCTAssertTrue(app.textFields["onbHeight"].firstMatch.exists, "required: the height field")
        let weight = app.textFields["onbWeight"].firstMatch
        XCTAssertTrue(weight.exists, "required: the weight field")
        let units = need(app, "onbUnits", "the units choice")
        let metric = units.buttons["Metric"].firstMatch, imperial = units.buttons["Imperial"].firstMatch
        XCTAssertTrue(metric.exists && imperial.exists, "required: Metric and Imperial")
        XCTAssertTrue(metric.isSelected, "required: a new athlete starts on Metric")
        weight.tap(); weight.typeText("70"); hideKeyboard(app)
        XCTAssertEqual(el(app, "onbWeightUnit").label, "kg", "required: weight is asked in kilograms on Metric")
        imperial.tap()
        XCTAssertTrue(imperial.isSelected, "required: the units choice changes")
        XCTAssertEqual(el(app, "onbWeightUnit").label, "lb", "required: Imperial shows pounds")
        XCTAssertEqual(weight.value as? String, "154", "required: the same weight is shown in pounds (\(String(describing: weight.value)))")
        app.settleForScreenshot(1); shot("onb-1-about-imperial")
        metric.tap()
        XCTAssertTrue(metric.isSelected, "required: units can be set back")
        XCTAssertEqual(weight.value as? String, "70", "required: changing units never changes the weight itself (\(String(describing: weight.value)))")
        XCTAssertTrue(need(app, "onbCoachLine", "the line above the button").label.contains("Nothing is estimated from blanks"), "required: page 1 wording")
        app.settleForScreenshot(1); shot("onb-1-about")
        XCTAssertTrue(next.isEnabled, "required: Continue after a name"); next.tap()

        // 2 · Athletic Roster, 3 · Goals
        rosterAndGoal(app)
        app.settleForScreenshot(1); shot("onb-3-goals")
        XCTAssertTrue(next.isEnabled, "required: Continue with a goal"); next.tap()

        // 4 · Build your week: strip, tap a day, edit it, totals, equipment
        page(app, 4)
        need(app, "onbWeek", "the week strip")
        need(app, "onbDayEditorHint", "the editor says to tap a day")
        XCTAssertEqual(need(app, "onbWeekStatus", "the proposal line").label, "Coach's proposal · rules-based", "required: the untouched week is the Coach's proposal")
        let total = need(app, "onbWeekTotal", "the weekly total")
        XCTAssertEqual(total.label, "3 h 30 min", "required: the proposed week's time (\(total.label))")
        XCTAssertTrue(need(app, "onbWeekSessions", "the session count").label.contains("5 sessions"), "required: five sessions proposed")
        need(app, "onbWeekBySport", "the totals by sport")
        need(app, "onbFeasibility", "the planner's check line")
        need(app, "onbEquipment", "the equipment choice")
        app.settleForScreenshot(1); shot("onb-4-week-proposal")
        let thursday = app.buttons["onbDay-3"].firstMatch
        XCTAssertTrue(thursday.waitForExistence(timeout: 5) && thursday.label.contains("rest"), "required: Thursday is a rest day in the proposal (\(thursday.label))")
        thursday.tap()
        XCTAssertEqual(need(app, "onbDayEditorDay", "the day editor").label, "Thursday", "required: the editor opens the tapped day")
        XCTAssertTrue(app.buttons["onbDayRest"].firstMatch.isSelected, "required: Rest is marked for a rest day")
        XCTAssertTrue(app.buttons["onbDayLift"].firstMatch.exists, "required: strength is offered for the day")
        tap(app, app.buttons["onbDayRide"].firstMatch, "make Thursday a ride")
        XCTAssertTrue(thursday.label.contains("ride 60 minutes"), "required: Thursday is now a 60 minute ride (\(thursday.label))")
        XCTAssertEqual(el(app, "onbDayEditorCount").label, "1 session", "required: the editor counts the day's sessions")
        XCTAssertEqual(el(app, "onbWeekStatus").label, "1 day changed by you", "required: the change is counted")
        XCTAssertTrue(app.buttons["onbRestoreProposal"].firstMatch.exists, "required: the proposal can be restored")
        XCTAssertTrue(el(app, "onbWeekSessions").label.contains("6 sessions"), "required: the total follows the change")
        XCTAssertEqual(el(app, "onbWeekTotal").label, "4 h 30 min", "required: the weekly time follows the change")
        let plus = app.buttons["onbRidePlus"].firstMatch, minus = app.buttons["onbRideMinus"].firstMatch
        XCTAssertTrue(plus.exists && minus.exists, "required: the ride length can be changed")
        plus.tap(); XCTAssertEqual(el(app, "onbRideMinutes").label, "70 min", "required: longer rides")
        minus.tap(); XCTAssertEqual(el(app, "onbRideMinutes").label, "60 min", "required: and back")
        let home = el(app, "onbEquipment").buttons["Home"].firstMatch
        tap(app, home, "choose Home equipment")
        XCTAssertTrue(home.isSelected, "required: the equipment choice changes")
        XCTAssertTrue(el(app, "onbCoachLine").label.contains("Nothing is scheduled until you approve"), "required: page 4 wording")
        app.settleForScreenshot(1); shot("onb-4-week-thursday-ride")
        XCTAssertTrue(next.isEnabled, "required: the edited week can be continued"); next.tap()

        // 5 · Connect and calibrate: Lab says it connects to nothing; FTP; plan changes
        page(app, 5)
        XCTAssertTrue(app.staticTexts["onbLabDevices"].firstMatch.waitForExistence(timeout: 8), "required: Lab says devices are switched off")
        need(app, "onbConnection-0", "the connections list")
        let ftp = need(app, "onbFTP", "the FTP choice")
        XCTAssertTrue(ftp.buttons["Don't know"].firstMatch.isSelected, "required: FTP starts as not known")
        ftp.buttons["I know it"].firstMatch.tap()
        let watts = app.textFields["onbFTPWatts"].firstMatch
        XCTAssertTrue(watts.waitForExistence(timeout: 5), "required: the FTP field"); watts.tap(); watts.typeText("215"); hideKeyboard(app)
        let changes = need(app, "onbPlanChanges", "the plan-changes choice")
        XCTAssertTrue(changes.buttons["Always ask me"].firstMatch.exists && changes.buttons["Auto-apply reductions"].firstMatch.exists, "required: both plan-change options")
        XCTAssertTrue(el(app, "onbCoachLine").label.contains("presented for your approval"), "required: page 5 wording")
        app.settleForScreenshot(1)
        // Added after simulator run 17: the page rested with its title cut off under the rail once the keyboard closed.
        let title5 = app.staticTexts["onbTitle"].firstMatch, rail = app.buttons["onboardingBack"].firstMatch
        XCTAssertEqual(title5.label, "Connect and calibrate", "required: page 5 title")
        XCTAssertTrue(title5.frame.minY >= rail.frame.maxY - 1, "required: the page 5 title rests wholly below the rail (title top \(title5.frame.minY), rail bottom \(rail.frame.maxY))")
        shot("onb-5-connect")
        next.tap()

        // 6 · Athlete Evolution: baseline state only, no stage
        page(app, 6)
        XCTAssertEqual(need(app, "onbEvolutionState", "the baseline headline").label, "Establishing your baseline", "required: the new-athlete state")
        XCTAssertTrue(need(app, "onbEvolutionTrack", "the empty stage track").label.contains("No stage yet"), "required: the track claims no stage")
        XCTAssertEqual(need(app, "onbEvolutionDeclared", "the declared line").label, "Intermediate rider · beginner lifter", "required: what was declared")
        XCTAssertEqual(need(app, "onbEvolutionMeasured", "the measured line").label, "Nothing recorded yet", "required: no evidence is claimed")
        XCTAssertTrue(need(app, "onbEvolutionStage", "the stage line").label.hasPrefix("No stage yet"), "required: no stage is claimed")
        XCTAssertEqual(next.label, "See my blueprint", "required: the button names the next page")
        app.settleForScreenshot(1); shot("onb-6-evolution")
        next.tap()

        // 7 · Athletic Blueprint: who, sports, goal, proposal, declared, measured; a group opens its page and returns
        page(app, 7)
        XCTAssertEqual(app.staticTexts["onbTitle"].firstMatch.label, "Sam", "required: the blueprint is headed by the athlete's name")
        let identity = app.staticTexts["blueprintIdentity"].firstMatch
        XCTAssertTrue(identity.exists && identity.label == "Road cycling + Gym training · balanced", "required: the roster line (\(identity.label))")
        need(app, "blueprintSports", "the sport line-up")
        for id in ["blueprintSport-roadCycling", "blueprintSport-strength"] { XCTAssertTrue(need(app, id, "a main sport").label.contains("main"), "required: \(id) is a main sport") }
        XCTAssertTrue(need(app, "blueprintMainGoal", "the main goal").label.contains("Endurance"), "required: the main goal is named")
        XCTAssertTrue(need(app, "blueprintWeekTotals", "the week totals").label.contains("6 sessions"), "required: the blueprint shows the edited week")
        need(app, "blueprintWeek", "the proposed week")
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "blueprintDay-3").firstMatch.label.contains("ride"), "required: Thursday's ride is in the blueprint")
        need(app, "blueprintDeclared", "the declared group")
        XCTAssertTrue(need(app, "blueprintCell-ftp", "the declared FTP").label.contains("215 W"), "required: the entered FTP")
        XCTAssertTrue(need(app, "blueprintCell-equipment", "the declared equipment").label.contains("Home"), "required: the chosen equipment")
        need(app, "blueprintCell-planChanges", "the plan-changes answer")
        XCTAssertTrue(need(app, "blueprintMeasuredLine", "the measured line").label.hasPrefix("No recorded training yet"), "required: no evidence is claimed")
        let approve = app.buttons["onbCreatePlan"].firstMatch
        XCTAssertTrue(approve.exists && approve.label == "Approve my blueprint", "required: the approval button (\(approve.label))")
        app.settleForScreenshot(1); shot("onb-7-blueprint")
        _ = app.reveal(el(app, "blueprintMeasured"), top: 110, bottomMargin: 230)
        app.settleForScreenshot(1); shot("onb-7-blueprint-end")
        // Added after simulator run 17: the last declared answer must be reachable clear of the fixed Approve zone.
        let lastCell = app.buttons["blueprintCell-planChanges"].firstMatch
        XCTAssertTrue(lastCell.exists, "required: the plan-changes answer is a button")
        XCTAssertTrue(app.reveal(lastCell, top: 110, bottomMargin: 180) && lastCell.isHittable, "required: the plan-changes answer can be scrolled clear of the Approve zone")

        tap(app, el(app, "blueprintProposal"), "the proposal group")
        page(app, 4)
        let back = app.buttons["onbBackToBlueprint"].firstMatch
        XCTAssertTrue(back.waitForExistence(timeout: 5), "required: Back to blueprint replaces Continue")
        XCTAssertFalse(next.exists, "required: an edit from the blueprint does not offer Continue")
        XCTAssertTrue(el(app, "onbCoachLine").label.contains("Editing from your blueprint"), "required: the page says it was opened from the blueprint")
        app.settleForScreenshot(1); shot("onb-7-edit-week")
        back.tap()
        page(app, 7)
        tap(app, app.buttons["blueprintCell-goals"].firstMatch, "the declared goals")
        page(app, 3)
        XCTAssertTrue(back.waitForExistence(timeout: 5), "required: Back to blueprint on the goals page")
        back.tap()
        page(app, 7)

        // Approve → Home → Plan
        approve.tap()
        XCTAssertTrue(app.waitForHome(name: "Sam", timeout: 20), "required: approval opens Home with the entered name")
        app.settleForScreenshot(1); shot("onb-8-home")
        let planTab = app.buttons["Plan"].firstMatch
        XCTAssertTrue(planTab.waitForExistence(timeout: 8), "required: the Plan tab"); planTab.tap()
        XCTAssertTrue(app.staticTexts["planTitle"].firstMatch.waitForExistence(timeout: 8), "required: Plan is shown")
        app.settleForScreenshot(1); shot("onb-9-plan-this-week")
        // next week is a whole planned week whatever today is
        let nextWeek = app.buttons["planWeekNext"].firstMatch
        XCTAssertTrue(nextWeek.waitForExistence(timeout: 8), "required: Plan's week control")
        if nextWeek.isEnabled { nextWeek.tap(); app.settleForScreenshot(1) }
        let days = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'planDay-'")).allElementsBoundByIndex.map { $0.label }
        XCTAssertFalse(days.isEmpty, "required: Plan shows its days")
        XCTAssertTrue(days.contains { $0.hasPrefix("Thursday") && $0.contains("session") }, "required: Plan has the Thursday ride added on page 4 (\(days))")
        XCTAssertTrue(days.contains { $0.hasPrefix("Monday") && $0.contains("session") }, "required: Plan has the proposed Monday session (\(days))")
        XCTAssertFalse(days.contains { $0.hasPrefix("Sunday") && $0.contains("session") }, "required: Sunday stays without a session, as approved (\(days))")
        shot("onb-9-plan-next-week")
    }

    /// Pages 3, 4 and 7 at a large accessibility text size: the required controls exist and the pages are captured.
    func testLargeTextPages() {
        let app = launch(arguments: ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityL"])
        let next = app.buttons["onboardingNext"].firstMatch
        reachGoals(app, name: "Sam")
        XCTAssertTrue(next.isEnabled, "required: Continue after a name"); next.tap()
        rosterAndGoal(app)
        app.settleForScreenshot(1); shot("onb-large-3-goals")
        _ = app.reveal(el(app, "onbStrengthLevel"), top: 110, bottomMargin: 300)
        app.settleForScreenshot(1); shot("onb-large-3-goals-levels")
        XCTAssertTrue(next.isEnabled, "required: Continue with a goal"); next.tap()
        page(app, 4)
        need(app, "onbWeek", "the week strip")
        need(app, "onbWeekTotal", "the weekly total")
        app.settleForScreenshot(1); shot("onb-large-4-week")
        tap(app, app.buttons["onbDay-1"].firstMatch, "open Tuesday")
        XCTAssertEqual(need(app, "onbDayEditorDay", "the day editor").label, "Tuesday", "required: the editor opens the tapped day")
        XCTAssertTrue(app.buttons["onbRidePlus"].firstMatch.exists, "required: the ride length control")
        app.settleForScreenshot(1); shot("onb-large-4-week-day")
        let kit = need(app, "onbEquipment", "the equipment choice")
        // Added after simulator run 17 ("Bodyweight" was broken mid-word): all four choices are still offered at large text.
        for t in ["Gym", "Home", "Bodyweight", "Not sure"] { XCTAssertTrue(kit.buttons[t].firstMatch.exists, "required: the \(t) equipment choice at large text") }
        _ = app.reveal(el(app, "onbEquipment"), top: 110, bottomMargin: 300)
        app.settleForScreenshot(1); shot("onb-large-4-week-equipment")
        next.tap(); page(app, 5)
        next.tap(); page(app, 6)
        next.tap(); page(app, 7)
        XCTAssertEqual(app.staticTexts["onbTitle"].firstMatch.label, "Sam", "required: the blueprint is headed by the athlete's name")
        for id in ["blueprintSports", "blueprintMainGoal", "blueprintWeek", "blueprintDeclared", "blueprintMeasuredLine"] { need(app, id, "blueprint part") }
        XCTAssertTrue(app.buttons["onbCreatePlan"].firstMatch.exists, "required: the approval button")
        app.settleForScreenshot(1); shot("onb-large-7-blueprint")
        _ = app.reveal(el(app, "blueprintDeclared"), top: 110, bottomMargin: 300)
        app.settleForScreenshot(1); shot("onb-large-7-blueprint-declared")
        _ = app.reveal(el(app, "blueprintMeasuredLine"), top: 110, bottomMargin: 300)
        app.settleForScreenshot(1); shot("onb-large-7-blueprint-end")
    }
}
