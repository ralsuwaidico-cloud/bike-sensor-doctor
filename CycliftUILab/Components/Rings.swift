import SwiftUI

// Circular indicators: Consistency (a real ratio), Load Balance and Recovery (status words, never a score),
// generic progress, missing data and loading. One ring = one tappable control.

struct CyRing: View {
    let model: CyRingModel
    var diameter: CGFloat = 84
    var onTap: (() -> Void)? = nil
    @Environment(\.cyTheme) private var theme
    @Environment(\.dynamicTypeSize) private var typeSize

    private var lineWidth: CGFloat { max(6, diameter * 0.095) * theme.ringLineWidthScale }
    private var color: Color { model.kind.color(theme) }

    var body: some View {
        Button(action: { onTap?() }) {
            VStack(spacing: CySpace.s) {
                ZStack {
                    ring
                    centre
                        .padding(lineWidth + 4)
                }
                .frame(width: diameter, height: diameter)
                VStack(spacing: 2) {
                    Text(model.title).font(CyFont.caption).foregroundStyle(theme.textPrimary)
                        .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                    Text(captionText).font(.caption2).foregroundStyle(theme.textSecondary)
                        .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(CyRingButtonStyle())
        .disabled(onTap == nil)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(model.title)
        .accessibilityValue(a11yValue)
        .accessibilityAddTraits(onTap == nil ? [] : .isButton)
        .accessibilityHint(onTap == nil ? "" : "Shows how this is worked out")
    }

    @ViewBuilder private var ring: some View {
        switch model.display {
        case .fraction(let f, _, _):
            Circle().stroke(theme.ringTrack, lineWidth: lineWidth)
            arc(f)
        case .status(_, _, let fill):
            Circle().stroke(theme.ringTrack, lineWidth: lineWidth)
            arc(fill)
        case .missing:
            Circle().stroke(theme.textTertiary, style: StrokeStyle(lineWidth: max(2, lineWidth * 0.45), lineCap: .round, dash: [3, 7]))
        case .loading:
            Circle().stroke(theme.ringTrack, lineWidth: lineWidth)
        }
    }
    private func arc(_ f: Double) -> some View {
        Circle()
            .trim(from: 0, to: CGFloat(min(max(f, 0.001), 1)))
            .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
            .rotationEffect(.degrees(-90))
            .animation(.easeOut(duration: 0.5), value: f)
    }
    @ViewBuilder private var centre: some View {
        switch model.display {
        case .fraction(_, let text, _):
            Text(text).font(CyFont.metricSmall).foregroundStyle(theme.textPrimary).minimumScaleFactor(0.5).lineLimit(1)
        case .status(_, let level, _):
            Image(systemName: level.icon).font(.title3).foregroundStyle(level.color(theme))
        case .missing:
            Image(systemName: "questionmark").font(.headline).foregroundStyle(theme.textTertiary)
        case .loading:
            ProgressView().controlSize(.small)
        }
    }
    private var captionText: String {
        switch model.display {
        case .fraction(_, _, let caption): return caption
        case .status(let word, _, _): return word
        case .missing(let reason): return reason
        case .loading: return "Loading"
        }
    }
    private var a11yValue: String {
        switch model.display {
        case .fraction(_, let text, let caption): return "\(text), \(caption)"
        case .status(let word, _, _): return word
        case .missing(let reason): return reason
        case .loading: return "Loading"
        }
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

/// Three (or more) rings side by side; stacks vertically at accessibility text sizes so labels never truncate.
struct CyRingRow: View {
    let rings: [CyRingModel]
    let onTap: (CyRingModel) -> Void
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        if typeSize.isAccessibilitySize {
            VStack(spacing: CySpace.m) {
                ForEach(rings) { r in CyRingListRow(model: r) { onTap(r) } }
            }
        } else {
            HStack(alignment: .top, spacing: CySpace.s) {
                ForEach(rings) { r in CyRing(model: r, onTap: { onTap(r) }) }
            }
        }
    }
}

/// Accessibility-size layout of a ring: small ring on the left, full-width text on the right.
struct CyRingListRow: View {
    let model: CyRingModel
    let onTap: () -> Void
    @Environment(\.cyTheme) private var theme
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: CySpace.m) {
                CyRingGlyph(model: model, diameter: 52)
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.title).font(CyFont.headline).foregroundStyle(theme.textPrimary).fixedSize(horizontal: false, vertical: true)
                    Text(text).font(CyFont.callout).foregroundStyle(theme.textSecondary).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .frame(minHeight: CyHit.min)
            .contentShape(Rectangle())
        }
        .buttonStyle(CyRingButtonStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(model.title)
        .accessibilityValue(text)
        .accessibilityAddTraits(.isButton)
    }
    private var text: String {
        switch model.display {
        case .fraction(_, let t, let c): return "\(t) · \(c)"
        case .status(let w, _, _): return w
        case .missing(let r): return r
        case .loading: return "Loading"
        }
    }
}

/// The ring drawing alone (no label, not a control) — used in rows and detail sheets.
struct CyRingGlyph: View {
    let model: CyRingModel
    var diameter: CGFloat = 52
    @Environment(\.cyTheme) private var theme
    var body: some View {
        let lw = max(5, diameter * 0.11) * theme.ringLineWidthScale
        ZStack {
            switch model.display {
            case .fraction(let f, _, _):
                Circle().stroke(theme.ringTrack, lineWidth: lw)
                Circle().trim(from: 0, to: CGFloat(min(max(f, 0.001), 1))).stroke(model.kind.color(theme), style: StrokeStyle(lineWidth: lw, lineCap: .round)).rotationEffect(.degrees(-90))
            case .status(_, let level, let fill):
                Circle().stroke(theme.ringTrack, lineWidth: lw)
                Circle().trim(from: 0, to: CGFloat(min(max(fill, 0.001), 1))).stroke(model.kind.color(theme), style: StrokeStyle(lineWidth: lw, lineCap: .round)).rotationEffect(.degrees(-90))
                Image(systemName: level.icon).font(.footnote).foregroundStyle(level.color(theme))
            case .missing:
                Circle().stroke(theme.textTertiary, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, dash: [3, 6]))
                Image(systemName: "questionmark").font(.footnote).foregroundStyle(theme.textTertiary)
            case .loading:
                Circle().stroke(theme.ringTrack, lineWidth: lw)
            }
        }
        .frame(width: diameter, height: diameter)
        .accessibilityHidden(true)
    }
}
