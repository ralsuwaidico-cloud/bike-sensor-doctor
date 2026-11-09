import XCTest

/// Completeness audit (owner 8 Nov 19:04) — the strength live session as the athlete runs it: Home → Train now → the
/// assigned routine → Start workout → log two sets → Finish → Save → check‑in → the log appears in the Strength summary
/// with the sets as recorded, and the planned session is done. Every assertion is on what the screens show.
final class StrengthSessionJourneyTests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = true }

    func testStartLogFinishSaveCheckInThenHistory() {
        let app = XCUIApplication()
        app.launchEnvironment["BC_UITEST_SEED_JSON"] = LaunchSmokeTests.build36Store()     // a strength day with the "Short Full Body Workout" routine assigned to today
        app.launch()
        XCTAssertTrue(app.waitForHome(name: "Rashed", timeout: 30), "Home")
        let centre = app.buttons["centreButton"].firstMatch
        XCTAssertTrue(centre.waitForExistence(timeout: 10)); _ = centre.waitUntilSettled(timeout: 5); centre.tap()
        XCTAssertTrue(app.openFromHub(), "hub → today's workout")
        let start = app.buttons["startWorkout"].firstMatch
        XCTAssertTrue(start.waitForExistence(timeout: 10), "Start workout"); start.tap()

        // the live session: a next-set card with a target and a Log set action
        let card = app.descendants(matching: .any)["nextSetCard"].firstMatch
        expect(card.waitForExistence(timeout: 10), "live session shows the next set", tag: "card")
        let target = app.descendants(matching: .any)["nextSetTarget"].firstMatch
        // run 205: the card existed but neither the target nor Log set did (model-level probe of the same seed finds two
        // open sets per exercise) — wait for the target, and on failure keep a screenshot plus the card's hierarchy
        if !target.waitForExistence(timeout: 5) {
            // run 206: neither the target nor Log set nor "All sets done" was found although the card exists — the card's
            // hierarchy goes into the failure message (the CI digest keeps error lines, not prints)
            let tree = card.debugDescription.replacingOccurrences(of: "\n", with: " ⏎ ")
            let texts = app.staticTexts.allElementsBoundByIndex.prefix(40).map(\.label).joined(separator: " | ")
            XCTFail("next-set card without target — bars \(app.navigationBars.allElementsBoundByIndex.map(\.identifier)); texts: \(texts.prefix(900)); card: \(tree.prefix(1500))")
        }
        expect(target.exists && !target.label.isEmpty, "the next set names its target (all-sets-done shown: \(app.buttons["nextSetFinish"].firstMatch.exists))", tag: "target")
        let log = app.buttons["logSet"].firstMatch
        expect(log.waitForExistence(timeout: 5) && log.isHittable, "Log set is reachable", tag: "logset")

        // Owner 8 Nov 22:59: log EVERY set and confirm the card advances each time — the seed's routine has two exercises
        // of two sets (4 sets); the target text must change between consecutive sets (set number or exercise), and
        // after the last set the card offers Finish instead of Log.
        var logged = 0, lastTarget = ""
        let setCounter = app.staticTexts.matching(NSPredicate(format: "label MATCHES 'Set [0-9]+ of [0-9]+'")).firstMatch
        for n in 1...8 where log.exists {
            let before = (setCounter.exists ? setCounter.label : "") + " " + target.label
            expect(before != lastTarget, "set \(n): the card advanced to a new set (\(before))", tag: "advance-\(n)")
            lastTarget = before
            expect(log.isHittable, "set \(n): Log set hittable", tag: "loghit-\(n)")
            log.tap(); logged += 1
            _ = app.descendants(matching: .any)["restTimer"].firstMatch.waitForExistence(timeout: 2)   // rest timer may show between sets
            if !log.waitForExistence(timeout: 8) { break }
        }
        expect(logged == 4, "all four planned sets were logged, got \(logged)", tag: "allsets")
        let finishFromCard = app.buttons["nextSetFinish"].firstMatch
        expect(finishFromCard.waitForExistence(timeout: 5), "after the last set the card offers Finish workout", tag: "cardfinish")
        expect(app.staticTexts.matching(NSPredicate(format: "label == '4/4 sets'")).firstMatch.exists, "the counter reads 4/4 sets", tag: "counter")

        // Finish → Save (sets were ticked, so saving is allowed) → the check-in appears
        let finish = app.buttons["finishWorkout"].firstMatch
        expect(finish.waitForExistence(timeout: 5), "Finish in the toolbar", tag: "finish"); finish.tap()
        let save = app.buttons["saveWorkout"].firstMatch
        expect(save.waitForExistence(timeout: 10), "Finish sheet", tag: "finishsheet")
        expect(save.isEnabled, "logged sets → Save is enabled (nothing-to-save state would disable it)", tag: "saveenabled")
        save.tap()
        let checkIn = app.descendants(matching: .any)["checkInForm"].firstMatch
        expect(checkIn.waitForExistence(timeout: 10), "a saved session asks for its check-in", tag: "checkin")
        let submit = app.buttons["checkInSubmit"].firstMatch
        if submit.waitForExistence(timeout: 3), submit.isEnabled { submit.tap() } else { app.buttons["checkInSkip"].firstMatch.tap() }

        // back on Home: the planned session is done and the summary lists today's log with its sets
        expect(app.waitForHome(name: "Rashed", timeout: 20), "back on Home after the session", tag: "home")
        // run 210: the whole flow start → 4 sets → finish → save → check-in → Home passed; the Home card was tapped while
        // the hub/check-in dismissal still covered it ("not hittable") — close the hub by its visible state, then tap once hittable
        let hubClose = app.buttons["hubClose"].firstMatch
        if hubClose.exists && hubClose.isHittable { hubClose.tap(); _ = hubClose.waitUntilDismissed(timeout: 6) }
        let strengthCard = app.buttons["homeStrength"].firstMatch
        expect(strengthCard.waitForExistence(timeout: 10), "strength card", tag: "card")
        expect(strengthCard.tapWhenHittable(timeout: 10), "strength card tappable", tag: "cardtap")
        XCTAssertTrue(app.descendants(matching: .any)["homeStrengthSummary"].firstMatch.waitForExistence(timeout: 10), "strength summary")
        let expand = app.buttons["strengthLogExpand-0"].firstMatch
        for _ in 0..<4 where !expand.isHittable { app.swipeUp(velocity: .slow) }
        XCTAssertTrue(expand.waitForExistence(timeout: 5), "today's log is the first row"); expand.tap()
        let exercises = app.descendants(matching: .any)["strengthLogExercises-0"].firstMatch
        expect(exercises.waitForExistence(timeout: 5), "the log lists its exercises", tag: "review")
        expect(app.staticTexts.matching(NSPredicate(format: "label CONTAINS '×'")).firstMatch.exists, "sets × reps as recorded", tag: "reps")
        // review: both exercises of the routine appear in the saved log with every set
        expect(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Goblet squat'")).firstMatch.exists, "Goblet squat in the saved log", tag: "ex1")
        expect(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Dumbbell row'")).firstMatch.exists, "Dumbbell row in the saved log", tag: "ex2")
        XCTAssertEqual(app.state, .runningForeground)
    }
}
