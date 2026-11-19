import XCTest

/// Cyclift Lab — FAST focused checks of the Coach review (design sheet G1, screens 2 and 3), from the fixture
/// LAB_DEMO_PROPOSAL=1: the demo athlete's own records make the app's rules raise a Goblet squat increase from 25 kg.
/// Each check starts from a fresh demo athlete, opens the review the way an athlete does (Plan row → Coach page →
/// Review), makes one decision and looks at what the Coach page and the plan then say — also after the app is closed
/// and opened again. Required elements fail the check when they are absent.
final class LabFastCoach: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = true }

    private func shot(_ name: String) {
        let dir = ProcessInfo.processInfo.environment["LAYOUT_DIR"] ?? ""
        guard !dir.isEmpty else { return }
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent("fast-\(name).png"))
    }
    private func launchFresh() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["LAB_FRESH_DEMO"] = "1"
        app.launchEnvironment["LAB_DEMO_PROPOSAL"] = "1"
        app.launchEnvironment["LAB_THEME"] = "obsidian"
        app.launch()
        XCTAssertTrue(app.waitForHome(name: "Demo", timeout: 30), "required: Home with the demo athlete")
        return app
    }
    /// Closed and opened again: no fresh demo and no scenario — only what was stored.
    private func relaunch(_ app: XCUIApplication) {
        app.terminate()
        app.launchEnvironment["LAB_FRESH_DEMO"] = nil
        app.launchEnvironment["LAB_DEMO_PROPOSAL"] = nil
        app.launch()
        XCTAssertTrue(app.waitForHome(name: "Demo", timeout: 30), "required: Home after reopening")
    }
    private func tab(_ app: XCUIApplication, _ name: String) {
        let b = app.buttons[name].firstMatch
        XCTAssertTrue(b.waitForExistence(timeout: 8), "required: tab \(name)")
        if b.exists { b.tap(); app.settleForScreenshot(1) }
    }
    private func el(_ app: XCUIApplication, _ id: String) -> XCUIElement { app.descendants(matching: .any).matching(identifier: id).firstMatch }
    private func starting(_ app: XCUIApplication, _ p: String) -> XCUIElementQuery { app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", p)) }
    private func entry(_ app: XCUIApplication, _ prefix: String, containing text: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@", prefix, text)).firstMatch
    }

    /// The Coach page, through Plan's Coach row. `required` = the row must be there (an open suggestion on a fresh demo).
    /// After a decision the row may show something else or nothing; the Coach page is then opened from Home.
    private func openCoach(_ app: XCUIApplication, rowRequired: Bool) -> Bool {
        tab(app, "Plan")
        let row = el(app, "planCoachRow")
        if row.waitForExistence(timeout: rowRequired ? 8 : 3) {
            if rowRequired {
                XCTAssertTrue(row.label.hasPrefix("Coach Suggests") && row.label.contains("Goblet squat"), "required: Plan shows the open suggestion (\(row.label))")
            }
            row.tap()
        } else {
            XCTAssertFalse(rowRequired, "required: Plan shows the Coach row")
            tab(app, "Home")
            let ways = [app.buttons["homeCoachOpen"].firstMatch, el(app, "homeCoachQuiet"), el(app, "homeCoachAction")]
            guard let way = ways.first(where: { $0.exists }) else { XCTFail("required: a way to the Coach page from Plan or Home"); return false }
            _ = app.reveal(way); way.tap()
        }
        return el(app, "coachTimeline").waitForExistence(timeout: 8)
    }

    /// Review on the open suggestion → the redesigned "Review change" page with everything G1 screen 2 requires.
    /// Returns the PROPOSED value as shown (e.g. "27 kg"), or nil when the page did not open.
    private func openReview(_ app: XCUIApplication, shotName: String) -> String? {
        let review = starting(app, "coachOpen-prop-hold").firstMatch
        XCTAssertTrue(review.waitForExistence(timeout: 8), "required: the open suggestion offers Review")
        guard review.exists else { return nil }
        _ = app.reveal(review); review.tap()
        guard el(app, "coachReview").waitForExistence(timeout: 8) else { XCTFail("required: Review opens the redesigned Review change page"); return nil }
        XCTAssertEqual(el(app, "coachReviewTitle").label, "Review change")
        XCTAssertTrue(el(app, "coachReviewRules").exists, "required: the review says it is rules-based")
        XCTAssertTrue(el(app, "coachReviewRules").label.contains("not AI"), "the rules label says it is not AI (\(el(app, "coachReviewRules").label))")
        XCTAssertEqual(el(app, "coachReviewState").label, "NEEDS YOUR APPROVAL")
        XCTAssertTrue(el(app, "coachReviewSubject").label.contains("Goblet squat"), "required: the review names the exercise (\(el(app, "coachReviewSubject").label))")
        let before = el(app, "coachReviewBefore"), after = el(app, "coachReviewAfter")
        XCTAssertTrue(before.exists, "required: the NOW value"); XCTAssertTrue(after.exists, "required: the PROPOSED value")
        XCTAssertTrue(before.label.hasPrefix("Now: 25 kg"), "required: NOW is the planned 25 kg (\(before.label))")
        XCTAssertTrue(after.label.hasPrefix("Proposed: ") && after.label.contains("kg") && !after.label.hasPrefix("Proposed: 25 kg"), "required: PROPOSED is a different weight (\(after.label))")
        XCTAssertTrue(el(app, "coachReviewWhy").label.contains("Goblet squat"), "required: the rule's reason (\(el(app, "coachReviewWhy").label))")
        // evidence: the two logged sessions the rule read, and the pain line — real text, not placeholders
        let e0 = el(app, "coachReviewEvidence-0"), e1 = el(app, "coachReviewEvidence-1")
        XCTAssertTrue(e0.exists && e1.exists, "required: two evidence rows from the logged sessions")
        for e in [e0, e1] where e.exists {
            XCTAssertTrue(e.label.contains("@ 25 kg") && e.label.contains("effort"), "required: an evidence row shows the logged sets and the effort (\(e.label))")
        }
        XCTAssertTrue(el(app, "coachReviewElse").exists, "required: what else changes")
        XCTAssertTrue(el(app, "coachReviewNeedsYou").exists, "required: why it needs the athlete")
        for id in ["proposalAccept", "proposalNotNow", "proposalDecline"] {
            let b = app.buttons[id].firstMatch
            _ = app.reveal(b)
            XCTAssertTrue(b.exists, "required: the review offers \(id)")
        }
        print("LAB-NOTE coach review: \(before.label) | \(after.label) | \(e0.label) | \(e1.label)")
        app.settleForScreenshot(1); shot(shotName)
        let said = after.label.dropFirst("Proposed: ".count)
        return said.components(separatedBy: ",").first.map { String($0) }
    }

    /// (a) Not now: nothing changes, the suggestion stays open and is marked postponed — also after reopening the app.
    func testNotNowPostponesAndStaysOpen() {
        let app = launchFresh()
        guard openCoach(app, rowRequired: true) else { XCTFail("required: the Plan row opens the Coach page"); return }
        shot("coach-a1-timeline-open")
        guard openReview(app, shotName: "coach-a2-review") != nil else { return }
        app.buttons["proposalNotNow"].firstMatch.tap(); app.settleForScreenshot(1)
        XCTAssertTrue(el(app, "coachTimeline").waitForExistence(timeout: 8), "required: back on the Coach page")
        let marked = starting(app, "coachPostponed-").firstMatch
        XCTAssertTrue(marked.waitForExistence(timeout: 8), "required: Not now is acknowledged on the suggestion")
        XCTAssertTrue(marked.label.contains("stays open"), "it says the suggestion stays open (\(marked.label))")
        XCTAssertTrue(starting(app, "coachOpen-prop-hold").firstMatch.exists, "required: the postponed suggestion is still reviewable")
        XCTAssertEqual(starting(app, "coachEntry-dec-").count, 0, "Not now is neither an approval nor a rejection: no decision is recorded")
        XCTAssertEqual(starting(app, "coachUndo-").count, 0, "nothing was applied")
        _ = app.reveal(marked); shot("coach-a3-postponed")
        el(app, "coachClose").tap(); app.settleForScreenshot(1)

        relaunch(app)
        guard openCoach(app, rowRequired: false) else { XCTFail("required: the Coach page opens after reopening"); return }
        let still = starting(app, "coachPostponed-").firstMatch
        XCTAssertTrue(still.waitForExistence(timeout: 8), "required: still open and still marked postponed after reopening")
        XCTAssertTrue(starting(app, "coachOpen-prop-hold").firstMatch.exists, "required: still reviewable after reopening")
        XCTAssertEqual(starting(app, "coachEntry-dec-").count, 0, "still no decision after reopening")
        _ = app.reveal(still); shot("coach-a4-postponed-after-reopen")
        // and the review still opens with the same unchanged plan value
        XCTAssertNotNil(openReview(app, shotName: "coach-a5-review-after-reopen"))
    }

    /// (b) Approve: the timeline shows the approved change, the planned session carries the new value (read from the
    /// plan itself), Undo is offered — and all of it is still there after reopening the app.
    func testApproveShowsTheOutcomeAndThePlanCarriesIt() {
        let app = launchFresh()
        guard openCoach(app, rowRequired: true) else { XCTFail("required: the Plan row opens the Coach page"); return }
        guard let proposed = openReview(app, shotName: "coach-b1-review") else { return }
        app.buttons["proposalAccept"].firstMatch.tap(); app.settleForScreenshot(2)
        XCTAssertTrue(el(app, "coachTimeline").waitForExistence(timeout: 8), "required: back on the Coach page")
        func checkOutcome(_ step: String) {
            let approved = entry(app, "coachEntry-dec-", containing: "Approved by you")
            XCTAssertTrue(approved.waitForExistence(timeout: 8), "required (\(step)): the timeline shows the approved change")
            XCTAssertTrue(approved.label.contains("Goblet squat") && approved.label.contains("25 kg") && approved.label.contains(proposed),
                          "required (\(step)): it says what changed, from and to (\(approved.label))")
            let now = starting(app, "coachPlanNow-dec-").firstMatch
            XCTAssertTrue(now.waitForExistence(timeout: 5), "required (\(step)): the planned session's current value is shown")
            XCTAssertTrue(now.label.contains("Goblet squat") && now.label.contains("@ \(proposed)") && !now.label.contains("@ 25 kg"),
                          "required (\(step)): the planned session carries the new value \(proposed) (\(now.label))")
            XCTAssertTrue(starting(app, "coachUndo-dec-").firstMatch.exists, "required (\(step)): an applied change offers Undo")
            XCTAssertEqual(starting(app, "coachOpen-prop-hold").count, 0, "(\(step)) the decided suggestion is no longer open")
            XCTAssertEqual(starting(app, "coachNotSaved-").count, 0, "(\(step)) the change is saved")
            print("LAB-NOTE coach approve \(step): \(approved.label) | \(now.label)")
            _ = app.reveal(now)
        }
        checkOutcome("after approval"); shot("coach-b2-approved")
        el(app, "coachClose").tap(); app.settleForScreenshot(1)

        relaunch(app)
        guard openCoach(app, rowRequired: false) else { XCTFail("required: the Coach page opens after reopening"); return }
        checkOutcome("after reopening"); shot("coach-b3-approved-after-reopen")
    }

    /// (c) Decline: the timeline shows the declined decision; the plan is unchanged (no applied change, nothing to undo,
    /// no planned-value line) and the suggestion is not open any more — also after reopening.
    func testDeclineIsRecordedAndThePlanIsUnchanged() {
        let app = launchFresh()
        guard openCoach(app, rowRequired: true) else { XCTFail("required: the Plan row opens the Coach page"); return }
        guard openReview(app, shotName: "coach-c1-review") != nil else { return }
        app.buttons["proposalDecline"].firstMatch.tap(); app.settleForScreenshot(2)
        XCTAssertTrue(el(app, "coachTimeline").waitForExistence(timeout: 8), "required: back on the Coach page")
        func checkOutcome(_ step: String) {
            let declined = entry(app, "coachEntry-dec-", containing: "Declined: Goblet squat")
            XCTAssertTrue(declined.waitForExistence(timeout: 8), "required (\(step)): the timeline shows the declined suggestion")
            XCTAssertTrue(declined.label.contains("Your plan stays as it is"), "(\(step)) it says the plan is unchanged (\(declined.label))")
            XCTAssertEqual(entry(app, "coachEntry-dec-", containing: "Approved by you").exists, false, "(\(step)) nothing was approved")
            XCTAssertEqual(entry(app, "coachEntry-adj-", containing: "Goblet squat").exists, false, "required (\(step)): no Goblet squat change is in force in the plan")
            XCTAssertEqual(starting(app, "coachPlanNow-").count, 0, "(\(step)) no changed planned value")
            XCTAssertEqual(starting(app, "coachUndo-").count, 0, "(\(step)) nothing to undo")
            XCTAssertEqual(starting(app, "coachOpen-prop-hold").count, 0, "(\(step)) the declined suggestion is no longer open")
            _ = app.reveal(declined)
        }
        checkOutcome("after declining"); shot("coach-c2-declined")
        el(app, "coachClose").tap(); app.settleForScreenshot(1)

        relaunch(app)
        guard openCoach(app, rowRequired: false) else { XCTFail("required: the Coach page opens after reopening"); return }
        checkOutcome("after reopening"); shot("coach-c3-declined-after-reopen")
    }
}
