import XCTest

/// MAIN DEVELOPMENT CONFIGURATION (owner directive, 17 Nov 2026).
/// The MAIN Cyclift app — not Cyclift Lab — run with the redesign switched on by its simulator-only test setting, on a
/// fresh test athlete created by the test itself. Everything behind the screens is the real thing: the planner that
/// builds the first plan, the store that persists it, the Coach rules. No sensor, GPS or Apple Health is touched.
/// Every control named here is required: a missing one fails the test.
///
/// The strength journey (preparation → recorder → Finish → Saved → Review) runs here on a seeded test athlete whose
/// plan has a strength session with a routine today (the same fixture as the production strength journey).
/// NOT COVERED YET in the main app: the cycling screen (not connected to the real ride recorder; Lab only).
final class RedesignMainTests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    private func el(_ app: XCUIApplication, _ id: String) -> XCUIElement { app.descendants(matching: .any).matching(identifier: id).firstMatch }
    private func shot(_ name: String) {
        guard let dir = ProcessInfo.processInfo.environment["LAYOUT_DIR"] else { return }
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent("redesign-main-\(name).png"))
    }
    private func must(_ e: XCUIElement, _ what: String, timeout: TimeInterval = 10) { XCTAssertTrue(e.waitForExistence(timeout: timeout), "required: \(what)") }

    func testNewAthleteReachesAnApprovedPlanInTheRedesignedMainApp() {
        let app = XCUIApplication()
        app.launchEnvironment["BC_UITEST_RESET"] = "1"          // fresh, empty test store
        app.launchEnvironment["BC_UITEST_REDESIGN"] = "1"       // the redesign, in the main target
        app.launchEnvironment["BC_UITEST_THEME"] = "obsidian"   // themes are a second simulator-only setting in the main app
        app.launch()

        // this is the main app, not Lab: no Lab strip
        let start = app.buttons["onboardingContinue"].firstMatch
        must(start, "Welcome", timeout: 40)
        XCTAssertFalse(el(app, "labThemeName").exists, "the main app carries no Cyclift Lab strip")
        must(el(app, "onboardingV34"), "the seven-page onboarding (redesign is on)")
        shot("0-welcome"); start.tap()
        let next = app.buttons["onboardingNext"].firstMatch
        func page(_ n: Int) {
            let p = app.staticTexts["onboardingProgress"].firstMatch
            must(p, "progress label on page \(n)"); XCTAssertTrue(p.label.hasPrefix("\(n) of 7"), "onboarding page \(n) (\(p.label))")
        }
        page(1)
        let name = app.textFields["onbName"].firstMatch
        must(name, "name field"); name.tap(); name.typeText("Sam")
        let done = app.buttons["keyboardDone"].firstMatch; if done.waitForExistence(timeout: 3) { done.tap() }   // optional control
        must(next, "Continue"); XCTAssertTrue(next.isEnabled); next.tap()
        page(2)
        let road = app.buttons["rosterAdd-roadCycling"].firstMatch, gym = app.buttons["rosterAdd-strength"].firstMatch
        must(road, "Road cycling in the roster suggestions"); road.tap()
        must(gym, "Gym training in the roster suggestions"); gym.tap()
        must(el(app, "rosterLead"), "the lead control for two domains"); shot("2-roster")
        XCTAssertTrue(next.isEnabled); next.tap()
        page(3)
        let goal = el(app, "goal-endurance"); must(goal, "goal cards"); goal.tap()
        XCTAssertTrue(next.isEnabled); next.tap()
        page(4); must(el(app, "onbWeek"), "the week builder"); XCTAssertTrue(next.isEnabled); next.tap()
        page(5); XCTAssertFalse(app.staticTexts["onbLabDevices"].firstMatch.exists, "the main app does not show the Lab devices note"); next.tap()
        page(6); must(app.staticTexts["onbEvolutionStage"].firstMatch, "the no-stage statement"); next.tap()
        page(7)
        let identity = app.staticTexts["blueprintIdentity"].firstMatch
        must(identity, "Blueprint identity"); XCTAssertEqual(identity.label, "Road cycling + Gym training · balanced")
        shot("7-blueprint")
        let approve = app.buttons["onbCreatePlan"].firstMatch; must(approve, "Approve my plan"); approve.tap()

        // the real planner made the plan; Home and the new navigation show it
        XCTAssertTrue(app.waitForHome(name: "Sam", timeout: 25), "required: Home for the new athlete after approval")
        must(el(app, "cradleDock"), "the v1.2 dock")
        for t in ["Home", "Plan", "Progress"] { XCTAssertTrue(app.buttons[t].firstMatch.exists, "required: dock tab \(t)") }
        shot("8-home")
        app.buttons["Plan"].firstMatch.tap()
        must(app.staticTexts["planTitle"].firstMatch, "Plan v2.0"); shot("9-plan")
        XCTAssertFalse(el(app, "planSampleNote").exists, "the main app's Plan is not labelled as demo data")
        app.buttons["Progress"].firstMatch.tap()
        let track = el(app, "evolutionTrack"); must(track, "Progress hero"); XCTAssertTrue(track.label.contains("No generation yet"), "no stage is claimed (\(track.label))")
        // Train: the compact panel on the real plan
        let ball = app.buttons["centreButton"].firstMatch; must(ball, "the Train ball"); ball.tap()
        must(el(app, "trainPanel"), "the compact Train panel"); must(app.staticTexts["trainPanelTitle"].firstMatch, "the panel names today's state"); shot("10-train")
        app.buttons["Home"].firstMatch.tap()
        XCTAssertTrue(app.waitForHome(name: "Sam", timeout: 10), "required: back on Home")
        // Coach: the page opens and answers from this athlete's real record by rules
        let quiet = el(app, "homeCoachQuiet"), link = app.buttons["homeCoachOpen"].firstMatch, card = el(app, "homeCoachAction")
        // Home v2.3 (provisional design) on this athlete's real records: the prototype's sections, never the previous dashboard
        for id in ["homeV23", "indicatorConsistency", "indicatorMix", "indicatorRecovery", "scheduleDay-0", "sleepBar", "metricRow-restingHR"] { must(el(app, id), "Home v2.3: \(id)") }
        XCTAssertFalse(el(app, "cyHeroRing").exists, "the previous dashboard is not shown when the redesign is on")
        let consistency = el(app, "indicatorConsistency")
        let cv = consistency.value as? String ?? ""
        XCTAssertTrue(cv.contains("0 of") || cv.contains("Nothing planned"), "Consistency counts this athlete's own planned sessions, none done yet (\(cv))")
        XCTAssertFalse((el(app, "indicatorRecovery").value as? String ?? "").contains("%"), "Recovery shows no percentage")
        let way = link.exists ? link : (quiet.exists ? quiet : card)
        must(way, "a way into the Coach page from Home"); app.reveal(way); shot("8b-home-coach"); way.tap()
        if !app.staticTexts["coachTitle"].firstMatch.waitForExistence(timeout: 6) {
            // the card led to its own destination (allowed); the Coach page must then be reachable by its link
            let close = app.buttons["homeSheetClose"].firstMatch; if close.exists { close.tap() }
            must(link, "the Coach page link beside a card that leads elsewhere"); app.reveal(link); link.tap()
        }
        must(app.staticTexts["coachTitle"].firstMatch, "the Coach page")
        XCTAssertFalse(app.staticTexts["DEMO DATA"].firstMatch.exists, "the main app's Coach page is not labelled as demo data")
        must(app.buttons["coachTabTimeline"].firstMatch, "the Timeline | Ask selector (sheet G1)"); shot("10-coach-timeline")
        app.buttons["coachTabAsk"].firstMatch.tap()
        let ask = app.buttons["coachAsk-week"].firstMatch; must(ask, "the week question"); ask.tap()
        let answer = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'coachEntry-chat-' AND label CONTAINS 'Coach, Answer, Rules'")).firstMatch
        must(answer, "a rules-based answer from the athlete's own plan"); shot("11-coach")
        app.buttons["coachClose"].firstMatch.tap()

        // persistence: the approved athlete and plan survive a relaunch (no reset this time), still in the redesign
        app.terminate()
        let again = XCUIApplication()
        again.launchEnvironment["BC_UITEST_REDESIGN"] = "1"
        again.launchEnvironment["BC_UITEST_THEME"] = "obsidian"
        again.launch()
        XCTAssertTrue(again.waitForHome(name: "Sam", timeout: 30), "required: after a relaunch the athlete and plan are still there")
        XCTAssertFalse(again.buttons["onboardingContinue"].firstMatch.exists, "onboarding does not return")
        must(el(again, "cradleDock"), "the redesigned dock after relaunch")
        // Home navigation in the main app with the redesign on (the Lab runs 20–28 defect: the handler runs, the page never
        // appears). Required here too: the first tap on a schedule day presents that day's page — the page itself is on
        // screen and its back button can be tapped, not merely an identifier that exists somewhere.
        let day = again.buttons["scheduleDay-0"].firstMatch
        must(day, "Home v2.3 schedule day after relaunch")
        let dayOK = again.tapPresents(day, page: "homeDayDetail")
        print("REDESIGN-NOTE main app, redesign on: schedule day presented its page at the first tap: \(dayOK)")
        shot("9-home-day-after-first-tap")
        XCTAssertTrue(dayOK, "required: in the redesigned main app the first tap on a schedule day presents that day's page")
        XCTAssertTrue(again.backReveals(day), "required: back from the day page returns to Home")
        let ring = el(again, "indicatorConsistency")
        let weekOK = again.tapPresents(ring, page: "homeWeekOverview")
        print("REDESIGN-NOTE main app, redesign on: Consistency presented the week page at the first tap: \(weekOK)")
        XCTAssertTrue(weekOK, "required: in the redesigned main app the Consistency ring presents the week page")
        XCTAssertTrue(again.backReveals(ring), "required: back from the week page returns to Home")
    }

    /// With the setting absent the same build shows the existing interface: the redesign is not on by default.
    func testWithoutTheSettingTheMainAppKeepsTheExistingInterface() {
        let app = XCUIApplication()
        app.launchEnvironment["BC_UITEST_RESET"] = "1"
        app.launch()
        must(app.buttons["onboardingContinue"].firstMatch, "Welcome", timeout: 40)
        XCTAssertFalse(el(app, "onboardingV34").exists, "without the setting the existing onboarding is shown")
    }

    /// Training Hub v1.4 in the MAIN app with the redesign on: Train → preparation (01a J2) → recorder → Finish (06e) →
    /// Saved (06f) → Review (06a) → back, on the app's real store, planner and save path.
    func testStrengthSessionFromPreparationToReviewInTheRedesignedMainApp() {
        let app = XCUIApplication()
        app.launchEnvironment["BC_UITEST_SEED_JSON"] = LaunchSmokeTests.build36Store()     // a strength day with a routine assigned to today
        app.launchEnvironment["BC_UITEST_REDESIGN"] = "1"
        app.launchEnvironment["BC_UITEST_THEME"] = "obsidian"
        app.launch()
        must(el(app, "homeV23"), "Home v2.3 in the main app", timeout: 40)
        XCTAssertFalse(el(app, "labThemeName").exists, "the main app carries no Cyclift Lab strip")
        let centre = app.buttons["centreButton"].firstMatch; must(centre, "the Train ball"); centre.tap()
        let primary = app.buttons["trainPanelPrimary"].firstMatch; must(primary, "the panel offers today's session"); primary.tap()
        must(el(app, "strengthPrepareV14"), "the v1.4 preparation screen")
        let start = app.buttons["startWorkout"].firstMatch; must(start, "Start"); XCTAssertTrue(start.isHittable, "Start is on screen")
        XCTAssertTrue(el(app, "prepareOverline").label.hasPrefix("Strength · planned"), el(app, "prepareOverline").label)
        shot("s1-prepare"); start.tap()
        must(el(app, "strengthRecorderV14"), "the v1.4 recorder")
        XCTAssertFalse(el(app, "recorderName").label.contains("DEMO DATA"), "the main app does not label the athlete's session as demo data")
        let log = el(app, "logSet"), finish = app.buttons["nextSetFinish"].firstMatch
        must(log, "Log set"); shot("s2-recorder")
        var taps = 0
        while !finish.exists && taps < 60 {
            let skip = app.buttons["restSkip"].firstMatch; if skip.exists { skip.tap() }
            if log.exists { log.tap() }; taps += 1
        }
        must(finish, "Finish after the last set (\(taps) sets logged)", timeout: 5); finish.tap()
        must(el(app, "finishOverline"), "the v1.4 Finish page")      // run 296: the page container's own name is not exposed inside the recorder; its first line is
        XCTAssertEqual(el(app, "finishCount").label, "Complete"); XCTAssertTrue(el(app, "finishPlan").label.contains("Will be marked done"), el(app, "finishPlan").label)
        XCTAssertFalse(el(app, "finishOverline").label.contains("DEMO"), "no demo label in the main app")
        let save = app.buttons["saveWorkout"].firstMatch; must(save, "Save"); shot("s3-finish"); save.tap()
        must(el(app, "saveConfirmed"), "the save is confirmed")
        XCTAssertTrue(el(app, "savedPlan").label.contains("Marked done"), "the plan itself says done: \(el(app, "savedPlan").label)")
        shot("s4-saved"); app.buttons["saveReview"].firstMatch.tap()
        must(el(app, "reviewV14"), "the review")
        for v in ["reviewIntensityValue", "reviewPerformanceValue", "reviewEffortValue"] { XCTAssertEqual(el(app, v).label, "–", "\(v) starts unanswered") }
        let saveReview = app.buttons["reviewSave"].firstMatch
        XCTAssertFalse(saveReview.isEnabled, "nothing answered: nothing to save")
        app.buttons["reviewPerformancePlus"].firstMatch.tap()
        XCTAssertEqual(el(app, "reviewPerformanceValue").label, "6"); XCTAssertEqual(el(app, "reviewEffortValue").label, "–", "Effort stays unanswered")
        shot("s5-review"); XCTAssertTrue(saveReview.isEnabled); saveReview.tap()
        XCTAssertFalse(el(app, "reviewNotSaved").waitForExistence(timeout: 2), "the review was stored")
        // back in the app: the session page says it is done, and it survives a relaunch
        let done = app.buttons["Done"].firstMatch; if done.waitForExistence(timeout: 6) { done.tap() }      // the session page's own Done (optional: it may already be closed)
        must(el(app, "homeV23"), "Home again")
        app.terminate()
        app.launchEnvironment["BC_UITEST_SEED_JSON"] = nil
        app.launch()
        must(el(app, "homeV23"), "Home after relaunch", timeout: 40)
        app.buttons["centreButton"].firstMatch.tap()
        must(el(app, "trainPanel"), "the Train panel")
        let again = app.buttons["trainPanelPrimary"].firstMatch
        XCTAssertFalse(again.exists && again.label.hasPrefix("Start"), "after the relaunch today's strength session is not offered to start again (\(again.exists ? again.label : "no button"))")
        shot("s6-panel-after-relaunch")
    }
}
