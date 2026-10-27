import Foundation

/// One offline ride from the BikeComputer queue as saved on this iPhone (meta JSON next to the samples text file).
struct BoardQueueRideMeta: Codable, Equatable, Identifiable {
    var boardId: String
    var rideId: UInt32
    var samplesSize: UInt32
    var samplesCrc32: UInt32
    var summaryCrc32: UInt32
    var startEpochS: UInt32
    var durationS: UInt32
    var flags: UInt8
    var receivedAt: Date
    /// The RideRecord in Cyclift's history that holds this ride (set once the history import is saved).
    var historyRideId: UUID? = nil
    /// RIDEQ_ACK sent (only after the ride was durably stored and both CRCs verified).
    var acked = false
    /// The board answered the ACK with state 3 / 4 (verified on the phone / samples deleted).
    var boardConfirmedState: UInt8? = nil
    var id: String { "\(boardId)/\(rideId)" }
    var sizeText: String { samplesSize < 1024 ? "\(samplesSize) B" : String(format: "%.1f KB", Double(samplesSize) / 1024) }
}

/// Files under `root` (the app uses Application Support/BoardRides). Same resumable layout as DiagStore:
///   <board-id>/<ride_id>.txt        the verified samples file, byte-identical to the board's rides/r####.txt
///   <board-id>/<ride_id>.json       BoardQueueRideMeta
///   <board-id>/<ride_id>.part       bytes received so far (resume point = its length)
///   <board-id>/<ride_id>.part.json  size + crc the partial belongs to
/// Nothing here is deleted automatically: the samples are the rider's ride data.
final class BoardRideQueueStore {
    let root: URL
    private let fm = FileManager.default
    init(root: URL) { self.root = root }

    static func defaultRoot() -> URL {
        let base = (try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)) ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("BoardRides", isDirectory: true)
    }
    func dir(_ boardId: String) -> URL { root.appendingPathComponent(DiagStore.folderName(boardId), isDirectory: true) }
    private func url(_ boardId: String, _ id: UInt32, _ ext: String) -> URL { dir(boardId).appendingPathComponent("\(id).\(ext)") }
    func samplesURL(_ m: BoardQueueRideMeta) -> URL { url(m.boardId, m.rideId, "txt") }
    private func ensureDir(_ boardId: String) { try? fm.createDirectory(at: dir(boardId), withIntermediateDirectories: true) }

    func meta(_ boardId: String, _ id: UInt32) -> BoardQueueRideMeta? {
        guard let d = try? Data(contentsOf: url(boardId, id, "json")) else { return nil }
        return try? Self.decoder.decode(BoardQueueRideMeta.self, from: d)
    }
    @discardableResult
    func save(_ m: BoardQueueRideMeta) -> Bool {
        ensureDir(m.boardId)
        guard let d = try? Self.encoder.encode(m) else { return false }
        do { try d.write(to: url(m.boardId, m.rideId, "json"), options: .atomic); return true } catch { return false }
    }
    func samples(_ m: BoardQueueRideMeta) -> Data? { try? Data(contentsOf: samplesURL(m)) }
    func all() -> [BoardQueueRideMeta] {
        guard let boards = try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) else { return [] }
        var out: [BoardQueueRideMeta] = []
        for b in boards {
            for f in (try? fm.contentsOfDirectory(at: b, includingPropertiesForKeys: nil)) ?? [] where f.pathExtension == "json" && !f.lastPathComponent.hasSuffix(".part.json") && f.lastPathComponent != "summary-crc.json" {
                if let d = try? Data(contentsOf: f), let m = try? Self.decoder.decode(BoardQueueRideMeta.self, from: d) { out.append(m) }
            }
        }
        return out.sorted { ($0.receivedAt, $0.rideId) > ($1.receivedAt, $1.rideId) }
    }
    /// Bytes of ride samples kept on this phone.
    func totalBytes() -> Int { all().reduce(0) { $0 + Int($1.samplesSize) } }

    // MARK: summaries received over SYNC_RIDE (Link 1.1) — the phone's side of `summary_crc32`
    /// CRC-32 over the SYNC_RIDE TLV fields (every byte after the 8-byte header) as the board sent them. Contract
    /// question Q-iOS-1: the firmware must compute `summary_crc32` over exactly these bytes, else no ride is ever ACKed
    /// (safe: the board keeps it).
    static func summaryCrc(ofSyncRide d: Data) -> UInt32? { d.count > BCLink.headerSize ? CRC32.ieee(d.dropFirst(BCLink.headerSize)) : nil }
    private func summaryURL(_ boardId: String) -> URL { dir(boardId).appendingPathComponent("summary-crc.json") }
    func summaryCrc(_ boardId: String, _ rideId: UInt32) -> UInt32? {
        guard let d = try? Data(contentsOf: summaryURL(boardId)), let m = try? JSONDecoder().decode([String: UInt32].self, from: d) else { return nil }
        return m[String(rideId)]
    }
    func saveSummaryCrc(_ boardId: String, _ rideId: UInt32, _ crc: UInt32) {
        ensureDir(boardId)
        var m = (try? Data(contentsOf: summaryURL(boardId))).flatMap { try? JSONDecoder().decode([String: UInt32].self, from: $0) } ?? [:]
        guard m[String(rideId)] != crc else { return }
        m[String(rideId)] = crc
        if let d = try? JSONEncoder().encode(m) { try? d.write(to: summaryURL(boardId), options: .atomic) }
    }

    // MARK: partial transfer
    private struct PartialMeta: Codable, Equatable { var size: UInt32; var crc32: UInt32 }
    func preparePartial(_ boardId: String, _ i: BCLink.RideQueueInfo) -> UInt32 {
        ensureDir(boardId)
        let pm = PartialMeta(size: i.samplesSize, crc32: i.samplesCrc32)
        let metaURL = url(boardId, i.rideId, "part.json"), partURL = url(boardId, i.rideId, "part")
        if let d = try? Data(contentsOf: metaURL), let old = try? JSONDecoder().decode(PartialMeta.self, from: d), old == pm,
           let attrs = try? fm.attributesOfItem(atPath: partURL.path), let n = (attrs[.size] as? NSNumber)?.uint32Value, n <= i.samplesSize {
            return n
        }
        deletePartial(boardId, i.rideId)
        fm.createFile(atPath: partURL.path, contents: Data())
        if let d = try? JSONEncoder().encode(pm) { try? d.write(to: metaURL, options: .atomic) }
        return 0
    }
    @discardableResult
    func appendPartial(_ boardId: String, _ id: UInt32, _ data: Data) -> Bool {
        guard let h = try? FileHandle(forWritingTo: url(boardId, id, "part")) else { return false }
        defer { try? h.close() }
        do { try h.seekToEnd(); try h.write(contentsOf: data); try h.synchronize(); return true } catch { return false }
    }
    func partialData(_ boardId: String, _ id: UInt32) -> Data? { try? Data(contentsOf: url(boardId, id, "part")) }
    func deletePartial(_ boardId: String, _ id: UInt32) {
        try? fm.removeItem(at: url(boardId, id, "part")); try? fm.removeItem(at: url(boardId, id, "part.json"))
    }
    /// Verified partial → saved samples + meta. nil when the move or the meta write failed (then nothing is ACKed).
    func commit(_ boardId: String, _ i: BCLink.RideQueueInfo, receivedAt: Date) -> BoardQueueRideMeta? {
        let part = url(boardId, i.rideId, "part"), txt = url(boardId, i.rideId, "txt")
        ensureDir(boardId)
        if fm.fileExists(atPath: part.path) {
            try? fm.removeItem(at: txt)
            do { try fm.moveItem(at: part, to: txt) } catch { return nil }
        } else if i.samplesSize == 0 {
            guard fm.createFile(atPath: txt.path, contents: Data()) else { return nil }
        } else { return nil }
        try? fm.removeItem(at: url(boardId, i.rideId, "part.json"))
        // read back what is on disk: the ACK is based on the stored bytes, not on what was in memory
        guard let back = try? Data(contentsOf: txt), back.count == Int(i.samplesSize), CRC32.ieee(back) == i.samplesCrc32 else { return nil }
        let m = BoardQueueRideMeta(boardId: boardId, rideId: i.rideId, samplesSize: i.samplesSize, samplesCrc32: i.samplesCrc32, summaryCrc32: i.summaryCrc32,
                                   startEpochS: i.startEpochS, durationS: i.durationS, flags: i.flags, receivedAt: receivedAt)
        return save(m) ? m : nil
    }

    private static let encoder: JSONEncoder = { let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; e.outputFormatting = [.sortedKeys]; return e }()
    private static let decoder: JSONDecoder = { let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d }()
}

/// The board's per-second samples file (`rides/r####.txt`, BLE_CONTRACT.md §6): one text line per ride second,
/// `power cadence hr distance_m`, a line "-" = a paused second. Parsed tolerantly: "-" for a single field = no value,
/// "\r" ignored, blank lines and lines starting with "#" skipped. Nothing is invented: a missing value stays nil.
enum BoardRideSamples {
    struct Second: Equatable { var paused: Bool; var power: Int?; var cadence: Int?; var hr: Int?; var distanceM: Int? }
    static func parse(_ d: Data) -> [Second] {
        var out: [Second] = []
        // "\r\n" is ONE Character in Swift: drop "\r" first, then split on "\n"
        for raw in String(decoding: d, as: UTF8.self).replacingOccurrences(of: "\r", with: "").components(separatedBy: "\n") {
            let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty || line.hasPrefix("#") { continue }
            if line == "-" { out.append(Second(paused: true, power: nil, cadence: nil, hr: nil, distanceM: nil)); continue }
            let t = line.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
            func v(_ k: Int) -> Int? { k < t.count ? Int(t[k]) : nil }
            out.append(Second(paused: false, power: v(0).flatMap { $0 >= 0 && $0 <= 3000 ? $0 : nil }, cadence: v(1).flatMap { $0 >= 0 && $0 <= 250 ? $0 : nil },
                              hr: v(2).flatMap { $0 >= 25 && $0 <= 250 ? $0 : nil }, distanceM: v(3).flatMap { $0 >= 0 ? $0 : nil }))
        }
        return out
    }
    struct Totals: Equatable { var movingS = 0, pausedS = 0, distanceM = 0; var avgPower: Int?, maxPower: Int?, avgCadence: Int?, avgHR: Int?, maxHR: Int?; var kj: Int? }
    static func totals(_ s: [Second]) -> Totals {
        var t = Totals()
        let rec = s.filter { !$0.paused }
        t.movingS = rec.count; t.pausedS = s.count - rec.count
        t.distanceM = s.compactMap { $0.distanceM }.max() ?? 0
        let w = rec.compactMap { $0.power }, c = rec.compactMap { $0.cadence }.filter { $0 > 0 }, h = rec.compactMap { $0.hr }
        if !w.isEmpty { t.avgPower = w.reduce(0, +) / w.count; t.maxPower = w.max(); t.kj = w.reduce(0, +) / 1000 }
        if !c.isEmpty { t.avgCadence = c.reduce(0, +) / c.count }
        if !h.isEmpty { t.avgHR = h.reduce(0, +) / h.count; t.maxHR = h.max() }
        return t
    }
}
