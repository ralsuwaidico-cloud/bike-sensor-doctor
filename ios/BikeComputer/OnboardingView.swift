import SwiftUI
import AuthenticationServices

/// First run in about two minutes: sign in or guest → goal → hours + level → connect the board (or phone only) → Home.
struct OnboardingView: View {
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var device: DeviceLink
    @State private var step = 0
    @State private var name = ""
    @State private var authError: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    switch step {
                    case 0: welcome
                    case 1: goal
                    case 2: hoursLevel
                    default: connect
                    }
                }.padding()
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { if step > 0 { ToolbarItem(placement: .navigationBarLeading) { Button("Back") { step -= 1 } } } }
        }
    }

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Welcome").font(.system(size: 34, weight: .bold, design: .rounded))
            Text("BikeComputer works with your Waveshare cycling computer and power meter, or with the phone alone. Sign in so your rides and plan follow you between devices, or try it first.").foregroundStyle(.secondary)
            SignInWithAppleButton(.signIn) { req in req.requestedScopes = [.fullName] } onCompletion: { result in
                switch result {
                case .success(let auth):
                    if let c = auth.credential as? ASAuthorizationAppleIDCredential {
                        store.appleUserId = c.user; store.guest = false
                        if let n = c.fullName?.givenName, !n.isEmpty { store.profile.name = n }
                        step = 1
                    }
                case .failure(let e): authError = e.localizedDescription
                }
            }
            .signInWithAppleButtonStyle(.black).frame(height: 50).clipShape(RoundedRectangle(cornerRadius: 14))
            choice("Sign in with Google", "Coming with the account service (next build)", disabled: true) {}
            choice("Continue with email", "Coming with the account service (next build)", disabled: true) {}
            choice("Try it first (guest)", "No account, no device needed. Rides stay on this phone until you create an account.") { store.guest = true; step = 1 }
            if let e = authError { Text(e).font(.footnote).foregroundStyle(BC.warn) }
            Text("Apple requires Sign in with Apple when other sign-ins are offered; Google and email arrive together with the sync service.").font(.footnote).foregroundStyle(.secondary)
        }
    }

    private var goal: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("What are you riding for?").font(.system(size: 30, weight: .bold, design: .rounded))
            TextField("Your name (optional)", text: $store.profile.name).textFieldStyle(.roundedBorder)
            ForEach(RiderProfile.Goal.allCases, id: \.self) { g in
                choice(g.title, g.hint, selected: store.profile.goal == g) { store.profile.goal = g }
            }
            Button { step = 2 } label: { Text("Next").frame(maxWidth: .infinity) }.buttonStyle(.borderedProminent).tint(BC.accent).controlSize(.large)
        }
    }

    private var hoursLevel: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Time and level").font(.system(size: 30, weight: .bold, design: .rounded))
            Card {
                Eyebrow(t: "Hours per week")
                HStack(alignment: .firstTextBaseline) { Text("\(store.profile.hoursPerWeek)").font(BC.bigNum); Text("hours").foregroundStyle(.secondary) }
                Slider(value: Binding(get: { Double(store.profile.hoursPerWeek) }, set: { store.profile.hoursPerWeek = Int($0) }), in: 2...14, step: 1).tint(BC.accent)
                Text("The plan never schedules more than this.").font(.footnote).foregroundStyle(.secondary)
            }
            Card {
                Eyebrow(t: "Weight (kg)")
                HStack { Text(String(format: "%.0f", store.profile.weightKg)).font(BC.numFont); Slider(value: $store.profile.weightKg, in: 40...150, step: 1).tint(BC.accent) }
            }
            ForEach(RiderProfile.Level.allCases, id: \.self) { l in choice(l.title, l.hint, selected: store.profile.level == l) { store.profile.level = l } }
            Button { store.profile.refreshAssumption(); step = 3 } label: { Text("Next").frame(maxWidth: .infinity) }.buttonStyle(.borderedProminent).tint(BC.accent).controlSize(.large)
        }
    }

    private var connect: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Connect your BikeComputer").font(.system(size: 30, weight: .bold, design: .rounded))
            Card {
                Text("Switch the Waveshare on. Tap Connect: a 6-digit code appears on its round screen, type it here once. Then the phone is remembered.").foregroundStyle(.secondary)
                if device.state == .ready {
                    HStack { StatusDot(color: BC.live); Text("BikeComputer connected").bold(); Spacer(); if let i = device.info { Pill(text: "firmware \(i.fw)", color: BC.live) } }
                } else {
                    Text(device.state.rawValue).font(.footnote).foregroundStyle(.secondary)
                    if device.state == .scanning, !device.found.isEmpty { ForEach(device.found, id: \.id) { f in Button("Connect to \(f.name) (\(f.rssi) dBm)") { device.connect(to: f.id) } } }
                    Button { device.connect() } label: { Text(device.state == .scanning || device.state == .connecting ? "Searching…" : "Connect").frame(maxWidth: .infinity) }.buttonStyle(.borderedProminent).tint(BC.accent).controlSize(.large)
                }
            }
            Card {
                Eyebrow(t: "No BikeComputer yet?")
                Text("Ride with the phone alone: GPS speed, distance, map and heart rate from your Apple Watch. When a BikeComputer is connected later it becomes the recorder.").foregroundStyle(.secondary)
            }
            Text("Your starting FTP (\(store.profile.ftpW) W) is estimated from weight and level and marked provisional until a real ride proves it. No fitness knowledge needed.").font(.footnote).foregroundStyle(.secondary)
            Button { store.onboarded = true } label: { Text(device.state == .ready ? "Ride on" : "Continue with phone only").frame(maxWidth: .infinity) }.buttonStyle(.borderedProminent).tint(device.state == .ready ? BC.live : BC.accent).controlSize(.large)
        }
    }

    private func choice(_ title: String, _ hint: String, selected: Bool = false, disabled: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 3) { Text(title).font(.body.weight(.bold)); Text(hint).font(.caption).foregroundStyle(.secondary) }
                .frame(maxWidth: .infinity, alignment: .leading).padding(13)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(selected ? BC.accent : Color.clear, lineWidth: 2))
        }.buttonStyle(.plain).disabled(disabled).opacity(disabled ? 0.5 : 1)
    }
}
