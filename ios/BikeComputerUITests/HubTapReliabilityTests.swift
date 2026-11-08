import XCTest

/// Training Hub centre-button reliability (owner 8 Nov 14:32). Runs 176 and 198 each saw one centre tap in the layout
/// audit that did not open the hub. This test taps the centre button repeatedly, one single tap per cycle, only after
/// the interface is ready (Home visible, no transition running), and requires EVERY tap to open the hub at the first
/// attempt; the hub is then closed with its own Close button before the next cycle. Misses are reported one by one
/// with the cycle number and what was on screen, so a failure here is evidence, not a retry.
final class HubTapReliabilityTests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = true }

    private func cycles(_ app: XCUIApplication, state: String, n: Int) -> [String] {
        var misses: [String] = []
        let centre = app.buttons["centreButton"].firstMatch
        let hub = app.descendants(matching: .any)["trainingHub"].firstMatch
        for i in 1...n {
            XCTAssertTrue(centre.waitForExistence(timeout: 10), "\(state) cycle \(i): centre button present")
            _ = centre.waitUntilSettled(timeout: 5)
            centre.tap()                                   // ONE tap, the plain XCUITest tap the audits use
            let opened = hub.waitForExistence(timeout: 6)
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
            if !hub.waitUntilGone(timeout: 6) {
                let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); a.name = "FAIL-hub-close-\(state)-\(i)"; a.lifetime = .keepAlways; add(a)
                XCTFail("\(state) cycle \(i): hub closes again (Close frame \(close.frame), hittable \(close.isHittable))")
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
}
