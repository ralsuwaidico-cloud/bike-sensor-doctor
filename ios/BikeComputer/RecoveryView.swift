import SwiftUI

// Checkpoint E — the Recovery page. One recommendation at the top with the readings it rests on; then one card per
// enabled reading: value, source, time, freshness, what it means against the athlete's own usual range, and the last
// 14 days. No readiness score. Readings older than a day are labelled so; absent readings are described, not drawn.
struct HomeRecoveryView: View {
    @EnvironmentObject private var store: Store
    let recovery: HomeDashboard.Recovery
    var openConnections: () -> Void

    var body: some View {
        let report = store.recoveryReport()
        ScrollView {
            VStack(alignment: .leading, spacing: CyTheme.sp3) {
                if report.metrics.isEmpty {
                    CyEmptyState(systemImage: "heart.text.square", title: recovery.emptyTitle, line: "Cyclift shows sleep, resting heart rate and HRV once Apple Health reads are turned on in Connections. Each reading is shown with its source and time; nothing is scored.", actionTitle: "Open Connections", action: openConnections)
                } else {
                    adviceCard(report.advice)
                    ForEach(report.metrics) { m in metricCard(m) }
                    Text("Cyclift computes no recovery score. Each line names the reading, where Apple Health got it and when. \"Usual range\" is the middle half of your own readings from the last \(RecoveryAnalysis.baselineDays) days, widened slightly, and needs at least \(RecoveryAnalysis.minBaselineRecords) readings. Readings are not medical advice.")
                        .font(CyType.captionSmall).foregroundStyle(CyTheme.ink3).padding(.horizontal, 4)
                }
            }
            .padding(.horizontal, CyTheme.margin).padding(.vertical, CyTheme.sp3).padding(.bottom, CyTheme.dockClearance)
        }
        .background(CyTheme.canvas)
        .navigationTitle("Recovery").navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("homeRecoveryPage")
    }

    private func adviceCard(_ a: RecoveryAdvice) -> some View {
        Card {
            VStack(alignment: .leading, spacing: DS.s) {
                Eyebrow(t: "Today")
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: icon(a.kind)).font(.title3.weight(.semibold)).foregroundStyle(tint(a.kind)).frame(width: 28)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(a.title).font(.headline).accessibilityAddTraits(.isHeader)
                        Text(a.detail).font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                }
                if !a.basis.isEmpty {
                    Divider()
                    Text("Based on").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    ForEach(a.basis, id: \.self) { Text($0).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("recoveryAdvice")
    }

    private func metricCard(_ m: RecoveryMetric) -> some View {
        Card {
            VStack(alignment: .leading, spacing: DS.s) {
                HStack(alignment: .firstTextBaseline) {
                    Eyebrow(t: m.kind.title)
                    Spacer()
                    if m.freshness != .fresh, m.latest != nil { Text(m.freshness.word.capitalized).font(.caption2.weight(.semibold)).foregroundStyle(BC.warn) }
                }
                if let l = m.latest {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(RecoveryAnalysis.valueText(m.kind, l.value)).font(.title2.weight(.bold)).monospacedDigit()
                        if m.flagged { Image(systemName: "exclamationmark.circle.fill").foregroundStyle(BC.warn).font(.subheadline) }
                    }
                    Text(m.sourceLine).font(.caption).foregroundStyle(.secondary)
                    Text(m.explanation).font(.footnote).fixedSize(horizontal: false, vertical: true)
                    let n = m.series.compactMap { $0 }.count
                    if n >= 3 {
                        CyBarChart(values: m.series, labels: m.labels, tint: CyTheme.recovery.tint, soft: CyTheme.recovery.soft, unit: unit(m.kind), valueText: { RecoveryAnalysis.valueText(m.kind, $0) }, height: 72, missingUnit: "day")
                        Text("Last \(RecoveryAnalysis.seriesDays) days · \(n) with a reading").font(.caption2).foregroundStyle(.secondary)
                    } else {
                        Text("\(n) of the last \(RecoveryAnalysis.seriesDays) days have a reading — a chart needs 3.").font(.caption2).foregroundStyle(.secondary)
                    }
                } else {
                    Text(m.explanation).font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("recoveryMetric-\(m.kind.rawValue)")
    }

    private func unit(_ k: HealthSample.Kind) -> String { switch k { case .sleep: return "h"; case .restingHR: return "bpm"; case .hrv: return "ms"; case .weight: return "kg" } }
    private func icon(_ k: RecoveryAdvice.Kind) -> String {
        switch k { case .hold: return "hand.raised.fill"; case .trainAsPlanned: return "checkmark.circle.fill"; case .watch: return "eye.fill"; case .easier: return "tortoise.fill"; case .noData: return "questionmark.circle" }
    }
    private func tint(_ k: RecoveryAdvice.Kind) -> Color {
        switch k { case .hold: return BC.warn; case .trainAsPlanned: return CyTheme.recovery.tint; case .watch, .easier: return BC.warn; case .noData: return .secondary }
    }
}
