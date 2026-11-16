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

    /// Decided once at launch. false = `themed` returns the original colour object untouched.
    static let available: Bool = {
        #if CYCLIFT_LAB
        return true
        #elseif targetEnvironment(simulator)
        return ProcessInfo.processInfo.environment["BC_UITEST_THEME"].flatMap(CyThemeID.init(rawValue:)) != nil
        #else
        return false
        #endif
    }()
    /// Read by the colours while drawing (any thread); written on the main thread only, together with `active`.
    private(set) static var tokens: CyThemeTokens? = nil

    @Published private(set) var active: CyThemeID?

    private init() {
        var first: CyThemeID? = nil
        #if CYCLIFT_LAB
        first = LabTheme.chosen
        #elseif targetEnvironment(simulator)
        first = ProcessInfo.processInfo.environment["BC_UITEST_THEME"].flatMap(CyThemeID.init(rawValue:))
        #endif
        active = first
        CyThemeState.tokens = first.map(CyThemeTokens.tokens(for:))
    }

    /// Shows a theme now. Ignored where theming is not available.
    func show(_ id: CyThemeID) {
        guard CyThemeState.available, id != active else { return }
        CyThemeState.tokens = CyThemeTokens.tokens(for: id)
        active = id
    }
}

extension UIColor {
    convenience init(cyRGBA c: CyRGBA) { self.init(red: CGFloat(c.r), green: CGFloat(c.g), blue: CGFloat(c.b), alpha: CGFloat(c.a)) }
}

extension Color {
    /// This colour; where theming is available, the shown theme's answer, asked again every time it is drawn.
    func themed(_ token: @escaping (CyThemeTokens) -> CyRGBA) -> Color {
        guard CyThemeState.available else { return self }
        _ = CyThemeState.shared                      // makes sure the first theme is set before anything is drawn
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
