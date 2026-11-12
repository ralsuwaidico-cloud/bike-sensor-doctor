import SwiftUI

// SYNTHETIC SAMPLE SERIES for the Home v2.2 trend graph. Generated once with a fixed seed and written out as literals;
// nothing is measured. nil = no measurement that day (drawn as a gap). Future days of the current week are nil.
// "Recovery %" exists ONLY as UI Lab sample data — Cyclift has no approved numerical recovery model.

struct GraphOptions {
    var endurance = true, strength = true
    var recoveryScore = true          // false = no numeric sample (qualitative / unavailable scenarios)
    var restingHR = true, hrv = true, sleep = true
}

enum MockGraph {
    /// 7 days = the last seven days of the 28-day sample (Thu 5 – Wed 11 Nov), so both ranges show the same data.
    static let dates7: [CyGraphDate] = dates28.suffix(7).enumerated().map { i, d in
        CyGraphDate(id: i, axisLabel: String(d.full.prefix(3)), short: d.short, full: d.full)
    }
    static let dates28: [CyGraphDate] = [
        CyGraphDate(id: 0, axisLabel: "15 Oct", short: "T", full: "Thursday 15 Oct"),
        CyGraphDate(id: 1, axisLabel: nil, short: "F", full: "Friday 16 Oct"),
        CyGraphDate(id: 2, axisLabel: nil, short: "S", full: "Saturday 17 Oct"),
        CyGraphDate(id: 3, axisLabel: nil, short: "S", full: "Sunday 18 Oct"),
        CyGraphDate(id: 4, axisLabel: nil, short: "M", full: "Monday 19 Oct"),
        CyGraphDate(id: 5, axisLabel: nil, short: "T", full: "Tuesday 20 Oct"),
        CyGraphDate(id: 6, axisLabel: nil, short: "W", full: "Wednesday 21 Oct"),
        CyGraphDate(id: 7, axisLabel: "22 Oct", short: "T", full: "Thursday 22 Oct"),
        CyGraphDate(id: 8, axisLabel: nil, short: "F", full: "Friday 23 Oct"),
        CyGraphDate(id: 9, axisLabel: nil, short: "S", full: "Saturday 24 Oct"),
        CyGraphDate(id: 10, axisLabel: nil, short: "S", full: "Sunday 25 Oct"),
        CyGraphDate(id: 11, axisLabel: nil, short: "M", full: "Monday 26 Oct"),
        CyGraphDate(id: 12, axisLabel: nil, short: "T", full: "Tuesday 27 Oct"),
        CyGraphDate(id: 13, axisLabel: nil, short: "W", full: "Wednesday 28 Oct"),
        CyGraphDate(id: 14, axisLabel: "29 Oct", short: "T", full: "Thursday 29 Oct"),
        CyGraphDate(id: 15, axisLabel: nil, short: "F", full: "Friday 30 Oct"),
        CyGraphDate(id: 16, axisLabel: nil, short: "S", full: "Saturday 31 Oct"),
        CyGraphDate(id: 17, axisLabel: nil, short: "S", full: "Sunday 1 Nov"),
        CyGraphDate(id: 18, axisLabel: nil, short: "M", full: "Monday 2 Nov"),
        CyGraphDate(id: 19, axisLabel: nil, short: "T", full: "Tuesday 3 Nov"),
        CyGraphDate(id: 20, axisLabel: nil, short: "W", full: "Wednesday 4 Nov"),
        CyGraphDate(id: 21, axisLabel: "5 Nov", short: "T", full: "Thursday 5 Nov"),
        CyGraphDate(id: 22, axisLabel: nil, short: "F", full: "Friday 6 Nov"),
        CyGraphDate(id: 23, axisLabel: nil, short: "S", full: "Saturday 7 Nov"),
        CyGraphDate(id: 24, axisLabel: nil, short: "S", full: "Sunday 8 Nov"),
        CyGraphDate(id: 25, axisLabel: nil, short: "M", full: "Monday 9 Nov"),
        CyGraphDate(id: 26, axisLabel: nil, short: "T", full: "Tuesday 10 Nov"),
        CyGraphDate(id: 27, axisLabel: nil, short: "W", full: "Wednesday 11 Nov")]

    // 28 days, one value per day (Thu 15 Oct – Wed 11 Nov). Sat 7 Nov has no HRV reading, so no sample recovery value.
    static let e28: [Double?] = [0, 0, 99, 0, 0, 40, 32, 0, 0, 0, 0, 0, 45, 32, 0, 0, 90, 0, 0, 45, 32, 0, 0, 99, 0, 0, 45, 32]
    static let s28: [Double?] = [0, 40, 0, 0, 40, 0, 35, 0, 40, 0, 0, 40, 0, 35, 0, 0, 0, 0, 40, 0, 35, 0, 40, 0, 0, 40, 0, 0]
    static let p28: [Double?] = [0, 40, 90, 0, 40, 45, 67, 0, 40, 90, 0, 40, 45, 67, 0, 40, 90, 0, 40, 45, 67, 0, 40, 90, 0, 85, 45, 67]
    static let load28: [Double?] = [0, 240, 594, 0, 240, 200, 370, 0, 240, 0, 0, 240, 225, 370, 0, 0, 540, 0, 240, 225, 370, 0, 240, 594, 0, 240, 225, 96]
    static let rec28: [Double?] = [75, 75, 75, 75, 79, 64, nil, 58, 58, 66, 75, 68, 70, nil, 61, 68, 66, 72, 61, 61, 72, 64, 58, nil, 64, 72, 61, 68]
    static let rhr28: [Double?] = [55, 53, 54, 52, 55, 53, nil, 51, 55, 53, 51, 53, 55, 51, 53, 53, 52, 54, 53, 52, 55, 52, 53, 53, 53, 53, 54, 52]
    static let hrv28: [Double?] = [69, 61, 60, 60, 55, 55, nil, 61, 66, 61, 58, 69, 61, nil, nil, 58, 55, 64, 61, 63, nil, 58, 66, nil, 64, 62, 58, 64]
    static let slp28: [Double?] = [7.6, 6.8, 6.5, 6.5, 7.4, 7.9, nil, 7.0, 7.2, 7.1, 7.6, 6.5, 7.9, 6.5, 6.5, 6.2, 7.6, 7.4, 7.1, nil, 6.5, 6.2, 6.8, 7.0, 6.5, 7.4, 6.8, 7.2]

    static func last7(_ a: [Double?]) -> [Double?] { Array(a.suffix(7)) }
    /// 4-week view of load and minutes: 7-DAY ROLLING TOTAL (documented prototype formula — the sum of the day and the
    /// six days before it). Daily values with rest days at zero make an unreadable sawtooth over 28 days.
    /// The six days before the window reuse the sample's second week as lead-in.
    static func rolling7(_ a: [Double?]) -> [Double?] {
        let v = a.map { $0 ?? 0 }
        let padded = Array(v[7..<13]) + v
        return (0..<v.count).map { i in padded[i...(i + 6)].reduce(0, +) }
    }

    static func none(_ n: Int) -> [Double?] { Array(repeating: nil, count: n) }

    static func modes(_ o: GraphOptions, rolling: Bool, e: [Double?], s: [Double?], p: [Double?], load: [Double?], rec: [Double?], rhr: [Double?], hrv: [Double?], slp: [Double?]) -> [CyGraphMode] {
        let n = e.count
        let sfx = rolling ? " (7-day)" : ""
        let src = rolling ? " · 7-day rolling total" : ""
        var a: [CyGraphSeries] = [
            CyGraphSeries(id: "load", name: "Training load" + sfx, unit: "RPE×min", source: "Sample · session effort × minutes" + src, provenance: rolling ? .needsCalculation : .existingEngine,
                          color: .load, axis: .leading, values: load)]
        a.append(CyGraphSeries(id: "recovery", name: "Recovery", unit: "%", source: "Sample only · no approved model", provenance: .needsValidation,
                               color: .recovery, axis: .trailing, isSampleScore: true, fixedDomain: 0...100, values: o.recoveryScore ? rec : none(n)))
        var b: [CyGraphSeries] = []
        if o.endurance { b.append(CyGraphSeries(id: "endurance", name: "Endurance" + sfx, unit: "min", source: "Sample · recorded rides" + src, provenance: rolling ? .needsCalculation : .existingEngine, color: .endurance, axis: .leading, values: e)) }
        if o.strength { b.append(CyGraphSeries(id: "strength", name: "Strength" + sfx, unit: "min", source: "Sample · logged sessions" + src, provenance: rolling ? .needsCalculation : .existingEngine, color: .strength, axis: .leading, values: s)) }
        b.append(CyGraphSeries(id: "planned", name: "Planned" + sfx, unit: "min", source: "Sample · plan" + src, provenance: .needsMapping, color: .neutral, axis: .leading, dashed: true, values: p))
        let c: [CyGraphSeries] = [
            CyGraphSeries(id: "rhr", name: "Resting HR", unit: "bpm", source: "Sample · Apple Health", provenance: .existingEngine, color: .recovery, axis: .leading, values: o.restingHR ? rhr : none(n)),
            CyGraphSeries(id: "hrv", name: "HRV", unit: "ms", source: "Sample · Apple Health", provenance: .existingEngine, color: .consistency, axis: .leading, values: o.hrv ? hrv : none(n)),
            CyGraphSeries(id: "sleep", name: "Sleep", unit: "h", source: "Sample · Apple Health", provenance: .existingEngine, color: .load, axis: .leading, values: o.sleep ? slp : none(n))]
        let roll = rolling ? " Load and minutes are 7-day rolling totals in this view." : ""
        return [
            CyGraphMode(id: "recovery", title: "Training & Recovery", singleSelection: false, series: a,
                        note: (o.recoveryScore ? "Recovery % is sample data. Cyclift has no validated recovery score; the app would show a status word instead." : "No recovery score: the app shows a status word, not a number.") + roll),
            CyGraphMode(id: "activity", title: "Activity", singleSelection: false, series: b, note: rolling ? "Each point is the total of the last 7 days." : nil),
            CyGraphMode(id: "trends", title: "Recovery trends", singleSelection: true, series: c, note: "One metric at a time — the units differ."),
        ]
    }

    static func ranges(_ o: GraphOptions = GraphOptions()) -> [CyGraphRange] {
        [CyGraphRange(id: "7d", title: "7 days", dates: dates7,
                      modes: modes(o, rolling: false, e: last7(e28), s: last7(s28), p: last7(p28), load: last7(load28), rec: last7(rec28), rhr: last7(rhr28), hrv: last7(hrv28), slp: last7(slp28))),
         CyGraphRange(id: "4w", title: "4 weeks", dates: dates28,
                      modes: modes(o, rolling: true, e: rolling7(e28), s: rolling7(s28), p: rolling7(p28), load: rolling7(load28), rec: rec28, rhr: rhr28, hrv: hrv28, slp: slp28))]
    }
}
