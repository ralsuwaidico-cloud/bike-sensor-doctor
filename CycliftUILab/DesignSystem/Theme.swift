import SwiftUI

// Cyclift UI Lab — design tokens. PROTOTYPE ONLY: not part of the production app.
// Six approved themes (owner decision 10 Nov 2026). Theme ids are stable strings for a later Watch mapping.
// Every colour below is checked by tools/contrast_check.py (WCAG 2.1 contrast ratios).

enum CyThemeID: String, CaseIterable, Identifiable {
    case obsidian, arctic, ocean, forest, sandstone, highContrast
    var id: String { rawValue }
    var title: String {
        switch self {
        case .obsidian: return "Obsidian"
        case .arctic: return "Arctic"
        case .ocean: return "Ocean"
        case .forest: return "Forest"
        case .sandstone: return "Sandstone"
        case .highContrast: return "High Contrast"
        }
    }
}

struct CyTheme {
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
    var scheme: ColorScheme { isDark ? .dark : .light }

    static func named(_ id: CyThemeID) -> CyTheme {
        switch id {
        case .obsidian: return obsidian
        case .arctic: return arctic
        case .ocean: return ocean
        case .forest: return forest
        case .sandstone: return sandstone
        case .highContrast: return highContrast
        }
    }

    // TOKENS-BEGIN (parsed by tools/contrast_check.py — keep one token per line)
    static let obsidian = CyTheme(
        id: .obsidian, isDark: true,
        background: Color(hex: 0x0B0D10),
        surface: Color(hex: 0x15181D),
        surface2: Color(hex: 0x1F242B),
        textPrimary: Color(hex: 0xF2F4F7),
        textSecondary: Color(hex: 0xA9B0BB),
        textTertiary: Color(hex: 0x8A93A0),
        textOnAccent: Color(hex: 0x0B0D10),
        border: Color(hex: 0x2E343D), borderWidth: 1,
        accent: Color(hex: 0x9CC2EE),
        endurance: Color(hex: 0x58C4F6),
        strength: Color(hex: 0xFFB25B),
        recovery: Color(hex: 0x7EDC9A),
        success: Color(hex: 0x5BD68A),
        warning: Color(hex: 0xF5C04A),
        danger: Color(hex: 0xFF8077),
        ringConsistency: Color(hex: 0x5FD3C4),
        ringLoad: Color(hex: 0xF5B85C),
        ringRecovery: Color(hex: 0xA99BFF))
    static let arctic = CyTheme(
        id: .arctic, isDark: false,
        background: Color(hex: 0xF3F6FA),
        surface: Color(hex: 0xFFFFFF),
        surface2: Color(hex: 0xE9EEF4),
        textPrimary: Color(hex: 0x111820),
        textSecondary: Color(hex: 0x465261),
        textTertiary: Color(hex: 0x5D6978),
        textOnAccent: Color(hex: 0xFFFFFF),
        border: Color(hex: 0xD3DBE5), borderWidth: 1,
        accent: Color(hex: 0x1B63C2),
        endurance: Color(hex: 0x0A6FA8),
        strength: Color(hex: 0xA35400),
        recovery: Color(hex: 0x1A7F45),
        success: Color(hex: 0x1A7F45),
        warning: Color(hex: 0x8F5F00),
        danger: Color(hex: 0xC2302A),
        ringConsistency: Color(hex: 0x0B7F74),
        ringLoad: Color(hex: 0xA35F00),
        ringRecovery: Color(hex: 0x5F4BD0))
    static let ocean = CyTheme(
        id: .ocean, isDark: true,
        background: Color(hex: 0x071726),
        surface: Color(hex: 0x0E2236),
        surface2: Color(hex: 0x17304A),
        textPrimary: Color(hex: 0xEAF3FB),
        textSecondary: Color(hex: 0xA3B9CC),
        textTertiary: Color(hex: 0x8AA2B8),
        textOnAccent: Color(hex: 0x04202A),
        border: Color(hex: 0x27496A), borderWidth: 1,
        accent: Color(hex: 0x48D6CF),
        endurance: Color(hex: 0x6CCBFA),
        strength: Color(hex: 0xFFB866),
        recovery: Color(hex: 0x86E0A4),
        success: Color(hex: 0x66DB95),
        warning: Color(hex: 0xF7C75A),
        danger: Color(hex: 0xFF8C84),
        ringConsistency: Color(hex: 0x5FD9CB),
        ringLoad: Color(hex: 0xF7BE68),
        ringRecovery: Color(hex: 0xB0A4FF))
    static let forest = CyTheme(
        id: .forest, isDark: true,
        background: Color(hex: 0x0C1512),
        surface: Color(hex: 0x14201B),
        surface2: Color(hex: 0x1D2D26),
        textPrimary: Color(hex: 0xEEF5F0),
        textSecondary: Color(hex: 0xA8BBAF),
        textTertiary: Color(hex: 0x8CA195),
        textOnAccent: Color(hex: 0x0C1512),
        border: Color(hex: 0x2D4238), borderWidth: 1,
        accent: Color(hex: 0x9AD6A8),
        endurance: Color(hex: 0x6CC6F2),
        strength: Color(hex: 0xF9B466),
        recovery: Color(hex: 0x86DDA0),
        success: Color(hex: 0x6BD893),
        warning: Color(hex: 0xF2C458),
        danger: Color(hex: 0xFF8A80),
        ringConsistency: Color(hex: 0x62D2C3),
        ringLoad: Color(hex: 0xF2B962),
        ringRecovery: Color(hex: 0xADA0FF))
    static let sandstone = CyTheme(
        id: .sandstone, isDark: false,
        background: Color(hex: 0xF5F0E8),
        surface: Color(hex: 0xFFFDF9),
        surface2: Color(hex: 0xECE4D8),
        textPrimary: Color(hex: 0x221C16),
        textSecondary: Color(hex: 0x574C40),
        textTertiary: Color(hex: 0x6B5F52),
        textOnAccent: Color(hex: 0xFFFFFF),
        border: Color(hex: 0xDBCFBF), borderWidth: 1,
        accent: Color(hex: 0xA6482A),
        endurance: Color(hex: 0x0F6C9C),
        strength: Color(hex: 0x9C5300),
        recovery: Color(hex: 0x24773F),
        success: Color(hex: 0x24773F),
        warning: Color(hex: 0x855B00),
        danger: Color(hex: 0xB93026),
        ringConsistency: Color(hex: 0x0F7A70),
        ringLoad: Color(hex: 0x9C5C00),
        ringRecovery: Color(hex: 0x5B49C4))
    static let highContrast = CyTheme(
        id: .highContrast, isDark: true,
        background: Color(hex: 0x000000),
        surface: Color(hex: 0x000000),
        surface2: Color(hex: 0x1C1C1E),
        textPrimary: Color(hex: 0xFFFFFF),
        textSecondary: Color(hex: 0xE5E5EA),
        textTertiary: Color(hex: 0xC7C7CC),
        textOnAccent: Color(hex: 0x000000),
        border: Color(hex: 0xFFFFFF), borderWidth: 1.5,
        accent: Color(hex: 0xFFD60A),
        endurance: Color(hex: 0x64D2FF),
        strength: Color(hex: 0xFF9F0A),
        recovery: Color(hex: 0x30D158),
        success: Color(hex: 0x30D158),
        warning: Color(hex: 0xFFD60A),
        danger: Color(hex: 0xFF6961),
        ringConsistency: Color(hex: 0x66E5D6),
        ringLoad: Color(hex: 0xFFB340),
        ringRecovery: Color(hex: 0xBFB5FF))
    // TOKENS-END
}

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: 1)
    }
}

private struct CyThemeKey: EnvironmentKey { static let defaultValue = CyTheme.obsidian }
extension EnvironmentValues {
    var cyTheme: CyTheme {
        get { self[CyThemeKey.self] }
        set { self[CyThemeKey.self] = newValue }
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
