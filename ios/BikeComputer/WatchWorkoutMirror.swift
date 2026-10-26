import Foundation
import HealthKit

/// iPhone side of Apple's live workout channel (iOS 17 / watchOS 10, WWDC23 "Build a multidevice workout app"):
/// the watch starts its HKWorkoutSession and calls startMirroringToCompanionDevice(); HealthKit then launches this app
/// (also in the background) and hands the MIRRORED session to `workoutSessionMirroringStartHandler`, which must
/// therefore be set at every app launch — this object is created in BikeComputerApp.init via WatchLink.
/// The watch sends each heart-rate sample with sendToRemoteWorkoutSession(data:); it arrives in
/// workoutSession(_:didReceiveDataFromRemoteWorkoutSession:). Unlike WatchConnectivity sendMessage it does not need the
/// phone app in the foreground or "reachable".
///
/// Rules: the mirrored session is never ended, finished or saved here — only the watch's primary session saves (and
/// only when the rider chooses Save), so no duplicate workout can appear in Fitness. HKLiveWorkoutBuilder exists on
/// iOS only from 26, so live values come from the data payloads, not from a builder. After a disconnect the session
/// object is invalid; while the primary session runs, HealthKit reconnects and calls the start handler again with a
/// new session (Apple: HKWorkoutSessionDelegate.workoutSession(_:didDisconnectFromRemoteDeviceWithError:)).
final class WatchWorkoutMirror: NSObject, ObservableObject, HKWorkoutSessionDelegate {
    @Published private(set) var active = false
    @Published private(set) var startedAt: Date?
    @Published private(set) var remoteState = "none"
    @Published private(set) var sessionsReceived = 0
    @Published private(set) var payloads = 0
    @Published private(set) var badPayloads = 0
    @Published private(set) var lastDisconnectAt: Date?
    @Published private(set) var lastDisconnectReason: String?

    var onPayload: ((WatchHRPayload) -> Void)?
    var onEvent: ((String) -> Void)?

    private let store = HKHealthStore()
    private var session: HKWorkoutSession?

    override init() {
        super.init()
        guard HKHealthStore.isHealthDataAvailable() else { return }
        // Set on every launch (foreground or background) so a session mirrored while the app was not running is received.
        store.workoutSessionMirroringStartHandler = { [weak self] s in
            DispatchQueue.main.async { self?.attach(s) }
        }
    }

    private func attach(_ s: HKWorkoutSession) {
        session = s
        s.delegate = self
        active = true
        startedAt = Date()
        sessionsReceived += 1
        remoteState = Self.name(s.state)
        onEvent?("Watch workout mirrored to the iPhone (session \(sessionsReceived))")
    }

    static func name(_ s: HKWorkoutSessionState) -> String {
        switch s {
        case .notStarted: return "idle"; case .prepared: return "prepared"; case .running: return "running"
        case .paused: return "paused"; case .ended: return "ended"; case .stopped: return "stopped"
        @unknown default: return "unknown"
        }
    }

    // MARK: HKWorkoutSessionDelegate (called on a HealthKit queue)
    func workoutSession(_ workoutSession: HKWorkoutSession, didChangeTo toState: HKWorkoutSessionState, from fromState: HKWorkoutSessionState, date: Date) {
        DispatchQueue.main.async {
            self.remoteState = Self.name(toState)
            if toState == .ended { self.active = false; self.session = nil }
        }
    }

    func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        DispatchQueue.main.async { self.onEvent?("Mirrored watch workout error: \(error.localizedDescription)") }
    }

    func workoutSession(_ workoutSession: HKWorkoutSession, didReceiveDataFromRemoteWorkoutSession data: [Data]) {
        let decoded = data.map { WatchHRPayload.decode($0) }
        DispatchQueue.main.async {
            for p in decoded {
                guard let p else { self.badPayloads += 1; continue }
                self.payloads += 1
                self.onPayload?(p)
            }
        }
    }

    func workoutSession(_ workoutSession: HKWorkoutSession, didDisconnectFromRemoteDeviceWithError error: Error?) {
        DispatchQueue.main.async {
            self.active = false
            self.session = nil
            self.lastDisconnectAt = Date()
            self.lastDisconnectReason = error?.localizedDescription ?? "ended by the watch"
            self.onEvent?("Mirrored watch workout disconnected: \(self.lastDisconnectReason ?? "")")
        }
    }
}
