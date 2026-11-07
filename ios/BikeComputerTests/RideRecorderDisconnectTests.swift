import XCTest
@testable import BikeComputer

/// Owner correction 7 Nov 2026 (RA-20, RA-25): a disconnected device must never trap the rider in a workout.
/// A board-owned ride whose link is lost can still be paused, resumed, ended and saved on the phone; the board's
/// own record of the same ride is refused as a duplicate when it arrives later.
final class RideRecorderDisconnectTests: XCTestCase {
    private func boardFrame(rideId: Int, state: BCLink.RideState, elapsed: Int, dist: Int, w: Int? = 180) -> BCLink.Live {
        var l = BCLink.Live(); l.rideId = rideId; l.rideState = state; l.elapsedS = elapsed; l.distanceM = dist; l.powerW = w; l.cadenceRpm = 85; l.hrBpm = 140
        return l
    }

    func testBoardRideWithLostLinkCanBePausedResumedEndedAndReviewed() {
        let r = RideRecorder(autoTick: false)
        r.adoptBoardForTests(boardFrame(rideId: 7, state: .running, elapsed: 1, dist: 10))
        r.adoptBoardForTests(boardFrame(rideId: 7, state: .running, elapsed: 2, dist: 20))
        XCTAssertEqual(r.owner, .board); XCTAssertEqual(r.state, .running)
        r.markBoardLinkLostForTests()
        XCTAssertTrue(r.boardLinkLost)
        XCTAssertTrue(r.isActive, "a lost link does not end or drop the ride")

        r.pause(); XCTAssertEqual(r.state, .paused, "pause works without the board")
        r.resume(); XCTAssertEqual(r.state, .running)
        r.pause()
        r.endWithoutBoard()
        XCTAssertEqual(r.state, .ended)
        XCTAssertTrue(r.endedWithoutBoard)
        let rec = r.pendingResult
        XCTAssertNotNil(rec, "End produces a reviewable record from the phone's mirror")
        XCTAssertEqual(rec?.recorder, .board)
        XCTAssertEqual(rec?.boardRideId, 7)
        XCTAssertEqual(rec?.durationS, 2); XCTAssertEqual(rec?.distanceM, 20)
        XCTAssertTrue(rec?.sources.contains { $0.contains("link was lost") } ?? false, "the record says how it was ended")
    }

    func testEndWithoutBoardDoesNothingForPhoneRidesOrIdle() {
        let r = RideRecorder(autoTick: false)
        r.endWithoutBoard(); XCTAssertEqual(r.state, .idle)
        XCTAssertTrue(r.start()); r.endWithoutBoard()
        XCTAssertEqual(r.state, .running, "a phone-owned ride is never ended by the board path")
        r.pause(); r.end(); XCTAssertEqual(r.state, .ended)
    }

    func testBoardFrameAfterPhoneSideEndDoesNotReplaceTheReview() {
        let r = RideRecorder(autoTick: false)
        r.adoptBoardForTests(boardFrame(rideId: 9, state: .running, elapsed: 3, dist: 30))
        r.markBoardLinkLostForTests(); r.pause(); r.endWithoutBoard()
        let first = r.pendingResult?.id
        // the board comes back and reports its own end of the same ride: the review in progress must not change
        r.adoptBoardForTests(boardFrame(rideId: 9, state: .ended, elapsed: 40, dist: 400))
        XCTAssertEqual(r.pendingResult?.id, first)
        XCTAssertEqual(r.pendingResult?.durationS, 3)
    }

    func testStoreRefusesTheBoardsCopyOfARideEndedOnThePhone() {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let s = Store(directory: dir, generatePlan: false)
        var phoneCopy = RideRecord(start: Date(), durationS: 600, distanceM: 5000, recorder: .board, sources: ["BikeComputer"]); phoneCopy.boardRideId = 11; phoneCopy.boardId = "b1"
        phoneCopy.sources.append("ended on the phone while the BikeComputer link was lost")
        XCTAssertTrue(s.addRide(phoneCopy))
        var boardCopy = RideRecord(start: Date(), durationS: 1800, distanceM: 15000, recorder: .board, sources: ["BikeComputer"]); boardCopy.boardRideId = 11; boardCopy.boardId = "b1"
        XCTAssertFalse(s.addRide(boardCopy), "one completed ride creates at most one record")
        XCTAssertEqual(s.rides.count, 1)
    }
}
