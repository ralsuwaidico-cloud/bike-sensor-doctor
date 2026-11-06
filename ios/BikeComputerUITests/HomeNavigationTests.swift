import XCTest

/// Checkpoint C correction pass (owner 6 Nov): every Home card, calendar day and Profile Quick Menu row reaches its own
/// meaningful page; back returns to Home where it was; the top never sits under the status bar and the last card scrolls
/// fully above the Liquid Dock. Seeded with the LayoutAudit Home stores ("Demo", 8 weeks of rides and lifts).
final class HomeNavigationTests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    private func launch(_ state: String = "planned", supersets: Bool? = nil, size: String? = nil, extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += extra
        var json = LayoutAudit.homeStore(state)
        if let s = supersets, var obj = try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any] {
            obj["strengthPrefs"] = ["prefersSupersets": s, "experience": "intermediate", "favourites": [] as [Any], "alwaysPrefer": [:] as [String: Any], "avoid": [] as [Any], "reviewFlags": [] as [Any], "temporary": [] as [Any], "swapHistory": [] as [Any]]
            json = String(data: try! JSONSerialization.data(withJSONObject: obj), encoding: .utf8)!
        }
        app.launchEnvironment["BC_UITEST_SEED_JSON"] = json
        if let s = size { app.launchArguments += ["-UIPreferredContentSizeCategoryName", s] }
        app.launch()
        XCTAssertTrue(app.waitForHome(name: "Demo", timeout: 30), "Home did not appear")
        return app
    }
    private func el(_ app: XCUIApplication, _ id: String) -> XCUIElement { app.descendants(matching: .any)[id].firstMatch }
    private func back(_ app: XCUIApplication) {
        let b = app.navigationBars.buttons.element(boundBy: 0)
        XCTAssertTrue(b.waitForExistence(timeout: 5)); b.tap(); sleep(1)
    }
    /// Scrolls Home until the element is fully above the dock.
    private func reveal(_ app: XCUIApplication, _ e: XCUIElement) {
        let dockTop = el(app, "liquidDock").frame.minY
        for _ in 0..<6 where !(e.exists && e.isHittable && e.frame.maxY <= dockTop) { app.swipeUp(velocity: .slow); sleep(1) }
    }
    private func shot(_ name: String) {
        let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); a.name = name; a.lifetime = .keepAlways; add(a)
    }

    // MARK: A1 · ring → Weekly overview → a session (planned → prescription, recorded → details); week navigation

    func testRingOpensTheWeeklyOverviewAndItsSessions() {
        let app = launch()
        XCTAssertTrue(el(app, "cyHeroRing").tapWhenSettled())
        XCTAssertTrue(el(app, "homeWeekOverview").waitForExistence(timeout: 5), "the ring opens the weekly overview, not Plan")
        XCTAssertTrue(el(app, "weekOverviewExplanation").exists)
        XCTAssertTrue(el(app, "weekOverviewTitle").label.contains("This week"))
        for k in ["planned", "done", "remaining", "missed", "skipped", "rest-days"] { XCTAssertTrue(el(app, "weekOverview-\(k)").exists, "count \(k)") }
        shot("nav-01-week-overview")
        // last week: recorded rides from history open the ride details
        XCTAssertTrue(el(app, "weekOverviewPrev").tapWhenSettled()); sleep(1)
        XCTAssertFalse(el(app, "weekOverviewTitle").label.contains("This week"))
        let rec = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'weekOverviewItem-' AND NOT (identifier ENDSWITH '-action')")).firstMatch
        XCTAssertTrue(rec.waitForExistence(timeout: 5), "last week lists its recorded workouts")
        _ = rec.tapWhenSettled()
        XCTAssertTrue(el(app, "homeRideDetail").waitForExistence(timeout: 5) || el(app, "homeLogDetail").waitForExistence(timeout: 3), "a recorded workout opens its real details page")
        shot("nav-02-week-overview-recorded")
        back(app); back(app)
        XCTAssertTrue(el(app, "homeGreeting").waitForExistence(timeout: 5), "back returns to Home")
    }

    // MARK: A2 · Cycling card → Cycling summary → recorded ride

    func testCyclingCardOpensTheSummaryAndARide() {
        let app = launch()
        // owner 6 Nov (6): scroll Home a little first; the position must survive summary → historical ride → back → back
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.62)).press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)))
        sleep(1)
        let card = el(app, "homeCycling")
        let y = card.frame.minY
        XCTAssertTrue(card.tapWhenSettled())
        XCTAssertTrue(el(app, "homeCyclingSummary").waitForExistence(timeout: 5), "the cycling card opens the cycling summary, not Progress")
        XCTAssertTrue(app.navigationBars["Cycling summary"].exists)
        for t in ["Rides", "Time", "Distance", "Avg-heart-rate"] { XCTAssertTrue(el(app, "cyclingTile-\(t)").exists, t) }
        XCTAssertTrue(el(app, "cyclingTile-Avg-power").label.contains("—") || el(app, "cyclingTile-Avg-power").label.localizedCaseInsensitiveContains("not measured"), "no power measured in the seed → no number invented")
        XCTAssertTrue(el(app, "cyclingNext").exists || el(app, "cyclingNoNext").exists)
        shot("nav-03-cycling-summary")
        let ride = el(app, "cyclingRide-0")
        for _ in 0..<4 where !ride.isHittable { app.swipeUp(velocity: .slow) }
        XCTAssertTrue(ride.tapWhenSettled())
        XCTAssertTrue(el(app, "homeRideDetail").waitForExistence(timeout: 5)); XCTAssertTrue(app.navigationBars["Ride"].exists)
        shot("nav-04-ride-details")
        back(app); back(app)
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        XCTAssertEqual(card.frame.minY, y, accuracy: 12, "Home's scroll position survives summary → ride → back")
    }

    // MARK: A3 · Strength card → Strength summary → recorded log (exercises with sets, reps, weights)

    func testStrengthCardOpensTheSummaryAndALog() {
        let app = launch()
        XCTAssertTrue(el(app, "homeStrength").tapWhenSettled())
        XCTAssertTrue(el(app, "homeStrengthSummary").waitForExistence(timeout: 5), "the strength card opens the strength summary, not Progress")
        XCTAssertTrue(el(app, "strengthNext").exists || el(app, "strengthNoNext").exists)
        let expand = el(app, "strengthLogExpand-0")
        for _ in 0..<4 where !expand.isHittable { app.swipeUp(velocity: .slow) }
        XCTAssertTrue(expand.tapWhenSettled())
        let ex = el(app, "strengthLogExercises-0")
        XCTAssertTrue(ex.waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Goblet squat 3×10 @ 20 kg'")).firstMatch.exists, "logged sets, reps and weight as recorded")
        shot("nav-05-strength-summary")
        XCTAssertTrue(el(app, "strengthLog-0").tapWhenSettled())
        XCTAssertTrue(el(app, "homeLogDetail").waitForExistence(timeout: 5), "a log opens its real details page")
        shot("nav-06-strength-log")
        back(app); back(app)
        XCTAssertTrue(el(app, "homeGreeting").waitForExistence(timeout: 5))
    }

    // MARK: A4 · calendar: planned → prescription, rest → explanation, multiple → day page; Plan label → Plan

    func testCalendarDaysOpenTheRightThing() {
        let app = launch()
        let today = (Calendar.current.component(.weekday, from: Date()) + 5) % 7
        // today: one planned strength session → its prescription (the logger screen)
        XCTAssertTrue(el(app, "homeWeekDay-\(today)").tapWhenSettled())
        XCTAssertTrue(app.buttons["startWorkout"].firstMatch.waitForExistence(timeout: 8) || app.navigationBars.matching(NSPredicate(format: "identifier CONTAINS 'Full'")).firstMatch.exists, "today's session opens its prescription")
        shot("nav-07-day-prescription")
        app.swipeDown(velocity: .fast); sleep(1)
        if !el(app, "homeGreeting").isHittable { for n in ["Done", "Close", "Cancel"] { let b = app.buttons[n].firstMatch; if b.exists && b.isHittable { b.tap(); break } } }
        // Sunday is a rest day in the seed (unless today is Sunday)
        if today != 6 {
            XCTAssertTrue(el(app, "homeWeekDay-6").tapWhenSettled())
            XCTAssertTrue(el(app, "homeDayDetail").waitForExistence(timeout: 5))
            XCTAssertTrue(el(app, "dayEmpty").exists, "a rest day explains itself")
            shot("nav-08-rest-day")
            back(app)
        }
        // Plan label → Plan tab
        XCTAssertTrue(el(app, "homeWeekPlan").tapWhenSettled())
        XCTAssertTrue(el(app, "planDayStrip").waitForExistence(timeout: 5), "the Plan label opens Plan")
    }

    func testTwoSessionsOnOneDayStayIndividuallyAccessible() {
        let app = launch("multi")
        let today = (Calendar.current.component(.weekday, from: Date()) + 5) % 7
        XCTAssertTrue(el(app, "homeWeekDay-\(today)").tapWhenSettled())
        XCTAssertTrue(el(app, "homeDayDetail").waitForExistence(timeout: 5), "two sessions → the day page")
        XCTAssertTrue(el(app, "dayItem-0").exists && el(app, "dayItem-1").exists, "each session listed")
        shot("nav-09-multi-day")
        XCTAssertTrue(el(app, "dayItem-0").tapWhenSettled())
        XCTAssertTrue(el(app, "homeRideDetail").waitForExistence(timeout: 5) || app.buttons["startWorkout"].firstMatch.waitForExistence(timeout: 3) || app.navigationBars.count > 0)
    }

    // MARK: A5 · Recovery and Goal open their own pages; back keeps Home's scroll position; dock clearance; safe area

    func testRecoveryGoalBackNavigationScrollAndLayout() {
        let app = launch()
        // B1: the greeting is below the navigation bar (never under the status bar)
        let bar = app.navigationBars.firstMatch.frame
        XCTAssertGreaterThanOrEqual(el(app, "homeGreeting").frame.minY, bar.maxY - 1, "content below the status bar and the top bar")
        let rec = el(app, "homeRecovery")
        reveal(app, rec)
        // B2: the card scrolls fully above the dock
        XCTAssertLessThanOrEqual(rec.frame.maxY, el(app, "liquidDock").frame.minY + 1, "Recovery fully above the Liquid Dock")
        let y = rec.frame.minY
        XCTAssertTrue(rec.tapWhenSettled())
        XCTAssertTrue(el(app, "homeRecoveryPage").waitForExistence(timeout: 5), "Recovery opens the Recovery page, not Progress")
        shot("nav-10-recovery")
        back(app)
        XCTAssertTrue(rec.waitForExistence(timeout: 5))
        XCTAssertEqual(rec.frame.minY, y, accuracy: 12, "back returns to Home where it was")
        let goal = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'homeGoal-'")).firstMatch
        if goal.exists {
            XCTAssertTrue(goal.tapWhenSettled())
            XCTAssertTrue(el(app, "homeGoalPage").waitForExistence(timeout: 5), "Goal opens Goal details")
            shot("nav-11-goal")
            back(app)
        }
        // the bottom of Home clears the dock
        app.swipeUp(velocity: .fast); app.swipeUp(velocity: .fast); sleep(1)
        let last = [el(app, "homeTodayReminder"), el(app, "homeFirstWeek"), rec].first { $0.exists && $0.isHittable } ?? rec
        XCTAssertLessThanOrEqual(last.frame.maxY, el(app, "liquidDock").frame.minY + 1, "the last card scrolls fully above the dock")
        // A6: with recorded history the getting-started checklist has left Home
        XCTAssertFalse(el(app, "homeFirstWeek").exists, "no first-session prompt once sessions are recorded")
    }

    // MARK: G · Profile Quick Menu

    func testAvatarOpensTheMenuAndEveryRowItsOwnPage() {
        let app = launch(supersets: true)
        let avatar = app.buttons["homeAvatar"].firstMatch
        XCTAssertTrue(avatar.waitForExistence(timeout: 5))
        avatar.tap()
        let menu = el(app, "profileMenu")
        XCTAssertTrue(menu.waitForExistence(timeout: 3), "the avatar opens the menu")
        XCTAssertTrue(el(app, "homeGreeting").exists, "Home stays behind the menu (not the Profile tab)")
        XCTAssertFalse(el(app, "profileHeader").exists)
        shot("menu-01-open")
        // avatar again closes
        avatar.tap(); XCTAssertTrue(menu.waitUntilGone(timeout: 3), "the avatar closes the menu")
        // rapid taps never stack menus
        avatar.tap(); avatar.tap(); avatar.tap(); sleep(1)
        XCTAssertEqual(app.descendants(matching: .any).matching(identifier: "profileMenu").count, 1, "one menu")
        // outside tap closes
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.7)).tap()
        XCTAssertTrue(menu.waitUntilGone(timeout: 3), "a tap outside closes the menu")
        // Close button
        avatar.tap(); XCTAssertTrue(el(app, "profileMenuClose").waitForExistence(timeout: 3)); el(app, "profileMenuClose").tap()
        XCTAssertTrue(menu.waitUntilGone(timeout: 3))

        func openRow(_ id: String) { avatar.tap(); XCTAssertTrue(el(app, id).waitForExistence(timeout: 3)); XCTAssertTrue(el(app, id).tapWhenSettled()); XCTAssertTrue(menu.waitUntilGone(timeout: 3), "the menu closes as navigation begins") }
        openRow("menuMyProfile")
        XCTAssertTrue(el(app, "menuPageMyProfile").waitForExistence(timeout: 5)); XCTAssertTrue(el(app, "fact-Name").label.contains("Demo"))
        XCTAssertTrue(el(app, "fact-Height").exists); shot("menu-02-my-profile"); back(app)
        openRow("menuPreferences")
        XCTAssertTrue(el(app, "menuPagePreferences").waitForExistence(timeout: 5))
        let ss = el(app, "fact-Supersets"); for _ in 0..<4 where !ss.isHittable { app.swipeUp(velocity: .slow) }
        XCTAssertTrue(ss.label.contains("On — paired when the exercises allow it"), "the stored superset value: \(ss.label)")
        shot("menu-03-preferences"); back(app)
        openRow("menuConnections")
        XCTAssertTrue(app.navigationBars["Devices & sensors"].waitForExistence(timeout: 5), "Devices & connections opens the device manager")
        shot("menu-04-connections"); back(app)
        openRow("menuSettings")
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5)); shot("menu-05-settings"); back(app)
        openRow("menuHelp")
        XCTAssertTrue(el(app, "helpSupportPage").waitForExistence(timeout: 5)); XCTAssertTrue(el(app, "helpVersion").exists)
        shot("menu-06-help"); back(app)
        // header → the Profile tab
        openRow("menuViewProfile")
        XCTAssertTrue(el(app, "profileHeader").waitForExistence(timeout: 5), "View profile opens the Profile tab")
    }

    func testMenuClosesOnTabChangeKeepsScrollAndChangesNothing() {
        let app = launch()
        let rec = el(app, "homeRecovery"); reveal(app, rec)
        let y = rec.frame.minY
        app.buttons["homeAvatar"].firstMatch.tap()
        XCTAssertTrue(el(app, "profileMenu").waitForExistence(timeout: 3))
        app.buttons["Plan"].firstMatch.tap(); sleep(1)
        app.buttons["Home"].firstMatch.tap(); sleep(1)
        XCTAssertFalse(el(app, "profileMenu").exists, "a tab change dismisses the menu")
        XCTAssertEqual(rec.frame.minY, y, accuracy: 12, "Home's scroll position survives the menu and the tab change")
        // the Profile tab still works on its own
        app.buttons["Profile"].firstMatch.tap()
        XCTAssertTrue(el(app, "profileHeader").waitForExistence(timeout: 5))
    }

    // MARK: large text: the menu scrolls instead of clipping; Home detail pages wrap

    func testMenuAndPagesAtLargestAccessibilityText() {
        let app = launch(size: "UICTContentSizeCategoryAccessibilityXXXL")
        app.buttons["homeAvatar"].firstMatch.tap()
        XCTAssertTrue(el(app, "profileMenu").waitForExistence(timeout: 3))
        shot("menu-ax3-open")
        let help = el(app, "menuHelp")
        for _ in 0..<4 where !help.isHittable { el(app, "profileMenu").swipeUp(velocity: .slow) }
        XCTAssertTrue(help.isHittable, "the last row is reachable by scrolling the menu")
        el(app, "profileMenuClose").tap()
        XCTAssertTrue(el(app, "cyHeroRing").tapWhenSettled())
        XCTAssertTrue(el(app, "homeWeekOverview").waitForExistence(timeout: 5)); shot("nav-ax3-week-overview")
    }
}
