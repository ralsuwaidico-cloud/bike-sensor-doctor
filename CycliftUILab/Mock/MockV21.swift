import SwiftUI

// SYNTHETIC SAMPLE DATA for Home v2.1. Invented values for layout review; nothing is measured or computed by a
// Cyclift engine. The sleep target is a labelled sample, not a recommendation.

struct CyConsistencyModel: Equatable {
    let fraction: Double?            // completed ÷ eligible planned sessions to date; nil = nothing eligible yet
    let text: String                 // "80%"
    let caption: String              // "4 of 5 sessions"
    let counts: [CyTrendDetailRow]   // planned / completed / missed / rescheduled / rest days — for the detail sheet
}

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
    var endurance: CySportCardModel
    var strength: CySportCardModel
    var sleep: CySleepModel
    var coach: CyCoachBannerModel?
    var coachEmpty: String?
    var trends: [CyTrendRange]
    var trendsEmpty: String?
    var metrics: [CyMetricTile]
    var sessionsToday: Int
    var requiredOpen: Bool { steps.contains { $0.isRequired && !$0.isDone } }
}

enum Mock21 {
    static let letters = ["M", "T", "W", "T", "F", "S", "S"]
    static let names = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]
    static let shorts = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
    static let dates = ["9 Nov", "10 Nov", "11 Nov", "12 Nov", "13 Nov", "14 Nov", "15 Nov"]

    static func ride(_ id: String, _ state: CySessionState, _ title: String = "Endurance ride", _ detail: String = "45 min · easy") -> CyDaySession {
        CyDaySession(id: id, category: .endurance, state: state, title: title, detail: detail)
    }
    static func lift(_ id: String, _ state: CySessionState, _ title: String = "Strength session", _ detail: String = "35 min · moderate") -> CyDaySession {
        CyDaySession(id: id, category: .strength, state: state, title: title, detail: detail)
    }
    static func day(_ i: Int, _ sessions: [CyDaySession], rest: Bool = false) -> CyScheduleDay {
        CyScheduleDay(id: i, letter: letters[i], weekday: names[i], date: dates[i], sessions: sessions, isToday: i == 2, isRest: rest)
    }
    static func row(_ label: String, _ value: String) -> CyTrendDetailRow { CyTrendDetailRow(id: label, label: label, value: value) }
    static func trendDay(_ i: Int, e: Double?, s: Double?, p: Double?, rows: [CyTrendDetailRow]) -> CyTrendDay {
        CyTrendDay(id: i, short: letters[i], label: shorts[i], full: "\(names[i]) \(dates[i])", endurance: e, strength: s, planned: p,
                   hasData: (e ?? 0) > 0 || (s ?? 0) > 0 || (p ?? 0) > 0 || !rows.isEmpty, rows: rows)
    }
    static func points(_ labels: [String], _ values: [Double?]) -> [CySeriesPoint] {
        var out: [CySeriesPoint] = []
        for (i, v) in values.enumerated() { out.append(CySeriesPoint(id: i, label: i < labels.count ? labels[i] : "\(i + 1)", value: v)) }
        return out
    }
    static let weeks8 = ["W1", "W2", "W3", "W4", "W5", "W6", "W7", "W8"]

    static func make(_ scenario: LabScenario) -> Home21Data {
        switch scenario {
        case .established, .loading: return hybrid()
        case .newUser: return newAthlete()
        case .cyclingOnly: return cyclingOnly()
        case .strengthOnly: return strengthOnly()
        case .noPlan: return noPlan()
        case .partialData: return partialData()
        case .longName:
            var d = hybrid()
            d.name = "Alexandria-Maximiliana Featherstonehaugh"
            d.athleteType = "Hybrid athlete · cycling and strength"
            d.initials = "AF"
            return d
        }
    }

    // MARK: shared pieces

    static let sleepFull = CySleepModel(
        lastNight: 430, average7: 422, target: 480, targetSource: "sample target for the prototype",
        nights: points(shorts, [7.4, 6.8, 7.2, 6.5, 7.6, 6.9, 7.2]),
        guidance: "Sample wording: your last night was close to your seven-day average. General guidance, not medical advice.",
        source: "Sample data · would read \"Apple Health · updated this morning\"")
    static let sleepNone = CySleepModel(
        lastNight: nil, average7: nil, target: nil, targetSource: "no target set", nights: [],
        guidance: "Sleep appears here once a sleep source is connected. Nothing is estimated.",
        source: "No sleep source connected")

    static let recoveryFull = CyRecoveryIndicatorModel(
        state: .available(word: "In your usual range"),
        sources: [CyRecoverySource(id: "sleep", name: "Sleep", value: "7h 10m", note: "in your usual range"),
                  CyRecoverySource(id: "rhr", name: "Resting heart rate", value: "52 bpm", note: "in your usual range"),
                  CyRecoverySource(id: "hrv", name: "HRV", value: "64 ms", note: "in your usual range")],
        guidance: "Sample wording: today's readings sit inside your own recent range. This is general wellness information, not medical advice and not a clearance to train.",
        freshness: "Sample data · would read \"Apple Health · updated this morning\"")
    static let recoveryPartial = CyRecoveryIndicatorModel(
        state: .partial(word: "Partial data"),
        sources: [CyRecoverySource(id: "sleep", name: "Sleep", value: nil, note: "no sleep source connected"),
                  CyRecoverySource(id: "rhr", name: "Resting heart rate", value: "54 bpm", note: "from your heart-rate strap during rides"),
                  CyRecoverySource(id: "hrv", name: "HRV", value: nil, note: "no reading")],
        guidance: "Only one of three readings is available, so no overall statement is made.",
        freshness: "Sample data · heart-rate strap only")
    static let recoveryNone = CyRecoveryIndicatorModel(
        state: .awaiting,
        sources: [CyRecoverySource(id: "sleep", name: "Sleep", value: nil, note: "no reading"),
                  CyRecoverySource(id: "rhr", name: "Resting heart rate", value: nil, note: "no reading"),
                  CyRecoverySource(id: "hrv", name: "HRV", value: nil, note: "no reading")],
        guidance: "Recovery information appears once readings are available. Nothing is estimated in the meantime.",
        freshness: "No source connected")

    static func metric(_ id: String, _ icon: String, _ name: String, _ value: String?, _ unit: String, _ trend: String?, _ level: CyStatusLevel,
                       _ explanation: String, _ source: String, _ history: [Double?], _ historyUnit: String) -> CyMetricTile {
        CyMetricTile(id: id, icon: icon, name: name, value: value, unit: unit, trend: trend, trendLevel: level, explanation: explanation,
                     source: source, history: points(weeks8, history), historyUnit: historyUnit)
    }
    static let mRHR = metric("rhr", "heart", "Resting HR", "52", "bpm", "−1 vs 4-week avg", .neutral,
                             "Your lowest stable heart rate at rest, compared with your own recent average.", "Sample · Apple Health", [54, 53, 54, 53, 53, 52, 53, 52], "bpm")
    static let mHRV = metric("hrv", "waveform.path.ecg", "HRV", "64", "ms", "in your usual range", .neutral,
                             "Heart-rate variability overnight, compared with your own usual range. It varies a lot between people.", "Sample · Apple Health", [61, 66, 58, 63, 65, 62, 60, 64], "ms")
    static let mTime = metric("time", "clock", "Training time", "1h 57m", "this week", "of 5h 25m planned", .neutral,
                              "Total recorded training time this week across both disciplines.", "Sample · Cyclift sessions", [255, 270, 230, 285, 260, 290, 275, 117], "min")
    static let mLoad = metric("load", "chart.bar", "Weekly load", "410", "pts", "session effort × minutes", .neutral,
                              "Each session's effort rating multiplied by its minutes, added up for the week. It needs an effort rating or heart rate for every session.", "Sample · Cyclift sessions", [720, 760, 640, 800, 730, 820, 770, 410], "pts")
    static let mPower = metric("power", "bolt", "Avg ride power", "168", "W", "last 3 rides", .neutral,
                               "Average power across your recent rides, from your power meter.", "Sample · power meter", [158, 160, 157, 163, 165, 162, 166, 168], "W")
    static let mVolume = metric("volume", "scalemass", "Strength volume", "3,240", "kg", "1 session this week", .neutral,
                                "Sets × reps × load for logged strength sets this week.", "Sample · logged sets", [9100, 9400, 6200, 9600, 9300, 9800, 6400, 3240], "kg")

    // MARK: scenarios

    static func hybrid() -> Home21Data {
        let days = [
            day(0, [lift("m1", .completed, "Strength · full body", "40 min · moderate"), ride("m2", .missed, "Endurance ride", "45 min · easy")]),
            day(1, [ride("t1", .completed, "Endurance ride", "45 min · easy")]),
            day(2, [ride("w1", .completed, "Recovery spin", "32 min · easy"), lift("w2", .planned, "Strength · upper body", "35 min · moderate")]),
            day(3, [], rest: true),
            day(4, [lift("f1", .planned, "Strength · full body", "40 min · moderate")]),
            day(5, [ride("s1", .planned, "Long ride", "1h 30m · steady")]),
            day(6, [], rest: true),
        ]
        let week = CyTrendRange(id: "7d", title: "7 days", unit: "minutes", days: [
            trendDay(0, e: nil, s: 40, p: nil, rows: [row("Strength", "Full body · 40 min"), row("Endurance", "Ride missed"), row("Recovery", "In your usual range"), row("Sleep", "7h 24m")]),
            trendDay(1, e: 45, s: nil, p: nil, rows: [row("Endurance", "45 min · 23.2 km"), row("Recovery", "In your usual range"), row("Sleep", "6h 48m")]),
            trendDay(2, e: 32, s: nil, p: 35, rows: [row("Endurance", "Recovery spin · 32 min"), row("Strength", "Upper body · planned 35 min"), row("Recovery", "In your usual range"), row("Sleep", "7h 10m")]),
            trendDay(3, e: nil, s: nil, p: nil, rows: [row("Plan", "Rest day")]),
            trendDay(4, e: nil, s: nil, p: 40, rows: [row("Strength", "Full body · planned 40 min")]),
            trendDay(5, e: nil, s: nil, p: 90, rows: [row("Endurance", "Long ride · planned 1h 30m")]),
            trendDay(6, e: nil, s: nil, p: nil, rows: [row("Plan", "Rest day")]),
        ])
        let fourWeeks = CyTrendRange(id: "4w", title: "4 weeks", unit: "minutes per week", days: [
            CyTrendDay(id: 0, short: "1", label: "W1", full: "Week of 19 Oct", endurance: 165, strength: 115, planned: nil, hasData: true, rows: [row("Endurance", "2h 45m"), row("Strength", "3 sessions · 1h 55m")]),
            CyTrendDay(id: 1, short: "2", label: "W2", full: "Week of 26 Oct", endurance: 150, strength: 80, planned: nil, hasData: true, rows: [row("Endurance", "2h 30m"), row("Strength", "2 sessions · 1h 20m")]),
            CyTrendDay(id: 2, short: "3", label: "W3", full: "Week of 2 Nov", endurance: 170, strength: 120, planned: nil, hasData: true, rows: [row("Endurance", "2h 50m"), row("Strength", "3 sessions · 2h 00m")]),
            CyTrendDay(id: 3, short: "4", label: "W4", full: "This week", endurance: 77, strength: 40, planned: 165, hasData: true, rows: [row("Endurance", "1h 17m of 3h 30m"), row("Strength", "1 of 3 sessions")]),
        ])
        return Home21Data(
            dateLine: "Wed 11 Nov", name: "Alex", athleteType: "Hybrid athlete", initials: "A",
            consistency: CyConsistencyModel(fraction: 0.75, text: "75%", caption: "3 of 4 sessions",
                counts: [row("Planned to date", "4"), row("Completed", "3"), row("Missed", "1"), row("Rescheduled", "0"), row("Still to come", "3"), row("Rest days", "2 · not counted")]),
            mix: CyMixModel(endurance: CyMixLeg(done: "1h 17m", planned: "3h 30m", fraction: 0.37), strength: CyMixLeg(done: "1", planned: "3 sessions", fraction: 0.33)),
            recovery: recoveryFull,
            steps: [CySetupStep(id: "plan", title: "Approve your plan", detail: "Review the week Cyclift prepared", isDone: true, isRequired: true),
                    CySetupStep(id: "first", title: "Complete your first session", detail: "Any planned session counts", isDone: true, isRequired: true),
                    CySetupStep(id: "hr", title: "Connect a heart-rate sensor", detail: "Improves effort estimates", isDone: true, isRequired: false),
                    CySetupStep(id: "health", title: "Allow Apple Health", detail: "Sleep and resting heart rate", isDone: false, isRequired: false)],
            days: days,
            endurance: CySportCardModel(category: .endurance, title: "Endurance", done: "1h 17m", planned: "3h 30m", fraction: 0.37, secondary: "23.2 km ridden", emptyText: nil,
                                        history: [150, 165, 140, 175, 160, 185, 170, 77], historyCaption: "Minutes per week, last 8 weeks"),
            strength: CySportCardModel(category: .strength, title: "Strength", done: "1", planned: "3 sessions", fraction: 0.33, secondary: "3,240 kg lifted", emptyText: nil,
                                       history: [3, 3, 2, 3, 3, 3, 2, 1], historyCaption: "Sessions per week, last 8 weeks"),
            sleep: sleepFull,
            coach: CyCoachBannerModel(sentence: "Two upper-body sessions reached the top of the range. A small load step is ready.",
                                      why: "Both sessions reached the top of the rep range at a reported effort of 7 out of 10. The suggested step is the smallest available (2.5 kg). Nothing changes unless you approve it. Sample text.",
                                      hasProposal: true),
            coachEmpty: nil,
            trends: [week, fourWeeks], trendsEmpty: nil,
            metrics: [mRHR, mHRV, mTime, mLoad, mPower, mVolume],
            sessionsToday: 2)
    }

    static func newAthlete() -> Home21Data {
        var d = hybrid()
        d.name = "Alex"; d.athleteType = nil
        d.consistency = CyConsistencyModel(fraction: nil, text: "", caption: "Starts with your first session", counts: [row("Planned to date", "0"), row("Completed", "0")])
        d.mix = CyMixModel(endurance: CyMixLeg(done: "0m", planned: "40m", fraction: 0), strength: CyMixLeg(done: "0", planned: "2 sessions", fraction: 0))
        d.recovery = recoveryNone
        d.steps = [CySetupStep(id: "plan", title: "Approve your plan", detail: "Review the week Cyclift prepared", isDone: true, isRequired: true),
                   CySetupStep(id: "first", title: "Complete your first session", detail: "Any planned session counts", isDone: false, isRequired: true),
                   CySetupStep(id: "hr", title: "Connect a heart-rate sensor", detail: "Improves effort estimates", isDone: false, isRequired: false),
                   CySetupStep(id: "health", title: "Allow Apple Health", detail: "Sleep and resting heart rate", isDone: false, isRequired: false)]
        d.days = [day(0, []), day(1, []), day(2, [lift("w1", .planned, "Strength · full body", "30 min · easy start")]), day(3, [], rest: true),
                  day(4, [ride("f1", .planned, "Endurance ride", "40 min · easy")]), day(5, [lift("s1", .planned, "Strength · full body", "30 min")]), day(6, [], rest: true)]
        d.endurance = CySportCardModel(category: .endurance, title: "Endurance", done: nil, planned: "40m", fraction: 0, secondary: nil, emptyText: "No rides yet · 40m planned", history: [], historyCaption: "")
        d.strength = CySportCardModel(category: .strength, title: "Strength", done: nil, planned: "2 sessions", fraction: 0, secondary: nil, emptyText: "No sessions yet · 2 planned", history: [], historyCaption: "")
        d.sleep = sleepNone
        d.coach = nil
        d.coachEmpty = "Complete a session and the short check-in. The coach starts from what you actually do."
        d.trends = []; d.trendsEmpty = "Your training appears here after your first session."
        d.metrics = [mRHR, mHRV, mTime, mLoad].map { m in
            CyMetricTile(id: m.id, icon: m.icon, name: m.name, value: nil, unit: m.unit, trend: nil, trendLevel: .neutral, explanation: m.explanation, source: "No data yet", history: [], historyUnit: m.historyUnit)
        }
        d.sessionsToday = 1
        return d
    }

    static func cyclingOnly() -> Home21Data {
        var d = hybrid()
        d.athleteType = "Cyclist"
        d.mix = CyMixModel(endurance: CyMixLeg(done: "2h 02m", planned: "4h 30m", fraction: 0.45), strength: CyMixLeg(done: "0", planned: nil, fraction: nil))
        d.consistency = CyConsistencyModel(fraction: 1.0, text: "100%", caption: "3 of 3 sessions", counts: [row("Planned to date", "3"), row("Completed", "3"), row("Missed", "0"), row("Rescheduled", "1 (moved to Friday)")])
        d.days = [day(0, [ride("m1", .completed)]), day(1, [ride("t1", .completed, "Tempo ride", "50 min · moderate")]), day(2, [ride("w1", .completed, "Recovery spin", "27 min · easy")]),
                  day(3, [ride("th1", .rescheduled, "Endurance ride", "moved to Friday")]), day(4, [ride("f1", .planned)]), day(5, [ride("s1", .planned, "Long ride", "2h · steady")]), day(6, [], rest: true)]
        d.endurance = CySportCardModel(category: .endurance, title: "Endurance", done: "2h 02m", planned: "4h 30m", fraction: 0.45, secondary: "58.4 km ridden", emptyText: nil,
                                       history: [240, 255, 230, 270, 260, 280, 265, 122], historyCaption: "Minutes per week, last 8 weeks")
        d.strength = CySportCardModel(category: .strength, title: "Strength", done: nil, planned: nil, fraction: nil, secondary: nil, emptyText: "Not in your plan", history: [], historyCaption: "")
        d.metrics = [mRHR, mHRV, mTime, mPower]
        d.coach = CyCoachBannerModel(sentence: "Keep this week as planned.", why: "Your last sessions were completed as planned and nothing suggests a change. Sample text.", hasProposal: false)
        d.sessionsToday = 0
        return d
    }

    static func strengthOnly() -> Home21Data {
        var d = hybrid()
        d.athleteType = "Strength athlete"
        d.mix = CyMixModel(endurance: CyMixLeg(done: "0m", planned: nil, fraction: nil), strength: CyMixLeg(done: "2", planned: "4 sessions", fraction: 0.5))
        d.consistency = CyConsistencyModel(fraction: 0.67, text: "67%", caption: "2 of 3 sessions", counts: [row("Planned to date", "3"), row("Completed", "2"), row("Missed", "1"), row("Rescheduled", "0")])
        d.days = [day(0, [lift("m1", .completed, "Push", "45 min")]), day(1, [lift("t1", .missed, "Pull", "45 min")]), day(2, [lift("w1", .completed, "Legs", "50 min")]),
                  day(3, [], rest: true), day(4, [lift("f1", .planned, "Push", "45 min")]), day(5, [lift("s1", .planned, "Pull", "45 min")]), day(6, [], rest: true)]
        d.endurance = CySportCardModel(category: .endurance, title: "Endurance", done: nil, planned: nil, fraction: nil, secondary: nil, emptyText: "Not in your plan", history: [], historyCaption: "")
        d.strength = CySportCardModel(category: .strength, title: "Strength", done: "2", planned: "4 sessions", fraction: 0.5, secondary: "9,120 kg lifted", emptyText: nil,
                                      history: [4, 4, 3, 4, 4, 4, 3, 2], historyCaption: "Sessions per week, last 8 weeks")
        d.metrics = [mRHR, mHRV, mTime, mVolume]
        d.sessionsToday = 0
        return d
    }

    static func noPlan() -> Home21Data {
        var d = hybrid()
        d.consistency = CyConsistencyModel(fraction: nil, text: "", caption: "Nothing planned", counts: [row("Planned to date", "0")])
        d.mix = CyMixModel(endurance: CyMixLeg(done: "0m", planned: nil, fraction: nil), strength: CyMixLeg(done: "0", planned: nil, fraction: nil))
        d.days = []
        d.endurance = CySportCardModel(category: .endurance, title: "Endurance", done: nil, planned: nil, fraction: nil, secondary: nil, emptyText: "Nothing planned this week", history: [150, 165, 140, 175, 160, 185, 170, 0], historyCaption: "Minutes per week, last 8 weeks")
        d.strength = CySportCardModel(category: .strength, title: "Strength", done: nil, planned: nil, fraction: nil, secondary: nil, emptyText: "Nothing planned this week", history: [3, 3, 2, 3, 3, 3, 2, 0], historyCaption: "Sessions per week, last 8 weeks")
        d.coach = CyCoachBannerModel(sentence: "No sessions are planned this week. Add a session when you are ready.", why: "Your plan has no sessions for this week. Sample text.", hasProposal: false)
        d.trends = []; d.trendsEmpty = "Nothing planned or recorded this week."
        d.sessionsToday = 0
        return d
    }

    static func partialData() -> Home21Data {
        var d = hybrid()
        d.recovery = recoveryPartial
        d.sleep = sleepNone
        d.metrics = [
            CyMetricTile(id: "rhr", icon: "heart", name: "Resting HR", value: nil, unit: "bpm", trend: nil, trendLevel: .neutral, explanation: mRHR.explanation, source: "Apple Health not connected", history: [], historyUnit: "bpm"),
            CyMetricTile(id: "hrv", icon: "waveform.path.ecg", name: "HRV", value: nil, unit: "ms", trend: nil, trendLevel: .neutral, explanation: mHRV.explanation, source: "Apple Health not connected", history: [], historyUnit: "ms"),
            mTime,
            CyMetricTile(id: "power", icon: "bolt", name: "Avg ride power", value: nil, unit: "W", trend: nil, trendLevel: .neutral, explanation: mPower.explanation, source: "No power meter connected", history: [], historyUnit: "W"),
            mVolume,
            metric("hr", "heart.circle", "Avg ride HR", "138", "bpm", "last 3 rides", .neutral, "Average heart rate across recent rides, from your strap.", "Sample · heart-rate strap", [136, 139, 137, 140, 138, 139, 137, 138], "bpm"),
        ]
        d.steps[3].isDone = false
        return d
    }
}
