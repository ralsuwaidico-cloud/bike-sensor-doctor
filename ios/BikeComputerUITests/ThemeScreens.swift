import XCTest

/// UX1 preview: the same five real screens in each of the six themes, with the layout audit's clearly labelled demo
/// athlete. Screenshots only — it makes no claim about layout or behaviour. Runs when the runner has LAYOUT_DIR
/// (ios/ci/build.sh with LAYOUT_TEST=ThemeScreens); skipped everywhere else.
/// The themes are applied by the simulator-only preview bridge (DesignSystem/ThemeRuntime.swift). Screens or parts of
/// screens that do not change between themes are the ones not yet drawn from the shared tokens.
final class ThemeScreens: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = true }
    override func tearDown() { XCUIDevice.shared.appearance = .light; super.tearDown() }

    private var outDir: String? { let v = ProcessInfo.processInfo.environment["LAYOUT_DIR"] ?? ""; return v.isEmpty ? nil : v }
    private var device: String { ProcessInfo.processInfo.environment["LAYOUT_DEVICE"] ?? "iphone" }
    private func shot(_ name: String) {
        guard let dir = outDir else { return }
        let png = XCUIScreen.main.screenshot().pngRepresentation
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        try? png.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(device)-theme-\(name).png"))
    }
    private func tab(_ app: XCUIApplication, _ name: String) -> Bool {
        let b = app.buttons[name].firstMatch
        guard b.waitForExistence(timeout: 5) else { XCTFail("tab \(name) missing"); return false }
        b.tap(); app.settleForScreenshot(2); return true
    }

    /// (theme, dark appearance for the parts still drawn with system colours)
    private let themes: [(String, Bool)] = [("obsidian", true), ("arctic", false), ("ocean", true), ("forest", true), ("sandstone", false), ("highContrast", true)]

    func testFiveScreensInSixThemes() throws {
        guard outDir != nil else { throw XCTSkip("LAYOUT_DIR not set — theme screenshots run only in the CI layout stage") }
        for (i, (theme, dark)) in themes.enumerated() {
            XCUIDevice.shared.appearance = dark ? .dark : .light
            let app = XCUIApplication()
            app.launchEnvironment["BC_UITEST_SEED_JSON"] = LayoutAudit.demoStore()
            app.launchEnvironment["BC_UITEST_THEME"] = theme
            app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryL"]
            app.launch()
            XCTAssertTrue(app.waitForHome(name: "Demo", timeout: 30), "\(theme): Home did not appear")
            app.settleForScreenshot(2)
            let tag = "\(i + 1)-\(theme)"
            shot("\(tag)-1-home")
            app.swipeUp(); app.settleForScreenshot(); shot("\(tag)-2-home-lower")
            let centre = app.buttons["centreButton"].firstMatch
            if centre.waitForExistence(timeout: 5) {
                centre.tap(); app.settleForScreenshot(2); shot("\(tag)-3-train")     // the tab tap below closes the hub
            }
            if tab(app, "Plan") { shot("\(tag)-4-plan") }
            if tab(app, "Progress") { shot("\(tag)-5-progress") }
            if tab(app, "Profile") { shot("\(tag)-6-profile") }
            app.terminate()
        }
    }
}
