import Foundation

/// Offline-ride import into Cyclift's history (Link 1.3 ride queue). Thin adapter on the Store's existing public API:
/// it adds or completes ONE board RideRecord and reports success only when the store wrote it to disk. The coaching
/// logic in Models.swift is not changed; the summary merge (importBoardRide, SYNC_RIDE) keeps working as before and
/// keeps the samples set here.
extension Store {
    /// Saves the verified samples of board ride `m` in the history. `.stored(id)` only when the store file was written
    /// without error; the ride queue ACKs nothing otherwise.
    func importBoardQueueRide(_ m: BoardQueueRideMeta, samples data: Data) -> RideQueueTransfer.Delivery {
        let secs = BoardRideSamples.parse(data)
        let tot = BoardRideSamples.totals(secs)
        var samples: [RideRecord.Sample] = []
        samples.reserveCapacity(secs.count)
        var lastDist: Int? = nil
        for (t, s) in secs.enumerated() {
            var speed: Int? = nil
            if let d = s.distanceM, let p = lastDist, d >= p, d - p < 40 { speed = (d - p) * 100 }     /* m per second → cm/s; > 144 km/h = a glitch, not a speed */
            if let d = s.distanceM { lastDist = d }
            samples.append(RideRecord.Sample(t: t, w: s.power, cad: s.cadence, hr: s.hr, speedCms: s.paused ? nil : speed, lat: nil, lon: nil, alt: nil))
        }
        let rideId = Int(m.rideId)
        let start = m.startEpochS > 0 ? Date(timeIntervalSince1970: TimeInterval(m.startEpochS)) : Date(timeIntervalSince1970: 0)
        let id: UUID
        // 1. the same board ride already in the history (summary import, or the phone's live mirror of it)
        if let i = rides.firstIndex(where: { $0.recorder == .board && $0.boardRideId == rideId && ($0.boardId == m.boardId || $0.boardId == nil)
                                            && (m.startEpochS == 0 || !$0.dateKnown || abs($0.start.timeIntervalSince(start)) < 600) }) {
            var r = rides[i]
            r.boardId = m.boardId
            // the phone's mirror may hold GPS and its own trace: keep it; otherwise the board's seconds become the graph
            if r.samples.isEmpty { r.samples = samples }
            if r.avgPower == nil { r.avgPower = tot.avgPower; r.maxPower = tot.maxPower }
            if r.avgCadence == nil { r.avgCadence = tot.avgCadence }
            if r.avgHR == nil { r.avgHR = tot.avgHR; r.maxHR = tot.maxHR }
            if r.distanceM == 0 { r.distanceM = tot.distanceM }
            if r.durationS == 0 { r.durationS = m.durationS > 0 ? Int(m.durationS) : tot.movingS }
            if !r.sources.contains("BikeComputer") { r.sources.insert("BikeComputer", at: 0) }
            id = r.id
            rides[i] = r
        } else {
            // 2. a ride the phone never saw: summary values from the samples (the SYNC_RIDE summary refines them later)
            var r = RideRecord(start: start, durationS: m.durationS > 0 ? Int(m.durationS) : tot.movingS, distanceM: tot.distanceM, recorder: .board, sources: ["BikeComputer"])
            r.boardRideId = rideId; r.boardId = m.boardId
            r.avgPower = tot.avgPower; r.maxPower = tot.maxPower; r.avgCadence = tot.avgCadence; r.avgHR = tot.avgHR; r.maxHR = tot.maxHR; r.kj = tot.kj
            if tot.avgPower != nil { r.sources.append("Power meter") }
            if tot.avgHR != nil { r.sources.append("Heart rate") }
            r.powerVerified = PowerTrust.meterVerified
            r.samples = samples
            id = r.id
            let at = rides.firstIndex { $0.start < r.start } ?? rides.count
            rides.insert(r, at: at)
        }
        // durable = the store file was written (Store.persist is synchronous and atomic) and the ride is in it
        guard lastSaveError == nil, FileManager.default.fileExists(atPath: dir.appendingPathComponent("store.json").path), rides.contains(where: { $0.id == id }) else {
            return .failed(lastSaveError.map { "the history could not be saved (\($0))" } ?? "the history could not be saved")
        }
        return .stored(id)
    }
}
