import Foundation

// MARK: - Store side of the adaptive coach: check-ins → engine → future sessions, Undo, Restore, approvals.
// Completed logs and ride history are never changed here; the only write to a completed record is the rider's own
// check-in. Every automatic change keeps the session's original planned values (`Workout.coachOriginal`).
extension Store {
    /// Planned exercises of a session as originally planned (before any coach change).
    func originalEntries(for w: Workout) -> [ExerciseEntry] {
        let o = w.restoredOriginal
        if let e = o.plannedEntries, !e.isEmpty { return e }
        guard let t = routine(for: o) else { return [] }
        return t.prefilled(from: lastSession(template: t))
    }

    func adaptationInput(now: Date = Date()) -> AdaptationInput {
        let today = Calendar.current.startOfDay(for: now)
        var entries: [UUID: [ExerciseEntry]] = [:]
        for w in plan where w.kind == .strength && !w.done && w.date >= today { entries[w.id] = originalEntries(for: w) }
        return AdaptationInput(profile: profile, plan: plan, rides: rides, strength: strength, availability: effectiveAvailability, equipment: equipment,
                               catalogue: allExercises, templates: templates, originalEntries: entries, dismissed: Set(dismissedAdaptations),
                               approved: Set(approvedAdaptations), active: adaptations, units: settings.units, now: now, calendar: .current)
    }

    /// Analyze → Adapt: runs the engine and applies its result to the open future sessions.
    @discardableResult
    func runAdaptation(now: Date = Date()) -> AdaptationResult {
        let r = AdaptationEngine.run(adaptationInput(now: now))
        applyAdaptation(r, now: now)
        return r
    }

    /// Applies an engine result: each open future session is recomputed from its ORIGINAL values with exactly the
    /// changes wanted now (so changes never stack and a withdrawn reason restores the original). Sessions the rider
    /// edited or skipped are left as they are. With automatic changes off, only approved ones are applied.
    func applyAdaptation(_ r: AdaptationResult, now: Date = Date()) {
        let cal = Calendar.current
        let today = cal.startOfDay(for: now)
        let wanted = settings.autoAdapt ? r.adjustments : r.adjustments.filter { approvedAdaptations.contains($0.key) }
        var byWorkout: [UUID: [PlanAdjustment]] = [:]
        for a in wanted { byWorkout[a.workoutId, default: []].append(a) }
        var p = plan
        var active: [PlanAdjustment] = []
        for i in p.indices {
            let w = p[i]
            guard !w.done, cal.startOfDay(for: w.date) >= today else { continue }
            if w.edited || w.skipped {
                active += adaptations.filter { $0.workoutId == w.id }       // the rider took it over: listed, never recomputed
                continue
            }
            let desired = byWorkout[w.id] ?? []
            let base = w.restoredOriginal
            if desired.isEmpty {
                if w.coachOriginal != nil { p[i] = base }
                continue
            }
            var x = AdaptiveRules.apply(desired, to: base, entries: originalEntries(for: base))
            x.coachOriginal = base.planSnapshot
            p[i] = x
            for d in desired {
                if let old = adaptations.first(where: { $0.key == d.key && $0.change == d.change }) { active.append(old) } else { active.append(d) }
            }
        }
        if p != plan { plan = p }
        if adaptations != active { adaptations = active }
        let props = r.proposals.filter { !dismissedAdaptations.contains($0.id) }
        if adaptiveProposals != props { adaptiveProposals = props }
        lastAdaptation = r.summary
    }

    // MARK: Rate → Analyze → Adapt
    @discardableResult
    func recordCheckIn(_ c: CheckIn, rideId: UUID, now: Date = Date()) -> AdaptationResult? {
        guard let i = rides.firstIndex(where: { $0.id == rideId }) else { return nil }
        rides[i].checkIn = c
        return runAdaptation(now: now)
    }
    @discardableResult
    func recordCheckIn(_ c: CheckIn, strengthId: UUID, now: Date = Date()) -> AdaptationResult? {
        guard let i = strength.firstIndex(where: { $0.id == strengthId }) else { return nil }
        strength[i].checkIn = c
        return runAdaptation(now: now)
    }

    // MARK: visible and reversible (brief E)
    /// Changes in force on sessions that are still open.
    var activeAdaptations: [PlanAdjustment] { adaptations.filter { a in plan.contains { $0.id == a.workoutId && !$0.done } } }
    /// The one Home line: nil when nothing changed and nothing waits for approval.
    var adjustmentLine: String? {
        let n = Set(activeAdaptations.map { $0.workoutId }).count, p = adaptiveProposals.count
        if n == 0 && p == 0 { return nil }
        let first = n > 0 ? "Coach adjusted \(n) session\(n == 1 ? "" : "s") — see why" : "The coach has \(p == 1 ? "a suggestion" : "suggestions") — see why"
        return first + (n > 0 && p > 0 ? " · \(p) need\(p == 1 ? "s" : "") your OK" : "")
    }

    /// Undo one automatic change: the session is recomputed from its original values with the remaining changes, and
    /// that change is never made again for that session.
    func undoAdaptation(_ key: String) {
        guard let adj = adaptations.first(where: { $0.key == key }) else { return }
        if !dismissedAdaptations.contains(key) { dismissedAdaptations.append(key) }
        approvedAdaptations.removeAll { $0 == key }
        let remaining = adaptations.filter { $0.workoutId == adj.workoutId && $0.key != key }
        if let i = plan.firstIndex(where: { $0.id == adj.workoutId }), !plan[i].done, !plan[i].edited {
            let base = plan[i].restoredOriginal
            if remaining.isEmpty { plan[i] = base }
            else { var x = AdaptiveRules.apply(remaining, to: base, entries: originalEntries(for: base)); x.coachOriginal = base.planSnapshot; plan[i] = x }
        }
        adaptations.removeAll { $0.key == key }
        trimAdaptationKeys()
    }

    /// "Restore original plan": every open session back to its planned values; none of those changes is made again.
    func restoreOriginalPlan() {
        var p = plan
        for i in p.indices where p[i].coachOriginal != nil && !p[i].done && !p[i].edited { p[i] = p[i].restoredOriginal }
        var d = dismissedAdaptations
        for a in adaptations where !d.contains(a.key) { d.append(a.key) }
        let keys = Set(adaptations.map { $0.key })
        approvedAdaptations.removeAll { keys.contains($0) }
        dismissedAdaptations = d
        plan = p
        adaptations = []
        trimAdaptationKeys()
    }

    /// Accept a proposal: its adjustments become approved (applied while their reason holds), then the engine runs.
    @discardableResult
    func acceptAdaptiveProposal(_ p: AdaptiveProposal, now: Date = Date()) -> Bool {
        guard !p.adjustments.isEmpty else { return false }
        var ap = approvedAdaptations
        for a in p.adjustments where !ap.contains(a.key) { ap.append(a.key) }
        approvedAdaptations = ap
        let keys = Set(p.adjustments.map { $0.key })
        dismissedAdaptations.removeAll { keys.contains($0) }
        adaptiveProposals.removeAll { $0.id == p.id }
        _ = runAdaptation(now: now)
        return true
    }
    func dismissAdaptiveProposal(_ p: AdaptiveProposal) {
        if !dismissedAdaptations.contains(p.id) { dismissedAdaptations.append(p.id) }
        adaptiveProposals.removeAll { $0.id == p.id }
        trimAdaptationKeys()
    }
    private func trimAdaptationKeys() {
        if dismissedAdaptations.count > 300 { dismissedAdaptations.removeFirst(dismissedAdaptations.count - 300) }
        if approvedAdaptations.count > 300 { approvedAdaptations.removeFirst(approvedAdaptations.count - 300) }
    }

    // MARK: B — sessions built from the rider's own exercises (only once a split was chosen)
    func programmedSession(_ w: Workout) -> Workout {
        guard profile.trainingMode.includesLifting, profile.strengthSplit != nil, w.kind == .strength, w.templateId == nil, w.plannedEntries == nil else { return w }
        let e = StrengthProgrammer.entries(focus: w.strengthFocus ?? .fullBody, label: w.note, templates: templates, preserved: profile.preservedTemplateIds,
                                           custom: customExercises, catalogue: ExerciseCatalogue.builtIn, equipment: equipment)
        guard !e.isEmpty else { return w }
        var x = w; x.plannedEntries = e; x.generatedEntries = true
        return x
    }

    /// Profile › Training profile › Hybrid plan: optionally new days from the answers, both weeks rebuilt (hand edits,
    /// completed sessions and past days kept), then the coach adapts.
    func rebuildFromHybridAnswers(newDays: Bool, now: Date = Date()) {
        if newDays { availability = WeeklyAvailability.suggested(for: profile) }
        _ = regenerate(weekOf: now, replaceEdited: false)
        _ = regenerate(weekOf: Calendar.current.date(byAdding: .day, value: 7, to: now)!, replaceEdited: false)
        _ = runAdaptation(now: now)
    }
}
