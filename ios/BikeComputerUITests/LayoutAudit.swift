import XCTest

/// Quality release layout audit (ios/QUALITY_RELEASE.md). Runs ONLY when the runner has LAYOUT_DIR set (ios/ci/build.sh
/// passes TEST_RUNNER_LAYOUT_DIR per simulator: small iPhone, standard iPhone, Pro Max); otherwise it is skipped.
/// For each text size in LAYOUT_SIZES (default L, XXXL, AX3) it launches the app with clearly labelled demo data
/// ("Demo" rider, schema-1 store that reproduces the owner's report), takes PNG screenshots of the key screens and
/// checks the key controls' frames: inside the window, not overlapping each other, at least 44 pt tall, hittable.
/// Hard failures: key controls. Every other on-screen text outside the window is listed in layout-report.txt.
final class LayoutAudit: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = true }

    private var outDir: String? { let v = ProcessInfo.processInfo.environment["LAYOUT_DIR"] ?? ""; return v.isEmpty ? nil : v }
    private var device: String { ProcessInfo.processInfo.environment["LAYOUT_DEVICE"] ?? "iphone" }
    private var extras: Bool { ProcessInfo.processInfo.environment["LAYOUT_EXTRAS"] != "0" }
    private var sizes: [String] {
        let v = ProcessInfo.processInfo.environment["LAYOUT_SIZES"] ?? ""
        return v.isEmpty ? ["L", "XXXL", "AX3"] : v.split(separator: ",").map { String($0) }
    }
    /// Content size names (AX3 = Accessibility Extra Large, the third accessibility size).
    private func category(_ s: String) -> String {
        switch s {
        case "S": return "UICTContentSizeCategoryS"
        case "XL": return "UICTContentSizeCategoryXL"
        case "XXL": return "UICTContentSizeCategoryXXL"
        case "XXXL": return "UICTContentSizeCategoryXXXL"
        case "AX1": return "UICTContentSizeCategoryAccessibilityM"
        case "AX2": return "UICTContentSizeCategoryAccessibilityL"
        case "AX3": return "UICTContentSizeCategoryAccessibilityXL"
        case "AX5": return "UICTContentSizeCategoryAccessibilityXXXL"
        default: return "UICTContentSizeCategoryL"
        }
    }

    private var report: [String] = []
    private func note(_ s: String) { report.append(s) }
    override func tearDown() {
        if let d = outDir, !report.isEmpty {
            let url = URL(fileURLWithPath: d).appendingPathComponent("layout-report-\(device).txt")
            let old = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
            try? (old + report.joined(separator: "\n") + "\n").write(to: url, atomically: true, encoding: .utf8)
        }
        super.tearDown()
    }

    private func shot(_ name: String) {
        guard let dir = outDir else { return }
        let png = XCUIScreen.main.screenshot().pngRepresentation
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        try? png.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(device)-\(name).png"))
    }

    private func launch(_ size: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["BC_UITEST_SEED_JSON"] = Self.demoStore()
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", category(size)]
        app.launch()
        XCTAssertTrue(app.navigationBars["Hi Demo"].waitForExistence(timeout: 30) || app.staticTexts["Hi Demo"].waitForExistence(timeout: 5), "Home did not appear")
        sleep(2)
        return app
    }

    // MARK: frame checks — one accessibility snapshot per screen (querying elements one by one is far too slow)
    private func flatten(_ s: XCUIElementSnapshot) -> [XCUIElementSnapshot] { [s] + s.children.flatMap { flatten($0) } }
    private func elements(_ app: XCUIApplication) -> [XCUIElementSnapshot] { (try? app.snapshot()).map { flatten($0) } ?? [] }
    /// The elements of what is on screen: the visible tab page (`tab`), or with `tab == nil` everything outside the tab
    /// pages (a sheet, the tab bar). Hidden pages stay alive and still report frames, so they are left out.
    private func visibleElements(_ app: XCUIApplication, tab: Int?) -> [XCUIElementSnapshot] {
        guard let root = try? app.snapshot() else { return [] }
        func walk(_ s: XCUIElementSnapshot) -> [XCUIElementSnapshot] {
            if s.identifier.hasPrefix("tabPage-") { return tab.map { s.identifier == "tabPage-\($0)" } == true ? flatten(s) : [] }
            return [s] + s.children.flatMap { walk($0) }
        }
        return walk(root)
    }
    private func hasTextDescendant(_ s: XCUIElementSnapshot) -> Bool { s.children.contains { $0.elementType == .staticText || hasTextDescendant($0) } }
    /// System views that are not app content (iOS 26 toolbar glass dimming overlay reports a frame wider than the screen).
    private func isSystem(_ e: XCUIElementSnapshot) -> Bool { ["AdditionalDimmingOverlay"].contains(e.identifier) }

    private func checkKey(_ app: XCUIApplication, ids: [String], screen: String, minHeight: CGFloat = 44) {
        let all = elements(app)
        let win = app.windows.firstMatch.frame
        var frames: [(String, CGRect)] = []
        for id in ids {
            guard let e = all.first(where: { $0.elementType == .button && ($0.identifier == id || $0.label == id) }) else { note("\(screen): \(id) not found"); continue }
            let f = e.frame
            frames.append((id, f))
            XCTAssertGreaterThanOrEqual(f.minX, win.minX - 1, "\(screen) \(id) clipped left \(f)")
            XCTAssertLessThanOrEqual(f.maxX, win.maxX + 1, "\(screen) \(id) clipped right \(f)")
            XCTAssertGreaterThanOrEqual(f.height, minHeight - 0.5, "\(screen) \(id) shorter than \(minHeight) pt: \(f.height)")
        }
        // hittable when it is on screen above the tab bar zone (a control lower down scrolls into view; the scroll content
        // has a bottom inset so it can always come above the bar — checked on the "lower" screenshots)
        if let first = ids.first { let b = app.buttons[first].firstMatch; if b.exists, b.frame.minY > win.minY + 100, b.frame.maxY < win.maxY - 120 { XCTAssertTrue(b.isHittable, "\(screen) \(first) not hittable") } else if b.exists { note("\(screen): \(first) outside the checked zone (\(Int(b.frame.minY))–\(Int(b.frame.maxY)) of \(Int(win.height)))") } }
        for i in frames.indices { for j in frames.indices where j > i {
            let inter = frames[i].1.intersection(frames[j].1)
            XCTAssertTrue(inter.isNull || inter.width < 1 || inter.height < 1, "\(screen): \(frames[i].0) overlaps \(frames[j].0)")
        } }
        note("\(screen): key controls " + frames.map { "\($0.0) \(Int($0.1.width))×\(Int($0.1.height))" }.joined(separator: ", "))
    }
    /// On-screen texts that leave the window horizontally (soft check, listed in the report).
    private func checkTexts(_ app: XCUIApplication, screen: String) {
        let win = app.windows.firstMatch.frame
        var bad = 0
        for t in elements(app) where t.elementType == .staticText {
            let f = t.frame
            guard f.minY >= win.minY, f.maxY <= win.maxY, f.width > 0 else { continue }
            if f.minX < win.minX - 1 || f.maxX > win.maxX + 1 { bad += 1; note("\(screen): text out of window \(Int(f.minX))…\(Int(f.maxX)) of \(Int(win.width)): \"\(t.label.prefix(40))\"") }
        }
        if bad == 0 { note("\(screen): no text outside the window") }
        // soft: on-screen buttons shorter than 44 pt (listed in the report)
        var small: [String] = []
        for b in elements(app) where b.elementType == .button {
            let f = b.frame
            guard f.minY >= win.minY + 50, f.maxY <= win.maxY - 90, f.width > 0, f.height > 0 else { continue }
            if f.height < 43.5 { small.append("\(b.identifier.isEmpty ? b.label.prefix(24) : b.identifier.prefix(24)) \(Int(f.width))×\(Int(f.height))") }
        }
        note("\(screen): " + (small.isEmpty ? "every on-screen button ≥ 44 pt tall" : "buttons under 44 pt: " + small.joined(separator: ", ")))
    }
    private func scrollUp(_ app: XCUIApplication) { app.swipeUp(); sleep(1) }
    /// A button of the given identifier prefix that is fully on screen (below the bars), if any.
    private func visibleButton(_ app: XCUIApplication, prefix: String) -> XCUIElement? {
        let win = app.windows.firstMatch.frame
        let q = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", prefix))
        for i in 0..<min(q.count, 8) {
            let e = q.element(boundBy: i)
            let f = e.frame
            if f.minY > win.minY + 200 && f.maxY < win.maxY - 160 && e.isHittable { return e }
        }
        return nil
    }

    private func tab(_ app: XCUIApplication, _ name: String) {
        let b = app.buttons[name].firstMatch
        if b.waitForExistence(timeout: 5) { b.tap(); sleep(2) } else { note("tab \(name) missing") }
    }
    /// Closes the TOPMOST sheet: its Done / Cancel is the last matching button in the hierarchy.
    private func close(_ app: XCUIApplication) {
        sleep(1)      /* a sheet still animating in is not hittable yet: the Done BEHIND it would be tapped instead */
        for name in ["Done", "Cancel", "Close"] {
            let q = app.buttons.matching(NSPredicate(format: "label == %@", name))
            for i in stride(from: q.count - 1, through: 0, by: -1) { let b = q.element(boundBy: i); if b.isHittable { b.tap(); sleep(1); return } }
        }
    }

    func testKeyScreensAtTextSizes() throws {
        guard outDir != nil else { throw XCTSkip("LAYOUT_DIR not set — the layout audit runs only in the CI layout stage") }
        guard device != "owner" else { throw XCTSkip("the owner-size device runs testRC2OwnerScreens only (CI time)") }
        for size in sizes {
            let app = launch(size)
            let tag = size.lowercased()
            // Home: coach card actions (short labels, ≥ 44 pt, no overlap)
            shot("\(tag)-01-home")
            checkKey(app, ids: ["coachLog", "coachAdjust", "coachSwap"].filter { app.buttons[$0].exists }, screen: "\(size) home")
            checkTexts(app, screen: "\(size) home")
            scrollUp(app); shot("\(tag)-02-home-lower"); checkTexts(app, screen: "\(size) home lower")
            checkKey(app, ids: ["coachLog", "coachAdjust", "coachSwap"].filter { app.buttons[$0].exists }, screen: "\(size) home lower")
            // today's strength session (centre button): status, exercises with Why? / Swap
            let centre = app.buttons["centreButton"].firstMatch
            if centre.waitForExistence(timeout: 5) {
                centre.tap(); sleep(2)
                shot("\(tag)-03-strength")
                checkTexts(app, screen: "\(size) strength")
                scrollUp(app); shot("\(tag)-04-strength-exercises")
                if let why = visibleButton(app, prefix: "why-") {
                    XCTAssertGreaterThanOrEqual(why.frame.height, 43.5, "\(size) Why? button height")
                    if size == sizes.first && extras { why.tap(); sleep(2); shot("\(tag)-05-why"); close(app) }
                } else { note("\(size): no Why? button on screen") }
                if size == sizes.first && extras, let swap = visibleButton(app, prefix: "swap-") { swap.tap(); sleep(2); shot("\(tag)-06-swap"); close(app) }
                scrollUp(app); shot("\(tag)-07-strength-bottom")
                close(app)
            }
            tab(app, "Plan"); shot("\(tag)-08-plan"); checkTexts(app, screen: "\(size) plan")
            // tomorrow's session: the owner's "completed" bug must now read Planned (future)
            if size == sizes.first && extras {
                let f = DateFormatter(); f.dateFormat = "EEE d MMM"
                let tomorrow = f.string(from: Calendar.current.date(byAdding: .day, value: 1, to: Date())!)
                let day = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", tomorrow)).firstMatch
                if day.exists { day.tap(); sleep(2); shot("\(tag)-08b-tomorrow"); scrollUp(app); shot("\(tag)-08c-tomorrow-lower"); close(app) } else { note("tomorrow's day button not found") }
            }
            scrollUp(app); shot("\(tag)-09-plan-lower")
            scrollUp(app); scrollUp(app); shot("\(tag)-10-history")
            tab(app, "Progress"); shot("\(tag)-11-progress"); checkTexts(app, screen: "\(size) progress")
            let chart = app.descendants(matching: .any).matching(identifier: "trendChart").firstMatch
            if size == sizes.first && extras, chart.exists {
                chart.coordinate(withNormalizedOffset: CGVector(dx: 0.55, dy: 0.75)).tap(); sleep(1); shot("\(tag)-12-progress-selected")
                chart.coordinate(withNormalizedOffset: CGVector(dx: 0.55, dy: 0.75)).tap(); sleep(1)
            }
            scrollUp(app); shot("\(tag)-13-progress-lower"); checkTexts(app, screen: "\(size) progress lower")
            scrollUp(app); shot("\(tag)-14-progress-ftp")
            tab(app, "Profile"); shot("\(tag)-15-profile"); checkTexts(app, screen: "\(size) profile")
            if size == sizes.first && extras {
                let tp = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Training profile'")).firstMatch
                if tp.exists { tp.tap(); sleep(2); shot("\(tag)-16-training-profile"); scrollUp(app); shot("\(tag)-17-training-profile-lower"); app.navigationBars.buttons.firstMatch.tap(); sleep(1) }
            }
            // tab bar items never overlap the raised centre button
            checkKey(app, ids: ["Home", "Plan", "centreButton", "Progress", "Profile"], screen: "\(size) tab bar", minHeight: 30)
            tab(app, "Home")
            if size == sizes.first && extras {
                let conn = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Manage'")).firstMatch
                if conn.exists { conn.tap(); sleep(2); shot("\(tag)-18-connections"); checkTexts(app, screen: "\(size) connections"); app.navigationBars.buttons.firstMatch.tap(); sleep(1) }
            }
            XCTAssertEqual(app.state, .runningForeground)
            app.terminate()
        }
    }

    // MARK: RC2 owner report (28 Oct): Progress chart labels, Plan width, Done vs Planned, Connections — at the owner's
    // screen size too (CI device "owner" = iPhone 16, 393 × 852 pt). Screenshots: <device>-rc2-<size>-*.png.
    /// Frames of the date labels under a weekly chart (TrendCharts draws them as plain Text with "<chart>-xlabel").
    private func xLabelFrames(_ app: XCUIApplication, _ chart: String) -> [CGRect] {
        elements(app).filter { $0.identifier == "\(chart)-xlabel" && $0.frame.width > 0 }.map { $0.frame }
    }
    private func checkChartLabels(_ app: XCUIApplication, _ chart: String, screen: String) {
        let f = xLabelFrames(app, chart), win = app.windows.firstMatch.frame
        XCTAssertFalse(f.isEmpty, "\(screen): no \(chart) date labels")
        guard !f.isEmpty else { return }
        XCTAssertGreaterThanOrEqual(f.count, 2, "\(screen): at least two date labels")
        for (i, a) in f.enumerated() {
            XCTAssertGreaterThanOrEqual(a.minX, win.minX - 1, "\(screen): label clipped left \(a)"); XCTAssertLessThanOrEqual(a.maxX, win.maxX + 1, "\(screen): label clipped right \(a)")
            for b in f.dropFirst(i + 1) { XCTAssertTrue(a.intersection(b).isNull || a.intersection(b).width < 1, "\(screen): date labels overlap \(a) / \(b)") }
        }
        let gaps = zip(f.sorted { $0.minX < $1.minX }, f.sorted { $0.minX < $1.minX }.dropFirst()).map { $1.minX - $0.maxX }
        XCTAssertGreaterThanOrEqual(gaps.min() ?? 99, 2, "\(screen): date labels closer than 2 pt")
        note("\(screen): \(f.count) date labels, smallest gap \(Int(gaps.min() ?? 0)) pt")
    }
    /// Nothing on the Plan screen is wider than the window or sticks out sideways (no horizontal scrolling content).
    private func checkNoHorizontalOverflow(_ app: XCUIApplication, screen: String, tab: Int? = nil, scoped: Bool = false) {
        let win = app.windows.firstMatch.frame
        var bad: [String] = []
        for e in (scoped ? visibleElements(app, tab: tab) : elements(app)) where [.staticText, .button, .image].contains(e.elementType) && !isSystem(e) {
            let f = e.frame
            guard f.width > 0, f.maxY > win.minY + 40, f.minY < win.maxY - 90 else { continue }
            if f.minX < win.minX - 1 || f.maxX > win.maxX + 1 { bad.append("\(e.identifier.isEmpty ? String(e.label.prefix(30)) : e.identifier) \(Int(f.minX))…\(Int(f.maxX))") }
        }
        XCTAssertTrue(bad.isEmpty, "\(screen): content wider than the screen: \(bad.joined(separator: "; "))")
        note("\(screen): " + (bad.isEmpty ? "nothing wider than the screen" : "WIDER THAN THE SCREEN: " + bad.joined(separator: "; ")))
    }

    /// Static texts that overlap each other (any two, on screen, below the navigation bar and above the tab bar). HARD
    /// failure: the previous audit passed with overlapping date labels because it never compared texts with each other.
    private func checkNoTextOverlap(_ app: XCUIApplication, screen: String, tab: Int?) {
        let win = app.windows.firstMatch.frame
        // leaf texts only: an element combined for VoiceOver (".combine") reports its own frame AND its children's, so the
        // group "AVERAGE PER WEEK, 2 h 43 min, …" always "overlapped" its own parts (run 101: 20 false failures)
        let texts = visibleElements(app, tab: tab).filter { e in e.elementType == .staticText && e.frame.width > 1 && e.frame.height > 1
            && e.frame.minY > win.minY + 100 && e.frame.maxY < win.maxY - 90 && !hasTextDescendant(e) }
        var bad: [String] = []
        for (i, a) in texts.enumerated() { for b in texts.dropFirst(i + 1) {
            let r = a.frame.intersection(b.frame)
            // a LabeledContent row reports a leaf "Profile sync" AND a combined leaf "Profile sync, no BikeComputer connected"
            // whose frame contains it (run 102; checked on the screenshot: the two lines are stacked, not overlapping).
            // Skipped only when one frame contains the other AND the larger label starts with the smaller one + ", ".
            let (big, small) = a.frame.width * a.frame.height >= b.frame.width * b.frame.height ? (a, b) : (b, a)
            let summaryOfItself = big.frame.insetBy(dx: -1, dy: -1).contains(small.frame) && !small.label.isEmpty && big.label.hasPrefix(small.label + ", ")
            if !summaryOfItself && !r.isNull && r.width >= 1 && r.height >= 1 && a.frame != b.frame { bad.append("\"\(a.label.prefix(24))\" × \"\(b.label.prefix(24))\" (\(Int(r.width))×\(Int(r.height)) pt)") }
        } }
        XCTAssertTrue(bad.isEmpty, "\(screen): overlapping texts: \(bad.joined(separator: "; "))")
        note("\(screen): \(texts.count) texts, " + (bad.isEmpty ? "none overlapping" : "OVERLAPPING: " + bad.joined(separator: "; ")))
    }
    /// The three hard layout checks every RC2 screen gets.
    /// `tab`: the visible tab page (0 Home … 4 Profile); nil = a sheet over the tabs.
    private func checkScreen(_ app: XCUIApplication, _ screen: String, tab: Int?) {
        checkNoHorizontalOverflow(app, screen: screen, tab: tab, scoped: true)
        checkNoTextOverlap(app, screen: screen, tab: tab)
    }
    /// Picks a range of the Progress chart: a segmented control normally, a menu at accessibility sizes.
    private func pickRange(_ app: XCUIApplication, _ r: String) -> Bool {
        let seg = app.segmentedControls["trendChart-range"].buttons[r]
        if seg.waitForExistence(timeout: 2) { seg.tap(); sleep(1); return true }
        let menu = app.buttons["trendChart-range"].firstMatch
        if menu.exists { menu.tap(); sleep(1); let item = app.buttons[r].firstMatch; if item.waitForExistence(timeout: 2) { item.tap(); sleep(1); return true }; app.tap() }
        return false
    }
    /// Scrolls until the element is fully on screen between the bars (at most `tries` swipes).
    /// Scrolls (short drags, no fling) until the element's TOP is on screen below the navigation bar and at least 200 pt
    /// above the bottom. Run 101: "fully on screen" can never hold for a chart taller than the screen (AX3 on the small
    /// iPhone), so four swipes flung it off the top and the tap landed on the ride list.
    private func reveal(_ app: XCUIApplication, _ e: XCUIElement, tries: Int = 8) {
        let win = app.windows.firstMatch.frame
        for _ in 0..<tries {
            guard e.exists else { drag(app, up: true); continue }
            let f = e.frame
            if f.minY > win.minY + 90 && f.minY < win.maxY - 200 { return }
            drag(app, up: f.minY >= win.maxY - 200)
        }
    }
    private func drag(_ app: XCUIApplication, up: Bool) {
        let a = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: up ? 0.7 : 0.35)), b = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: up ? 0.35 : 0.7))
        a.press(forDuration: 0.05, thenDragTo: b); sleep(1)
    }
    /// Taps the chart at a fraction of its width, at a height that is on screen (the chart may be taller than the screen).
    private func tapChart(_ app: XCUIApplication, _ chart: XCUIElement, dx: CGFloat) {
        let f = chart.frame, win = app.windows.firstMatch.frame
        let y = max(f.minY + 10, min(f.minY + f.height * 0.6, win.maxY - 140))
        app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: f.minX + f.width * dx, dy: y)).tap(); sleep(1)
    }

    func testRC2OwnerScreens() throws {
        guard outDir != nil else { throw XCTSkip("LAYOUT_DIR not set — the layout audit runs only in the CI layout stage") }
        guard ["owner", "small"].contains(device) else { throw XCTSkip("RC2 screens: the owner's iPhone size and the small iPhone only (CI time)") }
        for size in sizes {
            let app = launch(size)
            let tag = "rc2-\(size.lowercased())"
            // Progress level 1: the at-a-glance cards
            tab(app, "Progress")
            shot("\(tag)-progress-glance"); checkScreen(app, "\(size) progress glance", tab: 3)
            for id in ["glanceRiding", "glanceStrength", "glanceFrequency"] { XCTAssertTrue(app.buttons[id].exists, "\(size): at-a-glance card \(id)") }
            // Progress level 2: the chart at every range, labels measured and checked, one selected week
            let glance = app.buttons["glanceRiding"].firstMatch
            if glance.exists { glance.tap(); sleep(2) }        /* opens the riding chart */
            let chart = app.descendants(matching: .any).matching(identifier: "trendChart").firstMatch
            reveal(app, chart)
            XCTAssertTrue(chart.exists, "\(size): the Progress chart")
            for r in ["4 wk", "8 wk", "12 wk", "16 wk", "1 yr"] {
                guard pickRange(app, r) else { note("\(size): range \(r) not offered"); continue }
                reveal(app, chart)
                let name = r.replacingOccurrences(of: " ", with: "")
                shot("\(tag)-progress-riding-\(name)")
                checkChartLabels(app, "trendChart", screen: "\(size) riding \(r)"); checkScreen(app, "\(size) riding \(r)", tab: 3)
            }
            _ = pickRange(app, "16 wk"); reveal(app, chart)
            if chart.exists {
                tapChart(app, chart, dx: 0.75)
                let header = app.descendants(matching: .any).matching(identifier: "trendChart-header").firstMatch
                XCTAssertTrue(header.exists && (header.label.contains("Week of") || header.label.contains("This week")), "\(size): a tapped bar shows its week (\(header.label))")
                XCTAssertTrue(header.label.contains("Done:") && header.label.contains("Planned:"), "\(size): the selection shows done and planned (\(header.label))")
                shot("\(tag)-progress-riding-16wk-selected"); checkScreen(app, "\(size) riding selected", tab: 3)
                tapChart(app, chart, dx: 0.75)
            }
            let strength = app.segmentedControls["trendChart-metric"].buttons["Strength"]
            if strength.exists {
                strength.tap(); sleep(1); _ = pickRange(app, "8 wk"); reveal(app, chart)
                shot("\(tag)-progress-strength-8wk"); checkChartLabels(app, "trendChart", screen: "\(size) strength 8 wk"); checkScreen(app, "\(size) strength 8 wk", tab: 3)
                tapChart(app, chart, dx: 0.80)
                shot("\(tag)-progress-strength-selected"); checkScreen(app, "\(size) strength selected", tab: 3)
            } else { note("\(size): no Strength metric") }
            // FTP: the badge never says "tested" without a recorded test (the demo FTP is a test result without one)
            let ftp = app.descendants(matching: .any).matching(identifier: "ftpConfidence").firstMatch
            reveal(app, ftp, tries: 6)
            if ftp.exists { XCTAssertFalse(ftp.label.lowercased().contains("tested"), "\(size): FTP badge '\(ftp.label)'"); shot("\(tag)-progress-ftp"); checkScreen(app, "\(size) progress ftp", tab: 3) } else { note("\(size): FTP badge not found") }
            // Plan: the seven days fit, nothing scrolls sideways, Done and Planned are named, statuses, Fix plan works
            tab(app, "Plan")
            shot("\(tag)-plan"); checkScreen(app, "\(size) plan", tab: 1)
            let days = (1...7).map { app.buttons["planDay-\($0)"] }
            let found = days.filter { $0.exists }
            XCTAssertEqual(found.count, 7, "\(size): seven day buttons")
            if found.count == 7 {
                let win = app.windows.firstMatch.frame
                for d in found { XCTAssertTrue(d.frame.minX >= win.minX - 1 && d.frame.maxX <= win.maxX + 1, "\(size): day \(d.identifier) outside the screen \(d.frame)") }
                let before = found.map { $0.frame.minX }
                app.otherElements["planDayStrip"].firstMatch.swipeLeft(); sleep(1)
                XCTAssertEqual(found.map { $0.frame.minX }, before, "\(size): the day strip moved sideways (horizontal scrolling)")
            }
            let done = app.staticTexts["planDoneRiding"], planned = app.staticTexts["planPlannedRiding"]
            XCTAssertTrue(done.exists && planned.exists, "\(size): Done this week / Planned this week figures")
            if done.exists { note("\(size) plan: done '\(done.label)' · planned '\(planned.label)'") }
            let fix = app.buttons["fixPlan"].firstMatch
            if fix.exists {
                fix.tap(); sleep(2); shot("\(tag)-plan-fix"); checkScreen(app, "\(size) fix plan", tab: nil)
                let action = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'fixPlan-'")).firstMatch
                XCTAssertTrue(action.exists, "\(size): Fix plan offers an action")
                if action.exists {
                    let label = action.label
                    action.tap(); sleep(2)
                    XCTAssertTrue(app.buttons["fixPlanUndo"].waitForExistence(timeout: 3), "\(size): '\(label)' did something (Undo offered)")
                    shot("\(tag)-plan-fix-applied"); checkScreen(app, "\(size) fix plan applied", tab: nil)
                    note("\(size): Fix plan action '\(label)' applied")
                    if app.buttons["fixPlanUndo"].exists { app.buttons["fixPlanUndo"].tap(); sleep(1) }
                }
                close(app)
            } else { note("\(size): no Fix plan button (week within budget)") }
            scrollUp(app); shot("\(tag)-plan-lower"); checkScreen(app, "\(size) plan lower", tab: 1)
            scrollUp(app); shot("\(tag)-plan-lower2"); checkScreen(app, "\(size) plan lower 2", tab: 1)
            // Connections (no board in the demo: what the link line says) — Home B moved the card to Profile › Connections
            tab(app, "Profile")
            let conn = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Connections'")).firstMatch
            if conn.waitForExistence(timeout: 3) {
                conn.tap(); sleep(2); shot("\(tag)-connections"); checkScreen(app, "\(size) connections", tab: 4)
                // the BikeComputer page (the owner's "stuck on Searching" screen): no board in the demo
                let bc = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'BikeComputer'")).firstMatch
                reveal(app, bc)
                if bc.exists { bc.tap(); sleep(3); shot("\(tag)-connections-bikecomputer"); checkScreen(app, "\(size) BikeComputer page", tab: 4) } else { note("\(size): BikeComputer row not found") }
            } else { note("\(size): Connections link not found") }
            XCTAssertEqual(app.state, .runningForeground)
            app.terminate()
        }
    }

    // MARK: Home B (coord/specs/HOME_B_SPEC.md v2.1) — every seedable state at the owner's size (393 × 852): screenshot,
    // no overlapping texts, nothing wider than the screen, the primary button above the fold and every Home button ≥ 44 pt.
    static let homeStatesAll = ["planned", "ride", "completed", "rest", "multi", "missed", "skipped", "pending", "clearance", "stop", "ill", "first", "cyclingonly", "strengthonly"]
    func testHomeStates() throws {
        guard outDir != nil else { throw XCTSkip("LAYOUT_DIR not set — the layout audit runs only in the CI layout stage") }
        guard ["owner", "small"].contains(device) else { throw XCTSkip("Home states: the owner's iPhone size and the small iPhone only (CI time)") }
        for size in sizes {
            let states = device == "owner" && size == sizes.first ? Self.homeStatesAll : ["planned", "multi", "missed", "stop"]
            for state in states {
                let app = XCUIApplication()
                app.launchEnvironment["BC_UITEST_SEED_JSON"] = Self.homeStore(state)
                app.launchArguments += ["-UIPreferredContentSizeCategoryName", category(size)]
                app.launch()
                XCTAssertTrue(app.staticTexts["Hi Demo"].waitForExistence(timeout: 30), "\(state): Home did not appear")
                sleep(2)
                let screen = "\(size) home \(state)"
                shot("home-\(size.lowercased())-\(state)")
                checkScreen(app, screen, tab: 0)
                let win = app.windows.firstMatch.frame
                // the one primary action (a multi-session day: the first row's) is fully above the tab bar without scrolling
                let primary = app.buttons["homePrimary"].firstMatch.exists ? app.buttons["homePrimary"].firstMatch : app.buttons["homeRow-0"].firstMatch
                XCTAssertTrue(primary.exists, "\(screen): no primary action")
                if primary.exists {
                    let f = primary.frame
                    XCTAssertLessThanOrEqual(f.maxY, win.maxY - 105, "\(screen): primary button below the fold \(f)")
                    XCTAssertGreaterThanOrEqual(f.height, 43.5, "\(screen): primary button \(f.height) pt")
                    XCTAssertTrue(primary.isHittable, "\(screen): primary button not hittable")
                    note("\(screen): primary '\(primary.label)' at \(Int(f.minY))–\(Int(f.maxY)) of \(Int(win.height))")
                }
                let ids = ["homePrimary", "homeWhy", "homeMore", "homeRow-0", "homeRowMore-0", "homeRow-1", "homeRowMore-1", "homeMissedMove", "homeHoldInfo", "homeCoachAction", "homeCaution", "homeAdjusted", "homeSensorLine"]
                checkKey(app, ids: ids.filter { app.buttons[$0].exists }, screen: screen)
                // the week card agrees with Plan (one wording, N1): its line is shown on Home
                let week = app.buttons["homeWeek"].firstMatch
                if week.exists { note("\(screen): week '\(week.label)'") }
                if size == sizes.first && device == "owner" && ["planned", "multi", "missed", "skipped"].contains(state) {
                    // More ⋯ opens its menu (Edit, Swap, Move, Skip) — then Move to another day opens the free-day picker
                    let more = app.buttons[state == "multi" ? "homeRowMore-1" : "homeMore"].firstMatch
                    if more.exists {
                        more.tap(); sleep(1); shot("home-\(size.lowercased())-\(state)-more")
                        let move = app.buttons["Move to another day"].firstMatch
                        if move.waitForExistence(timeout: 3) { move.tap(); sleep(2); shot("home-\(size.lowercased())-\(state)-move"); checkScreen(app, "\(screen) move", tab: nil); close(app) }
                        else { app.tap(); note("\(screen): More has no Move (state)") }
                    }
                }
                if size == sizes.first && device == "owner" && ["rest", "stop"].contains(state) {
                    primary.tap(); sleep(2); shot("home-\(size.lowercased())-\(state)-primary"); checkScreen(app, "\(screen) primary sheet", tab: nil); close(app)
                }
                if size == sizes.first && device == "owner" && state == "stop" {
                    // Train now during a health stop opens the hold sheet, never the Ride screen or a workout
                    app.buttons["centreButton"].firstMatch.tap(); sleep(2)
                    XCTAssertTrue(app.buttons["holdReviewHealth"].waitForExistence(timeout: 5), "\(screen): Train now must open the hold sheet")
                    shot("home-\(size.lowercased())-stop-trainnow"); close(app)
                }
                XCTAssertEqual(app.state, .runningForeground)
                app.terminate()
            }
        }
    }

    /// Home B seeds: a demo rider ("Demo") with 8 weeks of history and this week's plan, today set to the state's session.
    static func homeStore(_ state: String) -> String {
        let iso = ISO8601DateFormatter()
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let wd = (cal.component(.weekday, from: today) + 5) % 7
        let monday = cal.date(byAdding: .day, value: -wd, to: today)!
        func d(_ day: Date, _ h: Double) -> String { iso.string(from: day.addingTimeInterval(h * 3600)) }
        func w(_ day: Date, _ kind: String, _ mins: Int, seq: Int = 0, skipped: Bool = false, focus: String? = nil) -> [String: Any] {
            var x: [String: Any] = ["id": UUID().uuidString, "date": d(day, 7 + Double(seq) * 10), "kind": kind, "minutes": mins, "done": false, "skipped": skipped, "note": "", "edited": false, "sequence": seq]
            if kind == "strength" { x["strengthFocus"] = focus ?? "fullBody" }
            return x
        }
        let first = state == "first"
        let mode = state == "cyclingonly" ? "cycling" : (state == "strengthonly" || state == "first") ? "strength" : "hybrid"
        var plan: [[String: Any]] = []
        // the week around today (two weeks so the app does not generate a random next week)
        for i in 0..<14 {
            let day = cal.date(byAdding: .day, value: i, to: monday)!
            if cal.isDate(day, inSameDayAs: today) { continue }
            if first { plan.append(w(day, "rest", 0)); continue }
            let pattern: [String]
            switch mode {
            case "cycling": pattern = ["endurance", "rest", "tempo", "rest", "endurance", "long", "rest"]
            case "strength": pattern = ["strength", "rest", "strength", "rest", "strength", "rest", "rest"]
            default: pattern = ["endurance", "strength", "tempo", "rest", "strength", "long", "rest"]
            }
            let k = pattern[i % 7]
            let missedDay = state == "missed" && cal.isDate(day, inSameDayAs: cal.date(byAdding: .day, value: -1, to: today)!)
            plan.append(w(day, missedDay ? "endurance" : k, k == "rest" && !missedDay ? 0 : k == "long" ? 120 : k == "strength" ? 40 : 60))
        }
        var todayIds: [String] = []
        switch state {
        case "ride", "cyclingonly": let x = w(today, "endurance", 60); todayIds.append(x["id"] as! String); plan.append(x)
        case "rest": plan.append(w(today, "rest", 0))
        case "first": plan.append(w(today, "rest", 0))
        case "multi":
            let a = w(today, "recovery", 30, seq: 0), b = w(today, "strength", 35, seq: 1, focus: "upper")
            todayIds += [a["id"] as! String, b["id"] as! String]; plan += [a, b]
        case "skipped": let x = w(today, "strength", 40, skipped: true); todayIds.append(x["id"] as! String); plan.append(x)
        default: let x = w(today, "strength", 40); todayIds.append(x["id"] as! String); plan.append(x)
        }
        // history: 8 weeks of rides (cycling / hybrid) and lifts (strength / hybrid) — none for a first-time rider
        var rides: [[String: Any]] = [], strength: [[String: Any]] = []
        func set(_ reps: Int, _ kg: Double) -> [String: Any] { ["id": UUID().uuidString, "reps": reps, "weightKg": kg, "bodyweight": false, "unilateral": false, "done": true] }
        func entry(_ id: String, _ name: String, _ pat: String, _ reps: Int, _ kg: Double) -> [String: Any] {
            ["id": UUID().uuidString, "exerciseId": id, "name": name, "pattern": pat, "sets": [set(reps, kg), set(reps, kg), set(reps, kg)], "notes": ""]
        }
        if !first {
            for k in 1...8 {
                let m = cal.date(byAdding: .day, value: -7 * k, to: monday)!
                if mode != "strength" {
                    for (j, len) in [60, 75, 110].enumerated() {
                        rides.append(["id": UUID().uuidString, "start": d(cal.date(byAdding: .day, value: j * 2, to: m)!, 6.5), "durationS": len * 60, "distanceM": len * 470, "avgHR": 136,
                                      "zoneSeconds": [len * 6, len * 42, len * 12, 0, 0, 0, 0], "recorder": "phone", "sources": ["Phone GPS"], "demo": false, "samples": [] as [Any]])
                    }
                }
                if mode != "cycling" {
                    for day in [1, 4] {
                        strength.append(["id": UUID().uuidString, "date": d(cal.date(byAdding: .day, value: day, to: m)!, 18), "minutes": 40, "focus": "fullBody", "customName": "", "rpe": 7, "notes": "", "source": "manual",
                                         "exercises": [entry("ex-003", "Goblet squat", "squat", 10, 20), entry("ex-088", "Dumbbell row", "pull", 10, 16), entry("ex-059", "Dumbbell bench press", "push", 8, 18)]])
                    }
                }
            }
        }
        if state == "completed", let id = todayIds.first {
            strength.append(["id": UUID().uuidString, "date": d(today, 6), "minutes": 42, "focus": "fullBody", "customName": "", "rpe": 7, "notes": "", "source": "manual", "workoutId": id,
                             "exercises": [entry("ex-003", "Goblet squat", "squat", 10, 20), entry("ex-088", "Dumbbell row", "pull", 10, 16)]])
        }
        if state == "multi" {
            rides.append(["id": UUID().uuidString, "start": d(today, 6), "durationS": 1800, "distanceM": 9_000, "avgHR": 120, "zoneSeconds": [600, 1200, 0, 0, 0, 0, 0],
                          "recorder": "phone", "sources": ["Phone GPS"], "demo": false, "samples": [] as [Any]])
        }
        var health: [String: Any] = ["answeredAt": iso.string(from: Date().addingTimeInterval(-86_400)), "questionSet": 3]
        switch state {
        case "stop": health["chestPain"] = true
        case "ill": health["currentIllness"] = true
        case "clearance": health["heartOrBloodPressure"] = true
        default: break
        }
        var profile: [String: Any] = ["name": "Demo", "goal": "fitness", "hoursPerWeek": 5, "level": "intermediate", "weightKg": 75, "age": 40, "ftpW": 225, "ftpHow": "entered", "birthYear": 1986,
                                      "sports": mode == "strength" ? ["strength"] : mode == "cycling" ? ["roadCycling"] : ["roadCycling", "strength"], "version": 3, "updatedAt": "2026-10-25T20:00:00Z",
                                      "wheelMm": 2096, "cadenceLow": 85, "cadenceHigh": 95, "hrZoneMethod": "maxHR", "trainingMode": mode, "priority": "balanced", "cyclingDaysPerWeek": 3,
                                      "liftDaysPerWeek": 3, "liftingHoursPerWeek": 3, "preferredDays": [0, 2, 4, 5], "hybridGoal": "balanced", "strengthSplit": "fullBody"]
        if state != "pending" { profile["healthScreen"] = health }
        let settings: [String: Any] = ["units": "metric", "phoneOnlyMode": true, "hrPref": "watch", "keepScreenOn": true, "autoConnectBoard": false, "enabledConnections": ["watch"], "appearance": "dark",
                                       "backgroundNotice": true, "coachTalk": "normal", "coachEnabled": true, "appleHealthImportWorkouts": false]
        let file: [String: Any] = ["schema": 2, "profile": profile, "settings": settings, "plan": plan.sorted { ($0["date"] as! String) < ($1["date"] as! String) }, "rides": rides, "tiles": ["power", "cadence", "hr", "speed", "time", "dist"],
                                   "onboarded": true, "guest": true, "createdAt": "2026-06-01T10:00:00Z", "boardSync": [] as [Any], "onboardingStage": 0, "templates": [] as [Any], "customExercises": [] as [Any],
                                   "appliedProposals": [] as [Any], "equipment": ["owned": ["dumbbell", "bench", "kettlebell"], "excluded": [] as [Any]], "ignoredInsights": [] as [Any], "strength": strength]
        let data = try! JSONSerialization.data(withJSONObject: file)
        return String(data: data, encoding: .utf8)!
    }

    // MARK: demo data — labelled "Demo", no real person. Reproduces the owner's report: a Full body session planned for
    // TOMORROW stored as done with a 1-minute, zero-set log (schema 1), plus 16 weeks of rides and 6 weeks of lifts.
    static func demoStore() -> String {
        let iso = ISO8601DateFormatter()
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let wd = (cal.component(.weekday, from: today) + 5) % 7
        let monday = cal.date(byAdding: .day, value: -wd, to: today)!
        let tomorrow = cal.date(byAdding: .day, value: 1, to: today)!
        func d(_ day: Date, _ h: Double) -> String { iso.string(from: day.addingTimeInterval(h * 3600)) }
        var plan: [[String: Any]] = []
        for i in 0..<7 {
            let day = cal.date(byAdding: .day, value: i, to: monday)!
            var kind = ["endurance", "rest", "tempo", "rest", "endurance", "long", "rest"][i]
            if cal.isDate(day, inSameDayAs: today) || cal.isDate(day, inSameDayAs: tomorrow) { kind = "strength" }
            let mins = kind == "rest" ? 0 : kind == "long" ? 120 : kind == "strength" ? 40 : 60
            var w: [String: Any] = ["id": UUID().uuidString, "date": d(day, 7), "kind": kind, "minutes": mins, "done": false, "skipped": false, "note": "", "edited": false, "sequence": 0]
            if kind == "strength" { w["strengthFocus"] = "fullBody" }
            if cal.isDate(day, inSameDayAs: tomorrow) { w["done"] = true }       // the reported bug: "completed" tomorrow
            plan.append(w)
        }
        let tomorrowId = plan.first { ($0["done"] as? Bool) == true }?["id"] as? String ?? ""
        var rides: [[String: Any]] = []
        for k in 0..<16 {
            let m = cal.date(byAdding: .day, value: -7 * (k + 1), to: monday)!
            let pattern: [[Int]] = [[50, 75], [45, 60, 110], [60, 90], [40, 70, 95]]
            let lens: [Int] = pattern[k % 4]
            for j in 0..<lens.count {
                let len = lens[j]
                let start = cal.date(byAdding: .day, value: j * 2 + 1, to: m)!
                rides.append(["id": UUID().uuidString, "start": d(start, 6.5), "durationS": len * 60, "distanceM": len * 470, "avgHR": 136, "maxHR": 160,
                              "zoneSeconds": [len * 6, len * 42, len * 12, 0, 0, 0, 0], "recorder": "phone", "sources": ["Phone GPS"], "demo": false, "samples": [] as [Any]])
            }
        }
        // this week: one recorded ride (Monday) and one Apple Health ride, so "Done this week" ≠ "Planned this week"
        rides.append(["id": UUID().uuidString, "start": d(monday, 6.5), "durationS": 3780, "distanceM": 31_000, "avgHR": 138, "maxHR": 162,
                      "zoneSeconds": [300, 3000, 480, 0, 0, 0, 0], "recorder": "phone", "sources": ["Phone GPS"], "demo": false, "samples": [] as [Any]])
        rides.append(["id": UUID().uuidString, "start": d(monday, 18), "durationS": 1800, "distanceM": 12_000, "zoneSeconds": [0, 1800, 0, 0, 0, 0, 0],
                      "recorder": "health", "healthUUID": "AUDIT-H1", "sources": ["Apple Health"], "demo": false, "samples": [] as [Any]])
        func set(_ reps: Int, _ kg: Double) -> [String: Any] { ["id": UUID().uuidString, "reps": reps, "weightKg": kg, "bodyweight": false, "unilateral": false, "done": true] }
        func entry(_ id: String, _ name: String, _ pat: String, _ reps: Int, _ kg: Double) -> [String: Any] {
            ["id": UUID().uuidString, "exerciseId": id, "name": name, "pattern": pat, "sets": [set(reps, kg), set(reps, kg), set(reps, kg)], "notes": ""]
        }
        var strength: [[String: Any]] = []
        for k in 1...16 {      /* RC2 audit: a realistic 16-week lifting history, like the riding one */
            for day in [1, 4] {
                let date = cal.date(byAdding: .day, value: -7 * k + day, to: monday)!
                strength.append(["id": UUID().uuidString, "date": d(date, 18), "minutes": 40 + k, "focus": "fullBody", "customName": "", "rpe": 7, "notes": "", "source": "manual",
                                 "exercises": [entry("ex-003", "Goblet squat", "squat", 10, 20 + Double(6 - k)), entry("ex-088", "Dumbbell row", "pull", 10, 16), entry("ex-059", "Dumbbell bench press", "push", 8, 18)]])
            }
        }
        // the 1-minute record saved from workout mode with no set ticked, linked to tomorrow's session
        strength.append(["id": UUID().uuidString, "date": d(today, 9), "minutes": 1, "focus": "fullBody", "customName": "", "notes": "", "source": "manual",
                         "workoutId": tomorrowId, "startedAt": d(today, 8.98), "finishedAt": d(today, 9)])
        let profile: [String: Any] = ["name": "Demo", "goal": "fitness", "hoursPerWeek": 5, "level": "intermediate", "weightKg": 75, "age": 40, "ftpW": 225, "ftpHow": "tested", "birthYear": 1986,
                                      "sports": ["roadCycling", "strength"], "version": 3, "updatedAt": "2026-10-25T20:00:00Z", "wheelMm": 2096, "cadenceLow": 85, "cadenceHigh": 95, "hrZoneMethod": "maxHR",
                                      "trainingMode": "hybrid", "priority": "balanced", "cyclingDaysPerWeek": 3, "liftDaysPerWeek": 3, "liftingHoursPerWeek": 1, "preferredDays": [0, 2, 4, 5],
                                      "hybridGoal": "balanced", "strengthSplit": "fullBody"]
        let settings: [String: Any] = ["units": "metric", "phoneOnlyMode": true, "hrPref": "watch", "keepScreenOn": true, "autoConnectBoard": false, "enabledConnections": ["watch"], "appearance": "dark",
                                       "backgroundNotice": true, "coachTalk": "normal", "coachEnabled": true, "appleHealthImportWorkouts": false]
        let file: [String: Any] = ["schema": 1, "profile": profile, "settings": settings, "plan": plan, "rides": rides, "tiles": ["power", "cadence", "hr", "speed", "time", "dist"],
                                   "onboarded": true, "guest": true, "createdAt": "2026-06-01T10:00:00Z", "boardSync": [] as [Any], "onboardingStage": 0, "templates": [] as [Any], "customExercises": [] as [Any],
                                   "appliedProposals": [] as [Any], "equipment": ["owned": ["dumbbell", "bench", "kettlebell"], "excluded": [] as [Any]], "ignoredInsights": [] as [Any], "strength": strength]
        let data = try! JSONSerialization.data(withJSONObject: file)
        return String(data: data, encoding: .utf8)!
    }
}
