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

    private var sports: [RiderProfile.Sport] { a.sports ?? [] }
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
            .onChange(of: page) { _, p in store.onboardingStage = p == 0 ? 0 : Self.stageBase + p }
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
        HStack(spacing: 5) {
            Button { if !fromBlueprint { page -= 1 } else if canContinue { backToBlueprint() } } label: {
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
        let done = i < page, here = i == page
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
                if mode.includesCycling { Image(systemName: "bicycle") }
                if mode.includesLifting { Image(systemName: "dumbbell") }
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
        let k = a.week.flatMap { $0.count == 7 ? $0 : nil } ?? proposedWeek
        return HStack(alignment: .bottom, spacing: 2) {
            ForEach(0..<7, id: \.self) { i in
                RoundedRectangle(cornerRadius: 1)
                    .fill(k[i] == .rest ? theme.textTertiary : k[i] == .lift ? theme.strength : theme.endurance)
                    .frame(width: 3, height: k[i] == .rest ? 4 : k[i] == .both ? 13 : 10)
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
        case 4: let k = a.week ?? proposedWeek; return "\(k.filter { $0 != .rest }.count) training days"
        case 5: return ftpKnown ? "FTP entered" : "seen"
        default: return "seen"
        }
    }

    // MARK: shared chrome

    private func heading(_ n: Int, _ over: String, _ title: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            (Text("0\(n)").foregroundColor(theme.accent) + Text(" · \(over.uppercased())").foregroundColor(theme.textSecondary))
                .font(CyFont.overline).tracking(1.2)
                .accessibilityLabel("Page \(n), \(over)")
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
    /// The mark is the provenance mark of the sheets; `strong` is the part the sheets draw in full strength.
    private struct CoachLine { var mark: String; var tint: Color; var before: String = ""; var strong: String = ""; var after: String = "" }
    private var coachLine: CoachLine {
        if fromBlueprint, page < Self.pages {
            return CoachLine(mark: "◆", tint: theme.accent, strong: "Editing from your blueprint.",
                             after: page == 4 ? " Change the week here; the button returns you to the blueprint." : " Change it here; the button returns you to the blueprint.")
        }
        switch page {
        case 1: return CoachLine(mark: "●", tint: theme.textPrimary, before: "Only your name is needed. ", strong: "Nothing is estimated from blanks", after: " — a missing weight stays unknown.")
        case 2:
            if roster.mode == nil { return CoachLine(mark: "", tint: theme.textSecondary, before: roster.hasOnlyUnsupported ? "Your interests are saved. Add a sport Cyclift can plan to continue." : "Choose the sport you train most. Your plan is built around it.") }
            return CoachLine(mark: "◆", tint: theme.accent, before: "\(AthleticRoster.identityLine(sports, priority: a.priority)). " + (roster.mode == .hybrid ? "Rides and strength share one week; the lead decides the mix." : "Your week is built from this sport."))
        case 3:
            guard let g = a.primaryGoal ?? a.goals?.first else { return CoachLine(mark: "", tint: theme.textSecondary, before: "Pick at least one goal. The main goal shapes the sessions the Coach proposes.") }
            return CoachLine(mark: "◆", tint: theme.accent, strong: "Main goal: \(g.title).", after: " \(GoalInfo.effect(g))")
        case 4:
            let k = a.week ?? proposedWeek
            if OnboardingWeek.rides(k) + OnboardingWeek.lifts(k) == 0 { return CoachLine(mark: "◆", tint: theme.warning, strong: "A plan needs at least one training day.") }
            return CoachLine(mark: "◆", tint: theme.accent, before: "Each tile becomes one planned session of that sport and length. ", strong: "Nothing is scheduled until you approve.")
        case 5: return CoachLine(mark: "◆", tint: theme.accent, strong: "Increases to your plan are presented for your approval.",
                                 after: " Reductions that protect recovery can be applied for you if you allow it. You can review why your plan changed.")
        case 6: return CoachLine(mark: "▲", tint: theme.success, before: "Your stage is earned by ", strong: "recorded training only", after: ". Nothing you answered here can raise or lower it.")
        default: return CoachLine(mark: "◆", tint: theme.accent, strong: "Nothing is scheduled until you approve.", after: " Tap any part of the blueprint to change it first.")
        }
    }
    private func backToBlueprint() { fromBlueprint = false; page = Self.pages }
    /// A Blueprint group opens the page it came from; that page's button returns here.
    private func editFromBlueprint(_ p: Int) { fromBlueprint = true; page = p }

    private var bottom: some View {
        let line = coachLine
        return VStack(alignment: .leading, spacing: CySpace.s) {
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
            if fromBlueprint, page < Self.pages {
                CyPrimaryButton(title: "Back to blueprint", isEnabled: canContinue, action: backToBlueprint)
                    .accessibilityIdentifier("onbBackToBlueprint")
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

    // MARK: 0 — Welcome
    //
    // Owner's approved direction for this screen, 20 Nov 2026 ("Screen 1 final decision"): the singularity as the hero,
    // one headline, one supporting line and a circular control that is HELD for three seconds; the screen then
    // dissolves and About you appears. No logo, app name, legend or explanatory paragraph. Do not add to it.
    // What "Get started" did is kept exactly: the athlete continues without an account and page 1 opens.
    // The hero is the app's existing flat singularity (the same one Progress draws); it does not move.

    static let holdSeconds: Double = 3

    private var welcomeScreen: some View {
        GeometryReader { geo in
            ScrollView {
                VStack(spacing: 0) {
                    Spacer(minLength: 24)
                    SingularityPlaceholder(diameter: min(200, geo.size.width * 0.5), detail: 1)
                        .frame(height: min(200, geo.size.width * 0.5) * 1.25)
                        .accessibilityHidden(true)
                    Spacer(minLength: 28).frame(maxHeight: 44)
                    VStack(spacing: 14) {
                        Text("Start your journey to a better lifestyle")
                            .font(.system(.title, design: .rounded).weight(.semibold)).foregroundStyle(theme.textPrimary)
                            .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                            .accessibilityAddTraits(.isHeader).accessibilityIdentifier("onbWelcomeHeadline")
                        Text("See where you fit in the athletic world, and build a routine around your life.")
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
                Text("Hold to start").font(CyFont.headline).foregroundStyle(theme.textPrimary)
                Text("Hold for 3 seconds").font(CyFont.footnote).foregroundStyle(theme.textSecondary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Hold to start")
        .accessibilityHint("Press and hold for 3 seconds")
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
            OnbAboutPage(a: $a, units: $store.settings.units, healthWeight: healthWeightOffer)
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
                VStack(alignment: .leading, spacing: 6) {
                    Text(v.hasOnlyUnsupported ? "No planned sport yet" : "Start with the sport you train most.")
                        .font(.system(.title2, design: .default).weight(.bold)).foregroundStyle(theme.textPrimary).fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("rosterEmptyHeadline")
                    Text("You can add others next. Sports Cyclift can plan and record are listed first.")
                        .font(CyFont.footnote).foregroundStyle(theme.textSecondary).fixedSize(horizontal: false, vertical: true)
                }
            } else {
                VStack(alignment: .leading, spacing: CySpace.s) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(v.mainEndurance != nil && v.mainStrength != nil ? "MAIN SPORTS" : "MAIN SPORT").font(CyFont.overline).tracking(0.8).foregroundStyle(theme.textSecondary)
                            .accessibilityAddTraits(.isHeader)
                        Spacer(minLength: CySpace.s)
                        Text("suggested · Continue confirms").font(CyFont.caption).foregroundStyle(theme.textSecondary)
                    }
                    let leadStrength = a.priority == .strength
                    let mains = (leadStrength ? [v.mainStrength, v.mainEndurance] : [v.mainEndurance, v.mainStrength]).compactMap { $0 }
                    ForEach(mains) { m in mainRow(m, dimmed: v.showsLead && ((a.priority == .strength && m.domain == .endurance) || (a.priority == .cycling && m.domain == .strength))) }
                    if v.showsLead {
                        CyChoiceBar(options: [(TrainingPriority.cycling, "Endurance-led"), (TrainingPriority.balanced, "Balanced"), (TrainingPriority.strength, "Strength-led")],
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
                    HStack(alignment: .firstTextBaseline) {
                        Text(v.mainEndurance == nil && v.mainStrength == nil ? "CYCLIFT CAN PLAN AND RECORD THESE" : "ADD TO YOUR ROSTER")
                            .font(CyFont.overline).tracking(0.8).foregroundStyle(theme.textSecondary).accessibilityAddTraits(.isHeader)
                        Spacer(minLength: CySpace.s)
                        if v.mainEndurance != nil || v.mainStrength != nil { Text("suggestions").font(CyFont.caption).foregroundStyle(theme.textSecondary) }
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
            Text(x.title).font(.system(.title2, design: .default).weight(.bold))
                .foregroundStyle(dimmed ? theme.textSecondary : theme.textPrimary).fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel("\(x.title). \(x.capability.words), main \(x.domain.title.lowercased()) sport")
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
                    HStack(spacing: CySpace.m) {
                        Image(systemName: Self.symbol(x)).foregroundStyle(theme.textSecondary).frame(width: 26).accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) { rowText(x) }
                        Spacer(minLength: CySpace.s)
                        Image(systemName: "plus.circle").font(.title3).foregroundStyle(theme.textPrimary).accessibilityHidden(true)
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
    /// A plain symbol per activity (sheet Z2 draws one beside every row). Decorative: the name is always written.
    private static func symbol(_ x: RosterActivity) -> String {
        switch x.id {
        case "strength": return "dumbbell"
        case "indoorCycling": return "figure.indoor.cycle"
        case "roadCycling", "mountainBike", "commuting", "gravel": return "bicycle"
        default: return x.domain == .strength ? "figure.strengthtraining.traditional" : x.domain == .endurance ? "figure.run" : "figure.mind.and.body"
        }
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
            // PROVISIONAL (reference sheet Y3, not approved): compact goal cells and the level rows on one page. The
            // same answers as before — goals, main goal, cycling and strength level — written through the same model.
            // The priority ("when time is short, protect") is NOT repeated here: page 2 owns it (later sheet Z2).
            ForEach(GoalInfo.choices(for: mode)) { group in
                VStack(alignment: .leading, spacing: CySpace.s) {
                    Text("\(group.title.uppercased()) GOALS").font(CyFont.overline).tracking(0.8).foregroundStyle(theme.textSecondary).accessibilityAddTraits(.isHeader)
                    // two to a row; an odd last goal takes the full width, as on the sheet
                    let pairs = stride(from: 0, to: group.goals.count, by: 2).map { Array(group.goals[$0..<min($0 + 2, group.goals.count)]) }
                    VStack(spacing: 6) {
                        ForEach(Array(pairs.enumerated()), id: \.offset) { row in
                            HStack(spacing: 6) { ForEach(row.element) { g in goalCell(g) } }
                        }
                    }
                }
            }
            VStack(alignment: .leading, spacing: CySpace.s) {
                HStack(alignment: .firstTextBaseline) {
                    provenance("●", "Your level")
                    Spacer(minLength: CySpace.s)
                    Text("declared by you — not measured").font(CyFont.caption).foregroundStyle(theme.textSecondary)
                }
                if mode.includesCycling {
                    levelRow("Cycling", id: "onbCyclingLevel", options: RiderProfile.Level.allCases.map { ($0, ProfileText.level($0)) },
                             selection: Binding(get: { a.cyclingLevel ?? store.profile.level }, set: { a.cyclingLevel = $0 }))
                }
                if mode.includesLifting {
                    levelRow("Strength", id: "onbStrengthLevel", options: StrengthPrefs.Experience.allCases.map { ($0, ProfileText.strengthLevel($0)) },
                             selection: Binding(get: { a.strengthLevel ?? store.strengthPrefs.experience ?? .beginner }, set: { a.strengthLevel = $0 }))
                }
            }
        }
    }
    private func levelRow<T: Hashable>(_ title: String, id: String, options: [(T, String)], selection: Binding<T>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: CySpace.m) {
                Text(title).font(CyDyn.f(15, .semibold)).foregroundStyle(theme.textPrimary).frame(width: 74, alignment: .leading)
                CyChoiceBar(options: options, selection: selection).accessibilityIdentifier(id)
            }
        }
    }
    /// One goal of sheet Y3: a compact cell. Chosen and main = filled in the sport's colour with a filled star; chosen
    /// but not main = outlined with an open star; the star is its own control beside the cell, as before.
    private func goalCell(_ g: GoalID) -> some View {
        let chosen = a.goals ?? []
        let on = chosen.contains(g), main = on && a.primaryGoal == g
        let tint: Color = g.sport == .strength ? theme.strength : g.sport == .cycling ? theme.endurance : theme.recovery
        return ZStack(alignment: .trailing) {
            Button {
                var list = chosen
                if list.contains(g) { list.removeAll { $0 == g } } else { list.append(g) }
                a.goals = list
                a.primaryGoal = a.primaryGoal.flatMap { list.contains($0) ? $0 : nil } ?? list.first
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(g.title).font(CyDyn.f(15, .semibold)).foregroundStyle(main ? theme.background : theme.textPrimary).lineLimit(1).minimumScaleFactor(0.8)
                    Text(GoalInfo.line(g)).font(CyDyn.f(11.5)).foregroundStyle(main ? theme.background.opacity(0.8) : theme.textSecondary).lineLimit(1).minimumScaleFactor(0.75)
                }
                .padding(.horizontal, 11).padding(.vertical, 6).padding(.trailing, on ? 30 : 0)
                .frame(maxWidth: .infinity, minHeight: CyHit.min, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(main ? tint : theme.surface))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(on && !main ? tint : Color.clear, lineWidth: 1.5))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(g.title), \(GoalInfo.line(g))\(main ? ", main goal" : "")")
            .accessibilityAddTraits(on ? .isSelected : [])
            .accessibilityIdentifier("goal-\(g.rawValue)")
            if on {
                Button { a.primaryGoal = g } label: {
                    Image(systemName: main ? "star.fill" : "star").font(.caption.weight(.bold))
                        .foregroundStyle(main ? tint : tint)
                        .frame(width: 26, height: 26)
                        .background(Circle().fill(main ? theme.background : Color.clear))
                        .overlay(Circle().strokeBorder(main ? Color.clear : tint, lineWidth: 1))
                        .frame(width: CyHit.min, height: CyHit.min).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(main ? "\(g.title) is the main goal" : "Make \(g.title) the main goal")
                .accessibilityIdentifier("goalStar-\(g.rawValue)")
            }
        }
    }

    // MARK: 4 — Week

    private var pageWeek: some View {
        VStack(alignment: .leading, spacing: CySpace.m) {
            heading(4, "Week", "Build your week")
            OnbWeekPage(a: $a, mode: mode, enduranceTitle: roster.mainEndurance?.title ?? "Cycling", strengthTitle: roster.mainStrength?.title ?? "Strength")
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

    private var pageBlueprint: some View {
        OnbBlueprintPage(m: blueprintModel, onEdit: editFromBlueprint)
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
        let n = OnbWeekText.sessions(kinds)
        let single: String = (v.mainEndurance ?? v.mainStrength)?.title ?? ""
        let lead: String = v.mode == .hybrid ? leadWord : single
        var goalLine = ""
        if let g = main {
            goalLine = GoalInfo.line(g)
            if !others.isEmpty { goalLine += " · also " + others.map(\.title).joined(separator: ", ") }
        }
        let isStrengthGoal: Bool = main.map { $0.sport == .strength } ?? false
        let totals: String = "\(OnbWeekText.total(kinds, ride: ride, lift: lift)) · \(n) session\(n == 1 ? "" : "s")"
        return OnbBlueprintModel(
            name: (a.name ?? "").trimmingCharacters(in: .whitespaces),
            levels: levelsLine,
            lead: lead,
            identity: AthleticRoster.identityLine(sports, priority: a.priority),
            sports: blueprintSports(v),
            goalTitle: main?.title,
            goalIsStrength: isStrengthGoal,
            goalLine: goalLine,
            kinds: kinds, ride: ride, lift: lift,
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
        let leadStrength = a.priority == .strength
        let mains = (leadStrength ? [v.mainStrength, v.mainEndurance] : [v.mainEndurance, v.mainStrength]).compactMap { $0 }
        return mains.map { mark($0, main: true) } + v.also.map { mark($0, main: false) }
    }
    /// What the athlete declared, each with the page that changes it.
    private func blueprintCells(_ v: AthleticRoster.Page, main: GoalID?, others: [GoalID]) -> [OnbBlueprintModel.Cell] {
        var out: [OnbBlueprintModel.Cell] = []
        if let g = main { out.append(.init(id: "goals", title: "Goals", value: ([g.title + " ★"] + others.map(\.title)).joined(separator: " · "), page: 3)) }
        if v.mode == .hybrid { out.append(.init(id: "lead", title: "When time is short", value: leadWord, page: 2)) }
        if mode.includesLifting { out.append(.init(id: "equipment", title: "Equipment", value: (a.equipment ?? .notSure).title, page: 4)) }
        if mode.includesCycling {
            let p = store.profile
            let value = p.ftpKnown ? "\(p.ftpValue.map { "\($0) W" } ?? "Entered") · \(p.ftpSource == .tested ? "tested" : "not tested")" : "Unknown"
            out.append(.init(id: "ftp", title: "FTP", value: value, page: 5))
        }
        out.append(.init(id: "planChanges", title: "Plan changes", value: store.settings.autoAdapt ? "Auto-apply reductions" : "Always ask me", page: 5))
        let interests = v.also.filter { !$0.capability.plannable }.map(\.title)
        if !interests.isEmpty { out.append(.init(id: "interests", title: "Interests", value: interests.joined(separator: " · "), page: 2)) }
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
