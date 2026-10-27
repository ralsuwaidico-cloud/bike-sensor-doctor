import Foundation
import Combine

/// App-side owner of Link 1.3 (BLE_CONTRACT.md v1): negotiates on every connection, then — only for what the board's
/// HELLO_ACK enabled — mirrors the phone coach, imports offline rides and reads storage status. With a board that does
/// not advertise cap 0x0800 (firmware 0.7.3 and the release candidate pairing) it sends nothing and changes nothing.
final class Link13Center: ObservableObject {
    @Published private(set) var session = Link13Session()
    /// Coach mirroring status for the BikeComputer page ("Workout on the BikeComputer (works offline)" …).
    @Published private(set) var coachStatus = ""
    @Published private(set) var coachMirroring = false
    @Published private(set) var rideProgress: RideQueueTransfer.Progress?
    @Published private(set) var rideError: String?
    @Published private(set) var rideHolds: [UInt32: RideQueueTransfer.Hold] = [:]
    @Published private(set) var boardRides: [BCLink.RideQueueInfo] = []
    @Published private(set) var importedRides: [BoardQueueRideMeta] = []
    @Published private(set) var storage: BCLink.StorageStatus?
    @Published private(set) var storageAt: Date?
    @Published private(set) var cleanPending = false
    @Published private(set) var cleanResult: BCLink.StorageCleanResult?

    let rideStore: BoardRideQueueStore
    private(set) var rideEngine: RideQueueTransfer?
    let mirror: CoachMirror
    private weak var device: DeviceLink?
    private weak var store: Store?
    private weak var recorder: RideRecorder?
    private weak var diag: DiagReportCenter?
    private var timer: Timer?
    private var seq: UInt16 = 0
    var onLog: ((String) -> Void)?
    /// RIDEQ_INFO flags bit4 (v1.1): the board's storage is damaged and the ride exists only in its memory.
    static let ramOnlyWarning = "Only in the BikeComputer's memory: lost if the board powers off before Cyclift saves it. Keep the board on and connected."

    init(rideStore: BoardRideQueueStore = BoardRideQueueStore(root: BoardRideQueueStore.defaultRoot())) {
        self.rideStore = rideStore
        mirror = CoachMirror { _ in false }
        importedRides = rideStore.all()
        mirror.send = { [weak self] d in self?.device?.sendLink13(d) ?? false }
        mirror.seqStore = DefaultsCoachSeqStore()      /* seq stays strictly newer across relaunches (QA RC3-03) */
    }

    func attach(device d: DeviceLink, store s: Store, recorder r: RideRecorder, diag dc: DiagReportCenter) {
        device = d; store = s; recorder = r; diag = dc
        d.onLink13Ready = { [weak self] in self?.linkReady() }
        d.onLink13Down = { [weak self] in self?.linkDown() }
        d.onLink13Message = { [weak self] m in self?.receive(m) }
        // every SYNC_RIDE / SYNC_END, every board (also 0.7.3): history import + summary CRC + held-ride ACK (RC3-01)
        d.onSyncData = { [weak self, weak s] data, boardId in
            guard let self else { return }
            let now = Date()
            if let e = self.rideEngine, e.boardId == boardId { e.handleSync(data, history: s, now: now) }
            else { BoardSummaryIngest.ingest(data, boardId: boardId, history: s, queueStore: self.rideStore) }
            self.publish(); self.ensureTimer()
        }
        dc.ackWithDelete = { [weak self] in self?.session.diagAuto ?? false }
    }

    // MARK: link
    private func linkReady() {
        guard let d = device, let info = d.info else { return }
        var s = session
        let hello = s.connected(info: info, now: Date())
        session = s
        mirror.linkDown()
        rideEngine?.linkDown()
        guard hello else { coachStatus = ""; coachMirroring = false; publish(); return }      /* 0.7.3: Link 1.2.3 behaviour, nothing sent */
        if rideEngine?.boardId != d.boardId { rideEngine = makeRideEngine(d.boardId) }
        sendHello()
        ensureTimer()
    }
    private func linkDown() {
        session.linkDown(); mirror.linkDown(); rideEngine?.linkDown()
        cleanPending = false; coachMirroring = false
        storage = nil; storageAt = nil      /* measured on a connection that is gone: never shown as current (RC3-08) */
        stopTimer(); publish()
    }
    private func sendHello() {
        if let m = BCLink.encodeAppHello(appVersion: AppInfo.version, seq: nextSeq(), tMs: 0) { _ = device?.sendLink13(m) }
        onLog?("Link 1.3: hello sent")
    }
    private func helloAccepted() {
        onLog?("Link 1.3: \(session.summary)")
        if session.storage { requestStorageStatus() }
        if session.rideQueue { rideEngine?.start(now: Date()) }
        if session.diagAuto { diag?.helloEnabledAutoTransfer() }
        publish()
    }

    // MARK: board → phone
    private func receive(_ m: Data) {
        guard let t = m.first, let type = BCLink.MsgType(rawValue: t) else { return }
        let now = Date()
        switch type {
        case .helloAck:
            guard let a = BCLink.decodeHelloAck(m) else { return }
            session.helloAck(a); helloAccepted()
        case .rideqInfo, .rideqListEnd, .rideqChunk, .rideqErr, .event:
            guard session.rideQueue else { return }
            rideEngine?.receive(m, now: now)
        case .storageStatus:
            guard session.storage, let s = BCLink.decodeStorageStatus(m) else { return }
            storage = s; storageAt = now
        case .storageCleanResult:
            guard session.storage, let r = BCLink.decodeStorageCleanResult(m) else { return }
            cleanResult = r; cleanPending = false
            onLog?("BikeComputer storage cleanup: \(r.words)")
            requestStorageStatus()
        case .coachPlanAck:
            guard session.coach else { return }
            mirror.receive(m, now: now)
        default: break
        }
        publish(); ensureTimer()
    }

    // MARK: storage
    func requestStorageStatus() {
        guard session.storage, let m = BCLink.encodeStorageStatusRequest(seq: nextSeq(), tMs: 0) else { return }
        _ = device?.sendLink13(m)
    }
    /// The rider confirmed the safe cleanup. Sends exactly what `BoardStorageModel.cleanup` allows, nothing else.
    func clean(_ c: BoardStorageModel.Cleanup) {
        guard session.storage, c.allowed, !cleanPending, let m = BCLink.encodeStorageCleanRequest(c.what, seq: nextSeq(), tMs: 0) else { return }
        if device?.sendLink13(m) == true { cleanPending = true; cleanResult = nil }
    }
    var boardRecording: Bool { guard let d = device, d.liveIsFresh else { return false }; return d.live?.rideState == .running || d.live?.rideState == .paused }

    // MARK: ride queue
    private func makeRideEngine(_ boardId: String) -> RideQueueTransfer {
        let e = RideQueueTransfer(boardId: boardId, store: rideStore) { [weak self] d in self?.device?.sendLink13(d) ?? false }
        e.linkPayload = { [weak self] in self?.device?.maxNotifyBytes }
        e.boardRecording = { [weak self] in guard let d = self?.device, d.liveIsFresh else { return false }; return d.live?.rideState == .running }
        e.summaryCrc = { [weak self] id in self?.rideStore.summaryCrc(boardId, id) }
        e.sendSync = { [weak self] d in self?.device?.sendSyncRequest(d) ?? false }
        e.syncBusy = { [weak self] in self?.device?.syncInFlight ?? true }
        e.deliver = { [weak self] m, data in
            guard let s = self?.store else { return .failed("the history is not available") }
            let r = s.importBoardQueueRide(m, samples: data)
            if case .stored = r { self?.onLog?("Offline ride \(m.rideId) from the BikeComputer saved in Cyclift (\(m.sizeText))"); self?.reloadImported() }
            return r
        }
        e.onChange = { [weak self] in self?.reloadImported(); self?.publish() }
        return e
    }

    // MARK: coach (called once per ride-screen second by RideTabView)
    /// `plan`: what the phone coach runs now (nil = coach off / nothing to mirror); `live`: what it shows this second.
    func coachTick(plan input: CoachPlanInput?, live: CoachLiveInput, boardOwnsRide: Bool, phoneOwnsRide: Bool) {
        let now = Date()
        defer { publish() }
        guard session.coach else { coachMirroring = false; return }
        // a ride recorded by the phone alone runs on the phone's clock, not the board's: nothing to mirror
        guard let input, !phoneOwnsRide else {
            if mirror.plan != nil { mirror.end(.stoppedByRider, now: now) }
            coachMirroring = false
            return
        }
        guard let plan = CoachPlanBuilder.plan(input, t0ElapsedS: boardOwnsRide ? 0 : BCLink.coachT0AtRideStart) else { coachMirroring = false; return }
        if live.session == .finished || live.session == .abandoned {
            // the ride is over: the last state (WORKOUT DONE) and one COACH_END, then nothing until the next ride
            guard mirror.plan != nil else { coachMirroring = false; return }
            mirror.update(state: CoachStateBuilder.state(plan: plan, input: input, live: live), boardEcho: device?.live?.coachSeq, now: now)
            let done = live.elapsedS >= Int(plan.totalDurationS) && plan.segments.last?.durationS != CoachPlanBuilder.openEnded
            mirror.end(done ? .completed : .stoppedByRider, now: now)
            coachMirroring = false
            return
        }
        if let old = mirror.plan, old.workoutId != plan.workoutId, mirror.planStatus == .stored { mirror.end(.replaced, now: now) }
        mirror.setPlan(plan, now: now)
        mirror.update(state: CoachStateBuilder.state(plan: plan, input: input, live: live), boardEcho: device?.live?.coachSeq, now: now)
        coachMirroring = true
        ensureTimer()
    }

    // MARK: clock
    private func ensureTimer() {
        guard timer == nil, device?.state == .ready else { return }
        let t = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }
    private func stopTimer() { timer?.invalidate(); timer = nil }
    private func tick() {
        let now = Date()
        var s = session
        if s.tick(now: now) { sendHello() }
        if s != session { session = s }
        mirror.tick(now: now)
        rideEngine?.tick(now: now)
        if !(session.isWaiting || mirror.planStatus.isSending || rideEngine?.isBusy == true || cleanPending) { stopTimer() }
        publish()
    }

    private func publish() {
        let st = session.coach ? mirror.statusText : ""
        if coachStatus != st { coachStatus = st }
        let p = rideEngine?.progress; if rideProgress != p { rideProgress = p }
        let e = rideEngine?.lastError; if rideError != e { rideError = e }
        let h = rideEngine?.holds ?? [:]; if rideHolds != h { rideHolds = h }
        let b = rideEngine?.boardList ?? []; if boardRides != b { boardRides = b }
    }
    func reloadImported() { let all = rideStore.all(); if importedRides != all { importedRides = all } }
    private func nextSeq() -> UInt16 { seq &+= 1; return seq }

    /// Rides the board reports as not yet saved in Cyclift (STORAGE_STATUS, else LIVE, else the queue list).
    /// Rides the board holds that are not yet saved in Cyclift, from THIS connection only (QA RC3-08): LIVE tag 14 when the
    /// board sends it, else the ride list read on this connection (kept current by the board's replies to each ACK), else
    /// this connection's STORAGE_STATUS. nil = unknown — an omitted LIVE tag is never read as 0 and no old list is reused.
    var unsyncedOnBoard: Int? {
        if let d = device, d.liveIsFresh, let n = d.live?.ridesUnsynced { return n }
        if let e = rideEngine, e.lastListEnd != nil { return e.boardList.filter { $0.needsImport }.count }
        if let s = storage { return s.ridesUnsynced }
        return nil
    }
}

private extension CoachMirror.PlanStatus { var isSending: Bool { if case .sending = self { return true }; return false } }

/// Reads today's Workout, the rider's profile and the live hub into the plain inputs of CoachMirror. The only place
/// that touches the coaching models; it reads them and never changes them.
enum CoachMirrorAdapter {
    static func type(_ k: WorkoutKind?) -> BCLink.CoachWorkoutType {
        switch k {
        case .endurance?, .long?: return .endurance
        case .tempo?: return .tempo
        case .threshold?: return .threshold
        case .vo2?: return .vo2max
        case .recovery?: return .recovery
        case .ftpTest?: return .ftpTest
        default: return .freeRide
        }
    }
    /// nil when the phone coach is off (nothing to mirror). Same inputs RideCoach.configure uses.
    static func input(workout: Workout?, profile p: RiderProfile, settings s: AppSettings, powerTrusted: Bool) -> CoachPlanInput? {
        guard s.coachEnabled else { return nil }
        let ride = workout.flatMap { $0.kind.isRide ? $0 : nil }
        let maxHR = max(100, p.estimatedMaxHR)
        let zones = p.hrZones.map { z -> ClosedRange<Int> in let lo = z.lo == 0 ? Int(Double(maxHR) * 0.5) : z.lo; let hi = max(lo, z.hi ?? maxHR); return lo...hi }
        return CoachPlanInput(sessionKey: ride?.id.uuidString, name: ride?.kind.title ?? "Free ride", type: type(ride?.kind), zone: min(5, max(1, ride?.kind.zone ?? 2)),
                              plannedSec: ride.map { $0.minutes * 60 }, intervals: RideCoach.intervalPlan(for: ride), ftpW: p.ftpW, ftpKnown: p.ftpHow != .assumed, powerTrusted: powerTrusted,
                              hrZones: zones, cadLo: p.cadenceLow, cadHi: p.cadenceHigh)
    }
    /// The HR source the phone coach is using right now, as bc_src_t. Board HR keeps the board's own source byte (a
    /// board strap is 2; Apple Watch HR relayed through the board stays 4).
    static func hrSource(hub: SensorHub, boardLive: BCLink.Live?) -> (src: UInt8, live: Bool) {
        guard let r = hub.reading(.heartRate) else { return (0, false) }
        switch r.source.method {
        case .appleWatch: return (BCLink.Source.appleWatch.rawValue, true)
        case .bleDirect: return (BCLink.Source.phoneStrap.rawValue, true)
        case .bikeComputer: return (boardLive?.hrSource.rawValue ?? BCLink.Source.bleStrap.rawValue, true)
        default: return (0, false)
        }
    }
    static func session(_ r: RideRecorder) -> BCLink.CoachSessionState {
        switch r.state { case .idle: return .notStarted; case .running: return .running; case .paused: return .paused; case .ended: return .finished }
    }
}
