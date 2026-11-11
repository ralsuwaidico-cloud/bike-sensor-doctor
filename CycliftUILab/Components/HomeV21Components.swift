import SwiftUI

// Home v2.1 components: three indicators (Consistency ring, Training Mix double ring, qualitative Recovery),
// compact schedule, compact sport cards, Sleep bar, Coach banner, setup banner.
// Data in, callbacks out. No production dependencies.

// MARK: Indicator glyphs

/// Single progress ring with a gradient sweep.
struct CyProgressRingGlyph: View {
    let fraction: Double?            // nil = no data (dashed)
    let color: Color
    var diameter: CGFloat = 76
    var lineWidth: CGFloat = 8
    @Environment(\.cyTheme) private var theme
    var body: some View {
        let lw = lineWidth * theme.ringLineWidthScale
        ZStack {
            if let f = fraction {
                Circle().stroke(theme.ringTrack, lineWidth: lw)
                Circle().trim(from: 0, to: CGFloat(min(max(f, 0.004), 1)))
                    .stroke(theme.ringGradient(color, fraction: f), style: StrokeStyle(lineWidth: lw, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.easeOut(duration: 0.5), value: f)
            } else {
                Circle().stroke(theme.textTertiary.opacity(0.8), style: StrokeStyle(lineWidth: max(1.5, lw * 0.3), lineCap: .round, dash: [2, 6]))
            }
        }
        .padding(lw / 2)
        .frame(width: diameter, height: diameter)
        .accessibilityHidden(true)
    }
}

/// Training Mix: outer ring = endurance done vs planned, inner ring = strength done vs planned.
/// Two separate values; nothing is combined into one score. A discipline that is not planned is drawn inactive.
struct CyMixRingGlyph: View {
    let model: CyMixModel?           // nil = loading
    var diameter: CGFloat = 76
    @Environment(\.cyTheme) private var theme
    var body: some View {
        let outer: CGFloat = 7, gap: CGFloat = 4
        ZStack {
            CyProgressRingGlyph(fraction: model == nil ? 0 : model?.endurance.fraction, color: theme.endurance, diameter: diameter, lineWidth: outer)
            CyProgressRingGlyph(fraction: model == nil ? 0 : model?.strength.fraction, color: theme.strength,
                                diameter: diameter - 2 * (outer * theme.ringLineWidthScale + gap), lineWidth: outer)
            if model == nil { ProgressView().controlSize(.small) }
            else { Text("Mix").font(.caption2.weight(.semibold)).foregroundStyle(theme.textSecondary) }
        }
        .frame(width: diameter, height: diameter)
        .accessibilityHidden(true)
    }
}

/// Recovery: not a progress ring. Three short arcs show which readings exist today; the centre icon and the word
/// carry the state. No percentage, no tick, no "safe to train".
struct CyRecoveryGlyph: View {
    let model: CyRecoveryIndicatorModel?   // nil = loading
    var diameter: CGFloat = 76
    @Environment(\.cyTheme) private var theme
    var body: some View {
        let lw: CGFloat = 5 * theme.ringLineWidthScale
        ZStack {
            ForEach(0..<3, id: \.self) { i in
                let has = (model?.sources.indices.contains(i) ?? false) && model?.sources[i].value != nil
                Circle()
                    .trim(from: CGFloat(i) / 3 + 0.035, to: CGFloat(i + 1) / 3 - 0.035)
                    .stroke(has ? theme.ringRecovery : theme.textTertiary.opacity(0.55),
                            style: StrokeStyle(lineWidth: has ? lw : max(1.5, lw * 0.4), lineCap: .round, dash: has ? [] : [2, 5]))
                    .rotationEffect(.degrees(-90))
            }
            if model == nil { ProgressView().controlSize(.small) }
            else { Image(systemName: icon).font(.title3.weight(.semibold)).foregroundStyle(iconColor) }
        }
        .padding(lw / 2)
        .frame(width: diameter, height: diameter)
        .accessibilityHidden(true)
    }
    private var icon: String {
        guard let state = model?.state else { return "hourglass" }
        switch state {
        case .concern: return "exclamationmark.triangle.fill"
        case .awaiting: return "hourglass"
        case .partial: return "heart"
        case .available: return "heart.fill"
        }
    }
    private var iconColor: Color {
        guard let state = model?.state else { return theme.textTertiary }
        switch state {
        case .concern: return theme.warning
        case .awaiting: return theme.textTertiary
        case .partial, .available: return theme.ringRecovery
        }
    }
}

// MARK: Indicator row

struct CyIndicatorText: Equatable {
    let title: String
    let line: String                 // short caption under the title
    let spoken: String               // full VoiceOver value
}

struct CyIndicatorRow: View {
    // nil models = loading
    let consistency: (fraction: Double?, text: String, caption: String)?
    let mix: CyMixModel?
    let recovery: CyRecoveryIndicatorModel?
    var isLoading: Bool = false
    let onConsistency: () -> Void
    let onMix: () -> Void
    let onRecovery: () -> Void
    @Environment(\.cyTheme) private var theme
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let big = typeSize.isAccessibilitySize
        let layout = big ? AnyLayout(VStackLayout(alignment: .leading, spacing: CySpace.m)) : AnyLayout(HStackLayout(alignment: .top, spacing: CySpace.s))
        layout {
            tile(title: "Consistency", info: consistencyText, big: big, action: onConsistency) {
                ZStack {
                    CyProgressRingGlyph(fraction: isLoading ? 0 : consistency?.fraction, color: theme.ringConsistency, diameter: big ? 56 : 76)
                    if isLoading { ProgressView().controlSize(.small) }
                    else if let c = consistency, c.fraction != nil {
                        Text(c.text).font(big ? CyFont.caption : CyFont.metricSmall).foregroundStyle(theme.textPrimary).minimumScaleFactor(0.6).lineLimit(1).padding(.horizontal, 12)
                    } else { Image(systemName: "minus").foregroundStyle(theme.textTertiary) }
                }
            }
            tile(title: "Training Mix", info: mixText, big: big, action: onMix) {
                CyMixRingGlyph(model: isLoading ? nil : mix, diameter: big ? 56 : 76)
            }
            tile(title: "Recovery", info: recoveryText, big: big, action: onRecovery) {
                CyRecoveryGlyph(model: isLoading ? nil : recovery, diameter: big ? 56 : 76)
            }
        }
    }

    private func tile<G: View>(title: String, info: CyIndicatorText, big: Bool, action: @escaping () -> Void, @ViewBuilder glyph: () -> G) -> some View {
        let g = glyph()
        return Button(action: action) {
            Group {
                if big {
                    HStack(spacing: CySpace.m) {
                        g
                        VStack(alignment: .leading, spacing: 2) {
                            Text(title).font(CyFont.headline).foregroundStyle(theme.textPrimary)
                            Text(info.line).font(CyFont.callout).foregroundStyle(theme.textSecondary).fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                    }
                } else {
                    VStack(spacing: 6) {
                        g
                        Text(title).font(CyFont.caption).foregroundStyle(theme.textPrimary).lineLimit(1).minimumScaleFactor(0.8)
                        Text(info.line).font(.caption2).foregroundStyle(theme.textSecondary).multilineTextAlignment(.center)
                            .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(minHeight: CyHit.min)
            .contentShape(Rectangle())
        }
        .buttonStyle(CyRingButtonStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(info.spoken)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Opens details")
    }

    private var consistencyText: CyIndicatorText {
        if isLoading { return CyIndicatorText(title: "Consistency", line: "Loading", spoken: "Loading") }
        guard let c = consistency, c.fraction != nil else {
            return CyIndicatorText(title: "Consistency", line: consistency?.caption ?? "No sessions yet", spoken: consistency?.caption ?? "No sessions yet")
        }
        return CyIndicatorText(title: "Consistency", line: c.caption, spoken: "\(c.text), \(c.caption)")
    }
    private var mixText: CyIndicatorText {
        if isLoading { return CyIndicatorText(title: "Training Mix", line: "Loading", spoken: "Loading") }
        guard let m = mix, m.hasAnyPlan else { return CyIndicatorText(title: "Training Mix", line: "Nothing planned", spoken: "Nothing planned this week") }
        func pct(_ l: CyMixLeg) -> String { l.fraction.map { "\(Int(($0 * 100).rounded()))%" } ?? "not planned" }
        let spoken = "Endurance \(m.endurance.fraction == nil ? "not planned" : "\(m.endurance.done) of \(m.endurance.planned ?? "")"), strength \(m.strength.fraction == nil ? "not planned" : "\(m.strength.done) of \(m.strength.planned ?? "")")"
        let line: String
        if m.endurance.fraction == nil { line = "Lift \(pct(m.strength)) · no rides planned" }
        else if m.strength.fraction == nil { line = "Ride \(pct(m.endurance)) · no lifting planned" }
        else { line = "Ride \(pct(m.endurance)) · Lift \(pct(m.strength))" }
        return CyIndicatorText(title: "Training Mix", line: line, spoken: spoken)
    }
    private var recoveryText: CyIndicatorText {
        if isLoading { return CyIndicatorText(title: "Recovery", line: "Loading", spoken: "Loading") }
        guard let r = recovery else { return CyIndicatorText(title: "Recovery", line: "Awaiting data", spoken: "Awaiting data") }
        let have = r.sources.filter { $0.value != nil }.count
        switch r.state {
        case .available(let w): return CyIndicatorText(title: "Recovery", line: w, spoken: "\(w). \(have) of \(r.sources.count) readings available")
        case .partial(let w): return CyIndicatorText(title: "Recovery", line: w, spoken: "\(w). \(have) of \(r.sources.count) readings available")
        case .awaiting: return CyIndicatorText(title: "Recovery", line: "Awaiting data", spoken: "Awaiting data. No readings yet")
        case .concern(let w): return CyIndicatorText(title: "Recovery", line: w, spoken: "\(w). Open for details")
        }
    }
}

// MARK: Compact seven-day schedule

/// One session mark. State is carried by shape as well as colour:
/// completed = filled disc · planned = thin outline · missed = dashed outline with a slash · rescheduled = outline with an arrow.
struct CySessionMark: View {
    let session: CyDaySession
    var size: CGFloat = 22
    @Environment(\.cyTheme) private var theme
    var body: some View {
        let c = session.category.color(theme)
        ZStack {
            switch session.state {
            case .completed:
                Circle().fill(theme.gradient(c))
                Image(systemName: session.category.icon).font(.system(size: size * 0.5, weight: .semibold)).foregroundStyle(theme.background)
            case .planned:
                Circle().strokeBorder(theme.textTertiary, lineWidth: 1.2)
                Image(systemName: session.category.icon).font(.system(size: size * 0.5, weight: .regular)).foregroundStyle(theme.textSecondary)
            case .missed:
                Circle().strokeBorder(theme.warning, style: StrokeStyle(lineWidth: 1.4, dash: [2.5, 2.5]))
                Image(systemName: session.category.icon).font(.system(size: size * 0.5)).foregroundStyle(theme.textTertiary)
                Rectangle().fill(theme.warning).frame(width: size * 0.9, height: 1.5).rotationEffect(.degrees(-45))
            case .rescheduled:
                Circle().strokeBorder(theme.textTertiary, lineWidth: 1.2)
                Image(systemName: "arrow.right").font(.system(size: size * 0.48, weight: .semibold)).foregroundStyle(theme.textSecondary)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

struct CyCompactSchedule: View {
    let days: [CyScheduleDay]
    var isLoading: Bool = false
    let onDay: (CyScheduleDay) -> Void
    @Environment(\.cyTheme) private var theme
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        if isLoading {
            HStack(spacing: CySpace.xs) { ForEach(0..<7, id: \.self) { _ in CySkeleton(height: 48) } }
        } else if days.isEmpty {
            HStack(spacing: CySpace.s) {
                Image(systemName: "calendar").foregroundStyle(theme.textTertiary)
                Text("No sessions planned this week").font(CyFont.footnote).foregroundStyle(theme.textSecondary)
                Spacer(minLength: 0)
            }
            .frame(minHeight: CyHit.min)
            .accessibilityElement(children: .combine)
        } else {
            HStack(spacing: 0) { ForEach(days) { d in cell(d) } }
        }
    }

    private func cell(_ d: CyScheduleDay) -> some View {
        let mark: CGFloat = d.sessions.count > 1 ? 19 : 22
        return Button(action: { onDay(d) }) {
            VStack(spacing: 5) {
                Text(d.letter).font(.caption2.weight(d.isToday ? .bold : .medium)).foregroundStyle(d.isToday ? theme.accent : theme.textSecondary)
                HStack(spacing: 2) {
                    if d.sessions.isEmpty {
                        if d.isRest { Image(systemName: "moon").font(.system(size: 11)).foregroundStyle(theme.textTertiary) }
                        else { Capsule().fill(theme.textTertiary.opacity(0.5)).frame(width: 8, height: 2) }
                    } else {
                        ForEach(d.sessions.prefix(2)) { s in CySessionMark(session: s, size: mark) }
                    }
                }
                .frame(height: 22)
            }
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(d.isToday ? theme.selectedFill : Color.clear).padding(.horizontal, 1))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(d.isToday && theme.id == .highContrast ? theme.accent : Color.clear, lineWidth: 1.5).padding(.horizontal, 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(CyRingButtonStyle())
        .accessibilityLabel("\(d.weekday) \(d.date)\(d.isToday ? ", today" : "")")
        .accessibilityValue(d.sessions.isEmpty ? (d.isRest ? "Rest day" : "Nothing planned") : d.sessions.map { "\($0.title), \($0.state.label)" }.joined(separator: "; "))
        .accessibilityHint("Opens the day")
    }
}

// MARK: Compact sport card

struct CyCompactSportCard: View {
    let model: CySportCardModel?     // nil = loading
    let onOpen: () -> Void
    @Environment(\.cyTheme) private var theme

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 6) {
                if let m = model {
                    HStack(spacing: 6) {
                        Image(systemName: m.category.icon).font(.footnote.weight(.semibold)).foregroundStyle(m.category.color(theme))
                        Text(m.title).font(CyFont.label).foregroundStyle(theme.textSecondary)
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right").font(.caption2.weight(.semibold)).foregroundStyle(theme.textTertiary)
                    }
                    if let empty = m.emptyText {
                        Text(empty).font(CyFont.footnote).foregroundStyle(theme.textSecondary).fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    } else {
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text(m.done ?? "—").font(CyFont.value).foregroundStyle(theme.textPrimary)
                            if let p = m.planned { Text("/ \(p)").font(CyFont.footnote).foregroundStyle(theme.textSecondary) }
                        }
                        .lineLimit(1).minimumScaleFactor(0.7)
                        CyGradientBar(fraction: m.fraction ?? 0, color: m.category.color(theme))
                        Text(m.secondary ?? " ").font(.caption2).foregroundStyle(theme.textSecondary).lineLimit(1).minimumScaleFactor(0.8)
                    }
                } else {
                    CySkeleton(height: 10, width: 70); CySkeleton(height: 18, width: 100); CySkeleton(height: 4); CySkeleton(height: 8, width: 60)
                }
            }
            .padding(CySpace.m)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: CyRadius.m, style: .continuous).fill(theme.surface))
            .overlay(RoundedRectangle(cornerRadius: CyRadius.m, style: .continuous).strokeBorder(theme.cardStroke, lineWidth: theme.borderWidth))
        }
        .buttonStyle(CyCardButtonStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(model?.title ?? "Loading")
        .accessibilityValue(spoken)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Opens details")
    }
    private var spoken: String {
        guard let m = model else { return "" }
        if let e = m.emptyText { return e }
        return [m.done.map { d in m.planned.map { "\(d) of \($0)" } ?? d } ?? "No data", m.secondary ?? ""].filter { !$0.isEmpty }.joined(separator: ", ")
    }
}

struct CyGradientBar: View {
    let fraction: Double
    let color: Color
    var height: CGFloat = 4
    @Environment(\.cyTheme) private var theme
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(theme.ringTrack)
                if fraction > 0 {
                    Capsule().fill(theme.gradient(color)).frame(width: max(height, geo.size.width * CGFloat(min(max(fraction, 0), 1))))
                }
            }
        }
        .frame(height: height * (theme.id == .highContrast ? 1.5 : 1))
        .accessibilityHidden(true)
    }
}

// MARK: Sleep bar (borderless)

/// The bar means one thing: last recorded sleep ÷ the displayed target. The average and the target are labelled
/// separately; the target's source is always stated and never derived here.
struct CySleepBar: View {
    let model: CySleepModel?         // nil = loading
    let onOpen: () -> Void
    @Environment(\.cyTheme) private var theme

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: "moon.stars.fill").font(.footnote).foregroundStyle(theme.ringRecovery)
                    Text("Sleep").font(CyFont.label).foregroundStyle(theme.textSecondary)
                    Spacer(minLength: CySpace.s)
                    if let m = model {
                        if let last = m.lastNight {
                            Text(CySleepModel.text(last)).font(CyFont.value).foregroundStyle(theme.textPrimary)
                        } else {
                            Text("No sleep recorded").font(CyFont.footnote).foregroundStyle(theme.textSecondary)
                        }
                    } else { CySkeleton(height: 16, width: 70) }
                    Image(systemName: "chevron.right").font(.caption2.weight(.semibold)).foregroundStyle(theme.textTertiary)
                }
                if let m = model {
                    if let last = m.lastNight, let t = m.target, t > 0 {
                        CyGradientBar(fraction: Double(last) / Double(t), color: theme.ringRecovery)
                    } else {
                        CyGradientBar(fraction: 0, color: theme.ringRecovery)
                    }
                    HStack {
                        Text(m.average7.map { "7-day average \(CySleepModel.text($0))" } ?? "7-day average —")
                        Spacer(minLength: CySpace.s)
                        Text(m.target.map { "Target \(CySleepModel.text($0))" } ?? "No target set")
                    }
                    .font(.caption2).foregroundStyle(theme.textSecondary).lineLimit(1).minimumScaleFactor(0.8)
                } else {
                    CySkeleton(height: 4); CySkeleton(height: 8, width: 180)
                }
            }
            .padding(.vertical, CySpace.s)
            .padding(.horizontal, CySpace.xs)
            .frame(minHeight: CyHit.min)
            .contentShape(Rectangle())
        }
        .buttonStyle(CyRingButtonStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Sleep")
        .accessibilityValue(spoken)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Opens sleep details")
    }
    private var spoken: String {
        guard let m = model else { return "Loading" }
        let last = m.lastNight.map { "Last night \(CySleepModel.text($0))" } ?? "No sleep recorded"
        let avg = m.average7.map { "seven-day average \(CySleepModel.text($0))" } ?? "no seven-day average yet"
        let tgt = m.target.map { "target \(CySleepModel.text($0)), \(m.targetSource)" } ?? "no target set"
        return "\(last), \(avg), \(tgt)"
    }
}

// MARK: Coach banner

/// One recommendation, one primary action. Review is primary when a decision is pending; Why? is a small
/// explanation action; Not now postpones (it is not a rejection). Labelled rules-based — no generative model.
struct CyCoachBanner: View {
    let model: CyCoachBannerModel?   // nil = loading
    var emptyText: String? = nil
    var decision: CyCoachDecision = .none
    let onWhy: () -> Void
    let onReview: () -> Void
    let onNotNow: () -> Void
    @Environment(\.cyTheme) private var theme
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: CyRadius.m, style: .continuous)
        VStack(alignment: .leading, spacing: CySpace.s) {
            HStack(spacing: CySpace.s) {
                Image(systemName: "sparkles").font(.footnote.weight(.semibold)).foregroundStyle(theme.textOnAccent)
                    .frame(width: 26, height: 26).background(Circle().fill(theme.accent))
                    .accessibilityHidden(true)
                Text("Coach").font(CyFont.label).foregroundStyle(theme.textPrimary)
                Text("rules-based").font(.caption2).foregroundStyle(theme.textSecondary)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .overlay(Capsule().strokeBorder(theme.textTertiary.opacity(0.6), lineWidth: 1))
                Spacer(minLength: 0)
                if model != nil && emptyText == nil {
                    Button(action: onWhy) {
                        Label("Why?", systemImage: "info.circle").font(CyFont.caption).foregroundStyle(theme.accent)
                            .frame(minWidth: CyHit.min, minHeight: CyHit.min, alignment: .trailing).contentShape(Rectangle())
                    }
                    .buttonStyle(CyRingButtonStyle())
                    .accessibilityLabel("Why this suggestion")
                }
            }
            .accessibilityElement(children: .contain)
            if let emptyText {
                Text(emptyText).font(CyFont.callout).foregroundStyle(theme.textSecondary).fixedSize(horizontal: false, vertical: true)
            } else if let m = model {
                Text(m.sentence).font(CyFont.callout).foregroundStyle(theme.textPrimary).fixedSize(horizontal: false, vertical: true)
                if let note = decisionNote {
                    Label(note.text, systemImage: note.icon).font(CyFont.caption).foregroundStyle(theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if m.hasProposal && (decision == .none || decision == .postponed) {
                    let actions = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: CySpace.s)) : AnyLayout(HStackLayout(spacing: CySpace.m))
                    actions {
                        Button(action: onReview) {
                            Text("Review").font(CyFont.headline).foregroundStyle(theme.textOnAccent)
                                .padding(.horizontal, CySpace.xl).frame(minHeight: CyHit.min)
                                .background(Capsule().fill(theme.accent))
                        }
                        .buttonStyle(CyRingButtonStyle())
                        if decision == .none {
                            Button(action: onNotNow) {
                                Text("Not now").font(CyFont.label).foregroundStyle(theme.textSecondary)
                                    .padding(.horizontal, CySpace.s).frame(minHeight: CyHit.min).contentShape(Rectangle())
                            }
                            .buttonStyle(CyRingButtonStyle())
                            .accessibilityHint("Postpones the suggestion. It is not declined.")
                        }
                    }
                }
            } else {
                CySkeleton(); CySkeleton(width: 220)
            }
        }
        .padding(CySpace.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ZStack { shape.fill(theme.surface); shape.fill(theme.highlightSurface) })
        .overlay(shape.strokeBorder(theme.id == .highContrast ? theme.accent : theme.accent.opacity(0.28), lineWidth: theme.borderWidth))
    }
    private var decisionNote: (text: String, icon: String)? {
        switch decision {
        case .none: return nil
        case .accepted: return ("Accepted — applied to the sample plan", "checkmark.circle")
        case .declined: return ("Declined — this suggestion will not be repeated", "xmark.circle")
        case .postponed: return ("Postponed — still waiting for your decision", "clock")
        }
    }
}

// MARK: Setup banner (Getting Started, compact)

/// While a required step is open: compact card showing the next required action. When all required steps are
/// done: one quiet line. Optional steps never block completion and are labelled as optional.
struct CySetupBanner: View {
    let steps: [CySetupStep]
    let onStep: (CySetupStep) -> Void
    @Environment(\.cyTheme) private var theme
    @State private var expanded = false

    private var required: [CySetupStep] { steps.filter(\.isRequired) }
    private var optional: [CySetupStep] { steps.filter { !$0.isRequired } }
    private var next: CySetupStep? { required.first { !$0.isDone } }
    private var optionalLeft: Int { optional.filter { !$0.isDone }.count }

    var body: some View {
        if let next {
            VStack(alignment: .leading, spacing: CySpace.s) {
                HStack(spacing: CySpace.s) {
                    Text("Getting started").font(CyFont.label).foregroundStyle(theme.textSecondary)
                    Spacer(minLength: 0)
                    Text("\(required.filter(\.isDone).count) of \(required.count) required").font(.caption2).foregroundStyle(theme.textSecondary)
                }
                Button(action: { onStep(next) }) {
                    HStack(spacing: CySpace.m) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(next.title).font(CyFont.headline).foregroundStyle(theme.textPrimary).fixedSize(horizontal: false, vertical: true)
                            Text(next.detail).font(.caption2).foregroundStyle(theme.textSecondary).fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "arrow.right").font(.footnote.weight(.bold)).foregroundStyle(theme.textOnAccent)
                            .frame(width: 34, height: 34).background(Circle().fill(theme.accent))
                    }
                    .frame(minHeight: CyHit.min).contentShape(Rectangle())
                }
                .buttonStyle(CyRingButtonStyle())
                .accessibilityLabel("Next required step: \(next.title)")
                disclosure(title: expanded ? "Hide all steps" : "All steps (\(optionalLeft) optional)")
                if expanded { list }
            }
            .padding(CySpace.m)
            .background(RoundedRectangle(cornerRadius: CyRadius.m, style: .continuous).fill(theme.surface))
            .overlay(RoundedRectangle(cornerRadius: CyRadius.m, style: .continuous).strokeBorder(theme.cardStroke, lineWidth: theme.borderWidth))
        } else if !steps.isEmpty {
            VStack(alignment: .leading, spacing: CySpace.s) {
                Button(action: { withAnimation(.easeInOut(duration: 0.2)) { expanded.toggle() } }) {
                    HStack(spacing: CySpace.s) {
                        Image(systemName: "checkmark.seal.fill").foregroundStyle(theme.success)
                        Text("Setup complete").font(CyFont.label).foregroundStyle(theme.textPrimary)
                        if optionalLeft > 0 { Text("· \(optionalLeft) optional left").font(.caption2).foregroundStyle(theme.textSecondary) }
                        Spacer(minLength: 0)
                        Image(systemName: expanded ? "chevron.up" : "chevron.down").font(.caption2.weight(.semibold)).foregroundStyle(theme.textTertiary)
                    }
                    .frame(minHeight: CyHit.min).contentShape(Rectangle())
                }
                .buttonStyle(CyRingButtonStyle())
                .accessibilityLabel("Setup complete\(optionalLeft > 0 ? ", \(optionalLeft) optional steps left" : "")")
                .accessibilityHint(expanded ? "Hides the steps" : "Shows the steps")
                if expanded { list }
            }
            .padding(.horizontal, CySpace.xs)
        }
    }

    private func disclosure(title: String) -> some View {
        Button(action: { withAnimation(.easeInOut(duration: 0.2)) { expanded.toggle() } }) {
            HStack(spacing: 4) {
                Text(title).font(CyFont.caption).foregroundStyle(theme.accent)
                Image(systemName: expanded ? "chevron.up" : "chevron.down").font(.caption2.weight(.semibold)).foregroundStyle(theme.accent)
            }
            .frame(minHeight: CyHit.min, alignment: .leading).contentShape(Rectangle())
        }
        .buttonStyle(CyRingButtonStyle())
    }

    private var list: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(steps) { s in
                Button(action: { onStep(s) }) {
                    HStack(alignment: .center, spacing: CySpace.m) {
                        Image(systemName: s.isDone ? "checkmark.circle.fill" : "circle").foregroundStyle(s.isDone ? theme.success : theme.textTertiary)
                        Text(s.title).font(CyFont.callout).foregroundStyle(theme.textPrimary).strikethrough(s.isDone, color: theme.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                        Text(s.isRequired ? "Required" : "Optional").font(.caption2.weight(s.isRequired ? .semibold : .regular))
                            .foregroundStyle(s.isRequired ? theme.textPrimary : theme.textSecondary)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .overlay(Capsule().strokeBorder(s.isRequired ? theme.textSecondary : theme.textTertiary.opacity(0.6), style: StrokeStyle(lineWidth: 1, dash: s.isRequired ? [] : [3, 2])))
                    }
                    .frame(minHeight: CyHit.min).contentShape(Rectangle())
                }
                .buttonStyle(CyRingButtonStyle())
                .accessibilityLabel(s.title)
                .accessibilityValue("\(s.isDone ? "done" : "not done"), \(s.isRequired ? "required" : "optional")")
            }
        }
    }
}
