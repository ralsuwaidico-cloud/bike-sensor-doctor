import XCTest
@testable import BikeComputer

final class WatchMessageTests: XCTestCase {
    func testPingPongRoundTrip() {
        let sent = Date(timeIntervalSince1970: 1_800_000_000)
        let ping = WatchMessage.makePing(now: sent)
        XCTAssertEqual(ping[WatchMessage.kind] as? String, WatchMessage.ping)

        let pong = WatchMessage.makePong(for: ping, build: "0.1.0 (7)")
        XCTAssertEqual(pong[WatchMessage.kind] as? String, WatchMessage.pong)
        XCTAssertEqual(pong[WatchMessage.build] as? String, "0.1.0 (7)")

        let ms = WatchMessage.roundTripMs(of: pong, now: sent.addingTimeInterval(0.042))
        XCTAssertEqual(ms, 42)
    }

    func testRejectsInvalidReplies() {
        let now = Date()
        XCTAssertNil(WatchMessage.roundTripMs(of: [:], now: now))
        XCTAssertNil(WatchMessage.roundTripMs(of: [WatchMessage.kind: WatchMessage.ping, WatchMessage.sentAt: now.timeIntervalSince1970], now: now))
        // A reply "from the future" or far too old is not a valid measurement.
        XCTAssertNil(WatchMessage.roundTripMs(of: [WatchMessage.kind: WatchMessage.pong, WatchMessage.sentAt: now.timeIntervalSince1970 + 5], now: now))
        XCTAssertNil(WatchMessage.roundTripMs(of: [WatchMessage.kind: WatchMessage.pong, WatchMessage.sentAt: now.timeIntervalSince1970 - 600], now: now))
    }

    func testVersionLabelIsReadFromBundle() {
        XCTAssertFalse(AppInfo.label.isEmpty)
    }
}
