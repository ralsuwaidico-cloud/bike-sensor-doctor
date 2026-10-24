import XCTest
@testable import BikeComputer

/// Link v1.2 conformance: every byte vector below is copied from firmware/waveshare/docs/BLE_LINK_PROTOCOL.md
/// (asserted there by test/host t_link2 / t_link3). Both sides must agree byte for byte.
final class LinkV12Tests: XCTestCase {
    private func bytes(_ hex: String) -> [UInt8] { hex.split(separator: " ").map { UInt8($0, radix: 16)! } }

    // MARK: Wi-Fi provisioning
    func testWiFiRequestsMatchFirmwareVectors() {
        XCTAssertEqual([UInt8](BCLink.encodeWiFiStatusRequest(seq: 10, tMs: 0)!), bytes("66 00 0A 00 00 00 00 00"))
        XCTAssertEqual([UInt8](BCLink.encodeWiFiScanRequest(max: nil, seq: 1, tMs: 0)!), bytes("60 00 01 00 00 00 00 00"))
        XCTAssertEqual([UInt8](BCLink.encodeWiFiScanRequest(max: 8, seq: 2, tMs: 0)!), bytes("60 00 02 00 00 00 00 00 01 01 08"))
        XCTAssertEqual([UInt8](BCLink.encodeWiFiSet(ssid: "HomeNet", password: "Secret-123", seq: 7, tMs: 0)!),
                       bytes("63 00 07 00 00 00 00 00 01 07 48 6F 6D 65 4E 65 74 02 0A 53 65 63 72 65 74 2D 31 32 33 03 01 03"))
        XCTAssertEqual([UInt8](BCLink.encodeWiFiForget(ssid: "HomeNet", seq: 8, tMs: 0)!), bytes("64 00 08 00 00 00 00 00 01 07 48 6F 6D 65 4E 65 74"))
        // limits: empty SSID, 64-byte password → rejected before anything reaches the board
        XCTAssertNil(BCLink.encodeWiFiSet(ssid: "", password: "x", seq: 1, tMs: 0))
        XCTAssertNil(BCLink.encodeWiFiSet(ssid: "a", password: String(repeating: "p", count: 64), seq: 1, tMs: 0))
        XCTAssertNotNil(BCLink.encodeWiFiSet(ssid: "open", password: "", seq: 1, tMs: 0))
    }

    func testWiFiScanResultWithCurlyApostrophe() {
        let d = Data(bytes("61 00 05 00 00 00 00 00 01 11 52 61 73 68 65 64 E2 80 99 73 20 69 50 68 6F 6E 65 02 01 C2 03 01 01 04 01 06 05 01 00"))
        let n = BCLink.decodeWiFiScanResult(d)
        XCTAssertEqual(n?.ssid, "Rashed’s iPhone")          // U+2019, matched byte-exact, never replaced by '
        XCTAssertEqual(n?.rssi, -62); XCTAssertEqual(n?.secured, true); XCTAssertEqual(n?.channel, 6); XCTAssertEqual(n?.saved, false)
        let e = BCLink.decodeWiFiScanEnd(Data(bytes("62 00 06 00 00 00 00 00 01 01 03 02 01 00")))
        XCTAssertEqual(e?.count, 3); XCTAssertEqual(e?.err, 0); XCTAssertNil(e?.errorText)
        XCTAssertEqual(BCLink.decodeWiFiScanEnd(Data(bytes("62 00 06 00 00 00 00 00 01 01 00 02 01 02")))?.errorText, "board busy (ride running)")
    }

    func testWiFiStatusVector() {
        let s = BCLink.decodeWiFiStatus(Data(bytes("65 00 09 00 00 00 00 00 01 01 04 02 01 00 03 07 48 6F 6D 65 4E 65 74 04 01 D0 05 01 02 06 01 01")))
        XCTAssertEqual(s?.state, .connected); XCTAssertEqual(s?.error, BCLink.WiFiError.none); XCTAssertEqual(s?.ssid, "HomeNet")
        XCTAssertEqual(s?.rssi, -48); XCTAssertEqual(s?.savedCount, 2); XCTAssertEqual(s?.radioOn, true)
        // wrong password is a distinct, user-visible state
        let w = BCLink.decodeWiFiStatus(Data(bytes("65 00 09 00 00 00 00 00 01 01 01 02 01 01")))
        XCTAssertEqual(w?.state, .disconnected); XCTAssertEqual(w?.error.label, "Wrong password")
    }

    // MARK: profile sync
    func testProfileVectors() {
        XCTAssertEqual([UInt8](BCLink.encodeProfileGet(seq: 1, tMs: 0)!), bytes("70 00 01 00 00 00 00 00"))
        var p = BCLink.ProfileMessage()
        p.version = 1; p.updatedEpochS = 1792850100; p.name = "Rashed"; p.ftpW = 250; p.ftpHow = 1; p.weightKgX10 = 780; p.birthYear = 1990
        p.maxHR = 186; p.restHR = 52; p.units = 0; p.hoursPerWeek = 6; p.level = 2; p.goal = 1; p.lthr = 170
        let expected = bytes("71 00 02 00 00 00 00 00 01 04 01 00 00 00 02 04 B4 B8 DC 6A 03 06 52 61 73 68 65 64 04 02 FA 00 05 01 01 06 02 0C 03 07 02 C6 07 08 01 BA 09 01 34 0A 01 00 0B 01 06 0C 01 02 0D 01 01 0E 01 AA")
        XCTAssertEqual([UInt8](BCLink.encodeProfileSet(p, seq: 2, tMs: 0)!), expected)
        // the same bytes decode back (0 values for birth/max/rest/lthr become nil)
        let back = BCLink.decodeProfile(Data(expected))
        XCTAssertEqual(back?.name, "Rashed"); XCTAssertEqual(back?.ftpW, 250); XCTAssertEqual(back?.weightKgX10, 780); XCTAssertEqual(back?.birthYear, 1990)
        XCTAssertEqual(back?.lthr, 170); XCTAssertEqual(back?.level, 2); XCTAssertEqual(back?.goal, 1)
        var zero = p; zero.birthYear = 0; zero.maxHR = 0
        let z = BCLink.decodeProfile(BCLink.encodeProfileSet(zero, seq: 1, tMs: 0)!)
        XCTAssertNil(z?.birthYear); XCTAssertNil(z?.maxHR)
        // version 0 is never sent
        XCTAssertNil(BCLink.encodeProfileSet(BCLink.ProfileMessage(), seq: 1, tMs: 0))
        let ack = BCLink.decodeProfileAck(Data(bytes("73 00 02 00 00 00 00 00 01 04 01 00 00 00 02 01 00 03 04 01 00 00 00")))
        XCTAssertEqual(ack?.version, 1); XCTAssertEqual(ack?.applied, true); XCTAssertEqual(ack?.boardVersion, 1)
    }

    func testRiderProfileMapsToLinkMessageAndBack() {
        var r = RiderProfile(); r.name = "Rashed"; r.ftpW = 250; r.ftpHow = .entered; r.weightKg = 78; r.birthYear = 1990; r.maxHR = 186; r.restHR = 52
        r.hoursPerWeek = 6; r.level = .advanced; r.goal = .endurance; r.lthr = 170; r.version = 1; r.updatedAt = Date(timeIntervalSince1970: 1792850100)
        let m = r.linkMessage(units: .metric)
        XCTAssertEqual(m.version, 1); XCTAssertEqual(m.weightKgX10, 780); XCTAssertEqual(m.level, 2); XCTAssertEqual(m.goal, 1); XCTAssertEqual(m.ftpHow, 1)
        XCTAssertEqual(m.updatedEpochS, 1792850100)
        // goals the board cannot represent travel as "fitness" (0) and never crash the mapping
        r.goal = .stronger; XCTAssertEqual(r.linkMessage(units: .imperial).goal, 0); XCTAssertEqual(r.linkMessage(units: .imperial).units, 1)
        XCTAssertEqual(RiderProfile.Goal.from(linkCode: 3), .event); XCTAssertEqual(RiderProfile.Level.from(linkCode: 9), .advanced)
        // differences: only fields the board reports; identical → none
        var b = m; b.ftpW = 230; b.name = "Rashed"
        let diffs = r.differences(from: b, units: .metric)
        XCTAssertEqual(diffs.map { $0.field }, ["FTP", "Goal"])   // goal: phone .stronger shows as fitness vs board endurance
        r.goal = .endurance
        XCTAssertEqual(r.differences(from: m, units: .metric), [])
    }

    // MARK: device settings
    func testSettingsVectors() {
        XCTAssertEqual([UInt8](BCLink.encodeSettingsGet(seq: 3, tMs: 0)!), bytes("76 00 03 00 00 00 00 00"))
        var s = BCLink.SettingsMessage(); s.version = 1; s.brightnessPct = 55; s.screenTimeoutS = 120; s.wakeGesture = 1
        XCTAssertEqual([UInt8](BCLink.encodeSettingsSet(s, seq: 4, tMs: 0)!), bytes("74 00 04 00 00 00 00 00 01 04 01 00 00 00 02 01 37 03 02 78 00 04 01 01"))
        let reply = BCLink.decodeSettings(Data(bytes("75 00 05 00 00 00 00 00 01 04 02 00 00 00 02 01 50 03 02 3C 00 04 01 00 05 01 01 06 01 00 07 02 00 00 08 01 00 09 01 01 0A 01 00 0F 01 00 10 04 FF 03 00 00")))
        XCTAssertEqual(reply?.version, 2); XCTAssertEqual(reply?.brightnessPct, 80); XCTAssertEqual(reply?.screenTimeoutS, 60); XCTAssertEqual(reply?.wakeGesture, 0)
        XCTAssertEqual(reply?.phoneLinkEnabled, true); XCTAssertEqual(reply?.hrPref, 0); XCTAssertEqual(reply?.autoSleepMin, 0); XCTAssertEqual(reply?.rideLayout, 0)
        XCTAssertEqual(reply?.wakeOnCue, true); XCTAssertEqual(reply?.units, 0); XCTAssertEqual(reply?.status, 0); XCTAssertEqual(reply?.supportedMask, 0x3FF)
        XCTAssertEqual(reply?.statusText, "applied")
        // supported_mask gates the controls: 0.6.0 supports tags 1–10, nothing beyond
        XCTAssertTrue(reply!.supports(tag: 2)); XCTAssertTrue(reply!.supports(tag: 10)); XCTAssertFalse(reply!.supports(tag: 11))
        var none = BCLink.SettingsMessage(); none.version = 1
        XCTAssertNil(BCLink.encodeSettingsSet(BCLink.SettingsMessage(), seq: 1, tMs: 0))     /* version 0 refused */
        XCTAssertNotNil(BCLink.encodeSettingsSet(none, seq: 1, tMs: 0))
    }

    func testCapsGateEverything() {
        var i = BCLink.Info(); i.caps = 0x3F
        XCTAssertFalse(i.hasRideSync); XCTAssertFalse(i.hasWiFi); XCTAssertFalse(i.hasProfileSync); XCTAssertFalse(i.hasSettings)
        i.caps = 0x3FF
        XCTAssertTrue(i.hasRideSync && i.hasWiFi && i.hasProfileSync && i.hasSettings)
        // INFO with device id (tag 07) from a 0.6.0 board
        let d: [UInt8] = [0x01, 0, 1, 0, 0, 0, 0, 0, 0x01, 1, 1, 0x02, 1, 2, 0x03, 5, 0x30, 0x2E, 0x36, 0x2E, 0x30, 0x05, 4, 0xFF, 0x03, 0, 0, 0x07, 6, 0x8C, 0xFD, 0x49, 0x9B, 0xEF, 0x40]
        let info = BCLink.decodeInfo(Data(d))
        XCTAssertEqual(info?.fw, "0.6.0"); XCTAssertEqual(info?.deviceId, "8c:fd:49:9b:ef:40"); XCTAssertEqual(info?.verMinor, 2)
    }
}
