import SwiftUI

// Cyclift UI Lab — Plan v2.0, visual round 1 (direction B "Athletic Dynamic"). PROTOTYPE ONLY.
// Specification: product/plan/PLAN_V2_SPECIFICATION.md v0.6 (documentation branch).
// Everything shown is SAMPLE DATA. There is no planning engine, no real athlete data and no connection to the
// production app. Actions that need an editing sheet or a backend open a labelled prototype placeholder.

// MARK: - Sample model

enum PlanDiscipline: String { case endurance, strength
    var word: String { self == .endurance ? "ride" : "strength" }
    var icon: String { self == .endurance ? "bicycle" : "dumbbell.fill" }
}

enum PlanStatus: String { case planned = "Planned", done = "Done", missed = "Missed" }

struct PlanSegment { let weight: Double; let level: Double }

struct PlanSession: Identifiable {
    let id: String
    let discipline: PlanDiscipline
    let title: String
    let detail: String
    let status: PlanStatus
    var link: String? = nil
    var structure: [PlanSegment] = []
}

struct PlanDay: Identifiable {
    let id: Int                 // day of the month (unique inside the three sample weeks)
    let weekday: String         // "Thursday"
    let short: String           // "Thu"
    let month: String           // "Nov"
    var isToday: Bool = false
    var isRest: Bool = false
    var sessions: [PlanSession] = []
    var letter: String { String(short.prefix(1)) }
    var title: String { "\(short) \(id) \(month)" }
}

struct PlanWeek: Identifiable {
    let id: Int                 // -1 previous, 0 current, 1 next
    let title: String
    let days: [PlanDay]
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
    var availability: String
    var availabilityWarning: String?
}

enum PlanScenario: String { case normal, noSuggestion, noGoal, budget }

enum PlanMock {
    private static func seg(_ pairs: [(Double, Double)]) -> [PlanSegment] { pairs.map { PlanSegment(weight: $0.0, level: $0.1) } }
    private static let ride: [PlanSegment] = seg([(10, 0.2), (8, 1.0), (3, 0.1), (8, 1.0), (3, 0.1), (8, 1.0), (3, 0.1), (8, 1.0), (9, 0.1)])
    private static func lift(_ n: Int) -> [PlanSegment] { (0..<n).map { PlanSegment(weight: $0 < 4 ? 3 : 2, level: 0.6) } }
    private static let steady: [PlanSegment] = [PlanSegment(weight: 1, level: 0.3)]
    private static let long: [PlanSegment] = [PlanSegment(weight: 2, level: 0.2), PlanSegment(weight: 14, level: 0.45), PlanSegment(weight: 2, level: 0.2)]

    private static func s(_ id: String, _ d: PlanDiscipline, _ title: String, _ detail: String, _ status: PlanStatus,
                          link: String? = nil, _ bar: [PlanSegment] = []) -> PlanSession {
        PlanSession(id: id, discipline: d, title: title, detail: detail, status: status, link: link, structure: bar)
    }
    private static func day(_ n: Int, _ weekday: String, today: Bool = false, rest: Bool = false, _ sessions: [PlanSession] = []) -> PlanDay {
        PlanDay(id: n, weekday: weekday, short: String(weekday.prefix(3)), month: "Nov", isToday: today, isRest: rest, sessions: sessions)
    }

    static func make(_ scenario: PlanScenario) -> PlanData {
        let previous = PlanWeek(id: -1, title: "2 – 8 Nov", days: [
            day(2, "Monday", [s("p1", .strength, "Lower Body A", "45 min · 5 exercises", .done, lift(5))]),
            day(3, "Tuesday", [s("p2", .endurance, "Zone 2 Ride", "60 min · Zone 2", .done, steady)]),
            day(4, "Wednesday", [s("p3", .endurance, "Threshold Intervals", "60 min · 3 × 8 min", .done, ride)]),
            day(5, "Thursday", [s("p4", .strength, "Upper Body A", "45 min · 6 exercises", .done, lift(6))]),
            day(6, "Friday", rest: true),
            day(7, "Saturday", [s("p5", .endurance, "Long Ride", "1 h 45 min · Zone 2", .done, long)]),
            day(8, "Sunday", [s("p6", .strength, "Full Body B", "30 min · 5 exercises", .done, lift(5))]),
        ])
        let current = PlanWeek(id: 0, title: "9 – 15 Nov", days: [
            day(9, "Monday", [s("c1", .strength, "Lower Body A", "45 min · 5 exercises", .missed, link: "Rescheduled to Fri 13 Nov")]),
            day(10, "Tuesday", [s("c2", .endurance, "Zone 2 Ride", "60 min · Zone 2", .done, steady)]),
            day(11, "Wednesday", [s("c3", .endurance, "Threshold Intervals", "60 min · 4 × 8 min", .done, ride)]),
            day(12, "Thursday", today: true, [
                s("c4", .strength, "Upper Body A", "45 min · 6 exercises", .planned, lift(6)),
                s("c5", .endurance, "Recovery Spin", "30 min · Zone 2 · added this week", .planned, steady)]),
            day(13, "Friday", [s("c6", .strength, "Lower Body A", "45 min · 5 exercises", .planned, link: "Rescheduled from Mon 9 Nov (missed)", lift(5))]),
            day(14, "Saturday", [s("c7", .endurance, "Long Ride", "2 h · Zone 2", .planned, long)]),
            day(15, "Sunday"),                                   // empty: this week's session was removed
        ])
        let next = PlanWeek(id: 1, title: "16 – 22 Nov", days: [
            day(16, "Monday", [s("n1", .strength, "Lower Body A", "45 min · 5 exercises", .planned, lift(5))]),
            day(17, "Tuesday", [s("n2", .endurance, "Zone 2 Ride", "60 min · Zone 2", .planned, steady)]),
            day(18, "Wednesday", [s("n3", .endurance, "Threshold Intervals", "60 min · 4 × 8 min", .planned, ride)]),
            day(19, "Thursday", [s("n4", .strength, "Upper Body A", "45 min · 6 exercises", .planned, lift(6))]),
            day(20, "Friday", rest: true),
            day(21, "Saturday", [s("n5", .endurance, "Long Ride", "2 h · Zone 2", .planned, long)]),
            day(22, "Sunday", [s("n6", .strength, "Full Body B", "30 min · 5 exercises", .planned, lift(5))]),
        ])
        // Recurring plan — checked sample (specification §24.3): 6 training days of 6 available, 6 h scheduled of a
        // 6 h budget, Saturday's ride (2 h) exceeds Saturday's own limit (1 h).
        var recurring = [
            PlanRecurringRow(id: "Mon", weekday: "Monday", discipline: .strength, title: "Lower Body A", duration: "45 min"),
            PlanRecurringRow(id: "Tue", weekday: "Tuesday", discipline: .endurance, title: "Zone 2 Ride", duration: "60 min"),
            PlanRecurringRow(id: "Wed", weekday: "Wednesday", discipline: .endurance, title: "Threshold Intervals", duration: "60 min"),
            PlanRecurringRow(id: "Thu", weekday: "Thursday", discipline: .strength, title: "Upper Body A", duration: "45 min"),
            PlanRecurringRow(id: "Fri", weekday: "Friday", discipline: nil, title: "Rest", duration: ""),
            PlanRecurringRow(id: "Sat", weekday: "Saturday", discipline: .endurance, title: "Long Ride", duration: "2 h",
                             warning: "2 h · Sat limit 1 h", spokenWarning: "2 hours planned, Saturday's limit is 1 hour"),
            PlanRecurringRow(id: "Sun", weekday: "Sunday", discipline: .strength, title: "Full Body B", duration: "30 min"),
        ]
        var data = PlanData(goalTitle: "Build strength", goalDetail: "Cycling maintained · week 2 of 4",
                            weeks: [previous, current, next], suggestion: "Resolve Saturday’s time conflict",
                            recurring: recurring, availability: "6 days · 6 h of 6 h", availabilityWarning: nil)
        switch scenario {
        case .normal: break
        case .noSuggestion:
            data.suggestion = nil
        case .noGoal:
            data.goalTitle = nil
            data.goalDetail = "Choose what you are training for"
            data.suggestion = nil
        case .budget:
            // week-level conflict: cycling 4 h scheduled against a 3 h cycling budget; no single day is over its limit
            recurring[5] = PlanRecurringRow(id: "Sat", weekday: "Saturday", discipline: .endurance, title: "Long Ride", duration: "2 h")
            data.recurring = recurring
            data.availability = "6 days · 6 h of 5 h"
            data.availabilityWarning = "Cycling 4 h · budget 3 h"
            data.suggestion = "Reduce next week’s planned cycling time"
        }
        return data
    }
}

// MARK: - Screen

struct PlanScreen: View {
    let data: PlanData
    var bottomInset: CGFloat = 0
    var initialSection: String? = nil            // weekly | recurring
    var initialDay: Int? = nil                   // day of the month to select at launch
    @Environment(\.cyTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var section = 0               // 0 Weekly Calendar · 1 Recurring Plan
    @State private var weekIndex = 1             // index into data.weeks (1 = current week)
    @State private var selectedDay = 12
    @State private var placeholder: String? = nil
    @State private var didInit = false

    private var week: PlanWeek { data.weeks[min(max(weekIndex, 0), data.weeks.count - 1)] }
    private var day: PlanDay { week.days.first { $0.id == selectedDay } ?? week.days[0] }
    private var todayID: Int? { data.weeks.flatMap { $0.days }.first { $0.isToday }?.id }

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header
                    programRow.padding(.top, CySpace.xs)
                    selector.padding(.top, CySpace.s)
                    if section == 0 { weekly } else { recurring }
                    Text("Prototype · sample data")
                        .font(.caption2).foregroundStyle(theme.textTertiary)
                        .frame(maxWidth: .infinity).padding(.top, CySpace.l)
                        .accessibilityIdentifier("planSampleNote")
                }
                .padding(.horizontal, CySpace.l)
                .padding(.bottom, bottomInset + CySpace.l)
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
                Button("Routines") { placeholder = "Routines" }
                Button("Availability & preferences") { placeholder = "Availability & preferences" }
                Button("Plan history") { placeholder = "Plan history" }
            } label: {
                Image(systemName: "ellipsis").font(.headline).foregroundStyle(theme.textPrimary)
                    .frame(width: 36, height: 36).background(Circle().fill(theme.surface2))
                    .frame(width: 44, height: 44).contentShape(Rectangle())
            }
            .accessibilityLabel("More").accessibilityIdentifier("planMore")
        }
        .frame(minHeight: 44)
    }

    private var programRow: some View {
        HStack(spacing: CySpace.s) {
            Button(action: { placeholder = "Goal & Program" }) {
                HStack(spacing: CySpace.s) {
                    Image(systemName: data.goalTitle == nil ? "scope" : "flag.fill").font(.footnote.weight(.semibold))
                        .foregroundStyle(theme.accent).frame(width: 28, height: 28).background(Circle().fill(theme.accentSubtle))
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(data.goalTitle ?? "Set your goal").font(.subheadline.weight(.bold)).foregroundStyle(theme.textPrimary).lineLimit(1)
                        Text(data.goalDetail).font(.caption).foregroundStyle(theme.textSecondary).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .frame(minHeight: 44).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityHint("Opens goal and program")
            .accessibilityIdentifier("planProgram")
            Button(action: { placeholder = "Add a goal" }) {
                HStack(spacing: 3) {
                    Image(systemName: "plus").font(.caption.weight(.bold))
                    Text("Add a goal").font(.caption.weight(.bold)).lineLimit(1)
                }
                .foregroundStyle(theme.accent)
                .padding(.horizontal, 10).frame(height: 32)
                .background(Capsule().fill(theme.isDark ? theme.accentSubtle : theme.surface))
                .overlay(Capsule().strokeBorder(theme.accent.opacity(theme.id == .highContrast ? 1 : 0.5), lineWidth: 1))
                .frame(minHeight: 44).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("planAddGoal")
        }
        .padding(.leading, CySpace.m).padding(.trailing, CySpace.s).padding(.vertical, 2)
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
            Text(title).font(.footnote.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.8)
                .foregroundStyle(on ? (theme.id == .highContrast ? theme.background : theme.textPrimary) : theme.textSecondary)
                .frame(maxWidth: .infinity).frame(minHeight: 38)
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
            .onChange(of: weekIndex) { _, new in
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
        if reduceMotion { weekIndex = target } else { withAnimation(.easeInOut(duration: 0.25)) { weekIndex = target } }
    }
    private func goToday() {
        guard let t = todayID, let w = data.weeks.firstIndex(where: { wk in wk.days.contains { $0.id == t } }) else { return }
        selectedDay = t
        if reduceMotion { weekIndex = w } else { withAnimation(.easeInOut(duration: 0.25)) { weekIndex = w } }
    }

    private func dayCircle(_ d: PlanDay) -> some View {
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
    private func circleStroke(_ d: PlanDay, on: Bool) -> Color {
        if on { return Color.clear }
        if d.isToday { return theme.accent }
        return theme.id == .highContrast ? theme.border : Color.clear
    }
    @ViewBuilder private func marks(_ d: PlanDay) -> some View {
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
    private func spoken(_ d: PlanDay) -> String {
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
        Button(action: { placeholder = "Coach proposal" }) {
            HStack(spacing: CySpace.s) {
                Image(systemName: "sparkles").font(.footnote).foregroundStyle(theme.accent).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 0) {
                    Text("COACH SUGGESTS").font(.system(size: 9.5, weight: .semibold)).tracking(0.4).foregroundStyle(theme.textSecondary)
                    Text(text).font(.footnote.weight(.semibold)).foregroundStyle(theme.textPrimary).lineLimit(2)
                }
                Spacer(minLength: CySpace.xs)
                Text("Review").font(.footnote.weight(.bold)).foregroundStyle(theme.accent)
                Image(systemName: "chevron.right").font(.caption2.weight(.bold)).foregroundStyle(theme.accent).accessibilityHidden(true)
            }
            .padding(.horizontal, CySpace.m).frame(minHeight: 44)
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
        HStack {
            Text(day.title + (day.isToday ? " · Today" : "")).font(.subheadline.weight(.bold)).foregroundStyle(theme.textPrimary)
                .accessibilityAddTraits(.isHeader).accessibilityIdentifier("planDayHeader")
            Spacer()
            Button(action: { placeholder = "Add session" }) {
                Text("+ Add session").font(.caption.weight(.bold)).foregroundStyle(theme.background)
                    .padding(.horizontal, 13).frame(height: 32).background(Capsule().fill(theme.textPrimary))
                    .frame(minHeight: 44).contentShape(Rectangle())
            }
            .buttonStyle(.plain).accessibilityLabel("Add session").accessibilityIdentifier("planAddSession")
        }
    }

    @ViewBuilder private var dayContent: some View {
        if day.isRest && day.sessions.isEmpty {
            quietRow(icon: "moon.fill", title: "Rest day", detail: "Planned rest in your recurring plan", id: "planRest")
        } else if day.sessions.isEmpty {
            quietRow(icon: "calendar", title: "Nothing scheduled", detail: "Add a session, or leave the day free", id: "planEmpty")
        } else {
            VStack(spacing: CySpace.s) {
                ForEach(day.sessions) { s in PlanSessionCard(session: s, onOpen: { placeholder = "Session detail" }, onMore: { placeholder = "Session actions" }) }
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
        VStack(spacing: 3) {
            ForEach(data.recurring) { row in recurringRow(row) }
            Button(action: { placeholder = "Availability & preferences" }) {
                HStack(spacing: CySpace.s) {
                    Text("Availability & preferences").font(.footnote.weight(.semibold)).foregroundStyle(theme.textPrimary).lineLimit(1).minimumScaleFactor(0.85)
                    Spacer(minLength: CySpace.xs)
                    if let w = data.availabilityWarning {
                        Label(w, systemImage: "exclamationmark.triangle.fill").font(.caption.weight(.bold)).foregroundStyle(theme.textPrimary).lineLimit(1)
                    } else {
                        Text(data.availability).font(.caption).foregroundStyle(theme.textSecondary).lineLimit(1)
                    }
                    Image(systemName: "chevron.right").font(.caption2.weight(.bold)).foregroundStyle(theme.textTertiary).accessibilityHidden(true)
                }
                .padding(.horizontal, CySpace.m).frame(minHeight: 48)
                .background(RoundedRectangle(cornerRadius: 13, style: .continuous).fill(theme.surface))
                .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).strokeBorder(theme.cardStroke, lineWidth: theme.borderWidth))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("planAvailability")
            .padding(.top, 3)
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
        return Button(action: { placeholder = "Edit \(row.weekday)" }) {
            HStack(spacing: CySpace.m) {
                Text(row.id).font(.caption.weight(.heavy))
                    .foregroundStyle(isRest ? theme.textSecondary : (theme.isDark ? theme.background : theme.surface))
                    .frame(width: 40, height: 28).background(Capsule().fill(tint))
                Text(row.title).font(.footnote.weight(isRest ? .regular : .bold))
                    .foregroundStyle(isRest ? theme.textSecondary : theme.textPrimary).lineLimit(1)
                Spacer(minLength: CySpace.xs)
                if let w = row.warning {
                    Label(w, systemImage: "exclamationmark.triangle.fill").font(.caption.weight(.bold)).foregroundStyle(theme.textPrimary).lineLimit(1)
                } else {
                    Text(row.duration).font(.caption).foregroundStyle(theme.textSecondary)
                }
                Image(systemName: "chevron.right").font(.caption2.weight(.bold)).foregroundStyle(theme.textTertiary).accessibilityHidden(true)
            }
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

    private func placeholderCard(_ name: String) -> some View {
        HStack(alignment: .top, spacing: CySpace.m) {
            Image(systemName: "hammer.fill").font(.footnote).foregroundStyle(theme.textSecondary).padding(.top, 2).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("Prototype placeholder").font(.caption.weight(.bold)).foregroundStyle(theme.textSecondary)
                Text("\(name) is not built in this visual round.").font(.footnote.weight(.semibold)).foregroundStyle(theme.textPrimary)
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
                    Text(session.title).font(.subheadline.weight(.bold)).foregroundStyle(theme.textPrimary.opacity(session.status == .done ? 0.85 : 1)).lineLimit(1)
                    Spacer(minLength: CySpace.xs)
                    status
                }
                Text(session.detail).font(.caption).foregroundStyle(theme.textSecondary).lineLimit(2)
                if !session.structure.isEmpty && !missed { PlanStructureBar(segments: session.structure, tint: tint) }
                if let link = session.link {
                    Text("↳ " + link).font(.caption.weight(.medium)).foregroundStyle(theme.textPrimary).lineLimit(2)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture(perform: onOpen)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
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

/// The planned structure of a session, from its prescription: segment width = share of the time, height = intensity
/// (ride) or one block per exercise (strength). It describes the plan, not performance. Sample data in this prototype.
struct PlanStructureBar: View {
    let segments: [PlanSegment]
    let tint: Color
    private let width: CGFloat = 168
    var body: some View {
        let total = max(segments.reduce(0) { $0 + $1.weight }, 0.001)
        let gaps = CGFloat(max(segments.count - 1, 0)) * 2
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(Array(segments.enumerated()), id: \.offset) { _, seg in
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(tint)
                    .frame(width: max((width - gaps) * CGFloat(seg.weight / total), 2), height: 4 + 10 * CGFloat(min(max(seg.level, 0), 1)))
            }
        }
        .frame(height: 14, alignment: .bottom)
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
