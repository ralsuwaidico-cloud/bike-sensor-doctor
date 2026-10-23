import Foundation
import WatchConnectivity

/// Watch side of the iPhone <-> Apple Watch connection. Answers the iPhone's connectivity test.
final class PhoneLink: NSObject, ObservableObject, WCSessionDelegate {
    @Published private(set) var activated = false
    @Published private(set) var reachable = false
    @Published private(set) var pingsAnswered = 0

    func activate() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        if session.delegate == nil { session.delegate = self }
        if session.activationState != .activated { session.activate() }
        refresh(session)
    }

    private func refresh(_ session: WCSession) {
        DispatchQueue.main.async {
            self.activated = session.activationState == .activated
            self.reachable = session.isReachable
        }
    }

    // MARK: WCSessionDelegate

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        refresh(session)
    }

    func sessionReachabilityDidChange(_ session: WCSession) { refresh(session) }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        guard message[WatchMessage.kind] as? String == WatchMessage.ping else {
            replyHandler([:])
            return
        }
        replyHandler(WatchMessage.makePong(for: message, build: AppInfo.label))
        DispatchQueue.main.async { self.pingsAnswered += 1 }
    }
}
