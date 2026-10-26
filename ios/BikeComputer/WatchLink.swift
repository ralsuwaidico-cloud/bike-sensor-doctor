import Foundation
import WatchConnectivity

/// iPhone side of the iPhone <-> Apple Watch connection (WatchConnectivity).
/// Reports pairing/reachability, measures a ping round trip, and relays the watch's live heart rate to the board with
/// its source (Apple Watch) and the sample time. A reading older than 6 s is never shown or forwarded.
final class WatchLink: NSObject, ObservableObject, WCSessionDelegate {
    @Published private(set) var supported = WCSession.isSupported()
    @Published private(set) var activated = false
    @Published private(set) var paired = false
    @Published private(set) var appInstalled = false
    @Published private(set) var reachable = false
    @Published private(set) var lastResult = "Not tested yet"
    @Published private(set) var watchBuild: String?
    @Published private(set) var hrBpm: Int?
    @Published private(set) var hrAt: Date?
    @Published private(set) var workoutState = "idle"
    @Published private(set) var watchBattery: Int?
    @Published private(set) var hrReceived = 0

    weak var device: DeviceLink?
    /// Ride commands from the wrist ("start", "pause", "resume", "end", "endConfirm"); the app maps them to the one-owner rules.
    var onCommand: ((String) -> Void)?
    private var lastContextAt: Date?

    var hrIsFresh: Bool { guard let t = hrAt else { return false }; return Date().timeIntervalSince(t) < 6 }

    func activate() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        if session.delegate == nil { session.delegate = self }
        if session.activationState != .activated { session.activate() }
        refresh(session)
    }

    func ping() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated else { lastResult = "Connection not ready yet"; return }
        guard session.isReachable else { lastResult = "Watch app not reachable. Open Cyclift on the watch and try again."; return }
        lastResult = "Sending…"
        session.sendMessage(WatchMessage.makePing(), replyHandler: { [weak self] reply in
            let ms = WatchMessage.roundTripMs(of: reply)
            let build = reply[WatchMessage.build] as? String
            DispatchQueue.main.async {
                self?.watchBuild = build
                self?.lastResult = ms.map { "Watch replied in \($0) ms" } ?? "Watch sent an unexpected reply"
            }
        }, errorHandler: { [weak self] error in
            DispatchQueue.main.async { self?.lastResult = "Failed: \(error.localizedDescription)" }
        })
    }

    private func refresh(_ session: WCSession) {
        let update = {
            self.activated = session.activationState == .activated
            self.paired = session.isPaired
            self.appInstalled = session.isWatchAppInstalled
            self.reachable = session.isReachable
        }
        if Thread.isMainThread { update() } else { DispatchQueue.main.async(execute: update) }
    }

    /// Mirror of the phone's ride for the watch: live message when reachable, application context (≤ every 10 s) otherwise.
    func sendRide(_ m: [String: Any]) {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated else { return }
        if session.isReachable { session.sendMessage(m, replyHandler: nil, errorHandler: nil) }
        else if lastContextAt == nil || Date().timeIntervalSince(lastContextAt!) > 10 { lastContextAt = Date(); try? session.updateApplicationContext(m) }
    }

    private func handle(_ message: [String: Any]) {
        if message[WatchMessage.kind] as? String == WatchMessage.cmd, let c = message[WatchMessage.cmdKey] as? String {
            DispatchQueue.main.async { self.onCommand?(c) }
            return
        }
        guard message[WatchMessage.kind] as? String == WatchMessage.hr else { return }
        let bpm = message[WatchMessage.bpm] as? Int
        let at = (message[WatchMessage.at] as? Double).map { Date(timeIntervalSince1970: $0) } ?? Date()
        let state = message[WatchMessage.workout] as? String ?? "idle"
        let batt = message[WatchMessage.battery] as? Int
        DispatchQueue.main.async {
            self.workoutState = state
            self.watchBattery = batt
            if let b = bpm, b >= 25, b <= 250, Date().timeIntervalSince(at) < 6 {
                self.hrBpm = b; self.hrAt = at; self.hrReceived += 1
                self.device?.send(heartRate: b, source: .appleWatch, sampledAt: at)
            } else {
                self.hrBpm = nil
            }
        }
    }

    // MARK: WCSessionDelegate
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        refresh(session)
        if let error { DispatchQueue.main.async { self.lastResult = "Activation failed: \(error.localizedDescription)" } }
    }
    func sessionDidBecomeInactive(_ session: WCSession) { refresh(session) }
    func sessionDidDeactivate(_ session: WCSession) { session.activate() }
    func sessionReachabilityDidChange(_ session: WCSession) { refresh(session) }
    func sessionWatchStateDidChange(_ session: WCSession) { refresh(session) }
    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) { handle(message) }
    func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) { handle(message); replyHandler([:]) }
}
