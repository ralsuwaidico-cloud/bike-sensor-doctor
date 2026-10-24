import SwiftUI

/// Settings that live on the BikeComputer, controlled from the phone (Link v1.2 SETTINGS, firmware 0.6.0). Only controls
/// the connected firmware reports in `supported_mask` are shown; each change waits for the board's reply and shows
/// synced / failed. Nothing here is a phone-side copy pretending to be applied.
struct DeviceSettingsView: View {
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var device: DeviceLink
    @EnvironmentObject private var sync: ProfileSync
    @State private var brightness = 80.0
    @State private var timeout = 60
    @State private var wake = 0
    @State private var autoSleep = 0
    @State private var layout = 0
    @State private var cue = true
    @State private var link = true
    @State private var hrPref = 0
    @State private var unitsImperial = false
    @State private var loaded = false

    private var s: BCLink.SettingsMessage? { device.boardSettings }
    private var supported: Bool { device.state == .ready && device.info?.hasSettings == true }

    var body: some View {
        Form {
            if !supported {
                Section { Text(device.state == .ready ? "Device settings from the phone need firmware 0.6.0 (board has \(device.info?.fw ?? "?")). Change them on the board: swipe down › Quick Settings." : "Connect the BikeComputer to read its settings.").font(.footnote).foregroundStyle(.secondary) }
            } else if s == nil {
                Section { HStack { ProgressView(); Text("Reading settings from the board…") }; Button("Read again") { device.settingsGet() } }
            } else {
                Section {
                    HStack { Text(sync.settingsPending ? "Sending…" : sync.settingsState).font(.footnote).foregroundStyle(sync.settingsState.hasPrefix("failed") || sync.settingsState.hasPrefix("no reply") ? BC.warn : .secondary); Spacer(); if sync.settingsPending { ProgressView() } }
                    if let v = s?.version { Text("Settings version on the board: \(v) · read \(device.boardSettingsAt?.formatted(date: .omitted, time: .shortened) ?? "")").font(.caption2).foregroundStyle(.secondary) }
                } header: { Text("Sync") }
                Section("Display") {
                    if sync.supports(tag: 2) {
                        VStack(alignment: .leading) {
                            HStack { Text("Brightness"); Spacer(); Text("\(Int(brightness)) %").foregroundStyle(.secondary) }
                            Slider(value: $brightness, in: 10...100, step: 5, onEditingChanged: { editing in if !editing { var m = BCLink.SettingsMessage(); m.brightnessPct = Int(brightness); sync.apply(m) } })
                        }
                    }
                    if sync.supports(tag: 3) {
                        Picker("Screen timeout (outside rides)", selection: $timeout) { Text("30 s").tag(30); Text("1 min").tag(60); Text("2 min").tag(120); Text("5 min").tag(300); Text("Never").tag(0) }
                            .onChange(of: timeout) { _, v in guard loaded else { return }; var m = BCLink.SettingsMessage(); m.screenTimeoutS = v; sync.apply(m) }
                    }
                    if sync.supports(tag: 4) {
                        Picker("Wake gesture", selection: $wake) { Text("Triple tap").tag(0); Text("Double tap").tag(1); Text("Any touch (rides only)").tag(2) }
                            .onChange(of: wake) { _, v in guard loaded else { return }; var m = BCLink.SettingsMessage(); m.wakeGesture = v; sync.apply(m) }
                        Text("Wake reliability is being verified on the hardware; RESET and USB always wake the board.").font(.footnote).foregroundStyle(.secondary)
                    }
                    if sync.supports(tag: 8) {
                        Picker("Ride screen layout", selection: $layout) { Text("A").tag(0); Text("B").tag(1); Text("C").tag(2) }
                            .onChange(of: layout) { _, v in guard loaded else { return }; var m = BCLink.SettingsMessage(); m.rideLayout = v; sync.apply(m) }
                    }
                    if sync.supports(tag: 9) {
                        Toggle("Wake the screen on a coach cue (rides)", isOn: $cue).onChange(of: cue) { _, v in guard loaded else { return }; var m = BCLink.SettingsMessage(); m.wakeOnCue = v; sync.apply(m) }
                    }
                }
                Section {
                    if sync.supports(tag: 5) {
                        Toggle("Phone link on the board", isOn: $link).onChange(of: link) { _, v in guard loaded else { return }; var m = BCLink.SettingsMessage(); m.phoneLinkEnabled = v; sync.apply(m) }
                    }
                    if sync.supports(tag: 7) {
                        Picker("Deep sleep after idle (connectivity off)", selection: $autoSleep) { Text("Off").tag(0); Text("10 min").tag(10); Text("30 min").tag(30); Text("60 min").tag(60) }
                            .onChange(of: autoSleep) { _, v in guard loaded else { return }; var m = BCLink.SettingsMessage(); m.autoSleepMin = v; sync.apply(m) }
                    }
                } header: { Text("Connectivity and power") } footer: { Text("Switching the phone link off disconnects this phone about 1.5 s after the board confirms; switch it back on at the board (Quick Settings). Display off and standby keep Bluetooth on; deep sleep turns it off and is explained on the board.") }
                Section("Sensors and units") {
                    if sync.supports(tag: 6) {
                        Picker("Heart-rate source", selection: $hrPref) { Text("Strap first").tag(0); Text("Watch first").tag(1) }
                            .onChange(of: hrPref) { _, v in guard loaded else { return }; var m = BCLink.SettingsMessage(); m.hrPref = v; sync.apply(m); store.settings.hrPref = v == 1 ? .watch : .strap }
                    }
                    if sync.supports(tag: 10) {
                        Toggle("Imperial units on the board", isOn: $unitsImperial).onChange(of: unitsImperial) { _, v in guard loaded else { return }; var m = BCLink.SettingsMessage(); m.units = v ? 1 : 0; sync.apply(m) }
                    }
                    Text("Sensor pairing (power meter, strap) is done on the board: Settings › Sensors.").font(.footnote).foregroundStyle(.secondary)
                }
                Section("Diagnostics") {
                    if let i = device.info { LabeledContent("Firmware", value: i.fw); LabeledContent("Protocol", value: "v\(i.verMajor).\(i.verMinor) · caps 0x\(String(i.caps, radix: 16))") }
                    if let r = device.rssi { LabeledContent("Signal", value: "\(r) dBm") }
                    LabeledContent("Live messages", value: "\(device.stats.liveMsgs)"); LabeledContent("Rejected messages", value: "\(device.stats.rejected)"); LabeledContent("Link drops", value: "\(device.stats.disconnects)")
                    Button("Read settings again") { device.settingsGet() }
                }
            }
            if device.info?.hasWiFi == true { Section { NavigationLink("Wi-Fi setup") { WiFiSetupView() } } }
            Section { NavigationLink("Profile sync status") { SyncStatusView() } }
        }
        .navigationTitle("Device settings")
        .onAppear { load() }
        .onChange(of: device.boardSettings) { _, _ in load() }
    }

    private func load() {
        guard let s else { return }
        loaded = false
        if let v = s.brightnessPct { brightness = Double(v) }
        if let v = s.screenTimeoutS { timeout = [0, 30, 60, 120, 300].contains(v) ? v : 60 }
        if let v = s.wakeGesture { wake = v }
        if let v = s.autoSleepMin { autoSleep = [0, 10, 30, 60].contains(v) ? v : 0 }
        if let v = s.rideLayout { layout = v }
        if let v = s.wakeOnCue { cue = v }
        if let v = s.phoneLinkEnabled { link = v }
        if let v = s.hrPref { hrPref = v }
        if let v = s.units { unitsImperial = v == 1 }
        DispatchQueue.main.async { loaded = true }
    }
}

/// Wi-Fi setup for the board over the encrypted phone link (Link v1.2 WIFI_*). The password goes to the board once and
/// is kept nowhere on the phone.
struct WiFiSetupView: View {
    @EnvironmentObject private var device: DeviceLink
    @State private var selected: BCLink.WiFiNetwork?
    @State private var password = ""
    @State private var showPassword = false
    @State private var manualSSID = ""
    @State private var showManual = false
    @State private var sentAt: Date?
    private let timer = Timer.publish(every: 5, on: .main, in: .common).autoconnect()

    var body: some View {
        List {
            Section {
                if let s = device.wifiStatus {
                    HStack { StatusBadge(status: statusColour(s)); VStack(alignment: .leading) { Text(s.state.label).bold(); if !s.ssid.isEmpty { Text(s.ssid + (s.rssi.map { " · \($0) dBm" } ?? "")).font(.footnote).foregroundStyle(.secondary) } }; Spacer(); if s.state == .connecting || s.state == .scanning { ProgressView() } }
                    if let e = s.error.label { Text(e).font(.footnote).foregroundStyle(BC.warn) }
                    if !s.radioOn { Text("The Wi-Fi radio is off on the board. Turn it on there: swipe down › Wi-Fi (hold).").font(.footnote).foregroundStyle(BC.stale) }
                    Text("\(s.savedCount) saved network\(s.savedCount == 1 ? "" : "s") on the board").font(.caption2).foregroundStyle(.secondary)
                } else {
                    HStack { ProgressView(); Text("Reading Wi-Fi status…") }
                }
            } header: { Text("Board Wi-Fi") } footer: { Text("The board supports 2.4 GHz networks only. iPhone hotspot: turn on Maximize Compatibility and keep the Personal Hotspot screen open while the board scans.") }
            Section {
                Button { device.wifiScan() } label: { HStack { Label(device.wifiScanning ? "Scanning…" : "Scan for networks", systemImage: "arrow.clockwise"); if device.wifiScanning { Spacer(); ProgressView() } } }.disabled(device.wifiScanning || device.wifiStatus?.radioOn == false)
                if let e = device.wifiScanError { Text(e).font(.footnote).foregroundStyle(BC.warn) }
                ForEach(device.wifiNetworks) { n in
                    Button { selected = n; password = "" } label: {
                        HStack {
                            Image(systemName: n.secured ? "lock.fill" : "lock.open").foregroundStyle(.secondary).frame(width: 20)
                            VStack(alignment: .leading) { Text(n.ssid).foregroundStyle(.primary); Text("channel \(n.channel)\(n.saved ? " · saved" : "")\(device.wifiStatus?.ssid == n.ssid && (device.wifiStatus?.state == .connected || device.wifiStatus?.state == .connectedNoInternet) ? " · connected" : "")").font(.caption2).foregroundStyle(.secondary) }
                            Spacer()
                            SignalBars(rssi: n.rssi)
                        }
                    }
                }
                if device.wifiNetworks.isEmpty, !device.wifiScanning, device.wifiScanError == nil { Text("No networks listed yet. Tap Scan.").font(.footnote).foregroundStyle(.secondary) }
                Button("Other network…") { showManual = true }
            } header: { Text("Networks") }
        }
        .navigationTitle("Wi-Fi setup")
        .onAppear { device.wifiStatusRequest(); if device.wifiNetworks.isEmpty { device.wifiScan() } }
        .onReceive(timer) { _ in if let t = sentAt, Date().timeIntervalSince(t) < 40 { device.wifiStatusRequest() } }
        .sheet(item: $selected) { n in networkSheet(n) }
        .alert("Other network", isPresented: $showManual) {
            TextField("Network name (SSID)", text: $manualSSID)
            Button("Next") { selected = BCLink.WiFiNetwork(ssid: manualSSID, rssi: -100, secured: true, channel: 0, saved: false) }
            Button("Cancel", role: .cancel) {}
        } message: { Text("Type the exact name. Names with a curly apostrophe (’) cannot be typed here — use the scan list.") }
    }

    private func statusColour(_ s: BCLink.WiFiStatus) -> ConnStatus {
        switch s.state { case .connected: return .green; case .connectedNoInternet, .connecting, .scanning: return .amber; case .off: return .gray; case .disconnected: return s.error == .none ? .gray : .red }
    }

    private func networkSheet(_ n: BCLink.WiFiNetwork) -> some View {
        NavigationStack {
            Form {
                Section { LabeledContent("Network", value: n.ssid); LabeledContent("Security", value: n.secured ? "password" : "open"); if n.rssi > -100 { LabeledContent("Signal", value: "\(n.rssi) dBm") } }
                if n.secured {
                    Section("Password") {
                        HStack {
                            if showPassword { TextField("Password", text: $password).textInputAutocapitalization(.never).autocorrectionDisabled() } else { SecureField("Password", text: $password) }
                            Button { showPassword.toggle() } label: { Image(systemName: showPassword ? "eye.slash" : "eye") }.buttonStyle(.plain)
                        }
                        Text("Sent once over the encrypted Bluetooth link and stored only on the board.").font(.footnote).foregroundStyle(.secondary)
                    }
                }
                Section {
                    Button { if device.wifiSet(ssid: n.ssid, password: password) { sentAt = Date(); password = ""; selected = nil } } label: { Text(n.saved ? "Connect (update password)" : "Connect and save").frame(maxWidth: .infinity) }
                        .buttonStyle(.borderedProminent).tint(BC.accent).disabled(n.secured && password.utf8.count < 8 || password.utf8.count > 63)
                    if n.saved { Button("Forget this network", role: .destructive) { _ = device.wifiForget(ssid: n.ssid); selected = nil } }
                }
                if n.secured, password.utf8.count > 0, password.utf8.count < 8 { Text("WPA passwords have at least 8 characters.").font(.footnote).foregroundStyle(BC.stale) }
            }
            .navigationTitle("Connect").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { selected = nil; password = "" } } }
        }
    }
}

struct SignalBars: View {
    let rssi: Int
    var bars: Int { rssi >= -55 ? 4 : rssi >= -65 ? 3 : rssi >= -75 ? 2 : 1 }
    var body: some View {
        HStack(alignment: .bottom, spacing: 2) { ForEach(1...4, id: \.self) { i in RoundedRectangle(cornerRadius: 1).fill(i <= bars ? BC.accent : Color.secondary.opacity(0.3)).frame(width: 4, height: CGFloat(4 + 3 * i)) } }
            .accessibilityLabel("signal \(bars) of 4")
    }
}

/// Whether the phone and the BikeComputer agree on the athlete profile, and the one question the rider has to answer
/// at first pairing: which side's shared settings win.
struct SyncStatusView: View {
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var device: DeviceLink
    @EnvironmentObject private var sync: ProfileSync
    var body: some View {
        List {
            Section("Profile sync") {
                HStack { StatusBadge(status: colour); Text(sync.state.label) }
                if let t = sync.lastSyncAt { LabeledContent("Last sync", value: t.formatted(date: .abbreviated, time: .shortened)) }
                LabeledContent("Phone profile version", value: "\(store.profile.version)")
                if let r = sync.record { LabeledContent("Board acknowledged", value: r.ackedVersion == 0 ? "nothing yet" : "version \(r.ackedVersion)"); LabeledContent("Phone is authoritative", value: r.confirmed ? "yes (confirmed)" : "not yet") }
                if let b = device.boardProfile { LabeledContent("Board profile", value: b.source == 1 ? "synced from a phone (v\(b.version))" : "set on the board (device-only)") }
            }
            if sync.state == .needsConfirmation {
                Section {
                    ForEach(sync.differences) { d in VStack(alignment: .leading, spacing: 2) { Text(d.field).font(.footnote.weight(.semibold)); HStack { Text("phone: \(d.phone)").font(.footnote); Spacer(); Text("board: \(d.board)").font(.footnote).foregroundStyle(.secondary) } } }
                    Button { sync.confirmPhoneIsAuthoritative() } label: { Text("Use the phone's profile on the board").frame(maxWidth: .infinity) }.buttonStyle(.borderedProminent).tint(BC.accent)
                    Button("Keep the board's values (copy them to the phone)") { sync.adoptBoardProfile() }
                } header: { Text("The phone and the board differ") } footer: { Text("Only the shared athlete settings (name, FTP, weight, birth year, heart rate, hours, experience, goal, units) are replaced. Ride history, sensor pairings, calibration and the phone pairing on the board stay as they are. After this, changes made on the phone sync automatically.") }
            }
            Section("How ownership works") {
                Text("BikeComputer alone: set up on the board, works without a phone.\nPhone alone: this app records phone-only rides.\nConnected: the phone's profile is the shared one; the board keeps using the last synced profile when the phone is away. Rides the board recorded on its own are imported without duplicates (history sync).").font(.footnote)
            }
            if device.state == .ready, device.info?.hasProfileSync == true { Section { Button("Read the board's profile again") { device.profileGet() } } }
        }.navigationTitle("Sync status")
    }
    private var colour: ConnStatus { switch sync.state { case .inSync: return .green; case .needsConfirmation, .failed: return .red; case .pushing, .waitingForBoard: return .amber; default: return .gray } }
}
