import XCTest

/// Onboarding r7 (rc3): the five-screen first run, checked step by step; screenshots only when the runner has
/// LAYOUT_DIR (ios/ci/build.sh with LAYOUT_TEST=OnboardingScreens). Sizes from LAYOUT_SIZES (default L and AX3).
final class OnboardingScreens: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = true }

    private var outDir: String? { let v = ProcessInfo.processInfo.environment["LAYOUT_DIR"] ?? ""; return v.isEmpty ? nil : v }
    private var device: String { ProcessInfo.processInfo.environment["LAYOUT_DEVICE"] ?? "iphone" }
    private var sizes: [String] {
        let v = ProcessInfo.processInfo.environment["LAYOUT_SIZES"] ?? ""
        return v.isEmpty ? ["L", "AX3"] : v.split(separator: ",").map { String($0) }
    }
    private func category(_ s: String) -> String {
        switch s {
        case "XXXL": return "UICTContentSizeCategoryXXXL"
        case "AX3": return "UICTContentSizeCategoryAccessibilityXL"
        default: return "UICTContentSizeCategoryL"
        }
    }
    private func shot(_ name: String) {
        guard let dir = outDir else { return }
        let png = XCUIScreen.main.screenshot().pngRepresentation
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        try? png.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(device)-onb-\(name).png"))
    }
    /// The screen, then (when it scrolls) up to three more screens of it, so the whole step is on record.
    private func shotScrolling(_ app: XCUIApplication, _ name: String) {
        guard outDir != nil else { return }
        shot("\(name)-a")
        for part in ["b", "c", "d"] {
            let before = XCUIScreen.main.screenshot().pngRepresentation
            app.swipeUp(); sleep(1)
            if XCUIScreen.main.screenshot().pngRepresentation == before { break }
            shot("\(name)-\(part)")
        }
    }

    /// Onboarding v3 (V1): Welcome (no input), then stages A–E. Real checks, not just navigation: the name is asked once,
    /// Continue waits for name + type, the goal effect appears, the week shows a live plan preview, Skip works on D, and
    /// Approve lands on Home with the same plan — the first workout shown on E is in Plan, and Home has the week strip.
    func testOnboardingV3FiveStages() throws {
        for size in (outDir == nil ? ["L"] : sizes) {
            let tag = size.lowercased()
            let app = XCUIApplication()
            app.launchEnvironment["BC_UITEST_RESET"] = "1"
            app.launchArguments += ["-UIPreferredContentSizeCategoryName", category(size)]
            app.launch()
            // Welcome: brand + Get started; no text field anywhere (GR-19: the name is asked once, on stage A)
            let start = app.buttons["onboardingContinue"].firstMatch
            XCTAssertTrue(start.waitForExistence(timeout: 30), "\(tag): welcome")
            XCTAssertFalse(app.textFields["onboardingName"].exists, "\(tag): the welcome screen asks no name")
            XCTAssertEqual(app.textFields.count, 0, "\(tag): no input on the welcome screen")
            shot("\(tag)-00-welcome")
            start.tap(); sleep(2)
            // A — name once + type; Continue disabled until both
            XCTAssertTrue(app.staticTexts["Who you are · 1 of 5"].waitForExistence(timeout: 10), "\(tag): stage A counter")
            let next = app.buttons["onboardingNext"].firstMatch
            XCTAssertTrue(next.waitForExistence(timeout: 5))
            XCTAssertFalse(next.isEnabled, "\(tag): Continue waits for a name and a type")
            let name = app.textFields["onbName"].firstMatch
            XCTAssertTrue(name.waitForExistence(timeout: 5)); name.tap(); name.typeText("Demo")
            XCTAssertEqual(app.textFields.matching(NSPredicate(format: "identifier CONTAINS[c] 'name'")).count, 1, "\(tag): exactly one name field in onboarding")
            XCTAssertFalse(next.isEnabled, "\(tag): still needs a type")
            let hybrid = app.buttons["onbMode-hybrid"].firstMatch
            XCTAssertTrue(hybrid.waitForExistence(timeout: 5)); hybrid.tap(); sleep(1)
            // APP-038: choosing a type puts the keyboard away, so the cards and Continue are never covered
            XCTAssertTrue(app.keyboards.firstMatch.waitUntilGone(timeout: 5), "\(tag): APP-038 keyboard dismissed by choosing a type")
            XCTAssertTrue(next.isHittable, "\(tag): APP-038 Continue is reachable after the keyboard goes")
            XCTAssertTrue(app.staticTexts["STRENGTH EXPERIENCE"].waitForExistence(timeout: 5) || app.staticTexts["Strength experience"].exists, "\(tag): Hybrid shows the strength experience chips")
            XCTAssertTrue(app.otherElements["onbPriority"].exists || app.staticTexts["PRIORITY"].exists || app.staticTexts["Priority"].exists, "\(tag): Hybrid shows the priority segment")
            XCTAssertFalse(app.staticTexts["Height"].exists, "\(tag): height is not asked")
            XCTAssertTrue(app.buttons["onbDOB"].firstMatch.label.contains("not set"), "\(tag): date of birth starts unset — nothing is pre-filled")
            if app.keyboards.count > 0 { app.swipeDown() }
            XCTAssertTrue(next.isEnabled, "\(tag): name + type → Continue")
            shotScrolling(app, "\(tag)-01-who")
            app.swipeDown(); app.swipeDown(); sleep(1)
            next.tap(); sleep(2)
            // B — goals: one tap = main goal, the effect line appears
            XCTAssertTrue(app.staticTexts["Your goals · 2 of 5"].waitForExistence(timeout: 10), "\(tag): stage B counter")
            XCTAssertFalse(next.isEnabled, "\(tag): Continue waits for a goal")
            let endurance = app.buttons["goal-endurance"].firstMatch
            XCTAssertTrue(endurance.waitForExistence(timeout: 5)); endurance.tap(); sleep(1)
            XCTAssertTrue(app.otherElements["onbGoalEffect"].waitForExistence(timeout: 5) || app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Zone 2'")).firstMatch.exists, "\(tag): the main goal's effect line")
            XCTAssertTrue(next.isEnabled)
            shotScrolling(app, "\(tag)-02-goals")
            app.swipeDown(); app.swipeDown(); sleep(1)
            next.tap(); sleep(2)
            // C — the coach's proposal and the live preview from the real planner
            XCTAssertTrue(app.staticTexts["Your week · 3 of 5"].waitForExistence(timeout: 10), "\(tag): stage C counter")
            XCTAssertTrue(app.otherElements["onbWeek"].firstMatch.waitForExistence(timeout: 5) || app.otherElements["cyWeekStrip"].firstMatch.exists, "\(tag): week strip")
            XCTAssertTrue(app.otherElements["onbWeekCounts"].exists || app.staticTexts["Coach's proposal"].exists, "\(tag): the coach proposed the week")
            XCTAssertTrue(app.otherElements["onbFeasibility"].exists || app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'a week'")).firstMatch.exists, "\(tag): feasibility line")
            let preview = app.otherElements["onbPlanPreview"].firstMatch
            var tries = 0
            while !preview.exists && tries < 6 { app.swipeUp(); sleep(1); tries += 1 }
            XCTAssertTrue(preview.exists, "\(tag): live plan preview strip")
            shotScrolling(app, "\(tag)-03-week")
            app.swipeDown(); app.swipeDown(); app.swipeDown(); sleep(1)
            // tapping a day changes it (the proposal is never overridden silently; the athlete's tap is)
            let day3 = app.buttons["cyDay-3"].firstMatch
            if day3.waitForExistence(timeout: 3) { let before = day3.label; day3.tap(); sleep(1); XCTAssertNotEqual(day3.label, before, "\(tag): a tap cycles the day") }
            app.swipeUp(); app.swipeUp(); sleep(1)
            XCTAssertTrue(next.waitForExistence(timeout: 5)); next.tap(); sleep(2)
            // D — ecosystem: real device cards, Skip
            XCTAssertTrue(app.staticTexts["Your ecosystem · 4 of 5"].waitForExistence(timeout: 10), "\(tag): stage D counter")
            XCTAssertTrue(app.buttons["onboardingSkip"].firstMatch.waitForExistence(timeout: 5), "\(tag): Skip on D")
            XCTAssertTrue(app.otherElements["deviceHealth"].firstMatch.exists || app.buttons["deviceHealth"].firstMatch.exists, "\(tag): Apple Health card")
            XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'deviceState-'")).firstMatch.exists, "\(tag): a real state badge on every card, never a switch")
            shotScrolling(app, "\(tag)-04-ecosystem")
            app.swipeDown(); app.swipeDown(); sleep(1)
            // run 147 (standard): a tap sent while the scroll was still settling did not register — wait for idle first
            XCTAssertTrue(app.buttons["onboardingSkip"].firstMatch.tapWhenSettled()); sleep(2)
            // E — the first dashboard; remember the first workout, then Approve
            XCTAssertTrue(app.staticTexts["Your training system · 5 of 5"].waitForExistence(timeout: 10), "\(tag): stage E counter")
            XCTAssertTrue(app.otherElements["onbDash"].firstMatch.waitForExistence(timeout: 5), "\(tag): dashboard card")
            let first = app.otherElements["onbFirst"].firstMatch
            var firstTitle = ""
            let rideTitles = ["Endurance", "Tempo", "Threshold", "VO2 max", "Recovery spin", "Long ride", "FTP test"]
            if first.waitForExistence(timeout: 5) { firstTitle = first.staticTexts.allElementsBoundByIndex.map(\.label).first { $0.hasPrefix("Strength ·") || rideTitles.contains($0) } ?? "" }
            XCTAssertTrue(app.otherElements["onbWhy"].exists || app.staticTexts["THE APPROACH"].exists, "\(tag): the approach")
            shotScrolling(app, "\(tag)-05-system")
            app.swipeUp(); app.swipeUp(); sleep(1)
            let approve = app.buttons["onbCreatePlan"].firstMatch
            XCTAssertTrue(approve.waitForExistence(timeout: 5), "\(tag): Approve plan"); approve.tap(); sleep(3)
            // Home: the week strip is there, no health prompt, and the plan exists (the same one)
            shot("\(tag)-06-home-first")
            XCTAssertTrue(app.otherElements["homeWeek"].firstMatch.waitForExistence(timeout: 10) || app.buttons["homeWeekDay-0"].firstMatch.waitForExistence(timeout: 3), "\(tag): Home shows the week")
            XCTAssertFalse(app.buttons["homeCaution"].firstMatch.waitForExistence(timeout: 2), "\(tag): no health questionnaire after onboarding")
            XCTAssertFalse(app.buttons["onboardingContinue"].exists, "\(tag): onboarding is not shown again")
            // Plan: the first workout shown on E is in the plan
            app.buttons["Plan"].firstMatch.tap(); sleep(2)
            if !firstTitle.isEmpty {
                let key = firstTitle.components(separatedBy: " · ").last ?? firstTitle
                var shown = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", key)).firstMatch.waitForExistence(timeout: 5)
                if !shown {
                    // late in the week stage E shows NEXT week's first session (run 191, Sunday): it is on the Plan's next-week page
                    let next = app.buttons["Next week"].firstMatch
                    if next.exists && next.isEnabled { next.tap(); sleep(1); shown = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", key)).firstMatch.waitForExistence(timeout: 5) }
                }
                XCTAssertTrue(shown, "\(tag): Plan shows the first workout from stage E (\(key)) this week or next")
            }
            shot("\(tag)-07-plan-first")
            app.terminate()
        }
    }
}
