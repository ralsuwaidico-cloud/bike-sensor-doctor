import XCTest

/// V1 end-to-end journey (owner, 2 Nov): install → onboarding (name once) → type/experience/goals → week → devices
/// skipped → personalised plan → Approve → Home → Profile keeps every answer → Plan shows the same week → relaunch keeps
/// everything. Three personas, no devices. Every assertion is on data the screens show, not on screenshots.
/// `BC_JOURNEY_PERSONA` (CI recording) limits the run to one persona; `LAYOUT_DIR` saves screenshots.
final class JourneyTests: XCTestCase {
    private var outDir: String? { ProcessInfo.processInfo.environment["LAYOUT_DIR"] }
    private var only: String? { ProcessInfo.processInfo.environment["BC_JOURNEY_PERSONA"] }

    struct Persona {
        let tag: String
        let mode: String           // cycling | strength | hybrid
        let name: String
        let goal: String           // GoalID raw value
        let expectsRides: Bool
        let expectsLifts: Bool
    }
    private let personas = [
        Persona(tag: "cycling", mode: "cycling", name: "Lina", goal: "endurance", expectsRides: true, expectsLifts: false),
        Persona(tag: "strength", mode: "strength", name: "Omar", goal: "strength", expectsRides: false, expectsLifts: true),
        Persona(tag: "hybrid", mode: "hybrid", name: "Sara", goal: "endurance", expectsRides: true, expectsLifts: true),
    ]

    override func setUpWithError() throws { continueAfterFailure = true }

    func testCyclingJourney() throws { try run(personas[0]) }
    func testStrengthJourney() throws { try run(personas[1]) }
    func testHybridJourney() throws { try run(personas[2]) }

    // MARK: - the journey

    private func run(_ p: Persona) throws {
        if let o = only, o != p.tag { throw XCTSkip("persona \(p.tag) not selected") }
        let app = XCUIApplication()
        app.launchEnvironment["BC_UITEST_RESET"] = "1"
        app.launch()

        // 1 — fresh install lands on Welcome; nothing asked there
        let start = app.buttons["onboardingContinue"].firstMatch
        XCTAssertTrue(start.waitForExistence(timeout: 30), "\(p.tag): welcome")
        XCTAssertEqual(app.textFields.count, 0, "\(p.tag): the welcome screen asks nothing")
        shot(app, "\(p.tag)-01-welcome")
        XCTAssertTrue(start.tapWhenSettled(timeout: 15), "\(p.tag): welcome button settles (run 160: first launch on a freshly booted simulator took > 5 s)")

        // 2 + 3 — personal details once; athlete type, experience, goals
        let next = app.buttons["onboardingNext"].firstMatch
        XCTAssertTrue(app.staticTexts["Who you are · 1 of 5"].waitForExistence(timeout: 10), "\(p.tag): stage A")
        XCTAssertFalse(next.isEnabled, "\(p.tag): Continue waits for name + type")
        let name = app.textFields["onbName"].firstMatch
        XCTAssertTrue(name.waitForExistence(timeout: 5)); name.tap(); name.typeText(p.name + "\n")
        XCTAssertEqual(app.textFields.matching(NSPredicate(format: "identifier CONTAINS[c] 'name'")).count, 1, "\(p.tag): exactly one name field")
        XCTAssertTrue(app.keyboards.firstMatch.waitUntilGone(timeout: 10), "\(p.tag): Return closes the keyboard")
        let mode = app.buttons["onbMode-\(p.mode)"].firstMatch
        XCTAssertTrue(mode.waitForExistence(timeout: 5)); XCTAssertTrue(tapVisible(app, mode))
        XCTAssertTrue(app.buttons["onbDOB"].firstMatch.label.lowercased().contains("not set"), "\(p.tag): date of birth is empty, never pre-filled")
        XCTAssertFalse(app.staticTexts["Height"].exists, "\(p.tag): height is not asked")
        // experience chips exist for the chosen sports; pick the second option where offered so Profile can prove it
        // every button on the stage does something (this taps the other training types too) — then the persona's own
        // choices are made last, so the answers carried to Profile are the persona's
        sweep(app, stage: "A", tag: p.tag, skip: ["onboardingNext", "onboardingBack", "onbName", "onbDOBDone", "onbMode-\(p.mode)"])   // run 151: re-selecting the chosen type correctly changes nothing
        XCTAssertTrue(tapVisible(app, mode))
        if p.mode != "strength" { pickChip(app, group: "onbCyclingLevel", index: 1, tag: p.tag) }
        if p.mode != "cycling" { pickChip(app, group: "onbStrengthLevel", index: 1, tag: p.tag) }
        if p.mode == "hybrid" { XCTAssertTrue(app.descendants(matching: .any)["onbPriority"].firstMatch.exists, "\(p.tag): priority segment for hybrid") }
        shotScrolling(app, "\(p.tag)-02-who")
        XCTAssertTrue(next.isEnabled, "\(p.tag): name + type → Continue")
        scrollToTop(app); XCTAssertTrue(next.tapWhenSettled())

        XCTAssertTrue(app.staticTexts["Your goals · 2 of 5"].waitForExistence(timeout: 10), "\(p.tag): stage B")
        XCTAssertFalse(next.isEnabled, "\(p.tag): Continue waits for a goal")
        let goal = app.buttons["goal-\(p.goal)"].firstMatch
        XCTAssertTrue(goal.waitForExistence(timeout: 5)); XCTAssertTrue(tapVisible(app, goal))
        XCTAssertTrue(goal.label.contains("main goal"), "\(p.tag): the first goal is the main goal")
        XCTAssertTrue(app.descendants(matching: .any)["onbGoalEffect"].firstMatch.waitForExistence(timeout: 5), "\(p.tag): the effect line explains the goal")
        sweep(app, stage: "B", tag: p.tag, skip: ["onboardingNext", "onboardingBack", "goal-\(p.goal)", "goalStar-\(p.goal)"])
        // run 147: the sweep can tap another goal's star and make it the main goal — the persona's main goal is set last.
        // Runs 154-155 (hybrid only, 9 goal cards): the goals sit in a lazy grid, so after the sweep scrolled to the
        // bottom the first card was no longer in the accessibility tree — scroll back up and wait for it before reading it.
        scrollToTop(app)
        XCTAssertTrue(goal.waitForExistence(timeout: 5), "\(p.tag): the persona's goal card is back on screen after the sweep")
        let star = app.buttons["goalStar-\(p.goal)"].firstMatch
        if !goal.label.contains("main goal"), star.exists { XCTAssertTrue(tapVisible(app, star)) }
        XCTAssertTrue(goal.label.contains("main goal"), "\(p.tag): the persona's main goal is set")
        shotScrolling(app, "\(p.tag)-03-goals")
        XCTAssertTrue(next.isEnabled); scrollToTop(app); XCTAssertTrue(next.tapWhenSettled())

        // 4 — availability and preferences: the coach proposes, the athlete adjusts, the preview follows
        XCTAssertTrue(app.staticTexts["Your week · 3 of 5"].waitForExistence(timeout: 10), "\(p.tag): stage C")
        XCTAssertTrue(app.descendants(matching: .any)["onbWeekCounts"].firstMatch.waitForExistence(timeout: 5), "\(p.tag): the coach proposed a week")
        XCTAssertTrue(app.descendants(matching: .any)["onbFeasibility"].firstMatch.exists, "\(p.tag): feasibility line")
        let day3 = app.buttons["cyDay-3"].firstMatch
        XCTAssertTrue(day3.waitForExistence(timeout: 5))
        let before3 = day3.label; XCTAssertTrue(tapVisible(app, day3)); XCTAssertNotEqual(day3.label, before3, "\(p.tag): tapping a day cycles its state")
        let week = (0..<7).map { app.buttons["cyDay-\($0)"].firstMatch.label }
        if p.expectsRides { bump(app, "onbRideMinutes", tag: p.tag) }
        if p.expectsLifts { bump(app, "onbLiftMinutes", tag: p.tag) }
        if p.expectsLifts, app.descendants(matching: .any)["onbEquipment"].firstMatch.exists {
            let home = app.descendants(matching: .any)["onbEquipment"].firstMatch.buttons["Home"].firstMatch   // the equipment chip (no tab bar in onboarding)
            if home.exists { XCTAssertTrue(tapVisible(app, home)); XCTAssertTrue(home.isSelected, "\(p.tag): equipment chip selected") }
        }
        // 5 Nov superset repair: the preference stated here must reach the approved sessions (checked on Plan below)
        if p.expectsLifts {
            let sw = app.buttons["onbSupersets"].firstMatch
            XCTAssertTrue(sw.waitForExistence(timeout: 5), "\(p.tag): the supersets switch is offered with the equipment")
            if (sw.value as? String) != "On" { XCTAssertTrue(tapVisible(app, sw)) }
            XCTAssertEqual(sw.value as? String, "On", "\(p.tag): supersets switched on")
        }
        let preview = app.descendants(matching: .any)["onbPlanPreview"].firstMatch
        var tries = 0; while !preview.exists && tries < 6 { app.swipeUp(); tries += 1 }
        XCTAssertTrue(preview.exists, "\(p.tag): live plan preview strip")
        shotScrolling(app, "\(p.tag)-04-week")
        scrollToTop(app); XCTAssertTrue(next.tapWhenSettled())

        // 5 — devices: real cards, Skip loses nothing
        XCTAssertTrue(app.staticTexts["Your ecosystem · 4 of 5"].waitForExistence(timeout: 10), "\(p.tag): stage D")
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'deviceState-'")).firstMatch.exists, "\(p.tag): device cards show a real state")
        XCTAssertEqual(app.switches.count, 0, "\(p.tag): no fake connection switches")
        shot(app, "\(p.tag)-05-ecosystem")
        XCTAssertTrue(app.buttons["onboardingSkip"].firstMatch.tapWhenSettled())

        // 6 — the personalised plan: counts match the week built on C, a first workout of the right sport
        XCTAssertTrue(app.staticTexts["Your training system · 5 of 5"].waitForExistence(timeout: 10), "\(p.tag): stage E")
        XCTAssertTrue(app.descendants(matching: .any)["onbDash"].firstMatch.waitForExistence(timeout: 5))
        let ridesE = Int(stat(app, "rides"))
        let liftsE = Int(stat(app, "lifts"))
        let plannedE = stat(app, "planned")
        XCTAssertEqual(ridesE != nil, p.expectsRides, "\(p.tag): rides stat only for riders"); XCTAssertEqual(liftsE != nil, p.expectsLifts, "\(p.tag): lifts stat only for lifters")
        XCTAssertFalse(plannedE.isEmpty, "\(p.tag): total planned time")
        let weekE = (0..<7).map { app.descendants(matching: .any)["cyDay-\($0)"].firstMatch.label }   // stage E days are display-only (not buttons)
        XCTAssertEqual(weekE.map(sport), week.map(sport), "\(p.tag): stage E shows the week built on C")
        let first = app.descendants(matching: .any)["onbFirst"].firstMatch
        XCTAssertTrue(first.waitForExistence(timeout: 5), "\(p.tag): first workout card")
        let firstLabel = ([first.label] + first.descendants(matching: .staticText).allElementsBoundByIndex.map(\.label)).joined(separator: " ")   // run 147: the card's texts are its children
        XCTAssertTrue(firstLabel.lowercased().contains("strength") || firstLabel.lowercased().contains("ride") || firstLabel.lowercased().contains("min"), "\(p.tag): first workout names a session")
        XCTAssertTrue(app.descendants(matching: .any)["onbWhy"].firstMatch.exists, "\(p.tag): the approach")
        shotScrolling(app, "\(p.tag)-06-system")
        scrollToTop(app); app.swipeUp(); app.swipeUp()
        let approve = app.buttons["onbCreatePlan"].firstMatch
        XCTAssertTrue(approve.waitForExistence(timeout: 5)); XCTAssertTrue(tapVisible(app, approve))

        // 7 — Home: the same week, the first workout, the first-week block, no onboarding
        XCTAssertTrue(app.descendants(matching: .any)["homeWeek"].firstMatch.waitForExistence(timeout: 15), "\(p.tag): Home week strip")
        XCTAssertFalse(app.buttons["onboardingContinue"].exists, "\(p.tag): onboarding is over")
        XCTAssertFalse(app.buttons["homeCaution"].exists, "\(p.tag): no health questionnaire")
        let homeWeek = (0..<7).map { app.descendants(matching: .any)["homeWeekDay-\($0)"].firstMatch.label }
        XCTAssertEqual(fromToday(homeWeek.map(sport)), fromToday(weekE.map(sport)), "\(p.tag): Home shows the approved week from today")
        // W12 (Checkpoint B): days of week 1 before the approval day are "before this plan started" — never rest, never missed
        for i in 0..<todayIndex {
            let l = app.descendants(matching: .any)["homeWeekDay-\(i)"].firstMatch.label.lowercased()
            XCTAssertTrue(l.contains("before this plan started"), "\(p.tag): Home day \(i) before the plan reads '\(l)'")
            XCTAssertFalse(l.contains("rest") || l.contains("missed"), "\(p.tag): Home day \(i) must not be rest or missed: '\(l)'")
        }
        XCTAssertTrue(app.descendants(matching: .any)["liquidDock"].firstMatch.exists, "\(p.tag): the Liquid Dock is the navigation")
        // Checkpoint C: today's card lives in the Training Hub behind the centre button; Home keeps a compact reminder
        XCTAssertTrue(app.buttons["centreButton"].firstMatch.tapWhenSettled())
        XCTAssertTrue(app.descendants(matching: .any)["trainingHub"].firstMatch.waitForExistence(timeout: 10), "\(p.tag): the centre button opens the Training Hub")
        XCTAssertTrue(app.staticTexts["homeTodayTitle"].firstMatch.exists || app.descendants(matching: .any)["homeTodayCard"].firstMatch.exists, "\(p.tag): today's card in the hub")
        shot(app, "\(p.tag)-07b-hub")
        app.closeHub()
        XCTAssertTrue(app.descendants(matching: .any)["homeWeek"].firstMatch.waitForExistence(timeout: 5), "\(p.tag): back on Home")
        var seen = 0; while !app.descendants(matching: .any)["homeFirstWeek"].firstMatch.exists && seen < 5 { app.swipeUp(); seen += 1 }
        XCTAssertTrue(app.descendants(matching: .any)["homeFirstWeek"].firstMatch.exists, "\(p.tag): first-week block (plan counts, goals, next steps)")
        XCTAssertTrue(app.descendants(matching: .any)["cyHeroRing"].firstMatch.exists, "\(p.tag): this-week ring from the plan")
        XCTAssertTrue(app.descendants(matching: .any)["homeGoal-\(p.goal)"].firstMatch.exists, "\(p.tag): the chosen main goal on Home")
        XCTAssertTrue(app.buttons["homeStartFirst"].firstMatch.exists, "\(p.tag): first-session next step")
        shot(app, "\(p.tag)-07-home")
        scrollToTop(app)

        // 8 — Profile keeps every answer
        XCTAssertTrue(app.buttons["Profile"].firstMatch.tapWhenSettled())
        XCTAssertTrue(app.buttons["profileHeader"].firstMatch.waitForExistence(timeout: 10), "\(p.tag): Profile")
        XCTAssertTrue(app.buttons["profileHeader"].firstMatch.label.contains(p.name), "\(p.tag): name retained once")
        let typeRow = app.buttons["profileType"].firstMatch
        XCTAssertTrue(typeRow.label.lowercased().contains(p.mode == "hybrid" ? "hybrid" : p.mode), "\(p.tag): training type retained (\(typeRow.label))")
        XCTAssertTrue(app.buttons["profileGoal"].firstMatch.label.lowercased().contains(goalTitle(p.goal).lowercased()), "\(p.tag): main goal retained")
        let weekRow = app.buttons["profileWeek"].firstMatch
        let trainingDays = weekE.map(sport).filter { $0 != "rest" }.count
        XCTAssertTrue(weekRow.label.contains("\(trainingDays) day"), "\(p.tag): week retained — \(trainingDays) training days (\(weekRow.label))")
        if p.expectsLifts { XCTAssertTrue(app.buttons["profileEquipment"].firstMatch.exists, "\(p.tag): equipment row") }
        if p.expectsRides { XCTAssertTrue(app.buttons["profileFTP"].firstMatch.label.contains("Unknown"), "\(p.tag): FTP stays Unknown — nothing invented") }
        XCTAssertTrue(tapVisible(app, app.buttons["profileType"].firstMatch))
        XCTAssertTrue(app.buttons["onbMode-\(p.mode)"].firstMatch.waitForExistence(timeout: 5), "\(p.tag): type editor shows the stored type")
        XCTAssertTrue(app.buttons["onbMode-\(p.mode)"].firstMatch.isSelected || app.buttons["onbMode-\(p.mode)"].firstMatch.label.contains("selected"), "\(p.tag): the stored type is selected")
        XCTAssertEqual(app.textFields.matching(NSPredicate(format: "identifier CONTAINS[c] 'name'")).count, 0, "\(p.tag): the type editor never asks the name again")
        app.navigationBars.buttons.firstMatch.tap()
        shot(app, "\(p.tag)-08-profile")

        // 9 — Plan shows the same approved schedule
        XCTAssertTrue(app.buttons["Plan"].firstMatch.tapWhenSettled())
        XCTAssertTrue(app.descendants(matching: .any)["planDayStrip"].firstMatch.waitForExistence(timeout: 10), "\(p.tag): Plan")
        let planWeek = planSports(app)
        XCTAssertEqual(fromToday(planWeek), fromToday(weekE.map(sport)), "\(p.tag): Plan shows the approved week from today")
        for i in 0..<todayIndex {   // W12 on Plan: the same wording as Home
            let wd = [2, 3, 4, 5, 6, 7, 1][i]
            let l = app.buttons["planDay-\(wd)"].firstMatch.label.lowercased()
            XCTAssertTrue(l.contains("before this plan started"), "\(p.tag): Plan day \(i) before the plan reads '\(l)'")
        }
        shot(app, "\(p.tag)-09-plan")
        // 5 Nov superset repair: a coach-built strength session of the approved week shows its superset grouping (A1/A2
        // badges) in the hybrid journey — the same screen that runs the session
        if p.expectsLifts {
            let order = [2, 3, 4, 5, 6, 7, 1]
            if let i = (todayIndex..<7).first(where: { planWeek[$0] == "strength" }) {
                let dayCell = app.buttons["planDay-\(order[i])"].firstMatch
                XCTAssertTrue(tapVisible(app, dayCell))
                // run 162: a session on a later day shows Move to today / Skip instead of Start — wait for the exercise list itself
                XCTAssertTrue(app.buttons["adjustSets"].firstMatch.waitForExistence(timeout: 10) || app.buttons["startWorkout"].firstMatch.exists, "\(p.tag): the strength session opens from Plan")
                let badge = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH 'superset '")).firstMatch
                XCTAssertTrue(badge.waitForExistence(timeout: 5), "\(p.tag): the approved session shows a superset group")
                shot(app, "\(p.tag)-09b-superset")
                let done = app.buttons["Done"].firstMatch
                if done.exists { done.tap() } else { app.swipeDown() }
                XCTAssertTrue(app.descendants(matching: .any)["planDayStrip"].firstMatch.waitForExistence(timeout: 10))
            } else { XCTFail("\(p.tag): no strength day from today on Plan to open") }
        }

        // 10 — relaunch: everything persists
        app.terminate()
        let again = XCUIApplication(); again.launch()
        XCTAssertTrue(again.descendants(matching: .any)["homeWeek"].firstMatch.waitForExistence(timeout: 20), "\(p.tag): relaunch lands on Home")
        XCTAssertFalse(again.buttons["onboardingContinue"].exists, "\(p.tag): no onboarding after relaunch")
        XCTAssertEqual((0..<7).map { again.descendants(matching: .any)["homeWeekDay-\($0)"].firstMatch.label }.map(sport).dropFirst(todayIndex).map { $0 }, fromToday(weekE.map(sport)), "\(p.tag): the week persists")
        XCTAssertTrue(again.buttons["Profile"].firstMatch.tapWhenSettled())
        XCTAssertTrue(again.buttons["profileHeader"].firstMatch.waitForExistence(timeout: 10))
        XCTAssertTrue(again.buttons["profileHeader"].firstMatch.label.contains(p.name), "\(p.tag): name persists")
        XCTAssertTrue(again.buttons["profileWeek"].firstMatch.label.contains("\(trainingDays) day"), "\(p.tag): week persists")
        XCTAssertTrue(again.buttons["Plan"].firstMatch.tapWhenSettled())
        XCTAssertTrue(again.descendants(matching: .any)["planDayStrip"].firstMatch.waitForExistence(timeout: 10))
        XCTAssertEqual(fromToday(planSports(again)), fromToday(weekE.map(sport)), "\(p.tag): Plan persists")
        shot(again, "\(p.tag)-10-relaunch")
        again.terminate()
    }

    // MARK: - helpers

    /// A day's sport from any strip label: "cycling" / "strength" / "both" / "rest".
    private func sport(_ label: String) -> String {
        let l = label.lowercased()
        // strips say "ride" / "cycling"; Plan's day cells name the session kind (Endurance, Tempo, Threshold, VO2 max,
        // Recovery spin, Long ride, FTP test) — a recovery *day* or mobility is rest
        let rideKinds = ["cycling", "ride", "endurance", "tempo", "threshold", "vo2", "recovery spin", "ftp test"]
        let ride = rideKinds.contains { l.contains($0) }
        let lift = l.contains("strength") || l.contains("lift")
        if ride && lift { return "both" }
        if ride { return "cycling" }
        if lift { return "strength" }
        return "rest"
    }
    /// Plan's day cells are keyed by weekday number; order them Monday first like every other strip.
    private func planSports(_ app: XCUIApplication) -> [String] {
        let order = [2, 3, 4, 5, 6, 7, 1]
        return order.map { app.buttons["planDay-\($0)"].firstMatch.label }.map(sport)
    }
    /// A stage-E stat ("onbStat-rides" …): its value, whatever element type the combined stat is exposed as; "" when absent.
    private func stat(_ app: XCUIApplication, _ name: String) -> String {
        let e = app.descendants(matching: .any)["onbStat-\(name)"].firstMatch
        return e.exists ? (e.value as? String ?? "") : ""
    }
    /// Week 1 starts on the day the plan is approved (V1 run 147): days before today are compared separately.
    private var todayIndex: Int { (Calendar.current.component(.weekday, from: Date()) + 5) % 7 }
    private func fromToday(_ w: [String]) -> [String] { Array(w.dropFirst(todayIndex)) }
    private func beforeToday(_ w: [String]) -> [String] { Array(w.prefix(todayIndex)) }
    private func goalTitle(_ raw: String) -> String {
        switch raw { case "endurance": return "Endurance"; case "strength": return "Strength"; case "muscle": return "Muscle"; default: return raw }
    }
    private func pickChip(_ app: XCUIApplication, group: String, index: Int, tag: String) {
        let g = app.descendants(matching: .any)[group].firstMatch
        guard g.waitForExistence(timeout: 5) else { return XCTFail("\(tag): \(group) chips") }
        let b = g.buttons.allElementsBoundByIndex
        guard b.count > index else { return XCTFail("\(tag): \(group) has \(b.count) options") }
        XCTAssertTrue(tapVisible(app, b[index])); XCTAssertTrue(b[index].isSelected || b[index].label.contains("selected"), "\(tag): \(group) option \(index) selected")
    }
    private func bump(_ app: XCUIApplication, _ id: String, tag: String) {
        let row = app.descendants(matching: .any)[id].firstMatch
        guard row.waitForExistence(timeout: 5) else { return XCTFail("\(tag): \(id)") }
        let plus = row.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'increase' OR label CONTAINS[c] 'plus' OR label == '+'")).firstMatch
        guard plus.exists else { return }
        // run 144: the row's label is its title ("Ride length"); the number is the stepper's accessibility value
        // run 145: the number is a text inside the stepper (its container exposes no value) — compare labels and values
        let values = { row.descendants(matching: .any).allElementsBoundByIndex.map { "\($0.label)=\($0.value as? String ?? "")" }.joined(separator: "|") }
        let before = values(); XCTAssertTrue(tapVisible(app, plus)); XCTAssertNotEqual(values(), before, "\(tag): \(id) stepper changes the value")
    }
    /// Every button on the stage does something: its own label changes, a selection appears, or the screen's text changes.
    private func sweep(_ app: XCUIApplication, stage: String, tag: String, skip: [String]) {
        // run 150: elements bound by index pointed at other buttons once a tap changed the layout — collect the identifiers,
        // then find each button by identifier when it is tapped
        let ids = app.buttons.allElementsBoundByIndex.map(\.identifier).filter { id in
            !id.isEmpty && !skip.contains(id) && (id.hasPrefix("onb") || id.hasPrefix("goal")) }
        var seenIds = Set<String>()
        for id in ids.prefix(12) where seenIds.insert(id).inserted {
            let b = app.buttons[id].firstMatch
            guard b.exists else { continue }
            reveal(app, b)
            let before = snapshotText(app)
            b.tap()
            _ = app.waitUntilSettled(timeout: 2)
            let after = snapshotText(app)
            XCTAssertTrue(before != after, "\(tag) stage \(stage): button \(id) did nothing")   // run 151: id first — the CI digest cut the long text comparison
        }
    }
    private func snapshotText(_ app: XCUIApplication) -> String {
        (app.staticTexts.allElementsBoundByIndex.map(\.label) + app.buttons.allElementsBoundByIndex.map { "\($0.label)|\($0.isSelected)" }).joined(separator: "\n")
    }
    /// Run 144: taps land on the element's centre, so an element under the fixed Continue bar (or the tab bar) received
    /// the bar's tap instead. Scroll in short drags until the element sits between the header and the bottom bar.
    private func reveal(_ app: XCUIApplication, _ e: XCUIElement) {
        let win = app.windows.firstMatch.frame
        let bar = app.buttons["onboardingNext"].firstMatch
        for _ in 0..<8 {
            guard e.waitForExistence(timeout: 2) else { return }   // run 154: a re-render between queries made `frame` throw
            let bottom = bar.exists && bar.frame.minY > win.midY ? bar.frame.minY - 8 : win.maxY - 100
            let top = win.minY + 110
            if e.frame.maxY > bottom { drag(app, up: true) } else if e.frame.minY < top { drag(app, up: false) } else { return }
        }
    }
    private func drag(_ app: XCUIApplication, up: Bool) {
        let a = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: up ? 0.6 : 0.35)), b = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: up ? 0.35 : 0.6))
        a.press(forDuration: 0.05, thenDragTo: b); _ = app.waitUntilSettled(timeout: 2)
    }
    private func tapVisible(_ app: XCUIApplication, _ e: XCUIElement) -> Bool {
        reveal(app, e)
        // run 152: on the first (cold, slowest) journey the type card did not hold still for 5 s; the rest of that journey
        // passed — allow 10 s, like the keyboard
        return e.tapWhenSettled(timeout: 10)
    }
    private func scrollToTop(_ app: XCUIApplication) { app.swipeDown(); app.swipeDown(); app.swipeDown() }
    private func shot(_ app: XCUIApplication, _ name: String) {
        guard let dir = outDir else { return }
        let png = XCUIScreen.main.screenshot().pngRepresentation
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        try? png.write(to: URL(fileURLWithPath: dir).appendingPathComponent("journey-\(name).png"))
    }
    private func shotScrolling(_ app: XCUIApplication, _ name: String) {
        shot(app, name); app.swipeUp(); shot(app, "\(name)-lower"); scrollToTop(app)
    }
}
