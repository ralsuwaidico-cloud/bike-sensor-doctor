import SwiftUI

/// What the coach panel says — a pure function of the ride state, the gated engine cue and which metrics are actually
/// live (and how trustworthy they are). Rule-based ("Coach"), no model is claimed. Never invents a value: every number
/// in the text comes from a hub reading or from the engine's cue.
struct CoachPanelModel: Equatable {
    enum Tone: Equatable { case idle, up, check, down, info }
    var headline: String
    var detail: String
    var why: String
    var tags: [String] = []
    var shape: CoachShape = .none
    var direction: Int? = nil
    var active = false
    var tone: Tone = .idle

    struct Inputs {
        var coachEnabled = true
        var recording = false          // recorder.isActive
        var paused = false
        var startHint = ""
        var cue: CoachCue = .none
        var cueActive = false
        var phase: Phase = .MAIN
        var intervals = false
        var power: Int? = nil, powerUnverified = false
        var hr: Int? = nil
        var cadence: Int? = nil
        var speedKmh: Double? = nil, speedSource: String? = nil
        var imperial = false
        var ftp = 200, ftpProvisional = false
        var targetZone = 2
        var hrBand: (Int, Int)? = nil
        var powerBand: (Int, Int?)? = nil
        var cadLo = 85, cadHi = 95
        var workoutTitle = "Free ride"
    }

    /// Perceived exertion for a target zone — the guidance when nothing measures effort.
    static func feel(_ zone: Int) -> String {
        switch zone {
        case 1: return "very easy — RPE 2/10, relaxed breathing"
        case 2: return "conversational — RPE 3–4/10, full sentences"
        case 3: return "steady — RPE 5–6/10, short sentences"
        case 4: return "hard — RPE 7–8/10, a few words at a time"
        default: return "very hard — RPE 9/10, no talking"
        }
    }

    static func make(_ i: Inputs) -> CoachPanelModel {
        let z = min(5, max(1, i.targetZone))
        if !i.coachEnabled { return CoachPanelModel(headline: "Coach off", detail: "Turn it on in Ride settings (gear icon above)", why: "") }
        if !i.recording { return CoachPanelModel(headline: "Ready", detail: i.startHint, why: sensorPlan(i, z), tone: .idle) }
        if i.paused { return CoachPanelModel(headline: "Paused", detail: "Resume to continue coaching", why: "") }

        // an engine cue (held on screen ≥ 15 s by CueGate) — "no effort signal" cues are replaced by the guidance below
        if i.cueActive, i.cue.type != .NONE, i.cue.action != .NO_SIGNAL {
            let c = i.cue
            let powerBased = c.sources.contains("power") || c.reason.hasPrefix("PW") || c.reason.hasPrefix("REL") || c.reason.hasPrefix("RECOVERY_PW")
            var tags: [String] = []
            var detail = c.why.isEmpty ? c.detail : c.why
            var why = c.detail.isEmpty ? "" : c.detail + ". "
            why += CoachWording.rule(c)
            if !c.sources.isEmpty { why += " Based on \(c.sources)" + (c.live.isEmpty ? "." : " (now \(c.live)).") }
            if powerBased, i.powerUnverified {
                tags.append(RideLabels.provisional)
                detail = "Provisional · " + detail
                why += " Power is not verified yet, so this advice is provisional."
            }
            if powerBased, i.ftpProvisional, c.reason.hasPrefix("PW") || c.reason.hasPrefix("RECOVERY_PW") {
                tags.append(RideLabels.ftpProvisional)
                why += " Power zones come from a provisional FTP of \(i.ftp) W."
            }
            let shape = Targets.coachShape(c.type)
            let tone: Tone = shape == .up ? .up : shape == .down ? .down : shape == .check ? .check : .info
            return CoachPanelModel(headline: CoachWording.instruction(c, targetZone: z), detail: detail, why: why, tags: tags, shape: shape, direction: Targets.coachDirection(c.type), active: true, tone: tone)
        }
        return guidance(i, z)
    }

    /// No current cue: say what the coach is doing with the sensors that are live, or how to ride by feel.
    private static func guidance(_ i: Inputs, _ z: Int) -> CoachPanelModel {
        var tags: [String] = []
        if i.ftpProvisional, i.power != nil { tags.append(RideLabels.ftpProvisional) }
        if i.phase == .WARMUP { return CoachPanelModel(headline: "Warm up — easy spinning", detail: "Effort coaching starts after the warm-up · Zone \(z) \(i.workoutTitle.lowercased())", why: "The first 5 minutes are a warm-up, so the coach gives no 'push' cues yet. " + sensorPlan(i, z), tags: tags, tone: .info) }
        if i.phase == .RECOVERY { return CoachPanelModel(headline: "Recover for the next interval", detail: "Easy spin until the next work block", why: "This is a recovery block of the \(i.workoutTitle) workout. " + sensorPlan(i, z), tags: tags, tone: .info) }
        if i.phase == .COOLDOWN { return CoachPanelModel(headline: "Cool down", detail: "Easy spinning to finish", why: "Cool-down: no more 'push' cues. " + sensorPlan(i, z), tags: tags, tone: .info) }

        if i.hr != nil || i.power != nil {
            var from: [String] = []
            if i.hr != nil { from.append("heart rate") }
            if i.power != nil { from.append(i.powerUnverified ? "power (provisional)" : "power") }
            if i.cadence != nil { from.append("cadence") }
            if i.power != nil, i.powerUnverified { tags.append(RideLabels.provisional) }
            return CoachPanelModel(headline: "Maintain current effort", detail: "Zone \(z) target · coaching from " + from.joined(separator: ", "), why: targetsNow(i, z) + " The coach speaks when the effort stays outside the band for several seconds.", tags: tags, tone: .check)
        }
        if let c = i.cadence {
            return CoachPanelModel(headline: "Ride by feel · keep \(i.cadLo)–\(i.cadHi) rpm", detail: "Zone \(z) is \(feel(z)) · cadence \(c) rpm",
                                   why: "No heart rate or power is live, so effort cannot be measured: the coach guides cadence (\(c) rpm now, range \(i.cadLo)–\(i.cadHi)) and perceived exertion. " + helps(i), tags: tags, tone: .info)
        }
        if let s = i.speedKmh {
            let st = String(format: i.imperial ? "%.1f mph" : "%.1f km/h", i.imperial ? s / 1.609 : s)
            return CoachPanelModel(headline: "Ride by feel · hold a steady pace", detail: "Zone \(z) is \(feel(z)) · \(st)",
                                   why: "Only speed is live (\(st) from \(i.speedSource ?? "GPS")). Wind and hills change speed, so judge effort by breathing. " + helps(i), tags: tags, tone: .info)
        }
        return CoachPanelModel(headline: "Ride by feel", detail: "Zone \(z) is \(feel(z))",
                               why: "No sensors are live: the coach uses time and perceived exertion only. " + helps(i), tags: tags, tone: .info)
    }

    private static func helps(_ i: Inputs) -> String {
        var s: [String] = []
        if i.hr == nil { s.append("a heart-rate source") }
        if i.power == nil { s.append("a power meter") }
        if i.cadence == nil { s.append("a cadence sensor") }
        if i.speedKmh == nil { s.append("location (speed)") }
        return s.isEmpty ? "" : "Would help: " + s.joined(separator: ", ") + " — add them in Connections."
    }
    private static func targetsNow(_ i: Inputs, _ z: Int) -> String {
        var parts: [String] = ["Target Zone \(z)."]
        if let b = i.hrBand {
            let now: String = i.hr.map { " (now \($0))." } ?? "."
            parts.append("Heart rate \(b.0)–\(b.1) bpm" + now)
        }
        if let b = i.powerBand, let p = i.power {
            let hi: String = b.1.map { String($0) } ?? "+"
            let flag: String = i.powerUnverified ? ", unverified" : ""
            let ftpNote: String = i.ftpProvisional ? " from a provisional FTP of \(i.ftp) W." : "."
            parts.append("Power \(b.0)–\(hi) W (now \(p)\(flag))" + ftpNote)
        }
        if let c = i.cadence { parts.append("Cadence \(i.cadLo)–\(i.cadHi) rpm (now \(c)).") }
        return parts.joined(separator: " ")
    }
    /// Before the ride: which live metrics the coach will use and what would help.
    private static func sensorPlan(_ i: Inputs, _ z: Int) -> String {
        var live: [String] = []
        if i.hr != nil { live.append("heart rate") }
        if i.power != nil { live.append(i.powerUnverified ? "power (unverified — provisional)" : "power") }
        if i.cadence != nil { live.append("cadence") }
        if i.speedKmh != nil { live.append("speed") }
        let head = "\(i.workoutTitle): Zone \(z)\(i.intervals ? " intervals" : ""). "
        let uses = live.isEmpty ? "No sensors live yet — the coach will guide by time and perceived exertion. " : "Coaching from " + live.joined(separator: ", ") + ". "
        return head + uses + helps(i)
    }
}

/// The one coaching panel every ride layout embeds: compact, prominent, with an optional "Why?".
/// Reuses CoachBadge and CoachScale (RideDashboard.swift).
struct CoachPanel: View {
    let model: CoachPanelModel
    var height: CGFloat = 100
    @State private var showWhy = false

    private var color: Color {
        switch model.tone { case .up: return D7.cyan; case .check: return D7.green; case .down: return D7.amber; case .info: return D7.violet; case .idle: return D7.faint }
    }
    var body: some View {
        let active = model.active
        let bg = active ? color : D7.panel2
        let ink = active ? D7.ink : D7.fg
        let sub = active ? D7.ink.opacity(0.82) : D7.mut
        VStack(spacing: 6) {
            HStack(alignment: .center, spacing: 8) {
                CoachBadge(shape: model.shape, badge: ink, glyph: active ? color : (model.tone == .info ? D7.violet : D7.faint))
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(RideLabels.coach).font(.system(size: 8, weight: .bold, design: .monospaced)).tracking(1.5).foregroundStyle(sub)
                        ForEach(model.tags, id: \.self) { t in DashTag(text: t, color: active ? D7.ink : D7.amber) }
                    }
                    Text(model.headline).font(.system(size: model.headline.count >= 30 ? 15 : 18, weight: .heavy, design: .rounded)).foregroundStyle(ink)
                        .lineLimit(2).minimumScaleFactor(0.6)
                    Text(showWhy ? model.why : model.detail).font(.system(size: 11)).foregroundStyle(sub).lineLimit(showWhy ? 4 : 2).minimumScaleFactor(0.6)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Button { showWhy.toggle() } label: {
                    Text(showWhy ? "Close" : "Why?").font(.system(size: 11, weight: .bold, design: .rounded)).foregroundStyle(ink)
                        .padding(.horizontal, 8).padding(.vertical, 5).overlay(Capsule().stroke(ink.opacity(0.6), lineWidth: 1))
                }
                .buttonStyle(.plain).disabled(model.why.isEmpty)
                .accessibilityIdentifier("coachWhy").accessibilityLabel(showWhy ? "Close the explanation" : "Why? Explain this advice")
            }
            if !showWhy { CoachScale(direction: model.direction, lit: active ? color : D7.faint, ink: ink, active: active) }
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .frame(maxWidth: .infinity).frame(height: height)
        .background(bg, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(active ? Color.clear : D7.line, lineWidth: 1))
        .animation(.easeInOut(duration: 0.3), value: model.headline)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("coachPanel")
    }
}
