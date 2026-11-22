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
    /// Athletic Blueprint (owner decision 22 Nov 2026, 22:51): everything on one screen at standard text size — from
    /// the name to the last section, above the line and the button — and nothing obsolete on it.
    private func blueprintFits(_ app: XCUIApplication, _ what: String, last ids: [String]) {
        let title = need(app, "onbTitle", "the athlete's name"), line = need(app, "onbCoachLine", "the line above the button")
        let rail = app.buttons["onboardingBack"].firstMatch
        XCTAssertTrue(title.isHittable && title.frame.minY >= rail.frame.maxY - 1, "required (\(what)): the name is wholly visible")
        for id in ["blueprintSports", "blueprintMainGoal", "blueprintWeek", "blueprintCoach"] + ids {
            let e = need(app, id, id)
            XCTAssertTrue(e.frame.minY >= title.frame.minY - 1 && e.frame.maxY <= line.frame.minY + 1, "required (\(what)): \(id) is on screen above the button area (\(e.frame), line \(line.frame))")
        }
        for gone in ["blueprintCell-ftp", "blueprintCell-planChanges"] { XCTAssertFalse(el(app, gone).exists, "required (\(what)): \(gone) is no longer on the Blueprint") }
        let obsolete = NSPredicate(format: "label CONTAINS[c] 'FTP' OR label CONTAINS[c] 'Plan changes' OR label CONTAINS[c] 'Always ask me' OR label CONTAINS[c] 'interest'")
        XCTAssertFalse(app.staticTexts.matching(obsolete).firstMatch.exists || app.buttons.matching(obsolete).firstMatch.exists, "required (\(what)): no FTP, Plan changes or 'interest' wording")
        let stage = NSPredicate(format: "label CONTAINS 'Estimated' OR label CONTAINS 'Verified' OR label MATCHES '.*G[0-5] · .*'")
        XCTAssertFalse(app.staticTexts.matching(stage).firstMatch.exists, "required (\(what)): no Evolution stage is assigned")
        let weekHead = NSPredicate(format: "label BEGINSWITH[c] 'Your training week'"), coachOverWeek = NSPredicate(format: "label BEGINSWITH[c] %@", "Coach's proposal · week")
        XCTAssertTrue(app.staticTexts.matching(weekHead).firstMatch.exists, "required (\(what)): the week is headed 'Your training week'")
        XCTAssertFalse(app.staticTexts.matching(coachOverWeek).firstMatch.exists, "required (\(what)): the athlete's week is not labelled the Coach's proposal")
    }
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
        // owner decision 20 Nov 2026, 18:24: date of birth, weight and height are required as well as the name
        XCTAssertFalse(app.buttons["onboardingNext"].firstMatch.isEnabled, "required: a name alone is not enough")
        app.fillAboutYouMeasurements()
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

    /// Screen 2 as approved on 20 Nov 2026 (17:09, revised 18:24): four REQUIRED fields — name, date of birth, weight,
    /// height; Continue stays disabled, and the page says what is missing, until all four are valid; no "optional"
    /// labels and no paragraph; the date is typed as day, month and year in a short sheet (no wheel); a compact
    /// "Units: Metric" menu; units never change what is stored; Back and Continue keep the answers; they are still
    /// there after the app is closed and opened again.
    func testAboutYouMeasurements() {
        let app = launch()
        let start = app.buttons["onboardingContinue"].firstMatch
        XCTAssertTrue(start.waitForExistence(timeout: 30), "required: a new athlete starts at Welcome")
        // fast check 25: a hold begun the instant the control first existed (the app still finishing its launch) did
        // not open page 1; the seven-page check, which touches the screen first, did. Let the launch finish first.
        app.settleForScreenshot(2)
        start.press(forDuration: 3.6)
        if !app.staticTexts["onboardingProgress"].firstMatch.waitForExistence(timeout: 8) { shot("onb-0-hold-did-not-start") }
        page(app, 1)
        let next = app.buttons["onboardingNext"].firstMatch
        need(app, "onbCoachLine", "the line that says what is missing")
        // once the page is complete the line is empty and may not be an element at all
        func lineText() -> String { let e = el(app, "onbCoachLine"); return e.exists ? e.label : "" }
        func says(_ words: [String], _ what: String) { let t = lineText(); for w in words { XCTAssertTrue(t.contains(w), "required: \(what) — the page names '\(w)' (\(t))") } }
        XCTAssertFalse(next.isEnabled, "required: Continue is disabled on an empty page")
        says(["first name", "date of birth", "weight", "height"], "empty page")
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] 'optional'")).firstMatch.exists, "required: no 'optional' label on the page")
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] 'Only your name is needed'")).firstMatch.exists, "required: the old paragraph is gone")
        app.settleForScreenshot(1); shot("onb-1-about-empty")

        let name = app.textFields["onbName"].firstMatch
        XCTAssertTrue(name.waitForExistence(timeout: 8), "required: the name field"); name.tap(); name.typeText("Sam"); hideKeyboard(app)
        XCTAssertFalse(next.isEnabled, "required: a name alone does not enable Continue")
        XCTAssertFalse(lineText().contains("first name"), "required: the name is no longer listed as missing (\(lineText()))")

        // date of birth: a short sheet with three typed parts, no wheel anywhere. Each rejected date is typed into a
        // freshly opened sheet (fast check 26 retyped into filled fields and garbled two of its three cases).
        let dob = need(app, "onbDOB", "date of birth row")
        XCTAssertTrue(dob.label.lowercased().contains("not set"), "required: no date is pre-filled (\(dob.label))")
        let d = app.textFields["onbDOBDay"].firstMatch, m = app.textFields["onbDOBMonth"].firstMatch, y = app.textFields["onbDOBYear"].firstMatch
        let done = app.buttons["onbDOBDone"].firstMatch, cancel = app.buttons["onbDOBCancel"].firstMatch
        func type(_ dd: String, _ mm: String, _ yy: String) {
            dob.tap()
            XCTAssertTrue(d.waitForExistence(timeout: 6) && m.exists && y.exists, "required: day, month and year fields")
            d.tap(); d.typeText(dd); m.tap(); m.typeText(mm); y.tap(); y.typeText(yy)
            XCTAssertEqual(d.value as? String, dd, "the day field holds what was typed"); XCTAssertEqual(m.value as? String, mm, "the month field holds what was typed")
            XCTAssertEqual(y.value as? String, yy, "the year field holds what was typed")
        }
        for (dd, mm, yy, why, words) in [("31", "4", "1990", "31 April", "does not exist"), ("29", "2", "1999", "29 February 1999", "does not exist"), ("1", "1", "2090", "a future birthday", "future")] {
            type(dd, mm, yy)
            XCTAssertEqual(app.pickerWheels.count, 0, "required: no date wheel")
            XCTAssertTrue(app.staticTexts["onbTitle"].firstMatch.exists, "required: the sheet does not cover the whole page")
            XCTAssertFalse(done.isEnabled, "required: \(why) cannot be saved")
            XCTAssertTrue(el(app, "onbDOBIssue").label.contains(words), "required: the reason for \(why) is shown (\(el(app, "onbDOBIssue").label))")
            if dd == "1" { app.settleForScreenshot(1); shot("onb-1-dob-sheet-invalid") }
            cancel.tap()
            XCTAssertTrue(dob.waitForExistence(timeout: 6) && dob.label.lowercased().contains("not set"), "required: Cancel stores nothing (\(dob.label))")
        }
        type("29", "2", "2000")
        XCTAssertTrue(done.isEnabled, "required: 29 February 2000 is a real date")
        app.settleForScreenshot(1); shot("onb-1-dob-sheet")
        done.tap()
        XCTAssertTrue(dob.waitForExistence(timeout: 6) && dob.label.contains("2000") && dob.label.contains("29"), "required: the chosen date is shown on the page (\(dob.label))")
        XCTAssertFalse(next.isEnabled, "required: name and date alone do not enable Continue")
        says(["weight", "height"], "after name and date")

        // weight and height: an out-of-range entry is named and blocks Continue; valid entries enable it
        let weight = app.textFields["onbWeight"].firstMatch, height = app.textFields["onbHeight"].firstMatch
        XCTAssertTrue(weight.exists && height.exists, "required: weight and height fields")
        weight.tap(); weight.typeText("70"); hideKeyboard(app)
        XCTAssertFalse(next.isEnabled, "required: three of four do not enable Continue")
        says(["height"], "after name, date and weight")
        height.tap(); height.typeText("17")
        XCTAssertFalse(next.isEnabled, "required: an impossible height does not enable Continue")
        says(["between 120 and 230 cm"], "an impossible height")
        height.typeText("5"); hideKeyboard(app)                                     // still in the field, cursor at the end: 17 → 175
        XCTAssertEqual(lineText(), "", "required: nothing is listed as missing once the page is complete")
        XCTAssertEqual(height.value as? String, "175", "the height field holds 175 (\(String(describing: height.value)))")
        XCTAssertTrue(next.isEnabled, "required: all four valid values enable Continue")
        XCTAssertEqual(el(app, "onbHeightUnit").label, "cm", "required: height is asked in centimetres on Metric")
        app.settleForScreenshot(1); shot("onb-1-about")

        // the compact units menu
        let units = need(app, "onbUnits", "the compact units selector")
        XCTAssertTrue(units.label.contains("Metric"), "required: a new athlete starts on Metric (\(units.label))")
        XCTAssertLessThan(units.frame.width, 200, "required: the selector is compact, not full width (\(units.frame.width) pt)")
        func choose(_ u: String) {
            units.tap()
            let item = app.buttons[u].firstMatch
            XCTAssertTrue(item.waitForExistence(timeout: 5), "required: the menu offers \(u)")
            if u == "Imperial" { app.settleForScreenshot(1); shot("onb-1-units-menu") }
            item.tap()
            let ok = NSPredicate(format: "label CONTAINS %@", u)
            XCTAssertEqual(XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: ok, object: units)], timeout: 5), .completed, "required: the selector shows \(u) (\(units.label))")
        }
        choose("Imperial")
        let feet = app.textFields["onbHeightFeet"].firstMatch, inches = app.textFields["onbHeightInches"].firstMatch
        XCTAssertTrue(feet.waitForExistence(timeout: 6) && inches.exists, "required: Imperial asks for feet and inches")
        XCTAssertEqual(feet.value as? String, "5", "required: 175 cm is shown as 5 ft"); XCTAssertEqual(inches.value as? String, "9", "required: … 9 in")
        XCTAssertEqual(weight.value as? String, "154", "required: 70 kg is shown as 154 lb")
        XCTAssertTrue(next.isEnabled, "required: still complete in Imperial")
        app.settleForScreenshot(1); shot("onb-1-about-imperial")
        choose("Metric")
        XCTAssertTrue(height.waitForExistence(timeout: 6), "required: Metric shows centimetres again")
        XCTAssertEqual(height.value as? String, "175", "required: changing units never changes the height itself")
        XCTAssertEqual(weight.value as? String, "70", "required: changing units never changes the weight itself")

        // Continue and Back keep everything
        next.tap(); page(app, 2)
        app.buttons["onboardingBack"].firstMatch.tap(); page(app, 1)
        XCTAssertEqual(name.value as? String, "Sam"); XCTAssertEqual(weight.value as? String, "70"); XCTAssertEqual(height.value as? String, "175")
        XCTAssertTrue(dob.label.contains("2000"), "required: the date is still shown after Back (\(dob.label))")
        XCTAssertTrue(next.isEnabled, "required: still complete after Back")

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
        XCTAssertTrue(again.buttons["onboardingNext"].firstMatch.isEnabled, "required: the reopened page is complete")
        again.settleForScreenshot(1); shot("onb-1-about-reopened")
    }

    /// Screen 3 as approved on 20 Nov 2026 (23:04): a multi-sport roster. Any number of activities, any of them main,
    /// identity from what was selected, every row saying truthfully what Cyclift plans and records, a searchable
    /// library with categories, and the selection still there after Back, Continue and reopening the app.
    func testAthleticRosterIsMultiSport() {
        let app = launch()
        let start = app.buttons["onboardingContinue"].firstMatch
        XCTAssertTrue(start.waitForExistence(timeout: 30), "required: a new athlete starts at Welcome")
        app.settleForScreenshot(2)
        start.press(forDuration: 3.6)
        page(app, 1)
        let name = app.textFields["onbName"].firstMatch
        XCTAssertTrue(name.waitForExistence(timeout: 8), "required: the name field"); name.tap(); name.typeText("Sam"); hideKeyboard(app)
        app.fillAboutYouMeasurements()
        let next = app.buttons["onboardingNext"].firstMatch
        XCTAssertTrue(next.isEnabled, "required: About you complete"); next.tap()
        page(app, 2)
        func lineText() -> String { let e = el(app, "onbCoachLine"); return e.exists ? e.label : "" }
        func identity() -> String { let e = app.staticTexts["rosterIdentity"].firstMatch; return e.waitForExistence(timeout: 5) ? e.label : "" }

        // nothing selected: one activity per sport is offered, none preselected, each with its honest capability
        XCTAssertTrue(app.staticTexts["rosterEmptyHeadline"].firstMatch.waitForExistence(timeout: 8), "required: the empty roster headline")
        XCTAssertFalse(next.isEnabled, "required: Continue needs a selection")
        for id in ["roadCycling", "strength", "running", "swimming", "walking", "mobility"] {
            XCTAssertTrue(app.buttons["rosterAdd-\(id)"].firstMatch.exists, "required: \(id) is offered before anything is chosen")
        }
        XCTAssertTrue(app.buttons["rosterAdd-roadCycling"].firstMatch.label.contains("Planned · recorded"), "road cycling says it is planned and recorded")
        let run = app.buttons["rosterAdd-running"].firstMatch
        XCTAssertTrue(run.label.contains("plans coming soon"), "required: running says plans are coming soon — owner wording of 21 Nov 2026 (\(run.label))")
        XCTAssertFalse(run.label.lowercased().contains("planned and recorded"), "required: running is never called planned and recorded")
        app.settleForScreenshot(1); shot("onb-2-roster-empty")

        // a runner: running is the main sport, named truthfully; Cyclift builds no plan from it
        tap(app, run, "add road running")
        let mainRun = need(app, "rosterMain-running", "running as the main sport")
        XCTAssertEqual(identity(), "Runner", "required: identity comes from the selection")
        XCTAssertTrue(lineText().contains("saved to your roster") && lineText().contains("coming soon"), "required: the limitation is stated simply (\(lineText()))")
        XCTAssertFalse(el(app, "rosterLead").exists, "no balance control without two planned sports")
        // 21 Nov 2026: a roster Cyclift cannot plan still continues to Goals (it stops there, with no plan built)
        XCTAssertTrue(next.isEnabled, "required: a runner is not stopped at the roster")
        _ = mainRun
        app.settleForScreenshot(1); shot("onb-2-roster-runner")

        // adding sports never removes one; the plan comes from what Cyclift can plan
        tap(app, app.buttons["rosterAdd-strength"].firstMatch, "add gym training")
        XCTAssertEqual(identity(), "Running/Strength hybrid")
        need(app, "rosterMain-running", "running is still the main sport"); need(app, "rosterMain-strength", "gym training is planned")
        tap(app, app.buttons["rosterAdd-roadCycling"].firstMatch, "add road cycling")
        XCTAssertEqual(identity(), "Multisport athlete")
        need(app, "rosterLead", "the balance control for cycling and strength")
        for id in ["running", "strength", "roadCycling"] { need(app, "rosterMain-\(id)", "\(id) is in the roster") }

        // the library: search, categories, every discipline selectable, honest wording
        tap(app, app.buttons["rosterBrowse"].firstMatch, "Browse all activities")
        let search = app.textFields["librarySearch"].firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 8), "required: the library's search field")
        need(app, "libraryCategory", "the category tabs")
        XCTAssertTrue(app.buttons["library-gravel"].firstMatch.exists && app.buttons["library-indoorCycling"].firstMatch.exists, "required: cycling disciplines are listed")
        app.settleForScreenshot(1); shot("onb-2-library")
        search.tap(); search.typeText("trail")
        let trail = app.buttons["library-trailRunning"].firstMatch
        XCTAssertTrue(trail.waitForExistence(timeout: 5), "required: search finds trail running")
        XCTAssertFalse(app.buttons["library-gravel"].firstMatch.exists, "search narrows the list")
        XCTAssertTrue(trail.label.contains("plans coming soon"), "required: honest wording in the library (\(trail.label))")
        trail.tap()
        XCTAssertEqual(trail.value as? String, "In your roster", "required: the tick shows it is selected")
        search.tap(); search.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 5))
        let cats = el(app, "libraryCategory")
        cats.buttons["Strength"].firstMatch.tap()
        let cali = app.buttons["library-calisthenics"].firstMatch
        XCTAssertTrue(cali.waitForExistence(timeout: 5), "required: the Strength category lists calisthenics")
        XCTAssertFalse(app.buttons["library-trailRunning"].firstMatch.exists, "the category narrows the list")
        cali.tap()
        cats.buttons["Endurance"].firstMatch.tap()
        let gravel = app.buttons["library-gravel"].firstMatch
        XCTAssertTrue(gravel.waitForExistence(timeout: 5), "required: the Endurance category lists gravel")
        XCTAssertTrue(gravel.label.contains("general cycling"), "required: gravel says it is planned as general cycling (\(gravel.label))")
        gravel.tap()
        let done = app.buttons["libraryDone"].firstMatch
        XCTAssertTrue(done.label.contains("6"), "required: six activities selected, no two-sport limit (\(done.label))")
        done.tap()

        // back on the page: all six, main and additional kept apart; any of them can be made main
        for id in ["trailRunning", "calisthenics", "gravel"] {
            let row = app.buttons["rosterMakeMain-\(id)"].firstMatch
            XCTAssertTrue(row.waitForExistence(timeout: 6), "required: \(id) is listed under Also training with Make main")
        }
        tap(app, app.buttons["rosterMakeMain-trailRunning"].firstMatch, "make trail running the main sport")
        need(app, "rosterMain-trailRunning", "trail running is the main sport")
        for id in ["strength", "roadCycling"] { need(app, "rosterMain-\(id)", "\(id) is still planned") }
        for id in ["running", "calisthenics", "gravel"] { XCTAssertTrue(app.buttons["rosterRemove-\(id)"].firstMatch.exists, "required: \(id) was not lost by changing the main sport") }
        XCTAssertEqual(identity(), "Multisport athlete")
        _ = app.reveal(el(app, "rosterMain-trailRunning"), top: 110, bottomMargin: 230)
        app.settleForScreenshot(1); shot("onb-2-roster-multisport")
        tap(app, app.buttons["rosterRemove-calisthenics"].firstMatch, "remove calisthenics")
        XCTAssertFalse(app.buttons["rosterRemove-calisthenics"].firstMatch.waitForExistence(timeout: 2), "required: removal works")

        // Continue and Back keep the roster; so does closing and reopening the app
        XCTAssertTrue(next.isEnabled); next.tap(); page(app, 3)
        app.buttons["onboardingBack"].firstMatch.tap(); page(app, 2)
        need(app, "rosterMain-trailRunning", "the main sport after Back")
        app.terminate()
        let again = XCUIApplication(); again.launchEnvironment["LAB_THEME"] = "obsidian"; again.launch()
        let counter = again.staticTexts["onboardingProgress"].firstMatch
        XCTAssertTrue(counter.waitForExistence(timeout: 30), "required: onboarding resumes after reopening")
        if counter.label.hasPrefix("3 of 7") { again.buttons["onboardingBack"].firstMatch.tap() }
        page(again, 2)
        XCTAssertTrue(el(again, "rosterMain-trailRunning").waitForExistence(timeout: 8), "required: the main sport was saved")
        for id in ["strength", "roadCycling"] { XCTAssertTrue(el(again, "rosterMain-\(id)").exists, "required: \(id) was saved") }
        for id in ["running", "gravel"] { XCTAssertTrue(again.buttons["rosterRemove-\(id)"].firstMatch.exists, "required: \(id) was saved") }
        XCTAssertFalse(again.buttons["rosterRemove-calisthenics"].firstMatch.exists, "required: the removed activity stayed removed")
        XCTAssertEqual(again.staticTexts["rosterIdentity"].firstMatch.label, "Multisport athlete", "required: the identity is derived again from the saved roster")
        again.settleForScreenshot(1); shot("onb-2-roster-reopened")
    }

    /// Welcome and About you, then the roster given, then Continue to Goals.
    private func reachGoalsPage(_ app: XCUIApplication, roster: [String]) {
        let start = app.buttons["onboardingContinue"].firstMatch
        XCTAssertTrue(start.waitForExistence(timeout: 30), "required: a new athlete starts at Welcome")
        app.settleForScreenshot(2)
        start.press(forDuration: 3.6)
        page(app, 1)
        let name = app.textFields["onbName"].firstMatch
        XCTAssertTrue(name.waitForExistence(timeout: 8), "required: the name field"); name.tap(); name.typeText("Sam"); hideKeyboard(app)
        app.fillAboutYouMeasurements()
        let next = app.buttons["onboardingNext"].firstMatch
        XCTAssertTrue(next.isEnabled, "required: About you complete"); next.tap()
        page(app, 2)
        for id in roster { tap(app, app.buttons["rosterAdd-\(id)"].firstMatch, "add \(id)") }
        XCTAssertTrue(next.isEnabled, "required: Continue with a roster"); next.tap()
        page(app, 3)
    }
    private func mainGoalTitle(_ app: XCUIApplication) -> String { let e = app.staticTexts["onbMainGoalTitle"].firstMatch; return e.waitForExistence(timeout: 5) ? e.label : "" }
    private func goalText(_ app: XCUIApplication) -> String { let e = app.staticTexts["onbCoachLine"].firstMatch; return e.exists ? e.label : "" }

    /// Screen 4 as approved on 21 Nov 2026 (00:30), cycling and strength athlete: Build 6 cards made compact so the whole
    /// page fits one iPhone 15 Pro screen; no balance question; several goals with exactly one main goal; the
    /// explanation above Continue follows the main goal; everything is kept after Back, Continue and reopening.
    func testGoalsForACyclingAndStrengthAthlete() {
        let app = launch()
        reachGoalsPage(app, roster: ["roadCycling", "strength"])
        let next = app.buttons["onboardingNext"].firstMatch
        for g in ["cycling", "strength", "general"] { need(app, "goalGroup-\(g)", "the \(g) goals") }
        for g in ["running", "swimming", "walking", "recovery"] { XCTAssertFalse(el(app, "goalGroup-\(g)").exists, "required: no \(g) goals for this roster") }
        XCTAssertFalse(el(app, "rosterLead").exists, "required: the balance is not asked again on this page")
        XCTAssertFalse(app.buttons["Balanced"].exists || app.buttons["Endurance-led"].exists, "required: no balance control on the Goals page")
        XCTAssertFalse(next.isEnabled, "required: Continue needs a goal")

        // everything essential is on screen at once: nothing scrolled away, clipped, or under the footer
        let footer = need(app, "onbGoalExplanation", "the main-goal explanation above Continue")
        let window = app.windows.firstMatch.frame
        let title = app.staticTexts["onbTitle"].firstMatch
        XCTAssertTrue(title.isHittable, "required: the page title is visible")
        let all = ["endurance", "power", "climbing", "sprint", "event", "strength", "muscle", "stamina", "maintain", "fitness"].map { "goal-\($0)" } + ["onbCyclingLevel", "onbStrengthLevel"]
        var frames: [(String, CGRect)] = []
        for id in all {
            let e = need(app, id, "\(id) on the page")
            XCTAssertTrue(e.isHittable, "required: \(id) is visible without scrolling")
            XCTAssertLessThanOrEqual(e.frame.maxY, footer.frame.minY + 1, "required: \(id) is not under the footer (bottom \(e.frame.maxY), footer starts \(footer.frame.minY))")
            XCTAssertGreaterThanOrEqual(e.frame.minY, title.frame.maxY - 1, "required: \(id) is below the title")
            XCTAssertGreaterThanOrEqual(e.frame.height, 43, "required: \(id) keeps a full-size touch target (\(e.frame.height) pt)")
            frames.append((id, e.frame))
        }
        for i in frames.indices { for j in frames.indices where j > i {
            XCTAssertFalse(frames[i].1.insetBy(dx: 1, dy: 1).intersects(frames[j].1.insetBy(dx: 1, dy: 1)), "required: \(frames[i].0) and \(frames[j].0) do not overlap")
        } }
        XCTAssertTrue(next.exists && next.frame.maxY <= window.maxY && next.frame.minY >= footer.frame.maxY - 1, "required: Continue is visible below the explanation")
        app.settleForScreenshot(1); shot("onb-3-goals-hybrid-empty")

        // several goals, one main goal, explained
        el(app, "goal-muscle").tap()
        XCTAssertEqual(mainGoalTitle(app), "MUSCLE · MAIN GOAL", "required: the first goal chosen is the main goal")
        XCTAssertTrue(goalText(app).contains("8–12 reps"), "required: the explanation is the planner's own rule for Muscle (\(goalText(app)))")
        XCTAssertTrue(next.isEnabled, "required: Continue with a goal Cyclift can plan")
        // the main-goal summary card (owner, 21 Nov 13:38): training-mix bar and legend, counted from the proposed week
        let mix = need(app, "onbGoalMix", "the training-mix bar and legend in the main-goal card")
        let muscleMix = mix.value as? String ?? ""
        XCTAssertTrue(muscleMix.contains("Strength") && muscleMix.contains("riding"), "required: the mix of a cycling and strength athlete names riding and strength (\(muscleMix))")
        XCTAssertFalse(muscleMix.contains("Run") || muscleMix.contains("Swim"), "required: no sport the athlete did not choose (\(muscleMix))")
        let card = el(app, "onbGoalExplanation").frame
        XCTAssertTrue(mix.frame.minY >= card.minY && mix.frame.maxY <= card.maxY + 1 && card.maxY <= next.frame.minY + 1, "required: the bar is inside the card and the card is above Continue (bar \(mix.frame), card \(card), Continue \(next.frame))")
        for id in ["goal-fitness", "onbCyclingLevel", "onbStrengthLevel"] { XCTAssertLessThanOrEqual(el(app, id).frame.maxY, card.minY + 1, "required: \(id) is not under the summary card") }
        print("MIX muscle: \(muscleMix)")
        el(app, "goal-endurance").tap(); el(app, "goal-fitness").tap()
        XCTAssertEqual(mainGoalTitle(app), "MUSCLE · MAIN GOAL", "required: adding goals does not move the main goal")
        for g in ["muscle", "endurance", "fitness"] { XCTAssertTrue(app.buttons["goalStar-\(g)"].firstMatch.exists, "required: \(g) is selected") }
        XCTAssertEqual(app.buttons["goalStar-muscle"].firstMatch.value as? String, "Main goal"); XCTAssertEqual(app.buttons["goalStar-endurance"].firstMatch.value as? String, "", "required: exactly one main goal")
        app.settleForScreenshot(1); shot("onb-3-goals-hybrid")
        app.buttons["goalStar-endurance"].firstMatch.tap()
        XCTAssertEqual(mainGoalTitle(app), "ENDURANCE · MAIN GOAL", "required: the star changes the main goal")
        XCTAssertTrue(goalText(app).contains("Zone 2"), "required: the explanation follows the main goal (\(goalText(app)))")
        for g in ["muscle", "endurance", "fitness"] { XCTAssertTrue(app.buttons["goalStar-\(g)"].firstMatch.exists, "required: changing the main goal deletes no other goal (\(g))") }
        XCTAssertEqual(app.buttons["goalStar-muscle"].firstMatch.value as? String, ""); XCTAssertEqual(app.buttons["goalStar-endurance"].firstMatch.value as? String, "Main goal")
        let enduranceMix = need(app, "onbGoalMix", "the training-mix bar with Endurance as the main goal").value as? String ?? ""
        XCTAssertTrue(enduranceMix.contains("riding") && enduranceMix.contains("Strength"), "required: the mix is still this athlete's proposed week (\(enduranceMix))")
        print("MIX endurance: \(enduranceMix)")
        for id in ["goal-fitness", "onbCyclingLevel", "onbStrengthLevel"] { XCTAssertLessThanOrEqual(el(app, id).frame.maxY, el(app, "onbGoalExplanation").frame.minY + 1, "required: \(id) is not under the summary card (Endurance)") }
        app.settleForScreenshot(1); shot("onb-3-goals-main-changed")

        // a level the planner needs, as one compact menu
        let level = el(app, "onbStrengthLevel"); level.tap()
        let inter = app.buttons["Intermediate"].firstMatch
        XCTAssertTrue(inter.waitForExistence(timeout: 5), "required: the level menu offers Intermediate"); inter.tap()
        XCTAssertEqual(XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS 'Intermediate'"), object: level)], timeout: 5), .completed, "required: the strength level can be changed (\(level.label))")

        // Continue and Back keep it; so does closing and reopening
        next.tap(); page(app, 4)
        app.buttons["onboardingBack"].firstMatch.tap(); page(app, 3)
        XCTAssertEqual(mainGoalTitle(app), "ENDURANCE · MAIN GOAL", "required: the main goal after Back")
        for g in ["muscle", "endurance", "fitness"] { XCTAssertTrue(app.buttons["goalStar-\(g)"].firstMatch.exists, "required: \(g) after Back") }
        app.terminate()
        let again = XCUIApplication(); again.launchEnvironment["LAB_THEME"] = "obsidian"; again.launch()
        let counter = again.staticTexts["onboardingProgress"].firstMatch
        XCTAssertTrue(counter.waitForExistence(timeout: 30), "required: onboarding resumes after reopening")
        if counter.label.hasPrefix("4 of 7") { again.buttons["onboardingBack"].firstMatch.tap() }
        page(again, 3)
        XCTAssertEqual(mainGoalTitle(again), "ENDURANCE · MAIN GOAL", "required: the main goal was saved")
        for g in ["muscle", "endurance", "fitness"] { XCTAssertTrue(again.buttons["goalStar-\(g)"].firstMatch.waitForExistence(timeout: 5), "required: \(g) was saved") }
        XCTAssertTrue(el(again, "onbStrengthLevel").label.contains("Intermediate"), "required: the level was saved")
    }

    /// A runner completes onboarding (owner decisions of 21 Nov 2026, 00:46 and 00:49): running goals, said to be saved
    /// with plans coming soon; no cycling or strength goals or levels; nothing prescribed; Goals leads straight to a
    /// Blueprint that says what is saved; "Create my profile" opens Cyclift with NO training plan, and none appears at
    /// the next launch. The earlier version of this check required Continue to stay unavailable for a runner.
    func testARunnerCompletesOnboardingWithoutAPlan() {
        let app = launch()
        reachGoalsPage(app, roster: ["running"])
        let next = app.buttons["onboardingNext"].firstMatch
        let group = need(app, "goalGroup-running", "the running goals")
        XCTAssertTrue(group.label.lowercased().contains("coming soon"), "required: running goals are said to be saved, plans coming soon (\(group.label))")
        for g in ["cycling", "strength"] { XCTAssertFalse(el(app, "goalGroup-\(g)").exists, "required: no \(g) goals for a runner") }
        for id in ["goal-endurance", "goal-muscle", "onbCyclingLevel", "onbStrengthLevel"] { XCTAssertFalse(el(app, id).exists, "required: \(id) is not asked of a runner") }
        for id in ["goal-runDistance", "goal-runPace", "goal-runEndurance", "goal-runRace"] { need(app, id, "\(id)") }
        XCTAssertFalse(next.isEnabled, "required: Continue needs a goal")
        el(app, "goal-runDistance").tap(); el(app, "goal-runPace").tap()
        app.buttons["goalStar-runPace"].firstMatch.tap()
        XCTAssertEqual(mainGoalTitle(app), "PACE · MAIN GOAL", "required: the runner's main goal is named")
        let text = goalText(app)
        XCTAssertFalse(el(app, "onbGoalMix").exists, "required: no training-mix bar for an athlete without a plan — nothing is proposed, so nothing is charted")
        XCTAssertTrue(text.contains("Your running goals are saved") && text.contains("coming soon"), "required: saved, plans coming soon (\(text))")
        for word in ["Zone", "reps", "interval", " km", "FTP", "nsupported", "not supported", "not implemented", "navailable"] {
            XCTAssertFalse(text.contains(word), "required: no prescription and no technical wording ('\(word)') in: \(text)")
        }
        XCTAssertTrue(next.isEnabled, "required: a runner is not blocked on the Goals page")
        app.settleForScreenshot(1); shot("onb-3-goals-runner")

        // Owner decision 21 Nov 2026 (21:18): every athlete builds their week, a runner included — from THEIR sports.
        // The earlier version of this check went from Goals straight to the Blueprint.
        next.tap(); page(app, 4)
        for i in 0..<7 { XCTAssertTrue(need(app, "onbDay-\(i)", "day \(i)").label.hasSuffix(", rest"), "required: every day starts as rest for a new athlete") }
        XCTAssertFalse(next.isEnabled, "required: Continue needs a training day")
        tap(app, app.buttons["onbDay-0"].firstMatch, "open Monday")
        need(app, "onbAct-running", "running in the day editor")
        for other in ["roadCycling", "strength"] { XCTAssertFalse(app.buttons["onbAct-\(other)"].firstMatch.exists, "required: \(other) is not offered to a runner") }
        tap(app, app.buttons["onbDayRest"].firstMatch, "close without choosing"); tap(app, app.buttons["onbDay-0"].firstMatch, "close Monday")
        app.chooseWeekDay(0, ["running"])
        tap(app, app.buttons["onbDay-3"].firstMatch, "open Thursday"); tap(app, app.buttons["onbAct-running"].firstMatch, "running on Thursday")
        for _ in 0..<3 { app.buttons["onbLen-0Plus"].firstMatch.tap() }
        XCTAssertEqual(el(app, "onbLen-0Minutes").label, "45 min", "required: Thursday's own length")
        tap(app, app.buttons["onbDayConfirm"].firstMatch, "confirm Thursday")
        app.chooseWeekDay(5, ["running"])
        XCTAssertTrue(el(app, "onbDay-0").label.contains("Road running 30 minutes") && el(app, "onbDay-3").label.contains("Road running 45 minutes"), "required: each day keeps its own length (\(el(app, "onbDay-0").label) / \(el(app, "onbDay-3").label))")
        XCTAssertEqual(el(app, "onbWeekTotal").label, "1 h 45 min"); XCTAssertEqual(el(app, "onbWeekCounts").label, "3 sessions · 3 training days · 4 rest days")
        XCTAssertEqual(el(app, "onbWeekBySport").label, "Running 1 h 45 min")
        XCTAssertFalse(el(app, "onbEquipment").exists, "required: no gym equipment question for a runner")
        let weekLine = el(app, "onbCoachLine").label
        XCTAssertTrue(weekLine.contains("saved") && weekLine.contains("coming soon"), "required: the schedule is said to be saved, with plans coming (\(weekLine))")
        XCTAssertTrue(next.isEnabled, "required: a runner continues with a valid training day")
        app.settleForScreenshot(1); shot("onb-4-week-runner")
        next.tap(); page(app, 7)
        let create = app.buttons["onbCreateProfile"].firstMatch
        XCTAssertTrue(create.waitForExistence(timeout: 8), "required: Create my profile")
        XCTAssertFalse(app.buttons["onbCreatePlan"].firstMatch.exists, "required: there is no plan to approve")
        XCTAssertEqual(app.staticTexts["onbTitle"].firstMatch.label, "Sam"); XCTAssertEqual(app.staticTexts["blueprintIdentity"].firstMatch.label, "Runner")
        // Owner's combined decision, 22 Nov 2026 (22:51): the Blueprint is one layout for every athlete. The runner's
        // sport, goals and CHOSEN WEEK are shown (the earlier check required no week on this Blueprint, and looked for
        // list rows that no longer exist); what must still be absent is any planned session.
        XCTAssertTrue(need(app, "blueprintSport-running", "running in the line-up").label.contains("main"), "required: running is the main sport")
        XCTAssertTrue(need(app, "blueprintMainGoal", "the main goal").label.contains("Pace"), "required: the runner's main goal (\(el(app, "blueprintMainGoal").label))")
        XCTAssertTrue(need(app, "blueprintGoalLine", "the other goals").label.contains("Distance"), "required: the other goal is named")
        XCTAssertTrue(need(app, "blueprintCell-goals", "the declared goals").label.contains("Pace ★"), "required: declared goals")
        XCTAssertTrue(need(app, "blueprintDay-0", "Monday").label.contains("Road running 30 minutes") && need(app, "blueprintDay-3", "Thursday").label.contains("Road running 45 minutes"),
                      "required: the Blueprint shows the week exactly as chosen (\(el(app, "blueprintDay-0").label); \(el(app, "blueprintDay-3").label))")
        XCTAssertTrue(el(app, "blueprintDay-1").label.hasSuffix(", rest"), "required: an unchosen day is rest")
        XCTAssertEqual(need(app, "blueprintWeekTotals", "the week totals").label, "1 h 45 min · 3 sessions", "required: the totals of the chosen week")
        XCTAssertTrue(need(app, "blueprintNoPlan", "the no-plan statement").label.contains("No training plan is created"), "required: the Blueprint says no plan is created (\(el(app, "blueprintNoPlan").label))")
        XCTAssertFalse(el(app, "blueprintCoachLine-0").exists, "required: no Coach guidance without a plan")
        XCTAssertFalse(el(app, "blueprintCell-equipment").exists, "required: no equipment line for a runner")
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] 'First session' OR label CONTAINS[c] 'rides ·' OR label CONTAINS[c] 'Zone' OR label CONTAINS[c] 'lift'")).firstMatch.exists, "required: no planned session and no cycling or strength guidance on this Blueprint")
        blueprintFits(app, "runner", last: ["blueprintDeclared"])
        // 21 Nov 2026 (21:18): page 4 is now visited by every athlete; pages 5 and 6 still describe a plan
        for i in 5...6 { XCTAssertFalse(app.buttons["railSlot-\(i)"].firstMatch.isEnabled, "required: page \(i) is not offered to an athlete without a plan") }
        app.settleForScreenshot(1); shot("onb-7-blueprint-profile-only")
        app.buttons["onboardingBack"].firstMatch.tap(); page(app, 4)
        XCTAssertTrue(el(app, "onbDay-3").label.contains("Road running 45 minutes"), "required: Back returns to the week as it was left")
        app.buttons["onboardingBack"].firstMatch.tap(); page(app, 3)
        XCTAssertEqual(mainGoalTitle(app), "PACE · MAIN GOAL", "required: Back returns to Goals with the selection kept")
        next.tap(); page(app, 4); next.tap(); page(app, 7)

        // into Cyclift without a plan — through the saved confirmation (owner decision 22 Nov 2026, 22:51)
        create.tap()
        let openHome = app.buttons["onbOpenHome"].firstMatch
        XCTAssertTrue(openHome.waitForExistence(timeout: 20), "required: the confirmation after Create my profile")
        let savedLine = el(app, "onbCoachLine").label
        XCTAssertTrue(savedLine.contains("Saved.") && savedLine.contains("profile and training week are saved") && savedLine.contains("No training plan was created"), "required: the confirmation says what was saved and claims no plan (\(savedLine))")
        XCTAssertFalse(el(app, "blueprintApprovedTag").exists, "required: no 'plan approved' mark without a plan")
        XCTAssertTrue(el(app, "blueprintDay-3").label.contains("Road running 45 minutes"), "required: the saved week is still shown")
        app.settleForScreenshot(1); shot("onb-7-blueprint-profile-saved")
        openHome.tap()
        let greeting = el(app, "homeGreeting")
        XCTAssertTrue(greeting.waitForExistence(timeout: 20), "required: Home opens after Create my profile")
        XCTAssertTrue(greeting.label.contains("Sam"), "required: Home greets the athlete (\(greeting.label))")
        // Added after focused check 32, where a cycling week generated before set-up stayed on Home and Plan:
        // nothing the runner did not choose may be shown as theirs.
        let notTheirs = NSPredicate(format: "label CONTAINS[c] 'first ride' OR label CONTAINS[c] 'of 1 sessions' OR label CONTAINS[c] 'training days a week' OR label CONTAINS[c] 'recurring plan' OR label CONTAINS[c] '· Cycling'")
        XCTAssertFalse(app.staticTexts.matching(notTheirs).firstMatch.exists, "required: Home shows no cycling plan, session or type the runner did not choose")
        app.settleForScreenshot(2); shot("profile-only-1-home")
        let dock = el(app, "cradleDock")
        dock.buttons["Plan"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["planTitle"].firstMatch.waitForExistence(timeout: 10), "required: the Plan screen opens")
        XCTAssertFalse(app.staticTexts.matching(notTheirs).firstMatch.exists, "required: Plan shows no cycling goal, week or rest day the runner did not choose")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] 'plans coming soon'")).firstMatch.exists, "required: Plan says the goals are saved and plans are coming")
        app.settleForScreenshot(2); shot("profile-only-2-plan")
        app.buttons["centreButton"].firstMatch.tap()
        let panel = need(app, "trainPanel", "the Train panel")
        let said = app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] 'no plan'")).firstMatch
        XCTAssertTrue(said.waitForExistence(timeout: 6), "required: Train says there is no plan (nothing is offered as today's session)")
        _ = panel
        XCTAssertFalse(app.buttons["trainPanelPrimary"].firstMatch.exists, "required: a cycling/strength plan set-up is not offered to an athlete whose sports cannot be planned yet")
        app.settleForScreenshot(1); shot("profile-only-3-train")

        // the next launch creates nothing either
        app.terminate()
        let again = XCUIApplication(); again.launchEnvironment["LAB_THEME"] = "obsidian"; again.launch()
        XCTAssertTrue(el(again, "homeGreeting").waitForExistence(timeout: 30), "required: the athlete stays onboarded after reopening")
        XCTAssertFalse(again.buttons["onboardingContinue"].firstMatch.exists, "required: onboarding does not start again")
        again.buttons["centreButton"].firstMatch.tap()
        XCTAssertTrue(again.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] 'no plan'")).firstMatch.waitForExistence(timeout: 8), "required: still no plan after reopening — none was generated at launch")
        again.settleForScreenshot(1); shot("profile-only-4-train-reopened")
    }

    /// Supported and other sports together: a plan is built only from a goal the athlete chose for a planned sport.
    /// With only a running goal the outcome is profile-only; choosing a cycling goal afterwards leads to Build your week.
    func testAMixedRosterPlansOnlyTheGoalsChosen() {
        let app = launch()
        reachGoalsPage(app, roster: ["running", "roadCycling"])
        let next = app.buttons["onboardingNext"].firstMatch
        need(app, "goalGroup-running", "running goals"); need(app, "goalGroup-cycling", "cycling goals")
        need(app, "onbCyclingLevel", "the cycling level"); XCTAssertFalse(el(app, "onbStrengthLevel").exists, "no strength level without a planned strength sport")
        el(app, "goal-runPace").tap()
        XCTAssertTrue(goalText(app).contains("Choose a goal for a sport Cyclift plans today"), "required: how to get a plan is said (\(goalText(app)))")
        for g in ["endurance", "power", "climbing", "sprint", "event", "fitness"] { XCTAssertFalse(app.buttons["goalStar-\(g)"].firstMatch.exists, "required: \(g) is never selected for the athlete") }
        // 21 Nov 2026 (21:18): the week is chosen by the athlete before any Blueprint — here a running day and a ride
        next.tap(); page(app, 4)
        app.chooseWeekDay(0, ["running"]); app.chooseWeekDay(1, ["roadCycling"])
        XCTAssertTrue(el(app, "onbCoachLine").label.contains("saved"), "required: without a cycling goal the week is a saved schedule (\(el(app, "onbCoachLine").label))")
        next.tap(); page(app, 7)
        XCTAssertTrue(app.buttons["onbCreateProfile"].firstMatch.waitForExistence(timeout: 8), "required: without a cycling goal no cycling plan is built")
        // Owner's combined decision, 22 Nov 2026 (22:51): one Blueprint layout. The per-sport status rows and the
        // "Change" buttons this check used are gone; the chosen week is shown instead, and goals are changed from
        // the declared Goals cell.
        need(app, "blueprintSport-roadCycling", "road cycling in the line-up"); need(app, "blueprintSport-running", "running in the line-up")
        XCTAssertTrue(need(app, "blueprintDay-0", "Monday").label.contains("Road running") && need(app, "blueprintDay-1", "Tuesday").label.contains("Road cycling"), "required: both chosen days are shown as chosen")
        XCTAssertTrue(need(app, "blueprintNoPlan", "the no-plan statement").label.contains("you chose no goal"), "required: why there is no plan (\(el(app, "blueprintNoPlan").label))")
        app.settleForScreenshot(1); shot("onb-7-blueprint-mixed-profile-only")
        tap(app, app.buttons["blueprintCell-goals"].firstMatch, "the declared goals")
        page(app, 3)
        el(app, "goal-endurance").tap()
        XCTAssertEqual(mainGoalTitle(app), "PACE · MAIN GOAL", "required: the chosen cycling goal does not take the main goal away")
        XCTAssertTrue(goalText(app).contains("Your plan today follows Endurance"), "required: the page says what the plan follows (\(goalText(app)))")
        app.settleForScreenshot(1); shot("onb-3-goals-runner-plus-cycling")
        let back = app.buttons["onbBackToBlueprint"].firstMatch
        XCTAssertTrue(back.waitForExistence(timeout: 6) && back.isEnabled, "required: the way back from the edit"); back.tap()
        // The athlete has already built their week (21 Nov 2026, 21:18), so the Blueprint follows — now with a plan to
        // approve, covering only the ride they chose. The earlier check expected Build your week here, because that
        // page used to be skipped for an athlete without a plan.
        page(app, 7)
        XCTAssertTrue(app.buttons["onbCreatePlan"].firstMatch.waitForExistence(timeout: 8), "required: a plan can now be approved")
        XCTAssertTrue(need(app, "blueprintDay-1", "Tuesday on the Blueprint").label.contains("Road cycling"), "required: the chosen ride is in the week")
        // Owner's decision 22 Nov 2026 (22:51): "Your training week" is the athlete's schedule, so the running day is
        // SHOWN AS CHOSEN (this check used to require it to read "rest", when the strip showed only planned sessions).
        // That it is not planned as cycling or strength is now stated by the Coach section instead.
        XCTAssertTrue(need(app, "blueprintDay-0", "Monday on the Blueprint").label.contains("Road running 30 minutes"), "required: the running day stays in the week as chosen (\(el(app, "blueprintDay-0").label))")
        XCTAssertEqual(need(app, "blueprintWeekTotals", "the week totals").label, "1 h 30 min · 2 sessions", "required: totals of the whole chosen week")
        let status = need(app, "blueprintCoachStatus", "the status of the unplanned session").label
        XCTAssertTrue(status.hasPrefix("Running: kept in your week as you chose it") && status.contains("coming soon"), "required: a truthful status for running (\(status))")
        let guidance = need(app, "blueprintCoachLine-0", "the Coach's guidance").label
        XCTAssertTrue(guidance.contains("Endurance") || guidance.contains("ride"), "required: guidance for the ride the Coach plans (\(guidance))")
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] 'lift'")).firstMatch.exists, "required: no strength guidance for an athlete without strength")
        XCTAssertTrue(need(app, "blueprintMainGoal", "the main goal").label.contains("Pace"), "required: the athlete's own main goal stays Pace")
        XCTAssertTrue(need(app, "blueprintGoalLine", "what the plan follows").label.contains("Coach plan follows Endurance"), "required: the goal the plan follows is said")
        blueprintFits(app, "running + cycling", last: ["blueprintDeclared"])
        app.settleForScreenshot(1); shot("onb-7-blueprint-running-cycling-plan")
    }

    /// Equipment on Build your week (owner decision 22 Nov 2026, 13:34): Gym | Home | Bodyweight | Custom — no "Not
    /// sure"; a compact Edit control opens the chosen environment's own checklist in a bottom sheet; ticking and
    /// unticking work; Bodyweight can include dumbbells and bands; Custom holds equipment across categories; switching
    /// environments erases nothing; everything is kept after reopening; the page itself does not change size.
    func testEquipmentEnvironments() {
        let app = launch()
        reachGoalsPage(app, roster: ["roadCycling", "strength"])
        let next = app.buttons["onboardingNext"].firstMatch
        el(app, "goal-endurance").tap()
        next.tap(); page(app, 4)
        XCTAssertFalse(el(app, "onbEquipment").exists, "required: no equipment question before a strength session is chosen")
        app.chooseWeekDay(0, ["strength"])
        let kit = need(app, "onbEquipment", "the equipment choice")
        for t in ["Gym", "Home", "Bodyweight", "Custom"] { XCTAssertTrue(kit.buttons[t].firstMatch.isHittable, "required: the \(t) environment") }
        XCTAssertFalse(kit.buttons["Not sure"].firstMatch.exists, "required: 'Not sure' is not an environment")
        let edit = need(app, "onbEquipmentEdit", "the compact Edit equipment control")
        XCTAssertFalse(edit.isEnabled, "required: nothing to edit before an environment is chosen")
        let line = need(app, "onbCoachLine", "the line above Continue")
        // Owner decision 22 Nov 2026 (14:36): a week with a strength session needs an environment before Continue
        XCTAssertFalse(next.isEnabled, "required: a strength athlete cannot continue without choosing an equipment environment")
        XCTAssertTrue(line.label.contains("Choose Gym, Home, Bodyweight or Custom"), "required: the page says what is needed (\(line.label))")

        func ticked(_ id: String) -> Bool { (need(app, "equip-\(id)", "the \(id) tick box").value as? String) == "ticked" }
        func tick(_ id: String) { let r = need(app, "equip-\(id)", "the \(id) tick box"); if !r.isHittable { app.swipeUp() }; r.tap() }
        func offered() -> Int { Int(need(app, "equipEffect", "the effect on eligible exercises").label.split(separator: " ").first ?? "") ?? -1 }
        func openSheet(_ title: String) {
            tap(app, edit, "Edit equipment")
            XCTAssertEqual(need(app, "equipTitle", "the equipment sheet").label, "\(title) equipment")
        }
        func done() { tap(app, app.buttons["equipDone"].firstMatch, "Done"); XCTAssertTrue(edit.waitForExistence(timeout: 5)) }

        // Bodyweight: nothing needed by default; dumbbells and bands can be added
        kit.buttons["Bodyweight"].firstMatch.tap()
        XCTAssertTrue(next.isEnabled, "required: Continue once an environment is chosen")
        XCTAssertEqual(edit.label, "No equipment. Edit equipment", "required: bodyweight starts with no equipment")
        XCTAssertLessThanOrEqual(kit.frame.maxY, line.frame.minY + 1, "required: the page is still one screen")
        app.settleForScreenshot(1); shot("onb-4-equipment-main")
        openSheet("Bodyweight")
        XCTAssertEqual(need(app, "equipIntro", "the plain-words line").label, "We’ll choose exercises based on the equipment you have.")
        XCTAssertTrue(need(app, "equipHint", "the bodyweight hint").label.contains("No equipment is needed"))
        need(app, "equipSavedOnlyNote", "the one note about items that are saved only")
        XCTAssertEqual(el(app, "equip-dip bars").label, "Dip bars, saved only"); XCTAssertEqual(el(app, "equip-dumbbell").label, "Dumbbells")
        for id in ["pull-up bar", "dip bars", "band", "gymnastic rings", "weighted vest", "exercise mat", "dumbbell"] { XCTAssertFalse(ticked(id), "required: \(id) is offered and not ticked by default") }
        XCTAssertFalse(app.buttons["equip-barbell"].firstMatch.exists, "required: the Bodyweight list is its own list")
        let bare = offered()
        tick("dumbbell"); tick("band")
        XCTAssertTrue(ticked("dumbbell") && ticked("band"), "required: ticking works")
        let withKit = offered()
        XCTAssertGreaterThan(withKit, bare, "required: more exercises can be offered with dumbbells and bands (\(bare) → \(withKit))")
        tick("weighted vest")
        XCTAssertEqual(offered(), withKit, "required: an item the planner does not use changes no exercise count")
        tick("weighted vest"); XCTAssertFalse(ticked("weighted vest"), "required: unticking works")
        app.settleForScreenshot(1); shot("onb-4-equipment-bodyweight-sheet")
        done()
        XCTAssertEqual(edit.label, "2 items. Edit equipment")
        app.settleForScreenshot(1); shot("onb-4-equipment-main-2-items")

        // Gym: its own list and preset; an edit there does not touch Bodyweight
        kit.buttons["Gym"].firstMatch.tap()
        XCTAssertEqual(edit.label, "8 items. Edit equipment")
        openSheet("Gym")
        XCTAssertTrue(need(app, "equipHint", "the gym hint").label.contains("suggested starting list"), "required: the gym preset is presented as a suggestion")
        for id in ["barbell", "dumbbell", "bench", "cable", "squat rack", "machine", "kettlebell", "band"] { XCTAssertTrue(ticked(id), "required: the Gym preset provides \(id), visibly") }
        XCTAssertFalse(app.buttons["equip-trap bar"].firstMatch.exists, "required: a gym is not assumed to have everything")
        let gymAll = offered(); tick("barbell")
        XCTAssertLessThan(offered(), gymAll, "required: without a barbell fewer exercises can be offered")
        done()
        XCTAssertEqual(edit.label, "7 items. Edit equipment")
        kit.buttons["Bodyweight"].firstMatch.tap()
        XCTAssertEqual(edit.label, "2 items. Edit equipment", "required: switching environments erased nothing")

        // Custom: the whole catalogue with search, across categories
        kit.buttons["Custom"].firstMatch.tap()
        XCTAssertEqual(edit.label, "No equipment. Edit equipment")
        openSheet("Custom")
        let search = need(app, "equipSearch", "the catalogue search")
        search.tap(); search.typeText("rack")
        XCTAssertTrue(need(app, "equip-squat rack", "squat rack found by search").exists)
        XCTAssertFalse(app.buttons["equip-dumbbell"].firstMatch.exists, "required: the search narrows the list")
        tick("squat rack")
        // a second search in a freshly opened sheet (retyping into a filled field has garbled text in these checks before)
        done(); XCTAssertEqual(edit.label, "1 item. Edit equipment")
        openSheet("Custom")
        let search2 = need(app, "equipSearch", "the catalogue search"); search2.tap(); search2.typeText("buoy")
        tick("pull buoy")
        XCTAssertTrue(ticked("pull buoy"), "required: swimming equipment can be ticked beside strength equipment")
        done()
        XCTAssertEqual(edit.label, "2 items. Edit equipment")
        kit.buttons["Gym"].firstMatch.tap(); XCTAssertEqual(edit.label, "7 items. Edit equipment", "required: the Gym edit is still there")
        kit.buttons["Bodyweight"].firstMatch.tap()

        // Back and Continue keep it; so does closing and reopening
        next.tap(); page(app, 5)
        app.buttons["onboardingBack"].firstMatch.tap(); page(app, 4)
        XCTAssertTrue(kit.buttons["Bodyweight"].firstMatch.isSelected); XCTAssertEqual(edit.label, "2 items. Edit equipment", "required: kept after Continue and Back")
        app.terminate()
        let again = XCUIApplication(); again.launchEnvironment["LAB_THEME"] = "obsidian"; again.launch()
        let counter = again.staticTexts["onboardingProgress"].firstMatch
        XCTAssertTrue(counter.waitForExistence(timeout: 30), "required: onboarding resumes after reopening")
        if counter.label.hasPrefix("5 of 7") { again.buttons["onboardingBack"].firstMatch.tap() }
        page(again, 4)
        let kit2 = need(again, "onbEquipment", "the equipment choice after reopening"), edit2 = need(again, "onbEquipmentEdit", "Edit after reopening")
        XCTAssertTrue(kit2.buttons["Bodyweight"].firstMatch.isSelected, "required: the environment was saved")
        XCTAssertEqual(edit2.label, "2 items. Edit equipment", "required: the Bodyweight selection was saved")
        kit2.buttons["Custom"].firstMatch.tap(); XCTAssertEqual(edit2.label, "2 items. Edit equipment", "required: the Custom selection was saved")
        kit2.buttons["Gym"].firstMatch.tap(); XCTAssertEqual(edit2.label, "7 items. Edit equipment", "required: the Gym selection was saved")
        tap(again, edit2, "Edit equipment after reopening")
        XCTAssertEqual((need(again, "equip-barbell", "barbell after reopening").value as? String), "not ticked", "required: the unticked barbell stayed unticked")
    }

    /// Connect your devices (owner's approved direction, 22 Nov 2026, 15:55): the new title; five integrations in a
    /// fixed order with truthful statuses; in Lab nothing can be connected and no action is offered; no BikeComputer
    /// or bike-sensor row; no FTP; "Always ask me" to start with, and the choice is saved and restored; nothing needs
    /// connecting to continue; everything on one screen.
    func testConnectYourDevices() {
        let app = launch()
        reachGoalsPage(app, roster: ["roadCycling", "strength"])
        let next = app.buttons["onboardingNext"].firstMatch
        el(app, "goal-endurance").tap()
        next.tap(); page(app, 4)
        app.chooseWeekDay(0, ["strength"]); app.chooseWeekDay(1, ["roadCycling"])
        need(app, "onbEquipment", "the equipment choice").buttons["Home"].firstMatch.tap()
        next.tap(); page(app, 5)

        let title = app.staticTexts["onbTitle"].firstMatch
        XCTAssertEqual(title.label, "Connect your devices", "required: the new title")
        XCTAssertTrue(app.staticTexts["onbLabDevices"].firstMatch.exists, "required: Lab says connections are switched off")
        // subtitles as set by the owner on 22 Nov 2026 (16:34)
        let wanted: [(id: String, name: String, status: String, sub: String)] = [
            ("health", "Apple Health", "Not available in Lab", "Connect your health and activity data"), ("watch", "Apple Watch", "Not available in Lab", "Connect your Apple Watch"),
            ("whoop", "WHOOP", "Coming soon", "Connect your WHOOP"), ("garmin", "Garmin", "Coming soon", "Connect your Garmin"),
            ("bluetooth", "Bluetooth devices", "Not available in Lab", "Connect your sensors and devices")]
        var lastY: CGFloat = -1
        for w in wanted {
            let row = need(app, "onbConnection-\(w.id)", "the \(w.name) row")
            XCTAssertTrue(row.staticTexts[w.name].firstMatch.exists, "required: \(w.name) is named")
            XCTAssertTrue(row.staticTexts[w.sub].firstMatch.exists, "required: the subtitle '\(w.sub)'")
            XCTAssertEqual(need(app, "onbConnectionStatus-\(w.id)", "the \(w.name) status").label, w.status, "required: a truthful status for \(w.name)")
            XCTAssertFalse(app.buttons["onbConnectionAction-\(w.id)"].firstMatch.exists, "required: no Connect, Manage or Pair button in Lab for \(w.name)")
            XCTAssertGreaterThan(row.frame.minY, lastY, "required: \(w.name) in the approved order"); lastY = row.frame.minY
        }
        XCTAssertEqual(app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'onbConnection-'")).count, 5, "required: exactly five integrations")
        let gone = NSPredicate(format: "label CONTAINS[c] 'BikeComputer' OR label CONTAINS[c] 'Bike sensors' OR label CONTAINS[c] 'FTP' OR label CONTAINS[c] 'watts' OR label CONTAINS[c] 'calibrate'")
        XCTAssertFalse(app.staticTexts.matching(gone).firstMatch.exists, "required: no BikeComputer row, no bike-sensors row, no FTP, no 'calibrate'")
        XCTAssertFalse(el(app, "onbFTP").exists || app.textFields["onbFTPWatts"].firstMatch.exists, "required: FTP is not asked in onboarding")

        // Owner decision 22 Nov 2026 (16:34): the Plan changes choice is not part of onboarding (it is in Profile ›
        // Coach). The check written at 15:55 required it here, and its saving and restoring.
        XCTAssertFalse(el(app, "onbPlanChanges").exists, "required: no Plan changes section in onboarding")
        let notHere = NSPredicate(format: "label CONTAINS[c] 'Always ask me' OR label CONTAINS[c] 'Auto-apply' OR label CONTAINS[c] 'Plan changes' OR label CONTAINS[c] 'approval' OR label CONTAINS[c] 'Reductions'")
        XCTAssertFalse(app.staticTexts.matching(notHere).firstMatch.exists || app.buttons.matching(notHere).firstMatch.exists, "required: no Coach setting and no paragraph about approval or reductions")
        let line = need(app, "onbCoachLine", "the line above Continue")
        XCTAssertEqual(line.label, "Connect now or set up your devices later in Profile.", "required: the one short line above Continue")

        // one screen, nothing clipped or under the Continue area
        let rail = app.buttons["onboardingBack"].firstMatch, window = app.windows.firstMatch.frame
        XCTAssertTrue(title.isHittable && title.frame.minY >= rail.frame.maxY - 1, "required: the title is wholly visible below the rail")
        for id in wanted.map({ "onbConnection-\($0.id)" }) {
            let e = el(app, id)
            XCTAssertTrue(e.frame.minY >= title.frame.maxY - 1 && e.frame.maxY <= line.frame.minY + 1, "required: \(id) is on screen between the title and the Continue area (\(e.frame), line \(line.frame))")
        }
        XCTAssertTrue(next.isHittable && next.frame.maxY <= window.maxY && next.frame.minY >= line.frame.maxY - 1, "required: Continue is visible below the line")
        app.settleForScreenshot(1); shot("onb-5-connect-your-devices")

        // nothing needs connecting; no system permission prompt appeared; onboarding goes on
        XCTAssertTrue(next.isEnabled, "required: Continue is enabled with no connection made")
        XCTAssertFalse(XCUIApplication(bundleIdentifier: "com.apple.springboard").alerts.firstMatch.exists, "required: no permission prompt on this page")
        next.tap(); page(app, 6)
        app.buttons["onboardingBack"].firstMatch.tap(); page(app, 5)
        need(app, "onbConnection-bluetooth", "the page again after Back")
    }

    /// Athletic Blueprint (owner's combined decision, 22 Nov 2026, 22:51), for a multisport athlete — cycling and gym
    /// planned, running not yet: every chosen activity is in "Your training week", two sessions on one
    /// day included, with the right totals; the Coach section guides only what it plans and says truthfully that the
    /// other sessions are kept; nothing obsolete is linked; a save that fails shows no success and writes nothing;
    /// approval shows the confirmation only once saved; Plan then holds no session for running.
    func testAthleticBlueprintMultisport() {
        let app = XCUIApplication()
        app.launchEnvironment["LAB_NEW_ATHLETE"] = "1"; app.launchEnvironment["LAB_THEME"] = "obsidian"
        app.launchEnvironment["BC_UITEST_SAVE_FAIL"] = "1"            // simulator only: the first Approve tap takes the failure path
        app.launch()
        reachGoalsPage(app, roster: ["roadCycling", "strength", "running"])
        let next = app.buttons["onboardingNext"].firstMatch
        el(app, "goal-endurance").tap()
        next.tap(); page(app, 4)
        app.chooseWeekDay(0, ["strength"]); app.chooseWeekDay(1, ["roadCycling", "running"]); app.chooseWeekDay(3, ["running"]); app.chooseWeekDay(5, ["roadCycling"])
        XCTAssertEqual(need(app, "onbWeekCounts", "the counts").label, "5 sessions · 4 training days · 3 rest days")
        let total = need(app, "onbWeekTotal", "the weekly total").label
        need(app, "onbEquipment", "the equipment choice").buttons["Home"].firstMatch.tap()
        next.tap(); page(app, 5); next.tap(); page(app, 6); next.tap(); page(app, 7)

        // every sport, none called an interest
        for id in ["roadCycling", "strength", "running"] { need(app, "blueprintSport-\(id)", "\(id) in the line-up") }
        // the week exactly as chosen
        XCTAssertTrue(need(app, "blueprintDay-0", "Monday").label.contains("Gym training 30 minutes"), "required: Monday (\(el(app, "blueprintDay-0").label))")
        let tue = need(app, "blueprintDay-1", "Tuesday").label
        XCTAssertTrue(tue.contains("Road cycling 60 minutes") && tue.contains("Road running 30 minutes"), "required: both of Tuesday's sessions (\(tue))")
        XCTAssertTrue(need(app, "blueprintDay-3", "Thursday").label.contains("Road running 30 minutes"), "required: Thursday's run is kept, not shown as rest (\(el(app, "blueprintDay-3").label))")
        XCTAssertTrue(need(app, "blueprintDay-5", "Saturday").label.contains("Road cycling 60 minutes"))
        for d in [2, 4, 6] { XCTAssertTrue(el(app, "blueprintDay-\(d)").label.hasSuffix(", rest"), "required: day \(d) is rest") }
        XCTAssertEqual(need(app, "blueprintWeekTotals", "the week totals").label, "\(total) · 5 sessions", "required: the Blueprint's totals are the chosen week's")
        XCTAssertEqual(total, "3 h 30 min", "required: 30 + 60 + 30 + 30 + 60 minutes")
        // the Coach: guidance for what it plans, a truthful status for the rest
        XCTAssertTrue(need(app, "blueprintCoachLine-0", "guidance").label.hasPrefix("Endurance:"))
        let lifts = need(app, "blueprintCoachLine-1", "strength guidance").label
        XCTAssertTrue(lifts.hasPrefix("1 lift as full body"), "required: guidance matches the one strength session chosen (\(lifts))")
        let status = need(app, "blueprintCoachStatus", "the status of unplanned sessions").label
        XCTAssertTrue(status.hasPrefix("Running: kept in your week as you chose it") && status.contains("coming soon"), "required: a truthful status for running (\(status))")
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] 'run workout' OR label CONTAINS[c] 'pace target' OR label CONTAINS[c] ' km'")).firstMatch.exists, "required: no running workout is claimed")
        blueprintFits(app, "multisport", last: ["blueprintDeclared", "blueprintCell-equipment"])
        app.settleForScreenshot(1); shot("onb-7-blueprint-multisport")

        // a save that fails: no success, still the Blueprint, nothing written
        let approve = app.buttons["onbCreatePlan"].firstMatch
        XCTAssertTrue(approve.exists && approve.label == "Approve my blueprint")
        approve.tap()
        let line = need(app, "onbCoachLine", "the line above the button")
        XCTAssertTrue(XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS 'Not saved.'"), object: line)], timeout: 6) == .completed, "required: a failed save is said (\(line.label))")
        XCTAssertFalse(app.buttons["onbOpenHome"].firstMatch.exists, "required: no success and no Open Home when saving failed")
        XCTAssertFalse(el(app, "blueprintApprovedTag").exists, "required: nothing is marked approved")
        XCTAssertTrue(approve.exists, "required: the athlete can try again")
        app.settleForScreenshot(1); shot("onb-7-blueprint-not-saved")
        app.terminate()
        let again = XCUIApplication(); again.launchEnvironment["LAB_THEME"] = "obsidian"; again.launch()
        XCTAssertTrue(again.staticTexts["onboardingProgress"].firstMatch.waitForExistence(timeout: 30), "required: after a failed save and a relaunch the athlete is still in onboarding — nothing was approved")
        XCTAssertFalse(el(again, "homeGreeting").exists, "required: Home is not shown for an unapproved athlete")
        for _ in 0..<7 {
            let counter = again.staticTexts["onboardingProgress"].firstMatch
            guard let n = Int(counter.label.prefix(1)), n < 7 else { break }
            again.buttons["onboardingNext"].firstMatch.tap()
            _ = XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "NOT (label BEGINSWITH %@)", "\(n) of 7"), object: counter)], timeout: 5)
        }
        page(again, 7)
        XCTAssertEqual(need(again, "blueprintWeekTotals", "the week totals after reopening").label, "3 h 30 min · 5 sessions", "required: the chosen week survived")
        XCTAssertTrue(need(again, "blueprintDay-1", "Tuesday after reopening").label.contains("Road running 30 minutes"), "required: the unplanned session survived")

        // approve for real: confirmation, then Home and Plan
        again.buttons["onbCreatePlan"].firstMatch.tap()
        let openHome = again.buttons["onbOpenHome"].firstMatch
        XCTAssertTrue(openHome.waitForExistence(timeout: 20), "required: the confirmation after approval")
        XCTAssertTrue(el(again, "onbCoachLine").label.contains("Approved and saved."), "required: approved and saved is said (\(el(again, "onbCoachLine").label))")
        XCTAssertEqual(el(again, "blueprintWeekTotals").label, "3 h 30 min · 5 sessions")
        again.settleForScreenshot(1); shot("onb-7-blueprint-multisport-approved")
        openHome.tap()
        XCTAssertTrue(again.waitForHome(name: "Sam", timeout: 20), "required: Home after Open Home")
        // closed and opened again: the approval was stored
        again.terminate()
        let third = XCUIApplication(); third.launchEnvironment["LAB_THEME"] = "obsidian"; third.launch()
        XCTAssertTrue(third.waitForHome(name: "Sam", timeout: 30), "required: after reopening the approved athlete opens Home")
        let planTab = third.buttons["Plan"].firstMatch
        XCTAssertTrue(planTab.waitForExistence(timeout: 8), "required: the Plan tab"); planTab.tap()
        XCTAssertTrue(third.staticTexts["planTitle"].firstMatch.waitForExistence(timeout: 8), "required: Plan is shown")
        let nextWeek = third.buttons["planWeekNext"].firstMatch
        if nextWeek.waitForExistence(timeout: 8), nextWeek.isEnabled { nextWeek.tap(); third.settleForScreenshot(1) }
        let days = third.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'planDay-'")).allElementsBoundByIndex.map { $0.label }
        XCTAssertTrue(days.contains { $0.hasPrefix("Monday") && $0.contains("session") } && days.contains { $0.hasPrefix("Saturday") && $0.contains("session") }, "required: the planned strength and ride days are in Plan (\(days))")
        XCTAssertFalse(days.contains { $0.hasPrefix("Thursday") && $0.contains("session") }, "required: no session is invented for the running day (\(days))")
        XCTAssertTrue(days.contains { $0.hasPrefix("Tuesday") && $0.contains("session") && !$0.contains("2 sessions") }, "required: Tuesday holds the ride only — nothing substituted for the run (\(days))")
        shot("onb-9-plan-multisport")
    }

    /// Athlete Evolution (owner's approved direction, 22 Nov 2026, 17:33), for a cycling, gym and running athlete: the
    /// page fits one screen; the athlete's own status is "Starting stage not yet assessed"; each of G0–G5 can be
    /// tapped and shows its own name and description and is highlighted; a stage being explored is labelled as such
    /// and never becomes the athlete's stage — not on the page, not after Back, Continue or reopening the app.
    func testAthleteEvolution() {
        let app = launch()
        reachGoalsPage(app, roster: ["roadCycling", "strength", "running"])
        let next = app.buttons["onboardingNext"].firstMatch
        el(app, "goal-endurance").tap()
        next.tap(); page(app, 4)
        app.chooseWeekDay(0, ["strength"]); app.chooseWeekDay(1, ["roadCycling"])
        need(app, "onbEquipment", "the equipment choice").buttons["Home"].firstMatch.tap()
        next.tap(); page(app, 5)
        next.tap(); page(app, 6)

        let title = app.staticTexts["onbTitle"].firstMatch
        XCTAssertEqual(title.label, "Athlete Evolution", "required: the title")
        let status = "Starting stage not yet assessed"
        let names = ["Origin", "Foundation", "Development", "Performance", "Refinement", "Mastery"]
        func selected() -> [Int] { (0...5).filter { app.buttons["onbStage-\($0)"].firstMatch.isSelected } }
        func fits(_ what: String) {
            let rail = app.buttons["onboardingBack"].firstMatch, line = need(app, "onbCoachLine", "the line above the button"), window = app.windows.firstMatch.frame
            XCTAssertTrue(title.isHittable && title.frame.minY >= rail.frame.maxY - 1, "required (\(what)): the title is wholly visible")
            for id in ["onbEvolutionState", "onbEvolutionSummary", "onbStage-0", "onbStage-5", "onbEvolutionDeclared", "onbEvolutionMeasured", "onbEvolutionStage"] {
                let e = need(app, id, id)
                XCTAssertTrue(e.frame.minY >= title.frame.maxY - 1 && e.frame.maxY <= line.frame.minY + 1, "required (\(what)): \(id) is on screen between the title and the button area (\(e.frame), line \(line.frame))")
            }
            XCTAssertTrue(next.isHittable && next.frame.maxY <= window.maxY && next.frame.minY >= line.frame.maxY - 1, "required (\(what)): the button is visible below the line")
        }

        // default: nothing explored, nothing claimed, the athlete's own sports
        XCTAssertEqual(need(app, "onbEvolutionState", "the headline").label, "Establishing your baseline", "required: the default headline")
        XCTAssertEqual(need(app, "onbEvolutionStage", "the athlete's own status").label, status, "required: the athlete's status before any assessment")
        XCTAssertFalse(el(app, "onbEvolutionBasis").exists, "required: no 'Estimated' or 'Verified' label while nothing is assessed")
        XCTAssertFalse(el(app, "onbEvolutionExploring").exists, "required: nothing is being explored at first")
        XCTAssertEqual(selected(), [], "required: no stage highlighted at first")
        XCTAssertTrue(need(app, "onbEvolutionYou", "the YOU marker").label.contains(status), "required: YOU carries the athlete's own status")
        let declared = need(app, "onbEvolutionDeclared", "what was declared").label
        for line in ["Cycling · Intermediate", "Strength · Beginner", "Running · experience not asked yet"] { XCTAssertTrue(declared.contains(line), "required: '\(line)' from the athlete's roster (\(declared))") }
        let measured = need(app, "onbEvolutionMeasured", "the evidence").label
        XCTAssertTrue(measured.hasPrefix("Nothing recorded yet") && measured.contains("Running: recording coming soon"), "required: no evidence is claimed, and running is said not to be recorded yet (\(measured))")
        XCTAssertEqual(next.label, "See my blueprint", "required: the button")
        fits("default"); app.settleForScreenshot(1); shot("onb-6-evolution-default")

        // every stage can be explored: its own name and description, highlighted, labelled as exploring — status unchanged
        var seen: [String] = []
        for g in 0...5 {
            app.buttons["onbStage-\(g)"].firstMatch.tap()
            let want = "G\(g) · \(names[g])"
            let head = need(app, "onbEvolutionState", "the headline")
            XCTAssertTrue(XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", want), object: head)], timeout: 4) == .completed, "required: tapping G\(g) shows '\(want)' (shown: \(head.label))")
            let about = need(app, "onbEvolutionSummary", "the stage description").label
            XCTAssertFalse(about.isEmpty || seen.contains(about), "required: G\(g) has its own description (\(about))"); seen.append(about)
            XCTAssertEqual(selected(), [g], "required: only G\(g) is highlighted")
            // wording set by the owner on 22 Nov 2026 (18:47): "Previewing G3" (was my proposed "Exploring · not your stage")
            XCTAssertEqual(need(app, "onbEvolutionExploring", "the preview label").label, "Previewing G\(g)", "required: a preview is said in words")
            XCTAssertEqual(el(app, "onbEvolutionStage").label, status, "required: exploring G\(g) does not change the athlete's status")
            XCTAssertFalse(el(app, "onbEvolutionBasis").exists, "required: exploring G\(g) is not shown as estimated or verified")
            fits("G\(g)")
            if [0, 3, 5].contains(g) { app.settleForScreenshot(1); shot("onb-6-evolution-g\(g)") }
        }
        // tapping the highlighted stage again returns to the default
        app.buttons["onbStage-5"].firstMatch.tap()
        XCTAssertEqual(selected(), [], "required: tapping the highlighted stage clears it")
        XCTAssertEqual(el(app, "onbEvolutionState").label, "Establishing your baseline", "required: the default headline returns")

        // G5 explored, then Back and forward: not kept
        app.buttons["onbStage-5"].firstMatch.tap(); XCTAssertEqual(selected(), [5])
        app.buttons["onboardingBack"].firstMatch.tap(); page(app, 5)
        next.tap(); page(app, 6)
        XCTAssertEqual(selected(), [], "required: an explored stage is not kept after Back")
        XCTAssertEqual(need(app, "onbEvolutionStage", "the status after Back").label, status, "required: the status after Back")

        // G5 explored, then on to the Blueprint: no stage is claimed there
        app.buttons["onbStage-5"].firstMatch.tap(); XCTAssertEqual(selected(), [5])
        next.tap(); page(app, 7)
        let claimed = NSPredicate(format: "label CONTAINS 'Mastery' OR label CONTAINS 'G5'")
        XCTAssertFalse(app.staticTexts.matching(claimed).firstMatch.exists || app.buttons.matching(claimed).firstMatch.exists, "required: the Blueprint does not show the explored stage")
        app.settleForScreenshot(1); shot("onb-7-blueprint-after-exploring-g5")

        // closed and opened again: still not assessed, nothing highlighted
        app.terminate()
        let again = XCUIApplication(); again.launchEnvironment["LAB_THEME"] = "obsidian"; again.launch()
        let counter = again.staticTexts["onboardingProgress"].firstMatch
        XCTAssertTrue(counter.waitForExistence(timeout: 30), "required: onboarding resumes after reopening")
        for _ in 0..<7 {
            guard let n = Int(counter.label.prefix(1)), n != 6 else { break }
            (n < 6 ? again.buttons["onboardingNext"] : again.buttons["onboardingBack"]).firstMatch.tap()
            _ = XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "NOT (label BEGINSWITH %@)", "\(n) of 7"), object: counter)], timeout: 5)
        }
        page(again, 6)
        XCTAssertEqual(need(again, "onbEvolutionStage", "the status after reopening").label, status, "required: no stage was saved by exploring")
        XCTAssertEqual((0...5).filter { again.buttons["onbStage-\($0)"].firstMatch.isSelected }, [], "required: nothing highlighted after reopening")
        XCTAssertEqual(need(again, "onbEvolutionState", "the headline after reopening").label, "Establishing your baseline", "required: the default after reopening")
    }

    /// Build your week (owner's approved direction, 21 Nov 2026, 21:18), for a cycling, gym and running athlete: seven
    /// rest days to start with; Continue needs a confirmed training day; the editor offers the athlete's own sports;
    /// a day changes only when confirmed; each session has its own length; two sessions on one day, not three; a day
    /// goes back to rest; the summary follows every change; equipment appears only with strength; everything is on
    /// one screen above Continue; Back, Continue and reopening keep the week.
    func testBuildYourWeek() {
        let app = launch()
        reachGoalsPage(app, roster: ["roadCycling", "strength", "running"])
        let next = app.buttons["onboardingNext"].firstMatch
        el(app, "goal-endurance").tap()
        next.tap(); page(app, 4)

        // seven rest days, nothing chosen for the athlete
        for i in 0..<7 { XCTAssertTrue(need(app, "onbDay-\(i)", "day \(i)").label.hasSuffix(", rest"), "required: day \(i) starts as rest (\(el(app, "onbDay-\(i)").label))") }
        XCTAssertEqual(need(app, "onbWeekTotal", "the weekly total").label, "0 min")
        XCTAssertEqual(need(app, "onbWeekCounts", "sessions, training days, rest days").label, "0 sessions · 0 training days · 7 rest days")
        XCTAssertFalse(next.isEnabled, "required: Continue is disabled before a training day is chosen")
        XCTAssertFalse(el(app, "onbEquipment").exists, "required: no equipment question before a strength session is chosen")
        need(app, "onbDayEditorHint", "the editor says to tap a day")
        app.settleForScreenshot(1); shot("onb-4-week-all-rest")

        // a day changes only when confirmed
        tap(app, app.buttons["onbDay-0"].firstMatch, "open Monday")
        if !el(app, "onbDayEditorDay").waitForExistence(timeout: 8) {
            // what the editor does contain, so a missing day name can be explained and not guessed at
            let inside = el(app, "onbDayEditor").descendants(matching: .any).allElementsBoundByIndex.prefix(30).map { "\($0.elementType.rawValue)|\($0.identifier)|\($0.label)" }
            XCTFail("required: the day editor names the day. It contains: \(inside)")
        }
        XCTAssertEqual(need(app, "onbDayEditorDay", "the day editor").label, "Monday")
        for a in ["roadCycling", "strength", "running"] { need(app, "onbAct-\(a)", "\(a) from the roster") }
        for a in ["swimming", "walking", "mobility"] { XCTAssertFalse(app.buttons["onbAct-\(a)"].firstMatch.exists, "required: \(a) is not in this roster and is not offered") }
        XCTAssertTrue(app.buttons["onbDayRest"].firstMatch.isSelected, "required: Rest is marked for a rest day")
        let confirm = app.buttons["onbDayConfirm"].firstMatch
        XCTAssertFalse(confirm.isEnabled, "required: nothing to confirm yet")
        tap(app, app.buttons["onbAct-roadCycling"].firstMatch, "road cycling on Monday")
        XCTAssertEqual(el(app, "onbLen-0Minutes").label, "60 min", "required: a ride starts at 60 minutes")
        XCTAssertTrue(el(app, "onbDay-0").label.hasSuffix(", rest") && !next.isEnabled, "required: Monday stays rest until it is confirmed")
        // a session is removed on its own row, without touching the other
        tap(app, app.buttons["onbAct-strength"].firstMatch, "add gym to Monday")
        XCTAssertTrue(need(app, "onbSession-1", "the second session's own row").exists)
        tap(app, app.buttons["onbSessionRemove-1"].firstMatch, "remove the gym session")
        XCTAssertFalse(el(app, "onbSession-1").exists, "required: one session is left"); XCTAssertEqual(el(app, "onbSession-0").label, "Road cycling", "required: the ride is still there")
        XCTAssertTrue(confirm.isEnabled); confirm.tap()
        XCTAssertTrue(el(app, "onbDay-0").label.contains("Road cycling 60 minutes"), "required: Monday is now the chosen ride (\(el(app, "onbDay-0").label))")
        XCTAssertEqual(el(app, "onbWeekTotal").label, "1 h"); XCTAssertEqual(el(app, "onbWeekCounts").label, "1 session · 1 training day · 6 rest days")
        // Owner decision 21 Nov 2026 (22:22): a cycling-and-strength athlete need not schedule both sports. The check
        // written an hour earlier required Continue to stay disabled here under the older planner rule.
        XCTAssertTrue(next.isEnabled, "required: one valid training session enables Continue, whatever else is in the roster")
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] 'Hybrid needs'")).firstMatch.exists, "required: the older both-sports rule is not shown")

        // two sessions on one day, each with its own length; the equipment question arrives with strength
        tap(app, app.buttons["onbDay-2"].firstMatch, "open Wednesday")
        tap(app, app.buttons["onbAct-strength"].firstMatch, "gym on Wednesday"); tap(app, app.buttons["onbAct-running"].firstMatch, "and a run")
        XCTAssertTrue(need(app, "onbSession-1", "the second session's own row").exists)
        for _ in 0..<3 { app.buttons["onbLen-0Plus"].firstMatch.tap() }
        XCTAssertEqual(el(app, "onbLen-0Minutes").label, "45 min"); XCTAssertEqual(el(app, "onbLen-1Minutes").label, "30 min", "required: one session's length does not change the other's")
        XCTAssertFalse(app.buttons["onbAct-roadCycling"].firstMatch.isEnabled, "required: a third session is not offered")
        let line = need(app, "onbCoachLine", "the line above Continue")
        XCTAssertEqual(need(app, "onbDayEditorState", "confirmed or not").label, "Not confirmed yet", "required: an unconfirmed edit is marked as such")
        XCTAssertTrue(el(app, "onbDay-2").label.hasSuffix(", rest"), "required: the calendar still shows the confirmed week while the day is edited")
        XCTAssertTrue(confirm.isHittable && confirm.frame.maxY <= line.frame.minY + 1, "required: Confirm is above the Continue area with two sessions open (confirm \(confirm.frame), line \(line.frame))")
        for id in ["onbDayEditor", "onbWeekTotal", "onbWeekCounts", "onbWeekBySport"] {
            XCTAssertLessThanOrEqual(need(app, id, id).frame.maxY, line.frame.minY + 1, "required: with two sessions open \(id) is not under the Continue area (\(el(app, id).frame), line \(line.frame))")
        }
        confirm.tap()
        // 22 Nov 2026 (14:36): with a strength session in the week the environment must be chosen before Continue
        XCTAssertFalse(next.isEnabled, "required: a strength session needs an equipment environment before Continue")
        need(app, "onbEquipment", "the equipment choice, once a strength session is in the week").buttons["Gym"].firstMatch.tap()
        XCTAssertTrue(el(app, "onbDay-2").label.contains("Gym training 45 minutes") && el(app, "onbDay-2").label.contains("Road running 30 minutes"), "required: Wednesday holds both sessions (\(el(app, "onbDay-2").label))")
        XCTAssertEqual(el(app, "onbWeekTotal").label, "2 h 15 min"); XCTAssertEqual(el(app, "onbWeekCounts").label, "3 sessions · 2 training days · 5 rest days")

        // two sessions of the SAME activity on one day, stored separately with their own lengths (22:22); Monday is not changed
        tap(app, app.buttons["onbDay-5"].firstMatch, "open Saturday")
        tap(app, app.buttons["onbAct-roadCycling"].firstMatch, "a Saturday ride"); tap(app, app.buttons["onbAct-roadCycling"].firstMatch, "and a second ride")
        XCTAssertTrue(el(app, "onbSession-0").exists && el(app, "onbSession-1").exists, "required: the second ride is added, not swapped for the first")
        for _ in 0..<3 { app.buttons["onbLen-0Plus"].firstMatch.tap() }
        for _ in 0..<2 { app.buttons["onbLen-1Minus"].firstMatch.tap() }
        XCTAssertEqual(el(app, "onbLen-0Minutes").label, "90 min"); XCTAssertEqual(el(app, "onbLen-1Minutes").label, "40 min")
        confirm.tap()
        XCTAssertTrue(el(app, "onbDay-5").label.contains("Road cycling 90 minutes and Road cycling 40 minutes"), "required: Saturday holds both rides (\(el(app, "onbDay-5").label))")
        XCTAssertTrue(el(app, "onbDay-0").label.contains("Road cycling 60 minutes"), "required: Monday is still 60 (\(el(app, "onbDay-0").label))")
        XCTAssertEqual(el(app, "onbWeekTotal").label, "4 h 25 min"); XCTAssertEqual(el(app, "onbWeekCounts").label, "5 sessions · 3 training days · 4 rest days")
        XCTAssertEqual(el(app, "onbWeekBySport").label, "Cycling 3 h 10 min · Strength 45 min · Running 30 min")
        XCTAssertTrue(need(app, "onbFeasibility", "the note about two double days").label.contains("double days"), "required: the existing note still appears, and does not block (\(el(app, "onbFeasibility").label))")
        XCTAssertTrue(next.isEnabled, "required: a note is not a block")

        // back to rest, and chosen again
        tap(app, app.buttons["onbDay-0"].firstMatch, "open Monday"); tap(app, app.buttons["onbDayRest"].firstMatch, "Rest")
        XCTAssertEqual(confirm.label, "Make Monday a rest day"); confirm.tap()
        XCTAssertTrue(el(app, "onbDay-0").label.hasSuffix(", rest"), "required: Monday is rest again")
        XCTAssertEqual(el(app, "onbWeekTotal").label, "3 h 25 min"); XCTAssertEqual(el(app, "onbWeekCounts").label, "4 sessions · 2 training days · 5 rest days")
        app.chooseWeekDay(0, ["roadCycling"])
        XCTAssertEqual(el(app, "onbWeekTotal").label, "4 h 25 min"); XCTAssertEqual(el(app, "onbWeekCounts").label, "5 sessions · 3 training days · 4 rest days")
        let mixedLine = el(app, "onbCoachLine").label
        XCTAssertTrue(mixedLine.contains("running days are saved") && mixedLine.contains("Nothing is scheduled until you approve"), "required: planned and saved sports are told apart (\(mixedLine))")

        // one screen: calendar, summary, equipment and Continue, nothing clipped or under the Continue area
        let window = app.windows.firstMatch.frame, title = app.staticTexts["onbTitle"].firstMatch
        XCTAssertTrue(title.isHittable, "required: the page title is visible")
        for id in ["onbWeek", "onbDayEditor", "onbWeekTotal", "onbWeekCounts", "onbWeekBySport", "onbFeasibility", "onbEquipment"] {
            let e = need(app, id, id)
            XCTAssertLessThanOrEqual(e.frame.maxY, line.frame.minY + 1, "required: \(id) is not under the Continue area (bottom \(e.frame.maxY), line starts \(line.frame.minY))")
            XCTAssertGreaterThanOrEqual(e.frame.minY, title.frame.maxY - 1, "required: \(id) is below the title")
        }
        for t in ["Gym", "Home", "Bodyweight", "Custom"] { XCTAssertTrue(el(app, "onbEquipment").buttons[t].firstMatch.isHittable, "required: the \(t) equipment choice is visible") }
        XCTAssertTrue(next.frame.maxY <= window.maxY && next.frame.minY >= line.frame.maxY - 1, "required: Continue is visible below the line")
        app.settleForScreenshot(1); shot("onb-4-week-multisport")

        // Owner's refinement, 22 Nov 2026: the calendar tiles carry icons only (minutes stay in the editor and in the
        // spoken label), and the EXPANDED editor with two sessions, the summary, the equipment choice and Continue are
        // all on the one screen. The check written on 21 Nov accepted the equipment choice stepping aside during an
        // edit; that is no longer accepted — it must be visible here.
        XCTAssertFalse(el(app, "onbWeek").staticTexts.matching(NSPredicate(format: "label MATCHES %@", "^[0-9]+$")).firstMatch.exists, "required: no minutes on the calendar tiles")
        tap(app, app.buttons["onbDay-2"].firstMatch, "open Wednesday again")
        XCTAssertEqual(el(app, "onbDayEditorState").label, "Confirmed", "required: a confirmed day is marked as confirmed")
        XCTAssertEqual(el(app, "onbSession-0").label, "Gym training"); XCTAssertEqual(el(app, "onbLen-0Minutes").label, "45 min"); XCTAssertEqual(el(app, "onbLen-1Minutes").label, "30 min")
        need(app, "onbDayRest", "Rest, in the editor header")
        for id in ["onbWeek", "onbDayEditor", "onbDayConfirm", "onbSessionRemove-1", "onbWeekTotal", "onbWeekCounts", "onbWeekBySport", "onbFeasibility", "onbEquipment"] {
            let e = need(app, id, id)
            XCTAssertLessThanOrEqual(e.frame.maxY, line.frame.minY + 1, "required: expanded editor — \(id) is not under the Continue area (bottom \(e.frame.maxY), line starts \(line.frame.minY))")
            XCTAssertGreaterThanOrEqual(e.frame.minY, title.frame.maxY - 1, "required: expanded editor — \(id) is below the title")
        }
        XCTAssertTrue(title.isHittable, "required: the title is still visible — the page did not need to scroll")
        for t in ["Gym", "Home", "Bodyweight", "Custom"] { XCTAssertTrue(el(app, "onbEquipment").buttons[t].firstMatch.isHittable, "required: expanded editor — the \(t) equipment choice is visible") }
        XCTAssertTrue(el(app, "onbEquipment").frame.minY >= el(app, "onbWeekCounts").frame.maxY - 1 && el(app, "onbWeekTotal").frame.minY >= el(app, "onbDayEditor").frame.maxY - 1, "required: nothing overlaps")
        app.settleForScreenshot(1); shot("onb-4-week-editing-two-sessions")
        // an unconfirmed change is marked, and leaving the day without confirming changes nothing
        app.buttons["onbLen-1Plus"].firstMatch.tap()
        XCTAssertEqual(el(app, "onbDayEditorState").label, "Not confirmed yet"); XCTAssertEqual(el(app, "onbWeekTotal").label, "4 h 25 min", "required: the summary is the confirmed week")
        tap(app, app.buttons["onbDay-2"].firstMatch, "close Wednesday without confirming")
        XCTAssertTrue(el(app, "onbDay-2").label.contains("Road running 30 minutes"), "required: an unconfirmed edit is not saved (\(el(app, "onbDay-2").label))")

        // Continue and Back keep it; so does closing and reopening
        next.tap(); page(app, 5)
        app.buttons["onboardingBack"].firstMatch.tap(); page(app, 4)
        let kept = ["onbDay-0": "Road cycling 60 minutes", "onbDay-2": "Gym training 45 minutes", "onbDay-5": "Road cycling 90 minutes and Road cycling 40 minutes"]
        for (id, text) in kept { XCTAssertTrue(el(app, id).label.contains(text), "required: \(id) after Back (\(el(app, id).label))") }
        app.terminate()
        let again = XCUIApplication(); again.launchEnvironment["LAB_THEME"] = "obsidian"; again.launch()
        let counter = again.staticTexts["onboardingProgress"].firstMatch
        XCTAssertTrue(counter.waitForExistence(timeout: 30), "required: onboarding resumes after reopening")
        if counter.label.hasPrefix("5 of 7") { again.buttons["onboardingBack"].firstMatch.tap() }
        page(again, 4)
        for (id, text) in kept { XCTAssertTrue(need(again, id, id).label.contains(text), "required: \(id) was saved (\(el(again, id).label))") }
        XCTAssertTrue(el(again, "onbDay-2").label.contains("Road running 30 minutes"), "required: the running session was saved too")
        XCTAssertTrue(el(again, "onbDay-1").label.hasSuffix(", rest"), "required: nothing was added while the app was closed")
        XCTAssertEqual(el(again, "onbWeekTotal").label, "4 h 25 min")
    }

    /// All seven pages: each page's required elements, the units choice, a day edit on page 4, a Blueprint group opened
    /// and returned from, then Approve → Home with the entered name → Plan with the approved sessions.
    func testSevenPagesApproveHomePlan() {
        let app = launch()
        let next = app.buttons["onboardingNext"].firstMatch
        reachGoals(app, name: "Sam")

        // 1 · About you (filled by reachGoals: name, 12 Mar 1990, 70 kg, 175 cm). Its details are checked by
        // testAboutYouMeasurements; here: the page is complete and carries no removed text.
        XCTAssertEqual(app.staticTexts["onbTitle"].firstMatch.label, "About you", "required: page 1 title")
        need(app, "onbDOB", "date of birth row"); need(app, "onbUnits", "the compact units selector")
        XCTAssertEqual(app.textFields["onbWeight"].firstMatch.value as? String, "70", "required: the weight entered")
        XCTAssertEqual(app.textFields["onbHeight"].firstMatch.value as? String, "175", "required: the height entered")
        // the owner removed this paragraph on 20 Nov 2026 (18:24); the earlier check required it
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] 'Nothing is estimated from blanks'")).firstMatch.exists, "required: the old page 1 paragraph is gone")
        app.settleForScreenshot(1); shot("onb-1-about-journey")
        XCTAssertTrue(next.isEnabled, "required: Continue once all four are given"); next.tap()

        // 2 · Athletic Roster, 3 · Goals
        rosterAndGoal(app)
        app.settleForScreenshot(1); shot("onb-3-goals")
        XCTAssertTrue(next.isEnabled, "required: Continue with a goal"); next.tap()

        // 4 · Build your week. Owner decision 21 Nov 2026 (21:18): seven rest days to start with and the athlete chooses;
        // the earlier check required the Coach's proposed five sessions here. The page itself is checked by testBuildYourWeek.
        page(app, 4)
        need(app, "onbWeek", "the week strip")
        XCTAssertFalse(next.isEnabled, "required: Continue needs a chosen training day")
        app.chooseWeekDay(0, ["strength"]); app.chooseWeekDay(1, ["roadCycling"]); app.chooseWeekDay(3, ["roadCycling"]); app.chooseWeekDay(4, ["strength"])
        XCTAssertEqual(need(app, "onbWeekCounts", "the counts").label, "4 sessions · 4 training days · 3 rest days")
        XCTAssertEqual(need(app, "onbWeekTotal", "the weekly total").label, "3 h", "required: two rides of 60 and two strength sessions of 30")
        let home = need(app, "onbEquipment", "the equipment choice").buttons["Home"].firstMatch
        XCTAssertTrue(home.exists, "required: the Home equipment choice"); home.tap()
        XCTAssertTrue(el(app, "onbCoachLine").label.contains("Nothing is scheduled until you approve"), "required: page 4 wording")
        app.settleForScreenshot(1); shot("onb-4-week-chosen")
        XCTAssertTrue(next.isEnabled, "required: the chosen week can be continued"); next.tap()

        // 5 · Connect your devices. Owner's direction 22 Nov 2026 (15:55): the page is renamed, FTP is no longer asked
        // here (the earlier check typed 215 W on this page), and the connections are five fixed rows. The page itself
        // is checked by testConnectYourDevices.
        page(app, 5)
        XCTAssertTrue(app.staticTexts["onbLabDevices"].firstMatch.waitForExistence(timeout: 8), "required: Lab says connections are switched off")
        need(app, "onbConnection-health", "the connections list")
        XCTAssertFalse(el(app, "onbFTP").exists, "required: FTP is not asked in onboarding")
        XCTAssertFalse(el(app, "onbPlanChanges").exists, "required: no Plan changes section in onboarding (22 Nov 2026, 16:34)")
        XCTAssertEqual(app.staticTexts["onbTitle"].firstMatch.label, "Connect your devices", "required: page 5 title")
        app.settleForScreenshot(1); shot("onb-5-connect")
        next.tap()

        // 6 · Athlete Evolution. Owner's direction of 22 Nov 2026 (17:33) replaced this page's wording: the status is
        // now "Starting stage not yet assessed" (was "No stage yet …"), what was declared is listed sport by sport
        // (was "Intermediate rider · beginner lifter"), and the rail is six buttons rather than one labelled picture.
        page(app, 6)
        XCTAssertEqual(need(app, "onbEvolutionState", "the baseline headline").label, "Establishing your baseline", "required: the new-athlete state")
        for g in 0...5 { XCTAssertFalse(need(app, "onbStage-\(g)", "stage G\(g) on the rail").isSelected, "required: no stage is selected or claimed") }
        let declared6 = need(app, "onbEvolutionDeclared", "the declared lines").label
        XCTAssertTrue(declared6.contains("Cycling · Intermediate") && declared6.contains("Strength · Beginner"), "required: what was declared, sport by sport (\(declared6))")
        XCTAssertTrue(need(app, "onbEvolutionMeasured", "the measured line").label.hasPrefix("Nothing recorded yet"), "required: no evidence is claimed")
        XCTAssertEqual(need(app, "onbEvolutionStage", "the stage line").label, "Starting stage not yet assessed", "required: no stage is claimed")
        XCTAssertEqual(next.label, "See my blueprint", "required: the button names the next page")
        app.settleForScreenshot(1); shot("onb-6-evolution")
        next.tap()

        // 7 · Athletic Blueprint: who, sports, goal, proposal, declared, measured; a group opens its page and returns
        page(app, 7)
        XCTAssertEqual(app.staticTexts["onbTitle"].firstMatch.label, "Sam", "required: the blueprint is headed by the athlete's name")
        let identity = app.staticTexts["blueprintIdentity"].firstMatch
        // Owner decision 20 Nov 2026 (23:04): the identity is derived from the selected sports — "Cycling/Strength hybrid" — where it used to list the two activity names.
        XCTAssertTrue(identity.exists && identity.label == "Cycling/Strength hybrid · balanced", "required: the roster line (\(identity.label))")
        need(app, "blueprintSports", "the sport line-up")
        for id in ["blueprintSport-roadCycling", "blueprintSport-strength"] { XCTAssertTrue(need(app, id, "a main sport").label.contains("main"), "required: \(id) is a main sport") }
        XCTAssertTrue(need(app, "blueprintMainGoal", "the main goal").label.contains("Endurance"), "required: the main goal is named")
        // four sessions were chosen on page 4 (it was five proposed plus one added before 21 Nov 2026)
        XCTAssertTrue(need(app, "blueprintWeekTotals", "the week totals").label.contains("4 sessions"), "required: the blueprint shows the chosen week (\(el(app, "blueprintWeekTotals").label))")
        need(app, "blueprintWeek", "the athlete's week")
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "blueprintDay-3").firstMatch.label.contains("Road cycling 60 minutes"), "required: Thursday's ride is in the blueprint, with its own length")
        XCTAssertEqual(el(app, "blueprintWeekTotals").label, "3 h · 4 sessions", "required: the totals of the chosen week")
        need(app, "blueprintDeclared", "the declared group")
        // Owner's combined decision, 22 Nov 2026 (22:51): FTP and Plan changes are removed from this page (they live in
        // Performance Settings and Profile › App preferences › Coach), and "Measured evidence" appears only when
        // something is recorded. The earlier checks required all three here.
        XCTAssertTrue(need(app, "blueprintCell-equipment", "the declared equipment").label.contains("Home"), "required: the chosen equipment")
        XCTAssertTrue(need(app, "blueprintCell-goals", "the declared goals").label.contains("Endurance ★"), "required: the declared goals")
        XCTAssertFalse(el(app, "blueprintMeasuredLine").exists, "required: no measured evidence is shown when nothing is recorded")
        XCTAssertTrue(need(app, "blueprintLevels", "declared experience").label.contains("rider") && el(app, "blueprintLevels").label.contains("lifter"), "required: sport-specific experience")
        let g0 = need(app, "blueprintCoachLine-0", "the Coach's first line").label, g1 = need(app, "blueprintCoachLine-1", "the Coach's second line").label
        XCTAssertTrue(g0.hasPrefix("Endurance:"), "required: guidance for the main goal (\(g0))")
        XCTAssertTrue(g1.hasPrefix("2 lifts as full body") && g1.contains("30 min each"), "required: guidance matches the two strength sessions chosen (\(g1))")
        XCTAssertTrue(need(app, "blueprintCoachLine-2", "the first session").label.hasPrefix("First session:"), "required: the first planned session")
        XCTAssertFalse(el(app, "blueprintCoachStatus").exists, "required: no 'coming soon' status when every session is planned")
        blueprintFits(app, "cycling + strength", last: ["blueprintDeclared", "blueprintCell-equipment"])
        let approve = app.buttons["onbCreatePlan"].firstMatch
        XCTAssertTrue(approve.exists && approve.label == "Approve my blueprint", "required: the approval button (\(approve.label))")
        app.settleForScreenshot(1); shot("onb-7-blueprint")
        // the last declared answer is a button, on screen without scrolling (it used to be Plan changes, scrolled into view)
        let lastCell = app.buttons["blueprintCell-equipment"].firstMatch
        XCTAssertTrue(lastCell.exists && lastCell.isHittable, "required: the equipment answer is a button on screen")

        tap(app, el(app, "blueprintYourWeek"), "your training week")
        page(app, 4)
        let back = app.buttons["onbBackToBlueprint"].firstMatch
        XCTAssertTrue(back.waitForExistence(timeout: 5), "required: Back to blueprint replaces Continue")
        XCTAssertFalse(next.exists, "required: an edit from the blueprint does not offer Continue")
        XCTAssertTrue(el(app, "onbCoachLine").label.contains("Editing from your blueprint"), "required: the page says it was opened from the blueprint")
        app.settleForScreenshot(1); shot("onb-7-edit-week")
        // edit the week from the Blueprint and return: the preview follows the latest confirmed answers
        tap(app, app.buttons["onbDay-5"].firstMatch, "open Saturday"); tap(app, app.buttons["onbAct-roadCycling"].firstMatch, "a ride on Saturday")
        tap(app, app.buttons["onbDayConfirm"].firstMatch, "confirm Saturday")
        back.tap()
        page(app, 7)
        XCTAssertEqual(el(app, "blueprintWeekTotals").label, "4 h · 5 sessions", "required: the Blueprint follows the edited week")
        XCTAssertTrue(el(app, "blueprintDay-5").label.contains("Road cycling 60 minutes"), "required: Saturday's new ride is on the Blueprint")
        tap(app, app.buttons["blueprintCell-goals"].firstMatch, "the declared goals")
        page(app, 3)
        XCTAssertTrue(back.waitForExistence(timeout: 5), "required: Back to blueprint on the goals page")
        back.tap()
        page(app, 7)

        // Approve → the saved confirmation (sheet B3) → Home → Plan
        approve.tap()
        let openHome = app.buttons["onbOpenHome"].firstMatch
        XCTAssertTrue(openHome.waitForExistence(timeout: 20), "required: the confirmation after approval")
        XCTAssertEqual(openHome.label, "Open Home", "required: the confirmation offers Open Home")
        let savedLine = el(app, "onbCoachLine").label
        XCTAssertTrue(savedLine.contains("Approved and saved.") && savedLine.contains("Your first session is"), "required: the confirmation says the blueprint was approved and saved (\(savedLine))")
        XCTAssertEqual(need(app, "blueprintApprovedTag", "the approved mark").label, "PLAN VERSION 1 · APPROVED")
        XCTAssertFalse(approve.exists, "required: nothing left to approve")
        XCTAssertEqual(el(app, "blueprintWeekTotals").label, "4 h · 5 sessions", "required: the saved week is the chosen week, with the Saturday ride added from the Blueprint")
        el(app, "blueprintYourWeek").tap()
        XCTAssertTrue(openHome.exists && !app.buttons["onbBackToBlueprint"].firstMatch.exists, "required: the confirmation cannot be edited")
        blueprintFits(app, "approved", last: ["blueprintDeclared"])
        app.settleForScreenshot(1); shot("onb-7-blueprint-approved")
        openHome.tap()
        XCTAssertTrue(app.waitForHome(name: "Sam", timeout: 20), "required: Open Home opens Home with the entered name")
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
        XCTAssertTrue(days.contains { $0.hasPrefix("Thursday") && $0.contains("session") }, "required: Plan has the Thursday ride chosen on page 4 (\(days))")
        XCTAssertTrue(days.contains { $0.hasPrefix("Monday") && $0.contains("session") }, "required: Plan has the Monday session chosen on page 4 (\(days))")
        XCTAssertFalse(days.contains { $0.hasPrefix("Sunday") && $0.contains("session") }, "required: Sunday stays without a session, as approved (\(days))")
        XCTAssertFalse(days.contains { $0.hasPrefix("Wednesday") && $0.contains("session") }, "required: no session on a day the athlete left as rest (\(days))")
        shot("onb-9-plan-next-week")
    }

    /// Pages 3, 4 and 7 at a large accessibility text size: the required controls exist and the pages are captured.
    func testLargeTextPages() {
        let app = launch(arguments: ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityL"])
        let next = app.buttons["onboardingNext"].firstMatch
        reachGoals(app, name: "Sam")
        XCTAssertTrue(next.isEnabled, "required: Continue once all four are given"); next.tap()
        rosterAndGoal(app)
        app.settleForScreenshot(1); shot("onb-large-3-goals")
        _ = app.reveal(el(app, "onbStrengthLevel"), top: 110, bottomMargin: 300)
        app.settleForScreenshot(1); shot("onb-large-3-goals-levels")
        XCTAssertTrue(next.isEnabled, "required: Continue with a goal"); next.tap()
        page(app, 4)
        need(app, "onbWeek", "the week strip")
        need(app, "onbWeekTotal", "the weekly total")
        app.settleForScreenshot(1); shot("onb-large-4-week")
        // 21 Nov 2026 (21:18): the week is chosen, not proposed; at large text the page scrolls
        app.chooseWeekDay(0, ["strength"])
        tap(app, app.buttons["onbDay-1"].firstMatch, "open Tuesday")
        XCTAssertEqual(need(app, "onbDayEditorDay", "the day editor").label, "Tuesday", "required: the editor opens the tapped day")
        tap(app, app.buttons["onbAct-roadCycling"].firstMatch, "a Tuesday ride")
        XCTAssertTrue(app.buttons["onbLen-0Plus"].firstMatch.exists, "required: the ride length control")
        app.settleForScreenshot(1); shot("onb-large-4-week-day")
        tap(app, app.buttons["onbDayConfirm"].firstMatch, "confirm Tuesday")
        let kit = need(app, "onbEquipment", "the equipment choice")
        // Added after simulator run 17 ("Bodyweight" was broken mid-word): all four choices are still offered at large text.
        for t in ["Gym", "Home", "Bodyweight", "Custom"] { XCTAssertTrue(kit.buttons[t].firstMatch.exists, "required: the \(t) equipment choice at large text") }
        tap(app, kit.buttons["Home"].firstMatch, "Home equipment")      // 22 Nov 2026 (14:36): required with a strength session
        _ = app.reveal(el(app, "onbEquipment"), top: 110, bottomMargin: 300)
        app.settleForScreenshot(1); shot("onb-large-4-week-equipment")
        next.tap(); page(app, 5)
        next.tap(); page(app, 6)
        next.tap(); page(app, 7)
        XCTAssertEqual(app.staticTexts["onbTitle"].firstMatch.label, "Sam", "required: the blueprint is headed by the athlete's name")
        // 22 Nov 2026 (22:51): "Measured evidence" is shown only when something is recorded; the Coach section replaces it here
        for id in ["blueprintSports", "blueprintMainGoal", "blueprintWeek", "blueprintCoach", "blueprintDeclared"] { need(app, id, "blueprint part") }
        XCTAssertTrue(app.buttons["onbCreatePlan"].firstMatch.exists, "required: the approval button")
        app.settleForScreenshot(1); shot("onb-large-7-blueprint")
        _ = app.reveal(el(app, "blueprintDeclared"), top: 110, bottomMargin: 300)
        app.settleForScreenshot(1); shot("onb-large-7-blueprint-declared")
        _ = app.reveal(el(app, "blueprintCell-equipment"), top: 110, bottomMargin: 300)
        app.settleForScreenshot(1); shot("onb-large-7-blueprint-end")
    }
}
