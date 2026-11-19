import XCTest

/// Cyclift Lab — FAST focused checks of Progress (compact hero, sheet PH4) and the pages it opens. One theme, the demo
/// athlete, straight to Progress. Every section and every destination is REQUIRED: a missing one fails the check.
/// The stage parts are checked in their honest baseline state only (no stage criteria are approved).
final class LabFastProgress: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = true }

    private func shot(_ name: String) {
        let dir = ProcessInfo.processInfo.environment["LAYOUT_DIR"] ?? ""
        guard !dir.isEmpty else { return }
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent("fast-\(name).png"))
    }
    private func launch(_ extra: [String: String] = [:]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["LAB_FRESH_DEMO"] = "1"
        app.launchEnvironment["LAB_THEME"] = "obsidian"
        for (k, v) in extra { app.launchEnvironment[k] = v }
        app.launch()
        XCTAssertTrue(app.waitForHome(name: "Demo", timeout: 30), "required: Home with the demo athlete")
        return app
    }
    private func el(_ app: XCUIApplication, _ id: String) -> XCUIElement { app.descendants(matching: .any).matching(identifier: id).firstMatch }
    private func openProgress(_ app: XCUIApplication) {
        let b = app.buttons["Progress"].firstMatch
        XCTAssertTrue(b.waitForExistence(timeout: 8), "required: the Progress tab")
        if b.exists { b.tap(); app.settleForScreenshot(1) }
        XCTAssertTrue(el(app, "evolutionTrack").waitForExistence(timeout: 8), "required: Progress shows the Evolution Track")
    }
    /// Waits (bounded, no fixed pause) until an element can be pressed.
    private func pressable(_ e: XCUIElement, _ timeout: TimeInterval = 6) -> Bool {
        guard e.waitForExistence(timeout: timeout) else { return false }
        let until = Date().addingTimeInterval(timeout)
        while !e.isHittable && Date() < until { Thread.sleep(forTimeInterval: 0.2) }
        return e.isHittable
    }
    /// Opens a page from a control of the page underneath, checks the page's own element, optionally runs checks on
    /// it, and returns to where the control is reachable again. The whole test is ONE launch: open, assert, back.
    ///
    /// Every control here is REQUIRED and unconditional for the demo athlete (the detail pages are plain, non-lazy
    /// stacks, so a control below the fold is in the accessibility tree; `tapPresents` scrolls it into the clear band,
    /// bounded, before the tap). Fast check 17 reported four of them "not on the page" (Heart-rate settings, Power
    /// settings and Strength development from analytics, Records & history from Endurance). They were on the page:
    /// the link before each of them had not opened, and this helper then pressed Back, which left the page they are
    /// on. A failed open now presses Back only when a page really was pushed.
    private func visit(_ app: XCUIApplication, _ what: String, control id: String, page: String, shotName: String? = nil, inside: () -> Void = {}) {
        let control = el(app, id)
        XCTAssertTrue(control.waitForExistence(timeout: 8), "required: \(what) (\(id)) is on the page")
        guard control.exists else { return }
        let ok = app.tapPresents(control, page: page)
        XCTAssertTrue(ok, "required: \(what) opens its page (\(page)) at the first tap")
        guard ok else {
            // Recover without leaving the page the control is on: the control is still in the tree when nothing was
            // pushed (a pushed page removes the page underneath from it). Only a wrong page that DID open is left.
            let back = app.navigationBars.buttons.firstMatch
            if !control.exists && back.exists && back.isHittable { back.tap() }
            return
        }
        if let shotName { app.settleForScreenshot(1); shot(shotName) }
        inside()
        XCTAssertTrue(app.backReveals(control), "required: back from \(page) returns to \(what)")
    }

    /// Every section of the landing page is present, in the baseline state where stages are concerned, with screenshots
    /// of the top, the middle and the end.
    func testSectionsArePresent() {
        let app = launch()
        openProgress(app)
        for id in ["progressTitle", "progressMenu", "heroIdentity", "heroStage", "evolutionTrack", "progressV23", "progressDevelopmentIntro",
                   "progressEndurance", "progressStrengthDevelopment", "progressConsistency", "progressZones",
                   "progressNextEvolution", "progressOpenAnalytics", "progressEvolutionTimeline", "progressOpenHistory"] {
            XCTAssertTrue(el(app, id).waitForExistence(timeout: 6), "required: \(id) on Progress (the demo athlete rides and lifts)")
        }
        // no stage is invented: the hero is in the baseline state and shows no generation
        XCTAssertEqual(el(app, "heroStage").label, "ESTABLISHING YOUR BASELINE", "required: the hero's baseline state")
        XCTAssertFalse(el(app, "heroGeneration").exists, "required: no stage is shown (stage criteria are not approved)")
        XCTAssertFalse(el(app, "headerGeneration").exists, "required: no stage in the header")
        let next = el(app, "progressNextEvolution").label, timeline = el(app, "progressEvolutionTimeline").label
        XCTAssertTrue(next.contains("Stage criteria are not set yet"), "required: Next evolution says the criteria are not set (\(next))")
        XCTAssertTrue(timeline.contains("being established") && timeline.contains("No stage events yet"), "required: the timeline is empty and says so (\(timeline))")
        for word in ["G1", "G2", "G3", "The Builder", "The Ascendant", "The Proven"] {
            XCTAssertFalse(next.contains(word) || timeline.contains(word), "required: no stage name on the page (\(word))")
        }
        XCTAssertFalse(el(app, "progressZonesMissing").exists, "required: the demo athlete's time in zones is shown, not 'Not shown'")
        print("LAB-NOTE progress sections: \(el(app, "progressEndurance").label.prefix(120)) | \(el(app, "progressStrengthDevelopment").label.prefix(120)) | \(el(app, "progressConsistency").label.prefix(80)) | \(el(app, "progressZones").label.prefix(140))")
        shot("progress-1-top")
        app.swipeUp(); app.settleForScreenshot(1); shot("progress-2-middle")
        // to the very end of the page: swipe until the last row stops moving (the page is longer than three swipes on a small phone)
        let last = app.buttons["progressOpenHistory"].firstMatch
        var y = last.frame.maxY, swipes = 0
        while swipes < 8 {
            app.swipeUp(); Thread.sleep(forTimeInterval: 0.8); swipes += 1
            let now = last.frame.maxY
            if abs(now - y) < 1 { break }
            y = now
        }
        print("LAB-NOTE progress: the end of the page was reached after \(swipes + 1) swipes in all")
        app.settleForScreenshot(1); shot("progress-3-end")
        // the last row ends above the dock
        let dockTop = el(app, "cradleDock").frame.minY, lastRow = app.buttons["progressOpenHistory"].firstMatch.frame.maxY
        XCTAssertLessThanOrEqual(lastRow, dockTop - 12, "required: the last Progress row ends above the dock (row ends at \(lastRow), dock starts at \(dockTop))")
    }

    /// Every tappable element of the landing page opens its own redesigned page with the athlete's figures, and returns.
    func testEveryControlOpensItsPage() {
        let app = launch()
        openProgress(app)
        visit(app, "the Evolution Track", control: "evolutionTrack", page: "evolutionDetailsTitle", shotName: "progress-4-evolution") {
            XCTAssertTrue(self.el(app, "evolutionNotEvaluated").exists, "required: Athlete Evolution says no stage is evaluated")
        }
        visit(app, "Endurance development", control: "progressEndurance", page: "progressEndurancePage", shotName: "progress-5-endurance") {
            XCTAssertTrue(self.el(app, "progressEndurancePageTitle").exists, "required: the page's own title")
            XCTAssertTrue(self.el(app, "enduranceFTP").exists, "required: FTP with its source")
            self.visit(app, "Time in zones (from Endurance)", control: "enduranceOpenZones", page: "progressZonesPage")
            self.visit(app, "Records & history (from Endurance)", control: "enduranceOpenHistory", page: "progressHistoryPage")
        }
        visit(app, "Strength development", control: "progressStrengthDevelopment", page: "progressStrengthPage", shotName: "progress-6-strength") {
            XCTAssertTrue(self.el(app, "progressStrengthPageTitle").exists, "required: the page's own title")
            self.visit(app, "Records & history (from Strength)", control: "strengthOpenHistory", page: "progressHistoryPage")
        }
        visit(app, "Training consistency", control: "progressConsistency", page: "progressConsistencyPage", shotName: "progress-7-consistency") {
            XCTAssertTrue(self.el(app, "progressConsistencyPageTitle").exists, "required: the page's own title")
            self.visit(app, "Records & history (from Consistency)", control: "consistencyOpenHistory", page: "progressHistoryPage")
        }
        visit(app, "Time in zones", control: "progressZones", page: "progressZonesPage", shotName: "progress-8-zones") {
            XCTAssertTrue(self.el(app, "progressZonesPageTitle").exists, "required: the page's own title")
            self.visit(app, "Power settings", control: "progressOpenPowerSettings", page: "ftpValue")
            self.visit(app, "Heart-rate settings", control: "progressOpenHeartRateSettings", page: "hrMaximum")
        }
        visit(app, "Detailed analytics", control: "progressOpenAnalytics", page: "progressAnalyticsPage", shotName: "progress-9-analytics") {
            XCTAssertTrue(app.navigationBars["Detailed analytics"].firstMatch.exists, "required: the page's own title")
            for id in ["progressPeriod", "analyticsFTP", "ftpSource", "progressRecords", "progressCheckpoints"] {
                XCTAssertTrue(self.el(app, id).exists, "required: \(id) on Detailed analytics")
            }
            self.visit(app, "Endurance development (from analytics)", control: "analyticsOpenEndurance", page: "progressEndurancePage")
            self.visit(app, "Power settings (from analytics)", control: "analyticsOpenPowerSettings", page: "ftpValue")
            self.visit(app, "Strength development (from analytics)", control: "analyticsOpenStrength", page: "progressStrengthPage")
        }
        visit(app, "Records & history", control: "progressOpenHistory", page: "progressHistoryPage", shotName: "progress-10-history") {
            XCTAssertTrue(app.navigationBars["Records & history"].firstMatch.exists, "required: the page's own title")
            XCTAssertFalse(self.el(app, "progressHistoryEmpty").exists, "required: the demo athlete's history is not empty")
            self.visit(app, "a logged strength session", control: "historyRow-strength", page: "progressSessionPage", shotName: "progress-11-session") {
                XCTAssertTrue(self.el(app, "progressSessionFullRecord").exists, "required: the way to the full record (edit, delete)")
            }
            self.visit(app, "a recorded ride", control: "historyRow-ride", page: "progressRidePage", shotName: "progress-12-ride") {
                XCTAssertTrue(self.el(app, "progressRideFullRecord").exists, "required: the way to the full record (graph, delete)")
            }
        }
    }

    /// Sheet PH4's "•••" button: a plain button that opens a compact sheet of plain buttons (not a pull-down menu:
    /// its entries could not be pressed in fast check 17). Every entry closes the sheet and opens a page that exists.
    func testMoreMenuEntriesOpenRealPages() {
        let app = launch()
        openProgress(app)
        let menu = el(app, "progressMenu")
        XCTAssertTrue(pressable(menu, 8), "required: the ••• button")
        let entries: [(String, String, String)] = [("progressMenuAnalytics", "Detailed analytics", "progressAnalyticsPage"),
                                                   ("progressMenuHistory", "Records & history", "progressHistoryPage"),
                                                   ("progressMenuEvolution", "Athlete Evolution", "evolutionDetailsTitle"),
                                                   ("progressMenuPower", "Power settings", "ftpValue"),
                                                   ("progressMenuHeartRate", "Heart-rate settings", "hrMaximum")]
        for (n, (id, label, page)) in entries.enumerated() {
            guard pressable(menu) else { XCTFail("required: the ••• button is reachable before \(label)"); return }
            menu.tap()
            let item = app.buttons[id].firstMatch
            XCTAssertTrue(pressable(item, 5), "required: the ••• sheet offers \(label) (\(id)) as a button that can be pressed")
            guard item.exists else { continue }
            XCTAssertEqual(item.label, label, "required: the entry is named as on sheet PH4")
            if n == 0 {
                for other in entries { XCTAssertTrue(app.buttons[other.0].firstMatch.exists, "required: \(other.1) is in the ••• sheet") }
                app.settleForScreenshot(1); shot("progress-13-menu")
            }
            item.tap()
            let shown = el(app, page).waitForExistence(timeout: 8)
            XCTAssertTrue(shown, "required: \(label) opens its page (\(page))")
            XCTAssertFalse(item.exists, "required: the ••• sheet has closed after choosing \(label)")
            let back = app.navigationBars.buttons.firstMatch
            XCTAssertTrue(shown && pressable(back, 4), "required: \(label) is a pushed page with a way back")
            if shown && back.exists && back.isHittable { back.tap() }
            else if item.exists { app.swipeDown() }   // the sheet stayed up: close it so the next entry is still checked
        }
        XCTAssertTrue(pressable(menu), "required: back on Progress after the ••• pages")
    }
}
