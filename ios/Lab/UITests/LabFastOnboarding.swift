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
        XCTAssertTrue(text.contains("Your running goals are saved") && text.contains("coming soon"), "required: saved, plans coming soon (\(text))")
        for word in ["Zone", "reps", "interval", " km", "FTP", "nsupported", "not supported", "not implemented", "navailable"] {
            XCTAssertFalse(text.contains(word), "required: no prescription and no technical wording ('\(word)') in: \(text)")
        }
        XCTAssertTrue(next.isEnabled, "required: a runner is not blocked on the Goals page")
        app.settleForScreenshot(1); shot("onb-3-goals-runner")

        // straight to a Blueprint that says what is saved; nothing about a week or a session
        next.tap(); page(app, 7)
        let create = app.buttons["onbCreateProfile"].firstMatch
        XCTAssertTrue(create.waitForExistence(timeout: 8), "required: Create my profile")
        XCTAssertFalse(app.buttons["onbCreatePlan"].firstMatch.exists, "required: there is no plan to approve")
        XCTAssertEqual(app.staticTexts["onbTitle"].firstMatch.label, "Sam"); XCTAssertEqual(app.staticTexts["blueprintIdentity"].firstMatch.label, "Runner")
        XCTAssertTrue(need(app, "blueprintSport-running", "running on the Blueprint").label.contains("plans coming soon"), "required: the sport's status is stated")
        XCTAssertTrue(need(app, "blueprintGoal-runPace", "the main goal on the Blueprint").label.contains("main goal"))
        need(app, "blueprintGoal-runDistance", "the other goal on the Blueprint")
        XCTAssertTrue(need(app, "blueprintNoPlan", "the no-plan statement").label.contains("No training plan is created"), "required: the Blueprint says no plan is created")
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] 'First session' OR label CONTAINS[c] 'rides ·' OR label CONTAINS[c] 'sessions a week'")).firstMatch.exists, "required: no week or session on this Blueprint")
        for i in 4...6 { XCTAssertFalse(app.buttons["railSlot-\(i)"].firstMatch.isEnabled, "required: page \(i) is not offered to an athlete without a plan") }
        app.settleForScreenshot(1); shot("onb-7-blueprint-profile-only")
        app.buttons["onboardingBack"].firstMatch.tap(); page(app, 3)
        XCTAssertEqual(mainGoalTitle(app), "PACE · MAIN GOAL", "required: Back returns to Goals with the selection kept")
        next.tap(); page(app, 7)

        // into Cyclift without a plan
        create.tap()
        let greeting = el(app, "homeGreeting")
        XCTAssertTrue(greeting.waitForExistence(timeout: 20), "required: Home opens after Create my profile")
        XCTAssertTrue(greeting.label.contains("Sam"), "required: Home greets the athlete (\(greeting.label))")
        app.settleForScreenshot(2); shot("profile-only-1-home")
        let dock = el(app, "cradleDock")
        dock.buttons["Plan"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["planTitle"].firstMatch.waitForExistence(timeout: 10), "required: the Plan screen opens")
        app.settleForScreenshot(2); shot("profile-only-2-plan")
        app.buttons["centreButton"].firstMatch.tap()
        let panel = need(app, "trainPanel", "the Train panel")
        let said = app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] 'no plan'")).firstMatch
        XCTAssertTrue(said.waitForExistence(timeout: 6), "required: Train says there is no plan (nothing is offered as today's session)")
        _ = panel
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
        next.tap(); page(app, 7)
        XCTAssertTrue(app.buttons["onbCreateProfile"].firstMatch.waitForExistence(timeout: 8), "required: without a cycling goal no cycling plan is built")
        XCTAssertTrue(need(app, "blueprintSport-roadCycling", "road cycling on the Blueprint").label.contains("work today"), "required: the Blueprint says cycling planning and recording work")
        XCTAssertTrue(need(app, "blueprintSport-running", "running on the Blueprint").label.contains("plans coming soon"))
        app.settleForScreenshot(1); shot("onb-7-blueprint-mixed-profile-only")
        tap(app, app.buttons["blueprintEditGoals"].firstMatch, "Change goals")
        page(app, 3)
        el(app, "goal-endurance").tap()
        XCTAssertEqual(mainGoalTitle(app), "PACE · MAIN GOAL", "required: the chosen cycling goal does not take the main goal away")
        XCTAssertTrue(goalText(app).contains("Your plan today follows Endurance"), "required: the page says what the plan follows (\(goalText(app)))")
        app.settleForScreenshot(1); shot("onb-3-goals-runner-plus-cycling")
        let back = app.buttons["onbBackToBlueprint"].firstMatch
        XCTAssertTrue(back.waitForExistence(timeout: 6) && back.isEnabled, "required: the way back from the edit"); back.tap()
        page(app, 4)        // a plan is now possible and its week has never been shown: it is shown before any Blueprint
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
        // Owner decision 20 Nov 2026 (23:04): the identity is derived from the selected sports — "Cycling/Strength hybrid" — where it used to list the two activity names.
        XCTAssertTrue(identity.exists && identity.label == "Cycling/Strength hybrid · balanced", "required: the roster line (\(identity.label))")
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
