import Foundation

/// A board diagnostic report saved on this iPhone (meta JSON next to the text file).
struct DiagReportMeta: Codable, Equatable, Identifiable {
    var boardId: String
    var reportId: UInt32
    var size: UInt32
    var crc32: UInt32
    var createdEpochS: UInt32
    var kindRaw: UInt8
    var summary: String
    var firmware: String
    var receivedAt: Date
    /// The board confirmed the ACK (it answered DIAG_INFO with state 1).
    var boardAcknowledged = false
    /// The rider has seen it (opened it or dismissed the "crashed earlier" banner).
    var seen = false
    /// Deleted by the rider: the text is gone, this record stays only so the report is never pulled again.
    var deletedByUser = false

    var id: String { "\(boardId)/\(reportId)" }
    var kind: BCLink.DiagKind? { BCLink.DiagKind(rawValue: kindRaw) }
    var kindTitle: String { kind?.title ?? "Report (kind \(kindRaw))" }
    var isCrash: Bool { kind == .crash }
    var created: Date? { createdEpochS == 0 ? nil : Date(timeIntervalSince1970: TimeInterval(createdEpochS)) }
    var crcHex: String { String(format: "%08x", crc32) }
    var sizeText: String { size < 1024 ? "\(size) B" : String(format: "%.1f KB", Double(size) / 1024) }
}

/// Files under `root` (the app uses Application Support/Diagnostics):
///   <board-id>/<report_id>.txt        the verified report (UTF-8 text as the board wrote it)
///   <board-id>/<report_id>.json       DiagReportMeta
///   <board-id>/<report_id>.part       bytes received so far (resume point = its length)
///   <board-id>/<report_id>.part.json  size + crc the partial belongs to (a different report with the same id → restart)
/// Nothing here is deleted automatically; only the rider deletes a report. Backed up like the rest of the app's data.
final class DiagStore {
    let root: URL
    private let fm = FileManager.default

    init(root: URL) { self.root = root }

    static func defaultRoot() -> URL {
        let base = (try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true))
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("Diagnostics", isDirectory: true)
    }

    /// File-system-safe board folder name ("aa:bb:cc:dd:ee:ff" → "aa-bb-cc-dd-ee-ff").
    static func folderName(_ boardId: String) -> String {
        let ok = Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_.")
        let s = String(boardId.map { ok.contains($0) ? $0 : "-" })
        return s.isEmpty || s == "." || s == ".." ? "unknown" : s
    }
    func dir(_ boardId: String) -> URL { root.appendingPathComponent(Self.folderName(boardId), isDirectory: true) }
    private func url(_ boardId: String, _ id: UInt32, _ ext: String) -> URL { dir(boardId).appendingPathComponent("\(id).\(ext)") }
    func textURL(_ m: DiagReportMeta) -> URL { url(m.boardId, m.reportId, "txt") }
    private func ensureDir(_ boardId: String) { try? fm.createDirectory(at: dir(boardId), withIntermediateDirectories: true) }

    // MARK: complete reports
    func meta(_ boardId: String, _ id: UInt32) -> DiagReportMeta? {
        guard let d = try? Data(contentsOf: url(boardId, id, "json")) else { return nil }
        return try? Self.decoder.decode(DiagReportMeta.self, from: d)
    }
    /// Known on this phone (saved, or saved and deleted by the rider): never pulled again.
    func isKnown(_ boardId: String, _ id: UInt32) -> Bool { meta(boardId, id) != nil }

    func save(_ m: DiagReportMeta) {
        ensureDir(m.boardId)
        if let d = try? Self.encoder.encode(m) { try? d.write(to: url(m.boardId, m.reportId, "json"), options: .atomic) }
    }

    /// Every report still present (not deleted), newest first.
    func allReports() -> [DiagReportMeta] {
        guard let boards = try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) else { return [] }
        var out: [DiagReportMeta] = []
        for b in boards {
            guard let files = try? fm.contentsOfDirectory(at: b, includingPropertiesForKeys: nil) else { continue }
            for f in files where f.pathExtension == "json" && !f.lastPathComponent.hasSuffix(".part.json") {
                if let d = try? Data(contentsOf: f), let m = try? Self.decoder.decode(DiagReportMeta.self, from: d), !m.deletedByUser { out.append(m) }
            }
        }
        return out.sorted { ($0.receivedAt, $0.reportId) > ($1.receivedAt, $1.reportId) }
    }

    func text(_ m: DiagReportMeta) -> String? {
        (try? Data(contentsOf: textURL(m))).map { String(decoding: $0, as: UTF8.self) }
    }

    /// The rider deletes a report: the text goes, a tombstone keeps it from being pulled again.
    func delete(_ m: DiagReportMeta) {
        try? fm.removeItem(at: textURL(m))
        var t = m; t.deletedByUser = true; t.summary = ""; save(t)
    }

    // MARK: partial transfer
    private struct PartialMeta: Codable, Equatable { var size: UInt32; var crc32: UInt32 }

    /// Resume point for `info`: the length of the partial when it belongs to the same report (same size and crc),
    /// otherwise the partial is discarded and a new one started at 0.
    func preparePartial(_ boardId: String, _ info: BCLink.DiagInfo) -> UInt32 {
        ensureDir(boardId)
        let pm = PartialMeta(size: info.size, crc32: info.crc32)
        let metaURL = url(boardId, info.reportId, "part.json"), partURL = url(boardId, info.reportId, "part")
        if let d = try? Data(contentsOf: metaURL), let old = try? JSONDecoder().decode(PartialMeta.self, from: d), old == pm,
           let attrs = try? fm.attributesOfItem(atPath: partURL.path), let n = (attrs[.size] as? NSNumber)?.uint32Value, n <= info.size {
            return n
        }
        deletePartial(boardId, info.reportId)
        fm.createFile(atPath: partURL.path, contents: Data())
        if let d = try? JSONEncoder().encode(pm) { try? d.write(to: metaURL, options: .atomic) }
        return 0
    }
    /// Appends a received chunk; false when the write failed (the transfer then stops and resumes later).
    @discardableResult
    func appendPartial(_ boardId: String, _ id: UInt32, _ data: Data) -> Bool {
        guard let h = try? FileHandle(forWritingTo: url(boardId, id, "part")) else { return false }
        defer { try? h.close() }
        do { try h.seekToEnd(); try h.write(contentsOf: data); return true } catch { return false }
    }
    func partialData(_ boardId: String, _ id: UInt32) -> Data? { try? Data(contentsOf: url(boardId, id, "part")) }
    func partialLength(_ boardId: String, _ id: UInt32) -> UInt32? {
        (try? fm.attributesOfItem(atPath: url(boardId, id, "part").path))?[.size].flatMap { ($0 as? NSNumber)?.uint32Value }
    }
    func deletePartial(_ boardId: String, _ id: UInt32) {
        try? fm.removeItem(at: url(boardId, id, "part"))
        try? fm.removeItem(at: url(boardId, id, "part.json"))
    }
    /// Turns a verified partial into the saved report. Returns the new meta.
    func commit(_ boardId: String, _ info: BCLink.DiagInfo, receivedAt: Date) -> DiagReportMeta? {
        let part = url(boardId, info.reportId, "part"), txt = url(boardId, info.reportId, "txt")
        try? fm.removeItem(at: txt)
        do { try fm.moveItem(at: part, to: txt) } catch { return nil }
        try? fm.removeItem(at: url(boardId, info.reportId, "part.json"))
        let m = DiagReportMeta(boardId: boardId, reportId: info.reportId, size: info.size, crc32: info.crc32, createdEpochS: info.createdEpochS,
                               kindRaw: info.kindRaw, summary: info.summary, firmware: info.firmware, receivedAt: receivedAt)
        save(m)
        return m
    }

    private static let encoder: JSONEncoder = { let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; e.outputFormatting = [.sortedKeys]; return e }()
    private static let decoder: JSONDecoder = { let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d }()
}
