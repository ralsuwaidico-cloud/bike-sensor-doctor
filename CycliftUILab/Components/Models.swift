import SwiftUI

// Input models for the components. Plain values only — no dependency on any production type, database or engine.
// A production adapter later maps real app state onto these (see docs/INTEGRATION_MAP.md).

enum CyCategory { case endurance, strength, recovery, rest
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
    func color(_ t: CyTheme) -> Color {
        switch self {
        case .endurance: return t.endurance
        case .strength: return t.strength
        case .recovery: return t.recovery
        case .rest: return t.textTertiary
        }
    }
}

enum CyStatusLevel { case good, caution, alert, neutral
    func color(_ t: CyTheme) -> Color {
        switch self {
        case .good: return t.success
        case .caution: return t.warning
        case .alert: return t.danger
        case .neutral: return t.textSecondary
        }
    }
    var icon: String {
        switch self {
        case .good: return "checkmark.circle.fill"
        case .caution: return "exclamationmark.triangle.fill"
        case .alert: return "exclamationmark.octagon.fill"
        case .neutral: return "minus.circle.fill"
        }
    }
}

/// What a ring shows. A status ring never carries a number — only a word (owner condition: status labels, not scores).
enum CyRingDisplay: Equatable {
    case fraction(Double, text: String, caption: String)          // e.g. 0.8, "80%", "4 of 5 sessions"
    case status(word: String, level: CyStatusLevel, fill: Double) // e.g. "Balanced", .good, 1.0
    case missing(reason: String)                                  // e.g. "Needs data"
    case loading
}
enum CyRingKind { case consistency, loadBalance, recovery, generic
    func color(_ t: CyTheme) -> Color {
        switch self {
        case .consistency: return t.ringConsistency
        case .loadBalance: return t.ringLoad
        case .recovery: return t.ringRecovery
        case .generic: return t.accent
        }
    }
}
struct CyRingModel: Identifiable, Equatable {
    let id: String
    let title: String
    let kind: CyRingKind
    let display: CyRingDisplay
    static func == (a: CyRingModel, b: CyRingModel) -> Bool { a.id == b.id && a.display == b.display && a.title == b.title }
}

enum CySessionStatus { case done, planned, today, missed, skipped, rest
    var label: String {
        switch self {
        case .done: return "Done"
        case .planned: return "Planned"
        case .today: return "Today"
        case .missed: return "Missed"
        case .skipped: return "Skipped"
        case .rest: return "Rest"
        }
    }
    var icon: String {
        switch self {
        case .done: return "checkmark.circle.fill"
        case .planned: return "circle"
        case .today: return "circle.inset.filled"
        case .missed: return "exclamationmark.circle.fill"
        case .skipped: return "forward.end.circle"
        case .rest: return "moon.circle"
        }
    }
    func color(_ t: CyTheme) -> Color {
        switch self {
        case .done: return t.success
        case .planned: return t.textTertiary
        case .today: return t.accent
        case .missed: return t.warning
        case .skipped, .rest: return t.textTertiary
        }
    }
}

struct CyDayModel: Identifiable, Equatable {
    let id: Int                      // 0 = Monday
    let weekday: String              // "Mon"
    let dayNumber: String            // "11"
    let sessions: [CyCategory]       // empty = rest
    let status: CySessionStatus
    let isToday: Bool
    let detail: String               // one line for the detail sheet and VoiceOver
}

struct CySummaryCardModel: Equatable {
    let category: CyCategory
    let title: String
    let primary: String              // "1 h 17 min"
    let secondary: String            // "of 2 h planned"
    let supporting: String?          // "23.2 km"
    let progress: Double?            // 0…1, nil = no bar
    let trend: [Double]?             // nil or fewer than 2 points = no sparkline, one-line empty text instead
    let trendCaption: String?
}

struct CyWorkoutModel: Equatable {
    let category: CyCategory
    let title: String
    let detail: String               // "35 min · Moderate"
    let status: CySessionStatus
}

struct CyRecoveryModel: Equatable {
    let word: String                 // "Train as planned"
    let level: CyStatusLevel
    let readings: [(label: String, value: String, note: String)]
    let recommendation: String
    static func == (a: CyRecoveryModel, b: CyRecoveryModel) -> Bool { a.word == b.word && a.recommendation == b.recommendation }
}

struct CyCoachModel: Equatable {
    let sentence: String
    let why: String
    let hasProposal: Bool
}

struct CyChecklistItem: Identifiable, Equatable {
    let id: String
    let title: String
    let detail: String?
    var isDone: Bool
    let isEssential: Bool
}

struct CyMetricModel: Equatable {
    let label: String
    let value: String?               // nil = no data
    let unit: String?
    let delta: String?               // "+3 vs last week"
    let deltaLevel: CyStatusLevel
}

struct CyChange: Identifiable, Equatable {
    let id: String
    let label: String
    let before: String
    let after: String
}

struct CySeriesPoint: Identifiable, Equatable {
    let id: Int                      // index on the x axis
    let label: String                // "Mon"
    let value: Double?               // nil = gap (never drawn as zero)
}
struct CySeries: Identifiable, Equatable {
    let id: String
    let name: String
    let unit: String
    let points: [CySeriesPoint]
    let colorKey: CyRingKind
}
/// A categorical row under a chart: one status word per day. Never converted to a number.
struct CyStatusRow: Identifiable, Equatable {
    let id: String
    let name: String
    let cells: [CyStatusCell]
    let colorKey: CyRingKind
}
struct CyStatusCell: Identifiable, Equatable {
    let id: Int
    let word: String?                // nil = no data that day
    let level: CyStatusLevel
}
