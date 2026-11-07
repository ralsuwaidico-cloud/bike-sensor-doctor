import XCTest
@testable import BikeComputer

/// RA-20: Pause → End → Review. End is never reachable while the ride is running — and ALWAYS reachable once paused,
/// whatever device has disconnected (owner correction, 7 Nov 2026).
final class RideControlPlanTests: XCTestCase {
    func testRunningShowsOnlyLapAndPause() {
        for board in [false, true] { for lost in [false, true] {
            let p = RideControlPlan.make(recording: true, paused: false, boardOwned: board, boardLinkLost: lost)
            XCTAssertEqual(p.buttons, [.lap, .pause])
        } }
    }
    func testPausedAlwaysShowsResumeAndEnd() {
        for board in [false, true] { for lost in [false, true] {
            let p = RideControlPlan.make(recording: true, paused: true, boardOwned: board, boardLinkLost: lost)
            XCTAssertEqual(p.buttons, [.resume, .end], "board=\(board) lost=\(lost)")
        } }
    }
    func testEndRouteFollowsTheRecorderAndFallsBackToThePhoneCopy() {
        XCTAssertEqual(RideControlPlan.make(recording: true, paused: true, boardOwned: false, boardLinkLost: false).endRoute, .phone)
        XCTAssertEqual(RideControlPlan.make(recording: true, paused: true, boardOwned: false, boardLinkLost: true).endRoute, .phone)   // the board is irrelevant to a phone ride
        XCTAssertEqual(RideControlPlan.make(recording: true, paused: true, boardOwned: true, boardLinkLost: false).endRoute, .board)
        XCTAssertEqual(RideControlPlan.make(recording: true, paused: true, boardOwned: true, boardLinkLost: true).endRoute, .phoneCopyBoardUnreachable)
    }
    func testSyncNoticeOnlyWhenTheBoardIsUnreachable() {
        XCTAssertNil(RideControlPlan.make(recording: true, paused: true, boardOwned: true, boardLinkLost: false).syncNotice)
        XCTAssertNil(RideControlPlan.make(recording: true, paused: true, boardOwned: false, boardLinkLost: true).syncNotice)
        XCTAssertNotNil(RideControlPlan.make(recording: true, paused: true, boardOwned: true, boardLinkLost: true).syncNotice)
    }
    func testNotRecordingHasNoRideControls() {
        XCTAssertEqual(RideControlPlan.make(recording: false, paused: false, boardOwned: false, boardLinkLost: false).buttons, [])
    }
    func testEndingAlwaysConfirms() {
        XCTAssertTrue(RideControlPlan.make(recording: true, paused: true, boardOwned: true, boardLinkLost: true).endConfirms)
    }
}
