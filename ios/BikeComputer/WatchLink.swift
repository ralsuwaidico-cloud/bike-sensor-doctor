import Foundation
import WatchConnectivity

/// iPhone side of the iPhone <-> Apple Watch connection (WatchConnectivity).
/// Phase 0: reports whether a watch is paired, whether the Watch app is installed and reachable,
/// and measures a ping round trip. Nothing here is simulated: every value comes from WCSession.
final class WatchLink: NSObject, ObservableObject, WCSessionDelegate {
    @Published private(set) var supported = WCSession.isSupported()
    @Published private(set) var activated = false
    @Published private(set) var paired = false
    @Published private(set) var appInstalled = false
    @Published private(set) var reachable = false
    @Published private(set) var lastResult = "Not tested yet"
    @Published private(set) var watchBuild: String?

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
        guard session.activationState == .activated else {
            lastResult = "Connection not ready yet"
            return
        }
        guard session.isReachable else {
            lastResult = "Watch app not reachable. Open BikeComputer on the watch and try again."
            return
        }
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

    // MARK: WCSessionDelegate

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        refresh(session)
        if let error {
            DispatchQueue.main.async { self.lastResult = "Activation failed: \(error.localizedDescription)" }
        }
    }

    func sessionDidBecomeInactive(_ session: WCSession) { refresh(session) }

    func sessionDidDeactivate(_ session: WCSession) {
        // The user switched to another watch: activate again for the new one.
        session.activate()
    }

    func sessionReachabilityDidChange(_ session: WCSession) { refresh(session) }

    func sessionWatchStateDidChange(_ session: WCSession) { refresh(session) }
}
