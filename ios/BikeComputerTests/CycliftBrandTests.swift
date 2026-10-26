import XCTest
@testable import BikeComputer

/// Cyclift rebrand: names, legal pages and the support-contact placeholder (no personal address in the bundle).
final class CycliftBrandTests: XCTestCase {
    private func bundled(_ name: String) throws -> String {
        let url = Bundle.main.url(forResource: name, withExtension: "md") ?? Bundle.main.url(forResource: name, withExtension: "md", subdirectory: "Resources")
        return try String(contentsOf: XCTUnwrap(url, "\(name).md must be bundled"), encoding: .utf8)
    }

    func testHomeScreenNameIsCyclift() {
        XCTAssertEqual(Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String, "Cyclift")
        // identifiers that must never change with the rebrand
        XCTAssertEqual(Bundle.main.bundleIdentifier, "com.ralsuwaidico.bikecomputer")
        XCTAssertEqual(CloudConfig.redirectURL.scheme, "com.ralsuwaidico.bikecomputer")
    }

    func testLegalPagesAreCycliftAndCarryNoPersonalAddress() throws {
        for name in ["privacy", "terms"] {
            let text = try bundled(name)
            XCTAssertTrue(text.hasPrefix("# Cyclift — "), "\(name) title")
            XCTAssertFalse(text.contains("Athletics"), "\(name) still names the old app")
            XCTAssertFalse(text.lowercased().contains("@gmail"), "\(name) contains a personal address")
            XCTAssertTrue(text.contains(SupportInfo.placeholder), "\(name) keeps the placeholder for the support address")
        }
        let privacy = try bundled("privacy")
        for source in ["Bluetooth", "Apple Watch", "Apple Health", "BikeComputer", "Garmin, WHOOP and Oura"] {
            XCTAssertTrue(privacy.contains(source), "privacy policy describes \(source)")
        }
    }

    func testSupportContactWithoutConfiguredAddress() throws {
        for name in ["privacy", "terms"] {
            let shown = SupportInfo.render(try bundled(name), email: nil)
            XCTAssertFalse(shown.contains(SupportInfo.placeholder), "\(name): placeholder left visible")
            XCTAssertTrue(shown.contains("Contact: see the [support page](\(SupportInfo.supportPage.absoluteString))"), "\(name): contact line")
        }
    }

    func testSupportContactWithConfiguredAddress() {
        let shown = SupportInfo.render("Intro. Contact: SUPPORT_EMAIL.\n\n## Contact\n\nSUPPORT_EMAIL", email: "help@example.com")
        XCTAssertEqual(shown, "Intro. Contact: help@example.com.\n\n## Contact\n\nhelp@example.com")
    }

    func testSupportAddressCleaning() {
        XCTAssertNil(SupportInfo.cleaned(nil))
        XCTAssertNil(SupportInfo.cleaned(""))
        XCTAssertNil(SupportInfo.cleaned("  "))
        XCTAssertNil(SupportInfo.cleaned("$(CYCLIFT_SUPPORT_EMAIL)"))
        XCTAssertNil(SupportInfo.cleaned("SUPPORT_EMAIL"))
        XCTAssertNil(SupportInfo.cleaned("not an address"))
        XCTAssertEqual(SupportInfo.cleaned(" help@example.com "), "help@example.com")
        // CI leaves the key empty when the optional secret is not set: the app must fall back to the support page
        XCTAssertNil(SupportInfo.email)
    }
}
