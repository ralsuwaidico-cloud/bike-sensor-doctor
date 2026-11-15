import Foundation

// MARK: - E1 data integrity (E0 evidence report, runs 223–225)
//
// What E0 reproduced, and what this file does about it:
//  1. A store.json that could not be decoded was treated as "no data": the app started empty and the launch-time plan
//     write replaced the file. → `StoreLoad.unreadable`: the file is never written over; a byte-for-byte copy is kept
//     beside it; the store refuses every write until the athlete decides (Store.storage).
//  2. One undecodable record in `plan` or `rides` made the whole file undecodable; in the other lists it emptied the
//     list. → lists are decoded record by record (StoreFile.lossy); the raw bad records are found here and written
//     to store.quarantine.json BEFORE the first write that would drop them.
//  3. A file written by a newer build lost its schema number and unknown fields at the first save.
//     → `StoreLoad.newer`: opened read-only. Unknown top-level keys of a same-or-older schema are carried through saves.
//
// Foundation only (compiled on Linux by the fast logic tests).

/// Why the store is (or is not) allowed to write.
enum StorageState: Equatable {
    /// Normal operation.
    case ok
    /// store.json exists but could not be decoded. It is left exactly as it is; nothing is written.
    case unreadable
    /// store.json was written by a newer build (its schema number). Read-only: this build must not lower it.
    case newerVersion(Int)
    /// Bad records were found but could not be set aside (quarantine file not writable). Read-only so they are not lost.
    case cannotSetAside

    var isWritable: Bool { self == .ok }
    /// Plain words for the athlete (shown on the recovery screen and as the save error).
    var explanation: String {
        switch self {
        case .ok: return ""
        case .unreadable: return "Cyclift could not read your saved data. Nothing has been changed or deleted."
        case .newerVersion: return "Your data was saved by a newer version of Cyclift. This version will not change it."
        case .cannotSetAside: return "Some saved records could not be read and could not be set aside safely. Nothing has been changed."
        }
    }
}

/// One record that could not be decoded, with the list it came from. `raw` is the record's own JSON, unchanged.
struct QuarantinedRecord {
    let list: String
    let raw: Data
}

/// The result of reading store.json.
enum StoreLoad {
    /// No file (fresh install, or the build-14 layout which is imported separately).
    case missing
    /// Decoded. `bad` = records that were skipped (empty for a healthy file); `unknown` = top-level keys this build does
    /// not know (kept and written back).
    case ok(StoreFile, bad: [QuarantinedRecord], unknown: [String: Any])
    /// Decoded far enough to see a schema number above this build's.
    case newer(Int)
    /// The file exists and is not a decodable store.
    case unreadable
}

enum StoreRecovery {
    static let quarantineName = "store.quarantine.json"
    static let previousName = "store.previous.json"

    /// Reads store.json without ever modifying it.
    static func load(_ url: URL) -> StoreLoad {
        guard FileManager.default.fileExists(atPath: url.path) else { return .missing }
        guard let data = try? Data(contentsOf: url) else { return .unreadable }   // exists but cannot be read (e.g. device locked)
        return load(data)
    }

    static func load(_ data: Data) -> StoreLoad {
        guard let top = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return .unreadable }
        if let n = schemaNumber(top), n > StoreFile.currentSchema { return .newer(n) }
        let iso = JSONDecoder(); iso.dateDecodingStrategy = .iso8601
        let plain = JSONDecoder()                                  // build-14 files used the default date encoding
        var best: (StoreFile, [QuarantinedRecord])? = nil
        for dec in [iso, plain] {
            guard let f = try? dec.decode(StoreFile.self, from: data) else { continue }
            let bad = badRecords(top: top, decoded: f, decoder: dec)
            if best == nil || bad.count < best!.1.count { best = (f, bad) }
            if bad.isEmpty { break }
        }
        guard let (file, bad) = best else { return .unreadable }
        let known = Set(StoreFile.CodingKeys.allCases.map { $0.rawValue })
        let unknown = top.filter { !known.contains($0.key) }
        return .ok(file, bad: bad, unknown: unknown)
    }

    private static func schemaNumber(_ top: [String: Any]) -> Int? {
        if let n = top["schema"] as? Int { return n }
        if let n = top["schema"] as? NSNumber { return n.intValue }
        return nil
    }

    /// The records of every stored list that the decoder skipped. Found by decoding each raw element on its own with the
    /// same decoder, so "bad" here means exactly "the app could not read it".
    private static func badRecords(top: [String: Any], decoded f: StoreFile, decoder: JSONDecoder) -> [QuarantinedRecord] {
        var out: [QuarantinedRecord] = []
        func check<T: Decodable>(_ key: String, _ type: T.Type, _ kept: Int) {
            guard let arr = top[key] as? [Any], arr.count != kept else { return }
            for el in arr {
                // a list element must be a JSON object; anything else (a number, a string, null) is itself a bad record
                if let obj = el as? [String: Any], let d = try? JSONSerialization.data(withJSONObject: obj) {
                    if (try? decoder.decode(T.self, from: d)) == nil { out.append(QuarantinedRecord(list: key, raw: d)) }
                } else if let d = try? JSONSerialization.data(withJSONObject: ["value": el]) {
                    out.append(QuarantinedRecord(list: key, raw: d))
                }
            }
        }
        check("plan", Workout.self, f.plan.count)
        check("rides", RideRecord.self, f.rides.count)
        check("strength", StrengthSession.self, f.strength.count)
        check("templates", WorkoutTemplate.self, f.templates.count)
        check("customExercises", Exercise.self, f.customExercises.count)
        check("appliedProposals", AppliedProposal.self, f.appliedProposals.count)
        check("boardSync", BoardSyncRecord.self, f.boardSync.count)
        check("adaptations", PlanAdjustment.self, f.adaptations.count)
        check("adaptiveProposals", AdaptiveProposal.self, f.adaptiveProposals.count)
        check("painClearances", PainClearance.self, f.painClearances.count)
        check("trash", TrashItem.self, f.trash.count)
        check("planVersions", PlanVersion.self, f.planVersions.count)
        return out
    }

    /// Appends the raw bad records to store.quarantine.json. Returns false when the file could not be written — the
    /// caller must then NOT write store.json, because that write would drop the only copy of those records.
    static func setAside(_ bad: [QuarantinedRecord], in dir: URL, now: Date = Date()) -> Bool {
        guard !bad.isEmpty else { return true }
        let url = dir.appendingPathComponent(quarantineName)
        var all: [Any] = []
        if let d = try? Data(contentsOf: url), let old = (try? JSONSerialization.jsonObject(with: d)) as? [Any] { all = old }
        let stamp = ISO8601DateFormatter().string(from: now)
        for b in bad {
            let record: Any = (try? JSONSerialization.jsonObject(with: b.raw)) ?? (String(data: b.raw, encoding: .utf8) ?? "")
            all.append(["list": b.list, "setAsideAt": stamp, "record": record] as [String: Any])
        }
        guard let d = try? JSONSerialization.data(withJSONObject: all, options: [.prettyPrinted]) else { return false }
        do { try d.write(to: url, options: .atomic); return true } catch { return false }
    }

    /// Keeps a byte-for-byte copy of an unreadable store.json beside it (once per distinct content). The original is not
    /// touched. Returns the copy's file name, or nil when no copy could be made.
    @discardableResult
    static func keepUnreadableCopy(of url: URL, in dir: URL, now: Date = Date()) -> String? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let fm = FileManager.default
        let existing = ((try? fm.contentsOfDirectory(atPath: dir.path)) ?? []).filter { $0.hasPrefix("store.unreadable-") }
        for n in existing { if (try? Data(contentsOf: dir.appendingPathComponent(n))) == data { return n } }
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = TimeZone(identifier: "UTC"); f.dateFormat = "yyyyMMdd-HHmmss"
        var name = "store.unreadable-\(f.string(from: now)).json"; var k = 1
        while fm.fileExists(atPath: dir.appendingPathComponent(name).path) { k += 1; name = "store.unreadable-\(f.string(from: now))-\(k).json" }
        do { try data.write(to: dir.appendingPathComponent(name), options: .atomic); return name } catch { return nil }
    }

    /// Copies the store.json that was read at launch to store.previous.json, before this launch's first write. Only ever
    /// called for a file that decoded, so a damaged primary can never replace the previous good copy.
    static func keepPreviousCopy(in dir: URL) {
        let src = dir.appendingPathComponent("store.json"), dst = dir.appendingPathComponent(previousName)
        guard let data = try? Data(contentsOf: src) else { return }
        try? data.write(to: dst, options: .atomic)
    }

    /// Adds the unknown top-level keys of the loaded file back into the encoded store, so a field written by a newer
    /// build of the same schema survives a save by this build. Known keys always win.
    static func merging(unknown: [String: Any], into encoded: Data) -> Data {
        guard !unknown.isEmpty, var o = (try? JSONSerialization.jsonObject(with: encoded)) as? [String: Any] else { return encoded }
        for (k, v) in unknown where o[k] == nil { o[k] = v }
        return (try? JSONSerialization.data(withJSONObject: o)) ?? encoded
    }
}
