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
    ///
    /// MAIN DEVELOPMENT CONFIGURATION (owner directive, 17 Nov 2026): the same main Cyclift target can be run with the
    /// redesign on, so the future main app is tested against its real planner, recording, persistence and Coach while
    /// Lab shows the design. It is a SIMULATOR-ONLY test setting (`BC_UITEST_REDESIGN=1`), exactly like the existing
    /// `BC_UITEST_THEME`: the line that reads it is not compiled into any device build, so no iPhone, TestFlight or
    /// App Store build can have the redesign switched on by a setting, an argument or anything stored on the phone.
    static let redesign: Bool = {
        if CycliftLab.isLab { return true }
        #if targetEnvironment(simulator)
        return ProcessInfo.processInfo.environment["BC_UITEST_REDESIGN"] == "1"
        #else
        return false
        #endif
    }()
}
