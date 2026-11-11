import SwiftUI

// Cards. Each takes a plain model plus callbacks; none knows where it is shown or what a tap leads to.

struct CyCard<Content: View>: View {
    var padding: CGFloat = CySpace.l
    var isSelected: Bool = false
    @ViewBuilder let content: () -> Content
    @Environment(\.cyTheme) private var theme

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: CyRadius.l, style: .continuous)
        content()
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(shape.fill(isSelected ? theme.selectedFill : theme.surface))
            .overlay(shape.strokeBorder(isSelected ? theme.selectedBorder : theme.border, lineWidth: isSelected ? max(theme.borderWidth, 1.5) : theme.borderWidth))
    }
}

/// Makes a whole card one tappable control with a pressed state.
struct CyCardButtonStyle: ButtonStyle {
    @Environment(\.cyTheme) private var theme
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .overlay(RoundedRectangle(cornerRadius: CyRadius.l, style: .continuous).fill(configuration.isPressed ? theme.pressedOverlay : Color.clear))
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct CyOverline: View {
    let text: String
    var icon: String? = nil
    var tint: Color? = nil
    @Environment(\.cyTheme) private var theme
    var body: some View {
        HStack(spacing: CySpace.xs) {
            if let icon { Image(systemName: icon).font(.caption).foregroundStyle(tint ?? theme.textSecondary) }
            Text(text.uppercased()).font(CyFont.overline).tracking(0.6).foregroundStyle(theme.textSecondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

/// Placeholder block used by every loading state.
struct CySkeleton: View {
    var height: CGFloat = 14
    var width: CGFloat? = nil
    @Environment(\.cyTheme) private var theme
    var body: some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(theme.textPrimary.opacity(theme.id == .highContrast ? 0.30 : 0.10))
            .frame(width: width, height: height)
            .frame(maxWidth: width == nil ? .infinity : nil, alignment: .leading)
            .accessibilityHidden(true)
    }
}

struct CySparkline: View {
    let values: [Double]
    let color: Color
    var body: some View {
        GeometryReader { geo in
            let lo = values.min() ?? 0, hi = values.max() ?? 1
            let span = max(hi - lo, 0.0001)
            Path { p in
                for (i, v) in values.enumerated() {
                    let x = geo.size.width * CGFloat(i) / CGFloat(max(values.count - 1, 1))
                    let y = geo.size.height * (1 - CGFloat((v - lo) / span))
                    if i == 0 { p.move(to: CGPoint(x: x, y: y)) } else { p.addLine(to: CGPoint(x: x, y: y)) }
                }
            }
            .stroke(color, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
        }
        .frame(height: 28)
        .accessibilityHidden(true)
    }
}

// MARK: Training summary (Endurance / Strength Load)

struct CyTrainingSummaryCard: View {
    let model: CySummaryCardModel?          // nil = loading
    var emptyMessage: String? = nil         // set = empty state instead of numbers
    let onOpen: () -> Void
    @Environment(\.cyTheme) private var theme

    var body: some View {
        Button(action: onOpen) {
            CyCard(padding: CySpace.m) {
                VStack(alignment: .leading, spacing: CySpace.s) {
                    if let m = model {
                        CyOverline(text: m.title, icon: m.category.icon, tint: m.category.color(theme))
                        if let emptyMessage {
                            Text(emptyMessage).font(CyFont.footnote).foregroundStyle(theme.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        } else {
                            Text(m.primary).font(CyFont.metric).foregroundStyle(theme.textPrimary)
                                .minimumScaleFactor(0.7).lineLimit(1)
                            Text(m.secondary).font(CyFont.footnote).foregroundStyle(theme.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                            if let p = m.progress {
                                CyProgressBar(fraction: p, color: m.category.color(theme))
                            }
                            if let s = m.supporting {
                                Text(s).font(CyFont.caption).foregroundStyle(theme.textSecondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            if let t = m.trend, t.count >= 2 {
                                CySparkline(values: t, color: m.category.color(theme))
                                if let c = m.trendCaption { Text(c).font(.caption2).foregroundStyle(theme.textTertiary) }
                            } else {
                                Text("Trend appears after two weeks of sessions.").font(.caption2).foregroundStyle(theme.textTertiary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    } else {
                        CySkeleton(height: 10, width: 80)
                        CySkeleton(height: 24, width: 110)
                        CySkeleton(height: 10)
                        CySkeleton(height: 6)
                    }
                    Spacer(minLength: 0)
                }
                .frame(maxHeight: .infinity, alignment: .top)
            }
        }
        .buttonStyle(CyCardButtonStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(a11y)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Opens details")
    }
    private var a11y: String {
        guard let m = model else { return "Loading" }
        if let emptyMessage { return "\(m.title). \(emptyMessage)" }
        return [m.title, m.primary, m.secondary, m.supporting ?? ""].filter { !$0.isEmpty }.joined(separator: ", ")
    }
}

struct CyProgressBar: View {
    let fraction: Double
    let color: Color
    @Environment(\.cyTheme) private var theme
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(theme.ringTrack)
                Capsule().fill(color).frame(width: max(6, geo.size.width * CGFloat(min(max(fraction, 0), 1))))
            }
        }
        .frame(height: 6)
        .accessibilityHidden(true)
    }
}

// MARK: Workout

struct CyWorkoutCard: View {
    let model: CyWorkoutModel?              // nil = loading
    var actionTitle: String = "Start"
    var isActionEnabled: Bool = true
    let onAction: () -> Void
    let onOpen: () -> Void
    @Environment(\.cyTheme) private var theme

    var body: some View {
        CyCard(padding: CySpace.m) {
            if let m = model {
                HStack(alignment: .center, spacing: CySpace.m) {
                    Button(action: onOpen) {
                        HStack(alignment: .center, spacing: CySpace.m) {
                            Image(systemName: m.category.icon)
                                .font(.title3)
                                .foregroundStyle(m.category.color(theme))
                                .frame(width: 40, height: 40)
                                .background(RoundedRectangle(cornerRadius: CyRadius.s, style: .continuous).fill(m.category.color(theme).opacity(0.16)))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(m.title).font(CyFont.headline).foregroundStyle(theme.textPrimary)
                                    .fixedSize(horizontal: false, vertical: true)
                                Text(m.detail).font(CyFont.footnote).foregroundStyle(theme.textSecondary)
                                    .fixedSize(horizontal: false, vertical: true)
                                CyStatusBadge(status: m.status)
                            }
                            Spacer(minLength: 0)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(m.title), \(m.detail), \(m.status.label)")
                    .accessibilityHint("Opens the session")
                    CyButton(title: actionTitle, kind: .compact, fullWidth: false, action: onAction)
                        .disabled(!isActionEnabled)
                }
            } else {
                HStack(spacing: CySpace.m) {
                    CySkeleton(height: 40, width: 40)
                    VStack(alignment: .leading, spacing: CySpace.s) { CySkeleton(height: 14, width: 150); CySkeleton(height: 10, width: 100) }
                }
            }
        }
    }
}

struct CyStatusBadge: View {
    let status: CySessionStatus
    @Environment(\.cyTheme) private var theme
    var body: some View {
        HStack(spacing: CySpace.xs) {
            Image(systemName: status.icon).font(.caption2)
            Text(status.label).font(.caption2.weight(.semibold))
        }
        .foregroundStyle(status.color(theme))
        .accessibilityElement(children: .combine)
    }
}

// MARK: Recovery

struct CyRecoveryCard: View {
    let model: CyRecoveryModel?             // nil = loading
    var emptyMessage: String? = nil
    let onOpen: () -> Void
    @Environment(\.cyTheme) private var theme

    var body: some View {
        Button(action: onOpen) {
            CyCard {
                VStack(alignment: .leading, spacing: CySpace.m) {
                    CyOverline(text: "Recovery", icon: CyCategory.recovery.icon, tint: theme.recovery)
                    if let emptyMessage {
                        Text(emptyMessage).font(CyFont.callout).foregroundStyle(theme.textSecondary).fixedSize(horizontal: false, vertical: true)
                    } else if let m = model {
                        HStack(spacing: CySpace.s) {
                            Image(systemName: m.level.icon).foregroundStyle(m.level.color(theme))
                            Text(m.word).font(CyFont.title).foregroundStyle(theme.textPrimary)
                        }
                        ForEach(Array(m.readings.enumerated()), id: \.offset) { _, r in
                            HStack(alignment: .firstTextBaseline) {
                                Text(r.label).font(CyFont.footnote).foregroundStyle(theme.textSecondary)
                                Spacer()
                                Text(r.value).font(CyFont.footnote.weight(.semibold)).foregroundStyle(theme.textPrimary)
                                Text(r.note).font(.caption2).foregroundStyle(theme.textTertiary)
                            }
                        }
                        Text(m.recommendation).font(CyFont.footnote).foregroundStyle(theme.textSecondary).fixedSize(horizontal: false, vertical: true)
                    } else {
                        CySkeleton(height: 20, width: 160); CySkeleton(); CySkeleton(); CySkeleton(width: 200)
                    }
                }
            }
        }
        .buttonStyle(CyCardButtonStyle())
        .accessibilityHint("Opens recovery details")
    }
}

// MARK: Coach insight (card and compact row)

struct CyCoachInsightCard: View {
    let model: CyCoachModel?                // nil = loading
    var compact: Bool = false
    var emptyMessage: String? = nil
    let onWhy: () -> Void
    var onAccept: (() -> Void)? = nil
    var onNotNow: (() -> Void)? = nil
    @Environment(\.cyTheme) private var theme

    var body: some View {
        CyCard(padding: compact ? CySpace.m : CySpace.l) {
            VStack(alignment: .leading, spacing: CySpace.s) {
                HStack(spacing: CySpace.xs) {
                    Image(systemName: "sparkles").font(.caption).foregroundStyle(theme.accent)
                    Text("CYCLIFT COACH").font(CyFont.overline).tracking(0.6).foregroundStyle(theme.textSecondary)
                    Text("· rules-based").font(.caption2).foregroundStyle(theme.textTertiary)
                    Spacer(minLength: 0)
                }
                .accessibilityElement(children: .combine)
                if let emptyMessage {
                    Text(emptyMessage).font(CyFont.callout).foregroundStyle(theme.textSecondary).fixedSize(horizontal: false, vertical: true)
                } else if let m = model {
                    Text(m.sentence).font(compact ? CyFont.callout : CyFont.body).foregroundStyle(theme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: CySpace.s) {
                        CyButton(title: "Why?", icon: "questionmark.circle", kind: .compact, fullWidth: false, action: onWhy)
                        if m.hasProposal {
                            if let onAccept { CyButton(title: "Review", kind: .compact, fullWidth: false, action: onAccept) }
                            if let onNotNow { CyButton(title: "Not now", kind: .compact, fullWidth: false, action: onNotNow) }
                        }
                        Spacer(minLength: 0)
                    }
                } else {
                    CySkeleton(); CySkeleton(width: 220)
                }
            }
        }
    }
}

// MARK: Empty state

struct CyEmptyStateCard: View {
    let icon: String
    let title: String
    let message: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil
    @Environment(\.cyTheme) private var theme

    var body: some View {
        CyCard {
            VStack(alignment: .leading, spacing: CySpace.m) {
                Image(systemName: icon).font(.title2).foregroundStyle(theme.textTertiary).accessibilityHidden(true)
                Text(title).font(CyFont.headline).foregroundStyle(theme.textPrimary).fixedSize(horizontal: false, vertical: true)
                Text(message).font(CyFont.callout).foregroundStyle(theme.textSecondary).fixedSize(horizontal: false, vertical: true)
                if let actionTitle, let action { CyButton(title: actionTitle, kind: .secondary, action: action) }
            }
        }
    }
}

// MARK: Getting Started

struct CyGettingStartedCard: View {
    let items: [CyChecklistItem]
    var collapsedWhenComplete: Bool = true
    let onItem: (CyChecklistItem) -> Void
    @Environment(\.cyTheme) private var theme
    @State private var expanded = false

    private var doneCount: Int { items.filter(\.isDone).count }
    private var essentialsOpen: Bool { items.contains { $0.isEssential && !$0.isDone } }

    var body: some View {
        CyCard(padding: CySpace.m) {
            VStack(alignment: .leading, spacing: CySpace.s) {
                Button(action: { withAnimation(.easeInOut(duration: 0.2)) { expanded.toggle() } }) {
                    HStack(spacing: CySpace.s) {
                        Image(systemName: essentialsOpen ? "flag.checkered" : "checkmark.seal.fill")
                            .foregroundStyle(essentialsOpen ? theme.accent : theme.success)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(essentialsOpen ? "Getting started" : "Setup complete").font(CyFont.headline).foregroundStyle(theme.textPrimary)
                            Text("\(doneCount) of \(items.count) done").font(CyFont.caption).foregroundStyle(theme.textSecondary)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: showList ? "chevron.up" : "chevron.down").font(.caption.weight(.semibold)).foregroundStyle(theme.textTertiary)
                    }
                    .frame(minHeight: CyHit.min)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(essentialsOpen ? "Getting started" : "Setup complete"), \(doneCount) of \(items.count) done")
                .accessibilityHint(showList ? "Collapses the list" : "Expands the list")
                CyProgressBar(fraction: items.isEmpty ? 0 : Double(doneCount) / Double(items.count), color: essentialsOpen ? theme.accent : theme.success)
                if showList { CyChecklist(items: items, onItem: onItem) }
            }
        }
    }
    private var showList: Bool { essentialsOpen ? !expanded : (collapsedWhenComplete ? expanded : !expanded) }
}

// MARK: Metric summary

struct CyMetricSummaryCard: View {
    let model: CyMetricModel?               // nil = loading
    var onOpen: (() -> Void)? = nil
    @Environment(\.cyTheme) private var theme

    var body: some View {
        Button(action: { onOpen?() }) {
            CyCard(padding: CySpace.m) {
                VStack(alignment: .leading, spacing: CySpace.xs) {
                    if let m = model {
                        Text(m.label).font(CyFont.caption).foregroundStyle(theme.textSecondary).fixedSize(horizontal: false, vertical: true)
                        HStack(alignment: .firstTextBaseline, spacing: CySpace.xs) {
                            Text(m.value ?? "—").font(CyFont.metric).foregroundStyle(m.value == nil ? theme.textTertiary : theme.textPrimary)
                                .minimumScaleFactor(0.7).lineLimit(1)
                            if let u = m.unit, m.value != nil { Text(u).font(CyFont.caption).foregroundStyle(theme.textSecondary) }
                        }
                        if m.value == nil {
                            Text("No data yet").font(.caption2).foregroundStyle(theme.textTertiary)
                        } else if let d = m.delta {
                            Text(d).font(.caption2.weight(.semibold)).foregroundStyle(m.deltaLevel.color(theme)).fixedSize(horizontal: false, vertical: true)
                        }
                    } else {
                        CySkeleton(height: 10, width: 70); CySkeleton(height: 22, width: 90); CySkeleton(height: 8, width: 60)
                    }
                }
            }
        }
        .buttonStyle(CyCardButtonStyle())
        .disabled(onOpen == nil)
        .accessibilityElement(children: .combine)
    }
}
