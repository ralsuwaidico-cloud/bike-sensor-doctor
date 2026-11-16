import XCTest
@testable import BikeComputer

/// One codebase, two configurations (owner directive, 16 Nov 2026). These tests run against the PRODUCTION app target
/// and pin what that configuration is: the redesign is off, the app is not Cyclift Lab, and theming is not available
/// unless a simulator screenshot run asks for it. Turning the redesign on for production must be a deliberate change
/// that fails this test first.
final class ProductConfigurationTests: XCTestCase {
    func testProductionConfigurationKeepsTheExistingInterface() {
        XCTAssertFalse(CycliftLab.isLab, "the production target must never be built as Cyclift Lab")
        XCTAssertFalse(CyProduct.redesign, "the redesign is switched on for production only by an authorised change")
    }

    func testTheRedesignSwitchHasOneSourceAndItIsTheBuildConfiguration() {
        // the switch is a constant decided at build time; nothing stored on the phone or sent to it can change it
        XCTAssertEqual(CyProduct.redesign, CycliftLab.isLab)
        for key in ["redesign", "CyProduct.redesign", "cyclift.redesign"] {
            UserDefaults.standard.set(true, forKey: key)
            XCTAssertFalse(CyProduct.redesign, "a stored value '\(key)' must not switch the redesign on")
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    func testThemingIsNotAvailableInProductionWithoutAScreenshotRun() {
        guard ProcessInfo.processInfo.environment["BC_UITEST_THEME"] == nil else { return }
        XCTAssertFalse(CyThemeState.available, "production keeps its existing appearance until UX1 is introduced")
    }
}
