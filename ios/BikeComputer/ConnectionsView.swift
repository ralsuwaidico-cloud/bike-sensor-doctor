import SwiftUI

/// Connections dashboard (replaces "Sensors"): every device and integration with one status colour, tappable for
/// details, pairing steps, what it measures, reconnect and troubleshooting. Red only for what the rider enabled or the
/// ride configuration requires (ConnectionRules).
struct ConnectionsView: View {
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var device: DeviceLink
    @EnvironmentObject private var watch: WatchLink
    @EnvironmentObject private var location: LocationService
    @EnvironmentObject private var reach: Reachability
    @EnvironmentObject private var health: HealthAccess
    @EnvironmentObject private var sync: ProfileSync
    @State private var tick = Date()
    private let timer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    var body: some View {
        List {
            Section {
                NavigationLink { BoardConnectionDetail() } label: { ConnRow(status: boardStatus, title: "BikeComputer", subtitle: boardSubtitle, icon: "circle.hexagongrid.circle") }
            } header: { Text("Cycling computer") } footer: {
                if !device.remembered { Text("Pair once: switch the board on, tap BikeComputer, Connect, type the 6-digit code from its round screen. Afterwards the phone reconnects by itself whenever the board is in range.") }
            }
            Section("Phone") {
                NavigationLink { PhoneConnectionDetail(kind: .bluetooth) } label: { ConnRow(status: bluetoothStatus, title: "Bluetooth", subtitle: bluetoothSubtitle, icon: "antenna.radiowaves.left.and.right") }
                NavigationLink { PhoneConnectionDetail(kind: .gps) } label: { ConnRow(status: gpsStatus, title: "GPS", subtitle: gpsSubtitle, icon: "location") }
                NavigationLink { PhoneConnectionDetail(kind: .internet) } label: { ConnRow(status: ConnectionRules.internet(online: reach.online), title: "Internet", subtitle: reach.online ? "online via \(reach.kind)" : "offline · the app keeps working", icon: "network") }
            }
            Section("Apple Watch") {
                NavigationLink { WatchConnectionDetail() } label: { ConnRow(status: watchStatus, title: "Apple Watch", subtitle: watchSubtitle, icon: "applewatch") }
            }
            Section {
                NavigationLink { SensorConnectionDetail(kind: .meter) } label: { ConnRow(status: meterStatus, title: "Power meter (XDS)", subtitle: meterSubtitle, icon: "bolt") }
                NavigationLink { SensorConnectionDetail(kind: .strap) } label: { ConnRow(status: strapStatus, title: "Heart-rate strap", subtitle: strapSubtitle, icon: "heart") }
                NavigationLink { SensorConnectionDetail(kind: .speed) } label: { ConnRow(status: .gray, title: "Speed / cadence sensors", subtitle: "not supported by firmware 0.6.0 yet", icon: "gauge.with.dots.needle.33percent") }
            } header: { Text("Bluetooth sensors (via the BikeComputer)") } footer: { Text("Sensors pair on the board (Settings › Sensors). The phone shows what the board reports.") }
            Section {
                NavigationLink { HealthConnectionDetail() } label: { ConnRow(status: healthStatus, title: "Apple Health", subtitle: healthSubtitle, icon: "heart.text.square") }
                ConnRow(status: .gray, title: "WHOOP", subtitle: "not connected · arrives with the account service", icon: "waveform.path.ecg")
                ConnRow(status: .gray, title: "Garmin Connect", subtitle: "not connected · arrives with the account service", icon: "arrow.triangle.2.circlepath")
            } header: { Text("Other integrations") } footer: { Text("Cloud services provide recovery and history, never live heart rate. Gray = optional and not set up; nothing is shown from them until they are connected.") }
        }
        .navigationTitle("Connections")
        .onReceive(timer) { tick = $0; health.refresh() }
    }

    // MARK: statuses
    private var boardWanted: Bool { store.settings.enabledConnections.contains("board") && device.remembered && store.settings.autoConnectBoard }
    private var liveNow: BCLink.Live? { device.state == .ready && device.liveIsFresh ? device.live : nil }
    private var boardStatus: ConnStatus { ConnectionRules.board(linkState: device.state, liveFresh: device.liveIsFresh, remembered: device.remembered, autoConnect: store.settings.autoConnectBoard, phoneOnlyMode: store.settings.phoneOnlyMode) }
    private var boardSubtitle: String {
        if !store.settings.autoConnectBoard { return "phone link off (your choice)" }
        switch device.state {
        case .ready:
            var s = "connected"
            if let i = device.info { s += " · firmware \(i.fw)" }
            if let b = liveNow?.batteryPct { s += " · battery ≈\(b) % (estimate)" }
            if !device.liveIsFresh { s += " · no live data" }
            return s
        case .idle: return device.remembered ? "not in range · reconnects by itself" : "not paired yet"
        default: return device.state.rawValue
        }
    }
    private var bluetoothStatus: ConnStatus { ConnectionRules.bluetooth(linkState: device.state, boardWanted: boardWanted) }
    private var bluetoothSubtitle: String { switch device.state { case .off: return "Bluetooth is off on the phone"; case .unauthorized: return "permission needed (Settings › BikeComputer)"; default: return "on" } }
    private var gpsRequired: Bool { store.settings.phoneOnlyMode || !device.remembered }
    private var gpsStatus: ConnStatus { ConnectionRules.gps(authorized: location.authorized, sharing: location.sharing, hasFix: location.last != nil, requiredForRides: gpsRequired) }
    private var gpsSubtitle: String { location.authorized ? (location.sharing ? location.status : "ready · starts with a ride") : "location permission needed" }
    private var watchEnabled: Bool { store.settings.enabledConnections.contains("watch") }
    private var watchStatus: ConnStatus { ConnectionRules.watch(paired: watch.paired, appInstalled: watch.appInstalled, hrFresh: watch.hrIsFresh, workoutRunning: watch.workoutState == "running", enabled: watchEnabled) }
    private var watchSubtitle: String {
        if !watchEnabled { return "off (your choice)" }
        if watch.hrIsFresh { return "heart rate live · \(watch.hrBpm ?? 0) bpm" }
        if !watch.paired { return "no watch paired with this iPhone" }
        if !watch.appInstalled { return "BikeComputer app not installed on the watch" }
        return watch.workoutState == "running" ? "workout running · waiting for heart rate" : "ready · start the workout on the watch"
    }
    private var meterEnabled: Bool { store.settings.enabledConnections.contains("meter") || device.remembered }
    private var meterStatus: ConnStatus { ConnectionRules.meter(boardLive: liveNow != nil, meterLink: liveNow?.meterLink, enabled: meterEnabled) }
    private var meterSubtitle: String {
        guard let l = liveNow else { return device.remembered ? "reported by the board when connected" : "pairs on the board" }
        switch l.meterLink { case 4: return "connected to the board" + (l.powerW.map { " · \($0) W" } ?? ""); case 2: return "board searching (pedal once)"; case 3: return "connecting"; case 5: return "reconnecting"; case 1: return "not paired on the board"; default: return "off" }
    }
    private var strapEnabled: Bool { store.settings.enabledConnections.contains("strap") }
    private var strapStatus: ConnStatus { ConnectionRules.strap(boardLive: liveNow != nil, hrFromStrap: liveNow?.hrSource == .bleStrap && liveNow?.hrBpm != nil, enabled: strapEnabled) }
    private var strapSubtitle: String { strapStatus == .green ? "live via the board" : strapEnabled ? "pair on the board · Settings › Sensors" : "optional" }
    private var healthStatus: ConnStatus { ConnectionRules.health(wanted: store.settings.appleHealthWanted, authorized: health.workoutWriteAuthorized, available: health.available) }
    private var healthSubtitle: String { !health.available ? "not available on this device" : health.workoutWriteAuthorized ? "workouts can be saved" : store.settings.appleHealthWanted ? "permission not granted yet" : "optional · not connected" }
}

struct ConnRow: View {
    let status: ConnStatus; let title: String; let subtitle: String; let icon: String
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(.title3).foregroundStyle(.secondary).frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body.weight(.semibold))
                Text(subtitle).font(.footnote).foregroundStyle(.secondary).lineLimit(2)
            }
            Spacer(minLength: 8)
            StatusBadge(status: status)
        }.padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title), \(status.label), \(subtitle)")
    }
}

struct StatusBadge: View {
    let status: ConnStatus
    var body: some View {
        switch status {
        case .green: Circle().fill(BC.live).frame(width: 12, height: 12)
        case .red: Image(systemName: "exclamationmark.circle.fill").foregroundStyle(BC.warn).font(.title3)
        case .amber: Circle().fill(BC.stale).frame(width: 12, height: 12)
        case .gray: Circle().fill(Color.secondary.opacity(0.4)).frame(width: 12, height: 12)
        }
    }
}

// MARK: - details

struct BoardConnectionDetail: View {
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var device: DeviceLink
    @EnvironmentObject private var sync: ProfileSync
    var body: some View {
        List {
            Section("Status") {
                LabeledContent("Link", value: device.state.rawValue)
                if let i = device.info { LabeledContent("Firmware", value: i.fw); LabeledContent("Protocol", value: "v\(i.verMajor).\(i.verMinor)"); if let id = i.deviceId { LabeledContent("Board id", value: id) } }
                if let r = device.rssi { LabeledContent("Signal", value: "\(r) dBm") }
                if let l = device.live, device.liveIsFresh { LabeledContent("Board battery", value: l.batteryPct.map { "≈\($0) % (estimate from voltage)" } ?? "unknown") }
                if let t = device.lastConnectedAt { LabeledContent("Connected since", value: t.formatted(date: .omitted, time: .shortened)) }
                if let t = device.lastDisconnectedAt, device.state != .ready { LabeledContent("Last seen", value: t.formatted(date: .abbreviated, time: .shortened)) }
                LabeledContent("Profile sync", value: sync.state.label)
            }
            Section {
                Toggle("Connect automatically", isOn: Binding(get: { store.settings.autoConnectBoard }, set: { store.settings.autoConnectBoard = $0; device.autoConnect = $0 }))
                if device.state == .pairing { Text("Look at the round screen: it shows a 6-digit code. Type it into the iPhone dialog. This happens once.").font(.footnote).foregroundStyle(BC.stale) }
                if device.state == .scanning {
                    if device.found.isEmpty { Text("Searching… the board must be on and its Settings › Phone must say WAITING FOR PHONE.").font(.footnote).foregroundStyle(.secondary) }
                    ForEach(device.found, id: \.id) { f in Button { device.connect(to: f.id) } label: { HStack { Text(f.name); Spacer(); Text("\(f.rssi) dBm").foregroundStyle(.secondary) } } }
                }
                HStack {
                    if device.state == .ready || device.state == .connecting || device.state == .pairing { Button("Disconnect") { device.disconnect() } }
                    else { Button(device.remembered ? "Reconnect now" : "Find my BikeComputer") { device.connect() }.bold() }
                    Spacer()
                    if device.remembered { Button("Forget", role: .destructive) { device.forget() } }
                }
                if let e = device.lastError { Text(e).font(.footnote).foregroundStyle(BC.warn) }
            } header: { Text("Connection") } footer: {
                Text("With \"Connect automatically\" on, iOS keeps a connection request open in the background and the phone attaches as soon as the board advertises — no touch on the board needed (firmware 0.6.0 keeps advertising with the screen off; 0.5.0 drops the link when it sleeps).")
            }
            Section("Pairing steps") {
                step(1, "Switch the BikeComputer on and keep it within a metre.")
                step(2, "Tap Find my BikeComputer, then the board in the list.")
                step(3, "Type the 6-digit code shown on the round screen into the iPhone dialog.")
                step(4, "Done: the phone is remembered on the board and reconnects by itself.")
            }
            Section("What it provides") {
                Text("Live power and cadence from the XDS, ride state, time and distance, board battery estimate, heart rate from a strap paired on the board, finished rides (history sync, firmware 0.6.0).").font(.footnote)
            }
            if device.info?.hasSettings == true || device.info?.hasWiFi == true {
                Section { NavigationLink("Device settings and Wi-Fi") { DeviceSettingsView() } }
            } else if device.state == .ready {
                Section { Text("Device settings, Wi-Fi setup and profile sync from the phone need firmware 0.6.0 (board has \(device.info?.fw ?? "?")).").font(.footnote).foregroundStyle(.secondary) }
            }
            Section("Troubleshooting") {
                Text("• Nothing found: the board's Settings › Phone must show WAITING FOR PHONE; Bluetooth on the phone must be on.\n• Pairing code refused: on the board choose Forget phone, and in iOS Settings › Bluetooth › BikeComputer choose Forget This Device, then pair again.\n• Connected but no values: pedal once so the XDS wakes; the board shows the meter state on its Sensors page.\n• Drops when the board screen turns off: fixed in firmware 0.6.0; on 0.5.0 wake the board.").font(.footnote)
                Text("Sent: \(device.stats.sentGPS) GPS · \(device.stats.sentHR) HR · \(device.stats.sentTime) time   Received: \(device.stats.liveMsgs) live · \(device.stats.rejected) rejected · \(device.stats.disconnects) drops").font(.caption2).foregroundStyle(.secondary)
            }
        }.navigationTitle("BikeComputer")
    }
    private func step(_ n: Int, _ t: String) -> some View { HStack(alignment: .top, spacing: 10) { Text("\(n)").font(.caption.bold()).frame(width: 22, height: 22).background(BC.accent.opacity(0.18), in: Circle()); Text(t).font(.footnote) } }
}

struct PhoneConnectionDetail: View {
    enum Kind { case bluetooth, gps, internet }
    let kind: Kind
    @EnvironmentObject private var device: DeviceLink
    @EnvironmentObject private var location: LocationService
    @EnvironmentObject private var reach: Reachability
    var body: some View {
        List {
            switch kind {
            case .bluetooth:
                Section("Status") { LabeledContent("Bluetooth", value: device.state == .off ? "off" : device.state == .unauthorized ? "permission needed" : "on") }
                Section("Used for") { Text("The BikeComputer link (power, cadence, ride control, GPS to the board). Apple Watch uses its own connection.").font(.footnote) }
                Section("Troubleshooting") { Text("Turn Bluetooth on in Control Centre or Settings. If permission was denied: Settings › BikeComputer › Bluetooth.").font(.footnote) }
            case .gps:
                Section("Status") {
                    LabeledContent("Permission", value: location.authorized ? "granted" : "not granted")
                    LabeledContent("GPS", value: location.sharing ? location.status : "off until a ride starts")
                    LabeledContent("Fixes sent to the board", value: "\(location.sent)")
                }
                Section("Used for") { Text("Speed, distance and the route map for phone-only rides; speed and distance for the BikeComputer, which has no GPS of its own.").font(.footnote) }
                Section { if !location.authorized { Button("Allow location") { location.requestPermission() } } ; Toggle("GPS on now", isOn: $location.sharing) }
                Section("Troubleshooting") { Text("Allow \"While Using\" at least; background recording needs the app to be allowed in the background (iOS asks once). GPS is weak indoors.").font(.footnote) }
            case .internet:
                Section("Status") { LabeledContent("Internet", value: reach.online ? "online (\(reach.kind))" : "offline") }
                Section("Used for") { Text("Nothing yet: this build makes no network calls. Rides, plan and profile stay on the phone and the board. The account service (sync, Google/e-mail sign-in) arrives later and will use it; everything keeps working offline.").font(.footnote) }
            }
        }.navigationTitle(kind == .bluetooth ? "Bluetooth" : kind == .gps ? "GPS" : "Internet")
    }
}

struct WatchConnectionDetail: View {
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var watch: WatchLink
    var body: some View {
        List {
            Section("Status") {
                StatusRow(title: "Watch paired with this iPhone", ok: watch.paired)
                StatusRow(title: "BikeComputer app installed on the watch", ok: watch.appInstalled)
                StatusRow(title: "Watch app reachable now", ok: watch.reachable)
                LabeledContent("Workout on the watch", value: watch.workoutState)
                LabeledContent("Live heart rate", value: watch.hrIsFresh ? "\(watch.hrBpm ?? 0) bpm" : "--")
                LabeledContent("Readings forwarded to the board", value: "\(watch.hrReceived)")
                if let b = watch.watchBattery { LabeledContent("Watch battery", value: "\(b) %") }
            }
            Section {
                Toggle("Use the Apple Watch", isOn: Binding(get: { store.settings.enabledConnections.contains("watch") }, set: { if $0 { store.settings.enabledConnections.insert("watch") } else { store.settings.enabledConnections.remove("watch") } }))
                Button("Test connection to the watch") { watch.ping() }
                Text(watch.lastResult).font(.footnote).foregroundStyle(.secondary)
            } footer: { Text("Off = the watch is never shown as missing. On = heart rate from the watch workout reaches the phone and the board, labelled Apple Watch; a reading older than 6 s is dropped, never held.") }
            Section("Steps") {
                Text("1. Install BikeComputer on the watch (Watch app › Available Apps).\n2. Open it and tap Start: a cycling workout begins (one workout, no duplicates in Fitness).\n3. Heart rate appears here and on the board within a few seconds.").font(.footnote)
            }
            Section("Measurements") { Text("Heart rate (1 Hz), workout state, watch battery. Ride controls from the wrist: start, pause, resume, end.").font(.footnote) }
            Section("Troubleshooting") { Text("Not reachable: open the watch app once; make sure the iPhone's Bluetooth is on. No heart rate: the watch must sit snug and the workout must be running.").font(.footnote) }
        }.navigationTitle("Apple Watch")
    }
}

struct SensorConnectionDetail: View {
    enum Kind { case meter, strap, speed }
    let kind: Kind
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var device: DeviceLink
    private var live: BCLink.Live? { device.state == .ready && device.liveIsFresh ? device.live : nil }
    var body: some View {
        List {
            switch kind {
            case .meter:
                Section("Status") {
                    LabeledContent("Board link", value: live == nil ? "no live data from the board" : "live")
                    if let l = live { LabeledContent("Power meter", value: ["off", "not paired", "searching", "connecting", "connected", "reconnecting"][min(5, max(0, l.meterLink))]); LabeledContent("Gaps this ride", value: "\(l.meterGaps)") }
                    if let w = live?.powerW { LabeledContent("Power", value: "\(w) W") }
                    if let c = live?.cadenceRpm { LabeledContent("Cadence", value: "\(c) rpm") }
                }
                Section("Pairing") { Text("The XDS pairs on the BikeComputer (Settings › Sensors › Power meter). Pedal once to wake it; the board connects to the meter before it accepts the phone.").font(.footnote) }
                Section("Measurements") { Text("Power (W), cadence (rpm), energy (kJ), zones — recorded by the board, mirrored here.").font(.footnote) }
            case .strap:
                Section("Status") { LabeledContent("Heart rate from a strap", value: live?.hrSource == .bleStrap ? "\(live?.hrBpm ?? 0) bpm live" : "none") }
                Section {
                    Toggle("I use a heart-rate strap", isOn: Binding(get: { store.settings.enabledConnections.contains("strap") }, set: { if $0 { store.settings.enabledConnections.insert("strap") } else { store.settings.enabledConnections.remove("strap") } }))
                } footer: { Text("Pairs on the board (Settings › Sensors › Heart rate, standard Bluetooth 0x180D). A strap on the board wins over the watch unless you prefer the watch in Settings.") }
            case .speed:
                Section { Text("Standard Bluetooth speed/cadence sensors (0x1816) are not supported by firmware 0.6.0. Speed and distance come from the phone's GPS; cadence from the XDS. Planned for a later firmware.").font(.footnote) }
            }
        }.navigationTitle(kind == .meter ? "Power meter" : kind == .strap ? "Heart-rate strap" : "Speed / cadence")
    }
}

struct HealthConnectionDetail: View {
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var health: HealthAccess
    var body: some View {
        List {
            Section("Status") {
                LabeledContent("Apple Health", value: !health.available ? "not available" : health.workoutWriteAuthorized ? "connected (workouts can be saved)" : "not connected")
                if let e = health.lastError { Text(e).font(.footnote).foregroundStyle(BC.warn) }
            }
            Section {
                Toggle("Use Apple Health", isOn: Binding(get: { store.settings.appleHealthWanted }, set: { v in store.settings.appleHealthWanted = v; if v, !health.workoutWriteAuthorized { health.request { _ in } } }))
                if store.settings.appleHealthWanted, !health.workoutWriteAuthorized, health.available { Button("Grant permission") { health.request { _ in } } }
                Toggle("Save finished rides as workouts", isOn: $store.settings.appleHealthExportRides).disabled(!health.workoutWriteAuthorized)
            } footer: { Text("Shown as connected only after iOS confirms the permission. Saving rides is prepared but not active in this build (it will write a cycling workout per saved ride).") }
            Section("What each permission does") {
                Text("Workouts (write): save a finished BikeComputer or phone ride into Health and Fitness.\nWorkouts (read): find rides recorded by other apps for the training calendar (later build).\nHeart rate (read): heart-rate history for recovery views (later build). iOS does not tell apps whether reading was allowed, so nothing is claimed about it.").font(.footnote)
                Text("Live heart rate during a ride does not come from Health; it comes from the Apple Watch workout or a strap.").font(.footnote).foregroundStyle(.secondary)
            }
        }.navigationTitle("Apple Health")
    }
}
