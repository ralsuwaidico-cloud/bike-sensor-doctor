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
