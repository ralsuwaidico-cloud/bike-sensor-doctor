import Foundation

// Home v2.3 — the adapter from the athlete's own records to the Home v2.3 input models (HomeV23Models.swift).
// PROVISIONAL design (not yet visually approved); the numbers are not provisional: every value is read from the
// existing plan, training ledger, recovery log and profile — the same sources the previous dashboard used.
// Nothing is estimated or invented:
//  • no recovery percentage or score exists, so Recovery is a status word, "partial" or "awaiting" — never a number;
//  • a sleep target is not stored anywhere in the app, so none is shown and none is offered;
//  • the trend graph has two modes built from records (Activity; Recovery trends). The prototype's third mode
//    ("Training & Recovery": session load against a recovery score) is NOT built: there is no approved recovery score;
//  • a day or a metric without a reading is nil ("No data"), never zero.
// Foundation only, so the Linux harness tests it.

enum HomeV23Builder {
    static let coreReads: [HealthSample.Kind] = [.sleep, .restingHR, .hrv]

    static func initials(_ name: String) -> String {
        let words = name.split(whereSeparator: { $0 == " " }).prefix(2)
        return words.compactMap { $0.first }.map { String($0).uppercased() }.joined()
    }

    // MARK: indicators

    /// The week's planned sessions that are completed ÷ the week's planned sessions — the ledger's own counts.
    static func consistency(total t: TrainingLedger.SportWeek, missed: Int, hasPlan: Bool) -> CyConsistencyModel {
        guard t.planned > 0 else {
            return CyConsistencyModel(fraction: nil, text: "", caption: hasPlan ? "Nothing planned this week" : "No plan yet", counts: [])
        }
        let f = min(1, Double(t.plannedDone) / Double(t.planned))
        var rows = [CyTrendDetailRow(id: "planned", label: "Planned", value: "\(t.planned)"),
                    CyTrendDetailRow(id: "completed", label: "Completed", value: "\(t.plannedDone)"),
                    CyTrendDetailRow(id: "missed", label: "Missed", value: "\(missed)")]
        if t.skipped > 0 { rows.append(CyTrendDetailRow(id: "skipped", label: "Skipped", value: "\(t.skipped)")) }
        if t.extra > 0 { rows.append(CyTrendDetailRow(id: "extra", label: "Extra", value: "\(t.extra)")) }
        return CyConsistencyModel(fraction: f, text: "\(Int((f * 100).rounded()))%", caption: "\(t.plannedDone) of \(t.planned) sessions", counts: rows)
    }

    /// One discipline against its plan. Time is used when every completed session has a duration and the plan has
    /// minutes; otherwise sessions are counted (a session marked done without a duration still counts as done).
    static func leg(_ w: TrainingLedger.SportWeek) -> CyMixLeg {
        guard w.planned > 0 else {
            return CyMixLeg(done: Fmt.duration(minutes: w.minutes), planned: nil, fraction: nil, minutesDone: w.minutes, minutesPlanned: nil)
        }
        let byTime = w.plannedMinutes > 0 && w.unknownDuration == 0
        let f = byTime ? Double(w.minutes) / Double(w.plannedMinutes) : Double(w.plannedDone) / Double(w.planned)
        return CyMixLeg(done: Fmt.duration(minutes: w.minutes), planned: w.plannedMinutes > 0 ? Fmt.duration(minutes: w.plannedMinutes) : "\(w.planned) sessions",
                        fraction: min(1, max(0, f)), minutesDone: w.minutes, minutesPlanned: w.plannedMinutes > 0 ? w.plannedMinutes : nil)
    }

    static func value(_ k: HealthSample.Kind, _ v: Double) -> String {
        switch k {
        case .sleep: return String(format: "%.1f", v)
        case .weight: return String(format: "%.1f", v)
        case .restingHR, .hrv: return "\(Int(v.rounded()))"
        }
    }

    /// Qualitative only. "In your usual range" is said only when all three readings are present, not stale, and each
    /// has a usual range from the athlete's own history (RecoveryAnalysis). Anything less is "partial" or "awaiting".
    static func recovery(metrics: [RecoveryMetric], advice: RecoveryAdvice?) -> CyRecoveryIndicatorModel {
        let core = coreReads.map { k in metrics.first { $0.kind == k } }
        let sources: [CyRecoverySource] = zip(coreReads, core).map { k, m in
            guard let m, let l = m.latest else { return CyRecoverySource(id: k.rawValue, name: k.title, value: nil, note: m == nil ? "not connected" : "no reading yet") }
            let note: String
            switch m.standing {
            case .typical: note = "in your usual range"
            case .lower: note = "below your usual range"
            case .higher: note = "above your usual range"
            case .noBaseline: note = "no usual range yet"
            }
            return CyRecoverySource(id: k.rawValue, name: k.title, value: "\(value(k, l.value)) \(k.unit)", note: m.freshness == .fresh ? note : "\(note) · \(m.freshness.word)")
        }
        let usable = core.compactMap { $0 }.filter { $0.latest != nil && $0.freshness != .stale && $0.freshness != .missing }
        let state: CyRecoveryState
        if core.compactMap({ $0?.latest }).isEmpty { state = .awaiting }
        else if usable.count < coreReads.count { state = .partial(word: "\(usable.count) of \(coreReads.count) readings") }
        else if usable.contains(where: { $0.standing == .noBaseline }) { state = .partial(word: "No usual range yet") }
        else if usable.contains(where: { $0.flagged }) { state = .qualitative(word: "Outside your usual range") }
        else { state = .qualitative(word: "In your usual range") }
        let newest = core.compactMap { $0?.latest?.date }.max()
        let f = DateFormatter(); f.dateFormat = "EEE d MMM, HH:mm"
        return CyRecoveryIndicatorModel(state: state, sources: sources,
                                        guidance: (advice.map { $0.kind == .noData ? "" : $0.title }) ?? "",
                                        freshness: newest.map { "Latest reading \(f.string(from: $0)) · Apple Health" } ?? "No readings yet")
    }

    // MARK: schedule

    static func category(_ k: WorkoutKind) -> CyCategory { k == .strength ? .strength : .endurance }

    /// Monday–Sunday of the current week from the plan. Empty when there is no plan at all (Home says so in one line).
    static func days(plan: [Workout], status: (Workout) -> WorkoutStatus, routine: (Workout) -> WorkoutTemplate?, now: Date, calendar cal: Calendar) -> [CyScheduleDay] {
        guard plan.contains(where: { HomeToday.isTraining($0) }) else { return [] }
        let today = cal.startOfDay(for: now), monday = TrainingLedger.monday(of: now, calendar: cal)
        let long = DateFormatter(); long.dateFormat = "EEEE"
        let dm = DateFormatter(); dm.dateFormat = "d MMM"
        return (0..<7).map { i in
            let d = cal.date(byAdding: .day, value: i, to: monday)!
            let all = plan.filter { cal.isDate($0.date, inSameDayAs: d) }
            let train = all.filter { HomeToday.isTraining($0) && !$0.skipped }.sorted { $0.sequence < $1.sequence }
            let sessions = train.map { w -> CyDaySession in
                let st = status(w)
                let state: CySessionState = st.isCompleted ? .completed : (d < today ? .missed : .planned)
                return CyDaySession(id: w.id.uuidString, category: category(w.kind), state: state, title: HomeText.title(w, routine: routine(w)),
                                    detail: w.minutes > 0 ? Fmt.duration(minutes: w.minutes) : "")
            }
            let weekday = long.string(from: d)
            // a rest day is a day the plan itself marks as rest; a day with nothing in the plan is "nothing planned"
            let rest = sessions.isEmpty && all.contains { !HomeToday.isTraining($0) }
            return CyScheduleDay(id: i, letter: String(weekday.prefix(1)), weekday: weekday, date: dm.string(from: d), sessions: sessions,
                                 isToday: cal.isDate(d, inSameDayAs: now), isRest: rest)
        }
    }

    // MARK: sport cards

    static func enduranceCard(_ r: TrainingLedger.SportWeek, km: Double) -> CySportCardModel {
        if r.planned == 0 && r.completed == 0 {
            return CySportCardModel(category: .endurance, title: "Endurance", done: nil, planned: nil, fraction: nil, secondary: nil, emptyText: "Nothing planned this week", history: [], historyCaption: "")
        }
        let leg = HomeV23Builder.leg(r)
        let done = r.minutes > 0 ? Fmt.duration(minutes: r.minutes) : "\(r.completed) \(r.completed == 1 ? "ride" : "rides")"
        let secondary = km > 0 ? String(format: "%.1f km", km) : (r.planned > 0 ? "\(r.plannedDone) of \(r.planned) rides" : nil)
        return CySportCardModel(category: .endurance, title: "Endurance", done: done, planned: r.plannedMinutes > 0 ? Fmt.duration(minutes: r.plannedMinutes) : nil,
                                fraction: leg.fraction, secondary: secondary, emptyText: nil, history: [], historyCaption: "")
    }
    static func strengthCard(_ l: TrainingLedger.SportWeek) -> CySportCardModel {
        if l.planned == 0 && l.completed == 0 {
            return CySportCardModel(category: .strength, title: "Strength", done: nil, planned: nil, fraction: nil, secondary: nil, emptyText: "Nothing planned this week", history: [], historyCaption: "")
        }
        let planned: String? = l.planned > 0 ? "\(l.planned) \(l.planned == 1 ? "session" : "sessions")" : nil
        let done = l.planned > 0 ? "\(l.plannedDone)" : "\(l.completed)"
        return CySportCardModel(category: .strength, title: "Strength", done: done, planned: planned,
                                fraction: l.planned > 0 ? min(1, Double(l.plannedDone) / Double(l.planned)) : nil,
                                secondary: l.minutes > 0 ? "\(Fmt.duration(minutes: l.minutes)) logged" : nil, emptyText: nil, history: [], historyCaption: "")
    }

    // MARK: sleep

    /// Last night = a sleep reading less than 24 hours old. The 7-day average needs at least three nights. No target.
    static func sleep(metric m: RecoveryMetric?, log: RecoveryLog, now: Date, calendar cal: Calendar) -> CySleepModel {
        let last: Int? = (m?.latest).flatMap { m?.freshness == .fresh ? Int(($0.value * 60).rounded()) : nil }
        let from = cal.date(byAdding: .day, value: -7, to: now) ?? now
        let week = log.entries(.sleep).filter { $0.date > from && $0.date <= now }.map(\.value)
        let avg: Int? = week.count >= 3 ? Int((week.reduce(0, +) / Double(week.count) * 60).rounded()) : nil
        let nights = (m?.series ?? []).enumerated().map { i, v in CySeriesPoint(id: i, label: m?.labels[i] ?? "", value: v) }
        return CySleepModel(lastNight: last, average7: avg, target: nil, targetSource: "", nights: nights,
                            guidance: m?.explanation ?? "", source: m?.sourceLine ?? "Apple Health sleep is not connected", targetLabel: "Target", canSetTarget: false)
    }

    // MARK: trends

    struct DayTotals: Equatable { var endurance = 0; var strength = 0; var planned = 0 }

    /// Minutes per calendar day from the ledger's own records: recorded rides, logged strength sessions, and planned
    /// sessions marked done with a typed duration. `planned` = the plan's minutes of that day (not skipped).
    static func totals(ledger: TrainingLedger, from: Date, days: Int, calendar cal: Calendar) -> [DayTotals] {
        (0..<days).map { i in
            let d = cal.date(byAdding: .day, value: i, to: from)!, e = cal.date(byAdding: .day, value: 1, to: d)!
            var t = DayTotals()
            t.endurance = ledger.rides.filter { $0.start >= d && $0.start < e }.reduce(0) { $0 + $1.durationS } / 60
            t.strength = ledger.logs.filter { $0.date >= d && $0.date < e }.reduce(0) { $0 + $1.minutes }
            for p in ledger.plan where p.date >= d && p.date < e && HomeToday.isTraining(p) && !p.skipped {
                t.planned += p.minutes
                if p.completion == .marked, let mm = p.manualMinutes, mm > 0 {
                    if p.kind == .strength { if ledger.log(for: p) == nil { t.strength += mm } }
                    else if ledger.ride(for: p) == nil { t.endurance += mm }
                }
            }
            return t
        }
    }

    static func rolling7(_ a: [Int], lead: [Int]) -> [Int] {
        let padded = Array(lead.suffix(6)) + a
        let off = padded.count - a.count
        return a.indices.map { i in padded[max(0, i + off - 6)...(i + off)].reduce(0, +) }
    }

    /// Two ranges (7 days, 4 weeks), each ending today. Days before the athlete's first record or plan are nil.
    static func graph(ledger: TrainingLedger, log: RecoveryLog, mode: TrainingMode, firstDay: Date?, now: Date, calendar cal: Calendar) -> [CyGraphRange] {
        guard let firstDay else { return [] }
        let today = cal.startOfDay(for: now)
        let start34 = cal.date(byAdding: .day, value: -33, to: today)!
        let all = totals(ledger: ledger, from: start34, days: 34, calendar: cal)          // 6 lead-in days + 28
        let long = DateFormatter(); long.dateFormat = "EEEE d MMM"
        let wd = DateFormatter(); wd.dateFormat = "EEE"
        let dm = DateFormatter(); dm.dateFormat = "d MMM"
        func dates(_ n: Int) -> [CyGraphDate] {
            (0..<n).map { i in
                let d = cal.date(byAdding: .day, value: i - (n - 1), to: today)!
                let label: String? = n <= 7 ? wd.string(from: d) : (i % 7 == 0 ? dm.string(from: d) : nil)
                return CyGraphDate(id: i, axisLabel: label, short: String(wd.string(from: d).prefix(1)), full: long.string(from: d))
            }
        }
        func known(_ n: Int, _ v: [Int]) -> [Double?] {
            (0..<n).map { i in
                let d = cal.date(byAdding: .day, value: i - (n - 1), to: today)!
                return d < cal.startOfDay(for: firstDay) ? nil : Double(v[i])
            }
        }
        func health(_ k: HealthSample.Kind, _ n: Int) -> [Double?] {
            let xs = log.entries(k)
            return (0..<n).map { i in
                let key = RecoveryLog.dayKey(cal.date(byAdding: .day, value: i - (n - 1), to: today)!, calendar: cal)
                return xs.last { RecoveryLog.dayKey($0.date, calendar: cal) == key }?.value
            }
        }
        func modes(_ n: Int, rolling: Bool) -> [CyGraphMode] {
            let window = Array(all.suffix(n)), lead = Array(all.dropLast(n))
            func series(_ pick: (DayTotals) -> Int) -> [Double?] {
                let v = window.map(pick)
                return known(n, rolling ? rolling7(v, lead: lead.map(pick)) : v)
            }
            let unit = rolling ? "min/7d" : "min", src = rolling ? " · 7-day rolling total" : ""
            var activity: [CyGraphSeries] = []
            if mode != .strength { activity.append(CyGraphSeries(id: "endurance", name: "Endurance", unit: unit, source: "Recorded rides" + src, provenance: .existingEngine, color: .endurance, axis: .leading, values: series { $0.endurance })) }
            if mode != .cycling { activity.append(CyGraphSeries(id: "strength", name: "Strength", unit: unit, source: "Logged sessions" + src, provenance: .existingEngine, color: .strength, axis: .leading, values: series { $0.strength })) }
            activity.append(CyGraphSeries(id: "planned", name: "Planned", unit: unit, source: "Your plan" + src, provenance: .existingEngine, color: .neutral, axis: .leading, dashed: true, values: series { $0.planned }))
            let trends: [CyGraphSeries] = [
                CyGraphSeries(id: "rhr", name: "Resting HR", unit: "bpm", source: "Apple Health", provenance: .existingEngine, color: .recovery, axis: .leading, values: health(.restingHR, n)),
                CyGraphSeries(id: "hrv", name: "HRV", unit: "ms", source: "Apple Health", provenance: .existingEngine, color: .consistency, axis: .leading, values: health(.hrv, n)),
                CyGraphSeries(id: "sleep", name: "Sleep", unit: "h", source: "Apple Health", provenance: .existingEngine, color: .load, axis: .leading, values: health(.sleep, n))]
            return [CyGraphMode(id: "activity", title: "Activity", singleSelection: false, series: activity, note: rolling ? "Each point is a 7-day total (/7d)." : nil),
                    CyGraphMode(id: "trends", title: "Recovery trends", singleSelection: true, series: trends, note: nil)]
        }
        return [CyGraphRange(id: "7d", title: "7 days", dates: dates(7), modes: modes(7, rolling: false)),
                CyGraphRange(id: "4w", title: "4 weeks", dates: dates(28), modes: modes(28, rolling: true))]
    }

    /// The calendar day a graph column stands for (columns end today).
    static func date(ofColumn id: Int, count: Int, now: Date, calendar cal: Calendar) -> Date {
        cal.date(byAdding: .day, value: id - (count - 1), to: cal.startOfDay(for: now)) ?? now
    }

    // MARK: key metrics

    static func metric(_ k: HealthSample.Kind, _ m: RecoveryMetric?) -> CyHomeMetric {
        let icon: String, name: String
        switch k {
        case .restingHR: icon = "heart.fill"; name = "Resting HR"
        case .hrv: icon = "waveform.path.ecg"; name = "HRV"
        case .sleep: icon = "moon.fill"; name = "Sleep"
        case .weight: icon = "scalemass.fill"; name = "Weight"
        }
        let history = (m?.series ?? []).enumerated().map { i, v in CySeriesPoint(id: i, label: m?.labels[i] ?? "", value: v) }
        var direction: CyDirection = .none
        var baseline: String? = nil
        if let m, m.latest != nil {
            switch m.standing { case .typical: direction = .flat; case .lower: direction = .down; case .higher: direction = .up; case .noBaseline: direction = .none }
            if let b = m.baseline { baseline = "usual \(value(k, b.low))–\(value(k, b.high))" }
            else if m.freshness != .fresh { baseline = m.freshness.word }
        }
        return CyHomeMetric(id: k.rawValue, icon: icon, name: name, value: (m?.latest).map { value(k, $0.value) }, unit: k.unit, trend: nil, trendLevel: .neutral,
                            explanation: m?.explanation ?? "No reading yet.", source: m?.sourceLine ?? "Apple Health is not connected for this reading.",
                            history: history, historyUnit: k.unit, baseline: baseline, direction: direction)
    }
}

extension Store {
    /// Everything Home v2.3 shows, from this athlete's records.
    func homeV23(now: Date = Date(), hrConnected: Bool = false, calendar cal: Calendar = .current) -> Home21Data {
        let mode = profile.trainingMode
        let led = ledger
        let monday = TrainingLedger.monday(of: now, calendar: cal), nextMonday = cal.date(byAdding: .day, value: 7, to: monday)!
        let today = cal.startOfDay(for: now)
        let week = homeWeek(now: now)
        let hasPlan = plan.contains { HomeToday.isTraining($0) }
        let weekPlan = plan.filter { $0.date >= monday && $0.date < nextMonday && HomeToday.isTraining($0) && !$0.skipped }
        let missed = weekPlan.filter { cal.startOfDay(for: $0.date) < today && led.status($0) == .planned }.count
        let riding = led.riding(weekOf: monday), lifting = led.lifting(weekOf: monday)
        let km = Double(led.rides.filter { $0.start >= monday && $0.start < nextMonday }.reduce(0) { $0 + $1.distanceM }) / 1000
        let report = recoveryReport(now: now)
        let none = CyMixLeg(done: Fmt.duration(minutes: 0), planned: nil, fraction: nil, minutesDone: 0, minutesPlanned: nil)
        let first = [planEffectiveStart, led.rides.map(\.start).min(), led.logs.map(\.date).min()].compactMap { $0 }.min()
        var metrics = [HomeV23Builder.metric(.restingHR, report.metrics.first { $0.kind == .restingHR }),
                       HomeV23Builder.metric(.hrv, report.metrics.first { $0.kind == .hrv }),
                       HomeV23Builder.metric(.sleep, report.metrics.first { $0.kind == .sleep })]
        if let w = report.metrics.first(where: { $0.kind == .weight }), w.latest != nil { metrics.append(HomeV23Builder.metric(.weight, w)) }
        if mode != .strength {
            let known = profile.ftpHow != .assumed && profile.ftpW > 0      // the starting assumption is never shown as an FTP
            metrics.append(CyHomeMetric(id: "ftp", icon: "bolt.fill", name: "FTP", value: known ? "\(profile.ftpW)" : nil, unit: "W", trend: nil, trendLevel: .neutral,
                                        explanation: "Functional threshold power sets your riding zones.", source: profile.ftpLabel, history: [], historyUnit: "W",
                                        baseline: known ? profile.ftpLabel : nil, direction: .none))
        }
        // Key Metrics (owner, 27 Nov 2026): once the athlete has chosen their own Home metrics, those are shown, in their
        // order. Without a saved choice the rows above are exactly what Home showed before.
        if let saved = settings.homeMetrics { let chosen = KeyMetricsPrefs.clean(saved); metrics = keyMetricsHomeRows(chosen, defaults: metrics, now: now, calendar: cal) }
        return Home21Data(
            dateLine: HomeDashboardModel.dateLine(now),
            name: profile.name.trimmingCharacters(in: .whitespaces),
            athleteType: profile.isProfileOnly ? ProfileOnlyText.identity(profile) : (mode == .hybrid ? "Hybrid" : mode.title),
            initials: HomeV23Builder.initials(profile.name),
            consistency: HomeV23Builder.consistency(total: week.total, missed: missed, hasPlan: hasPlan),
            mix: CyMixModel(endurance: mode == .strength && riding.planned == 0 && riding.completed == 0 ? none : HomeV23Builder.leg(riding),
                            strength: mode == .cycling && lifting.planned == 0 && lifting.completed == 0 ? none : HomeV23Builder.leg(lifting)),
            recovery: HomeV23Builder.recovery(metrics: report.metrics, advice: report.advice),
            steps: homeSetupItems(hrConnected: hrConnected, now: now, calendar: cal).map { CySetupStep(id: $0.id.rawValue, title: $0.title, detail: $0.detail, isDone: $0.done, isRequired: $0.required) },
            days: HomeV23Builder.days(plan: plan, status: { led.status($0) }, routine: { [weak self] in self?.routine(for: $0) }, now: now, calendar: cal),
            endurance: mode == .strength && riding.planned == 0 && riding.completed == 0 ? nil : HomeV23Builder.enduranceCard(riding, km: km),
            strength: mode == .cycling && lifting.planned == 0 && lifting.completed == 0 ? nil : HomeV23Builder.strengthCard(lifting),
            sleep: HomeV23Builder.sleep(metric: report.metrics.first { $0.kind == .sleep }, log: recoveryLog, now: now, calendar: cal),
            coachEmpty: "Nothing new right now",
            trendsEmpty: first == nil ? "Your training time appears here after your first session." : nil,
            graph: HomeV23Builder.graph(ledger: led, log: recoveryLog, mode: mode, firstDay: first, now: now, calendar: cal),
            metrics: metrics)
    }
}
