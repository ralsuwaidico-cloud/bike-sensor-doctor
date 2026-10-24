import Foundation
import Combine
import CoreLocation

/// Ride session on the phone. Two modes:
///  - board connected: the Waveshare is the recorder; this object only mirrors its state and, when the board ends the
///    ride, builds a RideRecord from the board's live totals plus the phone's own GPS trace for the map;
///  - phone only: records time, GPS distance (speed integration, same rule as the board: ignore < 1.8 km/h and fixes
///    worse than 50 m) and watch heart rate at 1 Hz. No power/cadence exists in this mode and none is invented.
final class RideRecorder: ObservableObject {
    enum State: String { case idle, running, paused, ended }
    @Published private(set) var state: State = .idle
    @Published private(set) var elapsedS = 0
    @Published private(set) var distanceM = 0
    @Published private(set) var recorderIsBoard = false
    @Published private(set) var samples: [RideRecord.Sample] = []
    @Published private(set) var lapStartS = 0
    @Published private(set) var lapCount = 1
    @Published var pendingResult: RideRecord?

    private var timer: Timer?
    private var distCm = 0
    private var hrSum = 0, hrN = 0, hrMax = 0
    private var startDate = Date()
    private var lastBoardState: BCLink.RideState = .idle
    weak var device: DeviceLink?
    weak var location: LocationService?
    weak var watch: WatchLink?

    /// Called once per second by the app; decides which mode applies.
    func tick() {
        let boardLive = device?.state == .ready && (device?.liveIsFresh ?? false)
        if boardLive, let live = device?.live {
            recorderIsBoard = true
            mirror(live)
        } else if state == .running || state == .paused {
            if recorderIsBoard { return }          /* board recorder temporarily out of reach: keep its last values, record nothing locally */
            if state == .running { phoneSecond() }
        }
    }

    // MARK: board mirror
    private func mirror(_ l: BCLink.Live) {
        elapsedS = l.elapsedS; distanceM = l.distanceM
        let st: State = l.rideState == .running ? .running : l.rideState == .paused ? .paused : l.rideState == .ended ? .ended : .idle
        if st == .running, lastBoardState != .running, lastBoardState != .paused { startDate = Date().addingTimeInterval(-Double(l.elapsedS)); samples = []; hrSum = 0; hrN = 0; hrMax = 0 }
        if st == .running {
            var s = RideRecord.Sample(t: l.elapsedS, w: l.powerW, cad: l.cadenceRpm, hr: l.hrBpm, speedCms: nil)
            if let loc = location?.last, Date().timeIntervalSince(loc.timestamp) < 3 { s.lat = loc.coordinate.latitude; s.lon = loc.coordinate.longitude; s.alt = loc.verticalAccuracy >= 0 ? loc.altitude : nil; s.speedCms = loc.speed >= 0 ? Int(loc.speed * 100) : nil }
            if samples.last?.t != s.t { samples.append(s); if let hr = s.hr { hrSum += hr; hrN += 1; hrMax = max(hrMax, hr) } }
        }
        if st == .ended, lastBoardState == .running || lastBoardState == .paused { pendingResult = boardRecord(l) }
        state = st; lastBoardState = l.rideState
    }

    private func boardRecord(_ l: BCLink.Live) -> RideRecord {
        let ws = samples.compactMap { $0.w }
        let cads = samples.compactMap { $0.cad }
        var r = RideRecord(boardRideId: l.rideId, start: startDate, durationS: l.elapsedS, distanceM: l.distanceM,
                           avgPower: ws.isEmpty ? nil : ws.reduce(0, +) / ws.count, maxPower: ws.max(), normalizedPower: Self.normalized(ws),
                           avgCadence: cads.isEmpty ? nil : cads.reduce(0, +) / cads.count, avgHR: hrN > 0 ? hrSum / hrN : nil, maxHR: hrN > 0 ? hrMax : nil,
                           kj: ws.isEmpty ? nil : ws.reduce(0, +) / 1000, recorder: .board, sources: ["Waveshare", "XDS"] + (hrN > 0 ? ["Apple Watch"] : []) + (samples.contains { $0.lat != nil } ? ["Phone GPS"] : []), demo: l.demo)
        r.samples = samples
        return r
    }

    // MARK: phone-only
    func start() {
        guard state == .idle || state == .ended else { return }
        recorderIsBoard = false
        state = .running; elapsedS = 0; distanceM = 0; distCm = 0; samples = []; hrSum = 0; hrN = 0; hrMax = 0; lapStartS = 0; lapCount = 1
        startDate = Date()
        location?.sharing = true
    }
    func pause() { if state == .running { state = .paused } }
    func resume() { if state == .paused { state = .running } }
    func lap() { lapCount += 1; lapStartS = elapsedS }
    func end() {
        guard state == .running || state == .paused else { return }
        state = .ended
        pendingResult = RideRecord(start: startDate, durationS: elapsedS, distanceM: distanceM, avgHR: hrN > 0 ? hrSum / hrN : nil, maxHR: hrN > 0 ? hrMax : nil,
                                   recorder: .phone, sources: ["Phone GPS"] + (hrN > 0 ? ["Apple Watch"] : []), samples: samples)
        pendingResult?.samples = samples
    }
    func discard() { pendingResult = nil; state = .idle }
    func finish() { state = .idle; pendingResult = nil }

    private func phoneSecond() {
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

    /// Normalized power (Coggan): 30 s rolling average, 4th power mean, 4th root. Needs ≥ 30 s of power.
    static func normalized(_ w: [Int]) -> Int? {
        guard w.count >= 30 else { return nil }
        var sum = 0.0; var n = 0; var window = 0
        for i in 0..<w.count { window += w[i]; if i >= 30 { window -= w[i - 30] }; if i >= 29 { let a = Double(window) / 30; sum += a * a * a * a; n += 1 } }
        return n > 0 ? Int(pow(sum / Double(n), 0.25).rounded()) : nil
    }
}
