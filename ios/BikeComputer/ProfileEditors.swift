import SwiftUI

// MARK: - V1: the editors shared by onboarding and Profile (ONE implementation of each)
//
// Every editor is a view over `OnboardingAnswers` (OnboardingDraft.swift). Onboarding writes each answer straight into
// the single authoritative profile through `OnboardingAnswers.apply`; the Profile editors hold a local copy and save it
// through the plan preview (`Store.changeTraining`). Nothing here invents a value: a missing date of birth, weight or
// FTP stays "Not set" / "Unknown".

// MARK: Stage A — Who are you as an athlete?

struct AthleteTypeEditor: View {
    enum Part: Hashable { case name, type, experience, personal }
    @Binding var a: OnboardingAnswers
    var parts: Set<Part> = [.name, .type, .experience, .personal]
    /// Prefill offered from Apple Health (weight) when the athlete has authorized it — shown, never applied silently.
    var healthWeight: (kg: Double, date: Date)? = nil
    var units: AppSettings.Units = .metric
    /// Provenance lines for the Profile editor (nil in onboarding, where nothing is stored yet).
    var dobLine: String? = nil
    var weightLine: String? = nil
    @State private var weightText = ""
    @State private var showDOB = false
    @State private var dobDraft: Date? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: CyTheme.sp4) {
            if parts.contains(.name) {
                VStack(alignment: .leading, spacing: 6) {
                    CyCaption(text: "Name")
                    TextField("Your first name", text: Binding(get: { a.name ?? "" }, set: { a.name = $0 }))
                        .textContentType(.givenName).font(CyType.bodyStrong).foregroundStyle(CyTheme.ink)
                        .padding(.horizontal, 14).frame(minHeight: 52)
                        .background(CyTheme.card, in: RoundedRectangle(cornerRadius: CyTheme.rField, style: .continuous))
                        .accessibilityIdentifier("onbName")
                }
            }
            if parts.contains(.type) {
                HStack(spacing: 10) {
                    ForEach(TrainingMode.allCases, id: \.self) { m in typeCard(m) }
                }
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("onbMode")
            }
            if parts.contains(.experience), let m = a.mode {
                if m.includesCycling {
                    chips("Cycling experience", RiderProfile.Level.allCases, selected: a.cyclingLevel, label: levelTitle, id: "onbCyclingLevel") { a.cyclingLevel = $0 }
                }
                if m.includesLifting {
                    chips("Strength experience", StrengthPrefs.Experience.allCases, selected: a.strengthLevel, label: strengthTitle, id: "onbStrengthLevel") { a.strengthLevel = $0 }
                }
                if m == .hybrid {
                    VStack(alignment: .leading, spacing: 6) {
                        CyCaption(text: "Priority")
                        CySegmentedControl(options: [(TrainingPriority.cycling, "Cycling"), (TrainingPriority.balanced, "Balanced"), (TrainingPriority.strength, "Strength")],
                                           selection: Binding(get: { a.priority ?? .balanced }, set: { a.priority = $0 }))
                            .accessibilityIdentifier("onbPriority")
                    }
                }
            }
            if parts.contains(.personal) { personal }
        }
        .onAppear { if let w = a.weightKg { weightText = Self.weightString(w, units) } }
    }

    // --- the three visual athlete-type cards
    private func typeCard(_ m: TrainingMode) -> some View {
        let on = a.mode == m
        let (sport, line): (CySport?, String) = { () -> (CySport?, String) in
            switch m {
            case .cycling: return (.cycling, "Rides, zones, FTP")
            case .strength: return (.strength, "Lifts, sets, progression")
            case .hybrid: return (nil, "Both, coordinated")
            }
        }()
        let tint = sport.map { CyTheme.identity($0).tint } ?? CyTheme.insight.tint
        let bg = sport.map { CyTheme.identity($0).bg } ?? CyTheme.insight.bg
        return Button {
            withAnimation(CyMotion.animation(CyTheme.motionPop, reduce: reduceMotion)) {
                a.mode = m
                if m != .hybrid { a.priority = nil }
            }
        } label: {
            VStack(spacing: 8) {
                ZStack {
                    Circle().fill(bg).frame(width: 52, height: 52)
                    if m == .hybrid {
                        HStack(spacing: -4) {
                            Image(systemName: "bicycle").foregroundStyle(CyTheme.cycling.tint)
                            Image(systemName: "dumbbell.fill").foregroundStyle(CyTheme.strength.tint)
                        }.font(.system(size: 17, weight: .semibold))
                    } else {
                        Image(systemName: m == .cycling ? "bicycle" : "dumbbell.fill").font(.system(size: 22, weight: .semibold)).foregroundStyle(tint)
                    }
                }
                Text(m == .hybrid ? "Hybrid" : m.title).font(CyType.bodyStrong).foregroundStyle(CyTheme.ink).lineLimit(1).minimumScaleFactor(0.8)
                Text(line).font(CyType.captionSmall).foregroundStyle(CyTheme.ink3).multilineTextAlignment(.center).lineLimit(2).minimumScaleFactor(0.85)
            }
            .padding(.vertical, 14).padding(.horizontal, 6)
            .frame(maxWidth: .infinity, minHeight: 128)
            .background(CyTheme.card, in: RoundedRectangle(cornerRadius: CyTheme.rCard, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: CyTheme.rCard, style: .continuous).stroke(on ? CyTheme.ink : CyTheme.line, lineWidth: on ? 2 : 1))
            .overlay(alignment: .topTrailing) {
                if on { Image(systemName: "checkmark.circle.fill").font(.body).foregroundStyle(CyTheme.ink).padding(8).transition(.scale) }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(m == .hybrid ? "Hybrid" : m.title): \(line)")
        .accessibilityAddTraits(on ? .isSelected : [])
        .accessibilityIdentifier("onbMode-\(m.rawValue)")
    }

    private func chips<T: Hashable>(_ title: String, _ options: [T], selected: T?, label: @escaping (T) -> String, id: String, set: @escaping (T) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            CyCaption(text: title)
            HStack(spacing: 8) {
                ForEach(Array(options.enumerated()), id: \.offset) { pair in
                    CyChip(title: label(pair.element), selected: selected == pair.element) { set(pair.element) }
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier(id)
        }
    }
    static func levelTitle(_ l: RiderProfile.Level) -> String { switch l { case .beginner: return "Beginner"; case .intermediate: return "Intermediate"; case .advanced: return "Advanced" } }
    static func strengthTitle(_ e: StrengthPrefs.Experience) -> String { switch e { case .beginner: return "Beginner"; case .intermediate: return "Intermediate"; case .advanced: return "Advanced" } }
    private func levelTitle(_ l: RiderProfile.Level) -> String { Self.levelTitle(l) }
    private func strengthTitle(_ e: StrengthPrefs.Experience) -> String { Self.strengthTitle(e) }

    // --- date of birth and weight: optional, with the reason, no sample values
    private var personal: some View {
        CyRowGroup {
            Button { withAnimation(CyMotion.animation(CyTheme.motionSheet, reduce: reduceMotion)) { showDOB.toggle() } } label: {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Date of birth").font(CyType.body).foregroundStyle(CyTheme.ink)
                        Text(dobLine ?? "for heart-rate zones · optional").font(CyType.captionSmall).foregroundStyle(CyTheme.ink3)
                    }
                    Spacer(minLength: 8)
                    Text(a.dateOfBirth.map { $0.formatted(date: .abbreviated, time: .omitted) } ?? "Select date")
                        .font(CyType.secondary.weight(.semibold)).foregroundStyle(a.dateOfBirth == nil ? CyTheme.cycling.tint : CyTheme.ink2)
                    if let age = a.dateOfBirth.flatMap(Self.age) { Text("\(age) yrs").font(CyType.captionSmall).foregroundStyle(CyTheme.ink3) }
                }
                .padding(.horizontal, 14).padding(.vertical, 10).frame(minHeight: 56).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("onbDOB")
            .accessibilityLabel("Date of birth, \(a.dateOfBirth.map { $0.formatted(date: .abbreviated, time: .omitted) } ?? "not set")")
            if showDOB {
                // Nothing is saved until the wheel is moved or Done is tapped on a moved wheel (never today − 35 years).
                DatePicker("Date of birth", selection: Binding(get: { dobDraft ?? a.dateOfBirth ?? Self.dobRange.upperBound }, set: { dobDraft = $0 }),
                           in: Self.dobRange, displayedComponents: .date)
                    .datePickerStyle(.wheel).labelsHidden().frame(maxWidth: .infinity)
                HStack {
                    if a.dateOfBirth != nil {
                        CyTertiaryLink(title: "Clear") { a.dateOfBirth = nil; dobDraft = nil; showDOB = false }
                    }
                    Spacer()
                    CySecondaryButton(title: "Done") {
                        if let d = dobDraft { a.dateOfBirth = d }
                        withAnimation(CyMotion.animation(CyTheme.motionSheet, reduce: reduceMotion)) { showDOB = false }
                    }
                    .frame(maxWidth: 140)
                    .accessibilityIdentifier("onbDOBDone")
                }
                .padding(.horizontal, 14).padding(.bottom, 10)
            }
            CyDivider()
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Weight").font(CyType.body).foregroundStyle(CyTheme.ink)
                    Text(weightLine ?? "for loads and W/kg · optional").font(CyType.captionSmall).foregroundStyle(CyTheme.ink3)
                }
                Spacer(minLength: 8)
                TextField("Not set", text: $weightText)
                    .keyboardType(.decimalPad).multilineTextAlignment(.trailing).font(CyType.bodyStrong).foregroundStyle(CyTheme.ink)
                    .frame(width: 84)
                    .onChange(of: weightText) { _, v in a.weightKg = Self.parseWeight(v, units) }
                    .accessibilityLabel("Weight in \(units == .imperial ? "pounds" : "kilograms")")
                    .accessibilityIdentifier("onbWeight")
                Text(units == .imperial ? "lb" : "kg").font(CyType.unit).foregroundStyle(CyTheme.ink3)
            }
            .padding(.horizontal, 14).padding(.vertical, 10).frame(minHeight: 56)
            if let h = healthWeight, a.weightKg == nil {
                CyDivider()
                HStack {
                    Text("Apple Health has \(Self.weightString(h.kg, units)) \(units == .imperial ? "lb" : "kg") (\(h.date.formatted(date: .abbreviated, time: .omitted)))").font(CyType.captionSmall).foregroundStyle(CyTheme.ink2)
                    Spacer()
                    CyTertiaryLink(title: "Use it") { a.weightKg = h.kg; weightText = Self.weightString(h.kg, units) }
                }.padding(.horizontal, 14).padding(.vertical, 8)
            }
        }
    }
    static let dobRange: ClosedRange<Date> = (Calendar.current.date(byAdding: .year, value: -100, to: Date()) ?? Date())...(Calendar.current.date(byAdding: .year, value: -13, to: Date()) ?? Date())
    static func age(_ d: Date) -> Int? { Calendar.current.dateComponents([.year], from: d, to: Date()).year }
    static func weightString(_ kg: Double, _ u: AppSettings.Units) -> String { u == .imperial ? String(format: "%.0f", kg * 2.20462) : (kg == kg.rounded() ? String(Int(kg)) : String(format: "%.1f", kg)) }
    /// A typed weight in the shown unit → kg within 30–200 kg; anything else = not set.
    static func parseWeight(_ s: String, _ u: AppSettings.Units) -> Double? {
        guard let v = Double(s.replacingOccurrences(of: ",", with: ".")) else { return nil }
        let kg = u == .imperial ? v / 2.20462 : v
        return (30...200).contains(kg) ? (kg * 10).rounded() / 10 : nil
    }
}

// MARK: Stage B — What do you want to achieve?

struct GoalCardsEditor: View {
    @Binding var a: OnboardingAnswers
    let mode: TrainingMode
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var goals: [GoalID] { a.goals ?? [] }

    var body: some View {
        VStack(alignment: .leading, spacing: CyTheme.sp4) {
            ForEach(GoalInfo.choices(for: mode)) { group in
                VStack(alignment: .leading, spacing: 8) {
                    CyCaption(text: group.title)
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                        ForEach(group.goals) { g in goalCard(g) }
                    }
                }
            }
            if let p = a.primaryGoal {
                let e = GoalInfo.emphasis(mode: mode, primary: p, priority: a.priority ?? .balanced)
                VStack(alignment: .leading, spacing: 8) {
                    CyCaption(text: "\(p.title) · main goal", color: CyTheme.goal.tint)
                    Text(GoalInfo.effect(p)).font(CyType.secondary).foregroundStyle(CyTheme.ink).fixedSize(horizontal: false, vertical: true)
                    emphasisBar(e)
                }
                .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                .cyCard(tinted: CyTheme.goal.bg)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("onbGoalEffect")
            }
        }
    }

    private func goalCard(_ g: GoalID) -> some View {
        let on = goals.contains(g)
        let main = on && a.primaryGoal == g
        let sport: CySport = g.sport == .cycling ? .cycling : g.sport == .strength ? .strength : .recovery
        let id = CyTheme.identity(sport)
        return ZStack(alignment: .topTrailing) {
            Button { toggle(g) } label: {
                HStack(spacing: 10) {
                    CyIconBox(systemName: GoalInfo.icon(g), sport: sport)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(g.title).font(CyType.bodyStrong).foregroundStyle(CyTheme.ink).lineLimit(1).minimumScaleFactor(0.8)
                        Text(GoalInfo.line(g)).font(CyType.captionSmall).foregroundStyle(CyTheme.ink3).lineLimit(2).minimumScaleFactor(0.85)
                    }
                    Spacer(minLength: 0)
                }
                .padding(10).padding(.trailing, on ? 18 : 0)
                .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
                .background(on ? id.bg : CyTheme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(on ? id.tint : CyTheme.line, lineWidth: on ? 1.5 : 1))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(g.title), \(GoalInfo.line(g))\(main ? ", main goal" : "")")
            .accessibilityAddTraits(on ? .isSelected : [])
            .accessibilityIdentifier("goal-\(g.rawValue)")
            if on {
                // the star sits beside the card button (never inside it): one tap = main goal
                Button { withAnimation(CyMotion.animation(CyTheme.motionPop, reduce: reduceMotion)) { a.primaryGoal = g } } label: {
                    Image(systemName: main ? "star.fill" : "star").font(.caption.weight(.bold))
                        .foregroundStyle(main ? CyTheme.goal.onTint : id.tint)
                        .frame(width: 26, height: 26)
                        .background(main ? CyTheme.goal.tint : CyTheme.card, in: Circle())
                        .overlay(Circle().stroke(main ? Color.clear : id.tint, lineWidth: 1))
                        .cyMinTap()
                }
                .buttonStyle(.plain)
                .accessibilityLabel(main ? "\(g.title) is the main goal" : "Make \(g.title) the main goal")
                .accessibilityIdentifier("goalStar-\(g.rawValue)")
            }
        }
    }
    private func toggle(_ g: GoalID) {
        var list = goals
        withAnimation(CyMotion.animation(CyTheme.motionPop, reduce: reduceMotion)) {
            if list.contains(g) { list.removeAll { $0 == g } } else { list.append(g) }
            a.goals = list
            a.primaryGoal = a.primaryGoal.flatMap { list.contains($0) ? $0 : nil } ?? list.first
        }
    }
    private func emphasisBar(_ e: GoalInfo.Emphasis) -> some View {
        let parts: [(String, Int, Color)] = [("Easy riding", e.easyRiding, CyTheme.cycling.mid), ("Hard riding", e.hardRiding, CyTheme.cycling.tint), ("Strength", e.strength, CyTheme.strength.mid), ("Rest", e.rest, CyTheme.line)].filter { $0.1 > 0 }
        let total = max(1, parts.reduce(0) { $0 + $1.1 })
        return VStack(alignment: .leading, spacing: 6) {
            GeometryReader { geo in
                HStack(spacing: 2) {
                    ForEach(Array(parts.enumerated()), id: \.offset) { p in
                        RoundedRectangle(cornerRadius: 3).fill(p.element.2).frame(width: max(4, geo.size.width * CGFloat(p.element.1) / CGFloat(total) - 2))
                    }
                }
            }
            .frame(height: 8)
            HStack(spacing: 10) {
                ForEach(Array(parts.enumerated()), id: \.offset) { p in
                    HStack(spacing: 4) { Circle().fill(p.element.2).frame(width: 7, height: 7); Text(p.element.0).font(CyType.captionSmall).foregroundStyle(CyTheme.ink3) }
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Week emphasis: " + parts.map { "\($0.0) \($0.1) of \(total)" }.joined(separator: ", "))
    }
}

// MARK: Stage C — Build your training week (also Profile › Your week)

struct WeekBuilder: View {
    @Binding var a: OnboardingAnswers
    let mode: TrainingMode
    /// The dry-run of the real planner for the week on screen (nil = no preview strip).
    var preview: (([DayKind], Int, Int) -> [Workout])? = nil
    var proposalLabel = "Coach's proposal"
    /// Profile: the saved week is the baseline the label restores (onboarding: the coach's proposal).
    var baseline: [DayKind]? = nil
    @State private var proposed: [DayKind] = []
    @State private var twoADay = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var kinds: [DayKind] { a.week ?? proposed }
    private var ride: Int { a.rideMinutes ?? OnboardingWeek.defaultRideMinutes }
    private var lift: Int { a.liftMinutes ?? OnboardingWeek.defaultLiftMinutes }
    private var touched: Bool { a.week != nil && a.week != proposed }

    var body: some View {
        let k = kinds
        let f = OnboardingWeek.feasibility(k, mode: mode, ride: ride, lift: lift, strengthLevel: a.strengthLevel)
        VStack(alignment: .leading, spacing: CyTheme.sp4) {
            VStack(alignment: .leading, spacing: 10) {
                CyCalendarStrip(days: days(k)) { d in tap(d.id) }
                    .accessibilityIdentifier("onbWeek")
                HStack(spacing: 12) {
                    if mode.includesCycling { Label("\(OnboardingWeek.rides(k))", systemImage: "bicycle").foregroundStyle(CyTheme.cycling.tint).accessibilityLabel("\(OnboardingWeek.rides(k)) rides") }
                    if mode.includesLifting { Label("\(OnboardingWeek.lifts(k))", systemImage: "dumbbell").foregroundStyle(CyTheme.strength.tint).accessibilityLabel("\(OnboardingWeek.lifts(k)) strength sessions") }
                    Label("\(k.filter { $0 == .rest }.count)", systemImage: "moon").foregroundStyle(CyTheme.ink3).accessibilityLabel("\(k.filter { $0 == .rest }.count) rest days")
                    Spacer()
                    if touched { CyTertiaryLink(title: proposalLabel) { withAnimation(CyMotion.animation(CyTheme.motionPop, reduce: reduceMotion)) { a.week = proposed } } }
                    else { Text(proposalLabel).font(CyType.captionSmall).foregroundStyle(CyTheme.ink3) }
                }
                .font(CyType.secondary.weight(.semibold))
                .accessibilityIdentifier("onbWeekCounts")
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: f.ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill").font(.footnote).foregroundStyle(f.ok ? CyTheme.ok : CyTheme.warn)
                    Text(f.text).font(CyType.secondary).foregroundStyle(f.ok ? CyTheme.recovery.tint : CyTheme.warn).fixedSize(horizontal: false, vertical: true)
                }
                .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                .background(f.ok ? CyTheme.recovery.bg : CyTheme.warnBg, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("onbFeasibility")
            }
            CyRowGroup {
                if mode.includesCycling {
                    stepperRow("Ride length", "Typical ride", value: ride, range: 20...300, step: 10) { a.rideMinutes = $0 }
                        .accessibilityIdentifier("onbRideMinutes")
                }
                if mode.includesLifting {
                    if mode.includesCycling { CyDivider() }
                    stepperRow("Strength length", "Typical session", value: lift, range: 15...120, step: 5) { a.liftMinutes = $0 }
                        .accessibilityIdentifier("onbLiftMinutes")
                }
                if mode == .hybrid {
                    CyDivider()
                    CySwitchRow(title: "Two sessions in one day", caption: "Ride + lift on the same day, lift first",
                                isOn: Binding(get: { twoADay }, set: { v in twoADay = v; if !v { a.week = kinds.map { OnboardingWeek.normalise($0, mode: mode, twoADay: false) } } }))
                        .accessibilityIdentifier("onbTwoADay")
                }
            }
            if mode.includesLifting {
                VStack(alignment: .leading, spacing: 8) {
                    CyCaption(text: "Equipment")
                    HStack(spacing: 8) {
                        ForEach(EquipmentPreset.allCases, id: \.self) { p in
                            CyChip(title: p.title, selected: (a.equipment ?? .notSure) == p, sport: p == .notSure ? nil : .strength) { a.equipment = p }
                        }
                    }
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("onbEquipment")
                    if (a.equipment ?? .notSure) == .notSure { Text("Not sure = bodyweight sessions until you confirm what you have.").font(CyType.captionSmall).foregroundStyle(CyTheme.ink3) }
                    CyRowGroup {
                        CySwitchRow(title: "Supersets", caption: "Pair exercises to save time", isOn: Binding(get: { a.supersets ?? false }, set: { a.supersets = $0 }))
                            .accessibilityIdentifier("onbSupersets")
                    }
                }
            }
            if let p = preview {
                let plan = p(k, ride, lift)
                VStack(alignment: .leading, spacing: 8) {
                    HStack { CyCaption(text: "Your plan · live preview"); Spacer(); Text("\(OnboardingWeek.rides(k)) rides · \(OnboardingWeek.lifts(k)) lifts · \(OnboardingWeek.durationText(OnboardingWeek.minutes(k, ride: ride, lift: lift)))").font(CyType.captionSmall).foregroundStyle(CyTheme.ink3) }
                    if plan.isEmpty {
                        Text("Pick a training day to see the plan.").font(CyType.secondary).foregroundStyle(CyTheme.ink3)
                    } else {
                        VStack(spacing: 6) {
                            ForEach(plan.filter { $0.kind.isRide || $0.kind == .strength }) { w in previewRow(w) }
                        }
                    }
                }
                .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                .cyCard()
                .accessibilityIdentifier("onbPlanPreview")
            }
        }
        .onAppear {
            proposed = baseline ?? OnboardingWeek.propose(mode: mode, cyclingLevel: a.cyclingLevel ?? .intermediate, strengthLevel: a.strengthLevel, priority: a.priority ?? .balanced)
            twoADay = kinds.contains(.both)
            if a.week == nil { a.week = proposed }
        }
    }

    private func days(_ k: [DayKind]) -> [CyDay] {
        (0..<7).map { i in
            let s: CyDaySport = { switch k[i] { case .ride: return .cycling; case .lift: return .strength; case .both: return .both; case .rest: return .rest } }()
            return CyDay(id: i, shortName: WeeklyAvailability.dayNames[i], longName: WeeklyAvailability.longDayNames[i], sport: s, status: s == .rest ? .none : .planned)
        }
    }
    private func tap(_ i: Int) {
        var k = kinds
        k[i] = OnboardingWeek.next(k[i], mode: mode, twoADay: twoADay)
        withAnimation(CyMotion.animation(CyTheme.motionPop, reduce: reduceMotion)) { a.week = k }
    }
    private func stepperRow(_ title: String, _ caption: String, value: Int, range: ClosedRange<Int>, step: Int, set: @escaping (Int) -> Void) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(CyType.body).foregroundStyle(CyTheme.ink)
                Text(caption).font(CyType.captionSmall).foregroundStyle(CyTheme.ink3)
            }
            Spacer(minLength: 8)
            CyStepper(title: title, value: Binding(get: { Double(value) }, set: { set(Int($0)) }), step: Double(step), range: Double(range.lowerBound)...Double(range.upperBound), unit: "min")
                .frame(width: 150)
        }
        .padding(.horizontal, 14).padding(.vertical, 8).frame(minHeight: 56)
    }
    private func previewRow(_ w: Workout) -> some View {
        let sport: CySport = w.kind.isRide ? .cycling : .strength
        let id = CyTheme.identity(sport)
        return HStack(spacing: 10) {
            Text(w.date.formatted(.dateTime.weekday(.abbreviated))).font(CyType.captionSmall).foregroundStyle(CyTheme.ink3).frame(width: 34, alignment: .leading)
            Image(systemName: sport.icon).font(.caption.weight(.semibold)).foregroundStyle(id.tint).frame(width: 18)
            Text(w.displayTitle).font(CyType.secondary.weight(.semibold)).foregroundStyle(CyTheme.ink).lineLimit(1)
            Spacer()
            Text("\(w.minutes) min").font(CyType.captionSmall).foregroundStyle(CyTheme.ink2)
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(id.bg.opacity(0.6), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

// MARK: Stage D / Devices — the device cards (real states only)

/// The card list used by onboarding Stage D and the Devices screen. Actions go to the existing flows only.
struct DeviceCardList: View {
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var device: DeviceLink
    @EnvironmentObject private var watch: WatchLink
    @EnvironmentObject private var health: HealthAccess
    @EnvironmentObject private var hub: SensorHub
    @EnvironmentObject private var location: LocationService
    @State private var pairSheet = false
    @State private var healthNote: String? = nil
    @State private var tick = Date()
    private let timer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    private var cards: [DeviceCardModel] {
        DeviceCards.build(states: hub.deviceStates, mode: store.profile.trainingMode,
                          bleSensors: hub.ble.paired.map { DeviceCards.Sensor(id: $0.sourceId, name: $0.name, provides: $0.kinds.map(\.title).joined(separator: ", "),
                                                                              hasHR: $0.kinds.contains(.heartRate), hasPower: $0.kinds.contains(.power), hasCadence: $0.kinds.contains(.speedCadence)) },
                          healthAvailable: health.available, boardRemembered: device.remembered)
    }

    var body: some View {
        VStack(spacing: 10) {
            ForEach(cards) { c in card(c) }
            if let n = healthNote { Text(n).font(CyType.captionSmall).foregroundStyle(CyTheme.warn) }
        }
        .sheet(isPresented: $pairSheet) { NavigationStack { BLEPairView(ble: hub.ble).navigationTitle("Add a sensor").navigationBarTitleDisplayMode(.inline) } }
        .onReceive(timer) { t in tick = t; health.refresh(); hub.refresh(device: device, watch: watch, location: location, powerVerified: PowerTrust.meterVerified) }
        .onAppear { hub.refresh(device: device, watch: watch, location: location, powerVerified: PowerTrust.meterVerified) }
    }

    @ViewBuilder private func card(_ c: DeviceCardModel) -> some View {
        let content = HStack(spacing: 12) {
            CyIconBox(systemName: c.systemImage, sport: c.state.isReceiving ? .recovery : nil, large: true)
            VStack(alignment: .leading, spacing: 4) {
                Text(c.name).font(CyType.bodyStrong).foregroundStyle(CyTheme.ink).lineLimit(1)
                Text(c.provides).font(CyType.captionSmall).foregroundStyle(CyTheme.ink3).lineLimit(2)
                CyDeviceStateBadge(state: c.state.cy, detail: c.detail)
            }
            Spacer(minLength: 6)
            if let t = c.actionTitle, c.action != .openDetail {
                CySecondaryButton(title: t) { perform(c) }.frame(width: 96)
            } else if c.action == .openDetail {
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(CyTheme.ink3).accessibilityHidden(true)
            }
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .cyCard()
        if c.action == .openDetail {
            NavigationLink { detail(c) } label: { content }.buttonStyle(.plain)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(c.name), \(c.state.title), \(c.detail)")
                .accessibilityIdentifier(identifier(c))
        } else {
            content
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier(identifier(c))
        }
    }
    private func identifier(_ c: DeviceCardModel) -> String {
        switch c.id {
        case DeviceCards.boardId: return "deviceBoard"
        case DeviceCards.watchId: return "deviceWatch"
        case DeviceCards.healthId: return "deviceHealth"
        default: return "device-\(c.id)"
        }
    }
    @ViewBuilder private func detail(_ c: DeviceCardModel) -> some View {
        switch c.id {
        case DeviceCards.boardId: BoardConnectionDetail()
        case DeviceCards.watchId: WatchConnectionDetail()
        case DeviceCards.healthId: HealthConnectionDetail()
        default:
            if let s = hub.ble.paired.first(where: { $0.sourceId == c.id }) { BLESensorDetail(ble: hub.ble, hub: hub, sensorId: s.id) } else { EmptyView() }
        }
    }
    private func perform(_ c: DeviceCardModel) {
        switch c.action {
        case .connectHealth:
            store.settings.appleHealthWanted = true
            health.request { ok in healthNote = ok ? nil : "Not allowed. Change it in iOS Settings › Health." }
        case .connectBoard:
            store.settings.enabledConnections.insert("board")
            device.connect()
        case .pairSensor: pairSheet = true
        case .openDetail, .none: break
        }
    }
}
