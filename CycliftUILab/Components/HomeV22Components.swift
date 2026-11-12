import SwiftUI

// Home v2.2 (owner review of 12 Nov 2026, UI Lab only): indicators with a numeric centre, simplified schedule marks,
// clearer Sleep bar, Coach as Observation → Recommendation → Action. Accessibility identifiers are for the
// prototype's own interaction tests.

// MARK: Training Mix glyph

/// Outer ring = endurance completed ÷ planned. Inner ring = strength completed ÷ planned.
/// Centre = composition of COMPLETED TRAINING TIME (endurance : strength minutes) — a different measurement from the
/// arcs; the detail sheet explains both. No completed time → "—", never an invented ratio.
struct CyMixRingGlyph: View {
    let model: CyMixModel?           // nil = loading
    var diameter: CGFloat = 76
    var showsCentre: Bool = true
    @Environment(\.cyTheme) private var theme
    var body: some View {
        let outer: CGFloat = 6.5, gap: CGFloat = 3.5
        ZStack {
            CyProgressRingGlyph(fraction: model == nil ? 0 : model?.endurance.fraction, color: theme.endurance, diameter: diameter, lineWidth: outer)
            CyProgressRingGlyph(fraction: model == nil ? 0 : model?.strength.fraction, color: theme.strength,
                                diameter: diameter - 2 * (outer * theme.ringLineWidthScale + gap), lineWidth: outer)
            if let m = model, showsCentre {
                Text(m.ratioText ?? "—")
                    .font(.system(size: diameter * 0.17, weight: .bold, design: .rounded)).monospacedDigit()
                    .foregroundStyle(m.ratioText == nil ? theme.textTertiary : theme.textPrimary)
                    .lineLimit(1).minimumScaleFactor(0.7)
                    .frame(width: diameter * 0.5)
            }
        }
        .frame(width: diameter, height: diameter)
        .accessibilityHidden(true)
    }
}

// MARK: Recovery glyph

/// v2.2: no heart, no availability arcs. A percentage ring is drawn only for clearly marked SAMPLE data.
/// Qualitative: a plain ring with a short status word in the centre and no number. Partial / awaiting: dashed ring.
struct CyRecoveryGlyph: View {
    let model: CyRecoveryIndicatorModel?   // nil = loading
    var diameter: CGFloat = 76
    var showsCentre: Bool = true
    @Environment(\.cyTheme) private var theme
    var body: some View {
        ZStack {
            switch model?.state {
            case .some(.numericSample(let pct, _)):
                CyProgressRingGlyph(fraction: Double(pct) / 100, color: theme.ringRecovery, diameter: diameter)
                if showsCentre {
                    Text("\(pct)%").font(CyFont.metricSmall).foregroundStyle(theme.textPrimary).minimumScaleFactor(0.6).lineLimit(1).padding(.horizontal, 12)
                }
            case .some(.qualitative):
                Circle().strokeBorder(theme.ringRecovery.opacity(theme.id == .highContrast ? 1 : 0.75), lineWidth: 2.5 * theme.ringLineWidthScale).padding(3)
                if showsCentre { Image(systemName: "text.alignleft").font(.system(size: diameter * 0.22, weight: .semibold)).foregroundStyle(theme.ringRecovery) }
            case .some(.partial):
                CyProgressRingGlyph(fraction: nil, color: theme.ringRecovery, diameter: diameter)
                if showsCentre { Image(systemName: "circle.lefthalf.filled").font(.system(size: diameter * 0.22)).foregroundStyle(theme.textSecondary) }
            case .some(.awaiting):
                CyProgressRingGlyph(fraction: nil, color: theme.ringRecovery, diameter: diameter)
                if showsCentre { Image(systemName: "minus").font(.system(size: diameter * 0.22)).foregroundStyle(theme.textTertiary) }
            case .none:
                CyProgressRingGlyph(fraction: 0, color: theme.ringRecovery, diameter: diameter)
            }
        }
        .frame(width: diameter, height: diameter)
        .accessibilityHidden(true)
    }
}

// MARK: Indicator row

struct CyIndicatorText: Equatable {
    let line: String                 // caption under the title
    let spoken: String               // full VoiceOver value
    let centre: String               // what the centre shows (exposed to the interaction tests)
}

struct CyIndicatorRow: View {
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
            tile(id: "indicatorConsistency", title: "Consistency", info: consistencyText, big: big, action: onConsistency) {
                ZStack {
                    CyProgressRingGlyph(fraction: isLoading ? 0 : consistency?.fraction, color: theme.ringConsistency, diameter: big ? 56 : 76)
                    if isLoading { EmptyView() }
                    else if let c = consistency, c.fraction != nil {
                        if !big { Text(c.text).font(CyFont.metricSmall).foregroundStyle(theme.textPrimary).minimumScaleFactor(0.6).lineLimit(1).padding(.horizontal, 12) }
                    } else { Image(systemName: "minus").foregroundStyle(theme.textTertiary) }
                }
            }
            tile(id: "indicatorMix", title: "Training Mix", info: mixText, big: big, action: onMix) {
                CyMixRingGlyph(model: isLoading ? nil : mix, diameter: big ? 56 : 76, showsCentre: !big)
            }
            tile(id: "indicatorRecovery", title: "Recovery", info: recoveryText, big: big, action: onRecovery) {
                CyRecoveryGlyph(model: isLoading ? nil : recovery, diameter: big ? 56 : 76, showsCentre: !big)
            }
        }
    }

    private func tile<G: View>(id: String, title: String, info: CyIndicatorText, big: Bool, action: @escaping () -> Void, @ViewBuilder glyph: () -> G) -> some View {
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
        .accessibilityValue("\(info.centre). \(info.spoken)")
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Opens details")
        .accessibilityIdentifier(id)
    }

    private var consistencyText: CyIndicatorText {
        if isLoading { return CyIndicatorText(line: "Loading", spoken: "Loading", centre: "") }
        guard let c = consistency, c.fraction != nil else {
            let t = consistency?.caption ?? "No sessions yet"
            return CyIndicatorText(line: t, spoken: t, centre: "No value")
        }
        return CyIndicatorText(line: typeSize.isAccessibilitySize ? "\(c.text) · \(c.caption)" : c.caption, spoken: c.caption, centre: c.text)
    }
    private var mixText: CyIndicatorText {
        if isLoading { return CyIndicatorText(line: "Loading", spoken: "Loading", centre: "") }
        guard let m = mix else { return CyIndicatorText(line: "Nothing planned", spoken: "Nothing planned", centre: "No ratio") }
        let ratio = m.ratioText
        let spoken = "Endurance \(m.endurance.fraction == nil ? "not planned" : "\(m.endurance.done) of \(m.endurance.planned ?? "")"), strength \(m.strength.fraction == nil ? "not planned" : "\(m.strength.done) of \(m.strength.planned ?? "")")"
        let line: String
        if ratio == nil { line = m.hasAnyPlan ? "No training time yet" : "Nothing planned" }
        else if typeSize.isAccessibilitySize { line = "\(ratio ?? "") · ride : lift time" }
        else { line = "Ride : lift · time done" }
        return CyIndicatorText(line: line, spoken: "\(ratio.map { "Completed time ratio \($0), endurance to strength. " } ?? "No completed training time. ")\(spoken)", centre: ratio ?? "No ratio")
    }
    private var recoveryText: CyIndicatorText {
        if isLoading { return CyIndicatorText(line: "Loading", spoken: "Loading", centre: "") }
        guard let r = recovery else { return CyIndicatorText(line: "Awaiting data", spoken: "Awaiting data", centre: "No value") }
        switch r.state {
        case .numericSample(let pct, let w):
            return CyIndicatorText(line: typeSize.isAccessibilitySize ? "\(pct)% · sample score" : "Sample score", spoken: "\(w). Sample data, not a validated score", centre: "\(pct)%")
        case .qualitative(let w): return CyIndicatorText(line: w, spoken: "\(w). Status only, no score", centre: "Status only")
        case .partial(let w): return CyIndicatorText(line: w, spoken: "\(w). Some readings are missing", centre: "Partial")
        case .awaiting: return CyIndicatorText(line: "Awaiting data", spoken: "No readings yet", centre: "No value")
        }
    }
}

// MARK: Schedule (v2.2)

/// One session = one icon with a small state mark under it; no circles, so two sessions never overlap.
/// completed: coloured icon + filled dot · planned: muted icon + hollow dot · missed: muted icon + cross ·
/// rescheduled: muted icon + arrow. State is always a shape as well as a colour.
struct CySessionMark: View {
    let session: CyDaySession
    var size: CGFloat = 16
    @Environment(\.cyTheme) private var theme
    var body: some View {
        let c = session.category.color(theme)
        VStack(spacing: 3) {
            Image(systemName: session.category.icon)
                .font(.system(size: size, weight: session.state == .completed ? .semibold : .regular))
                .foregroundStyle(session.state == .completed ? c : theme.textSecondary)
                .frame(width: size + 4, height: size)
            Group {
                switch session.state {
                case .completed: Circle().fill(c).frame(width: 6, height: 6)
                case .planned: Circle().strokeBorder(theme.textSecondary, lineWidth: 1.2).frame(width: 6, height: 6)
                case .missed: Image(systemName: "xmark").font(.system(size: 8, weight: .heavy)).foregroundStyle(theme.warning)
                case .rescheduled: Image(systemName: "arrow.right").font(.system(size: 8, weight: .heavy)).foregroundStyle(theme.textSecondary)
                }
            }
            .frame(height: 8)
        }
        .accessibilityHidden(true)
    }
}

struct CyCompactSchedule: View {
    let days: [CyScheduleDay]
    var isLoading: Bool = false
    let onDay: (CyScheduleDay) -> Void
    @Environment(\.cyTheme) private var theme

    var body: some View {
        if isLoading {
            HStack(spacing: CySpace.xs) { ForEach(0..<7, id: \.self) { _ in CySkeleton(height: 54) } }
        } else if days.isEmpty {
            HStack(spacing: CySpace.s) {
                Image(systemName: "calendar").foregroundStyle(theme.textTertiary)
                Text("No sessions planned this week").font(CyFont.footnote).foregroundStyle(theme.textSecondary)
                Spacer(minLength: 0)
            }
            .frame(minHeight: CyHit.min)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("scheduleEmpty")
        } else {
            HStack(spacing: 0) { ForEach(days) { d in cell(d) } }
        }
    }

    private func cell(_ d: CyScheduleDay) -> some View {
        let two = d.sessions.count > 1
        return Button(action: { onDay(d) }) {
            VStack(spacing: 5) {
                Text(d.letter).font(.caption2.weight(d.isToday ? .bold : .medium)).foregroundStyle(d.isToday ? theme.accent : theme.textSecondary)
                HStack(spacing: two ? 5 : 0) {
                    if d.sessions.isEmpty {
                        VStack(spacing: 3) {
                            if d.isRest { Image(systemName: "moon").font(.system(size: 12)).foregroundStyle(theme.textTertiary).frame(height: 16) }
                            else { Capsule().fill(theme.textTertiary.opacity(0.5)).frame(width: 8, height: 2).frame(height: 16) }
                            Color.clear.frame(height: 8)
                        }
                    } else {
                        ForEach(d.sessions.prefix(2)) { s in CySessionMark(session: s, size: two ? 13 : 17) }
                    }
                }
            }
            .frame(maxWidth: .infinity, minHeight: 54)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(d.isToday ? theme.selectedFill : Color.clear).padding(.horizontal, 1))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(d.isToday && theme.id == .highContrast ? theme.accent : Color.clear, lineWidth: 1.5).padding(.horizontal, 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(CyRingButtonStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(d.weekday) \(d.date)\(d.isToday ? ", today" : "")")
        .accessibilityValue(d.sessions.isEmpty ? (d.isRest ? "Rest day" : "Nothing planned") : d.sessions.map { "\($0.title), \($0.state.label)" }.joined(separator: "; "))
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Opens the day")
        .accessibilityIdentifier("scheduleDay-\(d.id)")
    }
}

// MARK: Sleep bar (v2.2)

/// Three clearly separate quantities: LAST NIGHT (the big value and the bar's fill), 7-DAY AVERAGE, and TARGET with
/// its kind stated ("Your target", "Sample target"). The bar always means last night ÷ target. No sleep need is computed.
struct CySleepBar: View {
    let model: CySleepModel?         // nil = loading
    let onOpen: () -> Void
    @Environment(\.cyTheme) private var theme
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Image(systemName: "moon.stars.fill").font(.footnote).foregroundStyle(theme.ringRecovery)
                    Text("Sleep").font(CyFont.label).foregroundStyle(theme.textPrimary)
                    Text("last night").font(.caption2).foregroundStyle(theme.textSecondary)
                    Spacer(minLength: CySpace.s)
                    if let m = model {
                        if let last = m.lastNight { Text(CySleepModel.text(last)).font(CyFont.value).foregroundStyle(theme.textPrimary) }
                        else { Text("No record").font(CyFont.footnote).foregroundStyle(theme.textSecondary) }
                    } else { CySkeleton(height: 16, width: 70) }
                    Image(systemName: "chevron.right").font(.caption2.weight(.semibold)).foregroundStyle(theme.textTertiary)
                }
                if let m = model {
                    CyGradientBar(fraction: (m.lastNight != nil && (m.target ?? 0) > 0) ? Double(m.lastNight ?? 0) / Double(m.target ?? 1) : 0, color: theme.ringRecovery, height: 5)
                    let stats = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4)) : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: CySpace.s))
                    stats {
                        stat("7-day avg", m.average7.map(CySleepModel.text) ?? "—")
                        if !typeSize.isAccessibilitySize { Spacer(minLength: CySpace.s) }
                        if let t = m.target { stat(m.targetLabel, CySleepModel.text(t)) }
                        else { Text("Target not set · Set").font(CyFont.footnote.weight(.semibold)).foregroundStyle(theme.accent).lineLimit(1) }
                    }
                } else {
                    CySkeleton(height: 5); CySkeleton(height: 10, width: 200)
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
        .accessibilityHint(model?.target == nil ? "Opens sleep details, where you can set a target" : "Opens sleep details")
        .accessibilityIdentifier("sleepBar")
    }
    private func stat(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Text(label).font(CyFont.footnote).foregroundStyle(theme.textSecondary)
            Text(value).font(CyFont.footnote.weight(.semibold)).monospacedDigit().foregroundStyle(theme.textPrimary)
        }
        .lineLimit(1).minimumScaleFactor(0.85)
    }
    private var spoken: String {
        guard let m = model else { return "Loading" }
        let last = m.lastNight.map { "Last night \(CySleepModel.text($0))" } ?? "No sleep recorded"
        let avg = m.average7.map { "seven-day average \(CySleepModel.text($0))" } ?? "no seven-day average yet"
        let tgt = m.target.map { "\(m.targetLabel) \(CySleepModel.text($0))" } ?? "target not set"
        return "\(last), \(avg), \(tgt)"
    }
}

// MARK: Coach banner (v2.2)

/// Observation → Recommendation → Action. Review is the primary action when approval is needed; Not now postpones
/// (it is not a decline); Why? explains. Labelled rules-based — no generative model.
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
                Text("rules-based").font(.caption2).foregroundStyle(theme.textSecondary).lineLimit(1).fixedSize()
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .overlay(Capsule().strokeBorder(theme.textTertiary.opacity(0.6), lineWidth: 1))
                Spacer(minLength: 0)
                if model != nil && emptyText == nil && !typeSize.isAccessibilitySize { whyButton }
            }
            if let emptyText {
                Text(emptyText).font(CyFont.callout).foregroundStyle(theme.textSecondary).fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("coachEmpty")
            } else if let m = model {
                if let obs = m.observation, let rec = m.recommendation {
                    Text(obs).font(CyFont.footnote).foregroundStyle(theme.textSecondary).fixedSize(horizontal: false, vertical: true)
                    Text(rec).font(CyFont.headline).foregroundStyle(theme.textPrimary).fixedSize(horizontal: false, vertical: true)
                } else {
                    Text(m.sentence).font(CyFont.callout).foregroundStyle(theme.textPrimary).fixedSize(horizontal: false, vertical: true)
                }
                if let note = decisionNote {
                    Label(note.text, systemImage: note.icon).font(CyFont.caption).foregroundStyle(theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("coachDecisionNote")
                }
                if typeSize.isAccessibilitySize { whyButton }
                if m.hasProposal && (decision == .none || decision == .postponed) {
                    let actions = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: CySpace.s)) : AnyLayout(HStackLayout(spacing: CySpace.m))
                    actions {
                        Button(action: onReview) {
                            Text("Review").font(CyFont.headline).foregroundStyle(theme.textOnAccent)
                                .padding(.horizontal, CySpace.xl).frame(minHeight: CyHit.min)
                                .background(Capsule().fill(theme.accent))
                        }
                        .buttonStyle(CyRingButtonStyle())
                        .accessibilityIdentifier("coachReview")
                        if decision == .none {
                            Button(action: onNotNow) {
                                Text("Not now").font(CyFont.label).foregroundStyle(theme.textSecondary)
                                    .padding(.horizontal, CySpace.s).frame(minHeight: CyHit.min).contentShape(Rectangle())
                            }
                            .buttonStyle(CyRingButtonStyle())
                            .accessibilityHint("Postpones the suggestion. It is not declined.")
                            .accessibilityIdentifier("coachNotNow")
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
    private var whyButton: some View {
        Button(action: onWhy) {
            Label("Why?", systemImage: "info.circle").font(CyFont.caption).foregroundStyle(theme.accent).lineLimit(1).fixedSize()
                .frame(minWidth: CyHit.min, minHeight: CyHit.min, alignment: .trailing).contentShape(Rectangle())
        }
        .buttonStyle(CyRingButtonStyle())
        .accessibilityLabel("Why this suggestion")
        .accessibilityIdentifier("coachWhy")
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
