import SwiftUI

// Onboarding — the seven-page journey (ONBOARDING_V33_EXPERIENCE_REFINEMENT, with Page 2 from
// ONBOARDING_V34_PAGE2_ATHLETIC_ROSTER). Shown where CyProduct.redesign is on.
//
//   1 About you · 2 What do you train? (Athletic Roster) · 3 What are you aiming for? · 4 Build your week ·
//   5 Connect and calibrate · 6 Athlete Evolution · 7 Athletic Blueprint (approval creates plan version 1)
//
// ONE MODEL. Every answer goes through OnboardingAnswers.apply into the one profile, and reading, writing, the week
// preview and approval are the shared OnboardingFlow functions — the same ones the five-stage screen uses. The goal,
// week, device and FTP controls are the app's existing editors.
//
// STANDING OF THE DESIGN. The seven-page structure is the current direction and Page 2 is the selected baseline; the
// VISUAL design of pages 1 and 3–7 is not approved, so their look here is provisional. Pages 1 and 4–7 are drawn to
// the v3.3 reference sheets (Y1, Y4, Y5) in OnboardingV34Pages.swift.
//
// NOT BUILT, AND NOT PRETENDED
// • Sport per session, a length per day and the recovery reminder (Page 4): they need stored fields that do not
//   exist. The week is built in the stored terms — cycling, strength, both, rest — with one ride length and one
//   strength length for the week.
// • The "approved" state of the Blueprint with an Open Home button (sheet Y5, B3): approval opens Home directly.
// • Athlete Evolution stages (Page 6): no stage criteria are approved. The page shows the honest "establishing your
//   baseline" state and names no stage.
// • Activities without a stored identifier (walking, bodyweight, mobility, breathing, sauna) are listed as coming
//   later and cannot be chosen.

struct OnboardingV34View: View {
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var health: HealthAccess
    @State private var page = 0                 // 0 = welcome, 1…7
    /// Welcome only: how far the hold-to-start ring has filled (0…1), whether a finger is down, and whether the
    /// screen is dissolving away after a completed hold.
    @State private var holdProgress: CGFloat = 0
    @State private var holding = false
    @State private var welcomeLeaving = false
    /// True once Build your week has been shown in this run of onboarding.
    @State private var sawWeek = false
    /// About you: why a typed weight or height is not accepted (shown above Continue).
    @State private var aboutIssue: String? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var a = OnboardingAnswers()
    @State private var ftpKnown = false
    @State private var ftpText = ""
    @State private var resumed = false
    @State private var library = false
    /// A group of the Blueprint was tapped: this page was opened from page 7 and its button returns there.
    @State private var fromBlueprint = false
    /// Counts requests to bring the page back to its top (page 5, when the FTP keyboard closes).
    @State private var toTop = 0
    private static let topID = "onbPageTop"
    @EnvironmentObject private var hub: SensorHub
    @Environment(\.cyTheme) private var theme
    @Environment(\.dynamicTypeSize) private var dts
    static let pages = 7
    /// Stored as 201…207 so a reopened setup returns to its page (the five-stage screen uses 101…105).
    private static let stageBase = 200

    /// The roster: selected activity identifiers in roster order (first = main sport).
    private var sports: [String] { a.activities ?? [] }
    private var roster: AthleticRoster.Page { AthleticRoster.view(sports) }
    private var mode: TrainingMode { a.mode ?? store.profile.trainingMode }

    var body: some View {
        NavigationStack {
            Group {
            if page == 0 { welcomeScreen } else {
            VStack(spacing: 0) {
                rail
                // Simulator run 17: all pages share this one scroll view, which kept its position from page to page and
                // after the keyboard, so a page could rest with its title under the rail. Every page now opens at its top.
                ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: CySpace.l) {
                        switch page {
                        case 1: pageAbout
                        case 2: pageRoster
                        case 3: pageGoals
                        case 4: pageWeek
                        case 5: pageConnect
                        case 6: pageEvolution
                        default: pageBlueprint
                        }
                    }
                    .padding(.horizontal, CySpace.l).padding(.top, CySpace.s).padding(.bottom, CySpace.xl)
                    .frame(maxWidth: CyTheme.maxContentWidth).frame(maxWidth: .infinity)
                    .id(Self.topID)
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: page) { _, _ in proxy.scrollTo(Self.topID, anchor: .top) }
                .onChange(of: toTop) { _, _ in withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(Self.topID, anchor: .top) } }
                }
                bottom
            }
            .transition(.opacity)
            }
            }
            .background(theme.background.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .onAppear(perform: resume)
            .onChange(of: a) { _, _ in OnboardingFlow.commit(a, to: store) }
            .onChange(of: page) { _, p in store.onboardingStage = p == 0 ? 0 : Self.stageBase + p; if p >= 4 && p < Self.pages { sawWeek = true } }
            .sheet(isPresented: $library) { RosterLibrarySheet(sports: sportsBinding).cyThemeRoot() }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("onboardingV34")
    }

    // MARK: state

    private func resume() {
        guard !resumed else { return }
        resumed = true
        let s = store.onboardingStage
        page = s > Self.stageBase ? min(Self.pages, s - Self.stageBase) : 0
        let r = OnboardingFlow.storedAnswers(store, pastFirstStage: page >= 3)
        var x = r.answers
        // the roster is the stored sports list once the athlete has been on Page 2; before that nothing is preselected
        if page >= 2 { x.activities = AthleticRoster.roster(of: store.profile) }
        // Build your week: a saved schedule is shown as it was left; a new athlete has none and starts with seven rest days
        x.schedule = OnboardingFlow.storedSchedule(store)
        // the training environment and every environment's own equipment selection, as saved
        x.equipmentSets = store.profile.equipmentSets
        x.environment = store.profile.equipmentEnvironment.flatMap(EquipmentEnvironment.init(rawValue:)) ?? EquipmentEnvironment.of(store.equipment)
        if let env = x.environment, x.equipmentSets?[env.rawValue] == nil, store.equipment.isSet {
            // an athlete whose equipment was set before environments existed keeps exactly what they had
            var sets = x.equipmentSets ?? [:]; sets[env.rawValue] = store.equipment.owned.map(EquipmentProfile.normalised).sorted(); x.equipmentSets = sets
        }
        x.equipment = nil
        a = x
        ftpKnown = r.ftpKnown
        if let w = r.ftpWatts { ftpText = String(w) }
    }

    /// Every roster change also sets the stored training type and lead that the roster means.
    private var sportsBinding: Binding<[String]> {
        Binding(get: { sports }, set: { new in setSports(new) })
    }
    private func setSports(_ new: [String]) {
        var x = a
        x.activities = AthleticRoster.unique(new)
        let m = AthleticRoster.view(new).mode
        x.mode = m
        x.priority = m == .hybrid ? (a.priority ?? .balanced) : nil
        if let s = x.schedule {
            // the chosen week keeps every session whose activity is still in the roster; nothing is put in place of the others
            let kept = ChosenWeek.normalised(s.map { $0.filter { (x.activities ?? []).contains($0.activity) } })
            x.schedule = kept
            x.week = ChosenWeek.kinds(kept)
        } else if x.mode != a.mode { x.week = nil }
        a = x
        // goals of a sport that left the roster go with it; the others, and the main goal if it survives, stay
        if a.goalIDs != nil || a.goals != nil {
            var sel = goalSelection
            sel.keep(offered: RosterGoals.groups(roster: x.activities ?? []))
            if sel != goalSelection { setGoals(sel) }
        }
    }
    /// All selected goals in the order chosen, with the one main goal.
    private var goalSelection: RosterGoals.Selection {
        var sel = RosterGoals.Selection(ids: a.goalIDs ?? (a.goals ?? []).map(\.rawValue), main: a.mainGoalID ?? a.primaryGoal?.rawValue)
        if let m = sel.main, !sel.ids.contains(m) { sel.main = sel.ids.first } else if sel.main == nil { sel.main = sel.ids.first }
        return sel
    }
    /// Writes a selection: the full list and main goal, and — for the planner, unchanged fields — its own goals.
    private func setGoals(_ sel: RosterGoals.Selection) {
        var x = a
        x.goalIDs = sel.ids; x.mainGoalID = sel.main
        x.goals = sel.plannerGoals; x.primaryGoal = sel.plannerMain
        a = x
    }

    private var canContinue: Bool {
        switch page {
        // owner decision 20 Nov 2026, 18:24: a new athlete gives all four — name, date of birth, weight, height
        case 1: return aboutIssue == nil && BodyMeasure.aboutYouComplete(name: a.name, dateOfBirth: a.dateOfBirth, weightKg: a.weightKg, heightCm: a.heightCm)
        // 21 Nov 2026: any roster continues to Goals; cycling and gym training are not a condition of having a roster
        case 2: return !roster.isEmpty
        // Every athlete continues with at least one goal (owner decision 21 Nov 2026). Whether a plan is built is decided
        // by `planPossible`; without one the athlete goes straight to a profile-only Blueprint.
        case 3: return !goalSelection.ids.isEmpty
        // 21 Nov 2026, 21:18: the week starts as seven rest days; Continue needs at least one valid training day
        // (22:22: any one valid session is enough — a cycling-and-strength athlete need not schedule both)
        case 4: return !ChosenWeek.feasibility(a.schedule ?? ChosenWeek.empty, strengthLevel: a.strengthLevel).blocking
        default: return true
        }
    }
    private var proposedWeek: [DayKind] {
        OnboardingWeek.propose(mode: mode, cyclingLevel: a.cyclingLevel ?? .intermediate, strengthLevel: a.strengthLevel, priority: a.priority ?? .balanced)
    }
    /// A training plan can be built: a planned activity in the roster and a goal its planner knows, chosen by the athlete.
    /// Once the athlete has chosen a week, it must also hold a session of a sport Cyclift plans — their schedule is the
    /// planner's input, and cycling or strength is never substituted for the days they chose.
    private var planPossible: Bool {
        guard RosterGoals.canPlan(roster: sports, selection: goalSelection) else { return false }
        return a.schedule.map { ChosenWeek.hasPlannable($0) } ?? true
    }


    private func next() {
        // Every athlete builds their week (21 Nov 2026, 21:18). Profile-only: nothing chosen can be planned today, so
        // Connect and calibrate and Athlete Evolution, which describe a plan, are passed over; the Blueprint says what is saved.
        if page == 4, !planPossible { page = Self.pages; return }
        if page == 3 {
            // what is shown on screen is the answer (the level chips start on the stored level)
            if a.cyclingLevel == nil, mode.includesCycling { a.cyclingLevel = store.profile.level }
            if a.strengthLevel == nil, mode.includesLifting { a.strengthLevel = store.strengthPrefs.experience ?? .beginner }
        }
        page = min(Self.pages, page + 1)
    }

    // MARK: blueprint rail — progress, summary and the way back

    private var rail: some View {
        HStack(spacing: 5) {
            Button {
                if fromBlueprint { if canContinue { backToBlueprint() } }
                else if page == Self.pages, !planPossible { page = 4 }       // the profile-only Blueprint was reached from Build your week
                else { page -= 1 }
            } label: {
                Image(systemName: "chevron.left").font(.body.weight(.semibold)).foregroundStyle(theme.textPrimary)
                    .frame(width: 36, height: CyHit.min).contentShape(Rectangle())
            }
            .buttonStyle(.plain).accessibilityLabel(fromBlueprint ? "Back to blueprint" : "Back").accessibilityIdentifier("onboardingBack")
            ForEach(1...6, id: \.self) { i in railSlot(i) }
            Text("\(page) of \(Self.pages)").font(CyFont.caption).monospacedDigit().foregroundStyle(theme.textSecondary)
                .lineLimit(1).fixedSize()
                .accessibilityIdentifier("onboardingProgress")
        }
        .dynamicTypeSize(...DynamicTypeSize.xLarge)
        .padding(.horizontal, CySpace.s).padding(.top, 4)
    }
    /// One slot of the blueprint rail (sheet Y1): a number until its page is finished, then the mark the page left.
    private func railSlot(_ i: Int) -> some View {
        // pages 5–6 were never visited by an athlete without a plan: they are not offered as places to go back to
        let done = i < page && (planPossible || i <= 4), here = i == page
        return Button { if done { fromBlueprint = false; page = i } } label: {
            railMark(i, done: done, here: here)
                .frame(maxWidth: .infinity).frame(height: 26)
                .background(Capsule().fill(done ? theme.surface2 : Color.clear))
                .overlay(Capsule().strokeBorder(here ? theme.textPrimary : theme.border.opacity(done ? 0 : 0.7), lineWidth: here ? 1.6 : 1))
                .frame(minHeight: CyHit.min).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!done)
        .accessibilityLabel("Page \(i), \(Self.titles[i])\(done ? ", done: \(railWords(i))" : here ? ", current" : "")")
        .accessibilityHint(done ? "Goes back to this page" : "")
        .accessibilityIdentifier("railSlot-\(i)")
    }
    @ViewBuilder private func railMark(_ i: Int, done: Bool, here: Bool) -> some View {
        if !done {
            Text("\(i)").font(.caption.weight(.bold)).foregroundStyle(here ? theme.textPrimary : theme.textTertiary)
        } else if i == 1 {
            Text(String((a.name ?? "").trimmingCharacters(in: .whitespaces).prefix(1)).uppercased())
                .font(.caption.weight(.bold)).foregroundStyle(theme.textPrimary)
        } else if i == 2 {
            HStack(spacing: 2) {
                // the athlete's own main sport(s) — a runner is never drawn as a cyclist (seen in focused check 32)
                ForEach(roster.mains.prefix(2)) { Image(systemName: Self.symbol($0)) }
            }
            .font(.caption2.weight(.semibold)).foregroundStyle(theme.textPrimary)
        } else if i == 3 {
            Image(systemName: "star.fill").font(.caption2).foregroundStyle(goalTint(a.primaryGoal ?? a.goals?.first))
        } else if i == 4 {
            railWeekBars
        } else if i == 5 {
            Text(ftpKnown ? "FTP" : "✓").font(.caption2.weight(.bold)).foregroundStyle(theme.textPrimary)
        } else {
            Image(systemName: "circle").font(.caption2.weight(.bold)).foregroundStyle(theme.textPrimary)
        }
    }
    /// The week as seven small bars: a ride, a strength day, both, or a short bar for rest.
    private var railWeekBars: some View {
        let w = ChosenWeek.normalised(a.schedule)
        func tint(_ d: [ChosenSession]) -> Color {
            guard let f = d.first.flatMap({ AthleticRoster.activity($0.activity) })?.family else { return theme.textTertiary }
            return f == .strength ? theme.strength : f == .recovery ? theme.recovery : theme.endurance
        }
        return HStack(alignment: .bottom, spacing: 2) {
            ForEach(0..<7, id: \.self) { i in
                RoundedRectangle(cornerRadius: 1)
                    .fill(tint(w[i]))
                    .frame(width: 3, height: w[i].isEmpty ? 4 : w[i].count > 1 ? 13 : 10)
            }
        }
    }
    private func goalTint(_ g: GoalID?) -> Color {
        guard let g else { return theme.textPrimary }
        return g.sport == .strength ? theme.strength : g.sport == .cycling ? theme.endurance : theme.recovery
    }
    private static let titles = ["", "About you", "What do you train?", "What are you aiming for?", "Build your week", "Connect and calibrate", "Athlete Evolution", "Athletic Blueprint"]
    private func railWords(_ i: Int) -> String {
        switch i {
        case 1: return a.name ?? ""
        case 2: return AthleticRoster.identityLine(sports, priority: a.priority)
        case 3: return "main goal \(a.primaryGoal?.title ?? a.goals?.first?.title ?? "")"
        case 4: return "\(ChosenWeek.totals(a.schedule ?? ChosenWeek.empty).trainingDays) training days"
        case 5: return ftpKnown ? "FTP entered" : "seen"
        default: return "seen"
        }
    }

    // MARK: shared chrome

    private func heading(_ n: Int, _ over: String, _ title: String, compact: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: compact ? 2 : 4) {
            (Text("0\(n)").foregroundColor(theme.accent) + Text(" · \(over.uppercased())").foregroundColor(theme.textSecondary))
                .font(CyFont.overline).tracking(1.2)
                .accessibilityLabel("Page \(n), \(over)")
            // compact (Goals, 21 Nov 2026): one line at standard text sizes so the whole page fits without scrolling
            Text(title).font(.system(compact ? .title : .largeTitle, design: .rounded).weight(.bold)).foregroundStyle(theme.textPrimary)
                .lineLimit(compact && !dts.isAccessibilitySize ? 1 : nil).minimumScaleFactor(compact ? 0.75 : 1)
                .fixedSize(horizontal: false, vertical: true).accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("onbTitle")
        }
    }
    /// The three provenance marks, in words: declared by you · Coach's proposal (rules-based) · measured evidence.
    private func provenance(_ mark: String, _ words: String) -> some View {
        HStack(spacing: 6) {
            Text(mark).font(.caption.weight(.bold)).foregroundStyle(theme.accent).accessibilityHidden(true)
            Text(words.uppercased()).font(CyFont.overline).tracking(0.8).foregroundStyle(theme.textSecondary)
        }
        .accessibilityElement(children: .combine)
    }
    private func card<V: View>(@ViewBuilder _ content: () -> V) -> some View {
        VStack(alignment: .leading, spacing: CySpace.m) { content() }
            .padding(CySpace.l).frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: CyRadius.m, style: .continuous).fill(theme.surface))
            .overlay(RoundedRectangle(cornerRadius: CyRadius.m, style: .continuous).strokeBorder(theme.cardStroke, lineWidth: theme.borderWidth))
    }

    /// Fixed zone above the button: what the answers on this page mean for the plan. Rules-based, never a guess.
    /// The mark is the provenance mark of the sheets; `strong` is the part the sheets draw in full strength.
    private struct CoachLine { var mark: String; var tint: Color; var before: String = ""; var strong: String = ""; var after: String = "" }
    private var coachLine: CoachLine {
        if fromBlueprint, page < Self.pages {
            return CoachLine(mark: "◆", tint: theme.accent, strong: "Editing from your blueprint.",
                             after: page == 4 ? " Change the week here; the button returns you to the blueprint." : " Change it here; the button returns you to the blueprint.")
        }
        switch page {
        case 1:
            // the earlier paragraph is removed (owner decision 18:24). This zone now only says what still has to be
            // entered or corrected, and is empty once the page is complete.
            if let issue = aboutIssue { return CoachLine(mark: "", tint: theme.warning, strong: issue) }
            return CoachLine(mark: "", tint: theme.textSecondary, before: BodyMeasure.aboutYouPrompt(name: a.name, dateOfBirth: a.dateOfBirth, weightKg: a.weightKg, heightCm: a.heightCm) ?? "")
        case 2:
            // Multi-sport roster (owner decision 20 Nov 2026): the line names the athlete from what was selected and
            // says truthfully what Cyclift plans and records for it today.
            guard !roster.isEmpty else { return CoachLine(mark: "", tint: theme.textSecondary, before: "Choose what you train. You can add as many activities as you like.") }
            let support = AthleticRoster.supportLine(sports) ?? ""
            if roster.mode == nil { return CoachLine(mark: "◆", tint: theme.accent, strong: AthleticRoster.identity(sports) + ". ", after: support) }
            return CoachLine(mark: "◆", tint: theme.accent, strong: AthleticRoster.identityLine(sports, priority: a.priority) + ". ", after: support)
        case 3:
            guard let g = a.primaryGoal ?? a.goals?.first else { return CoachLine(mark: "", tint: theme.textSecondary, before: "Pick at least one goal. The main goal shapes the sessions the Coach proposes.") }
            return CoachLine(mark: "◆", tint: theme.accent, strong: "Main goal: \(g.title).", after: " \(GoalInfo.effect(g))")
        case 4:
            // the athlete's chosen schedule is told apart from a generated programme, and sports without a planner are named truthfully
            let w = ChosenWeek.normalised(a.schedule)
            if ChosenWeek.totals(w).sessions == 0 { return CoachLine(mark: "", tint: theme.textSecondary, before: "Every day starts as rest. Tap a day to choose your training.") }
            let waiting = ChosenWeek.bySport(w.map { $0.filter { ChosenWeek.engine($0.activity) == nil } }).map { $0.sport.lowercased() }
            if !planPossible { return CoachLine(mark: "◆", tint: theme.accent, strong: "This is your schedule, saved as you set it.", after: " Personalized plans for your sports are coming soon.") }
            if !waiting.isEmpty { return CoachLine(mark: "◆", tint: theme.accent, strong: "Your schedule. ", after: "Cyclift plans your cycling and strength days; your \(waiting.joined(separator: " and ")) days are saved. Nothing is scheduled until you approve.") }
            return CoachLine(mark: "◆", tint: theme.accent, before: "This is your schedule; the Coach plans inside it. ", strong: "Nothing is scheduled until you approve.")
        case 5: return CoachLine(mark: "◆", tint: theme.accent, strong: "Increases to your plan are presented for your approval.",
                                 after: " Reductions that protect recovery can be applied for you if you allow it. You can review why your plan changed.")
        case 6: return CoachLine(mark: "▲", tint: theme.success, before: "Your stage is earned by ", strong: "recorded training only", after: ". Nothing you answered here can raise or lower it.")
        default:
            if !planPossible { return CoachLine(mark: "◆", tint: theme.accent, strong: "No training plan is created.", after: " Your profile, sports and goals are saved, and you can change them first.") }
            return CoachLine(mark: "◆", tint: theme.accent, strong: "Nothing is scheduled until you approve.", after: " Tap any part of the blueprint to change it first.")
        }
    }
    /// Back to the Blueprint after an edit. If the edit made a plan possible for an athlete who had none, the week has
    /// never been shown to them: they go to Build your week first, so no proposed week is approved unseen.
    private func backToBlueprint() {
        fromBlueprint = false
        page = (planPossible && !sawWeek) ? 4 : Self.pages
    }
    /// A Blueprint group opens the page it came from; that page's button returns here.
    private func editFromBlueprint(_ p: Int) { fromBlueprint = true; page = p }

    private var bottom: some View {
        let line = coachLine
        return VStack(alignment: .leading, spacing: CySpace.s) {
            if page == 3 { goalExplanation } else {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                if !line.mark.isEmpty { Text(line.mark).font(CyDyn.f(10, .bold)).foregroundStyle(line.tint).accessibilityHidden(true) }
                (Text(line.before).foregroundColor(theme.textSecondary) + Text(line.strong).fontWeight(.semibold).foregroundColor(theme.textPrimary) + Text(line.after).foregroundColor(theme.textSecondary))
                    .font(CyDyn.f(14))
                    .lineLimit(dts.isAccessibilitySize ? 6 : 3, reservesSpace: !dts.isAccessibilitySize)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .clipped()                              // Lab run 13: a long line was drawn over the page above it
                    .accessibilityIdentifier("onbCoachLine")
            }
            }
            if fromBlueprint, page < Self.pages {
                CyPrimaryButton(title: "Back to blueprint", isEnabled: canContinue, action: backToBlueprint)
                    .accessibilityIdentifier("onbBackToBlueprint")
            } else if page == Self.pages, !planPossible {
                // profile-only: nothing is approved because no plan exists; the profile is saved and the app opens
                CyPrimaryButton(title: "Create my profile") { OnboardingFlow.createProfileOnly(a, store: store) }
                    .accessibilityIdentifier("onbCreateProfile")
            } else if page == Self.pages {
                CyPrimaryButton(title: "Approve my blueprint") { OnboardingFlow.approve(a, store: store) }
                    .accessibilityIdentifier("onbCreatePlan")
            } else {
                CyPrimaryButton(title: page == 6 ? "See my blueprint" : "Continue", isEnabled: canContinue, action: next)
                    .accessibilityIdentifier("onboardingNext")
            }
        }
        .padding(.horizontal, CySpace.l).padding(.vertical, 10)
        .background(theme.background)
    }

    /// Goals page: the main-goal summary card, immediately above Continue (owner decisions 21 Nov 2026, 00:30 and 13:38;
    /// visual basis: the Build 6 card). Heading, the goal's effect on training, the training-mix bar and its legend.
    /// The bar is counted from the week the real planner proposes for these answers (`TrainingMix`); an athlete with
    /// no plan gets the truthful sentence and NO bar.
    private var goalExplanation: some View {
        let sel = goalSelection
        let e = RosterGoals.explanation(main: sel.main, roster: sports, selection: sel)
        let fam = sel.main.flatMap { RosterGoals.goal($0) }?.family
        let tint: Color = e == nil ? theme.textSecondary : fam == .strength ? theme.strength : fam == nil || fam == .recovery ? theme.recovery : theme.endurance
        let mix = e == nil ? [] : proposedMix
        return VStack(alignment: .leading, spacing: 5) {
            Text((e?.title ?? "Your main goal").uppercased()).font(CyFont.overline).tracking(0.8)
                .foregroundStyle(tint)
                .lineLimit(1).minimumScaleFactor(0.8)
                .accessibilityIdentifier("onbMainGoalTitle")
            Text(e?.text ?? "Choose one or more goals. The first is your main goal; tap a star to change it.")
                .font(CyDyn.f(13)).foregroundStyle(e == nil ? theme.textSecondary : theme.textPrimary)
                .lineLimit(dts.isAccessibilitySize ? 8 : 3)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("onbCoachLine")
            if !mix.isEmpty { mixBar(mix) }
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(e == nil ? theme.surface : tint.opacity(0.14)))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("onbGoalExplanation")
    }
    /// The mix of the week the planner proposes for the answers so far (the week chosen on page 4 once there is one).
    private var proposedMix: [TrainingMix.Share] {
        guard planPossible else { return [] }
        let kinds = a.week.flatMap { $0.count == 7 ? $0 : nil } ?? proposedWeek
        let plan = OnboardingFlow.dryRun(a, store: store, kinds: kinds, ride: a.rideMinutes ?? OnboardingWeek.defaultRideMinutes,
                                         lift: a.liftMinutes ?? OnboardingWeek.defaultLiftMinutes, weekOffset: 1)   // next week: a whole week, never a part-elapsed one
        return TrainingMix.shares(of: plan)
    }
    private func mixColor(_ p: TrainingMix.Part) -> Color {
        switch p {
        case .easyRiding: return theme.endurance.opacity(0.6)
        case .hardRiding: return theme.endurance
        case .strength: return theme.strength
        case .other: return theme.recovery
        case .rest: return theme.textTertiary.opacity(0.45)
        }
    }
    private func mixBar(_ mix: [TrainingMix.Share]) -> some View {
        let total = max(1, mix.reduce(0) { $0 + $1.count })
        return VStack(alignment: .leading, spacing: 5) {
            GeometryReader { geo in
                HStack(spacing: 2) {
                    ForEach(mix, id: \.part) { m in
                        RoundedRectangle(cornerRadius: 3).fill(mixColor(m.part))
                            .frame(width: max(4, (geo.size.width - CGFloat(2 * (mix.count - 1))) * CGFloat(m.count) / CGFloat(total)))
                    }
                }
            }
            .frame(height: 7)
            HStack(spacing: 10) {
                ForEach(mix, id: \.part) { m in
                    HStack(spacing: 4) {
                        Circle().fill(mixColor(m.part)).frame(width: 7, height: 7)
                        Text(m.part.title).font(CyDyn.f(11, .semibold)).foregroundStyle(theme.textSecondary).lineLimit(1)
                    }
                }
            }
            .minimumScaleFactor(0.8)
        }
        .padding(.top, 2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Proposed week")
        .accessibilityValue(TrainingMix.summary(mix))
        .accessibilityIdentifier("onbGoalMix")
    }

    // MARK: 0 — Welcome
    //
    // Owner's approved direction for this screen, 20 Nov 2026 ("Screen 1 final decision"): the singularity as the hero,
    // one headline, one supporting line and a circular control that is HELD for three seconds; the screen then
    // dissolves and About you appears. No logo, app name, legend or explanatory paragraph. Do not add to it.
    // Visually approved by the owner on 20 Nov 2026 (16:59) with this wording: "Your evolution starts here." /
    // "Your goals. Your training. A better you, every day." / "Hold to begin" / "Hold for 3 seconds". Do not change it.
    // What "Get started" did is kept exactly: the athlete continues without an account and page 1 opens.
    // The hero is a still image of the singularity exactly as the approved Progress design sheets draw it: produced by
    // the sheets' own drawing routine (baseline form, no generation implied), one image per theme. It does not move.
    // If an image is ever missing, the flat singularity Progress draws stands in.

    static let holdSeconds: Double = 3

    private var welcomeScreen: some View {
        GeometryReader { geo in
            ScrollView {
                VStack(spacing: 0) {
                    Spacer(minLength: 24)
                    welcomeHero(side: min(320, geo.size.width * 0.8))
                    Spacer(minLength: 28).frame(maxHeight: 44)
                    VStack(spacing: 14) {
                        Text("Your evolution starts here.")
                            .font(.system(.title, design: .rounded).weight(.semibold)).foregroundStyle(theme.textPrimary)
                            .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                            .accessibilityAddTraits(.isHeader).accessibilityIdentifier("onbWelcomeHeadline")
                        Text("Your goals. Your training. A better you, every day.")
                            .font(CyFont.body).foregroundStyle(theme.textSecondary)
                            .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("onbWelcomeLine")
                    }
                    .padding(.horizontal, CySpace.s)
                    Spacer(minLength: 32)
                    holdToStart
                    Spacer(minLength: 16).frame(maxHeight: 28)
                }
                .padding(.horizontal, CySpace.xl)
                .frame(maxWidth: CyTheme.maxContentWidth).frame(maxWidth: .infinity)
                .frame(minHeight: geo.size.height)
            }
        }
        .opacity(welcomeLeaving ? 0 : 1)
        .scaleEffect(welcomeLeaving && !reduceMotion ? 1.04 : 1)
        .blur(radius: welcomeLeaving && !reduceMotion ? 8 : 0)
        .allowsHitTesting(!welcomeLeaving)
    }

    @ViewBuilder private func welcomeHero(side: CGFloat) -> some View {
        let name = "SingularityHero-\(theme.id.rawValue)"
        Group {
            if UIImage(named: name) != nil {
                // the image carries its own soft glow to its edges; the layout reserves the body only
                Image(name).resizable().interpolation(.high).scaledToFit()
                    .frame(width: side, height: side)
                    .frame(height: side * 0.72)
            } else {
                SingularityPlaceholder(diameter: side * 0.6, detail: 1).frame(height: side * 0.72)
            }
        }
        .accessibilityHidden(true)
    }

    private var holdToStart: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle().stroke(theme.textSecondary.opacity(0.28), lineWidth: 3)
                Circle().trim(from: 0, to: holdProgress)
                    .stroke(theme.accent, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Circle().fill(theme.textPrimary.opacity(holding ? 0.20 : 0.10)).padding(9)
                    .scaleEffect(holding ? 0.94 : 1)
            }
            .frame(width: 88, height: 88)
            .contentShape(Circle())
            .onLongPressGesture(minimumDuration: Self.holdSeconds, maximumDistance: 60, perform: startOnboarding) { down in
                guard !welcomeLeaving else { return }
                if down {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    withAnimation(.easeOut(duration: 0.15)) { holding = true }
                    withAnimation(.linear(duration: Self.holdSeconds)) { holdProgress = 1 }
                } else {
                    // released early: the ring empties and nothing has started
                    withAnimation(.easeOut(duration: 0.25)) { holding = false; holdProgress = 0 }
                }
            }
            VStack(spacing: 3) {
                Text("Hold to begin").font(CyFont.headline).foregroundStyle(theme.textPrimary)
                Text("Hold for 3 seconds").font(CyFont.footnote).foregroundStyle(theme.textSecondary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Hold to begin")
        .accessibilityHint("Press and hold for 3 seconds")
        .accessibilityValue(holdProgress > 0 ? "Holding" : "Not started")
        .accessibilityAddTraits(.isButton)
        // VoiceOver and Switch Control cannot hold a control for three seconds; their activation starts onboarding.
        .accessibilityAction { startOnboarding() }
        .accessibilityIdentifier("onboardingContinue")
    }

    /// The hold completed. Same effect as the earlier "Get started": continue without an account, open page 1 —
    /// after the welcome screen has dissolved.
    private func startOnboarding() {
        guard !welcomeLeaving else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        store.guest = true
        holdProgress = 1
        withAnimation(.easeOut(duration: 0.45)) { welcomeLeaving = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
            withAnimation(.easeIn(duration: 0.35)) { page = 1 }
            holding = false; holdProgress = 0; welcomeLeaving = false
        }
    }

    // MARK: 1 — About you

    private var pageAbout: some View {
        VStack(alignment: .leading, spacing: CySpace.m) {
            heading(1, "You", "About you")
            OnbAboutPage(a: $a, units: $store.settings.units, healthWeight: healthWeightOffer, entryIssue: $aboutIssue)
        }
    }
    /// A weight already read from Apple Health (with permission) is offered, never applied silently.
    private var healthWeightOffer: (kg: Double, date: Date)? {
        let p = store.profile
        guard p.provenance(.weight).source == .appleHealth, let w = p.weightKg, let d = p.provenance(.weight).recordedAt else { return nil }
        return (w, d)
    }

    // MARK: 2 — Athletic Roster

    private var pageRoster: some View {
        let v = roster
        return VStack(alignment: .leading, spacing: CySpace.l) {
            heading(2, "Sports", "What do you train?")
            if v.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Start with the sport you train most.")
                        .font(.system(.title2, design: .default).weight(.bold)).foregroundStyle(theme.textPrimary).fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("rosterEmptyHeadline")
                    Text("Add as many as you like. Each one says what Cyclift can plan and record for it today.")
                        .font(CyFont.footnote).foregroundStyle(theme.textSecondary).fixedSize(horizontal: false, vertical: true)
                }
            } else {
                VStack(alignment: .leading, spacing: CySpace.s) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(v.mains.count > 1 ? "MAIN SPORTS" : "MAIN SPORT").font(CyFont.overline).tracking(0.8).foregroundStyle(theme.textSecondary)
                            .accessibilityAddTraits(.isHeader)
                        Spacer(minLength: CySpace.s)
                        Text(AthleticRoster.identity(sports)).font(CyFont.caption).foregroundStyle(theme.textSecondary)
                            .accessibilityIdentifier("rosterIdentity")
                    }
                    ForEach(v.mains) { m in
                        mainRow(m, dimmed: v.showsLead && ((a.priority == .strength && m.planning == .cycling) || (a.priority == .cycling && m.planning == .strength)))
                    }
                    if v.showsLead {
                        CyChoiceBar(options: [(TrainingPriority.cycling, "Endurance-led"), (TrainingPriority.balanced, "Balanced"), (TrainingPriority.strength, "Strength-led")],
                                    selection: Binding(get: { a.priority ?? .balanced }, set: { a.priority = $0 }))
                            .accessibilityIdentifier("rosterLead")
                    }
                }
            }
            if !v.also.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("ALSO TRAINING").font(CyFont.overline).tracking(0.8).foregroundStyle(theme.textSecondary).accessibilityAddTraits(.isHeader)
                        Spacer(minLength: CySpace.s)
                        Text("\(v.also.count)").font(CyFont.caption).foregroundStyle(theme.textSecondary).accessibilityHidden(true)
                    }
                    .padding(.bottom, CySpace.s)
                    ForEach(v.also) { x in rosterRow(x, inRoster: true) }
                }
            }
            if !v.suggestions.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(v.isEmpty ? "CHOOSE AN ACTIVITY" : "ADD TO YOUR ROSTER")
                            .font(CyFont.overline).tracking(0.8).foregroundStyle(theme.textSecondary).accessibilityAddTraits(.isHeader)
                        Spacer(minLength: CySpace.s)
                        if !v.isEmpty { Text("suggestions").font(CyFont.caption).foregroundStyle(theme.textSecondary) }
                    }
                    .padding(.bottom, CySpace.s)
                    ForEach(v.suggestions) { x in rosterRow(x, inRoster: false) }
                }
            }
            Button { library = true } label: {
                HStack(spacing: CySpace.m) {
                    Image(systemName: "magnifyingglass").frame(width: 26).accessibilityHidden(true)
                    Text("Browse all activities").font(CyFont.headline)
                    Spacer(minLength: 0)
                    Text("search · categories").font(CyFont.footnote).foregroundStyle(theme.textSecondary)
                    Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(theme.textSecondary).accessibilityHidden(true)
                }
                .foregroundStyle(theme.textPrimary)
                .frame(maxWidth: .infinity, minHeight: 52)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("rosterBrowse")
        }
    }

    private func mainRow(_ x: RosterActivity, dimmed: Bool) -> some View {
        HStack(alignment: .center, spacing: CySpace.m) {
            Image(systemName: Self.symbol(x)).font(.body.weight(.semibold))
                .foregroundStyle(x.domain == .strength ? theme.strength : theme.endurance).frame(width: 26).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(x.title).font(.system(.title2, design: .default).weight(.bold))
                    .foregroundStyle(dimmed ? theme.textSecondary : theme.textPrimary).fixedSize(horizontal: false, vertical: true)
                // an activity Cyclift cannot plan says so under its name, also when it is the main sport
                if x.planning == nil {
                    Text("\(x.capability.mark) \(x.capabilityWords)").font(CyFont.footnote).foregroundStyle(theme.textSecondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(x.title). \(x.capabilityWords). Main sport")
            Spacer(minLength: CySpace.s)
            removeButton(x)
        }
        .frame(minHeight: CyHit.min)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("rosterMain-\(x.id)")
    }

    private func rosterRow(_ x: RosterActivity, inRoster: Bool) -> some View {
        HStack(spacing: CySpace.s) {
            if inRoster {
                Image(systemName: Self.symbol(x)).foregroundStyle(theme.textSecondary).frame(width: 26).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) { rowText(x) }
                Spacer(minLength: CySpace.s)
                // any selected activity can be the main sport; nothing else is removed
                Button("Make main") { setSports(AthleticRoster.makingMain(x.id, in: sports)) }
                    .font(CyFont.caption.weight(.semibold)).foregroundStyle(theme.accent)
                    .frame(minHeight: CyHit.min).contentShape(Rectangle()).buttonStyle(.plain)
                    .accessibilityLabel("Make \(x.title) the main sport")
                    .accessibilityIdentifier("rosterMakeMain-\(x.id)")
                removeButton(x)
            } else {
                Button { setSports(AthleticRoster.adding(x.id, to: sports)) } label: {
                    HStack(spacing: CySpace.m) {
                        Image(systemName: Self.symbol(x)).foregroundStyle(theme.textSecondary).frame(width: 26).accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) { rowText(x) }
                        Spacer(minLength: CySpace.s)
                        Image(systemName: "plus").font(.footnote.weight(.bold)).foregroundStyle(theme.textPrimary)
                            .frame(width: 30, height: 30).background(Circle().fill(theme.surface2)).accessibilityHidden(true)
                    }
                    .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Add \(x.title). \(x.capabilityWords)")
                .accessibilityIdentifier("rosterAdd-\(x.id)")
            }
        }
        .frame(minHeight: 52)
        .overlay(alignment: .bottom) { Rectangle().fill(theme.separator).frame(height: 1).accessibilityHidden(true) }
    }
    /// A plain symbol per activity (sheet Z2 draws one beside every row). Decorative: the name is always written.
    private static func symbol(_ x: RosterActivity) -> String { x.symbol }      // one mapping for every screen (AthleticRoster.swift)
    @ViewBuilder private func rowText(_ x: RosterActivity) -> some View {
        Text(x.title).font(CyFont.headline).foregroundStyle(theme.textPrimary).fixedSize(horizontal: false, vertical: true)
        Text("\(x.capability.mark) \(x.capabilityWords)").font(CyFont.footnote).foregroundStyle(theme.textSecondary).fixedSize(horizontal: false, vertical: true)
    }
    private func removeButton(_ x: RosterActivity) -> some View {
        Button { setSports(AthleticRoster.removing(x.id, from: sports)) } label: {
            Image(systemName: "xmark").font(.footnote.weight(.bold)).foregroundStyle(theme.textSecondary)
                .frame(width: CyHit.min, height: CyHit.min).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Remove \(x.title)")
        .accessibilityIdentifier("rosterRemove-\(x.id)")
    }

    // MARK: 3 — Goals, then level

    // Owner decision of 21 Nov 2026 (00:30): the Build 6 goal cards — an icon, the goal and what it means, tinted when
    // chosen, a star for the main goal — made compact so the whole page fits one iPhone 15 Pro screen at standard
    // text size (it scrolls at larger sizes). The groups follow the roster. The balance question is NOT asked here:
    // Screen 3 owns it and the stored answer is used unchanged. Levels are asked only for the sports the planner plans.
    private var pageGoals: some View {
        let groups = RosterGoals.groups(roster: sports)
        return VStack(alignment: .leading, spacing: 10) {
            heading(3, "Goals", "What are you aiming for?", compact: true)
            ForEach(groups) { group in
                VStack(alignment: .leading, spacing: 5) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("\(group.title.uppercased()) GOALS").font(CyFont.overline).tracking(0.8).foregroundStyle(theme.textSecondary).accessibilityAddTraits(.isHeader)
                        if !group.planned {
                            Text("· saved · plans coming soon").font(CyFont.caption).foregroundStyle(theme.textSecondary)
                                .accessibilityIdentifier("goalGroupSavedOnly-\(group.family?.rawValue ?? "general")")
                        }
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("goalGroup-\(group.family?.rawValue ?? "general")")
                    // two to a row; an odd last goal takes half the width beside an empty place
                    let pairs = stride(from: 0, to: group.goals.count, by: 2).map { Array(group.goals[$0..<min($0 + 2, group.goals.count)]) }
                    VStack(spacing: 6) {
                        ForEach(Array(pairs.enumerated()), id: \.offset) { row in
                            HStack(spacing: 6) {
                                ForEach(row.element) { g in goalCard(g, planned: group.planned) }
                                if row.element.count == 1 { Color.clear.frame(maxWidth: .infinity, maxHeight: 1).accessibilityHidden(true) }
                            }
                        }
                    }
                }
            }
            if roster.mainEndurance != nil || roster.mainStrength != nil {
                HStack(spacing: CySpace.s) {
                    if roster.mainEndurance != nil {
                        levelMenu("Cycling level", id: "onbCyclingLevel", options: RiderProfile.Level.allCases.map { ($0, ProfileText.level($0)) },
                                  selection: Binding(get: { a.cyclingLevel ?? store.profile.level }, set: { a.cyclingLevel = $0 }))
                    }
                    if roster.mainStrength != nil {
                        levelMenu("Strength level", id: "onbStrengthLevel", options: StrengthPrefs.Experience.allCases.map { ($0, ProfileText.strengthLevel($0)) },
                                  selection: Binding(get: { a.strengthLevel ?? store.strengthPrefs.experience ?? .beginner }, set: { a.strengthLevel = $0 }))
                    }
                }
            }
        }
    }
    /// A level the planner needs, as one compact native menu ("Cycling level  Intermediate ▾").
    private func levelMenu<T: Hashable>(_ title: String, id: String, options: [(T, String)], selection: Binding<T>) -> some View {
        let current = options.first { $0.0 == selection.wrappedValue }?.1 ?? ""
        return Menu {
            Picker(title, selection: selection) { ForEach(Array(options.enumerated()), id: \.offset) { o in Text(o.element.1).tag(o.element.0) } }
        } label: {
            VStack(alignment: .leading, spacing: 1) {
                Text(title.uppercased()).font(CyFont.overline).tracking(0.6).foregroundStyle(theme.textSecondary).lineLimit(1).minimumScaleFactor(0.8)
                HStack(spacing: 4) {
                    Text(current).font(CyDyn.f(14, .semibold)).foregroundStyle(theme.textPrimary).lineLimit(1).minimumScaleFactor(0.8)
                    Image(systemName: "chevron.down").font(.caption2.weight(.bold)).foregroundStyle(theme.textSecondary)
                }
            }
            .padding(.horizontal, 11).padding(.vertical, 5)
            .frame(maxWidth: .infinity, minHeight: CyHit.min, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(theme.surface))
            .contentShape(Rectangle())
        }
        .accessibilityLabel("\(title), \(current)")
        .accessibilityIdentifier(id)
    }
    /// One goal card (Build 6 design, compact): icon box, title and meaning; chosen = tinted with the sport's colour and
    /// outlined; the star, beside the card's own button, marks the one main goal and is how it is changed.
    private func goalCard(_ g: RosterGoal, planned: Bool) -> some View {
        let sel = goalSelection
        let on = sel.ids.contains(g.id), main = on && sel.main == g.id
        let tint: Color = g.family == .strength ? theme.strength : g.family == nil || g.family == .recovery ? theme.recovery : theme.endurance
        return ZStack(alignment: .trailing) {
            Button { var s = sel; s.toggle(g.id); setGoals(s) } label: {
                HStack(spacing: 8) {
                    Image(systemName: g.icon).font(.footnote.weight(.semibold)).foregroundStyle(tint)
                        .frame(width: 28, height: 28)
                        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(tint.opacity(0.16)))
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(g.title).font(CyDyn.f(15, .semibold)).foregroundStyle(theme.textPrimary).lineLimit(1).minimumScaleFactor(0.8)
                        // fast check 31: "Feel better, move more" was cut to "move…" on a selected card; the star now takes
                        // less room and the line may shrink a little further before it would ever be cut
                        Text(g.line).font(CyDyn.f(11.5)).foregroundStyle(theme.textSecondary).lineLimit(dts.isAccessibilitySize ? 3 : 1).minimumScaleFactor(0.7)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.leading, 8).padding(.trailing, on ? 28 : 6).padding(.vertical, 5)
                .frame(maxWidth: .infinity, minHeight: CyHit.min, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(on ? tint.opacity(0.14) : theme.surface))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(on ? tint : theme.separator, lineWidth: on ? 1.5 : 1))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(g.title), \(g.line)\(planned ? "" : ", saved, plans coming soon")\(main ? ", main goal" : "")")
            .accessibilityAddTraits(on ? .isSelected : [])
            .accessibilityIdentifier("goal-\(g.id)")
            if on {
                Button { var s = sel; s.setMain(g.id); setGoals(s) } label: {
                    Image(systemName: main ? "star.fill" : "star").font(.caption.weight(.bold))
                        .foregroundStyle(main ? theme.background : tint)
                        .frame(width: 22, height: 22)
                        .background(Circle().fill(main ? tint : Color.clear))
                        .overlay(Circle().strokeBorder(main ? Color.clear : tint, lineWidth: 1))
                        .frame(width: 30, height: CyHit.min).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(main ? "\(g.title) is the main goal" : "Make \(g.title) the main goal")
                .accessibilityValue(main ? "Main goal" : "")
                .accessibilityIdentifier("goalStar-\(g.id)")
            }
        }
    }

    // MARK: 4 — Week

    private var pageWeek: some View {
        VStack(alignment: .leading, spacing: 10) {
            heading(4, "Week", "Build your week", compact: true)
            OnbWeekPage(a: $a, roster: sports.compactMap { AthleticRoster.activity($0) })
        }
    }

    // MARK: 5 — Connect and calibrate

    private var pageConnect: some View {
        VStack(alignment: .leading, spacing: CySpace.m) {
            heading(5, "Connect", "Connect and calibrate")
            OnbConnectPage(a: $a, ftpKnown: $ftpKnown, ftpText: $ftpText, mode: mode, onEditingEnded: { toTop += 1 })
        }
    }

    // MARK: 6 — Athlete Evolution (nothing stored; no stage is named because none is evaluated)

    private var pageEvolution: some View {
        VStack(alignment: .leading, spacing: CySpace.m) {
            heading(6, "Evolution", "Athlete Evolution")
            OnbEvolutionPage(declared: levelsLine, rides: store.rides.count, lifts: store.strength.count)
        }
    }
    /// "Intermediate rider · beginner lifter" — what the athlete declared on page 3.
    private var levelsLine: String {
        var parts: [String] = []
        if mode.includesCycling { parts.append("\(ProfileText.level(a.cyclingLevel ?? store.profile.level)) rider") }
        if mode.includesLifting, let s = a.strengthLevel ?? store.strengthPrefs.experience {
            let word = ProfileText.strengthLevel(s)
            parts.append("\(parts.isEmpty ? word : word.lowercased()) lifter")
        }
        return parts.isEmpty ? "Nothing declared yet" : parts.joined(separator: " · ")
    }

    // MARK: 7 — Athletic Blueprint

    @ViewBuilder private var pageBlueprint: some View {
        if planPossible { OnbBlueprintPage(m: blueprintModel, onEdit: editFromBlueprint) }
        else { profileBlueprint }
    }
    /// The Blueprint of an athlete without a training plan (owner decision 21 Nov 2026): who they are, every sport they
    /// selected with what Cyclift does for it today, their goals, and a plain statement that no plan is created. No
    /// week, no session and no figure appears, because none exists.
    private var profileBlueprint: some View {
        let v = roster, sel = goalSelection
        let all = v.mains + v.also
        return VStack(alignment: .leading, spacing: CySpace.l) {
            VStack(alignment: .leading, spacing: 4) {
                (Text("07").foregroundColor(theme.accent) + Text(" · ATHLETIC BLUEPRINT").foregroundColor(theme.textSecondary))
                    .font(CyFont.overline).tracking(1.2).accessibilityLabel("Page 7, Athletic Blueprint")
                Text((a.name ?? "").trimmingCharacters(in: .whitespaces)).font(.system(.largeTitle, design: .rounded).weight(.bold)).foregroundStyle(theme.textPrimary)
                    .lineLimit(2).minimumScaleFactor(0.7).accessibilityAddTraits(.isHeader).accessibilityIdentifier("onbTitle")
                Text(AthleticRoster.identity(sports)).font(CyDyn.f(15, .semibold)).foregroundStyle(theme.textSecondary)
                    .accessibilityIdentifier("blueprintIdentity")
            }
            VStack(alignment: .leading, spacing: 0) {
                blueprintGroupHeader("Your sports", edit: 2, id: "blueprintEditSports")
                ForEach(all) { x in
                    HStack(spacing: CySpace.m) {
                        Image(systemName: Self.symbol(x)).foregroundStyle(theme.textSecondary).frame(width: 26).accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(x.title + (x == v.main ? " · main" : "")).font(CyFont.headline).foregroundStyle(theme.textPrimary).fixedSize(horizontal: false, vertical: true)
                            Text(x.planning != nil ? "Planning and recording work today" : "Saved · plans coming soon")
                                .font(CyFont.footnote).foregroundStyle(theme.textSecondary).fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                    }
                    .frame(minHeight: 48)
                    .overlay(alignment: .bottom) { Rectangle().fill(theme.separator).frame(height: 1).accessibilityHidden(true) }
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("blueprintSport-\(x.id)")
                }
            }
            VStack(alignment: .leading, spacing: 0) {
                blueprintGroupHeader("Your goals", edit: 3, id: "blueprintEditGoals")
                ForEach(sel.ids.compactMap { RosterGoals.goal($0) }) { g in
                    HStack(spacing: CySpace.m) {
                        Image(systemName: sel.main == g.id ? "star.fill" : "circle.fill").font(sel.main == g.id ? .footnote : .system(size: 6))
                            .foregroundStyle(sel.main == g.id ? theme.accent : theme.textSecondary).frame(width: 26).accessibilityHidden(true)
                        Text(g.title + (g.family.map { " · " + ($0 == .walking ? "Walking" : $0 == .recovery ? "Mobility & recovery" : $0.title) } ?? "") + (sel.main == g.id ? " · main goal" : ""))
                            .font(CyFont.headline).foregroundStyle(theme.textPrimary).fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                    .frame(minHeight: 44)
                    .overlay(alignment: .bottom) { Rectangle().fill(theme.separator).frame(height: 1).accessibilityHidden(true) }
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("blueprintGoal-\(g.id)")
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("NO TRAINING PLAN YET").font(CyFont.overline).tracking(0.8).foregroundStyle(theme.textSecondary).accessibilityAddTraits(.isHeader)
                Text(all.contains { $0.planning != nil }
                     ? "Your profile, sports and goals are saved. No training plan is created, because you chose no goal for a sport Cyclift plans today. Personalized plans for your other sports are coming soon."
                     : "Your profile, sports and goals are saved. No training plan is created: personalized plans for your sports are coming soon. Nothing is scheduled for you.")
                    .font(CyFont.callout).foregroundStyle(theme.textPrimary).fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("blueprintNoPlan")
            }
        }
    }
    private func blueprintGroupHeader(_ title: String, edit page: Int, id: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title.uppercased()).font(CyFont.overline).tracking(0.8).foregroundStyle(theme.textSecondary).accessibilityAddTraits(.isHeader)
            Spacer(minLength: CySpace.s)
            Button("Change") { editFromBlueprint(page) }
                .font(CyFont.caption.weight(.semibold)).foregroundStyle(theme.accent).frame(minHeight: CyHit.min).contentShape(Rectangle()).buttonStyle(.plain)
                .accessibilityLabel("Change \(title.lowercased())").accessibilityIdentifier(id)
        }
    }
    private var blueprintModel: OnbBlueprintModel {
        let kinds = a.week.flatMap { $0.count == 7 ? $0 : nil } ?? proposedWeek
        let ride = a.rideMinutes ?? OnboardingWeek.defaultRideMinutes, lift = a.liftMinutes ?? OnboardingWeek.defaultLiftMinutes
        let plan = OnboardingFlow.dryRun(a, store: store, kinds: kinds, ride: ride, lift: lift, weekOffset: 0)
        let first = OnboardingApproach.firstWorkout(in: plan, from: Date())
            ?? OnboardingApproach.firstWorkout(in: OnboardingFlow.dryRun(a, store: store, kinds: kinds, ride: ride, lift: lift, weekOffset: 1), from: Date())
        var lines = Array(OnboardingApproach.lines(primary: a.primaryGoal, mode: mode, kinds: kinds, liftMinutes: lift, ftpKnown: store.profile.ftpKnown,
                                                   ftpWatts: store.profile.ftpValue, equipmentProvisional: store.equipment.isProvisional).prefix(2))
        if let w = first { lines.append("First session: \(w.date.formatted(.dateTime.weekday(.wide))) · \(w.displayTitle) · \(w.minutes) min.") }
        let v = roster
        let main = a.primaryGoal ?? a.goals?.first
        let others = (a.goals ?? []).filter { $0 != main }
        let chosen = a.schedule.map { ChosenWeek.plannable($0) }       // what the plan covers, with each day's own minutes
        let n = chosen.map { ChosenWeek.totals($0).sessions } ?? OnbWeekText.sessions(kinds)
        let single: String = (v.mainEndurance ?? v.mainStrength)?.title ?? ""
        let lead: String = v.mode == .hybrid ? leadWord : single
        var goalLine = ""
        if let g = main {
            goalLine = GoalInfo.line(g)
            if !others.isEmpty { goalLine += " · also " + others.map(\.title).joined(separator: ", ") }
        }
        let isStrengthGoal: Bool = main.map { $0.sport == .strength } ?? false
        let time: String = chosen.map { OnboardingWeek.durationText(ChosenWeek.totals($0).minutes) } ?? OnbWeekText.total(kinds, ride: ride, lift: lift)
        let totals: String = "\(time) · \(n) session\(n == 1 ? "" : "s")"
        return OnbBlueprintModel(
            name: (a.name ?? "").trimmingCharacters(in: .whitespaces),
            levels: levelsLine,
            lead: lead,
            identity: AthleticRoster.identityLine(sports, priority: a.priority),
            sports: blueprintSports(v),
            goalTitle: main?.title,
            goalIsStrength: isStrengthGoal,
            goalLine: goalLine,
            kinds: kinds, ride: ride, lift: lift, sessions: chosen,
            weekTotals: totals,
            proposalLines: lines,
            cells: blueprintCells(v, main: main, others: others),
            measured: measuredLine + " " + connectedLine)
    }
    private var leadWord: String {
        switch a.priority ?? .balanced { case .cycling: return "Endurance-led"; case .strength: return "Strength-led"; case .balanced: return "Balanced" }
    }
    /// The roster as the sheet's line-up: main sports filled, other planned sports outlined, interests dashed.
    private func blueprintSports(_ v: AthleticRoster.Page) -> [OnbBlueprintModel.SportMark] {
        func mark(_ x: RosterActivity, main: Bool) -> OnbBlueprintModel.SportMark {
            OnbBlueprintModel.SportMark(id: x.id, short: OnbWeekText.short(x.title), icon: Self.symbol(x),
                                        role: main ? "main" : x.capability.plannable ? "" : "interest",
                                        strength: x.domain == .strength, main: main, interest: !x.capability.plannable)
        }
        return v.mains.map { mark($0, main: true) } + v.also.map { mark($0, main: false) }
    }
    /// What the athlete declared, each with the page that changes it.
    private func blueprintCells(_ v: AthleticRoster.Page, main: GoalID?, others: [GoalID]) -> [OnbBlueprintModel.Cell] {
        var out: [OnbBlueprintModel.Cell] = []
        if let g = main { out.append(.init(id: "goals", title: "Goals", value: ([g.title + " ★"] + others.map(\.title)).joined(separator: " · "), page: 3)) }
        if v.mode == .hybrid { out.append(.init(id: "lead", title: "When time is short", value: leadWord, page: 2)) }
        if mode.includesLifting { out.append(.init(id: "equipment", title: "Equipment", value: a.environment.map { e in let n = e.selection(in: a.equipmentSets).count; return "\(e.title) · \(n == 0 ? "no equipment" : n == 1 ? "1 item" : "\(n) items")" } ?? "Not chosen", page: 4)) }
        if mode.includesCycling {
            let p = store.profile
            let value = p.ftpKnown ? "\(p.ftpValue.map { "\($0) W" } ?? "Entered") · \(p.ftpSource == .tested ? "tested" : "not tested")" : "Unknown"
            out.append(.init(id: "ftp", title: "FTP", value: value, page: 5))
        }
        out.append(.init(id: "planChanges", title: "Plan changes", value: store.settings.autoAdapt ? "Auto-apply reductions" : "Always ask me", page: 5))
        // selected activities Cyclift does not plan yet — part of the athlete's roster, not "interests" (20 Nov 2026)
        let unplanned = (v.mains + v.also).filter { !$0.capability.plannable }.map(\.title)
        if !unplanned.isEmpty { out.append(.init(id: "interests", title: "Saved · plans coming soon", value: unplanned.joined(separator: " · "), page: 2)) }
        return out
    }
    private var measuredLine: String {
        let rides = store.rides.count, lifts = store.strength.count
        return rides + lifts == 0 ? "No recorded training yet."
            : "\(rides) recorded ride\(rides == 1 ? "" : "s") · \(lifts) logged strength session\(lifts == 1 ? "" : "s")."
    }
    /// Only links that are really up are named; Lab connects to nothing and says so.
    private var connectedLine: String {
        if CycliftLab.isLab { return "Devices are switched off in Cyclift Lab." }
        let names = hub.deviceStates.values.filter { $0.state.isConnectedOrBetter }.map(\.name).sorted()
        return names.isEmpty ? "No devices connected — add them any time in Profile."
            : names.joined(separator: ", ") + (names.count == 1 ? " is connected." : " are connected.")
    }
}

// MARK: - The activity library (a sheet over Page 2)

// Sheet Z3's structure — title with Done, one search field, category tabs, plain rows with a tick circle — over the
// multi-sport catalogue (owner decision 20 Nov 2026): activities are grouped by sport, every discipline of a sport is
// listed, any of them can be selected, and each row says what Cyclift plans and records for it today.
struct RosterLibrarySheet: View {
    @Binding var sports: [String]
    @Environment(\.dismiss) private var dismiss
    @Environment(\.cyTheme) private var theme
    @State private var query = ""
    @State private var domain: RosterDomain? = nil

    private static let categories: [(RosterDomain?, String)] = [(nil, "All"), (.endurance, "Endurance"), (.strength, "Strength"), (.recovery, "Recovery")]
    private var shown: [RosterActivity] {
        let q = query.trimmingCharacters(in: .whitespaces)
        return AthleticRoster.library.filter { x in
            (domain == nil || x.domain == domain) && (q.isEmpty || x.title.localizedCaseInsensitiveContains(q) || x.family.title.localizedCaseInsensitiveContains(q))
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: CySpace.m) {
            HStack(alignment: .firstTextBaseline) {
                Text("All activities").font(.system(.title3, design: .default).weight(.bold)).foregroundStyle(theme.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: CySpace.s)
                Button("Done · \(sports.count)") { dismiss() }
                    .font(CyFont.headline).foregroundStyle(theme.accent).frame(minHeight: CyHit.min).contentShape(Rectangle())
                    .accessibilityIdentifier("libraryDone")
            }
            HStack(spacing: CySpace.s) {
                Image(systemName: "magnifyingglass").foregroundStyle(theme.textSecondary).accessibilityHidden(true)
                TextField("Search activities", text: $query)
                    .textInputAutocapitalization(.never).autocorrectionDisabled().submitLabel(.search)
                    .foregroundStyle(theme.textPrimary)
                    .accessibilityIdentifier("librarySearch")
            }
            .padding(.horizontal, CySpace.m).frame(minHeight: CyHit.min)
            .background(RoundedRectangle(cornerRadius: CyRadius.m, style: .continuous).fill(theme.surface2))
            CyChoiceBar(options: Self.categories, selection: $domain)
                .accessibilityIdentifier("libraryCategory")
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(RosterFamily.allCases, id: \.self) { fam in
                        let rows = shown.filter { $0.family == fam }
                        if !rows.isEmpty {
                            Text(fam.title.uppercased()).font(CyFont.overline).tracking(0.8).foregroundStyle(theme.textSecondary)
                                .padding(.top, CySpace.m).padding(.bottom, 4).accessibilityAddTraits(.isHeader)
                            ForEach(rows) { x in row(x) }
                        }
                    }
                    if shown.isEmpty {
                        Text("No activity matches. Nothing typed here is saved as a sport.")
                            .font(CyFont.footnote).foregroundStyle(theme.textSecondary).padding(.top, CySpace.l)
                            .accessibilityIdentifier("libraryNoMatch")
                    }
                }
                .padding(.bottom, CySpace.xl)
            }
            .scrollDismissesKeyboard(.immediately)
        }
        .padding(.horizontal, CySpace.l).padding(.top, CySpace.l)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(theme.surface.ignoresSafeArea())
        .presentationDragIndicator(.visible)
    }

    private func row(_ x: RosterActivity) -> some View {
        let on = sports.contains(x.id)
        return Button { sports = on ? AthleticRoster.removing(x.id, from: sports) : AthleticRoster.adding(x.id, to: sports) } label: {
            HStack(spacing: CySpace.m) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(x.title).font(CyFont.headline).foregroundStyle(theme.textPrimary).fixedSize(horizontal: false, vertical: true)
                    Text("\(x.capability.mark) \(x.capabilityWords)").font(CyFont.footnote).foregroundStyle(theme.textSecondary).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: CySpace.s)
                Image(systemName: on ? "checkmark.circle.fill" : "circle").font(.title3)
                    .foregroundStyle(on ? theme.accent : theme.textTertiary).accessibilityHidden(true)
            }
            .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading).contentShape(Rectangle())
            .overlay(alignment: .bottom) { Rectangle().fill(theme.separator).frame(height: 1).accessibilityHidden(true) }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(x.title). \(x.capabilityWords)").accessibilityValue(on ? "In your roster" : "Not in your roster")
        .accessibilityAddTraits(on ? .isSelected : [])
        .accessibilityIdentifier("library-\(x.id)")
    }
}
