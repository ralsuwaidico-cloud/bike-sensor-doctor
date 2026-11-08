import XCTest
@testable import BikeComputer

/// Checkpoint G (master order 6.5): one coherent FTP ownership model — Unknown / Entered / Estimated / Tested, each with
/// a source and a timestamp; a tested FTP is never silently replaced by an unverified estimate; targets use the current value.
final class FTPOwnershipTests: XCTestCase {
    func testEveryStateCarriesSourceAndTimestamp() {
        var p = RiderProfile.screened(); let t = Date(timeIntervalSince1970: 1_794_130_860)
        XCTAssertFalse(p.ftpKnown); XCTAssertEqual(p.ftpLabel, "Unknown")
        p.setFTP(250, source: .entered, at: t)
        XCTAssertEqual(p.ftpW, 250); XCTAssertEqual(p.ftpHow, .entered); XCTAssertEqual(p.provenance(.ftp).source, .entered); XCTAssertEqual(p.provenance(.ftp).recordedAt, t)
        p.setFTP(240, source: .estimated, at: t.addingTimeInterval(86_400))
        XCTAssertEqual(p.ftpHow, .fromRides); XCTAssertEqual(p.provenance(.ftp).source, .estimatedFromRides); XCTAssertEqual(p.provenance(.ftp).recordedAt, t.addingTimeInterval(86_400))
        p.ftpVerifiedTest = true; p.setFTP(262, source: .tested, at: t.addingTimeInterval(2 * 86_400))
        XCTAssertEqual(p.ftpHow, .tested); XCTAssertEqual(p.provenance(.ftp).source, .measuredTest)
        p.setFTP(nil, source: .unknown)
        XCTAssertFalse(p.ftpKnown); XCTAssertEqual(p.ftpW, 0); XCTAssertEqual(p.provenance(.ftp).source, .unknown)
    }
    func testAcceptingASuggestionWritesValueSourceAndTimestampTogether() {
        let d = FileManager.default.temporaryDirectory.appendingPathComponent("ftp-\(UUID().uuidString)"); try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        let s = Store(directory: d, generatePlan: false)
        var p = RiderProfile.screened(); p.ftpVerifiedTest = true; p.setFTP(262, source: .tested, at: Date(timeIntervalSince1970: 1_794_000_000)); s.profile = p
        let rideDate = Date(timeIntervalSince1970: 1_794_130_860)
        s.ftpSuggestion = FTPSuggestion(watts: 240, best20: 253, best60: nil, rideId: UUID(), rideDate: rideDate, previousFTP: 262)
        XCTAssertEqual(s.profile.ftpW, 262, "a suggestion alone changes nothing — the tested FTP stands until the athlete accepts")
        s.acceptFTPSuggestion()
        XCTAssertEqual(s.profile.ftpW, 240); XCTAssertEqual(s.profile.ftpHow, .fromRides, "an unverified ride → estimate, chosen explicitly")
        XCTAssertEqual(s.profile.provenance(.ftp).source, .estimatedFromRides); XCTAssertEqual(s.profile.provenance(.ftp).recordedAt, rideDate, "the timestamp is the ride's date")
        XCTAssertEqual(s.profile.ftpFromDate, rideDate)
    }
    func testZonesAndTargetsUseTheCurrentValue() {
        var p = RiderProfile.screened(); p.setFTP(200, source: .entered)
        let z200 = p.powerZones.map(\.lo); p.setFTP(250, source: .entered); let z250 = p.powerZones.map(\.lo)
        XCTAssertNotEqual(z200, z250, "zones follow the current FTP"); XCTAssertEqual(z250.count, z200.count)
        XCTAssertEqual(p.zone(forWatts: 214), p.zone(forWatts: 214), "zone lookup is deterministic for the current value")
        p.setFTP(nil, source: .unknown); XCTAssertTrue(p.powerZones.isEmpty, "unknown FTP → no zones, no watt targets")
    }
}
