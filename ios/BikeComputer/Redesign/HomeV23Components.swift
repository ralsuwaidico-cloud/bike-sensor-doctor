import SwiftUI

// Home v2.3 — components. PROVISIONAL design (owner direction of 12 Nov 2026; not yet visually approved).
// Brought over from the UI Lab prototype (branch proto/ui-lab) as shared code for both apps, unchanged in layout:
// Components/HomeV21Components.swift, HomeV22Components.swift (without the superseded Coach banner),
// CoachConversation.swift (the compact Coach preview only), TrendsAndDock.swift (the Key metrics list only),
// Cards.swift and Rings.swift (the skeleton and the two button styles).
// Changes made for the app, and nothing else:
//  • colours come from the app's one token set through `CxTheme` (the prototype's own colour tables are not carried over);
//  • the Sleep bar offers "Set" only when a target can be set (`CySleepModel.canSetTarget`);
//  • the Coach preview takes its identifier, spoken prefix and hint from the host.
// Data in, callbacks out. No store, engine or navigation in this file.

extension CyCategory {
    func color(_ t: CxTheme) -> Color {
        switch self {
        case .endurance: return t.endurance
        case .strength: return t.strength
        case .recovery: return t.recovery
        case .rest: return t.textTertiary
        }
    }
}
extension CyStatusLevel {
    func color(_ t: CxTheme) -> Color {
        switch self {
        case .good: return t.success
        case .caution: return t.warning
        case .alert: return t.danger
        case .neutral: return t.textSecondary
        }
    }
}
extension CyGraphColor {
    func color(_ t: CxTheme) -> Color {
        switch self {
        case .endurance: return t.endurance
        case .strength: return t.strength
        case .recovery: return t.ringRecovery
        case .consistency: return t.ringConsistency
        case .load: return t.ringLoad
        case .neutral: return t.textSecondary
        }
    }
}

// MARK: Shared pieces

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

struct CyRingButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.7 : 1)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}


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
                        Text(m.title).font(HomeType.f(.cardTitle, CyFont.label)).foregroundStyle(theme.textSecondary)
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right").font(.caption2.weight(.semibold)).foregroundStyle(theme.textTertiary)
                    }
                    if let empty = m.emptyText {
                        Text(empty).font(HomeType.f(.cardPlanned, CyFont.footnote)).foregroundStyle(theme.textSecondary).fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    } else {
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text(m.done ?? "—").font(HomeType.f(.cardTotal, CyFont.value)).foregroundStyle(theme.textPrimary)
                            if let p = m.planned { Text("/ \(p)").font(HomeType.f(.cardPlanned, CyFont.footnote)).foregroundStyle(theme.textSecondary) }
                        }
                        .lineLimit(1).minimumScaleFactor(0.7)
                        CyGradientBar(fraction: m.fraction ?? 0, color: m.category.color(theme))
                        Text(m.secondary ?? " ").font(HomeType.f(.meta, .caption2)).foregroundStyle(HomeType.tone(theme.textSecondary, quiet: theme.textTertiary)).lineLimit(1).minimumScaleFactor(0.8)
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
        .accessibilityIdentifier("sportCard-\(model?.category == .strength ? "strength" : "endurance")")
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
                .accessibilityIdentifier("setupNext")
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
                .accessibilityIdentifier("setupComplete")
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
                    .font(HomeType.f(.ringValue, .system(size: diameter * 0.17, weight: .bold, design: .rounded))).monospacedDigit()
                    .foregroundStyle(m.ratioText == nil ? theme.textTertiary : theme.textPrimary)
                    .lineLimit(1).minimumScaleFactor(HomeType.isReview ? 0.5 : 0.7)       // review: the 23 pt target scales down to fit inside the inner ring, never truncates
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
                    Text("\(pct)%").font(HomeType.f(.ringValue, CyFont.metricSmall)).foregroundStyle(theme.textPrimary).minimumScaleFactor(0.6).lineLimit(1).padding(.horizontal, 12)
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
                        if !big { Text(c.text).font(HomeType.f(.ringValue, CyFont.metricSmall)).foregroundStyle(theme.textPrimary).minimumScaleFactor(0.6).lineLimit(1).padding(.horizontal, 12) }
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
                        Text(title).font(HomeType.f(.ringLabel, CyFont.caption)).foregroundStyle(theme.textPrimary).lineLimit(1).minimumScaleFactor(0.8)
                        Text(info.line).font(HomeType.f(.ringSupport, .caption2)).foregroundStyle(HomeType.tone(theme.textSecondary, quiet: theme.textTertiary)).multilineTextAlignment(.center)
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
                Text(d.letter).font(HomeType.f(d.isToday ? .weekdayToday : .weekday, .caption2.weight(d.isToday ? .bold : .medium))).foregroundStyle(d.isToday ? theme.accent : theme.textSecondary)
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
                    Text("Sleep").font(HomeType.f(.rowTitle, CyFont.label)).foregroundStyle(theme.textPrimary)
                    Text("last night").font(HomeType.f(.meta, .caption2)).foregroundStyle(HomeType.tone(theme.textSecondary, quiet: theme.textTertiary))
                    Spacer(minLength: CySpace.s)
                    if let m = model {
                        if let last = m.lastNight { Text(CySleepModel.text(last)).font(HomeType.f(.rowValue, CyFont.value)).foregroundStyle(theme.textPrimary) }
                        else { Text("No record").font(HomeType.f(.metaLarge, CyFont.footnote)).foregroundStyle(theme.textSecondary) }
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
                        else if m.canSetTarget { Text("Target not set · Set").font(HomeType.f(.metaStrong, CyFont.footnote.weight(.semibold))).foregroundStyle(theme.accent).lineLimit(1) }
                        else { Text("Target not set").font(HomeType.f(.metaLarge, CyFont.footnote)).foregroundStyle(HomeType.tone(theme.textSecondary, quiet: theme.textTertiary)).lineLimit(1) }
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
        .accessibilityHint(model?.target == nil && model?.canSetTarget == true ? "Opens sleep details, where you can set a target" : "Opens sleep details")
        .accessibilityIdentifier("sleepBar")
    }
    private func stat(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Text(label).font(HomeType.f(.metaLarge, CyFont.footnote)).foregroundStyle(HomeType.tone(theme.textSecondary, quiet: theme.textTertiary))
            Text(value).font(HomeType.f(.metaStrong, CyFont.footnote.weight(.semibold))).monospacedDigit().foregroundStyle(theme.textPrimary)
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

// MARK: Coach preview (v2.3)

/// Compact, text-only, tappable. No Review / Approve / Not now / Decline here — decisions live in the conversation's
/// proposal detail. About two lines of text; longer text is truncated.
struct CyCoachPreview: View {
    let model: CyCoachPreviewModel?  // nil while loading or when there is nothing to say
    var emptyText: String? = nil
    var isLoading: Bool = false
    /// App integration: the host names the element and may put a statement in front of the spoken label ("Demo, rule-based, not AI.").
    var identifier: String = "coachPreview"
    var spokenPrefix: String = ""
    var hint: String = "Opens the coach conversation"
    let onOpen: () -> Void
    @Environment(\.cyTheme) private var theme
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: CyRadius.m, style: .continuous)
        Button(action: onOpen) {
            HStack(alignment: .top, spacing: CySpace.m) {
                Image(systemName: "sparkles").font(.footnote.weight(.semibold)).foregroundStyle(theme.accent)
                    .frame(width: 22, height: 22)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text("Coach").font(HomeType.f(.rowTitle, CyFont.caption.weight(.semibold))).foregroundStyle(theme.textSecondary)
                        if model?.needsDecision == true && !isLoading {
                            Circle().fill(theme.accent).frame(width: 6, height: 6)
                            Text("Needs your decision").font(HomeType.f(.meta, .caption2)).foregroundStyle(theme.textSecondary).lineLimit(1)
                        }
                    }
                    if isLoading {
                        CySkeleton(); CySkeleton(width: 200)
                    } else {
                        Text(model?.text ?? emptyText ?? "Nothing to report yet.")
                            .font(HomeType.f(.coachText, CyFont.callout)).foregroundStyle(model == nil ? theme.textSecondary : theme.textPrimary)
                            .lineLimit(typeSize.isAccessibilitySize ? 4 : 2).truncationMode(.tail)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.caption2.weight(.semibold)).foregroundStyle(theme.textTertiary)
                    .padding(.top, 5)
                    .accessibilityHidden(true)
            }
            .padding(.vertical, CySpace.m)
            .padding(.horizontal, CySpace.m)
            .frame(maxWidth: .infinity, minHeight: CyHit.min, alignment: .leading)
            .background(shape.fill(theme.highlightSurface))
            .overlay(shape.strokeBorder(theme.id == .highContrast ? theme.border : Color.clear, lineWidth: theme.borderWidth))
            .contentShape(shape)
        }
        .buttonStyle(CyRingButtonStyle())
        .disabled(isLoading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spokenPrefix + "Coach")
        .accessibilityValue(isLoading ? "Loading" : ((model?.needsDecision == true ? "Needs your decision. " : "") + (model?.text ?? emptyText ?? "Nothing to report yet.")))
        .accessibilityAddTraits(.isButton)
        .accessibilityHint(hint)
        .accessibilityIdentifier(identifier)
    }
}

// MARK: Metrics dashboard

struct CyMetricGrid: View {
    let tiles: [CyHomeMetric]
    var isLoading: Bool = false
    var style: CyMetricStyle = .rows
    let onTile: (CyHomeMetric) -> Void
    @Environment(\.cyTheme) private var theme
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let cols = typeSize.isAccessibilitySize ? [GridItem(.flexible())] : [GridItem(.flexible(), spacing: CySpace.s), GridItem(.flexible(), spacing: CySpace.s)]
        VStack(alignment: .leading, spacing: CySpace.m) {
            Text("Key metrics").font(HomeType.f(.heading, CyFont.title)).foregroundStyle(theme.textPrimary).accessibilityAddTraits(.isHeader)
            if style == .rows { rows } else {
            LazyVGrid(columns: cols, spacing: CySpace.s) {
                if isLoading {
                    ForEach(0..<4, id: \.self) { _ in
                        VStack(alignment: .leading, spacing: 6) { CySkeleton(height: 10, width: 80); CySkeleton(height: 18, width: 70); CySkeleton(height: 8, width: 90) }
                            .padding(CySpace.m).frame(maxWidth: .infinity, alignment: .leading)
                            .background(RoundedRectangle(cornerRadius: CyRadius.m, style: .continuous).fill(theme.surface))
                    }
                } else {
                    ForEach(tiles) { t in tile(t) }
                }
            }
            }
        }
    }

    /// Dashboard rows: icon and name on the left, value on the right with the athlete's own comparison value beneath
    /// and a neutral direction marker. One grouped surface with hairlines instead of a border per row.
    private var rows: some View {
        VStack(spacing: 0) {
            if isLoading {
                ForEach(0..<4, id: \.self) { _ in
                    HStack { CySkeleton(height: 12, width: 130); Spacer(); CySkeleton(height: 18, width: 50) }.padding(.horizontal, CySpace.m).frame(minHeight: 54)
                }
            } else {
                ForEach(tiles) { t in
                    Button(action: { onTile(t) }) {
                        HStack(spacing: CySpace.m) {
                            Image(systemName: t.icon).font(.footnote.weight(.semibold)).foregroundStyle(theme.textSecondary).frame(width: 22)
                            Text(t.name.uppercased()).font(HomeType.f(.metricLabel, .caption.weight(.semibold))).tracking(0.7).foregroundStyle(HomeType.tone(theme.textPrimary, quiet: theme.textSecondary))
                                .lineLimit(typeSize.isAccessibilitySize ? 3 : 1).minimumScaleFactor(0.8)
                            Spacer(minLength: CySpace.s)
                            VStack(alignment: .trailing, spacing: 0) {
                                HStack(alignment: .firstTextBaseline, spacing: 3) {
                                    Text(t.value ?? "—").font(HomeType.f(.metricValue, CyFont.value)).foregroundStyle(t.value == nil ? theme.textTertiary : theme.textPrimary)
                                    if t.value != nil { Text(t.unit).font(HomeType.f(.meta, .caption2)).foregroundStyle(theme.textSecondary) }
                                }
                                Text(t.value == nil ? "No data" : (t.baseline ?? t.trend ?? " ")).font(HomeType.f(.meta, .caption2)).foregroundStyle(HomeType.tone(theme.textSecondary, quiet: theme.textTertiary))
                            }
                            .lineLimit(1)
                            Group {
                                if let sym = t.direction.symbol, t.value != nil {
                                    Image(systemName: sym).font(.system(size: t.direction == .flat ? 6 : 8)).foregroundStyle(theme.textSecondary)
                                } else { Color.clear }
                            }
                            .frame(width: 10)
                            Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold)).foregroundStyle(theme.textTertiary)
                        }
                        .padding(.horizontal, CySpace.m)
                        .frame(minHeight: 54)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(CyRingButtonStyle())
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(t.name)
                    .accessibilityValue(t.value.map { "\($0) \(t.unit)\(t.baseline.map { ", \($0)" } ?? "")\(t.direction == .none ? "" : ", \(t.direction.spoken)")" } ?? "No data")
                    .accessibilityAddTraits(.isButton)
                    .accessibilityHint("Opens details")
                    .accessibilityIdentifier("metricRow-\(t.id)")
                    if t.id != tiles.last?.id { Rectangle().fill(theme.separator.opacity(0.6)).frame(height: 0.5).padding(.leading, CySpace.m + 22 + CySpace.m) }
                }
            }
        }
        .background(RoundedRectangle(cornerRadius: CyRadius.m, style: .continuous).fill(theme.surface))
        .overlay(RoundedRectangle(cornerRadius: CyRadius.m, style: .continuous).strokeBorder(theme.cardStroke, lineWidth: theme.borderWidth))
    }

    private func tile(_ t: CyHomeMetric) -> some View {
        Button(action: { onTile(t) }) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: t.icon).font(.caption.weight(.semibold)).foregroundStyle(theme.textSecondary).frame(width: 16)
                    Text(t.name).font(.caption.weight(.medium)).foregroundStyle(theme.textSecondary).lineLimit(1).minimumScaleFactor(0.8)
                    Spacer(minLength: 0)
                }
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(t.value ?? "—").font(CyFont.value).foregroundStyle(t.value == nil ? theme.textTertiary : theme.textPrimary)
                    if t.value != nil { Text(t.unit).font(.caption2).foregroundStyle(theme.textSecondary) }
                }
                .lineLimit(1).minimumScaleFactor(0.7)
                Text(t.value == nil ? "No data" : (t.trend ?? " ")).font(.caption2)
                    .foregroundStyle(t.value == nil ? theme.textTertiary : t.trendLevel.color(theme)).lineLimit(1).minimumScaleFactor(0.8)
            }
            .padding(CySpace.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: CyRadius.m, style: .continuous).fill(theme.surface))
            .overlay(RoundedRectangle(cornerRadius: CyRadius.m, style: .continuous).strokeBorder(theme.cardStroke, lineWidth: theme.borderWidth))
        }
        .buttonStyle(CyCardButtonStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(t.name)
        .accessibilityValue(t.value.map { "\($0) \(t.unit)\(t.trend.map { ", \($0)" } ?? "")" } ?? "No data")
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Opens details")
    }
}
