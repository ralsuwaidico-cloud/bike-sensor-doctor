import Foundation

/// The ONE path for every message on the Sync characteristic (Link 1.1 SYNC_RIDE / SYNC_END), for every board:
/// the summary goes into Cyclift's history (Store.importBoardRide, unchanged rules), its CRC over the SYNC_RIDE fields
/// is kept for the ride-queue verification (`summary_crc32`, BLE_CONTRACT.md §6), and the caller learns which ride
/// arrived so a held RIDEQ ride can be ACKed at once (QA RC3-01).
enum BoardSummaryIngest {
    enum Result: Equatable { case ride(id: UInt32, crc: UInt32), end(BCLink.SyncEnd), none }
    @discardableResult
    static func ingest(_ d: Data, boardId: String, history: Store?, queueStore: BoardRideQueueStore) -> Result {
        if let r = BCLink.decodeSyncRide(d) {
            history?.importBoardRide(r, boardId: boardId)
            guard let crc = BoardRideQueueStore.summaryCrc(ofSyncRide: d), r.id >= 0 else { return .none }
            queueStore.saveSummaryCrc(boardId, UInt32(r.id), crc)
            return .ride(id: UInt32(r.id), crc: crc)
        }
        if let e = BCLink.decodeSyncEnd(d) { return .end(e) }
        return .none
    }
}

extension RideQueueTransfer {
    /// Link13Center's handler for every Sync message of THIS engine's board: history import + summary CRC, then the held
    /// ride is ACKed at once if it verifies, and the next by-id summary request goes out (QA RC3-01).
    @discardableResult
    func handleSync(_ d: Data, history: Store?, now: Date) -> BoardSummaryIngest.Result {
        let r = BoardSummaryIngest.ingest(d, boardId: boardId, history: history, queueStore: store)
        switch r {
        case .ride(let id, _): summaryArrived(rideId: id, now: now)
        case .end: syncEnded(now: now)
        case .none: break
        }
        return r
    }
}
