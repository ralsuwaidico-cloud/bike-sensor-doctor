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
        if let first = ids.first { let b = app.buttons[first].firstMatch; if b.exists, b.frame.maxY < win.maxY { XCTAssertTrue(b.isHittable, "\(screen) \(first) not hittable") } }
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
    }
    private func scrollUp(_ app: XCUIApplication) { app.swipeUp(); sleep(1) }
    /// A button of the given identifier prefix that is fully on screen (below the bars), if any.
    private func visibleButton(_ app: XCUIApplication, prefix: String) -> XCUIElement? {
        let win = app.windows.firstMatch.frame
        let q = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", prefix))
        for i in 0..<min(q.count, 8) {
            let e = q.element(boundBy: i)
            let f = e.frame
            if f.minY > win.minY + 120 && f.maxY < win.maxY - 120 { return e }
        }
        return nil
    }

    private func tab(_ app: XCUIApplication, _ name: String) {
        let b = app.buttons[name].firstMatch
        if b.waitForExistence(timeout: 5) { b.tap(); sleep(2) } else { note("tab \(name) missing") }
    }
    private func close(_ app: XCUIApplication) {
        for name in ["Done", "Close", "Cancel"] { let b = app.buttons[name].firstMatch; if b.exists && b.isHittable { b.tap(); sleep(1); return } }
    }

    func testKeyScreensAtTextSizes() throws {
        guard outDir != nil else { throw XCTSkip("LAYOUT_DIR not set — the layout audit runs only in the CI layout stage") }
        for size in sizes {
            let app = launch(size)
            let tag = size.lowercased()
            // Home: coach card actions (short labels, ≥ 44 pt, no overlap)
            shot("\(tag)-01-home")
            checkKey(app, ids: ["coachLog", "coachAdjust", "coachSwap"].filter { app.buttons[$0].exists }, screen: "\(size) home")
            checkTexts(app, screen: "\(size) home")
            scrollUp(app); shot("\(tag)-02-home-lower"); checkTexts(app, screen: "\(size) home lower")
            // today's strength session (centre button): status, exercises with Why? / Swap
            let centre = app.buttons["centreButton"].firstMatch
            if centre.waitForExistence(timeout: 5) {
                centre.tap(); sleep(2)
                shot("\(tag)-03-strength")
                checkTexts(app, screen: "\(size) strength")
                scrollUp(app); shot("\(tag)-04-strength-exercises")
                if let why = visibleButton(app, prefix: "why-") {
                    XCTAssertGreaterThanOrEqual(why.frame.height, 43.5, "\(size) Why? button height")
                    if size == sizes.first { why.tap(); sleep(2); shot("\(tag)-05-why"); close(app) }
                } else { note("\(size): no Why? button on screen") }
                if size == sizes.first, let swap = visibleButton(app, prefix: "swap-") { swap.tap(); sleep(2); shot("\(tag)-06-swap"); close(app) }
                scrollUp(app); shot("\(tag)-07-strength-bottom")
                close(app)
            }
            tab(app, "Plan"); shot("\(tag)-08-plan"); checkTexts(app, screen: "\(size) plan")
            // tomorrow's session: the owner's "completed" bug must now read Planned (future)
            if size == sizes.first {
                let f = DateFormatter(); f.dateFormat = "EEE d MMM"
                let tomorrow = f.string(from: Calendar.current.date(byAdding: .day, value: 1, to: Date())!)
                let day = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", tomorrow)).firstMatch
                if day.exists { day.tap(); sleep(2); shot("\(tag)-08b-tomorrow"); scrollUp(app); shot("\(tag)-08c-tomorrow-lower"); close(app) } else { note("tomorrow's day button not found") }
            }
            scrollUp(app); shot("\(tag)-09-plan-lower")
            scrollUp(app); scrollUp(app); shot("\(tag)-10-history")
            tab(app, "Progress"); shot("\(tag)-11-progress"); checkTexts(app, screen: "\(size) progress")
            let chart = app.descendants(matching: .any).matching(identifier: "ridingChart").firstMatch
            if size == sizes.first, chart.exists {
                chart.press(forDuration: 1.0); sleep(1); shot("\(tag)-12-progress-selected")
            }
            scrollUp(app); shot("\(tag)-13-progress-lower"); checkTexts(app, screen: "\(size) progress lower")
            scrollUp(app); shot("\(tag)-14-progress-ftp")
            tab(app, "Profile"); shot("\(tag)-15-profile"); checkTexts(app, screen: "\(size) profile")
            // tab bar items never overlap the raised centre button
            checkKey(app, ids: ["Home", "Plan", "centreButton", "Progress", "Profile"], screen: "\(size) tab bar", minHeight: 30)
            tab(app, "Home")
            XCTAssertEqual(app.state, .runningForeground)
            app.terminate()
        }
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
        func set(_ reps: Int, _ kg: Double) -> [String: Any] { ["id": UUID().uuidString, "reps": reps, "weightKg": kg, "bodyweight": false, "unilateral": false, "done": true] }
        func entry(_ id: String, _ name: String, _ pat: String, _ reps: Int, _ kg: Double) -> [String: Any] {
            ["id": UUID().uuidString, "exerciseId": id, "name": name, "pattern": pat, "sets": [set(reps, kg), set(reps, kg), set(reps, kg)], "notes": ""]
        }
        var strength: [[String: Any]] = []
        for k in 1...6 {
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
                                      "trainingMode": "hybrid", "priority": "balanced", "cyclingDaysPerWeek": 3, "liftDaysPerWeek": 3, "liftingHoursPerWeek": 2, "preferredDays": [0, 2, 4, 5],
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
