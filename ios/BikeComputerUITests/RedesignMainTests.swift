import XCTest

/// MAIN DEVELOPMENT CONFIGURATION (owner directive, 17 Nov 2026).
/// The MAIN Cyclift app — not Cyclift Lab — run with the redesign switched on by its simulator-only test setting, on a
/// fresh test athlete created by the test itself. Everything behind the screens is the real thing: the planner that
/// builds the first plan, the store that persists it, the Coach rules. No sensor, GPS or Apple Health is touched.
/// Every control named here is required: a missing one fails the test.
///
/// NOT COVERED YET in the main app: recording a strength session with the new recorder (the first planned session of
/// a new athlete falls on a day the test cannot choose), the review, and the cycling screen (not connected to the real
/// ride recorder). Those are proven in Cyclift Lab only.
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
        var n = 0; while !(quiet.exists || link.exists || card.exists) && n < 4 { app.swipeUp(); n += 1 }
        let way = link.exists ? link : (quiet.exists ? quiet : card)
        must(way, "a way into the Coach page from Home"); if !way.isHittable { app.swipeUp() }; way.tap()
        if !app.staticTexts["coachTitle"].firstMatch.waitForExistence(timeout: 6) {
            // the card led to its own destination (allowed); the Coach page must then be reachable by its link
            let close = app.buttons["homeSheetClose"].firstMatch; if close.exists { close.tap() }
            must(link, "the Coach page link beside a card that leads elsewhere"); link.tap()
        }
        must(app.staticTexts["coachTitle"].firstMatch, "the Coach page")
        XCTAssertFalse(app.staticTexts["DEMO DATA"].firstMatch.exists, "the main app's Coach page is not labelled as demo data")
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
    }

    /// With the setting absent the same build shows the existing interface: the redesign is not on by default.
    func testWithoutTheSettingTheMainAppKeepsTheExistingInterface() {
        let app = XCUIApplication()
        app.launchEnvironment["BC_UITEST_RESET"] = "1"
        app.launch()
        must(app.buttons["onboardingContinue"].firstMatch, "Welcome", timeout: 40)
        XCTAssertFalse(el(app, "onboardingV34").exists, "without the setting the existing onboarding is shown")
    }
}
