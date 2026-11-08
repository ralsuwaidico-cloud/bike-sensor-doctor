import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif

// Checkpoint F2 (owner master order 8 Nov §2.2): GPX import, loaded-route guidance and off-route detection.
// Pure Foundation — unit-tested without MapKit or CoreLocation. The map only DRAWS what this file computes; nothing here
// ever adds or moves a recorded GPS point (recording stays independent of any loaded route, map tiles or network).

/// One point of a loaded route (degrees; elevation metres when the file had it).
struct RoutePoint: Codable, Equatable { var lat: Double; var lon: Double; var ele: Double? = nil }

/// A turn cue on the route: where it is (point index), which way, and an optional name from the file's waypoint.
struct RouteTurn: Codable, Equatable, Identifiable {
    enum Direction: String, Codable { case left, right, sharpLeft, sharpRight, straight, arrive }
    var index: Int; var direction: Direction; var name: String? = nil; var distanceFromStartM: Double
    var id: Int { index }
    var arrow: String { switch direction { case .left, .sharpLeft: return "↰"; case .right, .sharpRight: return "↱"; case .straight: return "↑"; case .arrive: return "⦿" } }
    var word: String { switch direction { case .left: return "Turn left"; case .right: return "Turn right"; case .sharpLeft: return "Sharp left"; case .sharpRight: return "Sharp right"; case .straight: return "Continue"; case .arrive: return "Arrive" } }
}

/// A route the rider loaded (GPX). Stored as JSON; never modified by a ride.
struct LoadedRoute: Codable, Equatable, Identifiable {
    var id = UUID()
    var name: String
    var points: [RoutePoint]
    var turns: [RouteTurn]
    var totalM: Double
    var importedAt: Date
    var sourceFile: String? = nil
    var cumulativeM: [Double] { RouteGeometry.cumulative(points) }
}

// MARK: - geometry

enum RouteGeometry {
    static let earthR = 6_371_000.0
    static func distanceM(_ a: RoutePoint, _ b: RoutePoint) -> Double { distanceM(a.lat, a.lon, b.lat, b.lon) }
    static func distanceM(_ lat1: Double, _ lon1: Double, _ lat2: Double, _ lon2: Double) -> Double {
        let p = Double.pi / 180, dlat = (lat2 - lat1) * p, dlon = (lon2 - lon1) * p
        let a = sin(dlat / 2) * sin(dlat / 2) + cos(lat1 * p) * cos(lat2 * p) * sin(dlon / 2) * sin(dlon / 2)
        return 2 * earthR * asin(min(1, sqrt(a)))
    }
    /// Initial bearing a → b in degrees 0…360.
    static func bearing(_ a: RoutePoint, _ b: RoutePoint) -> Double {
        let p = Double.pi / 180, φ1 = a.lat * p, φ2 = b.lat * p, dλ = (b.lon - a.lon) * p
        let y = sin(dλ) * cos(φ2), x = cos(φ1) * sin(φ2) - sin(φ1) * cos(φ2) * cos(dλ)
        let d = atan2(y, x) / p; return d < 0 ? d + 360 : d
    }
    static func cumulative(_ pts: [RoutePoint]) -> [Double] {
        var out: [Double] = []; out.reserveCapacity(pts.count); var acc = 0.0
        for i in pts.indices { if i > 0 { acc += distanceM(pts[i - 1], pts[i]) }; out.append(acc) }
        return out
    }
    /// Drops points closer than `minStepM` to the previous kept point (GPX recorded at 1 Hz has thousands of near-duplicates).
    static func thin(_ pts: [RoutePoint], minStepM: Double = 5) -> [RoutePoint] {
        var out: [RoutePoint] = []
        for p in pts { if let l = out.last, distanceM(l, p) < minStepM { continue }; out.append(p) }
        if let l = pts.last, let o = out.last, o != l { out.append(l) }
        return out
    }
    /// Distance from `p` to segment a–b and the fraction along it (planar approximation, fine for < 1 km legs).
    static func distanceToSegment(_ p: RoutePoint, _ a: RoutePoint, _ b: RoutePoint) -> (d: Double, t: Double) {
        let k = cos(a.lat * .pi / 180) * 111_320.0, m = 110_540.0
        let ax = 0.0, ay = 0.0, bx = (b.lon - a.lon) * k, by = (b.lat - a.lat) * m, px = (p.lon - a.lon) * k, py = (p.lat - a.lat) * m
        let len2 = bx * bx + by * by
        let t = len2 > 0 ? max(0, min(1, ((px - ax) * bx + (py - ay) * by) / len2)) : 0
        let cx = ax + t * bx, cy = ay + t * by
        return (sqrt((px - cx) * (px - cx) + (py - cy) * (py - cy)), t)
    }
    /// Turn detection: a heading change of ≥ `minAngle` between legs of ≥ `minLegM` is a turn; the last point is "arrive".
    static func detectTurns(_ pts: [RoutePoint], minAngle: Double = 35, minLegM: Double = 15, mergeWithinM: Double = 60) -> [RouteTurn] {
        guard pts.count >= 2 else { return [] }
        let cum = cumulative(pts)
        var raw: [(index: Int, angle: Double)] = []
        var lastLegStart = 0
        var i = 1
        while i < pts.count - 1 {
            var j = i + 1; while j < pts.count - 1, distanceM(pts[i], pts[j]) < minLegM { j += 1 }   // outgoing heading over ≥ minLegM
            if distanceM(pts[lastLegStart], pts[i]) >= minLegM {
                let inB = bearing(pts[lastLegStart], pts[i]), outB = bearing(pts[i], pts[j])
                var d = outB - inB; while d > 180 { d -= 360 }; while d < -180 { d += 360 }
                if abs(d) >= minAngle { raw.append((i, d)); lastLegStart = i; i = j; continue }
            }
            i += 1
        }
        // a bend drawn as several close heading changes is ONE turn: merge neighbours within mergeWithinM and sum the angle
        var merged: [(index: Int, angle: Double)] = []
        for t in raw { if let l = merged.last, cum[t.index] - cum[l.index] <= mergeWithinM { merged[merged.count - 1].angle += t.angle } else { merged.append(t) } }
        var out: [RouteTurn] = merged.map { t in
            let a = abs(t.angle); let dir: RouteTurn.Direction = a >= 120 ? (t.angle < 0 ? .sharpLeft : .sharpRight) : (t.angle < 0 ? .left : .right)
            return RouteTurn(index: t.index, direction: dir, distanceFromStartM: cum[t.index]) }
        out.append(RouteTurn(index: pts.count - 1, direction: .arrive, distanceFromStartM: cum[pts.count - 1]))
        return out
    }
}

// MARK: - GPX

/// Minimal GPX 1.0/1.1 reader: <trk>/<trkseg>/<trkpt>, <rte>/<rtept>, and <wpt> with <name> as turn cues. Anything else
/// is ignored. Throws when no usable points exist. Never invents points: what is not in the file is not in the route.
final class GPXParser: NSObject, XMLParserDelegate {
    enum Failure: Error, LocalizedError { case notGPX, noPoints, malformed(String)
        var errorDescription: String? { switch self { case .notGPX: return "This file is not a GPX route."; case .noPoints: return "The GPX file has no track or route points."; case .malformed(let m): return "The GPX file could not be read: \(m)" } } }
    private var pts: [RoutePoint] = [], wpts: [(RoutePoint, String?)] = [], rtePts: [RoutePoint] = []
    private var cur: RoutePoint? = nil, curIsWpt = false, curIsRte = false, text = "", name: String? = nil, inMetadata = false, inTrkName = false, inWptName = false, sawGPX = false, wptName: String? = nil

    static func parse(_ data: Data, fileName: String? = nil, now: Date = Date()) throws -> LoadedRoute {
        let p = GPXParser(); let x = XMLParser(data: data); x.delegate = p
        if !x.parse(), let e = x.parserError, p.pts.isEmpty && p.rtePts.isEmpty { throw Failure.malformed(e.localizedDescription) }
        guard p.sawGPX else { throw Failure.notGPX }
        var raw = p.pts.isEmpty ? p.rtePts : p.pts
        raw = RouteGeometry.thin(raw, minStepM: 5)
        guard raw.count >= 2 else { throw Failure.noPoints }
        var turns = RouteGeometry.detectTurns(raw)
        // waypoints become named cues on the nearest route point (within 40 m); unnamed ones are ignored
        let cum = RouteGeometry.cumulative(raw)
        for (wp, wn) in p.wpts {
            var best = 0; var bd = Double.greatestFiniteMagnitude
            for i in raw.indices { let d = RouteGeometry.distanceM(wp, raw[i]); if d < bd { bd = d; best = i } }
            guard bd <= 40 else { continue }
            if let k = turns.firstIndex(where: { abs($0.index - best) <= 3 }) { if turns[k].name == nil { turns[k].name = wn } }
            else { turns.append(RouteTurn(index: best, direction: .straight, name: wn, distanceFromStartM: cum[best])) }
        }
        turns.sort { $0.index < $1.index }
        let name = (p.name?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 } ?? (fileName.map { ($0 as NSString).deletingPathExtension } ?? "Imported route")
        return LoadedRoute(name: name, points: raw, turns: turns, totalM: cum.last ?? 0, importedAt: now, sourceFile: fileName)
    }

    func parser(_ parser: XMLParser, didStartElement e: String, namespaceURI: String?, qualifiedName: String?, attributes a: [String: String]) {
        text = ""
        switch e.lowercased() {
        case "gpx": sawGPX = true
        case "trkpt", "rtept", "wpt":
            guard let la = a["lat"].flatMap(Double.init), let lo = a["lon"].flatMap(Double.init), abs(la) <= 90, abs(lo) <= 180 else { return }
            cur = RoutePoint(lat: la, lon: lo); curIsWpt = e.lowercased() == "wpt"; curIsRte = e.lowercased() == "rtept"; wptName = nil
        case "metadata": inMetadata = true
        case "name": if cur != nil { inWptName = true } else { inTrkName = true }
        default: break
        }
    }
    func parser(_ parser: XMLParser, foundCharacters s: String) { text += s }
    func parser(_ parser: XMLParser, didEndElement e: String, namespaceURI: String?, qualifiedName: String?) {
        switch e.lowercased() {
        case "ele": if cur != nil, let v = Double(text.trimmingCharacters(in: .whitespacesAndNewlines)) { cur?.ele = v }
        case "name":
            if inWptName { wptName = text.trimmingCharacters(in: .whitespacesAndNewlines); inWptName = false }
            else if inTrkName { if name == nil || inMetadata { name = text.trimmingCharacters(in: .whitespacesAndNewlines) }; inTrkName = false }
        case "metadata": inMetadata = false
        case "trkpt": if let c = cur { pts.append(c) }; cur = nil
        case "rtept": if let c = cur { rtePts.append(c) }; cur = nil
        case "wpt": if let c = cur { wpts.append((c, wptName)) }; cur = nil
        default: break
        }
    }
}

// MARK: - guidance

/// Follows a loaded route from the phone's fixes. Forward-biased nearest-segment search, off-route hysteresis (> 50 m
/// for 3 consecutive fixes → off; < 25 m → back on), next turn with distance along the route. Without a fresh fix the
/// state does not advance: a lost GPS never moves the rider along the route.
struct RouteGuidance: Equatable {
    struct State: Equatable {
        var segment: Int = 0                 // index of the segment start point the rider is on
        var progressM: Double = 0            // metres along the route
        var remainingM: Double = 0
        var deviationM: Double = 0
        var offRoute: Bool = false
        var nextTurn: RouteTurn? = nil
        var toNextTurnM: Double = 0
        var arrived: Bool = false
        var fixes: Int = 0
        var text: String {                    // the one line the ride screen shows
            if arrived { return "Arrived · route complete" }
            if offRoute { return "Off route · \(Int(deviationM.rounded())) m from the line" }
            guard let t = nextTurn else { return "\(RouteGuidance.km(remainingM)) to go" }
            return "\(t.arrow) \(Int(toNextTurnM.rounded())) m · " + (t.name ?? t.word)
        }
    }
    let route: LoadedRoute
    private(set) var state = State()
    private var cum: [Double]
    private var offCount = 0
    var offThresholdM: Double = 50, onThresholdM: Double = 25, offConsecutive: Int = 3, arriveRadiusM: Double = 30

    init(route: LoadedRoute) { self.route = route; cum = route.cumulativeM; state.remainingM = route.totalM; state.nextTurn = route.turns.first; state.toNextTurnM = route.turns.first?.distanceFromStartM ?? route.totalM }

    static func km(_ m: Double) -> String { m >= 1000 ? String(format: "%.1f km", m / 1000) : "\(Int(m.rounded())) m" }

    /// Feed one FRESH fix (the caller checks the age). Returns the new state.
    @discardableResult mutating func update(lat: Double, lon: Double) -> State {
        let pts = route.points; guard pts.count >= 2 else { return state }
        let p = RoutePoint(lat: lat, lon: lon)
        // search window: a little behind, well ahead; widen to the whole route when far from the window (re-join after a detour)
        func search(_ lo: Int, _ hi: Int) -> (seg: Int, d: Double, t: Double) {
            var best = (seg: lo, d: Double.greatestFiniteMagnitude, t: 0.0)
            for i in max(0, lo)..<min(pts.count - 1, hi) { let r = RouteGeometry.distanceToSegment(p, pts[i], pts[i + 1]); if r.d < best.d { best = (i, r.d, r.t) } }
            return best
        }
        var best = search(state.segment - 3, state.segment + 80)
        if best.d > 200 { best = search(0, pts.count - 1) }
        state.segment = best.seg; state.deviationM = best.d; state.fixes += 1
        let segLen = cum[best.seg + 1] - cum[best.seg]
        state.progressM = cum[best.seg] + best.t * segLen
        state.remainingM = max(0, route.totalM - state.progressM)
        if best.d > offThresholdM { offCount += 1; if offCount >= offConsecutive { state.offRoute = true } }
        else if best.d < onThresholdM { offCount = 0; state.offRoute = false }
        // next turn = first turn whose index is past the current segment (or on it but still ahead of the rider)
        state.nextTurn = route.turns.first { t in t.index > best.seg || (t.index == best.seg + 1) }
        if let t = state.nextTurn { state.toNextTurnM = max(0, t.distanceFromStartM - state.progressM) }
        if let last = pts.last, RouteGeometry.distanceM(p, last) <= arriveRadiusM, state.progressM >= route.totalM * 0.9 { state.arrived = true }
        return state
    }
}

// MARK: - store

/// Persists the one loaded route as JSON in Application Support. Loading a route never touches rides or recordings.
final class RouteStore: ObservableObject {
    @Published private(set) var loaded: LoadedRoute?
    private let url: URL
    init(directory: URL? = nil) {
        let dir = directory ?? (FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory).appendingPathComponent("Cyclift", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        url = dir.appendingPathComponent("loaded-route.json")
        if let d = try? Data(contentsOf: url), let r = try? JSONDecoder().decode(LoadedRoute.self, from: d) { loaded = r }
    }
    func set(_ r: LoadedRoute?) {
        loaded = r
        if let r, let d = try? JSONEncoder().encode(r) { try? d.write(to: url, options: .atomic) } else { try? FileManager.default.removeItem(at: url) }
    }
    /// Import from a file URL picked by the user (security-scoped when it comes from Files).
    func importGPX(at fileURL: URL) throws -> LoadedRoute {
#if os(iOS)
        let scoped = fileURL.startAccessingSecurityScopedResource(); defer { if scoped { fileURL.stopAccessingSecurityScopedResource() } }
#endif
        let data = try Data(contentsOf: fileURL)
        let r = try GPXParser.parse(data, fileName: fileURL.lastPathComponent)
        set(r); return r
    }
}
