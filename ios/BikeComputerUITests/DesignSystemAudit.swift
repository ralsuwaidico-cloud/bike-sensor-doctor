import XCTest

/// Design-system audit (ios/DESIGN_SYSTEM.md). Launches the gallery (`-BC_DESIGN_GALLERY`, simulator only) in light
/// and dark at each text size in LAYOUT_SIZES, screenshots it section by section and checks every on-screen button:
/// inside the window and at least 44 pt tall. Runs only when LAYOUT_DIR is set (ios/ci/build.sh); the CI quick check
/// runs it on the iPhone SE at AX3 and a standard iPhone at L.
final class DesignSystemAudit: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = true }

    private var outDir: String? { let v = ProcessInfo.processInfo.environment["LAYOUT_DIR"] ?? ""; return v.isEmpty ? nil : v }
    private var device: String { ProcessInfo.processInfo.environment["LAYOUT_DEVICE"] ?? "iphone" }
    private var sizes: [String] {
        let v = ProcessInfo.processInfo.environment["LAYOUT_SIZES"] ?? ""
        return v.isEmpty ? ["L", "AX3"] : v.split(separator: ",").map { String($0) }
    }
    private func category(_ s: String) -> String {
        switch s {
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
            let url = URL(fileURLWithPath: d).appendingPathComponent("design-report-\(device).txt")
            let old = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
            try? (old + report.joined(separator: "\n") + "\n").write(to: url, atomically: true, encoding: .utf8)
        }
        super.tearDown()
    }
    private func shot(_ name: String) {
        guard let dir = outDir else { return }
        let png = XCUIScreen.main.screenshot().pngRepresentation
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        try? png.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(device)-design-\(name).png"))
    }
    private func flatten(_ s: XCUIElementSnapshot) -> [XCUIElementSnapshot] { [s] + s.children.flatMap { flatten($0) } }

    /// Every on-screen button (fully inside the vertical window, below the navigation bar) must be inside the window
    /// horizontally and at least 44 pt tall. Hard failures: these are the system's own controls.
    private func checkButtons(_ app: XCUIApplication, screen: String) {
        guard let root = try? app.snapshot() else { note("\(screen): no snapshot"); return }
        let win = app.windows.firstMatch.frame
        var n = 0
        for e in flatten(root) where e.elementType == .button || e.elementType == .switch {
            let f = e.frame
            guard f.width > 0, f.height > 0, f.minY >= win.minY + 90, f.maxY <= win.maxY - 10 else { continue }
            n += 1
            let name = e.identifier.isEmpty ? String(e.label.prefix(30)) : e.identifier
            XCTAssertGreaterThanOrEqual(f.minX, win.minX - 1, "\(screen): \(name) clipped left \(f)")
            XCTAssertLessThanOrEqual(f.maxX, win.maxX + 1, "\(screen): \(name) clipped right \(f)")
            XCTAssertGreaterThanOrEqual(f.height, 43.5, "\(screen): \(name) shorter than 44 pt (\(Int(f.height)))")
            XCTAssertFalse(e.label.isEmpty && e.identifier.isEmpty, "\(screen): a control has no accessible name at \(f)")
        }
        // texts outside the window horizontally (hard: the gallery is the system's own layout)
        var out = 0
        for t in flatten(root) where t.elementType == .staticText {
            let f = t.frame
            guard f.width > 0, f.minY >= win.minY, f.maxY <= win.maxY else { continue }
            if f.minX < win.minX - 1 || f.maxX > win.maxX + 1 { out += 1; XCTFail("\(screen): text outside the window: \"\(t.label.prefix(40))\" \(Int(f.minX))…\(Int(f.maxX)) of \(Int(win.width))") }
        }
        note("\(screen): \(n) controls checked, \(out) texts outside the window")
    }

    func testGalleryLightAndDark() throws {
        guard outDir != nil else { throw XCTSkip("LAYOUT_DIR not set — design audit runs only on the CI layout job") }
        for size in sizes {
            for dark in [false, true] {
                let app = XCUIApplication()
                app.launchArguments += ["-BC_DESIGN_GALLERY", "-UIPreferredContentSizeCategoryName", category(size)]
                if dark { app.launchArguments.append("-BC_DESIGN_GALLERY_DARK") }
                app.launch()
                XCTAssertTrue(app.otherElements["galleryBanner"].firstMatch.waitForExistence(timeout: 30) || app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'DEMO'")).firstMatch.waitForExistence(timeout: 5), "gallery did not appear")
                app.settleForScreenshot()
                let tag = "\(size)-\(dark ? "dark" : "light")"
                // interactions near the top: the segmented control and a chip respond to taps
                let seg = app.buttons["Strength"].firstMatch
                if seg.exists, seg.isHittable { seg.tap(); XCTAssertTrue(seg.isSelected, "\(tag): segmented control did not select") }
                var page = 0
                var lastTexts = ""
                for _ in 0..<14 {
                    shot("\(tag)-\(page)")
                    checkButtons(app, screen: "\(tag) page \(page)")
                    let texts = (try? app.snapshot()).map { flatten($0).filter { $0.elementType == .staticText }.map(\.label).joined() } ?? ""
                    if texts == lastTexts { break }      // reached the end of the scroll view
                    lastTexts = texts
                    app.swipeUp(); app.settleForScreenshot()
                    page += 1
                }
                note("\(tag): \(page + 1) pages")
                app.terminate()
            }
        }
    }
}
