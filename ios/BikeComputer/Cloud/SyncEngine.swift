import Foundation
import Combine
import CryptoKit
import UIKit

// MARK: - pure merge rules (unit-tested in SyncMergeTests)

/// What the ledger remembers about one record: the hash of what was last pushed or pulled and when the local copy
/// last changed. Compared with the server's `client_updated_at` to decide who wins.
struct LedgerEntry: Codable, Equatable {
    var hash: String
    var changedAt: Date          // local change time (detected when the hash moved)
    var syncedAt: Date?          // last time this hash was confirmed on the server
}

enum MergeDecision: Equatable { case keepLocal, takeRemote, deleteLocal, pushLocal, nothing }

enum MergeRules {
    /// Local present, remote row seen on pull. Last writer wins on timestamps; equal hashes need nothing.
    static func decide(localHash: String?, local: LedgerEntry?, remoteHash: String, remoteClientUpdatedAt: Date, remoteDeleted: Bool) -> MergeDecision {
        guard let localHash else {                         // not on this phone
            return remoteDeleted ? .nothing : .takeRemote
        }
        if remoteDeleted {
            // deleted elsewhere: honour it unless this phone changed the record after that deletion
            let changedHere = local.map { $0.syncedAt == nil || $0.hash != localHash } ?? true
            let when = local?.changedAt ?? Date.distantPast
            return changedHere && when > remoteClientUpdatedAt ? .pushLocal : .deleteLocal
        }
        if remoteHash == localHash { return .nothing }
        // changed since the last sync: the engine re-records a moved hash with syncedAt = nil before pulling, so an
        // unconfirmed entry counts as a local change (comparing hashes alone would always let the server win)
        let localChanged = local.map { $0.syncedAt == nil || $0.hash != localHash } ?? true
        guard localChanged else { return .takeRemote }                       // only the server moved
        let localTime = local?.changedAt ?? Date.distantPast
        return localTime > remoteClientUpdatedAt ? .pushLocal : .takeRemote  // both moved: newer client time wins
    }

    /// Rides and strength sessions from another device must not duplicate what this phone already has
    /// (same origin id, or same start within 2 minutes and similar duration).
    static func isDuplicateRide(_ r: RideRecord, in existing: [RideRecord]) -> Bool {
        existing.contains { e in
            if r.sourceId == e.sourceId { return true }
            return abs(e.start.timeIntervalSince(r.start)) < 120 && abs(Double(e.durationS - r.durationS)) < 60
        }
    }
    static func isDuplicateStrength(_ s: StrengthSession, in existing: [StrengthSession]) -> Bool {
        existing.contains { e in e.id == s.id || (abs(e.date.timeIntervalSince(s.date)) < 120 && abs(e.minutes - s.minutes) <= 1 && e.focus == s.focus) }
    }

    static func hash(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }

    /// The one-row-per-user records (profile, settings).
    static func isSingleton(_ table: String) -> Bool { table == "profiles" || table == "settings" }

    /// "Changed at" for a record the ledger has never seen. Collections (rides, sessions, templates, plan) count as new
    /// local changes. The profile and settings rows count as the oldest possible change, so a phone that signs in to an
    /// account that already has a profile takes the account's profile instead of overwriting it with its own defaults
    /// (a brand-new account has no row yet, so the guest's profile is uploaded — the guest → account upgrade).
    static let neverChanged = Date(timeIntervalSince1970: 0)
    static func firstSeenChangedAt(table: String, now: Date) -> Date { isSingleton(table) ? neverChanged : now }

    /// Server tombstones are sent only for records this phone actually held and synced, never for remote rows the phone
    /// skipped (a duplicate of a local ride, or a payload this app version could not read).
    static func tombstoneIds(ledger: [String: LedgerEntry], localIds: Set<String>) -> [String] {
        ledger.compactMap { kv in !localIds.contains(kv.key) && kv.value.syncedAt != nil ? kv.key : nil }.sorted()
    }

    /// Rows per upsert request, so a long ride history never becomes one oversized request.
    static let batchSize = 50
    static func batches<T>(_ items: [T], size: Int = batchSize) -> [[T]] {
        guard size > 0, !items.isEmpty else { return items.isEmpty ? [] : [items] }
        return stride(from: 0, to: items.count, by: size).map { Array(items[$0..<min($0 + size, items.count)]) }
    }
}

// MARK: - ledger (persisted next to store.json)

struct SyncLedger: Codable, Equatable {
    var lastPull: [String: Date] = [:]            // table → server updated_at high-water mark
    var records: [String: [String: LedgerEntry]] = [:]   // table → id → entry
    var userId: String?                           // whose data this ledger describes
    var lastSuccess: Date?
    var lastError: String?
}

// MARK: - wire format

/// One row of any sync table. Timestamps travel as ISO-8601 strings (Postgres returns microseconds; we parse both).
struct CloudRow: Codable {
    var id: String?               // absent on the one-row-per-user tables (profiles, settings)
    var user_id: String
    var source_id: String?
    var started_at: String?
    var day: String?
    var payload: AnyCodableJSON
    var client_updated_at: String
    var updated_at: String?
    var deleted_at: String?
    init(id: String?, user_id: String, source_id: String?, started_at: String?, day: String?, payload: AnyCodableJSON, client_updated_at: String, updated_at: String?, deleted_at: String?) {
        self.id = id; self.user_id = user_id; self.source_id = source_id; self.started_at = started_at; self.day = day; self.payload = payload
        self.client_updated_at = client_updated_at; self.updated_at = updated_at; self.deleted_at = deleted_at
    }
    /// Only columns that exist on the target table are sent (nil = omitted), so one row type serves every table.
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(id, forKey: .id); try c.encode(user_id, forKey: .user_id)
        try c.encodeIfPresent(source_id, forKey: .source_id); try c.encodeIfPresent(started_at, forKey: .started_at); try c.encodeIfPresent(day, forKey: .day)
        try c.encode(payload, forKey: .payload); try c.encode(client_updated_at, forKey: .client_updated_at)
        try c.encodeIfPresent(deleted_at, forKey: .deleted_at)
    }
}

/// Minimal JSON passthrough so record payloads are stored as real jsonb objects and come back untouched.
struct AnyCodableJSON: Codable {
    let data: Data
    init(data: Data) { self.data = data }
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        let v = try c.decode(JSONFragment.self)
        data = try JSONSerialization.data(withJSONObject: v.object, options: [.sortedKeys])
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        let obj = try JSONSerialization.jsonObject(with: data)
        try c.encode(JSONFragment(object: obj))
    }
}
/// Recursive JSON value used only to move arbitrary objects through Codable.
struct JSONFragment: Codable {
    let object: Any
    init(object: Any) { self.object = object }
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { object = NSNull() }
        else if let b = try? c.decode(Bool.self) { object = b }
        else if let i = try? c.decode(Int64.self) { object = i }
        else if let d = try? c.decode(Double.self) { object = d }
        else if let s = try? c.decode(String.self) { object = s }
        else if let a = try? c.decode([JSONFragment].self) { object = a.map(\.object) }
        else if let o = try? c.decode([String: JSONFragment].self) { object = o.mapValues(\.object) }
        else { throw DecodingError.dataCorruptedError(in: c, debugDescription: "unsupported JSON") }
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        // JSONSerialization hands numbers back as NSNumber, and `as Bool` also matches the NSNumbers 0 and 1, which
        // silently turned integer 0/1 into false/true. Decide by the number's real CoreFoundation type first.
        if let n = object as? NSNumber, !(object is String) {
            if CFGetTypeID(n) == CFBooleanGetTypeID() { try c.encode(n.boolValue) }
            else if CFNumberIsFloatType(n) { try c.encode(n.doubleValue) }
            else { try c.encode(n.int64Value) }
            return
        }
        switch object {
        case is NSNull: try c.encodeNil()
        case let b as Bool: try c.encode(b)
        case let i as Int64: try c.encode(i)
        case let i as Int: try c.encode(i)
        case let d as Double: try c.encode(d)
        case let s as String: try c.encode(s)
        case let a as [Any]: try c.encode(a.map { JSONFragment(object: $0) })
        case let o as [String: Any]: try c.encode(o.mapValues { JSONFragment(object: $0) })
        default:
            if let n = object as? NSNumber { try c.encode(n.doubleValue) } else { throw EncodingError.invalidValue(object, .init(codingPath: c.codingPath, debugDescription: "unsupported JSON")) }
        }
    }
}

enum ISO {
    static let out: ISO8601DateFormatter = { let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return f }()
    static let plain: ISO8601DateFormatter = { let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime]; return f }()
    static func string(_ d: Date) -> String { out.string(from: d) }
    static func date(_ s: String?) -> Date? {
        guard var s else { return nil }
        if s.contains(" ") { s = s.replacingOccurrences(of: " ", with: "T") }
        if let d = out.date(from: s) ?? plain.date(from: s) { return d }
        // Postgres microseconds ("2026-10-26T01:02:03.123456+00:00"): trim to milliseconds
        if let r = s.range(of: #"\.\d{4,}"#, options: .regularExpression) {
            let frac = String(s[r].dropFirst().prefix(3)); let t = s.replacingCharacters(in: r, with: "." + frac)
            return out.date(from: t)
        }
        return nil
    }
}

// MARK: - the engine

/// Push-then-pull sync of the phone's store with the user's Supabase tables. Offline-first: nothing here blocks the
/// UI; failures are recorded and retried on the next trigger (sign-in, app foreground, a store change, manual Sync now).
@MainActor
final class SyncEngine: ObservableObject {
    enum State: Equatable { case off, idle, syncing, pending(Int), failed(String) }
    @Published private(set) var state: State = .off
    @Published private(set) var lastSuccess: Date?
    @Published private(set) var lastDetail = ""

    private let store: Store
    private let account: AccountService
    private var ledger = SyncLedger()
    private var bag = Set<AnyCancellable>()
    private var debounce: AnyCancellable?
    private var running = false
    private let enc: JSONEncoder = { let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; e.outputFormatting = [.sortedKeys]; return e }()
    private let dec: JSONDecoder = { let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d }()
    private var ledgerURL: URL { store.dir.appendingPathComponent("sync-ledger.json") }
    static let tables = ["rides", "strength_sessions", "templates", "plans", "profiles", "settings"]

    init(store: Store, account: AccountService) {
        self.store = store; self.account = account
        if let d = try? Data(contentsOf: ledgerURL), let l = try? dec.decode(SyncLedger.self, from: d) { ledger = l }
        lastSuccess = ledger.lastSuccess
        guard CloudConfig.isConfigured else { return }
        state = account.state.isSignedIn ? .idle : .off
        account.sessionChanged.sink { [weak self] signedIn in
            guard let self else { return }
            if signedIn {
                // also covers sign-ins that did not go through the account sheet (e-mail confirmation link, OAuth fallback)
                if self.store.guest { self.store.guest = false }
                self.state = .idle; Task { await self.syncNow(reason: "signed in") }
            }
            else { self.state = .off }
        }.store(in: &bag)
        // a store change → push ~10 s later (coalesced), only while signed in
        store.objectWillChange.sink { [weak self] _ in
            guard let self, self.account.state.isSignedIn else { return }
            self.debounce?.cancel()
            self.debounce = Just(()).delay(for: .seconds(10), scheduler: RunLoop.main).sink { [weak self] _ in Task { await self?.syncNow(reason: "changes") } }
        }.store(in: &bag)
        NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification).sink { [weak self] _ in
            Task { await self?.syncNow(reason: "foreground") }
        }.store(in: &bag)
    }

    var pendingCount: Int {
        guard account.state.isSignedIn else { return 0 }
        return localSets().reduce(0) { acc, kv in acc + kv.value.filter { (ledger.records[kv.key]?[$0.id]?.hash) != $0.hash }.count }
    }

    func syncNow(reason: String = "manual") async {
        guard CloudConfig.isConfigured, let userId = account.state.userId, !running else { return }
        guard let token = await account.accessToken(), let base = CloudConfig.supabaseURL, let key = CloudConfig.anonKey else {
            state = .failed("No session token"); return
        }
        running = true; state = .syncing; defer { running = false }
        if ledger.userId != userId { ledger = SyncLedger(); ledger.userId = userId }      // another account: start clean
        let api = REST(base: base, key: key, token: token)
        do {
            var pushed = 0, pulled = 0, removed = 0
            for table in Self.tables {
                let r = try await syncTable(table, api: api, userId: userId)
                pushed += r.pushed; pulled += r.pulled; removed += r.removed
            }
            ledger.lastSuccess = Date(); ledger.lastError = nil; lastSuccess = ledger.lastSuccess
            lastDetail = "\(reason): \(pushed) sent, \(pulled) received, \(removed) removed"
            state = .idle
        } catch {
            ledger.lastError = AccountService.describe(error); state = .failed(ledger.lastError!)
            lastDetail = "\(reason): \(ledger.lastError!)"
        }
        saveLedger()
    }

    // MARK: per table
    private struct Local { let id: String; let hash: String; let data: Data; let sourceId: String?; let startedAt: Date?; let day: Date? }

    /// Everything the phone holds, per table, canonically encoded.
    private func localSets() -> [String: [Local]] {
        func enc<T: Encodable>(_ v: T) -> Data { (try? self.enc.encode(v)) ?? Data() }
        var out: [String: [Local]] = [:]
        out["rides"] = store.rides.map { r in let d = enc(r); return Local(id: r.id.uuidString.lowercased(), hash: MergeRules.hash(d), data: d, sourceId: r.sourceId, startedAt: r.start, day: nil) }
        out["strength_sessions"] = store.strength.map { s in let d = enc(s); return Local(id: s.id.uuidString.lowercased(), hash: MergeRules.hash(d), data: d, sourceId: nil, startedAt: s.date, day: nil) }
        out["templates"] = store.templates.map { t in let d = enc(t); return Local(id: t.id.uuidString.lowercased(), hash: MergeRules.hash(d), data: d, sourceId: nil, startedAt: nil, day: nil) }
        out["plans"] = store.plan.map { w in let d = enc(w); return Local(id: w.id.uuidString.lowercased(), hash: MergeRules.hash(d), data: d, sourceId: nil, startedAt: nil, day: w.date) }
        let me = ledger.userId ?? "me"
        let p = enc(store.profile); out["profiles"] = [Local(id: me, hash: MergeRules.hash(p), data: p, sourceId: nil, startedAt: nil, day: nil)]
        let s = enc(SettingsBundle(store: store)); out["settings"] = [Local(id: me, hash: MergeRules.hash(s), data: s, sourceId: nil, startedAt: nil, day: nil)]
        return out
    }

    private func syncTable(_ table: String, api: REST, userId: String) async throws -> (pushed: Int, pulled: Int, removed: Int) {
        let singleton = MergeRules.isSingleton(table)
        let locals = localSets()[table] ?? []
        var entries = ledger.records[table] ?? [:]
        let now = Date()
        // 1. note local changes (hash moved since the ledger last saw it)
        for l in locals {
            if let e = entries[l.id] { if e.hash != l.hash { entries[l.id] = LedgerEntry(hash: l.hash, changedAt: now, syncedAt: nil) } }
            else { entries[l.id] = LedgerEntry(hash: l.hash, changedAt: MergeRules.firstSeenChangedAt(table: table, now: now), syncedAt: nil) }
        }
        // 2. pull what changed on the server since the last pull
        let since = ledger.lastPull[table]
        let rows = try await api.pull(table: table, userId: userId, since: since)
        var pulled = 0, removed = 0, highWater = since
        var takeRemote: [CloudRow] = []
        for row in rows {
            let rid = singleton ? userId : (row.id ?? "").lowercased()
            let local = locals.first { $0.id == rid }
            let remoteHash = MergeRules.hash(row.payload.data)
            let rcu = ISO.date(row.client_updated_at) ?? .distantPast
            let decision = MergeRules.decide(localHash: local?.hash, local: entries[rid], remoteHash: remoteHash, remoteClientUpdatedAt: rcu, remoteDeleted: row.deleted_at != nil)
            switch decision {
            case .takeRemote: takeRemote.append(row); entries[rid] = LedgerEntry(hash: remoteHash, changedAt: rcu, syncedAt: now); pulled += 1
            case .deleteLocal: if local != nil { applyDelete(table: table, id: rid); removed += 1 }; entries[rid] = nil
            case .pushLocal, .keepLocal, .nothing:
                if decision == .nothing, let l = local { entries[rid] = LedgerEntry(hash: l.hash, changedAt: entries[rid]?.changedAt ?? now, syncedAt: now) }
            }
            if let u = ISO.date(row.updated_at), highWater == nil || u > highWater! { highWater = u }
        }
        if !takeRemote.isEmpty {
            let applied = applyRemote(table: table, rows: takeRemote)
            // The ledger keeps the hash of the record as THIS phone encodes it, so a payload the server re-formatted
            // (number formatting, key order) does not look like a local change and is not pushed back on every sync.
            let after = localSets()[table] ?? []
            for r in takeRemote {
                let rid = singleton ? userId : (r.id ?? "").lowercased()
                let rcu = ISO.date(r.client_updated_at) ?? now
                if applied.contains(rid), let l = after.first(where: { $0.id == rid }) {
                    entries[rid] = LedgerEntry(hash: l.hash, changedAt: rcu, syncedAt: now)
                } else if singleton, let l = after.first(where: { $0.id == rid }) {
                    // unreadable profile/settings row (newer app version): keep ours locally, do not overwrite the server
                    entries[rid] = LedgerEntry(hash: l.hash, changedAt: MergeRules.neverChanged, syncedAt: now)
                } else {
                    // not applied (duplicate of a local record, unreadable payload): forgotten, so it is neither
                    // re-uploaded nor tombstoned (a tombstone would delete it for the device that created it)
                    entries[rid] = nil
                }
            }
        }
        if let hw = highWater { ledger.lastPull[table] = hw }
        // 3. push local records whose hash is not confirmed, and tombstones for records the ledger knew but the phone no longer has
        let fresh = localSets()[table] ?? []
        var upserts: [CloudRow] = []
        for l in fresh where entries[l.id]?.syncedAt == nil || entries[l.id]?.hash != l.hash {
            var e = entries[l.id] ?? LedgerEntry(hash: l.hash, changedAt: now, syncedAt: nil)
            if e.changedAt == MergeRules.neverChanged { e.changedAt = now; entries[l.id] = e }   // first upload of the guest's profile/settings
            upserts.append(CloudRow(id: singleton ? nil : l.id, user_id: userId, source_id: l.sourceId, started_at: l.startedAt.map(ISO.string),
                                    day: l.day.map { Self.dayString($0) }, payload: AnyCodableJSON(data: l.data), client_updated_at: ISO.string(e.changedAt), updated_at: nil, deleted_at: nil))
        }
        var tombstones: [CloudRow] = []
        if !singleton {
            for id in MergeRules.tombstoneIds(ledger: entries, localIds: Set(fresh.map(\.id))) {
                let needsStart = table == "rides" || table == "strength_sessions"
                tombstones.append(CloudRow(id: id, user_id: userId, source_id: nil, started_at: needsStart ? ISO.string(now) : nil, day: table == "plans" ? Self.dayString(now) : nil,
                                           payload: AnyCodableJSON(data: Data("{}".utf8)), client_updated_at: ISO.string(now), updated_at: nil, deleted_at: ISO.string(now)))
            }
        }
        for chunk in MergeRules.batches(upserts) { try await api.upsert(table: table, rows: chunk, conflict: singleton ? "user_id" : "id") }
        for chunk in MergeRules.batches(tombstones) { try await api.upsert(table: table, rows: chunk, conflict: "id") }
        for l in fresh where upserts.contains(where: { singleton || $0.id == l.id }) { entries[l.id] = LedgerEntry(hash: l.hash, changedAt: entries[l.id]?.changedAt ?? now, syncedAt: now) }
        for t in tombstones { if let i = t.id { entries[i] = nil } }
        ledger.records[table] = entries
        return (upserts.count, pulled, removed)
    }

    /// Applies pulled rows to the store; returns the ids that were actually applied.
    @discardableResult
    private func applyRemote(table: String, rows: [CloudRow]) -> Set<String> {
        var applied = Set<String>()
        func key(_ id: UUID) -> String { id.uuidString.lowercased() }
        switch table {
        case "rides":
            var rides = store.rides
            for r in rows { guard let v = try? dec.decode(RideRecord.self, from: r.payload.data) else { continue }
                if let i = rides.firstIndex(where: { $0.id == v.id }) { rides[i] = v; applied.insert(key(v.id)) } else if !MergeRules.isDuplicateRide(v, in: rides) { rides.append(v); applied.insert(key(v.id)) } }
            store.rides = rides.sorted { $0.start > $1.start }
        case "strength_sessions":
            var s = store.strength
            for r in rows { guard let v = try? dec.decode(StrengthSession.self, from: r.payload.data) else { continue }
                if let i = s.firstIndex(where: { $0.id == v.id }) { s[i] = v; applied.insert(key(v.id)) } else if !MergeRules.isDuplicateStrength(v, in: s) { s.append(v); applied.insert(key(v.id)) } }
            store.strength = s.sorted { $0.date > $1.date }
        case "templates":
            var t = store.templates
            for r in rows { guard let v = try? dec.decode(WorkoutTemplate.self, from: r.payload.data) else { continue }
                if let i = t.firstIndex(where: { $0.id == v.id }) { t[i] = v } else { t.append(v) }; applied.insert(key(v.id)) }
            store.templates = t
        case "plans":
            var p = store.plan
            for r in rows { guard let v = try? dec.decode(Workout.self, from: r.payload.data) else { continue }
                if let i = p.firstIndex(where: { $0.id == v.id }) { p[i] = v } else { p.append(v) }; applied.insert(key(v.id)) }
            store.plan = p.sorted { $0.date < $1.date }
        case "profiles":
            if let r = rows.last, let v = try? dec.decode(RiderProfile.self, from: r.payload.data) { store.profile = v; applied.insert(r.user_id.lowercased()) }
        case "settings":
            if let r = rows.last, let v = try? dec.decode(SettingsBundle.self, from: r.payload.data) { v.apply(to: store); applied.insert(r.user_id.lowercased()) }
        default: break
        }
        return applied
    }
    private func applyDelete(table: String, id: String) {
        switch table {
        case "rides": store.rides.removeAll { $0.id.uuidString.lowercased() == id }
        case "strength_sessions": store.strength.removeAll { $0.id.uuidString.lowercased() == id }
        case "templates": store.templates.removeAll { $0.id.uuidString.lowercased() == id }
        case "plans": store.plan.removeAll { $0.id.uuidString.lowercased() == id }
        default: break
        }
    }

    private func saveLedger() { if let d = try? enc.encode(ledger) { try? d.write(to: ledgerURL, options: .atomic) } }
    /// Called when the account is deleted or the phone wiped.
    func reset() { ledger = SyncLedger(); saveLedger(); state = CloudConfig.isConfigured ? (account.state.isSignedIn ? .idle : .off) : .off; lastSuccess = nil; lastDetail = "" }
    static func dayString(_ d: Date) -> String { let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.timeZone = .current; return f.string(from: d) }
}

/// The per-user settings that travel together (one row).
struct SettingsBundle: Codable {
    var settings: AppSettings
    var availability: WeeklyAvailability?
    var weekdayRoutines: [Int: UUID]
    var equipment: EquipmentProfile
    var tiles: [String]
    init(store: Store) { settings = store.settings; availability = store.availability; weekdayRoutines = store.weekdayRoutines; equipment = store.equipment; tiles = store.tiles }
    @MainActor func apply(to store: Store) {
        store.settings = settings; store.availability = availability; store.weekdayRoutines = weekdayRoutines; store.equipment = equipment; store.tiles = tiles
    }
}

/// PostgREST over URLSession with the user's JWT; row-level security does the rest.
struct REST {
    let base: URL; let key: String; let token: String
    func pull(table: String, userId: String, since: Date?) async throws -> [CloudRow] {
        var c = URLComponents(url: base.appendingPathComponent("rest/v1/\(table)"), resolvingAgainstBaseURL: false)!
        var q = [URLQueryItem(name: "select", value: "*"), URLQueryItem(name: "user_id", value: "eq.\(userId)"), URLQueryItem(name: "order", value: "updated_at.asc"), URLQueryItem(name: "limit", value: "1000")]
        if let since { q.append(URLQueryItem(name: "updated_at", value: "gt.\(ISO.string(since))")) }
        c.queryItems = q
        var r = URLRequest(url: c.url!); r.httpMethod = "GET"; headers(&r)
        let (d, resp) = try await URLSession.shared.data(for: r)
        try check(resp, d)
        return try JSONDecoder().decode([CloudRow].self, from: d)
    }
    func upsert(table: String, rows: [CloudRow], conflict: String) async throws {
        var c = URLComponents(url: base.appendingPathComponent("rest/v1/\(table)"), resolvingAgainstBaseURL: false)!
        c.queryItems = [URLQueryItem(name: "on_conflict", value: conflict)]
        var r = URLRequest(url: c.url!); r.httpMethod = "POST"; headers(&r)
        r.setValue("resolution=merge-duplicates,return=minimal", forHTTPHeaderField: "Prefer")
        r.httpBody = try JSONEncoder().encode(rows)
        let (d, resp) = try await URLSession.shared.data(for: r)
        try check(resp, d)
    }
    private func headers(_ r: inout URLRequest) {
        r.setValue(key, forHTTPHeaderField: "apikey"); r.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        r.setValue("application/json", forHTTPHeaderField: "Content-Type"); r.setValue("application/json", forHTTPHeaderField: "Accept")
        r.timeoutInterval = 30
    }
    private func check(_ resp: URLResponse, _ d: Data) throws {
        guard let h = resp as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        guard (200..<300).contains(h.statusCode) else {
            let msg = (try? JSONSerialization.jsonObject(with: d) as? [String: Any])?["message"] as? String ?? String(data: d.prefix(200), encoding: .utf8) ?? ""
            throw NSError(domain: "sync", code: h.statusCode, userInfo: [NSLocalizedDescriptionKey: "Server \(h.statusCode): \(msg)"])
        }
    }
}
