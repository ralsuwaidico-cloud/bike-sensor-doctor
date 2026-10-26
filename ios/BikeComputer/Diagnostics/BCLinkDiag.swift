import Foundation

/// Link 1.2.3 — diagnostic report transfer (firmware 0.7.3, INFO cap 0x400 DIAG_XFER). docs/LINK_V1_2_SPEC.md "1.2.3".
/// All messages travel on the Control characteristic 0005 (encrypted write + notify); the phone pulls, so a transfer
/// resumes exactly where it stopped. Same TLV rules as the rest of BCLink: little-endian, unknown tags skipped,
/// wrong-length known fields skipped, truncated messages rejected whole (`parse` returns nil).
extension BCLink {
    /// EVENT 0x40 `01 u8 event_id = 0x22 diag_ready` · `02 u8 pending count` · `03 u32 newest report_id`.
    static let diagReadyEventId = 0x22

    enum DiagKind: UInt8, Codable, CaseIterable {
        case crash = 1, recoverySession = 2, manual = 3, periodicHealth = 4
        var title: String {
            switch self { case .crash: return "Crash"; case .recoverySession: return "Recovery session"; case .manual: return "Sent from the board"; case .periodicHealth: return "Health check" }
        }
    }

    /// One DIAG_INFO (0x81): a report as the board stores it.
    struct DiagInfo: Equatable {
        var reportId: UInt32 = 0
        var size: UInt32 = 0
        var crc32: UInt32 = 0
        var createdEpochS: UInt32 = 0          /* 0 = unknown */
        var kindRaw: UInt8 = 0
        var state: UInt8 = 0                   /* 0 pending, 1 sent/acknowledged */
        var summary = ""
        var firmware = ""
        var kind: DiagKind? { DiagKind(rawValue: kindRaw) }
        var pending: Bool { state == 0 }
    }
    struct DiagListEnd: Equatable { var count = 0; var pending = 0 }
    struct DiagChunk: Equatable { var reportId: UInt32 = 0; var offset: UInt32 = 0; var data = Data(); var last = false }
    struct DiagErr: Equatable {
        var reportId: UInt32 = 0
        var code: UInt8 = 0
        enum Code: UInt8 { case unknownId = 1, badOffset = 2, storageReadError = 3, busy = 4 }
        var known: Code? { Code(rawValue: code) }
        var text: String {
            switch known { case .unknownId: return "the board no longer has this report"; case .badOffset: return "bad offset"; case .storageReadError: return "board storage read error"; case .busy: return "board busy"; case nil: return "error \(code)" }
        }
    }
    struct DiagReady: Equatable { var pending = 0; var newestReportId: UInt32 = 0 }

    // MARK: phone → board
    static func encodeDiagListRequest(seq: UInt16, tMs: UInt32) -> Data? { Writer(type: .diagListReq, seq: seq, tMs: tMs).result }
    static func encodeDiagChunkRequest(reportId: UInt32, offset: UInt32, maxLen: UInt16, seq: UInt16, tMs: UInt32) -> Data? {
        var w = Writer(type: .diagChunkReq, seq: seq, tMs: tMs)
        w.u32(0x01, reportId); w.u32(0x02, offset); w.u16(0x03, maxLen)
        return w.result
    }
    static func encodeDiagAck(reportId: UInt32, crc32: UInt32, seq: UInt16, tMs: UInt32) -> Data? {
        var w = Writer(type: .diagAck, seq: seq, tMs: tMs)
        w.u32(0x01, reportId); w.u32(0x02, crc32)
        return w.result
    }

    // MARK: board → phone
    /// nil unless it is a DIAG_INFO carrying report_id, size and crc32.
    static func decodeDiagInfo(_ d: Data) -> DiagInfo? {
        guard let (h, f) = parse(d), h.type == MsgType.diagInfo.rawValue else { return nil }
        var i = DiagInfo(); var gotId = false, gotSize = false, gotCrc = false
        for x in f {
            let v = x.value
            switch (x.tag, v.count) {
            case (0x01, 4): i.reportId = UInt32(uint(v)); gotId = true
            case (0x02, 4): i.size = UInt32(uint(v)); gotSize = true
            case (0x03, 4): i.crc32 = UInt32(uint(v)); gotCrc = true
            case (0x04, 4): i.createdEpochS = UInt32(uint(v))
            case (0x05, 1): i.kindRaw = v[v.startIndex]
            case (0x06, 1): i.state = v[v.startIndex]
            case (0x07, 0...40): i.summary = String(decoding: v, as: UTF8.self)
            case (0x08, 0...16): i.firmware = String(decoding: v, as: UTF8.self)
            default: break
            }
        }
        return gotId && gotSize && gotCrc ? i : nil
    }
    static func decodeDiagListEnd(_ d: Data) -> DiagListEnd? {
        guard let (h, f) = parse(d), h.type == MsgType.diagListEnd.rawValue else { return nil }
        var e = DiagListEnd()
        for x in f { switch (x.tag, x.value.count) { case (0x01, 1): e.count = Int(x.value[x.value.startIndex]); case (0x02, 1): e.pending = Int(x.value[x.value.startIndex]); default: break } }
        return e
    }
    /// nil unless report_id, offset and data are present. `data` may be empty only together with `last`.
    static func decodeDiagChunk(_ d: Data) -> DiagChunk? {
        guard let (h, f) = parse(d), h.type == MsgType.diagChunk.rawValue else { return nil }
        var c = DiagChunk(); var gotId = false, gotOff = false, gotData = false
        for x in f {
            let v = x.value
            switch (x.tag, v.count) {
            case (0x01, 4): c.reportId = UInt32(uint(v)); gotId = true
            case (0x02, 4): c.offset = UInt32(uint(v)); gotOff = true
            case (0x03, _): c.data = Data(v); gotData = true
            case (0x04, 1): c.last = v[v.startIndex] != 0
            default: break
            }
        }
        return gotId && gotOff && gotData ? c : nil
    }
    static func decodeDiagErr(_ d: Data) -> DiagErr? {
        guard let (h, f) = parse(d), h.type == MsgType.diagErr.rawValue else { return nil }
        var e = DiagErr(); var gotCode = false
        for x in f { switch (x.tag, x.value.count) { case (0x01, 4): e.reportId = UInt32(uint(x.value)); case (0x02, 1): e.code = x.value[x.value.startIndex]; gotCode = true; default: break } }
        return gotCode ? e : nil
    }
    /// EVENT 0x40 with event_id 0x22; nil for every other event.
    static func decodeDiagReady(_ d: Data) -> DiagReady? {
        guard let (h, f) = parse(d), h.type == MsgType.event.rawValue else { return nil }
        var r = DiagReady(); var isReady = false
        for x in f {
            switch (x.tag, x.value.count) {
            case (0x01, 1): isReady = Int(x.value[x.value.startIndex]) == diagReadyEventId
            case (0x02, 1): r.pending = Int(x.value[x.value.startIndex])
            case (0x03, 4): r.newestReportId = UInt32(uint(x.value))
            default: break
            }
        }
        return isReady ? r : nil
    }

    // MARK: test helpers mirroring the board's encoders (same tag order as the spec table)
    /// Builds header + TLVs without the 180-byte cap, so a full 160-byte DIAG_CHUNK (185 bytes) can be produced.
    private static func raw(_ type: MsgType, seq: UInt16, tMs: UInt32, _ fields: [(UInt8, Data)]) -> Data {
        var d = Data([type.rawValue, 0]); d.append(le(seq)); d.append(le(tMs))
        for (t, v) in fields { d.append(t); d.append(UInt8(v.count)); d.append(v) }
        return d
    }
    static func encodeDiagInfo(_ i: DiagInfo, seq: UInt16, tMs: UInt32) -> Data {
        raw(.diagInfo, seq: seq, tMs: tMs, [(0x01, le(i.reportId)), (0x02, le(i.size)), (0x03, le(i.crc32)), (0x04, le(i.createdEpochS)),
                                           (0x05, Data([i.kindRaw])), (0x06, Data([i.state])), (0x07, Data(i.summary.utf8.prefix(40))), (0x08, Data(i.firmware.utf8.prefix(16)))])
    }
    static func encodeDiagListEnd(count: UInt8, pending: UInt8, seq: UInt16, tMs: UInt32) -> Data {
        raw(.diagListEnd, seq: seq, tMs: tMs, [(0x01, Data([count])), (0x02, Data([pending]))])
    }
    static func encodeDiagChunk(_ c: DiagChunk, seq: UInt16, tMs: UInt32) -> Data {
        raw(.diagChunk, seq: seq, tMs: tMs, [(0x01, le(c.reportId)), (0x02, le(c.offset)), (0x03, c.data), (0x04, Data([c.last ? 1 : 0]))])
    }
    static func encodeDiagErr(reportId: UInt32, code: UInt8, seq: UInt16, tMs: UInt32) -> Data {
        raw(.diagErr, seq: seq, tMs: tMs, [(0x01, le(reportId)), (0x02, Data([code]))])
    }
    static func encodeDiagReady(pending: UInt8, newest: UInt32, seq: UInt16, tMs: UInt32) -> Data {
        raw(.event, seq: seq, tMs: tMs, [(0x01, Data([UInt8(diagReadyEventId)])), (0x02, Data([pending])), (0x03, le(newest))])
    }
}

/// CRC-32/IEEE 802.3 (zlib `crc32`, reflected, poly 0xEDB88320, init and xorout 0xFFFFFFFF). "123456789" → 0xCBF43926.
enum CRC32 {
    private static let table: [UInt32] = (0..<256).map { i -> UInt32 in
        var c = UInt32(i)
        for _ in 0..<8 { c = c & 1 != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1 }
        return c
    }
    static func update(_ crc: UInt32, _ data: Data) -> UInt32 {
        var c = ~crc
        for b in data { c = table[Int((c ^ UInt32(b)) & 0xFF)] ^ (c >> 8) }
        return ~c
    }
    static func ieee(_ data: Data) -> UInt32 { update(0, data) }
}
