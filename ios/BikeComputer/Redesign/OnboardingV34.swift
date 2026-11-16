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
// VISUAL design of pages 1 and 3–7 is not approved, so their look here is provisional.
//
// NOT BUILT, AND NOT PRETENDED
// • Sport per session and the recovery reminder (Page 4): they need stored fields that do not exist. The week is
//   built in the stored terms — cycling, strength, both, rest.
// • Athlete Evolution stages (Page 6): no stage criteria are approved. The page shows the honest "establishing your
//   baseline" state and names no stage.
// • Activities without a stored identifier (walking, bodyweight, mobility, breathing, sauna) are listed as coming
//   later and cannot be chosen.

struct OnboardingV34View: View {
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var health: HealthAccess
    @State private var page = 0                 // 0 = welcome, 1…7
    @State private var a = OnboardingAnswers()
    @State private var ftpKnown = false
    @State private var ftpText = ""
    @State private var resumed = false
    @State private var library = false
    @Environment(\.cyTheme) private var theme
    @Environment(\.dynamicTypeSize) private var dts
    static let pages = 7
    /// Stored as 201…207 so a reopened setup returns to its page (the five-stage screen uses 101…105).
    private static let stageBase = 200

    private var sports: [RiderProfile.Sport] { a.sports ?? [] }
    private var roster: AthleticRoster.Page { AthleticRoster.view(sports) }
    private var mode: TrainingMode { a.mode ?? store.profile.trainingMode }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if page > 0 { rail }
                ScrollView {
                    VStack(alignment: .leading, spacing: CySpace.l) {
                        switch page {
                        case 0: welcome
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
                }
                .scrollDismissesKeyboard(.interactively)
                if page > 0 { bottom }
            }
            .background(theme.background.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .onAppear(perform: resume)
            .onChange(of: a) { _, _ in OnboardingFlow.commit(a, to: store) }
            .onChange(of: page) { _, p in store.onboardingStage = p == 0 ? 0 : Self.stageBase + p }
            .sheet(isPresented: $library) { RosterLibrarySheet(sports: sportsBinding).cyThemeRoot() }
        }
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
        if page >= 2 { x.sports = AthleticRoster.unique(store.profile.sports) }
        a = x
        ftpKnown = r.ftpKnown
        if let w = r.ftpWatts { ftpText = String(w) }
    }

    /// Every roster change also sets the stored training type and lead that the roster means.
    private var sportsBinding: Binding<[RiderProfile.Sport]> {
        Binding(get: { sports }, set: { new in setSports(new) })
    }
    private func setSports(_ new: [RiderProfile.Sport]) {
        var x = a
        x.sports = AthleticRoster.unique(new)
        let m = AthleticRoster.view(new).mode
        x.mode = m
        x.priority = m == .hybrid ? (a.priority ?? .balanced) : nil
        if x.mode != a.mode { x.week = nil }      // a different training type gets a fresh proposed week
        a = x
    }

    private var canContinue: Bool {
        switch page {
        case 1: return !(a.name ?? "").trimmingCharacters(in: .whitespaces).isEmpty
        case 2: return roster.mode != nil
        case 3: return !(a.goals ?? []).isEmpty
        case 4: return !OnboardingWeek.feasibility(a.week ?? proposedWeek, mode: mode, ride: a.rideMinutes ?? OnboardingWeek.defaultRideMinutes,
                                                   lift: a.liftMinutes ?? OnboardingWeek.defaultLiftMinutes, strengthLevel: a.strengthLevel).blocking
        default: return true
        }
    }
    private var proposedWeek: [DayKind] {
        OnboardingWeek.propose(mode: mode, cyclingLevel: a.cyclingLevel ?? .intermediate, strengthLevel: a.strengthLevel, priority: a.priority ?? .balanced)
    }
    private func next() {
        if page == 3 {
            // what is shown on screen is the answer (the level chips start on the stored level)
            if a.cyclingLevel == nil, mode.includesCycling { a.cyclingLevel = store.profile.level }
            if a.strengthLevel == nil, mode.includesLifting { a.strengthLevel = store.strengthPrefs.experience ?? .beginner }
        }
        page = min(Self.pages, page + 1)
    }

    // MARK: blueprint rail — progress, summary and the way back

    private var rail: some View {
        HStack(spacing: 6) {
            Button { page -= 1 } label: {
                Image(systemName: "chevron.left").font(.body.weight(.semibold)).foregroundStyle(theme.textPrimary)
                    .frame(width: CyHit.min, height: CyHit.min).contentShape(Rectangle())
            }
            .buttonStyle(.plain).accessibilityLabel("Back").accessibilityIdentifier("onboardingBack")
            ForEach(1...6, id: \.self) { i in railSlot(i) }
            Spacer(minLength: 0)
            Text("\(page) of \(Self.pages)").font(CyFont.caption).monospacedDigit().foregroundStyle(theme.textSecondary)
                .accessibilityIdentifier("onboardingProgress")
        }
        .padding(.horizontal, CySpace.s).padding(.top, 4)
    }
    private func railSlot(_ i: Int) -> some View {
        let done = i < page, here = i == page
        return Button { if done { page = i } } label: {
            Text(done ? railMark(i) : "\(i)")
                .font(.caption.weight(.bold)).lineLimit(1).minimumScaleFactor(0.6)
                .foregroundStyle(done ? theme.textPrimary : here ? theme.accent : theme.textTertiary)
                .frame(width: 34, height: 30)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(done ? theme.surface2 : Color.clear))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(here ? theme.accent : theme.border.opacity(done ? 0 : 0.7), lineWidth: here ? 1.6 : 1))
                .frame(minWidth: 36, minHeight: CyHit.min).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!done)
        .accessibilityLabel("Page \(i), \(Self.titles[i])\(done ? ", done: \(railWords(i))" : here ? ", current" : "")")
        .accessibilityHint(done ? "Goes back to this page" : "")
        .accessibilityIdentifier("railSlot-\(i)")
    }
    private static let titles = ["", "About you", "What do you train?", "What are you aiming for?", "Build your week", "Connect and calibrate", "Athlete Evolution", "Athletic Blueprint"]
    /// The mark a finished page leaves in the rail.
    private func railMark(_ i: Int) -> String {
        switch i {
        case 1: return String((a.name ?? "").trimmingCharacters(in: .whitespaces).prefix(1)).uppercased()
        case 2: return mode == .hybrid ? "E+S" : mode == .cycling ? "E" : "S"
        case 3: return "★"
        case 4: let k = a.week ?? proposedWeek; return "\(k.filter { $0 != .rest }.count)d"
        case 5: return ftpKnown ? "FTP" : "✓"
        default: return "◎"
        }
    }
    private func railWords(_ i: Int) -> String {
        switch i {
        case 1: return a.name ?? ""
        case 2: return AthleticRoster.identityLine(sports, priority: a.priority)
        case 3: return "main goal \(a.primaryGoal?.title ?? a.goals?.first?.title ?? "")"
        case 4: let k = a.week ?? proposedWeek; return "\(k.filter { $0 != .rest }.count) training days"
        case 5: return ftpKnown ? "FTP entered" : "seen"
        default: return "seen"
        }
    }

    // MARK: shared chrome

    private func heading(_ n: Int, _ over: String, _ title: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("0\(n) · \(over.uppercased())").font(CyFont.overline).tracking(1.2).foregroundStyle(theme.textSecondary)
            Text(title).font(.system(.largeTitle, design: .rounded).weight(.bold)).foregroundStyle(theme.textPrimary)
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
    private var coachLine: String {
        switch page {
        case 1: return "Your name is used on Home. Date of birth and weight are optional: zones and W/kg need them, and nothing is assumed without them."
        case 2:
            if roster.mode == nil { return roster.hasOnlyUnsupported ? "Your interests are saved. Add a sport Cyclift can plan to continue." : "Choose the sport you train most. Your plan is built around it." }
            return "◆ \(AthleticRoster.identityLine(sports, priority: a.priority)). " + (roster.mode == .hybrid ? "Rides and strength share one week; the lead decides the mix." : "Your week is built from this sport.")
        case 3:
            guard let g = a.primaryGoal ?? a.goals?.first else { return "Pick at least one goal. The main goal shapes the sessions the Coach proposes." }
            return "◆ Main goal: \(g.title). \(GoalInfo.effect(g))"
        case 4:
            let k = a.week ?? proposedWeek, ride = a.rideMinutes ?? OnboardingWeek.defaultRideMinutes, lift = a.liftMinutes ?? OnboardingWeek.defaultLiftMinutes
            var parts: [String] = []
            if mode.includesCycling { parts.append("\(OnboardingWeek.rides(k)) rides") }
            if mode.includesLifting { parts.append("\(OnboardingWeek.lifts(k)) strength") }
            return "◆ \(parts.joined(separator: " · ")) · \(OnboardingWeek.durationText(OnboardingWeek.minutes(k, ride: ride, lift: lift))) a week. Each training day becomes one planned session."
        case 5: return "All optional. Your Coach works from what you record; increases to your plan are presented for your approval, and you can always see why a session changed."
        case 6: return "Nothing on this page is stored. Your stage will only ever come from measured training, never from what you declare."
        default: return "Approving creates your first plan from exactly these answers. You can change any of it later in Profile and Plan."
        }
    }

    private var bottom: some View {
        VStack(alignment: .leading, spacing: CySpace.s) {
            Text(coachLine).font(CyFont.footnote).foregroundStyle(theme.textSecondary)
                .lineLimit(dts.isAccessibilitySize ? 6 : 3, reservesSpace: !dts.isAccessibilitySize)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("onbCoachLine")
            if page == Self.pages {
                CyPrimaryButton(title: "Approve my plan", systemImage: "checkmark", sport: .recovery) { OnboardingFlow.approve(a, store: store) }
                    .accessibilityIdentifier("onbCreatePlan")
            } else {
                CyPrimaryButton(title: page == 5 ? "Continue — connect later in Profile if you like" : "Continue", isEnabled: canContinue, action: next)
                    .accessibilityIdentifier("onboardingNext")
            }
        }
        .padding(.horizontal, CySpace.l).padding(.vertical, 10)
        .background(theme.background)
    }

    // MARK: 0 — Welcome

    private var welcome: some View {
        VStack(alignment: .leading, spacing: CySpace.xl) {
            Spacer(minLength: 40)
            HStack(spacing: 12) { CycliftMark(size: 52); Text("Cyclift").font(.system(.largeTitle, design: .rounded).weight(.bold)).foregroundStyle(theme.textPrimary) }
            Text("Seven short pages build your Athletic Blueprint: who you are, what you train, what you aim for and the week that fits your life.")
                .font(CyFont.title).foregroundStyle(theme.textPrimary).fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 6) {
                provenance("●", "Declared by you")
                provenance("◆", "Coach's proposal (rules-based)")
                provenance("▲", "Measured evidence")
            }
            Text("About two minutes · connections optional · everything stays on this iPhone").font(CyFont.footnote).foregroundStyle(theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            CyPrimaryButton(title: "Get started", systemImage: "arrow.right") { store.guest = true; page = 1 }
                .accessibilityIdentifier("onboardingContinue")
        }
    }

    // MARK: 1 — About you

    private var pageAbout: some View {
        VStack(alignment: .leading, spacing: CySpace.l) {
            heading(1, "About you", (a.name ?? "").trimmingCharacters(in: .whitespaces).isEmpty ? "Who is training?" : (a.name ?? ""))
            provenance("●", "Declared by you")
            AthleteTypeEditor(a: $a, parts: [.name, .personal], healthWeight: healthWeightOffer, units: store.settings.units)
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
            if v.mainEndurance == nil && v.mainStrength == nil {
                Text(v.hasOnlyUnsupported ? "No planned sport yet" : "Start with the sport you train most.")
                    .font(CyFont.title).foregroundStyle(theme.textPrimary).fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("rosterEmptyHeadline")
            } else {
                VStack(alignment: .leading, spacing: CySpace.s) {
                    provenance("●", v.mainEndurance != nil && v.mainStrength != nil ? "Main sports" : "Main sport")
                    let leadStrength = a.priority == .strength
                    let mains = (leadStrength ? [v.mainStrength, v.mainEndurance] : [v.mainEndurance, v.mainStrength]).compactMap { $0 }
                    ForEach(mains) { m in mainRow(m, dimmed: v.showsLead && ((a.priority == .strength && m.domain == .endurance) || (a.priority == .cycling && m.domain == .strength))) }
                    if v.showsLead {
                        CySegmentedControl(options: [(TrainingPriority.cycling, "Endurance-led"), (TrainingPriority.balanced, "Balanced"), (TrainingPriority.strength, "Strength-led")],
                                           selection: Binding(get: { a.priority ?? .balanced }, set: { a.priority = $0 }))
                            .accessibilityIdentifier("rosterLead")
                    }
                }
            }
            if !v.also.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    provenance("●", "Also training").padding(.bottom, CySpace.s)
                    ForEach(v.also) { x in rosterRow(x, inRoster: true) }
                }
            }
            if !v.suggestions.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    Text("ADD TO YOUR ROSTER").font(CyFont.overline).tracking(0.8).foregroundStyle(theme.textSecondary).padding(.bottom, CySpace.s)
                    ForEach(v.suggestions) { x in rosterRow(x, inRoster: false) }
                }
            }
            Button { library = true } label: {
                HStack {
                    Image(systemName: "magnifyingglass").accessibilityHidden(true)
                    Text("Browse all activities").font(CyFont.label)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").font(.caption.weight(.semibold)).accessibilityHidden(true)
                }
                .foregroundStyle(theme.textPrimary)
                .padding(.horizontal, CySpace.l).frame(maxWidth: .infinity, minHeight: 52)
                .background(RoundedRectangle(cornerRadius: CyRadius.m, style: .continuous).strokeBorder(theme.border, lineWidth: 1))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("rosterBrowse")
        }
    }

    private func mainRow(_ x: RosterActivity, dimmed: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: CySpace.s) {
            VStack(alignment: .leading, spacing: 2) {
                Text(x.title).font(.system(dimmed ? .title2 : .title, design: .rounded).weight(.heavy))
                    .foregroundStyle(dimmed ? theme.textSecondary : theme.textPrimary).fixedSize(horizontal: false, vertical: true)
                Text("\(x.capability.mark) \(x.capability.words) · main \(x.domain.title.lowercased()) sport").font(CyFont.footnote).foregroundStyle(theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: CySpace.s)
            removeButton(x)
        }
        .frame(minHeight: 52)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("rosterMain-\(x.id)")
    }

    private func rosterRow(_ x: RosterActivity, inRoster: Bool) -> some View {
        HStack(spacing: CySpace.s) {
            if inRoster {
                VStack(alignment: .leading, spacing: 2) { rowText(x) }
                Spacer(minLength: CySpace.s)
                if x.capability.plannable, let s = x.sport {
                    Button("Make main") { setSports(AthleticRoster.makingMain(s, in: sports)) }
                        .font(CyFont.caption.weight(.semibold)).foregroundStyle(theme.accent)
                        .frame(minHeight: CyHit.min).contentShape(Rectangle()).buttonStyle(.plain)
                        .accessibilityLabel("Make \(x.title) the main \(x.domain.title.lowercased()) sport")
                        .accessibilityIdentifier("rosterMakeMain-\(x.id)")
                }
                removeButton(x)
            } else {
                Button { if let s = x.sport { setSports(AthleticRoster.adding(s, to: sports)) } } label: {
                    HStack(spacing: CySpace.s) {
                        VStack(alignment: .leading, spacing: 2) { rowText(x) }
                        Spacer(minLength: CySpace.s)
                        Image(systemName: "plus.circle").font(.title3).foregroundStyle(theme.accent).accessibilityHidden(true)
                    }
                    .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Add \(x.title). \(x.capability.words)")
                .accessibilityIdentifier("rosterAdd-\(x.id)")
            }
        }
        .frame(minHeight: 52)
        .overlay(alignment: .bottom) { Rectangle().fill(theme.separator).frame(height: 1).accessibilityHidden(true) }
    }
    @ViewBuilder private func rowText(_ x: RosterActivity) -> some View {
        Text(x.title).font(CyFont.headline).foregroundStyle(theme.textPrimary).fixedSize(horizontal: false, vertical: true)
        Text("\(x.capability.mark) \(x.capability.words)").font(CyFont.footnote).foregroundStyle(theme.textSecondary).fixedSize(horizontal: false, vertical: true)
    }
    private func removeButton(_ x: RosterActivity) -> some View {
        Button { if let s = x.sport { setSports(AthleticRoster.removing(s, from: sports)) } } label: {
            Image(systemName: "xmark").font(.footnote.weight(.bold)).foregroundStyle(theme.textSecondary)
                .frame(width: CyHit.min, height: CyHit.min).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Remove \(x.title)")
        .accessibilityIdentifier("rosterRemove-\(x.id)")
    }

    // MARK: 3 — Goals, then level

    private var pageGoals: some View {
        VStack(alignment: .leading, spacing: CySpace.l) {
            heading(3, "Goals", "What are you aiming for?")
            Text("Pick any. The first is your main goal — tap ★ to change it.").font(CyFont.callout).foregroundStyle(theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            GoalCardsEditor(a: $a, mode: mode)
            provenance("●", "Your experience, as you declare it")
            AthleteTypeEditor(a: $a, parts: [.experience], showsPriority: false, units: store.settings.units)
        }
    }

    // MARK: 4 — Week

    private var pageWeek: some View {
        VStack(alignment: .leading, spacing: CySpace.l) {
            heading(4, "Week", "Build your week")
            provenance("◆", "Coach's proposal (rules-based) — tap a day to change it")
            WeekBuilder(a: $a, mode: mode, preview: { k, r, l in OnboardingFlow.dryRun(a, store: store, kinds: k, ride: r, lift: l, weekOffset: 0) })
            Text("Choosing the sport of each session and a recovery reminder on rest days are not available yet: the week is planned as cycling and strength sessions.")
                .font(CyFont.footnote).foregroundStyle(theme.textTertiary).fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("onbWeekLimits")
        }
    }

    // MARK: 5 — Connect and calibrate

    private var pageConnect: some View {
        VStack(alignment: .leading, spacing: CySpace.l) {
            heading(5, "Devices", "Connect and calibrate")
            if CycliftLab.isLab {
                Text("Cyclift Lab: sensors, Apple Health and location are switched off in this demo app, so nothing can be connected here.")
                    .font(CyFont.footnote).foregroundStyle(theme.warning).fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("onbLabDevices")
            }
            provenance("▲", "Measured — from your devices")
            DeviceCardList()
            if mode.includesCycling {
                provenance("●", "Declared — your FTP, if you know it")
                OnboardingFTPCard(a: $a, ftpKnown: $ftpKnown, ftpText: $ftpText)
            }
        }
    }

    // MARK: 6 — Athlete Evolution (nothing stored; no stage is named because none is evaluated)

    private var pageEvolution: some View {
        VStack(alignment: .leading, spacing: CySpace.l) {
            heading(6, "Evolution", "Athlete Evolution")
            VStack(spacing: CySpace.s) {
                SingularityPlaceholder(diameter: 120, detail: 1).frame(height: 150).accessibilityHidden(true)
                Text("ESTABLISHING YOUR BASELINE").font(Font.system(.subheadline, design: .rounded).weight(.heavy)).tracking(2.4)
                    .foregroundStyle(theme.textPrimary).multilineTextAlignment(.center)
                    .accessibilityIdentifier("onbEvolutionState")
            }
            .frame(maxWidth: .infinity)
            card {
                provenance("●", "Declared")
                Text(declaredLine).font(CyFont.callout).foregroundStyle(theme.textPrimary).fixedSize(horizontal: false, vertical: true)
            }
            card {
                provenance("▲", "Measured")
                Text(measuredLine).font(CyFont.callout).foregroundStyle(theme.textPrimary).fixedSize(horizontal: false, vertical: true)
            }
            card {
                Text("STAGE").font(CyFont.overline).tracking(0.8).foregroundStyle(theme.textSecondary)
                Text("No stage yet. Cyclift does not evaluate stages in this version, and what you declare never sets one.")
                    .font(CyFont.callout).foregroundStyle(theme.textPrimary).fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("onbEvolutionStage")
            }
        }
    }
    private var declaredLine: String {
        var parts: [String] = []
        if mode.includesCycling { parts.append("Cycling: \((a.cyclingLevel ?? store.profile.level).rawValue)") }
        if mode.includesLifting, let s = a.strengthLevel ?? store.strengthPrefs.experience { parts.append("Strength: \(s.rawValue)") }
        return parts.isEmpty ? "Nothing declared yet." : parts.joined(separator: " · ") + ". Used to size your first weeks only."
    }
    private var measuredLine: String {
        let rides = store.rides.count, lifts = store.strength.count
        return rides + lifts == 0 ? "Nothing measured yet. Evidence builds from the sessions you record."
            : "\(rides) recorded ride\(rides == 1 ? "" : "s") · \(lifts) logged strength session\(lifts == 1 ? "" : "s")."
    }

    // MARK: 7 — Athletic Blueprint

    private var pageBlueprint: some View {
        let kinds = a.week.flatMap { $0.count == 7 ? $0 : nil } ?? proposedWeek
        let ride = a.rideMinutes ?? OnboardingWeek.defaultRideMinutes, lift = a.liftMinutes ?? OnboardingWeek.defaultLiftMinutes
        let plan = OnboardingFlow.dryRun(a, store: store, kinds: kinds, ride: ride, lift: lift, weekOffset: 0)
        let first = OnboardingApproach.firstWorkout(in: plan, from: Date())
            ?? OnboardingApproach.firstWorkout(in: OnboardingFlow.dryRun(a, store: store, kinds: kinds, ride: ride, lift: lift, weekOffset: 1), from: Date())
        let lines = OnboardingApproach.lines(primary: a.primaryGoal, mode: mode, kinds: kinds, liftMinutes: lift, ftpKnown: store.profile.ftpKnown,
                                             ftpWatts: store.profile.ftpValue, equipmentProvisional: store.equipment.isProvisional)
        return VStack(alignment: .leading, spacing: CySpace.l) {
            heading(7, "Blueprint", "Athletic Blueprint")
            VStack(alignment: .leading, spacing: 4) {
                Text(AthleticRoster.identityLine(sports, priority: a.priority)).font(CyFont.headline).foregroundStyle(theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("blueprintIdentity")
                if let g = a.primaryGoal ?? a.goals?.first {
                    Text("★ \(g.title)").font(CyFont.callout).foregroundStyle(theme.textSecondary).accessibilityLabel("Main goal: \(g.title)")
                }
            }
            // ◆ the proposal
            Button { page = 4 } label: {
                card {
                    provenance("◆", "Coach's proposal (rules-based) · week 1")
                    CyCalendarStrip(days: (0..<7).map { i in
                        let s: CyDaySport = { switch kinds[i] { case .ride: return .cycling; case .lift: return .strength; case .both: return .both; case .rest: return .rest } }()
                        return CyDay(id: i, shortName: WeeklyAvailability.dayNames[i], longName: WeeklyAvailability.longDayNames[i], sport: s, status: s == .rest ? .none : .planned)
                    })
                    .allowsHitTesting(false)
                    Text(weekTotals(kinds, ride: ride, lift: lift)).font(CyFont.label).foregroundStyle(theme.textPrimary).fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("blueprintWeekTotals")
                    if let w = first {
                        Text("First session: \(w.date.formatted(.dateTime.weekday(.wide))) · \(w.displayTitle) · \(w.minutes) min")
                            .font(CyFont.footnote).foregroundStyle(theme.textSecondary).fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("blueprintFirst")
                    }
                    ForEach(Array(lines.enumerated()), id: \.offset) { pair in
                        Text("\(pair.offset + 1). \(pair.element)").font(CyFont.footnote).foregroundStyle(theme.textSecondary).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .buttonStyle(.plain).accessibilityHint("Opens Build your week").accessibilityIdentifier("blueprintProposal")
            // ● declared
            Button { page = 3 } label: {
                card {
                    provenance("●", "Declared by you")
                    Text(declaredSummary).font(CyFont.callout).foregroundStyle(theme.textPrimary).fixedSize(horizontal: false, vertical: true)
                }
            }
            .buttonStyle(.plain).accessibilityHint("Opens your goals and experience").accessibilityIdentifier("blueprintDeclared")
            // ▲ measured
            Button { page = 5 } label: {
                card {
                    provenance("▲", "Measured evidence")
                    Text(measuredLine).font(CyFont.callout).foregroundStyle(theme.textPrimary).fixedSize(horizontal: false, vertical: true)
                    Text(connectedLine).font(CyFont.footnote).foregroundStyle(theme.textSecondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            .buttonStyle(.plain).accessibilityHint("Opens Connect and calibrate").accessibilityIdentifier("blueprintMeasured")
        }
    }
    private func weekTotals(_ k: [DayKind], ride: Int, lift: Int) -> String {
        var parts: [String] = []
        if mode.includesCycling { parts.append("\(OnboardingWeek.rides(k)) rides") }
        if mode.includesLifting { parts.append("\(OnboardingWeek.lifts(k)) strength") }
        parts.append(OnboardingWeek.durationText(OnboardingWeek.minutes(k, ride: ride, lift: lift)) + " planned")
        return parts.joined(separator: " · ")
    }
    private var declaredSummary: String {
        var parts: [String] = []
        if let g = a.goals, !g.isEmpty { parts.append("Goals: " + g.map(\.title).joined(separator: ", ")) }
        if mode.includesCycling { parts.append("Cycling experience: \((a.cyclingLevel ?? store.profile.level).rawValue)") }
        if mode.includesLifting, let s = a.strengthLevel ?? store.strengthPrefs.experience { parts.append("Strength experience: \(s.rawValue)") }
        if mode.includesCycling { parts.append(store.profile.ftpKnown ? "FTP: \(store.profile.ftpValue.map { "\($0) W" } ?? "entered")" : "FTP: unknown — rides use heart rate and effort") }
        parts.append(a.weightKg == nil ? "Weight: not given" : "Weight: given")
        return parts.joined(separator: "\n")
    }
    private var connectedLine: String {
        let n = store.settings.enabledConnections.count + (health.workoutWriteAuthorized ? 1 : 0)
        return n == 0 ? "No devices connected — add them any time in Profile." : "\(n) connection\(n == 1 ? "" : "s") set up."
    }
}

// MARK: - The activity library (a sheet over Page 2)

struct RosterLibrarySheet: View {
    @Binding var sports: [RiderProfile.Sport]
    @Environment(\.dismiss) private var dismiss
    @Environment(\.cyTheme) private var theme
    @State private var query = ""
    @State private var domain: RosterDomain? = nil

    private var shown: [RosterActivity] {
        AthleticRoster.library.filter { x in
            (domain == nil || x.domain == domain) && (query.trimmingCharacters(in: .whitespaces).isEmpty || x.title.localizedCaseInsensitiveContains(query.trimmingCharacters(in: .whitespaces)))
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Category", selection: $domain) {
                        Text("All").tag(RosterDomain?.none)
                        ForEach(RosterDomain.allCases, id: \.self) { d in Text(d.title).tag(RosterDomain?.some(d)) }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("libraryCategory")
                }
                .listRowBackground(Color.clear)
                ForEach(RosterCapability.allCases, id: \.rawValue) { cap in
                    let rows = shown.filter { $0.capability == cap }
                    if !rows.isEmpty {
                        Section("\(cap.mark) \(cap.words)") {
                            ForEach(rows) { x in row(x) }
                        }
                    }
                }
                if shown.isEmpty {
                    Text("No activity matches. Nothing typed here is saved as a sport.").font(CyFont.footnote).foregroundStyle(theme.textSecondary)
                }
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search activities")
            .navigationTitle("All activities").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done · \(sports.count)") { dismiss() }.accessibilityIdentifier("libraryDone") } }
        }
    }

    @ViewBuilder private func row(_ x: RosterActivity) -> some View {
        if let s = x.sport, x.capability.selectable {
            let on = sports.contains(s)
            Button { sports = on ? AthleticRoster.removing(s, from: sports) : AthleticRoster.adding(s, to: sports) } label: {
                HStack {
                    Text(x.title).foregroundStyle(theme.textPrimary)
                    Spacer(minLength: 8)
                    Image(systemName: on ? "checkmark.circle.fill" : "circle").foregroundStyle(on ? theme.accent : theme.textTertiary).accessibilityHidden(true)
                }
                .frame(minHeight: CyHit.min).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(x.title).accessibilityValue(on ? "In your roster" : "Not in your roster")
            .accessibilityAddTraits(on ? .isSelected : [])
            .accessibilityIdentifier("library-\(x.id)")
        } else {
            // known, but the app cannot store it yet: shown so the athlete sees it is coming, never selectable
            HStack {
                Text(x.title).foregroundStyle(theme.textSecondary)
                Spacer(minLength: 8)
                Text("Coming later").font(CyFont.caption).foregroundStyle(theme.textTertiary)
            }
            .frame(minHeight: CyHit.min)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(x.title). Coming later, cannot be chosen yet")
            .accessibilityIdentifier("library-\(x.id)")
        }
    }
}
