import SwiftUI

// Redesign foundation: the theme value and the spacing, radius and type scale that the redesigned screens read.
// Brought over from the UI Lab prototype (branch proto/ui-lab-plan, DesignSystem/Theme.swift) as SHARED code for both
// apps. `CxTheme` is the prototype's theme value under a new name (the app already has an enum called CyTheme); its
// colours come from the one token set. Screens read it from the environment (`\.cyTheme`), set by `cyThemeRoot`.
// Six approved themes (owner decision 10 Nov 2026). Theme ids are stable strings for a later Watch mapping.
// Every colour below is checked by tools/contrast_check.py (WCAG 2.1 contrast ratios).

struct CxTheme {
    let id: CyThemeID
    let isDark: Bool
    // Backgrounds and surfaces
    let background: Color
    let surface: Color
    let surface2: Color
    // Text
    let textPrimary: Color
    let textSecondary: Color
    let textTertiary: Color
    let textOnAccent: Color
    // Borders
    let border: Color
    let borderWidth: CGFloat
    // Accent (interactive)
    let accent: Color
    // Training categories (meaning is constant across themes: endurance = blue family, strength = amber family,
    // recovery = green family; each is always paired with an icon and a label, never colour alone)
    let endurance: Color
    let strength: Color
    let recovery: Color
    // Status (constant meaning: success green, warning amber, danger red; always paired with an icon or a word)
    let success: Color
    let warning: Color
    let danger: Color
    // Rings (identity hues constant across themes: consistency = teal, load balance = amber, recovery = violet)
    let ringConsistency: Color
    let ringLoad: Color
    let ringRecovery: Color
    // Derived tokens
    var separator: Color { border.opacity(isDark ? 0.7 : 0.8) }
    var ringTrack: Color { textPrimary.opacity(id == .highContrast ? 0.35 : 0.12) }
    var chartGrid: Color { textPrimary.opacity(id == .highContrast ? 0.45 : 0.10) }
    var chartAxis: Color { textSecondary }
    var accentSubtle: Color { accent.opacity(isDark ? 0.18 : 0.12) }
    var pressedOverlay: Color { textPrimary.opacity(0.10) }
    var disabledFill: Color { textPrimary.opacity(id == .highContrast ? 0.22 : 0.08) }
    var disabledText: Color { textPrimary.opacity(id == .highContrast ? 0.60 : 0.38) }
    var selectedFill: Color { accent.opacity(isDark ? 0.20 : 0.12) }
    var selectedBorder: Color { accent }
    var ringLineWidthScale: CGFloat { id == .highContrast ? 1.25 : 1.0 }

    // v2.1 — gradients and quieter surfaces. Every gradient is derived from an existing, contrast-checked token
    // (no new colour values), and High Contrast stays flat: legibility before decoration.
    var usesGradients: Bool { id != .highContrast }
    /// Card outline: none on dark themes (the surface step is enough), a hairline on light themes, full border in High Contrast.
    var cardStroke: Color { id == .highContrast ? border : (isDark ? Color.clear : border.opacity(0.55)) }
    /// Two-stop fill for bars, primary emphasis and selected states.
    func gradient(_ c: Color) -> LinearGradient {
        LinearGradient(colors: usesGradients ? [c, c.opacity(0.68)] : [c, c], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
    /// Sweep for a progress ring: lighter at the start of the arc, full colour at its head.
    func ringGradient(_ c: Color, fraction: Double) -> AngularGradient {
        AngularGradient(gradient: Gradient(colors: usesGradients ? [c.opacity(0.45), c] : [c, c]), center: .center,
                        startAngle: .degrees(0), endAngle: .degrees(360 * max(fraction, 0.02)))
    }
    /// Soft highlighted surface (coach card, navigation highlight).
    var highlightSurface: LinearGradient {
        LinearGradient(colors: usesGradients ? [accent.opacity(isDark ? 0.20 : 0.12), surface] : [surface, surface], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
    var scheme: ColorScheme { isDark ? .dark : .light }

    /// Built from the ONE token set (DesignSystem/ThemeTokens.swift). The prototype's own six colour tables are not
    /// carried over: there is a single source of colour values for the whole app.
    static func from(_ k: CyThemeTokens) -> CxTheme {
        func c(_ v: CyRGBA) -> Color { Color(cyRGBA: v) }
        return CxTheme(id: k.id, isDark: k.id.isDark, background: c(k.background), surface: c(k.surface), surface2: c(k.surfaceRaised),
                       textPrimary: c(k.textPrimary), textSecondary: c(k.textSecondary), textTertiary: c(k.textTertiary),
                       textOnAccent: c(k.shades(of: k.accent).onTint), border: c(k.border), borderWidth: CGFloat(k.borderWidth), accent: c(k.accent),
                       endurance: c(k.endurance), strength: c(k.strength), recovery: c(k.recovery), success: c(k.success), warning: c(k.warning), danger: c(k.danger),
                       ringConsistency: c(k.ringConsistency), ringLoad: c(k.ringLoad), ringRecovery: c(k.ringRecovery))
    }
}

private struct CxThemeKey: EnvironmentKey { static let defaultValue = CxTheme.from(CyThemeTokens.tokens(for: .newAthleteDefault)) }
extension EnvironmentValues {
    var cyTheme: CxTheme {
        get { self[CxThemeKey.self] }
        set { self[CxThemeKey.self] = newValue }
    }
}

// Spacing, radius and type scale. Type uses the system text styles so Dynamic Type applies everywhere.
enum CySpace {
    static let xs: CGFloat = 4
    static let s: CGFloat = 8
    static let m: CGFloat = 12
    static let l: CGFloat = 16
    static let xl: CGFloat = 24
}
enum CyRadius {
    static let s: CGFloat = 10
    static let m: CGFloat = 16
    static let l: CGFloat = 22
}
enum CyFont {
    static let display = Font.system(.title, design: .rounded).weight(.bold)
    static let name = Font.system(.title2, design: .rounded).weight(.semibold)          // v2.1 compact header
    static let value = Font.system(.title3, design: .rounded).weight(.semibold).monospacedDigit()
    static let label = Font.system(.subheadline).weight(.medium)
    static let title = Font.system(.title3, design: .rounded).weight(.semibold)
    static let headline = Font.system(.headline, design: .rounded)
    static let body = Font.system(.body)
    static let callout = Font.system(.callout)
    static let footnote = Font.system(.footnote)
    static let caption = Font.system(.caption).weight(.medium)
    static let overline = Font.system(.caption2).weight(.semibold)
    static let metric = Font.system(.title2, design: .rounded).weight(.bold).monospacedDigit()
    static let metricSmall = Font.system(.headline, design: .rounded).weight(.bold).monospacedDigit()
}
enum CyHit { static let min: CGFloat = 44 }
