import XCTest
@testable import BikeComputer

/// Settings › BikeComputer › Storage: the health category is the board's own, and "safe cleanup" never touches
/// unsynced rides or unsent crash evidence and never runs on a damaged filesystem.
final class BoardStorageModelTests: XCTestCase {
    private func status(_ st: BCLink.StorageState, health: UInt8? = nil) -> BCLink.StorageStatus {
        var s = BCLink.StorageStatus(); s.stateRaw = st.rawValue; s.healthRaw = health; s.fsTotalKB = 3072; s.fsFreeKB = 1024; return s
    }

    func testHealthCategoryIsTheBoardsOwn() {
        XCTAssertEqual(BoardStorageModel.category(status(.dirCorrupted), liveState: nil), "Directory corrupted")
        XCTAssertEqual(BoardStorageModel.category(nil, liveState: 2), "Filesystem unavailable", "LIVE storage_state until the status arrives")
        XCTAssertEqual(BoardStorageModel.category(nil, liveState: nil), "Not reported")
        XCTAssertEqual(BoardStorageModel.health(status(.dirCorrupted)), .failed)
        XCTAssertEqual(BoardStorageModel.health(status(.ok)), .good)
        XCTAssertEqual(BoardStorageModel.health(status(.full)), .degraded)
        XCTAssertEqual(BoardStorageModel.health(status(.ok, health: 1)), .degraded, "the board's health byte wins")
        XCTAssertEqual(BoardStorageModel.health(nil), .unknown)
        XCTAssertEqual(BoardStorageModel.usedFraction(status(.ok)) ?? -1, 2.0 / 3.0, accuracy: 0.0001)
        XCTAssertEqual(BoardStorageModel.kb(2048), "2.0 MB"); XCTAssertEqual(BoardStorageModel.kb(nil), "—")
        XCTAssertEqual(BoardStorageModel.crashPartitionText(0), "missing")
    }

    func testSafeCleanup() {
        let ok = BoardStorageModel.cleanup(status: status(.ok), linkEnabled: true, boardRecording: false, unsentReports: 1, unsyncedRides: 2)
        XCTAssertTrue(ok.allowed); XCTAssertEqual(ok.what, [.ackedReports, .syncedRideSamples, .caches])
        XCTAssertTrue(ok.keeps.contains { $0.contains("Rides not yet saved in Cyclift (2") })
        XCTAssertTrue(ok.keeps.contains { $0.contains("Crash reports not yet received by this iPhone (1)") })
        XCTAssertTrue(BoardStorageModel.cleanup(status: status(.full), linkEnabled: true, boardRecording: false, unsentReports: 0, unsyncedRides: 0).allowed, "a full board is exactly when cleanup helps")
        for bad in [BCLink.StorageState.dirCorrupted, .fsUnavailable, .writeFailed, .diagUnavailable, .notChecked] {
            let c = BoardStorageModel.cleanup(status: status(bad), linkEnabled: true, boardRecording: false, unsentReports: 0, unsyncedRides: 0)
            XCTAssertFalse(c.allowed, "\(bad)"); XCTAssertEqual(c.what, [])
        }
        XCTAssertTrue(BoardStorageModel.cleanup(status: status(.dirCorrupted), linkEnabled: true, boardRecording: false, unsentReports: 0, unsyncedRides: 0).blockedReason!.contains("never repaired over Bluetooth"))
        XCTAssertFalse(BoardStorageModel.cleanup(status: status(.ok), linkEnabled: true, boardRecording: true, unsentReports: 0, unsyncedRides: 0).allowed)
        XCTAssertFalse(BoardStorageModel.cleanup(status: status(.ok), linkEnabled: false, boardRecording: false, unsentReports: 0, unsyncedRides: 0).allowed, "0.7.3 board: no storage commands")
        XCTAssertFalse(BoardStorageModel.cleanup(status: nil, linkEnabled: true, boardRecording: false, unsentReports: 0, unsyncedRides: 0).allowed)
    }
}
