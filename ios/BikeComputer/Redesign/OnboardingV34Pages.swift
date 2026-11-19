import SwiftUI

// Onboarding pages 1, 4, 5, 6 and 7 drawn to the v3.3 reference sheets (Y1 lower row, Y4, Y5). The sheets are the
// established direction, not a final approval. Every page writes through the same `OnboardingAnswers` and the same
// settings the app already has: nothing new is stored and the plan is made by the existing planner.
//
// Where the sheets draw something the app cannot store, the page stays truthful instead of imitating it:
// • Page 4: the app stores ONE ride length and ONE strength length for the week and no cycling modality per session,
//   so the day editor changes what a day holds (ride, strength, both, rest) and the two lengths apply to every
//   session of that sport. The page says so.
// • Page 6: no stage is evaluated. The track is drawn empty (the sheet's new-athlete state) and names no stage.

// MARK: - Shared pieces

/// A group header of the sheets: provenance mark, tracked title and an optional trailing note.
struct OnbGroupHeader: View {
    enum Mark { case declared, proposal, measured, none
        var glyph: String { switch self { case .declared: return "●"; case .proposal: return "◆"; case .measured: return "▲"; case .none: return "" } }
        var spoken: String { switch self { case .declared: return "Declared by you"; case .proposal: return "Coach's proposal, rules-based"; case .measured: return "Measured evidence"; case .none: return "" } }
    }
    let mark: Mark
    let title: String
    var trailing: String? = nil
    var trailingId = "onbGroupNote"
    @Environment(\.cyTheme) private var theme
    @Environment(\.dynamicTypeSize) private var dts

    static func tint(_ m: Mark, _ t: CxTheme) -> Color {
        switch m { case .declared: return t.textPrimary; case .proposal: return t.accent; case .measured: return t.success; case .none: return t.textSecondary }
    }
    var body: some View {
        let layout = dts.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 2)) : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 6))
        layout {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                if mark != .none {
                    Text(mark.glyph).font(CyDyn.f(11, .bold)).foregroundStyle(Self.tint(mark, theme)).accessibilityHidden(true)
                }
                Text(title.uppercased()).font(CyDyn.f(11.5, .semibold)).tracking(1.1).foregroundStyle(theme.textSecondary)
                    .accessibilityLabel(mark == .none ? title : "\(title). \(mark.spoken)")
                    .accessibilityAddTraits(.isHeader)
            }
            if !dts.isAccessibilitySize { Spacer(minLength: CySpace.s) }
            if let t = trailing {
                Text(t).font(CyDyn.f(12)).foregroundStyle(theme.textSecondary).fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier(trailingId)
            }
        }
    }
}

/// The seven day tiles of sheets Y4 / Y5: the day, then each session's symbol and minutes, or the moon and "rest".
/// Text is capped at the XL size so seven tiles always fit; VoiceOver reads the full day.
struct OnbWeekStrip: View {
    let kinds: [DayKind]
    let ride: Int
    let lift: Int
    var selected: Int? = nil
    var changed: Set<Int> = []
    var idPrefix = "onbDay"
    var containerId = "onbWeek"
    var onTap: ((Int) -> Void)? = nil
    @Environment(\.cyTheme) private var theme

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<7, id: \.self) { i in tile(i) }
        }
        .dynamicTypeSize(...DynamicTypeSize.xLarge)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(containerId)
    }
    private func kind(_ i: Int) -> DayKind { i < kinds.count ? kinds[i] : .rest }

    static func spoken(_ k: DayKind, ride: Int, lift: Int) -> String {
        switch k {
        case .ride: return "ride \(ride) minutes"
        case .lift: return "strength \(lift) minutes"
        case .both: return "strength \(lift) minutes and ride \(ride) minutes"
        case .rest: return "rest"
        }
    }
    @ViewBuilder private func tile(_ i: Int) -> some View {
        let k = kind(i)
        let on = selected == i
        let content = VStack(spacing: 4) {
            Text(WeeklyAvailability.dayNames[i]).font(.caption).foregroundStyle(theme.textSecondary).lineLimit(1).minimumScaleFactor(0.7)
            VStack(spacing: 2) {
                if k == .rest {
                    Image(systemName: "moon").font(.footnote).foregroundStyle(theme.textSecondary)
                    Text("rest").font(.caption2).foregroundStyle(theme.textSecondary).lineLimit(1).minimumScaleFactor(0.7)
                } else {
                    if k.lifts { session("dumbbell", lift, theme.strength) }
                    if k.rides { session("bicycle", ride, theme.endurance) }
                }
            }
            .frame(minHeight: 34)
            Circle().fill(changed.contains(i) ? theme.accent : Color.clear).frame(width: 4, height: 4)
        }
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, minHeight: 78)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(theme.surface))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .strokeBorder(on ? theme.textPrimary : (theme.id == .highContrast ? theme.border : Color.clear), lineWidth: on ? 2 : 1))
        .contentShape(Rectangle())
        let label = "\(WeeklyAvailability.longDayNames[i]), \(Self.spoken(k, ride: ride, lift: lift))\(changed.contains(i) ? ", changed by you" : "")"
        if let tap = onTap {
            Button { tap(i) } label: { content }
                .buttonStyle(.plain)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(label)
                .accessibilityAddTraits(on ? [.isButton, .isSelected] : [.isButton])
                .accessibilityIdentifier("\(idPrefix)-\(i)")
        } else {
            content
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(label)
                .accessibilityIdentifier("\(idPrefix)-\(i)")
        }
    }
    private func session(_ icon: String, _ minutes: Int, _ tint: Color) -> some View {
        HStack(spacing: 2) {
            Image(systemName: icon).font(.caption2.weight(.semibold)).foregroundStyle(tint)
            Text("\(minutes)").font(.caption.weight(.bold)).monospacedDigit().foregroundStyle(theme.textPrimary).lineLimit(1).minimumScaleFactor(0.6)
        }
    }
}

/// Pure wording shared by the week page and the blueprint.
enum OnbWeekText {
    /// "Road" for "Road cycling", "Gym" for "Gym training".
    static func short(_ title: String) -> String { title.split(separator: " ").first.map(String.init) ?? title }
    static func sessions(_ k: [DayKind]) -> Int { OnboardingWeek.rides(k) + OnboardingWeek.lifts(k) }
    /// "3 h 30 min"
    static func total(_ k: [DayKind], ride: Int, lift: Int) -> String { OnboardingWeek.durationText(OnboardingWeek.minutes(k, ride: ride, lift: lift)) }
    /// "Gym 1 h 30 min · Road 2 h · 2 rest days"
    static func bySport(_ k: [DayKind], ride: Int, lift: Int, mode: TrainingMode, endurance: String, strength: String) -> String {
        var parts: [String] = []
        let l = OnboardingWeek.lifts(k), r = OnboardingWeek.rides(k), rest = k.filter { $0 == .rest }.count
        if mode.includesLifting, l > 0 { parts.append("\(short(strength)) \(OnboardingWeek.durationText(l * lift))") }
        if mode.includesCycling, r > 0 { parts.append("\(short(endurance)) \(OnboardingWeek.durationText(r * ride))") }
        parts.append("\(rest) rest day\(rest == 1 ? "" : "s")")
        return parts.joined(separator: " · ")
    }
    /// The planner's existing feasibility result in the sheet's words (same checks; only the time prefix is dropped
    /// because the page shows the time on its own line).
    static func flag(_ f: OnboardingWeek.Feasibility, time: String) -> String {
        if f.blocking { return f.text }
        if f.ok { return f.text.contains("48 h") ? "Strength sessions at least 48 h apart · nothing to flag" : "Nothing to flag" }
        let prefix = "\(time) a week · "
        let rest = f.text.hasPrefix(prefix) ? String(f.text.dropFirst(prefix.count)) : f.text
        return rest.prefix(1).uppercased() + rest.dropFirst()
    }
}

// MARK: - Page 1 · About you (sheet Y1, page 1)

struct OnbAboutPage: View {
    @Binding var a: OnboardingAnswers
    /// The app's one units setting.
    @Binding var units: AppSettings.Units
    /// A weight already read from Apple Health with permission: offered, never applied silently.
    var healthWeight: (kg: Double, date: Date)? = nil
    @State private var weightText = ""
    @State private var showDOB = false
    @State private var dobDraft: Date? = nil
    private enum Field: Hashable { case name, weight }
    @FocusState private var focus: Field?
    @Environment(\.cyTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            nameRow
            separator
            dobRow
            if showDOB { dobPicker }
            separator
            weightRow
            healthOffer
            unitsBlock
        }
        .onAppear { if let w = a.weightKg { weightText = AthleteTypeEditor.weightString(w, units) } }
        .onChange(of: units) { _, u in if let w = a.weightKg { weightText = AthleteTypeEditor.weightString(w, u) } }
    }
    private var separator: some View { Rectangle().fill(theme.separator).frame(height: 1).accessibilityHidden(true) }

    private var nameRow: some View {
        HStack(alignment: .lastTextBaseline, spacing: CySpace.s) {
            TextField("Your first name", text: Binding(get: { a.name ?? "" }, set: { a.name = $0 }))
                .textContentType(.givenName).font(CyDyn.f(34, .bold)).foregroundStyle(theme.textPrimary)
                .focused($focus, equals: .name).submitLabel(.done).onSubmit { focus = nil }
                .toolbar { ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("Done") { focus = nil }.accessibilityIdentifier("keyboardDone") } }
                .accessibilityIdentifier("onbName")
            Text("first name").font(CyDyn.f(12)).foregroundStyle(theme.textSecondary).accessibilityHidden(true)
        }
        .frame(minHeight: 52)
        .padding(.bottom, 10)
    }

    private var dobRow: some View {
        Button { showDOB.toggle(); focus = nil } label: {
            HStack(spacing: CySpace.m) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Date of birth").font(CyDyn.f(16, .semibold)).foregroundStyle(theme.textPrimary)
                    Text("for heart-rate zones · optional").font(CyDyn.f(12)).foregroundStyle(theme.textSecondary)
                }
                Spacer(minLength: CySpace.s)
                Text(a.dateOfBirth.map { $0.formatted(date: .abbreviated, time: .omitted) } ?? "Select date")
                    .font(CyDyn.f(16, .semibold)).foregroundStyle(a.dateOfBirth == nil ? theme.accent : theme.textPrimary)
                    .multilineTextAlignment(.trailing)
            }
            .padding(.vertical, 10).frame(minHeight: 56).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Date of birth, \(a.dateOfBirth.map { $0.formatted(date: .abbreviated, time: .omitted) } ?? "not set"). For heart-rate zones, optional")
        .accessibilityIdentifier("onbDOB")
    }
    /// Nothing is saved until the wheel is moved (never a default date).
    private var dobPicker: some View {
        VStack(spacing: 0) {
            DatePicker("Date of birth", selection: Binding(get: { dobDraft ?? a.dateOfBirth ?? AthleteTypeEditor.dobNeutral }, set: { dobDraft = $0 }),
                       in: AthleteTypeEditor.dobRange, displayedComponents: .date)
                .datePickerStyle(.wheel).labelsHidden().frame(maxWidth: .infinity)
            HStack {
                if a.dateOfBirth != nil {
                    Button("Clear") { a.dateOfBirth = nil; dobDraft = nil; showDOB = false }
                        .font(CyDyn.f(15, .semibold)).foregroundStyle(theme.textSecondary)
                        .frame(minHeight: CyHit.min).buttonStyle(.plain)
                        .accessibilityIdentifier("onbDOBClear")
                }
                Spacer()
                Button("Done") {
                    if let d = dobDraft { a.dateOfBirth = d }
                    showDOB = false
                }
                .font(CyDyn.f(15, .semibold)).foregroundStyle(theme.textPrimary)
                .padding(.horizontal, 18).frame(minHeight: CyHit.min)
                .background(Capsule().fill(theme.surface2))
                .buttonStyle(.plain)
                .accessibilityIdentifier("onbDOBDone")
            }
            .padding(.bottom, 10)
        }
    }

    private var weightRow: some View {
        HStack(spacing: CySpace.m) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Weight").font(CyDyn.f(16, .semibold)).foregroundStyle(theme.textPrimary)
                Text("for loads and W/kg · optional").font(CyDyn.f(12)).foregroundStyle(theme.textSecondary)
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: CySpace.s)
            TextField("Not set", text: Binding(get: { weightText }, set: { v in
                weightText = v
                a.weightKg = AthleteTypeEditor.parseWeight(v, units)      // typed by the athlete only; a units change never rewrites it
            }))
            .keyboardType(.decimalPad).multilineTextAlignment(.trailing)
            .font(CyDyn.f(16, .semibold)).foregroundStyle(theme.textPrimary)
            .focused($focus, equals: .weight)
            .frame(width: 96)
            .accessibilityLabel("Weight in \(units == .imperial ? "pounds" : "kilograms")")
            .accessibilityIdentifier("onbWeight")
            Text(units == .imperial ? "lb" : "kg").font(CyDyn.f(16, .semibold)).foregroundStyle(theme.textPrimary)
                .accessibilityIdentifier("onbWeightUnit")
        }
        .padding(.vertical, 10).frame(minHeight: 56)
    }
    @ViewBuilder private var healthOffer: some View {
        if let h = healthWeight, a.weightKg == nil {
            HStack {
                Text("Apple Health has \(AthleteTypeEditor.weightString(h.kg, units)) \(units == .imperial ? "lb" : "kg") (\(h.date.formatted(date: .abbreviated, time: .omitted)))")
                    .font(CyDyn.f(12)).foregroundStyle(theme.textSecondary).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: CySpace.s)
                Button("Use it") { a.weightKg = h.kg; weightText = AthleteTypeEditor.weightString(h.kg, units) }
                    .font(CyDyn.f(13, .semibold)).foregroundStyle(theme.accent)
                    .frame(minHeight: CyHit.min).buttonStyle(.plain)
                    .accessibilityIdentifier("onbWeightUseHealth")
            }
        }
    }
    private var unitsBlock: some View {
        VStack(alignment: .leading, spacing: CySpace.s) {
            OnbGroupHeader(mark: .none, title: "Units")
            CyChoiceBar(options: [(AppSettings.Units.metric, "Metric"), (AppSettings.Units.imperial, "Imperial")], selection: $units)
                .accessibilityIdentifier("onbUnits")
        }
        .padding(.top, CySpace.s)
    }
}

// MARK: - Page 4 · Build your week (sheet Y4)

struct OnbWeekPage: View {
    @Binding var a: OnboardingAnswers
    let mode: TrainingMode
    /// The athlete's main sports, as named on page 2 ("Road cycling", "Gym training").
    let enduranceTitle: String
    let strengthTitle: String
    @State private var selected: Int? = nil
    @Environment(\.cyTheme) private var theme
    @Environment(\.dynamicTypeSize) private var dts

    private var proposed: [DayKind] {
        OnboardingWeek.propose(mode: mode, cyclingLevel: a.cyclingLevel ?? .intermediate, strengthLevel: a.strengthLevel, priority: a.priority ?? .balanced)
    }
    /// Always seven days.
    private var kinds: [DayKind] {
        if let w = a.week, w.count == 7 { return w }
        return proposed
    }
    private var ride: Int { a.rideMinutes ?? OnboardingWeek.defaultRideMinutes }
    private var lift: Int { a.liftMinutes ?? OnboardingWeek.defaultLiftMinutes }
    private var changed: Set<Int> {
        let k = kinds, p = proposed
        return Set((0..<7).filter { k[$0] != p[$0] })
    }

    var body: some View {
        let k = kinds
        VStack(alignment: .leading, spacing: CySpace.m) {
            OnbWeekStrip(kinds: k, ride: ride, lift: lift, selected: selected, changed: changed) { i in selected = selected == i ? nil : i }
            statusRow
            editor(k)
            totals(k)
            if mode.includesLifting { equipment }
        }
        .onAppear { if a.week == nil || a.week?.count != 7 { a.week = proposed } }
    }

    private var statusRow: some View {
        let n = changed.count
        return HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text("●").font(CyDyn.f(8)).foregroundStyle(theme.accent).accessibilityHidden(true)
            Text(n == 0 ? "Coach's proposal · rules-based" : "\(n) day\(n == 1 ? "" : "s") changed by you")
                .font(CyDyn.f(13)).foregroundStyle(theme.textSecondary).fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("onbWeekStatus")
            Spacer(minLength: CySpace.s)
            if n > 0 {
                Button("Restore proposal") { a.week = proposed }
                    .font(CyDyn.f(13, .semibold)).foregroundStyle(theme.accent)
                    .frame(minHeight: CyHit.min).contentShape(Rectangle()).buttonStyle(.plain)
                    .accessibilityIdentifier("onbRestoreProposal")
            }
        }
        .frame(minHeight: 24)
    }

    // --- the day editor: fixed minimum height so nothing below it moves when a day is opened

    private func editor(_ k: [DayKind]) -> some View {
        VStack(alignment: .leading, spacing: CySpace.s) {
            if let i = selected { dayEditor(i, k[i]) } else { editorHint }
        }
        .padding(CySpace.m)
        .frame(maxWidth: .infinity, minHeight: dts.isAccessibilitySize ? 0 : 158, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: CyRadius.m, style: .continuous).fill(theme.surface))
        .overlay(RoundedRectangle(cornerRadius: CyRadius.m, style: .continuous).strokeBorder(theme.cardStroke, lineWidth: theme.borderWidth))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("onbDayEditor")
    }
    @ViewBuilder private var editorHint: some View {
        Text("Tap a day to change it").font(CyDyn.f(16, .semibold)).foregroundStyle(theme.textPrimary)
            .accessibilityIdentifier("onbDayEditorHint")
        Text(mode == .hybrid
             ? "Choose up to two sessions for a day from your planned sports, or make it a rest day. The ride and strength lengths apply to the whole week. The proposal stays until you change it."
             : "Make a day a training day or a rest day. The session length applies to the whole week. The proposal stays until you change it.")
            .font(CyDyn.f(13)).foregroundStyle(theme.textSecondary).fixedSize(horizontal: false, vertical: true)
    }
    @ViewBuilder private func dayEditor(_ i: Int, _ kind: DayKind) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(WeeklyAvailability.longDayNames[i]).font(CyDyn.f(16, .semibold)).foregroundStyle(theme.textPrimary)
                .accessibilityAddTraits(.isHeader).accessibilityIdentifier("onbDayEditorDay")
            Spacer(minLength: CySpace.s)
            Text(kind == .rest ? "rest day" : kind == .both ? "2 sessions · strength first" : "1 session")
                .font(CyDyn.f(12)).foregroundStyle(theme.textSecondary)
                .accessibilityIdentifier("onbDayEditorCount")
        }
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 6) { chips(i, kind) }
            VStack(alignment: .leading, spacing: 6) { chips(i, kind) }
        }
        if kind == .rest {
            Text("No session. Rest days are part of the plan.").font(CyDyn.f(13)).foregroundStyle(theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            if kind.lifts {
                lengthRow(strengthTitle, note: "every strength session", icon: "dumbbell", tint: theme.strength, value: lift, range: 15...120, step: 5, id: "onbLift") { a.liftMinutes = $0 }
            }
            if kind.rides {
                lengthRow(enduranceTitle, note: "every ride", icon: "bicycle", tint: theme.endurance, value: ride, range: 20...300, step: 10, id: "onbRide") { a.rideMinutes = $0 }
            }
        }
    }
    @ViewBuilder private func chips(_ i: Int, _ kind: DayKind) -> some View {
        if mode.includesCycling {
            chip(OnbWeekText.short(enduranceTitle), icon: "bicycle", on: kind.rides, tint: theme.endurance, id: "onbDayRide") { toggle(ride: true, day: i) }
        }
        if mode.includesLifting {
            chip(OnbWeekText.short(strengthTitle), icon: "dumbbell", on: kind.lifts, tint: theme.strength, id: "onbDayLift") { toggle(ride: false, day: i) }
        }
        chip("Rest", icon: "moon", on: kind == .rest, tint: nil, id: "onbDayRest") { set(.rest, day: i) }
    }
    private func chip(_ title: String, icon: String, on: Bool, tint: Color?, id: String, action: @escaping () -> Void) -> some View {
        let fill: Color = on ? (tint.map { $0.opacity(0.18) } ?? theme.textPrimary) : theme.surface2
        let ink: Color = on ? (tint == nil ? theme.background : theme.textPrimary) : theme.textSecondary
        return Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon).font(CyDyn.f(12, .semibold)).foregroundStyle(on ? (tint ?? theme.background) : theme.textSecondary)
                Text(title).font(CyDyn.f(14, .semibold)).foregroundStyle(ink).lineLimit(1)
            }
            .padding(.horizontal, 12).frame(minHeight: 36)
            .background(Capsule().fill(fill))
            .overlay(Capsule().strokeBorder(on ? (tint ?? Color.clear) : Color.clear, lineWidth: 1.5))
            .frame(minHeight: CyHit.min).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(on ? .isSelected : [])
        .accessibilityIdentifier(id)
    }
    private func lengthRow(_ title: String, note: String, icon: String, tint: Color, value: Int, range: ClosedRange<Int>, step: Int, id: String, apply: @escaping (Int) -> Void) -> some View {
        HStack(spacing: CySpace.s) {
            Image(systemName: icon).font(CyDyn.f(13, .semibold)).foregroundStyle(tint).frame(width: 22).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 0) {
                Text(title).font(CyDyn.f(14, .semibold)).foregroundStyle(theme.textPrimary).lineLimit(2).minimumScaleFactor(0.8)
                Text(note).font(CyDyn.f(11)).foregroundStyle(theme.textSecondary)
            }
            Spacer(minLength: 4)
            stepButton("minus", "\(title) shorter", enabled: value - step >= range.lowerBound, id: "\(id)Minus") { apply(max(range.lowerBound, value - step)) }
            Text("\(value) min").font(CyDyn.f(15, .semibold)).monospacedDigit().foregroundStyle(theme.textPrimary)
                .frame(minWidth: 62).lineLimit(1)
                .accessibilityIdentifier("\(id)Minutes")
            stepButton("plus", "\(title) longer", enabled: value + step <= range.upperBound, id: "\(id)Plus") { apply(min(range.upperBound, value + step)) }
        }
        .frame(minHeight: CyHit.min)
    }
    private func stepButton(_ icon: String, _ label: String, enabled: Bool, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.footnote.weight(.bold)).foregroundStyle(enabled ? theme.textPrimary : theme.disabledText)
                .frame(width: 32, height: 32).background(Circle().fill(theme.surface2))
                .frame(width: CyHit.min, height: CyHit.min).contentShape(Rectangle())
        }
        .buttonStyle(.plain).disabled(!enabled)
        .accessibilityLabel(label).accessibilityIdentifier(id)
    }
    private func toggle(ride isRide: Bool, day i: Int) {
        let cur = kinds[i]
        var r = cur.rides, l = cur.lifts
        if isRide { r.toggle() } else { l.toggle() }
        set(r && l ? .both : r ? .ride : l ? .lift : .rest, day: i)
    }
    private func set(_ kind: DayKind, day i: Int) {
        var k = kinds
        guard k.indices.contains(i) else { return }
        k[i] = kind
        a.week = k
    }

    // --- totals and the planner's existing checks

    private func totals(_ k: [DayKind]) -> some View {
        let f = OnboardingWeek.feasibility(k, mode: mode, ride: ride, lift: lift, strengthLevel: a.strengthLevel)
        let time = OnbWeekText.total(k, ride: ride, lift: lift)
        let n = OnbWeekText.sessions(k)
        let layout = dts.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 0)) : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 6))
        return VStack(alignment: .leading, spacing: 2) {
            layout {
                Text(time).font(CyDyn.f(28, .bold)).foregroundStyle(theme.textPrimary).lineLimit(1).minimumScaleFactor(0.7)
                    .accessibilityIdentifier("onbWeekTotal")
                Text("a week · \(n) session\(n == 1 ? "" : "s")").font(CyDyn.f(14)).foregroundStyle(theme.textSecondary)
                    .accessibilityIdentifier("onbWeekSessions")
            }
            Text(OnbWeekText.bySport(k, ride: ride, lift: lift, mode: mode, endurance: enduranceTitle, strength: strengthTitle))
                .font(CyDyn.f(13)).foregroundStyle(theme.textSecondary).fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("onbWeekBySport")
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: f.ok ? "checkmark" : "exclamationmark.triangle").font(CyDyn.f(11, .bold)).accessibilityHidden(true)
                Text(OnbWeekText.flag(f, time: time)).font(CyDyn.f(13, .medium)).fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(f.ok ? theme.success : f.blocking ? theme.danger : theme.warning)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("onbFeasibility")
        }
    }

    /// Simulator run 17: at an accessibility text size four choices side by side broke "Bodyweight" in the middle of
    /// the word. From those sizes the same choice is drawn as rows of two (one a row at the three largest sizes), each
    /// row the app's own choice bar on the same answer. What is stored is unchanged.
    private var equipmentChoice: some View {
        let all = EquipmentPreset.allCases.map { ($0, $0.title) }
        let selection = Binding<EquipmentPreset>(get: { a.equipment ?? .notSure }, set: { a.equipment = $0 })
        let perRow = !dts.isAccessibilitySize ? all.count : (dts >= .accessibility3 ? 1 : 2)
        let rows: [[(EquipmentPreset, String)]] = stride(from: 0, to: all.count, by: perRow).map { i in Array(all[i..<min(i + perRow, all.count)]) }
        return VStack(spacing: 6) {
            ForEach(Array(rows.enumerated()), id: \.offset) { row in
                CyChoiceBar(options: row.element, selection: selection)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("onbEquipment")
    }

    private var equipment: some View {
        VStack(alignment: .leading, spacing: CySpace.s) {
            OnbGroupHeader(mark: .none, title: "Equipment", trailing: "sets which exercises are offered")
            equipmentChoice
            if (a.equipment ?? .notSure) == .notSure {
                Text("Not sure = bodyweight sessions until you confirm what you have.").font(CyDyn.f(12)).foregroundStyle(theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - Page 5 · Connect and calibrate (sheet Y1, page 5)

struct OnbConnectPage: View {
    @EnvironmentObject private var store: Store
    @Binding var a: OnboardingAnswers
    @Binding var ftpKnown: Bool
    @Binding var ftpText: String
    let mode: TrainingMode
    /// Called when the FTP field gives up the keyboard, so the onboarding screen can bring the page title back.
    var onEditingEnded: () -> Void = {}
    @FocusState private var ftpFocused: Bool
    @Environment(\.cyTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: CySpace.m) {
            if CycliftLab.isLab {
                Text("Cyclift Lab: sensors, Apple Health and location are switched off in this demo app, so nothing can be connected here.")
                    .font(CyDyn.f(13)).foregroundStyle(theme.warning).fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("onbLabDevices")
            }
            OnbGroupHeader(mark: .measured, title: "Connections", trailing: "all optional")
            if CycliftLab.isLab { labRows } else { DeviceCardList() }
            if mode.includesCycling { ftp }
            planChanges
        }
        .onChange(of: ftpFocused) { _, focused in if !focused { onEditingEnded() } }
    }

    /// Lab connects to nothing: the sheet's rows, each saying it is switched off. No state is imitated.
    private var labRows: some View {
        var rows: [(String, String, String)] = [("heart", "Apple Health", "Workouts, weight, resting HR, sleep"), ("applewatch", "Apple Watch", "Heart rate while you train")]
        if mode.includesCycling {
            rows.append(("rectangle.portrait", "Cyclift BikeComputer", "Live ride display"))
            rows.append(("bolt", "Bike sensors", "Power, heart rate, cadence"))
        }
        return VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { row in
                HStack(spacing: CySpace.m) {
                    Image(systemName: row.element.0).font(CyDyn.f(15)).foregroundStyle(theme.textSecondary).frame(width: 24).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(row.element.1).font(CyDyn.f(16, .semibold)).foregroundStyle(theme.textPrimary).fixedSize(horizontal: false, vertical: true)
                        Text(row.element.2).font(CyDyn.f(12)).foregroundStyle(theme.textSecondary).fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: CySpace.s)
                    Text("off in Lab").font(CyDyn.f(12)).foregroundStyle(theme.textSecondary)
                }
                // Simulator run 17: the page was about 45 pt taller than the iPhone 15 Pro screen, so after the FTP
                // keyboard it rested with its title under the rail. These rows are not controls; they are drawn tighter.
                .padding(.vertical, 5).frame(minHeight: 44)
                .overlay(alignment: .bottom) { Rectangle().fill(theme.separator).frame(height: 1).accessibilityHidden(true) }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("onbConnection-\(row.offset)")
            }
        }
    }

    /// The FTP question, same rule as before: "Don't know", or a typed number in 50–600 W. No watts are ever guessed.
    private var ftp: some View {
        VStack(alignment: .leading, spacing: CySpace.s) {
            OnbGroupHeader(mark: .declared, title: "FTP", trailing: "declared by you — not tested")
            CyChoiceBar(options: [(false, "Don't know"), (true, "I know it")], selection: Binding(get: { ftpKnown }, set: { v in
                ftpKnown = v
                if !v { a.ftpSource = .unknown; a.ftpWatts = nil; ftpText = "" } else { a.ftpSource = nil }
            }))
            .accessibilityIdentifier("onbFTP")
            if ftpKnown {
                HStack(spacing: CySpace.s) {
                    TextField("FTP", text: $ftpText).keyboardType(.numberPad)
                        .font(CyDyn.f(20, .bold)).foregroundStyle(theme.textPrimary)
                        .onChange(of: ftpText) { _, v in
                            // Entered only with a typed number in 50–600 W; otherwise the FTP stays Unknown
                            if let n = Int(v), (50...600).contains(n) { a.ftpWatts = n; a.ftpSource = .entered }
                            else { a.ftpWatts = nil; a.ftpSource = .unknown }
                        }
                        .focused($ftpFocused)
                        .toolbar { ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("Done") { ftpFocused = false }.accessibilityIdentifier("keyboardDone") } }
                        .accessibilityLabel("FTP in watts").accessibilityIdentifier("onbFTPWatts")
                    Text("watts").font(CyDyn.f(13)).foregroundStyle(theme.textSecondary)
                }
                .padding(.horizontal, 14).frame(minHeight: 48)
                .background(RoundedRectangle(cornerRadius: 13, style: .continuous).fill(theme.surface))
                if a.ftpWatts == nil {
                    Text("Type your FTP in watts (50–600). Until then it stays Unknown.").font(CyDyn.f(12)).foregroundStyle(theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                Text("Rides use heart rate and effort until you know it. No watts are ever guessed.").font(CyDyn.f(12)).foregroundStyle(theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// The Coach preference the app already has (Profile › Coach, "Adjust future sessions automatically"). On = the
    /// Coach's written rules may apply reductions; every increase still waits for approval either way.
    private var planChanges: some View {
        VStack(alignment: .leading, spacing: CySpace.s) {
            OnbGroupHeader(mark: .proposal, title: "Plan changes", trailing: "rules-based Coach")
            CyChoiceBar(options: [(false, "Always ask me"), (true, "Auto-apply reductions")], selection: $store.settings.autoAdapt)
                .accessibilityIdentifier("onbPlanChanges")
        }
    }
}

// MARK: - Page 6 · Athlete Evolution (sheet Y5, E1 — the new-athlete state only)

struct OnbEvolutionPage: View {
    /// "Intermediate rider · beginner lifter"
    let declared: String
    let rides: Int
    let lifts: Int
    @Environment(\.cyTheme) private var theme
    @Environment(\.dynamicTypeSize) private var dts

    var body: some View {
        VStack(alignment: .leading, spacing: CySpace.m) {
            VStack(spacing: 6) {
                SingularityPlaceholder(diameter: 64, detail: 1).frame(height: 76).accessibilityHidden(true)
                Text("Establishing your baseline").font(CyDyn.f(22, .bold)).foregroundStyle(theme.textPrimary)
                    .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("onbEvolutionState")
                Text("Stages come from recorded training only. Cyclift does not evaluate stages in this version.")
                    .font(CyDyn.f(14)).foregroundStyle(theme.textSecondary).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity)
            track
            group(.declared, "Declared by you", declared, "Sets your first plan. Never your stage.", id: "onbEvolutionDeclared")
            group(.measured, "Measured evidence", measuredTitle, measuredNote, id: "onbEvolutionMeasured")
            stageGroup
        }
    }
    private var measuredTitle: String {
        rides + lifts == 0 ? "Nothing recorded yet" : "\(rides) ride\(rides == 1 ? "" : "s") · \(lifts) strength session\(lifts == 1 ? "" : "s")"
    }
    private var measuredNote: String { rides + lifts == 0 ? "Recorded rides and strength sessions will count." : "Recorded in Cyclift." }

    /// The empty track: where the athlete is (no stage) and six unfilled places. Nothing is filled, named or positioned
    /// by a calculation; the stage names of the sheet are not shown because they are not approved.
    private var track: some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 3, style: .continuous).fill(theme.textPrimary).frame(width: 14, height: 14)
                Text("YOU").font(.caption2.weight(.bold)).foregroundStyle(theme.textPrimary)
            }
            .frame(width: 34)
            ForEach(0..<6, id: \.self) { i in
                VStack(spacing: 6) {
                    ZStack {
                        Rectangle().fill(theme.border).frame(height: 1)
                        Circle().fill(theme.background).frame(width: 12, height: 12)
                        Circle().strokeBorder(theme.textSecondary, lineWidth: 1.5).frame(width: 11, height: 11)
                    }
                    .frame(height: 14)
                    Text("G\(i)").font(.caption2.weight(.semibold)).foregroundStyle(theme.textSecondary)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .dynamicTypeSize(...DynamicTypeSize.xLarge)
        .padding(.bottom, CySpace.xs)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Evolution track. Establishing your baseline. No stage yet.")
        .accessibilityIdentifier("onbEvolutionTrack")
    }

    private func group(_ mark: OnbGroupHeader.Mark, _ title: String, _ value: String, _ note: String, id: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Rectangle().fill(theme.separator).frame(height: 1).padding(.bottom, CySpace.s).accessibilityHidden(true)
            OnbGroupHeader(mark: mark, title: title)
            Text(value).font(CyDyn.f(17, .semibold)).foregroundStyle(theme.textPrimary).fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier(id)
            Text(note).font(CyDyn.f(13)).foregroundStyle(theme.textSecondary).fixedSize(horizontal: false, vertical: true)
        }
    }
    private var stageGroup: some View {
        VStack(alignment: .leading, spacing: 3) {
            Rectangle().fill(theme.separator).frame(height: 1).padding(.bottom, CySpace.s).accessibilityHidden(true)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: "square").font(CyDyn.f(10, .bold)).foregroundStyle(theme.textSecondary).accessibilityHidden(true)
                Text("YOUR STAGE").font(CyDyn.f(11.5, .semibold)).tracking(1.1).foregroundStyle(theme.textSecondary).accessibilityAddTraits(.isHeader)
            }
            Text("None yet").font(CyDyn.f(17, .semibold)).foregroundStyle(theme.textPrimary)
                .accessibilityLabel("No stage yet. Cyclift does not evaluate stages in this version, and what you declare never sets one.")
                .accessibilityIdentifier("onbEvolutionStage")
            Text("Cyclift does not evaluate stages in this version, and what you declare never sets one. The rules are not final.")
                .font(CyDyn.f(13)).foregroundStyle(theme.textSecondary).fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Page 7 · Athletic Blueprint (sheet Y5, B1)

/// Everything the blueprint shows, worked out by the onboarding screen from the answers and the planner's dry run.
struct OnbBlueprintModel {
    struct SportMark: Identifiable { let id: String; let short: String; let icon: String; let role: String; let strength: Bool; let main: Bool; let interest: Bool }
    struct Cell: Identifiable { let id: String; let title: String; let value: String; let page: Int }
    var name: String
    /// "Intermediate rider · beginner lifter"
    var levels: String
    /// "Balanced" for a hybrid athlete, otherwise the sport; spoken as the full roster line.
    var lead: String
    var identity: String
    var sports: [SportMark]
    var goalTitle: String?
    var goalIsStrength: Bool
    var goalLine: String
    var kinds: [DayKind]
    var ride: Int
    var lift: Int
    /// "3 h 30 min · 5 sessions"
    var weekTotals: String
    var proposalLines: [String]
    var cells: [Cell]
    var measured: String
}

struct OnbBlueprintPage: View {
    let m: OnbBlueprintModel
    /// Opens the page a group came from; the onboarding screen then offers "Back to blueprint".
    let onEdit: (Int) -> Void
    @Environment(\.cyTheme) private var theme
    @Environment(\.dynamicTypeSize) private var dts

    var body: some View {
        VStack(alignment: .leading, spacing: CySpace.m) {
            header
            sportsRow
            goal
            proposal
            declared
            measured
        }
    }
    private func tappable<V: View>(_ id: String, page: Int, hint: String, @ViewBuilder _ content: () -> V) -> some View {
        content()
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture { onEdit(page) }
            .accessibilityElement(children: .contain)
            .accessibilityAction(named: Text(hint)) { onEdit(page) }
            .accessibilityIdentifier(id)
    }

    private var header: some View {
        let layout = dts.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 2)) : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: CySpace.s))
        return VStack(alignment: .leading, spacing: 4) {
            (Text("07").foregroundColor(theme.accent) + Text(" · ATHLETIC BLUEPRINT").foregroundColor(theme.textSecondary))
                .font(CyFont.overline).tracking(1.2)
                .accessibilityLabel("Page 7, Athletic Blueprint")
            layout {
                Text(m.name).font(.system(.largeTitle, design: .rounded).weight(.bold)).foregroundStyle(theme.textPrimary)
                    .lineLimit(2).minimumScaleFactor(0.7).accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("onbTitle")
                if !dts.isAccessibilitySize { Spacer(minLength: CySpace.s) }
                VStack(alignment: dts.isAccessibilitySize ? .leading : .trailing, spacing: 1) {
                    Text(m.levels).font(CyDyn.f(13)).foregroundStyle(theme.textSecondary)
                        .multilineTextAlignment(dts.isAccessibilitySize ? .leading : .trailing).fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("blueprintLevels")
                    Text(m.lead).font(CyDyn.f(13)).foregroundStyle(theme.textSecondary)
                        .accessibilityLabel(m.identity)
                        .accessibilityIdentifier("blueprintIdentity")
                }
            }
        }
    }

    private var sportsRow: some View {
        tappable("blueprintSports", page: 2, hint: "Change your sports") {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: CySpace.m) {
                    ForEach(m.sports) { s in sportMark(s) }
                }
            }
            .dynamicTypeSize(...DynamicTypeSize.xLarge)
        }
    }
    private func sportMark(_ s: OnbBlueprintModel.SportMark) -> some View {
        let tint = s.strength ? theme.strength : theme.endurance
        let size: CGFloat = s.main ? 44 : 34
        return VStack(spacing: 3) {
            ZStack {
                if s.main {
                    Circle().fill(tint)
                } else {
                    Circle().strokeBorder(tint, style: StrokeStyle(lineWidth: 1.2, dash: s.interest ? [3, 3] : []))
                }
                Image(systemName: s.icon).font(s.main ? Font.body.weight(.semibold) : Font.footnote.weight(.semibold))
                    .foregroundStyle(s.main ? theme.background : tint)
            }
            .frame(width: size, height: size)
            .frame(height: 44)
            Text(s.short).font(s.main ? Font.caption.weight(.bold) : Font.caption).foregroundStyle(s.main ? theme.textPrimary : theme.textSecondary).lineLimit(1)
            if !s.role.isEmpty { Text(s.role).font(.caption2).foregroundStyle(theme.textSecondary).lineLimit(1) }
        }
        .frame(minWidth: 48)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(s.short)\(s.role.isEmpty ? "" : ", \(s.role)")")
        .accessibilityIdentifier("blueprintSport-\(s.id)")
    }

    private var goal: some View {
        tappable("blueprintGoal", page: 3, hint: "Change your goals") {
            VStack(alignment: .leading, spacing: 2) {
                (Text("Main goal · ").foregroundColor(theme.textPrimary)
                 + Text(m.goalTitle ?? "not chosen").foregroundColor(m.goalTitle == nil ? theme.textSecondary : (m.goalIsStrength ? theme.strength : theme.endurance)))
                    .font(CyDyn.f(20, .bold)).fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("blueprintMainGoal")
                if !m.goalLine.isEmpty {
                    Text(m.goalLine).font(CyDyn.f(14)).foregroundStyle(theme.textSecondary).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var proposal: some View {
        tappable("blueprintProposal", page: 4, hint: "Change your week") {
            VStack(alignment: .leading, spacing: CySpace.s) {
                OnbGroupHeader(mark: .proposal, title: "Coach's proposal · week 1", trailing: m.weekTotals, trailingId: "blueprintWeekTotals")
                OnbWeekStrip(kinds: m.kinds, ride: m.ride, lift: m.lift, idPrefix: "blueprintDay", containerId: "blueprintWeek")
                ForEach(Array(m.proposalLines.enumerated()), id: \.offset) { pair in bullet(pair.element, tint: theme.accent, glyph: "◆") }
            }
        }
    }
    /// A proposal line: what comes before the first colon is the subject and is drawn stronger, as on the sheet.
    private func bullet(_ text: String, tint: Color, glyph: String) -> some View {
        let parts = text.split(separator: ":", maxSplits: 1).map(String.init)
        let head = parts.count == 2 && parts[0].count <= 24 ? parts[0] + ":" : ""
        let tail = head.isEmpty ? text : parts[1]
        return HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(glyph).font(CyDyn.f(10, .bold)).foregroundStyle(tint).accessibilityHidden(true)
            (Text(head).fontWeight(.semibold) + Text(tail))
                .font(CyDyn.f(14)).foregroundStyle(theme.textPrimary).fixedSize(horizontal: false, vertical: true)
        }
    }

    private var declared: some View {
        VStack(alignment: .leading, spacing: CySpace.s) {
            OnbGroupHeader(mark: .declared, title: "Declared by you", trailing: "tap to change")
            // Simulator run 17: this was a LazyVGrid, which does not build the rows below the visible part of the
            // page, so the last answers (plan changes) did not exist for VoiceOver or the checks until scrolled to.
            // At most seven short cells: they are all built.
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(cellRows.enumerated()), id: \.offset) { row in
                    HStack(alignment: .top, spacing: 8) {
                        ForEach(row.element) { c in cell(c) }
                        if row.element.count < cellsPerRow {
                            Color.clear.frame(maxWidth: .infinity).frame(height: 1).accessibilityHidden(true)
                        }
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("blueprintDeclared")
    }
    private var cellsPerRow: Int { dts.isAccessibilitySize ? 1 : 2 }
    private var cellRows: [[OnbBlueprintModel.Cell]] {
        let n = cellsPerRow
        return stride(from: 0, to: m.cells.count, by: n).map { i in Array(m.cells[i..<min(i + n, m.cells.count)]) }
    }
    private func cell(_ c: OnbBlueprintModel.Cell) -> some View {
        Button { onEdit(c.page) } label: {
            VStack(alignment: .leading, spacing: 1) {
                Text(c.title).font(CyDyn.f(12)).foregroundStyle(theme.textSecondary)
                Text(c.value).font(CyDyn.f(15, .semibold)).foregroundStyle(theme.textPrimary)
                    .multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, minHeight: 38, alignment: .leading).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // Simulator run 17: `.accessibilityElement(children: .ignore)` stood here and replaced the Button with a plain
        // element — no button trait, so "blueprintCell-goals" was not found as a button and VoiceOver could not
        // activate it. The Button itself now carries the label and the identifier.
        .accessibilityLabel("\(c.title): \(c.value)")
        .accessibilityHint("Opens its page; you return to the blueprint")
        .accessibilityIdentifier("blueprintCell-\(c.id)")
    }

    private var measured: some View {
        tappable("blueprintMeasured", page: 5, hint: "Change connections") {
            VStack(alignment: .leading, spacing: CySpace.s) {
                OnbGroupHeader(mark: .measured, title: "Measured evidence")
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("▲").font(CyDyn.f(10, .bold)).foregroundStyle(theme.success).accessibilityHidden(true)
                    Text(m.measured).font(CyDyn.f(14)).foregroundStyle(theme.textPrimary).fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("blueprintMeasuredLine")
                }
            }
        }
    }
}
