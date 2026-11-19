import XCTest
@testable import BikeComputer

/// Navigation v1.2, sheet F4: the Train ball's state is built from plain facts about the one session
/// (Shell/CyTrainBallState.swift — Foundation only).
final class TrainBallStateTests: XCTestCase {
    private func strength(_ elapsed: Int, paused: Bool = false, all: Bool = false, failed: Bool = false, restored: Bool = false) -> CyTrainBallInput {
        var i = CyTrainBallInput()
        i.strength = .init(elapsed: elapsed, paused: paused, allSetsLogged: all, saveFailed: failed, restored: restored)
        return i
    }

    func testTimerFormatsFollowTheApprovedRule() {
        XCTAssertEqual(CyTrainBallState.clock(0), "00:00")
        XCTAssertEqual(CyTrainBallState.clock(846), "14:06")
        XCTAssertEqual(CyTrainBallState.clock(3599), "59:59")
        XCTAssertEqual(CyTrainBallState.clock(3600), "1h00")
        XCTAssertEqual(CyTrainBallState.clock(3840 + 59), "1h04")
        XCTAssertEqual(CyTrainBallState.clock(9000), "2h30")
        XCTAssertEqual(CyTrainBallState.clock(36720), "10h12")
        XCTAssertEqual(CyTrainBallState.clock(-5), "00:00")
    }

    func testIdleAndPanelOpen() {
        let idle = CyTrainBallState.make(CyTrainBallInput())
        XCTAssertEqual(idle, .idle); XCTAssertEqual(idle.ring, .none); XCTAssertEqual(idle.badge, .none); XCTAssertNil(idle.timerText)
        XCTAssertEqual(idle.spoken, "Train, no active session"); XCTAssertFalse(idle.hasSession)
        var i = CyTrainBallInput(); i.panelOpen = true
        let open = CyTrainBallState.make(i)
        XCTAssertEqual(open, .panelOpen); XCTAssertEqual(open.spoken, "Train, panel open"); XCTAssertNil(open.timerText)
    }

    func testStrengthRecordingAndPaused() {
        let rec = CyTrainBallState.make(strength(846))
        XCTAssertEqual(rec, .strengthRecording(846)); XCTAssertEqual(rec.ring, .segmented); XCTAssertEqual(rec.badge, .dot)
        XCTAssertEqual(rec.timerText, "14:06"); XCTAssertEqual(rec.spoken, "Strength workout recording, 14 minutes elapsed")
        let paused = CyTrainBallState.make(strength(846, paused: true))
        XCTAssertEqual(paused, .paused(846, ride: false)); XCTAssertEqual(paused.ring, .split); XCTAssertEqual(paused.badge, .pauseBars)
        XCTAssertEqual(paused.timerText, "14:06"); XCTAssertEqual(paused.spoken, "Workout paused, 14 minutes elapsed")
        // a session keeps the ball even while the panel is open: one session at a time
        var i = strength(10); i.panelOpen = true
        XCTAssertEqual(CyTrainBallState.make(i), .strengthRecording(10))
    }

    func testCompletionPendingSaveUncertainAndRestored() {
        let pending = CyTrainBallState.make(strength(1200, all: true))
        XCTAssertEqual(pending, .completionPending); XCTAssertEqual(pending.ring, .threeQuarter); XCTAssertEqual(pending.badge, .ellipsis); XCTAssertNil(pending.timerText)
        // Finish pauses the clock: all sets logged and paused is still "completion pending", not "paused"
        XCTAssertEqual(CyTrainBallState.make(strength(1200, paused: true, all: true)), .completionPending)
        let failed = CyTrainBallState.make(strength(1200, paused: true, all: true, failed: true))
        XCTAssertEqual(failed, .saveUncertain); XCTAssertEqual(failed.ring, .dotted); XCTAssertEqual(failed.badge, .exclamation); XCTAssertNil(failed.timerText)
        XCTAssertEqual(failed.spoken, "Workout not confirmed saved")
        var u = CyTrainBallInput(); u.saveUnconfirmed = true; u.panelOpen = true
        XCTAssertEqual(CyTrainBallState.make(u), .saveUncertain, "an unconfirmed save is never hidden by the panel")
        let restored = CyTrainBallState.make(strength(846, paused: true, restored: true))
        XCTAssertEqual(restored, .restored(846)); XCTAssertEqual(restored.ring, .split); XCTAssertEqual(restored.badge, .restore)
        XCTAssertEqual(restored.spoken, "Workout restored, paused, 14 minutes elapsed")
        // once resumed it is an ordinary recording again
        XCTAssertEqual(CyTrainBallState.make(strength(846, paused: false, restored: true)), .strengthRecording(846))
    }

    func testCyclingInput() {
        var i = CyTrainBallInput(); i.cycling = .init(elapsed: 1476, paused: false, simulated: false)
        let ride = CyTrainBallState.make(i)
        XCTAssertEqual(ride, .rideRecording(1476, simulated: false)); XCTAssertEqual(ride.ring, .solid); XCTAssertEqual(ride.badge, .dot)
        XCTAssertEqual(ride.timerText, "24:36"); XCTAssertEqual(ride.spoken, "Ride recording, 24 minutes elapsed")
        i.cycling = .init(elapsed: 1476, paused: true, simulated: false)
        XCTAssertEqual(CyTrainBallState.make(i), .paused(1476, ride: true)); XCTAssertEqual(CyTrainBallState.make(i).spoken, "Ride paused, 24 minutes elapsed")
        i.cycling = .init(elapsed: 60, paused: false, simulated: true)
        XCTAssertTrue(CyTrainBallState.make(i).spoken.hasPrefix("Demonstration ride, nothing is recorded"), "a simulated ride is never spoken as a recording")
    }

    func testSpokenElapsed() {
        XCTAssertEqual(CyTrainBallState.spokenElapsed(20), "less than a minute elapsed")
        XCTAssertEqual(CyTrainBallState.spokenElapsed(60), "1 minute elapsed")
        XCTAssertEqual(CyTrainBallState.spokenElapsed(3600), "1 hour elapsed")
        XCTAssertEqual(CyTrainBallState.spokenElapsed(3840), "1 hour 4 minutes elapsed")
    }
}
