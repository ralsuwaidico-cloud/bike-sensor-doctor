import Foundation


// =====================================================================================================================
// MARK: - Phase 1 rebuild fix: a significant change of a planned session (type, duration, supersets, a session turned
// into strength) rebuilds and validates the prescription, shows a before/after preview and is saved only on Apply.
// Approved 30 Oct 2026 (Phase 1 only). The validator READS CoachReadiness and never changes it: no medical rule changes.
// Design: coach-review/arch/REBUILD_FIX_SPEC.md (rev 2).
// =====================================================================================================================

/// The athlete's explicit choice for one session (type and/or duration, plus the structure preference it was made with).
struct RiderChoice: Codable, Equatable {
    var focus: StrengthFocus?
    var minutes: Int?
    var prefersSupersets: Bool?
    var at: Date
    var origin: String          // "athlete" | "ai" | "coach"
    var fromFocus: StrengthFocus?
    var fromMinutes: Int?
}

// MARK: exercise data the validator needs (S&C review required changes 1 and 6)
enum LiftDominance: String, Codable { case knee, hip, none }

extension ExerciseLibrary {
    /// Single-leg entries that are hip-dominant (the catalogue maps every single-leg exercise to `.lunge`).
    static let hipDominantSingleLeg: Set<String> = ["ex-044", "ex-048", "ex-049", "ex-055"]
    static func dominance(_ e: Exercise) -> LiftDominance {
        let m = meta(e)
        switch m.slot {
        case .squat: return m.compound ? .knee : .none
        case .hinge: return m.compound ? .hip : .none
        case .lunge:
            let n = e.name.lowercased()
            if hipDominantSingleLeg.contains(e.id) || ["romanian", "deadlift", "hip thrust", "glute bridge"].contains(where: { n.contains($0) }) { return .hip }
            return .knee
        default: return .none
        }
    }
    /// Apparatus the base catalogue does not list. Any one item of the set is enough. Only checked when equipment is set.
    /// Phase 1 checks only items the equipment screen can record today; the wider apparatus vocabulary (low bar, rings,
    /// dip bars, band anchor, box) belongs to the later equipment onboarding and is NOT checked here.
    static let apparatus: [String: Set<String>] = [
        "ex-104": ["pull-up bar"],                 // assisted pull-up hangs from a bar
    ]
    static func apparatusOK(_ e: Exercise, equipment eq: EquipmentProfile) -> Bool {
        guard eq.isSet else { return apparatus[e.id] == nil }       // RC3 / ENG-H1: unset equipment owns no apparatus
        let have = Set(eq.owned.map(EquipmentProfile.normalised))
        if let need = apparatus[e.id], need.isDisjoint(with: have) { return false }
        return true
    }
    static func gripLimited(_ e: Exercise) -> Bool {
        let m = meta(e), n = e.name.lowercased()
        if m.slot == .horizontalPull || m.slot == .verticalPull || m.slot == .carry { return true }
        let loadedDB = e.equipment.contains("dumbbell") || e.equipment.contains("kettlebell") || e.equipment.contains("barbell")
        if m.slot == .hinge && loadedDB && !["hip thrust", "glute bridge"].contains(where: { n.contains($0) }) { return true }
        if m.slot == .lunge && loadedDB && !n.contains("goblet") { return true }
        return false
    }
}

// MARK: duration model (S&C review §1 rules 6.1–6.4)
struct DurationModel {
    var warmUp = 180.0, rampSet = 60.0, secPerRep = 3.5, sideSwitch = 5.0, logging = 5.0
    var transition = 20.0, setupPerBlock = 60.0
    /// Seconds per dumbbell load change: 15 quick-change (default), 60 spin-lock.
    var loadChange = 15.0

    static func isHoldName(_ n: String) -> Bool { let l = n.lowercased(); return ["plank", "hold", "wall sit", "hollow"].contains { l.contains($0) } }

    /// Consecutive entries with the same superset letter form one block; others are single blocks.
    static func blocks(_ es: [ExerciseEntry]) -> [[ExerciseEntry]] {
        var out: [[ExerciseEntry]] = []
        for e in es {
            if let g = e.superset, let last = out.last, last.first?.superset == g { out[out.count - 1].append(e) } else { out.append([e]) }
        }
        return out
    }

    /// Elapsed seconds. `topReps` gives the reps to plan for (the top of the prescribed range for TIME-001).
    func seconds(_ es: [ExerciseEntry], catalogue: [Exercise], topReps: (ExerciseEntry) -> Int = { e in e.sets.map(\.reps).max() ?? 8 }) -> Double {
        guard !es.isEmpty else { return 0 }
        var t = warmUp
        let first = es[0]
        let firstEx = catalogue.first { $0.id == first.exerciseId }
        let heavyLowerFirst = firstEx.map { ExerciseLibrary.meta($0).slot.isLower && ExerciseLibrary.meta($0).compound } == true && first.sets.contains { $0.weightKg != nil && !$0.bodyweight }
        t += heavyLowerFirst ? 2 * rampSet : rampSet
        let bs = DurationModel.blocks(es)
        for (bi, b) in bs.enumerated() {
            t += setupPerBlock
            let rounds = b.map { $0.sets.count }.max() ?? 0
            let weighted = Set(b.compactMap { $0.sets.first?.weightKg })
            for r in 0..<rounds {
                let inRound = b.filter { $0.sets.count > r }
                for (k, e) in inRound.enumerated() {
                    let st = e.sets[r]
                    let reps = Double(DurationModel.isHoldName(e.name) ? st.reps : max(st.reps, topReps(e)))
                    let perSide = DurationModel.isHoldName(e.name) ? reps : reps * secPerRep
                    t += perSide * (st.unilateral ? 2 : 1) + (st.unilateral ? sideSwitch : 0) + logging
                    if k < inRound.count - 1 { t += transition }
                }
                if b.count > 1, weighted.count > 1 { t += loadChange * Double(weighted.count) }
                let lastRoundOfSession = bi == bs.count - 1 && r == rounds - 1
                if !lastRoundOfSession { t += Double(inRound.compactMap { $0.restSeconds }.max() ?? 90) }
            }
        }
        return t
    }
    func minutes(_ es: [ExerciseEntry], catalogue: [Exercise], topReps: (ExerciseEntry) -> Int = { e in e.sets.map(\.reps).max() ?? 8 }) -> Double {
        seconds(es, catalogue: catalogue, topReps: topReps) / 60
    }
}

// MARK: validation contract
enum ValidationOutcome: String, Codable { case pass = "PASS", adjust = "ADJUST", block = "BLOCK" }
enum IssueSeverity: String, Codable { case info, warning, error }

struct ValidationIssue: Codable, Equatable {
    var ruleId: String
    var severity: IssueSeverity
    var outcome: ValidationOutcome
    var workoutId: UUID?
    var explanation: String
    var remedy: String
    var autoRepairAllowed: Bool
    var needsConfirmation: Bool
}

struct ValidationReport: Codable, Equatable {
    var issues: [ValidationIssue] = []
    var repairs: [String] = []
    var attempts = 0
    var estimatedMinutes: Double? = nil
    var outcome: ValidationOutcome { issues.contains { $0.outcome == .block } ? .block : issues.contains { $0.outcome == .adjust } ? .adjust : .pass }
    var needsConfirmation: Bool { issues.contains { $0.needsConfirmation } }
    func has(_ id: String) -> Bool { issues.contains { $0.ruleId == id } }
    func issue(_ id: String) -> ValidationIssue? { issues.first { $0.ruleId == id } }
}

struct ValidationContext {
    var readiness: CoachReadiness
    var equipment: EquipmentProfile
    var catalogue: [Exercise]
    var plan: [Workout] = []
    var profile: RiderProfile
    var prohibitedWeekdays: Set<Int> = []
    var prefersSupersets: Bool? = nil
    var planner: PlannerContext? = nil
    var calendar: Calendar = .current
    var duration = DurationModel()
    /// TIME-001 margin: the estimate must be ≤ maximum − margin.
    var timeMarginMinutes = 1.0

    init(planner c: PlannerContext, prefersSupersets: Bool? = nil, prohibitedWeekdays: Set<Int> = []) {
        readiness = c.readiness; equipment = c.equipment; catalogue = c.catalogue; plan = c.plan; profile = c.profile
        self.prefersSupersets = prefersSupersets; self.prohibitedWeekdays = prohibitedWeekdays; planner = c; calendar = c.calendar
    }
}

enum WorkoutValidator {
    struct Coverage: Equatable { var knee = 0, hip = 0, push = 0, pull = 0, lowerTotal = 0, trunk = 0 }

    /// Working sets from COMPOUND slots only (accessories, arms and isolation never count, S&C required change 1).
    static func coverage(_ es: [ExerciseEntry], catalogue: [Exercise]) -> Coverage {
        var c = Coverage()
        for e in es {
            guard let ex = catalogue.first(where: { $0.id == e.exerciseId }) else { continue }
            let m = ExerciseLibrary.meta(ex), n = e.sets.count
            if m.slot == .core { c.trunk += n }
            guard m.compound else { continue }
            switch m.slot {
            case .horizontalPush, .verticalPush: c.push += n
            case .horizontalPull, .verticalPull: c.pull += n
            default: break
            }
            switch ExerciseLibrary.dominance(ex) { case .knee: c.knee += n; c.lowerTotal += n; case .hip: c.hip += n; c.lowerTotal += n; case .none: break }
        }
        return c
    }

    static func topReps(_ e: ExerciseEntry, rationale: SessionRationale?, ctx: ValidationContext) -> Int {
        let logged = e.sets.map(\.reps).max() ?? 8
        guard let p = ctx.planner, let r = rationale?.exercise(e.exerciseId), let role = StrengthPlanner.Role(rawValue: r.role) else { return logged }
        var d = StrengthPlanner.dose(role: role, goal: p.goal, experience: p.experience)
        if let lo = ctx.readiness.minStrengthReps, d.reps.lowerBound < lo { d.reps = lo...max(lo + 4, d.reps.upperBound) }
        if let ex = ctx.catalogue.first(where: { $0.id == e.exerciseId }), StrengthPlanner.bodyweightOnly(ex, ctx: p), !StrengthPlanner.isHold(ex) { d.reps = max(10, d.reps.lowerBound)...max(15, d.reps.upperBound) }
        return max(logged, d.reps.upperBound)
    }

    static func estimate(_ es: [ExerciseEntry], rationale: SessionRationale?, ctx: ValidationContext) -> Double {
        ctx.duration.minutes(es, catalogue: ctx.catalogue) { topReps($0, rationale: rationale, ctx: ctx) }
    }

    static func required(_ f: StrengthFocus?) -> (ruleId: String, need: [(String, KeyPath<Coverage, Int>)])? {
        switch f ?? .fullBody {
        case .fullBody: return ("SPLIT-001", [("knee-dominant", \.knee), ("hip-dominant", \.hip), ("push", \.push), ("pull", \.pull)])
        case .upper: return ("SPLIT-002", [("push", \.push), ("pull", \.pull)])
        case .lower, .legs: return ("SPLIT-003", [("knee-dominant", \.knee), ("hip-dominant", \.hip)])
        case .push: return ("SPLIT-004", [("push", \.push)])
        case .pull: return ("SPLIT-004", [("pull", \.pull)])
        case .custom: return nil
        }
    }

    /// Ride steps' total minutes as the app builds them today (Models.swift `steps(ftp:)`), rests included.
    static func rideStepsMinutes(_ w: Workout) -> Int? {
        // RC3 / ENG-E5: the fitted steps (Rc3Engine RideSteps) — their sum equals the session minutes by construction
        guard w.kind.isRide else { return nil }
        return w.rideSteps.reduce(0) { $0 + $1.minutes }
    }

    /// Validates one workout and its prescription. Pure: reads the context, changes nothing.
    static func validate(_ w: Workout, entries es: [ExerciseEntry], rationale: SessionRationale?, context c: ValidationContext) -> ValidationReport {
        var r = ValidationReport()
        func add(_ id: String, _ sev: IssueSeverity, _ out: ValidationOutcome, _ text: String, _ remedy: String, auto: Bool, confirm: Bool) {
            r.issues.append(ValidationIssue(ruleId: id, severity: sev, outcome: out, workoutId: w.id, explanation: text, remedy: remedy, autoRepairAllowed: auto, needsConfirmation: confirm))
        }
        if w.kind == .rest || w.kind == .recoveryDay { return r }
        // SAFE-001: stop / paused overrides every session, fixed ones included (existing rule, read only)
        if !c.readiness.trainingAllowed {
            add("SAFE-001", .error, .block, "Training is paused: \(c.readiness.restriction ?? "health status")", "Rest; answer the health check again when it applies", auto: false, confirm: false)
            return r
        }
        // SCHED-001: no session on a day the athlete keeps free
        if c.prohibitedWeekdays.contains(Store.weekdayIndex(w.date, calendar: c.calendar)) {
            add("SCHED-001", .error, .block, "This day is marked as no training.", "Move the session to an available day", auto: false, confirm: true)
        }
        if w.kind == .strength {
            // SAFE-002: health caps (RPE, minimum reps) — existing caps, checked not changed
            let rats = rationale?.exercises ?? []
            if rats.contains(where: { ($0.targetRPE ?? 0) > c.readiness.maxStrengthRPE }) {
                add("SAFE-002", .error, .adjust, "An effort target is above the RPE \(c.readiness.maxStrengthRPE) cap.", "Cap the effort", auto: true, confirm: false)
            }
            if let lo = c.readiness.minStrengthReps, es.contains(where: { e in !DurationModel.isHoldName(e.name) && e.sets.contains { $0.reps < lo } }) {
                add("SAFE-002", .error, .adjust, "A set is below the \(lo)-rep minimum while the health check limits heavy work.", "Raise reps to \(lo) with a lighter load", auto: true, confirm: false)
            }
            // SPLIT-00x: the label matches the content
            if w.templateId == nil, let req = required(w.strengthFocus) {
                let cov = coverage(es, catalogue: c.catalogue)
                let missing = req.need.filter { cov[keyPath: $0.1] < 2 }.map { $0.0 }
                if !missing.isEmpty {
                    add(req.ruleId, .error, .block, "Labelled \(w.strengthFocus?.title ?? "Full body") but missing \(missing.joined(separator: ", ")) work (≥ 2 working sets each).", "Rebuild, or label the session for what it is and say why", auto: false, confirm: true)
                }
                if w.strengthFocus == .push || w.strengthFocus == .upper, cov.lowerTotal > 0, w.strengthFocus == .push {
                    add("SPLIT-004", .warning, .adjust, "A Push session contains lower-body work.", "Remove it or relabel", auto: true, confirm: false)
                }
            }
            // TIME-001: estimate at the top of every rep range ≤ maximum − margin
            let est = estimate(es, rationale: rationale, ctx: c)
            r.estimatedMinutes = est
            if est > Double(w.minutes) - c.timeMarginMinutes {
                add("TIME-001", .error, .adjust, String(format: "Estimated %.1f min at the top of the rep ranges; the limit is %d min.", est, w.minutes), "Superset (if preferred), drop accessories, shorten rests within limits, then reduce sets", auto: true, confirm: false)
            }
            // EQUIP-001: every exercise possible with the stated equipment and apparatus
            for e in es {
                guard let ex = c.catalogue.first(where: { $0.id == e.exerciseId }) else { continue }
                if !(w.generatedEntries ? c.equipment.plannable(ex) : c.equipment.canDo(ex)) || !ExerciseLibrary.apparatusOK(ex, equipment: c.equipment) {   // RC3 / ENG-H1
                    add("EQUIP-001", .error, .adjust, "\(e.name) needs equipment you have not listed.", "Swap for a same-pattern exercise you can do", auto: true, confirm: false)
                }
            }
            // EXPL-001: explanations come from rules that fired for THIS content
            if let rat = rationale {
                if Set(rat.exercises.map(\.exerciseId)) != Set(es.map(\.exerciseId)) {
                    add("EXPL-001", .warning, .adjust, "The explanations describe exercises that are not in the session.", "Regenerate the explanations", auto: true, confirm: false)
                }
                let cov = coverage(es, catalogue: c.catalogue)
                if cov.lowerTotal == 0, rat.notes.contains(where: { $0.lowercased().contains("lower-body") || $0.lowercased().contains("leg work") }) {
                    add("EXPL-001", .warning, .adjust, "A note talks about lower-body work, but the session has none.", "Remove the note", auto: true, confirm: false)
                }
            } else if !es.isEmpty, w.generatedEntries {
                add("EXPL-001", .warning, .adjust, "A coach-built session has no explanation.", "Regenerate the explanations", auto: true, confirm: false)
            }
            // PREF-001: an athlete preference that the prescription does not meet (information, not a block)
            if c.prefersSupersets == true, !es.contains(where: { $0.superset != nil }), es.count >= 2 {
                add("PREF-001", .info, .pass, "You prefer supersets; this session uses straight sets.", "Shown so the trade-off is visible", auto: false, confirm: false)
            }
            // REC-001: heavy or voluminous leg work the day before a key ride (explicit choices are flagged, not changed)
            let cov = coverage(es, catalogue: c.catalogue)
            let next = c.calendar.date(byAdding: .day, value: 1, to: c.calendar.startOfDay(for: w.date))!
            if cov.lowerTotal > 2, let k = c.plan.first(where: { StrengthPlanner.isKeyRide($0) && c.calendar.isDate($0.date, inSameDayAs: next) }) {
                add("REC-001", .warning, .adjust, "\(cov.lowerTotal) lower-body sets the day before your \(k.kind.title.lowercased()).", "Keep lower-body work to 2 easy sets (RIR ≥ 3), or move the leg emphasis", auto: false, confirm: true)
            }
        }
        if w.kind.isRide {
            // RIDE-001: the steps must fit the session
            if let total = rideStepsMinutes(w), total > w.minutes {
                add("RIDE-001", .error, .adjust, "The steps add up to \(total) min in a \(w.minutes)-min session.", "Rebuild the steps to fit the duration", auto: true, confirm: false)
            }
            // FTP-001: no precise watts from an assumed FTP
            if c.profile.ftpHow == .assumed, w.kind.zone >= 2 {
                add("FTP-001", .warning, .adjust, "Your FTP is a starting assumption, so watt targets would look more precise than they are.", "Show effort and talk-test targets first; no watt numbers", auto: true, confirm: false)
            }
        }
        return r
    }

    /// Week-level checks (VOL-001: coverage by pattern, under- and over-target are both visible).
    static func validateWeek(_ week: [Workout], entries: (Workout) -> [ExerciseEntry], context c: ValidationContext) -> ValidationReport {
        var r = ValidationReport()
        let lifts = week.filter { $0.kind == .strength && !$0.skipped }
        guard lifts.count >= 2 else { return r }
        var tot = Coverage()
        for l in lifts { let x = coverage(entries(l), catalogue: c.catalogue); tot.knee += x.knee; tot.hip += x.hip; tot.push += x.push; tot.pull += x.pull }
        for (name, v, lo) in [("knee-dominant", tot.knee, 4), ("hip-dominant", tot.hip, 4), ("push", tot.push, 4), ("pull", tot.pull, 4)] where v < lo {
            r.issues.append(ValidationIssue(ruleId: "VOL-001", severity: .warning, outcome: .pass, workoutId: nil, explanation: "\(name): \(v) hard sets this week (target ≥ \(lo)).", remedy: "Shown on the week view with the reason", autoRepairAllowed: false, needsConfirmation: false))
        }
        return r
    }
}

// MARK: bounded repairs (predefined; never change the athlete's split or maximum duration)
enum PrescriptionRepair {
    /// Predefined repair strategies tried in order, one per attempt (bounded).
    static let maxAttempts = 4

    static func region(_ e: ExerciseEntry, _ cat: [Exercise]) -> String? {
        guard let ex = cat.first(where: { $0.id == e.exerciseId }) else { return nil }
        let m = ExerciseLibrary.meta(ex)
        guard m.compound else { return nil }
        switch m.slot {
        case .horizontalPush, .verticalPush: return "push"
        case .horizontalPull, .verticalPull: return "pull"
        default: let d = ExerciseLibrary.dominance(ex); return d == .none ? nil : d.rawValue
        }
    }
    static func isEssential(_ e: ExerciseEntry, catalogue: [Exercise], covered: Set<String> = []) -> Bool {
        guard let r = region(e, catalogue) else { return catalogue.first { $0.id == e.exerciseId } == nil }
        return !covered.contains(r)
    }
    static func isLowerEx(_ e: ExerciseEntry, _ cat: [Exercise]) -> Bool { cat.first { $0.id == e.exerciseId }.map { ExerciseLibrary.meta($0).slot.isLower } ?? false }

    /// Pairs non-competing exercises (lower with upper; never two grip-limited ones).
    static func pairSupersets(_ es: inout [ExerciseEntry], rats: inout [ExerciseRationale], catalogue cat: [Exercise]) -> Bool {
        var used = Set<Int>(), pairs: [(Int, Int)] = []
        for i in es.indices where !used.contains(i) && es[i].superset == nil {
            guard let a = cat.first(where: { $0.id == es[i].exerciseId }) else { continue }
            for j in es.indices where j > i && !used.contains(j) && es[j].superset == nil {
                guard let b = cat.first(where: { $0.id == es[j].exerciseId }) else { continue }
                let differentRegion = ExerciseLibrary.meta(a).slot.isLower != ExerciseLibrary.meta(b).slot.isLower
                if differentRegion && !(ExerciseLibrary.gripLimited(a) && ExerciseLibrary.gripLimited(b)) { used.insert(i); used.insert(j); pairs.append((i, j)); break }
            }
        }
        guard !pairs.isEmpty else { return false }
        var out: [ExerciseEntry] = [], outR: [ExerciseRationale] = []
        let letters = ["A", "B", "C", "D", "E"]
        for (k, (i, j)) in pairs.enumerated() {
            let main = [rats[safe: i], rats[safe: j]].contains { $0?.role == StrengthPlanner.Role.main.rawValue }
            let rest = main ? 90 : 75
            for x in [i, j] {
                var e = es[x]; e.superset = letters[min(k, letters.count - 1)]; e.restSeconds = rest; out.append(e)
                if var r = rats[safe: x] { r.dose += " Superset \(e.superset!): about 20 s to the partner exercise, \(rest) s after each round."; outR.append(r) }
            }
        }
        for x in es.indices where !used.contains(x) { out.append(es[x]); if let r = rats[safe: x] { outR.append(r) } }
        es = out; rats = outR
        return true
    }

    static func strategies(prefersSupersets: Bool?) -> [String] {
        switch prefersSupersets {
        case true?: return ["pair", "dropAccessory", "trimRest", "reduceSets"]
        case false?: return ["dropAccessory", "trimRest", "reduceSets"]
        case nil: return ["dropAccessory", "trimRest", "reduceSets"]   // Phase 1: supersets only when the athlete asks for them
        }
    }

    /// Applies strategy number `attempt` completely. Never changes the athlete's split or maximum duration.
    static func repairTime(_ es: inout [ExerciseEntry], rats: inout [ExerciseRationale], prefersSupersets: Bool?, attempt: Int, catalogue cat: [Exercise], covered: Set<String>, fits: ([ExerciseEntry], [ExerciseRationale]) -> Bool) -> String? {
        let steps = strategies(prefersSupersets: prefersSupersets)
        guard attempt < steps.count else { return nil }
        switch steps[attempt] {
        case "pair":
            return pairSupersets(&es, rats: &rats, catalogue: cat) ? "paired non-competing exercises as supersets" : "no superset pairing possible"
        case "dropAccessory":
            var dropped: [String] = []
            // 1) accessories and isolation work, 2) duplicates: a second exercise for a region already trained in this
            // session (owner §7.3: "avoid redundant exercise selection") — always from the end, the least important first
            func duplicate(_ j: Int) -> Bool {
                guard let r = region(es[j], cat) else { return false }
                return es[..<j].contains { region($0, cat) == r } || covered.contains(r)
            }
            while !fits(es, rats), let j = es.indices.reversed().first(where: { !isEssential(es[$0], catalogue: cat, covered: covered) }) ?? es.indices.reversed().first(where: duplicate) {
                dropped.append(es[j].name); es.remove(at: j); if j < rats.count { rats.remove(at: j) }
            }
            return dropped.isEmpty ? "no accessory to leave out" : "left out \(dropped.joined(separator: ", "))"
        case "trimRest":
            var changed = false
            for i in es.indices where es[i].superset == nil {
                let role = rats[safe: i]?.role
                let floor = role == StrengthPlanner.Role.main.rawValue ? 120 : role == StrengthPlanner.Role.secondary.rawValue ? 90 : 60
                if let r = es[i].restSeconds, r > floor { es[i].restSeconds = floor; changed = true; if i < rats.count { rats[i].dose += " Rest shortened to \(floor) s to fit the time." } }
            }
            return changed ? "rests shortened to their floors (main lifts 2 min, secondary 90 s)" : "rests already at their floors"
        default:
            var n = 0
            while !fits(es, rats), let j = es.indices.filter({ es[$0].sets.count > 2 }).max(by: { (rats[safe: $0]?.role == StrengthPlanner.Role.main.rawValue ? 0 : 1, es[$0].sets.count) < (rats[safe: $1]?.role == StrengthPlanner.Role.main.rawValue ? 0 : 1, es[$1].sets.count) }) {
                es[j].sets.removeLast(); n += 1
                if j < rats.count { rats[j].dose += " One set fewer to fit the time." }
            }
            return n == 0 ? "sets already at their floors" : "\(n) set\(n == 1 ? "" : "s") fewer (never below 2 per exercise)"
        }
    }

    static func dropAbsentLowerNotes(_ notes: [String], es: [ExerciseEntry], cat: [Exercise]) -> [String] {
        let lower = es.contains { isLowerEx($0, cat) }
        return lower ? notes : notes.filter { !$0.lowercased().contains("lower-body") && !$0.lowercased().contains("leg work") }
    }
}

extension Array { subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil } }

// MARK: change proposals and commits
struct SessionChangeRequest: Equatable, Codable {
    enum Origin: String, Codable { case athlete, ai, coach }
    var focus: StrengthFocus? = nil
    var minutes: Int? = nil
    var prefersSupersets: Bool? = nil
    /// review C R3: a change INTO strength (a ride or rest day becomes a lift)
    var kind: WorkoutKind? = nil
    /// review C R2: a type change on a routine session detaches the routine (always needs confirmation, ROUTINE-001)
    var detachRoutine = false
    /// review C A8: proposals the engine raises for legacy sessions always need confirmation (LEGACY-001)
    var legacy = false
    var origin: Origin = .athlete
}

struct SessionChangeProposal {
    var id = UUID()
    var workoutId: UUID
    var baseFingerprint: UInt64
    var request: SessionChangeRequest
    var before: Workout
    var after: Workout
    var beforeEntries: [ExerciseEntry]
    var afterEntries: [ExerciseEntry]
    var preservedLogged: [ExerciseEntry]
    var diff: [String]
    var report: ValidationReport
    var alternatives: [String]
    /// Estimated minutes of the current prescription (same duration model, top of the rep ranges), for the preview.
    var beforeEstimate: Double? = nil
    /// What the change does to the rest of the week (lifting time vs budget, weekly sets per pattern), for the preview.
    var weekly: [String] = []
    /// true only for proposals produced by the engine path (an AI or UI cannot hand-craft one, AI-001)
    fileprivate(set) var engineValidated = false
    /// Content seal set by the engine: a proposal edited after validation (by an AI or UI) is refused (AI-001).
    fileprivate(set) var seal: UInt64 = 0
    var createdAt = Date()
    var needsConfirmation: Bool { report.needsConfirmation || request.origin == .ai || request.legacy || request.detachRoutine }
}

enum CommitResult: Equatable { case applied, stale, blocked([String]), needsConfirmation, notValidated }

extension Store {
    /// review C A2/R5: the validation context a proposal depends on — readiness (via the profile's health answers),
    /// profile, equipment, strength preferences and the neighbouring days' sessions (REC-001 reads them).
    func contextFingerprint(_ id: UUID) -> UInt64 {
        let enc = JSONEncoder(); enc.outputFormatting = .sortedKeys; enc.dateEncodingStrategy = .secondsSince1970
        var d = Data()
        if let x = try? enc.encode(profile) { d.append(x) }
        if let x = try? enc.encode(equipment) { d.append(x) }
        if let x = try? enc.encode(strengthPrefs) { d.append(x) }
        d.append(contentsOf: "\(CoachReadiness(profile: profile, now: Date()).trainingAllowed)".utf8)
        if let w = plan.first(where: { $0.id == id }) {
            let cal = Calendar.current, day = cal.startOfDay(for: w.date)
            for n in plan where n.id != id && abs(cal.dateComponents([.day], from: day, to: cal.startOfDay(for: n.date)).day ?? 9) <= 1 {
                if let x = try? enc.encode(n) { d.append(x) }
            }
        }
        return Store.fnv(d)
    }
    /// What a proposal's compare-and-swap covers: the session (+ logs) AND its validation context.
    func changeFingerprint(_ id: UUID) -> UInt64 { sessionFingerprint(id) ^ (contextFingerprint(id) &* 1099511628211) }
    static func fnv(_ d: Data) -> UInt64 { var h: UInt64 = 1469598103934665603; for b in d { h = (h ^ UInt64(b)) &* 1099511628211 }; return h }
    /// Deterministic fingerprint of everything a session change depends on (the session, its active log, its saved logs).
    func sessionFingerprint(_ id: UUID) -> UInt64 {
        let enc = JSONEncoder(); enc.outputFormatting = .sortedKeys; enc.dateEncodingStrategy = .secondsSince1970
        var d = Data()
        if let w = plan.first(where: { $0.id == id }), let x = try? enc.encode(w) { d.append(x) }
        if let a = activeSession, a.workoutId == id, let x = try? enc.encode(a) { d.append(x) }
        for s in strength where s.workoutId == id { if let x = try? enc.encode(s) { d.append(x) } }
        var h: UInt64 = 5381
        for b in d { h = (h &* 33) &+ UInt64(b) }
        return h
    }

    /// Builds, validates and repairs a prescription for `x` (its focus and minutes are the athlete's). Bounded repairs.
    func rebuiltPrescription(for x: Workout, prefersSupersets: Bool?, ctx c: PlannerContext, exclude: Set<String> = [], limitMinutes: Int? = nil, covered: Set<String> = [], origin: SessionChangeRequest.Origin = .athlete) -> (entries: [ExerciseEntry], rationale: SessionRationale, report: ValidationReport) {
        let limit = limitMinutes ?? x.minutes
        // supersets save time, so the base prescription is built with more room and then fitted by the repairs
        var bx = x; bx.minutes = prefersSupersets == false ? limit : Int((Double(limit) * 1.5).rounded())
        let b = StrengthPlanner.build(for: bx, ctx: c)
        var es = b.entries.filter { !exclude.contains($0.exerciseId) }
        var rat = b.rationale
        // the base builder's own time notes refer to its budget, not the athlete's limit: removed (EXPL-001)
        rat.notes = rat.notes.filter { !$0.hasPrefix("To fit ") }
        var rats = rat.exercises.filter { r in es.contains { $0.exerciseId == r.exerciseId } }.map { r -> ExerciseRationale in
            var y = r
            if let k = y.dose.range(of: " Trimmed to") { y.dose = String(y.dose[..<k.lowerBound]) }
            return y
        }
        let vctx = ValidationContext(planner: c, prefersSupersets: prefersSupersets)
        var vx = x; vx.minutes = limit; vx.generatedEntries = true
        func check(_ e: [ExerciseEntry], _ r: [ExerciseRationale]) -> ValidationReport { WorkoutValidator.validate(vx, entries: e, rationale: RationaleWith(rat, r), context: vctx) }
        var report = check(es, rats)
        var repairs: [String] = []
        var attempt = 0
        while attempt < PrescriptionRepair.maxAttempts, report.has("TIME-001") || (attempt == 0 && prefersSupersets == true && report.has("PREF-001")) {
            guard let what = PrescriptionRepair.repairTime(&es, rats: &rats, prefersSupersets: prefersSupersets, attempt: attempt, catalogue: c.catalogue, covered: covered, fits: { e, r in !check(e, r).has("TIME-001") }) else { break }
            repairs.append(what); attempt += 1
            report = check(es, rats)
        }
        // a superset whose partner was left out is a straight exercise again (no one-member "supersets")
        for g in Set(es.compactMap(\.superset)) where es.filter({ $0.superset == g }).count < 2 {
            for i in es.indices where es[i].superset == g { es[i].superset = nil }
        }
        rat.exercises = rats
        rat.notes = PrescriptionRepair.dropAbsentLowerNotes(rat.notes, es: es, cat: c.catalogue)
        if let f = x.strengthFocus {
            // the first reason names who decided (EXPL-001: only reasons that actually apply)
            let who = origin == .coach ? "Coach suggestion you accepted:" : origin == .ai ? "Your request through the coach chat:" : "You chose"
            rat.notes.insert("\(who) \(f.title.lowercased()) for \(Fmt.duration(minutes: x.minutes)).", at: 0)
        }
        if !repairs.isEmpty { rat.notes.append("To fit \(Fmt.duration(minutes: limit)): \(repairs.joined(separator: "; ")).") }
        report = WorkoutValidator.validate(vx, entries: es, rationale: rat, context: vctx)
        report.repairs = repairs; report.attempts = attempt
        return (es, rat, report)
    }
    private func RationaleWith(_ r: SessionRationale, _ rats: [ExerciseRationale]) -> SessionRationale { var x = r; x.exercises = rats; return x }

    /// Proposes a change of type and/or duration for a planned strength session: the prescription is rebuilt, validated
    /// and compared with the current one. Nothing is saved; `commit` applies it.
    func proposeSessionChange(workoutId: UUID, request: SessionChangeRequest, now: Date = Date()) -> SessionChangeProposal? {
        guard let w = plan.first(where: { $0.id == workoutId }), w.kind == .strength || request.kind == .strength, !w.done, !w.skipped else { return nil }
        let fp = changeFingerprint(workoutId)
        var x = w
        if request.kind == .strength, w.kind != .strength { x.kind = .strength; x.strengthFocus = request.focus ?? w.strengthFocus ?? .fullBody }
        if let f = request.focus { x.strengthFocus = f }
        if let m = request.minutes { x.minutes = m }
        if request.detachRoutine { x.templateId = nil; x.routineManual = false }
        var c = plannerContext(now: now)
        c.plan = plan.map { $0.id == x.id ? x : $0 }
        let beforeEntries = w.kind == .strength ? plannedEntries(for: w) : []
        var p = SessionChangeProposal(workoutId: w.id, baseFingerprint: fp, request: request, before: w, after: w, beforeEntries: beforeEntries, afterEntries: beforeEntries, preservedLogged: [], diff: [], report: ValidationReport(), alternatives: [])
        // SAFE-001: nothing is rebuilt while training is paused or stopped
        let vctx = ValidationContext(planner: c, prefersSupersets: request.prefersSupersets)
        if !c.readiness.trainingAllowed {
            p.report = WorkoutValidator.validate(x, entries: [], rationale: nil, context: vctx)
            p.alternatives = ["Rest today", "Review the health check in Profile"]
            p.createdAt = now
            p.engineValidated = true
            p.seal = Store.sealOf(p)
            register(p)
            return p
        }
        // completed work: sets already logged in an in-progress session are kept; only the rest is rebuilt
        var logged: [ExerciseEntry] = []
        var limit: Int? = nil
        var covered = Set<String>()
        if let a = activeSession, a.workoutId == w.id {
            logged = (a.exercises ?? []).filter { !$0.doneSets.isEmpty }
            let done = logged.map { e in var y = e; y.sets = e.doneSets; return y }
            let used = DurationModel().minutes(done, catalogue: c.catalogue)
            limit = max(10, x.minutes - Int(used.rounded(.up)))
            let cov = WorkoutValidator.coverage(done, catalogue: c.catalogue)
            if cov.knee >= 2 { covered.insert("knee") }; if cov.hip >= 2 { covered.insert("hip") }
            if cov.push >= 2 { covered.insert("push") }; if cov.pull >= 2 { covered.insert("pull") }
        }
        let built = rebuiltPrescription(for: x, prefersSupersets: request.prefersSupersets, ctx: c, exclude: Set(logged.map(\.exerciseId)), limitMinutes: limit, covered: covered, origin: request.origin)
        let afterEntries = logged + built.entries
        var rat = built.rationale
        // the combined session (logged + rebuilt) is what must match the label
        var report = WorkoutValidator.validate(x, entries: afterEntries, rationale: nil, context: vctx)
        report.issues.removeAll { $0.ruleId == "TIME-001" || $0.ruleId == "EXPL-001" || $0.ruleId == "PREF-001" }   // time / text judged on the rebuilt part
        report.issues += built.report.issues.filter { r in !report.issues.contains(r) && !(r.ruleId.hasPrefix("SPLIT") && !logged.isEmpty) }
        report.repairs = built.report.repairs; report.attempts = built.report.attempts; report.estimatedMinutes = built.report.estimatedMinutes
        // Phase 1 (owner 30 Oct, item 10): a time limit the bounded repairs could not meet, or an exercise the stated
        // equipment cannot do, is a CONFLICT shown with alternatives — never saved as "adjusted"
        for i in report.issues.indices where ["TIME-001", "EQUIP-001"].contains(report.issues[i].ruleId) && report.issues[i].outcome == .adjust {
            report.issues[i].outcome = .block
            report.issues[i].autoRepairAllowed = false
        }
        // TITLE-001: a change of type or duration whose exercises did not change is a label-only change
        let changed = (request.focus != nil && request.focus != w.strengthFocus) || (request.minutes != nil && request.minutes != w.minutes)
        if changed, afterEntries.map(\.exerciseId) == beforeEntries.map(\.exerciseId), afterEntries.map({ $0.sets.count }) == beforeEntries.map({ $0.sets.count }), (request.focus ?? w.strengthFocus) != w.strengthFocus {
            report.issues.append(ValidationIssue(ruleId: "TITLE-001", severity: .error, outcome: .block, workoutId: w.id, explanation: "Only the title would change.", remedy: "Rebuild the prescription", autoRepairAllowed: false, needsConfirmation: false))
        }
        // HAND-001: the athlete's own exercise list is never replaced without asking
        if w.entriesHandEdited == true || (w.edited && !w.generatedEntries && w.plannedEntries != nil) {
            report.issues.append(ValidationIssue(ruleId: "HAND-001", severity: .info, outcome: .pass, workoutId: w.id, explanation: "This replaces the exercise list you edited yourself.", remedy: "Apply only if you confirm", autoRepairAllowed: false, needsConfirmation: true))
        }
        // ROUTINE-001 (review C R2): a type change on a routine session detaches the routine — only with the athlete's OK
        if w.templateId != nil {
            if request.detachRoutine {
                report.issues.append(ValidationIssue(ruleId: "ROUTINE-001", severity: .info, outcome: .pass, workoutId: w.id, explanation: "This session uses one of your routines. The new type replaces the routine for this session only; the routine itself is not changed.", remedy: "Apply only if you confirm", autoRepairAllowed: false, needsConfirmation: true))
            } else {
                report.issues.append(ValidationIssue(ruleId: "ROUTINE-001", severity: .error, outcome: .block, workoutId: w.id, explanation: "This session uses one of your routines.", remedy: "Detach the routine and rebuild, or keep the routine", autoRepairAllowed: false, needsConfirmation: true))
            }
        }
        // EQUIP-002 (review A): equipment never confirmed → the engine does not assume the athlete owns everything
        if !equipment.isSet {
            // athlete / AI edits: asked first (BLOCK until equipment is set); a coach proposal shows the same question on its
            // Accept card, so Accept is an informed confirmation (no silent assumption either way)
            // RC3 / ENG-H1: with equipment not set the planner uses bodyweight exercises only (a full gym is never assumed),
            // so the change can go ahead as a provisional session; the athlete is told and can set equipment from here
            report.issues.append(ValidationIssue(ruleId: "EQUIP-002", severity: .warning, outcome: .pass, workoutId: w.id, explanation: "Your equipment isn't set yet, so this session uses bodyweight exercises only (provisional).", remedy: "Set your equipment (Profile › Training) for exercises that use it", autoRepairAllowed: false, needsConfirmation: true))
        }
        // LEGACY-001 (review C A8): engine-raised proposals for legacy sessions always need the athlete's answer
        if request.legacy {
            report.issues.append(ValidationIssue(ruleId: "LEGACY-001", severity: .info, outcome: .pass, workoutId: w.id, explanation: "This session's exercises don't match its type (saved before the fix).", remedy: "Rebuild only if you confirm", autoRepairAllowed: false, needsConfirmation: true))
        }
        if request.origin == .ai {
            report.issues.append(ValidationIssue(ruleId: "AI-001", severity: .info, outcome: .pass, workoutId: w.id, explanation: "Proposed through the AI coach.", remedy: "Applied only after you confirm", autoRepairAllowed: false, needsConfirmation: true))
        }
        // alternatives when the request cannot be met as asked
        if report.outcome == .block {
            var alt: [String] = []
            if report.issues.contains(where: { $0.ruleId.hasPrefix("SPLIT") }) { alt += ["Keep \(w.strengthFocus?.title.lowercased() ?? "the session") as planned", "Label the session for what it can include, with the reason"] }
            if report.has("TIME-001") { alt.append("Allow \(Int((report.estimatedMinutes ?? Double(x.minutes)).rounded(.up)) + 1) min") }
            if report.has("EQUIP-002") { alt.append("Set your equipment in Profile › Equipment") }
            if report.has("ROUTINE-001") { alt += ["Detach the routine and rebuild", "Keep the routine"] }
            p.alternatives = alt
        }
        x.plannedEntries = afterEntries
        x.generatedEntries = true
        x.entriesHandEdited = nil
        rat.generatedAt = now
        x.rationale = rat
        x.riderChoice = RiderChoice(focus: request.focus ?? w.riderChoice?.focus, minutes: request.minutes ?? w.riderChoice?.minutes, prefersSupersets: request.prefersSupersets ?? w.riderChoice?.prefersSupersets, at: now, origin: request.origin.rawValue, fromFocus: w.strengthFocus, fromMinutes: w.minutes)
        x.markRiderEdited(before: w)
        p.after = x
        p.afterEntries = afterEntries
        p.preservedLogged = logged
        p.report = report
        p.diff = Store.describeDiff(before: w, after: x, beforeEntries: beforeEntries, afterEntries: afterEntries, estimate: report.estimatedMinutes)
        if w.kind == .strength, !beforeEntries.isEmpty { p.beforeEstimate = WorkoutValidator.estimate(beforeEntries, rationale: w.rationale, ctx: vctx) }
        p.weekly = weeklyConsequences(before: w, after: x, beforeEntries: beforeEntries, afterEntries: afterEntries, catalogue: c.catalogue)
        p.createdAt = now
        p.engineValidated = true
        p.seal = Store.sealOf(p)
        register(p)
        return p
    }

    /// review C A7: the engine keeps proposals; anything outside commits by id. Bounded (20) and expiring (1 h).
    func register(_ p: SessionChangeProposal) {
        pendingProposals[p.id] = p
        let cutoff = p.createdAt.addingTimeInterval(-3600)
        for (k, v) in pendingProposals where v.createdAt < cutoff { pendingProposals.removeValue(forKey: k) }
        if pendingProposals.count > 20, let oldest = pendingProposals.values.min(by: { $0.createdAt < $1.createdAt }) { pendingProposals.removeValue(forKey: oldest.id) }
    }
    /// Commit by reference (UI preview sheet, AI gateway). Unknown or expired id → `.stale` (propose again).
    func commit(proposalId: UUID, confirmed: Bool) -> CommitResult {
        guard let p = pendingProposals[proposalId] else { return .stale }
        return commit(p, confirmed: confirmed)
    }
    /// The preview's Cancel: the proposal is discarded; the session was never changed.
    func discardProposal(_ id: UUID) { pendingProposals.removeValue(forKey: id) }

    /// The shortest time limit a strength session can be rebuilt to without the validator blocking it (TIME-001): a dry
    /// run of the rebuild at `target`; when blocked for time, the estimate at the top of the rep ranges, rounded up, +1.
    /// Nothing is registered or saved. Non-strength sessions and sessions that cannot be rebuilt return `target`.
    func shortestFeasibleMinutes(for w: Workout, target: Int, now: Date = Date()) -> Int {
        guard w.kind == .strength, !w.done, !w.skipped else { return target }
        var req = SessionChangeRequest(); req.minutes = target
        guard let p = proposeSessionChange(workoutId: w.id, request: req, now: now) else { return target }
        if p.report.outcome == .block, p.report.has("TIME-001"), let e = p.report.estimatedMinutes { return max(target, Int(e.rounded(.up)) + 1) }
        return target
    }
    /// Builds a fresh proposal from an earlier one's request (after a stale refusal, or with one field changed by an
    /// alternative such as "Allow 32 min" or "Detach the routine"). Returns the new id, nil when the session is gone.
    func repropose(_ id: UUID, now: Date = Date(), adjust: (inout SessionChangeRequest) -> Void = { _ in }) -> UUID? {
        guard let old = pendingProposals[id] ?? lastStale[id] else { return nil }
        var r = old.request; adjust(&r)
        pendingProposals.removeValue(forKey: id)
        guard let p = proposeSessionChange(workoutId: old.workoutId, request: r, now: now) else { return nil }
        lastProposalId = p.id
        return p.id
    }

    // MARK: coach proposals (Phase 1: a strength rebuild from a coach suggestion goes through the same preview)
    /// The rebuild a coach proposal implies, or nil when it does not change a strength prescription (moves, ride kinds…).
    func rebuildRequest(for c: CoachProposal, allowFixed: Bool = false) -> (workoutId: UUID, request: SessionChangeRequest)? {
        func target(_ id: UUID) -> Workout? { plan.first { $0.id == id && (allowFixed || !$0.fixed) && !$0.edited && !$0.done } }
        var r: (UUID, SessionChangeRequest)? = nil
        switch c.change {
        case .move: return nil
        case .kind(let id, let k): if let w = target(id), k == .strength, w.kind != .strength { r = (id, SessionChangeRequest(focus: w.strengthFocus ?? .fullBody, minutes: w.minutes, kind: .strength)) }
        case .minutes(let id, let m): if let w = target(id), w.kind == .strength { r = (id, SessionChangeRequest(minutes: m)) }
        case .focus(let id, let f): if let w = target(id), w.kind == .strength { r = (id, SessionChangeRequest(focus: f)) }
        }
        guard var x = r else { return nil }
        x.1.origin = .coach
        return x
    }
    /// Accept on a coach card: when the suggestion rebuilds a strength session, returns the proposal id to preview
    /// (nothing is saved). nil = not a rebuild; the caller applies it as before with `apply(_:)`.
    func coachChangePreview(_ c: CoachProposal) -> UUID? {
        guard let (id, req) = rebuildRequest(for: c), let p = proposeSessionChange(workoutId: id, request: req) else { return nil }
        lastProposalId = p.id
        return p.id
    }
    /// Apply in the preview of a coach suggestion: commits the shown proposal and records it for the coach card's Undo
    /// (compare-and-swap, `undoLastProposal`).
    func commitCoachChange(_ c: CoachProposal, proposalId: UUID) -> CommitResult {
        guard let p = pendingProposals[proposalId] else { return .stale }
        let r = commit(p, confirmed: true, recordUndo: false)
        if r == .applied, let k = plan.firstIndex(where: { $0.id == p.workoutId }) {
            appliedProposals.append(AppliedProposal(id: c.id, text: c.text, before: p.before, appliedAt: Date(), after: plan[k]))
            if appliedProposals.count > 20 { appliedProposals.removeFirst(appliedProposals.count - 20) }
        }
        return r
    }

    /// Owner item 4: what the change does to the rest of the week.
    func weeklyConsequences(before w: Workout, after x: Workout, beforeEntries: [ExerciseEntry], afterEntries: [ExerciseEntry], catalogue: [Exercise]) -> [String] {
        let cal = Calendar.current
        let monday = TrainingLedger.monday(of: w.date, calendar: cal)
        guard let end = cal.date(byAdding: .day, value: 7, to: monday) else { return [] }
        let week = plan.filter { $0.date >= monday && $0.date < end && !$0.skipped }
        var out: [String] = []
        let liftBefore = week.filter { $0.kind == .strength }.reduce(0) { $0 + $1.minutes }
        let liftAfter = liftBefore - (w.kind == .strength ? w.minutes : 0) + x.minutes
        if liftAfter != liftBefore || w.kind != .strength {
            let budget = profile.liftingHoursPerWeek * 60
            out.append("Lifting this week: \(Fmt.duration(minutes: liftBefore)) → \(Fmt.duration(minutes: liftAfter))\(budget > 0 ? " (your lifting time: \(Fmt.duration(minutes: budget)))" : "")")
        }
        if w.kind.isRide {
            let rideBefore = week.filter { $0.kind.isRide }.reduce(0) { $0 + $1.minutes }
            out.append("Riding this week: \(Fmt.duration(minutes: rideBefore)) → \(Fmt.duration(minutes: rideBefore - w.minutes))")
        }
        func total(_ swap: Bool) -> WorkoutValidator.Coverage {
            var t = WorkoutValidator.Coverage()
            for s in week where s.kind == .strength || s.id == w.id {
                let es = s.id == w.id ? (swap ? afterEntries : beforeEntries) : plannedEntries(for: s)
                let c = WorkoutValidator.coverage(es, catalogue: catalogue)
                t.knee += c.knee; t.hip += c.hip; t.push += c.push; t.pull += c.pull; t.trunk += c.trunk
            }
            return t
        }
        let b = total(false), a = total(true)
        let rows: [(String, Int, Int)] = [("Legs, knee-dominant (squat, lunge)", b.knee, a.knee), ("Legs, hip-dominant (hinge, bridge)", b.hip, a.hip),
                                          ("Push (chest, shoulders)", b.push, a.push), ("Pull (back)", b.pull, a.pull), ("Trunk", b.trunk, a.trunk)]
        for (name, x0, x1) in rows where x0 != x1 { out.append("\(name) this week: \(x0) → \(x1) working sets") }
        if out.isEmpty { out.append("The rest of the week is unchanged.") }
        return out
    }

    static func sealOf(_ p: SessionChangeProposal) -> UInt64 {
        let enc = JSONEncoder(); enc.outputFormatting = .sortedKeys; enc.dateEncodingStrategy = .secondsSince1970
        var d = Data()
        // review C R5: every decision field is sealed (base fingerprint, request incl. origin, before, logged, after, report)
        d.append(contentsOf: "\(p.id.uuidString)|\(p.workoutId.uuidString)|\(p.baseFingerprint)|\(p.createdAt.timeIntervalSince1970)".utf8)
        if let x = try? enc.encode(p.request) { d.append(x) }
        if let x = try? enc.encode(p.before) { d.append(x) }
        if let x = try? enc.encode(p.beforeEntries) { d.append(x) }
        if let x = try? enc.encode(p.preservedLogged) { d.append(x) }
        if let x = try? enc.encode(p.after) { d.append(x) }
        if let x = try? enc.encode(p.afterEntries) { d.append(x) }
        if let x = try? enc.encode(p.report) { d.append(x) }
        if let x = try? enc.encode(p.alternatives) { d.append(x) }
        return Store.fnv(d)
    }

    static func describeDiff(before b: Workout, after a: Workout, beforeEntries be: [ExerciseEntry], afterEntries ae: [ExerciseEntry], estimate: Double?) -> [String] {
        var d: [String] = []
        if b.strengthFocus != a.strengthFocus { d.append("Type: \(b.strengthFocus?.title ?? "—") → \(a.strengthFocus?.title ?? "—")") }
        if b.minutes != a.minutes { d.append("Time: \(b.minutes) → \(a.minutes) min") }
        let removed = be.filter { e in !ae.contains { $0.exerciseId == e.exerciseId } }.map(\.name)
        let added = ae.filter { e in !be.contains { $0.exerciseId == e.exerciseId } }.map(\.name)
        if !removed.isEmpty { d.append("Out: \(removed.joined(separator: ", "))") }
        if !added.isEmpty { d.append("In: \(added.joined(separator: ", "))") }
        d.append("Sets: \(be.reduce(0) { $0 + $1.sets.count }) → \(ae.reduce(0) { $0 + $1.sets.count })")
        if let e = estimate { d.append(String(format: "Estimated time: %.0f min", e.rounded(.up))) }
        return d
    }

    /// Applies a proposal atomically (one write, review C A4). Rejects stale, blocked, unconfirmed or hand-made proposals,
    /// re-checks the medical status at commit time (review C R5), and never touches saved logs (DATA-001, release check).
    func commit(_ p: SessionChangeProposal, confirmed: Bool, recordUndo: Bool = true) -> CommitResult {
        guard p.engineValidated, Store.sealOf(p) == p.seal, let reg = pendingProposals[p.id], reg.seal == p.seal else { return .notValidated }
        if !CoachReadiness(profile: profile, now: Date()).trainingAllowed { return .blocked(["SAFE-001"]) }
        guard changeFingerprint(p.workoutId) == p.baseFingerprint else { pendingProposals.removeValue(forKey: p.id); lastStale = [p.id: p]; return .stale }
        if p.report.outcome == .block { return .blocked(p.report.issues.filter { $0.outcome == .block }.map(\.ruleId)) }
        if p.needsConfirmation && !confirmed { return .needsConfirmation }
        // TITLE-001 at commit (review C recommended): the committed session must differ in content when its type changed
        if p.before.strengthFocus != p.after.strengthFocus, p.before.kind == .strength, p.afterEntries.map(\.exerciseId) == p.beforeEntries.map(\.exerciseId) { return .blocked(["TITLE-001"]) }
        guard let i = plan.firstIndex(where: { $0.id == p.workoutId }) else { return .stale }
        let logsBefore = strength
        transaction {
            plan[i] = p.after
            // in-progress session: logged sets stay exactly as they are; the unperformed part is replaced
            if var a = activeSession, a.workoutId == p.workoutId {
                let keep = (a.exercises ?? []).filter { !$0.doneSets.isEmpty }
                let rest = p.afterEntries.filter { e in !keep.contains { $0.exerciseId == e.exerciseId } }.map { e -> ExerciseEntry in var x = e; x.sets = x.sets.map { var s = $0; s.done = false; return s }; return x }
                a.exercises = keep + rest
                a.focus = p.after.strengthFocus ?? a.focus
                activeSession = a
            }
            if strength != logsBefore { strength = logsBefore }      // DATA-001 holds in release builds too
            // Undo (owner item 8): restores the plan entry only while it is still exactly as this change left it, and
            // never touches logs or sets recorded after the change (see `undoDelete`)
            if recordUndo {
                let item = TrashItem(deletedAt: Date(), label: "Changed \(p.before.displayTitle)", planBefore: [p.before], planAfter: [p.after], sessionRebuild: true)
                trash.append(item)
                undoToast = UndoToast(id: item.id, text: "\(p.after.displayTitle) rebuilt")
            }
        }
        pendingProposals.removeValue(forKey: p.id)
        return .applied
    }

    /// Legacy sessions (edited before the fix: label changed, exercises kept) whose content contradicts their label get a
    /// rebuild PROPOSAL — never an automatic change.
    func legacyMismatchProposals(now: Date = Date()) -> [SessionChangeProposal] {
        let c = plannerContext(now: now)
        let v = ValidationContext(planner: c)
        let today = Calendar.current.startOfDay(for: now)
        return plan.filter { $0.kind == .strength && $0.edited && $0.riderChoice == nil && $0.templateId == nil && !$0.done && !$0.skipped && $0.date >= today }
            .compactMap { w in
                let r = WorkoutValidator.validate(w, entries: plannedEntries(for: w), rationale: w.rationale, context: v)
                guard r.issues.contains(where: { $0.ruleId.hasPrefix("SPLIT") }) else { return nil }
                return proposeSessionChange(workoutId: w.id, request: SessionChangeRequest(focus: w.strengthFocus, minutes: w.minutes, legacy: true, origin: .coach), now: now)
            }
    }
}
