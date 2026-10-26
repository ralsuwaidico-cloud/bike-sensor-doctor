import Foundation

/// Account-service configuration, injected at build time from CI secrets into Info.plist (see project.yml:
/// SUPABASE_URL / SUPABASE_ANON_KEY / GOOGLE_WEB_CLIENT_ID). Nothing is hard-coded. Cyclift 1.0 ships without accounts:
/// `ReleaseFlags.accountsEnabled` is false, so the app is never "configured", whatever values the build carries.
enum CloudConfig {
    static var supabaseURL: URL? {
        guard let s = value("SUPABASE_URL"), let u = URL(string: s), u.scheme == "https" else { return nil }
        return u
    }
    static var anonKey: String? { value("SUPABASE_ANON_KEY") }
    static var googleWebClientId: String? { value("GOOGLE_WEB_CLIENT_ID") }
    /// The URL scheme registered in Info.plist (CFBundleURLTypes); auth e-mails and the Google flow return through it.
    static let redirectURL = URL(string: "com.ralsuwaidico.bikecomputer://auth-callback")!
    static var isConfigured: Bool { configured(accountsEnabled: ReleaseFlags.accountsEnabled, url: supabaseURL, anonKey: anonKey) }
    static var googleEnabled: Bool { isConfigured && googleWebClientId != nil }

    /// Pure rule behind `isConfigured` (unit-tested): the release switch wins over any values in the build.
    static func configured(accountsEnabled: Bool, url: URL?, anonKey: String?) -> Bool {
        accountsEnabled && url != nil && anonKey != nil
    }

    private static func value(_ key: String) -> String? {
        guard let v = Bundle.main.object(forInfoDictionaryKey: key) as? String else { return nil }
        let t = v.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty || t.hasPrefix("$(") ? nil : t
    }
}
