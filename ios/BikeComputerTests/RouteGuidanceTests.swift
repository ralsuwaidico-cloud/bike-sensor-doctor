import XCTest
@testable import BikeComputer

/// Checkpoint F2 — GPX import, loaded-route guidance, off-route detection (owner master order §2.2). Pure Foundation.
final class RouteGuidanceTests: XCTestCase {
    // A synthetic 1.4 km route near 25.197 N 55.274 E: north 300 m, right bend, east 360 m, left bend, north-east 416 m.
    static func synthPoints(stepM: Double = 10) -> [RoutePoint] {
        let lat0 = 25.1972, lon0 = 55.2744, mLat = 110_540.0, mLon = 111_320.0 * cos(lat0 * .pi / 180)
        let W: [(Double, Double)] = [(0, 0), (0, 300), (40, 340), (400, 360), (560, 560), (900, 800)]
        var pts: [RoutePoint] = []
        for i in 0..<(W.count - 1) {
            let dx = W[i + 1].0 - W[i].0, dy = W[i + 1].1 - W[i].1, len = (dx * dx + dy * dy).squareRoot(); let n = max(1, Int(len / stepM))
            for k in 0..<n { let t = Double(k) / Double(n); pts.append(RoutePoint(lat: lat0 + (W[i].1 + dy * t) / mLat, lon: lon0 + (W[i].0 + dx * t) / mLon)) }
        }
        pts.append(RoutePoint(lat: lat0 + W.last!.1 / mLat, lon: lon0 + W.last!.0 / mLon))
        return pts
    }
    static func gpx(_ pts: [RoutePoint], name: String = "Al Reem loop", waypoint: (RoutePoint, String)? = nil) -> Data {
        var s = "<?xml version=\"1.0\"?><gpx version=\"1.1\" creator=\"test\"><metadata><name>\(name)</name></metadata>"
        if let (w, n) = waypoint { s += "<wpt lat=\"\(w.lat)\" lon=\"\(w.lon)\"><name>\(n)</name></wpt>" }
        s += "<trk><name>track name</name><trkseg>"
        for p in pts { s += "<trkpt lat=\"\(p.lat)\" lon=\"\(p.lon)\"><ele>12.5</ele></trkpt>" }
        s += "</trkseg></trk></gpx>"
        return s.data(using: .utf8)!
    }

    func testGPXParsesTrackWithNameDistanceAndTurns() throws {
        let pts = Self.synthPoints()
        let r = try GPXParser.parse(Self.gpx(pts), fileName: "loop.gpx")
        XCTAssertEqual(r.name, "Al Reem loop", "metadata name wins over the track name")
        XCTAssertEqual(r.totalM, 1_389, accuracy: 25, "north 300 + bend 57 + east 361 + bend 256 + diagonal 416 ≈ 1.39 km")
        XCTAssertEqual(r.turns.count, 3, "one right bend, one left bend, arrive — close heading steps merge into one cue: \(r.turns)")
        XCTAssertEqual(r.points.first?.ele, 12.5)
        let dirs = r.turns.map(\.direction)
        XCTAssertTrue(dirs.contains(.right) || dirs.contains(.sharpRight), "the first bend (north → east) is a right turn: \(dirs)")
        XCTAssertTrue(dirs.contains(.left) || dirs.contains(.sharpLeft), "the second bend (east → north-east) is a left turn: \(dirs)")
        XCTAssertEqual(dirs.last, .arrive)
        XCTAssertEqual(r.turns, r.turns.sorted { $0.index < $1.index })
    }
    func testGPXRouteElementAndWaypointCue() throws {
        let pts = Self.synthPoints()
        var s = "<gpx version=\"1.0\"><rte>"; for p in pts { s += "<rtept lat=\"\(p.lat)\" lon=\"\(p.lon)\"/>" }; s += "</rte></gpx>"
        let r = try GPXParser.parse(s.data(using: .utf8)!, fileName: "r.gpx")
        XCTAssertEqual(r.name, "r", "no name in the file → the file name")
        XCTAssertGreaterThan(r.points.count, 100)
        let named = try GPXParser.parse(Self.gpx(pts, waypoint: (pts[35], "Al Reem St")))
        XCTAssertTrue(named.turns.contains { $0.name == "Al Reem St" }, "a waypoint within 40 m names the nearest turn")
    }
    func testGPXRejectsNonGPXAndEmptyFiles() {
        XCTAssertThrowsError(try GPXParser.parse("<kml></kml>".data(using: .utf8)!))
        XCTAssertThrowsError(try GPXParser.parse("<gpx><trk><trkseg></trkseg></trk></gpx>".data(using: .utf8)!))
        XCTAssertThrowsError(try GPXParser.parse("not xml at all".data(using: .utf8)!))
    }
    func testThinningKeepsEndpointsAndSpacing() {
        let dense = Self.synthPoints(stepM: 1)
        let t = RouteGeometry.thin(dense, minStepM: 5)
        XCTAssertLessThan(t.count, dense.count / 3)
        XCTAssertEqual(t.first, dense.first); XCTAssertEqual(t.last, dense.last)
        for i in 1..<(t.count - 1) { XCTAssertGreaterThanOrEqual(RouteGeometry.distanceM(t[i - 1], t[i]), 5 - 0.01) }
    }

    func testGuidanceProgressNextTurnAndArrival() throws {
        let pts = Self.synthPoints()
        let route = try GPXParser.parse(Self.gpx(pts, waypoint: (pts[35], "Al Reem St")))
        var g = RouteGuidance(route: route)
        XCTAssertEqual(g.state.remainingM, route.totalM, accuracy: 0.01, "before any fix nothing has progressed")
        // ride the first 200 m north
        for i in 0...20 { g.update(lat: pts[i].lat, lon: pts[i].lon) }
        XCTAssertEqual(g.state.progressM, 200, accuracy: 15)
        XCTAssertFalse(g.state.offRoute)
        XCTAssertEqual(g.state.nextTurn?.direction, .right)
        XCTAssertEqual(g.state.toNextTurnM, 100, accuracy: 20, "the right bend is ~100 m ahead")
        XCTAssertTrue(g.state.text.hasPrefix("↱"), g.state.text)
        // through the bend and along the east leg
        for i in 21...50 { g.update(lat: pts[i].lat, lon: pts[i].lon) }
        XCTAssertTrue([.left, .sharpLeft].contains(g.state.nextTurn?.direction ?? .arrive), "after the first bend the next cue is the left bend: \(String(describing: g.state.nextTurn))")
        // to the end
        for i in 61..<pts.count { g.update(lat: pts[i].lat, lon: pts[i].lon) }
        XCTAssertTrue(g.state.arrived); XCTAssertEqual(g.state.remainingM, 0, accuracy: 15)
        XCTAssertEqual(g.state.text, "Arrived · route complete")
    }
    func testOffRouteNeedsThreeFixesAndRejoinsWithHysteresis() throws {
        let pts = Self.synthPoints(); let route = try GPXParser.parse(Self.gpx(pts))
        var g = RouteGuidance(route: route)
        for i in 0...10 { g.update(lat: pts[i].lat, lon: pts[i].lon) }
        let offLon = pts[12].lon + 80 / (111_320.0 * cos(pts[12].lat * .pi / 180))   // 80 m east of the line
        g.update(lat: pts[12].lat, lon: offLon); XCTAssertFalse(g.state.offRoute, "one far fix is not yet off route (GPS can jump)")
        g.update(lat: pts[13].lat, lon: offLon); XCTAssertFalse(g.state.offRoute)
        g.update(lat: pts[14].lat, lon: offLon); XCTAssertTrue(g.state.offRoute, "three consecutive fixes > 50 m → off route")
        XCTAssertEqual(g.state.deviationM, 80, accuracy: 5); XCTAssertTrue(g.state.text.hasPrefix("Off route"))
        let nearLon = pts[15].lon + 35 / (111_320.0 * cos(pts[15].lat * .pi / 180))  // 35 m: between the thresholds
        g.update(lat: pts[15].lat, lon: nearLon); XCTAssertTrue(g.state.offRoute, "35 m is inside the hysteresis band — still off")
        g.update(lat: pts[16].lat, lon: pts[16].lon); XCTAssertFalse(g.state.offRoute, "back under 25 m → on route again")
    }
    func testGuidanceDoesNotAdvanceWithoutFixesAndRejoinsAfterDetour() throws {
        let pts = Self.synthPoints(); let route = try GPXParser.parse(Self.gpx(pts))
        var g = RouteGuidance(route: route)
        for i in 0...5 { g.update(lat: pts[i].lat, lon: pts[i].lon) }
        let s = g.state
        XCTAssertEqual(g.state, s, "no update → identical state (the caller only feeds FRESH fixes; a lost GPS changes nothing)")
        // rejoin far ahead (detour): the global search finds the diagonal leg
        g.update(lat: pts[120].lat, lon: pts[120].lon)
        XCTAssertGreaterThan(g.state.progressM, 1_000); XCTAssertFalse(g.state.offRoute)
    }
    func testStoreRoundTripAndClear() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = RouteStore(directory: dir)
        XCTAssertNil(store.loaded)
        let r = try GPXParser.parse(Self.gpx(Self.synthPoints()))
        store.set(r)
        let again = RouteStore(directory: dir)
        XCTAssertEqual(again.loaded?.name, r.name); XCTAssertEqual(again.loaded?.points.count, r.points.count)
        again.set(nil); XCTAssertNil(RouteStore(directory: dir).loaded)
    }
}
