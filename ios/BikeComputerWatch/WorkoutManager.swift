import Foundation
import HealthKit
import WatchConnectivity
#if os(watchOS)
import WatchKit
#endif

/// A real outdoor-cycling workout session on the watch (HKWorkoutSession + HKLiveWorkoutBuilder). The session is what
/// gives live heart rate. Every reading goes to the iPhone with its HealthKit sample time on two channels:
///  1. PRIMARY — the mirrored workout session (watchOS 10 / iOS 17, WWDC23 "Build a multidevice workout app"):
///     startMirroringToCompanionDevice() once the session is prepared/running, then sendToRemoteWorkoutSession(data:)
///     per reading. HealthKit launches the iPhone app in the background if needed; no "reachable" requirement.
///  2. SECONDARY — WatchConnectivity sendMessage, only while the phone app is reachable.
/// The phone de-duplicates by sample time and drops anything older than 6 s, so nothing is ever held or counted twice.
/// A reading is never silently dropped here any more: when neither channel is up the status says so and mirroring is
/// retried (every 10 s while the workout runs).
/// Saving to Apple Health is EXPLICIT: at the end the rider chooses Save or Discard. Only this (primary) session can
/// save; the iPhone's mirrored copy never saves, so no duplicate workout appears in Fitness.
final class WorkoutManager: NSObject, ObservableObject, HKWorkoutSessionDelegate, HKLiveWorkoutBuilderDelegate {
    enum Phase: String { case idle, running, paused, ended }
    /// One instance for the app and the application delegate (the iPhone's start request arrives at the delegate).
    static let shared = WorkoutManager()

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var hrBpm: Int?
    @Published private(set) var hrAt: Date?
    @Published private(set) var elapsed: TimeInterval = 0
    @Published private(set) var sentCount = 0
    @Published private(set) var status = "Ready"
    @Published private(set) var permissionAsked = false
    @Published private(set) var hrReadAllowed: Bool?     /* nil = unknown (HealthKit does not reveal read permission); we infer from data */
    /// Phone delivery: mirrored session up, last time a reading was confirmed sent on either channel, failures.
    @Published private(set) var mirroring = false
    @Published private(set) var lastDeliveredAt: Date?
    @Published private(set) var lastDeliveryChannel = ""
    @Published private(set) var sendFailures = 0

    private let store = HKHealthStore()
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?
    private var timer: Timer?
    private var lastSentAt: Date?
    private var seq = 0
    private var mirrorAttemptAt: Date?
    private var mirrorPending = false

    var available: Bool { HKHealthStore.isHealthDataAvailable() }
    var hrIsFresh: Bool { guard let t = hrAt else { return false }; return Date().timeIntervalSince(t) < 6 }
    var deliveryIsFresh: Bool { guard let t = lastDeliveredAt else { return false }; return Date().timeIntervalSince(t) < 8 }

    // MARK: permission
    func requestPermission(_ done: ((Bool) -> Void)? = nil) {
        guard available, let hr = HKObjectType.quantityType(forIdentifier: .heartRate) else { status = "Health data not available"; done?(false); return }
        let share: Set<HKSampleType> = [HKObjectType.workoutType()]
        let read: Set<HKObjectType> = [hr, HKObjectType.workoutType(), HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)!]
        store.requestAuthorization(toShare: share, read: read) { [weak self] ok, err in
            DispatchQueue.main.async {
                self?.permissionAsked = true
                self?.status = err.map { "Permission error: \($0.localizedDescription)" } ?? (ok ? "Permission sheet completed" : "Permission not completed")
                done?(ok)
            }
        }
    }

    /// Writing workouts is the only permission HealthKit reports; it tells us the sheet was answered.
    var workoutWriteStatus: String {
        switch store.authorizationStatus(for: HKObjectType.workoutType()) {
        case .sharingAuthorized: return "allowed"
        case .sharingDenied: return "denied"
        default: return "not asked"
        }
    }

    // MARK: workout
    func start() {
        guard phase == .idle || phase == .ended else { return }
        if workoutWriteStatus == "not asked" { requestPermission { [weak self] _ in self?.begin() } } else { begin() }
    }

    private func begin() {
        guard phase == .idle || phase == .ended else { return }
        let cfg = HKWorkoutConfiguration(); cfg.activityType = .cycling; cfg.locationType = .outdoor
        do {
            let s = try HKWorkoutSession(healthStore: store, configuration: cfg)
            let b = s.associatedWorkoutBuilder()
            b.dataSource = HKLiveWorkoutDataSource(healthStore: store, workoutConfiguration: cfg)
            s.delegate = self; b.delegate = self
            session = s; builder = b
            mirroring = false; mirrorPending = false
            // Apple DevRel guidance (forums thread 804276): mirror only once the session is prepared or running.
            s.prepare()
            let now = Date()
            s.startActivity(with: now)
            b.beginCollection(withStart: now) { [weak self] ok, err in
                DispatchQueue.main.async { self?.status = ok ? "Workout running" : "Could not start: \(err?.localizedDescription ?? "?")" }
            }
            phase = .running; hrBpm = nil; hrAt = nil; sentCount = 0; sendFailures = 0
            timer?.invalidate()
            timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.tickTimer() }
        } catch {
            status = "Could not create the workout: \(error.localizedDescription)"
        }
    }

    /// Mirrors the session to the iPhone. Retried every 10 s while the workout runs and mirroring is not up.
    private func startMirroring() {
        guard let s = session, !mirroring, !mirrorPending, phase == .running || phase == .paused else { return }
        mirrorPending = true; mirrorAttemptAt = Date()
        s.startMirroringToCompanionDevice { [weak self] ok, err in
            DispatchQueue.main.async {
                self?.mirrorPending = false
                self?.mirroring = ok
                if !ok { self?.status = "iPhone link: \(err?.localizedDescription ?? "mirroring failed") — retrying" }
                else { self?.sendState() }
            }
        }
    }

    func pause() { session?.pause(); phase = .paused; sendState() }
    func resume() { session?.resume(); phase = .running; sendState() }

    func end() {
        session?.end()
        phase = .ended
        timer?.invalidate(); timer = nil
        status = "Ended — save to Apple Health or discard"
        sendState()
    }

    /// Writes the workout into Apple Health (one entry). Only on explicit request.
    func saveToHealth() {
        guard let b = builder else { reset(); return }
        b.endCollection(withEnd: Date()) { [weak self] _, _ in
            b.finishWorkout { _, err in
                DispatchQueue.main.async { self?.status = err.map { "Save failed: \($0.localizedDescription)" } ?? "Saved to Apple Health"; self?.reset() }
            }
        }
    }

    /// Discards the HealthKit record. The ride on the Waveshare is unaffected.
    func discard() {
        guard let b = builder else { reset(); return }
        b.endCollection(withEnd: Date()) { [weak self] _, _ in
            b.discardWorkout()
            DispatchQueue.main.async { self?.status = "Discarded (not saved to Apple Health)"; self?.reset() }
        }
    }

    private func reset() { session = nil; builder = nil; phase = .idle; hrBpm = nil; hrAt = nil; elapsed = 0; mirroring = false; mirrorPending = false }

    private func tickTimer() {
        if let b = builder { elapsed = b.elapsedTime }
        if !mirroring, !mirrorPending, mirrorAttemptAt.map({ Date().timeIntervalSince($0) > 10 }) ?? true { startMirroring() }
        // keep the phone informed every 5 s even without a new heart-rate sample (state + battery)
        if let t = lastSentAt, Date().timeIntervalSince(t) < 5 { return }
        if !hrIsFresh { sendState() }
    }

    // MARK: sending to the iPhone
    private func sendState() { send(bpm: nil, at: Date()) }

    private func send(bpm: Int?, at: Date) {
        var batt: Int? = nil
        #if os(watchOS)
        let dev = WKInterfaceDevice.current(); dev.isBatteryMonitoringEnabled = true
        if dev.batteryLevel >= 0 { batt = Int(dev.batteryLevel * 100) }
        #endif
        seq += 1
        lastSentAt = Date()
        var delivered = false
        // 1. mirrored workout session (primary)
        if mirroring, let s = session, let data = WatchHRPayload(bpm: bpm, at: at.timeIntervalSince1970, state: phase.rawValue, build: AppInfo.label, battery: batt, seq: seq).encoded() {
            delivered = true
            s.sendToRemoteWorkoutSession(data: data) { [weak self] ok, err in
                DispatchQueue.main.async {
                    guard let self else { return }
                    if ok { self.lastDeliveredAt = Date(); self.lastDeliveryChannel = "workout mirroring"; if bpm != nil { self.sentCount += 1 } }
                    else { self.sendFailures += 1; self.status = "Mirroring send failed: \(err?.localizedDescription ?? "?")"; if self.sendFailures % 5 == 0 { self.mirroring = false } }
                }
            }
        }
        // 2. WatchConnectivity (secondary; the phone de-duplicates by sample time)
        if WCSession.isSupported(), WCSession.default.activationState == .activated, WCSession.default.isReachable {
            delivered = true
            let msg = WatchMessage.makeHR(bpm: bpm ?? -1, at: at, workout: phase.rawValue, battery: batt, build: AppInfo.label)
            WCSession.default.sendMessage(msg, replyHandler: nil) { [weak self] e in DispatchQueue.main.async { self?.status = "Phone message failed: \(e.localizedDescription)" } }
            if !mirroring { lastDeliveredAt = Date(); lastDeliveryChannel = "Watch Connectivity"; if bpm != nil { sentCount += 1 } }
        }
        if !delivered { status = "iPhone not reachable — reconnecting automatically" }
    }

    // MARK: HK delegates
    func workoutSession(_ s: HKWorkoutSession, didChangeTo to: HKWorkoutSessionState, from: HKWorkoutSessionState, date: Date) {
        DispatchQueue.main.async {
            switch to { case .running: self.phase = .running; case .paused: self.phase = .paused; case .ended: self.phase = .ended; default: break }
            if to == .prepared || to == .running { self.startMirroring() }
        }
    }
    func workoutSession(_ s: HKWorkoutSession, didFailWithError error: Error) { DispatchQueue.main.async { self.status = "Workout error: \(error.localizedDescription)" } }
    /// The iPhone's mirrored copy went away (phone app killed, out of range): retry mirroring from the tick.
    func workoutSession(_ s: HKWorkoutSession, didDisconnectFromRemoteDeviceWithError error: Error?) {
        DispatchQueue.main.async { self.mirroring = false; self.mirrorAttemptAt = Date(); self.status = "iPhone link lost — reconnecting automatically" }
    }
    func workoutBuilderDidCollectEvent(_ b: HKLiveWorkoutBuilder) {}

    func workoutBuilder(_ b: HKLiveWorkoutBuilder, didCollectDataOf types: Set<HKSampleType>) {
        guard let hrType = HKQuantityType.quantityType(forIdentifier: .heartRate), types.contains(hrType),
              let stats = b.statistics(for: hrType), let q = stats.mostRecentQuantity() else { return }
        let bpm = Int(q.doubleValue(for: HKUnit.count().unitDivided(by: .minute())).rounded())
        let at = stats.mostRecentQuantityDateInterval()?.end ?? Date()
        DispatchQueue.main.async {
            self.hrReadAllowed = true
            self.hrBpm = bpm; self.hrAt = at
            self.send(bpm: bpm, at: at)
        }
    }
}
