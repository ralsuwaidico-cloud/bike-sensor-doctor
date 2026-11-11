import SwiftUI

// Home v2.1 input models (owner revision, 12 Nov 2026). Plain values only; no production types.

/// One discipline's progress against the approved plan. `fraction == nil` means the discipline is not in the plan —
/// drawn as inactive, never as a failure.
struct CyMixLeg: Equatable {
    let done: String            // "1h 17m"
    let planned: String?        // "2h 45m"; nil = not planned
    let fraction: Double?       // completed ÷ planned, 0…1; nil = not planned
}
struct CyMixModel: Equatable {
    let endurance: CyMixLeg
    let strength: CyMixLeg
    var hasAnyPlan: Bool { endurance.fraction != nil || strength.fraction != nil }
}

/// Recovery is qualitative. The indicator shows which readings exist and one supported word — never a percentage,
/// never a clearance to train.
enum CyRecoveryState: Equatable {
    case available(word: String)     // e.g. "In your usual range"
    case partial(word: String)       // e.g. "Partial data"
    case awaiting                    // no readings
    case concern(word: String)       // e.g. "Outside your usual range"
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
    let target: Int?                 // minutes
    let targetSource: String         // where the target comes from — never invented
    let nights: [CySeriesPoint]      // recent nights, hours
    let guidance: String
    let source: String               // data source and freshness
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

struct CyMetricTile: Identifiable, Equatable {
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
}

struct CySetupStep: Identifiable, Equatable {
    let id: String
    let title: String
    let detail: String
    var isDone: Bool
    let isRequired: Bool
}

enum CyCoachDecision: Equatable { case none, accepted, declined, postponed }
struct CyCoachBannerModel: Equatable {
    let sentence: String
    let why: String
    let hasProposal: Bool
}
