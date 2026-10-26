import XCTest
@testable import BikeComputer

/// Cyclift rebrand: names, legal pages and the public support contact.
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

    /// 1.0: the owner published his address as the support contact; the bundled pages carry it directly and describe
    /// the no-account, on-device app truthfully (no sign-in, no server, no third-party integrations advertised).
    func testLegalPagesAreCycliftWithSupportAddressAndNoAccounts() throws {
        for name in ["privacy", "terms"] {
            let text = try bundled(name)
            XCTAssertTrue(text.hasPrefix("# Cyclift — "), "\(name) title")
            XCTAssertFalse(text.contains("Athletics"), "\(name) still names the old app")
            XCTAssertTrue(text.contains(SupportInfo.publicAddress), "\(name) shows the support address")
            XCTAssertFalse(text.contains(SupportInfo.placeholder), "\(name) still has the placeholder")
            for gone in ["Supabase", "Sign in with", "Google", "Profile › Account", "sync between", "later build", "coming soon"] {
                XCTAssertFalse(text.contains(gone), "\(name) still mentions \(gone)")
            }
        }
        let privacy = try bundled("privacy")
        for source in ["Bluetooth", "Apple Watch", "Apple Health", "BikeComputer", "Location", "no account", "Profile › Your data", "Children"] {
            XCTAssertTrue(privacy.contains(source), "privacy policy describes \(source)")
        }
        XCTAssertFalse(privacy.contains("WHOOP") || privacy.contains("Oura") || privacy.contains("Garmin"), "1.0 does not advertise those services")
        XCTAssertTrue(try bundled("terms").contains("not medical advice"), "terms carry the training-guidance disclaimer")
    }

    func testSupportContactRendersUnchangedWithAddress() throws {
        for name in ["privacy", "terms"] {
            let raw = try bundled(name)
            XCTAssertEqual(SupportInfo.render(raw, email: SupportInfo.email), raw, "\(name): nothing left to replace")
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
        // 1.0: static Info.plist value (project.yml), shown in Profile › About › Contact support
        XCTAssertEqual(SupportInfo.email, SupportInfo.publicAddress)
        XCTAssertEqual(SupportInfo.mailURL?.scheme, "mailto")
    }
}
