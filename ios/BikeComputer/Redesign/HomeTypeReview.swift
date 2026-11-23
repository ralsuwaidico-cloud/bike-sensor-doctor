import SwiftUI

/// Home visual hierarchy refinement — owner's implementation brief of 23 Nov 2026 (08:57): Option A typography and six
/// hierarchy directions (minimal header, unified rings, connected day tiles, balanced activity cards, quiet Sleep and a
/// readable Coach card, one compact analytics area). PENDING THE OWNER'S VISUAL APPROVAL — not locked.
///
/// The refinement changes presentation only: no content, value, calculation, action, identifier or order. Until it is
/// approved the Home that existed before stays in the code, drawn when the launch setting `CY_HOME_STYLE=before` is
/// given, so the two can be captured side by side on identical data. That setting is used by the capture check only.
///
/// Typography: SF Pro through the system font (default design), sizes scaled with Dynamic Type, tabular figures for
/// numbers. The approved dock is not part of this: its typography and dimensions are unchanged.
enum HomeType {
    enum Role {
        case name, overline
        case ringValue, ringLabel, ringSupport
        case weekday, weekdayToday
        case cardTitle, cardTotal, cardPlanned
        case rowTitle, rowValue
        case coachText, status
        case heading
        case chartLabel, chartLabelStrong
        case metricLabel, metricValue
        case meta, metaLarge, metaStrong
        case segment, link
    }
    static let isRefined: Bool = ProcessInfo.processInfo.environment["CY_HOME_STYLE"] != "before"

    /// The font for a role. `before` is what the screen used until now and is returned untouched for the "before" capture.
    static func f(_ role: Role, _ before: Font) -> Font {
        guard isRefined else { return before }
        switch role {
        case .name: return CyDyn.f(28, .semibold)
        case .overline: return CyDyn.f(11, .medium)
        // The target is 23 pt. All three rings share one size so their values read as one family, and "100:0" has to
        // fit inside the Training Mix's inner ring without being scaled down on its own: 21 pt is the largest that does.
        case .ringValue: return CyDyn.f(21, .semibold).monospacedDigit()
        case .ringLabel: return CyDyn.f(12, .medium)
        case .ringSupport: return CyDyn.f(11, .regular)
        case .weekday: return CyDyn.f(11, .medium)
        case .weekdayToday: return CyDyn.f(11, .semibold)
        case .cardTitle: return CyDyn.f(15, .medium)
        case .cardTotal: return CyDyn.f(23, .semibold).monospacedDigit()
        case .cardPlanned: return CyDyn.f(13, .regular).monospacedDigit()
        case .rowTitle: return CyDyn.f(15, .medium)
        case .rowValue: return CyDyn.f(19, .semibold).monospacedDigit()
        case .coachText: return CyDyn.f(13, .regular)
        case .status: return CyDyn.f(11, .medium)
        case .heading: return CyDyn.f(19, .semibold)
        case .chartLabel: return CyDyn.f(11, .regular).monospacedDigit()
        case .chartLabelStrong: return CyDyn.f(11, .semibold).monospacedDigit()
        case .metricLabel: return CyDyn.f(12, .medium)
        case .metricValue: return CyDyn.f(19, .semibold).monospacedDigit()
        case .meta: return CyDyn.f(11, .regular).monospacedDigit()
        case .metaLarge: return CyDyn.f(12, .regular).monospacedDigit()
        case .metaStrong: return CyDyn.f(12, .medium).monospacedDigit()
        case .segment: return CyDyn.f(12, .medium)
        case .link: return CyDyn.f(12, .medium)
        }
    }
    /// A measure (spacing, size) that the refinement changes.
    static func v(_ refined: CGFloat, before: CGFloat) -> CGFloat { isRefined ? refined : before }
    /// A colour the refinement quiets — always one of the theme's own text colours.
    static func tone(_ before: Color, refined: Color) -> Color { isRefined ? refined : before }
}
