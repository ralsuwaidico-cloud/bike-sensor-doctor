import SwiftUI

// Training Hub v1.4 — what the compact panel's "Strength" shortcut opens (sheet 06b: "an activity opens in its own
// mode"). PROVISIONAL LAYOUT: the sheets draw the shortcut, not this chooser.
//
// Everything listed is something the app can already do, through the existing store and screens:
// • today's planned strength sessions that are still open → the v1.4 preparation screen;
// • the athlete's own routines → an extra session for today from that routine (the same steps as the existing
//   "Train now" sheet: one planned entry is added, then its preparation screen opens);
// • "Log a strength session" → the existing quick log (entered afterwards, stored as entered).
// Nothing starts recording here: recording starts with Start on the preparation screen.

struct CyStrengthPicker: View {
    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.cyTheme) private var theme
    /// Opens the session's page (the caller's existing route for a strength workout).
    var open: (UUID) -> Void
    @State private var quickLog = false

    private var today: [Workout] {
        store.plan.filter { w in
            guard w.kind == .strength, Calendar.current.isDateInToday(w.date) else { return false }
            let st = store.status(w)
            return !st.isCompleted && st != .skipped
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("Strength").font(CyFont.display).foregroundStyle(theme.textPrimary)
                    .accessibilityAddTraits(.isHeader).accessibilityIdentifier("strengthPickerTitle")
                Spacer(minLength: 8)
                Button("Close") { dismiss() }
                    .font(CyFont.label.weight(.semibold)).foregroundStyle(theme.textSecondary)
                    .frame(minWidth: CyHit.min, minHeight: CyHit.min).contentShape(Rectangle()).buttonStyle(.plain)
                    .accessibilityIdentifier("strengthPickerClose")
            }
            .padding(.horizontal, CySpace.l).padding(.top, CySpace.l)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if !today.isEmpty {
                        section("PLANNED TODAY")
                        ForEach(today) { w in
                            line(w.displayTitle(routine: store.routine(for: w)), "\(w.minutes) min · planned today", id: "strengthPickerToday") { dismiss(); open(w.id) }
                        }
                    }
                    if !store.templates.isEmpty {
                        section("YOUR ROUTINES · AN EXTRA SESSION TODAY")
                        ForEach(store.templates.prefix(6)) { t in
                            line(t.name, "About \(t.estimatedMinutes) min · added to today", id: "strengthPickerRoutine") { startUnplanned(t) }
                        }
                    }
                    section("AFTERWARDS")
                    line("Log a strength session", "Done elsewhere · stored as entered by you", id: "strengthPickerLog") { quickLog = true }
                }
                .padding(.horizontal, CySpace.l).padding(.bottom, CySpace.xl)
            }
        }
        .background(theme.background.ignoresSafeArea())
        .sheet(isPresented: $quickLog) { QuickStrengthLogSheet() }
        .presentationDetents([.medium, .large])
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("strengthPicker")
    }

    private func section(_ t: String) -> some View {
        Text(t).font(CyFont.overline).tracking(1.2).foregroundStyle(theme.textSecondary).padding(.top, CySpace.l).padding(.bottom, CySpace.xs)
    }
    private func line(_ title: String, _ detail: String, id: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(CyFont.headline).foregroundStyle(theme.textPrimary).fixedSize(horizontal: false, vertical: true)
                    Text(detail).font(CyFont.footnote).foregroundStyle(theme.textSecondary).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(theme.textTertiary).accessibilityHidden(true)
            }
            .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottom) { Rectangle().fill(theme.separator).frame(height: 1).accessibilityHidden(true) }
        .accessibilityIdentifier(id)
    }
    /// The existing "Train now" steps for a routine (TrainNowSheet.startUnplanned): one entry for today, then its page.
    private func startUnplanned(_ t: WorkoutTemplate) {
        var w = Workout(date: Date(), kind: .strength, minutes: t.estimatedMinutes, strengthFocus: t.focus == .custom ? nil : t.focus)
        w.templateId = t.id; w.routineManual = true
        store.add(w)
        dismiss(); open(w.id)
    }
}
