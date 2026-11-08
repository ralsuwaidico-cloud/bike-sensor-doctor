import XCTest
@testable import BikeComputer

/// R-020 — ride steps to the board: targets come only from the phone's FTP state, the message set is complete or not
/// sent at all, the CRC covers every step, and the board's ack decodes. No firmware is changed or flashed by these.
final class RideStepsSyncTests: XCTestCase {
    private func profile(ftp: Int, _ src: FTPSource) -> RiderProfile { var p = RiderProfile.screened(); p.setFTP(ftp, source: src, at: Date()); return p }

    func testUnknownOrEstimatedFTPSendsNoWattTargets() {
        let w = Workout(date: Date(), kind: .tempo, minutes: 60)
        let unknown = RideStepsSync.bundle(for: w, profile: RiderProfile.screened(), version: 1)!
        XCTAssertEqual(unknown.header.ftpW, 0); XCTAssertEqual(unknown.header.ftpHow, 0)
        XCTAssertTrue(unknown.steps.allSatisfy { $0.powerLoW == 0 && $0.powerHiW == 0 }, "no FTP → no watt band on any step")
        XCTAssertTrue(unknown.steps.allSatisfy { $0.rpeLo >= 1 && $0.rpeHi <= 10 }, "RPE always present")
        // estimated: the phone's conservative target FTP (5 % lower) is what travels, with ftp_how 2
        let est = profile(ftp: 250, .estimated)
        let estimated = RideStepsSync.bundle(for: w, profile: est, version: 2)!
        XCTAssertEqual(estimated.header.ftpW, est.targetFTP!); XCTAssertEqual(estimated.header.ftpW, 238); XCTAssertEqual(estimated.header.ftpHow, 2)
        let tested = RideStepsSync.bundle(for: w, profile: profile(ftp: 250, .tested), version: 3)!
        XCTAssertEqual(tested.header.ftpW, profile(ftp: 250, .tested).targetFTP!); XCTAssertEqual(tested.header.ftpHow, 3)
        let work = tested.steps.first { $0.role == 2 }!
        XCTAssertEqual(work.powerLoW, w.rideSteps.first { $0.role == .work }!.watts(ftp: tested.header.ftpW)!.lowerBound, "bands are the phone's RideStep.watts, not the board's arithmetic")
        XCTAssertEqual(tested.steps.map(\.index), Array(0..<tested.steps.count))
        XCTAssertEqual(tested.steps.map(\.seconds), w.rideSteps.map { $0.minutes * 60 })
        XCTAssertNil(RideStepsSync.bundle(for: Workout(date: Date(), kind: .strength, minutes: 30), profile: RiderProfile.screened(), version: 1), "strength sessions are never sent as ride steps")
    }

    func testMessageSetIsCompleteAndCRCCoversEveryStep() {
        let w = Workout(date: Date(), kind: .threshold, minutes: 60)
        let b = RideStepsSync.bundle(for: w, profile: profile(ftp: 260, .tested), version: 7)!
        let msgs = try! XCTUnwrap(RideStepsSync.messages(b, seq: 10, tMs: 1000))
        XCTAssertEqual(msgs.count, b.steps.count + 2)
        XCTAssertEqual(BCLink.parse(msgs[0])!.0.type, BCLink.MsgType.stepsBegin.rawValue)
        XCTAssertEqual(BCLink.parse(msgs.last!)!.0.type, BCLink.MsgType.stepsEnd.rawValue)
        XCTAssertTrue(msgs.allSatisfy { $0.count <= BCLink.maxMessage })
        XCTAssertEqual(BCLink.parse(msgs[1])!.0.seq, 11, "sequence numbers advance per message")
        // the END crc changes when any step changes
        var altered = b.steps; altered[0].powerHiW += 1
        XCTAssertNotEqual(BCLink.stepsCRC(b.steps), BCLink.stepsCRC(altered))
        XCTAssertEqual(BCLink.stepsCRC(b.steps), BCLink.stepsCRC(b.steps.reversed()), "order of the array does not matter — the CRC is over index order")
        // header fields round-trip through the parser
        let (_, f) = BCLink.parse(msgs[0])!
        XCTAssertEqual(f.first { $0.tag == 0x05 }.map { Int(BCLink.uint($0.value)) }, b.header.ftpW)
        XCTAssertEqual(f.first { $0.tag == 0x04 }.map { Int(BCLink.uint($0.value)) }, b.steps.count)
        XCTAssertEqual(f.first { $0.tag == 0x07 }?.value.count, b.header.hrZones == nil ? nil : 10)
        // the board's ack decodes; a reply without a version is rejected
        let ack = BCLink.encodeStepsAck(.init(version: 7, status: 0, storedCount: b.steps.count), seq: 1, tMs: 0)!
        XCTAssertEqual(BCLink.decodeStepsAck(ack), .init(version: 7, status: 0, storedCount: b.steps.count))
        XCTAssertEqual(BCLink.decodeStepsAck(ack)?.statusText, "stored")
        var w2 = BCLink.Writer(type: .stepsAck, seq: 1, tMs: 0); w2.u8(0x02, 4)
        XCTAssertNil(BCLink.decodeStepsAck(w2.result!))
        XCTAssertNotNil(BCLink.encodeStepsClear(version: 8, seq: 1, tMs: 0))
        XCTAssertNil(BCLink.encodeStepsBegin(.init(version: 0, workoutId: "x", title: "t", stepCount: 1, ftpW: 0, ftpHow: 0, hrZones: nil, replace: true), seq: 0, tMs: 0), "version 0 is never sent")
    }

    func testCapabilityGateIsOffForEveryShippedFirmware() {
        var i = BCLink.Info(); i.caps = BCLink.Info.capLive | BCLink.Info.capCtrl | BCLink.Info.capDiagXfer
        XCTAssertFalse(i.hasSteps, "no shipped board reports cap 0x10000; the phone must not send steps")
        i.caps |= BCLink.Info.capSteps; XCTAssertTrue(i.hasSteps)
    }
}
