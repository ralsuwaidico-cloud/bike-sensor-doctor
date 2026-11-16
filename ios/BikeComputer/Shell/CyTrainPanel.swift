import SwiftUI

// Training Hub v1.4 — the compact Train panel (design sheets 06b / 06c): the Train ball first opens a small panel above
// the dock that answers "what am I doing now, what is next, how do I start or resume, what else can I choose".
// "All training" expands it into the full Hub. Shown where CyProduct.redesign is on.
//
// Everything here is the app's existing state and routing: the session comes from the same HomeToday the Hub and Home
// use, and every button performs an existing HomeAction. The panel starts nothing by itself.
//
// NOT IN THIS STEP (and not pretended): the redesigned strength recorder and cycling screens; the Mobility, Stretch,
// Breathing and sauna shortcuts (the app has no such sessions to open); the "sensor unavailable" row beyond the line
// the Hub already shows; minimising a ride (blocked by the cycling safety gate).

struct CyTrainPanel: View {
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var recorder: RideRecorder
    var perform: (HomeAction) -> Void
    var freeRide: () -> Void
    var otherSession: () -> Void
    var expand: () -> Void
    var close: () -> Void
    @Environment(\.cyTheme) private var theme
    @Environment(\.dynamicTypeSize) private var dts

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
            if s.status == .inProgress { quiet("One session at a time") } else { shortcuts }
        case .multi(let rows):
            let main = rows.first { $0.status == .inProgress } ?? rows.first { $0.status == .planned } ?? rows[0]
            session(main)
            ForEach(rows.filter { $0.id != main.id }) { other(_: $0) }
            if main.status == .inProgress { quiet("One session at a time") } else { shortcuts }
        case .rest:
            heading(left: "Today", right: "Rest day", title: "Rest is the plan", line: "Nothing to do. Optional, if you want to:")
            shortcuts
        case .freeSession:
            running(title: "Strength session", tag: "Strength · recording", action: .resumeStrength(nil))
            quiet("One session at a time")
        case .hold(let hold):
            heading(left: "Today", right: "Paused", title: "Training is paused", line: hold.title)
            primary(.holdInfo, isRide: false)
        case .first:
            heading(left: "Today", right: "Nothing planned", title: "Choose an activity", line: "There is no plan yet.")
            primary(.createPlan, isRide: false)
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

    /// A session in progress: its clock from the session's own start time, and Resume. Nothing else can be started.
    private func running(title: String, tag: String, action: HomeAction, isRide: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            tagLine(tag, ride: isRide)
            Text(title).font(CyFont.display).foregroundStyle(theme.textPrimary).fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader).accessibilityIdentifier("trainPanelTitle")
            if isRide {
                Text(clock(recorder.elapsedS)).font(.system(.largeTitle, design: .rounded).weight(.heavy)).monospacedDigit().foregroundStyle(theme.textPrimary)
            } else if let start = store.activeSession?.startedAt {
                TimelineView(.periodic(from: .now, by: 1)) { c in
                    Text(clock(max(0, Int(c.date.timeIntervalSince(start))))).font(.system(.largeTitle, design: .rounded).weight(.heavy)).monospacedDigit().foregroundStyle(theme.textPrimary)
                        .accessibilityLabel("Session time \(clock(max(0, Int(c.date.timeIntervalSince(start)))))")
                }
                .accessibilityIdentifier("trainPanelClock")
            }
            primary(action, isRide: isRide, title: "Resume").padding(.top, 4)
        }
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
                shortcut("Free ride", "bicycle", id: "trainPanelRide", action: freeRide)
            }
            shortcut("Other session", "plus", id: "trainPanelOtherSession", action: otherSession)
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
