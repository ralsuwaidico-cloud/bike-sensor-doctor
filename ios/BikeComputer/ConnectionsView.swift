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
                NavigationLink { SensorConnectionDetail(kind: .speed) } label: { ConnRow(status: .gray, title: "Speed / cadence sensors", subtitle: (device.info?.fw ?? "") >= "0.6.0" ? "pair on the board: Connections › Cadence / Speed" : "needs firmware 0.6.0 (pairs on the board)", icon: "gauge.with.dots.needle.33percent") }
            } header: { Text("Bluetooth sensors (via the BikeComputer)") } footer: { Text("Sensors pair on the board (its Connections menu: Power meter, Heart rate, Cadence, Speed). The phone shows what the board reports; a direct BLE connection on the board is marked \"direct\", data that passes through this phone \"via phone\".") }
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
    private var boardStatus: ConnStatus { ConnectionRules.board(linkState: device.state, liveFresh: device.liveIsFresh, remembered: device.remembered, autoConnect: store.settings.autoConnectBoard, phoneOnlyMode: store.settings.phoneOnlyMode, pairingLost: device.failure?.action == .repair) }
    private var boardSubtitle: String {
        if !store.settings.autoConnectBoard { return "phone link off (your choice)" }
        switch device.state {
        case .ready:
            var s = "connected"
            if let i = device.info { s += " · firmware \(i.fw)" }
            if let b = liveNow?.batteryPct { s += " · battery ≈\(b) % (estimate)" }
            if !device.liveIsFresh { s += " · no live data" }
            return s
        case .idle:
            if let f = device.failure, f.action == .repair { return "pairing lost — tap for Repair" }
            return device.remembered ? "not in range · reconnects by itself" : "not paired yet"
        default:
            if device.stage == .failed, let f = device.failure { return "\(f.stage.rawValue.lowercased()) failed — " + (f.action == .repair ? "tap for Repair" : "tap for details") }
            if device.stage == .waiting { return "waiting for the board (not in range)" }
            return device.stage.rawValue.lowercased() + "…"
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
    @State private var confirmForget = false
    @State private var showRepairHelp = false
    var body: some View {
        List {
            Section {
                StageStrip(stage: device.stage, failure: device.failure)
                if let f = device.failure { FailureBanner(failure: f, onRepair: { showRepairHelp = true }) }
                if device.stage == .pairing || device.stage == .authenticating { Text("Look at the round screen: it shows a 6-digit code. Type it into the iPhone dialog. This happens once per phone.").font(.footnote).foregroundStyle(BC.stale) }
                if device.stage == .waiting { Text("iOS keeps the request open and connects the moment the board advertises — no touch on the board needed. On firmware 0.6.0+ the board advertises with the screen off; in deep sleep it does not.").font(.footnote).foregroundStyle(.secondary) }
            } header: { Text("Connection stage") }
            Section("Status") {
                if let i = device.info { LabeledContent("Firmware", value: i.fw); LabeledContent("Protocol", value: "v\(i.verMajor).\(i.verMinor)"); if let id = i.deviceId { LabeledContent("Board id", value: id) } }
                else if let k = device.knownDeviceId { LabeledContent("Board id (last seen)", value: k) }
                if let r = device.rssi { LabeledContent("Signal", value: "\(r) dBm") }
                if let l = device.live, device.liveIsFresh { LabeledContent("Board battery", value: l.batteryPct.map { "≈\($0) % (estimate from voltage)" } ?? "unknown") }
                if let t = device.lastConnectedAt, device.state == .ready { LabeledContent("Connected since", value: t.formatted(date: .omitted, time: .shortened)) }
                if let t = device.lastDisconnectedAt, device.state != .ready { LabeledContent("Last seen", value: t.formatted(date: .abbreviated, time: .shortened)) }
                LabeledContent("Profile sync", value: sync.statusLine)
                if sync.state == .needsConfirmation { NavigationLink("Review the differences") { SyncStatusView() } }
            }
            Section {
                Toggle("Connect automatically", isOn: Binding(get: { store.settings.autoConnectBoard }, set: { store.settings.autoConnectBoard = $0; device.autoConnect = $0 }))
                if device.stage == .searching || device.stage == .found {
                    if device.found.isEmpty { Text("Searching… the board must be on and its Phone screen must say SEARCHING / WAITING.").font(.footnote).foregroundStyle(.secondary) }
                    ForEach(device.found, id: \.id) { f in Button { device.connect(to: f.id) } label: { HStack { Text(f.name); Spacer(); Text("\(f.rssi) dBm").foregroundStyle(.secondary) } }.frame(minHeight: 44) }
                }
                actionButtons
            } header: { Text("Actions") } footer: { Text(actionsFooter) }
            Section {
                NavigationLink { ConnectionDiagnosticsView() } label: { Label("Connection diagnostics", systemImage: "stethoscope") }
                if device.info?.hasSettings == true || device.info?.hasWiFi == true { NavigationLink("Device settings and Wi-Fi") { DeviceSettingsView() } }
                else if device.state == .ready { Text("Device settings, Wi-Fi setup and profile sync from the phone need firmware 0.6.0 or newer (board has \(device.info?.fw ?? "?")).").font(.footnote).foregroundStyle(.secondary) }
            }
            Section("Pairing steps") {
                step(1, "Switch the BikeComputer on and keep it within a metre. Its Phone screen (Connections › Phone) shows SEARCHING.")
                step(2, "Tap Connect, then the board in the list.")
                step(3, "Type the 6-digit code shown on the round screen into the iPhone dialog.")
                step(4, "Done: the phone is remembered on the board and reconnects by itself; the profile is compared and, after your confirmation, the phone's profile is applied.")
            }
            Section("What it provides") {
                Text("Live power and cadence from the XDS, ride state, time and distance, board battery estimate, heart rate from a strap paired on the board, finished rides (history sync), Wi-Fi setup, device settings and the shared athlete profile (firmware 0.6.0+).").font(.footnote)
            }
            Section("Troubleshooting") {
                Text("• Nothing found: Phone link must be ON on the board (Connections › Phone); Bluetooth on the phone must be on; firmware 0.5.0 stops advertising when its screen sleeps.\n• \"Peer removed pairing information\" / pairing refused: the board lost this phone's keys (data reset, Forget phone, restored backup). Use Repair below.\n• Connected but no values: pedal once so the XDS wakes; the board shows the meter state under Connections › Power meter.\n• Drops when the board screen turns off: fixed in firmware 0.6.0.").font(.footnote)
                Text("Sent: \(device.stats.sentGPS) GPS · \(device.stats.sentHR) HR · \(device.stats.sentTime) time   Received: \(device.stats.liveMsgs) live · \(device.stats.events) events · \(device.stats.rejected) rejected · \(device.stats.disconnects) drops").font(.caption2).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("BikeComputer")
        .alert("Forget this BikeComputer?", isPresented: $confirmForget) {
            Button("Forget", role: .destructive) { device.forget() }
            Button("Cancel", role: .cancel) {}
        } message: { Text("The phone forgets the board and its pairing record here. Your rides, plan and profile stay. To pair again you also remove it in iOS Settings › Bluetooth and hold FORGET PHONE on the board.") }
        .sheet(isPresented: $showRepairHelp) { RepairSheet() }
    }

    /// One consistent set of buttons per state: never Disconnect without a live connection, never Connect while connected.
    @ViewBuilder private var actionButtons: some View {
        switch device.stage {
        case .ready, .connected, .syncingProfile:
            Button("Disconnect") { device.disconnect() }.frame(minHeight: 44)
            if sync.state.isFailed || sync.state == .needsConfirmation { Button("Retry profile sync") { sync.retry() }.frame(minHeight: 44) }
            Button("Forget device", role: .destructive) { confirmForget = true }.frame(minHeight: 44)
        case .searching, .found, .connecting, .waiting, .pairing, .authenticating:
            Button("Cancel") { device.disconnect() }.frame(minHeight: 44)
            Button("Repair connection") { showRepairHelp = true }.frame(minHeight: 44)
        case .failed:
            if device.failure?.action == .repair { Button("Repair connection") { showRepairHelp = true }.bold().frame(minHeight: 44) }
            Button(device.remembered ? "Try again" : "Connect") { device.connect() }.frame(minHeight: 44)
            if device.failure?.action != .repair, device.remembered { Button("Repair connection") { showRepairHelp = true }.frame(minHeight: 44) }
            if device.remembered { Button("Forget device", role: .destructive) { confirmForget = true }.frame(minHeight: 44) }
        case .off: Button("Open Settings (turn Bluetooth on)") { DeviceLink.openSettings() }.frame(minHeight: 44)
        case .unauthorized: Button("Open Settings (allow Bluetooth)") { DeviceLink.openSettings() }.frame(minHeight: 44)
        case .idle:
            Button(device.remembered ? "Connect" : "Find my BikeComputer") { device.connect() }.bold().frame(minHeight: 44)
            if device.remembered { Button("Repair connection") { showRepairHelp = true }.frame(minHeight: 44); Button("Forget device", role: .destructive) { confirmForget = true }.frame(minHeight: 44) }
        }
    }
    private var actionsFooter: String {
        switch device.stage {
        case .ready: return "Repair is only needed when pairing fails; Forget removes the board from this phone."
        default: return "With \"Connect automatically\" on, iOS keeps a connection request open in the background and the phone attaches as soon as the board advertises — no touch on the board needed."
        }
    }
    private func step(_ n: Int, _ t: String) -> some View { HStack(alignment: .top, spacing: 10) { Text("\(n)").font(.caption.bold()).frame(width: 22, height: 22).background(BC.accent.opacity(0.18), in: Circle()); Text(t).font(.footnote) } }
}

/// Searching → Found → Pairing → Authenticating → Connected → Syncing profile → Ready, the current one highlighted.
struct StageStrip: View {
    let stage: DeviceLink.Stage
    let failure: DeviceLink.Failure?
    private let steps: [DeviceLink.Stage] = [.searching, .found, .pairing, .authenticating, .connected, .syncingProfile, .ready]
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 4) {
                ForEach(steps, id: \.self) { s in
                    Capsule().fill(colour(s)).frame(height: 6)
                }
            }
            HStack {
                Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(stage == .failed ? BC.warn : .primary)
                Spacer()
                if stage.isAttempt { ProgressView().controlSize(.small) }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Connection stage: \(title)")
    }
    private var effective: DeviceLink.Stage {
        if stage == .failed { return failure?.stage ?? .idle }
        if stage == .waiting || stage == .connecting { return .found }
        return stage
    }
    private func colour(_ s: DeviceLink.Stage) -> Color {
        let cur = effective.order
        if stage == .failed, s.order == cur { return BC.warn }
        if s.order < cur || (s == effective && stage == .ready) { return BC.live }
        if s == effective { return BC.accent }
        return Color.secondary.opacity(0.25)
    }
    private var title: String {
        switch stage {
        case .failed: return "Failed while \(failure?.stage.rawValue.lowercased() ?? "connecting")"
        case .waiting: return "Waiting for the board (not in range)"
        default: return stage.rawValue + (stage == .pairing ? " — type the code shown on the board" : "")
        }
    }
}

struct FailureBanner: View {
    let failure: DeviceLink.Failure
    var onRepair: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(failure.reason).font(.footnote).foregroundStyle(BC.warn).fixedSize(horizontal: false, vertical: true)
            if let c = failure.code { Text("\(failure.at.formatted(date: .omitted, time: .standard)) · \(c)").font(.caption2).foregroundStyle(.secondary) }
            if failure.action == .repair { Text("The iPhone still holds the old pairing while the board has none. Repair clears it on both sides.").font(.caption2).foregroundStyle(.secondary) }
        }
    }
}

/// The repair flow, step by step. Only the iOS Settings step cannot be done by the app.
struct RepairSheet: View {
    @EnvironmentObject private var device: DeviceLink
    @Environment(\.dismiss) private var dismiss
    @State private var started = false
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("A pairing breaks when one side loses its keys: the board after a data reset, a restored backup or FORGET PHONE; the iPhone still remembers the old pairing and refuses to pair again with the same device. Repair fixes both sides without touching rides, settings or sensor pairings.").font(.footnote)
                } header: { Text("Why") }
                Section("Steps") {
                    step(1, "On the board: Connections › Phone › hold REPAIR. The board forgets this phone and takes a new Bluetooth identity (firmware 0.7.0+). On 0.6.x use FORGET PHONE instead.")
                    step(2, "On the iPhone: Settings › Bluetooth › \"BikeComputer Link\" › Forget This Device — the one step the app cannot do.", action: ("Open Settings", { DeviceLink.openSettings() }))
                    step(3, "Back here: tap Start repair. The app forgets the old identity, searches for the board and pairs again with the 6-digit code.", action: (started ? "Searching…" : "Start repair", { device.repair(); started = true }))
                }
                if started {
                    Section("Progress") {
                        StageStrip(stage: device.stage, failure: device.failure)
                        if let f = device.failure { FailureBanner(failure: f, onRepair: {}) }
                        if device.stage == .ready { Text("Repaired: connected and paired again.").font(.footnote).foregroundStyle(BC.live) }
                        if let k = device.knownDeviceId { Text("Board id \(k)" + (device.staleIdentifier != nil ? " · previous identity \(device.staleIdentifier!.prefix(8))… marked stale" : "")).font(.caption2).foregroundStyle(.secondary) }
                    }
                }
            }
            .navigationTitle("Repair connection").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button(device.stage == .ready ? "Done" : "Close") { dismiss() } } }
        }
    }
    private func step(_ n: Int, _ t: String, action: (String, () -> Void)? = nil) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 10) { Text("\(n)").font(.caption.bold()).frame(width: 22, height: 22).background(BC.accent.opacity(0.18), in: Circle()); Text(t).font(.footnote) }
            if let a = action { Button(a.0) { a.1() }.buttonStyle(.bordered).controlSize(.small).padding(.leading, 32).disabled(a.0 == "Searching…") }
        }
    }
}

/// Stage history with timestamps, last failure, the board's own LINK_DIAG, identities, sync state, app state.
struct ConnectionDiagnosticsView: View {
    @EnvironmentObject private var device: DeviceLink
    @EnvironmentObject private var sync: ProfileSync
    @EnvironmentObject private var store: Store
    var body: some View {
        List {
            Section("Now") {
                LabeledContent("Stage", value: device.stage.rawValue)
                LabeledContent("Link usable", value: device.state == .ready ? "yes" : "no")
                LabeledContent("App state", value: device.appBackgroundState)
                LabeledContent("Connect automatically", value: store.settings.autoConnectBoard ? "on" : "off")
                if let f = device.failure { LabeledContent("Last failure", value: "\(f.stage.rawValue): \(f.reason)"); if let c = f.code { LabeledContent("Error code", value: c) } }
                if let e = device.lastError, device.failure == nil { LabeledContent("Last error", value: e) }
            }
            Section("Identity") {
                LabeledContent("Board id (INFO)", value: device.info?.deviceId ?? device.knownDeviceId ?? "unknown")
                LabeledContent("Remembered identifier", value: device.rememberedIdentifier.map { String($0.prefix(13)) + "…" } ?? "none")
                if let s = device.staleIdentifier { LabeledContent("Stale identifier", value: String(s.prefix(13)) + "…") }
                if let i = device.info { LabeledContent("Firmware / protocol", value: "\(i.fw) · v\(i.verMajor).\(i.verMinor) · caps 0x\(String(i.caps, radix: 16))") }
            }
            Section("Board's report (LINK_DIAG, once per connection)") {
                if let d = device.linkDiag {
                    LabeledContent("Previous link ended by", value: d.reasonText)
                    LabeledContent("Phones remembered on the board", value: "\(d.bonds)")
                    LabeledContent("Board profile sync", value: d.syncText)
                    if let t = device.linkDiagAt { LabeledContent("Received", value: t.formatted(date: .omitted, time: .standard)) }
                } else { Text("Not received yet (firmware 0.7.0 sends it right after connecting).").font(.footnote).foregroundStyle(.secondary) }
            }
            Section("Profile sync") {
                LabeledContent("State", value: sync.statusLine)
                if let l = sync.lastSuccessful { LabeledContent("Last successful", value: "v\(l.version) at \(l.at.formatted(date: .abbreviated, time: .shortened))") }
                LabeledContent("Phone profile version", value: "\(store.profile.version)")
                if let b = device.boardProfile { LabeledContent("Board profile version", value: "\(b.version) (\(b.source == 1 ? "phone-synced" : "device-only"))") }
                if let a = device.lastProfileAck { LabeledContent("Last ack", value: "v\(a.version) · \(a.statusText)") }
            }
            Section("Stage history") {
                if device.log.isEmpty { Text("Nothing yet").foregroundStyle(.secondary) }
                ForEach(device.log.reversed()) { l in HStack(alignment: .top) { Text(l.at.formatted(date: .omitted, time: .standard)).font(.caption2).monospacedDigit().foregroundStyle(.secondary).frame(width: 68, alignment: .leading); Text(l.text).font(.caption) } }
            }
            Section("Counters") {
                Text("Connects \(device.stats.connects) · drops \(device.stats.disconnects) · live \(device.stats.liveMsgs) · events \(device.stats.events) · rejected \(device.stats.rejected) · sent GPS \(device.stats.sentGPS), HR \(device.stats.sentHR), time \(device.stats.sentTime)").font(.caption)
            }
        }
        .navigationTitle("Connection diagnostics").navigationBarTitleDisplayMode(.inline)
    }
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
    @State private var importing = false
    @State private var importResult: String?
    private func runImport() {
        guard !importing else { return }
        importing = true
        health.importWorkouts(into: store) { r in importing = false; importResult = r.message; store.settings.lastHealthImport = Date() }
    }
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
            Section {
                Toggle("Import workouts from Apple Health", isOn: Binding(get: { store.settings.appleHealthImportWorkouts }, set: { v in store.settings.appleHealthImportWorkouts = v; if v { store.settings.appleHealthWanted = true; if !health.workoutWriteAuthorized { health.request { _ in runImport() } } else { runImport() } } }))
                Button { runImport() } label: { HStack { Text(importing ? "Importing…" : "Import now (last 90 days)"); Spacer(); if importing { ProgressView() } } }.disabled(importing || !health.available)
                if let r = importResult { Text(r).font(.footnote).foregroundStyle(.secondary) }
                if let d = store.settings.lastHealthImport { LabeledContent("Last import", value: d.formatted(date: .abbreviated, time: .shortened)) }
            } header: { Text("Workout import (0.6.0)") } footer: { Text("Cycling, traditional and functional strength workouts recorded by other apps or the Apple Watch become rides and strength sessions here, marked \"Apple Health\". Duplicates of what the phone or BikeComputer already recorded (same start within 2 minutes, similar duration) are skipped. Health workouts carry no body region, so they count as sessions but never as push / pull / lower evidence.") }
            Section("What each permission does") {
                Text("Workouts (write): save a finished BikeComputer or phone ride into Health and Fitness.\nWorkouts (read): find rides recorded by other apps for the training calendar (later build).\nHeart rate (read): heart-rate history for recovery views (later build). iOS does not tell apps whether reading was allowed, so nothing is claimed about it.").font(.footnote)
                Text("Live heart rate during a ride does not come from Health; it comes from the Apple Watch workout or a strap.").font(.footnote).foregroundStyle(.secondary)
            }
        }.navigationTitle("Apple Health")
    }
}
