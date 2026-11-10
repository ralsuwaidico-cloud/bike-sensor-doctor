import SwiftUI

// MARK: - Home B destinations that did not exist before (spec "Must be built"): Move to another day, recovery guidance,
// the health hold sheet, "Add duration" for a ride marked done; plus the small sheets Home opens (Why, Swap, coach items).

/// A sheet with its own navigation bar and a Done button (for screens that are normally pushed).
struct HomeSheetWrap<Content: View>: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    @ViewBuilder var content: Content
    var body: some View {
        NavigationStack {
            content
                .navigationTitle(title).navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() }.accessibilityIdentifier("homeSheetClose") } }
        }
        .tint(BC.accent)   // the app accent, not system blue (independent QA, run 111)
    }
}

/// "Why this workout?" — the coach's existing explanation (Coach.why; the planner's notes for a session it built).
struct HomeWhySheet: View {
    @EnvironmentObject private var store: Store
    let workout: Workout
    var body: some View {
        HomeSheetWrap(title: "Why this workout?") {
            ScrollView {
                VStack(alignment: .leading, spacing: DS.m) {
                    Text(workout.displayTitle(routine: store.routine(for: workout))).font(DS.screenTitle).fixedSize(horizontal: false, vertical: true)
                    Text(Coach.why(workout, store: store)).font(.body).fixedSize(horizontal: false, vertical: true)
                    if let notes = workout.rationale?.notes, !notes.isEmpty {
                        Eyebrow(t: "How this session was built")
                        ForEach(Array(notes.enumerated()), id: \.offset) { pair in Text(pair.element).font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
                    }
                    if let r = store.profile.readiness.restriction { Text("Health check: \(r).").font(.footnote).foregroundStyle(BC.stale).fixedSize(horizontal: false, vertical: true) }
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
        }
        .presentationDetents([.medium, .large])
    }
}

/// Swap today's session for an alternative of the same day (the rider's pick is a rider edit), or skip it.
struct HomeSwapSheet: View {
    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss
    let workout: Workout
    /// Phase 1 rebuild fix: a swap INTO strength is previewed before it is saved.
    @State private var preview: PreviewRef? = nil
    @State private var notice: String? = nil
    var body: some View {
        HomeSheetWrap(title: "Swap \(workout.kind.title.lowercased())") {
            List {
                Section("Instead of \(workout.kind.title)") {
                    ForEach(Array(Coach.alternatives(for: workout).enumerated()), id: \.offset) { pair in
                        Button {
                            var w = workout; w.kind = pair.element.kind; w.minutes = pair.element.minutes
                            switch store.requestEdit(w) {
                            case .saved: dismiss()
                            case .preview(let id): preview = PreviewRef(id: id)
                            case .refused(let t): notice = t
                            }
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(pair.element.kind.title).bold().foregroundStyle(.primary)
                                Text("\(Fmt.duration(minutes: pair.element.minutes)) · \(pair.element.kind.subtitle) · \(pair.element.benefit)").font(.footnote).foregroundStyle(.secondary)
                            }
                            .frame(minHeight: DS.minTap, alignment: .leading)
                        }
                    }
                    if let n = notice { Text(n).font(.footnote).foregroundStyle(BC.stale).fixedSize(horizontal: false, vertical: true) }
                }
            }
            .sheet(item: $preview) { r in SessionChangeSheet(proposalId: r.id, onApplied: { dismiss() }, onClose: { preview = nil }).id(r.id) }
        }
    }
}

/// Move to another day: today and the later days of this week without an open session, with what is there and a warning
/// when the move stacks the same sport or sits next to another hard ride. Undo in the snackbar.
struct RescheduleSheet: View {
    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss
    let workoutId: UUID
    var body: some View {
        let w = store.plan.first { $0.id == workoutId }
        let targets = store.moveTargets(for: workoutId)
        HomeSheetWrap(title: "Move to another day") {
            List {
                if let w {
                    Section {
                        Text("\(w.displayTitle(routine: store.routine(for: w))) · \(Fmt.duration(minutes: w.minutes)), planned \(HomeText.weekday(w.date))").font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                if targets.isEmpty {
                    Section { Text("No free day is left this week. Open Plan to change next week, or leave this session out.").font(.subheadline).foregroundStyle(.secondary) }
                } else {
                    Section("Free days this week") {
                        ForEach(targets) { t in
                            Button {
                                if store.reschedule(workoutId, to: t.date) { dismiss() }
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(Calendar.current.isDateInToday(t.date) ? "Today" : HomeText.longDate(t.date)).font(.body.weight(.semibold)).foregroundStyle(.primary)
                                    Text(t.note).font(.footnote).foregroundStyle(.secondary)
                                    if let warn = t.warning { Text(warn).font(.footnote).foregroundStyle(BC.stale) }
                                }
                                .frame(minHeight: DS.minTap, alignment: .leading)
                            }
                            .accessibilityIdentifier("moveTarget")
                        }
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

/// Rest day: honest, static guidance built from plan facts only (no recovery score; no sleep or HRV source exists).
struct RecoveryGuidanceSheet: View {
    @EnvironmentObject private var store: Store
    var body: some View {
        let week = store.homeWeek()
        HomeSheetWrap(title: "Recovery guidance") {
            ScrollView {
                VStack(alignment: .leading, spacing: DS.m) {
                    Text("Today is a rest day in your plan").font(DS.screenTitle).fixedSize(horizontal: false, vertical: true)
                    Text("Rest days are planned so the training of the last days can take effect.").fixedSize(horizontal: false, vertical: true)
                    VStack(alignment: .leading, spacing: DS.s) {
                        bullet("Easy walking or light mobility is fine.")
                        bullet("Regular meals and a normal night's sleep help the next session.")
                        bullet("Feel fresh and want to move? An optional easy session counts like any other — Train now offers one.")
                    }
                    Text(week.upNext.map { "Next planned: \($0)." } ?? "Nothing else is planned this week.").font(.subheadline.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
                    Text("Cyclift has no sleep, heart-rate-variability or recovery data, so this is general guidance, not a measurement of how recovered you are.").font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
        }
        .presentationDetents([.medium, .large])
    }
    private func bullet(_ s: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: DS.s) { Text("•").accessibilityHidden(true); Text(s).fixedSize(horizontal: false, vertical: true) }
    }
}

/// The health hold (stop, supervised only, ill): what it means, and the way back (the health check).
struct HealthHoldSheet: View {
    @EnvironmentObject private var store: Store
    var body: some View {
        let r = store.profile.readiness
        let hold: HomeHold = r.screen == .stop ? ((store.profile.healthScreen?.supervisedOnly ?? false) ? .supervised : .stop) : r.screen == .paused ? .ill : .paused
        HomeSheetWrap(title: "Training paused") {
            ScrollView {
                VStack(alignment: .leading, spacing: DS.m) {
                    Text(hold.title).font(DS.screenTitle).fixedSize(horizontal: false, vertical: true)
                    Text(hold.detail).fixedSize(horizontal: false, vertical: true)
                    if let why = r.restriction { Text("Cyclift's rule: \(why).").font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
                    Text("Train now, the Ride screen and the strength logger stay paused until then.").font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    if hold == .paused {
                        Button { store.resumeTraining() } label: {
                            Text(hold.button).font(.headline).frame(maxWidth: .infinity, minHeight: DS.minTap)
                        }
                        .buttonStyle(.borderedProminent).tint(BC.accent).foregroundStyle(Color.black)
                        .accessibilityIdentifier("holdResume")
                    } else {
                        NavigationLink { HealthCheckView() } label: {
                            Text(hold.button).font(.headline).frame(maxWidth: .infinity, minHeight: DS.minTap)
                        }
                        .buttonStyle(.borderedProminent).tint(BC.accent).foregroundStyle(Color.black)
                        .accessibilityIdentifier("holdReviewHealth")
                    }
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
        }
        .presentationDetents([.medium, .large])
    }
}

/// The health check as a sheet (from Home's buttons).
struct HealthCheckSheet: View {
    @EnvironmentObject private var store: Store
    // RC3: Home's hold button sends "review health"; when the athlete paused training themselves it means "resume"
    var body: some View {
        if store.profile.trainingPause != nil && store.profile.healthScreen.map({ $0.status() == .clear || $0.status() == .cleared || $0.status() == .notAnswered || $0.status() == .needsClearance }) ?? true {
            HomeSheetWrap(title: "Training paused") { TrainingPauseView() }
        } else {
            HomeSheetWrap(title: "Health check") { HealthCheckView() }
        }
    }
}

/// Shown instead of a Start button while the health check pauses training (Ride screen, strength logger: P0-2, defence in depth).
struct HealthHoldNotice: View {
    @State private var show = false
    var dark = false
    var body: some View {
        VStack(alignment: .leading, spacing: DS.s) {
            Text("Training is paused by your health check.").font(.subheadline.weight(.semibold)).foregroundStyle(dark ? Color.white : Color.primary).fixedSize(horizontal: false, vertical: true)
            Button { show = true } label: { Text("What this means").font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity, minHeight: DS.minTap) }
                .buttonStyle(.bordered).tint(BC.accent)
                .accessibilityIdentifier("healthHoldNotice")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .sheet(isPresented: $show) { HealthHoldSheet() }
    }
}

/// "Add duration" for a ride marked done without one (QA #23: there is no ride editor).
struct RideDurationSheet: View {
    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss
    let workoutId: UUID
    @State private var minutes = 60
    var body: some View {
        HomeSheetWrap(title: "Add duration") {
            Form {
                Section {
                    Stepper(value: $minutes, in: 5...600, step: 5) { Text("\(Fmt.duration(minutes: minutes))").monospacedDigit() }
                } footer: { Text("The time you rode, as you remember it. It counts in your weekly riding time; nothing else is estimated.") }
                Section {
                    Button("Save") { if store.setManualMinutes(workoutId, minutes: minutes) { dismiss() } }.accessibilityIdentifier("saveRideDuration")
                }
            }
        }
        .onAppear { if let w = store.plan.first(where: { $0.id == workoutId }), w.minutes > 0 { minutes = w.minutes } }
        .presentationDetents([.medium])
    }
}

/// A coach proposal from the slot: what, why, Accept / Not now (the same actions as Profile › Coach adjustments).
struct HomeProposalSheet: View {
    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss
    let adaptiveId: String?
    let hybridId: String?
    /// The hybrid proposal just accepted (its Undo used to live on the old Home coach card).
    @State private var applied: String? = nil
    /// Rebuild fix (Phase 1): a suggestion that rebuilds a strength session opens the before/after preview first.
    @State private var coachPreview: PreviewRef? = nil
    @State private var coachProposal: CoachProposal? = nil
    var body: some View {
        let a = adaptiveId.flatMap { id in store.adaptiveProposals.first { $0.id == id } }
        let h = hybridId.flatMap { id in HybridCoach.assess(profile: store.profile, plan: store.plan, rides: store.rides, strength: store.strength, availability: store.effectiveAvailability).proposals.first { $0.id == id } }
        HomeSheetWrap(title: "Coach suggestion") {
            ScrollView {
                VStack(alignment: .leading, spacing: DS.m) {
                    if let a {
                        Text(a.text).font(.title3.weight(.bold)).fixedSize(horizontal: false, vertical: true)
                        Text(a.why).fixedSize(horizontal: false, vertical: true)
                        if !a.adjustments.isEmpty {
                            Button { _ = store.acceptAdaptiveProposal(a); dismiss() } label: { Text("Accept").font(.headline).frame(maxWidth: .infinity, minHeight: DS.minTap) }
                                .buttonStyle(.borderedProminent).tint(BC.accent).foregroundStyle(Color.black).accessibilityIdentifier("proposalAccept")
                        }
                        Button { store.dismissAdaptiveProposal(a); dismiss() } label: { Text("Not now").frame(maxWidth: .infinity, minHeight: DS.minTap) }.buttonStyle(.bordered)
                    } else if let done = applied {
                        Text("Applied: \(done)").font(.title3.weight(.bold)).fixedSize(horizontal: false, vertical: true)
                        Button { _ = store.undoLastProposal(); applied = nil; dismiss() } label: { Text("Undo").frame(maxWidth: .infinity, minHeight: DS.minTap) }
                            .buttonStyle(.bordered).accessibilityIdentifier("proposalUndo")
                    } else if let h {
                        Text(h.text).font(.title3.weight(.bold)).fixedSize(horizontal: false, vertical: true)
                        Text(h.why).fixedSize(horizontal: false, vertical: true)
                        Button {
                            if let pid = store.coachChangePreview(h) { coachProposal = h; coachPreview = PreviewRef(id: pid) }
                            else if store.apply(h) { applied = h.text }
                        } label: { Text("Accept").font(.headline).frame(maxWidth: .infinity, minHeight: DS.minTap) }
                            .buttonStyle(.borderedProminent).tint(BC.accent).foregroundStyle(Color.black).accessibilityIdentifier("proposalAccept")
                    } else {
                        Text("This suggestion no longer applies.").foregroundStyle(.secondary)
                    }
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
        }
        .presentationDetents([.medium, .large])
        .sheet(item: $coachPreview) { r in SessionChangeSheet(proposalId: r.id, coach: coachProposal, onApplied: { applied = coachProposal?.text }, onClose: { coachPreview = nil }).id(r.id) }
    }
}

/// The FTP suggestion (the same card as Progress, with its Accept / Not now).
struct HomeFTPSheet: View {
    var body: some View {
        HomeSheetWrap(title: "Suggested FTP") {
            ScrollView { FTPSuggestionCard().padding() }.background(Color(.systemGroupedBackground))
        }
        .presentationDetents([.medium])
    }
}

// MARK: - RC3: explicit training pause (replaces the illness question as the everyday way to stop the plan)
/// Pause / resume in one place. Used by Home's hold sheet and available to Profile › Settings (`TrainingPauseView()`).
struct TrainingPauseView: View {
    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss
    @State private var reason: TrainingPause.Reason = .unwell
    var body: some View {
        Form {
            if let p = store.profile.trainingPause {
                Section {
                    Text("Paused since \(p.since.formatted(date: .abbreviated, time: .omitted)) · \(p.reason.title)").fixedSize(horizontal: false, vertical: true)
                    Button("Resume training") { store.resumeTraining(); dismiss() }
                        .bold().frame(minHeight: DS.minTap).accessibilityIdentifier("resumeTraining")
                } footer: { Text("No sessions are planned while paused. Your history is kept.") }
            } else {
                Section {
                    Picker("Reason", selection: $reason) {
                        ForEach(TrainingPause.Reason.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    Button("Pause training") { store.pauseTraining(reason: reason); dismiss() }
                        .bold().frame(minHeight: DS.minTap).accessibilityIdentifier("pauseTraining")
                } footer: { Text("Unwell or injured? Pause and resume when you feel ready. If symptoms are severe or don't go away, see a doctor.") }
            }
        }
    }
}
