import SwiftUI

// Training Hub v1.4 — the cycling recorder screen (design sheets 05a / 05b): Focus layout, the five sensor truths,
// Lap + Pause while riding, Resume + Finish when paused. Shown where CyProduct.redesign is on.
//
// THE SCREEN draws a CyclingReadout and reports four taps (lap, pause, resume, finish). It records nothing itself.
//
// WHERE THE READOUT COMES FROM TODAY
// • Cyclift Lab: `CyclingDemoRide` below — the fixed demonstration script. Every figure is SIMULATED and the screen
//   says so on a permanent strip. No Bluetooth, no GPS, no HealthKit; finishing saves nothing and changes no record.
// • Production: nothing. This screen is not connected to the real ride recorder; the existing Ride screen stays until
//   the cycling safety gate is passed and approved.
//
// NOT BUILT: the Map view (Lab has no location, so no route exists to draw), minimising a ride (blocked by the safety
// gate), lap history.

struct CyclingRecorderV14: View {
    let readout: CyclingReadout
    /// Shown on a permanent strip when the figures are not real.
    var simulatedNote: String? = nil
    var onLap: () -> Void
    var onPause: () -> Void
    var onResume: () -> Void
    var onFinish: () -> Void
    @Environment(\.cyTheme) private var theme
    @Environment(\.dynamicTypeSize) private var dts
    @State private var view = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let n = simulatedNote {
                Text(n).font(.caption.weight(.bold)).foregroundStyle(Color.black)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, CySpace.l).padding(.vertical, 6)
                    .background(theme.warning)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("cyclingSimulated")
            }
            VStack(spacing: 2) {
                Text(readout.title).font(CyFont.headline).foregroundStyle(theme.textPrimary)
                Text(readout.phase == .paused ? "Cycling · paused — readings are live, not recorded" : "Cycling · recording")
                    .font(CyFont.caption).foregroundStyle(readout.phase == .paused ? theme.warning : theme.textSecondary)
                    .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("cyclingState")
            }
            .frame(maxWidth: .infinity).padding(.vertical, CySpace.s)
            Picker("View", selection: $view) { Text("Focus").tag(0); Text("Map").tag(1) }
                .pickerStyle(.segmented).padding(.horizontal, CySpace.l).accessibilityIdentifier("cyclingView")
            ScrollView {
                if view == 0 { focus } else { mapUnavailable }
            }
            controls
        }
        .background(theme.background.ignoresSafeArea())
        .accessibilityElement(children: .contain)       // see StrengthRecorderV14: keeps every control's own identifier
        .accessibilityIdentifier("cyclingRecorderV14")
    }

    private var focus: some View {
        VStack(alignment: .leading, spacing: CySpace.m) {
            block("ELAPSED") {
                Text(CyclingReadout.clock(readout.elapsedSeconds)).font(.system(size: 52, weight: .heavy, design: .rounded)).monospacedDigit()
                    .foregroundStyle(readout.phase == .paused ? theme.textSecondary : theme.textPrimary).accessibilityIdentifier("cyclingElapsed")
                Text("Moving \(CyclingReadout.clock(readout.movingSeconds)) · lap \(readout.laps + 1)").font(CyFont.footnote).foregroundStyle(theme.textSecondary)
                    .accessibilityIdentifier("cyclingLap")
            }
            rule
            block(readout.powerLabel) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(readout.power.figure).font(.system(size: 76, weight: .heavy, design: .rounded)).monospacedDigit()
                        .foregroundStyle(readout.power.dimmed ? theme.textSecondary : theme.textPrimary).minimumScaleFactor(0.5).lineLimit(1)
                        .accessibilityIdentifier("cyclingPower")
                    if readout.power.figure != "—" { Text("W").font(CyFont.title).foregroundStyle(theme.textSecondary) }
                }
                HStack(alignment: .firstTextBaseline) {
                    Text(readout.powerLine).font(CyFont.label).foregroundStyle(theme.textPrimary).accessibilityIdentifier("cyclingPowerLine")
                    Spacer(minLength: 8)
                    if let lo = readout.targetLow, let hi = readout.targetHigh { Text("Target \(lo)–\(hi) W").font(CyFont.footnote).foregroundStyle(theme.textSecondary) }
                }
            }
            rule
            let pair = dts.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: CySpace.m)) : AnyLayout(HStackLayout(alignment: .top, spacing: CySpace.xl))
            pair {
                small("HEART RATE", readout.heartRate, "bpm", id: "cyclingHR")
                small("CADENCE", readout.cadence, "rpm", id: "cyclingCadence")
            }
            rule
            HStack {
                Text("Speed ").foregroundColor(theme.textSecondary) + Text(readout.speedKmh.map { String(format: "%.1f km/h", $0) } ?? "—").bold().foregroundColor(theme.textPrimary)
                Spacer(minLength: 8)
                Text("Distance ").foregroundColor(theme.textSecondary) + Text(String(format: "%.1f km", readout.distanceKm)).bold().foregroundColor(theme.textPrimary)
            }
            .font(CyFont.callout).monospacedDigit()
            if let w = readout.warning {
                Label(w, systemImage: "exclamationmark.circle").font(CyFont.label).foregroundStyle(theme.textPrimary)
                    .padding(CySpace.m).frame(maxWidth: .infinity, alignment: .leading)
                    .overlay(RoundedRectangle(cornerRadius: CyRadius.s, style: .continuous).strokeBorder(theme.textPrimary, lineWidth: 1.2))
                    .accessibilityIdentifier("cyclingWarning")
            }
        }
        .padding(.horizontal, CySpace.l).padding(.top, CySpace.m)
    }
    private var rule: some View { Rectangle().fill(theme.separator).frame(height: 1).accessibilityHidden(true) }
    private func block<V: View>(_ title: String, @ViewBuilder _ content: () -> V) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(CyFont.overline).tracking(1.2).foregroundStyle(theme.textSecondary)
            content()
        }
    }
    private func small(_ title: String, _ v: SensorTruth, _ unit: String, id: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(CyFont.overline).tracking(1.2).foregroundStyle(theme.textSecondary)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(v.figure).font(.system(size: 34, weight: .heavy, design: .rounded)).monospacedDigit().foregroundStyle(v.dimmed ? theme.textSecondary : theme.textPrimary)
                    .accessibilityIdentifier(id)
                if v.figure != "—" { Text(unit).font(CyFont.footnote).foregroundStyle(theme.textSecondary) }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var mapUnavailable: some View {
        VStack(alignment: .leading, spacing: CySpace.s) {
            Text("No map").font(CyFont.title).foregroundStyle(theme.textPrimary)
            Text("There is no route to draw: this ride has no location. Nothing is drawn in its place.")
                .font(CyFont.callout).foregroundStyle(theme.textSecondary).fixedSize(horizontal: false, vertical: true)
        }
        .padding(CySpace.l).frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("cyclingMapUnavailable")
    }

    /// Fixed positions. Riding: Lap + Pause only. Paused: Resume + Finish.
    private var controls: some View {
        HStack(spacing: CySpace.m) {
            if readout.phase == .recording {
                control("Lap", filled: false, id: "cyclingLapButton", onLap).frame(width: 96)
                control("Pause", filled: true, id: "cyclingPause", onPause)
            } else {
                control("Finish", filled: false, id: "cyclingFinish", onFinish).frame(width: 96)
                control("Resume", filled: true, id: "cyclingResume", onResume)
            }
        }
        .padding(.horizontal, CySpace.l).padding(.vertical, CySpace.m)
    }
    private func control(_ t: String, filled: Bool, id: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(t).font(.headline).foregroundStyle(filled ? theme.background : theme.textPrimary)
                .frame(maxWidth: .infinity, minHeight: 60)
                .background(RoundedRectangle(cornerRadius: CyRadius.m, style: .continuous).fill(filled ? theme.textPrimary : Color.clear))
                .overlay(RoundedRectangle(cornerRadius: CyRadius.m, style: .continuous).strokeBorder(theme.border, lineWidth: filled ? 0 : 1.2))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain).accessibilityIdentifier(id)
    }
}

/// Cyclift Lab's demonstration ride: the script on a one-second clock with the approved lifecycle. It touches no
/// sensor, no location, no HealthKit and no stored record; finishing shows what the demonstration was and saves nothing.
struct CyclingDemoRide: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.cyTheme) private var theme
    @State private var seconds = 0
    @State private var phase: CyclingPhase = .recording
    @State private var laps = 0
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        Group {
            if phase == .ended {
                VStack(alignment: .leading, spacing: CySpace.l) {
                    Spacer()
                    Text("Demonstration ended").font(.system(.largeTitle, design: .rounded).weight(.bold)).foregroundStyle(theme.textPrimary)
                        .accessibilityIdentifier("cyclingDemoEnded")
                    Text("Nothing was recorded or saved. Cyclift Lab has no sensors, no GPS and no Apple Health, so this ride existed only on this screen: \(CyclingReadout.clock(seconds)) of simulated riding, \(laps) lap\(laps == 1 ? "" : "s").")
                        .font(CyFont.callout).foregroundStyle(theme.textSecondary).fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    Button { dismiss() } label: {
                        Text("Close").font(.headline).foregroundStyle(theme.textOnAccent).frame(maxWidth: .infinity, minHeight: 56)
                            .background(RoundedRectangle(cornerRadius: CyRadius.m, style: .continuous).fill(theme.accent))
                    }
                    .buttonStyle(.plain).accessibilityIdentifier("cyclingDemoClose")
                }
                .padding(CySpace.l)
                .background(theme.background.ignoresSafeArea())
            } else {
                CyclingRecorderV14(readout: CyclingDemoScript.readout(at: seconds, phase: phase, laps: laps),
                                   simulatedNote: "SIMULATED RIDE · no sensor, no GPS · nothing is recorded or saved",
                                   onLap: { laps += 1 }, onPause: { phase = .paused }, onResume: { phase = .recording }, onFinish: { phase = .ended })
            }
        }
        .onReceive(timer) { _ in if phase == .recording { seconds += 1 } }
    }
}
