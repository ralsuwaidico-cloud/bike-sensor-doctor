import XCTest

/// Plan's week timeline ("day strip"): layout and touch, at each text size in LAYOUT_SIZES (default L and AX3), on
/// whichever iPhone the runner uses. Owner decision of 16 Nov 2026: the layout is checked by rendered frames, and the
/// touch behaviour by its own tests, instead of the old sideways swipe (see LayoutAudit.testRC2OwnerScreens for why).
/// Demo athlete: the layout audit's (today and tomorrow carry a strength session).
final class PlanLayoutTests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = true }

    private var sizes: [String] {
        let v = ProcessInfo.processInfo.environment["LAYOUT_SIZES"] ?? ""
        return v.isEmpty ? ["L", "AX3"] : v.split(separator: ",").map { String($0) }
    }
    private var outDir: String? { let v = ProcessInfo.processInfo.environment["LAYOUT_DIR"] ?? ""; return v.isEmpty ? nil : v }
    private var device: String { ProcessInfo.processInfo.environment["LAYOUT_DEVICE"] ?? "iphone" }
    private func shot(_ name: String) {
        guard let dir = outDir else { return }
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(device)-plan-\(name).png"))
    }
    private func category(_ s: String) -> String {
        switch s {
        case "XXXL": return "UICTContentSizeCategoryXXXL"
        case "AX3": return "UICTContentSizeCategoryAccessibilityXL"
        default: return "UICTContentSizeCategoryL"
        }
    }
    private func openPlan(_ size: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["BC_UITEST_SEED_JSON"] = LayoutAudit.demoStore()
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", category(size)]
        app.launch()
        XCTAssertTrue(app.waitForHome(name: "Demo", timeout: 30), "\(size): Home did not appear")
        let plan = app.buttons["Plan"].firstMatch
        XCTAssertTrue(plan.waitForExistence(timeout: 8), "\(size): Plan tab"); plan.tap()
        XCTAssertTrue(app.otherElements["planDayStrip"].firstMatch.waitForExistence(timeout: 10), "\(size): the day strip exists")
        app.settleForScreenshot()
        return app
    }
    private func days(_ app: XCUIApplication) -> [XCUIElement] { (1...7).map { app.buttons["planDay-\($0)"].firstMatch } }
    private func chips(_ app: XCUIApplication) -> [XCUIElement] {
        let q = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "planChip-"))
        return (0..<q.count).map { q.element(boundBy: $0) }
    }
    /// The part of the screen a finger can use for the page: below the navigation bar, above the floating dock.
    private func usable(_ app: XCUIApplication) -> (top: CGFloat, bottom: CGFloat) {
        let win = app.windows.firstMatch.frame
        let nav = app.navigationBars.firstMatch
        let dock = app.descendants(matching: .any).matching(identifier: "liquidDock").firstMatch
        return ((nav.exists ? nav.frame.maxY : win.minY + 60) + 4, (dock.exists ? dock.frame.minY : win.maxY - 110) - 4)
    }
    /// A vertical drag on the page's left margin (16 pt from the edge is card padding, not a control), so the scroll
    /// itself cannot activate anything.
    private func scroll(_ app: XCUIApplication, up: Bool) {
        let x: CGFloat = 0.012
        let a = app.coordinate(withNormalizedOffset: CGVector(dx: x, dy: up ? 0.62 : 0.38)), b = app.coordinate(withNormalizedOffset: CGVector(dx: x, dy: up ? 0.38 : 0.62))
        a.press(forDuration: 0.05, thenDragTo: b); app.settleForScreenshot(1)
    }
    /// Brings the element's middle into the usable area by vertical scrolling only. false when it cannot be reached.
    private func bringIntoView(_ app: XCUIApplication, _ e: XCUIElement, tries: Int = 14) -> Bool {
        for _ in 0..<tries {
            let u = usable(app), f = e.frame
            if f.midY > u.top && f.midY < u.bottom && f.minY >= u.top - 1 { return true }
            if f.midY > u.top && f.midY < u.bottom && f.height > (u.bottom - u.top) { return true }       // taller than the area: its middle is in view
            scroll(app, up: f.midY >= u.bottom || f.minY >= u.top)
        }
        return false
    }
    private func dayOfMonth(weekday: Int) -> String {
        var cal = Calendar.current; cal.firstWeekday = 2
        let today = cal.startOfDay(for: Date())
        let monday = cal.date(byAdding: .day, value: -((cal.component(.weekday, from: today) + 5) % 7), to: today)!
        let offset = (weekday + 5) % 7
        return String(cal.component(.day, from: cal.date(byAdding: .day, value: offset, to: monday)!))
    }

    /// 1 + 2: the strip, all seven days and every session chip lie inside the screen's width and inside the strip, with
    /// real size; a day is at least the minimum touch height. Frames are the rendered ones (accessibility snapshot).
    func testStripDaysAndChipsFitTheWidthAtEveryTextSize() {
        for size in sizes {
            let app = openPlan(size)
            let win = app.windows.firstMatch.frame
            let strip = app.otherElements["planDayStrip"].firstMatch.frame
            XCTAssertTrue(strip.minX >= win.minX - 1 && strip.maxX <= win.maxX + 1 && strip.width > 100, "\(size): the day strip does not fit the width \(strip) in \(win)")
            let ds = days(app)
            XCTAssertEqual(ds.filter { $0.exists }.count, 7, "\(size): seven days")
            for d in ds where d.exists {
                let f = d.frame
                XCTAssertTrue(f.minX >= strip.minX - 1 && f.maxX <= strip.maxX + 1, "\(size): \(d.identifier) outside the strip \(f) / \(strip)")
                XCTAssertGreaterThanOrEqual(f.height, 43.5, "\(size): \(d.identifier) lower than the minimum touch height: \(f.height)")
                XCTAssertGreaterThan(f.width, 20, "\(size): \(d.identifier) has no usable width \(f)")
                XCTAssertFalse(d.label.isEmpty, "\(size): \(d.identifier) has no spoken name")
            }
            // days are stacked top to bottom in week order without overlapping
            let ordered = [2, 3, 4, 5, 6, 7, 1].map { app.buttons["planDay-\($0)"].firstMatch }.filter { $0.exists }.map { $0.frame }
            for (a, b) in zip(ordered, ordered.dropFirst()) { XCTAssertLessThanOrEqual(a.maxY, b.minY + 1, "\(size): two days overlap \(a) / \(b)") }
            let cs = chips(app)
            XCTAssertGreaterThan(cs.count, 0, "\(size): the demo week has sessions")
            var lowest: CGFloat = 999
            for c in cs {
                let f = c.frame
                XCTAssertTrue(f.minX >= strip.minX - 1 && f.maxX <= strip.maxX + 1, "\(size): session '\(c.label)' is clipped sideways \(f) / \(strip)")
                XCTAssertGreaterThanOrEqual(f.width, 55.5, "\(size): session '\(c.label)' narrower than its minimum width: \(f.width)")
                XCTAssertGreaterThanOrEqual(f.height, 43.5, "\(size): session '\(c.label)' has a touch target lower than 44 pt: \(f.height)")
                lowest = min(lowest, f.height)
            }
            // touch targets of different controls must not overlap: no chip on another chip, no chip on a day button
            let frames = cs.map { $0.frame }
            for i in frames.indices { for j in frames.indices where j > i {
                let x = frames[i].intersection(frames[j])
                XCTAssertTrue(x.isNull || x.width < 1 || x.height < 1, "\(size): two session targets overlap \(frames[i]) / \(frames[j])")
            } }
            for d in ds where d.exists { for f in frames {
                let x = d.frame.intersection(f)
                XCTAssertTrue(x.isNull || x.width < 1 || x.height < 1, "\(size): a session target overlaps \(d.identifier) \(f) / \(d.frame)")
            } }
            // kept for the owner: the measured sizes
            let line = "\(device) \(size): strip \(Int(strip.width)) of \(Int(win.width)) pt wide · \(cs.count) session chips · lowest chip \(Int(lowest)) pt high\n"
            if let dir = outDir { let u = URL(fileURLWithPath: dir).appendingPathComponent("plan-layout-measurements.txt"); let old = (try? String(contentsOf: u, encoding: .utf8)) ?? ""; try? (old + line).write(to: u, atomically: true, encoding: .utf8) }
            shot("\(size.lowercased())-1-top")
            app.terminate()
        }
    }

    /// 3: every one of the seven days can be brought into view by vertical scrolling alone and is then touchable.
    func testAllSevenDaysAreReachableByVerticalScrolling() {
        for size in sizes {
            let app = openPlan(size)
            for n in [2, 3, 4, 5, 6, 7, 1] {
                let d = app.buttons["planDay-\(n)"].firstMatch
                XCTAssertTrue(d.exists, "\(size): planDay-\(n)")
                guard d.exists else { continue }
                XCTAssertTrue(bringIntoView(app, d), "\(size): planDay-\(n) cannot be scrolled into view (frame \(d.frame))")
                XCTAssertTrue(d.isHittable, "\(size): planDay-\(n) is in view but not touchable")
                XCTAssertFalse(app.descendants(matching: .any).matching(identifier: "homeDayDetail").firstMatch.exists, "\(size): scrolling to planDay-\(n) opened a day")
            }
            shot("\(size.lowercased())-2-last-day")
            app.terminate()
        }
    }

    /// 4: tapping a day opens that day's page; tapping a session opens that session.
    func testTappingADayOpensThatDayAndTappingASessionOpensThatSession() {
        var cal = Calendar.current; cal.firstWeekday = 2
        let todayWeekday = cal.component(.weekday, from: Date())
        for size in sizes {
            let app = openPlan(size)
            let day = app.buttons["planDay-\(todayWeekday)"].firstMatch
            XCTAssertTrue(day.exists && bringIntoView(app, day), "\(size): today's row")
            day.tap()
            let page = app.descendants(matching: .any).matching(identifier: "homeDayDetail").firstMatch
            XCTAssertTrue(page.waitForExistence(timeout: 8), "\(size): tapping today's day opens the Day page")
            // Run 248: `navigationBars.firstMatch` was another tab's bar ("Progress") — every tab page stays alive. The
            // Day page's own title is looked for among all bars; the expectation (today's date in the title) is unchanged.
            let titles = app.navigationBars.allElementsBoundByIndex.map { $0.identifier }
            let dayNumber = dayOfMonth(weekday: todayWeekday)
            XCTAssertTrue(titles.contains { $0.contains(dayNumber) && $0 != "Plan" && $0 != "Progress" && $0 != "Profile" }, "\(size): the Day page is today's (bar titles \(titles), expected day \(dayNumber))")
            shot("\(size.lowercased())-3-day-page")
            app.navigationBars.buttons.firstMatch.tap()
            XCTAssertTrue(app.otherElements["planDayStrip"].firstMatch.waitForExistence(timeout: 8), "\(size): back on Plan")
            app.settleForScreenshot()

            // today's session chip: the one drawn inside today's row
            XCTAssertTrue(bringIntoView(app, day), "\(size): today's row again")
            let row = day.frame
            let chip = chips(app).first { $0.frame.midY >= row.minY - 1 && $0.frame.midY <= row.maxY + 1 }
            XCTAssertNotNil(chip, "\(size): today's session chip")
            guard let c = chip else { app.terminate(); continue }
            let name = c.label.components(separatedBy: ",").first ?? ""
            XCTAssertTrue(name.lowercased().contains("strength"), "\(size): today's demo session is strength ('\(c.label)')")
            XCTAssertTrue(c.isHittable, "\(size): today's session chip is touchable")
            c.tap()
            let done = app.buttons["Done"].firstMatch
            XCTAssertTrue(done.waitForExistence(timeout: 8), "\(size): tapping the session opens its sheet")
            XCTAssertFalse(page.exists, "\(size): the session tap must open the session, not the Day page")
            let texts = app.staticTexts.allElementsBoundByIndex.prefix(40).map { $0.label }.joined(separator: " | ")
            XCTAssertTrue(texts.contains("Strength"), "\(size): the sheet is the strength session (\(texts.prefix(200)))")
            shot("\(size.lowercased())-4-session-sheet")
            if done.exists { done.tap() }
            app.terminate()
        }
    }

    /// 5: a deliberate vertical scroll that starts ON a session chip scrolls the page and opens nothing.
    func testAScrollThatStartsOnASessionDoesNotOpenIt() {
        for size in sizes {
            let app = openPlan(size)
            guard let c = chips(app).first(where: { bringIntoView(app, $0) && $0.isHittable }) else { XCTFail("\(size): no session chip in view"); app.terminate(); continue }
            let before = c.frame
            // Run 248 (owner-size phone, standard text): the drag went DOWN from a chip while the page was already at
            // its top, where nothing can move, so "did not scroll" said nothing about the chip. The finger now always
            // moves up, which scrolls a page that is longer than the screen (Plan always is with the demo week).
            let from = c.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            let to = from.withOffset(CGVector(dx: 0, dy: -160))
            from.press(forDuration: 0.05, thenDragTo: to)
            app.settleForScreenshot(1)
            XCTAssertFalse(app.buttons["Done"].firstMatch.exists, "\(size): a scroll that started on a session opened its sheet")
            XCTAssertFalse(app.descendants(matching: .any).matching(identifier: "homeDayDetail").firstMatch.exists, "\(size): a scroll that started on a session opened the Day page")
            XCTAssertTrue(app.otherElements["planDayStrip"].firstMatch.exists, "\(size): still on Plan")
            let moved = abs(c.frame.minY - before.minY)
            XCTAssertGreaterThan(moved, 20, "\(size): the page did not scroll when dragged from a session (moved \(moved) pt) — the gesture was swallowed")
            shot("\(size.lowercased())-5-after-scroll")
            app.terminate()
        }
    }
}
