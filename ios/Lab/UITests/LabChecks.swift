import XCTest

/// Cyclift Lab only (ios/project-lab.yml). Drives the built Lab app with its own generated demo athlete — no seed, no
/// reset hook — and keeps screenshots when the runner sets LAYOUT_DIR.
final class LabChecks: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = true }

    private var outDir: String? { let v = ProcessInfo.processInfo.environment["LAYOUT_DIR"] ?? ""; return v.isEmpty ? nil : v }
    private func shot(_ name: String) {
        guard let dir = outDir else { return }
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent("lab-\(name).png"))
    }
    private func banner(_ app: XCUIApplication) -> Bool { app.staticTexts["CYCLIFT LAB · DEMO DATA"].firstMatch.waitForExistence(timeout: 10) }
    private func tab(_ app: XCUIApplication, _ name: String) {
        let b = app.buttons[name].firstMatch
        XCTAssertTrue(b.waitForExistence(timeout: 8), "tab \(name)")
        if b.exists { b.tap(); app.settleForScreenshot(2) }
    }
    /// Home v2.3 controls open their pages at the first tap, and the pages are really presented (see `tapPresents`).
    /// The regression check for the defect of Lab runs 20–31: Home asked the window for its bottom inset while its body
    /// was being evaluated, was never redrawn again, and so no tapped control ever showed its page — while every handler
    /// ran. Each page is opened, left, and the next one opened, so "navigate again after returning" is covered too.
    func test0HomeControlsPresentTheirPages() throws {
        let app = XCUIApplication()
        app.launchEnvironment["LAB_FRESH_DEMO"] = "1"
        app.launchEnvironment["LAB_THEME"] = "obsidian"
        app.launch()
        XCTAssertTrue(banner(app), "Lab is running")
        XCTAssertTrue(app.waitForHome(name: "Demo", timeout: 20), "Home is shown")
        app.settleForScreenshot(2)
        func el(_ id: String) -> XCUIElement { app.descendants(matching: .any).matching(identifier: id).firstMatch }
        let day = app.buttons["scheduleDay-0"].firstMatch
        let steps: [(String, XCUIElement, String)] = [
            ("the first schedule day", day, "homeDayDetail"),
            ("the Consistency ring", el("indicatorConsistency"), "homeWeekOverview"),
            ("the Recovery indicator", el("indicatorRecovery"), "homeRecoveryPage"),
            ("the Endurance card", el("sportCard-endurance"), "homeCyclingSummary"),
            ("the Strength card", el("sportCard-strength"), "homeStrengthSummary"),
            ("the Sleep bar", el("sleepBar"), "homeRecoveryPage"),
            ("a Key metrics row", el("metricRow-restingHR"), "homeRecoveryPage"),
            ("the first schedule day, again after returning", day, "homeDayDetail")]
        for (n, (what, control, page)) in steps.enumerated() {
            let ok = app.tapPresents(control, page: page)
            print("LAB-NOTE Home navigation: \(what) presented its page at the first tap: \(ok)")
            XCTAssertTrue(ok, "required: \(what) presents its page (\(page)) at the first tap")
            if n == 0 || n == 3 { app.settleForScreenshot(1); shot("home-nav-\(n)-\(page)") }
            XCTAssertTrue(app.backReveals(control), "required: back from \(page) returns to Home, with \(what) reachable again")
        }
        // the two interactions that are not pushed pages still work afterwards
        let coach = el("homeCoachAction").exists ? el("homeCoachAction") : el("homeCoachQuiet")
        XCTAssertTrue(coach.waitForExistence(timeout: 6), "the Coach preview is on Home"); app.reveal(coach)
        XCTAssertTrue(coach.isHittable, "the Coach preview can be tapped after the page visits")
        let avatar = app.buttons["homeAvatar"].firstMatch
        XCTAssertTrue(avatar.isHittable, "the avatar can be tapped"); avatar.tap()
        let profile = el("profileSectionA")
        XCTAssertTrue(profile.waitForExistence(timeout: 8) && profile.isHittable, "required: the avatar shows Profile")
        app.terminate()
    }

    /// The strip's theme name ("Theme: Ocean").
    private func themeName(_ app: XCUIApplication) -> String { app.staticTexts["labThemeName"].firstMatch.label }
    /// Navigation v1.2 / Profile v2.0: Profile has no tab; the Home avatar opens the one Profile.
    private func openProfile(_ app: XCUIApplication) -> Bool {
        tab(app, "Home")
        let avatar = app.buttons["homeAvatar"].firstMatch
        guard avatar.waitForExistence(timeout: 8) else { return false }
        avatar.tap(); app.settleForScreenshot(2)
        return app.descendants(matching: .any).matching(identifier: "profileSectionA").firstMatch.waitForExistence(timeout: 8)
    }
    /// Profile → Data, Help & About → the existing settings page (export, permissions, delete all data).
    private func openSettings(_ app: XCUIApplication) -> Bool {
        let f = app.descendants(matching: .any).matching(identifier: "profileSectionF").firstMatch
        var tries = 0
        while !(f.exists && f.isHittable) && tries < 6 { app.swipeUp(); tries += 1 }
        guard f.exists else { return false }
        f.tap()
        let row = app.descendants(matching: .any).matching(identifier: "profileSettings").firstMatch
        guard row.waitForExistence(timeout: 8) else { return false }
        row.tap(); return true
    }
    private let themes: [(id: String, title: String)] = [("obsidian", "Obsidian"), ("arctic", "Arctic"), ("ocean", "Ocean"), ("forest", "Forest"), ("sandstone", "Sandstone"), ("highContrast", "High Contrast")]

    /// The same five screens in each theme, each from a fresh launch in that theme.
    func test1FiveScreensInSixThemes() {
        var sawNotNow = false
        for (i, t) in themes.enumerated() {
            let app = XCUIApplication()
            app.launchEnvironment["LAB_THEME"] = t.id
            app.launch()
            XCTAssertTrue(app.waitForHome(name: "Demo", timeout: 30), "\(t.id): Home with the demo athlete")
            XCTAssertTrue(banner(app), "\(t.id): the demo banner is shown")
            let tag = "\(i + 1)-\(t.id)"
            // Navigation v1.2 rev 1.1: the dock is the cradle; there are exactly three tabs and no Profile tab
            if i == 0 {
                let dock = app.descendants(matching: .any).matching(identifier: "cradleDock").firstMatch
                XCTAssertTrue(dock.waitForExistence(timeout: 8), "the cradle dock is shown")
                for name in ["Home", "Plan", "Progress"] { XCTAssertTrue(dock.buttons[name].exists, "tab \(name) in the dock") }
                XCTAssertFalse(dock.buttons["Profile"].exists, "Profile must not be a tab")
                let ball = app.buttons["centreButton"].firstMatch, home = dock.buttons["Home"].firstMatch
                XCTAssertTrue(ball.exists && ball.frame.maxX <= home.frame.minX + 1, "the Train ball is left of Home (\(ball.frame) / \(home.frame))")
                XCTAssertEqual(ball.frame.width, 72, accuracy: 1, "Train ball is 72 pt"); XCTAssertEqual(ball.frame.height, 72, accuracy: 1)
                // Navigation v1.2, sheet F1 / specification §1: the ball's bottom edge is 34 pt above the bottom of the screen
                // on a phone with a home indicator, 16 pt without one; the ball starts 14 pt from the left edge.
                let below = app.frame.height - ball.frame.maxY
                print("LAB-NOTE dock: ball bottom \(below) pt above the screen bottom, left \(ball.frame.minX) pt, dock frame \(dock.frame)")
                XCTAssertTrue(abs(below - 34) <= 1.5 || abs(below - 16) <= 1.5, "the Train ball sits 34 pt (16 pt without a home indicator) above the bottom of the screen, as in F1 — it is \(below) pt")
                XCTAssertEqual(ball.frame.minX, 14, accuracy: 1, "the Train ball starts 14 pt from the left edge")
                // Home v2.3 (provisional design): the prototype's sections are all there, on the demo athlete's records
                for id in ["homeV23", "indicatorConsistency", "indicatorMix", "indicatorRecovery", "sleepBar", "metricRow-restingHR"] {
                    XCTAssertTrue(app.descendants(matching: .any).matching(identifier: id).firstMatch.waitForExistence(timeout: 8), "Home v2.3 shows \(id)")
                }
                XCTAssertTrue(app.buttons["scheduleDay-0"].firstMatch.exists || app.descendants(matching: .any).matching(identifier: "scheduleEmpty").firstMatch.exists, "Home v2.3 shows the week's schedule (or says nothing is planned)")
                XCTAssertFalse(app.descendants(matching: .any).matching(identifier: "cyHeroRing").firstMatch.exists, "the previous dashboard is not shown in the redesign")
                let rec = app.descendants(matching: .any).matching(identifier: "indicatorRecovery").firstMatch
                XCTAssertFalse((rec.value as? String ?? "").contains("%"), "Recovery never shows a percentage (\(rec.value ?? ""))")
            }
            app.settleForScreenshot(2); shot("\(tag)-1-home")
            // Lab run 11: the card is one accessibility element of its own and is not reported as a button
            let coach = app.descendants(matching: .any).matching(identifier: "homeCoachAction").firstMatch
            if coach.exists { XCTAssertTrue(coach.label.hasPrefix("Demo, rule-based, not AI."), "\(t.id): the Coach card says it is demo and not AI (\(coach.label))") }
            if i < 2 {
                // Coach page: the Home card (or its quiet line) opens the one Coach timeline; it says rules-based, not AI
                let quiet = app.descendants(matching: .any).matching(identifier: "homeCoachQuiet").firstMatch
                let link = app.buttons["homeCoachOpen"].firstMatch
                XCTAssertTrue(coach.exists || quiet.exists, "\(t.id): Home has a way into the Coach page")
                if !(coach.exists || quiet.exists) { app.terminate(); continue }
                var way = quiet
                if coach.exists {
                    app.reveal(coach); app.settleForScreenshot()
                    if link.exists {
                        // the card leads to its own destination (a hybrid-coach suggestion here): that route must still work…
                        coach.tap()
                        // Lab run 18: which card the demo athlete has depends on the day (run 17: a suggestion sheet; run 18: not).
                        // Any of the card's legitimate destinations is accepted — and exactly one must appear.
                        let sheetClose = app.buttons["homeSheetClose"].firstMatch, planTitle = app.staticTexts["planTitle"].firstMatch, startWorkout = app.buttons["startWorkout"].firstMatch
                        var where_ = "nowhere"; let until = Date().addingTimeInterval(10)
                        while where_ == "nowhere" && Date() < until {
                            if sheetClose.exists { where_ = "its own sheet" } else if planTitle.exists { where_ = "Plan" } else if startWorkout.exists { where_ = "the session page" } else { usleep(300_000) }
                        }
                        XCTAssertNotEqual(where_, "nowhere", "\(t.id): the Coach card leads to its destination (sheet, Plan or session page)")
                        if i == 0 { print("LAB-NOTE Coach card today leads to: \(where_)"); app.settleForScreenshot(1); shot("\(tag)-1a-coach-card-destination") }
                        switch where_ {
                        case "its own sheet": sheetClose.tap()
                        case "Plan": tab(app, "Home")
                        case "the session page":       // v1.4 preparation screen (Back) or, for a session that cannot start, the existing page (Done)
                            let back = app.buttons["prepareBack"].firstMatch
                            if back.exists { back.tap() } else { app.buttons["Done"].firstMatch.tap() }
                        default: break
                        }
                        app.settleForScreenshot(1)
                        XCTAssertTrue(app.waitForHome(name: "Demo", timeout: 10), "\(t.id): back on Home after the card's destination")
                        app.reveal(link); app.settleForScreenshot()
                        // …and the Coach page is one tap away on its own line
                        way = link
                    } else { way = coach }
                }
                do {
                    app.reveal(way); app.settleForScreenshot()
                    way.tap()
                    XCTAssertTrue(app.staticTexts["coachTitle"].firstMatch.waitForExistence(timeout: 8), "\(t.id): the Coach page opens")
                    XCTAssertTrue(app.staticTexts["coachRulesNote"].firstMatch.exists, "\(t.id): the Coach page says it follows rules and is not an AI chat")
                    if i == 0 {
                        // the conversation: a supported question is answered by rules from the demo athlete's records; anything
                        // else gets the plain statement that AI chat is not connected. Nothing is invented.
                        func entry(_ part: String) -> XCUIElement { app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'coachEntry-chat-' AND label CONTAINS %@", part)).firstMatch }
                        // G1: Timeline | Ask. The questions and their answers are on Ask.
                        XCTAssertTrue(app.buttons["coachTabTimeline"].firstMatch.isSelected, "required: the page opens on Timeline")
                        app.settleForScreenshot(1); shot("\(tag)-1b-coach")
                        // G1 "Not now": a deliberate postponement. Only an open suggestion carries it, so this depends on the demo records.
                        let notNow = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'coachNotNow-'")).firstMatch
                        if notNow.exists {
                            notNow.tap()
                            let said = app.staticTexts.matching(NSPredicate(format: "identifier BEGINSWITH 'coachPostponed-'")).firstMatch
                            XCTAssertTrue(said.waitForExistence(timeout: 5), "required: Not now is recorded and said on the card")
                            XCTAssertFalse(notNow.exists, "a postponed suggestion offers Review only")
                            print("LAB-NOTE coach Not now: \(said.label)"); shot("\(tag)-1b2-coach-postponed")
                            sawNotNow = true
                        } else { print("LAB-NOTE coach Not now: the demo athlete has no open suggestion, so the button was not on screen (logic tests cover the record)") }
                        app.buttons["coachTabAsk"].firstMatch.tap()
                        XCTAssertTrue(app.staticTexts["coachAskNote"].firstMatch.waitForExistence(timeout: 5), "required: Ask says its answers come from fixed rules, with no AI model")
                        app.buttons["coachAsk-week"].firstMatch.tap()
                        XCTAssertTrue(entry("You, Question").waitForExistence(timeout: 8), "the question is kept in the timeline")
                        XCTAssertTrue(entry("Coach, Answer, Rules").waitForExistence(timeout: 8), "the answer is labelled as rules-based")
                        let field = app.descendants(matching: .any).matching(identifier: "coachField").firstMatch
                        XCTAssertTrue(field.waitForExistence(timeout: 5), "the question field"); field.tap(); field.typeText("Should I buy new wheels")
                        app.buttons["coachSend"].firstMatch.tap()
                        XCTAssertTrue(entry("AI chat is not connected yet").waitForExistence(timeout: 8), "a question the rules cannot answer says AI chat is not connected")
                        app.settleForScreenshot(2); shot("\(tag)-1c-coach-chat")
                    } else {
                        if i == 1 && sawNotNow {
                            // this is a new launch of the app: the postponement made in the first launch is still there, and the suggestion can still be reviewed
                            let said = app.staticTexts.matching(NSPredicate(format: "identifier BEGINSWITH 'coachPostponed-'")).firstMatch
                            XCTAssertTrue(said.waitForExistence(timeout: 5), "required: Not now is still recorded after a relaunch")
                            XCTAssertTrue(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'coachOpen-'")).firstMatch.exists, "required: a postponed suggestion can still be reviewed")
                            XCTAssertFalse(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'coachNotNow-'")).firstMatch.exists, "it is not offered as new again")
                            print("LAB-NOTE coach Not now after relaunch: \(said.label)")
                        }
                        app.settleForScreenshot(2); shot("\(tag)-1b-coach")
                    }
                    app.buttons["coachClose"].firstMatch.tap(); app.settleForScreenshot(2)
                    XCTAssertTrue(app.waitForHome(name: "Demo", timeout: 10), "\(t.id): closing the Coach page returns to Home")
                }
            }
            app.swipeUp(); app.settleForScreenshot(); shot("\(tag)-2-home-lower")
            if i == 0 {
                // Home v2.3 interactions on the athlete's records: a schedule day opens that day; the graph and the metrics are there
                app.swipeDown(); app.swipeDown(); app.settleForScreenshot(2)
                // after the Coach steps above (a tab round trip, a sheet, typing): a schedule day still presents its page
                let day = app.buttons["scheduleDay-0"].firstMatch
                XCTAssertTrue(app.tapPresents(day, page: "homeDayDetail"), "required: after the Coach steps a schedule day presents that day's page at the first tap")
                app.settleForScreenshot(1); shot("\(tag)-2a-home-day")
                XCTAssertTrue(app.backReveals(day), "required: back from the day page returns to Home")
                let chart = app.descendants(matching: .any).matching(identifier: "trendsChart").firstMatch, emptyTrends = app.descendants(matching: .any).matching(identifier: "trendsEmpty").firstMatch
                XCTAssertTrue(chart.exists || emptyTrends.exists, "Home v2.3 shows the trend graph or says there is nothing recorded")
                if chart.exists { app.reveal(chart, top: 170, bottomMargin: 130); app.settleForScreenshot(1); shot("\(tag)-2b-home-trends") }
                // Navigation v1.2, C1 / C2: at the end of the page the last control is clear of the cradle (the dock's highest
                // point is 115 pt above the bottom of the screen with a home indicator, 97 pt without; clearance at least 12 pt)
                for _ in 0..<4 { app.swipeUp() }
                app.settleForScreenshot(1); shot("\(tag)-2c-home-end")
                let rows = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'metricRow-'"))
                let last = rows.element(boundBy: max(0, rows.count - 1))
                XCTAssertTrue(last.exists, "the Key metrics rows are the end of Home v2.3")
                let ball = app.buttons["centreButton"].firstMatch
                let indicator = abs((app.frame.height - ball.frame.maxY) - 34) <= 1.5
                let lastAbove = app.frame.height - last.frame.maxY
                print("LAB-NOTE Home end of page: last control ends \(lastAbove) pt above the screen bottom (scrolling inset \(indicator ? 128 : 110))")
                XCTAssertGreaterThanOrEqual(lastAbove, (indicator ? 115.1 : 97.1) + 12 - 1, "at the end of Home the last control is at least 12 pt above the cradle (it ends \(lastAbove) pt above the screen bottom)")
                app.swipeDown(); app.swipeDown(); app.swipeDown(); app.settleForScreenshot(1)
            }
            let centre = app.buttons["centreButton"].firstMatch
            XCTAssertTrue(centre.waitForExistence(timeout: 5), "\(t.id): the Train ball")     // required: no silent skip
            centre.tap(); app.settleForScreenshot(2); shot("\(tag)-3-train"); XCTAssertTrue(banner(app), "\(t.id): banner on Train")
            if i == 0 {
                // Training Hub v1.4: the Train ball opens the compact panel first; "All training" expands it into the Hub
                let panel = app.descendants(matching: .any).matching(identifier: "trainPanel").firstMatch
                XCTAssertTrue(panel.waitForExistence(timeout: 8), "the compact Train panel opens from the Train ball")
                XCTAssertTrue(app.staticTexts["trainPanelTitle"].firstMatch.exists, "the panel names today's session or state")
                let all = app.buttons["trainPanelAll"].firstMatch
                XCTAssertTrue(all.exists, "All training"); all.tap()
                XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "trainingHub").firstMatch.waitForExistence(timeout: 8), "All training opens the full Hub")
                app.settleForScreenshot(2); shot("\(tag)-3b-hub")
            }
            tab(app, "Plan"); shot("\(tag)-4-plan")
            if i == 0 {
                // Plan v2.0: the schedule-first screen, fed from the athlete record (Lab: the demo athlete, and it says so)
                XCTAssertTrue(app.staticTexts["planTitle"].firstMatch.waitForExistence(timeout: 8), "Plan v2.0 is shown")
                let note = app.staticTexts["planSampleNote"].firstMatch
                XCTAssertTrue(note.exists && note.label.contains("demo athlete"), "Plan says the data is the demo athlete's")
                XCTAssertTrue(app.staticTexts["planDayHeader"].firstMatch.exists, "today's day is selected")
                app.swipeUp(); app.settleForScreenshot(); shot("\(tag)-4b-plan-lower")
            }
            tab(app, "Progress"); shot("\(tag)-5-progress")
            if i == 0 {
                // Progress: the approved compact hero, in its honest "no stage yet" state, over the real analysis
                let track = app.descendants(matching: .any).matching(identifier: "evolutionTrack").firstMatch
                XCTAssertTrue(track.waitForExistence(timeout: 8), "Progress shows the Evolution Track")
                XCTAssertFalse(app.staticTexts["heroGeneration"].firstMatch.exists, "no stage may be shown: there is no approved stage evaluation")
                XCTAssertTrue(track.label.contains("No generation yet"), "the track says no stage is evaluated (\(track.label))")
                // Progress v2.3 (sheet PH4): open sections with the athlete's own figures; the full analysis and the history are one tap away
                func pe(_ id: String) -> XCUIElement { app.descendants(matching: .any).matching(identifier: id).firstMatch }
                XCTAssertTrue(pe("progressDevelopmentIntro").exists, "required: the v2.3 sections under the hero")
                for s in ["progressEndurance", "progressStrengthDevelopment", "progressConsistency"] { XCTAssertTrue(pe(s).exists, "required: \(s) (the demo athlete rides and lifts)") }
                print("LAB-NOTE progress: \(pe("progressEndurance").label.prefix(140)) | \(pe("progressStrengthDevelopment").label.prefix(140)) | \(pe("progressConsistency").label.prefix(80)) | zones: \(pe("progressZones").exists ? String(pe("progressZones").label.prefix(80)) : (pe("progressZonesMissing").exists ? pe("progressZonesMissing").label : "absent"))")
                app.swipeUp(); app.settleForScreenshot(); shot("\(tag)-5b-progress-lower")
                app.swipeUp(); app.settleForScreenshot(); shot("\(tag)-5c-progress-end")
                let analytics = app.buttons["progressOpenAnalytics"].firstMatch
                XCTAssertTrue(analytics.waitForExistence(timeout: 5), "required: Detailed analytics"); app.reveal(analytics); analytics.tap()
                XCTAssertTrue(app.navigationBars["Detailed analytics"].firstMatch.waitForExistence(timeout: 8), "Detailed analytics opens the app's full analysis"); app.settleForScreenshot(1); shot("\(tag)-5d-progress-analytics")
                app.navigationBars.buttons.firstMatch.tap()
                let history = app.buttons["progressOpenHistory"].firstMatch
                XCTAssertTrue(history.waitForExistence(timeout: 8), "required: Records & history"); app.reveal(history); history.tap()
                XCTAssertTrue(app.navigationBars["Records & history"].firstMatch.waitForExistence(timeout: 8), "Records & history opens the session history"); shot("\(tag)-5e-progress-history")
                app.navigationBars.buttons.firstMatch.tap()
                XCTAssertTrue(history.waitForExistence(timeout: 8), "back on Progress")
            }
            XCTAssertTrue(openProfile(app), "\(t.id): Profile opens from the Home avatar"); shot("\(tag)-6-profile"); XCTAssertTrue(banner(app), "\(t.id): banner on Profile")
            app.terminate()
        }
    }

    /// Choosing a theme in Profile › App Preferences › Appearance changes the app at once: no relaunch, the strip names
    /// the new theme, and the picture really changes. All six, then back to the first.
    func test2ThemesSwitchWithoutRelaunch() {
        let app = XCUIApplication()
        app.launchEnvironment["LAB_THEME"] = "obsidian"
        app.launch()
        XCTAssertTrue(app.waitForHome(name: "Demo", timeout: 30))
        var last = XCUIScreen.main.screenshot().pngRepresentation
        for i in Array(1..<themes.count) + [0] {
            let t = themes[i]
            XCTAssertTrue(openProfile(app), "\(t.id): Profile from the avatar")
            let prefs = app.descendants(matching: .any).matching(identifier: "profileSectionE").firstMatch
            XCTAssertTrue(prefs.waitForExistence(timeout: 8), "App Preferences"); prefs.tap()
            let appearance = app.descendants(matching: .any).matching(identifier: "profileAppearance").firstMatch
            XCTAssertTrue(appearance.waitForExistence(timeout: 8), "Appearance"); appearance.tap()
            let row = app.buttons["theme-\(t.id)"].firstMatch
            XCTAssertTrue(row.waitForExistence(timeout: 8), "theme row \(t.title)")
            _ = row.waitUntilHittable(timeout: 4); row.tap()
            app.settleForScreenshot(2)
            XCTAssertEqual(app.state, .runningForeground, "\(t.id): still the same running app")
            XCTAssertTrue(themeName(app).contains(t.title), "\(t.id): the strip names the theme now shown (\(themeName(app)))")
            XCTAssertTrue(app.waitForHome(name: "Demo", timeout: 10), "\(t.id): Home is shown after the change")
            let now = XCUIScreen.main.screenshot().pngRepresentation
            XCTAssertNotEqual(now, last, "\(t.id): the screen did not change")
            last = now; shot("switch-\(i + 1)-\(t.id)")
        }
    }

    /// The strength journey on the demo athlete: Train ball → compact panel → Start → the v1.4 recorder → log, undo,
    /// minimise and return, rest, every set → Finish → Save → confirmed "Saved" → Done.
    func test2bStrengthSessionIsRecordedAndSaved() {
        let app = XCUIApplication()
        app.launchEnvironment["LAB_FRESH_DEMO"] = "1"      // independent of every other test
        app.launchEnvironment["LAB_THEME"] = "obsidian"
        app.launch()
        XCTAssertTrue(app.waitForHome(name: "Demo", timeout: 30))
        func el(_ id: String) -> XCUIElement { app.descendants(matching: .any).matching(identifier: id).firstMatch }
        app.buttons["centreButton"].firstMatch.tap()
        let primary = app.buttons["trainPanelPrimary"].firstMatch
        XCTAssertTrue(primary.waitForExistence(timeout: 8), "the panel offers today's session"); shot("strength-0-panel"); primary.tap()
        // Training Hub v1.4, sheet 01a "J2 Prepare": the approved preparation screen, not the previous session sheet
        XCTAssertTrue(el("strengthPrepareV14").waitForExistence(timeout: 10), "required: the v1.4 preparation screen opens from the Train panel")
        let start = app.buttons["startWorkout"].firstMatch
        XCTAssertTrue(start.waitForExistence(timeout: 5) && start.isHittable, "required: Start is on screen without scrolling")
        XCTAssertEqual(start.label, "Start")
        XCTAssertTrue(el("prepareOverline").label.hasPrefix("Strength · planned"), "says what and when: \(el("prepareOverline").label)")
        XCTAssertFalse(el("prepareTitle").label.isEmpty, "the session's name")
        XCTAssertTrue(el("prepareSummary").label.hasPrefix("About "), "planned length and equipment: \(el("prepareSummary").label)")
        let rows = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'prepareRow-'"))
        XCTAssertGreaterThan(rows.count, 0, "required: the exercises are listed in order")
        print("LAB-NOTE preparation: '\(el("prepareTitle").label)' · \(el("prepareSummary").label) · \(rows.count) exercises listed; first: \(rows.firstMatch.label)")
        XCTAssertFalse(el("moreMenu").exists, "the previous session sheet is not what is shown")
        shot("strength-1-prepare")
        // nothing is lost: More opens the existing session page (adjust sets, swap, routine, move, skip, quick log)
        app.buttons["prepareMore"].firstMatch.tap()
        XCTAssertTrue(el("moreMenu").waitForExistence(timeout: 8), "required: More opens the existing session page with its options")
        print("LAB-NOTE full session page from More: Adjust sets \(app.buttons["Adjust sets"].firstMatch.exists ? "is offered" : "is NOT visible without scrolling")")
        shot("strength-1b-full-page")
        app.buttons["Done"].firstMatch.tap(); app.settleForScreenshot(1)
        // and from the panel again: the preparation screen, then Start
        if !app.buttons["trainPanelPrimary"].firstMatch.exists { app.buttons["centreButton"].firstMatch.tap() }
        XCTAssertTrue(primary.waitForExistence(timeout: 8), "the panel offers today's session again"); primary.tap()
        XCTAssertTrue(el("strengthPrepareV14").waitForExistence(timeout: 10), "the preparation screen again")
        XCTAssertTrue(start.waitForExistence(timeout: 5) && start.isHittable, "Start again")
        start.tap()
        XCTAssertTrue(el("strengthRecorderV14").waitForExistence(timeout: 10), "the v1.4 recorder opens")
        XCTAssertTrue(el("recorderExercise").exists && el("recorderSet").exists && el("recorderReps").exists, "exercise, set and reps are shown")
        XCTAssertTrue(el("recorderNext").exists, "the next exercise is always visible")
        XCTAssertEqual(el("recorderState").label, "Recording")
        shot("strength-2-recorder")
        // change the reps, log one set, see it logged with rest, undo it
        let reps = el("recorderReps").label
        app.buttons["recorderRepsPlus"].firstMatch.tap()
        XCTAssertNotEqual(el("recorderReps").label, reps, "+ changes the reps")
        app.buttons["recorderRepsMinus"].firstMatch.tap()
        let firstSet = el("recorderSet").label
        let log = el("logSet")
        XCTAssertTrue(log.waitForExistence(timeout: 5), "the Log set button")
        XCTAssertTrue(el("recorderName").label.contains("DEMO DATA"), "the recorder says the athlete is the demo athlete")
        log.tap()
        XCTAssertTrue(el("recorderLogged").waitForExistence(timeout: 5), "the logged set is named, with Undo")
        XCTAssertTrue(el("restTimer").exists || el("restPlanned").exists, "rest is shown")
        shot("strength-3-logged")
        app.buttons["recorderUndo"].firstMatch.tap()
        XCTAssertFalse(el("recorderLogged").exists, "Undo removes the logged line")
        XCTAssertEqual(el("recorderSet").label, firstSet, "Undo returns to the same set")
        // log again, minimise, come back: the session, its logged set and Undo are still there
        log.tap()
        XCTAssertTrue(el("recorderLogged").waitForExistence(timeout: 5))
        app.buttons["recorderMinimise"].firstMatch.tap()
        XCTAssertTrue(start.waitForExistence(timeout: 10), "minimising returns to the session's page; the workout keeps running")
        XCTAssertTrue(start.label.contains("Resume"), "the page offers Resume (\(start.label))")
        XCTAssertTrue(el("strengthPrepareV14").exists && start.isHittable, "required: the preparation screen is the page underneath, with Resume on screen")
        start.tap()
        XCTAssertTrue(el("recorderLogged").waitForExistence(timeout: 10), "after returning, the logged set and Undo are still shown")
        // pause and resume
        app.buttons["recorderPause"].firstMatch.tap()
        XCTAssertTrue(el("recorderState").label.hasPrefix("Paused"), "paused is said in words"); shot("strength-4-paused")
        app.buttons["recorderPause"].firstMatch.tap()
        XCTAssertEqual(el("recorderState").label, "Recording")
        // every remaining set
        let finish = el("nextSetFinish")
        var taps = 0, sawSuperset = false
        while !finish.exists && taps < 80 {
            if el("recorderOverline").label.hasPrefix("SUPERSET") { if !sawSuperset { shot("strength-5-superset") }; sawSuperset = true }
            let skip = app.buttons["restSkip"].firstMatch; if skip.exists { skip.tap() }
            if log.exists { log.tap() }; taps += 1
        }
        XCTAssertTrue(finish.waitForExistence(timeout: 5), "after the last set the recorder offers Finish (\(taps) sets logged)")
        print("LAB-NOTE strength journey: \(taps) sets logged; superset seen: \(sawSuperset)")
        shot("strength-6-all-done"); finish.tap()
        // Finish — sheet 06e X1: a page of its own (not a sheet), the clock paused, Save and Back to workout at the bottom
        let save = app.buttons["saveWorkout"].firstMatch
        // (Changed check, Lab 34: the page's own container name "finishV14" is not exposed because the recorder around it is one
        // named container — every control on the page was found and passed. The page is now recognised by its own first line.)
        XCTAssertTrue(el("finishOverline").waitForExistence(timeout: 8), "required: the v1.4 Finish page")
        XCTAssertTrue(save.waitForExistence(timeout: 5) && save.isHittable, "required: Save is on screen"); XCTAssertEqual(save.label, "Save")
        XCTAssertTrue(el("finishOverline").label.hasPrefix("Strength · paused while you decide"), "says the session is paused: \(el("finishOverline").label)")
        XCTAssertEqual(el("finishCount").label, "Complete", "every set was logged")
        XCTAssertTrue(el("finishTime").exists && el("finishSets").exists && el("finishPlan").exists, "required: Time, Sets and Plan rows")
        XCTAssertTrue(el("finishPlan").label.contains("Will be marked done"), "the plan is not marked before the save: \(el("finishPlan").label)")
        print("LAB-NOTE finish: '\(el("finishTitle").label)' · \(el("finishTime").label) · \(el("finishSets").label) · \(el("finishPlan").label)")
        shot("strength-7-finish")
        // Discard… always asks first (06f X8); Keep workout changes nothing
        app.buttons["finishDiscard"].firstMatch.tap()
        XCTAssertTrue(el("discardDialog").waitForExistence(timeout: 5), "required: Discard asks for confirmation")
        XCTAssertTrue(el("discardMessage").label.contains("logged set"), "says what would be deleted: \(el("discardMessage").label)")
        shot("strength-7b-discard"); app.buttons["discardKeep"].firstMatch.tap()
        XCTAssertFalse(el("discardDialog").exists, "Keep workout closes the question"); XCTAssertTrue(save.isHittable, "and the Finish page is unchanged")
        // Back to workout returns to the recorder with the clock running again; Finish opens the page again
        app.buttons["finishBackToWorkout"].firstMatch.tap()
        XCTAssertTrue(el("recorderState").waitForExistence(timeout: 5), "Back to workout shows the recorder")
        XCTAssertEqual(el("recorderState").label, "Recording", "the clock that Finish paused is running again")
        app.buttons["finishWorkout"].firstMatch.tap()
        XCTAssertTrue(save.waitForExistence(timeout: 5) && save.isHittable, "Finish again"); save.tap()
        // Saved — 06f X5: only now is the plan marked and the review offered
        XCTAssertTrue(el("saveConfirmed").waitForExistence(timeout: 10), "the save is confirmed")
        XCTAssertTrue(el("savedWorkout").label.contains("Saved on this phone"), "says where it is saved")
        XCTAssertTrue(el("savedPlan").label.contains("Marked done"), "the plan itself now says done: \(el("savedPlan").label)")
        XCTAssertEqual(app.buttons["saveReview"].firstMatch.label, "Add how it felt", "the review is offered, not required")
        XCTAssertTrue(app.buttons["saveDone"].firstMatch.isHittable, "Done leaves without a review")
        print("LAB-NOTE saved: \(el("saveSummary").label) · \(el("savedPlan").label)")
        shot("strength-8-saved")
        // The optional review — sheet 06a: nothing is pre-filled; one answer alone can be saved
        app.buttons["saveReview"].firstMatch.tap()
        XCTAssertTrue(el("reviewV14").waitForExistence(timeout: 8), "the review opens")
        XCTAssertEqual(el("reviewTitle").label, "How was it?"); XCTAssertTrue(el("reviewSavedLine").label.hasPrefix("Saved · "), "says the workout is already saved: \(el("reviewSavedLine").label)")
        for v in ["reviewIntensityValue", "reviewPerformanceValue", "reviewEffortValue"] { XCTAssertEqual(el(v).label, "–", "\(v) starts unanswered") }
        XCTAssertEqual(el("reviewEffortWord").label, "Not answered")
        let saveReview = app.buttons["reviewSave"].firstMatch
        XCTAssertTrue(saveReview.isHittable, "required: the page does not scroll — the button is on screen from the start")
        XCTAssertFalse(saveReview.isEnabled, "nothing answered: nothing to save"); XCTAssertEqual(saveReview.label, "Nothing to save yet")
        shot("strength-8a-review-empty")
        app.buttons["reviewEffortPlus"].firstMatch.tap(); app.buttons["reviewEffortPlus"].firstMatch.tap(); app.buttons["reviewEffortPlus"].firstMatch.tap()
        XCTAssertEqual(el("reviewEffortValue").label, "8", "Effort is answered"); XCTAssertEqual(el("reviewEffortWord").label, "Hard")
        XCTAssertEqual(el("reviewPerformanceValue").label, "–", "Performance stays unanswered")
        // a drag inside a column sets that column and nothing else (the page cannot scroll instead)
        let track = el("reviewIntensityTrack")
        track.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.9)).press(forDuration: 0.1, thenDragTo: track.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35)))
        XCTAssertNotEqual(el("reviewIntensityValue").label, "–", "dragging the Intensity column answers Intensity"); XCTAssertEqual(el("reviewPerformanceValue").label, "–")
        print("LAB-NOTE review: Intensity \(el("reviewIntensityValue").label) (\(el("reviewIntensityWord").label)) after a drag · Effort 8 (Hard) · Performance unanswered")
        shot("strength-8b-review")
        // "Anything your Coach should know?" opens to four choices; Pain opens its sheet (where, then how)
        app.buttons["reviewCoachRow"].firstMatch.tap()
        for c in ["reviewChipPain", "reviewChipFatigue", "reviewChipEquipment", "reviewChipNote"] { XCTAssertTrue(app.buttons[c].firstMatch.waitForExistence(timeout: 4), "required: \(c)") }
        shot("strength-8c-review-coach")
        app.buttons["reviewChipPain"].firstMatch.tap()
        XCTAssertTrue(el("reviewPainSheet").waitForExistence(timeout: 6), "the pain sheet")
        XCTAssertTrue(app.buttons["reviewArea-knees"].firstMatch.exists && app.buttons["reviewPain-soreness"].firstMatch.exists, "required: areas and levels")
        app.buttons["reviewArea-knees"].firstMatch.tap(); shot("strength-8d-review-pain")
        app.buttons["reviewPainDone"].firstMatch.tap()        // an area without a level: nothing about pain is stored
        XCTAssertTrue(saveReview.waitForExistence(timeout: 5) && saveReview.isHittable)
        XCTAssertFalse(app.buttons["reviewChipPain"].firstMatch.isSelected, "an area alone does not report pain")
        XCTAssertTrue(saveReview.isEnabled, "one answer is enough to save"); XCTAssertEqual(saveReview.label, "Save review"); saveReview.tap()
        // 06e: "optional review → return". (Changed expectation: the earlier screen stayed open with a "Review saved" line
        // that is not on the approved sheet. A review that cannot be stored keeps the page open and says so.)
        XCTAssertFalse(el("reviewNotSaved").waitForExistence(timeout: 2), "the review was stored")
        app.settleForScreenshot(2)
        XCTAssertFalse(el("reviewV14").exists, "a saved review returns"); XCTAssertFalse(el("strengthRecorderV14").exists, "and leaves the recorder")
        // updated training state: back on Home, today's strength session is no longer offered to start
        let close = app.buttons["Done"].firstMatch
        if close.waitForExistence(timeout: 5) { close.tap() }       // the session page's own Done (optional: it may already be closed)
        XCTAssertTrue(app.waitForHome(name: "Demo", timeout: 15), "back on Home")
        app.settleForScreenshot(2); shot("strength-9-home-after")
        app.buttons["centreButton"].firstMatch.tap()
        XCTAssertTrue(el("trainPanel").waitForExistence(timeout: 8), "the Train panel")
        let again = app.buttons["trainPanelPrimary"].firstMatch
        XCTAssertFalse(again.exists && again.label.hasPrefix("Start"), "today's strength session is no longer offered to start (\(again.exists ? again.label : "no button"))")
        shot("strength-10-panel-after")
    }

    /// The save lifecycle on one session (sheets 06e X2, X3, X4 and 06f X5, X6, X7): nothing logged → no Save; partial →
    /// a save made to fail keeps the workout and offers Try again; a save that cannot be confirmed is checked again and
    /// never assumed; "Saved" appears only after the file on the phone holds the workout. The two failures are
    /// switched on for this launch by simulator-only test settings; the store's own save is not altered.
    func test2b3SaveFailureAndUnconfirmedSaveKeepTheWorkout() {
        let app = XCUIApplication()
        app.launchEnvironment["LAB_FRESH_DEMO"] = "1"
        app.launchEnvironment["LAB_THEME"] = "obsidian"
        app.launchEnvironment["BC_UITEST_SAVE_FAIL"] = "1"            // the first Save tap fails without writing
        app.launchEnvironment["BC_UITEST_SAVE_UNCONFIRMED"] = "1"     // the first read-back check answers "not confirmed"
        app.launch()
        XCTAssertTrue(app.waitForHome(name: "Demo", timeout: 30))
        func el(_ id: String) -> XCUIElement { app.descendants(matching: .any).matching(identifier: id).firstMatch }
        app.buttons["centreButton"].firstMatch.tap()
        let primary = app.buttons["trainPanelPrimary"].firstMatch
        XCTAssertTrue(primary.waitForExistence(timeout: 8)); primary.tap()
        let start = app.buttons["startWorkout"].firstMatch
        XCTAssertTrue(start.waitForExistence(timeout: 10)); start.tap()
        XCTAssertTrue(el("strengthRecorderV14").waitForExistence(timeout: 10), "the recorder")
        // X3 — nothing logged: no Save is offered
        app.buttons["finishWorkout"].firstMatch.tap()
        XCTAssertTrue(el("finishNothing").waitForExistence(timeout: 8), "required: 'Nothing was logged'")
        XCTAssertEqual(el("finishTitle").label, "Nothing was logged")
        XCTAssertFalse(app.buttons["saveWorkout"].firstMatch.exists, "required: no Save when no set is logged")
        XCTAssertTrue(app.buttons["finishMarkDone"].firstMatch.exists, "Mark done without details is offered")
        XCTAssertTrue(el("finishPlan").label.contains("Not marked done"), el("finishPlan").label)
        shot("save-1-nothing-logged")
        app.buttons["finishBackToWorkout"].firstMatch.tap()
        // X2 — one set logged: partial, and what was not done is named
        let log = el("logSet"); XCTAssertTrue(log.waitForExistence(timeout: 8), "back in the recorder"); log.tap()
        XCTAssertTrue(el("recorderLogged").waitForExistence(timeout: 5))
        app.buttons["finishWorkout"].firstMatch.tap()
        let save = app.buttons["saveWorkout"].firstMatch
        XCTAssertTrue(save.waitForExistence(timeout: 8)); XCTAssertEqual(save.label, "Save")
        XCTAssertTrue(el("finishCount").label.hasPrefix("Partial · 1 of "), "partial, counted: \(el("finishCount").label)")
        XCTAssertTrue(el("finishNotDone").exists, "required: the Not done row"); XCTAssertTrue(el("finishPlan").label.contains("as partial"), el("finishPlan").label)
        print("LAB-NOTE partial finish: \(el("finishCount").label) · \(el("finishNotDone").label) · \(el("finishPlan").label)")
        shot("save-2-partial"); save.tap()
        // X6 — the save failed: never shown as success, the workout is kept, Try again is offered
        XCTAssertTrue(el("saveFailed").waitForExistence(timeout: 10), "required: 'Not saved yet' after a failed save")
        XCTAssertFalse(el("saveConfirmed").exists, "a failed save is never shown as Saved")
        XCTAssertEqual(save.label, "Try again"); XCTAssertTrue(el("finishPlan").label.contains("Not marked done yet"), el("finishPlan").label)
        XCTAssertTrue(el("finishSets").label.contains("1 of "), "the logged set is still there: \(el("finishSets").label)")
        shot("save-3-not-saved"); save.tap()
        // X7 — written, but the read-back did not confirm it: not shown as Saved, checked again
        XCTAssertTrue(el("saveUnconfirmed").waitForExistence(timeout: 10), "required: 'Save not confirmed' when the check does not confirm")
        XCTAssertFalse(el("saveConfirmed").exists, "an unconfirmed save is never shown as Saved")
        XCTAssertTrue(el("unconfirmedSets").label.contains("kept"), el("unconfirmedSets").label)
        shot("save-4-not-confirmed")
        // The app closes while the save is still "not confirmed". After a relaunch (no failure switches, no fresh demo):
        // the workout is there once, nothing is in progress, and today's session is not offered again.
        app.terminate()
        app.launchEnvironment["LAB_FRESH_DEMO"] = nil; app.launchEnvironment["BC_UITEST_SAVE_FAIL"] = nil; app.launchEnvironment["BC_UITEST_SAVE_UNCONFIRMED"] = nil
        app.launch()
        XCTAssertTrue(app.waitForHome(name: "Demo", timeout: 30))
        app.buttons["centreButton"].firstMatch.tap()
        XCTAssertTrue(el("trainPanel").waitForExistence(timeout: 8))
        let again = app.buttons["trainPanelPrimary"].firstMatch
        XCTAssertFalse(again.exists && (again.label.hasPrefix("Start") || again.label.hasPrefix("Resume")), "after the failed save, the retry and a restart during the uncertain save, the session is saved once and nothing is in progress (\(again.exists ? again.label : "no button"))")
        print("LAB-NOTE save lifecycle with restart: nothing logged → partial → not saved → not confirmed → app closed → relaunch: saved once; panel offers '\(again.exists ? again.label : "nothing to start")'")
        shot("save-5-after-restart")
    }

    /// "Check again" (06f X7 → X5): a save the read-back did not confirm is checked again, the existing workout is found,
    /// and only then is "Saved" shown. Nothing is written twice.
    func test2b4CheckAgainFindsTheSavedWorkout() {
        let app = XCUIApplication()
        app.launchEnvironment["LAB_FRESH_DEMO"] = "1"
        app.launchEnvironment["LAB_THEME"] = "obsidian"
        app.launchEnvironment["BC_UITEST_SAVE_UNCONFIRMED"] = "2"     // the read-back after Save, and the first read of "Check again", answer "the file does not hold it"
        app.launch()
        XCTAssertTrue(app.waitForHome(name: "Demo", timeout: 30))
        func el(_ id: String) -> XCUIElement { app.descendants(matching: .any).matching(identifier: id).firstMatch }
        app.buttons["centreButton"].firstMatch.tap()
        let primary = app.buttons["trainPanelPrimary"].firstMatch
        XCTAssertTrue(primary.waitForExistence(timeout: 8)); primary.tap()
        let start = app.buttons["startWorkout"].firstMatch
        XCTAssertTrue(start.waitForExistence(timeout: 10)); start.tap()
        let log = el("logSet"); XCTAssertTrue(log.waitForExistence(timeout: 10), "the recorder"); log.tap()
        XCTAssertTrue(el("recorderLogged").waitForExistence(timeout: 5))
        app.buttons["finishWorkout"].firstMatch.tap()
        let save = app.buttons["saveWorkout"].firstMatch
        XCTAssertTrue(save.waitForExistence(timeout: 8)); save.tap()
        XCTAssertTrue(el("saveUnconfirmed").waitForExistence(timeout: 10), "required: 'Save not confirmed'")
        XCTAssertFalse(el("saveConfirmed").exists, "not shown as Saved"); XCTAssertFalse(el("saveFailed").exists, "and not shown as a failure")
        let check = app.buttons["saveCheckAgain"].firstMatch
        // (Changed expectation, Lab 39: the test expected a second "not confirmed" here. That was written before "Check again"
        // gained its recovery: when the file can be read and does not hold the workout, the same record is written again and
        // read back. So one tap is enough — the test's old expectation, not the app, was wrong.)
        shot("save-6-not-confirmed")
        check.tap()        // reads: not there → writes the same record again → reads: found
        XCTAssertTrue(el("saveConfirmed").waitForExistence(timeout: 10), "required: Saved once the check finds the workout")
        XCTAssertTrue(el("savedPlan").label.contains("Marked done · partial"), el("savedPlan").label)
        XCTAssertTrue(el("saveSummary").label.contains("1 of "), "what was saved: \(el("saveSummary").label)")
        shot("save-7-saved-after-check")
        app.buttons["saveDone"].firstMatch.tap()
        app.terminate(); app.launchEnvironment["LAB_FRESH_DEMO"] = nil; app.launchEnvironment["BC_UITEST_SAVE_UNCONFIRMED"] = nil; app.launch()
        XCTAssertTrue(app.waitForHome(name: "Demo", timeout: 30))
        app.buttons["centreButton"].firstMatch.tap()
        XCTAssertTrue(el("trainPanel").waitForExistence(timeout: 8))
        let again = app.buttons["trainPanelPrimary"].firstMatch
        XCTAssertFalse(again.exists && (again.label.hasPrefix("Start") || again.label.hasPrefix("Resume")), "saved once: not offered again after a relaunch (\(again.exists ? again.label : "no button"))")
    }

    /// A real superset on the preparation screen and in the recorder (sheets 01a J2 and 04b). The demo athlete says they
    /// prefer supersets, and the app's own session builder pairs the exercises; nothing is drawn by hand.
    func test2b2SupersetIsGroupedOnThePreparationScreen() {
        let app = XCUIApplication()
        app.launchEnvironment["LAB_FRESH_DEMO"] = "1"
        app.launchEnvironment["LAB_DEMO_SUPERSETS"] = "1"
        app.launchEnvironment["LAB_THEME"] = "obsidian"
        app.launch()
        XCTAssertTrue(app.waitForHome(name: "Demo", timeout: 30))
        func el(_ id: String) -> XCUIElement { app.descendants(matching: .any).matching(identifier: id).firstMatch }
        app.buttons["centreButton"].firstMatch.tap()
        let primary = app.buttons["trainPanelPrimary"].firstMatch
        XCTAssertTrue(primary.waitForExistence(timeout: 8), "the panel offers today's session"); primary.tap()
        XCTAssertTrue(el("strengthPrepareV14").waitForExistence(timeout: 10), "the preparation screen")
        let group = el("prepareSuperset-A")
        XCTAssertTrue(group.waitForExistence(timeout: 5), "required: the session's superset is shown as one group")
        XCTAssertTrue(group.label.uppercased().contains("SUPERSET A") && group.label.lowercased().contains("rounds"), "the group names its rounds: \(group.label)")
        let rows = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'prepareRow-'"))
        print("LAB-NOTE superset preparation: '\(group.label)' · \(rows.count) exercises · \(el("prepareSummary").label)")
        shot("superset-1-prepare")
        app.buttons["startWorkout"].firstMatch.tap()
        XCTAssertTrue(el("strengthRecorderV14").waitForExistence(timeout: 10), "the recorder")
        var n = 0
        while !el("recorderOverline").label.hasPrefix("SUPERSET") && n < 12 {
            let skip = app.buttons["restSkip"].firstMatch; if skip.exists { skip.tap() }
            let log = el("logSet"); if log.exists { log.tap() }; n += 1
        }
        XCTAssertTrue(el("recorderOverline").label.hasPrefix("SUPERSET"), "the recorder reaches the superset: \(el("recorderOverline").label)")
        shot("superset-2-recorder")
    }

    /// Profile v2.0: every section page and the pages behind it, as pictures for the comparison with sheets P03–P08.
    /// Each row named here is required to exist and to open a page with a way back.
    func test2dProfileSectionsAndTheirPagesOpen() {
        let app = XCUIApplication()
        app.launchEnvironment["LAB_FRESH_DEMO"] = "1"
        app.launchEnvironment["LAB_THEME"] = "obsidian"
        app.launch()
        XCTAssertTrue(app.waitForHome(name: "Demo", timeout: 30))
        XCTAssertTrue(openProfile(app), "Profile opens from the Home avatar")
        func el(_ id: String) -> XCUIElement { app.descendants(matching: .any).matching(identifier: id).firstMatch }
        func back() { app.navigationBars.buttons.firstMatch.tap(); app.settleForScreenshot(1) }
        let pages: [(section: String, name: String, rows: [String])] = [
            ("profileSectionA", "athlete", ["profilePersonal", "profileType"]),
            ("profileSectionB", "setup", ["profileEquipment", "profilePreferences", "profileHealthSafety", "profileGoal", "profileWeek"]),
            ("profileSectionC", "performance", ["profileHR", "profileFTP"]),
            ("profileSectionD", "devices", []),
            ("profileSectionE", "preferences", ["profileAppearance", "profileUnits", "profileCoach"]),
            ("profileSectionF", "data", ["profileSettings", "profileHelp"]),
        ]
        for p in pages {
            let s = el(p.section)
            XCTAssertTrue(s.waitForExistence(timeout: 8), "required: \(p.section)"); app.reveal(s); s.tap(); app.settleForScreenshot(1)
            shot("profile-\(p.name)")
            for r in p.rows {
                let row = el(r)
                XCTAssertTrue(row.waitForExistence(timeout: 8), "required: \(r) on \(p.name)"); app.reveal(row); row.tap(); app.settleForScreenshot(1)
                XCTAssertFalse(row.isHittable, "\(r) opens its page")
                shot("profile-\(p.name)-\(r)")
                back()
                XCTAssertTrue(row.waitForExistence(timeout: 8), "back from \(r)")
            }
            back()
        }
        XCTAssertTrue(el("profileSectionA").waitForExistence(timeout: 8), "back on the Profile landing page")
    }

    /// The cycling screen in Lab is a labelled demonstration: the v1.4 layout and lifecycle, simulated figures, nothing saved.
    func test2cCyclingDemonstrationIsLabelledAndSavesNothing() {
        let app = XCUIApplication()
        app.launchEnvironment["LAB_FRESH_DEMO"] = "1"      // independent of every other test
        app.launchEnvironment["LAB_THEME"] = "obsidian"
        app.launch()
        XCTAssertTrue(app.waitForHome(name: "Demo", timeout: 30))
        func el(_ id: String) -> XCUIElement { app.descendants(matching: .any).matching(identifier: id).firstMatch }
        app.buttons["centreButton"].firstMatch.tap()
        let ride = app.buttons["trainPanelRide"].firstMatch
        XCTAssertTrue(ride.waitForExistence(timeout: 8), "the panel offers a ride"); ride.tap()
        XCTAssertTrue(el("cyclingRecorderV14").waitForExistence(timeout: 10), "the cycling screen opens")
        let strip = el("cyclingSimulated")
        XCTAssertTrue(strip.exists && strip.label.contains("SIMULATED") && strip.label.contains("nothing is recorded or saved"), "the screen says its figures are simulated (\(strip.label))")
        XCTAssertTrue(app.buttons["cyclingLapButton"].firstMatch.exists && app.buttons["cyclingPause"].firstMatch.exists, "riding: Lap and Pause")
        XCTAssertFalse(app.buttons["cyclingFinish"].firstMatch.exists, "riding: no Finish")
        app.settleForScreenshot(3); shot("cycling-1-recording")
        app.buttons["cyclingLapButton"].firstMatch.tap()
        XCTAssertTrue(el("cyclingLap").label.contains("lap 2"), "Lap counts a lap (\(el("cyclingLap").label))")
        app.buttons["cyclingPause"].firstMatch.tap()
        XCTAssertTrue(app.buttons["cyclingResume"].firstMatch.waitForExistence(timeout: 5) && app.buttons["cyclingFinish"].firstMatch.exists, "paused: Resume and Finish")
        XCTAssertTrue(el("cyclingState").label.contains("paused"), "paused is said in words")
        let frozen = el("cyclingElapsed").label; app.settleForScreenshot(3)
        XCTAssertEqual(el("cyclingElapsed").label, frozen, "the clock does not count while paused"); shot("cycling-2-paused")
        app.buttons["cyclingResume"].firstMatch.tap()
        XCTAssertTrue(app.buttons["cyclingPause"].firstMatch.waitForExistence(timeout: 5))
        app.buttons["cyclingPause"].firstMatch.tap(); app.buttons["cyclingFinish"].firstMatch.tap()
        XCTAssertTrue(el("cyclingDemoEnded").waitForExistence(timeout: 5), "finishing says the demonstration ended"); shot("cycling-3-ended")
        app.buttons["cyclingDemoClose"].firstMatch.tap()
        XCTAssertTrue(app.waitForHome(name: "Demo", timeout: 10), "back on Home")
    }

    /// Delete all data inside Lab: back to Welcome at once, still empty after a plain relaunch, banner still there.
    /// (That the production app's files are untouched is checked outside, by ios/ci/lab.sh.) Runs last.
    func test3DeleteAllDataEmptiesLabAndStaysEmpty() {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.waitForHome(name: "Demo", timeout: 30))
        XCTAssertTrue(openProfile(app), "Profile opens from the Home avatar")
        for id in ["profileSectionA", "profileSectionB", "profileSectionC", "profileSectionD", "profileSectionE", "profileSectionF"] {
            XCTAssertTrue(app.descendants(matching: .any).matching(identifier: id).firstMatch.exists, "Profile v2.0 section \(id)")
        }
        deleteAll(app, shotName: "delete-1-question")
        XCTAssertTrue(banner(app), "the demo banner stays on Welcome"); shot("delete-2-welcome")
        app.terminate()
        let again = XCUIApplication()
        again.launch()
        XCTAssertTrue(again.buttons["onboardingContinue"].firstMatch.waitForExistence(timeout: 30), "relaunch: still Welcome, the demo athlete did not come back")
        XCTAssertFalse(again.waitForHome(name: "Demo", timeout: 3), "the deleted demo athlete must not reappear")
        shot("delete-3-relaunch")
    }

    /// After the deletion above Lab is empty. "Restore the demo athlete" is an explicit choice: nothing comes back until
    /// it is chosen AND Lab is reopened; then the demo athlete is there again.
    /// Profile › Data, Help & About › settings › Delete all data, confirmed. Ends at Welcome.
    private func deleteAll(_ app: XCUIApplication, shotName: String? = nil) {
        XCTAssertTrue(openSettings(app), "Profile › Data, Help & About › settings")
        var tries = 0
        let delete = app.buttons["deleteAllData"].firstMatch
        while !(delete.exists && delete.isHittable) && tries < 12 { app.swipeUp(); tries += 1 }
        XCTAssertTrue(delete.waitForExistence(timeout: 10), "Delete all data"); delete.tap()
        let alert = app.alerts.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 10), "deletion asks first"); if let n = shotName { shot(n) }
        alert.buttons["Delete"].firstMatch.tap()
        XCTAssertTrue(app.buttons["onboardingContinue"].firstMatch.waitForExistence(timeout: 15), "after Delete, Lab is at Welcome")
    }

    /// The new-athlete journey. Named "3z" so it runs after the deletion test whatever the letter case rule (run 11: as
    /// "3b" it ran before "3Delete" and met the demo athlete). Lab starts empty here: the seven onboarding pages, the
    /// Athletic Roster, approval of the Blueprint, then Home and Plan showing the approved week. Leaves Lab empty again.
    func test3zNewAthleteOnboardsApprovesAndSeesThePlan() {
        let app = XCUIApplication()
        app.launchEnvironment["LAB_THEME"] = "obsidian"
        app.launch()
        let start = app.buttons["onboardingContinue"].firstMatch
        XCTAssertTrue(start.waitForExistence(timeout: 30), "starts at Welcome (after the deletion test)"); shot("journey-0-welcome")
        start.tap()
        let next = app.buttons["onboardingNext"].firstMatch
        func page(_ n: Int) { XCTAssertTrue(app.staticTexts["onboardingProgress"].firstMatch.waitForExistence(timeout: 8) && app.staticTexts["onboardingProgress"].firstMatch.label.hasPrefix("\(n) of 7"), "onboarding page \(n) (\(app.staticTexts["onboardingProgress"].firstMatch.label))") }
        // 1 About you
        page(1); XCTAssertFalse(next.isEnabled, "page 1: Continue needs a name")
        let name = app.textFields["onbName"].firstMatch
        XCTAssertTrue(name.waitForExistence(timeout: 8)); name.tap(); name.typeText("Sam")
        let done = app.buttons["keyboardDone"].firstMatch; if done.waitForExistence(timeout: 3) { done.tap() }
        shot("journey-1-about"); XCTAssertTrue(next.isEnabled); next.tap()
        // 2 Athletic Roster
        page(2); XCTAssertFalse(next.isEnabled, "page 2: Continue needs a sport Cyclift can plan")
        XCTAssertTrue(app.staticTexts["rosterEmptyHeadline"].firstMatch.exists, "empty roster headline")
        shot("journey-2a-roster-empty")
        app.buttons["rosterAdd-roadCycling"].firstMatch.tap()
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "rosterMain-roadCycling").firstMatch.waitForExistence(timeout: 5), "the first sport becomes the main sport")
        XCTAssertFalse(app.descendants(matching: .any).matching(identifier: "rosterLead").firstMatch.exists, "one domain: no lead control")
        app.buttons["rosterAdd-strength"].firstMatch.tap()
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "rosterMain-strength").firstMatch.waitForExistence(timeout: 5), "strength is the second main sport")
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "rosterLead").firstMatch.waitForExistence(timeout: 5), "two domains: the lead control appears")
        shot("journey-2b-roster-hybrid")
        app.buttons["rosterBrowse"].firstMatch.tap()
        XCTAssertTrue(app.buttons["library-running"].firstMatch.waitForExistence(timeout: 8), "the library opens")
        let sauna = app.descendants(matching: .any).matching(identifier: "library-sauna").firstMatch
        var n = 0; while !sauna.exists && n < 4 { app.swipeUp(); n += 1 }
        XCTAssertTrue(sauna.exists && sauna.label.contains("Coming later"), "an activity that cannot be stored says so and is not a button")
        shot("journey-2c-library")
        app.buttons["libraryDone"].firstMatch.tap()
        XCTAssertTrue(next.waitForExistence(timeout: 8) && next.isEnabled); next.tap()
        // 3 Goals
        page(3); XCTAssertFalse(next.isEnabled, "page 3: Continue needs a goal")
        let goal = app.descendants(matching: .any).matching(identifier: "goal-endurance").firstMatch
        XCTAssertTrue(goal.waitForExistence(timeout: 8), "goal cards"); goal.tap()
        shot("journey-3-goals"); XCTAssertTrue(next.isEnabled); next.tap()
        // 4 Week
        page(4); XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "onbWeek").firstMatch.waitForExistence(timeout: 8), "the week builder")
        shot("journey-4-week"); XCTAssertTrue(next.isEnabled, "the proposed week can be accepted as it is"); next.tap()
        // 5 Connect
        page(5); XCTAssertTrue(app.staticTexts["onbLabDevices"].firstMatch.exists, "Lab says devices are switched off")
        shot("journey-5-connect"); next.tap()
        // 6 Evolution
        page(6); XCTAssertTrue(app.staticTexts["onbEvolutionStage"].firstMatch.waitForExistence(timeout: 8) && app.staticTexts["onbEvolutionStage"].firstMatch.label.hasPrefix("No stage yet"), "no stage is claimed")
        shot("journey-6-evolution"); next.tap()
        // 7 Blueprint
        page(7)
        let identity = app.staticTexts["blueprintIdentity"].firstMatch
        XCTAssertTrue(identity.waitForExistence(timeout: 8) && identity.label == "Road cycling + Gym training · balanced", "the Blueprint names the roster (\(identity.label))")
        XCTAssertTrue(app.staticTexts["blueprintWeekTotals"].firstMatch.exists, "the proposed week's totals")
        shot("journey-7-blueprint")
        app.buttons["onbCreatePlan"].firstMatch.tap()
        // Home and Plan show the approved athlete and week
        XCTAssertTrue(app.waitForHome(name: "Sam", timeout: 20), "approval lands on Home for the new athlete"); shot("journey-8-home")
        tab(app, "Plan")
        XCTAssertTrue(app.staticTexts["planTitle"].firstMatch.waitForExistence(timeout: 8), "Plan is shown"); shot("journey-9-plan")
        // leave Lab empty for the restore test
        tab(app, "Home")
        XCTAssertTrue(openProfile(app), "Profile from the avatar")
        deleteAll(app)
    }

    func test4RestoreBringsTheDemoAthleteBackOnlyWhenAsked() {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.buttons["onboardingContinue"].firstMatch.waitForExistence(timeout: 30), "starts empty (after the deletion test)")
        let restore = app.buttons["labRestore"].firstMatch
        XCTAssertTrue(restore.waitForExistence(timeout: 8), "the restore button in the Lab strip"); restore.tap()
        app.settleForScreenshot(1)
        XCTAssertTrue(app.buttons["labRestore"].firstMatch.label.hasPrefix("Restore asked for"), "the strip confirms that restore was asked for")
        XCTAssertTrue(app.buttons["onboardingContinue"].firstMatch.exists, "nothing changes until Lab is reopened")
        shot("restore-1-asked")
        app.terminate()
        let again = XCUIApplication()
        again.launch()
        XCTAssertTrue(again.waitForHome(name: "Demo", timeout: 30), "after reopening, the demo athlete is back")
        shot("restore-2-back")
    }
}
