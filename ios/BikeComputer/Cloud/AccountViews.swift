import SwiftUI
import AuthenticationServices
import UniformTypeIdentifiers

/// Profile › Account section: who is signed in, sync, sign out / create account, export, deletion (≤ 3 taps).
struct AccountSection: View {
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var account: AccountService
    @EnvironmentObject private var cloud: SyncEngine
    @EnvironmentObject private var device: DeviceLink
    @State private var showAccount = false
    @State private var confirmDelete = false
    @State private var deleting = false
    @State private var exportURL: URL?
    @State private var deleteError: String?

    var body: some View {
        Section("Account") {
            switch account.state {
            case .notConfigured:
                if store.guest {
                    Button { showAccount = true } label: { HStack { Label("Create account", systemImage: "person.badge.plus"); Spacer(); Text("not available yet").font(.caption).foregroundStyle(.secondary) } }
                } else {
                    HStack { Label("Signed in with Apple", systemImage: "checkmark.seal"); Spacer(); Pill(text: "local only", color: BC.stale) }
                    Button("Sign out (keeps data on this phone)") { store.guest = true; store.appleUserId = nil }
                }
                Text("Accounts and cloud sync are switched off in this build; everything stays on this phone.").font(.footnote).foregroundStyle(.secondary)
            case .signedOut:
                Button { showAccount = true } label: { HStack { Label("Create account or sign in", systemImage: "person.badge.plus"); Spacer(); Text("guest · data on this phone").font(.caption).foregroundStyle(.secondary) } }
                Text("An account keeps your workouts, plan, templates and settings in sync across your devices. Guest data is uploaded when you sign in — nothing is lost.").font(.footnote).foregroundStyle(.secondary)
            case .signedIn(_, let email, let provider):
                HStack { Label("Signed in with \(provider)", systemImage: "checkmark.seal"); Spacer(); if let e = email { Text(e).font(.caption).foregroundStyle(.secondary).lineLimit(1) } }
                HStack {
                    Label("Cloud sync", systemImage: "icloud")
                    Spacer()
                    Text(syncLabel).font(.footnote).foregroundStyle(.secondary).lineLimit(1)
                    Button("Sync now") { Task { await cloud.syncNow() } }.font(.footnote).disabled(cloud.state == .syncing)
                }
                if case .failed(let why) = cloud.state { Text(why).font(.footnote).foregroundStyle(BC.warn) }
                Button("Sign out (keeps data on this phone)") { Task { await account.signOut(); store.guest = true } }
            }
            Button { exportURL = exportFile() } label: { Label("Export my data (JSON)", systemImage: "square.and.arrow.up") }
            Button(role: .destructive) { confirmDelete = true } label: { Label(account.state.isSignedIn ? "Delete account and all data" : "Delete all data on this phone", systemImage: "trash") }
            if let e = deleteError { Text(e).font(.footnote).foregroundStyle(BC.warn) }
        }
        .sheet(isPresented: $showAccount) { AccountSheet() }
        .sheet(item: $exportURL) { url in ShareSheet(items: [url]) }
        .alert(account.state.isSignedIn ? "Delete your account?" : "Delete everything on this phone?", isPresented: $confirmDelete) {
            Button("Delete", role: .destructive) { Task { await deleteAll() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(account.state.isSignedIn
                 ? "Your account and every workout, ride, template, plan and setting stored for it are deleted permanently from our servers and from this phone. Your BikeComputer keeps its own data."
                 : "Profile, plan, ride history, strength logs, templates and the remembered BikeComputer are removed from this phone. The board keeps its own data; use Forget phone on the board too.")
        }
    }
    private var syncLabel: String {
        switch cloud.state {
        case .off: return "off"
        case .syncing: return "syncing…"
        case .pending(let n): return "\(n) pending"
        case .failed: return "failed"
        case .idle: return cloud.lastSuccess.map { "synced \($0.formatted(date: .omitted, time: .shortened))" } ?? "not yet"
        }
    }
    private func deleteAll() async {
        deleting = true; defer { deleting = false }
        if account.state.isSignedIn {
            let ok = await account.deleteAccount()
            if !ok { if case .error(let e) = account.notice { deleteError = e }; return }
        }
        cloud.reset(); device.forget(); store.resetAll(); store.guest = true
    }
    private func exportFile() -> URL? {
        let enc = JSONEncoder(); enc.outputFormatting = [.prettyPrinted, .sortedKeys]; enc.dateEncodingStrategy = .iso8601
        guard let data = try? enc.encode(store.snapshot) else { return nil }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("athletics-export-\(Int(Date().timeIntervalSince1970)).json")
        try? data.write(to: url, options: .atomic)
        return url
    }
}

extension URL: Identifiable { public var id: String { absoluteString } }

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController { UIActivityViewController(activityItems: items, applicationActivities: nil) }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}

/// Create account / sign in: Apple, Google, e-mail (sign in, create, forgot). Also shown from onboarding.
struct AccountSheet: View {
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var account: AccountService
    @Environment(\.dismiss) private var dismiss
    @State private var mode = 0           // 0 sign in, 1 create, 2 reset
    @State private var email = ""
    @State private var password = ""
    @State private var password2 = ""
    var onDone: (() -> Void)? = nil

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 10) { AthleticsMark(size: 40); Text(mode == 1 ? "Create your account" : "Sign in").font(.system(size: 26, weight: .bold, design: .rounded)) }
                    if account.state == .notConfigured {
                        Card { Eyebrow(t: "Not available yet"); Text("Accounts are not configured in this build. Everything you do stays on this phone; sign-in arrives with the account service.").foregroundStyle(.secondary) }
                    } else {
                        Text("Your workouts, plan, templates and settings follow you to any device. What is already on this phone is uploaded — nothing is lost.").foregroundStyle(.secondary).font(.subheadline)
                        SignInWithAppleButton(mode == 1 ? .signUp : .signIn) { req in req.requestedScopes = [.fullName, .email]; req.nonce = account.prepareAppleRequest() } onCompletion: { result in
                            Task { if await account.completeApple(result) { finish() } }
                        }
                        .signInWithAppleButtonStyle(.black).frame(height: 50).clipShape(RoundedRectangle(cornerRadius: 14))
                        Button { Task { if await account.signInWithGoogle() { finish() } } } label: {
                            HStack { Image(systemName: "g.circle.fill"); Text(mode == 1 ? "Sign up with Google" : "Sign in with Google") }.frame(maxWidth: .infinity).frame(height: 36)
                        }.buttonStyle(.bordered).disabled(!CloudConfig.googleEnabled || account.busy)
                        if !CloudConfig.googleEnabled { Text("Google sign-in is not configured yet.").font(.caption).foregroundStyle(.secondary) }
                        Card {
                            Picker("", selection: $mode) { Text("Sign in").tag(0); Text("Create").tag(1); Text("Forgot password").tag(2) }.pickerStyle(.segmented)
                            TextField("E-mail", text: $email).textContentType(.emailAddress).keyboardType(.emailAddress).textInputAutocapitalization(.never).autocorrectionDisabled().textFieldStyle(.roundedBorder)
                            if mode != 2 { SecureField(mode == 1 ? "Choose a password (8+ characters)" : "Password", text: $password).textContentType(mode == 1 ? .newPassword : .password).textFieldStyle(.roundedBorder) }
                            if mode == 1 { SecureField("Repeat the password", text: $password2).textContentType(.newPassword).textFieldStyle(.roundedBorder) }
                            Button { Task { await submit() } } label: { Text(mode == 0 ? "Sign in" : mode == 1 ? "Create account" : "Send reset link").frame(maxWidth: .infinity) }
                                .buttonStyle(.borderedProminent).tint(BC.accent).controlSize(.large).disabled(!valid || account.busy)
                            if mode == 1 { Text("You will receive an e-mail to confirm the address before the first sign-in.").font(.caption).foregroundStyle(.secondary) }
                        }
                        notice
                        Text("Passwords are handled by the account service (Supabase) and never stored by the app.").font(.footnote).foregroundStyle(.secondary)
                        HStack(spacing: 16) {
                            NavigationLink("Privacy policy") { LegalView(kind: .privacy) }
                            NavigationLink("Terms of use") { LegalView(kind: .terms) }
                        }.font(.footnote)
                    }
                }.padding()
            }
            .background(Color(.systemGroupedBackground))
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Not now") { dismiss() } } }
            .overlay { if account.busy { ProgressView().controlSize(.large) } }
        }
    }
    private var valid: Bool {
        let e = email.contains("@") && email.contains(".")
        switch mode { case 0: return e && password.count >= 6; case 1: return e && password.count >= 8 && password == password2; default: return e }
    }
    @ViewBuilder private var notice: some View {
        switch account.notice {
        case .none: EmptyView()
        case .verifyEmail(let e): Label("Check \(e) and tap the confirmation link, then sign in.", systemImage: "envelope").font(.footnote).foregroundStyle(BC.accent)
        case .info(let s): Text(s).font(.footnote).foregroundStyle(BC.accent)
        case .error(let s): Text(s).font(.footnote).foregroundStyle(BC.warn)
        case .passwordRecovery: Text("Set your new password below.").font(.footnote).foregroundStyle(BC.accent)
        }
    }
    private func submit() async {
        account.notice = .none
        switch mode {
        case 0: if await account.signIn(email: email, password: password) { finish() }
        case 1: _ = await account.signUp(email: email, password: password)
        default: _ = await account.resetPassword(email: email)
        }
    }
    private func finish() {
        store.guest = false
        if let n = account.pendingGivenName, store.profile.name.isEmpty { store.profile.name = n; account.pendingGivenName = nil }
        onDone?(); dismiss()
    }
}

/// Shown when a password-recovery link opened the app.
struct SetNewPasswordSheet: View {
    @EnvironmentObject private var account: AccountService
    @Environment(\.dismiss) private var dismiss
    @State private var p1 = ""; @State private var p2 = ""
    var body: some View {
        NavigationStack {
            Form {
                Section { SecureField("New password (8+ characters)", text: $p1); SecureField("Repeat", text: $p2) }
                if case .error(let e) = account.notice { Text(e).foregroundStyle(BC.warn) }
                Button("Save new password") { Task { if await account.setNewPassword(p1) { dismiss() } } }.disabled(p1.count < 8 || p1 != p2 || account.busy)
            }.navigationTitle("New password").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { account.recoveryPending = false; dismiss() } } }
        }
    }
}

/// Privacy policy / Terms, rendered from the bundled markdown (also exported under ios/legal for hosting).
struct LegalView: View {
    enum Kind: String { case privacy, terms; var title: String { self == .privacy ? "Privacy policy" : "Terms of use" } }
    let kind: Kind
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(paragraphs.enumerated()), id: \.offset) { _, p in
                    if p.hasPrefix("# ") { Text(p.dropFirst(2)).font(.title2.bold()) }
                    else if p.hasPrefix("## ") { Text(p.dropFirst(3)).font(.headline).padding(.top, 6) }
                    else { Text(LocalizedStringKey(p)).font(.subheadline) }
                }
            }.padding()
        }.navigationTitle(kind.title).navigationBarTitleDisplayMode(.inline)
    }
    private var paragraphs: [String] {
        let url = Bundle.main.url(forResource: kind.rawValue, withExtension: "md") ?? Bundle.main.url(forResource: kind.rawValue, withExtension: "md", subdirectory: "Resources")
        let text = url.flatMap { try? String(contentsOf: $0, encoding: .utf8) } ?? "Document not bundled."
        return text.components(separatedBy: "\n\n").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }
}

/// One line for App & device settings › Data synchronization.
struct CloudSyncRow: View {
    @EnvironmentObject private var account: AccountService
    @EnvironmentObject private var cloud: SyncEngine
    var body: some View {
        HStack {
            Text("Cloud sync"); Spacer()
            Text(label).font(.footnote).foregroundStyle(.secondary).lineLimit(1)
            if account.state.isSignedIn { Button("Sync now") { Task { await cloud.syncNow() } }.font(.footnote).disabled(cloud.state == .syncing) }
        }
    }
    private var label: String {
        switch account.state {
        case .notConfigured: return "not available in this build"
        case .signedOut: return "sign in to enable"
        case .signedIn:
            switch cloud.state {
            case .syncing: return "syncing…"
            case .failed(let w): return "failed: \(w)"
            case .pending(let n): return "\(n) pending"
            default: return cloud.lastSuccess.map { "synced \($0.formatted(date: .abbreviated, time: .shortened))" } ?? "not synced yet"
            }
        }
    }
}
