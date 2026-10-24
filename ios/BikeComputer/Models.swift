import Foundation
import Combine

// MARK: - Rider profile (mirrors the board's bc_profile fields that matter to the app)
struct RiderProfile: Codable, Equatable {
    enum Goal: String, Codable, CaseIterable { case stronger, endurance, progress
        var title: String { switch self { case .stronger: return "Get stronger"; case .endurance: return "Ride longer"; case .progress: return "Measure progress" } }
        var hint: String { switch self { case .stronger: return "more power at the same effort"; case .endurance: return "aerobic base, Zone 2"; case .progress: return "see real change, no guesswork" } } }
    enum Level: String, Codable, CaseIterable { case beginner, intermediate, advanced
        var title: String { rawValue.capitalized }
        var hint: String { switch self { case .beginner: return "new to training with power"; case .intermediate: return "ride regularly, some structure"; case .advanced: return "years of structured training" } }
        /// Starting-assumption W/kg, same table as the board (bc_exp_wkg_x100): 1.75 / 3.0 / 4.0
        var wkg: Double { switch self { case .beginner: return 1.75; case .intermediate: return 3.0; case .advanced: return 4.0 } } }
    enum FTPHow: String, Codable { case assumed, fromRides, entered
        var label: String { switch self { case .assumed: return "provisional"; case .fromRides: return "from rides"; case .entered: return "entered" } } }

    var name = ""
    var goal: Goal = .endurance
    var hoursPerWeek = 5
    var level: Level = .intermediate
    var weightKg = 75.0
    var heightCm: Int? = nil
    var maxHR: Int? = nil
    var age = 35
    var ftpW: Int = 225
    var ftpHow: FTPHow = .assumed
    var hrPrefWatchFirst = false

    var estimatedMaxHR: Int { maxHR ?? Int((208.0 - 0.7 * Double(age)).rounded()) }
    mutating func refreshAssumption() { if ftpHow == .assumed { ftpW = Int((weightKg * level.wkg).rounded()) } }
    /// Coggan zones from FTP: 55/75/90/105/120/150 %
    var powerZones: [(lo: Int, hi: Int?)] {
        let f = Double(ftpW); let b = [0.55, 0.75, 0.90, 1.05, 1.20, 1.50].map { Int((f * $0).rounded()) }
        return [(0, b[0]), (b[0], b[1]), (b[1], b[2]), (b[2], b[3]), (b[3], b[4]), (b[4], b[5]), (b[5], nil)]
    }
    func zone(forWatts w: Int) -> Int { for (i, z) in powerZones.enumerated() where w < (z.hi ?? Int.max) { return i + 1 }; return 7 }
}

// MARK: - Plan
enum WorkoutKind: String, Codable, CaseIterable {
    case endurance, tempo, threshold, vo2, recovery, long, ftpTest, strength, mobility, other, recoveryDay, rest
    var title: String { switch self { case .endurance: return "Endurance"; case .tempo: return "Tempo"; case .threshold: return "Threshold"; case .vo2: return "VO2 max"; case .recovery: return "Recovery spin"; case .long: return "Long ride"; case .ftpTest: return "FTP test"; case .strength: return "Strength"; case .mobility: return "Mobility / yoga"; case .other: return "Other activity"; case .recoveryDay: return "Recovery day"; case .rest: return "Rest" } }
    var subtitle: String { switch self { case .endurance: return "Zone 2, steady"; case .tempo: return "Zone 3 blocks"; case .threshold: return "Zone 4 intervals"; case .vo2: return "Zone 5 short efforts"; case .recovery: return "Zone 1, easy"; case .long: return "Zone 2, 2 h+"; case .ftpTest: return "20-minute effort"; case .strength: return "off the bike"; case .mobility: return "off the bike, 20–40 min"; case .other: return "run, swim, hike…"; case .recoveryDay: return "rest + sleep focus"; case .rest: return "no training" } }
    var zone: Int { switch self { case .endurance, .long: return 2; case .tempo: return 3; case .threshold, .ftpTest: return 4; case .vo2: return 5; case .recovery: return 1; default: return 0 } }
    var isRide: Bool { zone > 0 }
    var defaultMinutes: Int { switch self { case .long: return 120; case .tempo: return 75; case .threshold: return 70; case .vo2: return 60; case .recovery: return 45; case .strength, .mobility: return 30; case .other: return 60; case .ftpTest: return 60; case .endurance: return 60; default: return 0 } }
}

struct Workout: Codable, Identifiable, Equatable {
    var id = UUID()
    var date: Date
    var kind: WorkoutKind
    var minutes: Int
    var done = false
    var skipped = false
    var note = ""

    struct Step: Equatable { let name: String; let duration: String; let target: String }
    /// Steps with power targets from the rider's FTP; HR targets appear only when the rider has an HR source (the caller decides).
    func steps(ftp: Int) -> [Step] {
        let z = { (lo: Double, hi: Double) in "\(Int(Double(ftp) * lo))–\(Int(Double(ftp) * hi)) W" }
        switch kind {
        case .endurance: return [.init(name: "Warm-up", duration: "10 min", target: "\(z(0.45, 0.6)) · 85–95 rpm"), .init(name: "Main", duration: "\(max(5, minutes - 15)) min", target: "\(z(0.65, 0.75)) (Z2) · 85–95 rpm"), .init(name: "Cool-down", duration: "5 min", target: "under \(Int(Double(ftp) * 0.5)) W")]
        case .tempo: return [.init(name: "Warm-up", duration: "15 min", target: z(0.5, 0.65)), .init(name: "Block 1", duration: "15 min", target: "\(z(0.84, 0.9)) (Z3) · 85–90 rpm"), .init(name: "Easy", duration: "10 min", target: "\(Int(Double(ftp) * 0.55)) W"), .init(name: "Block 2", duration: "15 min", target: "\(z(0.84, 0.9)) (Z3)"), .init(name: "Cool-down", duration: "10 min", target: "under \(Int(Double(ftp) * 0.5)) W")]
        case .threshold: return [.init(name: "Warm-up", duration: "15 min", target: z(0.5, 0.65)), .init(name: "3 × 8 min", duration: "24 min", target: "\(z(0.93, 1.02)) (Z4) · 3 min easy between"), .init(name: "Cool-down", duration: "10 min", target: "under \(Int(Double(ftp) * 0.5)) W")]
        case .vo2: return [.init(name: "Warm-up", duration: "15 min", target: z(0.5, 0.65)), .init(name: "5 × 3 min", duration: "15 min", target: "\(z(1.06, 1.18)) (Z5) · 3 min easy between"), .init(name: "Cool-down", duration: "10 min", target: "under \(Int(Double(ftp) * 0.5)) W")]
        case .recovery: return [.init(name: "Easy spin", duration: "\(minutes) min", target: "under \(Int(Double(ftp) * 0.58)) W · 90+ rpm")]
        case .long: return [.init(name: "Warm-up", duration: "15 min", target: z(0.5, 0.65)), .init(name: "Main", duration: "\(max(10, minutes - 25)) min", target: "\(z(0.65, 0.75)) (Z2) · eat every 30 min"), .init(name: "Cool-down", duration: "10 min", target: "under \(Int(Double(ftp) * 0.5)) W")]
        case .ftpTest: return [.init(name: "Warm-up", duration: "20 min", target: "with 3 × 1 min fast"), .init(name: "Test", duration: "20 min", target: "as hard as you can hold steady"), .init(name: "Cool-down", duration: "10 min", target: "easy")]
        case .strength: return [.init(name: "Circuit", duration: "3 × 10 min", target: "squats, lunges, plank · bodyweight")]
        case .mobility: return [.init(name: "Flow", duration: "\(minutes) min", target: "hips, back, calves")]
        case .other: return [.init(name: "Activity", duration: "\(minutes) min", target: "counted as training load, not as a ride")]
        case .recoveryDay, .rest: return []
        }
    }
    var why: String {
        switch kind {
        case .endurance: return "Builds the aerobic base. Steady Zone 2 is where most of the adaptation happens."
        case .tempo: return "Two steady tempo blocks raise sustainable power without the fatigue of intervals."
        case .threshold: return "Threshold work moves your FTP; it is placed after steady weeks."
        case .vo2: return "Short hard efforts raise the ceiling; only after the base is in place."
        case .recovery: return "The day after a hard session: light pressure, high cadence."
        case .long: return "Your long ride. Steady Zone 2, eat every 30 minutes."
        case .ftpTest: return "A fresh measurement so the plan uses a real number, not an assumption."
        case .strength: return "Optional. Skip if the legs are heavy."
        case .mobility: return "Keeps you supple between hard days."
        case .other: return "Counts toward your weekly load so the coach does not overload the bike days."
        case .recoveryDay: return "A deliberate recovery day: light movement, early night."
        case .rest: return "Rest is part of the plan: adaptation happens here."
        }
    }
}

/// Deterministic week builder: the rider's hours and level decide the mix. No model involved.
enum PlanEngine {
    static func week(starting monday: Date, profile p: RiderProfile) -> [Workout] {
        let cal = Calendar.current
        let d = { (i: Int) in cal.date(byAdding: .day, value: i, to: monday)! }
        let h = p.hoursPerWeek
        let longMin = min(180, max(60, h * 20))
        let hard: WorkoutKind = p.level == .beginner ? .tempo : (p.goal == .stronger ? .threshold : .tempo)
        var w: [Workout] = [
            Workout(date: d(0), kind: .rest, minutes: 0),
            Workout(date: d(1), kind: .endurance, minutes: 60),
            Workout(date: d(2), kind: hard, minutes: hard.defaultMinutes),
            Workout(date: d(3), kind: h >= 6 ? .endurance : .rest, minutes: h >= 6 ? 60 : 0),
            Workout(date: d(4), kind: .recovery, minutes: 45),
            Workout(date: d(5), kind: .long, minutes: longMin),
            Workout(date: d(6), kind: .strength, minutes: 30)]
        if h <= 3 { w[1].kind = .rest; w[1].minutes = 0; w[4].kind = .rest; w[4].minutes = 0 }
        return w
    }
    static func rideMinutes(_ w: [Workout]) -> Int { w.filter { $0.kind.isRide && !$0.skipped }.reduce(0) { $0 + $1.minutes } }
}

// MARK: - Rides
struct RideRecord: Codable, Identifiable, Equatable {
    enum Recorder: String, Codable { case board, phone }
    var id = UUID()
    var boardRideId: Int? = nil
    var start: Date
    var durationS: Int
    var distanceM: Int
    var avgPower: Int?; var maxPower: Int?; var normalizedPower: Int?
    var avgCadence: Int?
    var avgHR: Int?; var maxHR: Int?
    var kj: Int?
    var zoneSeconds: [Int] = Array(repeating: 0, count: 7)
    var recorder: Recorder
    var sources: [String]
    var demo = false
    var samples: [Sample] = []      /* 1 Hz, kept for graphs; nil fields = no data that second */
    struct Sample: Codable, Equatable { var t: Int; var w: Int?; var cad: Int?; var hr: Int?; var speedCms: Int?; var lat: Double?; var lon: Double?; var alt: Double? }

    var title: String { recorder == .phone ? "Ride (phone only)" : "Ride" }
    var recordedBy: String { recorder == .board ? "BikeComputer" : "this phone" }
    var hasPower: Bool { avgPower != nil }
    var hasTrack: Bool { samples.contains { $0.lat != nil } }
}

// MARK: - Settings
struct AppSettings: Codable, Equatable {
    enum Units: String, Codable, CaseIterable { case metric, imperial; var title: String { self == .metric ? "km, m" : "mi, ft" } }
    enum HRPref: String, Codable, CaseIterable { case strap, watch
        var title: String { self == .strap ? "Strap / band via BikeComputer first" : "Apple Watch first" } }
    var units: Units = .metric
    /// Phone-only mode: the phone records even when a BikeComputer is connected (its live values are still shown).
    var phoneOnlyMode = false
    var hrPref: HRPref = .strap
    var keepScreenOn = true
}

// MARK: - Store (local JSON file with a schema version; cloud sync comes with the account service)
/// One file `store.json` in Application Support. `schema` lets a future build migrate instead of dropping data; build 15
/// writes schema 1 and still imports the build-14 per-file layout (profile.json / plan.json / rides.json / tiles.json).
struct StoreFile: Codable, Equatable {
    static let currentSchema = 1
    var schema = StoreFile.currentSchema
    var profile = RiderProfile()
    var settings = AppSettings()
    var plan: [Workout] = []
    var rides: [RideRecord] = []
    var tiles: [String] = Store.defaultTiles
    var onboarded = false
    var guest = true
    var appleUserId: String? = nil
    var createdAt = Date()

    init(schema: Int = StoreFile.currentSchema, profile: RiderProfile = RiderProfile(), settings: AppSettings = AppSettings(), plan: [Workout] = [], rides: [RideRecord] = [], tiles: [String] = Store.defaultTiles, onboarded: Bool = false, guest: Bool = true, appleUserId: String? = nil, createdAt: Date = Date()) {
        self.schema = schema; self.profile = profile; self.settings = settings; self.plan = plan; self.rides = rides; self.tiles = tiles
        self.onboarded = onboarded; self.guest = guest; self.appleUserId = appleUserId; self.createdAt = createdAt
    }

    /// Tolerant decoding: a key missing from an older file takes its default instead of failing the whole load.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schema = try c.decodeIfPresent(Int.self, forKey: .schema) ?? 1
        profile = try c.decodeIfPresent(RiderProfile.self, forKey: .profile) ?? RiderProfile()
        settings = try c.decodeIfPresent(AppSettings.self, forKey: .settings) ?? AppSettings()
        plan = try c.decodeIfPresent([Workout].self, forKey: .plan) ?? []
        rides = try c.decodeIfPresent([RideRecord].self, forKey: .rides) ?? []
        tiles = try c.decodeIfPresent([String].self, forKey: .tiles) ?? Store.defaultTiles
        onboarded = try c.decodeIfPresent(Bool.self, forKey: .onboarded) ?? false
        guest = try c.decodeIfPresent(Bool.self, forKey: .guest) ?? true
        appleUserId = try c.decodeIfPresent(String.self, forKey: .appleUserId)
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
    }

    /// Migration entry point. Unknown (newer) schemas are kept as they are; older ones are upgraded step by step.
    static func migrate(_ f: StoreFile) -> StoreFile {
        var f = f
        if f.schema < 1 { f.schema = 1 }          /* schema 0 never shipped; placeholder for the pattern */
        if f.tiles.isEmpty { f.tiles = Store.defaultTiles }
        if f.rides.contains(where: { $0.zoneSeconds.count != 7 }) { for i in f.rides.indices where f.rides[i].zoneSeconds.count != 7 { f.rides[i].zoneSeconds = Array(repeating: 0, count: 7) } }
        return f
    }
}

final class Store: ObservableObject {
    static let defaultTiles = ["power", "cadence", "hr", "speed", "time", "dist"]
    @Published var profile = RiderProfile() { didSet { persist() } }
    @Published var settings = AppSettings() { didSet { persist() } }
    @Published var onboarded = false { didSet { persist() } }
    @Published var guest = true { didSet { persist() } }
    @Published var appleUserId: String? { didSet { persist() } }
    @Published var plan: [Workout] = [] { didSet { persist() } }
    @Published var rides: [RideRecord] = [] { didSet { persist() } }
    @Published var tiles: [String] = Store.defaultTiles { didSet { persist() } }
    @Published private(set) var lastSaveError: String?

    let dir: URL
    private var loading = true
    private var createdAt = Date()

    static var defaultDirectory: URL {
        let u = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("BikeComputer", isDirectory: true)
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }

    init(directory: URL = Store.defaultDirectory, generatePlan: Bool = true) {
        dir = directory
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if let f = Self.read(dir.appendingPathComponent("store.json")) { apply(StoreFile.migrate(f)) }
        else if let legacy = legacyImport() { apply(legacy) }
        loading = false
        if generatePlan { ensurePlan() }
        if !FileManager.default.fileExists(atPath: dir.appendingPathComponent("store.json").path) { persist() }
    }

    private func apply(_ f: StoreFile) {
        profile = f.profile; settings = f.settings; plan = f.plan; rides = f.rides; tiles = f.tiles
        onboarded = f.onboarded; guest = f.guest; appleUserId = f.appleUserId; createdAt = f.createdAt
    }

    var snapshot: StoreFile { StoreFile(profile: profile, settings: settings, plan: plan, rides: rides, tiles: tiles, onboarded: onboarded, guest: guest, appleUserId: appleUserId, createdAt: createdAt) }

    /// Build-14 layout: separate JSON files + UserDefaults flags. Imported once, then superseded by store.json.
    private func legacyImport() -> StoreFile? {
        var f = StoreFile(); var any = false
        if let p: RiderProfile = Self.read(dir.appendingPathComponent("profile.json")) { f.profile = p; any = true }
        if let w: [Workout] = Self.read(dir.appendingPathComponent("plan.json")) { f.plan = w; any = true }
        if let r: [RideRecord] = Self.read(dir.appendingPathComponent("rides.json")) { f.rides = r; any = true }
        if let t: [String] = Self.read(dir.appendingPathComponent("tiles.json")) { f.tiles = t; any = true }
        let ud = UserDefaults.standard
        if ud.object(forKey: "bc.onboarded") != nil { f.onboarded = ud.bool(forKey: "bc.onboarded"); any = true }
        if let g = ud.object(forKey: "bc.guest") as? Bool { f.guest = g }
        if let a = ud.string(forKey: "bc.appleUser") { f.appleUserId = a; f.guest = false }
        return any ? f : nil
    }

    func ensurePlan() {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let weekday = (cal.component(.weekday, from: today) + 5) % 7   // Monday = 0
        let monday = cal.date(byAdding: .day, value: -weekday, to: today)!
        if plan.isEmpty || !plan.contains(where: { cal.isDate($0.date, inSameDayAs: today) }) {
            // keep history of past workouts, generate this week (and next) fresh
            let keep = plan.filter { $0.date < monday }
            plan = keep + PlanEngine.week(starting: monday, profile: profile) + PlanEngine.week(starting: cal.date(byAdding: .day, value: 7, to: monday)!, profile: profile)
        }
    }

    var today: Workout? { plan.first { Calendar.current.isDateInToday($0.date) } }
    func workouts(weekOf date: Date) -> [Workout] {
        let cal = Calendar.current; let d0 = cal.startOfDay(for: date)
        let wd = (cal.component(.weekday, from: d0) + 5) % 7
        let monday = cal.date(byAdding: .day, value: -wd, to: d0)!
        let sunday = cal.date(byAdding: .day, value: 7, to: monday)!
        return plan.filter { $0.date >= monday && $0.date < sunday }.sorted { $0.date < $1.date }
    }
    func update(_ w: Workout) { if let i = plan.firstIndex(where: { $0.id == w.id }) { plan[i] = w } }
    func swapDays(_ a: Workout, _ b: Workout) {
        guard let i = plan.firstIndex(where: { $0.id == a.id }), let j = plan.firstIndex(where: { $0.id == b.id }) else { return }
        let da = plan[i].date; plan[i].date = plan[j].date; plan[j].date = da
    }

    /// Adds a finished ride. Demo rides never enter history; a board ride already imported (same board ride id) is
    /// ignored, so a ride can never appear twice or under two recorders.
    @discardableResult
    func addRide(_ r: RideRecord) -> Bool {
        guard !r.demo else { return false }
        if let b = r.boardRideId, rides.contains(where: { $0.boardRideId == b && $0.recorder == .board }) { return false }
        if rides.contains(where: { $0.id == r.id }) { return false }
        rides.insert(r, at: 0)
        if let t = today, t.kind.isRide, !t.done { var w = t; w.done = true; update(w) }
        return true
    }
    func deleteRide(_ r: RideRecord) { rides.removeAll { $0.id == r.id } }

    /// Weekly totals for Progress (last `weeks` weeks, oldest first).
    struct WeekTotal: Identifiable { var id: Date { monday }; let monday: Date; let minutes: Int; let km: Double; let rides: Int }
    func weekTotals(weeks: Int = 8) -> [WeekTotal] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let wd = (cal.component(.weekday, from: today) + 5) % 7
        let thisMonday = cal.date(byAdding: .day, value: -wd, to: today)!
        return (0..<weeks).reversed().map { k in
            let m = cal.date(byAdding: .day, value: -7 * k, to: thisMonday)!
            let e = cal.date(byAdding: .day, value: 7, to: m)!
            let rs = rides.filter { $0.start >= m && $0.start < e }
            return WeekTotal(monday: m, minutes: rs.reduce(0) { $0 + $1.durationS } / 60, km: Double(rs.reduce(0) { $0 + $1.distanceM }) / 1000, rides: rs.count)
        }
    }

    /// Guideline 5.1.1(v): everything the app stores about the rider can be removed in-app.
    func resetAll() {
        loading = true
        rides = []; plan = []; profile = RiderProfile(); settings = AppSettings(); onboarded = false; guest = true; appleUserId = nil
        tiles = Store.defaultTiles; createdAt = Date()
        loading = false
        for n in ["store.json", "profile.json", "plan.json", "rides.json", "tiles.json"] { try? FileManager.default.removeItem(at: dir.appendingPathComponent(n)) }
        for k in ["bc.onboarded", "bc.guest", "bc.appleUser"] { UserDefaults.standard.removeObject(forKey: k) }
        ensurePlan()
    }

    // MARK: persistence
    private func persist() {
        guard !loading else { return }
        do {
            let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601
            let d = try enc.encode(snapshot)
            try d.write(to: dir.appendingPathComponent("store.json"), options: .atomic)
            lastSaveError = nil
        } catch { lastSaveError = error.localizedDescription }
    }
    private static func read<T: Decodable>(_ url: URL) -> T? {
        guard let d = try? Data(contentsOf: url) else { return nil }
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        if let v = try? dec.decode(T.self, from: d) { return v }
        return try? JSONDecoder().decode(T.self, from: d)      /* build-14 files used the default date encoding */
    }
}

// MARK: - Coach (rules). Deterministic plain-word notes; no model is involved in this build and the UI says "Coach (rules)".
enum Coach {
    static func homeNote(store s: Store, device: DeviceLink?) -> String {
        let last = s.rides.first
        guard let t = s.today else { return "No plan for today." }
        var out = ""
        if let l = last, let p = l.avgPower { out += "Last ride: \(l.durationS / 60) min at \(p) W" + (l.avgHR.map { ", HR \($0)" } ?? "") + ". " }
        else if let l = last { out += "Last ride: \(l.durationS / 60) min, \(String(format: "%.1f", Double(l.distanceM) / 1000)) km (no power data). " }
        else { out += "No rides recorded yet. " }
        switch t.kind {
        case .rest: out += "Today is a rest day."
        case .recoveryDay: out += "Recovery day: light movement, early night."
        default: out += "Today: \(t.kind.title.lowercased()), \(t.minutes) min."
        }
        if s.profile.ftpHow == .assumed { out += " Your FTP is still an assumption; a steady 20-minute effort in a real ride will replace it." }
        return out
    }
    static func rideSummary(_ r: RideRecord, profile p: RiderProfile) -> String {
        guard let avg = r.avgPower else { return "Recorded on the phone without a power meter: distance and time are real, no power analysis is possible. Connect the BikeComputer for watts." }
        let z = p.zone(forWatts: avg)
        var s = "Average \(avg) W is Zone \(z) for your FTP of \(p.ftpW) W (\(p.ftpHow.label))."
        if let hr = r.avgHR { s += String(format: " Efficiency %.2f W per beat.", Double(avg) / Double(hr)) }
        if r.durationS >= 1200, p.ftpHow == .assumed { s += " No qualifying 20-minute effort yet (needs a steady block clearly harder than the rest)." }
        return s
    }
}
