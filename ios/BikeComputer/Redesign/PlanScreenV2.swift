import SwiftUI

// Plan v2.0 — schedule-first Plan (Weekly Calendar and Recurring Plan), visual direction B "Athletic Dynamic".
// Specification: product/plan/PLAN_V2_SPECIFICATION.md v0.6. Brought over from the UI Lab prototype (branch
// proto/ui-lab-plan, Screens/PlanScreen.swift, 13 Nov 2026) as SHARED code for both apps, switched on by
// `CyProduct.redesign`. The screen draws plain values only: PlanV2Adapter builds them from the athlete record and the
// existing planner, and PlanV2Host opens the existing editors — there is no second planner and no sample data here.
// A request the app cannot serve yet is answered with "Not available yet" on the page.

// MARK: - Values the screen draws

/// One thing the athlete asked the Plan page to do.
struct PlanV2Request {
    let name: String
    var session: PlanSession? = nil
    var day: PlanV2Day? = nil
    /// "Mon" … "Sun" for a Recurring Plan row.
    var weekday: String? = nil
}

enum PlanDiscipline: String { case endurance, strength
    var word: String { self == .endurance ? "ride" : "strength" }
    var icon: String { self == .endurance ? "bicycle" : "dumbbell.fill" }
}

enum PlanStatus: String { case planned = "Planned", done = "Done", missed = "Missed", skipped = "Skipped" }

struct PlanSegment { let weight: Double; let level: Double }

struct PlanSession: Identifiable {
    let id: String
    let discipline: PlanDiscipline
    let title: String
    let detail: String
    let status: PlanStatus
    var link: String? = nil
    var structure: [PlanSegment] = []
    /// A structure indicator is informative only when the prescription has more than one part (intervals, a list of
    /// exercises). One steady block — an ordinary Zone 2 ride — says nothing a bar could add.
    var hasInformativeStructure: Bool { structure.count > 1 }
}

struct PlanV2Day: Identifiable {
    let id: Int                 // day of the month (unique inside the three sample weeks)
    let weekday: String         // "Thursday"
    let short: String           // "Thu"
    let month: String           // "Nov"
    var isToday: Bool = false
    var isRest: Bool = false
    var sessions: [PlanSession] = []
    /// The calendar day this row stands for (start of day).
    var date: Date = Date()
    var letter: String { String(short.prefix(1)) }
    var title: String { "\(short) \(id) \(month)" }
}

struct PlanWeek: Identifiable {
    let id: Int                 // -1 previous, 0 current, 1 next
    let title: String
    let days: [PlanV2Day]
}

struct PlanRecurringRow: Identifiable {
    let id: String              // "Mon"
    let weekday: String         // "Monday"
    let discipline: PlanDiscipline?
    let title: String
    let duration: String
    var warning: String? = nil
    var spokenWarning: String? = nil
}

struct PlanData {
    var goalTitle: String?
    var goalDetail: String
    var weeks: [PlanWeek]
    var suggestion: String?
    var recurring: [PlanRecurringRow]
    var availability: String              // plain summary of the time available and planned
    var availabilityWarning: String?      // plain sentence naming the conflict, when there is one
    var programName: String? = nil
    /// Shown under the screen when the data is not the athlete's own (e.g. "Cyclift Lab · demo athlete"). nil = nothing.
    var note: String? = nil
}

// (The prototype's sample scenarios are not carried over: the screen is fed from the athlete record by PlanV2Adapter.)

// MARK: - Screen

struct PlanScreen: View {
    let data: PlanData
    var bottomInset: CGFloat = 0
    var initialSection: String? = nil            // weekly | recurring
    var initialDay: Int? = nil                   // day of the month to select at launch
    var sessionStyle: String? = nil              // nil = approved cards (Variant A) · "hybrid" = compact Variant B
    /// What the athlete asked for. The host opens the real screen for it and returns true; anything it cannot do yet is
    /// answered on the page with a plain "not available yet" — never with a made-up result.
    var onRequest: ((PlanV2Request) -> Bool)? = nil
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.cyTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var section = 0               // 0 Weekly Calendar · 1 Recurring Plan
    @State private var weekIndex = 1             // index into data.weeks (1 = current week)
    @State private var selectedDay = 12
    @State private var placeholder: String? = nil
    @State private var didInit = false
    @State private var weekLog: [String] = []    // diagnostic: every week change and where it came from
    private var large: Bool { typeSize.isAccessibilitySize }

    private var week: PlanWeek { data.weeks[min(max(weekIndex, 0), data.weeks.count - 1)] }
    private var day: PlanV2Day { week.days.first { $0.id == selectedDay } ?? week.days[0] }
    private var todayID: Int? { data.weeks.flatMap { $0.days }.first { $0.isToday }?.id }

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header
                    programRow.padding(.top, CySpace.xs)
                    // the note sits above the calendar, where the floating dock can never cover it (Lab run 9)
                    if let note = data.note {
                        Text(note)
                            .font(.caption2).foregroundStyle(theme.textTertiary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .accessibilityIdentifier("planSampleNote")
                    }
                    selector.padding(.top, CySpace.s)
                    if section == 0 { weekly } else { recurring }
                }
                .padding(.horizontal, CySpace.l)
                .padding(.bottom, bottomInset + 44)      // the dock's centre button rises above the bar
            }
            .accessibilityIdentifier("planScroll")
            if let placeholder { placeholderCard(placeholder).padding(.horizontal, CySpace.l).padding(.bottom, bottomInset + CySpace.m) }
        }
        .background(PlanBackdrop().ignoresSafeArea())
        .onAppear {
            guard !didInit else { return }
            didInit = true
            if initialSection == "recurring" { section = 1 }
            if let d = initialDay, let w = data.weeks.firstIndex(where: { wk in wk.days.contains { $0.id == d } }) {
                weekIndex = w
                selectedDay = d
            }
        }
    }

    // MARK: Header, program, selector

    private var header: some View {
        HStack {
            Text("Plan").font(CyFont.display).foregroundStyle(theme.textPrimary)
                .accessibilityAddTraits(.isHeader).accessibilityIdentifier("planTitle")
            Spacer()
            Menu {
                Button(data.goalTitle == nil ? "Set a goal" : "Add another goal") { act("Add a goal") }
                Button("Routines") { act("Routines") }
                Button("Availability & preferences") { act("Availability & preferences") }
                Button("Plan history") { act("Plan history") }
            } label: {
                Image(systemName: "ellipsis").font(.headline).foregroundStyle(theme.textPrimary)
                    .frame(width: 36, height: 36).background(Circle().fill(theme.surface2))
                    .frame(width: 44, height: 44).contentShape(Rectangle())
            }
            .accessibilityLabel("More").accessibilityIdentifier("planMore")
        }
        .frame(minHeight: 44)
    }

    /// With a goal: its name and context; the row opens the details and carries no "add" action (that lives in More).
    /// Without a goal: a clear "Set your goal" state with one action.
    private var programRow: some View {
        let hasGoal = data.goalTitle != nil
        let layout = large && !hasGoal ? AnyLayout(VStackLayout(alignment: .leading, spacing: CySpace.xs)) : AnyLayout(HStackLayout(spacing: CySpace.s))
        return layout {
            Button(action: { act("Goal & Program") }) {
                HStack(spacing: CySpace.s) {
                    Image(systemName: hasGoal ? "flag.fill" : "scope").font(.footnote.weight(.semibold))
                        .foregroundStyle(theme.accent).frame(width: 28, height: 28).background(Circle().fill(theme.accentSubtle))
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(data.goalTitle ?? "Set your goal").font(.subheadline.weight(.bold)).foregroundStyle(theme.textPrimary)
                            .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                        Text(data.goalDetail).font(.caption).foregroundStyle(theme.textSecondary)
                            .lineLimit(large ? 4 : 2).fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                    if hasGoal {
                        Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(theme.textTertiary).accessibilityHidden(true)
                    }
                }
                .padding(.vertical, 6).frame(minHeight: 44).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityHint("Opens goal and program")
            .accessibilityIdentifier("planProgram")
            if !hasGoal {
                Button(action: { act("Set a goal") }) {
                    Text("Set goal").font(.caption.weight(.bold)).foregroundStyle(theme.textOnAccent)
                        .padding(.horizontal, 14).frame(minHeight: 32)
                        .background(Capsule().fill(theme.accent))
                        .frame(minHeight: 44).contentShape(Rectangle())
                        .fixedSize(horizontal: true, vertical: false)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("planSetGoal")
            }
        }
        .padding(.leading, CySpace.m).padding(.trailing, CySpace.m).padding(.vertical, 2)
        .background(programFill, in: RoundedRectangle(cornerRadius: CyRadius.m, style: .continuous))
        .background(theme.surface.opacity(theme.isDark ? 0.6 : 1), in: RoundedRectangle(cornerRadius: CyRadius.m, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: CyRadius.m, style: .continuous).strokeBorder(theme.cardStroke, lineWidth: theme.borderWidth))
    }
    private var programFill: LinearGradient {
        theme.usesGradients
            ? LinearGradient(colors: [theme.accent.opacity(theme.isDark ? 0.22 : 0.10), theme.surface.opacity(0)], startPoint: .leading, endPoint: UnitPoint(x: 0.7, y: 0.5))
            : LinearGradient(colors: [theme.surface, theme.surface], startPoint: .leading, endPoint: .trailing)
    }

    private var selector: some View {
        HStack(spacing: 0) {
            selectorButton("Weekly Calendar", 0, "planSection-weekly")
            selectorButton("Recurring Plan", 1, "planSection-recurring")
        }
        .padding(3)
        .background(RoundedRectangle(cornerRadius: 13, style: .continuous).fill(theme.surface2))
        .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).strokeBorder(theme.id == .highContrast ? theme.border : Color.clear, lineWidth: 1))
    }
    private func selectorButton(_ title: String, _ index: Int, _ id: String) -> some View {
        let on = section == index
        return Button(action: { section = index }) {
            Text(title).font(.footnote.weight(.semibold)).lineLimit(2).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .foregroundStyle(on ? (theme.id == .highContrast ? theme.background : theme.textPrimary) : theme.textSecondary)
                .padding(.horizontal, 6).padding(.vertical, 4)
                .frame(maxWidth: .infinity).frame(minHeight: 44)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(on ? (theme.id == .highContrast ? theme.textPrimary : theme.surface) : Color.clear))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? [.isSelected] : [])
        .accessibilityIdentifier(id)
    }

    // MARK: Weekly Calendar

    private var weekly: some View {
        VStack(alignment: .leading, spacing: 0) {
            weekBar.padding(.top, CySpace.xs)
            TabView(selection: $weekIndex) {
                ForEach(Array(data.weeks.enumerated()), id: \.offset) { index, w in
                    HStack(spacing: 0) {
                        ForEach(w.days) { d in dayCircle(d) }
                    }
                    .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(height: 86)
            .dynamicTypeSize(...DynamicTypeSize.xxLarge)
            .padding(.horizontal, -CySpace.xs)
            .onChange(of: weekIndex) { old, new in
                note("week index \(old) to \(new)")
                // keep a day selected inside the visible week: the same weekday, or today when the week holds it
                let days = data.weeks[new].days
                if days.contains(where: { $0.id == selectedDay }) { return }
                let position = data.weeks.flatMap { $0.days }.firstIndex { $0.id == selectedDay }.map { $0 % 7 } ?? 0
                selectedDay = days.first { $0.isToday }?.id ?? days[min(position, days.count - 1)].id
            }
            if let text = data.suggestion, week.id == 0 { coachRow(text).padding(.top, CySpace.xs) }
            dayHeader
            dayContent
        }
    }

    private var weekBar: some View {
        HStack(spacing: 0) {
            navButton("chevron.left", "Previous week", "planWeekPrev", enabled: weekIndex > 0) { move(-1) }
            Spacer(minLength: 0)
            Text(week.title).font(.footnote.weight(.bold)).foregroundStyle(theme.textPrimary)
                .accessibilityValue(weekLog.suffix(10).joined(separator: " | "))
                .accessibilityIdentifier("planWeekTitle")
            if week.id != 0 || selectedDay != todayID {
                Button(action: goToday) {
                    Text("Today").font(.caption.weight(.bold)).foregroundStyle(theme.accent)
                        .padding(.horizontal, 10).frame(minHeight: 44).contentShape(Rectangle())
                }
                .buttonStyle(.plain).accessibilityIdentifier("planToday")
            }
            Spacer(minLength: 0)
            navButton("chevron.right", "Next week", "planWeekNext", enabled: weekIndex < data.weeks.count - 1) { move(1) }
        }
        .frame(minHeight: 44)
    }
    private func navButton(_ icon: String, _ label: String, _ id: String, enabled: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.footnote.weight(.bold))
                .foregroundStyle(enabled ? theme.textSecondary : theme.disabledText)
                .frame(width: 44, height: 44).contentShape(Rectangle())
        }
        .buttonStyle(.plain).disabled(!enabled)
        .accessibilityLabel(label).accessibilityIdentifier(id)
    }
    private func move(_ step: Int) {
        let target = min(max(weekIndex + step, 0), data.weeks.count - 1)
        note("arrow \(step > 0 ? "next" : "previous") pressed at index \(weekIndex), target \(target)")
        if reduceMotion { weekIndex = target } else { withAnimation(.easeInOut(duration: 0.25)) { weekIndex = target } }
    }
    private func goToday() {
        guard let t = todayID, let w = data.weeks.firstIndex(where: { wk in wk.days.contains { $0.id == t } }) else { return }
        selectedDay = t
        note("today pressed at index \(weekIndex), target \(w)")
        if reduceMotion { weekIndex = w } else { withAnimation(.easeInOut(duration: 0.25)) { weekIndex = w } }
    }

    private func note(_ text: String) { weekLog.append(text) }

    private func dayCircle(_ d: PlanV2Day) -> some View {
        let on = d.id == selectedDay
        return Button(action: { selectedDay = d.id }) {
            VStack(spacing: 4) {
                Text(d.letter).font(.caption2.weight(.semibold)).foregroundStyle(on ? theme.textPrimary : theme.textSecondary)
                Text("\(d.id)").font(.callout.weight(.bold)).monospacedDigit()
                    .foregroundStyle(on ? theme.textOnAccent : theme.textPrimary)
                    .frame(width: 44, height: 44)
                    .background(circleFill(on: on))
                    .overlay(Circle().strokeBorder(circleStroke(d, on: on), lineWidth: d.isToday && !on ? 1.5 : 1))
                    .shadow(color: on && theme.usesGradients ? theme.endurance.opacity(0.55) : Color.clear, radius: 8, x: 0, y: 4)
                marks(d).frame(height: 8)
            }
            .frame(maxWidth: .infinity).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken(d))
        .accessibilityAddTraits(on ? [.isButton, .isSelected] : [.isButton])
        .accessibilityIdentifier("planDay-\(d.id)")
    }
    @ViewBuilder private func circleFill(on: Bool) -> some View {
        if on {
            if theme.usesGradients {
                Circle().fill(LinearGradient(colors: [theme.endurance, theme.accent], startPoint: .topLeading, endPoint: .bottomTrailing))
            } else {
                Circle().fill(theme.accent)
            }
        } else {
            Circle().fill(theme.surface2)
        }
    }
    private func circleStroke(_ d: PlanV2Day, on: Bool) -> Color {
        if on { return Color.clear }
        if d.isToday { return theme.accent }
        return theme.id == .highContrast ? theme.border : Color.clear
    }
    @ViewBuilder private func marks(_ d: PlanV2Day) -> some View {
        HStack(spacing: 4) {
            if d.isRest {
                Capsule().fill(theme.textSecondary.opacity(0.7)).frame(width: 9, height: 2)
            } else {
                ForEach(Array(d.sessions.prefix(2).enumerated()), id: \.offset) { _, s in
                    if s.discipline == .endurance {
                        Circle().fill(theme.endurance).frame(width: 7, height: 7)
                    } else {
                        RoundedRectangle(cornerRadius: 1.5).fill(theme.strength).frame(width: 7, height: 7)
                    }
                }
                if d.sessions.count > 2 { Text("+").font(.system(size: 9, weight: .bold)).foregroundStyle(theme.textSecondary) }
            }
        }
        .accessibilityHidden(true)
    }
    private func spoken(_ d: PlanV2Day) -> String {
        var parts = ["\(d.weekday) \(d.id) November"]
        if d.isToday { parts.append("today") }
        if d.isRest { parts.append("rest day") }
        else if d.sessions.isEmpty { parts.append("nothing scheduled") }
        else {
            let n = d.sessions.count
            parts.append("\(n) session\(n == 1 ? "" : "s"): " + d.sessions.map { $0.discipline.word }.joined(separator: ", "))
        }
        return parts.joined(separator: ", ")
    }

    private func coachRow(_ text: String) -> some View {
        Button(action: { act("Coach proposal") }) {
            HStack(spacing: CySpace.s) {
                Image(systemName: "sparkles").font(.footnote).foregroundStyle(theme.accent).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 0) {
                    Text("COACH SUGGESTS").font(.system(size: 9.5, weight: .semibold)).tracking(0.4).foregroundStyle(theme.textSecondary)
                    Text(text).font(.footnote.weight(.semibold)).foregroundStyle(theme.textPrimary).lineLimit(large ? 4 : 2).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: CySpace.xs)
                Text("Review").font(.footnote.weight(.bold)).foregroundStyle(theme.accent)
                Image(systemName: "chevron.right").font(.caption2.weight(.bold)).foregroundStyle(theme.accent).accessibilityHidden(true)
            }
            .padding(.horizontal, CySpace.m).padding(.vertical, 5).frame(minHeight: 44)
            .background(RoundedRectangle(cornerRadius: 13, style: .continuous).fill(theme.surface.opacity(theme.id == .highContrast ? 1 : 0.7)))
            .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).strokeBorder(theme.border, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Coach suggests: \(text). Review")
        .accessibilityIdentifier("planCoachRow")
    }

    private var dayHeader: some View {
        let layout = large ? AnyLayout(VStackLayout(alignment: .leading, spacing: 0)) : AnyLayout(HStackLayout())
        return layout {
            Text(day.title + (day.isToday ? " · Today" : "")).font(.subheadline.weight(.bold)).foregroundStyle(theme.textPrimary)
                .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader).accessibilityIdentifier("planDayHeader")
            if !large { Spacer() }
            Button(action: { act("Add session") }) {
                Text("+ Add session").font(.caption.weight(.bold)).foregroundStyle(theme.background)
                    .padding(.horizontal, 13).frame(minHeight: 32).background(Capsule().fill(theme.textPrimary))
                    .fixedSize(horizontal: true, vertical: false)
                    .frame(minHeight: 44).contentShape(Rectangle())
            }
            .buttonStyle(.plain).accessibilityLabel("Add session").accessibilityIdentifier("planAddSession")
        }
        .padding(.top, large ? CySpace.s : 0)
    }

    @ViewBuilder private var dayContent: some View {
        if day.isRest && day.sessions.isEmpty {
            quietRow(icon: "moon.fill", title: "Rest day", detail: "Planned rest in your recurring plan", id: "planRest")
        } else if day.sessions.isEmpty {
            quietRow(icon: "calendar", title: "Nothing scheduled", detail: "Add a session, or leave the day free", id: "planEmpty")
        } else {
            VStack(spacing: sessionStyle == "hybrid" ? 6 : CySpace.s) {
                ForEach(day.sessions) { s in
                    if sessionStyle == "hybrid" {
                        PlanSessionHybridRow(session: s, onOpen: { act("Session detail", session: s) }, onMore: { act("Session actions", session: s) })
                    } else {
                        PlanSessionCard(session: s, onOpen: { act("Session detail", session: s) }, onMore: { act("Session actions", session: s) })
                    }
                }
            }
        }
    }
    private func quietRow(icon: String, title: String, detail: String, id: String) -> some View {
        HStack(spacing: CySpace.m) {
            Image(systemName: icon).font(.body).foregroundStyle(theme.textSecondary)
                .frame(width: 40, height: 40).overlay(Circle().strokeBorder(theme.border, lineWidth: 1)).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(theme.textPrimary)
                Text(detail).font(.caption).foregroundStyle(theme.textSecondary)
            }
            Spacer(minLength: 0)
        }
        .padding(CySpace.m).frame(minHeight: 64)
        .overlay(RoundedRectangle(cornerRadius: CyRadius.m, style: .continuous).strokeBorder(theme.border.opacity(theme.id == .highContrast ? 1 : 0.7), lineWidth: 1))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(id)
    }

    // MARK: Recurring Plan

    private var recurring: some View {
        VStack(spacing: 2) {
            ForEach(data.recurring) { row in recurringRow(row) }
            Button(action: { act("Availability & preferences") }) {
                HStack(spacing: CySpace.s) {
                    VStack(alignment: .leading, spacing: 3) {
                        let head = large ? AnyLayout(VStackLayout(alignment: .leading, spacing: 2)) : AnyLayout(HStackLayout(spacing: CySpace.s))
                        head {
                            Text("Availability & preferences").font(.footnote.weight(.semibold)).foregroundStyle(theme.textPrimary)
                                .lineLimit(large ? 3 : 1).fixedSize(horizontal: false, vertical: true)
                            if !large { Spacer(minLength: CySpace.xs) }
                            Text(data.availability).font(.caption).foregroundStyle(theme.textSecondary)
                                .lineLimit(large ? 3 : 1).minimumScaleFactor(large ? 1 : 0.85).fixedSize(horizontal: false, vertical: true)
                        }
                        if let w = data.availabilityWarning {
                            Label(w, systemImage: "exclamationmark.triangle.fill").font(.caption.weight(.bold)).foregroundStyle(theme.textPrimary)
                                .lineLimit(3).fixedSize(horizontal: false, vertical: true)
                                .accessibilityIdentifier("planAvailabilityConflict")
                        }
                    }
                    Spacer(minLength: CySpace.xs)
                    Image(systemName: "chevron.right").font(.caption2.weight(.bold)).foregroundStyle(theme.textTertiary).accessibilityHidden(true)
                }
                .padding(.horizontal, CySpace.m).padding(.vertical, CySpace.s).frame(minHeight: 48)
                .background(RoundedRectangle(cornerRadius: 13, style: .continuous).fill(theme.surface))
                .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).strokeBorder(theme.cardStroke, lineWidth: theme.borderWidth))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityValue(data.availabilityWarning ?? "")
            .accessibilityIdentifier("planAvailability")
            .padding(.top, 2)
        }
        .padding(.top, CySpace.s)
    }

    private func recurringRow(_ row: PlanRecurringRow) -> some View {
        let tint: Color = row.discipline == .endurance ? theme.endurance : (row.discipline == .strength ? theme.strength : theme.surface2)
        let isRest = row.discipline == nil
        var spoken = row.weekday + ", " + row.title
        if !row.duration.isEmpty { spoken += ", " + row.duration }
        if let w = row.spokenWarning { spoken += ", warning: " + w }
        let label = spoken
        return Button(action: { act("Edit \(row.weekday)", weekday: row.id) }) {
            HStack(spacing: CySpace.m) {
                Text(row.id).font(.caption.weight(.heavy)).lineLimit(1).fixedSize()
                    .foregroundStyle(isRest ? theme.textSecondary : (theme.isDark ? theme.background : theme.surface))
                    .padding(.horizontal, 8).frame(minWidth: 40, minHeight: 28).background(Capsule().fill(tint))
                let titleText = Text(row.title).font(.footnote.weight(isRest ? .regular : .bold))
                    .foregroundStyle(isRest ? theme.textSecondary : theme.textPrimary)
                if large {
                    VStack(alignment: .leading, spacing: 2) {
                        titleText.lineLimit(2).fixedSize(horizontal: false, vertical: true)
                        recurringTrailing(row).fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: CySpace.xs)
                } else {
                    titleText.lineLimit(1)
                    Spacer(minLength: CySpace.xs)
                    recurringTrailing(row).lineLimit(1)
                }
                Image(systemName: "chevron.right").font(.caption2.weight(.bold)).foregroundStyle(theme.textTertiary).accessibilityHidden(true)
            }
            .padding(.vertical, large ? 6 : 0)
            .padding(.leading, 7).padding(.trailing, CySpace.s).frame(minHeight: 46)
            .background(recurringFill(tint, isRest: isRest))
            .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous)
                .strokeBorder(theme.id == .highContrast || isRest ? theme.border.opacity(theme.id == .highContrast ? 1 : 0.6) : Color.clear, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(row.warning ?? "")
        .accessibilityIdentifier("planRecurring-\(row.id)")
    }
    @ViewBuilder private func recurringTrailing(_ row: PlanRecurringRow) -> some View {
        if let w = row.warning {
            Label(w, systemImage: "exclamationmark.triangle.fill").font(.caption.weight(.bold)).foregroundStyle(theme.textPrimary)
        } else {
            Text(row.duration).font(.caption).foregroundStyle(theme.textSecondary)
        }
    }
    @ViewBuilder private func recurringFill(_ tint: Color, isRest: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: 13, style: .continuous)
        if isRest {
            shape.fill(Color.clear)
        } else if theme.usesGradients {
            shape.fill(theme.surface).overlay(shape.fill(LinearGradient(colors: [tint.opacity(theme.isDark ? 0.22 : 0.14), tint.opacity(0)], startPoint: .leading, endPoint: UnitPoint(x: 0.55, y: 0.5))))
        } else {
            shape.fill(theme.surface)
        }
    }

    // MARK: Placeholder (no sheet: editing sheets are a later, separately approved round)

    private func act(_ name: String, session: PlanSession? = nil, weekday: String? = nil) {
        if onRequest?(PlanV2Request(name: name, session: session, day: day, weekday: weekday)) != true { placeholder = name }
    }

    private func placeholderCard(_ name: String) -> some View {
        HStack(alignment: .top, spacing: CySpace.m) {
            Image(systemName: "hammer.fill").font(.footnote).foregroundStyle(theme.textSecondary).padding(.top, 2).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("Not available yet").font(.caption.weight(.bold)).foregroundStyle(theme.textSecondary)
                Text("\(name) is not in the app yet.").font(.footnote.weight(.semibold)).foregroundStyle(theme.textPrimary)
            }
            Spacer(minLength: 0)
            Button(action: { placeholder = nil }) {
                Image(systemName: "xmark").font(.caption.weight(.bold)).foregroundStyle(theme.textPrimary)
                    .frame(width: 44, height: 44).contentShape(Rectangle())
            }
            .buttonStyle(.plain).accessibilityLabel("Close").accessibilityIdentifier("planPlaceholderClose")
        }
        .padding(.leading, CySpace.m).padding(.vertical, CySpace.s)
        .background(RoundedRectangle(cornerRadius: CyRadius.m, style: .continuous).fill(theme.surface2))
        .overlay(RoundedRectangle(cornerRadius: CyRadius.m, style: .continuous).strokeBorder(theme.border, lineWidth: 1))
        .shadow(color: Color.black.opacity(theme.usesGradients ? 0.25 : 0), radius: 12, x: 0, y: 6)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("planPlaceholder")
    }
}

// MARK: - Session card

struct PlanSessionCard: View {
    let session: PlanSession
    let onOpen: () -> Void
    let onMore: () -> Void
    @Environment(\.cyTheme) private var theme

    private var tint: Color { session.discipline == .endurance ? theme.endurance : theme.strength }
    private var missed: Bool { session.status == .missed }

    var body: some View {
        HStack(spacing: CySpace.m) {
            badge
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: CySpace.s) {
                    Text(session.title).font(.subheadline.weight(.bold)).foregroundStyle(theme.textPrimary.opacity(session.status == .done ? 0.85 : 1)).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: CySpace.xs)
                    status
                }
                Text(session.detail).font(.caption).foregroundStyle(theme.textSecondary).lineLimit(3).fixedSize(horizontal: false, vertical: true)
                if !session.structure.isEmpty && !missed { PlanStructureBar(segments: session.structure, tint: tint) }
                if let link = session.link {
                    Text("↳ " + link).font(.caption.weight(.medium)).foregroundStyle(theme.textPrimary).lineLimit(3).fixedSize(horizontal: false, vertical: true)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture(perform: onOpen)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
            .accessibilityValue(!session.structure.isEmpty && !missed ? "planned structure shown" : "no structure shown")
            .accessibilityIdentifier("planSession-\(session.id)")
            Button(action: onMore) {
                Image(systemName: "ellipsis").font(.footnote.weight(.bold)).foregroundStyle(theme.textSecondary)
                    .frame(width: 36, height: 44).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("More actions for \(session.title)")
            .accessibilityIdentifier("planSessionMore-\(session.id)")
        }
        .padding(.leading, CySpace.m).padding(.vertical, CySpace.m).padding(.trailing, 2)
        .frame(minHeight: 72)
        .background(fill)
        .overlay(RoundedRectangle(cornerRadius: CyRadius.m, style: .continuous).strokeBorder(stroke, style: StrokeStyle(lineWidth: 1, dash: missed ? [5, 4] : [])))
        .shadow(color: Color.black.opacity(theme.usesGradients && !missed ? (theme.isDark ? 0.22 : 0.08) : 0), radius: 9, x: 0, y: 5)
    }

    @ViewBuilder private var badge: some View {
        let icon = Image(systemName: session.discipline.icon).font(.callout.weight(.semibold))
        if missed {
            icon.foregroundStyle(theme.textSecondary).frame(width: 40, height: 40)
                .overlay(badgeShape.strokeBorder(theme.textSecondary, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3])))
                .accessibilityHidden(true)
        } else {
            icon.foregroundStyle(theme.isDark ? theme.background : theme.surface).frame(width: 40, height: 40)
                .background(badgeShape.fill(tint))
                .accessibilityHidden(true)
        }
    }
    private var badgeShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: session.discipline == .endurance ? 20 : 12, style: .continuous)
    }

    @ViewBuilder private var status: some View {
        switch session.status {
        case .planned:
            Text("Planned").font(.caption2.weight(.semibold)).foregroundStyle(theme.textSecondary)
        case .done:
            Label("Done", systemImage: "checkmark").font(.caption2.weight(.semibold)).foregroundStyle(theme.textSecondary)
        case .missed:
            Text("Missed").font(.caption2.weight(.semibold)).foregroundStyle(theme.textPrimary)
                .padding(.horizontal, 6).padding(.vertical, 1)
                .overlay(Capsule().strokeBorder(theme.textSecondary, style: StrokeStyle(lineWidth: 1, dash: [3, 2])))
        case .skipped:
            Text("Skipped").font(.caption2.weight(.semibold)).foregroundStyle(theme.textSecondary)
        }
    }

    @ViewBuilder private var fill: some View {
        let shape = RoundedRectangle(cornerRadius: CyRadius.m, style: .continuous)
        if missed {
            shape.fill(Color.clear)
        } else if theme.usesGradients {
            shape.fill(theme.surface).overlay(shape.fill(LinearGradient(colors: [tint.opacity(theme.isDark ? 0.26 : 0.16), tint.opacity(0)], startPoint: .leading, endPoint: UnitPoint(x: 0.62, y: 0.5))))
        } else {
            shape.fill(theme.surface)
        }
    }
    private var stroke: Color {
        if missed { return theme.textSecondary }
        return theme.id == .highContrast ? theme.border : Color.clear
    }
}

/// Variant B — hybrid compact presentation (comparison only; not the approved layout).
/// Keeps discipline colour and icon, name, duration, truthful status and the rescheduling relationship. A compact
/// planned-structure indicator is shown only when it is informative (intervals, a list of exercises) — never for an
/// ordinary steady session, and it describes the plan, not completion.
struct PlanSessionHybridRow: View {
    let session: PlanSession
    let onOpen: () -> Void
    let onMore: () -> Void
    @Environment(\.cyTheme) private var theme
    @Environment(\.dynamicTypeSize) private var typeSize

    private var tint: Color { session.discipline == .endurance ? theme.endurance : theme.strength }
    private var missed: Bool { session.status == .missed }
    private var showsStructure: Bool { session.hasInformativeStructure && !missed }

    var body: some View {
        HStack(spacing: 10) {
            badge
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: CySpace.s) {
                    Text(session.title).font(.subheadline.weight(.bold)).foregroundStyle(theme.textPrimary.opacity(session.status == .done ? 0.85 : 1))
                        .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: CySpace.xs)
                    status
                }
                HStack(alignment: .center, spacing: CySpace.s) {
                    Text(session.detail).font(.caption).foregroundStyle(theme.textSecondary)
                        .lineLimit(typeSize.isAccessibilitySize ? 3 : 1).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    if showsStructure && !typeSize.isAccessibilitySize { PlanStructureBar(segments: session.structure, tint: tint, width: 84, height: 12) }
                }
                if showsStructure && typeSize.isAccessibilitySize { PlanStructureBar(segments: session.structure, tint: tint, width: 120, height: 12) }
                if let link = session.link {
                    Text("↳ " + link).font(.caption2.weight(.medium)).foregroundStyle(theme.textPrimary).lineLimit(3).fixedSize(horizontal: false, vertical: true)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture(perform: onOpen)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
            .accessibilityValue(showsStructure ? "planned structure shown" : "no structure shown")
            .accessibilityIdentifier("planSession-\(session.id)")
            Button(action: onMore) {
                Image(systemName: "ellipsis").font(.footnote.weight(.bold)).foregroundStyle(theme.textSecondary)
                    .frame(width: 36, height: 44).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("More actions for \(session.title)")
            .accessibilityIdentifier("planSessionMore-\(session.id)")
        }
        .padding(.leading, 10).padding(.vertical, 6).padding(.trailing, 2)
        .frame(minHeight: 56)
        .background(fill)
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(stroke, style: StrokeStyle(lineWidth: 1, dash: missed ? [5, 4] : [])))
    }

    @ViewBuilder private var badge: some View {
        let icon = Image(systemName: session.discipline.icon).font(.footnote.weight(.semibold))
        let shape = RoundedRectangle(cornerRadius: session.discipline == .endurance ? 17 : 10, style: .continuous)
        if missed {
            icon.foregroundStyle(theme.textSecondary).frame(width: 34, height: 34)
                .overlay(shape.strokeBorder(theme.textSecondary, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))).accessibilityHidden(true)
        } else {
            icon.foregroundStyle(theme.isDark ? theme.background : theme.surface).frame(width: 34, height: 34)
                .background(shape.fill(tint)).accessibilityHidden(true)
        }
    }
    @ViewBuilder private var status: some View {
        switch session.status {
        case .planned:
            Text("Planned").font(.caption2.weight(.semibold)).foregroundStyle(theme.textSecondary)
        case .done:
            Label("Done", systemImage: "checkmark").font(.caption2.weight(.semibold)).foregroundStyle(theme.textSecondary)
        case .missed:
            Text("Missed").font(.caption2.weight(.semibold)).foregroundStyle(theme.textPrimary)
                .padding(.horizontal, 6).padding(.vertical, 1)
                .overlay(Capsule().strokeBorder(theme.textSecondary, style: StrokeStyle(lineWidth: 1, dash: [3, 2])))
        case .skipped:
            Text("Skipped").font(.caption2.weight(.semibold)).foregroundStyle(theme.textSecondary)
        }
    }
    @ViewBuilder private var fill: some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        if missed {
            shape.fill(Color.clear)
        } else if theme.usesGradients {
            shape.fill(theme.surface).overlay(shape.fill(LinearGradient(colors: [tint.opacity(theme.isDark ? 0.20 : 0.12), tint.opacity(0)], startPoint: .leading, endPoint: UnitPoint(x: 0.55, y: 0.5))))
        } else {
            shape.fill(theme.surface)
        }
    }
    private var stroke: Color {
        if missed { return theme.textSecondary }
        return theme.id == .highContrast ? theme.border : Color.clear
    }
}

/// The planned structure of a session, from its prescription: segment width = share of the time, height = intensity
/// (ride) or one block per exercise (strength). It describes the plan, not performance. Sample data in this prototype.
struct PlanStructureBar: View {
    let segments: [PlanSegment]
    let tint: Color
    var width: CGFloat = 168
    var height: CGFloat = 14
    var body: some View {
        let total = max(segments.reduce(0) { $0 + $1.weight }, 0.001)
        let gaps = CGFloat(max(segments.count - 1, 0)) * 2
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(Array(segments.enumerated()), id: \.offset) { _, seg in
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(tint)
                    .frame(width: max((width - gaps) * CGFloat(seg.weight / total), 2), height: 4 + (height - 4) * CGFloat(min(max(seg.level, 0), 1)))
            }
        }
        .frame(height: height, alignment: .bottom)
        .padding(.top, 2)
        .accessibilityHidden(true)
    }
}

// MARK: - Backdrop

/// Two soft discipline-coloured glows behind the header (direction B). Flat background in High Contrast.
struct PlanBackdrop: View {
    @Environment(\.cyTheme) private var theme
    var body: some View {
        ZStack {
            theme.background
            if theme.usesGradients {
                RadialGradient(colors: [theme.endurance.opacity(theme.isDark ? 0.26 : 0.16), theme.endurance.opacity(0)],
                               center: UnitPoint(x: 0.9, y: 0), startRadius: 0, endRadius: 380)
                RadialGradient(colors: [theme.strength.opacity(theme.isDark ? 0.16 : 0.10), theme.strength.opacity(0)],
                               center: UnitPoint(x: 0, y: 0.06), startRadius: 0, endRadius: 300)
            }
        }
        .accessibilityHidden(true)
    }
}
