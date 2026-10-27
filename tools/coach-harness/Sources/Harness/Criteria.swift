import Foundation
@testable import BikeComputer

/// Acceptance criteria declared BEFORE any profile was run (see CYCLIFT_COACH_SCIENTIFIC_AUDIT.md §10.1).
/// kind "spec" = what the app itself promises (docs + code comments); "safety" = must hold for a public coach;
/// "science-advisory" = a literature-based expectation the owner asked about (reported, not counted in pass/fail).
enum Criteria {
    static func generic(_ rep: Report, _ s: Store, _ r: AdaptationResult, _ c: Case) -> [CriterionOut] {
        var out: [CriterionOut] = []
        let p = s.profile
        let nextEnd = cal.date(byAdding: .day, value: 7, to: nextMonday)!
        let nw = s.plan.filter { $0.date >= nextMonday && $0.date < nextEnd }
        let future = s.plan.filter { cal.startOfDay(for: $0.date) >= today && !$0.done }
        func add(_ id: String, _ kind: String, _ text: String, _ ok: Bool, _ d: String) { out.append(CriterionOut(id: id, kind: kind, text: text, pass: ok, detail: d)) }

        // G1 session counts, or a visible message (never a silent violation)
        let rides = nw.filter { $0.kind.isRide && !$0.skipped }.count, lifts = nw.filter { $0.kind == .strength && !$0.skipped }.count
        let wantR = p.trainingMode.includesCycling ? p.cyclingDaysPerWeek : 0, wantL = p.trainingMode.includesLifting ? p.liftDaysPerWeek : 0
        let countsOK = rides == wantR && lifts == wantL
        let surfaced = !rep.consistency.isEmpty
        add("G1-session-counts", "spec", "Next week has exactly the requested rides and lifts, or the mismatch is shown to the rider", countsOK || surfaced,
            "requested \(wantR) rides / \(wantL) lifts; generated \(rides) / \(lifts)" + (countsOK ? "" : (surfaced ? " — surfaced: \(rep.consistency.joined(separator: " | "))" : " — NOT surfaced anywhere (silent)")))
        // G2 budgets
        let rm = PlanEngine.rideMinutes(nw), lm = PlanEngine.liftMinutes(nw)
        let bOK = (!p.trainingMode.includesCycling || rm <= p.hoursPerWeek * 60) && (p.liftingHoursPerWeek <= 0 || !p.trainingMode.includesLifting || lm <= p.liftingHoursPerWeek * 60)
        add("G2-budgets", "spec", "Planned riding and lifting minutes never exceed their weekly budgets", bOK, "riding \(rm)/\(p.hoursPerWeek * 60) min, lifting \(lm)/\(p.liftingHoursPerWeek * 60) min")
        // G3 training days / rest days
        if let n = p.trainingDaysPerWeek {
            let days = Set(nw.filter { $0.kind != .rest }.map { cal.startOfDay(for: $0.date) }).count
            add("G3-training-days", "spec", "Number of training days ≤ the rider's training days; the rest are rest days", days <= n, "\(days) training days vs \(n) requested")
        }
        // G4 equipment / exclusions / avoid / temporary blocks
        // revised after run 1: the rider's OWN routines may contain exercises they cannot do; the app's rule is that the
        // coach never progresses them and offers a replacement only as a proposal (checked here), never silently.
        var bad: [String] = []
        var routineIssues: [String] = []
        for w in future where w.kind == .strength {
            for e in s.plannedEntries(for: w) {
                guard let ex = s.allExercises.first(where: { $0.id == e.exerciseId }) else { continue }
                let blockedByPrefs = s.strengthPrefs.avoids(ex.id) || s.strengthPrefs.blocked(ex.id, now: realNow)
                if w.generatedEntries || w.rationale != nil {
                    if !s.equipment.canDo(ex) || blockedByPrefs { bad.append("\(ds(w.date)) \(ex.name) [\(ex.equipment.joined(separator: ","))]") }
                } else if !s.equipment.canDo(ex) {
                    routineIssues.append(ex.id)
                    if r.adjustments.contains(where: { $0.workoutId == w.id && { if case .weight(let id, _) = $0.change { return id == ex.id }; if case .reps(let id, let d) = $0.change { return id == ex.id && d > 0 }; return false }($0) }) { bad.append("\(ds(w.date)) routine exercise \(ex.name) progressed although not doable") }
                }
            }
        }
        for id in Set(routineIssues) where !r.proposals.contains(where: { $0.reason == .replaceExercise && $0.id.contains(id) }) { bad.append("routine exercise \(id) not doable and no replacement proposal") }
        add("G4-equipment", "safety", "Coach-built sessions never prescribe unowned / excluded / avoided exercises; a rider routine with such an exercise gets a replacement PROPOSAL and is never progressed (revised after run 1)", bad.isEmpty, bad.isEmpty ? "all exercises doable with \(s.equipment.isSet ? s.equipment.owned.sorted().joined(separator: ",") : "unset equipment (all allowed)")" : bad.joined(separator: "; "))
        // G5 pain
        let areas = r.analysis.painAreas
        if !areas.isEmpty {
            var v: [String] = []
            for a in r.adjustments where a.category == .progression {
                let w = s.plan.first { $0.id == a.workoutId }
                switch a.change {
                case .weight(let e, _), .reps(let e, _), .sets(let e, _):
                    if let pat = s.plannedEntries(for: w!).first(where: { $0.exerciseId == e })?.pattern ?? s.allExercises.first(where: { $0.id == e })?.pattern, r.analysis.painBlocks(pat) { v.append("progression on \(e) (\(pat.rawValue))") }
                case .intervalReps, .minutes: if r.analysis.painBlocksCycling { v.append("cycling progression: \(a.summary)") }
                default: break
                }
            }
            let tags = areas.reduce(into: Set<LoadTag>()) { $0.formUnion(LoadTag.forPain($1)) }
            for w in future where w.kind == .strength && w.generatedEntries {
                for e in s.plannedEntries(for: w) { if let ex = s.allExercises.first(where: { $0.id == e.exerciseId }), !ExerciseLibrary.meta(ex).tags.isDisjoint(with: tags) { v.append("\(ds(w.date)) planner kept \(ex.name) (\(ExerciseLibrary.meta(ex).tags.intersection(tags).map { $0.rawValue }.joined(separator: ",")))") } }
            }
            if r.summary.painAdvice == nil { v.append("no pain advice shown") }
            add("G5-pain", "safety", "After a concerning-pain report: no progression in that area, restricted loading left out, advice shown", v.isEmpty, v.isEmpty ? "areas \(areas.map { $0.rawValue }.joined(separator: ",")) respected" : v.joined(separator: "; "))
        }
        // G6 interference (heavy legs within a day before a key ride / later the same day)
        var iv: [String] = []
        for w in nw where w.kind == .strength {
            let day = cal.startOfDay(for: w.date), next = cal.date(byAdding: .day, value: 1, to: day)!
            let key = nw.first { StrengthPlanner.isKeyRide($0) && (cal.isDate($0.date, inSameDayAs: next) || (cal.isDate($0.date, inSameDayAs: day) && $0.sequence > w.sequence)) }
            guard let k = key else { continue }
            let entries = s.plannedEntries(for: w)
            let lower = entries.filter { e in s.allExercises.first(where: { $0.id == e.exerciseId }).map { ExerciseLibrary.meta($0).slot.isLower } ?? false }
            if lower.isEmpty { continue }
            if w.rationale != nil {
                let unlightened = lower.filter { w.rationale?.exercise($0.exerciseId)?.cycling == nil }
                if !unlightened.isEmpty { iv.append("\(ds(w.date)) \(unlightened.map { $0.name }.joined(separator: ",")) before \(k.kind.title) \(ds(k.date)) not lightened") }
            } else if !rep.hybridFindingsNextWeek.contains(where: { $0.contains("heavy leg") || $0.contains("back to back") }) {
                iv.append("\(ds(w.date)) routine with leg work before \(k.kind.title) \(ds(k.date)) — no finding")
            }
        }
        add("G6-interference", "spec", "Leg work within ~24 h before a key ride (or before it the same day) is lightened or flagged", iv.isEmpty, iv.isEmpty ? "no unhandled leg-before-key-ride pairs next week" : iv.joined(separator: "; "))
        // G6b back-to-back hard days surfaced
        let hardDays = Set(nw.filter { !$0.skipped && (($0.kind.isRide && $0.kind.zone >= 3) || ($0.kind == .strength && ($0.strengthFocus?.loadsLegs ?? false))) }.map { cal.startOfDay(for: $0.date) }).sorted()
        var b2b: [String] = []
        for i in hardDays.indices.dropFirst() where cal.dateComponents([.day], from: hardDays[i - 1], to: hardDays[i]).day == 1 { b2b.append("\(ds(hardDays[i - 1]))→\(ds(hardDays[i]))") }
        let flagged = rep.hybridFindingsNextWeek.contains { $0.contains("back to back") || $0.contains("heavy leg") }
        add("G6b-hard-days", "spec", "Two hard days in a row (hard ride / leg lift) are avoided or shown to the rider", b2b.isEmpty || flagged, b2b.isEmpty ? "none" : "\(b2b.joined(separator: ", ")) — \(flagged ? "flagged by HybridCoach" : "not flagged")")
        // G7 bounds of automatic changes
        var bv: [String] = []; var bv2: [String] = []
        for a in r.adjustments {
            guard let w = s.plan.first(where: { $0.id == a.workoutId }) else { bv.append("unknown workout"); continue }
            let o = w.restoredOriginal
            if w.done || cal.startOfDay(for: w.date) < today { bv.append("touches a past/completed session") }
            if o.fixed && !s.approvedAdaptations.contains(a.key) { bv.append("fixed day changed without approval: \(a.summary)") }
            if o.edited { bv.append("edited session changed") }
            switch a.change {
            case .weight(let e, let k):
                let top = (s.originalEntries(for: o).first { $0.exerciseId == e }?.sets.compactMap { $0.weightKg }.max()) ?? 0
                if k > min(2.5, top * 0.05) + 0.001 { bv.append("weight +\(k) kg on \(top) kg") }
                // G7-bounds-b (remediation criterion, G7 kept unchanged): independent review F-17 — one smallest step, never
                // more than 2.5 kg, with a caution in the Why? above 10 % of the load (ACSM 2009: 2–10 % increments)
                if k > 2.5 + 0.001 || (top > 0 && k / top > 0.1 && !a.why.contains("big jump")) { bv2.append("weight +\(k) kg on \(top) kg") }
            case .reps(_, let d): if abs(d) != 1 { bv.append("reps \(d)") }
            case .sets(_, let d): if abs(d) != 1 { bv.append("sets \(d)") }
            case .minutes(let d): if abs(d) > AdaptiveRules.roundTo5(Double(o.minutes) * 0.1) { bv.append("minutes \(d) on \(o.minutes)") }
            case .kind(let k): if !(k.zone < o.kind.zone) { bv.append("kind \(o.kind) → \(k) is not easier") }
            case .intervalReps(let d): if d != 1 { bv.append("intervals \(d)") }
            case .replace: if !s.approvedAdaptations.contains(a.key) { bv.append("replacement applied without approval") }
            }
        }
        add("G7-bounds", "safety", "Every automatic change is bounded (±1 rep/set, ≤2.5 kg and ≤5 %, ±10 % time, one zone easier, +1 interval) and never touches fixed / edited / past sessions without approval", bv.isEmpty, bv.isEmpty ? "\(r.adjustments.count) adjustment(s), all within bounds" : bv.joined(separator: "; "))
        // non-weight violations count for G7-bounds-b too
        let other = bv.filter { !$0.hasPrefix("weight +") }
        add("G7-bounds-b", "remediation", "As G7, with the load step of independent review F-17: one smallest step, ≤ 2.5 kg, a caution above 10 % of the load (G7 kept and reported)", (other + bv2).isEmpty, (other + bv2).isEmpty ? "\(r.adjustments.count) adjustment(s), all within the F-17 bounds" : (other + bv2).joined(separator: "; "))
        // G8 determinism / no stacking
        let in1 = s.adaptationInput(now: realNow)
        let k1 = AdaptationEngine.run(in1).adjustments.map { $0.key }.sorted(), k2 = AdaptationEngine.run(in1).adjustments.map { $0.key }.sorted()
        let before = s.plan
        _ = s.runAdaptation(now: realNow)
        let stable = s.plan.map { $0.planSnapshot } == before.map { $0.planSnapshot }
        add("G8-deterministic", "spec", "Same inputs → same decisions; re-running the coach never stacks changes", k1 == k2 && stable, "run1 \(k1.count) / run2 \(k2.count) keys equal=\(k1 == k2); plan unchanged after re-run=\(stable)")
        // G9 beginner safety
        let ctx = s.plannerContext(now: realNow)
        if ctx.experience == .beginner && p.trainingMode.includesLifting {
            var v: [String] = []
            for w in future where w.kind == .strength && w.rationale != nil {
                for e in s.plannedEntries(for: w) {
                    guard let ex = s.allExercises.first(where: { $0.id == e.exerciseId }) else { continue }
                    if ExerciseLibrary.meta(ex).difficulty > 1 { v.append("\(ex.name) difficulty \(ExerciseLibrary.meta(ex).difficulty)") }
                    if let t = w.rationale?.exercise(e.exerciseId)?.targetRPE, t > 7 { v.append("\(ex.name) RPE \(t)") }
                    if w.rationale?.exercise(e.exerciseId)?.role == "main lift", let m = e.sets.map({ $0.reps }).min(), m < 6 { v.append("\(ex.name) \(m) reps") }
                }
            }
            add("G9-beginner", "safety", "Beginners get only difficulty-1 exercises, target RPE ≤ 7 and ≥ 6 reps on main lifts", v.isEmpty, v.isEmpty ? "ok" : Array(Set(v)).sorted().joined(separator: "; "))
        }
        // G10 movement coverage (planner-built weeks with ≥ 2 lifts, or 1 full-body)
        let built = nw.filter { $0.kind == .strength && $0.rationale != nil }
        if !built.isEmpty, built.count >= 2 || built.contains(where: { $0.strengthFocus == .fullBody }) {
            var fam = Set<String>()
            for w in built { for e in s.plannedEntries(for: w) { if let ex = s.allExercises.first(where: { $0.id == e.exerciseId }) { let sl = ExerciseLibrary.meta(ex).slot; fam.insert(sl == .lunge ? "squat" : sl.family.rawValue) } } }
            let need = ["squat", "hinge", "push", "pull"]
            let miss = need.filter { !fam.contains($0) }
            add("G10-coverage", "spec", "Coach-built weeks cover squat/knee-dominant, hinge, push and pull", miss.isEmpty, miss.isEmpty ? "covered: \(fam.sorted().joined(separator: ","))" : "missing \(miss.joined(separator: ","))")
        }
        // S1 weekly working sets per region (science-advisory)
        if !built.isEmpty {
            var reg: [String: Int] = [:]
            for w in built { for e in s.plannedEntries(for: w) { if let ex = s.allExercises.first(where: { $0.id == e.exerciseId }) { reg[StrengthPlanner.region(ExerciseLibrary.meta(ex).slot), default: 0] += e.sets.count } } }
            let txt = ["lower", "push", "pull", "core", "arms", "accessory"].map { "\($0) \(reg[$0] ?? 0)" }.joined(separator: ", ")
            if ctx.goal == .hypertrophy {
                let low = ["lower", "push", "pull"].filter { (reg[$0] ?? 0) < 10 }
                add("S1-volume-hypertrophy", "science-advisory", "Hypertrophy goal: ≥ 10 weekly sets per major region (Schoenfeld et al. 2017 dose–response)", low.isEmpty, "weekly sets: \(txt)")
            } else {
                add("S1-volume", "science-advisory", "Weekly sets per region reported (no hypertrophy goal: ≥ 2–4 sets/region/week accepted as a minimum dose)", ["lower", "push", "pull"].allSatisfy { (reg[$0] ?? 0) >= 2 || !p.trainingMode.includesLifting }, "weekly sets: \(txt)")
            }
            if ctx.goal == .strength {
                let mains = built.flatMap { w in s.plannedEntries(for: w).filter { w.rationale?.exercise($0.exerciseId)?.role == "main lift" }.map { ($0.name, $0.sets.map { $0.reps }.max() ?? 0) } }
                let high = mains.filter { $0.1 > 6 }
                add("S3-strength-reps", "science-advisory", "Strength goal: main lifts ≤ 6 reps (ACSM 2009 / NSCA)", high.isEmpty, mains.map { "\($0.0) \($0.1)" }.joined(separator: ", "))
            }
        }
        // S2 intensity distribution of planned riding
        if p.trainingMode.includesCycling, rm > 0 {
            let hard = nw.filter { $0.kind.isRide && $0.kind.zone >= 3 && !$0.skipped }.reduce(0) { $0 + $1.minutes }
            let share = Double(hard) / Double(rm)
            add("S2-intensity-distribution", "science-advisory", "≤ ~25 % of planned ride time in hard sessions (Zone ≥ 3) — polarised/pyramidal distributions (Seiler 2010; Stöggl & Sperlich 2014)", share <= 0.25,
                String(format: "%d of %d ride minutes in Zone ≥ 3 sessions (%.0f %%; session-level, includes warm-up/cool-down)", hard, rm, share * 100))
        }
        return out
    }
}
