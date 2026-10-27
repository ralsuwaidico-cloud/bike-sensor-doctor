import Foundation

/// Link 1.3 offline ride import (BLE_CONTRACT.md §6), phone side. Pure and synchronous like DiagTransfer: the caller
/// feeds board messages, link events and the clock; it answers through `send`.
///
/// Flow: RIDEQ_LIST_REQ → RIDEQ_INFO… RIDEQ_LIST_END → for each ride the board still holds as unsynced (state 1/2,
/// oldest first): RIDEQ_CHUNK_REQ at the resume offset → chunks appended to disk → size + CRC-32 of the stored file →
/// `deliver` saves it in Cyclift's history → RIDEQ_ACK only when the ride is durably stored AND the summary the phone
/// received matches the board's `summary_crc32`. The board deletes nothing before that ACK; this engine never asks it
/// to delete a ride that is not verified here. A ride already saved here (same id, same CRC) is never pulled again.
final class RideQueueTransfer {
    struct Config {
        var timeout: TimeInterval = 5
        var maxTimeoutRetries = 3
        var maxCrcRetries = 3
        var maxReadErrorRetries = 3
        var readErrorDelay: TimeInterval = 2
        var busyDelay: TimeInterval = 10
        var boardRideRecheck: TimeInterval = 10
        /// RIDEQ_ACK `04 delete_samples`: the samples are on this phone, so the board may free them.
        var deleteSamplesOnAck = true
    }
    enum Phase: Equatable { case idle, listing, pulling(UInt32) }
    struct Progress: Equatable { var rideId: UInt32; var received: UInt32; var size: UInt32 }
    /// Result of handing a verified ride to Cyclift's history.
    enum Delivery: Equatable { case stored(UUID), failed(String) }
    /// Why a ride is still on the board (shown on the Storage page).
    enum Hold: Equatable { case demo, recording, summaryNotVerified, conflict, failed(String) }

    let boardId: String
    let store: BoardRideQueueStore
    var config: Config
    var send: (Data) -> Bool
    /// Saves the verified samples in Cyclift's history (must return only after the save is on disk).
    var deliver: (BoardQueueRideMeta, Data) -> Delivery = { _, _ in .failed("not connected to the history") }
    /// CRC-32 the phone computed over the summary it received for this ride (SYNC_RIDE fields), nil = none received.
    var summaryCrc: (UInt32) -> UInt32? = { _ in nil }
    /// Asks the board for ride summaries (Link 1.1 SYNC) when one is missing; the center calls `summariesArrived` after.
    var requestSummaries: () -> Void = {}
    var boardRecording: () -> Bool = { false }
    var linkPayload: () -> Int? = { nil }
    var onChange: (() -> Void)?

    private(set) var phase: Phase = .idle { didSet { if phase != oldValue { onChange?() } } }
    private(set) var progress: Progress? { didSet { if progress != oldValue { onChange?() } } }
    private(set) var lastError: String? { didSet { if lastError != oldValue { onChange?() } } }
    private(set) var boardList: [BCLink.RideQueueInfo] = []
    private(set) var lastListEnd: BCLink.RideQueueListEnd?
    private(set) var holds: [UInt32: Hold] = [:]

    private var listed: [BCLink.RideQueueInfo] = []
    private var queue: [BCLink.RideQueueInfo] = []
    private var current: BCLink.RideQueueInfo?
    private var offset: UInt32 = 0
    private var outstanding: (list: Bool, sentAt: Date)?
    private var scheduled: (list: Bool, at: Date)?
    private var timeouts = 0, readErrors = 0
    private var crcFailures: [UInt32: Int] = [:]
    private var relist = false
    private var summariesRequested = false
    private var seq: UInt16 = 0

    init(boardId: String, store: BoardRideQueueStore, config: Config = Config(), send: @escaping (Data) -> Bool) {
        self.boardId = boardId; self.store = store; self.config = config; self.send = send
    }
    var isBusy: Bool { phase != .idle }
    var chunkLen: UInt16? { guard let p = linkPayload() else { return UInt16(BCLink.diagChunkDataMax) }; return BCLink.diagRequestMaxLen(linkPayload: p) }

    // MARK: triggers
    func start(now: Date) { if phase == .idle { lastError = nil; requestList(now: now) } else { relist = true } }
    func ridesPending(_ r: BCLink.RidesPending, now: Date) { if r.unsynced > 0 { start(now: now) } }
    /// SYNC_END arrived after `requestSummaries`: rides held for a missing summary are checked again.
    func summariesArrived(now: Date) {
        guard phase == .idle else { return }
        if holds.values.contains(.summaryNotVerified) { holds = holds.filter { $0.value != .summaryNotVerified }; requestList(now: now) }
    }
    func linkDown() {
        phase = .idle; progress = nil; current = nil; queue = []; listed = []
        outstanding = nil; scheduled = nil; relist = false; timeouts = 0; readErrors = 0; summariesRequested = false
    }

    // MARK: input
    func receive(_ d: Data, now: Date) {
        guard let t = d.first else { return }
        switch BCLink.MsgType(rawValue: t) {
        case .rideqInfo: if let i = BCLink.decodeRideQueueInfo(d) { gotInfo(i) }
        case .rideqListEnd: if let e = BCLink.decodeRideQueueListEnd(d) { lastListEnd = e; gotListEnd(now: now) }
        case .rideqChunk: if let c = BCLink.decodeRideQueueChunk(d) { gotChunk(c, now: now) }
        case .rideqErr: if let e = BCLink.decodeRideQueueErr(d) { gotErr(e, now: now) }
        case .event: if let r = BCLink.decodeRidesPending(d) { ridesPending(r, now: now) }
        default: break
        }
    }
    func tick(now: Date) {
        if let o = outstanding, now.timeIntervalSince(o.sentAt) >= config.timeout {
            outstanding = nil; timeouts += 1
            if timeouts > config.maxTimeoutRetries {
                lastError = o.list ? "The BikeComputer did not answer the ride list." : "The BikeComputer stopped sending the ride — it resumes on the next connection."
                pause(); return
            }
            issue(list: o.list, now: now); return
        }
        if let s = scheduled, now >= s.at { scheduled = nil; issue(list: s.list, now: now) }
    }

    // MARK: listing
    private func requestList(now: Date) { phase = .listing; listed = []; timeouts = 0; readErrors = 0; issue(list: true, now: now) }
    private func gotInfo(_ i: BCLink.RideQueueInfo) {
        if let k = boardList.firstIndex(where: { $0.rideId == i.rideId }) { boardList[k] = i } else { boardList.append(i) }
        // the board answers RIDEQ_ACK with RIDEQ_INFO in the new state: remember the confirmation
        if let s = i.state, s == .verifiedOnPhone || s == .samplesDeleted, var m = store.meta(boardId, i.rideId), m.samplesCrc32 == i.samplesCrc32, m.boardConfirmedState != i.stateRaw {
            m.boardConfirmedState = i.stateRaw; store.save(m); onChange?()
        }
        if phase == .listing { if let k = listed.firstIndex(where: { $0.rideId == i.rideId }) { listed[k] = i } else { listed.append(i) } }
    }
    private func gotListEnd(now: Date) {
        guard phase == .listing else { return }
        outstanding = nil; timeouts = 0; queue = []
        for i in listed.sorted(by: { $0.rideId < $1.rideId }) {
            if i.state == .recording { holds[i.rideId] = .recording; continue }
            guard i.needsImport else { holds[i.rideId] = nil; continue }
            if i.demo { holds[i.rideId] = .demo; continue }               /* demo rides are not training history: never imported, never ACKed */
            if let m = store.meta(boardId, i.rideId) {
                if m.samplesCrc32 != i.samplesCrc32 || m.samplesSize != i.samplesSize { holds[i.rideId] = .conflict; continue }   /* same number, other data: keep both, ACK nothing */
                if m.historyRideId == nil { retryDelivery(m) } else { ackIfVerified(i, m) }
            } else if (crcFailures[i.rideId] ?? 0) <= config.maxCrcRetries {
                queue.append(i)
            }
        }
        next(now: now)
    }

    // MARK: pulling
    private func next(now: Date) {
        current = nil; progress = nil; readErrors = 0
        guard !queue.isEmpty else {
            phase = .idle
            if relist { relist = false; requestList(now: now) }
            return
        }
        let i = queue.removeFirst()
        current = i; phase = .pulling(i.rideId)
        offset = store.preparePartial(boardId, i)
        progress = Progress(rideId: i.rideId, received: offset, size: i.samplesSize)
        if offset >= i.samplesSize { finish(now: now) } else { issue(list: false, now: now) }
    }
    private func gotChunk(_ c: BCLink.RideQueueChunk, now: Date) {
        guard case .pulling(let id) = phase, let i = current, c.rideId == id, c.offset == offset else { return }
        outstanding = nil; scheduled = nil; timeouts = 0
        let len = UInt32(c.data.count)
        if (len == 0 && !c.last) || UInt64(offset) + UInt64(len) > UInt64(i.samplesSize) { restart(i, now: now, reason: "the board sent more data than the ride size"); return }
        if len > 0 {
            guard store.appendPartial(boardId, id, c.data) else { lastError = "Could not save the ride on this iPhone (storage full?). It stays on the BikeComputer."; pause(); return }
            offset += len
            progress = Progress(rideId: id, received: offset, size: i.samplesSize)
        }
        if offset >= i.samplesSize { finish(now: now) }
        else if c.last { restart(i, now: now, reason: "the board ended the ride early") }
        else { issue(list: false, now: now) }
    }
    private func finish(now: Date) {
        guard let i = current else { return }
        let data = store.partialData(boardId, i.rideId) ?? (i.samplesSize == 0 ? Data() : nil)
        guard let data, data.count == Int(i.samplesSize), CRC32.ieee(data) == i.samplesCrc32 else { restart(i, now: now, reason: "checksum mismatch"); return }
        guard let m = store.commit(boardId, i, receivedAt: now) else { lastError = "Could not save ride \(i.rideId) on this iPhone; it stays on the BikeComputer."; next(now: now); return }
        retryDelivery(m)
        next(now: now)
    }
    /// Samples are on disk: put the ride in Cyclift's history, then ACK when the summary is verified too.
    private func retryDelivery(_ m0: BoardQueueRideMeta) {
        var m = m0
        guard let data = store.samples(m), data.count == Int(m.samplesSize), CRC32.ieee(data) == m.samplesCrc32 else { holds[m.rideId] = .failed("stored file unreadable"); return }
        switch deliver(m, data) {
        case .stored(let rid):
            m.historyRideId = rid
            guard store.save(m) else { holds[m.rideId] = .failed("could not save the ride record"); return }
            if let i = boardList.first(where: { $0.rideId == m.rideId }) { ackIfVerified(i, m) }
        case .failed(let why): holds[m.rideId] = .failed(why); lastError = "Ride \(m.rideId) is kept on the BikeComputer: \(why)."
        }
    }
    private func ackIfVerified(_ i: BCLink.RideQueueInfo, _ m0: BoardQueueRideMeta) {
        var m = m0
        guard m.historyRideId != nil else { return }
        guard let s = summaryCrc(i.rideId), s == i.summaryCrc32 else {
            holds[i.rideId] = .summaryNotVerified
            if !summariesRequested { summariesRequested = true; requestSummaries() }
            return
        }
        holds[i.rideId] = nil
        if let d = BCLink.encodeRideQueueAck(rideId: i.rideId, samplesCrc32: m.samplesCrc32, summaryCrc32: s, deleteSamples: config.deleteSamplesOnAck, seq: nextSeq(), tMs: 0), send(d) {
            m.acked = true; store.save(m); onChange?()
        }
    }
    private func restart(_ i: BCLink.RideQueueInfo, now: Date, reason: String) {
        store.deletePartial(boardId, i.rideId)
        let n = (crcFailures[i.rideId] ?? 0) + 1; crcFailures[i.rideId] = n
        if n > config.maxCrcRetries { lastError = "Ride \(i.rideId) could not be received intact (\(reason)); it stays on the BikeComputer."; holds[i.rideId] = .failed(reason); next(now: now); return }
        offset = store.preparePartial(boardId, i)
        progress = Progress(rideId: i.rideId, received: offset, size: i.samplesSize)
        issue(list: false, now: now)
    }
    private func gotErr(_ e: BCLink.RideQueueErr, now: Date) {
        if phase == .listing {
            outstanding = nil
            if e.known != .busy { readErrors += 1; if readErrors > config.maxReadErrorRetries { lastError = "The BikeComputer could not list its rides (\(e.text))."; pause(); return } }
            scheduled = (true, now.addingTimeInterval(e.known == .busy ? config.busyDelay : config.readErrorDelay)); return
        }
        guard case .pulling(let id) = phase, let i = current, e.reportId == id || e.reportId == 0 else { return }
        outstanding = nil
        switch e.known {
        case .unknownId: store.deletePartial(boardId, id); next(now: now)
        case .badOffset: restart(i, now: now, reason: "bad offset")
        case .busy: scheduled = (false, now.addingTimeInterval(config.busyDelay))       /* a ride is recording on the board */
        case .linkTooSmall: lastError = "The Bluetooth link is too small to transfer rides; they stay on the BikeComputer."; pause()
        case .storageReadError, nil:
            readErrors += 1
            if readErrors > config.maxReadErrorRetries { lastError = "The BikeComputer could not read ride \(id) (\(e.text)); it is kept there."; holds[id] = .failed(e.text); next(now: now) }
            else { scheduled = (false, now.addingTimeInterval(config.readErrorDelay)) }
        }
    }

    // MARK: output
    private func issue(list: Bool, now: Date) {
        if list { outstanding = (true, now); _ = send(BCLink.encodeRideQueueListRequest(seq: nextSeq(), tMs: 0) ?? Data()); return }
        guard let i = current else { return }
        if boardRecording() { scheduled = (false, now.addingTimeInterval(config.boardRideRecheck)); return }
        guard let maxLen = chunkLen else { lastError = "The Bluetooth link is too small to transfer rides; they stay on the BikeComputer."; pause(); return }
        outstanding = (false, now)
        _ = send(BCLink.encodeRideQueueChunkRequest(rideId: i.rideId, offset: offset, maxLen: maxLen, seq: nextSeq(), tMs: 0) ?? Data())
    }
    private func pause() { phase = .idle; progress = nil; current = nil; queue = []; outstanding = nil; scheduled = nil; relist = false }
    private func nextSeq() -> UInt16 { seq &+= 1; return seq }

    /// Rides the board holds that are not yet confirmed as saved in Cyclift.
    var unsyncedOnBoard: [BCLink.RideQueueInfo] { boardList.filter { $0.needsImport || $0.state == .recording } }
}
