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

    static func makeHR(bpm: Int, at: Date, workout: String, battery: Int?) -> [String: Any] {
        var m: [String: Any] = [kind: hr, WatchMessage.bpm: bpm, WatchMessage.at: at.timeIntervalSince1970, WatchMessage.workout: workout]
        if let b = battery { m[WatchMessage.battery] = b }
        return m
    }

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
