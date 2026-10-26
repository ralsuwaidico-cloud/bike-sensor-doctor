import Foundation
import WatchConnectivity

/// Watch side of the iPhone <-> Apple Watch connection: answers the connectivity test, receives the phone's ride mirror
/// (1 Hz while reachable, application context otherwise) and sends ride commands from the wrist.
final class PhoneLink: NSObject, ObservableObject, WCSessionDelegate {
    struct RideMirror: Equatable {
        var state = "idle", owner = "none"
        var elapsed = 0, dist = 0
        var power: Int?, cad: Int?, hr: Int?, hrSrc: String?, zone: Int?
        var boardReady = false
        var phoneBuild: String?
        var receivedAt = Date.distantPast
        var isFresh: Bool { Date().timeIntervalSince(receivedAt) < 5 }
        var active: Bool { state == "running" || state == "paused" }
        var ownerText: String { switch owner { case "board": return "on the board"; case "phone": return "on the phone"; default: return boardReady ? "board ready" : "not recording" } }
    }

    @Published private(set) var activated = false
    @Published private(set) var reachable = false
    @Published private(set) var pingsAnswered = 0
    @Published private(set) var ride = RideMirror()
    @Published private(set) var lastCommand = ""
    /// Version handshake: the iPhone app's build as it reports it in the ride mirror.
    @Published private(set) var phoneBuild: String?
    var versionMismatch: Bool { if let p = phoneBuild { return WatchVersion.compare(phone: p, watch: AppInfo.label) == .watchOlder } else { return false } }

    func activate() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        if session.delegate == nil { session.delegate = self }
        if session.activationState != .activated { session.activate() }
        refresh(session)
    }

    /// "start" | "pause" | "resume" | "end" | "endConfirm" — the phone applies the one-owner rules and the mirror shows the result.
    func send(command c: String) {
        guard WCSession.isSupported(), WCSession.default.activationState == .activated, WCSession.default.isReachable else { lastCommand = "phone not reachable"; return }
        WCSession.default.sendMessage(WatchMessage.makeCommand(c), replyHandler: nil) { [weak self] e in DispatchQueue.main.async { self?.lastCommand = "failed: \(e.localizedDescription)" } }
        lastCommand = c
    }

    private func refresh(_ session: WCSession) {
        DispatchQueue.main.async {
            self.activated = session.activationState == .activated
            self.reachable = session.isReachable
        }
        // tell the phone which watch build is installed (and the Health permission state) — survives app restarts
        if session.activationState == .activated {
            try? session.updateApplicationContext(WatchMessage.makeWatchInfo(build: AppInfo.label, workoutAuth: WorkoutManager.shared.workoutWriteStatus))
        }
    }

    private func apply(_ m: [String: Any]) {
        guard m[WatchMessage.kind] as? String == WatchMessage.ride else { return }
        var r = RideMirror()
        r.state = m[WatchMessage.state] as? String ?? "idle"; r.owner = m[WatchMessage.owner] as? String ?? "none"
        r.elapsed = m[WatchMessage.elapsed] as? Int ?? 0; r.dist = m[WatchMessage.dist] as? Int ?? 0
        r.power = m[WatchMessage.power] as? Int; r.cad = m[WatchMessage.cad] as? Int; r.hr = m[WatchMessage.hr] as? Int
        r.hrSrc = m[WatchMessage.hrSrc] as? String; r.zone = m[WatchMessage.zone] as? Int
        r.boardReady = m[WatchMessage.boardReady] as? Bool ?? false
        r.phoneBuild = m[WatchMessage.phoneBuild] as? String
        r.receivedAt = Date()
        DispatchQueue.main.async { self.ride = r; if let b = r.phoneBuild { self.phoneBuild = b } }
    }

    // MARK: WCSessionDelegate
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) { refresh(session) }
    func sessionReachabilityDidChange(_ session: WCSession) { refresh(session) }
    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) { apply(message) }
    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) { apply(applicationContext) }
    func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        guard message[WatchMessage.kind] as? String == WatchMessage.ping else { apply(message); replyHandler([:]); return }
        replyHandler(WatchMessage.makePong(for: message, build: AppInfo.label))
        DispatchQueue.main.async { self.pingsAnswered += 1 }
    }
}
