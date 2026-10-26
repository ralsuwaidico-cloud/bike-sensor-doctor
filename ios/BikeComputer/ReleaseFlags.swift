import Foundation

/// Compile-time switches for the Cyclift 1.0 App Store build (owner decisions, docs/briefs/RELEASE_1_0_DECISIONS.md).
/// The code behind each switch stays compiled and tested, but nothing behind a `false` switch can appear or run.
enum ReleaseFlags {
    /// Accounts and cloud sync (Supabase). Off in 1.0: no sign-in anywhere, `CloudConfig.isConfigured` is always false
    /// (even when a build carries account values), so `AccountService` creates no client and `SyncEngine` never starts.
    static let accountsEnabled = false
    /// Garmin / WHOOP / Oura entries (not integrated). Off in 1.0: no "planned" placeholders in the UI (App Review 2.1).
    static let plannedProvidersVisible = false
}
