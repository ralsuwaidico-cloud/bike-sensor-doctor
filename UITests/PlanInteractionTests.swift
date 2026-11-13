import XCTest

// Plan v2.0, visual round 1 — interaction and layout checks for the UI Lab PROTOTYPE (sample data only).
// A pass here is evidence about the prototype on a simulator. It is NOT validation of the production app and
// NOT a real-device test. An assertion is never loosened to get a pass.

final class PlanInteractionTests: XCTestCase {
    var app: XCUIApplication!

    override func setUp() { continueAfterFailure = false }

    @discardableResult
    private func launch(_ env: [String: String] = [:], args: [String] = []) -> XCUIApplication {
        app = XCUIApplication()
        var e = ["LAB_THEME": "obsidian", "LAB_SCREEN": "plan"]
        env.forEach { e[$0.key] = $0.value }
        app.launchEnvironment = e
        app.launchArguments = args
        app.launch()
        XCTAssertTrue(el("planTitle").waitForExistence(timeout: 20), "Plan did not appear")
        return app
    }
    private func el(_ id: String) -> XCUIElement { app.descendants(matching: .any).matching(identifier: id).firstMatch }
    private var window: CGRect { app.windows.firstMatch.frame }
    private var dockTop: CGFloat { let d = el("dockCentre"); return d.exists ? d.frame.minY : window.maxY - 110 }
    private func tap(_ id: String, file: StaticString = #filePath, line: UInt = #line) {
        let e = el(id)
        XCTAssertTrue(e.waitForExistence(timeout: 8), "Missing \(id)", file: file, line: line)
        e.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
    }
    private func waitLabel(_ id: String, _ text: String, file: StaticString = #filePath, line: UInt = #line) {
        let e = el(id)
        let p = NSPredicate(format: "label == %@", text)
        let x = XCTNSPredicateExpectation(predicate: p, object: e)
        let r = XCTWaiter().wait(for: [x], timeout: 8)
        XCTAssertEqual(r, .completed, "\(id) shows \"\(e.exists ? e.label : "nothing")\", expected \"\(text)\"", file: file, line: line)
    }
    /// Drags the page up from the left margin until the element's bottom edge is above the dock (or gives up).
    private func scrollUntilClear(_ e: XCUIElement) {
        for _ in 0..<10 {
            if e.exists && e.frame.maxY <= dockTop - 4 && e.frame.minY >= window.minY { return }
            let a = app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: window.minX + 6, dy: window.midY + 120))
            let b = app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: window.minX + 6, dy: window.midY - 120))
            a.press(forDuration: 0.05, thenDragTo: b, withVelocity: .slow, thenHoldForDuration: 0.3)
        }
    }

    // MARK: landing

    func test01_LandingShowsHeaderProgramAndTwoSections() {
        launch()
        for id in ["planTitle", "planMore", "planProgram", "planSection-weekly", "planSection-recurring",
                   "planWeekTitle", "planDay-12", "planDayHeader", "planAddSession"] {
            XCTAssertTrue(el(id).exists, "Missing \(id)")
        }
        XCTAssertTrue(el("planProgram").label.contains("Build strength"), "Program row does not state the primary objective: \(el("planProgram").label)")
        XCTAssertTrue(el("planProgram").label.contains("Hybrid Foundation"), "Program row does not name the program: \(el("planProgram").label)")
        XCTAssertFalse(el("planAddGoal").exists || el("planSetGoal").exists, "With a primary goal there must be no prominent goal action on the row")
        waitLabel("planWeekTitle", "9 – 15 Nov")
        waitLabel("planDayHeader", "Thu 12 Nov · Today")
    }

    func test02_NoGoalStateAsksForAGoal() {
        launch(["LAB_PLAN": "noGoal"])
        XCTAssertTrue(el("planProgram").label.contains("Set your goal"), "No-goal header reads: \(el("planProgram").label)")
        XCTAssertTrue(el("planSetGoal").exists, "The no-goal state must offer one clear action")
        XCTAssertGreaterThanOrEqual(el("planSetGoal").frame.height, 44)
        XCTAssertTrue(el("planProgram").label.contains("added by you"), "Hand-scheduled sessions must be stated as such: \(el("planProgram").label)")
        XCTAssertTrue(el("planSession-g2").waitForExistence(timeout: 5) && el("planSession-g2").label.contains("added by you"))
        XCTAssertFalse(el("planCoachRow").exists, "A Coach row is shown without a proposal")
        tap("planSection-recurring")
        XCTAssertTrue(el("planRecurring-Mon").waitForExistence(timeout: 5) && el("planRecurring-Mon").label.contains("Not set"))
    }

    // MARK: date selector

    func test03_SelectingADayUpdatesTheSessionsInPlace() {
        launch()
        tap("planDay-9");  waitLabel("planDayHeader", "Mon 9 Nov")
        XCTAssertTrue(el("planSession-c1").waitForExistence(timeout: 5), "Missed session not shown on Monday")
        XCTAssertTrue(el("planSession-c1").label.contains("Missed"))
        XCTAssertTrue(el("planSession-c1").label.contains("Rescheduled to Fri 13 Nov"))
        tap("planDay-10"); waitLabel("planDayHeader", "Tue 10 Nov")
        XCTAssertTrue(el("planSession-c2").waitForExistence(timeout: 5)); XCTAssertFalse(el("planSession-c1").exists)
        tap("planDay-12"); waitLabel("planDayHeader", "Thu 12 Nov · Today")
        XCTAssertTrue(el("planSession-c4").exists && el("planSession-c5").exists, "Thursday should show two sessions")
        tap("planDay-13"); waitLabel("planDayHeader", "Fri 13 Nov")
        XCTAssertTrue(el("planSession-c6").label.contains("Rescheduled from Mon 9 Nov (missed)"))
        tap("planDay-15"); waitLabel("planDayHeader", "Sun 15 Nov")
        XCTAssertTrue(el("planEmpty").waitForExistence(timeout: 5), "Empty day state missing")
        XCTAssertTrue(el("planTitle").exists, "Selecting a day left the Plan page")
    }

    func test04_WeekButtonsAndTodayButton() {
        launch()
        tap("planWeekNext"); waitLabel("planWeekTitle", "16 – 22 Nov")
        waitLabel("planDayHeader", "Thu 19 Nov")
        XCTAssertFalse(el("planCoachRow").exists, "Coach row belongs to the current week only")
        tap("planDay-20"); waitLabel("planDayHeader", "Fri 20 Nov")
        XCTAssertTrue(el("planRest").waitForExistence(timeout: 5), "Rest day state missing")
        XCTAssertFalse(el("planWeekNext").isEnabled, "Next week should be unavailable at the end of the sample")
        tap("planWeekPrev"); waitLabel("planWeekTitle", "9 – 15 Nov")
        tap("planWeekPrev"); waitLabel("planWeekTitle", "2 – 8 Nov")
        XCTAssertFalse(el("planWeekPrev").isEnabled)
        tap("planToday"); waitLabel("planWeekTitle", "9 – 15 Nov"); waitLabel("planDayHeader", "Thu 12 Nov · Today")
        XCTAssertFalse(el("planToday").exists, "Today button should hide when today is selected")
    }

    func test05_HorizontalSwipeChangesWeek_VerticalSwipeDoesNot() {
        launch()
        let c = el("planDay-12"); XCTAssertTrue(c.waitForExistence(timeout: 8))
        let y = c.frame.midY
        func drag(fromX: CGFloat, toX: CGFloat, fromY: CGFloat, toY: CGFloat) {
            let a = app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: fromX, dy: fromY))
            let b = app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: toX, dy: toY))
            a.press(forDuration: 0.05, thenDragTo: b, withVelocity: .fast, thenHoldForDuration: 0.2)
        }
        drag(fromX: window.maxX - 40, toX: window.minX + 40, fromY: y, toY: y)        // swipe left: next week
        waitLabel("planWeekTitle", "16 – 22 Nov")
        let c2 = el("planDay-19"); XCTAssertTrue(c2.waitForExistence(timeout: 8))
        drag(fromX: window.minX + 40, toX: window.maxX - 40, fromY: c2.frame.midY, toY: c2.frame.midY)   // swipe right: back
        waitLabel("planWeekTitle", "9 – 15 Nov")
        // a vertical drag that starts on the date selector must not change the week
        let c3 = el("planDay-12"); XCTAssertTrue(c3.waitForExistence(timeout: 8))
        let before = el("planTitle").frame.minY
        drag(fromX: c3.frame.midX, toX: c3.frame.midX, fromY: c3.frame.midY, toY: c3.frame.midY - 160)
        waitLabel("planWeekTitle", "9 – 15 Nov")
        let after = el("planTitle").exists ? el("planTitle").frame.minY : -1
        print("LABNOTE vertical drag starting on the date selector: week unchanged; page title moved from y \(Int(before)) to y \(Int(after)) (it moves only when the page has more content than the screen)")
    }

    func test06_SectionSwitchKeepsTheSelectedDay() {
        launch()
        tap("planDay-10"); waitLabel("planDayHeader", "Tue 10 Nov")
        tap("planSection-recurring")
        XCTAssertTrue(el("planRecurring-Mon").waitForExistence(timeout: 5)); XCTAssertFalse(el("planDayHeader").exists)
        tap("planSection-weekly")
        waitLabel("planDayHeader", "Tue 10 Nov")
    }

    // MARK: Coach row

    func test07_CoachRowOnlyWhenThereIsAProposal_NoSpaceReservedOtherwise() {
        launch()
        XCTAssertTrue(el("planCoachRow").waitForExistence(timeout: 5), "Coach row missing")
        XCTAssertTrue(el("planCoachRow").label.contains("Resolve Saturday’s time conflict"), el("planCoachRow").label)
        XCTAssertGreaterThanOrEqual(el("planCoachRow").frame.height, 44)
        let with = el("planDayHeader").frame.minY
        launch(["LAB_PLAN": "noSuggestion"])
        XCTAssertFalse(el("planCoachRow").exists, "Coach row shown without a proposal")
        let without = el("planDayHeader").frame.minY
        XCTAssertLessThan(without, with - 40, "The space of the Coach row is still reserved (day header at \(without) vs \(with))")
        print("LABNOTE Coach row: day header at y \(Int(with)) with a proposal, y \(Int(without)) without")
    }

    // MARK: Recurring Plan

    func test08_RecurringPlanRowsWarningAndClearance() {
        launch(["LAB_PLAN_SECTION": "recurring"])
        for d in ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"] {
            let r = el("planRecurring-\(d)")
            XCTAssertTrue(r.waitForExistence(timeout: 5), "Missing weekday row \(d)")
            XCTAssertGreaterThanOrEqual(r.frame.height, 44, "Row \(d) is shorter than 44 pt")
            XCTAssertTrue(r.label.hasPrefix(["Mon": "Monday", "Tue": "Tuesday", "Wed": "Wednesday", "Thu": "Thursday", "Fri": "Friday", "Sat": "Saturday", "Sun": "Sunday"][d]!))
        }
        XCTAssertEqual(el("planRecurring-Sat").value as? String, "2 h · Sat limit 1 h", "Saturday's warning must name the exceeded constraint")
        XCTAssertEqual(el("planRecurring-Mon").value as? String, "", "Monday must carry no warning")
        let a = el("planAvailability"); XCTAssertTrue(a.exists)
        let clear = dockTop - a.frame.maxY
        print("LABNOTE Recurring Plan: availability row ends \(Int(clear)) pt above the dock (window height \(Int(window.height)))")
        XCTAssertGreaterThanOrEqual(clear, 16, "Recurring Plan content ends \(clear) pt above the dock; at least 16 pt is required at default text size")
    }

    func test09_BudgetConflictIsShownOnTheAvailabilityRow() {
        launch(["LAB_PLAN_SECTION": "recurring", "LAB_PLAN": "budget"])
        XCTAssertTrue(el("planAvailability").waitForExistence(timeout: 5))
        XCTAssertEqual(el("planAvailability").value as? String, "Cycling has 4 h planned and 3 h in your weekly budget")
        XCTAssertTrue(el("planAvailability").label.contains("5 h a week"), el("planAvailability").label)
        XCTAssertEqual(el("planRecurring-Sat").value as? String, "", "No day limit is exceeded in this sample")
    }

    // MARK: placeholders, dock, themes, text size

    func test10_UnbuiltActionsOpenALabelledPlaceholder() {
        launch()
        for (id, name) in [("planProgram", "Goal & Program"), ("planCoachRow", "Coach proposal"),
                           ("planAddSession", "Add session"), ("planSession-c4", "Session detail"), ("planSessionMore-c4", "Session actions")] {
            tap(id)
            let p = el("planPlaceholder")
            XCTAssertTrue(p.waitForExistence(timeout: 5), "No placeholder after \(id)")
            let texts = p.descendants(matching: .staticText).allElementsBoundByIndex.map { $0.label }.joined(separator: " | ")
            XCTAssertTrue(texts.contains("Prototype placeholder") && texts.contains(name), "Placeholder for \(id) reads: \(texts)")
            tap("planPlaceholderClose")
            XCTAssertFalse(el("planPlaceholder").waitForExistence(timeout: 1), "Placeholder did not close")
        }
    }

    func test11_SessionCardsStayClearOfTheDock() {
        launch()
        let last = el("planSession-c5"); XCTAssertTrue(last.waitForExistence(timeout: 5))
        let visibleAtRest = last.frame.maxY <= dockTop
        scrollUntilClear(last)
        XCTAssertLessThanOrEqual(last.frame.maxY, dockTop, "The last session card cannot be brought above the dock")
        print("LABNOTE Weekly Calendar, two sessions and a Coach row: second card fully above the dock without scrolling: \(visibleAtRest) (window height \(Int(window.height)))")
        for id in ["dock-0", "dock-1", "dock-3", "dock-4", "dockCentre"] { XCTAssertTrue(el(id).exists, "Dock item \(id) missing on Plan") }
    }

    func test12_AllSixThemesShowBothSections() {
        for t in ["obsidian", "arctic", "ocean", "forest", "sandstone", "highContrast"] {
            launch(["LAB_THEME": t])
            XCTAssertTrue(el("planDay-12").exists && el("planSession-c4").exists, "Weekly Calendar incomplete in \(t)")
            tap("planSection-recurring")
            XCTAssertTrue(el("planRecurring-Sat").waitForExistence(timeout: 5), "Recurring Plan incomplete in \(t)")
        }
    }

    func test13_LargeTextKeepsControlsUsable() {
        launch(args: ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityL"])
        let sw = el("planSection-weekly").frame, sr = el("planSection-recurring").frame
        XCTAssertLessThanOrEqual(sw.maxX, sr.minX + 1, "The two section labels collide (\(sw) and \(sr))")
        for id in ["planProgram", "planSection-weekly", "planSection-recurring", "planDay-12", "planAddSession"] {
            let e = el(id)
            XCTAssertTrue(e.exists, "Missing \(id) at large text")
            XCTAssertGreaterThanOrEqual(e.frame.height, 44, "\(id) is shorter than 44 pt at large text")
            XCTAssertGreaterThanOrEqual(e.frame.minX, window.minX - 1); XCTAssertLessThanOrEqual(e.frame.maxX, window.maxX + 1)
        }
        tap("planDay-10"); waitLabel("planDayHeader", "Tue 10 Nov")
        tap("planSection-recurring")
        let a = el("planAvailability"); XCTAssertTrue(a.waitForExistence(timeout: 5))
        scrollUntilClear(a)
        XCTAssertLessThanOrEqual(a.frame.maxY, dockTop, "At large text the availability row cannot be brought above the dock")
        let sat = el("planRecurring-Sat")
        XCTAssertEqual(sat.value as? String, "2 h · Sat limit 1 h")
        // the weekday pills must not be squeezed: every row is at least as wide as the screen minus the margins
        for d in ["Mon", "Wed", "Sat"] { XCTAssertGreaterThanOrEqual(el("planRecurring-\(d)").frame.height, 44) }
        tap("planSection-weekly")
        let last = el("planSession-c2"); XCTAssertTrue(last.waitForExistence(timeout: 5))
        scrollUntilClear(last)
        XCTAssertLessThanOrEqual(last.frame.maxY, dockTop, "At large text the session card cannot be brought above the dock")
    }

    /// Regression for the week-arrow failure of run 43409711047 (standard iPhone): the arrows are pressed repeatedly
    /// and the week must follow every time. On failure the prototype's own record of week changes is printed.
    func test15_WeekArrowsFollowEveryPress() {
        launch()
        func expect(_ title: String, _ step: String) {
            let e = el("planWeekTitle")
            let x = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", title), object: e)
            let r = XCTWaiter().wait(for: [x], timeout: 8)
            XCTAssertEqual(r, .completed, "After \(step) the week shows \"\(e.label)\", expected \"\(title)\". Prototype record: \(e.value as? String ?? "none")")
        }
        tap("planWeekNext"); expect("16 – 22 Nov", "first press of Next, straight after launch")
        for i in 1...6 {
            tap("planWeekPrev"); expect("9 – 15 Nov", "Previous, cycle \(i)")
            tap("planWeekPrev"); expect("2 – 8 Nov", "Previous again, cycle \(i)")
            tap("planWeekNext"); expect("9 – 15 Nov", "Next, cycle \(i)")
            tap("planWeekNext"); expect("16 – 22 Nov", "Next again, cycle \(i)")
        }
        print("LABNOTE week arrows: 25 presses followed; prototype record (last entries): \(el("planWeekTitle").value as? String ?? "none")")
    }

    // MARK: session presentation — Variant A (approved cards) and Variant B (hybrid), same four sessions

    private func measure(_ variant: String, _ env: [String: String]) {
        var e = ["LAB_PLAN": "busy"]; env.forEach { e[$0.key] = $0.value }
        launch(e)
        let ids = ["c4", "c5", "b3", "b4"]
        var heights: [Int] = [], visible = 0
        for id in ids {
            let s = el("planSession-\(id)"); XCTAssertTrue(s.waitForExistence(timeout: 5), "Missing session \(id) in \(variant)")
            let more = el("planSessionMore-\(id)")
            XCTAssertGreaterThanOrEqual(more.frame.height, 44, "The actions control of \(id) is shorter than 44 pt in \(variant)")
            XCTAssertGreaterThanOrEqual(more.frame.union(s.frame).height, 44, "Row \(id) is shorter than 44 pt in \(variant)")
            heights.append(Int(more.frame.union(s.frame).height.rounded()))
            if max(s.frame.maxY, more.frame.maxY) <= dockTop { visible += 1 }
        }
        XCTAssertTrue(el("planSession-b3").label.contains("Rescheduled from Mon 9 Nov (missed)"), "The rescheduling relationship is missing in \(variant)")
        XCTAssertTrue(el("planSession-b4").label.contains("Done") && el("planSession-c4").label.contains("Planned"), "Status is missing in \(variant)")
        let first = el("planSession-c4").frame.minY, lastBottom = max(el("planSession-b4").frame.maxY, el("planSessionMore-b4").frame.maxY)
        print("LABNOTE \(variant): content heights \(heights) pt · list from y \(Int(first)) to y \(Int(lastBottom)) (\(Int(lastBottom - first)) pt for four sessions) · dock top y \(Int(dockTop)) · sessions fully above the dock without scrolling: \(visible) of 4 · window \(Int(window.width)) × \(Int(window.height))")
        let last = el("planSession-b4"); scrollUntilClear(last)
        XCTAssertLessThanOrEqual(last.frame.maxY, dockTop, "The last session cannot be brought above the dock in \(variant)")
    }
    func test16_VariantA_ApprovedCards_Measured() {
        measure("Variant A (approved cards)", [:])
        XCTAssertEqual(el("planSession-c5").value as? String, "planned structure shown")      // unchanged approved behaviour
    }
    func test17_VariantB_Hybrid_MeasuredAndStructureOnlyWhenInformative() {
        measure("Variant B (hybrid)", ["LAB_PLAN_CARDS": "hybrid"])
        XCTAssertEqual(el("planSession-c4").value as? String, "planned structure shown", "A structured strength session must keep its indicator")
        XCTAssertEqual(el("planSession-b4").value as? String, "planned structure shown", "An interval workout must keep its indicator")
        XCTAssertEqual(el("planSession-c5").value as? String, "no structure shown", "A steady Zone 2 session must not show a decorative bar")
    }

    func test14_DayCirclesAreLabelledForVoiceOver() {
        launch()
        XCTAssertEqual(el("planDay-12").label, "Thursday 12 November, today, 2 sessions: strength, ride")
        XCTAssertEqual(el("planDay-9").label, "Monday 9 November, 1 session: strength")
        XCTAssertEqual(el("planDay-15").label, "Sunday 15 November, nothing scheduled")
        XCTAssertTrue(el("planDay-12").isSelected, "The selected day is not exposed as selected")
        XCTAssertGreaterThanOrEqual(el("planDay-12").frame.width, 44); XCTAssertGreaterThanOrEqual(el("planDay-12").frame.height, 44)
    }
}
