import Foundation
import Combine
import CryptoKit
import AuthenticationServices
import UIKit
import Supabase

/// Accounts on top of Supabase Auth. The app never sees or stores a password: Apple and Google hand over identity
/// tokens, e-mail sign-in/sign-up/reset go straight to Supabase over HTTPS, and the session (JWT + refresh token) is
/// kept by the SDK in the iOS Keychain. Guest mode needs none of this; everything here is inert when
/// `CloudConfig.isConfigured` is false.
@MainActor
final class AccountService: NSObject, ObservableObject {
    enum State: Equatable {
        case notConfigured          // no Supabase values in this build
        case signedOut              // guest (data on the phone only)
        case signedIn(userId: String, email: String?, provider: String)
        var isSignedIn: Bool { if case .signedIn = self { return true }; return false }
        var userId: String? { if case .signedIn(let u, _, _) = self { return u }; return nil }
        var label: String {
            switch self {
            case .notConfigured: return "Accounts not configured yet"
            case .signedOut: return "Guest · data on this phone"
            case .signedIn(_, let e, let p): return "Signed in with \(p)\(e.map { " · \($0)" } ?? "")"
            }
        }
    }
    enum Notice: Equatable { case none, verifyEmail(String), passwordRecovery, info(String), error(String) }

    @Published private(set) var state: State = CloudConfig.isConfigured ? .signedOut : .notConfigured
    @Published var notice: Notice = .none
    @Published private(set) var busy = false
    /// Set when a password-recovery link opened the app: the UI shows "set a new password".
    @Published var recoveryPending = false

    let client: SupabaseClient?
    private var authTask: Task<Void, Never>?
    private var currentNonce: String?
    /// Fired after every sign-in (the sync engine uploads local data) and sign-out.
    let sessionChanged = PassthroughSubject<Bool, Never>()

    override init() {
        if let url = CloudConfig.supabaseURL, let key = CloudConfig.anonKey {
            client = SupabaseClient(supabaseURL: url, supabaseKey: key)
        } else { client = nil }
        super.init()
        guard let client else { return }
        authTask = Task { [weak self] in
            for await (event, session) in client.auth.authStateChanges {
                guard let self else { return }
                switch event {
                case .initialSession, .signedIn, .tokenRefreshed, .userUpdated:
                    if let s = session { self.apply(session: s); if event == .signedIn { self.sessionChanged.send(true) } }
                    else if event == .initialSession { self.state = .signedOut }
                case .signedOut, .userDeleted:
                    self.state = .signedOut; self.sessionChanged.send(false)
                case .passwordRecovery:
                    self.recoveryPending = true; self.notice = .passwordRecovery
                    if let s = session { self.apply(session: s) }
                default: break
                }
            }
        }
    }

    private func apply(session: Auth.Session) {
        let u = session.user
        let provider = (u.appMetadata["provider"]?.stringValue ?? "e-mail").replacingOccurrences(of: "apple", with: "Apple").replacingOccurrences(of: "google", with: "Google").replacingOccurrences(of: "email", with: "e-mail")
        state = .signedIn(userId: u.id.uuidString.lowercased(), email: u.email, provider: provider)
    }

    /// A valid access token (refreshed by the SDK when needed) for the REST sync layer.
    func accessToken() async -> String? {
        guard let client, state.isSignedIn else { return nil }
        return try? await client.auth.session.accessToken
    }

    // MARK: Sign in with Apple (native) — the view sets `request.nonce = account.prepareAppleRequest()`
    func prepareAppleRequest() -> String {
        let raw = Self.randomNonce(); currentNonce = raw
        return SHA256.hash(data: Data(raw.utf8)).map { String(format: "%02x", $0) }.joined()
    }
    func completeApple(_ result: Result<ASAuthorization, Error>) async -> Bool {
        guard let client else { notice = .error("Accounts are not configured in this build."); return false }
        switch result {
        case .failure(let e):
            if (e as? ASAuthorizationError)?.code != .canceled { notice = .error(e.localizedDescription) }
            return false
        case .success(let auth):
            guard let c = auth.credential as? ASAuthorizationAppleIDCredential, let tokenData = c.identityToken,
                  let token = String(data: tokenData, encoding: .utf8), let nonce = currentNonce else { notice = .error("Apple did not return an identity token."); return false }
            return await run {
                _ = try await client.auth.signInWithIdToken(credentials: .init(provider: .apple, idToken: token, nonce: nonce))
                if let n = c.fullName?.givenName, !n.isEmpty { self.pendingGivenName = n }
            }
        }
    }
    /// Apple only sends the name on the very first sign-in; the view copies it into the profile if the name is empty.
    @Published var pendingGivenName: String?

    // MARK: Google — Supabase OAuth in an in-app browser; the redirect comes back through our URL scheme.
    func signInWithGoogle() async -> Bool {
        guard let client else { notice = .error("Accounts are not configured in this build."); return false }
        guard CloudConfig.googleEnabled else { notice = .error("Google sign-in is not configured yet."); return false }
        return await run {
            let url = try client.auth.getOAuthSignInURL(provider: .google, redirectTo: CloudConfig.redirectURL)
            let callback = try await self.webAuth(url: url)
            try await client.auth.session(from: callback)
        }
    }
    private func webAuth(url: URL) async throws -> URL {
        try await withCheckedThrowingContinuation { cont in
            let s = ASWebAuthenticationSession(url: url, callbackURLScheme: CloudConfig.redirectURL.scheme) { cb, err in
                if let cb { cont.resume(returning: cb) } else { cont.resume(throwing: err ?? URLError(.cancelled)) }
            }
            s.presentationContextProvider = self
            s.prefersEphemeralWebBrowserSession = false
            if !s.start() { cont.resume(throwing: URLError(.cannotConnectToHost)) }
        }
    }

    // MARK: e-mail
    func signUp(email: String, password: String) async -> Bool {
        guard let client else { return false }
        return await run {
            let r = try await client.auth.signUp(email: email, password: password, redirectTo: CloudConfig.redirectURL)
            if r.session == nil { self.notice = .verifyEmail(email) }       // confirmation required (as configured)
        }
    }
    func signIn(email: String, password: String) async -> Bool {
        guard let client else { return false }
        return await run { _ = try await client.auth.signIn(email: email, password: password) }
    }
    func resetPassword(email: String) async -> Bool {
        guard let client else { return false }
        return await run {
            try await client.auth.resetPasswordForEmail(email, redirectTo: CloudConfig.redirectURL)
            self.notice = .info("If an account exists for \(email), a reset link is on its way. Open it on this phone.")
        }
    }
    func setNewPassword(_ password: String) async -> Bool {
        guard let client else { return false }
        return await run {
            _ = try await client.auth.update(user: UserAttributes(password: password))
            self.recoveryPending = false; self.notice = .info("Password changed.")
        }
    }

    /// Links opened by the app (e-mail confirmation, reset, OAuth fallback). Returns true when consumed.
    func handle(url: URL) -> Bool {
        guard let client, url.scheme == CloudConfig.redirectURL.scheme else { return false }
        Task { _ = await run { try await client.auth.session(from: url) } }
        return true
    }

    func signOut() async {
        guard let client else { return }
        _ = await run { try await client.auth.signOut() }
        state = .signedOut
    }

    /// App Store guideline 5.1.1 (v): removes every row and the auth user (SQL function auth_delete_user), then the
    /// caller wipes the phone. Works only while signed in.
    func deleteAccount() async -> Bool {
        guard let client else { return false }
        return await run {
            try await client.rpc("auth_delete_user").execute()
            try? await client.auth.signOut()
            self.state = .signedOut
        }
    }

    /// Everything the server holds for this user, as one JSON document (SQL function export_my_data).
    func exportServerData() async -> Data? {
        guard let client, state.isSignedIn else { return nil }
        return try? await client.rpc("export_my_data").execute().data
    }

    // MARK: helpers
    private func run(_ body: @escaping () async throws -> Void) async -> Bool {
        busy = true; defer { busy = false }
        do { try await body(); return true }
        catch { notice = .error(Self.describe(error)); return false }
    }
    static func describe(_ e: Error) -> String {
        if let u = e as? URLError { return u.code == .cancelled ? "Cancelled." : "No connection: \(u.localizedDescription)" }
        let s = e.localizedDescription
        if s.lowercased().contains("invalid login") { return "Wrong e-mail or password." }
        if s.lowercased().contains("email not confirmed") { return "Please confirm your e-mail first (check your inbox)." }
        if s.lowercased().contains("already registered") { return "This e-mail already has an account — sign in instead." }
        return s
    }
    private static func randomNonce(length: Int = 32) -> String {
        let chars = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var bytes = [UInt8](repeating: 0, count: length)
        _ = SecRandomCopyBytes(kSecRandomDefault, length, &bytes)
        return String(bytes.map { chars[Int($0) % chars.count] })
    }
}

extension AccountService: ASWebAuthenticationPresentationContextProviding {
    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            (UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first?.windows.first { $0.isKeyWindow }) ?? ASPresentationAnchor()
        }
    }
}
