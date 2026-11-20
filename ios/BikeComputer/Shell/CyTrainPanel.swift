import SwiftUI

// Training Hub v1.4 — the compact Train panel (design sheets 06b / 06c): the Train ball first opens a small panel above
// the dock that answers "what am I doing now, what is next, how do I start or resume, what else can I choose".
// "All training" expands it into the full Hub. Shown where CyProduct.redesign is on.
//
// Everything here is the app's existing state and routing: the session comes from the same HomeToday the Hub and Home
// use, and every button performs an existing HomeAction. The panel starts nothing by itself.
//
// Shortcuts (06b P1–P4): the sheet draws Cycling · Strength · Mobility · Stretch (and Breathing · Log sauna on a rest
// day). Shown here: Cycling (the Ride screen; in Cyclift Lab the labelled demonstration) and Strength (today's strength
// sessions, the athlete's routines, or logging a session — Shell/CyStrengthPicker.swift).
// NOT SHOWN, AND NOT PRETENDED: Mobility, Stretch, Breathing and Log sauna — the app has no recorder or record for
// them (sheet 06d marks all recovery modes as future capabilities); the "sensor unavailable" row beyond the line the
// Hub already shows; minimising a ride (blocked by the cycling safety gate).

struct CyTrainPanel: View {
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var recorder: RideRecorder
    var perform: (HomeAction) -> Void
    var freeRide: () -> Void
    /// Opens the strength chooser (today's sessions, routines, log a session).
    var strength: () -> Void
    var expand: () -> Void
    var close: () -> Void
    @Environment(\.cyTheme) private var theme
    @Environment(\.dynamicTypeSize) private var dts
    @ObservedObject private var memory = CyRecorderMemory.shared

    var body: some View {
        let h = store.homeToday(recorderActive: recorder.isActive)
        VStack(alignment: .leading, spacing: CySpace.m) {
            Capsule().fill(theme.textTertiary.opacity(0.6)).frame(width: 36, height: 4).frame(maxWidth: .infinity)
                .accessibilityHidden(true)
            content(h)
            Button(action: expand) {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.up").font(.caption.weight(.bold))
                    Text("All training").font(CyFont.label)
                }
                .foregroundStyle(theme.textSecondary)
                .frame(maxWidth: .infinity, minHeight: CyHit.min).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens the full Training Hub")
            .accessibilityIdentifier("trainPanelAll")
        }
        .padding(.horizontal, CySpace.l).padding(.top, CySpace.s).padding(.bottom, CySpace.xs)
        .background(RoundedRectangle(cornerRadius: CyRadius.l, style: .continuous).fill(theme.surface))
        .overlay(RoundedRectangle(cornerRadius: CyRadius.l, style: .continuous).strokeBorder(theme.id == .highContrast ? theme.border : theme.border.opacity(0.5), lineWidth: theme.borderWidth))
        .padding(.horizontal, CySpace.m)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("trainPanel")
        .accessibilityAction(.escape, close)
    }

    @ViewBuilder private func content(_ h: HomeToday) -> some View {
        switch h.layout {
        case .single(let s):
            session(s)
            if s.status == .inProgress { quiet(activeNote(isRide: s.isRide)) } else { shortcuts }
        case .multi(let rows):
            let main = rows.first { $0.status == .inProgress } ?? rows.first { $0.status == .planned } ?? rows[0]
            session(main)
            ForEach(rows.filter { $0.id != main.id }) { other(_: $0) }
            if main.status == .inProgress { quiet(activeNote(isRide: main.isRide)) } else { shortcuts }
        case .rest:
            heading(left: "Today", right: "Rest day", title: "Rest is the plan", line: "Nothing to do. Optional, if you want to:")
            shortcuts
        case .freeSession:
            running(title: "Strength session", tag: "Strength · recording", action: .resumeStrength(nil))
            quiet(activeNote(isRide: false))
        case .hold(let hold):
            heading(left: "Today", right: "Paused", title: "Training is paused", line: hold.title)
            primary(.holdInfo, isRide: false)
        case .first:
            if store.profile.isProfileOnly {
                // an athlete without a training plan: say what is saved, and do not offer a cycling/strength plan set-up
                heading(left: "Today", right: "Nothing planned", title: "Choose an activity", line: "There is no plan yet. " + ProfileOnlyText.saved(store.profile))
            } else {
                heading(left: "Today", right: "Nothing planned", title: "Choose an activity", line: "There is no plan yet.")
                primary(.createPlan, isRide: false)
            }
            shortcuts
        }
    }

    // MARK: pieces

    private func heading(left: String, right: String, title: String, line: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack { Text(left); Spacer(minLength: 8); Text(right) }.font(CyFont.footnote).foregroundStyle(theme.textSecondary)
            Text(title).font(CyFont.display).foregroundStyle(theme.textPrimary).fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader).accessibilityIdentifier("trainPanelTitle")
            Text(line).font(CyFont.callout).foregroundStyle(theme.textSecondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func tagLine(_ text: String, ride: Bool) -> some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 1.5).fill(ride ? theme.endurance : theme.strength).frame(width: 3, height: 14).accessibilityHidden(true)
            Text(text).font(CyFont.footnote).foregroundStyle(theme.textSecondary)
        }
    }

    @ViewBuilder private func session(_ s: HomeSession) -> some View {
        let sport = s.isRide ? "Cycling" : (s.workout.kind == .strength ? "Strength" : s.workout.kind.title)
        if s.status == .inProgress {
            running(title: s.title, tag: "\(sport) · recording", action: s.action, isRide: s.isRide)
        } else {
            VStack(alignment: .leading, spacing: 4) {
                tagLine("\(sport) · \(s.status.chip?.lowercased() ?? "planned today")", ride: s.isRide)
                Text(s.title).font(CyFont.display).foregroundStyle(theme.textPrimary).fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader).accessibilityIdentifier("trainPanelTitle")
                Text(s.subtitle).font(CyFont.callout).foregroundStyle(theme.textSecondary).fixedSize(horizontal: false, vertical: true)
            }
            primary(s.action, isRide: s.isRide)
        }
    }

    /// Whether the session in progress is paused (06c P6), read from the session itself.
    private func isPaused(isRide: Bool) -> Bool { isRide ? recorder.state == .paused : store.activeSession?.pausedAt != nil }
    /// P5 "One session at a time" · P6 "Finish from the workout screen".
    private func activeNote(isRide: Bool) -> String { isPaused(isRide: isRide) ? "Finish from the workout screen" : "One session at a time" }

    /// A session in progress: its clock (working time, pauses excluded — the same figure the recorder shows), what is
    /// on now, and Resume. Nothing else can be started.
    private func running(title: String, tag: String, action: HomeAction, isRide: Bool = false) -> some View {
        let paused = isPaused(isRide: isRide)
        return VStack(alignment: .leading, spacing: 4) {
            tagLine(paused ? tag.replacingOccurrences(of: "recording", with: "paused") : tag, ride: isRide)
            Text(title).font(CyFont.display).foregroundStyle(theme.textPrimary).fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader).accessibilityIdentifier("trainPanelTitle")
            if isRide {
                Text(clock(recorder.elapsedS)).font(.system(.largeTitle, design: .rounded).weight(.heavy)).monospacedDigit()
                    .foregroundStyle(paused ? theme.textSecondary : theme.textPrimary)
            } else if let session = store.activeSession {
                TimelineView(.periodic(from: .now, by: 1)) { c in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(clock(session.elapsedSeconds(now: c.date))).font(.system(.largeTitle, design: .rounded).weight(.heavy)).monospacedDigit()
                            .foregroundStyle(paused ? theme.textSecondary : theme.textPrimary)
                            .accessibilityLabel("Session time \(clock(session.elapsedSeconds(now: c.date)))")
                            .accessibilityIdentifier("trainPanelClock")
                        Text(nowLine(session, now: c.date)).font(CyFont.callout).foregroundStyle(theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("trainPanelNow")
                    }
                }
            }
            primary(action, isRide: isRide, title: "Resume").padding(.top, 4)
        }
    }
    /// "Goblet squat · set 2 of 3 · rest 0:31" (P5) — or "Paused · time is not counting" (P6). Read from the session.
    private func nowLine(_ s: StrengthSession, now: Date) -> String {
        if s.pausedAt != nil { return memory.restoredSession == s.id ? "Restored after the app closed · paused" : "Paused · time is not counting" }
        let es = s.exercises ?? []
        guard let p = NextSet.pick(es) else { return "All sets logged · finish from the workout screen" }
        var line = "\(es[p.entry].name) · \(p.label == nil ? "set" : "round") \(p.set + 1) of \(es[p.entry].sets.count)"
        if let end = memory.restEndsAt {
            let left = Int(end.timeIntervalSince(now).rounded(.up))
            if left > 0 { line += " · rest " + String(format: "%d:%02d", left / 60, left % 60) }
        }
        return line
    }

    private func other(_ s: HomeSession) -> some View {
        Button { perform(s.action) } label: {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(s.title).font(CyFont.label).foregroundStyle(theme.textPrimary).fixedSize(horizontal: false, vertical: true)
                    Text("\(s.subtitle) · \(s.status.chip?.lowercased() ?? "also today")").font(CyFont.footnote).foregroundStyle(theme.textSecondary).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Text(s.action.shortLabel).font(CyFont.label.weight(.semibold)).foregroundStyle(theme.accent)
            }
            .frame(maxWidth: .infinity, minHeight: CyHit.min, alignment: .leading).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint(s.action.hint)
        .accessibilityIdentifier("trainPanelOther")
    }

    private func primary(_ a: HomeAction, isRide: Bool, title: String? = nil) -> some View {
        let label = title ?? a.label(isRide: isRide, elapsed: nil)
        return Button { perform(a) } label: {
            Text(label).font(.headline).lineLimit(2).multilineTextAlignment(.center)
                .foregroundStyle(theme.textOnAccent)
                .frame(maxWidth: .infinity, minHeight: 50)
                .background(RoundedRectangle(cornerRadius: CyRadius.s, style: .continuous).fill(theme.accent))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityHint(a.hint)
        .accessibilityIdentifier("trainPanelPrimary")
    }

    private func quiet(_ t: String) -> some View {
        Text(t).font(CyFont.footnote).foregroundStyle(theme.textSecondary).frame(maxWidth: .infinity)
    }

    /// The other things that can be started now. Only shortcuts with a real destination are shown.
    private var shortcuts: some View {
        let layout = dts.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 0)) : AnyLayout(HStackLayout(spacing: 0))
        return layout {
            if store.profile.trainingMode != .strength {
                shortcut("Cycling", "bicycle", id: "trainPanelRide", action: freeRide)
            }
            if store.profile.trainingMode != .cycling {
                shortcut("Strength", "dumbbell", id: "trainPanelStrength", action: strength)
            }
        }
    }
    private func shortcut(_ title: String, _ icon: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            let l = dts.isAccessibilitySize ? AnyLayout(HStackLayout(spacing: 10)) : AnyLayout(VStackLayout(spacing: 6))
            l {
                Image(systemName: icon).font(.body.weight(.semibold)).foregroundStyle(theme.textPrimary).accessibilityHidden(true)
                Text(title).font(CyFont.caption).foregroundStyle(theme.textSecondary)
            }
            .frame(maxWidth: .infinity, minHeight: CyHit.min, alignment: dts.isAccessibilitySize ? .leading : .center).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
    }

    private func clock(_ s: Int) -> String { s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60) : String(format: "%02d:%02d", s / 60, s % 60) }
}
