import SwiftUI

// Local mock detail sheets for Home v2.1. Sample content only.

struct InfoBlock: View {
    let head: String
    let text: String
    @Environment(\.cyTheme) private var theme
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            CyOverline(text: head)
            Text(text).font(CyFont.callout).foregroundStyle(theme.textPrimary).fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct KeyValueList: View {
    let rows: [CyTrendDetailRow]
    @Environment(\.cyTheme) private var theme
    var body: some View {
        CyCard(padding: CySpace.m) {
            VStack(spacing: CySpace.s) {
                ForEach(rows) { r in
                    HStack(alignment: .firstTextBaseline) {
                        Text(r.label).font(CyFont.callout).foregroundStyle(theme.textSecondary)
                        Spacer(minLength: CySpace.m)
                        Text(r.value).font(CyFont.callout.weight(.semibold)).foregroundStyle(theme.textPrimary).multilineTextAlignment(.trailing)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }
}

/// Consistency → weekly adherence: every day with its sessions and their state; rest days are listed as rest, never as missed.
struct ConsistencySheet: View {
    let model: CyConsistencyModel
    let days: [CyScheduleDay]
    let onClose: () -> Void
    @Environment(\.cyTheme) private var theme
    var body: some View {
        CySheet(title: "Consistency", onClose: onClose) {
            HStack(spacing: CySpace.l) {
                ZStack {
                    CyProgressRingGlyph(fraction: model.fraction, color: theme.ringConsistency, diameter: 72)
                    Text(model.fraction == nil ? "—" : model.text).font(CyFont.metricSmall).foregroundStyle(theme.textPrimary)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.caption).font(CyFont.title).foregroundStyle(theme.textPrimary).fixedSize(horizontal: false, vertical: true)
                    Text("Completed ÷ planned sessions that were due").font(CyFont.footnote).foregroundStyle(theme.textSecondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            .accessibilityElement(children: .combine)
            KeyValueList(rows: model.counts)
            if !days.isEmpty {
                CyCard(padding: CySpace.m) {
                    VStack(alignment: .leading, spacing: CySpace.s) {
                        CyOverline(text: "This week")
                        ForEach(days) { d in
                            HStack(alignment: .center, spacing: CySpace.m) {
                                Text(d.weekday.prefix(3)).font(CyFont.caption).foregroundStyle(d.isToday ? theme.accent : theme.textSecondary).frame(width: 40, alignment: .leading)
                                if d.sessions.isEmpty {
                                    Text(d.isRest ? "Rest day" : "Nothing planned").font(CyFont.footnote).foregroundStyle(theme.textTertiary)
                                } else {
                                    VStack(alignment: .leading, spacing: 4) {
                                        ForEach(d.sessions) { s in
                                            HStack(spacing: CySpace.s) {
                                                CySessionMark(session: s, size: 20)
                                                Text(s.title).font(CyFont.footnote).foregroundStyle(theme.textPrimary)
                                                Spacer(minLength: 0)
                                                Text(s.state.label.capitalized).font(.caption2.weight(.semibold))
                                                    .foregroundStyle(s.state == .missed ? theme.warning : theme.textSecondary)
                                            }
                                        }
                                    }
                                }
                                Spacer(minLength: 0)
                            }
                            .accessibilityElement(children: .combine)
                        }
                    }
                }
            }
            InfoBlock(head: "How it is counted", text: "Sessions that were due up to today. Rest days and sessions still to come are not counted. A rescheduled session counts on its new day.")
        }
    }
}

/// Training Mix → each discipline against its own plan. Two values; no combined score.
struct MixSheet: View {
    let model: CyMixModel
    let endurance: CySportCardModel
    let strength: CySportCardModel
    let onClose: () -> Void
    @Environment(\.cyTheme) private var theme
    var body: some View {
        CySheet(title: "Training Mix", onClose: onClose) {
            HStack(spacing: CySpace.l) {
                CyMixRingGlyph(model: model, diameter: 84)
                VStack(alignment: .leading, spacing: 6) {
                    legend("Outer ring · Endurance", theme.endurance)
                    legend("Inner ring · Strength", theme.strength)
                }
            }
            leg(title: "Endurance", icon: CyCategory.endurance.icon, color: theme.endurance, l: model.endurance, extra: endurance.secondary)
            leg(title: "Strength", icon: CyCategory.strength.icon, color: theme.strength, l: model.strength, extra: strength.secondary)
            InfoBlock(head: "What this shows", text: "How far you are through this week's plan in each discipline. Each ring has its own value.")
            InfoBlock(head: "What it does not show", text: "The two rings are not added together, and matching rings do not mean an ideal balance. This is separate from the load analysis (recent load against your own longer-term average), which stays its own analytics feature.")
        }
    }
    private func legend(_ text: String, _ color: Color) -> some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(text).font(CyFont.footnote).foregroundStyle(theme.textSecondary)
        }
    }
    private func leg(title: String, icon: String, color: Color, l: CyMixLeg, extra: String?) -> some View {
        CyCard(padding: CySpace.m) {
            VStack(alignment: .leading, spacing: CySpace.s) {
                HStack(spacing: 6) {
                    Image(systemName: icon).foregroundStyle(color)
                    Text(title).font(CyFont.headline).foregroundStyle(theme.textPrimary)
                    Spacer(minLength: 0)
                    if let f = l.fraction { Text("\(Int((f * 100).rounded()))%").font(CyFont.value).foregroundStyle(theme.textPrimary) }
                }
                if let planned = l.planned, let f = l.fraction {
                    CyGradientBar(fraction: f, color: color, height: 6)
                    HStack {
                        Text("Completed \(l.done)").font(CyFont.footnote).foregroundStyle(theme.textSecondary)
                        Spacer()
                        Text("Planned \(planned)").font(CyFont.footnote).foregroundStyle(theme.textSecondary)
                    }
                    if let extra { Text(extra).font(.caption2).foregroundStyle(theme.textTertiary) }
                } else {
                    Text("Not in your plan this week. Shown as inactive — it is not a missed target.").font(CyFont.footnote).foregroundStyle(theme.textSecondary).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

struct RecoverySheet: View {
    let model: CyRecoveryIndicatorModel
    let onClose: () -> Void
    @Environment(\.cyTheme) private var theme
    var body: some View {
        CySheet(title: "Recovery", onClose: onClose) {
            HStack(spacing: CySpace.l) {
                CyRecoveryGlyph(model: model, diameter: 72)
                VStack(alignment: .leading, spacing: 2) {
                    Text(word).font(CyFont.title).foregroundStyle(theme.textPrimary).fixedSize(horizontal: false, vertical: true)
                    Text("\(model.sources.filter { $0.value != nil }.count) of \(model.sources.count) readings available").font(CyFont.footnote).foregroundStyle(theme.textSecondary)
                }
            }
            .accessibilityElement(children: .combine)
            CyCard(padding: CySpace.m) {
                VStack(spacing: CySpace.s) {
                    ForEach(model.sources) { s in
                        HStack(alignment: .firstTextBaseline) {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(s.name).font(CyFont.callout).foregroundStyle(theme.textPrimary)
                                Text(s.note).font(.caption2).foregroundStyle(theme.textSecondary)
                            }
                            Spacer(minLength: CySpace.m)
                            Text(s.value ?? "No reading").font(CyFont.callout.weight(.semibold)).foregroundStyle(s.value == nil ? theme.textTertiary : theme.textPrimary)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }
            InfoBlock(head: "Guidance", text: model.guidance)
            InfoBlock(head: "About this indicator", text: "The three arcs show which readings exist today. There is no recovery percentage, and this is not a medical assessment.")
            Text(model.freshness).font(.caption2).foregroundStyle(theme.textTertiary)
        }
    }
    private var word: String {
        switch model.state {
        case .available(let w), .partial(let w), .concern(let w): return w
        case .awaiting: return "Awaiting data"
        }
    }
}

struct SleepSheet: View {
    let model: CySleepModel
    let onClose: () -> Void
    @Environment(\.cyTheme) private var theme
    var body: some View {
        CySheet(title: "Sleep", onClose: onClose) {
            KeyValueList(rows: [
                CyTrendDetailRow(id: "last", label: "Last night", value: model.lastNight.map(CySleepModel.text) ?? "No record"),
                CyTrendDetailRow(id: "avg", label: "7-day average", value: model.average7.map(CySleepModel.text) ?? "—"),
                CyTrendDetailRow(id: "target", label: "Target", value: model.target.map(CySleepModel.text) ?? "Not set"),
            ])
            if let last = model.lastNight, let t = model.target, t > 0 {
                VStack(alignment: .leading, spacing: 4) {
                    CyGradientBar(fraction: Double(last) / Double(t), color: theme.ringRecovery, height: 6)
                    Text("Bar: last night ÷ target").font(.caption2).foregroundStyle(theme.textTertiary)
                }
            }
            CyWeeklyBars(title: "Recent nights", points: model.nights, unit: "h", category: .recovery, emptyText: "No sleep history yet.")
            InfoBlock(head: "About the target", text: "Source: \(model.targetSource). Cyclift does not calculate a sleep need. In the app this would be your own chosen target or a documented source.")
            InfoBlock(head: "Guidance", text: model.guidance)
            Text(model.source).font(.caption2).foregroundStyle(theme.textTertiary)
        }
    }
}

struct DaySheet: View {
    let day: CyScheduleDay
    let onClose: () -> Void
    let onAction: () -> Void
    @Environment(\.cyTheme) private var theme
    var body: some View {
        CySheet(title: "\(day.weekday) \(day.date)", onClose: onClose) {
            if day.sessions.isEmpty {
                CyEmptyStateCard(icon: day.isRest ? "moon" : "calendar", title: day.isRest ? "Rest day" : "Nothing planned",
                                 message: day.isRest ? "A planned rest day. It does not count against consistency." : "No session is planned for this day.")
            } else {
                ForEach(day.sessions) { s in
                    CyWorkoutCard(model: CyWorkoutModel(category: s.category, title: s.title, detail: "\(s.detail) · \(s.state.label)", status: status(s.state)),
                                  actionTitle: s.state == .completed ? "Results" : "Open",
                                  isActionEnabled: true, onAction: onAction, onOpen: onAction)
                }
            }
        }
    }
    private func status(_ s: CySessionState) -> CySessionStatus {
        switch s {
        case .completed: return .done
        case .planned: return day.isToday ? .today : .planned
        case .missed: return .missed
        case .rescheduled: return .skipped
        }
    }
}

/// Endurance / Strength detail — the sparkline and history that left the Home card in v2.1 live here.
struct SportSheet: View {
    let model: CySportCardModel
    let onClose: () -> Void
    @Environment(\.cyTheme) private var theme
    var body: some View {
        CySheet(title: model.title, onClose: onClose) {
            if let empty = model.emptyText {
                CyEmptyStateCard(icon: model.category.icon, title: empty, message: model.planned == nil ? "This discipline is not part of your plan this week." : "Your totals appear here after your first session.")
            } else {
                KeyValueList(rows: [
                    CyTrendDetailRow(id: "done", label: "Completed this week", value: model.done ?? "—"),
                    CyTrendDetailRow(id: "plan", label: "Planned this week", value: model.planned ?? "—"),
                    CyTrendDetailRow(id: "extra", label: "Also", value: model.secondary ?? "—"),
                ])
            }
            CyWeeklyBars(title: model.historyCaption.isEmpty ? "History" : model.historyCaption,
                         points: model.history.enumerated().map { CySeriesPoint(id: $0.offset, label: "W\($0.offset + 1)", value: $0.element) },
                         unit: "", category: model.category, emptyText: "History appears after two weeks of sessions.")
        }
    }
}

struct TrendDaySheet: View {
    let day: CyTrendDay
    let onClose: () -> Void
    @Environment(\.cyTheme) private var theme
    var body: some View {
        CySheet(title: day.full, onClose: onClose) {
            if day.rows.isEmpty {
                CyEmptyStateCard(icon: "calendar", title: "No data", message: "Nothing was recorded or planned for this day.")
            } else {
                KeyValueList(rows: day.rows)
            }
            Text("Only what was recorded is listed. Sample data.").font(.caption2).foregroundStyle(theme.textTertiary)
        }
    }
}

struct MetricSheet: View {
    let tile: CyMetricTile
    let onClose: () -> Void
    @Environment(\.cyTheme) private var theme
    var body: some View {
        CySheet(title: tile.name, onClose: onClose) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(tile.value ?? "No data").font(CyFont.display).foregroundStyle(tile.value == nil ? theme.textTertiary : theme.textPrimary)
                if tile.value != nil { Text(tile.unit).font(CyFont.callout).foregroundStyle(theme.textSecondary) }
            }
            .accessibilityElement(children: .combine)
            if let t = tile.trend, tile.value != nil { Text(t).font(CyFont.footnote).foregroundStyle(theme.textSecondary) }
            CyWeeklyBars(title: "Last 8 weeks", points: tile.history, unit: tile.historyUnit, category: .recovery, emptyText: "No history yet. Nothing is estimated.")
            InfoBlock(head: "What it is", text: tile.explanation)
            Text("Source: \(tile.source)").font(.caption2).foregroundStyle(theme.textTertiary)
        }
    }
}
