import Foundation

/// Version and build information shared by the iPhone and Apple Watch apps.
enum AppInfo {
    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
    }

    static var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
    }

    /// "0.1.0 (12)"
    static var label: String { "\(version) (\(build))" }
}

/// Messages exchanged between the iPhone app and the Watch app over WatchConnectivity.
/// Phase 0 only carries a connectivity test ("ping"); heart rate and workout state come in Phase 3.
enum WatchMessage {
    static let kind = "kind"
    static let ping = "ping"
    static let pong = "pong"
    static let sentAt = "sentAt"
    static let build = "build"
    /// live heart rate from the watch workout: {kind: "hr", bpm: Int, at: Double (epoch s), workout: String}
    static let hr = "hr"
    static let bpm = "bpm"
    static let at = "at"
    static let workout = "workout"          /* "idle" | "running" | "paused" | "ended" */
    static let battery = "battery"
    /// phone → watch, 1 Hz while the watch is reachable: the ride mirror {kind: "ride", state, owner, elapsed, dist, power?, cad?, hr?, hrSrc?, zone?}
    static let ride = "ride"
    static let state = "state"            /* "idle" | "running" | "paused" | "ended" */
    static let owner = "owner"            /* "none" | "board" | "phone" */
    static let elapsed = "elapsed"        /* Int seconds */
    static let dist = "dist"              /* Int metres */
    static let power = "power"
    static let cad = "cad"
    static let hrSrc = "hrSrc"
    static let zone = "zone"
    static let boardReady = "boardReady"  /* Bool: a connected board with live data would be the recorder */
    /// watch → phone: {kind: "cmd", cmd: "start" | "pause" | "resume" | "end" | "endConfirm"}
    static let cmd = "cmd"
    static let cmdKey = "cmd"
    static let cmdStart = "start", cmdPause = "pause", cmdResume = "resume", cmdEnd = "end", cmdEndConfirm = "endConfirm"

    static func makeRide(state: String, owner: String, elapsed: Int, dist: Int, power: Int?, cad: Int?, hr: Int?, hrSrc: String?, zone: Int?, boardReady: Bool) -> [String: Any] {
        var m: [String: Any] = [kind: ride, WatchMessage.state: state, WatchMessage.owner: owner, WatchMessage.elapsed: elapsed, WatchMessage.dist: dist, WatchMessage.boardReady: boardReady]
        if let p = power { m[WatchMessage.power] = p }
        if let c = cad { m[WatchMessage.cad] = c }
        if let h = hr { m[WatchMessage.hr] = h }
        if let s = hrSrc { m[WatchMessage.hrSrc] = s }
        if let z = zone { m[WatchMessage.zone] = z }
        return m
    }
    static func makeCommand(_ c: String) -> [String: Any] { [kind: cmd, cmdKey: c] }

    static func makeHR(bpm: Int, at: Date, workout: String, battery: Int?, build appBuild: String? = nil) -> [String: Any] {
        var m: [String: Any] = [kind: hr, WatchMessage.bpm: bpm, WatchMessage.at: at.timeIntervalSince1970, WatchMessage.workout: workout]
        if let b = battery { m[WatchMessage.battery] = b }
        if let v = appBuild { m[WatchMessage.build] = v }
        return m
    }

    /// watch → phone application context, sent on every activation: {kind: "watchInfo", build: "1.0.0 (65)", hkWorkoutAuth: "allowed"|"denied"|"not asked"}
    /// so the phone knows the installed watch build without a ping (version handshake).
    static let watchInfo = "watchInfo"
    static let hkWorkoutAuth = "hkWorkoutAuth"
    /// phone → watch, inside the ride mirror: the phone's build, so the watch can say "update this watch app".
    static let phoneBuild = "phoneBuild"
    static func makeWatchInfo(build appBuild: String, workoutAuth: String) -> [String: Any] { [kind: watchInfo, build: appBuild, hkWorkoutAuth: workoutAuth] }

    static func makePing(now: Date = Date()) -> [String: Any] {
        [kind: ping, sentAt: now.timeIntervalSince1970]
    }

    static func makePong(for message: [String: Any], build appBuild: String) -> [String: Any] {
        var reply: [String: Any] = [kind: pong, WatchMessage.build: appBuild]
        if let t = message[sentAt] as? Double { reply[sentAt] = t }
        return reply
    }

    /// Round-trip time in milliseconds for a pong, or nil when the reply is not a valid pong.
    static func roundTripMs(of reply: [String: Any], now: Date = Date()) -> Int? {
        guard reply[kind] as? String == pong, let t = reply[sentAt] as? Double else { return nil }
        let ms = (now.timeIntervalSince1970 - t) * 1000
        guard ms >= 0, ms < 120_000 else { return nil }
        return Int(ms.rounded())
    }
}

/// Live heart-rate payload the watch sends through the MIRRORED HealthKit workout session
/// (HKWorkoutSession.sendToRemoteWorkoutSession(data:) → iPhone workoutSession(_:didReceiveDataFromRemoteWorkoutSession:)),
/// and — with the same fields — as a WatchConnectivity message when the phone app is reachable. Compact JSON.
/// `at` is the HealthKit sample time (epoch seconds), the key for de-duplication on the phone.
struct WatchHRPayload: Codable, Equatable {
    var v = 1
    var bpm: Int?            /* nil = state-only message (no reading) */
    var at: Double
    var state: String        /* "idle" | "running" | "paused" | "ended" */
    var build: String
    var battery: Int?
    var seq: Int

    func encoded() -> Data? { try? JSONEncoder().encode(self) }
    static func decode(_ d: Data) -> WatchHRPayload? {
        guard let p = try? JSONDecoder().decode(WatchHRPayload.self, from: d), p.v == 1 else { return nil }
        return p
    }
}

/// Version handshake between the iPhone app and the Watch app. Both are built from one project with the same
/// MARKETING_VERSION / CURRENT_PROJECT_VERSION, so any difference means one side was not updated (TestFlight installs the
/// watch app only when the watch's automatic app install is on, or the rider installs it in the iPhone Watch app).
enum WatchVersion {
    /// "1.0.0 (64)" → 64. nil when the label carries no build number.
    static func buildNumber(_ label: String?) -> Int? {
        guard let l = label, let open = l.lastIndex(of: "("), let close = l.lastIndex(of: ")"), open < close else { return nil }
        return Int(l[l.index(after: open)..<close].trimmingCharacters(in: .whitespaces))
    }
    enum Comparison: Equatable { case unknown, same, watchOlder, watchNewer }
    static func compare(phone: String, watch: String?) -> Comparison {
        guard let w = watch, !w.isEmpty, w != "? (?)" else { return .unknown }
        if w == phone { return .same }
        if let pb = buildNumber(phone), let wb = buildNumber(w) { return wb < pb ? .watchOlder : wb > pb ? .watchNewer : .same }
        return .watchOlder
    }
    static let updateInstruction = "Update the Watch app: Watch app on iPhone › Cyclift › Update/Install"
}
