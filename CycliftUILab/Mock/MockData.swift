import SwiftUI

// SYNTHETIC SAMPLE DATA ONLY. Nothing here comes from a real athlete, Apple Health, a sensor, the production app
// or any Cyclift engine. Names, dates and numbers are invented for layout review and are labelled as sample data
// on screen. Status words (Load Balance, Recovery) are examples of wording, not computed or validated scores.

enum LabScenario: String, CaseIterable, Identifiable {
    case established, qualitativeRecovery, newUser, loading, cyclingOnly, strengthOnly, noPlan, noRecovery, partialData, noSleep, longName
    var id: String { rawValue }
    var title: String {
        switch self {
        case .established: return "Established hybrid athlete (recovery % = sample)"
        case .qualitativeRecovery: return "Hybrid — recovery as a status word (production fallback)"
        case .noRecovery: return "No recovery data"
        case .noSleep: return "No sleep source"
        case .newUser: return "New athlete (setup open, no history)"
        case .loading: return "Loading"
        case .cyclingOnly: return "Single sport — cycling only"
        case .strengthOnly: return "Single sport — strength only"
        case .noPlan: return "No planned sessions"
        case .partialData: return "No Apple Health, partial sensor data"
        case .longName: return "Long name"
        }
    }
}

struct HomeData: Equatable {
    var dateLine: String
    var greeting: String
    var initials: String
    var rings: [CyRingModel]
    var setup: [CyChecklistItem]
    var days: [CyDayModel]
    var endurance: CySummaryCardModel
    var enduranceEmpty: String?
    var strength: CySummaryCardModel
    var strengthEmpty: String?
    var coach: CyCoachModel?
    var coachEmpty: String?
    var trendLabels: [String]
    var trendSeries: [CySeries]
    var trendRows: [CyStatusRow]
    var trendEmpty: String?
    var sessionsToday: Int

    var essentialsOpen: Bool { setup.contains { $0.isEssential && !$0.isDone } }
}

enum MockData {
    static let weekdays = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]

    static let established = HomeData(
        dateLine: "Wednesday, 11 Nov",
        greeting: "Good afternoon, Alex",
        initials: "A",
        rings: [
            CyRingModel(id: "consistency", title: "Consistency", kind: .consistency, display: .fraction(0.8, text: "80%", caption: "4 of 5 sessions")),
            CyRingModel(id: "load", title: "Load Balance", kind: .loadBalance, display: .status(word: "Balanced", level: .good, fill: 1.0)),
            CyRingModel(id: "recovery", title: "Recovery", kind: .recovery, display: .status(word: "Train as planned", level: .good, fill: 1.0)),
        ],
        setup: [
            CyChecklistItem(id: "plan", title: "Approve your plan", detail: nil, isDone: true, isEssential: true),
            CyChecklistItem(id: "first", title: "Complete your first session", detail: nil, isDone: true, isEssential: true),
            CyChecklistItem(id: "hr", title: "Connect a heart-rate sensor", detail: "Improves effort and load estimates", isDone: true, isEssential: false),
            CyChecklistItem(id: "health", title: "Allow Apple Health", detail: "Sleep and resting heart rate for Recovery", isDone: false, isEssential: false),
        ],
        days: [
            CyDayModel(id: 0, weekday: "Mon", dayNumber: "9", sessions: [.strength], status: .done, isToday: false, detail: "Strength, full body, done"),
            CyDayModel(id: 1, weekday: "Tue", dayNumber: "10", sessions: [.endurance], status: .done, isToday: false, detail: "Endurance ride, 45 minutes, done"),
            CyDayModel(id: 2, weekday: "Wed", dayNumber: "11", sessions: [.endurance, .strength], status: .today, isToday: true, detail: "Recovery spin done, upper body strength planned"),
            CyDayModel(id: 3, weekday: "Thu", dayNumber: "12", sessions: [], status: .rest, isToday: false, detail: "Rest day"),
            CyDayModel(id: 4, weekday: "Fri", dayNumber: "13", sessions: [.strength], status: .planned, isToday: false, detail: "Strength, full body, planned"),
            CyDayModel(id: 5, weekday: "Sat", dayNumber: "14", sessions: [.endurance], status: .planned, isToday: false, detail: "Long ride, 90 minutes, planned"),
            CyDayModel(id: 6, weekday: "Sun", dayNumber: "15", sessions: [], status: .rest, isToday: false, detail: "Rest day"),
        ],
        endurance: CySummaryCardModel(category: .endurance, title: "Endurance", primary: "1 h 17 min", secondary: "of 2 h 45 min planned",
                                      supporting: "23.2 km", progress: 0.47, trend: [150, 165, 140, 175, 160, 185, 170, 77], trendCaption: "Weekly minutes, last 8 weeks"),
        enduranceEmpty: nil,
        strength: CySummaryCardModel(category: .strength, title: "Strength Load", primary: "2 of 3", secondary: "sessions completed",
                                     supporting: "Volume 6,480 kg", progress: 0.67, trend: [3, 3, 2, 3, 3, 3, 2, 2], trendCaption: "Sessions per week, last 8 weeks"),
        strengthEmpty: nil,
        coach: CyCoachModel(sentence: "Your last two upper-body sessions were completed at the top of the range. A small load step is ready for your review.",
                            why: "Both sessions reached the top of the rep range at a reported effort of 7 out of 10. The suggested step is the smallest available (2.5 kg). Sample text only.",
                            hasProposal: true),
        coachEmpty: nil,
        trendLabels: weekdays,
        trendSeries: [
            CySeries(id: "consistency", name: "Consistency", unit: "%", points: zip(0..<7, [100.0, 100, 80, nil, nil, nil, nil] as [Double?]).map { CySeriesPoint(id: $0, label: weekdays[$0], value: $1) }, colorKey: .consistency),
        ],
        trendRows: [
            CyStatusRow(id: "load", name: "Load Balance", cells: [
                CyStatusCell(id: 0, word: "Balanced", level: .good), CyStatusCell(id: 1, word: "Balanced", level: .good),
                CyStatusCell(id: 2, word: "Elevated", level: .caution), CyStatusCell(id: 3, word: nil, level: .neutral),
                CyStatusCell(id: 4, word: nil, level: .neutral), CyStatusCell(id: 5, word: nil, level: .neutral), CyStatusCell(id: 6, word: nil, level: .neutral)],
                        colorKey: .loadBalance),
            CyStatusRow(id: "recovery", name: "Recovery", cells: [
                CyStatusCell(id: 0, word: "Train as planned", level: .good), CyStatusCell(id: 1, word: "Watch", level: .caution),
                CyStatusCell(id: 2, word: "Train as planned", level: .good), CyStatusCell(id: 3, word: nil, level: .neutral),
                CyStatusCell(id: 4, word: nil, level: .neutral), CyStatusCell(id: 5, word: nil, level: .neutral), CyStatusCell(id: 6, word: nil, level: .neutral)],
                        colorKey: .recovery),
        ],
        trendEmpty: nil,
        sessionsToday: 2)

    static let newUser = HomeData(
        dateLine: "Wednesday, 11 Nov",
        greeting: "Welcome, Alex",
        initials: "A",
        rings: [
            CyRingModel(id: "consistency", title: "Consistency", kind: .consistency, display: .missing(reason: "Starts with your first session")),
            CyRingModel(id: "load", title: "Load Balance", kind: .loadBalance, display: .missing(reason: "Needs 4 weeks of sessions")),
            CyRingModel(id: "recovery", title: "Recovery", kind: .recovery, display: .missing(reason: "No readings")),
        ],
        setup: [
            CyChecklistItem(id: "plan", title: "Approve your plan", detail: "Review the week Cyclift prepared", isDone: true, isEssential: true),
            CyChecklistItem(id: "first", title: "Complete your first session", detail: "Any planned session counts", isDone: false, isEssential: true),
            CyChecklistItem(id: "hr", title: "Connect a heart-rate sensor", detail: "Improves effort and load estimates", isDone: false, isEssential: false),
            CyChecklistItem(id: "health", title: "Allow Apple Health", detail: "Sleep and resting heart rate for Recovery", isDone: false, isEssential: false),
        ],
        days: [
            CyDayModel(id: 0, weekday: "Mon", dayNumber: "9", sessions: [], status: .rest, isToday: false, detail: "Before your plan started"),
            CyDayModel(id: 1, weekday: "Tue", dayNumber: "10", sessions: [], status: .rest, isToday: false, detail: "Before your plan started"),
            CyDayModel(id: 2, weekday: "Wed", dayNumber: "11", sessions: [.strength], status: .today, isToday: true, detail: "Strength, full body, planned today"),
            CyDayModel(id: 3, weekday: "Thu", dayNumber: "12", sessions: [], status: .rest, isToday: false, detail: "Rest day"),
            CyDayModel(id: 4, weekday: "Fri", dayNumber: "13", sessions: [.endurance], status: .planned, isToday: false, detail: "Endurance ride, 40 minutes, planned"),
            CyDayModel(id: 5, weekday: "Sat", dayNumber: "14", sessions: [.strength], status: .planned, isToday: false, detail: "Strength, full body, planned"),
            CyDayModel(id: 6, weekday: "Sun", dayNumber: "15", sessions: [], status: .rest, isToday: false, detail: "Rest day"),
        ],
        endurance: CySummaryCardModel(category: .endurance, title: "Endurance", primary: "0 min", secondary: "of 40 min planned", supporting: nil, progress: 0, trend: nil, trendCaption: nil),
        enduranceEmpty: "No rides yet. Your first ride appears here.",
        strength: CySummaryCardModel(category: .strength, title: "Strength Load", primary: "0 of 2", secondary: "sessions completed", supporting: nil, progress: 0, trend: nil, trendCaption: nil),
        strengthEmpty: nil,
        coach: nil,
        coachEmpty: "Complete a session and answer the short check-in. The coach starts from what you actually do.",
        trendLabels: weekdays,
        trendSeries: [],
        trendRows: [],
        trendEmpty: "Trends appear once you have completed sessions. Nothing is estimated in the meantime.",
        sessionsToday: 1)

    // Gallery samples
    static let longText = "A deliberately long piece of text to check that this component wraps onto several lines instead of truncating or pushing its neighbours off the screen"
    static let recovery = CyRecoveryModel(word: "Train as planned", level: .good,
        readings: [("Sleep", "7 h 20 min", "in your usual range"), ("Resting heart rate", "52 bpm", "in your usual range"), ("HRV", "—", "no reading today")],
        recommendation: "Sample wording: your readings are within your own usual range. This is general guidance, not medical advice.")
    static let workout = CyWorkoutModel(category: .strength, title: "Strength · Upper body", detail: "35 min · Moderate", status: .today)
    static let workoutLong = CyWorkoutModel(category: .endurance, title: "Endurance ride with three long tempo intervals and an extended cool-down", detail: "1 h 30 min · Moderate to hard · Zones 2 to 3", status: .planned)
    static let metric = CyMetricModel(label: "Sessions this week", value: "4", unit: "of 5", delta: "+1 vs last week", deltaLevel: .good)
    static let metricEmpty = CyMetricModel(label: "Average heart rate", value: nil, unit: "bpm", delta: nil, deltaLevel: .neutral)
    static let changes = [
        CyChange(id: "load", label: "Bench press load", before: "40 kg", after: "42.5 kg"),
    ]
    static let sports = [
        CySportOption(id: "cycling", title: "Cycling", icon: "bicycle", note: "Full coaching"),
        CySportOption(id: "strength", title: "Strength", icon: "dumbbell.fill", note: "Full coaching"),
        CySportOption(id: "running", title: "Running", icon: "figure.run", note: "Logging only (planned)"),
        CySportOption(id: "swimming", title: "Swimming", icon: "figure.pool.swim", note: "Not available yet", isAvailable: false),
    ]
    static let weekly: [CySeriesPoint] = zip(0..<6, [150.0, 165, 140, 175, 160, 185]).map { CySeriesPoint(id: $0, label: "W\($0 + 1)", value: $1) }
    static let multiSeries = [
        CySeries(id: "a", name: "Endurance min", unit: "", points: zip(0..<7, [30.0, 45, nil, 0, 40, 90, nil] as [Double?]).map { CySeriesPoint(id: $0, label: weekdays[$0], value: $1) }, colorKey: .consistency),
        CySeries(id: "b", name: "Strength min", unit: "", points: zip(0..<7, [40.0, nil, 35, nil, 40, nil, nil] as [Double?]).map { CySeriesPoint(id: $0, label: weekdays[$0], value: $1) }, colorKey: .loadBalance),
    ]
}
