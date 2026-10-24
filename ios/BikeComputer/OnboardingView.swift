import SwiftUI
import AuthenticationServices

/// Two-stage first run.
/// Stage A — account entry: guest (name only), Sign in with Apple, Google / e-mail (disabled until the sync service is configured).
/// Stage B — progressive fitness & device profile, one question per screen, every screen skippable. Nothing unknown is
/// invented: skipped values stay empty (nil) and the app says "not set" instead of showing a number.
struct OnboardingView: View {
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var device: DeviceLink
    @EnvironmentObject private var watch: WatchLink
    @EnvironmentObject private var health: HealthAccess
    @State private var step = 0
    @State private var authError: String?
    @State private var guestName = ""
    @State private var birthText = ""
    @State private var ftpText = ""
    @State private var maxHRText = ""
    @State private var restHRText = ""
    @State private var healthResult: String?
    private let lastStep = 7

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if step > 0 { ProgressView(value: Double(step), total: Double(lastStep)).tint(BC.accent).padding(.horizontal).padding(.top, 6) }
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        switch step {
                        case 0: welcome
                        case 1: aboutYou
                        case 2: sportsAndGoal
                        case 3: experienceAndTime
                        case 4: heartAndFTP
                        case 5: devices
                        case 6: appleHealth
                        default: ready
                        }
                    }.padding(20)
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if step > 0 { ToolbarItem(placement: .navigationBarLeading) { Button("Back") { step -= 1 } } }
                if step > 0, step < lastStep { ToolbarItem(placement: .navigationBarTrailing) { Button("Skip") { step += 1 } } }
            }
            .onAppear { if store.onboardingStage > 0 { step = min(store.onboardingStage, lastStep) } }
            .onChange(of: step) { _, s in store.onboardingStage = s }
        }
    }

    // MARK: Stage A
    private var welcome: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("BikeComputer").font(.system(size: 36, weight: .bold, design: .rounded))
            Text("Train with your Waveshare cycling computer and power meter, or with the phone alone. Choose how to start; you can create an account later.").foregroundStyle(.secondary)
            Card {
                Eyebrow(t: "Continue as guest")
                TextField("Your first name", text: $guestName).textFieldStyle(.roundedBorder).textContentType(.givenName)
                Button { store.guest = true; store.profile.name = guestName.trimmingCharacters(in: .whitespaces); step = 1 } label: { Text("Continue").frame(maxWidth: .infinity) }.buttonStyle(.borderedProminent).tint(BC.accent).controlSize(.large)
                Text("No account, nothing leaves the phone. Only a name so the board can greet you.").font(.footnote).foregroundStyle(.secondary)
            }
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
            disabledSignIn("Sign in with Google", "Needs the account service (Supabase + Google sign-in) to be configured by the developer. Not available in this build.")
            disabledSignIn("Continue with e-mail", "Needs the account service. Not available in this build.")
            if let e = authError { Text(e).font(.footnote).foregroundStyle(BC.warn) }
        }
    }
    private func disabledSignIn(_ title: String, _ why: String) -> some View {
        VStack(alignment: .leading, spacing: 3) { Text(title).font(.body.weight(.bold)); Text(why).font(.caption).foregroundStyle(.secondary) }
            .frame(maxWidth: .infinity, alignment: .leading).padding(13)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14)).opacity(0.55)
    }

    // MARK: Stage B
    private func title(_ t: String, _ sub: String) -> some View {
        VStack(alignment: .leading, spacing: 6) { Text(t).font(.system(size: 30, weight: .bold, design: .rounded)); Text(sub).foregroundStyle(.secondary) }
    }
    private func next(_ label: String = "Next") -> some View {
        Button { step += 1 } label: { Text(label).frame(maxWidth: .infinity) }.buttonStyle(.borderedProminent).tint(BC.accent).controlSize(.large)
    }

    private var aboutYou: some View {
        VStack(alignment: .leading, spacing: 14) {
            title("About you", "Used for heart-rate zones and W/kg. Leave anything you don't know empty.")
            Card { Eyebrow(t: "Name"); TextField("First name", text: $store.profile.name).textFieldStyle(.roundedBorder) }
            Card {
                Eyebrow(t: "Birth year")
                TextField("e.g. 1990", text: $birthText).keyboardType(.numberPad).textFieldStyle(.roundedBorder)
                    .onAppear { if let y = store.profile.birthYear { birthText = "\(y)" } }
                    .onChange(of: birthText) { _, v in let y = Int(v); store.profile.birthYear = (y ?? 0) >= 1900 && (y ?? 0) <= Calendar.current.component(.year, from: Date()) ? y : nil }
                Text(store.profile.birthYear == nil ? "Not set: max heart rate stays an age-free estimate until you enter it." : "Age \(store.profile.effectiveAge) → estimated max HR \(store.profile.estimatedMaxHR) bpm (estimate)").font(.footnote).foregroundStyle(.secondary)
            }
            Card {
                HStack { Eyebrow(t: "Weight"); Spacer(); Picker("Units", selection: $store.settings.units) { ForEach(AppSettings.Units.allCases, id: \.self) { Text($0.title).tag($0) } }.pickerStyle(.segmented).frame(width: 150) }
                HStack(alignment: .firstTextBaseline) { Text(weightText).font(BC.numFont); Text(store.settings.units == .imperial ? "lb" : "kg").foregroundStyle(.secondary) }
                Slider(value: $store.profile.weightKg, in: 40...150, step: 0.5).tint(BC.accent).onChange(of: store.profile.weightKg) { _, _ in store.profile.refreshAssumption() }
            }
            next()
        }
    }
    private var weightText: String { store.settings.units == .imperial ? String(format: "%.0f", store.profile.weightKg * 2.20462) : String(format: "%.1f", store.profile.weightKg) }

    private var sportsAndGoal: some View {
        VStack(alignment: .leading, spacing: 14) {
            title("What do you do, and why?", "Pick everything that applies; the plan counts other sports as training load.")
            Card {
                Eyebrow(t: "Sports and activities")
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 130))], spacing: 8) {
                    ForEach(RiderProfile.Sport.allCases, id: \.self) { s in
                        let on = store.profile.sports.contains(s)
                        Button(s.title) { if on { store.profile.sports.removeAll { $0 == s } } else { store.profile.sports.append(s) } }
                            .buttonStyle(.bordered).tint(on ? BC.accent : .secondary).controlSize(.small)
                    }
                }
            }
            Eyebrow(t: "Main goal")
            ForEach(RiderProfile.Goal.onboardingChoices, id: \.self) { g in choice(g.title, g.hint, selected: store.profile.goal == g) { store.profile.goal = g } }
            next()
        }
    }

    private var experienceAndTime: some View {
        VStack(alignment: .leading, spacing: 14) {
            title("Experience and time", "The plan never schedules more hours than you have.")
            ForEach(RiderProfile.Level.allCases, id: \.self) { l in choice(l.title, l.hint, selected: store.profile.level == l) { store.profile.level = l; store.profile.refreshAssumption() } }
            Card {
                Eyebrow(t: "Hours per week")
                HStack(alignment: .firstTextBaseline) { Text("\(store.profile.hoursPerWeek)").font(BC.bigNum); Text("hours").foregroundStyle(.secondary) }
                Slider(value: Binding(get: { Double(store.profile.hoursPerWeek) }, set: { store.profile.hoursPerWeek = Int($0) }), in: 2...14, step: 1).tint(BC.accent)
            }
            next()
        }
    }

    private var heartAndFTP: some View {
        VStack(alignment: .leading, spacing: 14) {
            title("Heart rate and FTP", "Enter what you know. Anything left empty is estimated and labelled as an estimate.")
            Card {
                Eyebrow(t: "Max heart rate (bpm)")
                TextField("if you know it", text: $maxHRText).keyboardType(.numberPad).textFieldStyle(.roundedBorder)
                    .onAppear { if let v = store.profile.maxHR { maxHRText = "\(v)" } }
                    .onChange(of: maxHRText) { _, v in let n = Int(v); store.profile.maxHR = (n ?? 0) >= 100 && (n ?? 0) <= 230 ? n : nil }
                Text(store.profile.maxHR == nil ? "Estimated \(store.profile.estimatedMaxHR) bpm from age until you enter a measured value." : "Entered. Zones use this value.").font(.footnote).foregroundStyle(.secondary)
                Eyebrow(t: "Resting heart rate (bpm, optional)")
                TextField("optional", text: $restHRText).keyboardType(.numberPad).textFieldStyle(.roundedBorder)
                    .onAppear { if let v = store.profile.restHR { restHRText = "\(v)" } }
                    .onChange(of: restHRText) { _, v in let n = Int(v); store.profile.restHR = (n ?? 0) >= 25 && (n ?? 0) <= 120 ? n : nil }
            }
            Card {
                Eyebrow(t: "FTP (watts)")
                TextField("tested FTP, if you have one", text: $ftpText).keyboardType(.numberPad).textFieldStyle(.roundedBorder)
                    .onChange(of: ftpText) { _, v in if let n = Int(v), n >= 50, n <= 600 { store.profile.ftpW = n; store.profile.ftpHow = .tested } else if v.isEmpty, store.profile.ftpHow == .tested { store.profile.ftpHow = .assumed; store.profile.refreshAssumption() } }
                if store.profile.ftpHow == .assumed {
                    Text("Estimate for me: \(store.profile.ftpW) W from \(String(format: "%.0f", store.profile.weightKg)) kg × \(String(format: "%.2f", store.profile.level.wkg)) W/kg. Marked provisional until a real 20-minute effort or a tested value replaces it.").font(.footnote).foregroundStyle(.secondary)
                } else {
                    HStack { Text("\(store.profile.ftpW) W").bold(); Pill(text: store.profile.ftpLabel, color: BC.live) }
                }
            }
            next()
        }
    }

    private var devices: some View {
        VStack(alignment: .leading, spacing: 14) {
            title("Devices and sensors", "Tell the app what you own so it only warns about those. Everything can change later in Connections.")
            Card {
                HStack { Eyebrow(t: "Waveshare BikeComputer"); Spacer(); if device.state == .ready { Pill(text: "connected", color: BC.live) } }
                if device.state == .ready { if let i = device.info { Text("Firmware \(i.fw)").font(.footnote).foregroundStyle(.secondary) } }
                else {
                    Text("Switch it on, tap Connect, type the 6-digit code from its round screen once.").font(.footnote).foregroundStyle(.secondary)
                    if device.state == .scanning, !device.found.isEmpty { ForEach(device.found, id: \.id) { f in Button("Connect to \(f.name) (\(f.rssi) dBm)") { device.connect(to: f.id) } } }
                    Text(device.state.rawValue).font(.caption2).foregroundStyle(.secondary)
                    Button { device.connect() } label: { Text(device.state == .scanning || device.state == .connecting ? "Searching…" : "Connect").frame(maxWidth: .infinity) }.buttonStyle(.borderedProminent).tint(BC.accent)
                }
            }
            Card {
                Eyebrow(t: "I also use")
                toggleRow("Apple Watch", "watch", detail: watch.paired ? "watch paired" : "no watch paired with this iPhone")
                toggleRow("Heart-rate strap (pairs on the board)", "strap", detail: nil)
                toggleRow("Power meter (XDS, pairs on the board)", "meter", detail: nil)
            }
            Text("No BikeComputer? Ride with the phone alone: GPS speed, distance, map and watch heart rate. When a board is connected later it becomes the recorder.").font(.footnote).foregroundStyle(.secondary)
            next(device.state == .ready ? "Next" : "Continue with phone only")
        }
    }
    private func toggleRow(_ title: String, _ key: String, detail: String?) -> some View {
        Toggle(isOn: Binding(get: { store.settings.enabledConnections.contains(key) }, set: { if $0 { store.settings.enabledConnections.insert(key) } else { store.settings.enabledConnections.remove(key) } })) {
            VStack(alignment: .leading) { Text(title); if let d = detail { Text(d).font(.caption2).foregroundStyle(.secondary) } }
        }.tint(BC.accent)
    }

    private var appleHealth: some View {
        VStack(alignment: .leading, spacing: 14) {
            title("Apple Health (optional)", "Three separate things — allow what you want. Shown as connected only after iOS confirms.")
            Card { Eyebrow(t: "Save workouts"); Text("Finished rides saved into Health and Fitness as cycling workouts (one per ride, never duplicated with the watch workout).").font(.footnote) }
            Card { Eyebrow(t: "Read workouts"); Text("Rides from other apps appear in the training calendar (later build).").font(.footnote) }
            Card { Eyebrow(t: "Read heart rate"); Text("Heart-rate history for recovery views (later build). Live heart rate during a ride comes from the Apple Watch workout, not from Health.").font(.footnote) }
            if health.available {
                Button { store.settings.appleHealthWanted = true; health.request { ok in healthResult = ok ? "Permission granted: Apple Health is connected." : "Not granted. You can allow it later in iOS Settings › Health › BikeComputer." } } label: { Text(health.workoutWriteAuthorized ? "Connected ✓" : "Connect Apple Health").frame(maxWidth: .infinity) }.buttonStyle(.borderedProminent).tint(BC.accent).controlSize(.large).disabled(health.workoutWriteAuthorized)
                if let r = healthResult { Text(r).font(.footnote).foregroundStyle(health.workoutWriteAuthorized ? BC.live : BC.stale) }
            } else { Text("Health is not available on this device.").font(.footnote).foregroundStyle(.secondary) }
            Button("Not now") { step += 1 }.frame(maxWidth: .infinity)
            if health.workoutWriteAuthorized { next() }
        }
    }

    private var ready: some View {
        VStack(alignment: .leading, spacing: 14) {
            title("Ready", "Here is what the app will use. Anything marked estimate or not set can be completed later in Profile.")
            Card {
                row("Name", store.profile.name.isEmpty ? "not set" : store.profile.name)
                row("Account", store.guest ? "guest (this phone only)" : "Apple")
                row("Birth year", store.profile.birthYear.map(String.init) ?? "not set")
                row("Weight", String(format: "%.1f kg", store.profile.weightKg))
                row("Goal", store.profile.goal.title); row("Experience", store.profile.level.title); row("Hours / week", "\(store.profile.hoursPerWeek) h")
                row("Max HR", store.profile.maxHR.map { "\($0) bpm" } ?? "\(store.profile.estimatedMaxHR) bpm (estimate)")
                row("FTP", "\(store.profile.ftpW) W (\(store.profile.ftpLabel))")
                row("BikeComputer", device.state == .ready ? "connected" : "phone-only for now")
                row("Apple Health", health.workoutWriteAuthorized ? "connected" : "not connected")
            }
            if device.state == .ready, device.info?.hasProfileSync == true { Text("The board will be asked for its profile; if it differs you decide which one wins (Connections › BikeComputer › Sync status).").font(.footnote).foregroundStyle(.secondary) }
            Button { store.onboardingStage = 0; store.onboarded = true } label: { Text("Start").frame(maxWidth: .infinity) }.buttonStyle(.borderedProminent).tint(BC.live).controlSize(.large)
        }
    }
    private func row(_ k: String, _ v: String) -> some View { HStack { Text(k).foregroundStyle(.secondary); Spacer(); Text(v).multilineTextAlignment(.trailing) }.font(.footnote) }

    private func choice(_ title: String, _ hint: String, selected: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                VStack(alignment: .leading, spacing: 3) { Text(title).font(.body.weight(.bold)); Text(hint).font(.caption).foregroundStyle(.secondary) }
                Spacer(); if selected { Image(systemName: "checkmark.circle.fill").foregroundStyle(BC.accent) }
            }
            .frame(maxWidth: .infinity, alignment: .leading).padding(13)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(selected ? BC.accent : Color.clear, lineWidth: 2))
        }.buttonStyle(.plain)
    }
}
