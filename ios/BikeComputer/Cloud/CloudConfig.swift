import Foundation

/// Account-service configuration, injected at build time from CI secrets into Info.plist (see project.yml:
/// SUPABASE_URL / SUPABASE_ANON_KEY / GOOGLE_WEB_CLIENT_ID). Nothing is hard-coded; when the values are empty the app
/// runs exactly as before (guest mode, everything on the phone) and the account pages say so.
enum CloudConfig {
    static var supabaseURL: URL? {
        guard let s = value("SUPABASE_URL"), let u = URL(string: s), u.scheme == "https" else { return nil }
        return u
    }
    static var anonKey: String? { value("SUPABASE_ANON_KEY") }
    static var googleWebClientId: String? { value("GOOGLE_WEB_CLIENT_ID") }
    /// The URL scheme registered in Info.plist (CFBundleURLTypes); auth e-mails and the Google flow return through it.
    static let redirectURL = URL(string: "com.ralsuwaidico.bikecomputer://auth-callback")!
    static var isConfigured: Bool { supabaseURL != nil && anonKey != nil }
    static var googleEnabled: Bool { isConfigured && googleWebClientId != nil }

    private static func value(_ key: String) -> String? {
        guard let v = Bundle.main.object(forInfoDictionaryKey: key) as? String else { return nil }
        let t = v.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty || t.hasPrefix("$(") ? nil : t
    }
}
