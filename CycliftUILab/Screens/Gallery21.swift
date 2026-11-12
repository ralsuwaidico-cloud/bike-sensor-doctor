import SwiftUI

/// Gallery page for the Home v2.2 components in their states.
struct Gallery21: View {
    @Environment(\.cyTheme) private var theme
    @State private var steps = Mock21.newAthlete().steps
    @State private var note = ""
    private let hybrid = Mock21.hybrid(), fresh = Mock21.newAthlete(), cyc = Mock21.cyclingOnly(), lift = Mock21.strengthOnly(), partial = Mock21.partialData(), empty = Mock21.noPlan()

    var body: some View {
        VStack(alignment: .leading, spacing: CySpace.xl) {
            if !note.isEmpty { Text(note).font(CyFont.caption).foregroundStyle(theme.accent) }
            Group {
            Example(label: "INDICATORS · HYBRID") { row(hybrid) }
            Example(label: "INDICATORS · CYCLING ONLY (STRENGTH RING INACTIVE)") { row(cyc) }
            Example(label: "INDICATORS · STRENGTH ONLY (ENDURANCE RING INACTIVE)") { row(lift) }
            Example(label: "INDICATORS · PARTIAL RECOVERY DATA") { row(partial) }
            Example(label: "INDICATORS · NEW ATHLETE / NOTHING PLANNED") { VStack(spacing: CySpace.l) { row(fresh); row(empty) } }
            Example(label: "RECOVERY · SAMPLE % / STATUS WORD / PARTIAL / AWAITING") {
                HStack(spacing: CySpace.l) {
                    CyRecoveryGlyph(model: Mock21.recoveryFull)
                    CyRecoveryGlyph(model: Mock21.recoveryQualitative)
                    CyRecoveryGlyph(model: Mock21.recoveryPartial)
                    CyRecoveryGlyph(model: Mock21.recoveryNone)
                }
            }
            Example(label: "TRAINING MIX · 66:34 / 100:0 / 0:100 / NO COMPLETED TRAINING") {
                HStack(spacing: CySpace.l) {
                    CyMixRingGlyph(model: hybrid.mix)
                    CyMixRingGlyph(model: cyc.mix)
                    CyMixRingGlyph(model: lift.mix)
                    CyMixRingGlyph(model: fresh.mix)
                }
            }
            Example(label: "INDICATORS · LOADING") {
                CyIndicatorRow(consistency: nil, mix: nil, recovery: nil, isLoading: true, onConsistency: {}, onMix: {}, onRecovery: {})
            }
            }
            Group {
            Example(label: "SCHEDULE · HYBRID (COMPLETED, MISSED, PLANNED, TWO SESSIONS, REST)") { CyCompactSchedule(days: hybrid.days) { note = "\($0.weekday) opened" } }
            Example(label: "SCHEDULE · RESCHEDULED / MISSED / EMPTY / LOADING") {
                VStack(spacing: CySpace.m) {
                    CyCompactSchedule(days: cyc.days) { _ in }
                    CyCompactSchedule(days: lift.days) { _ in }
                    CyCompactSchedule(days: []) { _ in }
                    CyCompactSchedule(days: [], isLoading: true) { _ in }
                }
            }
            Example(label: "SPORT CARDS · NORMAL / NOT PLANNED / NO DATA / LOADING") {
                VStack(spacing: CySpace.s) {
                    HStack(alignment: .top, spacing: CySpace.s) { CyCompactSportCard(model: hybrid.endurance) { note = "Endurance opened" }; CyCompactSportCard(model: hybrid.strength) { note = "Strength opened" } }.fixedSize(horizontal: false, vertical: true)
                    HStack(alignment: .top, spacing: CySpace.s) { CyCompactSportCard(model: cyc.strength) {}; CyCompactSportCard(model: fresh.endurance) {} }.fixedSize(horizontal: false, vertical: true)
                    HStack(alignment: .top, spacing: CySpace.s) { CyCompactSportCard(model: nil) {}; CyCompactSportCard(model: nil) {} }.fixedSize(horizontal: false, vertical: true)
                }
            }
            Example(label: "SLEEP BAR · NORMAL / NO DATA / LOADING") {
                VStack(spacing: CySpace.s) {
                    CySleepBar(model: Mock21.sleepFull) { note = "Sleep opened" }
                    CySleepBar(model: Mock21.sleepNone) {}
                    CySleepBar(model: nil) {}
                }
            }
            }
            Group {
            Example(label: "COACH · PENDING / POSTPONED / ACCEPTED / DECLINED / NO PROPOSAL / EMPTY / LOADING") {
                VStack(spacing: CySpace.s) {
                    CyCoachBanner(model: hybrid.coach, onWhy: { note = "Why opened" }, onReview: { note = "Review opened" }, onNotNow: { note = "Postponed" })
                    CyCoachBanner(model: hybrid.coach, decision: .postponed, onWhy: {}, onReview: {}, onNotNow: {})
                    CyCoachBanner(model: hybrid.coach, decision: .accepted, onWhy: {}, onReview: {}, onNotNow: {})
                    CyCoachBanner(model: hybrid.coach, decision: .declined, onWhy: {}, onReview: {}, onNotNow: {})
                    CyCoachBanner(model: cyc.coach, onWhy: {}, onReview: {}, onNotNow: {})
                    CyCoachBanner(model: CyCoachBannerModel(sentence: "", why: "", hasProposal: false), emptyText: fresh.coachEmpty, onWhy: {}, onReview: {}, onNotNow: {})
                    CyCoachBanner(model: nil, onWhy: {}, onReview: {}, onNotNow: {})
                }
            }
            Example(label: "GETTING STARTED · REQUIRED STEP OPEN (TAP TO COMPLETE) / COMPLETE") {
                VStack(spacing: CySpace.m) {
                    CySetupBanner(steps: steps) { s in if let i = steps.firstIndex(where: { $0.id == s.id }) { steps[i].isDone.toggle() } }
                    CySetupBanner(steps: hybrid.steps) { _ in }
                }
            }
            }
            Group {
            Example(label: "GRAPH · TRAINING & RECOVERY (TWO LABELLED SCALES)") { CyTrendsGraph(ranges: hybrid.graph, initialSelection: 2, onInfo: { note = "Info opened" }, onDay: { d, _ in note = "\(d.full) opened" }) }
            Example(label: "GRAPH · TRAINING ACTIVITY") { CyTrendsGraph(ranges: hybrid.graph, initialMode: "activity", onInfo: {}, onDay: { _, _ in }) }
            Example(label: "GRAPH · RECOVERY TRENDS · 4 WEEKS (GAPS = MISSING DAYS)") { CyTrendsGraph(ranges: hybrid.graph, initialMode: "trends", initialRange: "4w", onInfo: {}, onDay: { _, _ in }) }
            Example(label: "GRAPH · EMPTY / LOADING") {
                VStack(spacing: CySpace.l) {
                    CyTrendsGraph(ranges: [], emptyText: fresh.trendsEmpty ?? "Nothing recorded yet.", onInfo: {}, onDay: { _, _ in })
                    CyTrendsGraph(ranges: [], isLoading: true, onInfo: {}, onDay: { _, _ in })
                }
            }
            Example(label: "KEY METRICS · ROWS / MISSING / LOADING") {
                VStack(spacing: CySpace.l) {
                    CyMetricGrid(tiles: hybrid.metrics) { note = "\($0.name) opened" }
                    CyMetricGrid(tiles: partial.metrics) { _ in }
                    CyMetricGrid(tiles: [], isLoading: true) { _ in }
                }
            }
            Example(label: "LARGE ACCESSIBILITY TEXT") {
                VStack(alignment: .leading, spacing: CySpace.l) {
                    row(hybrid)
                    CyCompactSchedule(days: hybrid.days) { _ in }
                    CySleepBar(model: Mock21.sleepFull) {}
                    CyCoachBanner(model: hybrid.coach, onWhy: {}, onReview: {}, onNotNow: {})
                }
                .dynamicTypeSize(.accessibility2)
            }
            }
        }
    }

    private func row(_ d: Home21Data) -> some View {
        CyIndicatorRow(consistency: (d.consistency.fraction, d.consistency.text, d.consistency.caption), mix: d.mix, recovery: d.recovery,
                       onConsistency: { note = "Consistency opened" }, onMix: { note = "Training Mix opened" }, onRecovery: { note = "Recovery opened" })
    }
}
