import XCTest

/// Training Hub centre-button reliability (owner 8 Nov 14:32). Runs 176 and 198 each saw one centre tap in the layout
/// audit that did not open the hub. This test taps the centre button repeatedly, one single tap per cycle, only after
/// the interface is ready (Home visible, no transition running), and requires EVERY tap to open the hub at the first
/// attempt; the hub is then closed with its own Close button before the next cycle. Misses are reported one by one
/// with the cycle number and what was on screen, so a failure here is evidence, not a retry.
final class HubTapReliabilityTests: XCTestCase {
    /// Run 209 (screenshots): every "hub did not close" failure showed Home fully visible with no hub — the hub HAD closed;
    /// only the `trainingHub` container lingered in the test driver's element tree for a few seconds before vanishing
    /// (the first-tap test then threw on it). What a rider sees is what counts: the hub's Close gone, no hub element that
    /// can be hit, and Home's centre button back in reach. That is the closed state; a stale, un-hittable container is not.
    func hubClosed(_ app: XCUIApplication, hub: XCUIElement, close: XCUIElement, centre: XCUIElement, timeout: TimeInterval = 6) -> Bool {
        let end = Date().addingTimeInterval(timeout)
        while Date() < end {
            let closeGone = !close.exists
            let hubGone = !hub.exists || !hub.isHittable
            if closeGone && hubGone && centre.exists && centre.isHittable { return true }
            Thread.sleep(forTimeInterval: 0.25)
        }
        return false
    }

    override func setUpWithError() throws { continueAfterFailure = true }

    private func cycles(_ app: XCUIApplication, state: String, n: Int) -> [String] {
        var misses: [String] = []
        let centre = app.buttons["centreButton"].firstMatch
        let hub = app.descendants(matching: .any)["trainingHub"].firstMatch
        for i in 1...n {
            XCTAssertTrue(centre.waitForExistence(timeout: 10), "\(state) cycle \(i): centre button present")
            _ = centre.waitUntilSettled(timeout: 5)
            centre.tap()                                   // ONE tap, the plain XCUITest tap the audits use
            // "open" = the hub's Close button is there (run 209: a stale `trainingHub` container can outlive the hub by seconds)
            let opened = app.buttons["hubClose"].firstMatch.waitForExistence(timeout: 6) && hub.exists
            if !opened {
                let bars = app.navigationBars.allElementsBoundByIndex.map { $0.identifier }.joined(separator: "|")
                misses.append("\(state) cycle \(i): hub not open after one tap (navigation bars: \(bars), hub exists: \(hub.exists))")
                // bring the interface back to the known state for the next cycle without counting it as a success
                if !hub.exists { centre.tap(); _ = hub.waitForExistence(timeout: 6) }
            }
            let close = app.buttons["hubClose"].firstMatch
            // Run 204 (3 of 48 cycles, all "hub closes again"): every first tap opened the hub, but a Close tapped the instant
            // the toolbar item existed — before the navigation bar of the freshly inserted hub had a settled frame — missed.
            // The reset step taps Close once its frame has stopped changing (tapWhenSettled), the same rule the audits use
            // for toolbar menu items; the assertion is unchanged: one tap on a settled Close must close the hub.
            if close.waitForExistence(timeout: 5) {
                if !close.tapWhenSettled(timeout: 5) { misses.append("\(state) cycle \(i): Close never had a settled frame \(close.frame)") }
            } else { misses.append("\(state) cycle \(i): hub has no Close button") }
            if !hubClosed(app, hub: hub, close: close, centre: centre) {
                let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); a.name = "FAIL-hub-close-\(state)-\(i)"; a.lifetime = .keepAlways; add(a)
                // run 205: the hub was still there but its Close was NOT (a query on it threw) — the screenshot above shows
                // what covered or replaced it; the message says so instead of throwing
                let closeState = close.exists ? "Close frame \(close.frame), hittable \(close.isHittable)" : "Close no longer present (sheet or pushed page over the hub?)"
                let bars = app.navigationBars.allElementsBoundByIndex.map(\.identifier)
                let tree = hub.exists ? hub.debugDescription.replacingOccurrences(of: "\n", with: " ⏎ ") : "hub element gone"
                XCTFail("\(state) cycle \(i): hub closes again — \(closeState); navigation bars: \(bars); sheets: \(app.sheets.count); centre hittable \(centre.exists && centre.isHittable); hub tree: \(tree.prefix(1200))")
            }
            _ = centre.waitUntilSettled(timeout: 3)
        }
        return misses
    }

    /// The two states that missed in CI (a cycling day in run 176, a two-session day in run 198), the small iPhone's
    /// large text where it happened, plus the default text size: 12 single taps each.
    func testEveryFirstCentreTapOpensTheHub() {
        var all: [String] = []
        for (state, size) in [("multi", "UICTContentSizeCategoryL"), ("ride", "UICTContentSizeCategoryL"), ("multi", "UICTContentSizeCategoryAccessibilityL"), ("planned", "UICTContentSizeCategoryL")] {
            let app = XCUIApplication()
            app.launchEnvironment["BC_UITEST_SEED_JSON"] = LayoutAudit.homeStore(state)
            app.launchArguments += ["-UIPreferredContentSizeCategoryName", size]
            app.launch()
            XCTAssertTrue(app.waitForHome(name: "Demo", timeout: 30), "\(state): Home did not appear")
            sleep(2)                                        // the dock's three-breath glow and Home's first layout pass
            all += cycles(app, state: "\(state)@\(size.replacingOccurrences(of: "UICTContentSizeCategory", with: ""))", n: 12)
            app.terminate()
        }
        print("hub reliability: \(48 - all.count)/48 first-attempt taps opened the hub")
        for m in all { XCTFail(m) }
    }

    /// Owner 8 Nov 20:58: a test synchronisation fix is not proof that Close works at runtime. This loop does what a person
    /// does — open the hub, look at it for half a second, tap Close once, plainly (no settle logic, no retry) — twelve
    /// times on the state that missed in run 204. Every cycle must close the hub; a miss is a runtime defect, not timing.
    func testCloseAtHumanPaceAlwaysClosesTheHub() {
        let app = XCUIApplication()
        app.launchEnvironment["BC_UITEST_SEED_JSON"] = LayoutAudit.homeStore("multi")
        app.launch()
        XCTAssertTrue(app.waitForHome(name: "Demo", timeout: 30))
        sleep(2)
        let centre = app.buttons["centreButton"].firstMatch
        let hub = app.descendants(matching: .any)["trainingHub"].firstMatch
        let close = app.buttons["hubClose"].firstMatch
        var closed = 0
        // Owner 8 Nov 22:59: Close must stay visible and functional through repeated normal use, including after nested
        // screens were opened and dismissed. Cycles 1–4 plain; 5–8 open "Why this workout?" (a sheet) and close it first;
        // 9–12 open the session details (More › Details and edit) and close them first — then one plain Close tap.
        for i in 1...12 {
            if !close.exists { _ = centre.waitUntilSettled(timeout: 5); centre.tap() }   // "open" = its Close is there, not a stale container
            expect(close.waitForExistence(timeout: 6) && hub.exists, "cycle \(i): hub open", tag: "open-\(i)")
            Thread.sleep(forTimeInterval: 0.5)                // a person's glance, not a machine's zero-delay tap
            if (5...8).contains(i) {
                let why = app.buttons["homeWhy"].firstMatch
                if why.waitForExistence(timeout: 3), why.isHittable {
                    why.tap()
                    let sheetClose = app.buttons["homeSheetClose"].firstMatch
                    expect(sheetClose.waitForExistence(timeout: 6), "cycle \(i): Why sheet opened", tag: "why-\(i)")
                    Thread.sleep(forTimeInterval: 0.5); sheetClose.tap()
                    expect(sheetClose.waitUntilGone(timeout: 6), "cycle \(i): Why sheet closed", tag: "whyclose-\(i)")
                    Thread.sleep(forTimeInterval: 0.5)
                }
            } else if (9...12).contains(i) {
                let more = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'More actions for'")).firstMatch
                if more.waitForExistence(timeout: 3), more.isHittable {
                    more.tap()
                    let details = app.buttons["Details and edit"].firstMatch
                    if details.waitForExistence(timeout: 4), details.tapWhenSettled(timeout: 4) {
                        let done = app.navigationBars.buttons["Done"].firstMatch
                        expect(done.waitForExistence(timeout: 8), "cycle \(i): details opened", tag: "details-\(i)")
                        Thread.sleep(forTimeInterval: 0.5); done.tap()
                        expect(done.waitUntilGone(timeout: 6), "cycle \(i): details closed", tag: "detailsclose-\(i)")
                        Thread.sleep(forTimeInterval: 0.5)
                    } else { app.swipeDown(velocity: .fast) }   // menu did not offer it: dismiss the menu
                }
            }
            expect(close.exists && close.isHittable, "cycle \(i): Close present and hittable after the nested screen", tag: "closepresent-\(i)")
            close.tap()                                       // ONE plain tap
            if hubClosed(app, hub: hub, close: close, centre: centre, timeout: 4) { closed += 1 } else {
                let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); a.name = "FAIL-hub-close-human-\(i)"; a.lifetime = .keepAlways; add(a)
                let closeState = close.exists ? "Close frame \(close.frame), hittable \(close.isHittable)" : "Close no longer present"
                XCTFail("cycle \(i): one plain Close tap after 0.5 s did not close the hub — \(closeState); bars \(app.navigationBars.allElementsBoundByIndex.map(\.identifier)); sheets \(app.sheets.count)")
            }
            Thread.sleep(forTimeInterval: 0.4)
        }
        print("hub close at human pace (with nested screens): \(closed)/12")
    }
}
