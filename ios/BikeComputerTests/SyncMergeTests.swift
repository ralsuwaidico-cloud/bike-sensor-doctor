import XCTest
@testable import BikeComputer

/// Cloud sync merge rules (pure functions, no network). Fixtures stand in for the ledger and the server rows.
final class SyncMergeTests: XCTestCase {
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    func testUnknownLocallyTakesRemote() {
        XCTAssertEqual(MergeRules.decide(localHash: nil, local: nil, remoteHash: "r", remoteClientUpdatedAt: t0, remoteDeleted: false), .takeRemote)
        XCTAssertEqual(MergeRules.decide(localHash: nil, local: nil, remoteHash: "r", remoteClientUpdatedAt: t0, remoteDeleted: true), .nothing)
    }

    func testSameHashNeedsNothing() {
        let e = LedgerEntry(hash: "a", changedAt: t0, syncedAt: t0)
        XCTAssertEqual(MergeRules.decide(localHash: "a", local: e, remoteHash: "a", remoteClientUpdatedAt: t0, remoteDeleted: false), .nothing)
    }

    func testOnlyServerMovedTakesRemote() {
        let e = LedgerEntry(hash: "a", changedAt: t0, syncedAt: t0)       // local unchanged since last sync
        XCTAssertEqual(MergeRules.decide(localHash: "a", local: e, remoteHash: "b", remoteClientUpdatedAt: t0.addingTimeInterval(60), remoteDeleted: false), .takeRemote)
    }

    func testBothMovedNewerClientWins() {
        let e = LedgerEntry(hash: "a", changedAt: t0.addingTimeInterval(120), syncedAt: t0)   // local changed at +120
        XCTAssertEqual(MergeRules.decide(localHash: "c", local: e, remoteHash: "b", remoteClientUpdatedAt: t0.addingTimeInterval(60), remoteDeleted: false), .pushLocal)
        XCTAssertEqual(MergeRules.decide(localHash: "c", local: e, remoteHash: "b", remoteClientUpdatedAt: t0.addingTimeInterval(600), remoteDeleted: false), .takeRemote)
    }

    func testRemoteDeletionHonouredUnlessEditedAfter() {
        let unchanged = LedgerEntry(hash: "a", changedAt: t0, syncedAt: t0)
        XCTAssertEqual(MergeRules.decide(localHash: "a", local: unchanged, remoteHash: "", remoteClientUpdatedAt: t0.addingTimeInterval(60), remoteDeleted: true), .deleteLocal)
        let editedLater = LedgerEntry(hash: "a", changedAt: t0.addingTimeInterval(120), syncedAt: t0)
        XCTAssertEqual(MergeRules.decide(localHash: "c", local: editedLater, remoteHash: "", remoteClientUpdatedAt: t0.addingTimeInterval(60), remoteDeleted: true), .pushLocal)
        XCTAssertEqual(MergeRules.decide(localHash: "c", local: editedLater, remoteHash: "", remoteClientUpdatedAt: t0.addingTimeInterval(600), remoteDeleted: true), .deleteLocal)
    }

    func testRideDedupeBySourceIdAndByTime() {
        var a = RideRecord(start: t0, durationS: 3600, distanceM: 25_000, recorder: .board, sources: ["BikeComputer"]); a.boardId = "b1"; a.boardRideId = 7
        var b = RideRecord(start: t0.addingTimeInterval(400), durationS: 3620, distanceM: 24_900, recorder: .board, sources: ["BikeComputer"]); b.boardId = "b1"; b.boardRideId = 7
        XCTAssertTrue(MergeRules.isDuplicateRide(b, in: [a]), "same board ride id even with a different start")
        let c = RideRecord(start: t0.addingTimeInterval(60), durationS: 3630, distanceM: 25_100, recorder: .phone, sources: ["Phone GPS"])
        XCTAssertTrue(MergeRules.isDuplicateRide(c, in: [a]), "same start within 2 min and similar duration")
        let d = RideRecord(start: t0.addingTimeInterval(7200), durationS: 1800, distanceM: 12_000, recorder: .phone, sources: ["Phone GPS"])
        XCTAssertFalse(MergeRules.isDuplicateRide(d, in: [a]))
    }

    func testStrengthDedupe() {
        let s = StrengthSession(date: t0, minutes: 40, focus: .upper, rpe: 7)
        var same = s; same.id = UUID()                                        // another device's copy of the same log
        XCTAssertTrue(MergeRules.isDuplicateStrength(same, in: [s]))
        let other = StrengthSession(date: t0.addingTimeInterval(86_400), minutes: 40, focus: .upper, rpe: 7)
        XCTAssertFalse(MergeRules.isDuplicateStrength(other, in: [s]))
    }

    func testIsoDatesFromPostgres() {
        XCTAssertNotNil(ISO.date("2026-10-26T01:02:03.123456+00:00"))
        XCTAssertNotNil(ISO.date("2026-10-26T01:02:03+00:00"))
        XCTAssertNotNil(ISO.date("2026-10-26 01:02:03.5+00:00"))
        let d = ISO.date(ISO.string(t0)); XCTAssertEqual(d!.timeIntervalSince1970, t0.timeIntervalSince1970, accuracy: 0.001)
    }

    func testPayloadRoundTripKeepsJSON() throws {
        let r = RideRecord(start: t0, durationS: 600, distanceM: 3000, recorder: .phone, sources: ["Phone GPS"])
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601; enc.outputFormatting = [.sortedKeys]
        let data = try enc.encode(r)
        let row = CloudRow(id: r.id.uuidString, user_id: "u", source_id: nil, started_at: ISO.string(t0), day: nil, payload: AnyCodableJSON(data: data), client_updated_at: ISO.string(t0), updated_at: nil, deleted_at: nil)
        let wire = try JSONEncoder().encode([row])
        let back = try JSONDecoder().decode([CloudRow].self, from: wire)
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        let r2 = try dec.decode(RideRecord.self, from: back[0].payload.data)
        XCTAssertEqual(r2, r)
    }

    func testCloudConfigAbsentMeansGuestOnly() {
        // The test bundle carries no Supabase values: accounts must read as not configured and nothing may be attempted.
        XCTAssertFalse(CloudConfig.isConfigured)
        XCTAssertFalse(CloudConfig.googleEnabled)
    }
    // MARK: Cyclift 1.0 audit fixes

    func testUnconfirmedLocalEditCountsAsLocalChange() {
        // The engine records a moved hash as (new hash, syncedAt nil) BEFORE pulling: that must still count as a local
        // change, otherwise a newer edit on this phone always lost to an older server row.
        let e = LedgerEntry(hash: "c", changedAt: t0.addingTimeInterval(120), syncedAt: nil)
        XCTAssertEqual(MergeRules.decide(localHash: "c", local: e, remoteHash: "b", remoteClientUpdatedAt: t0.addingTimeInterval(60), remoteDeleted: false), .pushLocal)
        XCTAssertEqual(MergeRules.decide(localHash: "c", local: e, remoteHash: "b", remoteClientUpdatedAt: t0.addingTimeInterval(600), remoteDeleted: false), .takeRemote)
        XCTAssertEqual(MergeRules.decide(localHash: "c", local: e, remoteHash: "", remoteClientUpdatedAt: t0.addingTimeInterval(60), remoteDeleted: true), .pushLocal, "edited here after the deletion elsewhere")
        XCTAssertEqual(MergeRules.decide(localHash: "c", local: e, remoteHash: "", remoteClientUpdatedAt: t0.addingTimeInterval(600), remoteDeleted: true), .deleteLocal)
    }

    func testSecondPhoneTakesTheAccountProfileInsteadOfItsDefaults() {
        let now = t0.addingTimeInterval(9_999)
        XCTAssertEqual(MergeRules.firstSeenChangedAt(table: "profiles", now: now), MergeRules.neverChanged)
        XCTAssertEqual(MergeRules.firstSeenChangedAt(table: "settings", now: now), MergeRules.neverChanged)
        XCTAssertEqual(MergeRules.firstSeenChangedAt(table: "rides", now: now), now)
        let firstSeen = LedgerEntry(hash: "defaults", changedAt: MergeRules.firstSeenChangedAt(table: "profiles", now: now), syncedAt: nil)
        XCTAssertEqual(MergeRules.decide(localHash: "defaults", local: firstSeen, remoteHash: "account", remoteClientUpdatedAt: t0, remoteDeleted: false), .takeRemote)
        // a new local ride on first sync is still pushed when the server has an older copy with the same id
        let ride = LedgerEntry(hash: "r", changedAt: MergeRules.firstSeenChangedAt(table: "rides", now: now), syncedAt: nil)
        XCTAssertEqual(MergeRules.decide(localHash: "r", local: ride, remoteHash: "s", remoteClientUpdatedAt: t0, remoteDeleted: false), .pushLocal)
    }

    func testTombstonesOnlyForRecordsThisPhoneSyncedAndNoLongerHas() {
        let ledger = ["a": LedgerEntry(hash: "1", changedAt: t0, syncedAt: t0),      // synced, deleted here → tombstone
                      "b": LedgerEntry(hash: "2", changedAt: t0, syncedAt: t0),      // synced, still here
                      "c": LedgerEntry(hash: "3", changedAt: t0, syncedAt: nil)]     // never confirmed → no tombstone
        XCTAssertEqual(MergeRules.tombstoneIds(ledger: ledger, localIds: ["b"]), ["a"])
        XCTAssertEqual(MergeRules.tombstoneIds(ledger: [:], localIds: ["x"]), [])
    }

    func testUpsertsAreBatched() {
        XCTAssertEqual(MergeRules.batches(Array(0..<120)).map(\.count), [50, 50, 20])
        XCTAssertEqual(MergeRules.batches(Array(0..<50)).map(\.count), [50])
        XCTAssertTrue(MergeRules.batches([Int]()).isEmpty)
        XCTAssertEqual(MergeRules.batches(Array(0..<5), size: 2).flatMap { $0 }, Array(0..<5))
    }
}
