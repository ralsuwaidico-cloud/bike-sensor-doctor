import Foundation

// Home v2.3 — input models. PROVISIONAL design (owner direction of 12 Nov 2026; not yet visually approved).
// Brought over from the UI Lab prototype (branch proto/ui-lab: Components/ModelsV21.swift, Components/Models.swift,
// Mock/MockV21.swift, Components/CoachConversation.swift) as shared code for both apps. Plain values only; Foundation
// only, so the Linux harness tests the adapter that fills them (HomeV23Builder.swift). The colour of a category or a
// graph series is decided by the theme in Redesign/HomeV23Components.swift.
// Renamed on the way in: the prototype's CyHomeMetric is CyHomeMetric here (the app already has a view of that name).

enum CyCategory: Equatable { case endurance, strength, recovery, rest
    var icon: String {
        switch self {
        case .endurance: return "bicycle"
        case .strength: return "dumbbell.fill"
        case .recovery: return "heart.fill"
        case .rest: return "moon.fill"
        }
    }
    var label: String {
        switch self {
        case .endurance: return "Endurance"
        case .strength: return "Strength"
        case .recovery: return "Recovery"
        case .rest: return "Rest"
        }
    }
}

enum CyStatusLevel: Equatable { case good, caution, alert, neutral }

struct CySeriesPoint: Identifiable, Equatable {
    let id: Int                      // index on the x axis
    let label: String                // "Mon"
    let value: Double?               // nil = gap (never drawn as zero)
}

/// One discipline's progress against the approved plan. `fraction == nil` means the discipline is not in the plan —
/// drawn as inactive, never as a failure.
struct CyMixLeg: Equatable {
    let done: String            // "1h 17m"
    let planned: String?        // "2h 45m"; nil = not planned
    let fraction: Double?       // completed ÷ planned, 0…1; nil = not planned
    var minutesDone: Int = 0    // completed training time, minutes (v2.2 — basis of the centre ratio)
    var minutesPlanned: Int? = nil
}
struct CyMixModel: Equatable {
    let endurance: CyMixLeg
    let strength: CyMixLeg
    var hasAnyPlan: Bool { endurance.fraction != nil || strength.fraction != nil }

    /// Documented prototype formula (v2.2): the centre ratio is the composition of COMPLETED TRAINING TIME —
    /// endurance minutes : strength minutes, each as a rounded share of their sum. Minutes are the only quantity
    /// used; kilograms, watts, distance and session load are never mixed in. nil when no time has been completed.
    /// The two ring arcs are a different measurement (each discipline's completed ÷ planned).
    var completedRatio: (endurance: Int, strength: Int)? { CyMixModel.ratio(endurance.minutesDone, strength.minutesDone) }
    /// Same formula on planned minutes (shown in the detail sheet only).
    var plannedRatio: (endurance: Int, strength: Int)? { CyMixModel.ratio(endurance.minutesPlanned ?? 0, strength.minutesPlanned ?? 0) }
    static func ratio(_ e: Int, _ s: Int) -> (endurance: Int, strength: Int)? {
        let total = e + s
        guard total > 0 else { return nil }
        let ePct = Int((Double(e) / Double(total) * 100).rounded())
        return (ePct, 100 - ePct)
    }
    var ratioText: String? { completedRatio.map { "\($0.endurance):\($0.strength)" } }
}

/// Recovery is qualitative. The indicator shows which readings exist and one supported word — never a percentage,
/// never a clearance to train.
/// v2.2. A percentage is shown ONLY from clearly marked sample data in the UI Lab. Production has no approved
/// numerical recovery model: until one exists it must use `.qualitative`, `.partial` or `.awaiting` — never a number
/// built from arbitrary sleep / HRV / resting-HR weights. No state is a medical clearance.
enum CyRecoveryState: Equatable {
    case numericSample(percent: Int, word: String)   // UI Lab sample only
    case qualitative(word: String)                   // e.g. "In your usual range" — status, no number
    case partial(word: String)                       // some readings missing; no overall statement
    case awaiting                                    // no readings
}
struct CyRecoverySource: Identifiable, Equatable {
    let id: String
    let name: String                 // "Sleep", "Resting heart rate", "HRV"
    let value: String?               // nil = no reading
    let note: String                 // "in your usual range", "no reading today"
}
struct CyRecoveryIndicatorModel: Equatable {
    let state: CyRecoveryState
    let sources: [CyRecoverySource]
    let guidance: String
    let freshness: String            // "Updated this morning · Apple Health (sample)"
}

enum CySessionState: Equatable { case completed, planned, missed, rescheduled
    var label: String {
        switch self {
        case .completed: return "completed"
        case .planned: return "planned"
        case .missed: return "missed"
        case .rescheduled: return "rescheduled"
        }
    }
}
struct CyDaySession: Identifiable, Equatable {
    let id: String
    let category: CyCategory
    let state: CySessionState
    let title: String                // "Endurance ride"
    let detail: String               // "45 min · easy"
}
struct CyScheduleDay: Identifiable, Equatable {
    let id: Int
    let letter: String               // "M"
    let weekday: String              // "Monday"
    let date: String                 // "9 Nov"
    let sessions: [CyDaySession]     // empty = rest day (or no plan)
    let isToday: Bool
    let isRest: Bool                 // false with no sessions = nothing planned (not a rest day)
}

struct CySportCardModel: Equatable {
    let category: CyCategory
    let title: String                // "Endurance" / "Strength"
    let done: String?                // "1h 17m" / "2"; nil = no data yet
    let planned: String?             // "2h 45m" / "3 sessions"; nil = not in the plan
    let fraction: Double?
    let secondary: String?           // one metric: "23.2 km" / "6,480 kg lifted"
    let emptyText: String?           // shown instead of numbers
    // detail sheet only (moved off Home in v2.1)
    let history: [Double]
    let historyCaption: String
}

struct CySleepModel: Equatable {
    let lastNight: Int?              // minutes; nil = no record
    let average7: Int?               // minutes
    var target: Int?                 // minutes — the athlete's own choice; nil = not set
    var targetSource: String         // where the target comes from — never invented
    let nights: [CySeriesPoint]      // recent nights, hours
    let guidance: String
    let source: String               // data source and freshness
    var targetLabel: String = "Target"   // what kind of target this is: "Your target", "Sample target" — never an invented need
    /// App integration: false while the app has no sleep-target setting, so Home never offers a control that does nothing.
    var canSetTarget: Bool = true
    static func text(_ minutes: Int) -> String { "\(minutes / 60)h \(String(format: "%02d", minutes % 60))m" }
}

struct CyTrendDetailRow: Identifiable, Equatable {
    let id: String
    let label: String
    let value: String
}
struct CyTrendDay: Identifiable, Equatable {
    let id: Int
    let short: String                // "M" (large text)
    let label: String                // "Mon"
    let full: String                 // "Monday 9 November"
    let endurance: Double?           // minutes completed; nil = none recorded
    let strength: Double?
    let planned: Double?             // minutes still planned (today / future)
    let hasData: Bool                // false = nothing recorded and nothing planned → "No data"
    let rows: [CyTrendDetailRow]     // what the day sheet / tooltip lists
}
struct CyTrendRange: Identifiable, Equatable {
    let id: String                   // "7d", "4w"
    let title: String                // "7 days"
    let unit: String                 // "min"
    let days: [CyTrendDay]
}

struct CyHomeMetric: Identifiable, Equatable {
    let id: String
    let icon: String
    let name: String
    let value: String?               // nil = no data
    let unit: String
    let trend: String?               // "−2 vs 4-week avg"
    let trendLevel: CyStatusLevel
    let explanation: String
    let source: String
    let history: [CySeriesPoint]
    let historyUnit: String
    var baseline: String? = nil      // comparison value shown under the main value, e.g. "avg 53"
    var direction: CyDirection = .none
}
/// Direction against the athlete's own baseline. A neutral marker: up or down is not labelled good or bad.
enum CyDirection: Equatable { case up, down, flat, none
    var symbol: String? {
        switch self {
        case .up: return "arrowtriangle.up.fill"
        case .down: return "arrowtriangle.down.fill"
        case .flat: return "circle.fill"
        case .none: return nil
        }
    }
    var spoken: String {
        switch self {
        case .up: return "above your average"
        case .down: return "below your average"
        case .flat: return "at your average"
        case .none: return ""
        }
    }
}
enum CyMetricStyle: String { case rows, grid }

struct CySetupStep: Identifiable, Equatable {
    let id: String
    let title: String
    let detail: String
    var isDone: Bool
    let isRequired: Bool
}

// MARK: v2.2 graph models

enum CyGraphColor: Equatable { case endurance, strength, recovery, consistency, load, neutral }
enum CyGraphAxis: Equatable { case leading, trailing }
/// Where a series would come from at integration — recorded per series so nothing is mistaken for a real measurement.
enum CyGraphProvenance: String, Equatable {
    case existingEngine = "Existing engine data"
    case needsMapping = "Needs additional mapping"
    case needsCalculation = "Needs a new calculation"
    case needsValidation = "Needs scientific validation"
}
struct CyGraphSeries: Identifiable, Equatable {
    let id: String
    let name: String                 // "Endurance"
    let unit: String                 // "min"
    let source: String               // "Sample · Cyclift sessions"
    let provenance: CyGraphProvenance
    let color: CyGraphColor
    let axis: CyGraphAxis
    var dashed: Bool = false
    var isSampleScore: Bool = false  // true = a number that only exists as UI Lab sample data (e.g. recovery %)
    var fixedDomain: ClosedRange<Double>? = nil
    let values: [Double?]            // one per date; nil = no measurement (drawn as a gap)
    func text(_ v: Double?) -> String {
        guard let v else { return "No data" }
        if unit == "h" { return String(format: "%.1f h", v) }
        return "\(Int(v.rounded())) \(unit)"
    }
}
struct CyGraphDate: Identifiable, Equatable {
    let id: Int
    let axisLabel: String?           // shown under the axis (nil = no tick label, e.g. most days in the 4-week view)
    let short: String                // single letter for large text
    let full: String                 // "Wednesday 11 Nov"
}
struct CyGraphMode: Identifiable, Equatable {
    let id: String                   // "recovery", "activity", "trends"
    let title: String                // "Training & Recovery"
    let singleSelection: Bool        // true = one metric at a time (units differ)
    let series: [CyGraphSeries]
    let note: String?                // one short line, e.g. "Recovery % is sample data"
}
struct CyGraphRange: Identifiable, Equatable {
    let id: String                   // "7d", "4w"
    let title: String
    let dates: [CyGraphDate]
    let modes: [CyGraphMode]
}


struct CyConsistencyModel: Equatable {
    let fraction: Double?            // completed ÷ eligible planned sessions to date; nil = nothing eligible yet
    let text: String                 // "80%"
    let caption: String              // "4 of 5 sessions"
    let counts: [CyTrendDetailRow]   // planned / completed / missed / skipped — for a detail page
}

struct CyCoachPreviewModel: Equatable {
    let text: String
    let needsDecision: Bool
}

/// Everything Home v2.3 shows. Filled from the athlete's own records by `Store.homeV23` (HomeV23Builder.swift).
struct Home21Data: Equatable {
    var dateLine: String
    var name: String
    var athleteType: String?
    var initials: String
    var consistency: CyConsistencyModel
    var mix: CyMixModel
    var recovery: CyRecoveryIndicatorModel
    var steps: [CySetupStep]
    var days: [CyScheduleDay]
    var endurance: CySportCardModel?     // nil = this athlete does not ride (strength-only): the card is not shown
    var strength: CySportCardModel?      // nil = this athlete does not lift (cycling-only)
    var sleep: CySleepModel
    var coachEmpty: String?
    var trendsEmpty: String?
    var graph: [CyGraphRange]
    var metrics: [CyHomeMetric]
    var requiredOpen: Bool { steps.contains { $0.isRequired && !$0.isDone } }
}
