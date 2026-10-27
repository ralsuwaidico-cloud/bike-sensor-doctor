import XCTest
import CoreBluetooth
@testable import BikeComputer

/// 0.8.0 — connection stages and failure reasons, the Repair rule, LINK_DIAG decoding (firmware vector), phone-side
/// profile validation that mirrors the board's 1.2.1 ranges, persisted sync status.
final class PairingTests: XCTestCase {

    func testStagesAreOrderedAsTheBriefLists() {
        let order: [DeviceLink.Stage] = [.searching, .found, .connecting, .pairing, .authenticating, .connected, .syncingProfile, .ready]
        for (a, b) in zip(order, order.dropFirst()) { XCTAssertLessThan(a.order, b.order, "\(a) before \(b)") }
        XCTAssertTrue(DeviceLink.Stage.pairing.isAttempt); XCTAssertFalse(DeviceLink.Stage.ready.isAttempt); XCTAssertFalse(DeviceLink.Stage.failed.isAttempt)
        XCTAssertEqual(DeviceLink.stageTimeout, 20, "no stage may sit indefinitely")
    }

    func testStaleKeysMapToRepair() {
        let gone = NSError(domain: CBErrorDomain, code: CBError.Code.peerRemovedPairingInformation.rawValue)
        let d = DeviceLink.describe(gone)
        XCTAssertEqual(d.action, .repair)
        XCTAssertTrue(d.reason.contains("no longer has this phone's keys"), d.reason)
        XCTAssertTrue(d.code.hasPrefix(CBErrorDomain))
        // ATT insufficient authentication / encryption → repair as well (the secure read was refused)
        for code in [5, 15, 8] { XCTAssertEqual(DeviceLink.describe(NSError(domain: CBATTErrorDomain, code: code)).action, .repair, "ATT \(code)") }
        // out of range / timeout → retry, not repair
        XCTAssertEqual(DeviceLink.describe(NSError(domain: CBErrorDomain, code: CBError.Code.connectionTimeout.rawValue)).action, .retry)
        XCTAssertEqual(DeviceLink.describe(NSError(domain: CBErrorDomain, code: CBError.Code.peripheralDisconnected.rawValue)).action, .retry)
        // an unknown error keeps iOS's own words and suggests a retry
        let other = NSError(domain: "x", code: 42, userInfo: [NSLocalizedDescriptionKey: "something odd"])
        XCTAssertEqual(DeviceLink.describe(other).reason, "something odd"); XCTAssertEqual(DeviceLink.describe(other).action, .retry)
    }

    func testLinkDiagVectorFromFirmware() {
        // BLE_LINK_PROTOCOL.md 1.2.1: seq 3, t 500, reason 3 (timeout / out of range), 1 bond, sync state 1 (synced)
        let bytes: [UInt8] = [0x40, 0x00, 0x03, 0x00, 0xF4, 0x01, 0x00, 0x00, 0x01, 0x01, 0x20, 0x02, 0x01, 0x03, 0x03, 0x02, 0x01, 0x00, 0x04, 0x01, 0x01]
        let e = BCLink.decodeEvent(Data(bytes))
        XCTAssertNotNil(e); XCTAssertTrue(e!.isLinkDiag)
        let d = BCLink.linkDiag(from: e!)
        XCTAssertEqual(d?.reason, 3); XCTAssertEqual(d?.bonds, 1); XCTAssertEqual(d?.syncState, 1)
        XCTAssertEqual(d?.reasonText, "timeout / out of range"); XCTAssertEqual(d?.syncText, "synced")
        // the battery notice vector (0.6.0) still decodes and is NOT a link diag
        let bat: [UInt8] = [0x40, 0x00, 0x07, 0x00, 0x40, 0xE2, 0x01, 0x00, 0x01, 0x01, 0x10, 0x02, 0x01, 0x51, 0x03, 0x02, 0x96, 0x0F, 0x04, 0x01, 0x01]
        let b = BCLink.decodeEvent(Data(bat))
        XCTAssertEqual(b?.isBatteryNotice, true); XCTAssertNil(BCLink.linkDiag(from: b!)); XCTAssertEqual(b?.b2, 81); XCTAssertEqual(b?.w3, 3990)
        // not an event / truncated → nil
        XCTAssertNil(BCLink.decodeEvent(Data([0x72, 0, 0, 0, 0, 0, 0, 0])))
        XCTAssertNil(BCLink.decodeEvent(Data(bytes.dropLast(2))))
        XCTAssertEqual(BCLink.eventsUUID, "B1CE0007-7E3A-4C55-9D2B-5A0E1C7C0000")
    }

    func testProfileValidationMirrorsTheBoardRanges() {
        var p = RiderProfile(); p.name = "Rider A"; p.ftpW = 210; p.weightKg = 82; p.birthYear = 1988; p.maxHR = 185; p.restHR = 52; p.lthr = 165; p.hoursPerWeek = 6
        XCTAssertTrue(p.linkValidationIssues().isEmpty)
        p.ftpW = 999; XCTAssertEqual(p.linkValidationIssues(), ["FTP must be 50–600 W"])
        p.ftpW = 210; p.restHR = 190; XCTAssertTrue(p.linkValidationIssues().contains("Resting heart rate must be below max heart rate"))
        p.restHR = 52; p.weightKg = 20; XCTAssertEqual(p.linkValidationIssues().first, "Weight must be 30–200 kg")
        p.weightKg = 82; p.name = ""; XCTAssertEqual(p.linkValidationIssues().first, "Name must be 1–24 characters")
        p.name = String(repeating: "x", count: 25); XCTAssertEqual(p.linkValidationIssues().count, 1)
        p.name = "Rider A"; p.hoursPerWeek = 41; XCTAssertEqual(p.linkValidationIssues(), ["Hours per week must be 40 or fewer"])
    }

    func testSyncRecordPersistsLastSuccessfulSync() {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let s1 = Store(directory: dir, generatePlan: false)
        var r = s1.syncRecord(for: "02:00:00:c1:f7:01"); r.confirmed = true; r.ackedVersion = 7; r.ackedAt = Date(timeIntervalSince1970: 1_793_000_000); s1.setSyncRecord(r)
        let s2 = Store(directory: dir, generatePlan: false)
        let back = s2.syncRecord(for: "02:00:00:c1:f7:01")
        XCTAssertTrue(back.confirmed); XCTAssertEqual(back.ackedVersion, 7); XCTAssertEqual(back.ackedAt, Date(timeIntervalSince1970: 1_793_000_000))
        XCTAssertFalse(s2.syncRecord(for: "other").confirmed, "a different board (new id) starts unconfirmed")
        try? FileManager.default.removeItem(at: dir)
    }

    func testProfileSyncStateWords() {
        XCTAssertEqual(ProfileSync.State.inSync.word, "synced")
        XCTAssertEqual(ProfileSync.State.failed("x").word, "failed"); XCTAssertTrue(ProfileSync.State.failed("x").isFailed)
        XCTAssertEqual(ProfileSync.State.pushing(3).word, "pending"); XCTAssertEqual(ProfileSync.State.needsConfirmation.word, "pending"); XCTAssertEqual(ProfileSync.State.waitingForBoard.word, "pending")
        XCTAssertEqual(ProfileSync.State.noBoard.word, "—")
        XCTAssertFalse(ProfileSync.State.inSync.isFailed)
    }

    func testBoardRowIsRedWhenPairingIsLost() {
        XCTAssertEqual(ConnectionRules.board(linkState: .idle, liveFresh: false, remembered: true, autoConnect: true, phoneOnlyMode: false, pairingLost: true), .red)
        XCTAssertEqual(ConnectionRules.board(linkState: .connecting, liveFresh: false, remembered: true, autoConnect: true, phoneOnlyMode: false, pairingLost: true), .red)
        XCTAssertEqual(ConnectionRules.board(linkState: .idle, liveFresh: false, remembered: true, autoConnect: false, phoneOnlyMode: false, pairingLost: true), .gray, "link switched off by the rider stays gray")
        XCTAssertEqual(ConnectionRules.board(linkState: .ready, liveFresh: true, remembered: true, autoConnect: true, phoneOnlyMode: false, pairingLost: false), .green)
    }
}
