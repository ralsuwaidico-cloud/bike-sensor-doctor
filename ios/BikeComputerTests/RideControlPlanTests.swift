import XCTest
@testable import BikeComputer

/// RA-20: Pause → End → Review. End is never reachable while the ride is running.
final class RideControlPlanTests: XCTestCase {
    func testRunningShowsOnlyLapAndPause() {
        for board in [false, true] {
            let p = RideControlPlan.make(recording: true, paused: false, boardOwned: board, boardLinkLost: false)
            XCTAssertEqual(p.buttons, [.lap, .pause])
            XCTAssertFalse(p.buttons.contains(.end))
        }
    }
    func testPausedShowsResumeAndEnd() {
        XCTAssertEqual(RideControlPlan.make(recording: true, paused: true, boardOwned: false, boardLinkLost: false).buttons, [.resume, .end])
        XCTAssertEqual(RideControlPlan.make(recording: true, paused: true, boardOwned: true, boardLinkLost: false).buttons, [.resume, .end])
    }
    func testBoardLinkLostDisablesEndButKeepsResume() {
        let p = RideControlPlan.make(recording: true, paused: true, boardOwned: true, boardLinkLost: true)
        XCTAssertEqual(p.buttons, [.resume, .endDisabled])
        // a phone-owned ride never depends on the board link
        XCTAssertEqual(RideControlPlan.make(recording: true, paused: true, boardOwned: false, boardLinkLost: true).buttons, [.resume, .end])
    }
    func testNotRecordingHasNoRideControls() {
        XCTAssertEqual(RideControlPlan.make(recording: false, paused: false, boardOwned: false, boardLinkLost: false).buttons, [])
    }
    func testEndingAlwaysConfirms() {
        XCTAssertTrue(RideControlPlan.make(recording: true, paused: true, boardOwned: false, boardLinkLost: false).endConfirms)
    }
}
