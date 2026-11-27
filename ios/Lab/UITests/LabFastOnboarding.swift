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
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] 'First session' OR label CONTAINS[c] 'rides ·' OR label CONTAINS[c] 'Zone' OR label CONTAINS[c] 'full body' OR label CONTAINS[c] ' lifts'")).firstMatch.exists, "required: no planned session and no cycling or strength guidance on this Blueprint")   // check 49: the first version looked for 'lift', which the Lab badge "CYCLIFT LAB" contains
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
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] 'full body' OR label CONTAINS[c] ' lifts' OR label CONTAINS[c] ' lift '")).firstMatch.exists, "required: no strength guidance for an athlete without strength")   // check 49: the first version looked for 'lift', which the Lab badge "CYCLIFT LAB" contains
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

    // MARK: Home — full-page captures for the owner's visual review (23 Nov 2026). CAPTURE ONLY: these change nothing
    // in the app and assert only that Home was reached; the pictures are stitched into one image per state afterwards.

    /// Consecutive screenshots of a scrolling page from the top to the end: each step drags the page up by the same
    /// distance and holds before lifting, so the page does not coast and no content is skipped between two pictures.
    private func captureFullPage(_ app: XCUIApplication, _ name: String, steps: Int = 14) {
        app.settleForScreenshot(1); shot("\(name)-00")
        for i in 1...steps {
            // from the page's left gutter: a drag begun on the trends graph inspects the graph instead of scrolling the page
            let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.015, dy: 0.62))
            from.press(forDuration: 0.1, thenDragTo: from.withOffset(CGVector(dx: 0, dy: -300)), withVelocity: .slow, thenHoldForDuration: 0.4)
            Thread.sleep(forTimeInterval: 0.6)
            shot(String(format: "%@-%02d", name, i))
        }
    }
    /// Home of the Lab's demonstration athlete: a plan, ride history and a strength session today.
    func testCaptureHomeDemoAthlete() {
        // check 51 captured the previous test's athlete here: without LAB_FRESH_DEMO Lab keeps whatever records it last held
        let app = XCUIApplication(); app.launchEnvironment["LAB_THEME"] = "obsidian"; app.launchEnvironment["LAB_FRESH_DEMO"] = "1"; app.launch()
        XCTAssertTrue(app.waitForHome(name: "Demo", timeout: 30), "required: Home of the demonstration athlete")
        captureFullPage(app, "home-demo")
    }
    /// Home — the owner's final decision (23 Nov 2026, 09:40): the original design, with one change. The separate
    /// "Coach page" link is gone and the whole Coach card opens the Coach page — from its text, its background and its
    /// chevron — and returns to Home. Everything else on Home is present and still answers. Then one full-page capture.
    func testHomeFinalBaselineAndCoachCard() {
        let app = XCUIApplication(); app.launchEnvironment["LAB_THEME"] = "obsidian"; app.launchEnvironment["LAB_FRESH_DEMO"] = "1"
        app.launch()
        XCTAssertTrue(app.waitForHome(name: "Demo", timeout: 30), "required: Home of the demonstration athlete")
        // every section is there
        for id in ["homeDate", "homeGreeting", "homeAvatar", "indicatorConsistency", "indicatorMix", "indicatorRecovery", "sportCard-endurance", "sportCard-strength",
                   "sleepBar", "trendsInfo", "trendsChart", "trendsHint", "metricRow-restingHR"] { need(app, id, id) }
        for d in 0..<7 { need(app, "scheduleDay-\(d)", "day \(d)") }
        for h in ["Trends", "Key metrics"] { XCTAssertTrue(app.staticTexts[h].firstMatch.exists, "required: the \(h) heading") }
        for kind in ["trendsMode-", "trendsRange-", "trendsSeries-", "metricRow-"] {
            XCTAssertGreaterThan(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", kind)).count, 0, "required: \(kind) controls are on Home")
        }
        // the Coach card: no separate link, and the whole card is the way in
        XCTAssertFalse(app.buttons["homeCoachOpen"].firstMatch.exists, "required: the separate Coach page link is gone")
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label == 'Coach page'")).firstMatch.exists, "required: no 'Coach page' text on Home")
        let action = el(app, "homeCoachAction"), quiet = el(app, "homeCoachQuiet")
        let card = action.exists ? action : quiet
        XCTAssertTrue(card.exists, "required: the Coach card is on Home")
        XCTAssertTrue(app.reveal(card, top: 170, bottomMargin: 140), "required: the Coach card can be brought fully on screen")
        let said = "\(card.label) | \((card.value as? String) ?? "")"
        XCTAssertTrue(card.label.hasSuffix("Coach"), "required: the card is announced as Coach (\(card.label))")
        XCTAssertFalse(((card.value as? String) ?? "").isEmpty, "required: the card speaks its finding in full")
        print("LAB-NOTE Home Coach card: \(said); frame \(card.frame)")
        XCTAssertGreaterThanOrEqual(card.frame.height, 44, "required: a complete touch area"); XCTAssertGreaterThan(card.frame.width, 300, "required: the card spans the page")
        app.settleForScreenshot(1); shot("home-final-coach-card")
        for (where_, at) in [("its text", CGVector(dx: 0.5, dy: 0.6)), ("its background", CGVector(dx: 0.035, dy: 0.9)), ("its chevron", CGVector(dx: 0.955, dy: 0.3))] {
            _ = app.reveal(card, top: 170, bottomMargin: 140)
            card.coordinate(withNormalizedOffset: at).tap()
            XCTAssertTrue(el(app, "coachTimeline").waitForExistence(timeout: 8), "required: tapping the Coach card on \(where_) opens the Coach page")
            if where_ == "its text" { app.settleForScreenshot(1); shot("home-final-coach-page") }
            let close = app.buttons["coachClose"].firstMatch
            XCTAssertTrue(close.waitForExistence(timeout: 5), "required: the Coach page can be closed"); close.tap()
            XCTAssertTrue(app.waitForHome(name: "Demo", timeout: 10), "required: closing the Coach page returns to Home (after \(where_))")
            XCTAssertEqual("\(card.label) | \((card.value as? String) ?? "")", said, "required: the card says the same after returning")
        }
        // the graph still answers
        let modes = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'trendsMode-'")).allElementsBoundByIndex
        if modes.count > 1 {
            _ = app.reveal(modes[1], top: 170, bottomMargin: 140); modes[1].tap()
            XCTAssertTrue(modes[1].isSelected, "required: the second Trends view can be chosen"); modes[0].tap()
        }
        let chart = el(app, "trendsChart"); _ = app.reveal(chart, top: 170, bottomMargin: 140)
        chart.coordinate(withNormalizedOffset: CGVector(dx: 0.55, dy: 0.5)).press(forDuration: 0.4)
        XCTAssertTrue(el(app, "trendsPanelDate").waitForExistence(timeout: 4), "required: touching the graph inspects a day")
        app.terminate()

        let again = XCUIApplication(); again.launchEnvironment["LAB_THEME"] = "obsidian"; again.launchEnvironment["LAB_FRESH_DEMO"] = "1"; again.launch()
        XCTAssertTrue(again.waitForHome(name: "Demo", timeout: 30))
        captureFullPage(again, "home-final", steps: 8)
    }

    // MARK: Plan — full-page captures for the owner's visual review (23 Nov 2026). CAPTURE ONLY.

    private func capturePlan(_ app: XCUIApplication, _ name: String) {
        let plan = app.buttons["Plan"].firstMatch
        XCTAssertTrue(plan.waitForExistence(timeout: 8), "required: the Plan tab"); plan.tap()
        XCTAssertTrue(app.staticTexts["planTitle"].firstMatch.waitForExistence(timeout: 8), "required: Plan is shown")
        captureFullPage(app, "\(name)-weekly", steps: 6)
        for _ in 0..<6 { app.swipeDown() }
        let recurring = app.buttons["planSection-recurring"].firstMatch
        XCTAssertTrue(recurring.waitForExistence(timeout: 5), "required: the Recurring Plan section"); recurring.tap()
        captureFullPage(app, "\(name)-recurring", steps: 8)
    }
    /// Plan of the Lab's demonstration athlete: Weekly Calendar and Recurring Plan, each from top to bottom.
    func testCapturePlanDemoAthlete() {
        let app = XCUIApplication(); app.launchEnvironment["LAB_THEME"] = "obsidian"; app.launchEnvironment["LAB_FRESH_DEMO"] = "1"; app.launch()
        XCTAssertTrue(app.waitForHome(name: "Demo", timeout: 30), "required: Home of the demonstration athlete")
        capturePlan(app, "plan-demo")
    }
    /// Plan of a runner who finished onboarding without a generated plan.
    func testCapturePlanAthleteWithoutPlan() {
        let app = launch()
        reachGoalsPage(app, roster: ["running"])
        let next = app.buttons["onboardingNext"].firstMatch
        el(app, "goal-runPace").tap()
        next.tap(); page(app, 4)
        app.chooseWeekDay(0, ["running"]); app.chooseWeekDay(3, ["running"])
        next.tap(); page(app, 7)
        app.buttons["onbCreateProfile"].firstMatch.tap(); app.openHomeFromBlueprint()
        XCTAssertTrue(el(app, "homeGreeting").waitForExistence(timeout: 20), "required: Home after Create my profile")
        capturePlan(app, "plan-noplan")
    }

    /// Home of a new cycling and strength athlete straight after approving a plan.
    func testCaptureHomeNewAthleteWithPlan() {
        let app = launch()
        reachGoalsPage(app, roster: ["roadCycling", "strength"])
        let next = app.buttons["onboardingNext"].firstMatch
        el(app, "goal-endurance").tap()
        next.tap(); page(app, 4)
        for d in 0..<7 { app.chooseWeekDay(d, [d % 2 == 0 ? "strength" : "roadCycling"]) }      // every day, so today always holds a session
        need(app, "onbEquipment", "the equipment choice").buttons["Home"].firstMatch.tap()
        next.tap(); page(app, 5); next.tap(); page(app, 6); next.tap(); page(app, 7)
        app.buttons["onbCreatePlan"].firstMatch.tap(); app.openHomeFromBlueprint()
        XCTAssertTrue(app.waitForHome(name: "Sam", timeout: 20), "required: Home after approval")
        captureFullPage(app, "home-plan")
    }
    /// Home of a runner who finished onboarding without a generated plan.
    func testCaptureHomeAthleteWithoutPlan() {
        let app = launch()
        reachGoalsPage(app, roster: ["running"])
        let next = app.buttons["onboardingNext"].firstMatch
        el(app, "goal-runPace").tap()
        next.tap(); page(app, 4)
        app.chooseWeekDay(0, ["running"]); app.chooseWeekDay(3, ["running"])
        next.tap(); page(app, 7)
        app.buttons["onbCreateProfile"].firstMatch.tap(); app.openHomeFromBlueprint()
        XCTAssertTrue(el(app, "homeGreeting").waitForExistence(timeout: 20), "required: Home after Create my profile")
        captureFullPage(app, "home-noplan")
    }

    // MARK: Consistency Dashboard (owner's design direction, 23 Nov 2026, 11:59) — the page the Home Consistency ring opens
    private func toTop(_ app: XCUIApplication) {
        for _ in 0..<6 {
            let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.015, dy: 0.35))
            from.press(forDuration: 0.05, thenDragTo: from.withOffset(CGVector(dx: 0, dy: 420)))
        }
        Thread.sleep(forTimeInterval: 0.6)
    }
    private func label(_ app: XCUIApplication, _ id: String) -> String {
        let e = el(app, id)
        XCTAssertTrue(e.waitForExistence(timeout: 6), "required: \(id)")
        return e.exists ? e.label : ""
    }
    /// Brings a control clear of the bar above and the dock below, then presses it.
    private func press(_ app: XCUIApplication, _ id: String) {
        let e = el(app, id)
        XCTAssertTrue(e.waitForExistence(timeout: 6), "required: \(id)")
        guard e.exists else { return }
        // Scrolls from the left gutter, clear of every control. Changed after check 65: the shared `reveal` drags from the
        // middle of the screen, and with the page at a new length that drag began on the chosen graph column, which the
        // simulator took as a press — clearing the selection and removing the very link about to be pressed.
        let screen = app.windows.firstMatch.frame
        for _ in 0..<14 {
            let f = e.frame
            if f.minY >= 190 && f.maxY <= screen.height - 190 { break }
            let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.015, dy: 0.5))
            let dy: CGFloat = f.minY < 190 ? min(300, 230 - f.minY) : -min(300, f.maxY - (screen.height - 230))
            from.press(forDuration: 0.05, thenDragTo: from.withOffset(CGVector(dx: 0, dy: dy)), withVelocity: .slow, thenHoldForDuration: 0.2)
            Thread.sleep(forTimeInterval: 0.3)
        }
        e.tap()
        Thread.sleep(forTimeInterval: 0.4)
    }
    private func openConsistency(_ app: XCUIApplication) -> String {
        let ring = el(app, "indicatorConsistency")
        XCTAssertTrue(ring.waitForExistence(timeout: 8), "required: the Consistency ring on Home")
        let value = ring.value as? String ?? ""
        ring.tap()
        XCTAssertTrue(el(app, "consistencyDashboard").waitForExistence(timeout: 8), "required: the ring opens the Consistency Dashboard")
        XCTAssertTrue(app.navigationBars["Consistency"].firstMatch.waitForExistence(timeout: 4), "required: the page is titled Consistency")
        return value
    }

    private func text(_ app: XCUIApplication, _ id: String) -> String {
        let e = app.staticTexts[id].firstMatch
        XCTAssertTrue(e.waitForExistence(timeout: 6), "required: \(id)")
        return e.exists ? e.label : ""
    }
    private func point(_ app: XCUIApplication, _ i: Int) -> XCUIElement { app.buttons["consistencyPoint-\(i)"].firstMatch }
    private func choose(_ app: XCUIApplication, _ i: Int) { point(app, i).tap(); Thread.sleep(forTimeInterval: 0.35) }
    /// The floating label is on screen, wholly inside the graph card, close to the chosen point's column, and clear of
    /// the Weeks / Days control and the legend. Returns what it says.
    private func tooltip(_ app: XCUIApplication, at i: Int, _ what: String) -> String {
        let t = app.staticTexts["consistencyTooltip"].firstMatch
        XCTAssertTrue(t.waitForExistence(timeout: 5), "required: a floating label at \(what)")
        guard t.exists else { return "" }
        let graph = el(app, "consistencyGraph").frame, col = point(app, i).frame, f = t.frame
        XCTAssertTrue(graph.contains(f), "required: the label stays inside the chart at \(what) (label \(f), chart \(graph))")
        XCTAssertLessThanOrEqual(abs(f.midX - col.midX), col.width + f.width / 2 + 14, "required: the label is at the chosen point at \(what)")
        XCTAssertTrue(f.minY >= col.minY - 1 && f.maxY <= col.maxY + 1, "required: the label is inside the plotted area, clear of the selector above and the legend below, at \(what)")
        return t.label
    }

    /// Consistency Dashboard, final refinements (owner, 23 Nov 2026, 14:04), for Lab's "Consistency history" athlete: no
    /// headline percentage; a floating label at the chosen point with the figure or the truthful status; the inspection
    /// card kept; ONE summary from the records that follows the chosen week or day; sport rows and navigation preserved.
    func testConsistencyDashboardHistory() {
        let app = XCUIApplication(); app.launchEnvironment["LAB_THEME"] = "obsidian"; app.launchEnvironment["LAB_FRESH_DEMO"] = "1"
        app.launchEnvironment["LAB_DEMO_CONSISTENCY"] = "1"; app.launch()
        XCTAssertTrue(app.waitForHome(name: "Demo", timeout: 30), "required: Home of the demonstration athlete")
        XCTAssertTrue(app.staticTexts["CYCLIFT LAB · DEMO DATA"].firstMatch.exists, "required: the page is marked as Lab demo data")
        let ring = openConsistency(app)
        let summary = text(app, "consistencySummaryLine")
        if let m = ring.range(of: #"\d+ of \d+"#, options: .regularExpression) {
            XCTAssertTrue(summary.contains(String(ring[m])), "required: the dashboard states the Home ring's own count (ring: \(ring) · dashboard: \(summary))")
        } else { XCTFail("required: the Home ring states a count for this athlete (\(ring))") }
        XCTAssertTrue(text(app, "consistencyPeriod").contains("In progress"), "required: the current week is marked In progress")
        XCTAssertFalse(app.staticTexts["consistencyPercent"].exists, "required: no headline percentage")
        XCTAssertFalse(summary.contains("%") || text(app, "consistencyPeriod").contains("%"), "required: no percentage in the header")
        XCTAssertFalse(app.staticTexts["consistencyTooltip"].exists || el(app, "consistencyInspection").exists, "nothing is chosen until a point is pressed")
        XCTAssertFalse(el(app, "consistencyInsightSports").exists, "required: one summary from the records only")
        let first = el(app, "consistencyInsightOverall").label
        captureFullPage(app, "cons-3-none-selected", steps: 5); toTop(app)

        // Weeks: every point answers with its floating label, its card and the summary for that week
        let expected: [(Int, String, String)] = [(0, "100%", "5 of 5"), (1, "60%", "3 of 5"), (2, "40%", "2 of 5"), (3, "80%", "4 of 5"), (4, "100%", "5 of 5"), (5, "60%", "3 of 5"), (6, "80%", "4 of 5")]
        for (i, pct, ratio) in expected {
            choose(app, i)
            let tip = tooltip(app, at: i, "week \(i)")
            XCTAssertTrue(tip.hasPrefix(pct), "required: the label at week \(i) says \(pct) (\(tip))")
            XCTAssertTrue(text(app, "consistencyInspectionLine").contains(ratio), "required: the card for week \(i) says \(ratio)")
            if i == 2 || i == 6 {
                XCTAssertTrue(text(app, "consistencySummaryLine").contains(ratio), "required: the header follows the chosen week")
                let coach = el(app, "consistencyInsightOverall").label
                XCTAssertTrue(coach.contains(ratio) && coach != first, "required: the summary from the records follows the chosen week (\(coach))")
            }
            if i == 2 { XCTAssertTrue(text(app, "consistencyInspectionCounts").contains("Missed 3"), "required: that week's missed sessions are counted") }
        }
        choose(app, 7)
        XCTAssertTrue(tooltip(app, at: 7, "the current week").contains("In progress"), "required: the current week's label says In progress")
        choose(app, 6)
        XCTAssertTrue(text(app, "consistencyInspectionTitle").contains("80%"), "required: choosing another point replaces the label and the card in place")
        XCTAssertTrue(text(app, "consistencyInspectionCounts").contains("Skipped 1"), "required: last week's skipped ride is counted as skipped, outside the figure")
        captureFullPage(app, "cons-1-weeks-selected", steps: 6); toTop(app)
        choose(app, 6)
        XCTAssertFalse(app.staticTexts["consistencyTooltip"].exists || el(app, "consistencyInspection").exists, "required: pressing the chosen point again clears the selection")
        choose(app, 6)
        press(app, "consistencyViewDetails")
        XCTAssertTrue(el(app, "weekOverviewTitle").waitForExistence(timeout: 8), "required: View week opens the existing weekly overview")
        XCTAssertTrue(el(app, "weekOverviewTitle").label.contains("Week of"), "required: for the chosen week, not this one")
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(el(app, "consistencyDashboard").waitForExistence(timeout: 6), "required: back returns to the dashboard")

        // Days of that week: Thursday holds two planned sessions, one recorded
        toTop(app); app.buttons["consistencyMode-days"].firstMatch.tap(); Thread.sleep(forTimeInterval: 0.4)
        XCTAssertFalse(app.staticTexts["consistencyTooltip"].exists, "switching the view clears the selection")
        let wants: [(Int, String)] = [(0, "100%"), (1, "100%"), (2, "Skipped"), (3, "50%"), (4, "Rest day"), (5, "100%"), (6, "Nothing planned")]
        for (i, want) in wants {
            choose(app, i)
            let tip = tooltip(app, at: i, "day \(i)")
            XCTAssertTrue(tip.hasPrefix(want), "required: the label at day \(i) says \(want) (\(tip))")
            if !want.contains("%") { XCTAssertFalse(tip.contains("%"), "required: no figure where there is none (day \(i): \(tip))") }
        }
        XCTAssertTrue(label(app, "consistencyInspectionSession-0").contains("not in the plan"), "required: Sunday's ride outside the plan is listed and not counted")
        choose(app, 3)
        let thu = text(app, "consistencyInspectionTitle")
        XCTAssertTrue(thu.contains("Thursday") && thu.contains("50%"), "required: Thursday shows 50% (\(thu))")
        XCTAssertTrue(text(app, "consistencyInspectionLine").contains("1 of 2"), "required: 1 of 2 planned sessions")
        XCTAssertTrue(label(app, "consistencyInspectionSession-0").contains("Completed") && label(app, "consistencyInspectionSession-1").contains("Missed"), "required: each session with its real state")
        let day = el(app, "consistencyInsightOverall").label
        XCTAssertTrue(day.contains("1 of 2") && day.contains("Thursday") && day.contains("Missed"), "required: the summary from the records follows the chosen day (\(day))")
        XCTAssertFalse(day.lowercased().contains("fatigue") || day.lowercased().contains("motivation"), "no cause is guessed")
        captureFullPage(app, "cons-2-days-thursday", steps: 6); toTop(app)
        press(app, "consistencyViewDetails")
        XCTAssertTrue(el(app, "homeDayDetail").waitForExistence(timeout: 8), "required: View Thursday opens the existing day page")
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(el(app, "consistencyDashboard").waitForExistence(timeout: 6), "required: back returns to the dashboard")

        // by sport, for the same week — rows and drill-downs as before, and no second summary
        XCTAssertTrue(el(app, "consistencySport-cycling").label.contains("2 of 3"), "required: cycling 2 of 3")
        XCTAssertTrue(el(app, "consistencySport-strength").label.contains("2 of 2"), "required: strength 2 of 2")
        for id in ["running", "swimming"] {
            let l = el(app, "consistencySport-\(id)").label
            XCTAssertTrue(l.contains("not tracked yet") && !l.contains("percent"), "required: \(id) says Not tracked yet and shows no percentage (\(l))")
        }
        press(app, "consistencySport-cycling")
        XCTAssertTrue(text(app, "consistencySportDetailLine").contains("2 of 3"), "required: the chosen sport shows its own count")
        XCTAssertTrue(el(app, "consistencySportSession-0").waitForExistence(timeout: 4), "required: and the sessions behind it")
        XCTAssertFalse(el(app, "consistencyInsightSports").exists, "required: choosing a sport adds no second summary")
        toTop(app); captureFullPage(app, "cons-4-sport-selected", steps: 7)
        press(app, "consistencySportSession-0")
        XCTAssertTrue(el(app, "homeRideDetail").waitForExistence(timeout: 8), "required: a recorded session opens its existing record")
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(el(app, "consistencyDashboard").waitForExistence(timeout: 6), "required: back returns to the dashboard")
        press(app, "consistencySport-running")
        XCTAssertTrue(text(app, "consistencySportDetailLine").contains("does not plan or record"), "required: an untracked sport explains itself")
        XCTAssertFalse(el(app, "consistencyDetail-0").exists, "session details start closed")
        press(app, "consistencyDetailsToggle")
        XCTAssertTrue(el(app, "consistencyDetail-0").waitForExistence(timeout: 4), "required: Session details opens the sessions")
        XCTAssertTrue(el(app, "consistencyOpenOverview").exists, "required: with the way to the existing pages")

        app.navigationBars.buttons.firstMatch.tap()
        let again = el(app, "indicatorConsistency")
        XCTAssertTrue(again.waitForExistence(timeout: 8), "required: back returns to Home")
        XCTAssertEqual(again.value as? String ?? "", ring, "required: the Home ring says what it said before")
    }

    /// An athlete with goals saved and no generated plan: no percentage anywhere, the floating label says "No plan", and
    /// the sport is said truthfully to be untracked.
    func testConsistencyDashboardWithoutPlan() {
        let app = launch()
        reachGoalsPage(app, roster: ["running"])
        let next = app.buttons["onboardingNext"].firstMatch
        el(app, "goal-runPace").tap()
        next.tap(); page(app, 4)
        app.chooseWeekDay(0, ["running"]); app.chooseWeekDay(3, ["running"])
        next.tap(); page(app, 7)
        app.buttons["onbCreateProfile"].firstMatch.tap(); app.openHomeFromBlueprint()
        XCTAssertTrue(el(app, "homeGreeting").waitForExistence(timeout: 20), "required: Home after Create my profile")
        _ = openConsistency(app)
        XCTAssertTrue(text(app, "consistencySummaryLine").contains("No training plan yet"), "required: the header says there is no plan")
        XCTAssertFalse(app.staticTexts["consistencyPercent"].exists, "required: no headline percentage")
        for i in 0..<8 { XCTAssertFalse(point(app, i).label.contains("percent"), "required: week \(i) shows no percentage") }
        choose(app, 5)
        let tip = tooltip(app, at: 5, "a week without a plan")
        XCTAssertTrue(tip.hasPrefix("No plan") && !tip.contains("%"), "required: the label says No plan, never a figure (\(tip))")
        choose(app, 7); _ = tooltip(app, at: 7, "the current week without a plan (the last column)")
        choose(app, 7)
        XCTAssertTrue(el(app, "consistencyInsightOverall").label.contains("no training plan yet"), "required: the summary from the records says so")
        XCTAssertFalse(el(app, "consistencyInsightSports").exists, "required: one summary only")
        let run = el(app, "consistencySport-running").label
        XCTAssertTrue(run.contains("not tracked yet") && !run.contains("percent"), "required: running is Not tracked yet, never 0 % (\(run))")
        app.buttons["consistencyMode-days"].firstMatch.tap(); Thread.sleep(forTimeInterval: 0.4)
        for i in 0..<7 { XCTAssertFalse(point(app, i).label.contains("percent"), "required: day \(i) shows no percentage") }
        app.buttons["consistencyMode-weeks"].firstMatch.tap()
        toTop(app); captureFullPage(app, "cons-5-noplan", steps: 4)
    }

    // MARK: Training Mix and Recovery dashboards (owner's shared design direction, 23 Nov 2026, 19:55)

    /// The floating label of a dashboard graph: on screen, wholly inside the graph card and inside the plotted area, at
    /// the chosen column. Returns its line and, when there is one, its second line.
    private func tip(_ app: XCUIApplication, _ prefix: String, at i: Int, _ what: String) -> (String, String) {
        let t = app.staticTexts["\(prefix)Tooltip"].firstMatch
        XCTAssertTrue(t.waitForExistence(timeout: 5), "required: a floating label at \(what)")
        guard t.exists else { return ("", "") }
        let graph = el(app, "\(prefix)Graph").frame, col = app.buttons["\(prefix)Point-\(i)"].firstMatch.frame
        let d = app.staticTexts["\(prefix)TooltipDetail"].firstMatch
        for f in [t.frame] + (d.exists ? [d.frame] : []) {
            XCTAssertTrue(graph.contains(f), "required: the label stays inside the chart at \(what) (label \(f), chart \(graph))")
            XCTAssertTrue(f.minY >= col.minY - 1 && f.maxY <= col.maxY + 1, "required: the label is inside the plotted area at \(what)")
            XCTAssertLessThanOrEqual(abs(f.midX - col.midX), col.width + f.width / 2 + 14, "required: the label is at the chosen column at \(what)")
        }
        return (t.label, d.exists ? d.label : "")
    }
    /// The floating label sits beside its point — above, below, or to a side — never sent to the top of the chart.
    private func anchored(_ app: XCUIApplication, _ prefix: String, _ what: String) {
        let side = app.staticTexts["\(prefix)Tooltip"].firstMatch.value as? String ?? ""
        XCTAssertTrue(["above", "below", "left", "right"].contains(side), "required: the label is anchored to its point at \(what) (placed: \(side))")
    }
    private func pick(_ app: XCUIApplication, _ prefix: String, _ i: Int) { app.buttons["\(prefix)Point-\(i)"].firstMatch.tap(); Thread.sleep(forTimeInterval: 0.35) }
    private func launchHistory(_ extra: String? = nil) -> XCUIApplication {
        let app = XCUIApplication(); app.launchEnvironment["LAB_THEME"] = "obsidian"; app.launchEnvironment["LAB_FRESH_DEMO"] = "1"
        app.launchEnvironment[extra ?? "LAB_DEMO_CONSISTENCY"] = "1"; app.launch()
        XCTAssertTrue(app.waitForHome(name: "Demo", timeout: 30), "required: Home of the demonstration athlete")
        XCTAssertTrue(app.staticTexts["CYCLIFT LAB · DEMO DATA"].firstMatch.exists, "required: the page is marked as Lab demo data")
        return app
    }
    private func openCircle(_ app: XCUIApplication, _ ring: String, page: String, title: String) -> String {
        let r = el(app, ring)
        XCTAssertTrue(r.waitForExistence(timeout: 8), "required: \(ring) on Home")
        let value = r.value as? String ?? ""
        r.tap()
        XCTAssertTrue(el(app, page).waitForExistence(timeout: 8), "required: the circle opens \(page)")
        XCTAssertTrue(app.navigationBars[title].firstMatch.waitForExistence(timeout: 4), "required: the page is titled \(title)")
        return value
    }

    /// Training Mix for the "Consistency history" athlete: last week holds 3 h 28 min of rides (58 + 115 + 35 min) and
    /// 1 h 24 min of strength (two sessions of 42 min) against 3 h 45 min and 1 h 20 min planned; Thursday holds one
    /// strength session recorded and a planned ride with nothing recorded.
    func testTrainingMixDashboard() {
        let app = launchHistory()
        let ring = openCircle(app, "indicatorMix", page: "trainingMixDashboard", title: "Training Mix")
        XCTAssertFalse(text(app, "mixSummaryLine").contains("%"), "required: no standalone ratio in the header")
        XCTAssertFalse(app.staticTexts["mixTooltip"].exists || el(app, "mixInspection").exists, "nothing is chosen until a column is pressed")
        let first = el(app, "mixInsight").label
        for i in 0..<8 {
            pick(app, "mix", i)
            let t = tip(app, "mix", at: i, "week \(i)")
            XCTAssertTrue(t.0.contains(" · "), "required: the label names its period (\(t.0))")
            // Changed 24 Nov 2026 (15:18) on the owner's instruction: the page opens by TRAINING TYPE, so the distribution
            // names Endurance and Strength; "Cycling" is the wording of the Individual sports view, asserted further down.
            if i < 7 { XCTAssertTrue(t.0.contains("h") && t.1.contains("Endurance") && t.1.contains("Strength"), "required: week \(i) shows its recorded time and distribution (\(t))") }
            // the planned-time line of each week is that week's own plan: five sessions (5 h 20 min), and last week 5 h 5 min
            // because its Wednesday ride was skipped and Thursday held a 45-minute ride (owner, 24 Nov 2026)
            if i < 7 { let l = app.buttons["mixPoint-\(i)"].firstMatch.label; XCTAssertTrue(l.hasSuffix(i == 6 ? "5 h 5 min planned" : "5 h 20 min planned"), "required: week \(i)'s planned time (\(l))") }
        }
        pick(app, "mix", 6)
        let t = tip(app, "mix", at: 6, "last week")
        XCTAssertTrue(t.0.hasPrefix("4 h 52 min"), "required: last week's recorded time (\(t.0))")
        XCTAssertEqual(t.1, "Endurance 71% · Strength 29%", "required: last week's distribution, by training type")
        XCTAssertTrue(text(app, "mixSummaryLine").hasPrefix("4 h 52 min"), "required: the header follows the chosen week")
        XCTAssertTrue(text(app, "mixPlanned").contains("5 h 5 min"), "required: the planned time of that week")
        XCTAssertTrue(text(app, "mixInspectionCycling").contains("3 h 28 min recorded") && text(app, "mixInspectionCycling").contains("3 h 45 min planned"), "required: cycling recorded and planned")
        XCTAssertTrue(text(app, "mixInspectionStrength").contains("1 h 24 min recorded") && text(app, "mixInspectionStrength").contains("1 h 20 min planned"), "required: strength recorded and planned")
        let coach = el(app, "mixInsight").label
        // Changed 24 Nov 2026 on the owner's instruction: the Coach note is now a short interpretation. It no longer repeats
        // the graph's figures ("71%", the recorded and planned times) or the roster note — the rows below say which sports
        // are not recorded, and that is still asserted there.
        // Changed again 24 Nov 2026 (15:18) on the owner's instruction: the note now sets the recorded mix beside the athlete's
        // stated priorities. This athlete's running and swimming cannot be recorded, so it says the comparison cannot be made.
        XCTAssertTrue(coach.hasSuffix("Endurance made up most of your recorded training in this week. Road running and Pool swimming are not recorded, so this cannot be compared with your priorities.") && coach != first, "required: the one summary follows the chosen week, briefly (\(coach))")
        // Training balance: time and completed sessions side by side, the stated priority, what is not recorded, and the caveat
        XCTAssertEqual(el(app, "mixBalanceTime").label, "By time: Endurance 71% · Strength 29%", "required: the balance by recorded time")
        XCTAssertEqual(el(app, "mixBalanceSessions").label, "Sessions completed: Endurance 3 · Strength 2", "required: completed sessions, kept apart from time")
        XCTAssertEqual(el(app, "mixBalancePriority").label, "Your stated priority: Balanced", "required: the priority the athlete stated")
        XCTAssertEqual(el(app, "mixBalanceUnrecorded").label, "Not recorded yet: Road running, Pool swimming", "required: what the figures leave out")
        XCTAssertTrue(text(app, "mixBalanceCaveat").contains("not training load"), "required: time is not presented as load")
        // by training type: running and swimming belong to Endurance, which therefore says its figure is incomplete
        let endurance = el(app, "mixType-endurance").label
        XCTAssertTrue(endurance.contains("3 h 28 min") && endurance.contains("71%") && endurance.contains("3 sessions"), "required: the Endurance row (\(endurance))")
        XCTAssertTrue(el(app, "mixType-strength").label.contains("1 h 24 min"), "required: the Strength row")
        XCTAssertFalse(el(app, "mixSport-cycling").exists, "required: sport rows belong to the Individual sports view")
        XCTAssertNil(coach.rangeOfCharacter(from: .decimalDigits), "required: the note repeats no figure of the graph (\(coach))")
        XCTAssertFalse(coach.lowercased().contains("overtrain") || coach.lowercased().contains("ideal"), "no balance is judged")
        captureFullPage(app, "mix-1-weeks-selected", steps: 7); toTop(app)
        press(app, "mixType-endurance")
        XCTAssertTrue(text(app, "mixTypeDetailLine").contains("Road cycling, Road running and Pool swimming"), "required: the type names its activities")
        XCTAssertTrue(text(app, "mixTypeGap").contains("Road running and Pool swimming are not recorded yet"), "required: and says what its figure leaves out")
        XCTAssertTrue(el(app, "mixTypeSession-0").waitForExistence(timeout: 4), "required: and lists its sessions")
        press(app, "mixType-endurance"); toTop(app)
        pick(app, "mix", 6)
        XCTAssertFalse(app.staticTexts["mixTooltip"].exists || el(app, "mixInspection").exists, "required: pressing the chosen column again clears the selection")
        pick(app, "mix", 6); press(app, "mixViewDetails")
        XCTAssertTrue(el(app, "weekOverviewTitle").waitForExistence(timeout: 8), "required: View week opens the existing weekly overview")
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(el(app, "trainingMixDashboard").waitForExistence(timeout: 6), "required: back returns to the dashboard")

        toTop(app); app.buttons["mixMode-days"].firstMatch.tap(); Thread.sleep(forTimeInterval: 0.4)
        XCTAssertFalse(app.staticTexts["mixTooltip"].exists, "switching the view clears the selection")
        let wants: [(Int, String, String)] = [(0, "58 min", "Endurance 100%"), (1, "42 min", "Strength 100%"), (2, "No recorded training", ""), (3, "42 min", "Strength 100%"),
                                              (4, "No recorded training", ""), (5, "1 h 55 min", "Endurance 100%"), (6, "35 min", "Endurance 100%")]   // by type since 24 Nov 2026 (owner)
        for (i, a, b) in wants {
            pick(app, "mix", i)
            let d = tip(app, "mix", at: i, "day \(i)")
            XCTAssertTrue(d.0.hasPrefix(a) && d.1 == b, "required: day \(i) says \(a) / \(b) (\(d))")
            let planned = ["1 h planned", "40 min planned", "nothing planned", "1 h 25 min planned", "nothing planned", "2 h planned", "nothing planned"][i]
            let l = app.buttons["mixPoint-\(i)"].firstMatch.label
            XCTAssertTrue(l.hasSuffix(planned), "required: day \(i)'s planned-time line stands at its own planned sessions: \(planned) (\(l))")
        }
        pick(app, "mix", 3)
        XCTAssertTrue(text(app, "mixInspectionTitle").contains("Thursday"), "required: the card is Thursday's")
        XCTAssertTrue(text(app, "mixInspectionStrength").contains("42 min recorded"), "required: Thursday's strength time")
        XCTAssertTrue(text(app, "mixInspectionCycling").contains("nothing recorded") && text(app, "mixInspectionCycling").contains("45 min planned"), "required: Thursday's planned ride has nothing recorded")
        let day = el(app, "mixInsight").label
        XCTAssertTrue(day.hasSuffix("On Thursday you recorded strength only. Planned and not recorded: Endurance."), "required: the summary follows the chosen day, briefly (\(day))")
        captureFullPage(app, "mix-2-days-selected", steps: 6); toTop(app)
        press(app, "mixViewDetails")
        XCTAssertTrue(el(app, "homeDayDetail").waitForExistence(timeout: 8), "required: View Thursday opens the existing day page")
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(el(app, "trainingMixDashboard").waitForExistence(timeout: 6), "required: back returns to the dashboard")

        // Individual sports: the same graph and figures, named by sport (owner, 24 Nov 2026)
        toTop(app); app.buttons["mixMode-weeks"].firstMatch.tap(); Thread.sleep(forTimeInterval: 0.4)
        app.buttons["mixView-sports"].firstMatch.tap(); Thread.sleep(forTimeInterval: 0.4)
        pick(app, "mix", 6)
        XCTAssertEqual(tip(app, "mix", at: 6, "last week by sport").1, "Cycling 71% · Strength 29%", "required: the label names the sports in this view")
        XCTAssertTrue(text(app, "mixInspectionCycling").hasPrefix("Cycling ·"), "required: the card names the sport")
        XCTAssertFalse(el(app, "mixType-endurance").exists, "required: type rows give way to sport rows")
        XCTAssertTrue(el(app, "mixSport-cycling").label.contains("3 h 28 min"), "required: cycling row (\(el(app, "mixSport-cycling").label))")
        XCTAssertTrue(el(app, "mixSport-strength").label.contains("1 h 24 min"), "required: strength row")
        for id in ["running", "swimming"] {
            let l = el(app, "mixSport-\(id)").label
            XCTAssertTrue(l.contains("not recorded yet") && !l.contains("%"), "required: \(id) says Not recorded yet and shows no figure (\(l))")
        }
        press(app, "mixSport-cycling")
        XCTAssertTrue(text(app, "mixSportDetailLine").contains("3 h 28 min recorded"), "required: the chosen sport shows its own time")
        XCTAssertTrue(el(app, "mixSportSession-0").waitForExistence(timeout: 4), "required: and its sessions")
        toTop(app); captureFullPage(app, "mix-3-sport-expanded", steps: 8)
        press(app, "mixSportSession-0")
        XCTAssertTrue(el(app, "homeRideDetail").waitForExistence(timeout: 8), "required: a recorded session opens its existing record")
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(el(app, "trainingMixDashboard").waitForExistence(timeout: 6), "required: back returns to the dashboard")
        press(app, "mixDetailsToggle")
        XCTAssertTrue(el(app, "mixDetail-0").waitForExistence(timeout: 4) && el(app, "mixOpenOverview").exists, "required: Session details opens with the way to the existing pages")
        app.navigationBars.buttons.firstMatch.tap()
        let again = el(app, "indicatorMix")
        XCTAssertTrue(again.waitForExistence(timeout: 8), "required: back returns to Home")
        XCTAssertEqual(again.value as? String ?? "", ring, "required: the Home circle says what it said before")
    }

    /// CAPTURE ONLY (Home review item 4, 24 Nov 2026): what each day of Home's weekly calendar opens, for the owner's
    /// comparison. No app code is changed; the only requirements are that every calendar day opens its Day page and returns.
    func testCaptureHomeCalendarDays() {
        let app = launchHistory()
        captureFullPage(app, "cal-home", steps: 1); toTop(app)
        for i in 0..<7 {
            let day = app.buttons["scheduleDay-\(i)"].firstMatch
            XCTAssertTrue(day.waitForExistence(timeout: 6), "required: calendar day \(i) on Home")
            day.tap()
            XCTAssertTrue(el(app, "homeDayDetail").waitForExistence(timeout: 8), "required: calendar day \(i) opens its Day page")
            captureFullPage(app, "cal-day-\(i)", steps: 2)
            app.navigationBars.buttons.element(boundBy: 0).tap()
            XCTAssertTrue(app.buttons["scheduleDay-0"].firstMatch.waitForExistence(timeout: 8), "required: Back returns to Home from day \(i)")
        }
        // two days of last week that the current week cannot show: a skipped session (Wed) and a missed one beside a recorded one (Thu)
        _ = openConsistency(app)
        pick(app, "consistency", 6)
        app.buttons["consistencyMode-days"].firstMatch.tap(); Thread.sleep(forTimeInterval: 0.5)
        for (i, name) in [(2, "skipped"), (3, "missed")] {
            toTop(app); pick(app, "consistency", i)
            press(app, "consistencyViewDetails")
            XCTAssertTrue(el(app, "homeDayDetail").waitForExistence(timeout: 8), "required: the Day page of last week's day \(i)")
            captureFullPage(app, "cal-lastweek-\(name)", steps: 2)
            app.navigationBars.buttons.element(boundBy: 0).tap()
            XCTAssertTrue(el(app, "consistencyDashboard").waitForExistence(timeout: 8), "required: Back returns to the dashboard")
        }
    }

    /// PROPOSED Daily Training Overview (owner, 24 Nov 2026, 22:42 — not approved). Each session is set beside the most
    /// relevant earlier recorded session; the working controls of the earlier Day page are exercised again.
    func testDayOverviewProposal() {
        func back(_ app: XCUIApplication) { app.navigationBars.buttons.element(boundBy: 0).tap(); Thread.sleep(forTimeInterval: 0.6) }
        func openDay(_ app: XCUIApplication, _ i: Int) {
            toTop(app)
            let day = app.buttons["scheduleDay-\(i)"].firstMatch
            XCTAssertTrue(day.waitForExistence(timeout: 8), "required: calendar day \(i) on Home"); day.tap()
            XCTAssertTrue(el(app, "homeDayDetail").waitForExistence(timeout: 8), "required: calendar day \(i) opens its Day page")
        }
        var app = launchHistory("LAB_DEMO_DAY")
        // The demo week is built around today: today and tomorrow hold the strength sessions. The check first ran on a
        // Tuesday with Wednesday written in as "the later day"; it now takes tomorrow from the calendar (corrected 25 Nov).
        let todayIndex = (Calendar.current.component(.weekday, from: Date()) + 5) % 7
        let later = min(6, todayIndex + 1)

        // Monday: a completed planned ride beside the previous recorded endurance session, and an unplanned ride.
        // Expectations follow the presentation refined on 25 Nov 2026 (owner, 01:41): the card shows the key results and one
        // short sentence; every other figure, the zones and the reasoning are under Details, closed by default.
        openDay(app, 0)
        XCTAssertTrue(el(app, "daySession-0-planned").label.hasPrefix("Planned: 1 h"), "required: the prescription is shown as planned (\(el(app, "daySession-0-planned").label))")
        XCTAssertTrue(el(app, "daySession-0-actual").label.contains("1 h 3 min"), "required: the recording is shown separately as recorded")
        XCTAssertTrue(el(app, "daySession-0-previous").label.contains("Endurance"), "required: the previous comparable ride, with its date (\(el(app, "daySession-0-previous").label))")
        let power = el(app, "daySession-0-metric-r-power"), hr = el(app, "daySession-0-metric-r-hr")
        // Expectations follow the comparison TABLE of 25 Nov 2026 (owner, 11:26): one row per measure with Previous, Current
        // and Change; the rules and figures behind it are unchanged.
        XCTAssertTrue(power.label.contains("Previous ") && power.label.contains("Current ") && power.label.contains("Change +") && power.label.contains(" W"), "required: power shows previous, current and change, with units (\(power.label))")
        for id in ["r-duration", "r-distance", "r-cadence"] { XCTAssertTrue(el(app, "daySession-0-metric-\(id)").exists, "required: the table row \(id)") }
        XCTAssertTrue(el(app, "daySession-0-metric-r-distance").label.contains("km") && el(app, "daySession-0-metric-r-cadence").label.contains("rpm") && el(app, "daySession-0-metric-r-duration").label.contains("min"), "required: every measure carries its unit")
        let tableFrame = el(app, "daySession-0-table").frame
        XCTAssertTrue(tableFrame.minX >= 0 && tableFrame.maxX <= app.windows.firstMatch.frame.maxX, "required: the table fits the screen without sideways scrolling (\(tableFrame))")
        XCTAssertEqual(power.value as? String, "better", "required: more power at no more heart rate is the favourable direction")
        XCTAssertEqual(hr.value as? String, "same", "required: heart rate within two beats is unchanged")
        XCTAssertTrue(el(app, "daySession-0-analysis").label.hasPrefix("More power at a similar or lower heart rate than"), "required: one short sentence built from the comparison (\(el(app, "daySession-0-analysis").label))")
        // Corrected after check 74: an unplanned ride is first of all not the same planned session as the ride beside it, and
        // the card says that; the earlier expectation looked for the heart-rate sentence, which is the second reason.
        XCTAssertTrue(el(app, "daySession-1-analysis").label.hasPrefix("Not comparable with") && el(app, "daySession-1-analysis").label.contains("not the same planned session"), "required: the second ride's note says why it is not compared (\(el(app, "daySession-1-analysis").label))")
        XCTAssertEqual(el(app, "daySession-1-metric-r-power").value as? String, "notComparable", "required: an unplanned ride set beside another ride is never coloured")
        XCTAssertEqual(app.buttons["dayItem-0-action"].firstMatch.label, "View results", "required: a recorded session keeps Results")
        XCTAssertFalse(el(app, "daySession-0-metric-r-zone2").exists || el(app, "daySession-0-reasoning").exists || app.buttons["dayHistory0Point-0"].exists, "required: details and history are closed by default")
        toTop(app); captureFullPage(app, "day-3-cycling", steps: 6)
        // the drill-downs are all still there
        toTop(app); press(app, "daySession-0-detailsToggle")
        XCTAssertTrue(el(app, "daySession-0-metric-r-zone2").waitForExistence(timeout: 4), "required: time in zones opens on request")
        XCTAssertEqual(el(app, "daySession-0-metric-r-duration").value as? String, "notComparable", "required: a longer ride is not called an improvement")
        XCTAssertTrue(["notComparable", "same"].contains(el(app, "daySession-0-metric-r-cadence").value as? String ?? ""), "required: cadence is shown and never judged better or worse")
        XCTAssertTrue(el(app, "daySession-0-reasoning").label.hasPrefix("Compared with"), "required: the full reasoning is under Details")
        press(app, "daySession-0-historyToggle")
        let point = app.buttons["dayHistory0Point-0"].firstMatch
        XCTAssertTrue(point.waitForExistence(timeout: 4), "required: the history graph has selectable points"); point.tap()
        XCTAssertTrue(app.staticTexts["dayHistory0Tooltip"].waitForExistence(timeout: 4) && text(app, "dayHistory0Tooltip").contains("W"), "required: a point shows its date and measurement")
        XCTAssertTrue(el(app, "daySession-0-historyOpen").exists, "required: and leads to its session")
        toTop(app); captureFullPage(app, "day-3b-cycling-opened", steps: 9)
        // the working controls: Results opens the recorded ride and returns
        toTop(app); app.buttons["dayItem-0-action"].firstMatch.tap(); Thread.sleep(forTimeInterval: 1.2)
        shot("day-9a-results")
        if app.buttons["Done"].firstMatch.exists { app.buttons["Done"].firstMatch.tap() } else if app.buttons["Close"].firstMatch.exists { app.buttons["Close"].firstMatch.tap() } else { app.swipeDown(velocity: .fast) }
        Thread.sleep(forTimeInterval: 0.8)
        if !el(app, "homeDayDetail").exists { back(app) }
        XCTAssertTrue(el(app, "homeDayDetail").waitForExistence(timeout: 6), "required: and returns to the Day page")
        back(app)

        // Wednesday: a planned strength session before it is done — prescription and previous, no verdict
        openDay(app, later)
        XCTAssertTrue(el(app, "daySession-0-actual").label.contains("Not done yet"), "required: nothing is shown as recorded before the session is done")
        XCTAssertTrue(el(app, "daySession-0-analysis").label.contains("Not done yet") , "required: the note says there is nothing to compare yet (\(el(app, "daySession-0-analysis").label))")
        XCTAssertEqual(el(app, "daySession-0-row-0").value as? String, "notComparable", "required: no result is judged for a session that is not done")
        XCTAssertTrue(el(app, "daySession-0-row-0").label.contains("Planned") && el(app, "daySession-0-row-0").label.contains("Change —"), "required: the third column holds the prescription, and no change is stated (\(el(app, "daySession-0-row-0").label))")
        XCTAssertTrue(el(app, "daySession-0-noChanges").exists, "required: the changes say they come once the session is recorded")
        XCTAssertEqual(app.buttons["dayItem-0-action"].firstMatch.label, "View workout", "required: a session of a later day is not offered as Start")
        toTop(app); captureFullPage(app, "day-2-planned-strength", steps: 5)
        back(app)

        // a free day is not a rest day: where this week has an unscheduled day ahead, it is titled so; Sunday is a rest day
        if later < 5 {
            for i in (later + 1)..<6 {
                openDay(app, i)
                if app.staticTexts["dayEmptyTitle"].exists && text(app, "dayEmptyTitle") == "Free day" { captureFullPage(app, "day-8-free-day", steps: 2); back(app); break }
                back(app)
            }
        }
        if later < 6 {
            openDay(app, 6)
            XCTAssertEqual(text(app, "dayEmptyTitle"), "Rest day", "required: a rest day of the recurring week is a rest day")
            back(app)
        }

        // last week, through the Consistency dashboard
        _ = openConsistency(app)
        pick(app, "consistency", 6)
        app.buttons["consistencyMode-days"].firstMatch.tap(); Thread.sleep(forTimeInterval: 0.5)
        func lastWeek(_ i: Int) {
            toTop(app); pick(app, "consistency", i); press(app, "consistencyViewDetails")
            XCTAssertTrue(el(app, "homeDayDetail").waitForExistence(timeout: 8), "required: the Day page of last week's day \(i)")
        }
        // Tuesday: a completed strength session with a favourable, an unfavourable and an unchanged exercise
        lastWeek(1)
        XCTAssertEqual(el(app, "daySession-0-row-0").value as? String, "better", "required: squat — heavier at the same reps and sets")
        XCTAssertEqual(el(app, "daySession-0-row-1").value as? String, "same", "required: row — unchanged")
        XCTAssertEqual(el(app, "daySession-0-row-2").value as? String, "worse", "required: bench press — lighter at the same reps and sets")
        XCTAssertTrue(el(app, "daySession-0-row-0").label.contains("Previous 24 kg") && el(app, "daySession-0-row-0").label.contains("Current 25 kg") && el(app, "daySession-0-row-0").label.contains("Change +1 kg"), "required: top load with previous, current and change (\(el(app, "daySession-0-row-0").label))")
        let strengthTable = el(app, "daySession-0-table").frame
        XCTAssertTrue(strengthTable.minX >= 0 && strengthTable.maxX <= app.windows.firstMatch.frame.maxX, "required: the table fits the screen without sideways scrolling")
        XCTAssertTrue(el(app, "daySession-0-analysis").label.hasPrefix("Since "), "required: one short sentence (\(el(app, "daySession-0-analysis").label))")
        XCTAssertFalse(el(app, "daySession-0-exercise-0").exists, "required: the exercise comparison is closed by default")
        toTop(app); captureFullPage(app, "day-1-strength-done", steps: 6)
        // the selector: each measure with its own unit, and only what is established is coloured
        toTop(app)
        for (id, word) in [("reps", "reps"), ("sets", "sets"), ("volume", "kg")] {
            press(app, "dayMeasure0-\(id)")
            XCTAssertTrue(el(app, "daySession-0-row-0").label.contains(word), "required: \(id) is shown with its unit (\(el(app, "daySession-0-row-0").label))")
            if id == "sets" { XCTAssertEqual(el(app, "daySession-0-row-0").value as? String, "same", "required: the same number of sets is unchanged, never an improvement") }
            if id == "volume" {
                XCTAssertEqual(el(app, "daySession-0-row-2").value as? String, "worse", "required: bench press volume fell with its load")
                XCTAssertEqual(el(app, "daySession-0-row-3").value as? String, "notComparable", "required: the total is not judged when exercises moved in opposite directions")
                toTop(app); captureFullPage(app, "day-1c-strength-volume", steps: 6); toTop(app)
            }
        }
        press(app, "dayMeasure0-load")
        toTop(app); press(app, "daySession-0-detailsToggle")
        XCTAssertEqual(el(app, "daySession-0-exercise-0").value as? String, "better"); XCTAssertEqual(el(app, "daySession-0-exercise-2").value as? String, "worse")
        press(app, "daySession-0-exercise-0")
        XCTAssertTrue(el(app, "daySession-0-exercise-0-Volume").waitForExistence(timeout: 4) && el(app, "daySession-0-exercise-0-Topload").exists, "required: an exercise opens to sets, reps, load and volume")
        toTop(app); el(app, "daySession-0-previous").tap(); Thread.sleep(forTimeInterval: 1.2)
        XCTAssertFalse(el(app, "homeDayDetail").exists, "required: the previous session opens its record")
        back(app)
        XCTAssertTrue(el(app, "homeDayDetail").waitForExistence(timeout: 6), "required: and returns to the day")
        toTop(app); captureFullPage(app, "day-1b-strength-opened", steps: 9)
        back(app)
        // Thursday: two different activities — strength done, the ride missed with Move
        lastWeek(3)
        XCTAssertTrue(el(app, "daySession-0").exists && el(app, "daySession-1").exists, "required: each activity has its own card")
        XCTAssertEqual(text(app, "dayItem-1-status"), "Missed", "required: the missed ride is still marked missed")
        XCTAssertTrue(el(app, "daySession-1-actual").label.contains("missed"), "required: and shows nothing as recorded")
        XCTAssertTrue(el(app, "daySession-1-analysis").label.hasPrefix("Missed"), "required: a missed session is not described as still to do (\(el(app, "daySession-1-analysis").label))")
        captureFullPage(app, "day-4-two-activities", steps: 10)
        back(app)
        // Friday: a rest day with the health readings that exist
        lastWeek(4)
        XCTAssertTrue(el(app, "dayHealth-restingHR").label.contains("bpm") && el(app, "dayHealth-hrv").label.contains("ms"), "required: the day's stored readings, with units")
        XCTAssertTrue(text(app, "dayHealthUncollected").contains("steps, water and energy: not collected yet"), "required: measures that are not collected are named, never shown as zero")
        captureFullPage(app, "day-6-rest-health", steps: 3)
        back(app)

        // Start on a session of a LATER day: what it does today, recorded as found
        back(app)
        openDay(app, later)
        app.buttons["dayItem-0-action"].firstMatch.tap(); Thread.sleep(forTimeInterval: 2)
        // Corrected after check 72: the page opened with "Move to today" and "Skip" (seen in its screenshot), but the button
        // could not be found by that exact name; it is now looked for by the words it shows, on any kind of element.
        let words = NSPredicate(format: "label CONTAINS[c] 'Move to today'")
        XCTAssertTrue(app.descendants(matching: .any).matching(words).firstMatch.waitForExistence(timeout: 6), "required: View workout opens the session's own page, with its actions")
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS[c] 'Skip'")).firstMatch.exists, "required: Skip is still offered there")
        XCTAssertEqual(app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] 'migration'")).count, 0, "required: no internal migration text is shown to the athlete")
        shot("day-9b-view-workout")
        app.terminate()

        // every session a first: no earlier record to compare
        app = launchHistory("LAB_DEMO_DAY_FIRST")
        openDay(app, 0)
        XCTAssertTrue(el(app, "daySession-0-noPrevious").exists, "required: a first session says there is no previous record")
        XCTAssertTrue(el(app, "daySession-0-analysis").label.hasPrefix("First recorded ride of this kind"), "required: and the note compares nothing")
        XCTAssertFalse(el(app, "daySession-0-historyToggle").exists, "required: no history graph without enough records")
        captureFullPage(app, "day-5-first-ever", steps: 6)
        app.terminate()

        // the plain demo athlete has no health readings at all
        app = launchHistory("LAB_NO_SCENARIO")
        openDay(app, 1)
        XCTAssertTrue(el(app, "dayHealthEmpty").waitForExistence(timeout: 6), "required: a day without readings says so")
        XCTAssertFalse(el(app, "dayHealth-sleep").label.contains(" h"), "required: and shows no value")
        captureFullPage(app, "day-7-no-health", steps: 6)
    }

    /// CAPTURE ONLY (Home review, Key Metrics, 25 Nov 2026): what each Key metrics row on Home opens today, for the owner's
    /// comparison. No app code is changed; the only requirement is that the rows that can be found open something.
    func testCaptureHomeKeyMetrics() {
        func metricRow(_ app: XCUIApplication, _ name: String) -> XCUIElement {
            app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", name)).firstMatch
        }
        var app = launchHistory()
        for (name, file) in [("RESTING HR", "km-1-resting-hr"), ("HRV", "km-2-hrv"), ("SLEEP", "km-3-sleep")] {
            let row = metricRow(app, name)
            XCTAssertTrue(row.waitForExistence(timeout: 8), "required: the \(name) row on Home")
            for _ in 0..<12 where !row.isHittable { app.swipeUp(velocity: .slow) }
            if name == "RESTING HR" { shot("km-0-home-key-metrics") }
            row.tap()
            XCTAssertTrue(el(app, "homeRecoveryPage").waitForExistence(timeout: 8), "required: the \(name) row opens the Recovery page")
            captureFullPage(app, file, steps: 8)
            app.navigationBars.buttons.element(boundBy: 0).tap(); Thread.sleep(forTimeInterval: 0.8)
        }
        let ftp = metricRow(app, "FTP")
        if ftp.waitForExistence(timeout: 4) {
            for _ in 0..<12 where !ftp.isHittable { app.swipeUp(velocity: .slow) }
            ftp.tap(); Thread.sleep(forTimeInterval: 1.5)
            captureFullPage(app, "km-4-ftp", steps: 6)
        }
        app.terminate()
        // the plain demo athlete has no readings: the same row, the same page, empty
        app = launchHistory("LAB_NO_SCENARIO")
        let row = metricRow(app, "RESTING HR")
        if row.waitForExistence(timeout: 8) {
            for _ in 0..<12 where !row.isHittable { app.swipeUp(velocity: .slow) }
            row.tap(); Thread.sleep(forTimeInterval: 1.2)
            captureFullPage(app, "km-5-resting-hr-no-readings", steps: 2)
        }
    }

    /// CAPTURE ONLY (Home review, the Endurance card, 27 Nov 2026): what the Endurance card on Home opens today, for the
    /// owner's comparison. No app code is changed. Required: the card exists, opens the Cycling summary, the three
    /// periods can be chosen, and a recent ride opens its record. Everything else is captured as found.
    func testCaptureHomeEndurance() {
        func openCard(_ app: XCUIApplication, _ file: String) -> Bool {
            let card = el(app, "sportCard-endurance")
            guard card.waitForExistence(timeout: 8) else { shot("\(file)-home-no-card"); return false }
            for _ in 0..<8 where !card.isHittable { app.swipeUp(velocity: .slow) }
            shot("\(file)-home"); card.tap()
            return el(app, "homeCyclingSummary").waitForExistence(timeout: 8)
        }
        func back(_ app: XCUIApplication) { app.navigationBars.buttons.element(boundBy: 0).tap(); Thread.sleep(forTimeInterval: 0.8) }
        var app = launchHistory()
        XCTAssertTrue(openCard(app, "end-0"), "required: the Endurance card opens the Cycling summary")
        captureFullPage(app, "end-1-four-weeks", steps: 5)
        for (title, file) in [("This week", "end-2-this-week"), ("All", "end-3-all")] {
            toTop(app)
            let seg = el(app, "cyclingPeriod").buttons[title].firstMatch
            XCTAssertTrue(seg.waitForExistence(timeout: 6), "required: the period '\(title)'")
            seg.tap(); Thread.sleep(forTimeInterval: 0.8)
            captureFullPage(app, file, steps: 5)
        }
        toTop(app)
        let action = el(app, "cyclingNext-action")
        if action.waitForExistence(timeout: 3) {
            for _ in 0..<6 where !action.isHittable { app.swipeUp(velocity: .slow) }
            shot("end-4-next-ride-row")
            let l = action.label.lowercased()
            if action.isHittable && !l.contains("start") && !l.contains("resume") && !l.contains("continue") {
                action.tap(); Thread.sleep(forTimeInterval: 1.2); shot("end-5-next-ride-opened")
                app.swipeDown(velocity: .fast); Thread.sleep(forTimeInterval: 0.8)
                if !el(app, "homeCyclingSummary").isHittable && app.navigationBars.buttons.count > 0 { back(app) }
            }
        }
        let ride = el(app, "cyclingRide-0")
        XCTAssertTrue(ride.waitForExistence(timeout: 6), "required: a recent ride row")
        press(app, "cyclingRide-0"); Thread.sleep(forTimeInterval: 1.2)
        XCTAssertFalse(el(app, "cyclingPeriod").isHittable, "required: the recent ride opens its own page")
        captureFullPage(app, "end-6-ride-record", steps: 6)
        back(app)
        XCTAssertTrue(el(app, "homeCyclingSummary").waitForExistence(timeout: 6), "required: Back returns to the Cycling summary")
        app.terminate()
        // an athlete with nothing recorded, and a running-and-strength athlete: captured as found
        for (env, file) in [("LAB_DEMO_NO_RECORDS", "end-7-nothing-recorded"), ("LAB_DEMO_MIX_RUN_STRENGTH", "end-8-runner")] {
            app = launchHistory(env)
            if openCard(app, file) { captureFullPage(app, file, steps: 3) }
            app.terminate()
        }
    }

    /// Key Metrics hub (design direction approved 27 Nov 2026, 11:40; refinement proposed 15:26 — four swipeable
    /// carousels and a simpler "Choose four for Home"; FINAL VISUAL APPROVAL PENDING). "See all" on Home opens the hub;
    /// each category is one row of four cards that swipes sideways with a position indicator; every card opens its own
    /// page; a metric without a source shows a dash and never a figure; the athlete's Home choice changes Home and is
    /// still there after the app is reopened. The metric pages themselves are unchanged and are checked, not re-captured.
    ///
    /// Rewritten for the refinement. Two earlier expectations no longer apply and are replaced, not weakened:
    ///  · the hub's tiles were all on screen in a grid; now a card may be off to the side, so the check swipes its row first;
    ///  · "Choose four" listed every metric and greyed out those without a value; it now offers only metrics that have a
    ///    value and names the others in one line, so the check reads that line and confirms there is no row to press.
    func testKeyMetricsHub() {
        let category = ["restingHR": "heart", "hrv": "heart", "spo2": "heart", "respiratory": "heart",
                        "sleepDuration": "sleep", "sleepStages": "sleep", "dailyEnergy": "sleep", "stressSoreness": "sleep",
                        "steps": "activity", "activeCalories": "activity", "hrZones": "activity", "strength": "activity",
                        "readiness": "advanced", "strain": "advanced", "recoveryVsStrain": "advanced", "baselines": "advanced"]
        let titles = ["restingHR": "Resting heart rate", "hrv": "HRV", "spo2": "Blood oxygen (SpO₂)", "respiratory": "Respiratory rate",
                      "sleepDuration": "Sleep duration", "sleepStages": "Sleep stages", "dailyEnergy": "Daily energy", "stressSoreness": "Stress & soreness",
                      "steps": "Daily steps", "activeCalories": "Active calories", "hrZones": "Heart rate zones", "strength": "Strength progression",
                      "readiness": "Recovery readiness", "strain": "Training strain", "recoveryVsStrain": "Recovery vs. strain", "baselines": "Personal baselines"]
        let sixteen = ["restingHR", "hrv", "spo2", "respiratory", "sleepDuration", "sleepStages", "dailyEnergy", "stressSoreness",
                       "steps", "activeCalories", "hrZones", "strength", "readiness", "strain", "recoveryVsStrain", "baselines"]
        let noSource = ["spo2": "Not collected yet", "respiratory": "Not collected yet", "sleepStages": "Not collected yet", "dailyEnergy": "Needs the journal",
                        "steps": "Not collected yet", "activeCalories": "Daily total not collected yet", "hrZones": "Not collected yet",
                        "readiness": "No score is calculated", "strain": "No score is calculated", "recoveryVsStrain": "No score is calculated"]
        func back(_ app: XCUIApplication) { app.navigationBars.buttons.element(boundBy: 0).tap(); Thread.sleep(forTimeInterval: 0.8) }
        func reveal(_ app: XCUIApplication, _ e: XCUIElement) {
            let screen = app.windows.firstMatch.frame
            for _ in 0..<16 {
                let f = e.frame
                if e.exists && f.minY >= 190 && f.maxY <= screen.height - 190 { break }
                let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.015, dy: 0.5))
                from.press(forDuration: 0.05, thenDragTo: from.withOffset(CGVector(dx: 0, dy: f.minY < 190 && e.exists ? 220 : -220)), withVelocity: .slow, thenHoldForDuration: 0.2)
                Thread.sleep(forTimeInterval: 0.3)
            }
        }
        /// Swipes one category's row sideways: `left` brings later cards in.
        func swipeRow(_ app: XCUIApplication, _ cat: String, left: Bool) {
            let row = el(app, "kmCarousel-\(cat)")
            let a = row.coordinate(withNormalizedOffset: CGVector(dx: left ? 0.8 : 0.25, dy: 0.5)), b = row.coordinate(withNormalizedOffset: CGVector(dx: left ? 0.25 : 0.8, dy: 0.5))
            a.press(forDuration: 0.05, thenDragTo: b, withVelocity: .slow, thenHoldForDuration: 0.2); Thread.sleep(forTimeInterval: 0.5)
        }
        func dots(_ app: XCUIApplication, _ cat: String) -> String { el(app, "kmDots-\(cat)").value as? String ?? "" }
        func openHub(_ app: XCUIApplication, shotName: String? = nil) {
            let all = el(app, "homeMetricsSeeAll")
            XCTAssertTrue(all.waitForExistence(timeout: 8), "required: 'See all' beside Key metrics on Home")
            reveal(app, all)
            if let n = shotName { app.settleForScreenshot(1); shot(n) }
            all.tap()
            XCTAssertTrue(el(app, "keyMetricsHub").waitForExistence(timeout: 8), "required: 'See all' opens the Key Metrics hub")
            XCTAssertTrue(app.navigationBars["Key metrics"].firstMatch.waitForExistence(timeout: 4), "required: the hub is titled Key metrics")
        }
        /// Brings a card fully onto the screen — down the page, then along its row — and opens it.
        func openTile(_ app: XCUIApplication, _ id: String) {
            let cat = category[id] ?? "", tile = el(app, "kmTile-\(id)"), width = app.windows.firstMatch.frame.width
            XCTAssertTrue(tile.exists, "required: the \(id) card")
            reveal(app, el(app, "kmCarousel-\(cat)"))
            for _ in 0..<6 {
                let f = tile.frame
                if f.minX >= 0 && f.maxX <= width { break }
                swipeRow(app, cat, left: f.maxX > width)
            }
            XCTAssertTrue(tile.frame.minX >= 0 && tile.frame.maxX <= width, "required: the \(id) card can be swiped fully into view")
            tile.tap()
            XCTAssertTrue(el(app, "keyMetricPage-\(id)").waitForExistence(timeout: 8), "required: the \(id) card opens its own page")
            XCTAssertTrue(app.navigationBars[titles[id] ?? ""].firstMatch.waitForExistence(timeout: 4), "required: the page is titled \(titles[id] ?? "")")
        }

        // ---- 1. an athlete with readings and a strength history
        var app = launchHistory("LAB_DEMO_DAY")
        // the approved Home is unchanged: the Resting HR row still opens the Recovery page
        let rhrRow = el(app, "metricRow-restingHR")
        XCTAssertTrue(rhrRow.waitForExistence(timeout: 8), "required: the Resting HR row on Home")
        reveal(app, rhrRow); rhrRow.tap()
        XCTAssertTrue(el(app, "homeRecoveryPage").waitForExistence(timeout: 8), "required: the Resting HR row still opens the existing Recovery page")
        back(app)
        openHub(app, shotName: "km3-00-home")
        // four categories, exactly four cards each, each row at its first position
        for c in ["heart", "sleep", "activity", "advanced"] {
            XCTAssertTrue(el(app, "kmSection-\(c)").exists && el(app, "kmCarousel-\(c)").exists, "required: the \(c) category and its row")
            XCTAssertEqual(category.filter { $0.value == c }.keys.filter { el(app, "kmTile-\($0)").exists }.count, 4, "required: exactly four cards in \(c)")
            XCTAssertEqual(dots(app, c), "1 of 4", "required: the \(c) row starts at its first position")
        }
        for (id, why) in noSource {
            let l = el(app, "kmTile-\(id)").label
            XCTAssertTrue(l.contains("no value") && l.contains(why), "required: \(id) has no value and says why (\(l))")
        }
        for id in ["restingHR", "hrv", "sleepDuration", "strength", "baselines"] {
            XCTAssertFalse(el(app, "kmTile-\(id)").label.contains("no value"), "required: \(id) shows the athlete's own value")
        }
        XCTAssertTrue(el(app, "kmTile-restingHR").label.contains("bpm"), "required: resting heart rate with its unit")
        // about one and a half cards: the first is whole, the second is cut by the screen's edge, the third is beyond it
        let width = app.windows.firstMatch.frame.width
        let c0 = el(app, "kmTile-restingHR").frame, c1 = el(app, "kmTile-hrv").frame, c2 = el(app, "kmTile-spo2").frame
        XCTAssertTrue(c0.minX >= 0 && c0.maxX < width, "required: the first card is whole")
        XCTAssertTrue(c1.minX < width && c1.maxX > width, "required: the next card shows at the edge")
        XCTAssertTrue(c2.minX >= width, "required: the third card is off to the side")
        XCTAssertTrue(c0.height >= 44 && c0.width >= 44, "required: a card is an adequate tap target")
        XCTAssertEqual(text(app, "kmHomeList"), "Resting heart rate · HRV · Sleep duration · FTP", "required: the hub names what Home shows")
        captureFullPage(app, "km3-01-hub-start", steps: 3); toTop(app)
        // swiping a row moves only that row, and its position indicator follows
        let pageY = el(app, "kmCarousel-heart").frame.minY
        swipeRow(app, "heart", left: true)
        XCTAssertNotEqual(dots(app, "heart"), "1 of 4", "required: the position indicator moves with the row")
        XCTAssertEqual(dots(app, "sleep"), "1 of 4", "required: swiping one row leaves the others where they were")
        XCTAssertEqual(el(app, "kmCarousel-heart").frame.minY, pageY, accuracy: 2, "required: swiping sideways does not scroll the page")
        app.settleForScreenshot(1); shot("km3-02-hub-one-row-swiped")
        for c in ["heart", "sleep", "activity", "advanced"] {
            reveal(app, el(app, "kmCarousel-\(c)"))
            for _ in 0..<4 where dots(app, c) != "4 of 4" { swipeRow(app, c, left: true) }
            XCTAssertEqual(dots(app, c), "4 of 4", "required: the \(c) row reaches its last position")
        }
        XCTAssertTrue(el(app, "kmTile-respiratory").frame.maxX <= width, "required: the last card is whole at the last position")
        toTop(app); captureFullPage(app, "km3-03-hub-end", steps: 3); toTop(app)

        // all sixteen destinations; a page without a source shows a dash and no graph
        for id in sixteen {
            openTile(app, id)
            if noSource[id] != nil {
                XCTAssertEqual(text(app, "kmLatestValue"), "—", "required: \(id) shows no value")
                XCTAssertFalse(text(app, "kmUnavailableText").isEmpty, "required: \(id) says why")
                XCTAssertFalse(app.buttons["kmPoint-0"].firstMatch.exists, "required: \(id) draws no graph")
            }
            if id == "restingHR" {       // the metric pages are unchanged: one is exercised to confirm it still works
                XCTAssertTrue(text(app, "kmStanding").contains("your usual range"), "required: the reading is set against the usual range")
                pick(app, "km", 28); XCTAssertTrue(el(app, "kmInspection").waitForExistence(timeout: 4), "required: choosing a day still shows its inspection card")
                toTop(app); press(app, "kmPeriod-90"); pick(app, "km", 11)
                XCTAssertTrue(app.staticTexts["kmWeekRecord-0"].firstMatch.waitForExistence(timeout: 4), "required: a chosen week still lists its readings")
            }
            if id == "strength" { XCTAssertTrue(el(app, "kmCompare-load").waitForExistence(timeout: 4), "required: previous and current are still shown") }
            if id == "hrZones" { XCTAssertTrue(text(app, "kmUnavailableText").contains("power zones instead"), "required: power zones are never shown as heart-rate zones") }
            back(app); toTop(app)
        }

        // choose four for Home
        press(app, "kmEditHome")
        XCTAssertTrue(el(app, "keyMetricsEdit").waitForExistence(timeout: 6), "required: Edit opens the chooser")
        XCTAssertEqual(text(app, "kmEditCount"), "4 of 4 chosen")
        XCTAssertEqual(el(app, "kmSlot-3").value as? String, "FTP", "required: the four places show what is chosen")
        for id in ["restingHR", "hrv", "sleepDuration", "strength", "ftp"] { XCTAssertTrue(el(app, "kmPick-\(id)").exists, "required: \(id) has a value and is offered") }
        for id in ["spo2", "readiness", "weight", "baselines"] { XCTAssertFalse(el(app, "kmPick-\(id)").exists, "required: \(id) has no single value and is not offered") }
        XCTAssertTrue(text(app, "kmNoValue-heart").contains("Blood oxygen"), "required: metrics without a value are named, not hidden")
        XCTAssertTrue(text(app, "kmNoValue-advanced").contains("Readiness"), "required: the scores that are not calculated are named")
        XCTAssertTrue(text(app, "kmNoValue-extras").contains("Weight"), "required: Weight is named as an option without a reading")
        captureFullPage(app, "km3-04-choose-four", steps: 2); toTop(app)
        press(app, "kmPick-strength")
        XCTAssertTrue(app.staticTexts["kmEditNote"].firstMatch.waitForExistence(timeout: 4), "required: a fifth cannot be added")
        XCTAssertEqual(text(app, "kmEditCount"), "4 of 4 chosen")
        toTop(app); app.settleForScreenshot(1); shot("km3-05-choose-four-fifth-refused")
        press(app, "kmPick-ftp"); XCTAssertEqual(text(app, "kmEditCount"), "3 of 4 chosen")
        XCTAssertEqual(el(app, "kmSlot-3").value as? String, "Empty", "required: an emptied place is shown as empty")
        press(app, "kmPick-strength"); XCTAssertEqual(text(app, "kmEditCount"), "4 of 4 chosen")
        XCTAssertEqual(el(app, "kmSlot-3").value as? String, "Strength progression", "required: the new choice takes the free place")
        toTop(app); captureFullPage(app, "km3-06-choose-four-changed", steps: 2)
        back(app)
        XCTAssertEqual(text(app, "kmHomeList"), "Resting heart rate · HRV · Sleep duration · Strength progression", "required: the hub shows the new choice")
        toTop(app); app.settleForScreenshot(1); shot("km3-07-hub-after-choice")
        back(app)
        let strengthRow = el(app, "metricRow-strength")
        XCTAssertTrue(strengthRow.waitForExistence(timeout: 8), "required: Home shows the chosen metric")
        XCTAssertFalse(el(app, "metricRow-ftp").exists, "required: the metric that was unticked has left Home")
        reveal(app, strengthRow); app.settleForScreenshot(1); shot("km3-08-home-after-choice")
        strengthRow.tap()
        XCTAssertTrue(el(app, "keyMetricPage-strength").waitForExistence(timeout: 8), "required: the new Home row opens its own page")
        app.terminate()
        // the four selections persist: the same athlete, opened again WITHOUT being restored
        app = XCUIApplication(); app.launchEnvironment["LAB_THEME"] = "obsidian"; app.launchEnvironment["LAB_DEMO_DAY"] = "1"; app.launch()
        XCTAssertTrue(app.waitForHome(name: "Demo", timeout: 30), "required: Home after reopening the app")
        let kept = el(app, "metricRow-strength")
        XCTAssertTrue(kept.waitForExistence(timeout: 8), "required: the chosen metric is still on Home after reopening the app")
        XCTAssertFalse(el(app, "metricRow-ftp").exists, "required: the unticked metric is still off Home after reopening the app")
        for id in ["restingHR", "hrv", "sleep"] { XCTAssertTrue(el(app, "metricRow-\(id)").exists, "required: \(id) is still on Home after reopening the app") }
        reveal(app, kept); app.settleForScreenshot(1); shot("km3-09-home-after-reopening")
        openHub(app)
        XCTAssertEqual(text(app, "kmHomeList"), "Resting heart rate · HRV · Sleep duration · Strength progression", "required: the hub shows the same choice after reopening the app")
        press(app, "kmEditHome"); XCTAssertEqual(el(app, "kmSlot-3").value as? String, "Strength progression", "required: the chooser shows the same choice after reopening the app")
        app.terminate()

        // ---- 2. an athlete with nothing recorded: every card a dash with its reason, never zero
        app = launchHistory("LAB_DEMO_NO_RECORDS")
        openHub(app)
        XCTAssertTrue(el(app, "kmHubEmpty").exists, "required: the hub says there is nothing to show yet")
        for id in sixteen {
            let l = el(app, "kmTile-\(id)").label
            XCTAssertTrue(l.contains("no value"), "required: \(id) has no value (\(l))"); XCTAssertFalse(l.contains(", 0"), "required: \(id) is not shown as zero (\(l))")
        }
        captureFullPage(app, "km3-10-hub-nothing-recorded", steps: 3); toTop(app)
        press(app, "kmEditHome")
        XCTAssertFalse(el(app, "kmPick-strength").exists, "required: nothing without a value is offered")
        XCTAssertTrue(text(app, "kmNoValue-activity").contains("Strength"), "required: it is named as having no value yet")
        captureFullPage(app, "km3-11-choose-four-nothing-recorded", steps: 2)
    }

    /// Training Mix for three different athletes (owner, 24 Nov 2026): the page follows the roster. Each is the history
    /// athlete with a different roster; last week is chosen in each.
    func testTrainingMixAthletes() {
        // 1 — cycling and strength, endurance-led, everything recorded: the comparison with the stated priority is made
        var app = launchHistory("LAB_DEMO_MIX_HYBRID")
        _ = openCircle(app, "indicatorMix", page: "trainingMixDashboard", title: "Training Mix")
        pick(app, "mix", 6)
        XCTAssertEqual(tip(app, "mix", at: 6, "hybrid, last week").1, "Endurance 71% · Strength 29%")
        XCTAssertEqual(el(app, "mixBalancePriority").label, "Your stated priority: Endurance-led", "required: the stated priority")
        XCTAssertFalse(el(app, "mixBalanceUnrecorded").exists, "required: nothing is called unrecorded when the whole roster is recorded")
        XCTAssertTrue(el(app, "mixInsight").label.hasSuffix("Endurance made up most of your recorded training in this week. By time, that is in line with the endurance-led priority you stated."), "required: the note compares with the stated priority (\(el(app, "mixInsight").label))")
        XCTAssertEqual(el(app, "mixType-endurance").exists && el(app, "mixType-strength").exists && !el(app, "mixType-mobility").exists, true, "required: only the roster's types")
        captureFullPage(app, "mix-6-hybrid", steps: 7)
        app.terminate()

        // 2 — a runner who lifts: strength is recorded, running cannot be; no cycling anywhere; no comparison is claimed
        app = launchHistory("LAB_DEMO_MIX_RUN_STRENGTH")
        _ = openCircle(app, "indicatorMix", page: "trainingMixDashboard", title: "Training Mix")
        pick(app, "mix", 6)
        let run = tip(app, "mix", at: 6, "runner, last week")
        XCTAssertTrue(run.0.hasPrefix("1 h 24 min") && run.1 == "Strength 100%", "required: only the recorded strength time (\(run))")
        XCTAssertEqual(el(app, "mixBalanceMain").label, "Your main sport: Road running", "required: the main sport, since no lead was asked of this athlete")
        XCTAssertEqual(el(app, "mixBalanceUnrecorded").label, "Not recorded yet: Road running")
        let e = el(app, "mixType-endurance").label
        XCTAssertTrue(e.contains("not recorded yet") && !e.contains("%") && !e.contains("min"), "required: Endurance shows no figure for a runner (\(e))")
        XCTAssertFalse(app.staticTexts["mixInspectionCycling"].exists, "required: no endurance line in the card when none is recorded or planned")
        XCTAssertTrue(el(app, "mixInsight").label.hasSuffix("All of your recorded training in this week was strength. Road running is not recorded, so this cannot be compared with your priorities."), "required: the note says what cannot be compared (\(el(app, "mixInsight").label))")
        app.buttons["mixView-sports"].firstMatch.tap(); Thread.sleep(forTimeInterval: 0.4)
        XCTAssertFalse(el(app, "mixSport-cycling").exists, "required: a runner sees no cycling row")
        XCTAssertTrue(el(app, "mixSport-running").label.contains("not recorded yet"), "required: running says Not recorded yet")
        app.buttons["mixView-types"].firstMatch.tap(); Thread.sleep(forTimeInterval: 0.4)
        XCTAssertTrue(app.staticTexts["mixTooltip"].exists, "required: changing the view keeps the chosen week")
        let key = el(app, "mixLegend").label
        XCTAssertTrue(key.contains("Strength") && !key.contains("Endurance"), "required: the key names only what the graph draws (\(key))")
        captureFullPage(app, "mix-7-run-strength", steps: 7)
        app.terminate()

        // 3 — endurance only: one type, no strength anywhere, no lead to compare with
        app = launchHistory("LAB_DEMO_MIX_ENDURANCE")
        _ = openCircle(app, "indicatorMix", page: "trainingMixDashboard", title: "Training Mix")
        pick(app, "mix", 6)
        let only = tip(app, "mix", at: 6, "endurance only, last week")
        XCTAssertTrue(only.0.hasPrefix("3 h 28 min") && only.1 == "Endurance 100%", "required: all recorded time is endurance (\(only))")
        XCTAssertFalse(el(app, "mixType-strength").exists || app.staticTexts["mixInspectionStrength"].exists, "required: no strength for an athlete without it")
        XCTAssertEqual(el(app, "mixBalanceMain").label, "Your main sport: Road cycling")
        XCTAssertFalse(el(app, "mixBalancePriority").exists || el(app, "mixBalanceUnrecorded").exists, "required: no lead and nothing unrecorded")
        XCTAssertTrue(el(app, "mixInsight").label.contains("All of your recorded training in this week was endurance."), "required: the note (\(el(app, "mixInsight").label))")
        XCTAssertFalse(el(app, "mixLegend").label.contains("Strength"), "required: no Strength key for an athlete without strength")
        captureFullPage(app, "mix-8-endurance-only", steps: 6)
    }

    /// Recovery for the "Consistency history" athlete: eight weeks of demo readings of sleep, resting heart rate and HRV
    /// with regular gaps. One metric at a time on its own scale; every reading with its source; no score anywhere.
    func testRecoveryDashboard() {
        let app = launchHistory()
        let ring = openCircle(app, "indicatorRecovery", page: "recoveryDashboard", title: "Recovery")
        XCTAssertEqual(text(app, "recSummaryLine"), "Latest readings")
        XCTAssertFalse(app.staticTexts["recPeriod"].exists, "required: the header of latest readings names no chosen week")
        for k in ["sleep", "restingHR", "hrv"] {
            let l = el(app, "recSummary-\(k)").label
            XCTAssertFalse(l.contains("%"), "required: no percentage in the header (\(k))")
            XCTAssertNotNil(l.range(of: #"[A-Z][a-z]{2} \d{1,2} [A-Z][a-z]{2}"#, options: .regularExpression), "required: the latest \(k) reading is dated in the header (\(l))")
        }
        let header = el(app, "recSummary-sleep").label
        XCTAssertTrue(el(app, "recSummary-restingHR").label.contains("bpm") && el(app, "recSummary-hrv").label.contains("ms"), "required: each latest reading with its unit")
        let first = el(app, "recInsight").label
        XCTAssertTrue(first.contains("sleep"), "required: the summary is about the chosen metric (\(first))")
        for i in 0..<8 {
            pick(app, "rec", i)
            let t = tip(app, "rec", at: i, "week \(i)")
            XCTAssertTrue(t.0.hasPrefix("Avg ") && t.0.contains(" h") && t.1.isEmpty && !t.0.contains("%"), "required: week \(i) shows the average on one line (\(t))")
            anchored(app, "rec", "sleep, week \(i)")
        }
        XCTAssertEqual(el(app, "recSummary-sleep").label, header, "required: choosing a week does not change the header of latest readings")
        XCTAssertTrue(el(app, "recInspection-sleep").label.contains("of 7 nights"), "required: how many readings the average rests on is in the card")
        pick(app, "rec", 6)
        let week = el(app, "recInsight").label
        XCTAssertTrue(week.contains("averaged") && week != first, "required: the one summary follows the chosen week (\(week))")
        XCTAssertFalse(week.lowercased().contains("ready") || week.lowercased().contains("fatigue") || week.contains("%"), "no readiness, diagnosis or score")
        XCTAssertTrue(el(app, "recInspection-sleep").label.contains("average") && el(app, "recInspection-hrv").label.contains("HRV"), "required: the card lists each indicator for the period")
        captureFullPage(app, "rec-1-weeks", steps: 6); toTop(app)
        pick(app, "rec", 6)
        XCTAssertFalse(app.staticTexts["recTooltip"].exists || el(app, "recInspection").exists, "required: pressing the chosen point again clears the selection")

        pick(app, "rec", 6); app.buttons["recMode-days"].firstMatch.tap(); Thread.sleep(forTimeInterval: 0.4)
        var readings = 0, chosen = -1
        for i in 0..<7 {
            pick(app, "rec", i)
            let t = tip(app, "rec", at: i, "day \(i)")
            anchored(app, "rec", "sleep, day \(i)")
            if t.0.hasPrefix("No reading") { XCTAssertFalse(t.0.contains(" h "), "a day without a reading shows no value") }
            else { readings += 1; chosen = i; XCTAssertTrue(t.0.contains(" h") && t.1.isEmpty, "required: day \(i) shows the value and the day on one line (\(t))") }
        }
        XCTAssertGreaterThanOrEqual(readings, 5, "the demo week holds at least five sleep readings")
        // Corrected after check 62: when the last day pressed in the loop was itself a day with a reading, pressing it
        // again here cleared the selection (the approved behaviour), and the assertions below then read the week's text.
        // The app was right; the check now presses the day only when it is not already the chosen one.
        if chosen != 6 { pick(app, "rec", chosen) }
        XCTAssertTrue(el(app, "recInsight").label.contains("your recorded sleep was"), "required: the summary follows the chosen day")
        XCTAssertNotNil(el(app, "recInspection-sleep").label.range(of: #"Demo data · \d\d:\d\d"#, options: .regularExpression), "required: the card names the source and the time of the reading")
        captureFullPage(app, "rec-2-days-selected", steps: 6); toTop(app)
        // each metric on its own scale and unit
        app.buttons["recMetric-restingHR"].firstMatch.tap(); Thread.sleep(forTimeInterval: 0.4)
        XCTAssertTrue(text(app, "recGraphCaption").contains("bpm"), "required: resting heart rate is drawn in bpm")
        app.buttons["recMode-weeks"].firstMatch.tap(); Thread.sleep(forTimeInterval: 0.4)
        for i in 0..<8 { pick(app, "rec", i); _ = tip(app, "rec", at: i, "resting HR, week \(i)"); anchored(app, "rec", "resting HR, week \(i)") }
        pick(app, "rec", 5)
        XCTAssertTrue(tip(app, "rec", at: 5, "resting HR, week 5").0.contains("bpm"), "required: the label is in bpm")
        XCTAssertTrue(el(app, "recInsight").label.contains("resting heart rate"), "required: the summary follows the chosen metric")
        app.buttons["recMetric-hrv"].firstMatch.tap(); Thread.sleep(forTimeInterval: 0.4)
        XCTAssertTrue(tip(app, "rec", at: 5, "HRV, week 5").0.contains("ms"), "required: HRV is in ms")
        anchored(app, "rec", "HRV, week 5")
        for i in [0, 3, 7] { pick(app, "rec", i); _ = tip(app, "rec", at: i, "HRV, week \(i)"); anchored(app, "rec", "HRV, week \(i)") }
        pick(app, "rec", 5)
        app.buttons["recMetric-sleep"].firstMatch.tap(); Thread.sleep(forTimeInterval: 0.4)
        press(app, "recViewDetails")
        XCTAssertTrue(el(app, "homeRecoveryPage").waitForExistence(timeout: 8), "required: View recovery details opens the existing Recovery page")
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(el(app, "recoveryDashboard").waitForExistence(timeout: 6), "required: back returns to the dashboard")

        for k in ["sleep", "restingHR", "hrv"] {
            let l = el(app, "recRow-\(k)").label
            XCTAssertTrue(l.contains("latest") && l.contains("Demo data") && !l.contains("%"), "required: the \(k) row shows its latest reading and source, no score (\(l))")
            XCTAssertNotNil(l.range(of: #"your usual range · .+ from \d+ (nights|days)"#, options: .regularExpression), "required: the usual range is stated with the readings it rests on (\(l))")
        }
        press(app, "recRow-sleep")
        XCTAssertTrue(text(app, "recRowReading-0").contains("Demo data"), "required: the expanded row lists real readings with their source")
        toTop(app); captureFullPage(app, "rec-3-metric-expanded", steps: 7)
        press(app, "recOpenDetails")
        XCTAssertTrue(el(app, "homeRecoveryPage").waitForExistence(timeout: 8), "required: the row opens the existing Recovery page")
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(el(app, "recoveryDashboard").waitForExistence(timeout: 6), "required: back returns to the dashboard")
        press(app, "recDetailsToggle")
        XCTAssertTrue(text(app, "recSource-sleep").contains("source: Demo data"), "required: Readings and sources names the source")
        XCTAssertTrue(text(app, "recSourceNote").contains("no recovery score"), "required: and says no score is calculated")
        app.navigationBars.buttons.firstMatch.tap()
        let again = el(app, "indicatorRecovery")
        XCTAssertTrue(again.waitForExistence(timeout: 8), "required: back returns to Home")
        XCTAssertEqual(again.value as? String ?? "", ring, "required: the Home circle says what it said before")
        XCTAssertFalse(ring.contains("%"), "Recovery on Home shows no percentage")
    }

    /// Recovery with readings from one source for one metric only (sleep, ten days): the other two say so truthfully.
    func testRecoveryDashboardPartialData() {
        let app = launchHistory("LAB_DEMO_RECOVERY_PARTIAL")
        _ = openCircle(app, "indicatorRecovery", page: "recoveryDashboard", title: "Recovery")
        XCTAssertTrue(el(app, "recSummary-sleep").label.contains(" h"), "required: sleep has a latest reading")
        XCTAssertTrue(el(app, "recSummary-restingHR").label.contains("No reading") && el(app, "recSummary-hrv").label.contains("No reading"), "required: the other two say No reading")
        pick(app, "rec", 7)
        XCTAssertTrue(tip(app, "rec", at: 7, "this week").0.hasPrefix("Avg "), "required: this week has a sleep average")
        pick(app, "rec", 2)
        XCTAssertTrue(tip(app, "rec", at: 2, "a week before the readings begin").0.hasPrefix("No reading"), "required: a week without readings says so, never zero")
        pick(app, "rec", 7)
        captureFullPage(app, "rec-4-partial", steps: 6); toTop(app)
        app.buttons["recMetric-hrv"].firstMatch.tap(); Thread.sleep(forTimeInterval: 0.4)
        XCTAssertTrue(text(app, "recEmpty").contains("No HRV readings yet"), "required: a metric without data shows a truthful empty state")
        XCTAssertTrue(el(app, "recInsight").label.contains("There are no HRV readings yet"), "required: and the summary says so")
        XCTAssertTrue(el(app, "recRow-hrv").label.contains("Not connected"), "required: HRV is not claimed to be connected")
        let sleepRow = el(app, "recRow-sleep").label
        XCTAssertTrue(sleepRow.contains("Demo data"), "required: sleep names its one source")
        XCTAssertTrue(sleepRow.contains("No usual range yet") && !sleepRow.contains("your usual range"), "required: with too few readings no usual range is stated (\(sleepRow))")
    }

    /// An athlete with nothing recorded and no readings (a runner with goals saved and no plan): both dashboards say so,
    /// show no figure, and show no cycling or strength analysis.
    func testDashboardsWithNoData() {
        let app = launch()
        reachGoalsPage(app, roster: ["running"])
        let next = app.buttons["onboardingNext"].firstMatch
        el(app, "goal-runPace").tap()
        next.tap(); page(app, 4)
        app.chooseWeekDay(0, ["running"]); app.chooseWeekDay(3, ["running"])
        next.tap(); page(app, 7)
        app.buttons["onbCreateProfile"].firstMatch.tap(); app.openHomeFromBlueprint()
        XCTAssertTrue(el(app, "homeGreeting").waitForExistence(timeout: 20), "required: Home after Create my profile")
        _ = openCircle(app, "indicatorMix", page: "trainingMixDashboard", title: "Training Mix")
        XCTAssertEqual(text(app, "mixSummaryLine"), "No recorded training")
        XCTAssertFalse(app.staticTexts["mixDistribution"].exists || app.staticTexts["mixPlanned"].exists, "required: no distribution or plan line without records")
        // Changed 24 Nov 2026 (15:18) on the owner's instruction: the page opens by training type, so the runner's row is the
        // Endurance type (still without a figure); the sport row is checked in the Individual sports view.
        XCTAssertFalse(el(app, "mixType-strength").exists, "required: a runner sees no strength type")
        let type = el(app, "mixType-endurance").label
        XCTAssertTrue(type.contains("not recorded yet") && !type.contains("%"), "required: Endurance says Not recorded yet (\(type))")
        XCTAssertTrue(el(app, "mixBalanceEmpty").exists && el(app, "mixBalanceUnrecorded").label.contains("Road running"), "required: the balance card shows no figure and names what is not recorded")
        app.buttons["mixView-sports"].firstMatch.tap(); Thread.sleep(forTimeInterval: 0.4)
        XCTAssertFalse(el(app, "mixSport-cycling").exists || el(app, "mixSport-strength").exists, "required: a runner sees no cycling or strength row")
        let run = el(app, "mixSport-running").label
        XCTAssertTrue(run.contains("not recorded yet") && !run.contains("%"), "required: running says Not recorded yet (\(run))")
        app.buttons["mixView-types"].firstMatch.tap(); Thread.sleep(forTimeInterval: 0.4)
        pick(app, "mix", 7)
        let t = tip(app, "mix", at: 7, "this week, nothing recorded")
        XCTAssertTrue(t.0.hasPrefix("Nothing recorded yet") && t.1.isEmpty, "required: the label says nothing is recorded, no figure (\(t))")
        pick(app, "mix", 7)
        XCTAssertTrue(el(app, "mixInsight").label.hasSuffix("Nothing is recorded yet this week."), "required: the summary says so")
        XCTAssertFalse(el(app, "mixLegend").exists, "required: no key when the graph draws nothing")
        captureFullPage(app, "mix-5-no-records", steps: 4); toTop(app)
        app.navigationBars.buttons.firstMatch.tap()
        _ = openCircle(app, "indicatorRecovery", page: "recoveryDashboard", title: "Recovery")
        XCTAssertEqual(text(app, "recSummaryLine"), "No recovery measurements")
        XCTAssertTrue(text(app, "recEmpty").contains("No sleep readings yet"), "required: a truthful empty graph")
        XCTAssertTrue(el(app, "recInsight").label.contains("no recovery measurements yet"), "required: the summary says so")
        for k in ["sleep", "restingHR", "hrv"] {
            let l = el(app, "recRow-\(k)").label
            XCTAssertTrue(l.contains("Not connected") && !l.contains("%"), "required: \(k) is not claimed connected and has no figure (\(l))")
        }
        captureFullPage(app, "rec-5-no-readings", steps: 4)
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
