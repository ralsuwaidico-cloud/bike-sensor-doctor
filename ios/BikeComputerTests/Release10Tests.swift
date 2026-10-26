import XCTest
@testable import BikeComputer

/// Cyclift 1.0 App Store hardening (docs/briefs/RELEASE_1_0_DECISIONS.md): no accounts, no placeholders, privacy
/// manifest, permission strings. Hosted in the app, so Bundle.main is the shipped app bundle.
final class Release10Tests: XCTestCase {

    // MARK: no accounts in 1.0
    func testAccountsAreSwitchedOff() {
        XCTAssertFalse(ReleaseFlags.accountsEnabled, "1.0 ships without accounts")
        XCTAssertFalse(CloudConfig.isConfigured)
        XCTAssertFalse(CloudConfig.googleEnabled)
    }

    func testReleaseSwitchWinsOverAccountValues() {
        let url = URL(string: "https://example.supabase.co")!
        // even with both values present, the 1.0 switch keeps accounts off …
        XCTAssertFalse(CloudConfig.configured(accountsEnabled: ReleaseFlags.accountsEnabled, url: url, anonKey: "anon-key"))
        XCTAssertFalse(CloudConfig.configured(accountsEnabled: false, url: url, anonKey: "anon-key"))
        // … and the rule itself still works for 1.1 (values required once the switch is on)
        XCTAssertTrue(CloudConfig.configured(accountsEnabled: true, url: url, anonKey: "anon-key"))
        XCTAssertFalse(CloudConfig.configured(accountsEnabled: true, url: nil, anonKey: "anon-key"))
        XCTAssertFalse(CloudConfig.configured(accountsEnabled: true, url: url, anonKey: nil))
    }

    @MainActor
    func testAccountServiceStaysInert() {
        let account = AccountService()
        XCTAssertFalse(account.hasClient, "no Supabase client may exist in 1.0")
        XCTAssertEqual(account.state, .notConfigured)
        XCTAssertFalse(account.handle(url: URL(string: "com.ralsuwaidico.bikecomputer://auth-callback#access_token=x")!))
    }

    func testPlannedProvidersAreHidden() {
        XCTAssertFalse(ReleaseFlags.plannedProvidersVisible, "no Garmin / WHOOP / Oura placeholders in 1.0")
    }

    // MARK: privacy manifest
    func testPrivacyManifestIsBundledAndDeclaresNoTracking() throws {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "PrivacyInfo", withExtension: "xcprivacy"), "PrivacyInfo.xcprivacy must be in the app bundle")
        let plist = try XCTUnwrap(PropertyListSerialization.propertyList(from: Data(contentsOf: url), format: nil) as? [String: Any])
        XCTAssertEqual(plist["NSPrivacyTracking"] as? Bool, false)
        XCTAssertEqual((plist["NSPrivacyTrackingDomains"] as? [Any])?.count, 0)
        XCTAssertEqual((plist["NSPrivacyCollectedDataTypes"] as? [Any])?.count, 0, "1.0 sends no data off the device")
        let apis = try XCTUnwrap(plist["NSPrivacyAccessedAPITypes"] as? [[String: Any]])
        let defaults = apis.first { $0["NSPrivacyAccessedAPIType"] as? String == "NSPrivacyAccessedAPICategoryUserDefaults" }
        XCTAssertEqual(defaults?["NSPrivacyAccessedAPITypeReasons"] as? [String], ["CA92.1"], "UserDefaults: app-only settings")
    }

    // MARK: Info.plist checks
    func testInfoPlistIsReleaseReady() {
        let info = Bundle.main.infoDictionary ?? [:]
        XCTAssertEqual(info["CFBundleDisplayName"] as? String, "Cyclift")
        XCTAssertEqual(info["CFBundleShortVersionString"] as? String, "1.0.0")
        XCTAssertEqual(info["ITSAppUsesNonExemptEncryption"] as? Bool, false)
        XCTAssertEqual(info["UIDeviceFamily"] as? [Int], [1], "iPhone only")
        XCTAssertEqual(Set(info["UIBackgroundModes"] as? [String] ?? []), ["bluetooth-central", "location"])
        XCTAssertNil(info["NSLocationAlwaysAndWhenInUseUsageDescription"], "the app only asks for When In Use")
        XCTAssertNil(info["NSLocationAlwaysUsageDescription"])
        for key in ["NSBluetoothAlwaysUsageDescription", "NSLocationWhenInUseUsageDescription", "NSHealthShareUsageDescription", "NSHealthUpdateUsageDescription"] {
            let text = info[key] as? String ?? ""
            XCTAssertTrue(text.hasPrefix("Cyclift "), "\(key) must name Cyclift")
            XCTAssertFalse(text.contains("Athletics") || text.contains("Waveshare"), "\(key) brand")
        }
    }
}
