import Foundation
import Combine
#if canImport(CoreLocation)
import CoreLocation
#endif

// Cyclift Watch (LILYGO) ↔ phone coordination. The pure part (`CyWatchFrames`, `CyWatchEvents`) is unit-tested; the
// coordinator only plugs it into the live objects. Rules (OWNERSHIP.md): the phone is the recorder — the watch's
// start / pause / resume / end are commands to the phone's RideRecorder (or the Board through it), never a second
// recording; logged sets flow into the phone's active strength session; a value the hub does not have is sent as absent.
enum CyWatchFrames {
    /// Today's session for the watch: ride (kind 1) or strength (kind 2) with the planned exercises; nil = nothing planned.
    static func planToday(store: Store, now: Date = Date()) -> CyWatchWire.PlanToday? {
        let cal = Calendar.current
        let todays = store.plan.filter { cal.isDate($0.date, inSameDayAs: now) && !$0.done && $0.kind != .rest && $0.kind != .recoveryDay }
        guard let w = todays.first else { return CyWatchWire.PlanToday(kind: 0, workoutId: "", title: "", startMin: 0, durationMin: 0, exercises: []) }
        let minuteOfDay = UInt16(cal.component(.hour, from: w.date) * 60 + cal.component(.minute, from: w.date))
        if w.kind.isRide {
            return CyWatchWire.PlanToday(kind: 1, workoutId: w.id.uuidString, title: w.displayTitle, startMin: minuteOfDay, durationMin: UInt16(clamping: w.minutes), exercises: [])
        }
        let entries = store.plannedEntries(for: w)
        let ex = entries.map { e -> CyWatchWire.PlanToday.Exercise in
            let first = e.sets.first
            return .init(id: e.exerciseId, name: e.name, sets: UInt8(clamping: e.sets.count), reps: UInt8(clamping: first?.reps ?? 0),
                         weightKg10: UInt16(clamping: Int(((first?.weightKg ?? 0) * 10).rounded())), restS: UInt16(clamping: e.restSeconds ?? 0),
                         superset: e.superset?.utf8.first ?? 0)
        }
        return CyWatchWire.PlanToday(kind: 2, workoutId: w.id.uuidString, title: w.displayTitle, startMin: minuteOfDay, durationMin: UInt16(clamping: w.minutes), exercises: ex)
    }

    /// Recovery summary for the watch face: last night's sleep and HRV with source + time; the ONE recommendation's
    /// title as the word; no percentage (recoveryPct stays absent — there is no score to send).
    static func cached(store: Store, now: Date = Date()) -> CyWatchWire.Cached {
        let r = store.recoveryReport(now: now)
        let sleep = r.metrics.first { $0.kind == .sleep }?.latest
        let hrv = r.metrics.first { $0.kind == .hrv }?.latest
        let week = store.homeWeekOverview(weekOf: now, now: now)
        return CyWatchWire.Cached(sleepMin: sleep.map { UInt16(clamping: Int(($0.value * 60).rounded())) }, sleepSource: sleep?.source ?? "", sleepUnixS: UInt32(max(0, sleep?.date.timeIntervalSince1970 ?? 0)),
                                  hrvMs: hrv.map { UInt16(clamping: Int($0.value.rounded())) }, hrvUnixS: UInt32(max(0, hrv?.date.timeIntervalSince1970 ?? 0)),
                                  recoveryPct: nil, recoveryWord: r.advice.kind == .noData ? "" : r.advice.title, insight: String(r.advice.detail.prefix(120)), loadPct: UInt8(clamping: Int((week.fraction * 100).rounded())))
    }

    /// Live frame from what the hub has right now (absent otherwise) plus the current ride step's targets.
    static func live(hub: SensorHub, recorder: RideRecorder, profile: RiderProfile, steps: [RideStep], now: Date = Date()) -> CyWatchWire.Live {
        var l = CyWatchWire.Live()
        func put(_ k: MetricKind) -> (UInt16?, UInt16) {
            guard let r = hub.reading(k), r.quality != .stale else { return (nil, CyWatchWire.absent16) }
            let scale = k == .speed ? 10.0 : 1.0
            return (UInt16(clamping: Int((r.value * scale).rounded())), UInt16(clamping: Int(now.timeIntervalSince(r.at) * 1000)))
        }
        (l.powerW, l.powerAgeMs) = put(.power); (l.hrBpm, l.hrAgeMs) = put(.heartRate); (l.cadenceRpm, l.cadenceAgeMs) = put(.cadence); (l.speedKmh10, l.speedAgeMs) = put(.speed)
        l.ftpKnown = profile.ftpKnown; l.ftpW = UInt16(clamping: profile.ftpKnown ? profile.ftpW : 0)
        l.recording = recorder.state == .running || recorder.state == .paused; l.paused = recorder.state == .paused
        l.elapsedS = UInt32(clamping: recorder.elapsedS); l.distanceM = UInt32(clamping: recorder.distanceM)
        if l.recording, let p = RideStepStrip.position(steps, at: recorder.elapsedS) {
            let s = steps[p.index]
            l.stepName = s.name; l.stepRemainingS = UInt16(clamping: p.left); l.stepTotalS = UInt16(clamping: s.minutes * 60)
            if let w = s.watts(ftp: profile.targetFTP) { l.powerBandW = (UInt16(clamping: w.lowerBound), UInt16(clamping: w.upperBound)) }
            if let z = s.hrZone, let zs = profile.hrZones, z >= 1, z <= zs.count { let b = zs[z - 1]; l.hrBandBpm = (UInt16(clamping: b.lo), UInt16(clamping: b.hi ?? (b.lo + 20))) }
        }
        return l
    }
}

/// Applies watch events to the Store (strength) and turns ride events into recorder commands. Pure decisions; the
/// coordinator supplies the side-effect closures so this is testable without Bluetooth.
enum CyWatchEvents {
    enum RideCommand: Equatable { case start, pause, resume, end, lap }
    struct Outcome: Equatable { var ride: RideCommand?; var note: String }

    /// Strength events change the Store directly; ride events are returned as a command for the recorder.
    @discardableResult
    static func apply(_ e: CyWatchWire.Event, store: Store, now: Date = Date()) -> Outcome {
        guard let k = e.kind else { return Outcome(ride: nil, note: "Unknown event kind \(e.kindRaw) ignored") }
        let planned = UUID(uuidString: e.workoutId).flatMap { id in store.plan.first { $0.id == id } }
        let isStrength = planned.map { !$0.kind.isRide } ?? (store.activeSession != nil && k == .setLogged)
        switch k {
        case .setLogged:
            if store.activeSession == nil, let w = planned, !w.kind.isRide {
                _ = store.startStrengthSession(for: w, template: nil, entries: store.plannedEntries(for: w), now: now)
            }
            guard store.activeSession != nil else { return Outcome(ride: nil, note: "Set from the watch ignored: no strength session for workout \(e.workoutId)") }
            let exerciseIx = Int(e.a) / 100, setIx = Int(e.a) % 100
            var applied = false
            store.updateActiveSession { s in
                guard var ex = s.exercises, exerciseIx < ex.count else { return }
                if setIx >= ex[exerciseIx].sets.count { ex[exerciseIx].sets.append(SetEntry(reps: Int(e.b))) }
                var st = ex[exerciseIx].sets[min(setIx, ex[exerciseIx].sets.count - 1)]
                st.done = true; st.reps = Int(e.b)
                if e.c > 0 { st.weightKg = Double(e.c) / 10; st.bodyweight = false }
                ex[exerciseIx].sets[min(setIx, ex[exerciseIx].sets.count - 1)] = st
                s.exercises = ex; applied = true
            }
            return Outcome(ride: nil, note: applied ? "Set \(setIx + 1) of exercise \(exerciseIx + 1) logged from the watch (\(e.manual ? "entered" : "counted"))" : "Set from the watch did not match the session's exercises")
        case .start:
            if isStrength, store.activeSession == nil, let w = planned { _ = store.startStrengthSession(for: w, template: nil, entries: store.plannedEntries(for: w), now: now); return Outcome(ride: nil, note: "Strength session started from the watch") }
            return isStrength ? Outcome(ride: nil, note: "Strength session already running") : Outcome(ride: .start, note: "Ride start requested from the watch")
        case .pause: if isStrength { store.pauseActiveSession(now: now); return Outcome(ride: nil, note: "Paused") }; return Outcome(ride: .pause, note: "Pause requested from the watch")
        case .resume: if isStrength { store.resumeActiveSession(now: now); return Outcome(ride: nil, note: "Resumed") }; return Outcome(ride: .resume, note: "Resume requested from the watch")
        case .lap: return Outcome(ride: .lap, note: "Lap from the watch")
        case .end: return isStrength ? Outcome(ride: nil, note: "Strength session ended on the watch; waiting for Save or Discard") : Outcome(ride: .end, note: "End requested from the watch")
        case .save:
            if isStrength || store.activeSession != nil {
                let saved = store.finishActiveSession(rpe: nil, notes: "Logged on Cyclift Watch", now: now)
                return Outcome(ride: nil, note: saved != nil ? "Strength session saved" : "Nothing to save: no set was logged (session kept open on the phone)")
            }
            return Outcome(ride: nil, note: "Save acknowledged")
        case .discard:
            if isStrength || store.activeSession != nil { store.discardActiveSession(); return Outcome(ride: nil, note: "Strength session discarded from the watch") }
            return Outcome(ride: nil, note: "Discard acknowledged")
        case .repCount: return Outcome(ride: nil, note: "Rep count \(e.b) (experimental, not stored until the set is logged)")
        }
    }
}

#if canImport(CoreBluetooth)
/// Binds a `CyWatchLink` to the app's objects. Created in the App; enabled from Connections (setting `cyWatchEnabled`).
final class CyWatchCoordinator: ObservableObject {
    let link = CyWatchLink()
    @Published private(set) var log: [String] = []
    private weak var store: Store?, hub: SensorHub?, recorder: RideRecorder?, device: DeviceLink?, location: LocationService?
    private var linkSub: AnyCancellable?
    init() { linkSub = link.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() } }

    func attach(store: Store, hub: SensorHub, recorder: RideRecorder, device: DeviceLink, location: LocationService) {
        self.store = store; self.hub = hub; self.recorder = recorder; self.device = device; self.location = location
        link.planProvider = { [weak store] in store.flatMap { CyWatchFrames.planToday(store: $0) } }
        link.cachedProvider = { [weak store] in store.map { CyWatchFrames.cached(store: $0) } }
        link.liveProvider = { [weak store, weak hub, weak recorder] in
            guard let s = store, let h = hub, let r = recorder else { return nil }
            let steps = s.today.flatMap { $0.kind.isRide ? $0.rideSteps : nil } ?? []
            return CyWatchFrames.live(hub: h, recorder: r, profile: s.profile, steps: steps)
        }
        link.gpsProvider = { [weak location] in
            guard let l = location?.last, l.horizontalAccuracy >= 0, l.horizontalAccuracy < 50, Date().timeIntervalSince(l.timestamp) < 2 else { return nil }
            return CyWatchWire.Gps(lat: l.coordinate.latitude, lon: l.coordinate.longitude, speedKmh: max(0, l.speed) * 3.6, headingDeg: max(0, l.course), at: l.timestamp, ageMs: Int(Date().timeIntervalSince(l.timestamp) * 1000))
        }
        link.session.onEvent = { [weak self] e in self?.handle(e) }
    }

    private func handle(_ e: CyWatchWire.Event) {
        guard let store, let recorder, let device else { return }
        let o = CyWatchEvents.apply(e, store: store)
        note(o.note)
        guard let cmd = o.ride else { return }
        // same one-owner rules as the Apple Watch and the phone buttons
        switch cmd {
        case .start:
            guard !recorder.isActive else { note("Ride already running — start ignored"); return }
            switch recorder.startMode(locationAuthorized: true) { case .board: device.control(.start); case .phone: _ = recorder.start(); default: note("Cannot start a ride now") }
        case .pause: if recorder.owner == .board { device.control(.pause) } else { recorder.pause() }
        case .resume: if recorder.owner == .board { device.control(.resume) } else { recorder.resume() }
        case .lap: recorder.lap()
        case .end: if recorder.owner == .board { device.control(.stopConfirm) } else { recorder.end() }   // the watch already confirmed End on its own screen
        }
    }
    private func note(_ t: String) { log.append("\(Date().formatted(date: .omitted, time: .standard)) \(t)"); if log.count > 50 { log.removeFirst(log.count - 50) } }
}
#endif
