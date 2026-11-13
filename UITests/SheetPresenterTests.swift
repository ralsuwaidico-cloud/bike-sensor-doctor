import XCTest

/// Shared sheet presenter — targeted checks (prototype only, simulator, sample data).
/// The sequence runs inside the prototype because a UI test cannot issue requests in the same instant.
final class SheetPresenterTests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    /// Duplicate request, switch to a different sheet, cancel-then-other, eight open/close cycles, nothing left behind.
    func test01_PresenterSelfTest() {
        let app = XCUIApplication()
        app.launchEnvironment = ["LAB_THEME": "obsidian", "LAB_SCREEN": "home", "LAB_STRESS": "presenter"]
        app.launch()
        let r = app.descendants(matching: .any).matching(identifier: "stressResult").firstMatch
        XCTAssertTrue(r.waitForExistence(timeout: 240), "The presenter self-test did not finish")
        print("LABNOTE presenter self-test: \(r.label)")
        XCTAssertEqual(r.label, "presenter duplicate:ok switch:ok cancel:ok cycles:8/8 settled:ok")
    }

    /// A presentation is lost on purpose (state set, nothing on screen). An immediate repeat is a duplicate and is
    /// ignored; a repeat after the one-second threshold recovers the sheet.
    func test02_LostPresentationIsRecoveredByARepeatedRequest() {
        let app = XCUIApplication()
        app.launchEnvironment = ["LAB_THEME": "obsidian", "LAB_SCREEN": "home", "LAB_STRESS": "lost"]
        app.launch()
        let r = app.descendants(matching: .any).matching(identifier: "stressResult").firstMatch
        XCTAssertTrue(r.waitForExistence(timeout: 120), "The lost-presentation self-test did not finish")
        print("LABNOTE lost-presentation self-test: \(r.label)")
        XCTAssertEqual(r.label, "lost early-duplicate-ignored:ok stayed-lost:ok recovery:ok settled:ok")
    }
}
