import SwiftUI

// MARK: - Adaptive coach UI: post-workout check-in, Adjustments ("Why this changed?", Undo, Restore original plan),
// the hybrid plan answers (goal, days, split, session length, equipment, routines to keep). No new tabs.

enum CheckInTarget: Equatable {
    case ride(UUID), strength(UUID)
    var isRide: Bool { if case .ride = self { return true }; return false }
}

/// Fast check-in after a ride or a strength session: performance 1–10, effort 1–10, pain, optional note. Save runs the
/// coach and shows what changed (and why); Skip closes without a rating.
struct CheckInFlow: View {
    @EnvironmentObject private var store: Store
    let target: CheckInTarget
    var initialEffort: Int? = nil
    var onDone: () -> Void
    @State private var performance = 7
    @State private var effort = 6
    @State private var pain: PainLevel = .noPain
    @State private var area: PainArea = .other
    @State private var note = ""
    @State private var showResult = false
    @State private var loaded = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(target.isRide ? "How was the ride?" : "How was the session?").font(.title3.weight(.bold))
                    Text("Ten seconds. The coach uses it to adapt your next sessions.").font(.footnote).foregroundStyle(.secondary)
                }
                Section { scale($performance, low: "far below expectations", high: "excellent") } header: { Text("Performance") } footer: { Text("10 = excellent performance compared with what you expected.") }
                Section { scale($effort, low: "very easy", high: "maximal") } header: { Text("Effort") } footer: { Text("10 = maximal effort.") }
                Section {
                    Picker("Pain or unusual discomfort", selection: $pain) { ForEach(PainLevel.allCases, id: \.self) { Text($0.short).tag($0) } }
                        .pickerStyle(.segmented).accessibilityIdentifier("checkInPain")
                    if pain.needsArea {
                        Picker("Where", selection: $area) { ForEach(PainArea.allCases, id: \.self) { Text($0.title).tag($0) } }
                        Text(pain == .concerning ? (AdaptationExplainer.painAdvice([area]) ?? "") : AdaptationExplainer.discomfortAdvice([area])).font(.footnote).foregroundStyle(pain == .concerning ? BC.warn : .secondary).fixedSize(horizontal: false, vertical: true)
                    }
                    Text(painDefinition(pain)).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    if pain == .soreness {
                        Text("Normal muscle soreness does not change your plan.").font(.footnote).foregroundStyle(.secondary)
                    }
                } header: { Text("Pain or unusual discomfort") }
                Section("Note (optional)") { TextField("Anything worth remembering", text: $note, axis: .vertical).lineLimit(1...3) }
                Section {
                    Button { submit() } label: { Text("Save check-in").frame(maxWidth: .infinity) }.buttonStyle(.borderedProminent).tint(BC.accent).accessibilityIdentifier("checkInSave")
                } footer: { Text(AdaptationExplainer.disclaimer) }
            }
            .accessibilityIdentifier("checkInForm")
            .navigationTitle("Check-in").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Skip") { onDone() }.accessibilityIdentifier("checkInSkip") }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { submit() }.bold().accessibilityIdentifier("checkInSubmit") }
            }
            .navigationDestination(isPresented: $showResult) {
                AdjustmentsView(afterCheckIn: true)
                    .navigationBarBackButtonHidden(true)
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { onDone() }.accessibilityIdentifier("adjustmentsDone") } }
            }
            .onAppear { if !loaded { loaded = true; if let e = initialEffort { effort = min(10, max(1, e)) } } }
        }
        .interactiveDismissDisabled()
    }

    private func scale(_ value: Binding<Int>, low: String, high: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 6) { Text("\(value.wrappedValue)").font(BC.numFont).monospacedDigit(); Text("of 10").foregroundStyle(.secondary); Spacer() }
            Slider(value: Binding(get: { Double(value.wrappedValue) }, set: { value.wrappedValue = Int($0.rounded()) }), in: 1...10, step: 1).tint(BC.accent)
            HStack { Text(low); Spacer(); Text(high) }.font(.caption2).foregroundStyle(.secondary)
        }
    }

    private func submit() {
        guard !showResult else { return }
        let c = CheckIn(performance: performance, effort: effort, pain: pain, painArea: pain.needsArea ? area : nil, note: note.trimmingCharacters(in: .whitespacesAndNewlines))
        switch target {
        case .ride(let id): _ = store.recordCheckIn(c, rideId: id)
        case .strength(let id): _ = store.recordCheckIn(c, strengthId: id)
        }
        showResult = true
    }
}

/// Every automatic change with "Why this changed?" and its own Undo, the proposals that need the rider's OK,
/// "Restore original plan", what the coach saw, and the switch for automatic changes.
struct AdjustmentsView: View {
    @EnvironmentObject private var store: Store
    var afterCheckIn = false
    @State private var confirmRestore = false
    @State private var openWhy: Set<String> = []

    var body: some View {
        let active = store.activeAdaptations
        let groups = Dictionary(grouping: active, by: { $0.workoutId })
        let sessions = store.plan.filter { groups[$0.id] != nil }.sorted { $0.date < $1.date }
        List {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Eyebrow(t: AdaptationExplainer.label)
                    Text(headline(sessions.count)).font(.headline).fixedSize(horizontal: false, vertical: true)
                    if let s = store.lastAdaptation { Text("Last analysis \(s.at.dayAndDate) · confidence \(s.confidence.title)").font(.caption).foregroundStyle(.secondary) }
                }
                if let s = store.lastAdaptation, let p = s.painAdvice {
                    Label { Text(p).font(.footnote).fixedSize(horizontal: false, vertical: true) } icon: { Image(systemName: "cross.case").foregroundStyle(BC.warn) }
                    // only the rider clears a concerning-pain report; after a week with two pain-free sessions the coach asks
                    ForEach(store.activePainAreas(), id: \.self) { area in
                        Button { store.confirmPainGone(area) } label: {
                            Label(store.painReviewDue().contains(area) ? "\(area.title): pain-free in your last 2 sessions — it's fine now" : "\(area.title): it's fine now", systemImage: "checkmark.circle").frame(maxWidth: .infinity, minHeight: DS.minTap, alignment: .leading)
                        }
                        .accessibilityIdentifier("painGone-\(area.rawValue)")
                        .accessibilityHint("Releases the hold on \(area.title.lowercased()) so the coach can progress that area again")
                    }
                }
                if let s = store.lastAdaptation, let f = s.feedbackRequest {
                    Label { Text(f).font(.footnote).fixedSize(horizontal: false, vertical: true) } icon: { Image(systemName: "text.bubble").foregroundStyle(BC.stale) }
                }
            }
            if afterCheckIn, let rb = store.checkInRebuild {
                Section {
                    ForEach(Array(rb.lines.enumerated()), id: \.offset) { _, l in Text(l).font(.footnote).fixedSize(horizontal: false, vertical: true) }
                    Button { store.undoCheckInRebuild() } label: { Label("Undo these changes", systemImage: "arrow.uturn.backward").frame(minHeight: DS.minTap) }
                        .accessibilityIdentifier("undoCheckInRebuild")
                } header: { Text("Changed after this check-in") } footer: { Text("Undo puts these sessions back exactly as they were and keeps them that way. Progression never comes from sessions marked done without details.") }
            }
            if !sessions.isEmpty {
                Section {
                    ForEach(sessions) { w in sessionBlock(w, groups[w.id] ?? []) }
                } header: { Text("Changed automatically") } footer: { Text("Only future sessions change. Fixed days, sessions you edited and completed logs are never touched by the coach on its own.") }
            }
            if !store.adaptiveProposals.isEmpty {
                Section("Needs your OK") { ForEach(store.adaptiveProposals) { p in proposalRow(p) } }
            }
            if let s = store.lastAdaptation, !s.findings.isEmpty {
                Section("What the coach saw") { ForEach(Array(s.findings.enumerated()), id: \.offset) { _, f in Text(f).font(.footnote).fixedSize(horizontal: false, vertical: true) } }
            }
            Section {
                if !active.isEmpty {
                    Button(role: .destructive) { confirmRestore = true } label: { Label("Restore original plan", systemImage: "arrow.uturn.backward") }.accessibilityIdentifier("restoreOriginalPlan")
                }
                Toggle("Adjust future sessions automatically", isOn: $store.settings.autoAdapt).tint(BC.accent)
            } footer: { Text("Off: nothing changes on its own; suggestions still wait here for your OK. " + AdaptationExplainer.disclaimer) }
        }
        .accessibilityIdentifier("adjustmentsView")
        .navigationTitle("Coach adjustments").navigationBarTitleDisplayMode(.inline)
        .onChange(of: store.settings.autoAdapt) { _, _ in _ = store.runAdaptation() }
        .alert("Restore the original plan?", isPresented: $confirmRestore) {
            Button("Restore", role: .destructive) { store.restoreOriginalPlan() }
            Button("Cancel", role: .cancel) {}
        } message: { Text("Every automatic change is undone and not made again for those sessions. Completed sessions and your own edits stay as they are.") }
    }

    private func headline(_ n: Int) -> String {
        if afterCheckIn, let rb = store.checkInRebuild, rb.before.count > n { return "Check-in saved. The coach updated \(rb.before.count) upcoming session\(rb.before.count == 1 ? "" : "s")." }
        if afterCheckIn { return n == 0 ? "Check-in saved. No change to your plan this time." : "Check-in saved. The coach adjusted \(n) upcoming session\(n == 1 ? "" : "s")." }
        return n == 0 ? "No automatic changes in force." : "\(n) upcoming session\(n == 1 ? "" : "s") adjusted automatically."
    }

    private func sessionBlock(_ w: Workout, _ list: [PlanAdjustment]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(w.date.dayAndDate).font(.caption.weight(.heavy)).foregroundStyle(.secondary)
                Text(w.displayTitle(routine: store.routine(for: w))).font(.subheadline.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
                Spacer()
            }
            ForEach(list) { a in
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Image(systemName: icon(a.category)).foregroundStyle(color(a.category)).font(.footnote)
                        Text(a.summary).font(.footnote.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 4)
                        Button("Undo") { store.undoAdaptation(a.key) }.font(.caption.bold()).buttonStyle(.bordered).controlSize(.large).accessibilityIdentifier("undoAdjustment")
                    }
                    DisclosureGroup(isExpanded: Binding(get: { openWhy.contains(a.key) }, set: { if $0 { openWhy.insert(a.key) } else { openWhy.remove(a.key) } })) {
                        Text(a.why).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    } label: { Text("Why this changed?").font(.caption.weight(.semibold)).foregroundStyle(BC.accent) }
                }
            }
            if w.edited { Text("You edited this session afterwards; it stays as you set it.").font(.caption2).foregroundStyle(.secondary) }
        }.padding(.vertical, 4)
    }

    private func proposalRow(_ p: AdaptiveProposal) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack { Pill(text: p.reason.title, color: BC.stale); Spacer() }
            Text(p.text).font(.footnote.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
            Text(p.why).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                if !p.adjustments.isEmpty { Button("Accept") { _ = store.acceptAdaptiveProposal(p) }.buttonStyle(.borderedProminent).tint(BC.accent).controlSize(.large) }
                Button(p.adjustments.isEmpty ? "OK" : "Not now") { store.dismissAdaptiveProposal(p) }.buttonStyle(.bordered).controlSize(.large)
                Spacer()
            }
        }.padding(.vertical, 4)
    }
    private func icon(_ c: PlanAdjustment.Category) -> String { switch c { case .progression: return "arrow.up.circle.fill"; case .reduction: return "arrow.down.circle.fill"; case .recovery: return "leaf.fill"; case .substitution: return "arrow.left.arrow.right.circle.fill" } }
    private func color(_ c: PlanAdjustment.Category) -> Color { switch c { case .progression: return BC.live; case .reduction: return BC.stale; case .recovery: return BC.accent; case .substitution: return BC.accent } }
}

/// Home: one line when the coach changed something (or waits for an OK) → the Adjustments view.
struct AdjustmentHomeLine: View {
    @EnvironmentObject private var store: Store
    var body: some View {
        if let line = store.adjustmentLine {
            NavigationLink { AdjustmentsView() } label: {
                Card {
                    HStack(spacing: 10) {
                        Image(systemName: "wand.and.stars").foregroundStyle(BC.accent)
                        Text(line).font(.subheadline.weight(.semibold)).foregroundStyle(.primary).multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 4)
                        Image(systemName: "chevron.right").foregroundStyle(.secondary)
                    }
                }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("coachAdjustedLine")
        }
    }
}

/// Hybrid plan answers (brief A): goal, total training days, sessions per sport, session length and weekly time,
/// strength split (custom = your own list of session types or routines with a frequency each), equipment, routines to
/// keep. Used in onboarding (as a sheet) and in Profile › Training profile. Every answer is optional.
struct HybridPlanEditor: View {
    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss
    var asSheet = false
    @State private var showDays = false
    @State private var applied: String? = nil

    var body: some View {
        if asSheet {
            NavigationStack { form.toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } } }
        } else { form }
    }
    private var p: RiderProfile { store.profile }
    private func update(_ change: (inout RiderProfile) -> Void) { store.updateProfile(change) }
    private var defaultDays: Int { max(1, store.effectiveAvailability.days.filter { !$0.isRest }.count) }

    private var form: some View {
        Form {
            Section {
                Picker("Primary goal", selection: Binding(get: { p.hybridGoal ?? .balanced }, set: { g in update { $0.hybridGoal = g; $0.priority = g.priority } })) {
                    ForEach(HybridGoal.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                if p.hybridGoal == .custom { TextField("Your goal in a few words", text: Binding(get: { p.hybridGoalNote ?? "" }, set: { v in update { $0.hybridGoalNote = v.isEmpty ? nil : v } })) }
            } header: { Text("Goal") } footer: { Text("Decides which sport the coach protects when time is short.") }

            Section {
                Stepper("Training days: \(p.trainingDaysPerWeek ?? defaultDays) a week", value: Binding(get: { p.trainingDaysPerWeek ?? defaultDays }, set: { v in update { $0.trainingDaysPerWeek = v } }), in: 1...7)
                if p.trainingMode.includesCycling {
                    Stepper("Cycling: \(p.cyclingDaysPerWeek) session\(p.cyclingDaysPerWeek == 1 ? "" : "s") a week", value: Binding(get: { p.cyclingDaysPerWeek }, set: { v in update { $0.cyclingDaysPerWeek = v } }), in: 0...10)
                }
                if p.strengthSplit == .custom {
                    LabeledContent("Strength", value: "\(p.liftDaysPerWeek) a week (from your split)")
                } else {
                    Stepper("Strength: \(p.liftDaysPerWeek) session\(p.liftDaysPerWeek == 1 ? "" : "s") a week", value: Binding(get: { p.liftDaysPerWeek }, set: { v in update { $0.liftDaysPerWeek = v } }), in: 0...10)
                }
                if !asSheet { Button("Rest days, fixed and flexible days") { showDays = true } }
            } header: { Text("Your week") } footer: { Text("When there are more sessions than training days, some days get two (a ride and a lift). The other days are rest days. \(asSheet ? "You choose the exact days, rest days and fixed days on the next screen." : "Choose the exact days and which are fixed in the day editor.")") }

            Section {
                if p.trainingMode.includesCycling {
                    Stepper("Ride length: \(Fmt.duration(minutes: rideMinutes))", value: Binding(get: { rideMinutes }, set: { v in update { $0.cyclingSessionMinutes = v } }), in: 20...240, step: 5)
                    Stepper("Cycling budget: \(p.hoursPerWeek) h a week", value: Binding(get: { p.hoursPerWeek }, set: { v in update { $0.hoursPerWeek = v } }), in: 1...25)
                }
                Stepper("Strength session: \(Fmt.duration(minutes: liftMinutes))", value: Binding(get: { liftMinutes }, set: { v in update { $0.strengthSessionMinutes = v } }), in: 15...150, step: 5)
                Stepper("Lifting budget: \(p.liftingHoursPerWeek) h a week", value: Binding(get: { p.liftingHoursPerWeek }, set: { v in update { $0.liftingHoursPerWeek = v } }), in: 1...12)
            } header: { Text("Session length and weekly time") } footer: { Text("Budgets are never exceeded on their own: the long ride and sessions are fitted inside them.") }

            Section {
                Picker("Split", selection: Binding(get: { p.strengthSplit }, set: { s in update { pr in
                    pr.strengthSplit = s
                    if s == .custom {
                        if pr.customSplit.isEmpty { pr.customSplit = [SplitSlot(focus: .fullBody, perWeek: 2), SplitSlot(focus: .custom, label: "Core / joints", perWeek: 1)] }
                        pr.liftDaysPerWeek = pr.customSplit.reduce(0) { $0 + $1.perWeek }
                    }
                } })) {
                    Text("Coach decides").tag(StrengthSplit?.none)
                    ForEach(StrengthSplit.allCases, id: \.self) { Text($0.title).tag(StrengthSplit?.some($0)) }
                }
                if let s = p.strengthSplit {
                    Text("This week: " + StrengthSplit.sessions(split: s, slots: p.customSplit, count: max(1, p.liftDaysPerWeek), offset: StrengthSplit.weekIndex(of: TrainingLedger.monday(of: Date())) * max(1, p.liftDaysPerWeek)).map { $0.title }.joined(separator: " · ")).font(.footnote).foregroundStyle(.secondary)
                }
                if p.strengthSplit == .custom {
                    ForEach(p.customSplit) { slot in
                        SplitSlotRow(slot: slot, templates: store.templates, onChange: { s in update { pr in
                            if let i = pr.customSplit.firstIndex(where: { $0.id == s.id }) { pr.customSplit[i] = s; pr.liftDaysPerWeek = pr.customSplit.reduce(0) { $0 + $1.perWeek } }
                        } }, onDelete: { update { pr in pr.customSplit.removeAll { $0.id == slot.id }; pr.liftDaysPerWeek = max(0, pr.customSplit.reduce(0) { $0 + $1.perWeek }) } })
                    }
                    Button { update { pr in pr.customSplit.append(SplitSlot(focus: .custom, label: "", perWeek: 1)); pr.liftDaysPerWeek = pr.customSplit.reduce(0) { $0 + $1.perWeek } } } label: { Label("Add a session type", systemImage: "plus") }
                }
            } header: { Text("Strength split") } footer: { Text("No split needs a fixed number of days: the rotation simply continues over the sessions you want. Custom: your own list, e.g. 2 × Full body + 1 × Core / joints, or one of your routines per slot.") }

            Section {
                NavigationLink { EquipmentPage() } label: { HStack { Text("Equipment I own"); Spacer(); Text(store.equipment.isSet ? "\(store.equipment.owned.count) items" : "not set").foregroundStyle(.secondary) } }
                ForEach(store.templates) { t in
                    Toggle(isOn: Binding(get: { p.preservedTemplateIds.contains(t.id) }, set: { on in update { pr in if on { if !pr.preservedTemplateIds.contains(t.id) { pr.preservedTemplateIds.append(t.id) } } else { pr.preservedTemplateIds.removeAll { $0 == t.id } } } })) {
                        VStack(alignment: .leading, spacing: 2) { Text("Keep “\(t.name)”"); Text(t.exerciseNames).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                    }.tint(BC.accent)
                }
                if store.templates.isEmpty { Text("No saved routines yet. Sessions are built from your own exercises first, then from exercises that fit your equipment.").font(.footnote).foregroundStyle(.secondary) }
                NavigationLink("Routines (templates)") { TemplatesView() }
            } header: { Text("Equipment and routines") } footer: { Text("The coach never prescribes equipment you do not have. Replacing one of your saved exercises is only ever a suggestion for your OK.") }

            if !asSheet {
                Section {
                    Button("Suggest new days from these answers") { store.rebuildFromHybridAnswers(newDays: true); applied = "New days suggested; this week and next were rebuilt (completed sessions, past days and your edits kept)." }
                    Button("Rebuild the coming weeks with my current days") { store.rebuildFromHybridAnswers(newDays: false); applied = "This week and next were rebuilt (completed sessions, past days and your edits kept)." }
                    if let a = applied { Text(a).font(.footnote).foregroundStyle(BC.live) }
                } footer: { Text("Your answers are saved as you change them; the calendar changes only when you rebuild.") }
            }
        }
        .navigationTitle("Hybrid plan").navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showDays) { AvailabilityEditor() }
    }
    private var rideMinutes: Int { p.cyclingSessionMinutes ?? min(240, max(20, (p.hoursPerWeek * 60) / max(1, p.cyclingDaysPerWeek) / 5 * 5)) }
    private var liftMinutes: Int { p.strengthSessionMinutes ?? min(150, max(15, (max(1, p.liftingHoursPerWeek) * 60) / max(1, p.liftDaysPerWeek) / 5 * 5)) }
}

/// One custom split entry: session type (or one of the rider's routines), its name and how often per week.
struct SplitSlotRow: View {
    let slot: SplitSlot
    let templates: [WorkoutTemplate]
    var onChange: (SplitSlot) -> Void
    var onDelete: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Picker("Type", selection: Binding(get: { slot.focus }, set: { v in var s = slot; s.focus = v; onChange(s) })) { ForEach(StrengthFocus.allCases, id: \.self) { Text($0.title).tag($0) } }
                Button(role: .destructive) { onDelete() } label: { Image(systemName: "minus.circle").frame(minWidth: DS.minTap, minHeight: DS.minTap).contentShape(Rectangle()) }.buttonStyle(.plain).foregroundStyle(.secondary).accessibilityLabel("Remove")
            }
            if slot.focus == .custom { TextField("Name, e.g. Core / joints", text: Binding(get: { slot.label }, set: { v in var s = slot; s.label = v; onChange(s) })) }
            Picker("Routine", selection: Binding(get: { slot.templateId }, set: { v in var s = slot; s.templateId = v; onChange(s) })) {
                Text("Coach builds it").tag(UUID?.none)
                ForEach(templates) { t in Text(t.name).tag(UUID?.some(t.id)) }
            }
            Stepper("\(slot.perWeek) × a week", value: Binding(get: { slot.perWeek }, set: { v in var s = slot; s.perWeek = v; onChange(s) }), in: 1...4)
        }.padding(.vertical, 2)
    }
}

/// Review N-15: short definitions so the rider can classify what they feel (coaching guidance, not a diagnosis).
func painDefinition(_ p: PainLevel) -> String {
    switch p {
    case .noPain: return "Nothing unusual."
    case .soreness: return "Soreness: a dull muscle ache 1–3 days after training that eases as you warm up."
    case .discomfort: return "Discomfort: something feels off in one spot, but it is not sharp, not in a joint and does not change how you move."
    case .concerning: return "Pain: sharp or stabbing, in or around a joint, with swelling, changes how you move, or still there the next day."
    }
}
