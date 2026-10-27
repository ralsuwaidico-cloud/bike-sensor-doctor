import SwiftUI

// Ride dashboard — SwiftUI port of the Nokia BikeComputer "Power Focus" design (app/.../ui/Design7.kt, Dashboard.kt,
// core/DashLayout.kt). Three circular target gauges (power large on top, cadence and heart rate tucked below), a
// coach panel with shape badge and EASE · ON TARGET · FASTER scale, a combined live graph, stats and controls — on one
// screen without scrolling. Every decision (zone, status, cue) comes from Shared/CoachCore.swift; the UI only draws.

// MARK: - Palette (identical to the Nokia mockup)
enum D7 {
    static let bg = Color(red: 0.024, green: 0.039, blue: 0.051), panel = Color(red: 0.031, green: 0.055, blue: 0.071), panel2 = Color(red: 0.039, green: 0.063, blue: 0.082)
    static let track = Color(red: 0.086, green: 0.141, blue: 0.169), line = Color(red: 0.114, green: 0.165, blue: 0.2)
    static let fg = Color(red: 0.933, green: 0.957, blue: 0.969), mut = Color(red: 0.514, green: 0.588, blue: 0.627), faint = Color(red: 0.353, green: 0.42, blue: 0.455), ink = Color(red: 0.02, green: 0.071, blue: 0.102)
    static let cyan = Color(red: 0.204, green: 0.906, blue: 0.894), green = Color(red: 0.337, green: 0.878, blue: 0.549), lime = Color(red: 0.651, green: 0.886, blue: 0.18), amber = Color(red: 1, green: 0.714, blue: 0.302)
    static let orange = Color(red: 1, green: 0.541, blue: 0.239), red = Color(red: 1, green: 0.353, blue: 0.353), violet = Color(red: 0.608, green: 0.549, blue: 1), grey = Color(red: 0.494, green: 0.549, blue: 0.576)
    static let powerZoneColors = [grey, cyan, green, lime, amber, orange, red]
    static let hrZoneColors = [faint, cyan, green, amber, red]
    static func powerZone(_ z: Int) -> Color { (1...7).contains(z) ? powerZoneColors[z - 1] : grey }
    static func hrZone(_ z: Int) -> Color { (1...5).contains(z) ? hrZoneColors[z - 1] : faint }
    static func status(_ s: TargetStatus) -> Color { switch s { case .below: return cyan; case .on: return green; case .above: return amber; case .unknown: return faint } }
    static let mono = Font.system(size: 10, weight: .regular, design: .monospaced)
}

// MARK: - Power-Focus geometry (port of DashLayout.kt, pure arithmetic in points)
struct PowerFocusGeometry: Equatable {
    var power: Double, small: Double
    var colPower: Double, colSmall: Double
    var xPower: Double, xLeft: Double, xRight: Double
    var yPower: Double, yLower: Double
    var blockHeight: Double
    var powerCenter: CGPoint, leftCenter: CGPoint, rightCenter: CGPoint
}

enum PowerFocus {
    static let gap = 6.0
    private static func distRectCircle(_ cx: Double, _ cy: Double, _ l: Double, _ t: Double, _ r: Double, _ b: Double) -> Double {
        let nx = min(max(cx, l), r), ny = min(max(cy, t), b)
        return ((cx - nx) * (cx - nx) + (cy - ny) * (cy - ny)).squareRoot()
    }
    /// Shrinks both rings together (power 0.44 → small 0.30 of the width at scale 1) until the block fits maxBlockH.
    static func compute(contentW: Double, maxBlockH: Double, labelH: Double, chipH: Double, chipW: Double, labelW: Double = 64) -> PowerFocusGeometry {
        // Build 27 hung at launch here: SwiftUI's GeometryReader reports a 0 × 0 size on its first pass (and the Ride
        // tab is laid out hidden behind Home), contentW − chip widths went negative, the square root below became NaN,
        // every comparison in the fitting loop was false and `dy += 1` never passed `dy > p` — an endless loop on the
        // main thread, killed by the iOS watchdog (black screen). Degenerate sizes now return a plain fallback at once
        // and the loops are bounded, so no size can hang the UI.
        guard contentW.isFinite, maxBlockH.isFinite, contentW >= max(2 * chipW, 160) else { return fallback(contentW: max(0, contentW.isFinite ? contentW : 0), labelH: labelH, chipH: chipH, chipW: chipW) }
        var best: PowerFocusGeometry? = nil
        var scale = 1.10
        var guardOuter = 0
        while scale >= 0.55, guardOuter < 64 {
            guardOuter += 1
            let p = (contentW * 0.44 * scale).rounded(), s = (contentW * 0.30 * scale).rounded()
            let colS = max(s, chipW), colP = max(p, chipW)
            let pcx = contentW / 2, pcy = labelH + p / 2
            let lcx = colS / 2, rcx = contentW - colS / 2
            let dx = pcx - lcx
            let need = (p + s) / 2 + gap
            var dy = dx >= need ? 0 : max(0, need * need - dx * dx).squareRoot()
            if !dy.isFinite { dy = 0 }
            var lcy = 0.0
            var guardInner = 0
            while guardInner < 4096 {
                guardInner += 1
                lcy = max(pcy + dy, labelH + s / 2)
                let labelTop = lcy - s / 2 - labelH, labelBot = lcy - s / 2
                let labelClear = distRectCircle(pcx, pcy, lcx - labelW / 2, labelTop, lcx + labelW / 2, labelBot) >= p / 2 + gap / 2
                let chipL = pcx - chipW / 2, chipR = pcx + chipW / 2, chipT = pcy + p / 2, chipB = chipT + chipH
                let chipClear = distRectCircle(lcx, lcy, chipL, chipT, chipR, chipB) >= s / 2 + gap / 2
                if labelClear && chipClear { break }
                dy += 1
                if dy > p { break }
            }
            let blockH = max(pcy + p / 2 + chipH, lcy + s / 2 + chipH)
            let g = PowerFocusGeometry(power: p, small: s, colPower: colP, colSmall: colS, xPower: (pcx - colP / 2).rounded(), xLeft: 0, xRight: (contentW - colS).rounded(),
                                       yPower: 0, yLower: (lcy - s / 2 - labelH).rounded(), blockHeight: blockH.rounded() + 1,
                                       powerCenter: CGPoint(x: pcx, y: pcy), leftCenter: CGPoint(x: lcx, y: lcy), rightCenter: CGPoint(x: rcx, y: lcy))
            if best == nil { best = g }
            if blockH <= maxBlockH { return g }
            scale -= 0.02
        }
        return best ?? fallback(contentW: contentW, labelH: labelH, chipH: chipH, chipW: chipW)
    }
    /// A safe layout for sizes the fitting loop must not run on (first layout pass, tiny or non-finite widths):
    /// three stacked columns that cannot overlap. Replaced by the computed geometry as soon as a real size arrives.
    static func fallback(contentW: Double, labelH: Double, chipH: Double, chipW: Double) -> PowerFocusGeometry {
        let w = max(contentW, 3 * chipW + 2 * gap)
        let p = (w * 0.44).rounded(), s = (w * 0.30).rounded()
        let colS = max(s, chipW), colP = max(p, chipW)
        let pcy = labelH + p / 2
        let lcy = pcy + p / 2 + chipH + gap + labelH + s / 2
        return PowerFocusGeometry(power: p, small: s, colPower: colP, colSmall: colS, xPower: ((w - colP) / 2).rounded(), xLeft: 0, xRight: (w - colS).rounded(),
                                  yPower: 0, yLower: (lcy - s / 2 - labelH).rounded(), blockHeight: (lcy + s / 2 + chipH).rounded() + 1,
                                  powerCenter: CGPoint(x: w / 2, y: pcy), leftCenter: CGPoint(x: colS / 2, y: lcy), rightCenter: CGPoint(x: w - colS / 2, y: lcy))
    }
    static func ringsClear(_ g: PowerFocusGeometry) -> Bool {
        func d(_ a: CGPoint, _ b: CGPoint) -> Double { ((a.x - b.x) * (a.x - b.x) + (a.y - b.y) * (a.y - b.y)).squareRoot() }
        let rp = g.power / 2, rs = g.small / 2
        return d(g.powerCenter, g.leftCenter) >= rp + rs + gap - 0.5 && d(g.powerCenter, g.rightCenter) >= rp + rs + gap - 0.5 && d(g.leftCenter, g.rightCenter) >= 2 * rs + gap
    }
}

/// Text under each gauge (statusText in Dashboard.kt): a valid zero is named as such, missing data is never a value.
enum GaugeText {
    enum SignalState { case fresh, stale, none }
    static func status(_ s: TargetStatus, kind: String, signal: SignalState = .fresh) -> String {
        switch s {
        case .below: return kind == "cad" ? "BELOW RANGE" : "BELOW TGT"
        case .above: return kind == "cad" ? "ABOVE RANGE" : "ABOVE TGT"
        case .on: return "ON TARGET"
        case .unknown:
            if kind == "hr" { return "NO HR SOURCE" }
            switch signal { case .stale: return "NO SIGNAL"; case .none: return "NO SENSOR"; case .fresh: return kind == "cad" ? "NOT TURNING" : "COASTING" }
        }
    }
}

// MARK: - Live coach model (1 Hz, fed by the Ride screen)
struct LiveSamplePoint: Equatable { var sec: Int; var powerW: Int?; var hr: Int?; var cadRpm: Int?; var bands: GraphBands }

final class RideCoach: ObservableObject {
    /// The cue on screen: the engine's latest decision after the display gate (held ≥ 15 s unless clearly necessary).
    @Published private(set) var cue: CoachCue = .none
    @Published private(set) var cueAt: Date? = nil
    @Published private(set) var phase: Phase = .WARMUP
    @Published private(set) var samples: [LiveSamplePoint] = []
    @Published private(set) var bands: GraphBands = GraphBands(pwLo: 100, pwHi: 200, hrLo: 110, hrHi: 130, cadLo: 85, cadHi: 95, pwReference: true)
    let engine = CoachEngine()
    private(set) var gate = CueGate()
    private(set) var targetZone = 2
    private(set) var targetHrZone = 2
    /// Interval workouts (threshold, VO2) coach work / recovery blocks; nil = one steady target.
    private(set) var intervals: IntervalPlan? = nil
    private(set) var workoutTitle = "Free ride"
    private var cooldownRequestedAtMs: Int64? = nil
    private var plannedSec: Int? = nil
    private var mainStartSec: Int? = nil
    private(set) var powerTrusted = false
    static let keepSeconds = 300

    /// Interval structure of today's ride: exactly the planned one (`Workout.liveIntervalPlan`, adaptive changes to the
    /// repetitions included); nil = one steady target.
    static func intervalPlan(for ride: Workout?) -> IntervalPlan? { ride?.liveIntervalPlan }

    /// Applies the rider's profile, the app settings and today's session (a ride's zone is the target; a strength or
    /// rest day coaches a free Zone 2 ride). `powerTrusted` = the power reading is verified (hub quality .good).
    func configure(profile p: RiderProfile, settings s: AppSettings, workout: Workout?, powerTrusted: Bool) {
        var c = engine.config
        let ride = workout.flatMap { $0.kind.isRide ? $0 : nil }
        let iv = Self.intervalPlan(for: ride)
        c.mode = s.coachEnabled ? (iv != nil ? .INTERVAL : .ZONE2) : .FREE
        let z = min(5, max(1, ride?.kind.zone ?? 2))
        c.targetPowerZone = z; c.targetHrZone = z
        c.ftpW = p.ftpW; c.maxHr = p.estimatedMaxHR
        c.cadenceLow = p.cadenceLow; c.cadenceHigh = p.cadenceHigh
        // audit G-05: watts drive zone cues only when the power reading is verified (hub quality .good, which follows
        // `PowerTrust.meterVerified`). Unverified power — every meter in this build — coaches like an assumed FTP:
        // heart rate when there is a strap, otherwise "hold your own steady output" without claiming a zone.
        c.ftpAssumed = p.ftpHow == .assumed || !powerTrusted
        // audit G-21: the rider's own HR zones (LTHR method included), as fractions of the max HR the engine uses
        let maxHr = Double(max(1, p.estimatedMaxHR))
        let bounds = p.hrZones.compactMap { $0.hi }.map { Double($0) / maxHr }
        if bounds.count == 4 { c.hrZoneBounds = bounds }
        c.powerCoaching = true
        c = c.withFrequency(s.coachTalk == .quiet ? .quiet : s.coachTalk == .frequent ? .frequent : .normal)
        engine.config = c
        if let iv { engine.interval = iv }
        intervals = iv
        targetZone = z; targetHrZone = z
        workoutTitle = ride?.kind.title ?? "Free ride"
        plannedSec = ride.map { $0.minutes * 60 }
        self.powerTrusted = powerTrusted
        bands = GraphBands.resolve(targets: nil, ftpW: p.ftpW, powerTrusted: powerTrusted, maxHr: p.estimatedMaxHR, targetZone: z, cadLo: p.cadenceLow, cadHi: p.cadenceHigh)
    }
    func reset() { engine.reset(); gate.reset(); cue = .none; cueAt = nil; samples = []; cooldownRequestedAtMs = nil; mainStartSec = nil; phase = .WARMUP }
    func requestCooldown(elapsedS: Int) { cooldownRequestedAtMs = Int64(elapsedS) * 1000 }

    /// One second of ride time. nil = no reading this second (never invented).
    func tick(elapsedS: Int, cadence: Int?, hr: Int?, power: Int?, speedKmh: Double?) {
        let ms = Int64(elapsedS) * 1000
        let plan = SessionPlan(warmupSec: 300, cooldownSec: 300, plannedSec: plannedSec)
        var ph = Session.phaseAt(plan, elapsedMs: ms, cooldownRequestedAtMs: cooldownRequestedAtMs)
        let input = CoachInput(nowMs: ms, phase: ph, cadence: cadence.map { Signal(value: $0) } ?? .none, hr: hr.map { Signal(value: $0) } ?? .none, power: power.map { Signal(value: $0) } ?? .none, targets: nil, speedKmh: speedKmh)
        // the label follows the engine's own interval clock (work → recovery → … → cool-down)
        if ph == .MAIN, let iv = intervals {
            if mainStartSec == nil { mainStartSec = elapsedS }
            let t = elapsedS - (mainStartSec ?? elapsedS), cycle = iv.workSec + iv.restSec
            if cycle > 0, iv.repeats > 0 { ph = t >= cycle * iv.repeats ? .COOLDOWN : (t % cycle) >= iv.workSec ? .RECOVERY : .MAIN }
        }
        phase = ph
        let c = engine.update(input)
        if gate.offer(c, nowMs: ms) { cue = gate.shown; cueAt = Date() }
        samples.append(LiveSamplePoint(sec: elapsedS, powerW: power, hr: hr, cadRpm: cadence, bands: bands))
        if samples.count > Self.keepSeconds { samples.removeFirst(samples.count - Self.keepSeconds) }
    }
    var cueActive: Bool { guard let t = cueAt else { return false }; return cue.type != .NONE && Date().timeIntervalSince(t) < 45 }
    var phaseLabel: String {
        switch phase { case .WARMUP: return "WARM-UP"; case .MAIN: return intervals != nil ? "WORK" : "MAIN"; case .RECOVERY: return "RECOVERY"; case .COOLDOWN: return "COOL-DOWN" }
    }
}

// MARK: - Gauge
struct TargetGauge: View {
    var value: Int?; var maxValue: Int; var color: Color
    var targetFraction: Double?; var zoneTicks: [Double]
    var band: (Double, Double)? = nil
    var sub: String?; var unit: String; var big: Bool
    var status: TargetStatus; var statusText: String; var showTgtLabel: Bool
    /// The source line under the pill ("Apple Watch", "Power meter via BikeComputer"); nil = no line.
    var source: String? = nil
    var sourceWarning = false
    private let start = 135.0, sweep = 270.0

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                Canvas { ctx, size in
                    let sw = size.width * (big ? 0.10 : 0.105)
                    let over = sw / 2 + (showTgtLabel ? 20 : 9)
                    let r = size.width / 2 - over
                    let c = CGPoint(x: size.width / 2, y: size.height / 2)
                    func polar(_ rr: Double, _ deg: Double) -> CGPoint { let a = (deg - 90) * .pi / 180; return CGPoint(x: c.x + rr * cos(a), y: c.y + rr * sin(a)) }
                    func arc(_ from: Double, _ to: Double, _ rr: Double) -> Path { var p = Path(); p.addArc(center: c, radius: rr, startAngle: .degrees(from - 90), endAngle: .degrees(to - 90), clockwise: false); return p }
                    ctx.stroke(arc(start, start + sweep, r), with: .color(D7.track), style: StrokeStyle(lineWidth: sw))
                    let frac = Targets.gaugeFraction(value, max: maxValue)
                    if frac > 0 { ctx.stroke(arc(start, start + sweep * frac, r), with: .color(color), style: StrokeStyle(lineWidth: sw, lineCap: .round)) }
                    for zf in zoneTicks where zf > 0 && zf < 1 {
                        let a = start + sweep * zf
                        var p = Path(); p.move(to: polar(r - sw / 2, a)); p.addLine(to: polar(r + sw / 2, a))
                        ctx.stroke(p, with: .color(D7.bg), lineWidth: 2)
                    }
                    if let bd = band {
                        let lo = min(1, max(0, bd.0)), hi = min(1, max(lo, bd.1))
                        let rb = r + sw / 2 + 5
                        let bc = status == .unknown ? D7.fg.opacity(0.7) : D7.status(status)
                        ctx.stroke(arc(start + sweep * lo, start + sweep * hi, rb), with: .color(bc), style: StrokeStyle(lineWidth: 3, lineCap: .butt))
                        for f in [lo, hi] { let ang = start + sweep * f; var p = Path(); p.move(to: polar(rb - 4, ang)); p.addLine(to: polar(rb + 4, ang)); ctx.stroke(p, with: .color(bc), lineWidth: 2) }
                        if showTgtLabel { let m = polar(rb + 11, start + sweep * (lo + hi) / 2); ctx.draw(Text("TGT").font(.system(size: 9, design: .monospaced)).foregroundColor(D7.mut), at: m) }
                    }
                    if value != nil, frac > 0 {
                        let p = polar(r, start + sweep * frac)
                        ctx.fill(Path(ellipseIn: CGRect(x: p.x - sw * 0.42, y: p.y - sw * 0.42, width: sw * 0.84, height: sw * 0.84)), with: .color(D7.fg))
                        ctx.fill(Path(ellipseIn: CGRect(x: p.x - sw * 0.28, y: p.y - sw * 0.28, width: sw * 0.56, height: sw * 0.56)), with: .color(color))
                    }
                    if band == nil, let tf = targetFraction {
                        let a = start + sweep * tf
                        var p = Path(); p.move(to: polar(r - sw / 2 - 4, a)); p.addLine(to: polar(r + sw / 2 + 4, a))
                        ctx.stroke(p, with: .color(D7.fg), lineWidth: 2.5)
                        if showTgtLabel { ctx.draw(Text("TGT").font(.system(size: 9, design: .monospaced)).foregroundColor(D7.mut), at: polar(r + sw / 2 + 13, a)) }
                    }
                }
                VStack(spacing: 0) {
                    Text((sub ?? " ").count > 8 && !big ? " " : (sub ?? " ")).font(.system(size: big ? 12 : 9, design: .monospaced)).foregroundStyle(color).lineLimit(1)
                    Text(value.map(String.init) ?? "—").font(.system(size: big ? 58 : 26, weight: .medium, design: .rounded)).monospacedDigit().foregroundStyle(value == nil ? D7.faint : D7.fg).lineLimit(1).minimumScaleFactor(0.5)
                    Text(unit).font(.system(size: big ? 12 : 9, design: .monospaced)).tracking(1).foregroundStyle(D7.mut).lineLimit(1).minimumScaleFactor(0.6)
                }.padding(.horizontal, big ? 30 : 22)
            }
            .aspectRatio(1, contentMode: .fit)
            StatusPill(status: status, text: statusText, big: big)
            if let source { Text(source).font(.system(size: 8.5, design: .monospaced)).foregroundStyle(sourceWarning ? D7.amber : D7.mut).lineLimit(1).minimumScaleFactor(0.6).frame(height: 11) }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(unit) \(value.map(String.init) ?? "no data"), \(statusText.lowercased())\(source.map { ", \($0)" } ?? "")")
    }
}

struct StatusPill: View {
    let status: TargetStatus; let text: String; let big: Bool
    var body: some View {
        let c = D7.status(status)
        let glyph = status == .below ? "▲" : status == .on ? "●" : status == .above ? "▼" : "○"
        Text("\(glyph) \(text)").font(.system(size: big ? 11 : 9, weight: .bold, design: .monospaced)).foregroundStyle(c).lineLimit(1).minimumScaleFactor(0.7)
            .padding(.horizontal, big ? 11 : 8).padding(.vertical, big ? 4 : 3)
            .background(c.opacity(0.16), in: Capsule()).overlay(Capsule().stroke(c, lineWidth: 1))
    }
}

// MARK: - Coach panel parts (CoachPanel lives in Ride/CoachPanel.swift and is embedded in every layout)
struct CoachBadge: View {
    let shape: CoachShape; let badge: Color; let glyph: Color
    var body: some View {
        Canvas { ctx, size in
            let c = CGPoint(x: size.width / 2, y: size.height / 2); let r = min(size.width, size.height) / 2
            ctx.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)), with: .color(badge))
            let u = r * 0.55
            var p = Path()
            switch shape {
            case .up: p.move(to: CGPoint(x: c.x, y: c.y - u)); p.addLine(to: CGPoint(x: c.x + u, y: c.y + u * 0.7)); p.addLine(to: CGPoint(x: c.x - u, y: c.y + u * 0.7)); p.closeSubpath(); ctx.fill(p, with: .color(glyph))
            case .down: p.move(to: CGPoint(x: c.x, y: c.y + u)); p.addLine(to: CGPoint(x: c.x + u, y: c.y - u * 0.7)); p.addLine(to: CGPoint(x: c.x - u, y: c.y - u * 0.7)); p.closeSubpath(); ctx.fill(p, with: .color(glyph))
            case .check: p.move(to: CGPoint(x: c.x - u * 0.9, y: c.y + u * 0.05)); p.addLine(to: CGPoint(x: c.x - u * 0.25, y: c.y + u * 0.7)); p.addLine(to: CGPoint(x: c.x + u, y: c.y - u * 0.7)); ctx.stroke(p, with: .color(glyph), style: StrokeStyle(lineWidth: 3.5, lineCap: .round, lineJoin: .round))
            case .none: ctx.stroke(Path(ellipseIn: CGRect(x: c.x - u * 0.8, y: c.y - u * 0.8, width: u * 1.6, height: u * 1.6)), with: .color(glyph), lineWidth: 2)
            }
        }.frame(width: 36, height: 36)
    }
}

struct CoachScale: View {
    let direction: Int?; let lit: Color; let ink: Color; let active: Bool
    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3, id: \.self) { i in
                let label = ["▼ EASE", "✓ ON TARGET", "▲ FASTER"][i], d = i - 1
                let on = active && direction == d
                Text(label).font(.system(size: 8.5, weight: .bold, design: .monospaced)).foregroundStyle(on ? lit : ink.opacity(0.75)).lineLimit(1).minimumScaleFactor(0.7)
                    .frame(maxWidth: .infinity).frame(height: 18)
                    .background(on ? ink : ink.opacity(0.12), in: Capsule())
                    .overlay(Capsule().stroke(ink.opacity(on ? 1 : 0.35), lineWidth: 1))
            }
        }
    }
}

// MARK: - Live graph: power, HR and cadence each normalised against its own band (LiveGraph.kt)
struct LiveGraphView: View {
    let samples: [LiveSamplePoint]
    let seconds: Int
    var body: some View {
        ZStack {
            Canvas { ctx, size in
                let top = size.height * GraphScale.bandTop, bot = size.height * GraphScale.bandBot
                ctx.fill(Path(CGRect(x: 0, y: top, width: size.width, height: bot - top)), with: .color(D7.green.opacity(0.10)))
                for y in [top, bot] { var p = Path(); p.move(to: CGPoint(x: 0, y: y)); p.addLine(to: CGPoint(x: size.width, y: y)); ctx.stroke(p, with: .color(D7.green.opacity(0.45)), style: StrokeStyle(lineWidth: 1, dash: [4, 4])) }
                guard let last = samples.last?.sec else { return }
                let first = last - seconds
                let dx = size.width / Double(max(1, seconds))
                func draw(_ pick: (LiveSamplePoint) -> (Int?, Int?, Int?), color: Color, width: Double) {
                    var p = Path(); var pen = false
                    for s in samples where s.sec >= first {
                        let (v, lo, hi) = pick(s)
                        guard let n = GraphScale.norm(v, lo: lo, hi: hi) else { pen = false; continue }
                        let pt = CGPoint(x: Double(s.sec - first) * dx, y: size.height * GraphScale.yFrac(n))
                        if pen { p.addLine(to: pt) } else { p.move(to: pt); pen = true }
                    }
                    ctx.stroke(p, with: .color(color), style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
                }
                draw({ ($0.cadRpm, $0.bands.cadLo, $0.bands.cadHi) }, color: D7.violet.opacity(0.8), width: 1.5)
                draw({ ($0.hr, $0.bands.hrLo, $0.bands.hrHi) }, color: D7.red, width: 2)
                draw({ ($0.powerW, $0.bands.pwLo, $0.bands.pwHi) }, color: D7.cyan, width: 2)
            }
            if samples.count < 2 { Text("live graph appears once the ride starts").font(D7.mono).foregroundStyle(D7.faint) }
            VStack { HStack(spacing: 8) { legend("W", D7.cyan); legend("BPM", D7.red); legend("RPM", D7.violet); Spacer(); Text("TARGET BAND").font(.system(size: 8, design: .monospaced)).foregroundStyle(D7.green.opacity(0.7)) }.padding(6); Spacer() }
        }
        .background(D7.panel, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(D7.line, lineWidth: 1))
        .accessibilityLabel("Live graph of power, heart rate and cadence against the target band")
    }
    private func legend(_ t: String, _ c: Color) -> some View { HStack(spacing: 3) { Circle().fill(c).frame(width: 6, height: 6); Text(t).font(.system(size: 8, design: .monospaced)).foregroundStyle(D7.mut) } }
}

struct ZoneBandView: View {
    let labels: [String]; let colors: [Color]; let currentFraction: Double?; let targetFraction: Double?
    var body: some View {
        Canvas { ctx, size in
            let top = 6.0, h = size.height - 10, w = size.width, sw = w / Double(labels.count)
            for (i, lab) in labels.enumerated() {
                ctx.fill(Path(roundedRect: CGRect(x: Double(i) * sw, y: top, width: sw - 2, height: h), cornerRadius: 3), with: .color(colors[i].opacity(0.25 + 0.1 * Double(i))))
                ctx.draw(Text(lab).font(.system(size: 9, design: .monospaced)).foregroundColor(D7.fg), at: CGPoint(x: Double(i) * sw + sw / 2, y: top + h / 2))
            }
            if let t = targetFraction { ctx.fill(Path(CGRect(x: t * w - 1, y: top - 3, width: 2, height: h + 6)), with: .color(D7.cyan)) }
            if let f = currentFraction { let mx = min(1, max(0, f)) * w; var p = Path(); p.move(to: CGPoint(x: mx - 5, y: top - 6)); p.addLine(to: CGPoint(x: mx + 5, y: top - 6)); p.addLine(to: CGPoint(x: mx, y: top + 1)); p.closeSubpath(); ctx.fill(p, with: .color(D7.fg)) }
        }.frame(height: 26)
    }
}

struct DashStat: View {
    let value: String; let label: String; var color: Color = D7.fg
    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value).font(.system(size: 20, weight: .semibold, design: .rounded)).monospacedDigit().foregroundStyle(color).lineLimit(1).minimumScaleFactor(0.6)
            Text(label).font(.system(size: 8, design: .monospaced)).tracking(1).foregroundStyle(D7.mut).lineLimit(1)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct DashTag: View {
    let text: String; let color: Color
    var body: some View { Text(text).font(.system(size: 8, weight: .bold, design: .monospaced)).foregroundStyle(color).padding(.horizontal, 5).padding(.vertical, 2).overlay(RoundedRectangle(cornerRadius: 4).stroke(color, lineWidth: 1)).lineLimit(1) }
}

struct BigButton: View {
    let text: String; let color: Color; var size: CGFloat = 17; let action: () -> Void
    var body: some View {
        Button(action: action) { Text(text).font(.system(size: size, weight: .heavy, design: .rounded)).foregroundStyle(D7.ink).frame(maxWidth: .infinity).frame(height: 52).lineLimit(1).minimumScaleFactor(0.7) }
            .background(color, in: RoundedRectangle(cornerRadius: 14)).buttonStyle(.plain)
    }
}
