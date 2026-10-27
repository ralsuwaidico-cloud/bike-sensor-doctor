import Foundation

/// Link 1.2.3 diagnostic report pull (ios/DIAG_TRANSFER.md). Pure and synchronous: the caller feeds it board messages
/// (`receive`), link events (`start`, `linkDown`) and the clock (`tick`); it answers through `send`. No timers, no
/// CoreBluetooth, so every path is unit-tested with a fake board.
///
/// Flow: DIAG_LIST_REQ → DIAG_INFO… DIAG_LIST_END → for each PENDING report not already on this phone (oldest first):
/// DIAG_CHUNK_REQ at the resume offset → DIAG_CHUNK appended to disk → … → crc32 of the whole file → DIAG_ACK only when
/// it matches. Reports already saved here that the board still lists as pending are acknowledged again (never re-pulled).
final class DiagTransfer {
    struct Config {
        var timeout: TimeInterval = 5           /* per request */
        var maxTimeoutRetries = 3               /* per request; then the session pauses until the next trigger */
        var maxCrcRetries = 3                   /* restarts from offset 0 after a crc mismatch / bad offset */
        var maxReadErrorRetries = 3             /* DIAG_ERR 3 */
        var readErrorDelay: TimeInterval = 2
        var busyDelay: TimeInterval = 10        /* DIAG_ERR 4 */
        var rideInterval: TimeInterval = 1      /* at most one chunk per second while a ride is recording on the phone */
        var boardRideRecheck: TimeInterval = 10 /* a ride RECORDING on the board: no chunk requests; look again this often */
    }
    enum Phase: Equatable { case idle, listing, pulling(UInt32) }
    struct Progress: Equatable { var reportId: UInt32; var received: UInt32; var size: UInt32; var kindRaw: UInt8 }

    let boardId: String
    let store: DiagStore
    var config: Config
    /// Writes one message on the Control characteristic; false when the link cannot take it now.
    var send: (Data) -> Bool
    var rideActive: () -> Bool = { false }
    /// The board's LIVE says a ride is RECORDING there (firmware 0.7.3 answers chunk requests BUSY then): don't ask at all.
    var boardRecording: () -> Bool = { false }
    /// Largest single ATT packet on this link = ATT_MTU − 3 (`CBPeripheral.maximumWriteValueLength(for: .withoutResponse)`);
    /// nil = not connected / unknown. The chunk size is computed from it — never learned from failures.
    var linkPayload: () -> Int? = { nil }
    var onSaved: ((DiagReportMeta) -> Void)?
    var onChange: (() -> Void)?

    private(set) var phase: Phase = .idle { didSet { if phase != oldValue { onChange?() } } }
    private(set) var progress: Progress? { didSet { if progress != oldValue { onChange?() } } }
    private(set) var lastError: String? { didSet { if lastError != oldValue { onChange?() } } }
    private(set) var boardList: [BCLink.DiagInfo] = []

    private var listed: [BCLink.DiagInfo] = []
    private var queue: [BCLink.DiagInfo] = []
    private var current: BCLink.DiagInfo?
    private var offset: UInt32 = 0
    private var outstanding: (kind: Request, sentAt: Date)?
    private var scheduled: (kind: Request, at: Date)?
    private var lastChunkRequestAt: Date?
    private var timeouts = 0
    private var readErrors = 0
    private var crcFailures: [UInt32: Int] = [:]
    private var relist = false
    private var seq: UInt16 = 0
    private enum Request: Equatable { case list, chunk }

    init(boardId: String, store: DiagStore, config: Config = Config(), send: @escaping (Data) -> Bool) {
        self.boardId = boardId; self.store = store; self.config = config; self.send = send
    }

    var isBusy: Bool { phase != .idle }
    /// `max_len` of the next DIAG_CHUNK_REQ: min(155, (ATT_MTU − 3) − 25) — docs/LINK_V1_2_SPEC.md 1.2.3. While the link size is
    /// unknown the protocol maximum 155 is asked for (the board clamps to the MTU it negotiated, so nothing can be oversized).
    /// nil: the link is too small for even one data byte.
    var chunkLen: UInt16? {
        guard let p = linkPayload() else { return UInt16(BCLink.diagChunkDataMax) }
        return BCLink.diagRequestMaxLen(linkPayload: p)
    }

    // MARK: triggers
    /// Link ready with cap 0x400, or a diag_ready event: (re)list. While busy, a list follows the current session.
    func start(now: Date) {
        if phase == .idle { lastError = nil; requestList(now: now) } else { relist = true }
    }
    func diagReady(_ r: BCLink.DiagReady, now: Date) { start(now: now) }
    /// The link went away (disconnect, board restart). Received bytes stay on disk; the next `start` resumes there.
    func linkDown() {
        phase = .idle; progress = nil; current = nil; queue = []; listed = []
        outstanding = nil; scheduled = nil; relist = false; timeouts = 0; readErrors = 0; lastChunkRequestAt = nil
    }

    // MARK: input
    func receive(_ d: Data, now: Date) {
        guard let t = d.first else { return }
        switch BCLink.MsgType(rawValue: t) {
        case .diagInfo: if let i = BCLink.decodeDiagInfo(d) { gotInfo(i) }
        case .diagListEnd: if BCLink.decodeDiagListEnd(d) != nil { gotListEnd(now: now) }
        case .diagChunk: if let c = BCLink.decodeDiagChunk(d) { gotChunk(c, now: now) }
        case .diagErr: if let e = BCLink.decodeDiagErr(d) { gotErr(e, now: now) }
        case .event: if let r = BCLink.decodeDiagReady(d) { diagReady(r, now: now) }
        default: break
        }
    }

    /// Timeouts and delayed requests. Call a few times per second while `isBusy`.
    func tick(now: Date) {
        if let o = outstanding, now.timeIntervalSince(o.sentAt) >= config.timeout {
            outstanding = nil
            timeouts += 1
            if timeouts > config.maxTimeoutRetries {
                lastError = o.kind == .list ? "The BikeComputer did not answer the report list." : "The BikeComputer stopped sending the report — it resumes on the next connection."
                pause()
                return
            }
            issue(o.kind, now: now, throttle: false)                  /* same offset, same size: sizing never depends on timeouts */
            return
        }
        if let s = scheduled, now >= s.at { scheduled = nil; issue(s.kind, now: now, throttle: false) }
    }

    // MARK: listing
    private func requestList(now: Date) {
        phase = .listing; listed = []; timeouts = 0; readErrors = 0
        issue(.list, now: now, throttle: false)
    }

    private func gotInfo(_ i: BCLink.DiagInfo) {
        if let k = boardList.firstIndex(where: { $0.reportId == i.reportId }) { boardList[k] = i } else { boardList.append(i) }
        // the board answers an ACK with DIAG_INFO state 1: remember that it is confirmed
        if i.state == 1, var m = store.meta(boardId, i.reportId), !m.boardAcknowledged, m.crc32 == i.crc32 { m.boardAcknowledged = true; store.save(m); onChange?() }
        if phase == .listing { if let k = listed.firstIndex(where: { $0.reportId == i.reportId }) { listed[k] = i } else { listed.append(i) } }
    }

    private func gotListEnd(now: Date) {
        guard phase == .listing else { return }
        outstanding = nil; timeouts = 0
        queue = []
        for i in listed.sorted(by: { $0.reportId < $1.reportId }) where i.pending {
            if let m = store.meta(boardId, i.reportId) {
                // already here (or deleted here by the rider): never pulled again; confirm it to the board if it still waits
                if m.crc32 == i.crc32 { sendAck(i.reportId, m.crc32) }
            } else if (crcFailures[i.reportId] ?? 0) <= config.maxCrcRetries {
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
        current = i
        phase = .pulling(i.reportId)
        offset = store.preparePartial(boardId, i)
        progress = Progress(reportId: i.reportId, received: offset, size: i.size, kindRaw: i.kindRaw)
        if offset >= i.size { finish(now: now) } else { issue(.chunk, now: now, throttle: true) }
    }

    private func gotChunk(_ c: BCLink.DiagChunk, now: Date) {
        guard case .pulling(let id) = phase, let i = current, c.reportId == id else { return }
        guard c.offset == offset else { return }                      /* duplicate or late answer to an earlier request */
        outstanding = nil; scheduled = nil; timeouts = 0
        let len = UInt32(c.data.count)
        if (len == 0 && !c.last) || UInt64(offset) + UInt64(len) > UInt64(i.size) { restart(i, now: now, reason: "the board sent more data than the report size"); return }
        if len > 0 {
            guard store.appendPartial(boardId, id, c.data) else { lastError = "Could not save the report on this iPhone (storage full?)."; pause(); return }
            offset += len
            progress = Progress(reportId: id, received: offset, size: i.size, kindRaw: i.kindRaw)
        }
        if offset >= i.size { finish(now: now) }
        else if c.last { restart(i, now: now, reason: "the board ended the report early") }
        else { issue(.chunk, now: now, throttle: true) }
    }

    private func finish(now: Date) {
        guard let i = current else { return }
        let data = store.partialData(boardId, i.reportId) ?? Data()
        guard data.count == Int(i.size), CRC32.ieee(data) == i.crc32 else { restart(i, now: now, reason: "checksum mismatch"); return }
        if let m = store.commit(boardId, i, receivedAt: now) {
            sendAck(i.reportId, i.crc32)
            onSaved?(m)
        } else { lastError = "Could not save the report on this iPhone." }
        next(now: now)
    }

    /// crc mismatch / inconsistent data / bad offset: drop the partial and start again from 0, at most maxCrcRetries times.
    private func restart(_ i: BCLink.DiagInfo, now: Date, reason: String) {
        store.deletePartial(boardId, i.reportId)
        let n = (crcFailures[i.reportId] ?? 0) + 1
        crcFailures[i.reportId] = n
        if n > config.maxCrcRetries {
            lastError = "Report \(i.reportId) could not be received intact (\(reason)); it stays on the board."
            next(now: now)
            return
        }
        offset = store.preparePartial(boardId, i)
        progress = Progress(reportId: i.reportId, received: offset, size: i.size, kindRaw: i.kindRaw)
        issue(.chunk, now: now, throttle: true)
    }

    private func gotErr(_ e: BCLink.DiagErr, now: Date) {
        if phase == .listing {
            outstanding = nil
            if e.known != .busy {
                readErrors += 1
                if readErrors > config.maxReadErrorRetries { lastError = "The BikeComputer could not list its reports (\(e.text))."; pause(); return }
            }
            scheduled = (.list, now.addingTimeInterval(e.known == .busy ? config.busyDelay : config.readErrorDelay))
            return
        }
        guard case .pulling(let id) = phase, let i = current, e.reportId == id || e.reportId == 0 else { return }
        outstanding = nil
        switch e.known {
        case .unknownId:
            store.deletePartial(boardId, id)
            lastError = nil
            next(now: now)
        case .badOffset:
            restart(i, now: now, reason: "bad offset")
        case .busy:                              /* > 4 outstanding, or a ride is recording on the board */
            scheduled = (.chunk, now.addingTimeInterval(config.busyDelay))
        case .linkTooSmall:
            lastError = "The Bluetooth link to the BikeComputer is too small to transfer reports; they stay on the board."
            pause()
        case .storageReadError, nil:
            readErrors += 1
            if readErrors > config.maxReadErrorRetries {
                lastError = "The BikeComputer could not read report \(id) (\(e.text)); it is kept there and retried on the next connection."
                next(now: now)                   /* partial kept: resumes later */
            } else {
                scheduled = (.chunk, now.addingTimeInterval(config.readErrorDelay))
            }
        }
    }

    // MARK: output
    private func issue(_ r: Request, now: Date, throttle: Bool) {
        switch r {
        case .list:
            outstanding = (.list, now)
            _ = send(BCLink.encodeDiagListRequest(seq: nextSeq(), tMs: 0) ?? Data())
        case .chunk:
            guard let i = current else { return }
            if boardRecording() {                /* the board refuses chunks while it records a ride: wait, ask nothing */
                scheduled = (.chunk, now.addingTimeInterval(config.boardRideRecheck))
                return
            }
            if throttle, rideActive(), let last = lastChunkRequestAt, now.timeIntervalSince(last) < config.rideInterval {
                scheduled = (.chunk, last.addingTimeInterval(config.rideInterval))
                return
            }
            guard let maxLen = chunkLen else {
                lastError = "The Bluetooth link to the BikeComputer is too small to transfer reports; they stay on the board."
                pause()
                return
            }
            outstanding = (.chunk, now); lastChunkRequestAt = now
            _ = send(BCLink.encodeDiagChunkRequest(reportId: i.reportId, offset: offset, maxLen: maxLen, seq: nextSeq(), tMs: 0) ?? Data())
            /* a refused write is handled like a lost answer: the timeout retries it */
        }
    }
    private func sendAck(_ id: UInt32, _ crc: UInt32) {
        if let d = BCLink.encodeDiagAck(reportId: id, crc32: crc, seq: nextSeq(), tMs: 0) { _ = send(d) }
    }
    /// Stop for now; the partial stays on disk and the next trigger resumes it.
    private func pause() {
        phase = .idle; progress = nil; current = nil; queue = []; outstanding = nil; scheduled = nil; relist = false
    }
    private func nextSeq() -> UInt16 { seq &+= 1; return seq }
}
