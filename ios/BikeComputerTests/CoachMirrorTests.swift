import XCTest
@testable import BikeComputer

/// Coach mirroring (BLE_CONTRACT.md §5): the plan the board gets is the timeline the phone coach runs, the sender
/// follows the ACK / CRC / keepalive rules, and heart-rate claims are explicit.
final class CoachMirrorTests: XCTestCase {
    private let hrZones: [ClosedRange<Int>] = [95...113, 114...132, 133...151, 152...170, 171...190]
    private func input(type: BCLink.CoachWorkoutType = .endurance, zone: Int = 2, planned: Int? = 3600, intervals: IntervalPlan? = nil, ftpKnown: Bool = true) -> CoachPlanInput {
        CoachPlanInput(sessionKey: "session-1", name: "Endurance", type: type, zone: zone, plannedSec: planned, intervals: intervals, ftpW: 220, ftpKnown: ftpKnown,
                       hrZones: hrZones, cadLo: 85, cadHi: 95)
    }

    /// RideCoach's phase rule (RideDashboard.swift `tick`), restated without SwiftUI so it also runs on Linux; the CI
    /// test below checks the real RideCoach as well.
    private func coachPhase(_ i: CoachPlanInput, _ t: Int) -> CoachPlanBuilder.Phase {
        let plan = SessionPlan(warmupSec: i.warmupSec, cooldownSec: i.cooldownSec, plannedSec: i.plannedSec)
        let ph = Session.phaseAt(plan, elapsedMs: Int64(t) * 1000, cooldownRequestedAtMs: nil)
        switch ph {
        case .WARMUP: return .warmup
        case .COOLDOWN, .RECOVERY: return .cooldown
        case .MAIN:
            guard let iv = i.intervals else { return .main }
            let x = t - i.warmupSec, cycle = iv.workSec + iv.restSec
            return x >= cycle * iv.repeats ? .cooldown : (x % cycle) >= iv.workSec ? .rest : .work
        }
    }

    func testTimelineMatchesThePhoneCoachEverySecond() {
        let cases: [CoachPlanInput] = [
            input(), input(planned: 45 * 60), input(planned: 4 * 60), input(planned: nil),
            input(type: .threshold, zone: 4, planned: 60 * 60, intervals: IntervalPlan(workSec: 480, restSec: 180, repeats: 3)),
            input(type: .vo2max, zone: 5, planned: 60 * 60, intervals: IntervalPlan(workSec: 180, restSec: 180, repeats: 5)),
            input(type: .vo2max, zone: 5, planned: 30 * 60, intervals: IntervalPlan(workSec: 180, restSec: 180, repeats: 8)),     /* truncated by the cool-down */
            input(type: .threshold, zone: 4, planned: nil, intervals: IntervalPlan(workSec: 480, restSec: 180, repeats: 3)),
        ]
        for i in cases {
            let tl = CoachPlanBuilder.timeline(i)
            XCTAssertFalse(tl.isEmpty)
            for (a, b) in zip(tl, tl.dropFirst()) { XCTAssertEqual(a.start + (a.duration ?? 0), b.start, "contiguous") }
            for t in 0..<((i.plannedSec ?? 7200) + 600) {
                XCTAssertEqual(CoachPlanBuilder.phase(at: t, tl), coachPhase(i, t), "planned \(String(describing: i.plannedSec)) t=\(t)")
            }
        }
        let th = CoachPlanBuilder.timeline(cases[4])
        XCTAssertEqual(th.map { $0.phase }, [.warmup, .work, .rest, .work, .rest, .work, .rest, .cooldown])
        XCTAssertEqual(th.last?.start, 300 + 3 * 660); XCTAssertEqual(th.last?.duration, 3600 - 2280)
        XCTAssertEqual(CoachPlanBuilder.timeline(cases[3]).last?.duration, nil, "free ride: open-ended main part")
    }

    func testPlanTargetsFollowTheRidersNumbers() throws {
        let p = try XCTUnwrap(CoachPlanBuilder.plan(input(), t0ElapsedS: BCLink.coachT0AtRideStart))
        XCTAssertEqual(p.segments.map { $0.type }, [.warmUp, .endurance, .coolDown])
        XCTAssertEqual(p.segments.map { $0.durationS }, [300, 3000, 300])
        let z2 = PowerZones.range(2, ftp: 220)
        XCTAssertEqual(p.segments[1].targetKind, .powerW); XCTAssertEqual(Int(p.segments[1].lo), z2.lo); XCTAssertEqual(Int(p.segments[1].hi), z2.hi)
        XCTAssertEqual(p.segments[1].cadLo, 85); XCTAssertEqual(p.segments[1].cadHi, 95)
        XCTAssertEqual(p.name, "ENDURANCE")
        // the onboarding FTP is an assumption → heart-rate zone targets, never invented watts
        let hr = try XCTUnwrap(CoachPlanBuilder.plan(input(ftpKnown: false), t0ElapsedS: 0))
        XCTAssertEqual(hr.segments[1].targetKind, .heartRateBpm); XCTAssertEqual(hr.segments[1].lo, 114); XCTAssertEqual(hr.segments[1].hi, 132)
        var none = input(ftpKnown: false); none.hrZones = []
        XCTAssertEqual(try XCTUnwrap(CoachPlanBuilder.plan(none, t0ElapsedS: 0)).segments[1].targetKind, .none, "nothing known: ride by feel")
        // id: stable for the same plan, new when the plan changes (FTP update) — t0 excluded
        XCTAssertEqual(CoachPlanBuilder.plan(input(), t0ElapsedS: 0)?.workoutId, p.workoutId)
        var other = input(); other.ftpW = 250
        XCTAssertNotEqual(CoachPlanBuilder.plan(other, t0ElapsedS: 0)?.workoutId, p.workoutId)
        XCTAssertNotEqual(p.workoutId, 0)
        let free = try XCTUnwrap(CoachPlanBuilder.plan(input(planned: nil), t0ElapsedS: 0))
        XCTAssertEqual(free.segments.last?.durationS, CoachPlanBuilder.openEnded)
    }

    func testStateInstructionsAndHeartRateClaims() throws {
        let i = input()
        let p = try XCTUnwrap(CoachPlanBuilder.plan(i, t0ElapsedS: 0))
        var live = CoachLiveInput(elapsedS: 600, session: .running, cue: .KEEP_IT_UP, cueActive: true, hrSource: BCLink.Source.appleWatch.rawValue, hrLive: true)
        var s = CoachStateBuilder.state(plan: p, input: i, live: live)
        XCTAssertEqual(s.workoutId, p.workoutId); XCTAssertEqual(s.intervalIndex, 1); XCTAssertEqual(s.intervalCount, 3); XCTAssertEqual(s.remainingS, 3300 - 600)
        XCTAssertEqual(s.instruction, .onTarget); XCTAssertEqual(s.nextType, .coolDown); XCTAssertEqual(s.nextDurationS, 300); XCTAssertEqual(s.zone, 2)
        XCTAssertEqual(s.hrSource, 4); XCTAssertEqual(s.flags & BCLink.CoachState.flagWatchHRLive, BCLink.CoachState.flagWatchHRLive)
        XCTAssertEqual(s.flags & BCLink.CoachState.flagFtpDerived, BCLink.CoachState.flagFtpDerived)
        // the watch HR is not live on the phone → no source claimed, no flag
        live.hrLive = false
        s = CoachStateBuilder.state(plan: p, input: i, live: live)
        XCTAssertEqual(s.hrSource, 0); XCTAssertEqual(s.flags & BCLink.CoachState.flagWatchHRLive, 0)
        // a board strap is named as such and never flagged as the watch
        live.hrLive = true; live.hrSource = BCLink.Source.bleStrap.rawValue
        s = CoachStateBuilder.state(plan: p, input: i, live: live)
        XCTAssertEqual(s.hrSource, 2); XCTAssertEqual(s.flags & BCLink.CoachState.flagWatchHRLive, 0)
        // ≤ 10 s before the next interval: GET READY; paused; done; last interval has no next
        live.elapsedS = 3292
        XCTAssertEqual(CoachStateBuilder.state(plan: p, input: i, live: live).instruction, .getReady)
        live.session = .paused
        XCTAssertEqual(CoachStateBuilder.state(plan: p, input: i, live: live).instruction, .paused)
        live.session = .finished
        XCTAssertEqual(CoachStateBuilder.state(plan: p, input: i, live: live).instruction, .workoutDone)
        live.session = .running; live.elapsedS = 3500
        let last = CoachStateBuilder.state(plan: p, input: i, live: live)
        XCTAssertNil(last.nextType); XCTAssertEqual(last.type, .coolDown)
        // cue mapping: every Cyclift cue maps to a code or a ≤ 24-byte word, never a sentence
        for c in [CueType.NONE, .KEEP_IT_UP, .PEDAL_FASTER, .PEDAL_SLOWER, .EASE_OFF, .PUSH_HARDER, .RECOVER, .WORK, .NO_HR, .NO_POWER, .WARMUP, .COOLDOWN, .QUIET, .SURGE, .STEADY, .SENSOR_LOST, .PACE] {
            let (_, text) = CoachStateBuilder.instruction(c, action: .NONE)
            XCTAssertLessThanOrEqual(text.utf8.count, 24)
        }
        XCTAssertEqual(CoachStateBuilder.instruction(.EASE_OFF, action: .HR_RISING_EASE).0, .hrHighEaseOff)
        XCTAssertEqual(CoachStateBuilder.instruction(.EASE_OFF, action: .REDUCE_PRESSURE).0, .lessPower)
        XCTAssertEqual(CoachStateBuilder.instruction(.SENSOR_LOST, action: .NONE).0, .noData)
    }

    // MARK: sender
    final class FakeBoard {
        var sent: [Data] = []
        var types: [UInt8] { sent.compactMap { $0.first } }
        func lastPlanPart() -> BCLink.CoachPlanPart? { sent.last(where: { $0.first == 0xB0 }).flatMap(BCLink.decodeCoachPlan) }
    }

    func testPlanTransferWithPartAcksCrcRetryAndTimeouts() throws {
        let seg = BCLink.CoachSegment(durationS: 60, type: .vo2max, targetKind: .powerW, lo: 300, hi: 340, cadLo: 95, cadHi: 105)
        let plan = BCLink.CoachPlan(workoutId: 77, name: "VO2", segments: Array(repeating: seg, count: 20), t0ElapsedS: 0)
        let b = FakeBoard(); let m = CoachMirror { b.sent.append($0); return true }
        let t0 = Date(timeIntervalSince1970: 0)
        m.setPlan(plan, now: t0)
        XCTAssertEqual(b.lastPlanPart()?.part, 0); XCTAssertEqual(m.planStatus, .sending(part: 0))
        m.receive(BCLink.encodeCoachPlanAck(.init(workoutId: 77, statusRaw: 1, nextPart: 1), seq: 1, tMs: 0), now: t0)
        XCTAssertEqual(b.lastPlanPart()?.part, 1)
        m.receive(BCLink.encodeCoachPlanAck(.init(workoutId: 99, statusRaw: 0, nextPart: 0), seq: 2, tMs: 0), now: t0)
        XCTAssertEqual(m.planStatus, .sending(part: 1), "an ACK for another workout is ignored")
        m.receive(BCLink.encodeCoachPlanAck(.init(workoutId: 77, statusRaw: 3, nextPart: 0), seq: 3, tMs: 0), now: t0)
        XCTAssertEqual(b.lastPlanPart()?.part, 0, "CRC mismatch → the whole plan again")
        m.receive(BCLink.encodeCoachPlanAck(.init(workoutId: 77, statusRaw: 1, nextPart: 1), seq: 4, tMs: 0), now: t0)
        m.receive(BCLink.encodeCoachPlanAck(.init(workoutId: 77, statusRaw: 0, nextPart: 0), seq: 5, tMs: 0), now: t0)
        XCTAssertEqual(m.planStatus, .stored)
        // same plan again: nothing resent; a reconnect sends it again (the board keeps it in RAM only)
        let n = b.sent.count
        m.setPlan(plan, now: t0); XCTAssertEqual(b.sent.count, n)
        m.linkDown(); m.setPlan(plan, now: t0); XCTAssertEqual(b.sent.count, n + 1)
        // unanswered parts: resent, then reported as failed (nothing claimed)
        for k in 1...4 { m.tick(now: t0.addingTimeInterval(Double(k) * 3.1)) }
        if case .failed = m.planStatus {} else { XCTFail("expected failure after retries, got \(m.planStatus)") }
        XCTAssertTrue(m.statusText.hasPrefix("Workout not on the BikeComputer"))
    }

    func testStateOnChangeKeepaliveEchoAndEnd() throws {
        let b = FakeBoard(); let m = CoachMirror { b.sent.append($0); return true }
        let t0 = Date(timeIntervalSince1970: 0)
        var s = BCLink.CoachState(); s.instruction = .onTarget; s.sessionState = .running
        m.update(state: s, boardEcho: nil, now: t0)
        XCTAssertTrue(b.types.isEmpty, "no state before a plan exists")
        let plan = BCLink.CoachPlan(workoutId: 5, name: "E", segments: [BCLink.CoachSegment(durationS: 60, type: .endurance, targetKind: .none, lo: 0, hi: 0, cadLo: 0, cadHi: 0)], t0ElapsedS: 0)
        m.setPlan(plan, now: t0); b.sent = []
        s.workoutId = 5
        m.update(state: s, boardEcho: nil, now: t0)
        XCTAssertEqual(b.types, [0xB2]); XCTAssertEqual(m.lastState?.seq, 1)
        m.update(state: s, boardEcho: 1, now: t0.addingTimeInterval(1))
        XCTAssertEqual(b.sent.count, 1, "unchanged and echoed: nothing")
        s.instruction = .morePower
        m.update(state: s, boardEcho: 1, now: t0.addingTimeInterval(2))
        XCTAssertEqual(b.sent.count, 2); XCTAssertEqual(m.lastState?.seq, 2)
        m.update(state: s, boardEcho: 1, now: t0.addingTimeInterval(4))
        XCTAssertEqual(b.sent.count, 2, "echo lags only 2 s")
        m.update(state: s, boardEcho: 1, now: t0.addingTimeInterval(5.1))
        XCTAssertEqual(b.sent.count, 3, "echo lags > 3 s → resend with a newer seq")
        XCTAssertEqual(BCLink.decodeCoachState(b.sent.last!)?.seq, 3)
        m.update(state: s, boardEcho: 3, now: t0.addingTimeInterval(10.2))
        XCTAssertEqual(b.sent.count, 4, "5 s keepalive")
        m.end(.completed, now: t0.addingTimeInterval(11)); m.end(.completed, now: t0.addingTimeInterval(12))
        XCTAssertEqual(b.types.filter { $0 == 0xB3 }.count, 1, "one COACH_END")
        m.update(state: s, boardEcho: 3, now: t0.addingTimeInterval(20))
        XCTAssertEqual(b.types.last, 0xB3, "nothing after the end")
    }

    /// The real RideCoach (CI only: it lives in a SwiftUI file) shows the same phase as the plan the board gets.
    func testRideCoachPhaseMatchesTheBoardPlan() {
        let coach = RideCoach()
        var w = Workout(date: Date(), kind: .threshold, minutes: 60)
        w.intervalReps = 3
        coach.configure(profile: RiderProfile(), settings: AppSettings(), workout: w, powerTrusted: false)
        let i = CoachPlanInput(sessionKey: "x", name: "T", type: .threshold, zone: 4, plannedSec: 3600, intervals: w.liveIntervalPlan, ftpW: 220, ftpKnown: true, hrZones: [], cadLo: 85, cadHi: 95)
        let tl = CoachPlanBuilder.timeline(i)
        for t in 0..<4000 {
            coach.tick(elapsedS: t, cadence: 90, hr: nil, power: 200, speedKmh: 30)
            let expect: Phase
            switch CoachPlanBuilder.phase(at: t, tl)! { case .warmup: expect = .WARMUP; case .main, .work: expect = .MAIN; case .rest: expect = .RECOVERY; case .cooldown: expect = .COOLDOWN }
            XCTAssertEqual(coach.phase, expect, "t=\(t)")
            if coach.phase != expect { break }
        }
    }
}
