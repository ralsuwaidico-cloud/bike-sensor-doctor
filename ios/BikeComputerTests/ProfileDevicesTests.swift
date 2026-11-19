import XCTest
@testable import BikeComputer

/// Profile › Devices & Connections (sheet P06) and Permissions (sheet P08 F2): the pure rules behind the redesigned
/// pages — where "This iPhone" sits, what Cyclift Lab shows, which sensor row a sensor belongs to, the permission words.
final class ProfileDevicesTests: XCTestCase {
    private func rows(mode: TrainingMode) -> [ProfileDeviceRow] {
        let cards = DeviceCards.build(states: [:], mode: mode, bleSensors: [], healthAvailable: true, boardRemembered: false)
        return ProfileDeviceRows.build(cards: cards, healthAvailable: true, cycling: mode.includesCycling)
    }

    func testThisIPhoneSitsAfterTheSensorsAndBeforeDiagnostics() {
        let r = ProfileDeviceRows.withPhone(rows(mode: .hybrid), summary: "Bluetooth on · location allowed")
        XCTAssertEqual(r.map(\.id), ["health", "watch", "board", "cywatch", "hr", "power", "other", "phone", "diagnostics"])
        let phone = r.first { $0.id == "phone" }
        XCTAssertEqual(phone?.title, "This iPhone"); XCTAssertEqual(phone?.opens, .phone); XCTAssertNil(phone?.state, "a phone is not a connection: no state word")
        XCTAssertEqual(ProfileDeviceRows.withPhone(rows(mode: .strength), summary: "x").map(\.id), ["health", "watch", "cywatch", "phone", "diagnostics"])
    }

    func testEveryFamilyRowOpensItsOwnPageAndTheFutureWatchOpensNothing() {
        let r = rows(mode: .hybrid)
        func opens(_ id: String) -> ProfileDeviceRow.Opens? { r.first { $0.id == id }?.opens }
        XCTAssertEqual(opens("health"), .health); XCTAssertEqual(opens("watch"), .watch); XCTAssertEqual(opens("board"), .board)
        for id in ["hr", "power", "other"] { XCTAssertEqual(opens(id), .sensors); XCTAssertNotNil(ProfileSensorFamily(rawValue: id), "the sensors page is chosen by the row's id") }
        XCTAssertEqual(opens("cywatch"), .nothing, "the future device opens nothing"); XCTAssertEqual(opens("diagnostics"), .diagnostics)
    }

    func testLabShowsEveryFamilyUnavailableAndNeverAConnection() {
        let lab = ProfileDeviceRows.lab(cycling: true)
        XCTAssertEqual(lab.map(\.id), ["health", "watch", "board", "cywatch", "hr", "power", "other", "phone"])
        for r in lab where r.id != "phone" { XCTAssertEqual(r.state, .unavailable, "\(r.id) is Unavailable in Lab") }
        XCTAssertNil(lab.last?.state); XCTAssertTrue(lab.last?.summary.contains("not used in Cyclift Lab") ?? false)
        XCTAssertEqual(lab.first { $0.id == "cywatch" }?.opens, .nothing)
        XCTAssertEqual(ProfileDeviceRows.lab(cycling: false).map(\.id), ["health", "watch", "cywatch", "phone"], "a strength-only athlete has no bike rows")
    }

    func testASensorBelongsToOneFamilyPowerFirst() {
        XCTAssertEqual(ProfileSensorFamily.of(hasHR: true, hasPower: false), .hr)
        XCTAssertEqual(ProfileSensorFamily.of(hasHR: false, hasPower: true), .power)
        XCTAssertEqual(ProfileSensorFamily.of(hasHR: true, hasPower: true), .power, "the same precedence as the row icon")
        XCTAssertEqual(ProfileSensorFamily.of(hasHR: false, hasPower: false), .other)
        XCTAssertEqual(ProfileSensorFamily.allCases.map(\.title), ["Heart-rate sensors", "Power meters", "Other sensors"])
    }

    func testPermissionWordsStateOnlyWhatIsKnown() {
        XCTAssertEqual(ProfilePhoneWords.bluetooth(off: false, unauthorized: false, unsupported: false), "On")
        XCTAssertEqual(ProfilePhoneWords.bluetooth(off: true, unauthorized: false, unsupported: false), "Off")
        XCTAssertEqual(ProfilePhoneWords.bluetooth(off: true, unauthorized: true, unsupported: false), "Not allowed", "a refused permission is said before the radio state")
        XCTAssertEqual(ProfilePhoneWords.bluetooth(off: false, unauthorized: false, unsupported: true), "Not available")
        XCTAssertEqual(ProfilePhoneWords.location(authorized: true, denied: false), "Allowed")
        XCTAssertEqual(ProfilePhoneWords.location(authorized: false, denied: true), "Not allowed")
        XCTAssertEqual(ProfilePhoneWords.location(authorized: false, denied: false), "Not asked yet", "never asked is not the same as refused")
        XCTAssertEqual(ProfilePhoneWords.notifications(.notAsked), "Not asked yet"); XCTAssertEqual(ProfilePhoneWords.notifications(.allowed), "Allowed")
        XCTAssertEqual(ProfilePhoneWords.notifications(.notAllowed), "Not allowed")
        XCTAssertEqual(ProfilePhoneWords.health(available: false, writeAuthorized: false, wanted: true), "Not available")
        XCTAssertEqual(ProfilePhoneWords.health(available: true, writeAuthorized: true, wanted: true), "On")
        XCTAssertEqual(ProfilePhoneWords.health(available: true, writeAuthorized: false, wanted: true), "Not allowed")
        XCTAssertEqual(ProfilePhoneWords.health(available: true, writeAuthorized: false, wanted: false), "Off")
        XCTAssertEqual(ProfilePhoneWords.summary(bluetooth: "On", location: "Not asked yet"), "Bluetooth on · location not asked yet")
    }
}
