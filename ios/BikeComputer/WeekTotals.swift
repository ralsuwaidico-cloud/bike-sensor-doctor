import Foundation

/// The week's riding and lifting totals as Plan, Progress and Home show them (RC2 owner report: Plan showed PLANNED
/// minutes under "Riding" while Progress showed DONE minutes, both unlabelled). One source: TrainingLedger (the query
/// layer in WorkoutState.swift), one week boundary (Monday 00:00 – next Monday, local calendar), and two clearly named
/// figures — "Done this week" (rides recorded or imported from Apple Health, sessions logged, marked done or imported,
/// with the minutes actually recorded or typed) and "Planned this week" (planned sessions not skipped, planned minutes).
struct WeekTotals: Equatable {
    let monday: Date
    let riding: TrainingLedger.SportWeek
    let lifting: TrainingLedger.SportWeek

    init(_ ledger: TrainingLedger, weekOf date: Date, calendar cal: Calendar = .current) {
        monday = TrainingLedger.monday(of: date, calendar: cal)
        riding = ledger.riding(weekOf: monday)
        lifting = ledger.lifting(weekOf: monday)
    }

    // MARK: words (the same on every screen)
    static let doneTitle = "Done this week"
    static let plannedTitle = "Planned this week"

    /// "1 h 03 min · 1 ride of 3 planned" (extra, unplanned sessions count too: "3 sessions of 2 planned")
    static func done(_ w: TrainingLedger.SportWeek, singular: String, plural: String) -> String {
        "\(Fmt.duration(minutes: w.minutes)) · \(w.completed) \(w.completed == 1 ? singular : plural) of \(w.planned) planned"
    }
    /// "4 h · 3 rides"
    static func planned(_ w: TrainingLedger.SportWeek, singular: String, plural: String) -> String {
        "\(Fmt.duration(minutes: w.plannedMinutes)) · \(w.planned) \(w.planned == 1 ? singular : plural)"
    }
    /// Progress footer: "Done this week: 1 h 03 min · 1 ride of 3 planned (1 imported). Planned this week: 4 h · 3 rides."
    static func sentence(_ w: TrainingLedger.SportWeek, singular: String, plural: String) -> String {
        var parts: [String] = []
        if w.logged > 0 { parts.append("\(w.logged) logged") }
        if w.manual > 0 { parts.append("\(w.manual) marked or quick") }
        if w.imported > 0 { parts.append("\(w.imported) imported") }
        if w.unknownDuration > 0 { parts.append("\(w.unknownDuration) without duration") }
        return "\(doneTitle): \(done(w, singular: singular, plural: plural))" + (parts.isEmpty ? "" : " (" + parts.joined(separator: ", ") + ")")
            + ". \(plannedTitle): \(planned(w, singular: singular, plural: plural))."
    }
}
