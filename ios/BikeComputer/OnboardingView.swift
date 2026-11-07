import SwiftUI

/// First run — onboarding v3 (Stage 2 / V1, owner approval 2 Nov 2026): Welcome, then five stages
///  A Who you are · B What you want to achieve · C Build your training week · D Connect your ecosystem · E Your training system.
/// One identity entry (the name is asked once, on A). Every answer is written through `OnboardingAnswers.apply` into the
/// single authoritative profile / availability / equipment / strength preferences — the same fields Profile edits — so
/// resume is safe and nothing is copied. The week preview is a dry run of the real planner on those inputs; Approve
/// generates the plan from the same inputs and Home shows it immediately (one plan state). Nothing unknown is invented.
struct OnboardingView: View {
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var health: HealthAccess
    @State private var step = 0
    @State private var a = OnboardingAnswers()
    @State private var ftpKnown = false
    @State private var ftpText = ""
    @State private var resumed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    static let stages = 5
    private static let titles = ["", "Who you are", "Your goals", "Your week", "Your ecosystem", "Your training system"]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if step > 0 { topBar }
                ScrollView {
                    VStack(alignment: .leading, spacing: CyTheme.sp4) {
                        switch step {
                        case 0: welcome
                        case 1: stageA
                        case 2: stageB
                        case 3: stageC
                        case 4: stageD
                        default: stageE
                        }
                    }
                    .padding(.horizontal, CyTheme.margin).padding(.top, 8).padding(.bottom, 24)
                    .frame(maxWidth: CyTheme.maxContentWidth)
                    .frame(maxWidth: .infinity)
                }
                .scrollDismissesKeyboard(.interactively)      /* APP-038: dragging the page puts the keyboard away */
                if step > 0 { bottomBar }
            }
            .background(CyTheme.canvas.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .onAppear(perform: resume)
            .onChange(of: a) { _, _ in commit() }
            .onChange(of: step) { _, s in store.onboardingStage = s == 0 ? 0 : 100 + s }
        }
    }

    // MARK: resume (stages are stored as 101…105; build-121 stages 1…9 map to the stage that holds that question)
    private func resume() {
        guard !resumed else { return }
        resumed = true
        let s = store.onboardingStage
        if s >= 101 { step = min(Self.stages, s - 100) }
        else {
            switch s {
            case 1, 4: step = 1
            case 5: step = 2
            case 2, 3: step = 3
            case 6, 7, 8: step = 4
            case 9: step = 5
            default: step = 0
            }
        }
        let p = store.profile
        var x = OnboardingAnswers()
        if !p.name.isEmpty { x.name = p.name }
        if step >= 1, s != 0 {
            // the athlete has been past Stage A: what is stored is what they chose
            x.mode = p.trainingMode
            x.cyclingLevel = p.level
            x.strengthLevel = store.strengthPrefs.experience
            x.priority = p.trainingMode == .hybrid ? p.priority : nil
        }
        x.dateOfBirth = p.dateOfBirth
        x.weightKg = p.provenance(.weight).source == .unknown ? nil : p.weightKg
        if !p.goals.isEmpty { x.goals = p.goals; x.primaryGoal = p.primaryGoal }
        let mode = x.mode ?? p.trainingMode
        if let k = OnboardingWeek.kinds(of: store.availability, mode: mode, twoADay: true), p.weekIsExplicit == true { x.week = k }
        x.rideMinutes = p.cyclingSessionMinutes
        x.liftMinutes = p.strengthSessionMinutes
        if store.equipment.isSet { x.equipment = EquipmentPreset.of(store.equipment) }
        x.supersets = store.strengthPrefs.prefersSupersets
        if p.ftpKnown { x.ftpWatts = p.ftpValue; x.ftpSource = p.ftpSource == .tested ? .tested : .entered; ftpKnown = true; ftpText = p.ftpValue.map(String.init) ?? "" }
        a = x
    }

    /// Writes the answers into the one authoritative profile (no second copy). Called on every change.
    private func commit() {
        var x = store.planInputs
        a.apply(to: &x)
        store.updateProfile { $0 = x.profile }
        if store.availability != x.availability { store.availability = x.availability }
        if store.equipment != x.equipment { store.equipment = x.equipment }
        if store.strengthPrefs != x.strengthPrefs { store.strengthPrefs = x.strengthPrefs }
    }

    private var mode: TrainingMode { a.mode ?? store.profile.trainingMode }

    // MARK: chrome
    private var topBar: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Button { withAnimation(CyMotion.animation(CyTheme.motionRise, reduce: reduceMotion)) { step -= 1 } } label: {
                    Image(systemName: "chevron.left").font(.body.weight(.semibold)).foregroundStyle(CyTheme.ink).cyMinTap()
                }
                .buttonStyle(.plain).accessibilityLabel("Back").accessibilityIdentifier("onboardingBack")
                Spacer()
                Text("\(Self.titles[step]) · \(step) of \(Self.stages)").font(CyType.captionSmall).foregroundStyle(CyTheme.ink3)
                    .accessibilityIdentifier("onboardingProgress")
                Spacer()
                if step == 4 {
                    Button("Skip") { withAnimation(CyMotion.animation(CyTheme.motionRise, reduce: reduceMotion)) { step = 5 } }
                        .font(CyType.secondary.weight(.semibold)).foregroundStyle(CyTheme.cycling.tint).cyMinTap()
                        .accessibilityIdentifier("onboardingSkip")
                } else {
                    Color.clear.frame(width: CyTheme.minTap, height: CyTheme.minTap)
                }
            }
            HStack(spacing: 4) {
                ForEach(1...Self.stages, id: \.self) { i in
                    Capsule().fill(i <= step ? CyTheme.ink : CyTheme.line).frame(height: 4)
                }
            }
            .accessibilityHidden(true)
        }
        .padding(.horizontal, CyTheme.margin).padding(.top, 6)
    }

    private var bottomBar: some View {
        VStack(spacing: 8) {
            switch step {
            case 4:
                CyPrimaryButton(title: "Continue", action: next).accessibilityIdentifier("onboardingNext")
                CyTertiaryLink(title: "Skip for now — connect later in Profile") { next() }.frame(maxWidth: .infinity)
            case 5:
                HStack(spacing: 10) {
                    CySecondaryButton(title: "Edit week") { withAnimation(CyMotion.animation(CyTheme.motionRise, reduce: reduceMotion)) { step = 3 } }
                        .accessibilityIdentifier("onbEditWeek")
                    CyPrimaryButton(title: "Approve plan", systemImage: "checkmark", sport: .recovery, action: approve)
                        .accessibilityIdentifier("onbCreatePlan")
                }
            default:
                CyPrimaryButton(title: "Continue", isEnabled: canContinue, action: next).accessibilityIdentifier("onboardingNext")
            }
        }
        .padding(.horizontal, CyTheme.margin).padding(.vertical, 10)
        .background(CyTheme.canvas)
    }
    private var canContinue: Bool {
        switch step {
        case 1: return !(a.name ?? "").trimmingCharacters(in: .whitespaces).isEmpty && a.mode != nil
        case 2: return !(a.goals ?? []).isEmpty
        case 3: return !OnboardingWeek.feasibility(a.week ?? [], mode: mode, ride: a.rideMinutes ?? 60, lift: a.liftMinutes ?? 30, strengthLevel: a.strengthLevel).blocking
        default: return true
        }
    }
    private func next() {
        if step == 1 {
            // what is shown on screen is the answer (the chips start on the stored level)
            if a.cyclingLevel == nil, mode.includesCycling { a.cyclingLevel = store.profile.level }
            if a.strengthLevel == nil, mode.includesLifting { a.strengthLevel = store.strengthPrefs.experience ?? .beginner }
            if a.priority == nil, mode == .hybrid { a.priority = .balanced }
        }
        withAnimation(CyMotion.animation(CyTheme.motionRise, reduce: reduceMotion)) { step = min(Self.stages, step + 1) }
    }
    private func header(_ t: String, _ sub: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(t).font(CyType.largeTitle).foregroundStyle(CyTheme.ink).fixedSize(horizontal: false, vertical: true).accessibilityAddTraits(.isHeader)
            Text(sub).font(CyType.secondary).foregroundStyle(CyTheme.ink2).fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Welcome (one tap, no input)
    private var welcome: some View {
        VStack(alignment: .leading, spacing: CyTheme.sp5) {
            Spacer(minLength: 40)
            HStack(spacing: 12) { CycliftMark(size: 52); Text("Cyclift").font(.system(.largeTitle, design: .rounded).weight(.bold)).foregroundStyle(CyTheme.ink) }
            Text("Your cycling and strength coach — one plan, built from your week.").font(CyType.title).foregroundStyle(CyTheme.ink).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                ZStack { Circle().fill(CyTheme.cycling.bg).frame(width: 40, height: 40); Image(systemName: "bicycle").foregroundStyle(CyTheme.cycling.tint) }
                ZStack { Circle().fill(CyTheme.strength.bg).frame(width: 40, height: 40); Image(systemName: "dumbbell.fill").foregroundStyle(CyTheme.strength.tint) }
                ZStack { Circle().fill(CyTheme.recovery.bg).frame(width: 40, height: 40); Image(systemName: "moon.fill").foregroundStyle(CyTheme.recovery.tint) }
            }
            .accessibilityHidden(true)
            Text("About a minute · connections optional · everything stays on this iPhone").font(CyType.secondary).foregroundStyle(CyTheme.ink3)
            CyPrimaryButton(title: "Get started", systemImage: "arrow.right") { store.guest = true; withAnimation(CyMotion.animation(CyTheme.motionRise, reduce: reduceMotion)) { step = 1 } }
                .accessibilityIdentifier("onboardingContinue")
        }
    }

    // MARK: A — Who are you as an athlete?
    private var stageA: some View {
        VStack(alignment: .leading, spacing: CyTheme.sp4) {
            header("Who are you as an athlete?", "Your name once, the training you do, and what the coach needs for zones and loads.")
            AthleteTypeEditor(a: $a, healthWeight: healthWeightOffer, units: store.settings.units)
        }
    }
    /// A weight already read from Apple Health (with permission) is offered, never applied silently.
    private var healthWeightOffer: (kg: Double, date: Date)? {
        let p = store.profile
        guard p.provenance(.weight).source == .appleHealth, let w = p.weightKg, let d = p.provenance(.weight).recordedAt else { return nil }
        return (w, d)
    }

    // MARK: B — What do you want to achieve?
    private var stageB: some View {
        VStack(alignment: .leading, spacing: CyTheme.sp4) {
            header("What do you want to achieve?", "Pick any. The first is your main goal — tap ★ to change it.")
            GoalCardsEditor(a: $a, mode: mode)
        }
    }

    // MARK: C — Build your training week (coach proposes; live preview from the real planner)
    private var stageC: some View {
        VStack(alignment: .leading, spacing: CyTheme.sp4) {
            header("Build your training week", "The coach proposed this from your answers — tap a day to change it.")
            WeekBuilder(a: $a, mode: mode, preview: dryRun)
        }
    }
    /// The planner on the inputs Approve will save, for this Monday — nothing persisted.
    private func dryRun(_ kinds: [DayKind], _ ride: Int, _ lift: Int) -> [Workout] { dryRun(kinds, ride, lift, weekOffset: 0) }
    private func dryRun(_ kinds: [DayKind], _ ride: Int, _ lift: Int, weekOffset: Int) -> [Workout] {
        var x = store.planInputs
        var draft = a; draft.week = kinds; draft.rideMinutes = ride; draft.liftMinutes = lift
        draft.apply(to: &x)
        guard let av = x.availability else { return [] }
        let cal = Calendar.current
        let d0 = cal.startOfDay(for: Date())
        let wd = (cal.component(.weekday, from: d0) + 5) % 7
        let monday = cal.date(byAdding: .day, value: -wd + 7 * weekOffset, to: d0) ?? d0
        return PlanEngine.week(starting: monday, profile: x.profile, availability: av)
    }

    // MARK: D — Connect your ecosystem (optional; only actions that work today)
    private var stageD: some View {
        VStack(alignment: .leading, spacing: CyTheme.sp4) {
            header("Connect your ecosystem", "All optional. Only actions that work today are shown; you can do this later in Profile.")
            DeviceCardList()
            if mode.includesCycling { ftpCard }
        }
    }
    private var ftpCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack { CyCaption(text: "FTP"); Spacer(); CySourceTagBadge(tag: store.profile.ftpKnown ? .logged : .unknown) }
            CySegmentedControl(options: [(false, "Don't know"), (true, "I know it")], selection: Binding(get: { ftpKnown }, set: { v in
                ftpKnown = v
                if !v { a.ftpSource = .unknown; a.ftpWatts = nil; ftpText = "" } else { a.ftpSource = nil }
            }))
            .accessibilityIdentifier("onbFTP")
            if ftpKnown {
                HStack(spacing: 10) {
                    TextField("Watts", text: $ftpText).keyboardType(.numberPad).font(CyType.bodyStrong).foregroundStyle(CyTheme.ink)
                        .padding(.horizontal, 12).frame(minHeight: 48)
                        .background(CyTheme.card2, in: RoundedRectangle(cornerRadius: CyTheme.rField, style: .continuous))
                        .onChange(of: ftpText) { _, v in
                            // GR-22: Entered only with a typed number in 50–600 W; otherwise the FTP stays Unknown
                            if let n = Int(v), (50...600).contains(n) { a.ftpWatts = n; a.ftpSource = .entered }
                            else { a.ftpWatts = nil; a.ftpSource = .unknown }
                        }
                        .accessibilityLabel("FTP in watts").accessibilityIdentifier("onbFTPWatts")
                    Text("W").font(CyType.unit).foregroundStyle(CyTheme.ink3)
                }
                Text(store.profile.ftpKnown ? "Entered · power targets use it. An FTP test ride later makes it Tested." : "Type your FTP in watts (50–600). Until then it stays Unknown.").font(CyType.captionSmall).foregroundStyle(CyTheme.ink3)
            } else {
                Text("Rides use heart rate and effort until you know it. No watts are ever guessed.").font(CyType.captionSmall).foregroundStyle(CyTheme.ink3)
            }
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .cyCard()
    }

    // MARK: E — Your training system (the first real dashboard; Approve → Home shows the same plan)
    private var stageE: some View {
        let kinds = a.week.flatMap { $0.count == 7 ? $0 : nil } ?? OnboardingWeek.propose(mode: mode, cyclingLevel: a.cyclingLevel ?? .intermediate, strengthLevel: a.strengthLevel, priority: a.priority ?? .balanced)
        let ride = a.rideMinutes ?? OnboardingWeek.defaultRideMinutes, lift = a.liftMinutes ?? OnboardingWeek.defaultLiftMinutes
        let plan = dryRun(kinds, ride, lift)
        // late in the week the remaining days may hold no session of this athlete's sports: the first workout is then next week's
        let first = OnboardingApproach.firstWorkout(in: plan, from: Date()) ?? OnboardingApproach.firstWorkout(in: dryRun(kinds, ride, lift, weekOffset: 1), from: Date())
        let lines = OnboardingApproach.lines(primary: a.primaryGoal, mode: mode, kinds: kinds, liftMinutes: lift, ftpKnown: store.profile.ftpKnown, ftpWatts: store.profile.ftpValue, equipmentProvisional: store.equipment.isProvisional)
        return VStack(alignment: .leading, spacing: CyTheme.sp4) {
            header("Your training system", "\(a.name.map { "\($0), this" } ?? "This") is week 1. Approve it and it's on Home.")
            VStack(alignment: .leading, spacing: 12) {
                if let gs = a.goals, !gs.isEmpty {
                    FlowRow(spacing: 6) {
                        ForEach(gs) { g in
                            let main = g == a.primaryGoal
                            HStack(spacing: 4) { if main { Image(systemName: "star.fill").font(.caption2) }; Text(g.title) }
                                .font(CyType.captionSmall).foregroundStyle(main ? CyTheme.goal.onTint : CyTheme.ink2)
                                .padding(.horizontal, 10).frame(minHeight: 30)
                                .background(main ? CyTheme.goal.tint : CyTheme.card2, in: Capsule())
                                .accessibilityLabel(main ? "\(g.title), main goal" : g.title)
                        }
                    }
                }
                CyCalendarStrip(days: (0..<7).map { i in
                    let s: CyDaySport = { switch kinds[i] { case .ride: return .cycling; case .lift: return .strength; case .both: return .both; case .rest: return .rest } }()
                    return CyDay(id: i, shortName: WeeklyAvailability.dayNames[i], longName: WeeklyAvailability.longDayNames[i], sport: s, status: s == .rest ? .none : .planned)
                })
                HStack(spacing: 0) {
                    if mode.includesCycling { stat("\(OnboardingWeek.rides(kinds))", "rides") }
                    if mode.includesLifting { stat("\(OnboardingWeek.lifts(kinds))", "lifts") }
                    stat(OnboardingWeek.durationText(OnboardingWeek.minutes(kinds, ride: ride, lift: lift)), "planned")
                }
            }
            .padding(14).frame(maxWidth: .infinity, alignment: .leading)
            .cyCard()
            .accessibilityElement(children: .contain)   // run 146: without it the card's identifier replaced the stats' own
            .accessibilityIdentifier("onbDash")
            if let w = first {
                CyCaption(text: "First workout · \(w.date.formatted(.dateTime.weekday(.wide)))")
                CySessionCard(sport: w.kind.isRide ? .cycling : .strength, caption: w.date.formatted(.dateTime.weekday(.wide)), title: w.displayTitle,
                              meta: "\(w.minutes) min" + (w.kind == .strength ? (store.equipment.isProvisional ? " · bodyweight" : "") : (store.profile.ftpKnown ? " · power targets" : " · effort targets")),
                              detail: w.kind == .strength ? "Light, to find your weights — every set you log sets week 2." : (store.profile.ftpKnown ? "Zones from your FTP." : "Heart rate or effort guides the ride."))
                    .accessibilityIdentifier("onbFirst")
            }
            CyCaption(text: "The approach")
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(lines.enumerated()), id: \.offset) { pair in
                    HStack(alignment: .top, spacing: 10) {
                        Text("\(pair.offset + 1)").font(CyType.captionSmall).foregroundStyle(CyTheme.goal.tint).frame(width: 22, height: 22).background(CyTheme.card, in: Circle())
                        Text(pair.element).font(CyType.secondary).foregroundStyle(CyTheme.ink).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(14).frame(maxWidth: .infinity, alignment: .leading)
            .cyCard(tinted: CyTheme.goal.bg)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("onbWhy")
            Text(connectedLine).font(CyType.captionSmall).foregroundStyle(CyTheme.ink3)
        }
    }
    private func stat(_ v: String, _ l: String) -> some View {
        VStack(spacing: 2) { Text(v).font(CyType.numeralSmall).foregroundStyle(CyTheme.ink).monospacedDigit(); Text(l).font(CyType.captionSmall).foregroundStyle(CyTheme.ink3) }
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(v) \(l)")
            .accessibilityValue(v)
            .accessibilityIdentifier("onbStat-\(l)")
    }
    private var connectedLine: String {
        let n = store.settings.enabledConnections.count + (health.workoutWriteAuthorized ? 1 : 0)
        return n == 0 ? "No devices yet — add them any time in Profile · what you log sets week 2." : "\(n) connection\(n == 1 ? "" : "s") set up · change them any time in Profile."
    }

    /// Plan version 1: the same inputs the preview used, generated for this week and next; Home and Plan read `plan`.
    private func approve() {
        commit()
        if store.profile.goals.isEmpty, let g = a.goals { store.updateProfile { $0.goals = g; $0.primaryGoal = a.primaryGoal ?? g.first } }
        store.onboardingStage = 0
        let now = Date()
        store.dropUnapprovedSessions(before: now)        // W12: pre-approval placeholder sessions never become history
        _ = store.regenerate(weekOf: now, replaceEdited: true)
        if let next = Calendar.current.date(byAdding: .day, value: 7, to: now) { _ = store.regenerate(weekOf: next, replaceEdited: true) }
        let made = store.plan.filter { $0.date >= Calendar.current.startOfDay(for: now) }
        store.planVersions.append(PlanVersion(createdAt: now, effectiveDate: made.first?.date ?? now, cause: .profile, before: [], after: made, inputsBefore: nil,
                                              summary: ["Plan approved in onboarding: \(OnboardingWeek.rides(a.week ?? [])) rides · \(OnboardingWeek.lifts(a.week ?? [])) lifts a week"], proposalId: nil))
        store.onboarded = true
    }
}
