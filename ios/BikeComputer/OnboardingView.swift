import SwiftUI

/// Two-stage first run.
/// Stage A — "Get started": first name only. Cyclift 1.0 has no accounts (ReleaseFlags.accountsEnabled), so there is no
/// sign-in of any kind here; everything stays on the phone.
/// Stage B — progressive fitness & device profile, one question per screen, every screen skippable. Nothing unknown is
/// invented: skipped values stay empty (nil) and the app says "not set" instead of showing a number.
struct OnboardingView: View {
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var device: DeviceLink
    @EnvironmentObject private var watch: WatchLink
    @EnvironmentObject private var health: HealthAccess
    @State private var step = 0
    @State private var guestName = ""
    @State private var birthText = ""
    @State private var ftpText = ""
    @State private var maxHRText = ""
    @State private var restHRText = ""
    @State private var healthResult: String?
    @State private var showDays = false
    @State private var daysDraft: WeeklyAvailability? = nil
    @State private var showHybrid = false
    private let lastStep = 9

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if step > 0 { ProgressView(value: Double(step), total: Double(lastStep)).tint(BC.accent).padding(.horizontal).padding(.top, 6) }
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        switch step {
                        case 0: welcome
                        case 1: modeStep
                        case 2: weekStep
                        case 3: daysStep
                        case 4: aboutYou
                        case 5: sportsAndGoal
                        case 6: heartAndFTP
                        case 7: devices
                        case 8: appleHealth
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
            HStack(spacing: 10) { CycliftMark(size: 44); Text("Cyclift").font(.system(size: 36, weight: .bold, design: .rounded)) }
            Text("Cycling and strength training in one plan, with one coach. Works with your iPhone alone, standard Bluetooth sensors, Apple Watch and Apple Health — and with the optional BikeComputer device.").foregroundStyle(.secondary)
            Card {
                Eyebrow(t: "Get started")
                TextField("Your first name", text: $guestName).textFieldStyle(.roundedBorder).textContentType(.givenName).accessibilityIdentifier("onboardingName")
                Button { store.guest = true; store.profile.name = guestName.trimmingCharacters(in: .whitespaces); step = 1 } label: { Text("Continue").frame(maxWidth: .infinity) }.buttonStyle(.borderedProminent).tint(BC.accent).controlSize(.large).accessibilityIdentifier("onboardingContinue")
                Text("Everything you enter stays on this iPhone. The first name is only used so the app (and a paired BikeComputer) can greet you.").font(.footnote).foregroundStyle(.secondary)
            }
        }
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

    // MARK: 0.6.0 — training mode, then the week (frequencies, priority, time, days). Short and skippable.
    private var modeStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            title("How do you train?", "One coach for everything you pick. You can change this any time in Profile › Training profile.")
            ForEach(TrainingMode.allCases, id: \.self) { m in choice(m.title, m.hint, selected: store.profile.trainingMode == m) { store.updateProfile { p in p.trainingMode = m; if m == .cycling { p.liftDaysPerWeek = 0; p.liftingHoursPerWeek = 0 } else if p.liftDaysPerWeek == 0 { p.liftDaysPerWeek = 2; p.liftingHoursPerWeek = 2 }; if m == .strength { p.priority = .strength } else if m == .cycling { p.priority = .cycling } } } }
            if store.profile.trainingMode == .hybrid {
                Card {
                    Eyebrow(t: "Main priority")
                    Picker("Priority", selection: Binding(get: { store.profile.priority }, set: { v in store.updateProfile { $0.priority = v } })) { ForEach(TrainingPriority.allCases, id: \.self) { Text($0.title).tag($0) } }.pickerStyle(.segmented)
                    Text("Decides which session comes first on a shared day and which sport the coach protects when time is short.").font(.footnote).foregroundStyle(.secondary)
                }
            }
            Card {
                Eyebrow(t: "Experience")
                Picker("Level", selection: Binding(get: { store.profile.level }, set: { v in store.updateProfile { $0.level = v; $0.refreshAssumption() } })) { ForEach(RiderProfile.Level.allCases, id: \.self) { Text($0.title).tag($0) } }.pickerStyle(.segmented)
                Text(store.profile.level.hint).font(.footnote).foregroundStyle(.secondary)
            }
            next()
        }
    }

    private var weekStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            title("Your week", "Frequency, time and the days you prefer. The plan is built around these and never schedules more.")
            if store.profile.trainingMode.includesCycling {
                Card {
                    Eyebrow(t: "Cycling")
                    Stepper("\(store.profile.cyclingDaysPerWeek) ride\(store.profile.cyclingDaysPerWeek == 1 ? "" : "s") a week", value: Binding(get: { store.profile.cyclingDaysPerWeek }, set: { v in store.updateProfile { $0.cyclingDaysPerWeek = v } }), in: 1...6)
                    Stepper("\(store.profile.hoursPerWeek) h riding a week", value: Binding(get: { store.profile.hoursPerWeek }, set: { v in store.updateProfile { $0.hoursPerWeek = v } }), in: 1...20)
                }
            }
            if store.profile.trainingMode.includesLifting {
                Card {
                    Eyebrow(t: "Strength")
                    Stepper("\(store.profile.liftDaysPerWeek) lift\(store.profile.liftDaysPerWeek == 1 ? "" : "s") a week", value: Binding(get: { store.profile.liftDaysPerWeek }, set: { v in store.updateProfile { $0.liftDaysPerWeek = v } }), in: 1...6)
                    Stepper("\(store.profile.liftingHoursPerWeek) h lifting a week", value: Binding(get: { store.profile.liftingHoursPerWeek }, set: { v in store.updateProfile { $0.liftingHoursPerWeek = v } }), in: 1...12)
                    Text("Cycling hours and lifting hours are tracked separately everywhere.").font(.footnote).foregroundStyle(.secondary)
                }
            }
            Card {
                Eyebrow(t: "Preferred days (optional)")
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 4) {
                    ForEach(0..<7, id: \.self) { i in
                        let on = store.profile.preferredDays.contains(i)
                        Button { store.updateProfile { p in if on { p.preferredDays.removeAll { $0 == i } } else { p.preferredDays.append(i); p.preferredDays.sort() } } } label: {
                            Text(WeeklyAvailability.dayNames[i]).font(.footnote.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.6).frame(maxWidth: .infinity, minHeight: 44)
                                .background(on ? BC.accent.opacity(0.2) : Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10)).foregroundStyle(on ? BC.accent : .primary)
                        }.buttonStyle(.plain).accessibilityLabel(WeeklyAvailability.longDayNames[i]).accessibilityAddTraits(on ? .isSelected : [])
                    }
                }
                Text(store.profile.preferredDays.isEmpty ? "None picked: a sensible week is suggested; refine days and durations later in Plan › Days." : "Sessions go on these days first; the long ride takes the first weekend day you picked.").font(.footnote).foregroundStyle(.secondary)
            }
            if store.profile.trainingMode == .hybrid {
                // adaptive coach: the hybrid answers (all optional, skippable; editable later in Profile › Training profile)
                Card {
                    Eyebrow(t: "Hybrid plan (optional)")
                    Text(hybridSummary).font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    Button { showHybrid = true } label: { Label("Goal, training days, split, equipment", systemImage: "slider.horizontal.3").frame(maxWidth: .infinity) }.buttonStyle(.bordered).accessibilityIdentifier("onboardingHybridPlan")
                }
            }
            next()
        }
        .sheet(isPresented: $showHybrid) { HybridPlanEditor(asSheet: true) }
    }

    private var hybridSummary: String {
        let p = store.profile
        var parts: [String] = []
        if let g = p.hybridGoal { parts.append("Goal: \(g.title.lowercased())") }
        if let d = p.trainingDaysPerWeek { parts.append("\(d) training days") }
        if let s = p.strengthSplit { parts.append("split: \(s.title)") }
        return parts.isEmpty ? "Primary goal, total training days, session length, strength split (or your own), equipment and the routines to keep. Skip it and the coach decides." : parts.joined(separator: " · ")
    }

    // MARK: 0.7.0 — what exactly happens each day (type, duration, fixed/flexible), with a readable preview
    private var daysStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            title("Your days", "Say what happens Monday to Sunday — ride, lift, both, rest or flexible — with the type and the time for each. The coach plans around it and never adds a day.")
            let a = daysDraft ?? WeeklyAvailability.suggested(for: store.profile)
            Card {
                HStack { Eyebrow(t: daysDraft == nil ? "Suggested from your answers" : "Your days"); Spacer(); Text("\(a.cycleDays) ride · \(a.liftDays) lift").font(.caption).foregroundStyle(.secondary) }
                ForEach(0..<7, id: \.self) { i in PreviewDayRow(index: i, day: a.days[i]) }
                let issues = a.consistency(profile: store.profile)
                ForEach(issues, id: \.self) { Text($0).font(.caption).foregroundStyle(BC.warn).fixedSize(horizontal: false, vertical: true) }
                if issues.isEmpty { Text("Frequency, durations and both budgets agree.").font(.caption).foregroundStyle(BC.live) }
                Button { showDays = true } label: { Label("Edit my days", systemImage: "calendar.badge.clock").frame(maxWidth: .infinity) }.buttonStyle(.bordered)
            }
            Text("Cycling hours and lifting hours stay separate budgets; nothing above \(store.profile.hoursPerWeek) h riding\(store.profile.trainingMode.includesLifting ? " or \(store.profile.liftingHoursPerWeek) h lifting" : "") is ever generated.").font(.footnote).foregroundStyle(.secondary)
            next()
        }
        .sheet(isPresented: $showDays) { AvailabilityEditor(onSave: { daysDraft = $0 }) }
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
                    .onChange(of: ftpText) { _, v in if let n = Int(v), n >= 50, n <= 600 { store.profile.ftpW = n; store.profile.ftpHow = .entered } else if v.isEmpty, store.profile.ftpHow == .entered || store.profile.ftpHow == .tested { store.profile.ftpHow = .assumed; store.profile.refreshAssumption() } }
                if store.profile.ftpHow == .assumed {
                    Text("Estimate for me: \(store.profile.ftpW) W from \(String(format: "%.0f", store.profile.weightKg)) kg × \(String(format: "%.2f", store.profile.level.wkg)) W/kg. Marked provisional until a real 20-minute effort or a tested value replaces it.").font(.footnote).foregroundStyle(.secondary)
                } else {
                    HStack { Text("\(store.profile.ftpW) W").bold(); FTPConfidencePill(profile: store.profile) }
                }
            }
            next()
        }
    }

    private var devices: some View {
        VStack(alignment: .leading, spacing: 14) {
            title("Devices and sensors", "Tell the app what you own so it only warns about those. Everything can change later in Connections.")
            Card {
                HStack { Eyebrow(t: "BikeComputer (optional)"); Spacer(); if device.state == .ready { Pill(text: "connected", color: BC.live) } }
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
                toggleRow("Heart-rate strap (on the phone or the BikeComputer)", "strap", detail: nil)
                toggleRow("Power meter (Bluetooth, on the phone or the BikeComputer)", "meter", detail: nil)
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
            title("Apple Health (optional)", "Allow what you want. Shown as connected only after iOS confirms.")
            Card { Eyebrow(t: "Save workouts"); Text("Cycling workouts you record with the Cyclift Apple Watch app are saved to Health and Fitness when you choose Save at the end.").font(.footnote) }
            Card { Eyebrow(t: "Import workouts"); Text("Cycling and strength workouts from other apps or your Apple Watch appear in Plan › History as rides and strength sessions (marked Apple Health, never duplicated).").font(.footnote); Toggle("Import my workouts", isOn: $store.settings.appleHealthImportWorkouts).tint(BC.accent) }
            Card { Eyebrow(t: "Heart rate"); Text("Live heart rate during a ride comes from the Cyclift Apple Watch workout or a Bluetooth heart-rate sensor, not from Health.").font(.footnote) }
            if health.available {
                Button { store.settings.appleHealthWanted = true; health.request { ok in healthResult = ok ? "Permission granted: Apple Health is connected." : "Not granted. You can allow it later in iOS Settings › Health › Cyclift." } } label: { Text(health.workoutWriteAuthorized ? "Connected ✓" : "Connect Apple Health").frame(maxWidth: .infinity) }.buttonStyle(.borderedProminent).tint(BC.accent).controlSize(.large).disabled(health.workoutWriteAuthorized)
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
                row("Data", "on this iPhone")
                row("Birth year", store.profile.birthYear.map(String.init) ?? "not set")
                row("Weight", String(format: "%.1f kg", store.profile.weightKg))
                row("Mode", store.profile.trainingMode.title + (store.profile.trainingMode == .hybrid ? " · \(store.profile.priority.title.lowercased()) priority" : ""))
                row("Goal", store.profile.goal.title); row("Experience", store.profile.level.title)
                row("Cycling", store.profile.trainingMode.includesCycling ? "\(store.profile.cyclingDaysPerWeek) rides · \(store.profile.hoursPerWeek) h/week" : "—")
                if store.profile.trainingMode.includesLifting { row("Strength", "\(store.profile.liftDaysPerWeek) lifts · \(store.profile.liftingHoursPerWeek) h/week") }
                row("Days", daysDraft == nil ? "suggested from your answers" : "\(daysDraft!.cycleDays) ride · \(daysDraft!.liftDays) lift · \(daysDraft!.fixedAssignments) fixed")
                row("Max HR", store.profile.maxHR.map { "\($0) bpm" } ?? "\(store.profile.estimatedMaxHR) bpm (estimate)")
                row("FTP", "\(store.profile.ftpW) W (\(store.profile.ftpLabel))")
                row("BikeComputer", device.state == .ready ? "connected" : "phone-only for now")
                row("Apple Health", health.workoutWriteAuthorized ? "connected" : "not connected")
            }
            if device.state == .ready, device.info?.hasProfileSync == true { Text("The board will be asked for its profile; if it differs you decide which one wins (Connections › BikeComputer › Sync status).").font(.footnote).foregroundStyle(.secondary) }
            Button { store.onboardingStage = 0; store.availability = daysDraft; _ = store.regenerate(weekOf: Date(), replaceEdited: true); _ = store.regenerate(weekOf: Calendar.current.date(byAdding: .day, value: 7, to: Date())!, replaceEdited: true); store.onboarded = true } label: { Text("Start").frame(maxWidth: .infinity) }.buttonStyle(.borderedProminent).tint(BC.live).controlSize(.large)
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
