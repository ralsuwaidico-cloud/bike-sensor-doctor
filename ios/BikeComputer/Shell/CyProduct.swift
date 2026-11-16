import Foundation

/// ONE application, two configurations (owner directive, 16 Nov 2026). The redesigned interface is written once, as
/// ordinary shared code, and both apps compile all of it. What differs between Cyclift Lab and production Cyclift is
/// configuration only:
///   • which interface is switched on (`redesign`), and
///   • which capabilities exist (Lab: demo athlete, no Health, Bluetooth, location or recording — Lab/CycliftLab.swift).
/// Promoting the redesign to production is changing `redesign` for the production configuration after the release
/// gates pass — not rewriting any screen.
enum CyProduct {
    /// Navigation v1.2, Profile v2.0 and the screens that follow them. On in Cyclift Lab. Off in production Cyclift, which
    /// keeps the build-216 interface until the owner authorises the promotion.
    static let redesign: Bool = CycliftLab.isLab
}
