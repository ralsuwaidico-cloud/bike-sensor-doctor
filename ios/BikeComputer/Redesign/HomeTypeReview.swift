import SwiftUI

/// REVIEW ONLY — two typography options for the Home screen, prepared for the owner's selection (23 Nov 2026).
///
/// Nothing here is the permanent design. Without the launch setting `CY_HOME_TYPE_REVIEW` (set only by the capture
/// check) every call returns the font and colour the screen already used, so Home is unchanged. With "A" or "B" the
/// same text is drawn in SF Pro (the system font, default design) at the owner's target hierarchy:
///   A — Refined: the target sizes and weights; colours as today.
///   B — Premium Minimal: the same sizes for the primary values; labels lighter, supporting text at the small end of
///       its range and in the quieter of the existing text colours.
/// Sizes scale with Dynamic Type. No content, colour token, layout, chart or navigation is changed by either option.
enum HomeType {
    enum Option { case current, refined, minimal }
    enum Role {
        case name, overline
        case ringValue, ringLabel, ringSupport
        case weekday, weekdayToday
        case cardTitle, cardTotal, cardPlanned
        case rowTitle, rowValue
        case coachText
        case heading
        case chartLabel, chartLabelStrong
        case metricLabel, metricValue
        case meta, metaLarge, metaStrong
        case segment, link, dock, dockSelected
    }
    static let option: Option = {
        switch ProcessInfo.processInfo.environment["CY_HOME_TYPE_REVIEW"] {
        case "A": return .refined
        case "B": return .minimal
        default: return .current
        }
    }()
    static var isReview: Bool { option != .current }

    /// The font for a role. `current` is what the screen uses today and is returned untouched outside the review.
    static func f(_ role: Role, _ current: Font) -> Font {
        guard option != .current else { return current }
        let b = option == .minimal
        switch role {
        case .name: return CyDyn.f(28, .semibold)
        case .overline: return CyDyn.f(11, .medium)
        case .ringValue: return CyDyn.f(23, .semibold).monospacedDigit()
        case .ringLabel: return CyDyn.f(12, .medium)
        case .ringSupport: return CyDyn.f(b ? 10 : 11, .regular)
        case .weekday: return CyDyn.f(11, b ? .regular : .medium)
        case .weekdayToday: return CyDyn.f(11, b ? .medium : .semibold)
        case .cardTitle: return CyDyn.f(15, b ? .regular : .medium)
        case .cardTotal: return CyDyn.f(23, .semibold).monospacedDigit()
        case .cardPlanned: return CyDyn.f(b ? 12 : 13, .regular).monospacedDigit()
        case .rowTitle: return CyDyn.f(15, b ? .regular : .medium)
        case .rowValue: return CyDyn.f(19, .semibold).monospacedDigit()
        case .coachText: return CyDyn.f(13, .regular)
        case .heading: return CyDyn.f(19, .semibold)
        case .chartLabel: return CyDyn.f(11, .regular).monospacedDigit()
        case .chartLabelStrong: return CyDyn.f(11, b ? .medium : .semibold).monospacedDigit()
        case .metricLabel: return CyDyn.f(12, b ? .regular : .medium)
        case .metricValue: return CyDyn.f(19, .semibold).monospacedDigit()
        case .meta: return CyDyn.f(11, .regular).monospacedDigit()
        case .metaLarge: return CyDyn.f(b ? 11 : 12, .regular).monospacedDigit()
        case .metaStrong: return CyDyn.f(b ? 11 : 12, .medium).monospacedDigit()
        case .segment: return CyDyn.f(12, b ? .regular : .medium)
        case .link: return CyDyn.f(12, .medium)
        case .dock: return .system(size: 11, weight: .medium)
        case .dockSelected: return .system(size: 11, weight: b ? .medium : .semibold)
        }
    }
    /// The colour for supporting text: today's colour, or — in option B only — the quieter existing text colour.
    static func tone(_ current: Color, quiet: Color) -> Color { option == .minimal ? quiet : current }
}
