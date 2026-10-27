import SwiftUI

/// Connections dashboard, built on the hub's source model (docs/INTEGRATIONS.md). Every live source — the optional
/// BikeComputer, Bluetooth sensors paired directly with this phone, the Apple Watch, phone GPS — and every imported
/// source (Apple Health; the planned cloud providers only when ReleaseFlags allows — never in 1.0) with one status colour, tappable for details. Red only
/// for what the rider set up or the ride configuration requires (ConnectionRules). Nothing here is required: the app
/// rides with the phone alone.
struct ConnectionsView: View {
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var device: DeviceLink
    @EnvironmentObject private var watch: WatchLink
    @EnvironmentObject private var location: LocationService
    @EnvironmentObject private var reach: Reachability
    @EnvironmentObject private var health: HealthAccess
    @EnvironmentObject private var sync: ProfileSync
    @EnvironmentObject private var hub: SensorHub
    @EnvironmentObject private var monitor: PipelineMonitor
    @State private var tick = Date()
    private let timer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    var body: some View {
        List {
            Section {
                PipelineBanner(monitor: monitor)
                NavigationLink { PipelineDiagnosticsView() } label: { Label("Diagnostics", systemImage: "stethoscope") }
                    .accessibilityIdentifier("connectionsDiagnostics")
            } footer: { Text("Checked every second; reconnects and restarts happen automatically. Export a technical report from Diagnostics.") }
            Section {
                InUseNowRows(hub: hub)
            } header: { Text("In use now") } footer: {
                Text("One value per metric. When two sources give the same metric, the first available wins: heart rate — strap on the BikeComputer, strap paired here, Apple Watch (or the watch first if you chose it in Profile); speed — wheel sensor, then phone GPS; power and cadence — power meter via the BikeComputer, then a sensor paired here.")
            }
            Section {
                NavigationLink { BoardConnectionDetail() } label: { ConnRow(status: boardStatus, title: "BikeComputer", subtitle: boardSubtitle, icon: "circle.hexagongrid.circle") }
                BLESensorRows(ble: hub.ble, hub: hub)
                NavigationLink { WatchConnectionDetail() } label: { ConnRow(status: watchStatus, title: "Apple Watch", subtitle: watchSubtitle, icon: "applewatch") }
                NavigationLink { PhoneConnectionDetail(kind: .gps) } label: { ConnRow(status: gpsStatus, title: "Phone GPS", subtitle: gpsSubtitle, icon: "location") }
            } header: { Text("Live sources") } footer: {
                Text("Ride with any combination: the phone alone (GPS), Bluetooth sensors paired here, an Apple Watch, or the optional BikeComputer.")
            }
            if device.remembered || liveNow != nil {
                Section {
                    NavigationLink { SensorConnectionDetail(kind: .meter) } label: { ConnRow(status: meterStatus, title: "Power meter via BikeComputer", subtitle: meterSubtitle, icon: "bolt") }
                    NavigationLink { SensorConnectionDetail(kind: .strap) } label: { ConnRow(status: strapStatus, title: "Heart-rate strap via BikeComputer", subtitle: strapSubtitle, icon: "heart") }
                    NavigationLink { SensorConnectionDetail(kind: .speed) } label: { ConnRow(status: .gray, title: "Speed / cadence via BikeComputer", subtitle: (device.info?.fw ?? "") >= "0.6.0" ? "pair on the board: Connections › Cadence / Speed" : "pair it with this phone instead (Bluetooth sensors)", icon: "gauge.with.dots.needle.33percent") }
                } header: { Text("Sensors paired on the BikeComputer") } footer: { Text("These pair on the board (its Connections menu). The phone shows what the board reports.") }
            }
            Section("Phone") {
                NavigationLink { PhoneConnectionDetail(kind: .bluetooth) } label: { ConnRow(status: bluetoothStatus, title: "Bluetooth", subtitle: bluetoothSubtitle, icon: "antenna.radiowaves.left.and.right") }
                NavigationLink { PhoneConnectionDetail(kind: .internet) } label: { ConnRow(status: ConnectionRules.internet(online: reach.online), title: "Internet", subtitle: reach.online ? "online via \(reach.kind)" : "offline · the app keeps working", icon: "network") }
            }
            Section {
                NavigationLink { HealthConnectionDetail() } label: { ConnRow(status: healthStatus, title: "Apple Health", subtitle: healthSubtitle, icon: "heart.text.square") }
                if ReleaseFlags.plannedProvidersVisible {
                    ForEach(ProviderCatalog.planned) { p in
                        NavigationLink { PlannedProviderDetail(provider: p) } label: { ConnRow(status: ConnectionRules.source(p.status), title: p.name, subtitle: "Planned — not available yet", icon: p.icon) }
                    }
                }
            } header: { Text("Imported (after the activity)") } footer: { Text("Imported workouts add to your history after the activity — never live values.") }
        }
        .navigationTitle("Connections")
        .onReceive(timer) { tick = $0; health.refresh() }
    }

    // MARK: statuses
    private var boardWanted: Bool { store.settings.enabledConnections.contains("board") && device.remembered && store.settings.autoConnectBoard }
    private var liveNow: BCLink.Live? { device.state == .ready && device.liveIsFresh ? device.live : nil }
    private var boardStatus: ConnStatus { ConnectionRules.board(linkState: device.state, liveFresh: device.liveIsFresh, remembered: device.remembered, autoConnect: store.settings.autoConnectBoard, phoneOnlyMode: store.settings.phoneOnlyMode, pairingLost: device.failure?.action == .repair) }
    private var boardSubtitle: String {
        if !device.remembered, device.state != .ready, !device.stage.isAttempt, device.stage != .failed { return "optional · not set up" }
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
            return device.remembered ? "not in range · reconnects by itself" : "optional · not set up"
        default:
            if device.stage == .failed, let f = device.failure { return "\(f.stage.rawValue.lowercased()) failed — " + (f.action == .repair ? "tap for Repair" : "tap for details") }
            if device.stage == .waiting { return "waiting for the board (not in range)" }
            return device.stage.rawValue.lowercased() + "…"
        }
    }
    private var sensorsWanted: Bool { !hub.ble.paired.isEmpty }
    private var bluetoothStatus: ConnStatus { ConnectionRules.bluetooth(linkState: device.state, boardWanted: boardWanted || sensorsWanted) }
    private var bluetoothSubtitle: String { switch device.state { case .off: return "Bluetooth is off on the phone"; case .unauthorized: return "permission needed (iOS Settings)"; default: return "on" } }
    private var gpsRequired: Bool { store.settings.phoneOnlyMode || !device.remembered }
    private var gpsStatus: ConnStatus { ConnectionRules.gps(authorized: location.authorized, sharing: location.sharing, hasFix: location.last != nil, requiredForRides: gpsRequired) }
    private var gpsSubtitle: String { location.authorized ? (location.sharing ? location.status : "ready · starts with a ride") : "location permission needed" }
    private var watchEnabled: Bool { store.settings.enabledConnections.contains("watch") }
    private var watchStatus: ConnStatus { ConnectionRules.watch(paired: watch.paired, appInstalled: watch.appInstalled, hrFresh: watch.hrIsFresh, workoutRunning: watch.workoutState == "running", enabled: watchEnabled) }
    private var watchSubtitle: String {
        if !watchEnabled { return "off (your choice)" }
        if watch.paired, watch.appInstalled, watch.version == .watchOlder { return "watch app outdated — update it in the Watch app" }
        if watch.hrIsFresh { return "heart rate live · \(watch.hrBpm ?? 0) bpm" + (watch.mirror.active ? " · mirrored" : "") }
        if let w = monitor.reports.first(where: { $0.id == "watch.hr" }), w.health.needsMessage { return w.message }
        if !watch.paired { return "no watch paired with this iPhone" }
        if !watch.appInstalled { return "watch app not installed" }
        return watch.workoutState == "running" ? "workout running · waiting for heart rate" : "ready · start the workout on the watch"
    }
    private var meterEnabled: Bool { store.settings.enabledConnections.contains("meter") || device.remembered }
    /// Green only with a live power value — "connected" alone is never success (PIPELINE_HEALTH.md).
    private var powerPipeline: PipelineReport? { monitor.reports.first { $0.id == "board.power" } }
    private var meterStatus: ConnStatus {
        let base = ConnectionRules.meter(boardLive: liveNow != nil, meterLink: liveNow?.meterLink, enabled: meterEnabled)
        if base == .green, liveNow?.powerW == nil { return powerPipeline?.health == .noData || powerPipeline?.health == .failed ? .red : .amber }
        return base
    }
    private var meterSubtitle: String {
        if let p = powerPipeline, p.health != .live, p.health != .notSetUp, !p.message.isEmpty { return p.message }
        guard let l = liveNow else { return device.remembered ? "reported by the board when connected" : "pairs on the board" }
        switch l.meterLink { case 4: return l.powerW.map { "live · \($0) W" } ?? "connected — waiting for data"; case 7: return "connected — data stale"; case 2: return "board searching (pedal once)"; case 3: return "connecting"; case 5: return "reconnecting"; case 1: return "not paired on the board"; default: return "off" }
    }
    private var strapEnabled: Bool { store.settings.enabledConnections.contains("strap") }
    private var strapStatus: ConnStatus { ConnectionRules.strap(boardLive: liveNow != nil, hrFromStrap: liveNow?.hrSource == .bleStrap && liveNow?.hrBpm != nil, enabled: strapEnabled) }
    private var strapSubtitle: String { strapStatus == .green ? "live via the board" : strapEnabled ? "pair on the board · Settings › Sensors" : "optional" }
    private var healthStatus: ConnStatus { ConnectionRules.health(wanted: store.settings.appleHealthWanted, authorized: health.workoutWriteAuthorized, available: health.available) }
    private var healthSubtitle: String { !health.available ? "not available on this device" : health.workoutWriteAuthorized ? "connected" : store.settings.appleHealthWanted ? "permission not granted yet" : "optional · not connected" }
}

/// The value each metric shows right now and where it comes from — or the plain "No … source".
struct InUseNowRows: View {
    @ObservedObject var hub: SensorHub
    var body: some View {
        ForEach(MetricKind.allCases, id: \.self) { k in
            HStack(alignment: .firstTextBaseline) {
                Text(k.title).font(.subheadline.weight(.semibold)).frame(width: 92, alignment: .leading)
                if let r = hub.reading(k) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(SourceFormat.value(r) + " " + k.unit).font(.subheadline.monospacedDigit())
                        Text(r.sourceLabel + (r.quality == .good ? "" : " · " + r.quality.title)).font(.caption).foregroundStyle(r.quality == .unverified ? BC.stale : .secondary)
                    }
                } else {
                    Text(hub.missingReason[k] ?? k.missingText).font(.subheadline).foregroundStyle(hub.missingReason[k] == nil ? Color.secondary : BC.stale)
                }
                Spacer()
            }
            .accessibilityElement(children: .combine)
        }
    }
}

enum SourceFormat {
    static func value(_ r: MetricReading) -> String { r.kind == .speed ? String(format: "%.1f", r.value) : "\(r.intValue)" }
    static func ago(_ d: Date?, now: Date = Date()) -> String {
        guard let d else { return "never" }
        let s = Int(now.timeIntervalSince(d))
        if s < 5 { return "just now" }
        if s < 60 { return "\(s) s ago" }
        if s < 3600 { return "\(s / 60) min ago" }
        return d.formatted(date: .abbreviated, time: .shortened)
    }
}

/// Paired direct sensors (one row each) and the "Add a Bluetooth sensor" entry.
struct BLESensorRows: View {
    @ObservedObject var ble: BLESensors
    @ObservedObject var hub: SensorHub
    var body: some View {
        ForEach(ble.paired) { s in
            NavigationLink { BLESensorDetail(ble: ble, hub: hub, sensorId: s.id) } label: {
                ConnRow(status: ConnectionRules.source(status(s)), title: s.name, subtitle: subtitle(s), icon: icon(s))
            }
        }
        NavigationLink { BLEPairView(ble: ble) } label: {
            Label(ble.paired.isEmpty ? "Add a Bluetooth sensor (heart rate, power, speed, cadence)" : "Add another Bluetooth sensor", systemImage: "plus.circle").font(.subheadline)
        }
    }
    private func status(_ s: PairedSensor) -> SourceStatus {
        hub.status(s.sourceId) ?? SourceStatus(descriptor: ble.descriptor(s), state: SourceStateRules.bleSensor(radio: ble.radio, link: ble.link(s.id)), metrics: s.metrics, provides: "", configured: true)
    }
    private func subtitle(_ s: PairedSensor) -> String {
        let st = SourceStateRules.bleSensor(radio: ble.radio, link: ble.link(s.id))
        let what = s.kinds.isEmpty ? "sensor" : s.kinds.map { $0.title.lowercased() }.joined(separator: " · ")
        switch st {
        case .connected:
            let vals = hub.readings(from: s.sourceId).map { SourceFormat.value($0) + " " + $0.kind.unit }
            return "connected · " + (vals.isEmpty ? what : vals.joined(separator: " · "))
        case .connecting: return "\(what) · waiting for the sensor (wake it up)"
        case .notAuthorized: return "Bluetooth permission needed"
        default: return ble.radio == .off ? "Bluetooth is off" : "\(what) · not connected"
        }
    }
    private func icon(_ s: PairedSensor) -> String {
        if s.kinds.contains(.power) { return "bolt" }
        if s.kinds.contains(.heartRate) { return "heart" }
        return "gauge.with.dots.needle.33percent"
    }
}

/// Search for standard sensors; nothing pairs until the rider taps one.
struct BLEPairView: View {
    @ObservedObject var ble: BLESensors
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        List {
            Section {
                switch ble.radio {
                case .off: Text("Bluetooth is off. Turn it on in Control Centre or Settings.").foregroundStyle(BC.warn)
                case .unauthorized:
                    Text("This app has no Bluetooth permission.").foregroundStyle(BC.warn)
                    Button("Open Settings") { DeviceLink.openSettings() }
                case .unsupported: Text("Bluetooth is not available on this device.").foregroundStyle(.secondary)
                default:
                    if ble.discovered.isEmpty {
                        HStack { Text(ble.scanning ? "Searching… wake the sensor (pedal, spin the wheel, or wear the strap)." : "Search stopped."); Spacer(); if ble.scanning { ProgressView() } }.font(.footnote)
                    }
                    ForEach(ble.discovered) { d in
                        Button { ble.pair(d.id); dismiss() } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(d.name).font(.body.weight(.semibold))
                                    Text(d.kinds.isEmpty ? "standard sensor" : d.kinds.map(\.title).joined(separator: " · ")).font(.footnote).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text("\(d.rssi) dBm").font(.caption).foregroundStyle(.secondary)
                            }
                        }.frame(minHeight: 44)
                    }
                    if !ble.scanning { Button("Search again") { ble.startScan() } }
                }
            } header: { Text("Sensors nearby") } footer: {
                Text("Tap a sensor to add it. Nothing is added automatically. Added sensors reconnect by themselves whenever they are awake and in range. The app only reads from sensors — it never changes their settings or calibration.")
            }
            Section("What can be added") {
                Text("Any standard Bluetooth heart-rate monitor, power meter, or speed / cadence sensor. Watches and bands that broadcast heart rate over standard Bluetooth also work while broadcasting.").font(.footnote)
                Text("A sensor that is already connected to another phone or app may not appear; close that app first.").font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Add a sensor")
        .onAppear { ble.startScan() }
        .onDisappear { ble.stopScan() }
    }
}

struct BLESensorDetail: View {
    @ObservedObject var ble: BLESensors
    @ObservedObject var hub: SensorHub
    let sensorId: String
    @State private var confirmForget = false
    @Environment(\.dismiss) private var dismiss
    private var sensor: PairedSensor? { ble.paired.first { $0.id == sensorId } }
    var body: some View {
        List {
            if let s = sensor {
                let st = SourceStateRules.bleSensor(radio: ble.radio, link: ble.link(s.id))
                Section("Status") {
                    LabeledContent("Connection", value: st.title)
                    LabeledContent("Connected by", value: ConnectionMethod.bleDirect.title)
                    LabeledContent("Data", value: "live")
                    LabeledContent("Last update", value: SourceFormat.ago(hub.status(s.sourceId)?.lastUpdate ?? ble.lastData[s.id]))
                    ForEach(hub.readings(from: s.sourceId), id: \.kind) { r in
                        LabeledContent(r.kind.title, value: SourceFormat.value(r) + " " + r.kind.unit + (r.quality == .good ? "" : " · " + r.quality.title))
                    }
                    if let e = ble.lastError, st != .connected { Text(e).font(.footnote).foregroundStyle(.secondary) }
                }
                Section("Measures") {
                    Text(s.metrics.isEmpty ? "Found when the sensor connects." : s.metrics.map(\.title).joined(separator: ", ")).font(.footnote)
                    if s.kinds.contains(.power) { Text("Power from a meter that has not been checked against a reference is marked unverified; the coach treats it as provisional.").font(.footnote).foregroundStyle(.secondary) }
                    if s.kinds.contains(.speedCadence) { Text("Speed uses your wheel circumference (Profile › \(hub.ble.wheelMm()) mm).").font(.footnote).foregroundStyle(.secondary) }
                }
                Section {
                    Button("Reconnect") { ble.reconnect(s.id) }.frame(minHeight: 44)
                    Button("Forget this sensor", role: .destructive) { confirmForget = true }.frame(minHeight: 44)
                } footer: { Text("Sensors sleep when not in use; they reconnect by themselves once awake. Forget removes it from this phone only.") }
            } else {
                Text("This sensor was removed.").foregroundStyle(.secondary)
            }
        }
        .navigationTitle(sensor?.name ?? "Sensor")
        .alert("Forget this sensor?", isPresented: $confirmForget) {
            Button("Forget", role: .destructive) { ble.forget(sensorId); dismiss() }
            Button("Cancel", role: .cancel) {}
        } message: { Text("The phone stops connecting to it. You can add it again any time.") }
    }
}

/// A cloud provider that is not built yet: honest status, what it will provide, what works today.
struct PlannedProviderDetail: View {
    let provider: PlannedProvider
    var body: some View {
        List {
            Section("Status") {
                LabeledContent("Status", value: "Planned — not available yet")
                LabeledContent("Data", value: "after the activity (imported)")
            }
            Section("Will provide") { Text(provider.willProvide).font(.footnote) }
            Section("Live heart rate today") { Text(provider.liveNow).font(.footnote) }
            Section { Text("This connection needs an approved developer account with \(provider.name) and your sign-in. Nothing is read from \(provider.name) in this version.").font(.footnote).foregroundStyle(.secondary) }
        }.navigationTitle(provider.name)
    }
}

struct ConnRow: View {
    let status: ConnStatus; let title: String; let subtitle: String; let icon: String
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(.title3).foregroundStyle(.secondary).frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body.weight(.semibold))
                Text(subtitle).font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
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
            BoardDiagReportSection()
            Section("Pairing steps") {
                step(1, "Switch the BikeComputer on and keep it within a metre. Its Phone screen (Connections › Phone) shows SEARCHING.")
                step(2, "Tap Connect, then the board in the list.")
                step(3, "Type the 6-digit code shown on the round screen into the iPhone dialog.")
                step(4, "Done: the phone is remembered on the board and reconnects by itself; the profile is compared and, after your confirmation, the phone's profile is applied.")
            }
            Section("What it provides") {
                Text("Live power and cadence from the power meter paired on the board, ride state, time and distance, board battery estimate, heart rate from a strap paired on the board, finished rides (history sync), Wi-Fi setup, device settings and the shared athlete profile (firmware 0.6.0+).").font(.footnote)
            }
            Section("Troubleshooting") {
                Text("• Nothing found: Phone link must be ON on the board (Connections › Phone); Bluetooth on the phone must be on; firmware 0.5.0 stops advertising when its screen sleeps.\n• \"Peer removed pairing information\" / pairing refused: the board lost this phone's keys (data reset, Forget phone, restored backup). Use Repair below.\n• Connected but no values: pedal once so the power meter wakes; the board shows the meter state under Connections › Power meter.\n• Drops when the board screen turns off: fixed in firmware 0.6.0.").font(.footnote)
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
            if let a = action { Button(a.0) { a.1() }.buttonStyle(.bordered).controlSize(.large).padding(.leading, 32).disabled(a.0 == "Searching…") }
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
                Section("Used for") { Text("Bluetooth sensors paired with this phone (heart rate, power, speed, cadence) and the optional BikeComputer link. Apple Watch uses its own connection.").font(.footnote) }
                Section("Troubleshooting") { Text("Turn Bluetooth on in Control Centre or Settings. If permission was denied: Settings › Cyclift › Bluetooth.").font(.footnote) }
            case .gps:
                Section("Status") {
                    LabeledContent("Permission", value: location.authorized ? "granted" : "not granted")
                    LabeledContent("GPS", value: location.sharing ? location.status : "off until a ride starts")
                    LabeledContent("Fixes sent to the board", value: "\(location.sent)")
                }
                Section("Used for") { Text("Speed, distance and the route map for phone-only rides; speed and distance for the BikeComputer, which has no GPS of its own.").font(.footnote) }
                Section { if !location.authorized { Button("Allow location") { location.requestPermission() } } ; Toggle("GPS on now", isOn: $location.sharing) }
                Section("Troubleshooting") { Text("Allow \"While Using the App\". Once a ride is recording, GPS keeps working with the screen locked. GPS is weak indoors.").font(.footnote) }
            case .internet:
                Section("Status") { LabeledContent("Internet", value: reach.online ? "online (\(reach.kind))" : "offline") }
                Section("Used for") { Text("Cyclift does not need the internet: rides, plan and profile stay on this iPhone (and the optional BikeComputer), and everything works offline. Maps of your rides load from Apple Maps when online.").font(.footnote) }
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
                StatusRow(title: "Cyclift app installed on the watch", ok: watch.appInstalled)
                StatusRow(title: "Watch app reachable now", ok: watch.reachable)
                LabeledContent("Workout on the watch", value: watch.workoutState)
                LabeledContent("Live heart rate", value: watch.hrIsFresh ? "\(watch.hrBpm ?? 0) bpm" : "--")
                LabeledContent("Live channel", value: watch.mirror.active ? "workout mirroring (works in the background)" : watch.reachable ? "Watch Connectivity (app open)" : "none")
                LabeledContent("Last delivery", value: SourceFormat.ago(watch.lastDeliveryAt))
                LabeledContent("Readings accepted", value: "\(watch.hrReceived)")
                LabeledContent("Watch app", value: watch.watchBuild ?? "not reported yet")
                if watch.version == .watchOlder {
                    Text(WatchVersion.updateInstruction).font(.footnote).foregroundStyle(BC.stale)
                    Text("TestFlight installs the new watch app by itself only when Automatic App Install is on (Watch app on iPhone › General).").font(.caption2).foregroundStyle(.secondary)
                }
                if let b = watch.watchBattery { LabeledContent("Watch battery", value: "\(b) %") }
            }
            Section {
                Toggle("Use the Apple Watch", isOn: Binding(get: { store.settings.enabledConnections.contains("watch") }, set: { if $0 { store.settings.enabledConnections.insert("watch") } else { store.settings.enabledConnections.remove("watch") } }))
                Button("Start watch workout (heart rate)") { watch.startWatchWorkout(reason: "manual") }
                if let r = watch.watchStartResult { Text(r).font(.footnote).foregroundStyle(.secondary) }
                Button("Test connection to the watch") { watch.ping() }
                Text(watch.lastResult).font(.footnote).foregroundStyle(.secondary)
            } footer: { Text("Off = the watch is never shown as missing. On = heart rate from the watch workout reaches the phone and the board, labelled Apple Watch; a reading older than 6 s is dropped, never held.") }
            Section("Steps") {
                Text("1. Install Cyclift on the watch (Watch app › Available Apps).\n2. Starting a ride on the iPhone starts the watch workout automatically (or tap Start watch workout here, or open Cyclift on the watch and tap Start). One workout, no duplicates in Fitness.\n3. Heart rate appears here and on the board within a few seconds.").font(.footnote)
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
                Section("Pairing") { Text("A power meter can pair on the BikeComputer (Settings › Sensors › Power meter) or directly with this phone (Connections › Add a Bluetooth sensor). Pedal once to wake it.").font(.footnote) }
                Section("Measurements") { Text("Power (W), cadence (rpm), energy (kJ), zones — recorded by the board, mirrored here.").font(.footnote) }
            case .strap:
                Section("Status") { LabeledContent("Heart rate from a strap", value: live?.hrSource == .bleStrap ? "\(live?.hrBpm ?? 0) bpm live" : "none") }
                Section {
                    Toggle("I use a heart-rate strap", isOn: Binding(get: { store.settings.enabledConnections.contains("strap") }, set: { if $0 { store.settings.enabledConnections.insert("strap") } else { store.settings.enabledConnections.remove("strap") } }))
                } footer: { Text("Pairs on the board (Settings › Sensors › Heart rate, standard Bluetooth 0x180D) — or directly with this phone under Bluetooth sensors. A strap wins over the watch unless you prefer the watch in Profile.") }
            case .speed:
                Section { Text("Standard Bluetooth speed / cadence sensors pair directly with this phone: Connections › Add a Bluetooth sensor. On the BikeComputer they need a firmware that lists Cadence / Speed under Connections. Without one, speed and distance come from the phone's GPS and cadence from the power meter.").font(.footnote) }
            }
        }.navigationTitle(kind == .meter ? "Power meter via BikeComputer" : kind == .strap ? "Heart-rate strap via BikeComputer" : "Speed / cadence")
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
            } footer: { Text("Shown as connected only after iOS confirms the permission. Cycling workouts recorded with the Cyclift Apple Watch app are saved to Health when you choose Save on the watch.") }
            Section {
                Toggle("Import workouts from Apple Health", isOn: Binding(get: { store.settings.appleHealthImportWorkouts }, set: { v in store.settings.appleHealthImportWorkouts = v; if v { store.settings.appleHealthWanted = true; if !health.workoutWriteAuthorized { health.request { _ in runImport() } } else { runImport() } } }))
                Button { runImport() } label: { HStack { Text(importing ? "Importing…" : "Import now (last 90 days)"); Spacer(); if importing { ProgressView() } } }.disabled(importing || !health.available)
                if let r = importResult { Text(r).font(.footnote).foregroundStyle(.secondary) }
                if let d = store.settings.lastHealthImport { LabeledContent("Last import", value: d.formatted(date: .abbreviated, time: .shortened)) }
            } header: { Text("Workout import") } footer: { Text("Cycling, traditional and functional strength workouts recorded by other apps or the Apple Watch become rides and strength sessions here, marked \"Apple Health\". Duplicates of what the phone or BikeComputer already recorded (same start within 2 minutes, similar duration) are skipped. Health workouts carry no body region, so they count as sessions but never as push / pull / lower evidence.") }
            Section("What each permission does") {
                Text("Workouts (write): save the cycling workout you record with the Cyclift Apple Watch app.\nWorkouts (read): import cycling and strength workouts recorded by other apps or the Apple Watch into your history.\nHeart rate and active energy (read): used by the watch app during your workout. iOS does not tell apps whether reading was allowed, so nothing is claimed about it.").font(.footnote)
                Text("Live heart rate during a ride does not come from Health; it comes from the Apple Watch workout or a strap.").font(.footnote).foregroundStyle(.secondary)
            }
        }.navigationTitle("Apple Health")
    }
}
