import Foundation
import Combine
import CoreLocation
import UIKit
import UserNotifications

/// Ride session on the phone with ONE owner per ride, fixed when the ride starts:
///  - `.board`: the Waveshare is the recorder. This object mirrors its live state and, when the board ends the ride,
///    builds a RideRecord from the board's totals plus the phone's own 1 Hz trace (GPS for the map, mirrored values
///    for the graphs). If the phone loses the link mid-ride the board keeps recording; nothing is recorded here.
///  - `.phone`: the phone records time, GPS distance (speed integration, same rule as the board: ignore < 1.8 km/h and
///    fixes worse than 50 m) and watch heart rate at 1 Hz. No power/cadence exists in this mode and none is invented.
/// A board that connects during a phone ride does NOT take over (the owner never changes mid-ride); a phone ride cannot
/// be started while the board reports a ride of its own. So a ride can never be recorded twice.
final class RideRecorder: ObservableObject {
    enum State: String { case idle, running, paused, ended }
    enum Owner: String { case none, board, phone
        var label: String { switch self { case .board: return "BikeComputer"; case .phone: return "this phone"; case .none: return "—" } } }

    @Published private(set) var state: State = .idle
    @Published private(set) var owner: Owner = .none
    @Published private(set) var elapsedS = 0
    @Published private(set) var distanceM = 0
    @Published private(set) var samples: [RideRecord.Sample] = []
    @Published private(set) var lapStartS = 0
    @Published private(set) var lapCount = 1
    @Published private(set) var boardLinkLost = false
    @Published var pendingResult: RideRecord?
    @Published private(set) var note: String?

    private var distCm = 0
    /// Wall-clock time of the last phone-owned second that was recorded; lets a late timer (app suspended) be
    /// recognised as a gap instead of silently losing time.
    private var lastPhoneTick: Date?
    @Published private(set) var gapSeconds = 0
    private var hrSum = 0, hrN = 0, hrMax = 0
    private var startDate = Date()
    private var lastBoardState: BCLink.RideState = .idle
    private var lastBoardRideId = -1
    weak var device: DeviceLink?
    weak var location: LocationService?
    weak var watch: WatchLink?
    var phoneOnlyMode = false
    /// Snapshot for the watch mirror and the background notice; refreshed every tick.
    var onTick: (() -> Void)?

    private var ticker: Timer?
    private var bgObserver: Any?
    private var notificationsAsked = false

    /// `autoTick`: the recorder drives itself at 1 Hz from a run-loop timer (keeps counting in the background while the
    /// location background mode keeps the app alive). Tests pass false and call tick() by hand.
    init(autoTick: Bool = true) {
        if autoTick {
            let t = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.tick(); self?.onTick?() }
            t.tolerance = 0.1
            RunLoop.main.add(t, forMode: .common)
            ticker = t
            bgObserver = NotificationCenter.default.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in self?.enteredBackground() }
        }
    }
    deinit { ticker?.invalidate(); if let o = bgObserver { NotificationCenter.default.removeObserver(o) } }

    /// Local notice while a ride keeps recording with the app in the background (no new entitlement needed).
    private func enteredBackground() {
        guard isActive else { return }
        let c = UNUserNotificationCenter.current()
        let content = UNMutableNotificationContent()
        content.title = owner == .board ? "BikeComputer ride in progress" : "Recording in the background"
        content.body = owner == .board ? "The board records; the phone keeps mirroring it and sending GPS." : "GPS and heart rate keep recording. Open BikeComputer to see the ride."
        content.sound = nil
        c.add(UNNotificationRequest(identifier: "bc.ride.background", content: content, trigger: nil))
    }
    private func clearBackgroundNotice() { UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: ["bc.ride.background"]) }
    private func askNotifications() {
        guard !notificationsAsked else { return }
        notificationsAsked = true
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert]) { _, _ in }
    }

    var recorderIsBoard: Bool { owner == .board }
    var isActive: Bool { state == .running || state == .paused }

    /// What a "Start" would do right now; the Ride tab shows this before the button.
    enum StartMode { case board, phone, blockedByBoardRide, blockedNoGPSPermission }
    func startMode(locationAuthorized: Bool) -> StartMode {
        let boardReady = device?.state == .ready && (device?.liveIsFresh ?? false)
        if boardReady, let l = device?.live, l.rideState == .running || l.rideState == .paused, owner != .board { return .blockedByBoardRide }
        if boardReady, !phoneOnlyMode { return .board }
        return .phone
    }

    /// Called once per second by the app.
    func tick() {
        let boardLive = device?.state == .ready && (device?.liveIsFresh ?? false)
        if let live = device?.live, boardLive {
            // the board's ride state is the truth for board-owned rides; it may also start a ride by itself (button on the board)
            if owner == .board || (owner == .none && (live.rideState == .running || live.rideState == .paused) && !phoneOnlyMode) {
                if owner == .none { adopt(live) }
                boardLinkLost = false
                mirror(live)
                return
            }
        }
        if owner == .board, isActive {
            boardLinkLost = !boardLive       /* board recorder out of reach: keep its last values, record nothing locally */
            return
        }
        if owner == .phone, state == .running { phoneSecond() }
    }

    /// Test hook: pretend `seconds` passed with no tick (the app was suspended).
    func simulateSuspension(seconds: Int) { if let t = lastPhoneTick { lastPhoneTick = t.addingTimeInterval(-Double(seconds)) } }

    // MARK: board-owned
    private func adopt(_ l: BCLink.Live) {
        owner = .board; samples = []; hrSum = 0; hrN = 0; hrMax = 0; lapCount = 1; lapStartS = 0
        startDate = Date().addingTimeInterval(-Double(l.elapsedS)); lastBoardRideId = l.rideId
        note = "The BikeComputer is recording; this phone mirrors it and adds GPS."
        location?.sharing = true
        askNotifications()
    }

    private func mirror(_ l: BCLink.Live) {
        elapsedS = l.elapsedS; distanceM = l.distanceM
        let st: State = l.rideState == .running ? .running : l.rideState == .paused ? .paused : l.rideState == .ended ? .ended : .idle
        if st == .running, lastBoardState != .running, lastBoardState != .paused { startDate = Date().addingTimeInterval(-Double(l.elapsedS)); samples = []; hrSum = 0; hrN = 0; hrMax = 0; lastBoardRideId = l.rideId }
        if st == .running {
            var s = RideRecord.Sample(t: l.elapsedS, w: l.powerW, cad: l.cadenceRpm, hr: l.hrBpm, speedCms: nil)
            if let loc = location?.last, Date().timeIntervalSince(loc.timestamp) < 3, loc.horizontalAccuracy >= 0, loc.horizontalAccuracy <= 50 {
                s.lat = loc.coordinate.latitude; s.lon = loc.coordinate.longitude; s.alt = loc.verticalAccuracy >= 0 ? loc.altitude : nil; s.speedCms = loc.speed >= 0 ? Int(loc.speed * 100) : nil
            }
            if samples.last?.t != s.t { samples.append(s); if let hr = s.hr { hrSum += hr; hrN += 1; hrMax = max(hrMax, hr) } }
        }
        if st == .ended, lastBoardState == .running || lastBoardState == .paused { pendingResult = boardRecord(l) }
        if st == .idle, lastBoardState == .ended || lastBoardState == .idle, pendingResult == nil, owner == .board, state != .idle { owner = .none; note = nil }
        state = st; lastBoardState = l.rideState
    }

    private func boardRecord(_ l: BCLink.Live) -> RideRecord {
        let ws = samples.compactMap { $0.w }
        let cads = samples.compactMap { $0.cad }
        var r = RideRecord(boardRideId: l.rideId, boardId: device?.boardId, start: startDate, durationS: l.elapsedS, distanceM: l.distanceM,
                           avgPower: ws.isEmpty ? nil : ws.reduce(0, +) / ws.count, maxPower: ws.max(), normalizedPower: Self.normalized(ws),
                           avgCadence: cads.isEmpty ? nil : cads.reduce(0, +) / cads.count, avgHR: hrN > 0 ? hrSum / hrN : nil, maxHR: hrN > 0 ? hrMax : nil,
                           kj: ws.isEmpty ? nil : ws.reduce(0, +) / 1000, recorder: .board,
                           sources: ["BikeComputer", "XDS"] + (hrN > 0 ? ["Heart rate"] : []) + (samples.contains { $0.lat != nil } ? ["Phone GPS"] : []), demo: l.demo)
        r.samples = samples
        if ws.count < l.elapsedS / 2 { r.sources.append("phone mirror incomplete") }   /* the board's own history has the full numbers */
        return r
    }

    // MARK: phone-owned
    /// Starts a phone-only ride. Returns false when a board ride is active (one recorder per ride).
    @discardableResult
    func start() -> Bool {
        guard state == .idle || state == .ended, owner != .board else { return false }
        if let l = device?.live, device?.state == .ready, device?.liveIsFresh ?? false, l.rideState == .running || l.rideState == .paused { return false }
        owner = .phone
        state = .running; elapsedS = 0; distanceM = 0; distCm = 0; samples = []; hrSum = 0; hrN = 0; hrMax = 0; lapStartS = 0; lapCount = 1; gapSeconds = 0
        startDate = Date(); boardLinkLost = false; lastPhoneTick = Date()
        note = device?.state == .ready ? "Phone-only ride: this phone records; the BikeComputer's values are shown but not merged." : "Phone-only ride: GPS speed and distance, heart rate from the watch."
        location?.sharing = true
        askNotifications()
        return true
    }
    func pause() { if owner == .phone, state == .running { state = .paused } }
    func resume() { if owner == .phone, state == .paused { state = .running; lastPhoneTick = Date() } }
    func lap() { lapCount += 1; lapStartS = elapsedS }
    func end() {
        guard owner == .phone, isActive else { return }
        state = .ended
        var r = RideRecord(start: startDate, durationS: elapsedS, distanceM: distanceM, avgHR: hrN > 0 ? hrSum / hrN : nil, maxHR: hrN > 0 ? hrMax : nil,
                           recorder: .phone, sources: ["Phone GPS"] + (hrN > 0 ? ["Apple Watch"] : []))
        r.samples = samples; r.gapSeconds = gapSeconds
        pendingResult = r
    }
    func discard() { pendingResult = nil; state = .idle; owner = .none; note = nil; clearBackgroundNotice() }
    func finish() { pendingResult = nil; state = .idle; owner = .none; note = nil; clearBackgroundNotice() }

    private func phoneSecond(now: Date = Date()) {
        // Gap handling: if more than one wall-clock second passed since the last recorded second (timer held back while
        // the app was suspended), the missing seconds are stored as empty samples flagged `gap` — time stays right,
        // nothing is interpolated.
        if let last = lastPhoneTick {
            let missed = Int(now.timeIntervalSince(last).rounded()) - 1
            if missed >= 1 {
                for _ in 0..<min(missed, 6 * 3600) { elapsedS += 1; var g = RideRecord.Sample(t: elapsedS); g.gap = true; samples.append(g) }
                gapSeconds += missed
            }
        }
        lastPhoneTick = now
        elapsedS += 1
        var s = RideRecord.Sample(t: elapsedS)
        if let loc = location?.last, Date().timeIntervalSince(loc.timestamp) < 3, loc.horizontalAccuracy >= 0, loc.horizontalAccuracy <= 50 {
            s.lat = loc.coordinate.latitude; s.lon = loc.coordinate.longitude; s.alt = loc.verticalAccuracy >= 0 ? loc.altitude : nil
            if loc.speed >= 0.5 { let cms = Int(loc.speed * 100); s.speedCms = cms; distCm += cms; distanceM = distCm / 100 }
            else if loc.speed >= 0 { s.speedCms = 0 }
        }
        if let w = watch, w.hrIsFresh, let hr = w.hrBpm { s.hr = hr; hrSum += hr; hrN += 1; hrMax = max(hrMax, hr) }
        samples.append(s)
    }

    /// Pure helper used by the unit tests: distance from a 1 Hz speed series with the same rule as above.
    static func distanceM(speedsCms: [Int?], haccM: [Double]) -> Int {
        var cm = 0
        for (i, s) in speedsCms.enumerated() { if let s, haccM[i] <= 50, s >= 50 { cm += s } }
        return cm / 100
    }

    /// Normalized power (Coggan): 30 s rolling average, 4th power mean, 4th root. Needs ≥ 30 s of power.
    static func normalized(_ w: [Int]) -> Int? {
        guard w.count >= 30 else { return nil }
        var sum = 0.0; var n = 0; var window = 0
        for i in 0..<w.count { window += w[i]; if i >= 30 { window -= w[i - 30] }; if i >= 29 { let a = Double(window) / 30; sum += a * a * a * a; n += 1 } }
        return n > 0 ? Int(pow(sum / Double(n), 0.25).rounded()) : nil
    }
}
