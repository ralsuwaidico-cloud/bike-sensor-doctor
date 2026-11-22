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
    /// The athlete's chosen sessions, each with its own activity and minutes. When given, the tiles are drawn from
    /// these (any sport); otherwise from `kinds` with the week-wide lengths.
    var sessions: [[ChosenSession]]? = nil
    /// Build your week (owner's refinement, 22 Nov 2026): the tile shows the weekday and the activity icon(s) only —
    /// no minutes (they are in the day editor and in the spoken label); a rest day shows the moon and "Rest".
    var iconsOnly = false
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
    static func spoken(_ day: [ChosenSession]) -> String {
        day.isEmpty ? "rest" : day.map { "\(AthleticRoster.activity($0.activity)?.title ?? "session") \($0.minutes) minutes" }.joined(separator: " and ")
    }
    static func tint(_ f: RosterFamily?, _ theme: CxTheme) -> Color {
        f == .strength ? theme.strength : f == .recovery ? theme.recovery : theme.endurance
    }
    @ViewBuilder private func tile(_ i: Int) -> some View {
        let k = kind(i)
        let on = selected == i
        let day: [ChosenSession]? = sessions.map { i < $0.count ? $0[i] : [] }
        let content = VStack(spacing: 4) {
            Text(WeeklyAvailability.dayNames[i]).font(.caption).foregroundStyle(theme.textSecondary).lineLimit(1).minimumScaleFactor(0.7)
            VStack(spacing: 2) {
                if let day, iconsOnly {
                    if day.isEmpty {
                        Image(systemName: "moon").font(.footnote).foregroundStyle(theme.textSecondary)
                        Text("Rest").font(.caption2).foregroundStyle(theme.textSecondary).lineLimit(1).minimumScaleFactor(0.7)
                    } else {
                        HStack(spacing: 3) {
                            ForEach(Array(day.enumerated()), id: \.offset) { item in
                                let x = AthleticRoster.activity(item.element.activity)
                                Image(systemName: x?.symbol ?? "figure.mixed.cardio")
                                    .font(.system(size: day.count > 1 ? 13 : 17, weight: .semibold))
                                    .foregroundStyle(Self.tint(x?.family, theme))
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                } else if let day {
                    if day.isEmpty {
                        Image(systemName: "moon").font(.footnote).foregroundStyle(theme.textSecondary)
                        Text("rest").font(.caption2).foregroundStyle(theme.textSecondary).lineLimit(1).minimumScaleFactor(0.7)
                    } else {
                        ForEach(Array(day.enumerated()), id: \.offset) { item in
                            let x = AthleticRoster.activity(item.element.activity)
                            session(x?.symbol ?? "figure.mixed.cardio", item.element.minutes, Self.tint(x?.family, theme))
                        }
                    }
                } else if k == .rest {
                    Image(systemName: "moon").font(.footnote).foregroundStyle(theme.textSecondary)
                    Text("rest").font(.caption2).foregroundStyle(theme.textSecondary).lineLimit(1).minimumScaleFactor(0.7)
                } else {
                    if k.lifts { session("dumbbell", lift, theme.strength) }
                    if k.rides { session("bicycle", ride, theme.endurance) }
                }
            }
            .frame(minHeight: iconsOnly ? 30 : 34)
            if !iconsOnly { Circle().fill(changed.contains(i) ? theme.accent : Color.clear).frame(width: 4, height: 4) }
        }
        .padding(.vertical, iconsOnly ? 7 : 8)
        .frame(maxWidth: .infinity, minHeight: iconsOnly ? 60 : 78)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(theme.surface))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .strokeBorder(on ? theme.textPrimary : (theme.id == .highContrast ? theme.border : Color.clear), lineWidth: on ? 2 : 1))
        .contentShape(Rectangle())
        let said = day.map { Self.spoken($0) } ?? Self.spoken(k, ride: ride, lift: lift)
        let label = "\(WeeklyAvailability.longDayNames[i]), \(said)\(changed.contains(i) ? ", changed by you" : "")"
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
    /// Why what is typed in Weight or Height is not accepted (nil when both are blank or valid). The page shows it.
    @Binding var entryIssue: String?
    @State private var weightText = ""
    @State private var heightText = ""          // centimetres (Metric)
    @State private var feetText = ""            // feet and inches (Imperial)
    @State private var inchText = ""
    @State private var showDOB = false
    private enum Field: Hashable { case name, weight, height, feet, inches }
    @FocusState private var focus: Field?
    @Environment(\.cyTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            nameRow
            separator
            dobRow
            separator
            weightRow
            healthOffer
            separator
            heightRow
            unitsRow
        }
        .onAppear { if let w = a.weightKg { weightText = AthleteTypeEditor.weightString(w, units) }; showHeight(units); noteIssue() }
        // a units change shows the SAME stored measurements in the other unit; it never rewrites what is stored
        .onChange(of: units) { _, u in if let w = a.weightKg { weightText = AthleteTypeEditor.weightString(w, u) }; showHeight(u); noteIssue() }
        .onChange(of: weightText) { _, _ in noteIssue() }
        .onChange(of: heightText) { _, _ in noteIssue() }
        .onChange(of: feetText) { _, _ in noteIssue() }
        .onChange(of: inchText) { _, _ in noteIssue() }
        .sheet(isPresented: $showDOB) {
            OnbBirthSheet(current: a.dateOfBirth) { a.dateOfBirth = $0 }
                .presentationDetents([.height(OnbBirthSheet.height)])
                .presentationDragIndicator(.hidden)
                .cyThemeRoot()
        }
    }
    private func noteIssue() {
        let imperial = units == .imperial
        entryIssue = BodyMeasure.weightIssue(weightText, imperial: imperial)
            ?? (imperial ? BodyMeasure.heightIssue(feet: feetText, inches: inchText) : BodyMeasure.heightIssue(cm: heightText))
    }
    private func showHeight(_ u: AppSettings.Units) {
        guard let cm = a.heightCm else { return }
        heightText = String(cm)
        let fi = BodyMeasure.feetInches(cm); feetText = String(fi.feet); inchText = String(fi.inches)
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
        Button { focus = nil; showDOB = true } label: {
            HStack(spacing: CySpace.m) {
                Text("Date of birth").font(CyDyn.f(16, .semibold)).foregroundStyle(theme.textPrimary)
                Spacer(minLength: CySpace.s)
                Text(a.dateOfBirth.map { $0.formatted(date: .abbreviated, time: .omitted) } ?? "Select date")
                    .font(CyDyn.f(16, .semibold)).foregroundStyle(a.dateOfBirth == nil ? theme.accent : theme.textPrimary)
                    .multilineTextAlignment(.trailing)
            }
            .padding(.vertical, 10).frame(minHeight: 56).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Date of birth, \(a.dateOfBirth.map { $0.formatted(date: .abbreviated, time: .omitted) } ?? "not set")")
        .accessibilityIdentifier("onbDOB")
    }
    private var weightRow: some View {
        HStack(spacing: CySpace.m) {
            Text("Weight").font(CyDyn.f(16, .semibold)).foregroundStyle(theme.textPrimary)
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
    /// Height: centimetres on Metric, feet and inches on Imperial. Stored in whole centimetres either way.
    private var heightRow: some View {
        HStack(spacing: CySpace.m) {
            Text("Height").font(CyDyn.f(16, .semibold)).foregroundStyle(theme.textPrimary)
            Spacer(minLength: CySpace.s)
            if units == .imperial {
                heightField($feetText, .feet, width: 40, label: "Height, feet", id: "onbHeightFeet") { a.heightCm = BodyMeasure.heightCm(feet: feetText, inches: inchText) }
                heightUnit("ft")
                heightField($inchText, .inches, width: 40, label: "Height, inches", id: "onbHeightInches") { a.heightCm = BodyMeasure.heightCm(feet: feetText, inches: inchText) }
                heightUnit("in")
            } else {
                heightField($heightText, .height, width: 96, label: "Height in centimetres", id: "onbHeight") { a.heightCm = BodyMeasure.parseHeightCm(heightText) }
                heightUnit("cm").accessibilityIdentifier("onbHeightUnit")
            }
        }
        .padding(.vertical, 10).frame(minHeight: 56)
    }
    private func heightField(_ text: Binding<String>, _ f: Field, width: CGFloat, label: String, id: String, typed: @escaping () -> Void) -> some View {
        TextField(f == .height ? "Not set" : "–", text: Binding(get: { text.wrappedValue }, set: { text.wrappedValue = $0; typed() }))
            .keyboardType(.numberPad).multilineTextAlignment(.trailing)
            .font(CyDyn.f(16, .semibold)).foregroundStyle(theme.textPrimary)
            .focused($focus, equals: f)
            .frame(width: width)
            .accessibilityLabel(label)
            .accessibilityIdentifier(id)
    }
    private func heightUnit(_ u: String) -> some View {
        Text(u).font(CyDyn.f(16, .semibold)).foregroundStyle(theme.textPrimary)
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
    /// "Units: Metric ▾" — a small native menu under the two measurements it applies to (owner decision 20 Nov 2026,
    /// 18:24; the full-width Metric / Imperial bar was rejected as too large). It changes the app's one units setting.
    private var unitsRow: some View {
        HStack {
            Spacer(minLength: 0)
            Menu {
                Picker("Units", selection: $units) {
                    Text("Metric").tag(AppSettings.Units.metric)
                    Text("Imperial").tag(AppSettings.Units.imperial)
                }
            } label: {
                HStack(spacing: 5) {
                    Text("Units:").foregroundStyle(theme.textSecondary)
                    Text(units == .imperial ? "Imperial" : "Metric").foregroundStyle(theme.textPrimary)
                    Image(systemName: "chevron.down").font(.caption2.weight(.bold)).foregroundStyle(theme.textSecondary)
                }
                .font(CyDyn.f(14, .semibold))
                .frame(minHeight: CyHit.min).contentShape(Rectangle())
            }
            .accessibilityLabel("Units, \(units == .imperial ? "Imperial" : "Metric")")
            .accessibilityIdentifier("onbUnits")
        }
    }
}

// MARK: - Date of birth: day, month and year, typed (owner decision 20 Nov 2026 — the date wheel is rejected)

/// A short sheet with three number fields. The year is typed directly; nothing scrolls. Done stores a date only when
/// it is a real date, not in the future and within the app's age limits; Cancel changes nothing.
struct OnbBirthSheet: View {
    static let height: CGFloat = 264
    let current: Date?
    let store: (Date?) -> Void
    @State private var day = ""
    @State private var month = ""
    @State private var year = ""
    private enum Part: Hashable { case day, month, year }
    @FocusState private var focus: Part?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.cyTheme) private var theme

    private var entry: BodyMeasure.BirthEntry { BodyMeasure.birthDate(day: day, month: month, year: year) }
    private var typedSomething: Bool { !day.isEmpty || !month.isEmpty || !year.isEmpty }
    /// Shown only once all three parts are there, so the sheet does not complain while the athlete is still typing.
    private var issue: String? {
        guard !day.isEmpty, !month.isEmpty, year.count >= 4, case .issue(let i) = entry else { return nil }
        return i.text
    }
    private var valid: Date? { if case .date(let d) = entry { return d }; return nil }

    var body: some View {
        VStack(alignment: .leading, spacing: CySpace.m) {
            HStack {
                Button("Cancel") { dismiss() }
                    .font(CyDyn.f(16)).foregroundStyle(theme.textSecondary).frame(minHeight: CyHit.min)
                    .accessibilityIdentifier("onbDOBCancel")
                Spacer()
                Text("Date of birth").font(CyDyn.f(16, .semibold)).foregroundStyle(theme.textPrimary).accessibilityAddTraits(.isHeader)
                Spacer()
                Button("Done") { if let d = valid { store(d); dismiss() } }
                    .font(CyDyn.f(16, .semibold)).foregroundStyle(valid == nil ? theme.textSecondary.opacity(0.5) : theme.accent)
                    .frame(minHeight: CyHit.min).disabled(valid == nil)
                    .accessibilityIdentifier("onbDOBDone")
            }
            HStack(spacing: CySpace.m) {
                part("Day", "DD", $day, .day, limit: 2, id: "onbDOBDay")
                part("Month", "MM", $month, .month, limit: 2, id: "onbDOBMonth")
                part("Year", "YYYY", $year, .year, limit: 4, id: "onbDOBYear").frame(maxWidth: .infinity)
            }
            Text(issue ?? " ").font(CyDyn.f(13)).foregroundStyle(theme.warning)
                .frame(maxWidth: .infinity, alignment: .leading).fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("onbDOBIssue").accessibilityHidden(issue == nil)
            if current != nil {
                Button("Clear date of birth") { store(nil); dismiss() }
                    .font(CyDyn.f(14, .semibold)).foregroundStyle(theme.textSecondary).frame(minHeight: CyHit.min)
                    .accessibilityIdentifier("onbDOBClear")
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, CySpace.l).padding(.top, CySpace.s)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(theme.surface.ignoresSafeArea())
        .onAppear {
            if let c = current { let p = BodyMeasure.birthParts(c); day = p.day; month = p.month; year = p.year }
            focus = .day
        }
    }

    private func part(_ title: String, _ hint: String, _ text: Binding<String>, _ p: Part, limit: Int, id: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased()).font(CyFont.overline).tracking(0.8).foregroundStyle(theme.textSecondary).accessibilityHidden(true)
            TextField(hint, text: Binding(get: { text.wrappedValue }, set: { v in
                let digits = String(v.filter(\.isNumber).prefix(limit))
                text.wrappedValue = digits
                // two digits of a day or month are complete: move on, so the date is typed in one run
                if digits.count == limit, focus == p { if p == .day { focus = .month } else if p == .month { focus = .year } }
            }))
            .keyboardType(.numberPad).multilineTextAlignment(.center)
            .font(CyDyn.f(22, .semibold)).foregroundStyle(theme.textPrimary)
            .focused($focus, equals: p)
            .frame(minWidth: p == .year ? 96 : 64, minHeight: 52)
            .background(RoundedRectangle(cornerRadius: CyRadius.m, style: .continuous).fill(theme.surface2))
            .accessibilityLabel(title)
            .accessibilityIdentifier(id)
        }
    }
}

// MARK: - Page 4 · Build your week
//
// Owner's approved direction, 21 Nov 2026 (21:18): the compact seven-day calendar, a day editor, weekly totals, the
// equipment selector and Continue, on one screen at the standard text size. A NEW athlete starts with seven rest days:
// nothing is preselected and nothing is inserted for them. Tapping a day opens its editor; the athlete picks an
// activity FROM THEIR OWN ROSTER (Screen 3 — never a fixed cycling/gym pair), sets that session's own length, may add
// a second session (any activity, the same one included), and CONFIRMS the day — only then does the tile change. Any day can go back to rest. A length set
// on one day never changes another day. What is built here is the athlete's chosen schedule, not a generated
// programme; sports without a planner are saved exactly as chosen and never replaced by cycling or strength.
// A returning athlete's saved schedule is shown as they left it (see OnboardingFlow.storedSchedule).

struct OnbWeekPage: View {
    @Binding var a: OnboardingAnswers
    /// The athlete's roster, in roster order.
    let roster: [RosterActivity]
    @State private var selected: Int? = nil
    /// The open day as being edited. Written to the week only by Confirm.
    @State private var draft: [ChosenSession] = []
    @State private var editingEquipment = false
    @Environment(\.cyTheme) private var theme
    @Environment(\.dynamicTypeSize) private var dts

    private var week: ChosenWeek.Week { ChosenWeek.normalised(a.schedule) }

    var body: some View {
        let w = week
        VStack(alignment: .leading, spacing: 8) {
            OnbWeekStrip(kinds: [], ride: 0, lift: 0, sessions: w, iconsOnly: true, selected: selected) { i in open(i, w) }
            editor(w)
            summary(w)
            // always shown when a strength session is in the confirmed week — also beside the open editor (owner, 22 Nov:
            // required functionality is not hidden; the page is made compact enough for both instead)
            if showsEquipment(w) { equipment }
        }
    }

    private func open(_ i: Int, _ w: ChosenWeek.Week) {
        if selected == i { selected = nil; return }
        selected = i
        draft = w[i]
    }
    private func confirm(_ i: Int) {
        var w = week
        guard w.indices.contains(i) else { return }
        w[i] = draft
        w = ChosenWeek.normalised(w)
        a.schedule = w
        // the older week fields stay in step for the pages that still read them (plannable sessions only)
        a.week = ChosenWeek.kinds(w)
        if let t = ChosenWeek.typicalMinutes(w, engine: .cycling) { a.rideMinutes = t }
        if let t = ChosenWeek.typicalMinutes(w, engine: .strength) { a.liftMinutes = t }
        selected = nil
    }

    // --- the day editor

    private func editor(_ w: ChosenWeek.Week) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if let i = selected, w.indices.contains(i) { dayEditor(i, saved: w[i]) }
            else {
                Text("Tap a day to choose its training").font(CyDyn.f(14, .semibold)).foregroundStyle(theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("onbDayEditorHint")
            }
        }
        .padding(.horizontal, CySpace.m).padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: CyRadius.m, style: .continuous).fill(theme.surface))
        .overlay(RoundedRectangle(cornerRadius: CyRadius.m, style: .continuous).strokeBorder(theme.cardStroke, lineWidth: theme.borderWidth))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("onbDayEditor")
    }
    /// "Road" for "Road cycling" when no other roster activity starts with the same word.
    private func chipTitle(_ x: RosterActivity) -> String {
        let short = OnbWeekText.short(x.title)
        guard roster.filter({ OnbWeekText.short($0.title) == short }).count > 1 else { return short }
        // "Road cycling" beside "Road running": the sport's own name, when only one roster activity has it (check 35:
        // full names pushed the chips onto two rows)
        return roster.filter { $0.family == x.family }.count == 1 ? x.family.title : x.title
    }
    @ViewBuilder private func dayEditor(_ i: Int, saved: [ChosenSession]) -> some View {
        let day = WeeklyAvailability.longDayNames[i]
        let changed = draft != saved
        // header: the day; whether what is shown is confirmed or not yet; and Rest, always in the same place
        HStack(spacing: 6) {
            // each is its own accessibility element with its own identifier (check 38: the day name could not be
            // found by its identifier once it shared the row with the tag; cause not established)
            Text(day).font(CyDyn.f(15, .semibold)).foregroundStyle(theme.textPrimary).lineLimit(1)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(day).accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("onbDayEditorDay")
            Text(changed ? "Not confirmed yet" : "Confirmed")
                .font(CyDyn.f(11, .semibold)).foregroundStyle(changed ? theme.warning : theme.textSecondary)
                .lineLimit(1).minimumScaleFactor(0.8)
                .padding(.horizontal, 7).padding(.vertical, 2)
                .background(Capsule().fill((changed ? theme.warning : theme.textSecondary).opacity(0.14)))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(changed ? "Not confirmed yet" : "Confirmed")
                .accessibilityIdentifier("onbDayEditorState")
            Spacer(minLength: 4)
            chip("Rest", spoken: "Rest", icon: "moon", on: draft.isEmpty, tint: nil, id: "onbDayRest") { draft = [] }
        }
        FlowLayout(spacing: 6) {
            ForEach(roster) { x in
                // a tap ADDS a session of that activity — any two may share a day, the same one twice included; nothing
                // already chosen is replaced; a third session is not offered. Each session is removed on its own row.
                let on = draft.contains { $0.activity == x.id }
                let full = draft.count >= ChosenWeek.maxPerDay
                chip(chipTitle(x), spoken: "Add \(x.title)", icon: x.symbol, on: on, tint: OnbWeekStrip.tint(x.family, theme), id: "onbAct-\(x.id)") {
                    draft = ChosenWeek.adding(x.id, to: draft)
                }
                .disabled(full).opacity(full && !on ? 0.4 : 1)
            }
        }
        ForEach(Array(draft.enumerated()), id: \.offset) { item in
            if let x = AthleticRoster.activity(item.element.activity) { lengthRow(item.offset, x, item.element.minutes) }
        }
        Button { confirm(i) } label: {
            Text(draft.isEmpty && !saved.isEmpty ? "Make \(day) a rest day" : "Confirm \(day)")
                .font(CyDyn.f(14, .semibold)).foregroundStyle(changed ? theme.background : theme.disabledText)
                .frame(maxWidth: .infinity, minHeight: 34)
                .background(Capsule().fill(changed ? theme.textPrimary : theme.surface2))
                .frame(minHeight: CyHit.min).contentShape(Rectangle())
        }
        .buttonStyle(.plain).disabled(!changed)
        .accessibilityIdentifier("onbDayConfirm")
    }
    private func chip(_ title: String, spoken: String, icon: String, on: Bool, tint: Color?, id: String, action: @escaping () -> Void) -> some View {
        let fill: Color = on ? (tint.map { $0.opacity(0.18) } ?? theme.textPrimary) : theme.surface2
        let ink: Color = on ? (tint == nil ? theme.background : theme.textPrimary) : theme.textSecondary
        return Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon).font(CyDyn.f(12, .semibold)).foregroundStyle(on ? (tint ?? theme.background) : theme.textSecondary)
                Text(title).font(CyDyn.f(14, .semibold)).foregroundStyle(ink).lineLimit(1)
            }
            .padding(.horizontal, 10).frame(minHeight: 32)
            .background(Capsule().fill(fill))
            .overlay(Capsule().strokeBorder(on ? (tint ?? Color.clear) : Color.clear, lineWidth: 1.5))
            .frame(minHeight: CyHit.min).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(spoken)
        .accessibilityAddTraits(on ? .isSelected : [])
        .accessibilityIdentifier(id)
    }
    /// One session: its own length, and its own remove button. It belongs to this day only.
    private func lengthRow(_ at: Int, _ x: RosterActivity, _ value: Int) -> some View {
        let range = ChosenWeek.range(x.id), step = ChosenWeek.step(x.id)
        func set(_ m: Int) { if draft.indices.contains(at) { draft[at].minutes = m } }
        return HStack(spacing: 6) {
            Image(systemName: x.symbol).font(CyDyn.f(13, .semibold)).foregroundStyle(OnbWeekStrip.tint(x.family, theme)).frame(width: 22).accessibilityHidden(true)
            Text(x.title).font(CyDyn.f(14, .semibold)).foregroundStyle(theme.textPrimary).lineLimit(2).minimumScaleFactor(0.8)
                .accessibilityIdentifier("onbSession-\(at)")
            Spacer(minLength: 2)
            stepButton("minus", "\(x.title) shorter", enabled: value - step >= range.lowerBound, id: "onbLen-\(at)Minus") { set(max(range.lowerBound, value - step)) }
            Text("\(value) min").font(CyDyn.f(15, .semibold)).monospacedDigit().foregroundStyle(theme.textPrimary)
                .frame(minWidth: 58).lineLimit(1)
                .accessibilityIdentifier("onbLen-\(at)Minutes")
            stepButton("plus", "\(x.title) longer", enabled: value + step <= range.upperBound, id: "onbLen-\(at)Plus") { set(min(range.upperBound, value + step)) }
            Button { if draft.indices.contains(at) { draft.remove(at: at) } } label: {
                Image(systemName: "xmark").font(.caption.weight(.bold)).foregroundStyle(theme.textSecondary)
                    .frame(width: 30, height: CyHit.min).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove \(x.title)").accessibilityIdentifier("onbSessionRemove-\(at)")
        }
        .frame(minHeight: CyHit.min)
    }
    private func stepButton(_ icon: String, _ label: String, enabled: Bool, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.footnote.weight(.bold)).foregroundStyle(enabled ? theme.textPrimary : theme.disabledText)
                .frame(width: 30, height: 30).background(Circle().fill(theme.surface2))
                .frame(width: CyHit.min, height: CyHit.min).contentShape(Rectangle())
        }
        .buttonStyle(.plain).disabled(!enabled)
        .accessibilityLabel(label).accessibilityIdentifier(id)
    }

    // --- the weekly summary: confirmed days only, so it changes the moment a day is confirmed

    private func summary(_ w: ChosenWeek.Week) -> some View {
        let t = ChosenWeek.totals(w)
        let f = ChosenWeek.feasibility(w, strengthLevel: a.strengthLevel)
        let time = t.minutes == 0 ? "0 min" : OnboardingWeek.durationText(t.minutes)      // check 35: an empty week read "0 h"
        let sports = ChosenWeek.bySport(w).map { "\($0.sport) \(OnboardingWeek.durationText($0.minutes))" }.joined(separator: " · ")
        let layout = dts.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 0)) : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 6))
        return VStack(alignment: .leading, spacing: 1) {
            layout {
                Text(time).font(CyDyn.f(26, .bold)).foregroundStyle(theme.textPrimary).lineLimit(1).minimumScaleFactor(0.7)
                    .accessibilityIdentifier("onbWeekTotal")
                Text("a week").font(CyDyn.f(14)).foregroundStyle(theme.textSecondary)
            }
            Text("\(t.sessions) session\(t.sessions == 1 ? "" : "s") · \(t.trainingDays) training day\(t.trainingDays == 1 ? "" : "s") · \(t.restDays) rest day\(t.restDays == 1 ? "" : "s")")
                .font(CyDyn.f(13)).foregroundStyle(theme.textSecondary).fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("onbWeekCounts")
            if !sports.isEmpty {
                Text(sports).font(CyDyn.f(13)).foregroundStyle(theme.textSecondary).fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("onbWeekBySport")
            }
            if !f.ok, t.sessions > 0 {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Image(systemName: "exclamationmark.triangle").font(CyDyn.f(11, .bold)).accessibilityHidden(true)
                    Text(OnbWeekText.flag(f, time: time)).font(CyDyn.f(13, .medium)).fixedSize(horizontal: false, vertical: true)
                }
                .foregroundStyle(f.blocking ? theme.danger : theme.warning)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("onbFeasibility")
            }
        }
    }

    // --- equipment: only when a strength session the planner builds is in the week (or being added)

    private func showsEquipment(_ w: ChosenWeek.Week) -> Bool {
        w.joined().contains { ChosenWeek.engine($0.activity) == .strength }
    }
    /// Gym | Home | Bodyweight | Custom (owner decision 22 Nov 2026, 13:34): training environments, not "Not sure".
    /// Simulator run 17: at an accessibility text size four choices side by side broke "Bodyweight" in the middle of
    /// the word. From those sizes the same choice is drawn as rows of two (one a row at the three largest sizes).
    private var equipmentChoice: some View {
        let all: [(EquipmentEnvironment?, String)] = EquipmentEnvironment.allCases.map { (Optional($0), $0.title) }
        let selection = Binding<EquipmentEnvironment?>(get: { a.environment }, set: { a.environment = $0 })
        let perRow = !dts.isAccessibilitySize ? all.count : (dts >= .accessibility3 ? 1 : 2)
        let rows: [[(EquipmentEnvironment?, String)]] = stride(from: 0, to: all.count, by: perRow).map { i in Array(all[i..<min(i + perRow, all.count)]) }
        return VStack(spacing: 6) {
            ForEach(Array(rows.enumerated()), id: \.offset) { row in
                CyChoiceBar(options: row.element, selection: selection)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("onbEquipment")
    }
    /// "3 items · Edit" — the compact way into the chosen environment's checklist (a bottom sheet; the page stays as it is).
    private var equipmentEdit: some View {
        let n = a.environment.map { $0.selection(in: a.equipmentSets).count }
        let words = n.map { $0 == 0 ? "No equipment" : $0 == 1 ? "1 item" : "\($0) items" } ?? "Choose where you train"
        return Button { editingEquipment = true } label: {
            HStack(spacing: 4) {
                Text(n == nil ? words : "\(words) · Edit").font(CyDyn.f(12, .semibold)).foregroundStyle(n == nil ? theme.warning : theme.accent).lineLimit(1)
                if n != nil { Image(systemName: "chevron.right").font(.system(size: 9, weight: .bold)).foregroundStyle(theme.accent).accessibilityHidden(true) }
            }
            .frame(minHeight: 22).contentShape(Rectangle().inset(by: -10))
        }
        .buttonStyle(.plain).disabled(a.environment == nil)
        .accessibilityLabel(n == nil ? words : "\(words). Edit equipment")
        .accessibilityIdentifier("onbEquipmentEdit")
    }
    private var equipment: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline) {
                Text("EQUIPMENT").font(CyDyn.f(11.5, .semibold)).tracking(1.1).foregroundStyle(theme.textSecondary).accessibilityAddTraits(.isHeader)
                Spacer(minLength: CySpace.s)
                equipmentEdit
            }
            equipmentChoice
        }
        .sheet(isPresented: $editingEquipment) {
            if let env = a.environment {
                OnbEquipmentSheet(environment: env, ticked: Binding(
                    get: { env.selection(in: a.equipmentSets) },
                    set: { new in var sets = a.equipmentSets ?? [:]; sets[env.rawValue] = EquipmentCatalogue.ordered(new); a.equipmentSets = sets }))
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
        }
    }
}

// MARK: - Equipment checklist (bottom sheet)
//
// One environment's own checklist: its usual items first, each a tick box; "All equipment" opens the whole catalogue
// with search (Custom starts there). Ticks are kept per environment. The line under the title is the existing strength
// planner's own count of exercises it can offer with what is ticked — nothing estimated; items the planner does not
// use yet say so, so storing them never looks like it changes training.

struct OnbEquipmentSheet: View {
    let environment: EquipmentEnvironment
    @Binding var ticked: [String]
    @State private var showAll = false
    @State private var query = ""
    @Environment(\.dismiss) private var dismiss
    @Environment(\.cyTheme) private var theme

    private var whole: Bool { environment == .custom || showAll }
    private var shown: [EquipmentItem] {
        if whole { return EquipmentCatalogue.search(query) }
        // the environment's usual items, then anything else the athlete has ticked for it (never dropped from view)
        let usual = environment.checklist
        let extra = ticked.filter { !usual.contains($0) }
        return (usual + extra).compactMap { EquipmentCatalogue.item($0) }
    }
    private func toggle(_ id: String) {
        ticked = ticked.contains(id) ? ticked.filter { $0 != id } : ticked + [id]
    }

    var body: some View {
        let count = EquipmentCatalogue.eligibleExercises(ticked)
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(environment.title) equipment").font(CyDyn.f(18, .bold)).foregroundStyle(theme.textPrimary)
                    .accessibilityAddTraits(.isHeader).accessibilityIdentifier("equipTitle")
                Spacer()
                Button("Done") { dismiss() }
                    .font(CyDyn.f(16, .semibold)).foregroundStyle(theme.accent).frame(minWidth: CyHit.min, minHeight: CyHit.min)
                    .accessibilityIdentifier("equipDone")
            }
            // plain words first (owner, 22 Nov 2026, 14:36); the exact count stays as secondary information
            Text("We’ll choose exercises based on the equipment you have.")
                .font(CyDyn.f(14)).foregroundStyle(theme.textPrimary).fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("equipIntro")
            if let hint = Self.hint(environment) {
                Text(hint).font(CyDyn.f(13)).foregroundStyle(theme.textSecondary).fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("equipHint")
            }
            Text("\(count.can) of \(count.of) strength exercises available")
                .font(CyDyn.f(12)).foregroundStyle(theme.textSecondary).fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("equipEffect")
            if whole {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").font(.footnote).foregroundStyle(theme.textSecondary).accessibilityHidden(true)
                    TextField("Search equipment", text: $query)
                        .font(CyDyn.f(15)).foregroundStyle(theme.textPrimary)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .accessibilityIdentifier("equipSearch")
                }
                .padding(.horizontal, 10).frame(minHeight: 38)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(theme.surface2))
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(shown) { item in row(item) }
                    if shown.isEmpty {
                        Text("Nothing in the catalogue matches.").font(CyDyn.f(14)).foregroundStyle(theme.textSecondary).padding(.vertical, 12)
                    }
                    if shown.contains(where: { !$0.planner }) {
                        // said once, not on every row
                        Label("Saved to your profile. Not used to choose exercises yet.", systemImage: "bookmark")
                            .font(CyDyn.f(12)).foregroundStyle(theme.textSecondary).fixedSize(horizontal: false, vertical: true)
                            .padding(.vertical, 8)
                            .accessibilityIdentifier("equipSavedOnlyNote")
                    }
                    if environment != .custom {
                        Button { showAll.toggle(); query = "" } label: {
                            Text(showAll ? "Show the \(environment.title) list" : "All equipment").font(CyDyn.f(14, .semibold)).foregroundStyle(theme.accent)
                                .frame(maxWidth: .infinity, minHeight: CyHit.min, alignment: .leading).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain).accessibilityIdentifier("equipShowAll")
                    }
                }
            }
        }
        .padding(.horizontal, CySpace.l).padding(.top, CySpace.l)
        .background(theme.background.ignoresSafeArea())
        // a container: its own identifier must not replace its children's (check 40: without this the title, tick
        // boxes and Done could not be found by theirs)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("equipSheet")
    }
    /// One short line per environment: what its starting list is.
    static func hint(_ e: EquipmentEnvironment) -> String? {
        switch e {
        case .gym: return "A suggested starting list. Untick anything your gym doesn’t have."
        case .home: return "A suggested starting list. Tick what you have at home."
        case .bodyweight: return "No equipment is needed. Tick anything you also have."
        case .custom: return nil
        }
    }
    private func row(_ item: EquipmentItem) -> some View {
        let on = ticked.contains(item.id)
        return Button { toggle(item.id) } label: {
            HStack(spacing: 10) {
                Image(systemName: on ? "checkmark.square.fill" : "square")
                    .font(.system(size: 20, weight: .medium)).foregroundStyle(on ? theme.accent : theme.textSecondary).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.title).font(CyDyn.f(15, .medium)).foregroundStyle(theme.textPrimary).fixedSize(horizontal: false, vertical: true)
                    if whole { Text(item.group.title).font(CyDyn.f(11.5)).foregroundStyle(theme.textSecondary) }
                }
                Spacer(minLength: 0)
                if !item.planner { Image(systemName: "bookmark").font(.system(size: 12, weight: .medium)).foregroundStyle(theme.textTertiary).accessibilityHidden(true) }
            }
            .frame(maxWidth: .infinity, minHeight: CyHit.min, alignment: .leading).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(item.planner ? item.title : "\(item.title), saved only")
        .accessibilityValue(on ? "ticked" : "not ticked")
        .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
        .accessibilityIdentifier("equip-\(item.id)")
    }
}

// MARK: - Page 5 · Connect your devices (sheet Y1, page 5 — owner's approved direction, 22 Nov 2026, 15:55)
//
// The compact connection rows of the sheet: five integrations in a fixed order with truthful statuses, an action only
// where it does something real. No FTP and no Plan changes choice. Lab consults no service and offers no action.

struct OnbConnectPage: View {
    @Environment(\.cyTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if CycliftLab.isLab {
                Text("Cyclift Lab: connections are switched off in this demo app.")
                    .font(CyDyn.f(13)).foregroundStyle(theme.warning).fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("onbLabDevices")
            }
            OnbGroupHeader(mark: .measured, title: "Connections", trailing: "all optional")
            if CycliftLab.isLab { OnbConnectionRows(rows: OnbConnections.rows(live: nil)) { _ in } } else { OnbLiveConnections() }
            // No Plan changes choice here (owner, 22 Nov 2026, 16:34): it belongs to Profile › App preferences › Coach.
        }
    }
}

/// The rows themselves: icon, name and what it provides, the status in a word and a symbol, and the action if there is one.
struct OnbConnectionRows: View {
    let rows: [OnbConnection]
    let perform: (OnbConnection.Action) -> Void
    @Environment(\.cyTheme) private var theme

    var body: some View {
        VStack(spacing: 0) {
            ForEach(rows) { r in
                HStack(spacing: 10) {
                    Image(systemName: r.icon).font(CyDyn.f(15)).foregroundStyle(theme.textSecondary).frame(width: 24).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(r.name).font(CyDyn.f(16, .semibold)).foregroundStyle(theme.textPrimary).fixedSize(horizontal: false, vertical: true)
                        Text(r.detail).font(CyDyn.f(12)).foregroundStyle(theme.textSecondary).fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 6)
                    HStack(spacing: 4) {
                        Image(systemName: r.status.symbol).font(.system(size: 11, weight: .semibold)).accessibilityHidden(true)
                        Text(r.note ?? r.status.word).font(CyDyn.f(12, .medium)).lineLimit(2).multilineTextAlignment(.trailing)
                    }
                    .foregroundStyle(r.status == .connected ? theme.success : theme.textSecondary)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(r.note ?? r.status.word)
                    .accessibilityIdentifier("onbConnectionStatus-\(r.id)")
                    if let a = r.action {
                        Button { perform(a) } label: {
                            Text(a.title).font(CyDyn.f(13, .semibold)).foregroundStyle(theme.textPrimary)
                                .padding(.horizontal, 12).frame(minHeight: 30)
                                .overlay(Capsule().strokeBorder(theme.cardStroke, lineWidth: 1))
                                .frame(minHeight: CyHit.min).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(a.title) \(r.name)").accessibilityIdentifier("onbConnectionAction-\(r.id)")
                    }
                }
                .padding(.vertical, 4).frame(minHeight: 48)
                .overlay(alignment: .bottom) { Rectangle().fill(theme.separator).frame(height: 1).accessibilityHidden(true) }
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("onbConnection-\(r.id)")
            }
        }
    }
}

/// The redesigned main app only (never built into the view tree in Lab): statuses read from the existing connection
/// services, and each action is the existing one — Apple Health's own permission request, the existing Apple Watch and
/// Apple Health settings screens, and the existing Bluetooth pairing screen. A permission is asked for only when the
/// athlete presses Connect.
struct OnbLiveConnections: View {
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var device: DeviceLink
    @EnvironmentObject private var watch: WatchLink
    @EnvironmentObject private var health: HealthAccess
    @EnvironmentObject private var hub: SensorHub
    @EnvironmentObject private var location: LocationService
    private enum Sheet: String, Identifiable { case pair, health, watch; var id: String { rawValue } }
    @State private var sheet: Sheet? = nil
    @State private var healthNote: String? = nil
    @Environment(\.cyTheme) private var theme

    private var live: OnbConnections.Live {
        OnbConnections.Live(healthAvailable: health.available,
                            healthConnected: hub.deviceStates[DeviceCards.healthId]?.state.isConnectedOrBetter ?? false,
                            watchConnected: hub.deviceStates[DeviceCards.watchId]?.state.isConnectedOrBetter ?? false,
                            bluetoothPaired: hub.ble.paired.count)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            OnbConnectionRows(rows: OnbConnections.rows(live: live)) { action in
                switch action {
                case .connectHealth:
                    store.settings.appleHealthWanted = true
                    health.request { ok in healthNote = ok ? nil : "Not allowed. Change it in iOS Settings › Health." }
                case .manageHealth: sheet = .health
                case .manageWatch: sheet = .watch
                case .pairBluetooth: sheet = .pair
                }
            }
            if let n = healthNote { Text(n).font(CyDyn.f(12)).foregroundStyle(theme.warning).accessibilityIdentifier("onbHealthNote") }
        }
        .onAppear { hub.refresh(device: device, watch: watch, location: location, powerVerified: PowerTrust.meterVerified) }
        .sheet(item: $sheet, onDismiss: { hub.refresh(device: device, watch: watch, location: location, powerVerified: PowerTrust.meterVerified) }) { which in
            NavigationStack {
                switch which {
                case .pair: BLEPairView(ble: hub.ble).navigationTitle("Add a sensor").navigationBarTitleDisplayMode(.inline)
                case .health: HealthConnectionDetail()
                case .watch: WatchConnectionDetail()
                }
            }
        }
    }
}

// MARK: - Page 6 · Athlete Evolution (sheet Y5, E1 — owner's approved direction, 22 Nov 2026, 17:33)
//
// The sheet's layout: orbital hero, title, the six-stage rail, what was declared, the measured evidence, the athlete's
// stage, "See my blueprint". The rail is interactive: tapping G0–G5 shows that stage's orbital form, its provisional
// name and a short description, and highlights it. That is EXPLORING — a local, unsaved state of this view. The
// athlete's own standing is drawn separately and is "Starting stage not yet assessed" until an assessment policy is
// approved; tapping G5 never makes anyone G5.

struct OnbEvolutionPage: View {
    /// One line per sport from the athlete's roster: "Cycling · Intermediate".
    let declared: [String]
    let evidence: (title: String, note: String)
    let standing: EvolutionStanding
    /// The stage being looked at. Never stored, never read by anything else; gone when the page is left.
    @State private var exploring: Int? = nil
    @Environment(\.cyTheme) private var theme
    @Environment(\.dynamicTypeSize) private var dts

    var body: some View {
        let shown = exploring.flatMap { EvolutionStages.stage($0) }
        VStack(alignment: .leading, spacing: 8) {
            VStack(spacing: 4) {
                hero(shown?.index ?? standing.stage)
                Text(shown.map { "\($0.code) · \($0.name)" } ?? "Establishing your baseline")
                    .font(CyDyn.f(21, .bold)).foregroundStyle(theme.textPrimary)
                    .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("onbEvolutionState")
                Text(shown?.summary ?? "Tap a stage to see what it looks like. Yours comes from your training.")
                    .font(CyDyn.f(13.5)).foregroundStyle(theme.textSecondary).multilineTextAlignment(.center)
                    .lineLimit(dts.isAccessibilitySize ? 6 : 2, reservesSpace: !dts.isAccessibilitySize)
                    .accessibilityIdentifier("onbEvolutionSummary")
                // a preview is said in words (owner's wording, 22 Nov 2026 18:47), so it is never read as the athlete's own
                Text(shown.map { "Previewing \($0.code)" } ?? " ")
                    .font(CyDyn.f(11, .semibold)).foregroundStyle(theme.accent)
                    .padding(.horizontal, 8).padding(.vertical, 2)
                    .background(Capsule().fill(theme.accent.opacity(shown == nil ? 0 : 0.14)))
                    .accessibilityHidden(shown == nil)
                    .accessibilityIdentifier("onbEvolutionExploring")
            }
            .frame(maxWidth: .infinity)
            rail
            group(.declared, "Declared by you", id: "onbEvolutionDeclared") {
                VStack(alignment: .leading, spacing: 1) {
                    ForEach(Array(declared.prefix(3).enumerated()), id: \.offset) { line in
                        Text(line.element).font(CyDyn.f(15, .semibold)).foregroundStyle(theme.textPrimary).fixedSize(horizontal: false, vertical: true)
                    }
                    if declared.count > 3 { Text("+ \(declared.count - 3) more").font(CyDyn.f(13)).foregroundStyle(theme.textSecondary) }
                    if declared.isEmpty { Text("Nothing declared yet").font(CyDyn.f(15, .semibold)).foregroundStyle(theme.textPrimary) }
                }
            }
            group(.measured, "Measured evidence", id: "onbEvolutionMeasured") {
                VStack(alignment: .leading, spacing: 1) {
                    Text(evidence.title).font(CyDyn.f(15, .semibold)).foregroundStyle(theme.textPrimary).fixedSize(horizontal: false, vertical: true)
                    Text(evidence.note).font(CyDyn.f(12.5)).foregroundStyle(theme.textSecondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            stageGroup
        }
    }

    /// The stage's orbital form: one drawing family, more developed stage by stage (rendered from the same routine as
    /// the approved Welcome artwork). Falls back to the flat placeholder if an image is missing.
    /// No stage (not assessed, nothing previewed) has its own neutral form: an empty orbit, distinct from G0.
    @ViewBuilder private func hero(_ stage: Int?) -> some View {
        let name = stage.map { "EvolutionStage-\($0)-\(theme.id.rawValue)" } ?? "EvolutionNeutral-\(theme.id.rawValue)"
        Group {
            if UIImage(named: name) != nil { Image(name).resizable().scaledToFit() }
            else { SingularityPlaceholder(diameter: 64, detail: 1) }
        }
        .frame(height: 132)
        .padding(.vertical, -10)   // the image carries its own soft margin; the layout reserves the body only
        .accessibilityHidden(true)
        .id(name)
        .transition(.opacity)
    }

    /// YOU (where the athlete stands — nowhere on the rail until assessed), then six stages, each a button.
    private var rail: some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(spacing: 4) {
                RoundedRectangle(cornerRadius: 3, style: .continuous).fill(theme.textPrimary).frame(width: 14, height: 14).frame(height: 22)
                Text("YOU").font(.caption2.weight(.bold)).foregroundStyle(theme.textPrimary)
            }
            .frame(width: 34)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("You: \(standing.title)")
            .accessibilityIdentifier("onbEvolutionYou")
            ForEach(EvolutionStages.all) { s in
                let on = exploring == s.index, mine = standing.stage == s.index
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { exploring = on ? nil : s.index }
                } label: {
                    VStack(spacing: 4) {
                        ZStack {
                            Rectangle().fill(theme.border).frame(height: 1)
                            Circle().fill(theme.background).frame(width: on ? 20 : 12, height: on ? 20 : 12)
                            if on {
                                Circle().fill(theme.accent).frame(width: 12, height: 12)
                                Circle().strokeBorder(theme.accent, lineWidth: 1.5).frame(width: 20, height: 20)
                            } else if mine {
                                Circle().fill(theme.textPrimary).frame(width: 11, height: 11)
                            } else {
                                Circle().strokeBorder(theme.textSecondary, lineWidth: 1.5).frame(width: 11, height: 11)
                            }
                        }
                        .frame(height: 22)
                        Text(s.code).font(.caption2.weight(on ? .bold : .semibold)).foregroundStyle(on ? theme.textPrimary : theme.textSecondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: CyHit.min).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(s.code), \(s.name)")
                .accessibilityValue(on ? "previewing" : mine ? "your stage" : "")
                .accessibilityHint("Shows this stage. It does not change yours.")
                .accessibilityAddTraits(on ? .isSelected : [])
                .accessibilityIdentifier("onbStage-\(s.index)")
            }
        }
        .dynamicTypeSize(...DynamicTypeSize.xLarge)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("onbEvolutionTrack")
    }

    private func group<Content: View>(_ mark: OnbGroupHeader.Mark, _ title: String, id: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Rectangle().fill(theme.separator).frame(height: 1).padding(.bottom, 5).accessibilityHidden(true)
            OnbGroupHeader(mark: mark, title: title)
            content()
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier(id)
        }
    }
    /// The athlete's OWN standing — never the stage being explored.
    private var stageGroup: some View {
        VStack(alignment: .leading, spacing: 2) {
            Rectangle().fill(theme.separator).frame(height: 1).padding(.bottom, 5).accessibilityHidden(true)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: "square").font(CyDyn.f(10, .bold)).foregroundStyle(theme.textSecondary).accessibilityHidden(true)
                Text("YOUR STAGE").font(CyDyn.f(11.5, .semibold)).tracking(1.1).foregroundStyle(theme.textSecondary).accessibilityAddTraits(.isHeader)
                if let b = standing.basis {
                    Text(b).font(CyDyn.f(11, .semibold)).foregroundStyle(theme.textSecondary).accessibilityIdentifier("onbEvolutionBasis")
                }
            }
            Text(standing.title).font(CyDyn.f(15, .semibold)).foregroundStyle(theme.textPrimary).fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("onbEvolutionStage")
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
    /// The chosen plannable sessions with each day's own minutes (nil = the week-wide lengths above are drawn).
    var sessions: [[ChosenSession]]? = nil
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
                OnbWeekStrip(kinds: m.kinds, ride: m.ride, lift: m.lift, sessions: m.sessions, idPrefix: "blueprintDay", containerId: "blueprintWeek")
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
