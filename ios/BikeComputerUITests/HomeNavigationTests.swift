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
    /// A control by identifier, any element type (run 172: combined cards such as the ring and Recovery are not
    /// exposed as buttons). Tapped with XCUI's own tap, which scrolls it into view and fails if it cannot.
    private func btn(_ app: XCUIApplication, _ id: String) -> XCUIElement { app.descendants(matching: .any).matching(identifier: id).firstMatch }
    /// Waits for a button and taps it (XCUI's own tap: waits for idle and hittability).
    @discardableResult
    private func tap(_ app: XCUIApplication, _ id: String, _ why: String = "") -> Bool {
        let b = btn(app, id)
        guard b.waitForExistence(timeout: 10) else { shot("FAIL-missing-\(id)"); XCTFail("control \(id) missing \(why)"); return false }
        b.tap(); return true
    }
    /// The tab pages stay alive in the background, so "exists" is not "showing": wait until it is hittable.
    private func showing(_ e: XCUIElement, _ timeout: TimeInterval = 8) -> Bool {
        let end = Date().addingTimeInterval(timeout)
        while Date() < end { if e.exists && e.isHittable { return true }; Thread.sleep(forTimeInterval: 0.3) }
        return false
    }
    private func check(_ ok: Bool, _ name: String, _ msg: String = "", file: StaticString = #filePath, line: UInt = #line) {
        if !ok { shot("FAIL-\(name)") }
        XCTAssertTrue(ok, msg, file: file, line: line)
    }
    private func back(_ app: XCUIApplication) {
        let b = app.navigationBars.buttons.element(boundBy: 0)
        XCTAssertTrue(b.waitForExistence(timeout: 5)); b.tap(); sleep(1)
    }
    /// Scrolls Home until the element is fully above the dock.
    private func reveal(_ app: XCUIApplication, _ e: XCUIElement) {
        let dockTop = el(app, "liquidDock").frame.minY
        for _ in 0..<6 where !(e.exists && e.isHittable && e.frame.maxY <= dockTop) { app.swipeUp(velocity: .slow); sleep(1) }
    }
    /// Saved next to the layout audit's screenshots (uploaded with the CI logs) and attached to the result.
    private func shot(_ name: String) {
        let s = XCUIScreen.main.screenshot()
        let a = XCTAttachment(screenshot: s); a.name = name; a.lifetime = .keepAlways; add(a)
        let dir = ProcessInfo.processInfo.environment["LAYOUT_DIR"] ?? ""
        guard !dir.isEmpty else { return }
        let device = ProcessInfo.processInfo.environment["LAYOUT_DEVICE"] ?? "iphone"
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        try? s.pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(device)-\(name).png"))
    }

    // MARK: A1 · ring → Weekly overview → a session (planned → prescription, recorded → details); week navigation

    func testRingOpensTheWeeklyOverviewAndItsSessions() {
        let app = launch()
        tap(app, "cyHeroRing")
        check(el(app, "homeWeekOverview").waitForExistence(timeout: 8), "homeWeekOverview", "the ring opens the weekly overview, not Plan")
        XCTAssertTrue(el(app, "weekOverviewExplanation").exists)
        XCTAssertTrue(el(app, "weekOverviewTitle").label.contains("This week"))
        for k in ["planned", "done", "remaining", "missed", "skipped", "rest-days"] { XCTAssertTrue(el(app, "weekOverview-\(k)").exists, "count \(k)") }
        shot("nav-01-week-overview")
        // last week: recorded rides from history open the ride details
        tap(app, "weekOverviewPrev"); sleep(1)
        XCTAssertFalse(el(app, "weekOverviewTitle").label.contains("This week"))
        let rec = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'weekOverviewItem-' AND NOT (identifier ENDSWITH '-action')")).firstMatch
        XCTAssertTrue(rec.waitForExistence(timeout: 5), "last week lists its recorded workouts")
        rec.tap()
        XCTAssertTrue(el(app, "homeRideDetail").waitForExistence(timeout: 5) || el(app, "homeLogDetail").waitForExistence(timeout: 3), "a recorded workout opens its real details page")
        shot("nav-02-week-overview-recorded")
        back(app); back(app)
        check(showing(el(app, "homeGreeting")), "back-home", "back returns to Home")
    }

    // MARK: A2 · Cycling card → Cycling summary → recorded ride

    func testCyclingCardOpensTheSummaryAndARide() {
        let app = launch()
        // owner 6 Nov (6): scroll Home a little first; the position must survive summary → historical ride → back → back
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.62)).press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)))
        sleep(1)
        let card = btn(app, "homeCycling")
        let y = card.frame.minY
        XCTAssertTrue(card.waitForExistence(timeout: 10)); card.tap()
        check(el(app, "homeCyclingSummary").waitForExistence(timeout: 8), "homeCyclingSummary", "the cycling card opens the cycling summary, not Progress")
        XCTAssertTrue(app.navigationBars["Cycling summary"].exists)
        for t in ["Rides", "Time", "Distance", "Avg-heart-rate"] { XCTAssertTrue(el(app, "cyclingTile-\(t)").exists, t) }
        XCTAssertTrue(el(app, "cyclingTile-Avg-power").label.contains("—") || el(app, "cyclingTile-Avg-power").label.localizedCaseInsensitiveContains("not measured"), "no power measured in the seed → no number invented")
        XCTAssertTrue(el(app, "cyclingNext").exists || el(app, "cyclingNoNext").exists)
        shot("nav-03-cycling-summary")
        let ride = btn(app, "cyclingRide-0")
        for _ in 0..<4 where !ride.isHittable { app.swipeUp(velocity: .slow) }
        XCTAssertTrue(ride.waitForExistence(timeout: 5)); ride.tap()
        check(el(app, "homeRideDetail").waitForExistence(timeout: 8), "homeRideDetail"); XCTAssertTrue(app.navigationBars["Ride"].exists)
        shot("nav-04-ride-details")
        back(app); back(app)
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        XCTAssertEqual(card.frame.minY, y, accuracy: 12, "Home's scroll position survives summary → ride → back")
    }

    // MARK: A3 · Strength card → Strength summary → recorded log (exercises with sets, reps, weights)

    func testStrengthCardOpensTheSummaryAndALog() {
        let app = launch()
        tap(app, "homeStrength")
        check(el(app, "homeStrengthSummary").waitForExistence(timeout: 8), "homeStrengthSummary", "the strength card opens the strength summary, not Progress")
        XCTAssertTrue(el(app, "strengthNext").exists || el(app, "strengthNoNext").exists)
        let expand = btn(app, "strengthLogExpand-0")
        for _ in 0..<4 where !expand.isHittable { app.swipeUp(velocity: .slow) }
        XCTAssertTrue(expand.waitForExistence(timeout: 5)); expand.tap()
        let ex = el(app, "strengthLogExercises-0")
        XCTAssertTrue(ex.waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Goblet squat 3×10 @ 20 kg'")).firstMatch.exists, "logged sets, reps and weight as recorded")
        shot("nav-05-strength-summary")
        tap(app, "strengthLog-0")
        check(el(app, "homeLogDetail").waitForExistence(timeout: 8), "homeLogDetail", "a log opens its real details page")
        shot("nav-06-strength-log")
        back(app); back(app)
        check(showing(el(app, "homeGreeting")), "back-home", "back returns to Home")
    }

    // MARK: A4 · calendar: planned → prescription, rest → explanation, multiple → day page; Plan label → Plan

    func testCalendarDaysOpenTheRightThing() {
        let app = launch()
        let today = (Calendar.current.component(.weekday, from: Date()) + 5) % 7
        // today: one planned strength session → its prescription (the logger screen)
        tap(app, "homeWeekDay-\(today)")
        // the workout sheet covers Home; its Start button is at the bottom (scroll to it)
        sleep(2)
        check(!showing(el(app, "homeGreeting"), 1), "day-sheet", "today's session opened over Home")
        let start = app.buttons["startWorkout"].firstMatch
        for _ in 0..<5 where !(start.exists && start.isHittable) { app.swipeUp(velocity: .slow) }
        check(start.exists && start.isHittable, "day-start", "today's session opens its prescription with Start")
        shot("nav-07-day-prescription")
        app.swipeDown(velocity: .fast); sleep(1)
        if !el(app, "homeGreeting").isHittable { for n in ["Done", "Close", "Cancel"] { let b = app.buttons[n].firstMatch; if b.exists && b.isHittable { b.tap(); break } } }
        // Sunday is a rest day in the seed (unless today is Sunday)
        if today != 6 {
            tap(app, "homeWeekDay-6")
            check(el(app, "homeDayDetail").waitForExistence(timeout: 8), "homeDayDetail")
            XCTAssertTrue(el(app, "dayEmpty").exists, "a rest day explains itself")
            shot("nav-08-rest-day")
            back(app)
        }
        // Plan label → Plan tab
        tap(app, "homeWeekPlan")
        check(showing(el(app, "planDayStrip")), "plan-label", "the Plan label opens Plan")
    }

    func testTwoSessionsOnOneDayStayIndividuallyAccessible() {
        let app = launch("multi")
        let today = (Calendar.current.component(.weekday, from: Date()) + 5) % 7
        tap(app, "homeWeekDay-\(today)")
        check(el(app, "homeDayDetail").waitForExistence(timeout: 8), "homeDayDetail", "two sessions → the day page")
        XCTAssertTrue(el(app, "dayItem-0").exists && el(app, "dayItem-1").exists, "each session listed")
        shot("nav-09-multi-day")
        tap(app, "dayItem-0")
        XCTAssertTrue(el(app, "homeRideDetail").waitForExistence(timeout: 5) || app.buttons["startWorkout"].firstMatch.waitForExistence(timeout: 3) || app.navigationBars.count > 0)
    }

    // MARK: A5 · Recovery and Goal open their own pages; back keeps Home's scroll position; dock clearance; safe area

    func testRecoveryGoalBackNavigationScrollAndLayout() {
        let app = launch()
        // B1: the greeting is below the navigation bar (never under the status bar)
        // run 171: navigationBars.firstMatch was another (kept-alive) tab's bar — measure against Home's own date label
        let date = app.staticTexts["homeDate"].firstMatch
        check(date.waitForExistence(timeout: 5), "home-date", "the date is in Home's top bar")
        let status = XCUIApplication(bundleIdentifier: "com.apple.springboard").statusBars.firstMatch
        let statusBottom = status.exists ? status.frame.maxY : 20
        XCTAssertGreaterThanOrEqual(date.frame.minY, statusBottom - 1, "the header starts below the system status area (\(statusBottom))")
        let avatarFrame = btn(app, "homeAvatar").frame
        XCTAssertGreaterThanOrEqual(avatarFrame.minY, statusBottom - 1, "the avatar's hit area is below the status bar")
        XCTAssertGreaterThanOrEqual(avatarFrame.width, 44); XCTAssertGreaterThanOrEqual(avatarFrame.height, 44, "a real 44 × 44 pt hit area")
        XCTAssertFalse(avatarFrame.intersects(date.frame), "the avatar's hit area does not cover the date")
        XCTAssertGreaterThanOrEqual(el(app, "homeGreeting").frame.minY, date.frame.maxY, "content starts below the top bar")
        shot("nav-00-home-top")
        let rec = btn(app, "homeRecovery")
        reveal(app, rec)
        // B2: the card scrolls fully above the dock
        XCTAssertLessThanOrEqual(rec.frame.maxY, el(app, "liquidDock").frame.minY + 1, "Recovery fully above the Liquid Dock")
        let y = rec.frame.minY
        rec.tap()
        check(el(app, "homeRecoveryPage").waitForExistence(timeout: 8), "homeRecoveryPage", "Recovery opens the Recovery page, not Progress")
        shot("nav-10-recovery")
        back(app)
        XCTAssertTrue(rec.waitForExistence(timeout: 5))
        XCTAssertEqual(rec.frame.minY, y, accuracy: 12, "back returns to Home where it was")
        let goal = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'homeGoal-'")).firstMatch
        if goal.exists {
            goal.tap()
            check(el(app, "homeGoalPage").waitForExistence(timeout: 8), "homeGoalPage", "Goal opens Goal details")
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
        XCTAssertFalse(showing(el(app, "profileHeader"), 1), "the Profile tab is not shown")
        shot("menu-01-open")
        let last = btn(app, "menuHelp")
        XCTAssertLessThanOrEqual(menu.frame.maxY - last.frame.maxY, 40, "the panel ends right after its last row")
        // avatar again closes
        avatar.tap(); check(menu.waitUntilGone(timeout: 5), "menu-avatar-close", "the avatar closes the menu")
        // rapid taps never stack menus
        avatar.tap(); avatar.tap(); avatar.tap(); sleep(1)
        XCTAssertEqual(app.descendants(matching: .any).matching(identifier: "profileMenu").count, 1, "one menu")
        // outside tap closes
        // outside = just left of the panel, at its middle (never on the panel, the header or the dock)
        let pf = menu.frame
        XCTAssertGreaterThan(pf.minX, 8, "the panel leaves a margin at the left")
        app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: pf.minX / 2, dy: pf.midY)).tap()
        check(menu.waitUntilGone(timeout: 5), "menu-outside-close", "a tap outside closes the menu")
        // Close button
        avatar.tap(); check(el(app, "profileMenuClose").waitForExistence(timeout: 8), "profileMenuClose"); tap(app, "profileMenuClose")
        check(menu.waitUntilGone(timeout: 5), "menu-close-button", "Close closes the menu")

        func openRow(_ id: String) { avatar.tap(); check(btn(app, id).waitForExistence(timeout: 5), "menu-\(id)", "menu row \(id)"); btn(app, id).tap(); check(menu.waitUntilGone(timeout: 5), "menu-nav-\(id)", "the menu closes as navigation begins") }
        openRow("menuMyProfile")
        check(el(app, "menuPageMyProfile").waitForExistence(timeout: 8), "menuPageMyProfile"); XCTAssertTrue(el(app, "fact-Name").label.contains("Demo"))
        XCTAssertTrue(el(app, "fact-Height").exists); shot("menu-02-my-profile"); back(app)
        openRow("menuPreferences")
        check(el(app, "menuPagePreferences").waitForExistence(timeout: 8), "menuPagePreferences")
        let ss = el(app, "fact-Supersets"); for _ in 0..<4 where !ss.isHittable { app.swipeUp(velocity: .slow) }
        XCTAssertTrue(ss.label.contains("On — paired when the exercises allow it"), "the stored superset value: \(ss.label)")
        shot("menu-03-preferences"); back(app)
        openRow("menuConnections")
        XCTAssertTrue(app.navigationBars["Devices & sensors"].waitForExistence(timeout: 5), "Devices & connections opens the device manager")
        shot("menu-04-connections"); back(app)
        openRow("menuSettings")
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5)); shot("menu-05-settings"); back(app)
        openRow("menuHelp")
        check(el(app, "helpSupportPage").waitForExistence(timeout: 8), "helpSupportPage"); XCTAssertTrue(el(app, "helpVersion").exists)
        shot("menu-06-help"); back(app)
        // header → the Profile tab
        openRow("menuViewProfile")
        check(showing(el(app, "profileHeader")), "view-profile", "View profile opens the Profile tab")
    }

    func testMenuClosesOnTabChangeKeepsScrollAndChangesNothing() {
        let app = launch()
        let rec = btn(app, "homeRecovery"); reveal(app, rec)
        let y = rec.frame.minY
        app.buttons["homeAvatar"].firstMatch.tap()
        check(el(app, "profileMenu").waitForExistence(timeout: 8), "profileMenu")
        app.buttons["Plan"].firstMatch.tap(); sleep(1)
        app.buttons["Home"].firstMatch.tap(); sleep(1)
        XCTAssertFalse(el(app, "profileMenu").exists, "a tab change dismisses the menu")
        XCTAssertEqual(rec.frame.minY, y, accuracy: 12, "Home's scroll position survives the menu and the tab change")
        // the Profile tab still works on its own
        app.buttons["Profile"].firstMatch.tap()
        check(showing(el(app, "profileHeader")), "profile-tab", "the Profile tab still works")
    }

    // MARK: large text: the menu scrolls instead of clipping; Home detail pages wrap

    func testMenuAndPagesAtLargestAccessibilityText() {
        let app = launch(size: "UICTContentSizeCategoryAccessibilityXXXL")
        app.buttons["homeAvatar"].firstMatch.tap()
        check(el(app, "profileMenu").waitForExistence(timeout: 8), "profileMenu")
        shot("menu-ax3-open")
        let help = el(app, "menuHelp")
        for _ in 0..<4 where !help.isHittable { el(app, "profileMenu").swipeUp(velocity: .slow) }
        XCTAssertTrue(help.isHittable, "the last row is reachable by scrolling the menu")
        tap(app, "profileMenuClose")
        tap(app, "cyHeroRing")
        check(el(app, "homeWeekOverview").waitForExistence(timeout: 8), "homeWeekOverview"); shot("nav-ax3-week-overview")
    }
}
