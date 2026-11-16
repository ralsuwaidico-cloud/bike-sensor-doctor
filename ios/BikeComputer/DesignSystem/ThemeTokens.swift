import Foundation

// UX1 theme foundation (owner authorization of 16 Nov 2026). Foundation only: no SwiftUI, no reference to navigation,
// recording or the athlete record. Nothing in the app reads this file yet.
//
// STATUS OF THE VALUES: PROVISIONAL. They are the UI Lab prototype values (brand book §4.3), carried over unchanged so
// that real screens can be compared. They are not approved brand tokens; `CyThemeTokens.valuesApproved` says so and a
// test pins it, so approval has to be a deliberate change.

enum CyThemeID: String, Codable, CaseIterable {
    case obsidian, arctic, ocean, forest, sandstone, highContrast

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
    /// Each theme is one fixed look. A theme does not change itself when iOS switches between light and dark; the
    /// athlete's preference decides which theme is shown (see `CyThemePreference`).
    var isDark: Bool {
        switch self {
        case .arctic, .sandstone: return false
        case .obsidian, .ocean, .forest, .highContrast: return true
        }
    }
    static let newAthleteDefault: CyThemeID = .obsidian
}

struct CyRGBA: Equatable, Codable {
    let r: Double, g: Double, b: Double, a: Double
    init(r: Double, g: Double, b: Double, a: Double = 1) { self.r = r; self.g = g; self.b = b; self.a = a }
    init(hex: UInt32, alpha: Double = 1) {
        self.init(r: Double((hex >> 16) & 0xFF) / 255, g: Double((hex >> 8) & 0xFF) / 255, b: Double(hex & 0xFF) / 255, a: alpha)
    }
    /// WCAG 2 relative luminance (opaque colours).
    var luminance: Double {
        func lin(_ v: Double) -> Double { v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
        return 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b)
    }
    /// WCAG 2 contrast ratio, 1 (none) to 21 (black on white).
    func contrast(with o: CyRGBA) -> Double {
        let hi = max(luminance, o.luminance), lo = min(luminance, o.luminance)
        return (hi + 0.05) / (lo + 0.05)
    }
}

/// One set of semantic tokens. Screens name a meaning ("textSecondary", "strength"), never a colour value, so all six
/// themes are data for one implementation.
struct CyThemeTokens: Equatable {
    let id: CyThemeID
    let background: CyRGBA
    let surface: CyRGBA
    let surfaceRaised: CyRGBA
    let textPrimary: CyRGBA
    let textSecondary: CyRGBA
    let textTertiary: CyRGBA
    let border: CyRGBA
    let accent: CyRGBA
    let endurance: CyRGBA
    let strength: CyRGBA
    let recovery: CyRGBA
    let success: CyRGBA
    let warning: CyRGBA
    let danger: CyRGBA
    let ringConsistency: CyRGBA
    let ringLoad: CyRGBA
    let ringRecovery: CyRGBA
    let borderWidth: Double
    /// High Contrast separates surfaces with borders and flat fills instead of shadows and gradients.
    let usesShadows: Bool

    static let valuesApproved = false

    /// Backgrounds a piece of text or a mark can sit on.
    var grounds: [CyRGBA] { [background, surface, surfaceRaised] }
    var textTokens: [(name: String, color: CyRGBA)] { [("textPrimary", textPrimary), ("textSecondary", textSecondary), ("textTertiary", textTertiary)] }
    /// Colours that carry meaning in icons, charts and rings.
    var markTokens: [(name: String, color: CyRGBA)] {
        [("accent", accent), ("endurance", endurance), ("strength", strength), ("recovery", recovery), ("success", success), ("warning", warning),
         ("danger", danger), ("ringConsistency", ringConsistency), ("ringLoad", ringLoad), ("ringRecovery", ringRecovery)]
    }
    func lowestContrast(of c: CyRGBA) -> Double { grounds.map { c.contrast(with: $0) }.min() ?? 1 }

    static func tokens(for id: CyThemeID) -> CyThemeTokens {
        func c(_ hex: UInt32) -> CyRGBA { CyRGBA(hex: hex) }
        switch id {
        case .obsidian:
            return CyThemeTokens(id: .obsidian, background: c(0x0B0D10), surface: c(0x15181D), surfaceRaised: c(0x1F242B), textPrimary: c(0xF2F4F7), textSecondary: c(0xA9B0BB), textTertiary: c(0x8A93A0), border: c(0x2E343D), accent: c(0x9CC2EE), endurance: c(0x58C4F6), strength: c(0xFFB25B), recovery: c(0x7EDC9A), success: c(0x5BD68A), warning: c(0xF5C04A), danger: c(0xFF8077), ringConsistency: c(0x5FD3C4), ringLoad: c(0xF5B85C), ringRecovery: c(0xA99BFF),
                                 borderWidth: 1, usesShadows: true)
        case .arctic:
            return CyThemeTokens(id: .arctic, background: c(0xF3F6FA), surface: c(0xFFFFFF), surfaceRaised: c(0xE9EEF4), textPrimary: c(0x111820), textSecondary: c(0x465261), textTertiary: c(0x5D6978), border: c(0xD3DBE5), accent: c(0x1B63C2), endurance: c(0x0A6FA8), strength: c(0xA35400), recovery: c(0x1A7F45), success: c(0x1A7F45), warning: c(0x8F5F00), danger: c(0xC2302A), ringConsistency: c(0x0B7F74), ringLoad: c(0xA35F00), ringRecovery: c(0x5F4BD0),
                                 borderWidth: 1, usesShadows: true)
        case .ocean:
            return CyThemeTokens(id: .ocean, background: c(0x071726), surface: c(0x0E2236), surfaceRaised: c(0x17304A), textPrimary: c(0xEAF3FB), textSecondary: c(0xA3B9CC), textTertiary: c(0x8AA2B8), border: c(0x27496A), accent: c(0x48D6CF), endurance: c(0x6CCBFA), strength: c(0xFFB866), recovery: c(0x86E0A4), success: c(0x66DB95), warning: c(0xF7C75A), danger: c(0xFF8C84), ringConsistency: c(0x5FD9CB), ringLoad: c(0xF7BE68), ringRecovery: c(0xB0A4FF),
                                 borderWidth: 1, usesShadows: true)
        case .forest:
            return CyThemeTokens(id: .forest, background: c(0x0C1512), surface: c(0x14201B), surfaceRaised: c(0x1D2D26), textPrimary: c(0xEEF5F0), textSecondary: c(0xA8BBAF), textTertiary: c(0x8CA195), border: c(0x2D4238), accent: c(0x9AD6A8), endurance: c(0x6CC6F2), strength: c(0xF9B466), recovery: c(0x86DDA0), success: c(0x6BD893), warning: c(0xF2C458), danger: c(0xFF8A80), ringConsistency: c(0x62D2C3), ringLoad: c(0xF2B962), ringRecovery: c(0xADA0FF),
                                 borderWidth: 1, usesShadows: true)
        case .sandstone:
            return CyThemeTokens(id: .sandstone, background: c(0xF5F0E8), surface: c(0xFFFDF9), surfaceRaised: c(0xECE4D8), textPrimary: c(0x221C16), textSecondary: c(0x574C40), textTertiary: c(0x6B5F52), border: c(0xDBCFBF), accent: c(0xA6482A), endurance: c(0x0F6C9C), strength: c(0x9C5300), recovery: c(0x24773F), success: c(0x24773F), warning: c(0x855B00), danger: c(0xB93026), ringConsistency: c(0x0F7A70), ringLoad: c(0x9C5C00), ringRecovery: c(0x5B49C4),
                                 borderWidth: 1, usesShadows: true)
        case .highContrast:
            return CyThemeTokens(id: .highContrast, background: c(0x000000), surface: c(0x000000), surfaceRaised: c(0x1C1C1E), textPrimary: c(0xFFFFFF), textSecondary: c(0xE5E5EA), textTertiary: c(0xC7C7CC), border: c(0xFFFFFF), accent: c(0xFFD60A), endurance: c(0x64D2FF), strength: c(0xFF9F0A), recovery: c(0x30D158), success: c(0x30D158), warning: c(0xFFD60A), danger: c(0xFF6961), ringConsistency: c(0x66E5D6), ringLoad: c(0xFFB340), ringRecovery: c(0xBFB5FF),
                                 borderWidth: 1.5, usesShadows: false)
        }
    }
}

/// The athlete's choice. Either one theme always, or "follow iOS": one theme of the athlete's choosing while iOS is in
/// light appearance and another while it is in dark. Nothing is substituted behind the athlete's back: the light slot
/// only accepts a light theme and the dark slot only a dark one.
struct CyThemePreference: Equatable, Codable {
    enum Mode: String, Codable { case fixed, system }
    private(set) var mode: Mode = .fixed
    private(set) var fixed: CyThemeID = .newAthleteDefault
    private(set) var systemLight: CyThemeID = .arctic
    private(set) var systemDark: CyThemeID = .obsidian

    static let newAthleteDefault = CyThemePreference()

    init() {}
    static func always(_ id: CyThemeID) -> CyThemePreference { var p = CyThemePreference(); p.mode = .fixed; p.fixed = id; return p }
    /// nil when a slot is given a theme of the wrong kind.
    static func followSystem(light: CyThemeID = .arctic, dark: CyThemeID = .obsidian) -> CyThemePreference? {
        guard !light.isDark, dark.isDark else { return nil }
        var p = CyThemePreference(); p.mode = .system; p.systemLight = light; p.systemDark = dark; return p
    }

    /// The theme to show now. `systemIsDark` is ignored unless the athlete chose to follow iOS.
    func resolved(systemIsDark: Bool) -> CyThemeID {
        switch mode {
        case .fixed: return fixed
        case .system: return systemIsDark ? systemDark : systemLight
        }
    }
    /// A stored preference that breaks the slot rule (hand-edited or damaged data) is not trusted.
    var isValid: Bool { !systemLight.isDark && systemDark.isDark }

    /// PROPOSAL, pending approval: what a returning athlete sees the first time, from the appearance setting they
    /// already have ("system", "light" or "dark" in today's app). Unknown or absent → the new-athlete default.
    static func forReturningAthlete(legacyAppearance: String?) -> CyThemePreference {
        switch legacyAppearance {
        case "light": return .always(.arctic)
        case "dark": return .always(.obsidian)
        case "system": return followSystem() ?? .newAthleteDefault
        default: return .newAthleteDefault
        }
    }
}

/// Where the choice is kept: its own key in the app's preferences. It is not part of the athlete's training record
/// (`store.json`), so choosing a theme can never change, grow or invalidate that file.
struct CyThemePreferenceStore {
    static let key = "cyclift.theme.preference.v1"
    let defaults: UserDefaults
    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    var hasStoredChoice: Bool { defaults.data(forKey: CyThemePreferenceStore.key) != nil }

    /// The stored choice. When there is none, or it cannot be read (damaged, or written by a newer version with a theme
    /// this version does not know), the answer is the migration from the legacy appearance — and the stored bytes are
    /// left alone, so a newer version's choice survives a downgrade.
    func load(legacyAppearance: String?) -> CyThemePreference {
        if let d = defaults.data(forKey: CyThemePreferenceStore.key), let p = try? JSONDecoder().decode(CyThemePreference.self, from: d), p.isValid { return p }
        return .forReturningAthlete(legacyAppearance: legacyAppearance)
    }
    @discardableResult
    func save(_ p: CyThemePreference) -> Bool {
        guard p.isValid, let d = try? JSONEncoder().encode(p) else { return false }
        defaults.set(d, forKey: CyThemePreferenceStore.key); return true
    }
    func clear() { defaults.removeObject(forKey: CyThemePreferenceStore.key) }
}
