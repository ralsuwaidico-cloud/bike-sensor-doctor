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

    /// Onboarding r7 (rc3): Welcome, then five screens "1 of 5" … "5 of 5"; no height, no health questionnaire.
    /// Screenshots in CI (LAYOUT_DIR) plus real checks: the step counter, the Hybrid-only rows, the week counts and that
    /// Create plan lands on Home without a health prompt.
    func testOnboardingR7FiveScreens() throws {
        // outside the layout run (plain UI test pass) one text size keeps it quick; the layout run does both
        for size in (outDir == nil ? ["L"] : sizes) {
            let tag = size.lowercased()
            let app = XCUIApplication()
            app.launchEnvironment["BC_UITEST_RESET"] = "1"
            app.launchArguments += ["-UIPreferredContentSizeCategoryName", category(size)]
            app.launch()
            let name = app.textFields["onboardingName"].firstMatch
            XCTAssertTrue(name.waitForExistence(timeout: 30), "welcome")
            shot("\(tag)-00-welcome")
            name.tap(); name.typeText("Demo")
            app.buttons["onboardingContinue"].firstMatch.tap(); sleep(2)
            // 1 About you + training
            XCTAssertTrue(app.staticTexts["1 of 5"].waitForExistence(timeout: 10), "\(tag): step counter on screen 1")
            XCTAssertFalse(app.staticTexts["Height"].exists, "\(tag): height is not asked in onboarding (r7)")
            let hybrid = app.buttons["Hybrid"].firstMatch
            if hybrid.waitForExistence(timeout: 5) { hybrid.tap(); sleep(1) }
            XCTAssertTrue(app.staticTexts["Strength level"].waitForExistence(timeout: 5), "\(tag): Hybrid shows the strength level row")
            XCTAssertTrue(app.staticTexts["Priority"].exists, "\(tag): Hybrid shows the priority row")
            shotScrolling(app, "\(tag)-01-about")
            let titles = ["02-goals", "03-week", "04-connections", "05-plan"]
            for (i, t) in titles.enumerated() {
                app.swipeUp(); app.swipeUp(); sleep(1)
                let next = app.buttons["onboardingNext"].firstMatch
                XCTAssertTrue(next.waitForExistence(timeout: 5), "\(tag): Continue before \(t)")
                next.tap(); sleep(2)
                XCTAssertTrue(app.staticTexts["\(i + 2) of 5"].waitForExistence(timeout: 5), "\(tag): step counter on \(t)")
                if t == "04-connections" { XCTAssertTrue(app.buttons["onboardingSkip"].firstMatch.waitForExistence(timeout: 5), "\(tag): Skip on Connections") }
                if t == "03-week" { XCTAssertTrue(app.otherElements["onbWeekCounts"].exists || app.staticTexts["Tap a day to change it"].exists, "\(tag): week counts") }
                app.swipeDown(); app.swipeDown(); sleep(1)
                shotScrolling(app, "\(tag)-\(t)")
            }
            XCTAssertTrue(app.otherElements["onbWhy"].exists || app.staticTexts["WHY THIS PLAN"].exists, "\(tag): Why this plan")
            app.swipeUp(); app.swipeUp(); sleep(1)
            let create = app.buttons["onbCreatePlan"].firstMatch
            XCTAssertTrue(create.waitForExistence(timeout: 5), "\(tag): Create plan")
            create.tap(); sleep(3)
            shot("\(tag)-06-home-first")
            XCTAssertFalse(app.buttons["homeCaution"].firstMatch.waitForExistence(timeout: 3), "\(tag): the health check must not be asked after onboarding")
            app.terminate()
        }
    }
}
