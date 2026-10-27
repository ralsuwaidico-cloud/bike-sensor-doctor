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
        // records waiting for the rider's review (migration) are not evidence of anything until confirmed
        return AdaptationInput(profile: profile, plan: plan, rides: rides, strength: strength.filter { !$0.awaitingReview }, availability: effectiveAvailability, equipment: equipment,
                               catalogue: allExercises, templates: templates, originalEntries: entries, dismissed: Set(dismissedAdaptations),
                               approved: Set(approvedAdaptations), active: adaptations, units: settings.units, now: now, calendar: .current,
                               painClearances: painClearances)
    }

    /// Pain areas currently holding progression (the same analysis the coach and the planner use).
    func activePainAreas(now: Date = Date()) -> [PainArea] { TrainingAnalyzer.analyze(adaptationInput(now: now)).painAreas }
    func painReviewDue(now: Date = Date()) -> [PainArea] { TrainingAnalyzer.analyze(adaptationInput(now: now)).painReviewDue }

    /// The rider confirms a reported pain has gone: that area is released at once (audit G-06), the coach-built
    /// sessions are rebuilt and the coach runs again. Later reports hold the area again.
    func confirmPainGone(_ area: PainArea, now: Date = Date()) {
        painClearances.append(PainClearance(area: area, at: now))
        if painClearances.count > 50 { painClearances.removeFirst(painClearances.count - 50) }
        refreshGeneratedSessions(now: now)
        _ = runAdaptation(now: now)
    }

    /// Analyze → Adapt: runs the engine and applies its result to the open future sessions.
    @discardableResult
    func runAdaptation(now: Date = Date()) -> AdaptationResult {
        let r = AdaptationEngine.run(adaptationInput(now: now))
        applyAdaptation(r, now: now)
        return r
    }

    /// Same planned session apart from generated entry / set ids (and the stored original's ids).
    static func sameContent(_ a: Workout, _ b: Workout) -> Bool {
        func key(_ e: [ExerciseEntry]?) -> [String] { (e ?? []).map { x in "\(x.exerciseId)|\(x.name)|\(x.superset ?? "")|\(x.notes)|" + x.sets.map { "\($0.reps),\($0.weightKg ?? -1),\($0.bodyweight),\($0.unilateral),\($0.rpe ?? -1),\($0.done)" }.joined(separator: ";") } }
        func snap(_ s: WorkoutPlanSnapshot?) -> String { s.map { "\($0.kind)|\($0.minutes)|\($0.intervalReps ?? -1)|\($0.generatedEntries)|" + key($0.plannedEntries).joined(separator: "#") } ?? "-" }
        var a0 = a, b0 = b
        a0.plannedEntries = nil; b0.plannedEntries = nil; a0.coachOriginal = nil; b0.coachOriginal = nil
        return a0 == b0 && key(a.plannedEntries) == key(b.plannedEntries) && snap(a.coachOriginal) == snap(b.coachOriginal)
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
            // re-running the coach with the same inputs must not change the plan: a routine's entries are prefilled
            // afresh (new ids) on every run, so the same content keeps the ids already in the plan
            if !Self.sameContent(x, w) { p[i] = x }
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
        let before = plan
        rides[i].checkIn = c
        refreshGeneratedSessions(now: now)      // planner: fatigue / pain from the check-in shape coach-built sessions
        let r = runAdaptation(now: now)
        noteCheckInRebuild(before: before, now: now)
        return r
    }
    @discardableResult
    func recordCheckIn(_ c: CheckIn, strengthId: UUID, now: Date = Date()) -> AdaptationResult? {
        guard let i = strength.firstIndex(where: { $0.id == strengthId }) else { return nil }
        let before = plan
        strength[i].checkIn = c
        refreshGeneratedSessions(now: now)
        let r = runAdaptation(now: now)
        noteCheckInRebuild(before: before, now: now)
        return r
    }

    /// Remembers which open sessions this check-in changed (planner rebuild and/or adaptive changes), as they were, with
    /// a one-line explanation each, so the result screen can offer one Undo for all of them.
    func noteCheckInRebuild(before: [Workout], now: Date = Date()) {
        var changed: [Workout] = [], lines: [String] = []
        for b in before where b.kind == .strength && !b.done {
            guard let a = plan.first(where: { $0.id == b.id }), a.plannedEntries != b.plannedEntries else { continue }
            changed.append(b)
            let sb = (b.plannedEntries ?? []).reduce(0) { $0 + $1.sets.count }, sa = (a.plannedEntries ?? []).reduce(0) { $0 + $1.sets.count }
            let removed = Set((b.plannedEntries ?? []).map { $0.name }).subtracting((a.plannedEntries ?? []).map { $0.name }).sorted()
            var t = "\(a.date.dayAndDate) · \(a.displayTitle): \(sb == sa ? "\(sa) sets" : "\(sb) → \(sa) sets")"
            if !removed.isEmpty { t += ", left out: \(removed.joined(separator: ", "))" }
            if let why = a.rationale?.notes.first(where: { $0.hasPrefix("Deload") || $0.lowercased().contains("pain") }) { t += ". \(why)" }
            else if let adj = adaptations.first(where: { $0.workoutId == a.id }) { t += ". \(adj.summary)" }
            lines.append(t)
        }
        checkInRebuild = changed.isEmpty ? nil : CheckInRebuild(before: changed, lines: lines, at: now)
    }

    /// Undo everything the latest check-in changed: those sessions go back exactly as they were and are kept that way
    /// (marked as the rider's own, so neither the planner nor the adaptive coach rebuilds them on its own again).
    func undoCheckInRebuild() {
        guard let r = checkInRebuild else { return }
        var p = plan, d = dismissedAdaptations
        let ids = Set(r.before.map { $0.id })
        for b in r.before { if let i = p.firstIndex(where: { $0.id == b.id }), !p[i].done { var x = b; x.edited = true; p[i] = x } }
        for a in adaptations where ids.contains(a.workoutId) && !d.contains(a.key) { d.append(a.key) }
        adaptations.removeAll { ids.contains($0.workoutId) }
        dismissedAdaptations = d
        plan = p
        checkInRebuild = nil
        trimAdaptationKeys()
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

    // MARK: B — coach-built sessions (with or without a chosen split; "Coach decides" included — audit G-04)
    /// Quality release: built by the personalised planner (StrengthPlanner) — goal, priority, experience, equipment,
    /// preferences, logged performance and the rides around the session — with its reasons stored for "Why?".
    func programmedSession(_ w: Workout, ctx: PlannerContext? = nil) -> Workout {
        guard profile.trainingMode.includesLifting, w.kind == .strength, w.templateId == nil, w.plannedEntries == nil else { return w }
        let b = StrengthPlanner.build(for: w, ctx: ctx ?? plannerContext())
        guard !b.entries.isEmpty else { return w }
        var x = w; x.plannedEntries = b.entries; x.generatedEntries = true; x.rationale = b.rationale
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

/// What the latest check-in changed in the open plan (for the result screen's Undo).
struct CheckInRebuild: Equatable {
    var before: [Workout]
    var lines: [String]
    var at: Date
}
