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
                CyMixRingGlyph(model: model, diameter: 92)
                VStack(alignment: .leading, spacing: 6) {
                    legend("Outer ring · Endurance", theme.endurance)
                    legend("Inner ring · Strength", theme.strength)
                    Text("Centre · endurance : strength").font(CyFont.footnote).foregroundStyle(theme.textSecondary)
                }
            }
            .accessibilityElement(children: .combine)
            KeyValueList(rows: [
                CyTrendDetailRow(id: "ratioDone", label: "Completed time, endurance : strength", value: model.ratioText ?? "No completed training yet"),
                CyTrendDetailRow(id: "ratioPlan", label: "Planned time, endurance : strength", value: model.plannedRatio.map { "\($0.endurance):\($0.strength)" } ?? "Nothing planned"),
                CyTrendDetailRow(id: "minDone", label: "Completed minutes", value: "\(model.endurance.minutesDone) endurance · \(model.strength.minutesDone) strength"),
            ])
            .accessibilityIdentifier("mixRatios")
            InfoBlock(head: "The centre number", text: "How the training time you have completed this week is split between endurance and strength. It is each discipline's minutes as a share of the total, rounded. Only minutes are used — kilograms, watts, distance and session load are never combined.")
            InfoBlock(head: "The two rings", text: "A different measurement: how far you are through this week's plan in each discipline (completed ÷ planned). The rings can be far apart while the centre ratio matches your plan, and the other way round.")
            leg(title: "Endurance", icon: CyCategory.endurance.icon, color: theme.endurance, l: model.endurance, extra: endurance.secondary)
            leg(title: "Strength", icon: CyCategory.strength.icon, color: theme.strength, l: model.strength, extra: strength.secondary)
            InfoBlock(head: "What it does not show", text: "The ratio is not a score and no split is marked as ideal. This is separate from the load analysis (recent load against your own longer-term average), which stays its own analytics feature.")
            Text("Sample data. Formula: endurance minutes ÷ (endurance + strength minutes), rounded to a whole percent.").font(.caption2).foregroundStyle(theme.textTertiary)
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
                CyRecoveryGlyph(model: model, diameter: 80)
                VStack(alignment: .leading, spacing: 3) {
                    Text(headline).font(CyFont.title).foregroundStyle(theme.textPrimary).fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("recoveryHeadline")
                    Text("\(available) of \(model.sources.count) readings available").font(CyFont.footnote).foregroundStyle(theme.textSecondary)
                    if isSample {
                        Text("SAMPLE SCORE").font(.system(size: 10, weight: .bold)).tracking(0.6).foregroundStyle(theme.warning)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .overlay(Capsule().strokeBorder(theme.warning.opacity(0.8), lineWidth: 1))
                            .accessibilityIdentifier("recoverySampleTag")
                    }
                }
            }
            .accessibilityElement(children: .contain)
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
            if !missing.isEmpty {
                InfoBlock(head: "Missing today", text: missing.joined(separator: ", ") + ". Nothing is estimated in their place.")
                    .accessibilityIdentifier("recoveryMissing")
            }
            if !model.guidance.isEmpty { InfoBlock(head: "Guidance", text: model.guidance) }
            InfoBlock(head: "About the number", text: about)
            InfoBlock(head: "Not medical advice", text: "This is training context only. It is not a medical assessment and never a clearance to train.")
            if !model.freshness.isEmpty { Text(model.freshness).font(.caption2).foregroundStyle(theme.textTertiary) }
        }
    }
    private var available: Int { model.sources.filter { $0.value != nil }.count }
    private var missing: [String] { model.sources.filter { $0.value == nil }.map(\.name) }
    private var isSample: Bool { if case .numericSample = model.state { return true }; return false }
    private var headline: String {
        switch model.state {
        case .numericSample(let p, let w): return "\(p)% · \(w)"
        case .qualitative(let w), .partial(let w): return w
        case .awaiting: return "Awaiting data"
        }
    }
    private var about: String {
        switch model.state {
        case .numericSample:
            return "The percentage on this screen is sample data for design review. Cyclift has no approved numerical recovery model, so the app will not show a percentage until a documented, validated method exists. Until then it shows a status in words."
        case .qualitative:
            return "No percentage is shown because Cyclift has no approved numerical recovery model. The status compares today's readings with your own recent range."
        case .partial:
            return "Some readings are missing, so no overall status or percentage is given. The readings that exist are listed above."
        case .awaiting:
            return "No readings are available, so nothing is shown. Connect a source or wear your watch overnight."
        }
    }
}

struct SleepSheet: View {
    let model: CySleepModel
    let onClose: () -> Void
    var onSetTarget: (Int?) -> Void = { _ in }
    @Environment(\.cyTheme) private var theme
    private let choices = [420, 450, 480, 510, 540]
    var body: some View {
        CySheet(title: "Sleep", onClose: onClose) {
            KeyValueList(rows: [
                CyTrendDetailRow(id: "last", label: "Last night", value: model.lastNight.map(CySleepModel.text) ?? "No record"),
                CyTrendDetailRow(id: "avg", label: "7-day average", value: model.average7.map(CySleepModel.text) ?? "—"),
                CyTrendDetailRow(id: "target", label: model.target == nil ? "Target" : model.targetLabel, value: model.target.map(CySleepModel.text) ?? "Not set"),
            ])
            .accessibilityIdentifier("sleepRows")
            if let last = model.lastNight, let t = model.target, t > 0 {
                VStack(alignment: .leading, spacing: 4) {
                    CyGradientBar(fraction: Double(last) / Double(t), color: theme.ringRecovery, height: 6)
                    Text("Bar: last night ÷ \(model.targetLabel.lowercased())").font(.caption2).foregroundStyle(theme.textTertiary)
                }
            }
            CyWeeklyBars(title: "Recent nights", points: model.nights, unit: "h", category: .recovery, emptyText: "No sleep history yet.")
            VStack(alignment: .leading, spacing: CySpace.s) {
                CyOverline(text: model.target == nil ? "Set your sleep target" : "Your sleep target")
                Text("You choose this number. Cyclift does not calculate or recommend a sleep need.").font(CyFont.footnote).foregroundStyle(theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: CySpace.s) {
                        ForEach(choices, id: \.self) { m in
                            let on = model.target == m
                            Button(action: { onSetTarget(m) }) {
                                Text(CySleepModel.text(m)).font(CyFont.label).foregroundStyle(on ? theme.textOnAccent : theme.textPrimary)
                                    .padding(.horizontal, CySpace.m).frame(minHeight: CyHit.min)
                                    .background(Capsule().fill(on ? theme.accent : theme.surface))
                                    .overlay(Capsule().strokeBorder(theme.id == .highContrast ? theme.border : Color.clear, lineWidth: theme.borderWidth))
                            }
                            .buttonStyle(CyRingButtonStyle())
                            .accessibilityLabel("Target \(CySleepModel.text(m))")
                            .accessibilityAddTraits(on ? [.isSelected, .isButton] : .isButton)
                            .accessibilityIdentifier("sleepTarget-\(m)")
                        }
                    }
                }
                if model.target != nil {
                    Button(action: { onSetTarget(nil) }) {
                        Text("Remove target").font(CyFont.footnote.weight(.semibold)).foregroundStyle(theme.textSecondary)
                            .frame(minHeight: CyHit.min).contentShape(Rectangle())
                    }
                    .buttonStyle(CyRingButtonStyle())
                    .accessibilityIdentifier("sleepTargetClear")
                }
            }
            InfoBlock(head: "Four different things", text: "Last night is one recorded night. The 7-day average is the mean of recorded nights. The target is a goal you set. A recommendation would be advice from a documented source — none is shown here.")
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

struct GraphDaySheet: View {
    let date: CyGraphDate
    let rows: [CyTrendDetailRow]
    let onClose: () -> Void
    @Environment(\.cyTheme) private var theme
    var body: some View {
        CySheet(title: date.full, onClose: onClose) {
            if rows.isEmpty {
                CyEmptyStateCard(icon: "calendar", title: "No data", message: "Nothing was recorded for this day in this view.")
            } else {
                KeyValueList(rows: rows).accessibilityIdentifier("graphDayRows")
            }
            Text("Only what was recorded is listed; a missing reading is shown as missing. Sample data.").font(.caption2).foregroundStyle(theme.textTertiary)
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
