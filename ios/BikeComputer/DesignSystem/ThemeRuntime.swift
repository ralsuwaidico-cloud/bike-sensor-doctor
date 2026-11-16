import SwiftUI
import UIKit

// UX1 PREVIEW BRIDGE — not the theme feature.
//
// Lets the six themes be SEEN on the real screens before any screen is migrated: when the simulator is launched with
// BC_UITEST_THEME=<theme>, the existing `CyTheme` colours answer from that theme's tokens instead of the two built-in
// palettes. On a real device, and in the simulator without that variable, `preview` is nil and every colour is exactly
// what it was — the athlete's appearance is unchanged until UX1 is actually introduced (owner decision, 16 Nov 2026).
// Not here yet: the athlete's choice in Profile, following iOS light/dark live, and the screens that still use system
// colours or the older `BC` colours (they follow light/dark only, and the preview screenshots show which they are).
enum CyThemeRuntime {
    static let preview: CyThemeTokens? = {
        #if CYCLIFT_LAB
        return CyThemeTokens.tokens(for: LabTheme.chosen)      // Cyclift Lab always shows one of the six themes
        #elseif targetEnvironment(simulator)
        guard let raw = ProcessInfo.processInfo.environment["BC_UITEST_THEME"], let id = CyThemeID(rawValue: raw) else { return nil }
        return CyThemeTokens.tokens(for: id)
        #else
        return nil
        #endif
    }()
}

extension Color {
    init(cyRGBA c: CyRGBA) { self.init(.sRGB, red: c.r, green: c.g, blue: c.b, opacity: c.a) }
    /// This colour, or the preview theme's answer when one is active.
    func themed(_ token: (CyThemeTokens) -> CyRGBA) -> Color {
        guard let t = CyThemeRuntime.preview else { return self }
        return Color(cyRGBA: token(t))
    }
}

extension CyTheme.Identity {
    /// This identity, or the preview theme's shades of the given meaning colour when one is active.
    func themed(_ token: (CyThemeTokens) -> CyRGBA) -> CyTheme.Identity {
        guard let t = CyThemeRuntime.preview else { return self }
        let s = t.shades(of: token(t))
        return CyTheme.Identity(tint: Color(cyRGBA: s.tint), bg: Color(cyRGBA: s.fill), mid: Color(cyRGBA: s.mid), soft: Color(cyRGBA: s.soft), onTint: Color(cyRGBA: s.onTint))
    }
}
