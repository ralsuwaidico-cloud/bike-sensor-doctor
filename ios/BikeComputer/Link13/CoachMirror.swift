import Foundation

// Link 1.3 coach mirroring, phone side (BLE_CONTRACT.md §5). Cyclift's live ride coach (RideCoach, Shared/CoachCore) is
// the ONE authority: this file only turns what it runs into the board's structured messages. It decides nothing about
// training — no targets, zones or adaptations are computed here beyond reading the same plan the phone coach runs.
// The coaching engine files (Planning, StrengthPlanner, AdaptationEngine, CoachSafety, Models) are not touched; the
// app-side adapter that reads Workout / RiderProfile is `CoachMirrorAdapter` in Link13Center.swift.

/// Everything the plan builder needs, in plain values (filled by the adapter from today's Workout and the profile).
struct CoachPlanInput {
    /// Stable id of the planned session (Workout.id); nil = free ride (no session planned).
    var sessionKey: String?
    var name: String
    var type: BCLink.CoachWorkoutType
    /// Target zone of the main part, 1–5 (RideCoach.targetZone).
    var zone: Int
    /// Planned duration (Workout.minutes × 60); nil = open-ended.
    var plannedSec: Int?
    /// Interval structure the live coach runs (Workout.liveIntervalPlan); nil = one steady target.
    var intervals: IntervalPlan?
    var ftpW: Int
    /// The FTP is the rider's (entered / tested / from rides), not the onboarding assumption: watts may be the target.
    var ftpKnown: Bool
    /// The rider's heart-rate zone ranges in bpm (5 zones, zone 1 first); empty = unknown.
    var hrZones: [ClosedRange<Int>]
    var cadLo: Int, cadHi: Int
    /// RideCoach's fixed session shape (SessionPlan(warmupSec: 300, cooldownSec: 300)).
    var warmupSec = 300, cooldownSec = 300
}

/// Builds the segment list from the SAME timeline rules RideCoach.tick uses (Session.phaseAt + the interval clock), so
/// the phone and the board derive the same interval from the same ride second. Verified second by second against
/// RideCoach in CoachMirrorTests.
enum CoachPlanBuilder {
    enum Phase: Equatable { case warmup, main, work, rest, cooldown }
    struct Segment: Equatable { var phase: Phase; var start: Int; var duration: Int? }
    /// 0xFFFF = "until the ride ends" (open-ended main part of a free ride). Contract question Q-iOS-3.
    static let openEnded: UInt16 = 0xFFFF

    /// The phase timeline: [warm-up][main | work/rest × n][cool-down]. The last segment of an open-ended ride has duration nil.
    static func timeline(_ i: CoachPlanInput) -> [Segment] {
        let w = max(0, i.warmupSec)
        let cooldownStart = i.plannedSec.map { max(w, $0 - i.cooldownSec) }
        let end = i.plannedSec.map { max($0, cooldownStart ?? $0) }
        var out: [Segment] = []
        if w > 0 { out.append(Segment(phase: .warmup, start: 0, duration: w)) }
        var t = w
        if let iv = i.intervals, iv.repeats > 0, iv.workSec + iv.restSec > 0 {
            outer: for _ in 0..<iv.repeats {
                for (ph, len) in [(Phase.work, iv.workSec), (.rest, iv.restSec)] where len > 0 {
                    if let c = cooldownStart, t >= c { break outer }
                    let d = cooldownStart.map { min(len, $0 - t) } ?? len
                    out.append(Segment(phase: ph, start: t, duration: d)); t += d
                }
            }
            // after the intervals the live coach shows COOL-DOWN until the planned end (or for good when open-ended)
            if let e = end { if e > t { out.append(Segment(phase: .cooldown, start: t, duration: e - t)) } }
            else { out.append(Segment(phase: .cooldown, start: t, duration: nil)) }
        } else if let c = cooldownStart, let e = end {
            if c > t { out.append(Segment(phase: .main, start: t, duration: c - t)); t = c }
            if e > t { out.append(Segment(phase: .cooldown, start: t, duration: e - t)) }
        } else {
            out.append(Segment(phase: .main, start: t, duration: nil))
        }
        return out
    }

    /// The phase RideCoach shows at `elapsedS` according to this timeline (cool-down continues after the planned end).
    static func phase(at elapsedS: Int, _ tl: [Segment]) -> Phase? {
        for s in tl where elapsedS >= s.start && (s.duration == nil || elapsedS < s.start + s.duration!) { return s.phase }
        return tl.isEmpty ? nil : .cooldown
    }

    struct Targets: Equatable { var kind: BCLink.CoachTargetKind; var lo: Int; var hi: Int; var zone: Int; var ftpDerived: Bool }
    /// Targets of a phase: the same bands WorkoutTargets.forPhase gives RideCoach (warm-up = ramp envelope, rest and
    /// cool-down = recovery band, main/work = the session zone). Watts only when the FTP is the rider's; otherwise the
    /// rider's HR zone in bpm; nothing (ride by feel) when neither is known.
    static func targets(_ i: CoachPlanInput, phase: Phase) -> Targets {
        let z = min(5, max(1, i.zone))
        let pw = PowerZones.range(z, ftp: max(1, i.ftpW))
        let hr = i.hrZones.count >= z ? i.hrZones[z - 1] : nil
        let plan = WorkoutPlan(hrLo: hr?.lowerBound ?? 0, hrHi: hr?.upperBound ?? 0, pwLo: pw.lo, pwHi: pw.hi ?? pw.lo, cadLo: i.cadLo, cadHi: i.cadHi,
                               ftp: max(1, i.ftpW), warmupSec: i.warmupSec, cooldownSec: i.cooldownSec, plannedSec: i.plannedSec, ramps: true)
        let a: ActiveTargets
        let zone: Int
        switch phase {
        case .warmup: a = WorkoutTargets.forPhase(plan, phase: .WARMUP, elapsedSec: i.warmupSec, cooldownStartSec: nil); zone = 1
        case .rest: a = WorkoutTargets.forPhase(plan, phase: .RECOVERY, elapsedSec: 0, cooldownStartSec: nil); zone = 1
        case .cooldown: a = WorkoutTargets.forPhase(plan, phase: .RECOVERY, elapsedSec: 0, cooldownStartSec: nil); zone = 1
        case .main, .work: a = WorkoutTargets.forPhase(plan, phase: .MAIN, elapsedSec: 0, cooldownStartSec: nil); zone = z
        }
        if i.ftpKnown, i.ftpW > 0, let lo = a.pwLo, let hi = a.pwHi, hi >= lo { return Targets(kind: .powerW, lo: lo, hi: hi, zone: zone, ftpDerived: true) }
        if hr != nil, a.hrHi > 0, a.hrHi >= a.hrLo { return Targets(kind: .heartRateBpm, lo: max(0, a.hrLo), hi: a.hrHi, zone: zone, ftpDerived: false) }
        return Targets(kind: .none, lo: 0, hi: 0, zone: 0, ftpDerived: false)
    }

    static func segmentType(_ i: CoachPlanInput, _ p: Phase) -> BCLink.CoachWorkoutType {
        switch p { case .warmup: return .warmUp; case .cooldown: return .coolDown; case .rest: return .recovery; case .main, .work: return i.type }
    }

    /// The authoritative plan for the board. nil when it cannot be expressed (more than 64 segments).
    static func plan(_ i: CoachPlanInput, t0ElapsedS: UInt32) -> BCLink.CoachPlan? {
        let tl = timeline(i)
        guard !tl.isEmpty, tl.count <= BCLink.coachMaxSegments else { return nil }
        let cadOK = i.cadLo > 0 && i.cadHi >= i.cadLo && i.cadHi <= 255
        let segs = tl.map { s -> BCLink.CoachSegment in
            let t = targets(i, phase: s.phase)
            return BCLink.CoachSegment(durationS: s.duration.map { UInt16(clamping: $0) } ?? openEnded, type: segmentType(i, s.phase), targetKind: t.kind,
                                       lo: UInt16(clamping: t.lo), hi: UInt16(clamping: t.hi), cadLo: cadOK ? UInt8(i.cadLo) : 0, cadHi: cadOK ? UInt8(i.cadHi) : 0)
        }
        var p = BCLink.CoachPlan(workoutId: 0, name: i.name.uppercased(), segments: segs, t0ElapsedS: t0ElapsedS)
        p.workoutId = workoutId(i, p)
        return p
    }
    /// Stable for the same session and the same segments (t0 excluded); any change of the plan gives a new id, which
    /// replaces the stored plan on the board (§5.2). Never 0.
    static func workoutId(_ i: CoachPlanInput, _ p: BCLink.CoachPlan) -> UInt32 {
        var d = Data((i.sessionKey ?? "free").utf8); d.append(p.segmentBytes); d.append(Data(p.name.utf8))
        let c = CRC32.ieee(d) & 0x7FFF_FFFF
        return c == 0 ? 1 : c
    }
}

/// What the phone's live coach shows this second (filled from RideCoach + the hub by the adapter).
struct CoachLiveInput: Equatable {
    var elapsedS: Int
    var session: BCLink.CoachSessionState
    var cue: CueType
    var cueAction: CoachAction = .NONE
    var cueActive: Bool
    var cueShort: String = ""
    /// HR the coach uses: bc_src_t (2 board strap, 4 Apple Watch via phone, 6 phone strap, 0 none) and whether it is live now.
    var hrSource: UInt8
    var hrLive: Bool
    /// The plan was just changed by the adaptive coach (shows TARGET CHANGED once).
    var adaptedNow = false
}

enum CoachStateBuilder {
    /// Cyclift cue → the board's fixed instruction (§5.1). Cues without an exact code map to the nearest one; the
    /// optional text is used only when no code fits, never for explanations.
    static func instruction(_ c: CueType, action: CoachAction) -> (BCLink.CoachInstruction, String) {
        switch c {
        case .KEEP_IT_UP: return (.onTarget, "")
        case .STEADY, .SURGE, .PACE: return (.holdSteady, "")
        case .PEDAL_FASTER: return (.cadenceUp, "")
        case .PEDAL_SLOWER: return (.cadenceDown, "")
        case .EASE_OFF: return (action == .HR_RISING_EASE ? .hrHighEaseOff : .lessPower, "")
        case .PUSH_HARDER: return (.morePower, "")
        case .RECOVER: return (.easyRecover, "")
        case .WORK: return (.go, "")
        case .NO_HR, .NO_POWER, .SENSOR_LOST: return (.noData, "")
        case .COOLDOWN: return (.coolDown, "")
        case .WARMUP: return (.none, "WARM UP")
        case .NONE, .QUIET: return (.none, "")
        }
    }

    /// COACH_STATE content (seq filled by the sender) for `live` on `plan`.
    static func state(plan: BCLink.CoachPlan, input i: CoachPlanInput, live: CoachLiveInput) -> BCLink.CoachState {
        var s = BCLink.CoachState()
        s.workoutId = plan.workoutId
        let tl = CoachPlanBuilder.timeline(i)
        let idx = tl.lastIndex { live.elapsedS >= $0.start } ?? 0
        let seg = tl[min(idx, tl.count - 1)]
        let t = CoachPlanBuilder.targets(i, phase: seg.phase)
        s.type = CoachPlanBuilder.segmentType(i, seg.phase)
        s.targetKind = t.kind; s.targetLo = UInt16(clamping: t.lo); s.targetHi = UInt16(clamping: t.hi); s.zone = UInt8(clamping: t.zone)
        let ps = plan.segments[min(idx, plan.segments.count - 1)]
        s.cadLo = ps.cadLo; s.cadHi = ps.cadHi
        s.intervalIndex = UInt16(idx); s.intervalCount = UInt16(tl.count)
        let remaining: Int? = seg.duration.map { max(0, seg.start + $0 - live.elapsedS) }
        s.remainingS = remaining.map { UInt16(clamping: $0) } ?? CoachPlanBuilder.openEnded
        s.intervalDurationS = seg.duration.map { UInt16(clamping: $0) } ?? CoachPlanBuilder.openEnded
        if idx + 1 < tl.count {
            let n = tl[idx + 1], nt = CoachPlanBuilder.targets(i, phase: n.phase)
            s.nextType = CoachPlanBuilder.segmentType(i, n.phase); s.nextTargetKind = nt.kind
            s.nextLo = UInt16(clamping: nt.lo); s.nextHi = UInt16(clamping: nt.hi)
            s.nextDurationS = n.duration.map { UInt16(clamping: $0) } ?? CoachPlanBuilder.openEnded
        }
        s.sessionState = live.session
        switch live.session {
        case .paused: s.instruction = .paused
        case .finished: s.instruction = .workoutDone
        case .notStarted, .abandoned: s.instruction = .none
        case .running:
            if live.adaptedNow { s.instruction = .targetChanged }
            else if let r = remaining, r <= 10, r > 0, idx + 1 < tl.count { s.instruction = .getReady }
            else if live.cueActive {
                let (code, text) = instruction(live.cue, action: live.cueAction)
                s.instruction = code; s.text = text
            }
        }
        // Heart rate: the source the PHONE's coach used, stated explicitly. "Apple Watch HR live" only while it is live
        // on the phone right now — the board itself has Apple Watch HR only through the phone's IN_HR relay.
        s.hrSource = live.hrLive ? live.hrSource : 0
        var f: UInt8 = 0
        if live.adaptedNow { f |= BCLink.CoachState.flagAdapted }
        if t.ftpDerived { f |= BCLink.CoachState.flagFtpDerived }
        if live.hrLive, live.hrSource == BCLink.Source.appleWatch.rawValue { f |= BCLink.CoachState.flagWatchHRLive }
        s.flags = f
        return s
    }
}

/// The sender: plan transfer with per-part ACKs and CRC, COACH_STATE on change + 5 s keepalive + resend when the
/// board's LIVE echo lags, COACH_END. Pure and synchronous like DiagTransfer: the caller feeds board messages, LIVE
/// echoes and the clock; `send` writes one Control message.
final class CoachMirror {
    struct Config {
        var keepalive: TimeInterval = 5
        var echoLag: TimeInterval = 3
        var partTimeout: TimeInterval = 3
        var maxPartRetries = 3
        var maxCrcRetries = 3
        var busyDelay: TimeInterval = 2
    }
    enum PlanStatus: Equatable { case none, sending(part: Int), stored, failed(String) }

    var config = Config()
    var send: (Data) -> Bool
    private(set) var plan: BCLink.CoachPlan?
    private(set) var planStatus: PlanStatus = .none
    private(set) var lastState: BCLink.CoachState?
    private(set) var lastStateAt: Date?
    private(set) var statesSent = 0
    private(set) var ended: UInt32?
    private var seq: UInt16 = 0
    private var stateSeq: UInt16 = 0
    private var partSentAt: Date?
    private var partRetries = 0
    private var crcRetries = 0
    private var retryAt: Date?

    init(send: @escaping (Data) -> Bool) { self.send = send }

    /// New connection: the board's RAM plan may be gone (it keeps one plan in RAM only) → send everything again.
    func linkDown() { planStatus = plan == nil ? .none : .sending(part: -1); lastState = nil; lastStateAt = nil; partSentAt = nil; retryAt = nil }

    /// The plan Cyclift runs now (nil = nothing to mirror). A different workout_id replaces the board's plan.
    func setPlan(_ p: BCLink.CoachPlan?, now: Date) {
        guard p?.workoutId != plan?.workoutId || p?.segments != plan?.segments else { if case .sending(-1) = planStatus { sendPart(0, now: now) }; return }
        plan = p; crcRetries = 0; ended = nil
        stateSeq = 0; lastState = nil
        if p != nil { sendPart(0, now: now) } else { planStatus = .none }
    }

    /// COACH_STATE for this second: sent when the content changed, every `keepalive`, and when the board's echo lags.
    func update(state s0: BCLink.CoachState, boardEcho: UInt16?, now: Date) {
        guard plan != nil else { return }
        var due = false
        if let last = lastState, let at = lastStateAt {
            if !last.sameContent(s0) { due = true }
            else if now.timeIntervalSince(at) >= config.keepalive { due = true }
            else if boardEcho != last.seq, now.timeIntervalSince(at) >= config.echoLag { due = true }
        } else { due = true }
        guard due else { return }
        stateSeq &+= 1
        var s = s0; s.seq = stateSeq
        if let d = BCLink.encodeCoachState(s, seq: nextSeq(), tMs: 0), send(d) { lastState = s; lastStateAt = now; statesSent += 1 }
    }

    /// The workout is over / replaced / the rider stopped: one COACH_END.
    func end(_ reason: BCLink.CoachEndReason, now: Date) {
        guard let p = plan, ended != p.workoutId else { return }
        if let d = BCLink.encodeCoachEnd(workoutId: p.workoutId, reason: reason, seq: nextSeq(), tMs: 0) { _ = send(d) }
        ended = p.workoutId
        plan = nil; planStatus = .none; lastState = nil; lastStateAt = nil
    }

    /// COACH_PLAN_ACK from the board.
    func receive(_ d: Data, now: Date) {
        guard let a = BCLink.decodeCoachPlanAck(d), let p = plan, a.workoutId == p.workoutId, case .sending = planStatus else { return }
        partSentAt = nil; partRetries = 0
        switch a.status {
        case .stored: planStatus = .stored
        case .partReceived:
            if a.nextPart > 0, a.nextPart < p.partCount { sendPart(a.nextPart, now: now) } else { sendPart(0, now: now) }
        case .crcMismatch:
            crcRetries += 1
            if crcRetries > config.maxCrcRetries { planStatus = .failed("the board could not verify the workout (checksum)") } else { sendPart(0, now: now) }
        case .tooManySegments: planStatus = .failed("the workout has too many intervals for the board")
        case .busy: retryAt = now.addingTimeInterval(config.busyDelay)
        case nil: planStatus = .failed("the board answered with status \(a.statusRaw)")
        }
    }

    func tick(now: Date) {
        guard case .sending(let part) = planStatus else { return }
        if let r = retryAt, now >= r { retryAt = nil; sendPart(max(0, part), now: now); return }
        if let t = partSentAt, now.timeIntervalSince(t) >= config.partTimeout {
            partRetries += 1
            if partRetries > config.maxPartRetries { planStatus = .failed("the board did not confirm the workout"); partSentAt = nil; return }
            sendPart(max(0, part), now: now)
        }
    }

    private func sendPart(_ part: Int, now: Date) {
        guard let p = plan, let d = BCLink.encodeCoachPlan(p, part: part, seq: nextSeq(), tMs: 0) else { planStatus = .failed("the workout cannot be sent to the board"); return }
        planStatus = .sending(part: part); partSentAt = now
        _ = send(d)      /* a refused write is handled like a lost ACK: the timeout resends */
    }
    private func nextSeq() -> UInt16 { seq &+= 1; return seq }

    var statusText: String {
        switch planStatus {
        case .none: return "No workout on the board"
        case .sending: return "Sending the workout to the BikeComputer…"
        case .stored: return "Workout on the BikeComputer (works offline)"
        case .failed(let why): return "Workout not on the BikeComputer: \(why)"
        }
    }
}
