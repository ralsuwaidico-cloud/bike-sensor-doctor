import SwiftUI

// Training Hub v1.4 — the cycling recorder screen (design sheets 05a / 05b): Focus and Map views, the sensor truths,
// Lap + Pause while riding, Lap (inactive) + Resume + Finish when paused, and the finish page.
// Shown where CyProduct.redesign is on.
//
// THE SCREEN draws a CyclingReadout and reports taps (lap, pause, resume, finish, start). It records nothing itself.
//
// WHERE THE READOUT COMES FROM
// • Cyclift Lab: `CyclingDemoRide` below — the fixed demonstration script. Every figure is SIMULATED and the screen
//   says so on a permanent strip and on its source line. No Bluetooth, no GPS, no HealthKit; finishing saves nothing.
// • Redesigned main app: `CyclingLiveV14` (CyclingLiveV14.swift) — the existing ride recorder and sensor hub.
//
// NOT BUILT: minimising a ride (sheet 05b C7–C9, blocked by the cycling safety gate). The header emblem is a mark, not
// a control. The value a minimised ride would need is published to `CyclingMinimise` (CyclingMapV14.swift).

/// What stands in place of the ride controls before a ride is being recorded (main app only).
struct CyclingStartControl {
    var message: String?
    var buttonTitle: String? = nil
    var buttonID = "cyclingStart"
    var action: () -> Void = {}
}

struct CyclingRecorderV14: View {
    let readout: CyclingReadout
    /// Shown on a permanent strip when the figures are not real.
    var simulatedNote: String? = nil
    /// What the Map view shows. The default draws nothing and says why.
    var map: CyclingMapContent = .unavailable(title: "No map", detail: "There is no route to draw: this ride has no location. Nothing is drawn in its place.")
    var start: CyclingStartControl? = nil
    /// Set when Pause, Resume and Finish cannot be done from this screen; they are then inactive and this says why.
    var lockedNote: String? = nil
    /// Leaves the screen; offered only while nothing is being recorded, or while this screen cannot control the ride
    /// (`lockedNote`) — a ride it cannot pause or finish must never trap the athlete here.
    var onClose: (() -> Void)? = nil
    var onLap: () -> Void
    var onPause: () -> Void
    var onResume: () -> Void
    var onFinish: () -> Void
    @Environment(\.cyTheme) private var theme
    @Environment(\.dynamicTypeSize) private var dts
    @State private var showMap = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let n = simulatedNote { CyclingSimulatedStrip(text: n) }
            header
            switcher
            if showMap { mapPage } else { ScrollView { focus } }
            controls
        }
        .background(theme.background.ignoresSafeArea())
        .accessibilityElement(children: .contain)       // see StrengthRecorderV14: keeps every control's own identifier
        .accessibilityIdentifier("cyclingRecorderV14")
        .onAppear { CyclingMinimise.shared.set(readout.mini) }
        .onChange(of: readout.mini) { _, m in CyclingMinimise.shared.set(m) }
    }

    // MARK: header (emblem · title · state) and the Focus / Map switch

    private var header: some View {
        ZStack {
            VStack(spacing: 1) {
                Text(readout.title).font(CyDyn.f(16, .bold)).foregroundStyle(theme.textPrimary).lineLimit(1).minimumScaleFactor(0.75)
                Text(readout.stateLine).font(CyDyn.f(12, .medium))
                    .foregroundStyle(readout.phase == .paused ? theme.warning : theme.textSecondary)
                    .accessibilityIdentifier("cyclingState")
            }
            .padding(.horizontal, 56)
            HStack {
                emblem
                Spacer()
                if let c = onClose, readout.phase == .ready || lockedNote != nil {
                    Button(action: c) {
                        Image(systemName: "xmark").font(.system(size: 15, weight: .bold)).foregroundStyle(theme.textPrimary)
                            .frame(width: 40, height: 40).background(Circle().fill(theme.surface)).contentShape(Circle())
                    }
                    .buttonStyle(.plain).accessibilityLabel("Close").accessibilityIdentifier("cyclingClose")
                }
            }
        }
        .padding(.horizontal, 20).padding(.top, CySpace.s).padding(.bottom, CySpace.s)
    }
    /// The session mark of the sheet. Not a control: minimising a ride is blocked.
    private var emblem: some View {
        Image(systemName: "bicycle").font(.system(size: 17, weight: .bold)).foregroundStyle(theme.textOnAccent)
            .frame(width: 40, height: 40).background(Circle().fill(theme.accent))
            .overlay(alignment: .topTrailing) {
                Circle().fill(readout.phase == .recording ? theme.textPrimary : theme.background).frame(width: 9, height: 9)
                    .overlay(Circle().strokeBorder(theme.textPrimary, lineWidth: 1.5)).offset(x: 2, y: -2)
            }
            .accessibilityHidden(true)
    }
    private var switcher: some View {
        HStack(spacing: 0) {
            segment("Focus", on: !showMap, id: "cyclingViewFocus") { showMap = false }
            segment("Map", on: showMap, id: "cyclingViewMap") { showMap = true }
        }
        .padding(3)
        .background(RoundedRectangle(cornerRadius: 13, style: .continuous).fill(theme.surface))
        .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).strokeBorder(theme.cardStroke, lineWidth: 1))
        .padding(.horizontal, 20)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("cyclingView")
    }
    private func segment(_ t: String, on: Bool, id: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(t).font(CyDyn.f(14, .semibold)).foregroundStyle(on ? theme.textPrimary : theme.textSecondary)
                .frame(maxWidth: .infinity, minHeight: 40)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(on ? theme.surface2 : Color.clear))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain).accessibilityAddTraits(on ? .isSelected : []).accessibilityIdentifier(id)
    }

    // MARK: Focus (sheet 05a C1, C3–C5; paused 05b C10)

    private var focus: some View {
        VStack(alignment: .leading, spacing: 0) {
            elapsedBlock.padding(.top, 18).padding(.bottom, 16)
            rule
            powerBlock.padding(.vertical, 16)
            rule
            pairBlock.padding(.vertical, 16)
            rule
            speedRow.padding(.vertical, 16)
            status
        }
        .padding(.horizontal, 20)
    }
    private var elapsedBlock: some View {
        VStack(alignment: .leading, spacing: 2) {
            overline(readout.elapsedLabel)
            Text(CyclingReadout.clock(readout.elapsedSeconds)).font(.system(size: 54, weight: .heavy, design: .rounded)).monospacedDigit()
                .foregroundStyle(readout.phase == .recording ? theme.textPrimary : theme.textSecondary).lineLimit(1).minimumScaleFactor(0.5)
                .accessibilityIdentifier("cyclingElapsed")
            Text(readout.timeLine).font(CyFont.footnote).foregroundStyle(theme.textSecondary).fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("cyclingLap")
        }
    }
    private var powerBlock: some View {
        VStack(alignment: .leading, spacing: 2) {
            overline(readout.powerLabel).accessibilityIdentifier("cyclingPowerLabel")
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(readout.power.figure).font(.system(size: 88, weight: .heavy, design: .rounded)).monospacedDigit()
                    .foregroundStyle(readout.power.dimmed ? theme.textSecondary : theme.textPrimary).minimumScaleFactor(0.5).lineLimit(1)
                    .accessibilityIdentifier("cyclingPower")
                if readout.power.figure != "—" { Text("W").font(CyFont.title).foregroundStyle(theme.textSecondary) }
            }
            powerFoot
        }
    }
    private var powerFoot: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(readout.powerLine).font(CyFont.label).foregroundStyle(readout.power.dimmed ? theme.textSecondary : theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("cyclingPowerLine")
            Spacer(minLength: 8)
            if let t = readout.targetText { Text(t).font(CyFont.footnote).foregroundStyle(theme.textSecondary).accessibilityIdentifier("cyclingTarget") }
        }
    }
    private var pairBlock: some View {
        let pair = dts.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: CySpace.m)) : AnyLayout(HStackLayout(alignment: .top, spacing: CySpace.xl))
        return pair {
            small(readout.heartRateLabel, readout.heartRate, "bpm", id: "cyclingHR")
            small(readout.cadenceLabel, readout.cadence, "rpm", id: "cyclingCadence")
        }
    }
    private func small(_ title: String, _ v: SensorTruth, _ unit: String, id: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            overline(title)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(v.figure).font(.system(size: 42, weight: .heavy, design: .rounded)).monospacedDigit()
                    .foregroundStyle(v.dimmed ? theme.textSecondary : theme.textPrimary).lineLimit(1).minimumScaleFactor(0.5)
                if v.figure != "—" { Text(unit).font(CyFont.footnote).foregroundStyle(theme.textSecondary) }
            }
            if let r = v.reason { Text(r).font(CyFont.footnote).foregroundStyle(theme.textSecondary) }
        }
        .frame(minWidth: 120, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(id)
    }
    private var speedRow: some View {
        HStack(alignment: .firstTextBaseline) {
            speedText.accessibilityIdentifier("cyclingSpeed")
            Spacer(minLength: 8)
            (Text("Distance ").foregroundColor(theme.textSecondary) + Text(readout.distanceText).bold().foregroundColor(theme.textPrimary))
                .accessibilityIdentifier("cyclingDistance")
        }
        .font(CyFont.callout).monospacedDigit()
    }
    private var speedText: Text {
        let base = Text("Speed ").foregroundColor(theme.textSecondary) + Text(readout.speedText).bold().foregroundColor(theme.textPrimary)
        if let n = readout.speedNote { return base + Text(" · \(n)").foregroundColor(theme.textSecondary) }
        return base
    }

    // MARK: notices and the source line (shared by Focus and Map)

    private var status: some View {
        VStack(alignment: .leading, spacing: CySpace.s) {
            ForEach(Array(readout.notices.enumerated()), id: \.offset) { pair in notice(pair.element) }
            sourceLine
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, CySpace.m)
    }
    private func notice(_ n: CyclingNotice) -> some View {
        let icon = n.kind == .paused ? "pause.circle" : n.kind == .warning ? "exclamationmark.circle" : "info.circle"
        let id = n.kind == .paused ? "cyclingPausedNotice" : n.kind == .warning ? "cyclingWarning" : "cyclingNotice"
        return HStack(alignment: .top, spacing: CySpace.s) {
            Image(systemName: icon).font(.system(size: 17, weight: .semibold)).foregroundStyle(theme.textPrimary).accessibilityHidden(true)
            Text(n.text).font(CyFont.label).foregroundStyle(theme.textPrimary).fixedSize(horizontal: false, vertical: true)
        }
        .padding(CySpace.m).frame(maxWidth: .infinity, alignment: .leading)
        .overlay(RoundedRectangle(cornerRadius: CyRadius.s, style: .continuous).strokeBorder(theme.textPrimary, lineWidth: 1.2))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(id)
    }
    private var sourceLine: some View {
        let s = readout.sourceLine
        let dot: Color = s.state == .live ? theme.success : s.state == .simulated ? theme.warning : theme.textTertiary
        return HStack(alignment: .firstTextBaseline, spacing: CySpace.s) {
            Circle().fill(dot).frame(width: 7, height: 7).accessibilityHidden(true)
            Text(s.text).font(CyFont.footnote).foregroundStyle(theme.textSecondary).fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("cyclingSource")
    }

    // MARK: Map (sheet 05a C2)

    private var mapPage: some View {
        VStack(alignment: .leading, spacing: CySpace.m) {
            CyclingMapV14(content: map, tiles: readout.mapTiles)
            status
        }
        .padding(.horizontal, 20).padding(.top, CySpace.m)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: controls — three fixed places: Lap · Pause/Resume · Finish. Riding: Lap + Pause. Paused: Resume + Finish.

    private var controls: some View {
        VStack(alignment: .leading, spacing: CySpace.s) {
            if let n = lockedNote, readout.phase != .ready {
                Text(n).font(CyFont.footnote).foregroundStyle(theme.textSecondary).fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("cyclingControlsNote")
            }
            switch readout.phase {
            case .ready: startPanel
            case .recording:
                HStack(spacing: 10) {
                    control("Lap", filled: false, id: "cyclingLapButton", onLap).frame(maxWidth: 101)
                    control("Pause", filled: true, id: "cyclingPause", enabled: lockedNote == nil, onPause).frame(maxWidth: 132)
                    Color.clear.frame(maxWidth: 101, maxHeight: 1).accessibilityHidden(true)
                }
            case .paused:
                HStack(spacing: 10) {
                    control("Lap", filled: false, id: "cyclingLapButton", enabled: false, onLap).frame(maxWidth: 101)
                    control("Resume", filled: true, id: "cyclingResume", enabled: lockedNote == nil, onResume).frame(maxWidth: 132)
                    control("Finish", filled: false, id: "cyclingFinish", enabled: lockedNote == nil, onFinish).frame(maxWidth: 101)
                }
            case .ended: Color.clear.frame(height: 1).accessibilityHidden(true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20).padding(.top, CySpace.s).padding(.bottom, CySpace.m)
    }
    @ViewBuilder private var startPanel: some View {
        if let s = start {
            if let m = s.message {
                Text(m).font(CyFont.footnote).foregroundStyle(theme.textSecondary).fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("cyclingStartMessage")
            }
            if let t = s.buttonTitle { control(t, filled: true, id: s.buttonID, s.action) }
        }
    }
    private func control(_ t: String, filled: Bool, id: String, enabled: Bool = true, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(t).font(.headline).foregroundStyle(filled ? theme.background : theme.textPrimary).lineLimit(1).minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity, minHeight: 72)
                .background(RoundedRectangle(cornerRadius: CyRadius.l, style: .continuous).fill(filled ? theme.textPrimary : Color.clear))
                .overlay(RoundedRectangle(cornerRadius: CyRadius.l, style: .continuous).strokeBorder(theme.border, lineWidth: filled ? 0 : 1.2))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain).disabled(!enabled).opacity(enabled ? 1 : 0.4).accessibilityIdentifier(id)
    }

    private var rule: some View { Rectangle().fill(theme.separator).frame(height: 1).accessibilityHidden(true) }
    private func overline(_ t: String) -> some View { Text(t).font(CyFont.overline).tracking(1.2).foregroundStyle(theme.textSecondary) }
}

/// The permanent strip over anything whose figures are not real.
struct CyclingSimulatedStrip: View {
    let text: String
    @Environment(\.cyTheme) private var theme
    var body: some View {
        Text(text).font(.caption.weight(.bold)).foregroundStyle(Color.black)
            .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, CySpace.l).padding(.vertical, 6)
            .background(theme.warning)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("cyclingSimulated")
    }
}

/// The finish page (sheet 05b C11): the ride stays paused while the athlete decides. It states what was measured,
/// counts and names what is missing, and offers one way forward and the way back. It saves nothing itself.
struct CyclingFinishV14: View {
    let title: String
    /// "Cycling · paused while you decide".
    let stateLine: String
    /// The line under the title; `headlineID` lets a check find it.
    let headline: String
    var headlineID = "cyclingFinishHeadline"
    let summary: CyclingFinishSummary
    /// The last row: what happens to the ride ("Plan", "Saved").
    let outcomeLabel: String
    let outcome: String
    var simulatedNote: String? = nil
    let primaryTitle: String
    var primaryID = "cyclingFinishPrimary"
    var onPrimary: () -> Void
    var onBack: () -> Void
    @Environment(\.cyTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let n = simulatedNote { CyclingSimulatedStrip(text: n) }
            ScrollView { page }
            buttons
        }
        .background(theme.background.ignoresSafeArea())
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("cyclingFinishV14")
    }
    private var page: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: CySpace.s) {
                Rectangle().fill(theme.endurance).frame(width: 3, height: 14).accessibilityHidden(true)
                Text(stateLine).font(CyFont.footnote).foregroundStyle(theme.textSecondary)
            }
            .padding(.top, 28)
            Text(title).font(.system(.title, design: .rounded).weight(.bold)).foregroundStyle(theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true).padding(.top, 6)
            Text(headline).font(CyFont.label).foregroundStyle(theme.textPrimary).fixedSize(horizontal: false, vertical: true)
                .padding(.top, 4).padding(.bottom, CySpace.m)
                .accessibilityIdentifier(headlineID)
            row("Elapsed", summary.elapsedText, summary.movingText, id: "cyclingFinishElapsed")
            rule
            row("Distance", summary.distanceText, nil, id: "cyclingFinishDistance")
            rule
            row("Power", summary.powerText, summary.powerDetail, id: "cyclingFinishPower")
            rule
            row("Heart rate", summary.heartRateText, summary.heartRateDetail, id: "cyclingFinishHR")
            rule
            row(outcomeLabel, outcome, nil, id: "cyclingFinishOutcome")
        }
        .padding(.horizontal, 20)
    }
    private func row(_ label: String, _ value: String, _ detail: String?, id: String) -> some View {
        HStack(alignment: .top) {
            Text(label).font(CyFont.callout).foregroundStyle(theme.textSecondary)
            Spacer(minLength: CySpace.m)
            VStack(alignment: .trailing, spacing: 1) {
                Text(value).font(CyFont.callout.weight(.bold)).monospacedDigit().foregroundStyle(theme.textPrimary).multilineTextAlignment(.trailing)
                    .fixedSize(horizontal: false, vertical: true)
                if let d = detail { Text(d).font(CyFont.caption).foregroundStyle(theme.textSecondary).multilineTextAlignment(.trailing).fixedSize(horizontal: false, vertical: true) }
            }
        }
        .padding(.vertical, CySpace.m)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(id)
    }
    private var rule: some View { Rectangle().fill(theme.separator).frame(height: 1).accessibilityHidden(true) }
    private var buttons: some View {
        VStack(spacing: CySpace.s) {
            Button(action: onPrimary) {
                Text(primaryTitle).font(.headline).foregroundStyle(theme.textOnAccent).frame(maxWidth: .infinity, minHeight: 56)
                    .background(RoundedRectangle(cornerRadius: CyRadius.m, style: .continuous).fill(theme.accent))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain).accessibilityIdentifier(primaryID)
            Button(action: onBack) {
                Text("Back to ride").font(.headline).foregroundStyle(theme.textPrimary).frame(maxWidth: .infinity, minHeight: CyHit.min)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain).accessibilityIdentifier("cyclingFinishBack")
        }
        .padding(.horizontal, 20).padding(.top, CySpace.s).padding(.bottom, CySpace.m)
    }
}

/// Cyclift Lab's demonstration ride: the script on a one-second clock with the approved lifecycle. It touches no
/// sensor, no location, no HealthKit and no stored record; finishing shows what the demonstration was and saves nothing.
struct CyclingDemoRide: View {
    static let note = "SIMULATED RIDE · no sensor, no GPS · nothing is recorded or saved"
    @Environment(\.dismiss) private var dismiss
    @State private var seconds = 0
    @State private var pausedSeconds = 0
    @State private var phase: CyclingPhase = .recording
    @State private var laps = 0
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var readout: CyclingReadout {
        var r = CyclingDemoScript.readout(at: seconds, phase: phase, laps: laps)
        if phase == .paused { r.pausedSeconds = pausedSeconds }
        return r
    }

    var body: some View {
        Group {
            if phase == .ended {
                CyclingFinishV14(title: CyclingDemoScript.title, stateLine: "Cycling · simulated demonstration",
                                 headline: "Demonstration ended · \(laps) lap\(laps == 1 ? "" : "s") · nothing was recorded or saved", headlineID: "cyclingDemoEnded",
                                 summary: CyclingDemoScript.summary(seconds: seconds), outcomeLabel: "Saved",
                                 outcome: "Nothing — Cyclift Lab has no sensors, no GPS and no Apple Health",
                                 simulatedNote: Self.note, primaryTitle: "Close", primaryID: "cyclingDemoClose",
                                 onPrimary: { CyclingMinimise.shared.set(nil); dismiss() }, onBack: { phase = .paused })
            } else {
                CyclingRecorderV14(readout: readout, simulatedNote: Self.note,
                                   map: .unavailable(title: CyclingMapCopy.labTitle, detail: CyclingMapCopy.labDetail),
                                   onLap: { laps += 1 }, onPause: { pausedSeconds = 0; phase = .paused }, onResume: { phase = .recording }, onFinish: { phase = .ended })
            }
        }
        .onReceive(timer) { _ in if phase == .recording { seconds += 1 } else if phase == .paused { pausedSeconds += 1 } }
        .onChange(of: phase) { _, p in if p == .ended { CyclingMinimise.shared.set(nil) } }
        .onDisappear { CyclingMinimise.shared.set(nil) }
    }
}
