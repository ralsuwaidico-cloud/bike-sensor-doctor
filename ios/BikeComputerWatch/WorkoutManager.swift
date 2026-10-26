import Foundation
import HealthKit
import WatchConnectivity
#if os(watchOS)
import WatchKit
#endif

/// A real outdoor-cycling workout session on the watch (HKWorkoutSession + HKLiveWorkoutBuilder). The session is what
/// gives live heart rate; every reading is sent to the iPhone with its sample time, which forwards it to the Waveshare.
/// Saving to Apple Health is EXPLICIT: at the end the rider chooses Save or Discard, so no duplicate workout appears
/// in Fitness by accident (the Waveshare keeps its own ride record regardless).
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

    private let store = HKHealthStore()
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?
    private var timer: Timer?
    private var lastSentAt: Date?

    var available: Bool { HKHealthStore.isHealthDataAvailable() }
    var hrIsFresh: Bool { guard let t = hrAt else { return false }; return Date().timeIntervalSince(t) < 6 }

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
        let cfg = HKWorkoutConfiguration(); cfg.activityType = .cycling; cfg.locationType = .outdoor
        do {
            let s = try HKWorkoutSession(healthStore: store, configuration: cfg)
            let b = s.associatedWorkoutBuilder()
            b.dataSource = HKLiveWorkoutDataSource(healthStore: store, workoutConfiguration: cfg)
            s.delegate = self; b.delegate = self
            session = s; builder = b
            let now = Date()
            s.startActivity(with: now)
            b.beginCollection(withStart: now) { [weak self] ok, err in
                DispatchQueue.main.async { self?.status = ok ? "Workout running" : "Could not start: \(err?.localizedDescription ?? "?")" }
            }
            phase = .running; hrBpm = nil; hrAt = nil; sentCount = 0
            timer?.invalidate()
            timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.tickTimer() }
        } catch {
            status = "Could not create the workout: \(error.localizedDescription)"
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

    private func reset() { session = nil; builder = nil; phase = .idle; hrBpm = nil; hrAt = nil; elapsed = 0 }

    private func tickTimer() {
        if let b = builder { elapsed = b.elapsedTime }
        // keep the phone informed every 5 s even without a new heart-rate sample (state + battery)
        if let t = lastSentAt, Date().timeIntervalSince(t) < 5 { return }
        if !hrIsFresh { sendState() }
    }

    // MARK: sending to the iPhone
    private func sendState() { send(bpm: nil, at: Date()) }

    private func send(bpm: Int?, at: Date) {
        guard WCSession.isSupported(), WCSession.default.activationState == .activated else { return }
        var batt: Int? = nil
        #if os(watchOS)
        let dev = WKInterfaceDevice.current(); dev.isBatteryMonitoringEnabled = true
        if dev.batteryLevel >= 0 { batt = Int(dev.batteryLevel * 100) }
        #endif
        let msg = WatchMessage.makeHR(bpm: bpm ?? -1, at: at, workout: phase.rawValue, battery: batt)
        lastSentAt = Date()
        if WCSession.default.isReachable {
            WCSession.default.sendMessage(msg, replyHandler: nil) { [weak self] e in DispatchQueue.main.async { self?.status = "Phone unreachable: \(e.localizedDescription)" } }
            if bpm != nil { sentCount += 1 }
        } else {
            status = "iPhone not reachable — open Cyclift on the phone"
        }
    }

    // MARK: HK delegates
    func workoutSession(_ s: HKWorkoutSession, didChangeTo to: HKWorkoutSessionState, from: HKWorkoutSessionState, date: Date) {
        DispatchQueue.main.async {
            switch to { case .running: self.phase = .running; case .paused: self.phase = .paused; case .ended: self.phase = .ended; default: break }
        }
    }
    func workoutSession(_ s: HKWorkoutSession, didFailWithError error: Error) { DispatchQueue.main.async { self.status = "Workout error: \(error.localizedDescription)" } }
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

