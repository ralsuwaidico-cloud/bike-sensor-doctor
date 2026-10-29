import Foundation

// MARK: - Home Option B (coord/specs/HOME_B_SPEC.md v2.1): what Home shows, as pure data.
//
// HomeView only lays this out; the tab-bar centre button reads the same model (one source for "what do I do now").
// Nothing here changes a coaching calculation, a health rule or stored data: it reads the plan, the ledger
// (WorkoutState.swift), the health readiness (CoachSafety.swift) and the coach outputs that already exist
// (AdaptationEngine / HybridCoach / FTP / insights). The only writes are the rider's own actions in `Store.reschedule`
// (move a session to a free day, with Undo) and `Store.setRideMinutes` (a typed duration for a ride marked done).

/// A health result that pauses all training (Home's TODAY card becomes the hold card; Train now opens the hold sheet).
enum HomeHold: String, Equatable {
    case stop, supervised, ill
    var title: String {
        switch self {
        case .stop: return "See a doctor before training"
        case .supervised: return "Train with your doctor's team"
        case .ill: return "Rest while you are ill"
        }
    }
    var detail: String {
        switch self {
        case .stop: return "Your health check answers mean a doctor should see you first. No sessions are planned until you record a clearance."
        case .supervised: return "A doctor said you should exercise only under medical supervision, so Cyclift plans no sessions."
        case .ill: return "You said you are ill or recovering. No sessions are planned until you answer the health check again."
        }
    }
    var button: String { self == .ill ? "I feel well again" : "Review health check" }
}

/// A health result that caps intensity (compact line above the TODAY card; the card shows the capped intensity).
enum HomeCaution: Equatable {
    case pending(questions: Int), clearance
    var title: String {
        switch self {
        case .pending(let n): return "Health check needed — answer \(n) questions"
        case .clearance: return "Clearance needed for hard training"
        }
    }
    var detail: String {
        switch self {
        case .pending: return "Until then: easy rides, moderate lifts."
        case .clearance: return "Until you record it: easy rides, light lifts."
        }
    }
}

/// The state of one session as Home names it.
enum HomeStatus: Equatable {
    case planned, inProgress, done, marked, imported, skipped, missed
    /// Chip text; nil = no chip (planned).
    var chip: String? {
        switch self {
        case .planned: return nil
        case .inProgress: return "In progress"
        case .done: return "Done"
        case .marked: return "Done · no details"
        case .imported: return "Imported"
        case .skipped: return "Skipped"
        case .missed: return "Missed"
        }
    }
}

/// Every action Home's buttons (and the centre button) can take. RootView performs them, so the card and the tab bar
/// always reach the same destination.
enum HomeAction: Equatable, Identifiable {
    /// StrengthWorkoutScreen (the logger) for a planned strength session.
    case startStrength(UUID)
    /// The Ride tab; recording starts only when the rider taps Start ride there (N4).
    case openRideScreen
    /// StrengthWorkoutScreen of the session in progress (N11); nil = an unplanned session → the session screen itself.
    case resumeStrength(UUID?)
    /// The Ride tab while the recorder runs.
    case openLiveRide
    case rideResults(UUID)
    case strengthResults(UUID)
    /// A session marked done without details: strength → the detailed log, ride → a typed duration.
    case addDetails(UUID)
    /// The free-day picker (skipped, missed or any open session).
    case reschedule(UUID)
    /// Missed session → today (when today is free).
    case moveToToday(UUID)
    /// WorkoutDetail of a session that has no logger (mobility, other).
    case openDetails(UUID)
    case recoveryGuidance
    case reviewHealth
    case createPlan
    /// Quick strength log (first-time "Log a lift").
    case quickLog
    /// The hold sheet ("What this means" + Review health check).
    case holdInfo

    var id: String {
        switch self {
        case .startStrength(let u): return "start-\(u)"
        case .openRideScreen: return "ride"
        case .resumeStrength(let u): return "resume-\(u?.uuidString ?? "free")"
        case .openLiveRide: return "live"
        case .rideResults(let u): return "rideResults-\(u)"
        case .strengthResults(let u): return "strengthResults-\(u)"
        case .addDetails(let u): return "details-\(u)"
        case .reschedule(let u): return "move-\(u)"
        case .moveToToday(let u): return "today-\(u)"
        case .openDetails(let u): return "open-\(u)"
        case .recoveryGuidance: return "recovery"
        case .reviewHealth: return "health"
        case .createPlan: return "createPlan"
        case .quickLog: return "quickLog"
        case .holdInfo: return "hold"
        }
    }

    /// Button text. `elapsed` = seconds of the running ride ("Open ride · 18:04").
    func label(isRide: Bool = false, elapsed: Int? = nil) -> String {
        switch self {
        case .startStrength: return "Start workout"
        case .openRideScreen: return "Start ride"
        case .resumeStrength: return "Resume workout"
        case .openLiveRide: return elapsed.map { "Open ride · " + HomeText.clock($0) } ?? "Open ride"
        case .rideResults, .strengthResults: return "View results"
        case .addDetails: return isRide ? "Add duration" : "Add details"
        case .reschedule: return "Move to another day"
        case .moveToToday: return "Move to today"
        case .openDetails: return "Open session"
        case .recoveryGuidance: return "Recovery guidance"
        case .reviewHealth: return "Review health check"
        case .createPlan: return "Create my plan"
        case .quickLog: return "Log a lift"
        case .holdInfo: return "What this means"
        }
    }
    /// VoiceOver hint: what opens.
    var hint: String {
        switch self {
        case .startStrength: return "Opens the strength logger"
        case .openRideScreen: return "Opens the Ride screen; recording starts there when you tap Start ride"
        case .resumeStrength: return "Opens the strength session in progress"
        case .openLiveRide: return "Opens the ride that is recording"
        case .rideResults: return "Opens the ride's results"
        case .strengthResults: return "Opens the logged session"
        case .addDetails: return "Adds what you did to the session you marked done"
        case .reschedule: return "Lists the free days left this week"
        case .moveToToday: return "Moves the session to today"
        case .openDetails: return "Opens the session"
        case .recoveryGuidance: return "Opens recovery guidance for a rest day"
        case .reviewHealth: return "Opens the health check"
        case .createPlan: return "Opens the plan set-up"
        case .quickLog: return "Opens the quick strength log"
        case .holdInfo: return "Explains the health restriction"
        }
    }
    /// The primary button is the prominent (turquoise) one except for review-type actions.
    var prominent: Bool {
        switch self {
        case .startStrength, .openRideScreen, .resumeStrength, .openLiveRide, .createPlan, .moveToToday: return true
        default: return false
        }
    }
}

/// How hard a session is, in plain words (display only; spec "plain intensity mapping", QA #24).
enum HomeIntensity {
    /// Ride zone → words: Z1 Very easy, Z2 Easy, Z3 Moderate, Z4 Hard, Z5+ Very hard.
    static func ride(zone z: Int) -> String {
        switch z {
        case ...1: return "Very easy"
        case 2: return "Easy"
        case 3: return "Moderate"
        case 4: return "Hard"
        default: return "Very hard"
        }
    }
    /// Strength by prescribed RPE: ≤ 6 Light, 7 Moderate, ≥ 8 Hard.
    static func strength(rpe: Int) -> String { rpe <= 6 ? "Light" : rpe == 7 ? "Moderate" : "Hard" }

    /// The prescribed RPE of a strength session: the planner's highest target when it built the session, else the
    /// default "moderate (RPE 6–7)" every other strength text uses (7) — capped by the health readiness.
    static func strengthRPE(_ w: Workout, readiness: CoachReadiness) -> Int {
        let target = w.rationale?.exercises.compactMap { $0.targetRPE }.max() ?? 7
        return min(target, readiness.maxStrengthRPE)
    }
    /// "40 min · Moderate", "60 min · Easy · Zone 2", "30 min · Mobility".
    static func subtitle(_ w: Workout, readiness: CoachReadiness) -> String {
        var parts: [String] = []
        if w.minutes > 0 { parts.append(Fmt.duration(minutes: w.minutes)) }
        if w.kind.isRide {
            let z = min(w.kind.zone, readiness.maxRideZone)
            if z > 0 { parts.append(ride(zone: z)); parts.append("Zone \(z)") }     // a ride without a zone shows no zone (never "Zone 0")
        } else if w.kind == .strength {
            parts.append(strength(rpe: strengthRPE(w, readiness: readiness)))
        } else if w.kind == .mobility { parts.append("Easy") }
        return parts.joined(separator: " · ")
    }
}

enum HomeText {
    static func clock(_ s: Int) -> String { let h = s / 3600, m = (s % 3600) / 60, sec = s % 60; return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec) : String(format: "%d:%02d", m, sec) }
    static func weekday(_ d: Date) -> String { let f = DateFormatter(); f.dateFormat = "EEE"; return f.string(from: d) }
    static func longDate(_ d: Date) -> String { let f = DateFormatter(); f.dateFormat = "EEEE, d MMMM"; return f.string(from: d) }
    /// Workout title as Home shows it: "Full-body strength"-style titles come from the plan (routine name when assigned).
    static func title(_ w: Workout, routine: WorkoutTemplate?) -> String { w.displayTitle(routine: routine) }
}

/// One session of today (or the missed one).
struct HomeSession: Equatable, Identifiable {
    var workout: Workout
    var title: String
    var subtitle: String
    var status: HomeStatus
    var action: HomeAction
    /// "Eased by coach — see change" / "Kept easy until your health check" (N6, QA #13).
    var adjustment: String?
    /// Skip, Move and Swap are offered (N10: never while the session is in progress, nor once it is done).
    var canChange: Bool
    var id: UUID { workout.id }
    var isRide: Bool { workout.kind.isRide }
}

/// The THIS WEEK card (P0-4 / N1): the same counts as Plan and Progress (WeekTotals over the ledger).
struct HomeWeek: Equatable {
    var total: TrainingLedger.SportWeek
    var riding: TrainingLedger.SportWeek?
    var lifting: TrainingLedger.SportWeek?
    /// "Thu · Strength · Full body 40 min"; nil = nothing else planned this week.
    var upNext: String?
    /// "2 of 5 sessions done · +1 extra · 1 skipped"
    var line: String { WeekTotals.sessions(total, singular: "session", plural: "sessions") }
    /// Hybrid only: "Rides 1 of 3 · Lifts 0 of 2".
    var split: String? {
        guard let r = riding, let l = lifting else { return nil }
        return "Rides \(r.plannedDone) of \(r.planned) · Lifts \(l.plannedDone) of \(l.planned)"
    }
    /// The rider's weekly targets (sessions per week from the profile and availability — the same numbers the coach's
    /// frequency sentence uses); nil when unknown. Shown so the card separates target, scheduled and done.
    var ridesTarget: Int? = nil
    var liftsTarget: Int? = nil
    /// "Weekly target: 3 rides · 2 lifts"
    var targetLine: String? {
        let parts = [ridesTarget.flatMap { $0 > 0 ? "\($0) \($0 == 1 ? "ride" : "rides")" : nil },
                     liftsTarget.flatMap { $0 > 0 ? "\($0) \($0 == 1 ? "lift" : "lifts")" : nil }].compactMap { $0 }
        return parts.isEmpty ? nil : "Weekly target: " + parts.joined(separator: " · ")
    }
    /// Segments of the bar: one per planned session (max 7; nil above that = a plain bar).
    var segments: Int? { total.planned > 0 && total.planned <= 7 ? total.planned : nil }

    static func make(_ ledger: TrainingLedger, mode: TrainingMode, plan: [Workout], routine: (Workout) -> WorkoutTemplate?, now: Date, calendar cal: Calendar = .current) -> HomeWeek {
        let t = WeekTotals(ledger, weekOf: now, calendar: cal)
        let parts: [TrainingLedger.SportWeek]
        switch mode {
        case .cycling: parts = [t.riding]
        case .strength: parts = [t.lifting]
        case .hybrid: parts = [t.riding, t.lifting]
        }
        let tomorrow = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: now))!
        let end = cal.date(byAdding: .day, value: 7, to: t.monday)!
        let next = plan.filter { $0.date >= tomorrow && $0.date < end && ($0.kind.isRide || $0.kind == .strength || $0.kind == .mobility || $0.kind == .other) && !$0.skipped && !ledger.status($0).isCompleted }
            .min { ($0.date, $0.sequence) < ($1.date, $1.sequence) }
        let upNext = next.map { "\(HomeText.weekday($0.date)) · \(HomeText.title($0, routine: routine($0)))" + ($0.minutes > 0 ? " \(Fmt.duration(minutes: $0.minutes))" : "") }
        return HomeWeek(total: WeekTotals.total(parts), riding: mode == .hybrid ? t.riding : nil, lifting: mode == .hybrid ? t.lifting : nil, upNext: upNext)
    }
}

/// The COACH slot (P0-3, N2, N5, N6, N13): the first existing engine output in a fixed priority order, or nothing.
struct HomeCoachItem: Equatable {
    enum Source: Equatable {
        /// AdaptationEngine proposal awaiting approval (id) — Accept / Not now.
        case adaptiveProposal(String)
        /// HybridCoach proposal (id) — Accept.
        case hybridProposal(String)
        /// An applied change to the next session (workout id) — See change (AdjustmentsView).
        case adjustment(UUID)
        /// FTP suggestion — Review.
        case ftp
        /// HybridCoach weekly review "revise my days" — Open Plan.
        case revise
        /// Strength insight for the next strength session (workout id) — Details.
        case insight(UUID)
        /// Low confidence: rate the last unrated session (ride or strength id).
        case rate(CheckInTargetID)
    }
    enum CheckInTargetID: Equatable { case ride(UUID), strength(UUID) }
    var source: Source
    var title: String
    /// The engine's own reason, first sentence only (N2: no invented counts).
    var evidence: String?
    var actionLabel: String?

    /// First sentence of an engine text (up to the first ". "), at most ~140 characters.
    static func firstSentence(_ s: String) -> String {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if let r = t.range(of: ". ") { return String(t[..<r.lowerBound]) + "." }
        return t
    }

    struct Input {
        var adaptiveProposals: [AdaptiveProposal] = []
        var hybridProposals: [CoachProposal] = []
        var adjustments: [PlanAdjustment] = []
        /// Today's session ids (their change is on the workout card, N6) and the next open session after today.
        var todayIds: Set<UUID> = []
        var nextSessionId: UUID? = nil
        var nextSessionTitle: String? = nil
        var ftp: FTPSuggestion? = nil
        var currentFTP: Int = 0
        var offerRevise: Bool = false
        var reviseText: String? = nil
        var insight: WorkoutInsight? = nil
        var insightWorkout: UUID? = nil
        var feedbackRequest: String? = nil
        var lowConfidence: Bool = false
        /// The most recent completed session (14 days) without a rating; nil = none (N13: no card on day 1).
        var unrated: CheckInTargetID? = nil
    }

    static func select(_ i: Input) -> HomeCoachItem? {
        if let p = i.adaptiveProposals.first {
            return HomeCoachItem(source: .adaptiveProposal(p.id), title: "Coach suggests: \(p.text)", evidence: firstSentence(p.why), actionLabel: p.adjustments.isEmpty ? "Details" : "Accept")
        }
        if let p = i.hybridProposals.first {
            return HomeCoachItem(source: .hybridProposal(p.id), title: "Coach suggests: \(p.text)", evidence: firstSentence(p.why), actionLabel: "Accept")
        }
        if let next = i.nextSessionId, !i.todayIds.contains(next), let a = i.adjustments.first(where: { $0.workoutId == next }) {
            let t = i.nextSessionTitle.map { "\($0): \(a.summary)" } ?? a.summary
            return HomeCoachItem(source: .adjustment(next), title: t, evidence: firstSentence(a.why), actionLabel: "See change")
        }
        if let f = i.ftp {
            return HomeCoachItem(source: .ftp, title: "Update FTP to \(f.watts) W?", evidence: "From your best 20 minutes (\(f.best20) W) on a recent ride; your FTP is \(i.currentFTP) W now.", actionLabel: "Review")
        }
        if i.offerRevise {
            return HomeCoachItem(source: .revise, title: "Revise your training days?", evidence: i.reviseText.map(firstSentence), actionLabel: "Revise my training days")
        }
        if let ins = i.insight, let w = i.insightWorkout, ins.kind != .insufficient {
            return HomeCoachItem(source: .insight(w), title: ins.text, evidence: "Evidence: \(ins.evidence)", actionLabel: "Details")
        }
        if i.lowConfidence, let req = i.feedbackRequest, let u = i.unrated {
            return HomeCoachItem(source: .rate(u), title: "Rate your sessions after training so the coach can adjust.", evidence: firstSentence(req), actionLabel: "Rate last session")
        }
        return nil
    }
}

/// Everything the TODAY card needs.
struct HomeToday: Equatable {
    enum Layout: Equatable {
        /// No plan yet. `liftFirst`: strength-only riders see "Log a lift" first.
        case first(liftFirst: Bool)
        case hold(HomeHold)
        /// Nothing to do today (the rest / recovery day of the plan, if any).
        case rest(Workout?)
        case single(HomeSession)
        case multi([HomeSession])
        /// A strength session started without a planned session.
        case freeSession
    }
    var layout: Layout
    var caution: HomeCaution?
    /// The most recent missed session (last 7 days), only when health allows training (N12).
    var missed: HomeSession?
    var moreMissed: Int = 0
    var showCoach: Bool
    var showWeek: Bool

    /// The card's one primary action (multi: the first session that is not done; else the first one's).
    var primary: HomeAction {
        switch layout {
        case .first: return .createPlan
        case .hold: return .reviewHealth
        case .rest: return missed.map { .moveToToday($0.id) } ?? .recoveryGuidance
        case .single(let s): return s.action
        case .multi(let ss): return (ss.first { $0.status == .inProgress } ?? ss.first { $0.status == .planned } ?? ss.first)?.action ?? .recoveryGuidance
        case .freeSession: return .resumeStrength(nil)
        }
    }

    /// The tab-bar centre button (P2-20): the same destination as the card whenever the card has one obvious next step;
    /// the optional-session sheet otherwise (rest, done, a ride and a lift both open).
    enum Centre: Equatable { case hold, perform(HomeAction), sheet }
    var centre: Centre {
        switch layout {
        case .hold: return .hold
        case .freeSession: return .perform(.resumeStrength(nil))
        case .single(let s):
            switch s.status { case .planned, .inProgress: return .perform(s.action); default: return .sheet }
        case .multi(let ss):
            if let p = ss.first(where: { $0.status == .inProgress }) { return .perform(p.action) }
            let open = ss.filter { $0.status == .planned }
            if open.count == 1 { return .perform(open[0].action) }
            return .sheet
        case .first, .rest: return .sheet
        }
    }
}

extension HomeToday {
    struct Input {
        var plan: [Workout]
        var ledger: TrainingLedger
        var readiness: CoachReadiness
        var supervisedOnly: Bool = false
        var questions: Int = HealthScreen.questions.count
        var mode: TrainingMode
        var recorderActive: Bool = false
        var activeSession: StrengthSession? = nil
        var hasHistory: Bool
        var routine: (Workout) -> WorkoutTemplate? = { _ in nil }
        var now: Date = Date()
        var calendar: Calendar = .current
    }

    static func isTraining(_ w: Workout) -> Bool { w.kind != .rest && w.kind != .recoveryDay }

    static func session(_ w: Workout, _ i: Input, firstOpenRide: UUID?) -> HomeSession {
        let st = i.ledger.status(w)
        let cal = i.calendar
        var status: HomeStatus
        var action: HomeAction
        switch st {
        case .started, .inProgress:
            status = .inProgress; action = .resumeStrength(w.id)
        case .completedLogged, .importedHealth:
            status = st == .importedHealth ? .imported : .done
            if w.kind.isRide, let r = i.ledger.ride(for: w) { action = .rideResults(r.id) }
            else if let l = i.ledger.log(for: w) { action = .strengthResults(l.id) }
            else { action = .openDetails(w.id) }
        case .completedManual:
            status = .marked; action = (w.kind.isRide || w.kind == .strength) ? .addDetails(w.id) : .openDetails(w.id)
        case .skipped:
            status = .skipped; action = .reschedule(w.id)
        case .planned:
            if cal.startOfDay(for: w.date) < cal.startOfDay(for: i.now) { status = .missed; action = .reschedule(w.id) }
            else if w.kind.isRide && i.recorderActive && w.id == firstOpenRide { status = .inProgress; action = .openLiveRide }
            else { status = .planned; action = w.kind == .strength ? .startStrength(w.id) : w.kind.isRide ? .openRideScreen : .openDetails(w.id) }
        }
        var adj: String? = nil
        if status == .planned || status == .inProgress || status == .missed {
            if w.safetyOriginal != nil { adj = "Kept easy until your health check" }
            else if w.coachAdjusted { adj = "Eased by coach — see change" }
        }
        let canChange = status == .planned || status == .missed || status == .skipped
        return HomeSession(workout: w, title: HomeText.title(w, routine: i.routine(w)), subtitle: HomeIntensity.subtitle(w, readiness: i.readiness),
                           status: status, action: action, adjustment: adj, canChange: canChange)
    }

    static func make(_ i: Input) -> HomeToday {
        let cal = i.calendar
        let today = cal.startOfDay(for: i.now)
        // health holds win over everything (P0-1)
        if !i.readiness.trainingAllowed {
            let hold: HomeHold = i.readiness.screen == .paused ? .ill : (i.supervisedOnly ? .supervised : .stop)
            return HomeToday(layout: .hold(hold), caution: nil, missed: nil, showCoach: false, showWeek: true)
        }
        let caution: HomeCaution? = i.readiness.screen == .notAnswered ? .pending(questions: i.questions) : i.readiness.screen == .needsClearance ? .clearance : nil
        // first-time: no training planned this week or next and no history
        let monday = TrainingLedger.monday(of: i.now, calendar: cal)
        let twoWeeks = cal.date(byAdding: .day, value: 14, to: monday)!
        let anyPlanned = i.plan.contains { isTraining($0) && $0.date >= monday && $0.date < twoWeeks }
        if !anyPlanned && !i.hasHistory && i.activeSession == nil {
            return HomeToday(layout: .first(liftFirst: i.mode == .strength), caution: caution, missed: nil, showCoach: false, showWeek: false)
        }
        let items = i.plan.filter { cal.isDate($0.date, inSameDayAs: i.now) && isTraining($0) }.sorted { $0.sequence < $1.sequence }
        let firstOpenRide = items.first { $0.kind.isRide && !$0.skipped && !i.ledger.status($0).isCompleted }?.id
        // missed: planned, not completed, not skipped, in the last 7 days (N12: the most recent one, "+n more in Plan")
        let weekAgo = cal.date(byAdding: .day, value: -7, to: today)!
        let missedAll = i.plan.filter { isTraining($0) && $0.date >= weekAgo && cal.startOfDay(for: $0.date) < today && !$0.skipped && i.ledger.status($0) == .planned }
            .sorted { ($0.date, $0.sequence) > ($1.date, $1.sequence) }
        let missed = missedAll.first.map { session($0, i, firstOpenRide: nil) }
        let more = max(0, missedAll.count - 1)
        let layout: Layout
        if let a = i.activeSession, !items.contains(where: { $0.id == a.workoutId }) { layout = .freeSession }
        else if items.isEmpty { layout = .rest(i.plan.first { cal.isDate($0.date, inSameDayAs: i.now) }) }
        else if items.count == 1 { layout = .single(session(items[0], i, firstOpenRide: firstOpenRide)) }
        else { layout = .multi(items.map { session($0, i, firstOpenRide: firstOpenRide) }) }
        let inProgress: Bool
        switch layout {
        case .single(let s): inProgress = s.status == .inProgress
        case .multi(let ss): inProgress = ss.contains { $0.status == .inProgress }
        case .freeSession: inProgress = true
        default: inProgress = false
        }
        return HomeToday(layout: layout, caution: caution, missed: missed, moreMissed: more, showCoach: !inProgress, showWeek: true)
    }
}

// MARK: - Store: Home inputs and the rider's own actions
extension Store {
    func homeToday(now: Date = Date(), recorderActive: Bool = false) -> HomeToday {
        HomeToday.make(.init(plan: plan, ledger: ledger, readiness: profile.readiness, supervisedOnly: profile.healthScreen?.supervisedOnly ?? false,
                             mode: profile.trainingMode, recorderActive: recorderActive, activeSession: activeSession,
                             hasHistory: !rides.filter { !$0.demo }.isEmpty || !strength.isEmpty, routine: { [weak self] w in self?.routine(for: w) }, now: now))
    }

    func homeWeek(now: Date = Date()) -> HomeWeek {
        var w = HomeWeek.make(ledger, mode: profile.trainingMode, plan: plan, routine: { [weak self] w in self?.routine(for: w) }, now: now)
        let a = HybridCoach.assess(profile: profile, plan: plan, rides: rides, strength: strength, availability: effectiveAvailability, now: now)
        w.ridesTarget = a.cycling?.sessionsTarget
        w.liftsTarget = a.strength?.sessionsTarget
        return w
    }

    /// The coach slot from the engine outputs that already exist (no new coaching).
    func homeCoach(now: Date = Date()) -> HomeCoachItem? {
        let cal = Calendar.current
        let today = cal.startOfDay(for: now)
        let l = ledger
        let todayIds = Set(plan.filter { cal.isDate($0.date, inSameDayAs: now) }.map { $0.id })
        let tomorrow = cal.date(byAdding: .day, value: 1, to: today)!
        let next = plan.filter { $0.date >= tomorrow && HomeToday.isTraining($0) && !$0.skipped && !l.status($0).isCompleted }.min { $0.date < $1.date }
        var i = HomeCoachItem.Input()
        i.adaptiveProposals = adaptiveProposals
        i.adjustments = activeAdaptations
        i.todayIds = todayIds
        i.nextSessionId = next?.id
        i.nextSessionTitle = next.map { "\(HomeText.weekday($0.date)) \(HomeText.title($0, routine: routine(for: $0)).lowercased())" }
        i.ftp = ftpSuggestion
        i.currentFTP = profile.ftpW
        if profile.trainingMode != .cycling {
            let a = HybridCoach.assess(profile: profile, plan: plan, rides: rides, strength: strength, availability: effectiveAvailability, now: now)
            i.hybridProposals = a.proposals
            // owner 29 Oct: a weekly-progress finding ("0 done and 1 still to come, 2 short of your target") is not a
            // recommendation — it is not shown in the coach slot (the week card shows done / scheduled / target); the
            // finding itself is unchanged (HybridCoach); the same numbers stay visible on the week card
            if let r = HybridCoach.weeklyReview(profile: profile, plan: plan, rides: rides, strength: strength, now: now), r.offerRevise { i.offerRevise = true; i.reviseText = r.suggestion }
            if let w = plan.filter({ $0.kind == .strength && !$0.done && !$0.skipped && $0.date >= today }).min(by: { $0.date < $1.date }), !w.plannerBuilt {
                let ins = insight(for: w, entries: plannedEntries(for: w), now: now)
                if !ignoredInsights.contains(ins.id) { i.insight = ins; i.insightWorkout = w.id }
            }
        }
        i.feedbackRequest = lastAdaptation?.feedbackRequest
        i.lowConfidence = lastAdaptation?.confidence == .low
        i.unrated = latestUnrated(now: now)
        return HomeCoachItem.select(i)
    }

    /// The most recent completed session of the last 14 days without a rating (check-in or session RPE).
    func latestUnrated(now: Date = Date()) -> HomeCoachItem.CheckInTargetID? {
        let since = now.addingTimeInterval(-14 * 86_400)
        let r = rides.filter { !$0.demo && $0.start >= since && $0.start <= now && $0.checkIn == nil }.max { $0.start < $1.start }
        let s = strength.filter { !$0.awaitingReview && !$0.inProgress && $0.date >= since && $0.date <= now && $0.checkIn == nil && $0.rpe == nil }.max { $0.date < $1.date }
        switch (r, s) {
        case let (r?, s?): return r.start > s.date ? .ride(r.id) : .strength(s.id)
        case let (r?, nil): return .ride(r.id)
        case let (nil, s?): return .strength(s.id)
        default: return nil
        }
    }

    /// Days a session may move to (QA #12, spec "Move to another day"): today and the later days of the current week with
    /// no open training session. Each with what is already there, and a warning when it stacks the same sport.
    struct MoveTarget: Equatable, Identifiable {
        var date: Date
        var note: String
        var warning: String?
        var id: Date { date }
    }
    func moveTargets(for id: UUID, now: Date = Date()) -> [MoveTarget] {
        guard let w = plan.first(where: { $0.id == id }) else { return [] }
        let cal = Calendar.current
        let today = cal.startOfDay(for: now)
        let end = cal.date(byAdding: .day, value: 7, to: TrainingLedger.monday(of: now))!
        let l = ledger
        var out: [MoveTarget] = []
        var d = today
        while d < end {
            defer { d = cal.date(byAdding: .day, value: 1, to: d)! }
            if cal.isDate(d, inSameDayAs: w.date) { continue }
            let there = plan.filter { cal.isDate($0.date, inSameDayAs: d) && HomeToday.isTraining($0) && $0.id != id && !$0.skipped }
            let isToday = cal.isDate(d, inSameDayAs: today)
            if !isToday && there.contains(where: { !l.status($0).isCompleted }) { continue }        /* free days only (today always offered) */
            let same = there.contains { ($0.kind.isRide && w.kind.isRide) || ($0.kind == .strength && w.kind == .strength) }
            let note = there.isEmpty ? "Free" : there.map { "\($0.displayTitle) \(Fmt.duration(minutes: $0.minutes))" }.joined(separator: " + ")
            let prev = cal.date(byAdding: .day, value: -1, to: d)!, nextDay = cal.date(byAdding: .day, value: 1, to: d)!
            let hardNeighbour = w.kind.zone >= 4 && plan.contains { $0.id != id && $0.kind.zone >= 4 && !$0.skipped && (cal.isDate($0.date, inSameDayAs: prev) || cal.isDate($0.date, inSameDayAs: nextDay)) }
            let warning: String? = same ? "Already has a \(w.kind.isRide ? "ride" : "strength session") — two on one day" : hardNeighbour ? "Next to another hard ride" : nil
            out.append(MoveTarget(date: d, note: note, warning: warning))
        }
        return out
    }

    /// Moves a session (also a past, missed one) to today or a later day of this week. A hand edit; the session keeps its
    /// time of day. Undo restores it exactly (snackbar). Refused for a completed session or a day outside this week.
    @discardableResult
    func reschedule(_ id: UUID, to day: Date, now: Date = Date()) -> Bool {
        guard let i = plan.firstIndex(where: { $0.id == id }) else { return false }
        let cal = Calendar.current
        let before = plan[i]
        let d0 = cal.startOfDay(for: day), today = cal.startOfDay(for: now)
        let end = cal.date(byAdding: .day, value: 7, to: TrainingLedger.monday(of: now))!
        guard d0 >= today, d0 < end, !ledger.status(before).isCompleted, HomeToday.isTraining(before) else { return false }
        let t = cal.dateComponents([.hour, .minute, .second], from: before.date)
        var x = before
        x.date = cal.date(bySettingHour: t.hour ?? 7, minute: t.minute ?? 0, second: t.second ?? 0, of: d0) ?? d0
        x.skipped = false
        x.markRiderEdited()
        plan[i] = x
        plan.sort { $0.date < $1.date }
        // Undo uses the trash's "plan as it was" record (no log or session is deleted by a move)
        let item = TrashItem(deletedAt: now, label: "Moved \(before.displayTitle)", planBefore: [before])
        trash.append(item)
        let f = DateFormatter(); f.dateFormat = "EEEE"
        undoToast = UndoToast(id: item.id, text: "\(before.displayTitle) moved to \(cal.isDate(d0, inSameDayAs: today) ? "today" : f.string(from: d0))")
        return true
    }

    /// Skip or unskip a session from Home's More menu: a hand edit with Undo (spec "Skip has Undo"). Refused for a completed
    /// session. Uses the same "plan as it was" trash record as Move, so Undo restores the session exactly.
    @discardableResult
    func setSkipped(_ id: UUID, _ skipped: Bool, now: Date = Date()) -> Bool {
        guard let i = plan.firstIndex(where: { $0.id == id }), plan[i].skipped != skipped, !ledger.status(plan[i]).isCompleted else { return false }
        let before = plan[i]
        var x = before
        x.skipped = skipped
        x.markRiderEdited(before: before)
        plan[i] = x
        let item = TrashItem(deletedAt: now, label: "\(skipped ? "Skipped" : "Unskipped") \(before.displayTitle)", planBefore: [before])
        trash.append(item)
        undoToast = UndoToast(id: item.id, text: "\(before.displayTitle) \(skipped ? "skipped" : "back in the plan")")
        return true
    }

    /// A typed duration for a ride marked done without one ("Add duration", QA #23). The rider's own figure; nothing else changes.
    @discardableResult
    func setManualMinutes(_ id: UUID, minutes: Int) -> Bool {
        guard minutes > 0, let i = plan.firstIndex(where: { $0.id == id }), plan[i].completion == .marked else { return false }
        plan[i].manualMinutes = minutes
        return true
    }
}
