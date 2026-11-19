import Foundation

// Plan › Add a goal (sheets B3 / B4, direction B) — the plain values behind the redesigned goal screens.
// Foundation only. There is no second goal model here: the goals are the athlete record's own `GoalID` list with its
// one main goal (RiderProfile.goals / primaryGoal), the choices are the planner's own (`GoalInfo.choices(for:)`, the
// list the existing Goals page offers), and the change is written through `OnboardingAnswers.apply` exactly as the
// existing Goals page writes it. What sheet B3 draws but the app cannot do (event programmes with a date, health
// targets, custom goals, adding a sport) has no row here.

enum PlanGoalV2 {
    /// One row of the "Add a goal" sheet: a group of goal types the planner really supports for this training type.
    struct Category: Identifiable, Equatable {
        let id: String              // fitness | strength | cycling
        let title: String
        let detail: String
        let icon: String
        let sport: GoalID.Sport
        let goals: [GoalID]
    }

    /// The rows offered, in sheet B3's order. A group the athlete's training type does not plan is left out.
    static func categories(for mode: TrainingMode) -> [Category] {
        let offered = GoalInfo.choices(for: mode).flatMap(\.goals)
        func pick(_ g: [GoalID]) -> [GoalID] { g.filter { offered.contains($0) } }
        var out: [Category] = []
        let general = pick([.fitness])
        if !general.isEmpty {
            let detail = mode == .hybrid ? "Balanced week across strength and cycling" : (mode == .cycling ? "Balanced, mostly easy riding" : "Balanced full-body training")
            out.append(Category(id: "fitness", title: "Improve general fitness", detail: detail, icon: "heart.fill", sport: .general, goals: general))
        }
        let lifting = pick([.strength, .muscle, .stamina, .maintain])
        if !lifting.isEmpty {
            out.append(Category(id: "strength", title: "Build strength or muscle", detail: "Strength-led plan", icon: "dumbbell.fill", sport: .strength, goals: lifting))
        }
        let riding = pick([.endurance, .power, .climbing, .sprint, .event])
        if !riding.isEmpty {
            out.append(Category(id: "cycling", title: "Improve endurance or cycling", detail: "Longer rides, power, climbing", icon: "bicycle", sport: .cycling, goals: riding))
        }
        return out
    }

    /// The goals the athlete holds, as the existing Goals page reads them (stored goals the training type still offers).
    static func held(_ p: RiderProfile) -> [GoalID] {
        let offered = GoalInfo.choices(for: p.trainingMode).flatMap(\.goals)
        return p.effectiveGoals.filter { offered.contains($0) }
    }
    /// The main goal among the held ones, as the existing Goals page reads it.
    static func heldPrimary(_ p: RiderProfile) -> GoalID? {
        let h = held(p)
        return p.primaryGoal.flatMap { h.contains($0) ? $0 : nil } ?? h.first
    }

    /// "Fitness (main) · Strength" — the main goal first.
    static func list(_ goals: [GoalID], primary: GoalID?) -> String {
        guard !goals.isEmpty else { return "No goal set" }
        let main = primary.flatMap { goals.contains($0) ? $0 : nil } ?? goals[0]
        let rest = goals.filter { $0 != main }
        if rest.isEmpty { return main.title }
        return (["\(main.title) (main)"] + rest.map(\.title)).joined(separator: " · ")
    }

    /// Sheet B3's subtitle: the goals the athlete already has.
    static func subtitle(_ p: RiderProfile) -> String {
        let h = held(p)
        if h.isEmpty { return "No goal set yet" }
        let main = heldPrimary(p) ?? h[0]
        if h.count == 1 { return "You have 1 goal: \(main.title)" }
        return "You have \(h.count) goals · main: \(main.title)"
    }

    enum Priority: String { case primary, secondary }

    /// What the athlete asked for on the set-up step.
    struct Request: Equatable {
        var goal: GoalID
        var priority: Priority
        var remove = false
    }

    /// The goal list and main goal the request leads to. nil = it cannot be done (removing the only goal).
    static func result(held: [GoalID], primary: GoalID?, request r: Request) -> (goals: [GoalID], primary: GoalID)? {
        var goals = held
        var main = primary.flatMap { held.contains($0) ? $0 : nil } ?? held.first
        if r.remove {
            goals.removeAll { $0 == r.goal }
            guard let first = goals.first else { return nil }
            if main == r.goal || main == nil { main = first }
            return (goals, main ?? first)
        }
        if !goals.contains(r.goal) { goals.append(r.goal) }
        if r.priority == .primary || main == nil { main = r.goal }
        else if main == r.goal, let other = goals.first(where: { $0 != r.goal }) { main = other }   // was main, now secondary
        return (goals, main ?? r.goal)
    }

    /// true when the request would leave the goals exactly as they are.
    static func changesNothing(held: [GoalID], primary: GoalID?, request r: Request) -> Bool {
        guard let out = result(held: held, primary: primary, request: r) else { return true }
        let main = primary.flatMap { held.contains($0) ? $0 : nil } ?? held.first
        return out.goals == held && out.primary == main
    }

    /// The answers the existing mapping (`OnboardingAnswers.apply`) writes — the same two fields the Goals page sends.
    static func answers(goals: [GoalID], primary: GoalID) -> OnboardingAnswers {
        var d = OnboardingAnswers()
        d.goals = goals
        d.primaryGoal = primary
        return d
    }

    /// Whether a secondary choice is possible: a goal can only be secondary when another goal can be the main one.
    static func canBeSecondary(held: [GoalID], goal: GoalID) -> Bool { held.contains { $0 != goal } }

    // MARK: Preview rows (from the planner's own proposal)

    struct ChangeRow: Identifiable, Equatable {
        let id: String
        let day: String
        let before: String
        let after: String
        /// cycling | strength | mixed — drawn as the coloured bar, always next to the words.
        let sport: String
    }

    /// One row per calendar day the proposal changes: what is planned now and what would be planned.
    static func rows(before: [Workout], after: [Workout], calendar cal: Calendar = .current) -> [ChangeRow] {
        let f = DateFormatter(); f.dateFormat = "EEE d MMM"; f.calendar = cal; f.timeZone = cal.timeZone
        func text(_ ws: [Workout]) -> String {
            let real = ws.filter { $0.kind != .rest }.sorted { $0.sequence < $1.sequence }
            if real.isEmpty { return "Rest" }
            return real.map { "\($0.displayTitle) · \(Fmt.duration(minutes: $0.minutes))" }.joined(separator: " + ")
        }
        let days = Set((before + after).map { cal.startOfDay(for: $0.date) }).sorted()
        return days.compactMap { day in
            let b = before.filter { cal.isDate($0.date, inSameDayAs: day) }, a = after.filter { cal.isDate($0.date, inSameDayAs: day) }
            let tb = text(b), ta = text(a)
            if tb == ta { return nil }               // same title and length: only the content differs (listed in the summary)
            let all = (b + a).filter { $0.kind != .rest }
            let rides = all.contains { $0.kind.isRide }, lifts = all.contains { $0.kind == .strength }
            return ChangeRow(id: f.string(from: day), day: f.string(from: day), before: tb, after: ta, sport: rides && lifts ? "mixed" : (lifts ? "strength" : "cycling"))
        }
    }

    /// The headline of the preview, in plain words. A scheduling statement only — never a performance prediction.
    static func headline(changedDays: Int, changesSessions: Bool) -> String {
        if !changesSessions { return "No planned sessions change" }
        if changedDays == 0 { return "Session content would change" }
        return "\(changedDays) planned day\(changedDays == 1 ? "" : "s") would change"
    }
}
