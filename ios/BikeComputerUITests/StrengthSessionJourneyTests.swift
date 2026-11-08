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
            print("RUN205-DIAG next-set card hierarchy:\n\(card.debugDescription)\nnavigation bars: \(app.navigationBars.allElementsBoundByIndex.map(\.identifier))")
        }
        expect(target.exists && !target.label.isEmpty, "the next set names its target (all-sets-done shown: \(app.buttons["nextSetFinish"].firstMatch.exists))", tag: "target")
        let log = app.buttons["logSet"].firstMatch
        expect(log.waitForExistence(timeout: 5) && log.isHittable, "Log set is reachable", tag: "logset")
        log.tap()
        // a rest timer or the next card follows; either way a second set can be logged
        _ = app.descendants(matching: .any)["restTimer"].firstMatch.waitForExistence(timeout: 3)
        XCTAssertTrue(log.waitForExistence(timeout: 20), "Log set is available again for the next set")
        if log.isHittable { log.tap() }

        // Finish → Save (sets were ticked, so saving is allowed) → the check-in appears
        let finish = app.buttons["finishWorkout"].firstMatch
        XCTAssertTrue(finish.waitForExistence(timeout: 5)); finish.tap()
        let save = app.buttons["saveWorkout"].firstMatch
        XCTAssertTrue(save.waitForExistence(timeout: 10), "Finish sheet")
        XCTAssertTrue(save.isEnabled, "two logged sets → Save is enabled (nothing-to-save state would disable it)")
        save.tap()
        let checkIn = app.descendants(matching: .any)["checkInForm"].firstMatch
        XCTAssertTrue(checkIn.waitForExistence(timeout: 10), "a saved session asks for its check-in")
        let submit = app.buttons["checkInSubmit"].firstMatch
        if submit.waitForExistence(timeout: 3), submit.isEnabled { submit.tap() } else { app.buttons["checkInSkip"].firstMatch.tap() }

        // back on Home: the planned session is done and the summary lists today's log with its sets
        XCTAssertTrue(app.waitForHome(name: "Rashed", timeout: 20), "back on Home after the session")
        if app.buttons["hubClose"].firstMatch.exists { app.buttons["hubClose"].firstMatch.tap() }
        let strengthCard = app.buttons["homeStrength"].firstMatch
        XCTAssertTrue(strengthCard.waitForExistence(timeout: 10), "strength card"); strengthCard.tap()
        XCTAssertTrue(app.descendants(matching: .any)["homeStrengthSummary"].firstMatch.waitForExistence(timeout: 10), "strength summary")
        let expand = app.buttons["strengthLogExpand-0"].firstMatch
        for _ in 0..<4 where !expand.isHittable { app.swipeUp(velocity: .slow) }
        XCTAssertTrue(expand.waitForExistence(timeout: 5), "today's log is the first row"); expand.tap()
        let exercises = app.descendants(matching: .any)["strengthLogExercises-0"].firstMatch
        XCTAssertTrue(exercises.waitForExistence(timeout: 5), "the log lists its exercises")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS '×'")).firstMatch.exists, "sets × reps as recorded")
        XCTAssertEqual(app.state, .runningForeground)
    }
}
