import SwiftUI

// MARK: - Cyclift design system: small primitives (tags, buttons, chips, rows, controls, banners, empty states)
// Pure presentational: explicit inputs, no Store. Every value-bearing component takes a `SourceTag`.

/// Honesty tag badge: "● Measured".
struct CySourceTagBadge: View {
    let tag: SourceTag
    var body: some View {
        let c = CyTheme.tagColors(tag)
        HStack(spacing: 4) {
            Circle().fill(c.0).frame(width: 6, height: 6)
            Text(tag.label).font(CyType.captionSmall)
        }
        .foregroundStyle(c.0)
        .padding(.horizontal, 7).padding(.vertical, 4)
        .background(c.1, in: Capsule())
        .overlay(Capsule().stroke(c.0.opacity(tag == .unknown || tag == .needsData ? 0.6 : 0), style: StrokeStyle(lineWidth: 1, dash: [3, 2])))
        .accessibilityLabel(tag.label)
        .accessibilityIdentifier("tag-\(tag.rawValue)")
    }
}

/// Icon in a tinted rounded square (36 pt; `large` = 46 pt).
struct CyIconBox: View {
    let systemName: String
    var sport: CySport? = nil
    var large = false
    var body: some View {
        let id = sport.map { CyTheme.identity($0) }
        Image(systemName: systemName)
            .font(.system(size: large ? 20 : 16, weight: .semibold))
            .foregroundStyle(id?.tint ?? CyTheme.ink2)
            .frame(width: large ? 46 : 36, height: large ? 46 : 36)
            .background(id?.bg ?? CyTheme.card2, in: RoundedRectangle(cornerRadius: large ? 15 : 12, style: .continuous))
            .accessibilityHidden(true)
    }
}

/// Uppercase tracked caption ("THIS WEEK").
struct CyCaption: View {
    let text: String
    var color: Color = CyTheme.ink3
    var body: some View { Text(text.uppercased()).font(CyType.captionSmall).tracking(0.8).foregroundStyle(color) }
}

/// Primary action: full-width pill, ink on light / pale on dark, or sport-tinted.
struct CyPrimaryButton: View {
    let title: String
    var systemImage: String? = nil
    var sport: CySport? = nil
    var isEnabled = true
    let action: () -> Void
    var body: some View {
        let id = sport.map { CyTheme.identity($0) }
        Button(action: action) {
            HStack(spacing: 8) {
                if let s = systemImage { Image(systemName: s).font(.body.weight(.semibold)) }
                Text(title).font(CyType.bodyStrong)
            }
            .frame(maxWidth: .infinity, minHeight: 48)
            .foregroundStyle(id?.onTint ?? CyTheme.ctaInk)
            .background(id?.tint ?? CyTheme.cta, in: Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.45)
    }
}

/// Secondary action: card2 pill.
struct CySecondaryButton: View {
    let title: String
    var systemImage: String? = nil
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let s = systemImage { Image(systemName: s).font(.body.weight(.semibold)) }
                Text(title).font(CyType.bodyStrong)
            }
            .frame(maxWidth: .infinity, minHeight: 48)
            .foregroundStyle(CyTheme.ink)
            .background(CyTheme.card2, in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

/// Tertiary: text link with a chevron, 44 pt hit area.
struct CyTertiaryLink: View {
    let title: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 2) { Text(title).font(CyType.secondary); Image(systemName: "chevron.right").font(.caption.weight(.semibold)) }
                .foregroundStyle(CyTheme.ink2)
                .cyMinTap()
        }
        .buttonStyle(.plain)
    }
}

/// Multi-select chip; `star` marks the main goal.
struct CyChip: View {
    let title: String
    var systemImage: String? = nil
    var selected = false
    var sport: CySport? = nil
    var star = false
    let action: () -> Void
    var body: some View {
        let id = sport.map { CyTheme.identity($0) }
        let bg: Color = selected ? (id?.tint ?? CyTheme.ink) : CyTheme.card
        let fg: Color = selected ? (id?.onTint ?? CyTheme.canvas) : CyTheme.ink2
        Button(action: action) {
            HStack(spacing: 6) {
                if let s = systemImage { Image(systemName: s).font(.caption.weight(.semibold)) }
                Text(title).font(CyType.secondary.weight(.semibold))
                if star { Image(systemName: "star.fill").font(.caption2) }
            }
            .foregroundStyle(fg)
            .padding(.horizontal, 14)
            .frame(minHeight: CyTheme.minTap)
            .background(bg, in: Capsule())
            .overlay(Capsule().stroke(selected ? Color.clear : CyTheme.line, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityLabel(star ? "\(title), main goal" : title)
    }
}

/// Compact segmented control for 2–4 exclusive options: the selected option lifts as a white pill.
struct CySegmentedControl<T: Hashable>: View {
    let options: [(T, String)]
    @Binding var selection: T
    var body: some View {
        HStack(spacing: 2) {
            ForEach(Array(options.enumerated()), id: \.offset) { pair in
                let opt = pair.element
                let on = opt.0 == selection
                Button { selection = opt.0 } label: {
                    Text(opt.1)
                        .font(CyType.secondary.weight(.semibold))
                        .lineLimit(1).minimumScaleFactor(0.8)
                        .foregroundStyle(on ? CyTheme.ink : CyTheme.ink2)
                        .frame(maxWidth: .infinity, minHeight: 38)
                        .background(on ? CyTheme.card : Color.clear, in: Capsule())
                        .shadow(color: on ? Color.black.opacity(0.12) : .clear, radius: 2, y: 1)
                        .padding(.vertical, 3)     // hit area reaches 44 pt while the pill stays 38 pt
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(3)
        .background(CyTheme.card2, in: Capsule())
        .overlay(Capsule().stroke(CyTheme.line2, lineWidth: 1))
        .accessibilityElement(children: .contain)
    }
}

/// List row: icon tile, title, value, chevron. With `action` it is a button that opens a focused editor.
struct CyListRow: View {
    let title: String
    var value: String? = nil
    var systemImage: String? = nil
    var sport: CySport? = nil
    var action: (() -> Void)? = nil
    @Environment(\.dynamicTypeSize) private var type
    var body: some View {
        let content = Group {
            if type.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 12) { icon; Text(title).font(CyType.body).foregroundStyle(CyTheme.ink); Spacer(); chevron }
                    if let v = value { Text(v).font(CyType.secondary).foregroundStyle(CyTheme.ink2).padding(.leading, systemImage == nil ? 0 : 48) }
                }
            } else {
                HStack(spacing: 12) {
                    icon
                    Text(title).font(CyType.body).foregroundStyle(CyTheme.ink).lineLimit(2)
                    Spacer(minLength: 8)
                    if let v = value { Text(v).font(CyType.secondary).foregroundStyle(CyTheme.ink2).multilineTextAlignment(.trailing).lineLimit(2) }
                    chevron
                }
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
        .contentShape(Rectangle())
        Group {
            if let a = action {
                Button(action: a) { content }.buttonStyle(.plain)
            } else {
                content
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(value.map { "\(title), \($0)" } ?? title)
    }
    @ViewBuilder private var icon: some View { if let s = systemImage { CyIconBox(systemName: s, sport: sport) } }
    @ViewBuilder private var chevron: some View { if action != nil { Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(CyTheme.ink3).accessibilityHidden(true) } }
}

/// A group of rows in one card with hairlines between them.
struct CyRowGroup<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(spacing: 0) { content }
            .cyCard()
    }
}

struct CyDivider: View { var body: some View { Rectangle().fill(CyTheme.line2).frame(height: 1).padding(.leading, 14) } }

/// Compact stepper: − value + with 44 pt buttons.
struct CyStepper: View {
    let title: String
    @Binding var value: Double
    var step: Double = 1
    var range: ClosedRange<Double> = 0...1000
    var unit: String = ""
    var format: (Double) -> String = { v in v == v.rounded() ? String(Int(v)) : String(format: "%.1f", v) }
    var body: some View {
        HStack(spacing: 4) {
            button("minus", "Decrease \(title)") { value = max(range.lowerBound, value - step) }
            VStack(spacing: 0) {
                Text(format(value)).font(CyType.numeralSmall).monospacedDigit().foregroundStyle(CyTheme.ink)
                if !unit.isEmpty { Text(unit).font(CyType.captionSmall).foregroundStyle(CyTheme.ink3) }
            }
            .frame(maxWidth: .infinity)
            button("plus", "Increase \(title)") { value = min(range.upperBound, value + step) }
        }
        .padding(4)
        .background(CyTheme.card2, in: RoundedRectangle(cornerRadius: CyTheme.rField, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
        .accessibilityValue("\(format(value)) \(unit)")
    }
    private func button(_ icon: String, _ label: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.body.weight(.semibold)).foregroundStyle(CyTheme.ink)
                .frame(width: CyTheme.minTap, height: CyTheme.minTap)
                .background(CyTheme.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

/// Switch row: label + caption on the left, a 44 pt toggle on the right.
struct CySwitchRow: View {
    let title: String
    var caption: String? = nil
    @Binding var isOn: Bool
    var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(CyType.body).foregroundStyle(CyTheme.ink)
                if let c = caption { Text(c).font(CyType.secondary).foregroundStyle(CyTheme.ink2) }
            }
        }
        .tint(CyTheme.recovery.tint)
        .padding(.horizontal, 14).padding(.vertical, 8)
        .frame(minHeight: 56)
    }
}

/// Banner: info (lavender), warn (amber), bad (red), success (mint).
struct CyBanner: View {
    let kind: CyBannerKind
    let text: String
    var systemImage: String? = nil
    var body: some View {
        let (fg, bg): (Color, Color) = {
            switch kind {
            case .info: return (CyTheme.insight.tint, CyTheme.insight.bg)
            case .warn: return (CyTheme.warn, CyTheme.warnBg)
            case .bad: return (CyTheme.bad, CyTheme.badBg)
            case .success: return (CyTheme.recovery.tint, CyTheme.recovery.bg)
            }
        }()
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: systemImage ?? defaultIcon).font(.body.weight(.semibold)).accessibilityHidden(true)
            Text(text).font(CyType.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(fg)
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(bg, in: RoundedRectangle(cornerRadius: CyTheme.rField, style: .continuous))
        .accessibilityElement(children: .combine)
    }
    private var defaultIcon: String {
        switch kind { case .info: return "info.circle"; case .warn: return "exclamationmark.triangle"; case .bad: return "xmark.octagon"; case .success: return "checkmark.circle" }
    }
}

/// Offline banner (the ride keeps recording; sync waits).
struct CyOfflineBanner: View {
    var text = "Offline — recording continues on this phone; sync resumes when you're back online."
    var body: some View { CyBanner(kind: .warn, text: text, systemImage: "wifi.slash").accessibilityIdentifier("offlineBanner") }
}

/// Empty state: dashed card that says what is missing and what would unlock it.
struct CyEmptyState: View {
    var systemImage: String = "tray"
    let title: String
    var line: String? = nil
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: systemImage).font(.title2).foregroundStyle(CyTheme.ink3).accessibilityHidden(true)
            Text(title).font(CyType.bodyStrong).foregroundStyle(CyTheme.ink).multilineTextAlignment(.center)
            if let l = line { Text(l).font(CyType.secondary).foregroundStyle(CyTheme.ink2).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true) }
            if let t = actionTitle, let a = action { CySecondaryButton(title: t, action: a).padding(.top, 4) }
        }
        .frame(maxWidth: .infinity)
        .padding(16)
        .background(RoundedRectangle(cornerRadius: CyTheme.rCard, style: .continuous).stroke(CyTheme.line, style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])))
        .accessibilityElement(children: .combine)
    }
}

/// "Needs 2 more rides" state for a chart or metric that has a source but not enough data yet.
struct CyInsufficientDataState: View {
    let missing: Int
    let unit: String
    var detail: String? = nil
    var body: some View {
        VStack(spacing: 4) {
            Text(CyDesign.needsMoreText(missing: missing, unit: unit)).font(CyType.bodyStrong).foregroundStyle(CyTheme.ink)
            if let d = detail { Text(d).font(CyType.secondary).foregroundStyle(CyTheme.ink2).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true) }
            CySourceTagBadge(tag: .needsData)
        }
        .frame(maxWidth: .infinity)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: CyTheme.rField, style: .continuous).stroke(CyTheme.line, style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("insufficientData")
    }
}

/// Device state chip: Not connected · Paired · Connected · Receiving live data · Connection problem, plus a detail line.
struct CyDeviceStateBadge: View {
    let state: CyDeviceState
    var detail: String? = nil
    var body: some View {
        let fg: Color = {
            switch state {
            case .receiving, .connected: return CyTheme.recovery.tint
            case .paired: return CyTheme.cycling.tint
            case .notPaired: return CyTheme.ink2
            case .problem: return CyTheme.bad
            }
        }()
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 5) {
                Circle().fill(fg).frame(width: 7, height: 7)
                Text(state.label).font(CyType.captionSmall)
            }
            .foregroundStyle(fg)
            .padding(.horizontal, 9).padding(.vertical, 5)
            .background(CyTheme.card, in: Capsule())
            .overlay(Capsule().stroke(CyTheme.line2, lineWidth: 1))
            if let d = detail { Text(d).font(CyType.captionSmall).foregroundStyle(CyTheme.ink3) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(detail.map { "\(state.label), \($0)" } ?? state.label)
        .accessibilityIdentifier("deviceState-\(state.rawValue)")
    }
}
