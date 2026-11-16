import SwiftUI
import UIKit

// UX1 THEME STATE — one shared state and one token engine for every screen.
//
// `CyThemeState.shared` holds the theme being shown. The existing `CyTheme` colours ask it for their value each time
// they are drawn (`.themed { token }` in CyTheme.swift), so a change of theme reaches every screen that uses them without
// any per-theme code. Where theming is not available the colours are exactly what they were:
//   • production app on a device: never available (the athlete's appearance is unchanged until UX1 is introduced —
//     owner decision, 16 Nov 2026);
//   • simulator: only when launched with BC_UITEST_THEME=<theme> (screenshot tests);
//   • Cyclift Lab: always (the Lab banner's chooser).
// Not here yet: the athlete's choice in Profile, following iOS light/dark, and the screens that still use system colours
// or the older `BC` colours (they follow light/dark only).
final class CyThemeState: ObservableObject {
    static let shared = CyThemeState()

    /// Decided once at launch. false = `themed` returns the original colour object untouched and `cyThemeRoot` does nothing.
    static let available: Bool = {
        #if CYCLIFT_LAB
        return true
        #elseif targetEnvironment(simulator)
        return ProcessInfo.processInfo.environment["BC_UITEST_THEME"].flatMap(CyThemeState.preference(named:)) != nil
        #else
        return false
        #endif
    }()
    /// Read by the colours while drawing (any thread). Written on the main thread only, by `cyThemeRoot`, before the
    /// screens are redrawn for a new theme.
    fileprivate(set) static var tokens: CyThemeTokens? = nil

    /// The athlete's choice: one theme always, or a light and a dark theme that follow iOS.
    @Published private(set) var preference: CyThemePreference

    /// "obsidian" … "highContrast", or "system" (follow iOS with the default pair, Arctic and Obsidian).
    static func preference(named raw: String) -> CyThemePreference? {
        if raw == "system" { return CyThemePreference.followSystem() }
        return CyThemeID(rawValue: raw).map { CyThemePreference.always($0) }
    }

    private init() {
        var first = CyThemePreference.newAthleteDefault
        #if CYCLIFT_LAB
        first = LabTheme.launchPreference
        #elseif targetEnvironment(simulator)
        first = ProcessInfo.processInfo.environment["BC_UITEST_THEME"].flatMap(CyThemeState.preference(named:)) ?? first
        #endif
        preference = first
        if CyThemeState.available { CyThemeState.tokens = CyThemeTokens.tokens(for: first.resolved(systemIsDark: UITraitCollection.current.userInterfaceStyle == .dark)) }
    }

    /// Changes the choice now. Ignored where theming is not available, and for a choice that breaks the slot rule.
    func choose(_ p: CyThemePreference) {
        guard CyThemeState.available, p.isValid, p != preference else { return }
        preference = p
    }
}

/// The one place a theme is applied to the screens. Where theming is not available it returns the content untouched.
private struct CyThemeRoot: ViewModifier {
    @ObservedObject private var state = CyThemeState.shared
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        if CyThemeState.available {
            let shown = state.preference.resolved(systemIsDark: scheme == .dark)
            let t = CyThemeTokens.tokens(for: shown)
            // the colours read this while drawing; it is set before the screens below are rebuilt for `shown`
            let _ = { CyThemeState.tokens = t }()
            content
                // `.primary`, `.secondary` and `.tertiary` text everywhere takes the theme's three text colours
                .foregroundStyle(Color(cyRGBA: t.textPrimary), Color(cyRGBA: t.textSecondary), Color(cyRGBA: t.textTertiary))
                .tint(Color(cyRGBA: t.accent))
                // a new identity per theme redraws every screen with the new tokens at once (the page returns to Home;
                // keeping the current screen needs navigation state lifted out of the screens — recorded for UX1)
                .id(shown)
                // a fixed theme decides light or dark itself; "follow iOS" leaves it to iOS, and the line above then
                // picks the athlete's light or dark theme whenever iOS changes
                .preferredColorScheme(state.preference.mode == .system ? nil : (shown.isDark ? .dark : .light))
        } else {
            content
        }
    }
}

extension View {
    /// Applies the shown theme to everything inside. No effect where theming is not available (production on a device).
    func cyThemeRoot() -> some View { modifier(CyThemeRoot()) }
}

// System-coloured surfaces of the older screens (Plan, Progress, Train cards). Unthemed, each is exactly the iOS colour
// it replaces; themed, it is the token named after it.
extension CyTheme {
    static let sysPage = Color(.systemGroupedBackground).themed { $0.background }
    static let sysCard = Color(.secondarySystemGroupedBackground).themed { $0.surface }
    static let sysCard2 = Color(.tertiarySystemGroupedBackground).themed { $0.surfaceRaised }
    static let sysFill = Color(.tertiarySystemFill).themed { $0.surfaceRaised }
    static let sysGray5 = Color(.systemGray5).themed { $0.surfaceRaised }
    static let sysGray6 = Color(.systemGray6).themed { $0.surfaceRaised }
}

extension UIColor {
    convenience init(cyRGBA c: CyRGBA) { self.init(red: CGFloat(c.r), green: CGFloat(c.g), blue: CGFloat(c.b), alpha: CGFloat(c.a)) }
}

extension Color {
    /// This colour; where theming is available, the shown theme's answer, asked again every time it is drawn.
    func themed(_ token: @escaping (CyThemeTokens) -> CyRGBA) -> Color {
        guard CyThemeState.available else { return self }
        _ = CyThemeState.shared                      // makes sure the first theme's tokens are set before anything is drawn
        let original = UIColor(self)
        return Color(uiColor: UIColor { traits in
            if let t = CyThemeState.tokens { return UIColor(cyRGBA: token(t)) }
            return original.resolvedColor(with: traits)
        })
    }
}

extension CyTheme.Identity {
    /// This identity; where theming is available, the shown theme's shades of the given meaning colour.
    func themed(_ token: @escaping (CyThemeTokens) -> CyRGBA) -> CyTheme.Identity {
        guard CyThemeState.available else { return self }
        return CyTheme.Identity(tint: tint.themed { $0.shades(of: token($0)).tint }, bg: bg.themed { $0.shades(of: token($0)).fill },
                                mid: mid.themed { $0.shades(of: token($0)).mid }, soft: soft.themed { $0.shades(of: token($0)).soft },
                                onTint: onTint.themed { $0.shades(of: token($0)).onTint })
    }
}
