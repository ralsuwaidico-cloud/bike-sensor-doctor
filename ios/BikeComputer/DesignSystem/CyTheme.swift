import SwiftUI

// MARK: - Cyclift design system: tokens (visual system v3, ios/DESIGN_SYSTEM.md)
//
// Two deliberate palettes. Light: warm grey canvas, white cards, sport pastels. Dark: deep slate canvas, lighter slate
// cards, desaturated and lifted accents — never inverted, never flat black. Every text/background pair below passes
// WCAG AA (checked in the v3 prototype with the same hex values).

enum CyTheme {
    // ---- canvas and text
    static let canvas = Color(cyLight: 0xF4F1EC, dark: 0x151A21)
    static let card = Color(cyLight: 0xFFFFFF, dark: 0x1E242C)
    static let card2 = Color(cyLight: 0xF8F6F2, dark: 0x252C35)
    static let line = Color(cyLight: 0xE7E2DA, dark: 0x2F3741)
    static let line2 = Color(cyLight: 0xEFEBE5, dark: 0x28303A)
    static let ink = Color(cyLight: 0x1F2328, dark: 0xEEF1F4)
    static let ink2 = Color(cyLight: 0x5A6068, dark: 0xAEB6C0)
    static let ink3 = Color(cyLight: 0x6E747C, dark: 0x8C95A0)

    // ---- sport identities (tint = text/icon on the soft fill, bg = soft fill, mid/soft = chart shades)
    struct Identity {
        let tint: Color
        let bg: Color
        let mid: Color
        let soft: Color
        /// Text drawn on the solid tint (buttons, selected chips).
        let onTint: Color
    }
    static let cycling = Identity(tint: Color(cyLight: 0x3550B5, dark: 0xA9BAF5), bg: Color(cyLight: 0xE4EAFC, dark: 0x232B42),
                                  mid: Color(cyLight: 0x8FA3EA, dark: 0x7088D8), soft: Color(cyLight: 0xC9D4F7, dark: 0x33406A),
                                  onTint: Color(cyLight: 0xFFFFFF, dark: 0x151A21))
    static let strength = Identity(tint: Color(cyLight: 0xA3324F, dark: 0xF2A9BB), bg: Color(cyLight: 0xFCE5EA, dark: 0x3A2430),
                                   mid: Color(cyLight: 0xE58FA5, dark: 0xC9708A), soft: Color(cyLight: 0xF5C6D2, dark: 0x5A3242),
                                   onTint: Color(cyLight: 0xFFFFFF, dark: 0x151A21))
    static let recovery = Identity(tint: Color(cyLight: 0x1C6B4E, dark: 0x8FD8B5), bg: Color(cyLight: 0xDCF2E7, dark: 0x1C3329),
                                   mid: Color(cyLight: 0x7FCBA6, dark: 0x4FA67F), soft: Color(cyLight: 0xBFE6D1, dark: 0x2A4E3E),
                                   onTint: Color(cyLight: 0xFFFFFF, dark: 0x151A21))
    static let goal = Identity(tint: Color(cyLight: 0x855400, dark: 0xF3D088), bg: Color(cyLight: 0xFDF1D3, dark: 0x3A3122),
                               mid: Color(cyLight: 0xF0BE55, dark: 0xC99A3C), soft: Color(cyLight: 0xF8DFA2, dark: 0x594A2C),
                               onTint: Color(cyLight: 0xFFFFFF, dark: 0x151A21))
    static let insight = Identity(tint: Color(cyLight: 0x5A44A8, dark: 0xC7B9F4), bg: Color(cyLight: 0xECE7FB, dark: 0x2C2742),
                                  mid: Color(cyLight: 0xA996E6, dark: 0x8C77D6), soft: Color(cyLight: 0xD9CFF8, dark: 0x3F3860),
                                  onTint: Color(cyLight: 0xFFFFFF, dark: 0x151A21))
    static func identity(_ s: CySport) -> Identity {
        switch s {
        case .cycling: return cycling
        case .strength: return strength
        case .recovery: return recovery
        case .goal: return goal
        case .insight: return insight
        }
    }

    // ---- status
    static let warn = Color(cyLight: 0x9A4B00, dark: 0xF5B97A)
    static let warnBg = Color(cyLight: 0xFFE9D6, dark: 0x3A2A1A)
    static let bad = Color(cyLight: 0xB42318, dark: 0xF59A90)
    static let badBg = Color(cyLight: 0xFDE4E1, dark: 0x3D2020)
    static let ok = recovery.tint

    // ---- navigation and primary action
    static let nav = Color(cyLight: 0x1F2328, dark: 0x2A313B)
    static let navInk = Color(cyLight: 0xB9BEC5, dark: 0x9AA3AE)
    static let navOn = Color.white
    static let cta = Color(cyLight: 0x1F2328, dark: 0xEEF1F4)
    static let ctaInk = Color(cyLight: 0xFFFFFF, dark: 0x151A21)

    // ---- honesty tags (text, background)
    static func tagColors(_ t: SourceTag) -> (Color, Color) {
        switch t {
        case .measured: return (recovery.tint, recovery.bg)
        case .logged: return (cycling.tint, cycling.bg)
        case .estimated: return (goal.tint, goal.bg)
        case .unknown: return (ink2, card2)
        case .needsData: return (insight.tint, insight.bg)
        }
    }

    // ---- spacing scale (pt)
    static let sp1: CGFloat = 4
    static let sp2: CGFloat = 8
    static let sp3: CGFloat = 12
    static let sp4: CGFloat = 16
    static let sp5: CGFloat = 20
    static let sp6: CGFloat = 24
    /// Screen margins and the widest content column.
    static let margin: CGFloat = 16
    static let maxContentWidth: CGFloat = 430

    // ---- radii
    static let rHero: CGFloat = 28
    static let rCard: CGFloat = 22
    static let rField: CGFloat = 16
    static let rChip: CGFloat = 12

    // ---- touch
    static let minTap: CGFloat = 44
    /// Checkpoint C correction (owner 6 Nov, B2): bottom padding every scroll page keeps so its last card can be scrolled
    /// fully above the floating Liquid Dock (dock 64 + 20 above the home indicator + the raised centre button + breathing room).
    static let dockClearance: CGFloat = 128

    // ---- motion (seconds); every animation goes through `CyMotion.animation` so reduce-motion turns them all off
    static let motionRise = 0.32
    static let motionSheet = 0.26
    static let motionPop = 0.36
    static let motionFill = 0.5
}

/// Typography: iOS text styles so everything follows Dynamic Type; numerals are rounded and tabular.
enum CyType {
    /// Large numerals in tiles and rings (title-sized at the default setting, scales with the user's size).
    static let numeral = Font.system(.title, design: .rounded).weight(.bold)
    static let numeralLarge = Font.system(.largeTitle, design: .rounded).weight(.bold)
    static let numeralSmall = Font.system(.title3, design: .rounded).weight(.bold)
    /// Tab roots only.
    static let largeTitle = Font.system(.title).weight(.bold)
    static let title = Font.system(.title3).weight(.bold)
    static let section = Font.system(.headline).weight(.semibold)
    static let body = Font.system(.body)
    static let bodyStrong = Font.system(.body).weight(.semibold)
    static let secondary = Font.system(.subheadline)
    static let caption = Font.system(.caption).weight(.bold)
    static let captionSmall = Font.system(.caption2).weight(.bold)
    static let unit = Font.system(.subheadline).weight(.semibold)
}

enum CyMotion {
    /// The one animation the system uses; nil when the person has Reduce Motion on.
    static func animation(_ duration: Double, reduce: Bool) -> Animation? {
        reduce ? nil : .easeOut(duration: duration)
    }
}

extension Color {
    /// Hex tokens for the two palettes.
    init(cyLight: UInt32, dark: UInt32) {
        self.init(light: Color(cyHex: cyLight), dark: Color(cyHex: dark))
    }
    init(cyHex h: UInt32) {
        self.init(red: Double((h >> 16) & 0xFF) / 255, green: Double((h >> 8) & 0xFF) / 255, blue: Double(h & 0xFF) / 255)
    }
}

/// Card surface with the system's radius and the light theme's single soft shadow (none for tinted cards).
struct CyCardStyle: ViewModifier {
    var tinted: Color? = nil
    var radius: CGFloat = CyTheme.rCard
    @Environment(\.colorScheme) private var scheme
    func body(content: Content) -> some View {
        content
            .background(tinted ?? CyTheme.card, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .shadow(color: (tinted == nil && scheme == .light) ? Color.black.opacity(0.06) : .clear, radius: 10, y: 4)
    }
}

extension View {
    func cyCard(tinted: Color? = nil, radius: CGFloat = CyTheme.rCard) -> some View { modifier(CyCardStyle(tinted: tinted, radius: radius)) }
    /// Extends the hit area of a visually small control to the 44 pt minimum without changing its look.
    func cyMinTap() -> some View { frame(minWidth: CyTheme.minTap, minHeight: CyTheme.minTap).contentShape(Rectangle()) }
}
