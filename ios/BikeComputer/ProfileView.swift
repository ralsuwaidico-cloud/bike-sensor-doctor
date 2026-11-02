import SwiftUI

// Profile (V1): the root screen and the focused editors live in ProfileScreens.swift / ProfileEditors.swift. This file keeps
// the pages they open — heart rate, power & cycling, sports, exercises and the data section.

/// A numeric field that only writes a valid value (or nil when cleared) — never a half-typed number.
struct NumberRow: View {
    let title: String; let placeholder: String
    @Binding var text: String
    let range: ClosedRange<Int>
    let commit: (Int?) -> Void
    var body: some View {
        HStack {
            Text(title); Spacer()
            TextField(placeholder, text: $text).keyboardType(.numberPad).multilineTextAlignment(.trailing).frame(width: 110)
                .onChange(of: text) { _, v in
                    if v.isEmpty { commit(nil); return }
                    if let n = Int(v), range.contains(n) { commit(n) }
                }
        }
    }
}

// MARK: - Heart rate
struct HeartRatePage: View {
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var watch: WatchLink
    @EnvironmentObject private var device: DeviceLink
    @State private var rest = ""
    @State private var maxHR = ""
    @State private var lthr = ""
    var body: some View {
        Form {
            Section {
                NumberRow(title: "Resting HR", placeholder: "not set", text: $rest, range: 25...120) { v in store.updateProfile { $0.setRestHR(v) } }.onAppear { rest = store.profile.restHR.map(String.init) ?? "" }
                NumberRow(title: "Max HR", placeholder: store.profile.maxHRForZones.map { "\($0) estimated" } ?? "not set", text: $maxHR, range: 100...230) { v in store.updateProfile { $0.setMaxHR(v) } }.onAppear { maxHR = store.profile.maxHR.map(String.init) ?? "" }
                NumberRow(title: "Threshold HR (LTHR)", placeholder: "not set", text: $lthr, range: 80...220) { v in store.updateProfile { $0.lthr = v } }.onAppear { lthr = store.profile.lthr.map(String.init) ?? "" }
            } header: { Text("Values") } footer: { Text(store.profile.maxHR != nil ? "Max heart rate entered by you." : store.profile.maxHRForZones != nil ? "Max heart rate is estimated from your age (208 − 0.7 × age) until you enter a measured value." : "No max heart rate: enter one, or set your date of birth in Profile for an age-based estimate. Until then there are no heart-rate zones.") }
            Section {
                Picker("Zone method", selection: $store.profile.hrZoneMethod) { ForEach(RiderProfile.HRZoneMethod.allCases, id: \.self) { Text($0.title).tag($0) } }
                if store.profile.hrZoneMethod == .lthr, store.profile.lthr == nil { Text("Enter your LTHR above; until then zones use max heart rate.").font(.footnote).foregroundStyle(BC.stale) }
                if let zones = store.profile.hrZones {
                    ForEach(Array(zones.enumerated()), id: \.offset) { i, z in
                        HStack { Text("Z\(i + 1)").font(.caption.weight(.heavy)).padding(.horizontal, 7).padding(.vertical, 3).background(BC.zone(i + 1), in: Capsule()).foregroundStyle(.white); Text(HrZones.names[i].dropFirst(3)).font(.footnote); Spacer(); Text("\(z.lo)–\(z.hi.map(String.init) ?? "∞") bpm").font(.footnote).monospacedDigit() }
                    }
                } else {
                    Text("Unknown — no max or threshold heart rate yet.").font(.footnote).foregroundStyle(.secondary)
                }
            } header: { Text("Heart-rate zones") }
            Section {
                Picker("Preferred source", selection: $store.settings.hrPref) { ForEach(AppSettings.HRPref.allCases, id: \.self) { Text($0.title).tag($0) } }
                LabeledContent("Apple Watch", value: watch.hrIsFresh ? "heart rate live" : watch.appInstalled ? "app installed · start the workout" : "no watch app")
                LabeledContent("Strap via BikeComputer", value: device.state == .ready && device.live?.hrSource == .bleStrap ? "live" : "pairs on the board")
            } header: { Text("Sources") } footer: { Text("Live heart rate comes from the Apple Watch (via this phone), a Bluetooth heart-rate sensor paired with this phone, or a strap paired on the BikeComputer. The coach uses whichever is live; nothing is shown without a live source.") }
        }
        .navigationTitle("Heart rate").navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Power & cycling
struct PowerCyclingPage: View {
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var device: DeviceLink
    @State private var ftpText = ""
    @State private var wheel = ""
    @State private var preview: PreviewRef? = nil
    var body: some View {
        Form {
            Section {
                // RC3 / ENG-E1: an unknown FTP stays "Unknown" — never a number from weight × level
                LabeledContent("FTP", value: "\(store.profile.ftpDisplay) · \(store.profile.ftpSource.title)")
                    .accessibilityIdentifier("ftpValue")
                HStack {
                    TextField("FTP in watts", text: $ftpText).keyboardType(.numberPad)
                    // a typed value is "Entered" — only a recorded FTP test ride with verified power is "Tested"
                    Button("Set") { if let v = Int(ftpText), v >= 50, v <= 600 { preview = store.changeTraining(cause: .ftp) { $0.profile.setFTP(v, source: .entered) }; ftpText = "" } }
                        .disabled(Int(ftpText).map { $0 < 50 || $0 > 600 } ?? true).frame(minHeight: DS.minTap)
                }
                if store.profile.ftpKnown {
                    Button("I don't know my FTP") { preview = store.changeTraining(cause: .ftp) { $0.profile.setFTP(nil, source: .unknown) } }.font(.footnote)
                }
                if let s = store.ftpSuggestion { Text("Suggested from your \(s.rideDate.dayAndDate) ride: \(s.watts) W. Accept it on Home or Progress.").font(.footnote).foregroundStyle(BC.accent) }
            } header: { Text("FTP") } footer: { Text(store.profile.ftpKnown ? ftpMethod : "Rides use heart rate and effort until you enter an FTP or do an FTP test.") }
            if store.profile.ftpKnown {
                Section("Power zones") {
                    ZoneBar()
                    ForEach(Array(store.profile.powerZones.enumerated()), id: \.offset) { i, z in
                        HStack { ZonePill(z: i + 1); Text(PowerZones.names[i].dropFirst(3)).font(.footnote); Spacer(); Text("\(z.lo)–\(z.hi.map(String.init) ?? "∞") W").font(.footnote).monospacedDigit() }
                    }
                }
            }
            Section {
                LabeledContent("Power meter", value: meterText)
                Pill(text: "power unverified until validated", color: BC.stale)
                Text("Cyclift does not calibrate power meters: it only reads them and never writes to the meter's control point (safety rule). Pair and forget the meter on the board's Connections › Power meter.").font(.footnote).foregroundStyle(.secondary)
            } header: { Text("Power meter") }
            Section {
                Stepper("Low: \(store.profile.cadenceLow) rpm", value: Binding(get: { store.profile.cadenceLow }, set: { v in store.updateProfile { $0.cadenceLow = min(v, $0.cadenceHigh - 5) } }), in: 50...110, step: 5)
                Stepper("High: \(store.profile.cadenceHigh) rpm", value: Binding(get: { store.profile.cadenceHigh }, set: { v in store.updateProfile { $0.cadenceHigh = max(v, $0.cadenceLow + 5) } }), in: 60...130, step: 5)
            } header: { Text("Cadence preference") } footer: { Text("The ride coach asks you to pedal faster or slower outside this range.") }
            Section {
                TextField("Bike name (optional)", text: Binding(get: { store.profile.bikeName ?? "" }, set: { v in store.updateProfile { $0.bikeName = v.isEmpty ? nil : v } }))
                NumberRow(title: "Wheel circumference (mm)", placeholder: "2096", text: $wheel, range: 1000...2600) { v in store.updateProfile { $0.wheelMm = v ?? 2096 } }.onAppear { wheel = "\(store.profile.wheelMm)" }
                Text("Used by a speed sensor on the board (firmware 0.6.0, Connections › Speed). 700×25c ≈ 2105 mm, 700×28c ≈ 2136 mm. \(device.info?.hasSettings == true ? "Sent to the board with the device settings." : "Stored on this phone until the board supports it.")").font(.footnote).foregroundStyle(.secondary)
            } header: { Text("Bike") }
        }
        .navigationTitle("Power & cycling").navigationBarTitleDisplayMode(.inline)
        .sheet(item: $preview) { r in PlanChangeSheet(proposalId: r.id) }
    }
    private var ftpMethod: String {
        let p = store.profile
        return p.ftpSourceText + (p.ftpCaution.map { " " + $0 } ?? "")
    }
    private var meterText: String {
        guard device.state == .ready, let l = device.live else { return device.remembered ? "via the BikeComputer (not connected)" : "pairs on the board" }
        switch l.meterLink { case 4: return "connected (direct on the board)"; case 1: return "not paired"; case 2: return "searching"; case 3: return "connecting"; case 5: return "reconnecting"; default: return "off" }
    }
}

struct SportsPicker: View {
    @EnvironmentObject private var store: Store
    var body: some View {
        List {
            ForEach(RiderProfile.Sport.allCases, id: \.self) { sp in
                let on = store.profile.sports.contains(sp)
                Button { if on { store.profile.sports.removeAll { $0 == sp } } else { store.profile.sports.append(sp) } } label: { HStack { Text(sp.title).foregroundStyle(.primary); Spacer(); if on { Image(systemName: "checkmark").foregroundStyle(BC.accent) } } }
            }
            Section { Text("Other sports count toward your weekly load so the plan does not overload the bike days.").font(.footnote).foregroundStyle(.secondary) }
        }.navigationTitle("Sports")
    }
}

struct DeviceRow: View {
    let name: String; let status: String; let live: Bool; let caps: [String]
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack { StatusDot(color: live ? BC.live : .secondary); Text(name).font(.subheadline.weight(.semibold)); Spacer(); Text(status).font(.caption).foregroundStyle(live ? BC.live : .secondary).multilineTextAlignment(.trailing) }
            HStack(spacing: 4) { ForEach(caps, id: \.self) { c in Pill(text: c, color: c.hasPrefix("LIVE") ? BC.live : c.hasPrefix("CLOUD") ? BC.accent : .secondary) } }
        }.padding(.vertical, 2)
    }
}

/// The rider's own exercises (built-in ones are listed read-only in the search sheet).
struct MyExercisesView: View {
    @EnvironmentObject private var store: Store
    @State private var create = false
    var body: some View {
        List {
            Section { Text("\(ExerciseCatalogue.builtIn.count) built-in exercises are searchable by name, equipment, movement and muscle when you log a session. Add anything missing here; your exercises appear first.").font(.footnote).foregroundStyle(.secondary) }
            Section("Your exercises") {
                if store.customExercises.isEmpty { Text("None yet.").foregroundStyle(.secondary) }
                ForEach(store.customExercises) { e in VStack(alignment: .leading, spacing: 2) { Text(e.name); Text("\(e.pattern.title) · \(e.equipmentText)").font(.caption).foregroundStyle(.secondary) } }
                    .onDelete { idx in for i in idx { store.removeCustomExercise(store.customExercises[i]) } }
                Button { create = true } label: { Label("New exercise", systemImage: "plus") }
            }
        }
        .navigationTitle("My exercises").navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $create) { CreateExerciseSheet(initialName: "") { store.addCustomExercise($0) } }
    }
}

/// Profile › Your data (Cyclift 1.0 has no accounts): where the data lives, export (JSON share sheet) and the local
/// wipe (App Review 5.1.1 v: everything the app stores can be deleted in-app; there is no server copy to delete).
/// The section only flips state owned by the Profile list: a sheet or alert attached to a row inside a List is torn
/// down when the list re-renders that row.
struct YourDataSection: View {
    @Binding var exportURL: URL?
    @Binding var confirmDelete: Bool
    @State private var exportError: String?
    let snapshot: () -> StoreFile

    var body: some View {
        Section {
            Label("Your data stays on this iPhone", systemImage: "iphone")
            Button { export() } label: { Label("Export my data", systemImage: "square.and.arrow.up") }.accessibilityIdentifier("exportData")
            if let e = exportError { Text(e).font(.footnote).foregroundStyle(BC.warn) }
            Button(role: .destructive) { confirmDelete = true } label: { Label("Delete all data on this phone", systemImage: "trash") }.accessibilityIdentifier("deleteAllData")
        } header: { Text("Your data") } footer: {
            Text("Profile, plan, rides, strength sessions and templates are stored only in Cyclift on this iPhone. Export creates one JSON file with all of it.")
        }
    }

    private func export() {
        exportError = nil
        let enc = JSONEncoder(); enc.outputFormatting = [.prettyPrinted, .sortedKeys]; enc.dateEncodingStrategy = .iso8601
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("cyclift-export-\(Int(Date().timeIntervalSince1970)).json")
        do { try enc.encode(snapshot()).write(to: url, options: .atomic); exportURL = url }
        catch { exportError = "Export failed: \(error.localizedDescription)" }
    }
}
