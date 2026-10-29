import XCTest

/// Onboarding audit (owner brief 29 Oct): screenshots of the CURRENT first-run flow and the health check, for the
/// before/after review. No checks beyond "the step appeared"; nothing in the app is changed. Runs only when the runner
/// has LAYOUT_DIR (ios/ci/build.sh with LAYOUT_TEST=OnboardingScreens); otherwise it is skipped.
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
        shot("\(name)-a")
        for part in ["b", "c", "d"] {
            let before = XCUIScreen.main.screenshot().pngRepresentation
            app.swipeUp(); sleep(1)
            if XCUIScreen.main.screenshot().pngRepresentation == before { break }
            shot("\(name)-\(part)")
        }
    }

    func testCurrentOnboardingAndHealthCheck() throws {
        guard outDir != nil else { throw XCTSkip("screenshots only in CI (LAYOUT_DIR)") }
        for size in sizes {
            let tag = size.lowercased()
            let app = XCUIApplication()
            app.launchEnvironment["BC_UITEST_RESET"] = "1"
            app.launchArguments += ["-UIPreferredContentSizeCategoryName", category(size)]
            app.launch()
            let name = app.textFields["onboardingName"].firstMatch
            XCTAssertTrue(name.waitForExistence(timeout: 30), "welcome")
            sleep(1); shotScrolling(app, "\(tag)-00-welcome")
            app.swipeDown(); app.swipeDown(); sleep(1)
            name.tap(); name.typeText("Demo")
            app.buttons["onboardingContinue"].firstMatch.tap(); sleep(2)
            // step 1: pick Hybrid so the hybrid-only parts of later steps are on record too
            let hybrid = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Hybrid Athlete")).firstMatch
            if hybrid.waitForExistence(timeout: 5) { hybrid.tap(); sleep(1) }
            let titles = ["01-mode", "02-week", "03-days", "04-about", "05-goal", "06-hr-ftp", "07-devices", "08-health", "09-ready"]
            for (i, t) in titles.enumerated() {
                app.swipeDown(); app.swipeDown(); sleep(1)
                shotScrolling(app, "\(tag)-\(t)")
                if i < titles.count - 1 {
                    let skip = app.navigationBars.buttons["Skip"].firstMatch
                    if skip.waitForExistence(timeout: 5) { skip.tap() } else { XCTFail("no Skip on \(t)"); break }
                    sleep(2)
                }
            }
            // finish (Start) and open the health check from Home
            app.swipeUp(); app.swipeUp(); sleep(1)
            let start = app.buttons["Start"].firstMatch
            if start.waitForExistence(timeout: 5) { start.tap(); sleep(3) }
            shot("\(tag)-10-home-first")
            let caution = app.buttons["homeCaution"].firstMatch
            if caution.waitForExistence(timeout: 5) {
                caution.tap(); sleep(2)
                shotScrolling(app, "\(tag)-11-healthcheck")
            }
            app.terminate()
        }
    }
}
