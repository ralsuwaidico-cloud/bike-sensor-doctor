import Foundation

/// APP-035 (owner 6 Nov, option 1): when the coach cannot fill a strength session — no exercise in the catalogue is
/// eligible for its slots after the Avoided list, equipment, temporary blocks and pain areas are applied — the app says
/// WHY, in neutral words, and points at the two editors that change it (Equipment, Avoided exercises). Nothing in the
/// planner, the engine or the schema changes: this only reads the same rules `StrengthPlanner.available` applies.
enum EmptyStrengthCheck: Equatable {
    struct Finding: Equatable {
        var total: Int            // exercises in the catalogue
        var avoided: Int          // on the Avoided list
        var noEquipment: Int      // need equipment the rider does not own (or equipment not set → bodyweight only)
        var paused: Int           // temporarily blocked after a discomfort report
        var painHeld: Int         // held because of a reported pain area
        var eligible: Int         // left after all of the above
        var equipmentSet: Bool
        var focus: String
        /// One neutral paragraph for the session screen and the change preview.
        var text: String {
            if total == 0 { return "The exercise catalogue is empty, so the coach cannot build this \(focus) session." }
            var parts: [String] = []
            if avoided > 0 { parts.append("\(avoided) on your Avoided list") }
            if noEquipment > 0 { parts.append(equipmentSet ? "\(noEquipment) need equipment you do not own" : "\(noEquipment) need equipment (yours is not set, so only bodyweight exercises are used)") }
            if paused > 0 { parts.append("\(paused) paused after a discomfort report") }
            if painHeld > 0 { parts.append("\(painHeld) held because of a reported pain area") }
            let why = parts.isEmpty ? "" : " Of \(total) exercises, " + parts.joined(separator: ", ") + "."
            let tail = eligible == 0 ? " None is left to choose from." : " \(eligible) remain, but none fits the movement slots of a \(focus) session."
            return "No exercise fits this \(focus) session, so it has no exercise detail." + why + tail + " Changing Equipment or the Avoided list fills it; the session still counts as planned strength time."
        }
        var suggestsEquipment: Bool { noEquipment > 0 }
        var suggestsAvoided: Bool { avoided > 0 }
    }

    /// Why the catalogue yields nothing for `w` — nil when the session is not a coach-built strength session, or when the
    /// planner does fill it. Pure: reads the context, writes nothing.
    static func check(_ w: Workout, ctx: PlannerContext) -> Finding? {
        guard w.kind == .strength, w.templateId == nil, (w.plannedEntries ?? []).isEmpty else { return nil }
        guard StrengthPlanner.build(for: w, ctx: ctx).entries.isEmpty else { return nil }
        return explain(focus: (w.strengthFocus ?? .fullBody).title.lowercased(), ctx: ctx)
    }

    static func explain(focus: String, ctx: PlannerContext) -> Finding {
        var f = Finding(total: ctx.catalogue.count, avoided: 0, noEquipment: 0, paused: 0, painHeld: 0, eligible: 0, equipmentSet: ctx.equipment.isSet, focus: focus)
        for e in ctx.catalogue {
            // the first rule that removes the exercise is the one counted, in the order the rider can act on them
            if ctx.prefs.avoids(e.id) || ctx.equipment.excluded.contains(e.id) { f.avoided += 1; continue }
            if !ctx.equipment.plannable(e) { f.noEquipment += 1; continue }
            if ctx.prefs.blocked(e.id, now: ctx.now) { f.paused += 1; continue }
            if !ExerciseLibrary.meta(e).tags.isDisjoint(with: ctx.painTags) { f.painHeld += 1; continue }
            f.eligible += 1
        }
        return f
    }

    /// The sessions of a plan-change proposal that would come out empty, each with its reason (recalculated on the exact
    /// sessions that Apply would save; completed sessions are never in a proposal).
    static func warnings(for after: [Workout], ctx: PlannerContext, calendar: Calendar = .current) -> [(workout: Workout, finding: Finding)] {
        after.compactMap { w in check(w, ctx: ctx).map { (w, $0) } }.sorted { $0.workout.date < $1.workout.date }
    }
}
