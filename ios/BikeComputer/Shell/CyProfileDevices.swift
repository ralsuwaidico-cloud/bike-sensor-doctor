import SwiftUI
import UserNotifications

// Profile v2.0, sheet P06 (visual design "Pending Review" on the sheet) — Devices & Connections and the pages behind it:
//   D   one row per device family with its real state, "This iPhone", Connection diagnostics
//   D1  Cyclift BikeComputer     D2  sensors (heart rate, power, other)     D3  Apple Health
//       Apple Watch · This iPhone (the sheet names the rows; these two pages follow the same pattern)
// Every action here calls the SAME function the existing pages call (ConnectionsView.swift, DeviceSettingsView.swift,
// ProfileEditors.swift › DeviceCardList): connect, disconnect, forget, repair, sensor scan / pair / reconnect / forget,
// the Apple Health switches. Nothing here writes a setting to the BikeComputer, starts a firmware update or sends a
// control command; firmware is shown, never changed. What stays on its existing page is opened by a named row:
// profile sync, device settings & Wi-Fi, the repair steps, the stored diagnostic reports, the pipeline diagnostics.
// Cyclift Lab: nothing connects and no permission is asked — the Lab pages below hold none of the device objects.

// MARK: - shared pieces

/// The state on the right of a row: a shape and a word, never colour alone (sheet P06, "six connection states").
struct CyDevStateBadge: View {
    let state: ProfileConnection
    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: state.symbol).font(CyDyn.f(11, .bold)).accessibilityHidden(true)
            Text(state.word).font(CyDyn.f(13, .semibold))
        }
        .foregroundStyle(state == .receiving || state == .connected ? CyTheme.ink : CyTheme.ink2)
    }
}

/// A fact: title, an optional line under it, the value on the right, a hairline. Long values wrap; nothing overlaps.
struct CyDevFact: View {
    let title: String
    var note: String? = nil
    let value: String
    var id: String
    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(CyDyn.f(16.5, .semibold)).foregroundStyle(CyTheme.ink).fixedSize(horizontal: false, vertical: true)
                    if let note, !note.isEmpty { Text(note).font(CyDyn.f(13.5)).foregroundStyle(CyTheme.ink2).fixedSize(horizontal: false, vertical: true) }
                }
                Spacer(minLength: 8)
                Text(value).font(CyDyn.f(15, .semibold)).foregroundStyle(CyTheme.ink2).multilineTextAlignment(.trailing).fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
            Rectangle().fill(CyTheme.line).frame(height: 1).accessibilityHidden(true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title), \(value)\(note.map { ". \($0)" } ?? "")")
        .accessibilityIdentifier(id)
    }
}

/// The status line at the top of a device page: the family's state in the sheet's word, and what is known about it.
struct CyDevStatus: View {
    let state: ProfileConnection?
    let note: String
    var id: String
    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Status").font(CyDyn.f(16.5, .semibold)).foregroundStyle(CyTheme.ink)
                    if !note.isEmpty { Text(note).font(CyDyn.f(13.5)).foregroundStyle(CyTheme.ink2).fixedSize(horizontal: false, vertical: true) }
                }
                Spacer(minLength: 8)
                if let state { CyDevStateBadge(state: state) }
            }
            .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
            Rectangle().fill(CyTheme.line).frame(height: 1).accessibilityHidden(true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Status, \(state?.word ?? "not known"). \(note)")
        .accessibilityIdentifier(id)
    }
}

/// A row that does something on this page (reconnect, forget, test): title, one line, a chevron, a hairline.
struct CyDevActionRow: View {
    let title: String
    var note: String? = nil
    var id: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title).font(CyDyn.f(16.5, .semibold)).foregroundStyle(CyTheme.ink).fixedSize(horizontal: false, vertical: true)
                        if let note, !note.isEmpty { Text(note).font(CyDyn.f(13.5)).foregroundStyle(CyTheme.ink2).fixedSize(horizontal: false, vertical: true) }
                    }
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(CyTheme.ink3).accessibilityHidden(true)
                }
                .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading).contentShape(Rectangle())
                Rectangle().fill(CyTheme.line).frame(height: 1).accessibilityHidden(true)
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
    }
}

/// The two buttons of sheet D1: the main one is a light pill with dark text, the other an outlined pill.
struct CyDevButton: View {
    let title: String
    var primary = true
    var id: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title).font(CyDyn.f(16, .semibold)).multilineTextAlignment(.center)
                .foregroundStyle(primary ? CyTheme.canvas : CyTheme.ink)
                .padding(.horizontal, 16).padding(.vertical, 6)
                .frame(maxWidth: .infinity, minHeight: 48)
                .background(primary ? CyTheme.ink : Color.clear, in: Capsule())
                .overlay(Capsule().stroke(primary ? Color.clear : CyTheme.ink, lineWidth: 1.2))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
    }
}

struct CyDevNote: View {
    let text: String
    var body: some View {
        Text(text).font(CyDyn.f(13.5)).foregroundStyle(CyTheme.ink2).fixedSize(horizontal: false, vertical: true).padding(.top, 14)
    }
}

/// One family row of sheet D: title, one line, the state on the right, a chevron when it opens a page.
struct CyDevFamilyLabel: View {
    let row: ProfileDeviceRow
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(row.title).font(CyDyn.f(16.5, .semibold)).foregroundStyle(row.opens == .nothing ? CyTheme.ink2 : CyTheme.ink).fixedSize(horizontal: false, vertical: true)
                    Text(row.summary).font(CyDyn.f(13.5)).foregroundStyle(CyTheme.ink2).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                if let s = row.state { CyDevStateBadge(state: s) }
                if row.opens != .nothing { Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(CyTheme.ink3).accessibilityHidden(true) }
            }
            .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading).contentShape(Rectangle())
            Rectangle().fill(CyTheme.line).frame(height: 1).accessibilityHidden(true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(row.state.map { "\(row.title), \($0.word). \(row.summary)" } ?? "\(row.title). \(row.summary)")
        .accessibilityAddTraits(row.opens == .nothing ? [] : .isButton)
    }
}

// MARK: - D · the family rows

/// Sheet P06 D in the main app: one row per device family with its real state on the right, then "This iPhone" and
/// Connection diagnostics. The states come from the same hub the existing devices screen reads.
struct CyProfileDeviceFamilies: View {
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var hub: SensorHub
    @EnvironmentObject private var device: DeviceLink
    @EnvironmentObject private var health: HealthAccess
    @EnvironmentObject private var location: LocationService

    private var rows: [ProfileDeviceRow] {
        let states = UITestSupport.deviceStatesForDisplay() ?? hub.deviceStates
        let sensors = hub.ble.paired.map { DeviceCards.Sensor(id: $0.sourceId, name: $0.name, provides: $0.kinds.map(\.title).joined(separator: ", "),
                                                              hasHR: $0.kinds.contains(.heartRate), hasPower: $0.kinds.contains(.power), hasCadence: $0.kinds.contains(.speedCadence)) }
        let cards = DeviceCards.build(states: states, mode: store.profile.trainingMode, bleSensors: sensors, healthAvailable: health.available, boardRemembered: device.remembered)
        let families = ProfileDeviceRows.build(cards: cards, healthAvailable: health.available, cycling: store.profile.trainingMode.includesCycling)
        let bluetooth = ProfilePhoneWords.bluetooth(off: device.state == .off || hub.ble.radio == .off,
                                                    unauthorized: device.state == .unauthorized || hub.ble.radio == .unauthorized, unsupported: hub.ble.radio == .unsupported)
        return ProfileDeviceRows.withPhone(families, summary: ProfilePhoneWords.summary(bluetooth: bluetooth, location: ProfilePhoneWords.location(authorized: location.authorized, denied: location.denied)))
    }

    var body: some View {
        ForEach(rows) { r in
            if r.opens == .nothing {
                CyDevFamilyLabel(row: r).accessibilityIdentifier("profileDevice-\(r.id)")
            } else {
                NavigationLink { destination(r) } label: { CyDevFamilyLabel(row: r) }
                    .buttonStyle(.plain).accessibilityIdentifier("profileDevice-\(r.id)")
            }
        }
    }

    @ViewBuilder private func destination(_ r: ProfileDeviceRow) -> some View {
        switch r.opens {
        case .health: CyDeviceHealthPage(shown: r.state)
        case .watch: CyDeviceWatchPage(shown: r.state)
        case .board: CyDeviceBoardPage(shown: r.state)
        case .sensors: CyDeviceSensorsPage(family: ProfileSensorFamily(rawValue: r.id) ?? .other, shown: r.state)
        case .phone: CyDevicePhonePage(permissions: false)
        // the existing page (every path stage by stage, recovery, export): kept as it is — see the report
        case .diagnostics: PipelineDiagnosticsView()
        case .nothing: EmptyView()
        }
    }
}

/// Sheet P06 D in Cyclift Lab: the same rows, all Unavailable. Each opens a page that says so and offers no action.
struct CyProfileDeviceFamiliesLab: View {
    @EnvironmentObject private var store: Store
    var body: some View {
        ForEach(ProfileDeviceRows.lab(cycling: store.profile.trainingMode.includesCycling)) { r in
            if r.opens == .nothing {
                CyDevFamilyLabel(row: r).accessibilityIdentifier("profileDevice-\(r.id)")
            } else {
                NavigationLink { CyDeviceLabPage(row: r) } label: { CyDevFamilyLabel(row: r) }
                    .buttonStyle(.plain).accessibilityIdentifier("profileDevice-\(r.id)")
            }
        }
    }
}

/// A device page in Cyclift Lab: the page's title and purpose, the one true state, and what the page offers in the
/// real app — as words, with no control. No device object is read here.
struct CyDeviceLabPage: View {
    let row: ProfileDeviceRow
    private var purpose: String {
        switch row.opens {
        case .health: return "Rides, weight and resting heart rate shared with Apple Health."
        case .watch: return "Heart rate from your Apple Watch while you train."
        case .board: return "Waveshare board. Records rides on the handlebar."
        case .sensors: return (ProfileSensorFamily(rawValue: row.id) ?? .other).purpose
        case .phone: return "What this iPhone allows Cyclift to use."
        default: return ""
        }
    }
    private var offers: [(String, String)] {
        switch row.opens {
        case .health: return [("Use Apple Health", "Off"), ("Export rides to Health", "Off"), ("Import workouts", "Off"), ("Weight, resting heart rate, HRV, sleep", "Off")]
        case .watch: return [("Use the Apple Watch", "Off"), ("Live heart rate", "None")]
        case .board: return [("Connect automatically", "Off"), ("Profile sync", "Not available"), ("Device settings & Wi-Fi", "Not available"), ("Connection diagnostics", "Not available")]
        case .sensors: return [("Paired with this iPhone", "None"), ("Add a sensor", "Not available")]
        case .phone: return [("Bluetooth", ProfilePhoneWords.labNote), ("Location", ProfilePhoneWords.labNote), ("Notifications", ProfilePhoneWords.labNote)]
        default: return []
        }
    }
    var body: some View {
        CyProfilePage(title: row.title, purpose: purpose) {
            if row.opens != .phone {
                CyDevStatus(state: .unavailable, note: ProfilePhoneWords.labNote, id: "deviceStatus-\(row.id)")
            }
            ForEach(Array(offers.enumerated()), id: \.offset) { i, o in
                CyDevFact(title: o.0, value: o.1, id: "deviceLabFact-\(row.id)-\(i)")
            }
            CyDevNote(text: "Cyclift Lab is a demonstration. It connects to nothing, asks for no permission and reads nothing from this iPhone. In the Cyclift app this page shows the real state and its actions.")
                .accessibilityIdentifier("deviceLabNote-\(row.id)")
        }
        .accessibilityIdentifier("devicePage-\(row.id)")
    }
}

// MARK: - D1 · Cyclift BikeComputer

struct CyDeviceBoardPage: View {
    /// The family's state as the Devices page shows it (the same word on both pages).
    let shown: ProfileConnection?
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var device: DeviceLink
    @EnvironmentObject private var sync: ProfileSync
    @State private var confirmForget = false
    @State private var showRepair = false

    private var statusNote: String {
        if let f = device.failure { return f.reason }
        if device.state == .ready, let t = device.lastConnectedAt { return "Connected since \(t.formatted(date: .omitted, time: .shortened))" }
        if device.state != .ready, device.remembered, let t = device.lastDisconnectedAt { return "Last seen \(t.formatted(date: .abbreviated, time: .shortened))" }
        return device.remembered ? device.statusText : "Not set up on this iPhone"
    }
    private var hasDeviceSettings: Bool { device.info?.hasSettings == true || device.info?.hasWiFi == true }

    var body: some View {
        CyProfilePage(title: "Cyclift BikeComputer", purpose: "Waveshare board. Records rides on the handlebar.") {
            CyDevStatus(state: shown, note: statusNote, id: "deviceStatus-board")
            CyToggleRow(title: "Connect automatically", note: "Attaches when the board is on and in range",
                        isOn: Binding(get: { store.settings.autoConnectBoard }, set: { store.settings.autoConnectBoard = $0; device.autoConnect = $0 }), id: "boardAutoConnect")
            found
            facts
            CyProfileRows {
                CyProfileRow(title: "Profile sync", summary: sync.statusLine, id: "boardProfileSync") { SyncStatusView() }
                if hasDeviceSettings {
                    CyProfileRow(title: "Device settings & Wi-Fi", summary: "Screen, wake, sleep", id: "boardSettings") { DeviceSettingsView() }
                } else {
                    CyProfileRow(title: "Device settings & Wi-Fi", summary: device.state == .ready ? "Needs firmware 0.6.0 or newer" : "Connect the BikeComputer first", kind: .fact, id: "boardSettings")
                }
                CyProfileRow(title: "Connection diagnostics", summary: "Stage, identity, history", id: "boardDiagnostics") { CyDeviceBoardDiagnostics() }
                CyProfileRow(title: "Pairing help", summary: "Steps and troubleshooting", id: "boardHelp") { CyDeviceBoardHelp() }
            }
            actions.padding(.top, 16)
        }
        .accessibilityIdentifier("devicePage-board")
        // the same question, wording and action as the existing BikeComputer page
        .alert("Forget this BikeComputer?", isPresented: $confirmForget) {
            Button("Forget", role: .destructive) { device.forget() }
            Button("Cancel", role: .cancel) {}
        } message: { Text("The phone forgets the board and its pairing record here. Your rides, plan and profile stay. To pair again you also remove it in iOS Settings › Bluetooth and hold FORGET PHONE on the board.") }
        .sheet(isPresented: $showRepair) { RepairSheet() }
    }

    /// While searching: the boards found; tapping one connects to it (the existing page's list).
    @ViewBuilder private var found: some View {
        if device.stage == .searching || device.stage == .found {
            if device.found.isEmpty {
                CyDevNote(text: "Searching… the board must be on and its Phone screen must say SEARCHING / WAITING.").padding(.bottom, 10)
            }
            ForEach(device.found, id: \.id) { f in
                CyDevActionRow(title: f.name, note: "\(f.rssi) dBm · tap to connect", id: "boardFound-\(f.id.uuidString)") { device.connect(to: f.id) }
            }
        }
        if device.stage == .pairing || device.stage == .authenticating {
            CyDevNote(text: "Look at the round screen: it shows a 6-digit code. Type it into the iPhone dialog. This happens once per phone.").padding(.bottom, 10)
        }
    }

    /// Shown, never changed: firmware and link facts the board reported.
    @ViewBuilder private var facts: some View {
        if let i = device.info {
            CyDevFact(title: "Firmware", note: "Shown only — not updated from here", value: i.fw, id: "boardFirmware")
            CyDevFact(title: "Protocol", value: "v\(i.verMajor).\(i.verMinor)", id: "boardProtocol")
        }
        if let r = device.rssi { CyDevFact(title: "Signal", value: "\(r) dBm", id: "boardSignal") }
        if let l = device.live, device.liveIsFresh {
            CyDevFact(title: "Board battery", note: "Estimate from voltage", value: l.batteryPct.map { "≈\($0) %" } ?? "Unknown", id: "boardBattery")
        }
    }

    /// One consistent set of buttons per state, as on the existing page: never Disconnect without a live connection,
    /// never Connect while connected.
    @ViewBuilder private var actions: some View {
        VStack(spacing: 12) {
            switch device.stage {
            case .ready, .connected, .syncingProfile:
                CyDevButton(title: "Disconnect", id: "boardPrimary") { device.disconnect() }
            case .searching, .found, .connecting, .waiting, .pairing, .authenticating:
                CyDevButton(title: "Cancel", id: "boardPrimary") { device.disconnect() }
                CyDevButton(title: "Repair connection", primary: false, id: "boardRepair") { showRepair = true }
            case .failed:
                CyDevButton(title: device.remembered ? "Try again" : "Connect", id: "boardPrimary") { device.connect() }
                if device.failure?.action == .repair || device.remembered {
                    CyDevButton(title: "Repair connection", primary: false, id: "boardRepair") { showRepair = true }
                }
            case .off, .unauthorized:
                CyDevButton(title: "Open iPhone Settings", id: "boardPrimary") { DeviceLink.openSettings() }
            case .idle:
                CyDevButton(title: device.remembered ? "Reconnect" : "Find my BikeComputer", id: "boardPrimary") { device.connect() }
                if device.remembered { CyDevButton(title: "Repair connection", primary: false, id: "boardRepair") { showRepair = true } }
            }
        }
        if device.remembered {
            CyDevActionRow(title: "Forget this device", note: "Removes the pairing from this iPhone", id: "boardForget") { confirmForget = true }
        }
    }
}

/// The existing connection diagnostics, read only (ConnectionDiagnosticsView's values), in the Profile style.
struct CyDeviceBoardDiagnostics: View {
    @EnvironmentObject private var device: DeviceLink
    @EnvironmentObject private var sync: ProfileSync
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var diag: DiagReportCenter

    var body: some View {
        CyProfilePage(title: "Connection diagnostics", purpose: "What the link to the BikeComputer is doing.") {
            CyGroupLabel(text: "NOW")
            now
            CyGroupLabel(text: "IDENTITY")
            identity
            CyGroupLabel(text: "BOARD'S REPORT")
            report
            CyGroupLabel(text: "PROFILE SYNC")
            profileSync
            CyGroupLabel(text: "STAGE HISTORY")
            history
            if diag.boardSupports || !diag.reports.isEmpty {
                CyProfileRows {
                    CyProfileRow(title: "Diagnostic reports", summary: "\(diag.reports.count) saved on this iPhone", id: "boardReports") {
                        List { BoardDiagReportSection() }.navigationTitle("Diagnostic reports").navigationBarTitleDisplayMode(.inline)
                    }
                }
            }
        }
        .accessibilityIdentifier("devicePage-boardDiagnostics")
    }

    @ViewBuilder private var now: some View {
        CyDevFact(title: "Stage", value: device.stage.rawValue, id: "diagStage")
        CyDevFact(title: "Link usable", value: device.state == .ready ? "Yes" : "No", id: "diagUsable")
        CyDevFact(title: "Connect automatically", value: store.settings.autoConnectBoard ? "On" : "Off", id: "diagAuto")
        if let f = device.failure {
            CyDevFact(title: "Last failure", note: f.reason, value: f.code ?? f.stage.rawValue, id: "diagFailure")
        } else if let e = device.lastError {
            CyDevFact(title: "Last error", note: e, value: "", id: "diagError")
        }
    }
    @ViewBuilder private var identity: some View {
        CyDevFact(title: "Board id", value: device.info?.deviceId ?? device.knownDeviceId ?? "Unknown", id: "diagBoardId")
        CyDevFact(title: "Remembered identifier", value: device.rememberedIdentifier.map { String($0.prefix(13)) + "…" } ?? "None", id: "diagRemembered")
        if let s = device.staleIdentifier { CyDevFact(title: "Stale identifier", value: String(s.prefix(13)) + "…", id: "diagStale") }
        if let i = device.info { CyDevFact(title: "Firmware / protocol", value: "\(i.fw) · v\(i.verMajor).\(i.verMinor)", id: "diagFirmware") }
    }
    @ViewBuilder private var report: some View {
        if let d = device.linkDiag {
            CyDevFact(title: "Previous link ended by", value: d.reasonText, id: "diagReason")
            CyDevFact(title: "Phones remembered on the board", value: "\(d.bonds)", id: "diagBonds")
            CyDevFact(title: "Board profile sync", value: d.syncText, id: "diagBoardSync")
        } else {
            Text("Not received yet (firmware 0.7.0 sends it right after connecting).").font(CyDyn.f(13.5)).foregroundStyle(CyTheme.ink2)
                .fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("diagNoReport")
        }
    }
    @ViewBuilder private var profileSync: some View {
        CyDevFact(title: "State", value: sync.statusLine, id: "diagSyncState")
        CyDevFact(title: "Phone profile version", value: "\(store.profile.version)", id: "diagPhoneVersion")
        if let b = device.boardProfile { CyDevFact(title: "Board profile version", value: "\(b.version) (\(b.source == 1 ? "phone-synced" : "device-only"))", id: "diagBoardVersion") }
    }
    @ViewBuilder private var history: some View {
        if device.log.isEmpty {
            Text("Nothing yet").font(CyDyn.f(13.5)).foregroundStyle(CyTheme.ink2).accessibilityIdentifier("diagNoHistory")
        }
        ForEach(device.log.reversed()) { l in
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(l.at.formatted(date: .omitted, time: .standard)).font(CyDyn.f(12)).monospacedDigit().foregroundStyle(CyTheme.ink2)
                Text(l.text).font(CyDyn.f(13.5)).foregroundStyle(CyTheme.ink).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(.vertical, 5).accessibilityElement(children: .combine)
        }
        Text("Connects \(device.stats.connects) · drops \(device.stats.disconnects) · live \(device.stats.liveMsgs) · events \(device.stats.events) · rejected \(device.stats.rejected)")
            .font(CyDyn.f(12)).foregroundStyle(CyTheme.ink2).fixedSize(horizontal: false, vertical: true).padding(.top, 10)
    }
}

/// The pairing steps and troubleshooting of the existing BikeComputer page, word for word, in the Profile style.
struct CyDeviceBoardHelp: View {
    private let steps = [
        "Switch the BikeComputer on and keep it within a metre. Its Phone screen (Connections › Phone) shows SEARCHING.",
        "Tap Find my BikeComputer, then the board in the list.",
        "Type the 6-digit code shown on the round screen into the iPhone dialog.",
        "Done: the phone is remembered on the board and reconnects by itself; the profile is compared and, after your confirmation, the phone's profile is applied.",
    ]
    private let troubles = [
        "Nothing found: Phone link must be ON on the board (Connections › Phone); Bluetooth on the phone must be on; firmware 0.5.0 stops advertising when its screen sleeps.",
        "“Peer removed pairing information” / pairing refused: the board lost this phone's keys (data reset, Forget phone, restored backup). Use Repair connection.",
        "Connected but no values: pedal once so the power meter wakes; the board shows the meter state under Connections › Power meter.",
        "Drops when the board screen turns off: fixed in firmware 0.6.0.",
    ]
    var body: some View {
        CyProfilePage(title: "Pairing help") {
            CyGroupLabel(text: "PAIRING STEPS")
            ForEach(Array(steps.enumerated()), id: \.offset) { i, t in line("\(i + 1)", t) }
            CyGroupLabel(text: "TROUBLESHOOTING")
            ForEach(Array(troubles.enumerated()), id: \.offset) { _, t in line("•", t) }
            CyGroupLabel(text: "WHAT IT PROVIDES")
            Text("Live power and cadence from the power meter paired on the board, ride state, time and distance, board battery estimate, heart rate from a strap paired on the board, finished rides, Wi-Fi setup, device settings and the shared athlete profile (firmware 0.6.0+).")
                .font(CyDyn.f(13.5)).foregroundStyle(CyTheme.ink2).fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityIdentifier("devicePage-boardHelp")
    }
    private func line(_ mark: String, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(mark).font(CyDyn.f(13.5, .semibold)).foregroundStyle(CyTheme.ink).frame(minWidth: 16, alignment: .leading)
            Text(text).font(CyDyn.f(13.5)).foregroundStyle(CyTheme.ink2).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 5).accessibilityElement(children: .combine)
    }
}

// MARK: - D2 · sensors paired with this iPhone (heart rate, power, other use the same page)

struct CyDeviceSensorsPage: View {
    let family: ProfileSensorFamily
    let shown: ProfileConnection?
    @EnvironmentObject private var hub: SensorHub

    private var sensors: [PairedSensor] {
        hub.ble.paired.filter { ProfileSensorFamily.of(hasHR: $0.kinds.contains(.heartRate), hasPower: $0.kinds.contains(.power)) == family }
    }
    private func state(_ s: PairedSensor) -> ProfileConnection {
        ProfileDeviceRows.connection((UITestSupport.deviceStatesForDisplay() ?? hub.deviceStates)[s.sourceId]?.state ?? .paired)
    }
    private func line(_ s: PairedSensor) -> String {
        let what = s.kinds.isEmpty ? "Sensor" : s.kinds.map(\.title).joined(separator: " · ")
        return "\(what) · last update \(SourceFormat.ago(hub.status(s.sourceId)?.lastUpdate ?? hub.ble.lastData[s.id]))"
    }

    var body: some View {
        CyProfilePage(title: family.title, purpose: family.purpose) {
            CyDevStatus(state: shown, note: sensors.isEmpty ? "No sensor of this kind is paired with this iPhone" : "\(sensors.count) paired with this iPhone", id: "deviceStatus-\(family.rawValue)")
            CyGroupLabel(text: "PAIRED WITH THIS IPHONE")
            ForEach(sensors) { s in
                NavigationLink { CyDeviceSensorDetail(sensorId: s.id) } label: {
                    CyDevFamilyLabel(row: ProfileDeviceRow(id: s.id, title: s.name, summary: line(s), state: state(s), opens: .sensors))
                }
                .buttonStyle(.plain).accessibilityIdentifier("sensor-\(s.id)")
            }
            CyProfileRows {
                CyProfileRow(title: "Add a sensor", summary: "Searches for sensors nearby", id: "sensorAdd") { CyDeviceAddSensor() }
            }
            CyDevNote(text: "Cyclift only reads from sensors — it never changes their settings or calibration. A sensor paired on the BikeComputer itself is managed on the board.")
        }
        .accessibilityIdentifier("devicePage-\(family.rawValue)")
    }
}

/// Sheet D2 "sensor detail": connection, what it measures, Reconnect, Forget — the existing sensor page's values and calls.
struct CyDeviceSensorDetail: View {
    let sensorId: String
    @EnvironmentObject private var hub: SensorHub
    @Environment(\.dismiss) private var dismiss
    @State private var confirmForget = false
    private var sensor: PairedSensor? { hub.ble.paired.first { $0.id == sensorId } }

    var body: some View {
        CyProfilePage(title: sensor?.name ?? "Sensor") {
            if let s = sensor {
                detail(s)
            } else {
                Text("This sensor was removed.").font(CyDyn.f(14)).foregroundStyle(CyTheme.ink2).accessibilityIdentifier("sensorRemoved")
            }
        }
        .accessibilityIdentifier("devicePage-sensor")
        // the same question, wording and action as the existing sensor page
        .alert("Forget this sensor?", isPresented: $confirmForget) {
            Button("Forget", role: .destructive) { hub.ble.forget(sensorId); dismiss() }
            Button("Cancel", role: .cancel) {}
        } message: { Text("The phone stops connecting to it. You can add it again any time.") }
    }

    @ViewBuilder private func detail(_ s: PairedSensor) -> some View {
        let st = SourceStateRules.bleSensor(radio: hub.ble.radio, link: hub.ble.link(s.id))
        CyDevFact(title: "Connection", note: "Direct Bluetooth", value: st.title, id: "sensorConnection")
        CyDevFact(title: "Measures", value: s.metrics.isEmpty ? "Found when the sensor connects" : s.metrics.map(\.title).joined(separator: ", "), id: "sensorMeasures")
        CyDevFact(title: "Last update", value: SourceFormat.ago(hub.status(s.sourceId)?.lastUpdate ?? hub.ble.lastData[s.id]), id: "sensorLastUpdate")
        ForEach(hub.readings(from: s.sourceId), id: \.kind) { r in
            CyDevFact(title: r.kind.title, note: r.quality == .good ? nil : r.quality.title, value: SourceFormat.value(r) + " " + r.kind.unit, id: "sensorReading-\(r.kind.title)")
        }
        if let e = hub.ble.lastError, st != .connected {
            Text(e).font(CyDyn.f(13.5)).foregroundStyle(CyTheme.ink2).fixedSize(horizontal: false, vertical: true).padding(.top, 8)
        }
        if s.kinds.contains(.power) {
            CyDevNote(text: "Power from a meter that has not been checked against a reference is marked unverified; the Coach treats it as provisional.")
        }
        CyDevActionRow(title: "Reconnect", note: "Sensors sleep when not in use and reconnect once awake", id: "sensorReconnect") { hub.ble.reconnect(s.id) }
        CyDevActionRow(title: "Forget this sensor", note: "Removes it from this iPhone only", id: "sensorForget") { confirmForget = true }
    }
}

/// "Add a sensor": searches while this page is open; nothing pairs until a sensor is tapped (the existing pairing
/// page's calls: startScan, pair, stopScan).
struct CyDeviceAddSensor: View {
    @EnvironmentObject private var hub: SensorHub
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        CyProfilePage(title: "Add a sensor", purpose: "Heart rate, power, speed or cadence over standard Bluetooth.") {
            AddSensorList(ble: hub.ble) { dismiss() }
            CyDevNote(text: "Tap a sensor to add it. Nothing is added automatically. Added sensors reconnect by themselves whenever they are awake and in range. A sensor that is already connected to another phone or app may not appear; close that app first.")
        }
        .accessibilityIdentifier("devicePage-addSensor")
        .onAppear { hub.ble.startScan() }
        .onDisappear { hub.ble.stopScan() }
    }

    /// Observes the Bluetooth object itself so the list follows the search as it runs.
    private struct AddSensorList: View {
        @ObservedObject var ble: BLESensors
        let done: () -> Void
        var body: some View {
            switch ble.radio {
            case .off:
                CyDevFact(title: "Bluetooth", note: "Turn it on in Control Centre or Settings", value: "Off", id: "addSensorRadio")
            case .unauthorized:
                CyDevFact(title: "Bluetooth", note: "Cyclift has no Bluetooth permission", value: "Not allowed", id: "addSensorRadio")
                CyDevButton(title: "Open iPhone Settings", primary: false, id: "addSensorSettings") { DeviceLink.openSettings() }.padding(.top, 12)
            case .unsupported:
                CyDevFact(title: "Bluetooth", note: "Not available on this device", value: "Not available", id: "addSensorRadio")
            default:
                CyGroupLabel(text: "SENSORS NEARBY")
                if ble.discovered.isEmpty {
                    Text(ble.scanning ? "Searching… wake the sensor (pedal, spin the wheel, or wear the strap)." : "Search stopped.")
                        .font(CyDyn.f(13.5)).foregroundStyle(CyTheme.ink2).fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("addSensorSearching")
                }
                ForEach(ble.discovered) { d in
                    CyDevActionRow(title: d.name, note: (d.kinds.isEmpty ? "Standard sensor" : d.kinds.map(\.title).joined(separator: " · ")) + " · \(d.rssi) dBm", id: "addSensor-\(d.id.uuidString)") {
                        ble.pair(d.id); done()
                    }
                }
                if !ble.scanning {
                    CyDevButton(title: "Search again", primary: false, id: "addSensorAgain") { ble.startScan() }.padding(.top, 12)
                }
            }
        }
    }
}

// MARK: - D3 · Apple Health

/// Sheet D3. Each switch writes the same setting and makes the same request as the existing Apple Health page
/// (HealthConnectionDetail); the recording and import rules themselves are unchanged.
struct CyDeviceHealthPage: View {
    let shown: ProfileConnection?
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var health: HealthAccess
    @State private var importing = false
    @State private var importResult: String?
    @State private var reading = false
    @State private var readResult: String?
    private let reader = HealthMetricsReader()

    private var statusNote: String {
        if let e = health.lastError { return e }
        if !health.available { return "Apple Health is not available on this device" }
        return health.workoutWriteAuthorized ? "Workouts can be saved" : "Shown as connected only after iOS confirms the permission"
    }
    private func setRead(_ k: HealthSample.Kind, _ on: Bool) {
        switch k { case .weight: store.settings.healthReads.weight = on; case .restingHR: store.settings.healthReads.restingHR = on; case .hrv: store.settings.healthReads.hrv = on; case .sleep: store.settings.healthReads.sleep = on }
        if on { reader.requestRead([k]) { _ in readNow() } }
    }
    private func readNow() {
        guard !reading else { return }
        reading = true
        store.refreshHealthReads(from: reader) { changed in
            reading = false
            readResult = changed.isEmpty ? "No newer values from Apple Health." : "Updated: " + changed.map(\.title).joined(separator: ", ")
        }
    }
    private func runImport() {
        guard !importing else { return }
        importing = true
        health.importWorkouts(into: store) { r in importing = false; importResult = r.message; store.settings.lastHealthImport = Date() }
    }
    private func valueText(_ k: HealthSample.Kind) -> String {
        let p = store.profile
        let v: String?
        switch k {
        case .weight: v = p.weightKg.map { String(format: "%.1f kg", $0) }
        case .restingHR: v = p.restHR.map { "\($0) bpm" }
        case .hrv: v = p.hrvMs.map { String(format: "%.0f ms", $0) }
        case .sleep: v = p.sleepHours.map { String(format: "%.1f h", $0) }
        }
        guard let v else { return "No data" }
        let prov = p.provenance(k.field)
        let when = prov.recordedAt.map { " · " + $0.formatted(date: .abbreviated, time: .omitted) } ?? ""
        return "\(v) · \(prov.source.title)\(when)"
    }
    private var useBinding: Binding<Bool> {
        Binding(get: { store.settings.appleHealthWanted }, set: { v in store.settings.appleHealthWanted = v; if v, !health.workoutWriteAuthorized { health.request { _ in } } })
    }
    private var exportBinding: Binding<Bool> {
        Binding(get: { store.settings.appleHealthExportRides }, set: { v in store.settings.appleHealthExportRides = v; if v { store.settings.appleHealthWanted = true; if !health.workoutWriteAuthorized { health.request { _ in } } } })
    }
    private var importBinding: Binding<Bool> {
        Binding(get: { store.settings.appleHealthImportWorkouts }, set: { v in
            store.settings.appleHealthImportWorkouts = v
            if v { store.settings.appleHealthWanted = true; if !health.workoutWriteAuthorized { health.request { _ in runImport() } } else { runImport() } }
        })
    }

    var body: some View {
        CyProfilePage(title: "Apple Health") {
            CyDevStatus(state: shown, note: statusNote, id: "deviceStatus-health")
            CyToggleRow(title: "Use Apple Health", note: "iOS asks for the permission once", isOn: useBinding, id: "healthUse")
            if store.settings.appleHealthWanted, !health.workoutWriteAuthorized, health.available {
                CyDevActionRow(title: "Grant permission", note: "Asks iOS again", id: "healthGrant") { health.request { _ in } }
            }
            CyToggleRow(title: "Export rides to Health", note: "Once, when a ride is saved", isOn: exportBinding, id: "healthExportRides")
            CyToggleRow(title: "Import workouts", note: "Cycling and strength", isOn: importBinding, id: "healthImport")
            importRows
            CyGroupLabel(text: "OPTIONAL READS")
            ForEach(HealthSample.Kind.allCases, id: \.self) { k in
                CyToggleRow(title: k == .hrv ? "Heart-rate variability" : k.title, note: store.settings.healthReads.enabled(k) ? valueText(k) : "Off",
                            isOn: Binding(get: { store.settings.healthReads.enabled(k) }, set: { v in setRead(k, v) }), id: "healthRead-\(k.rawValue)")
            }
            if store.settings.healthReads.anyEnabled {
                CyDevActionRow(title: reading ? "Reading…" : "Read now", note: readResult, id: "healthReadNow") { if health.available { readNow() } }
            }
            CyDevNote(text: "The newer of your own entry and Apple Health is used; the source and date are always shown. A ride is written to Health at most once, never when the Apple Watch already saved it. Cyclift draws no readiness score or medical conclusion from these values.")
        }
        .accessibilityIdentifier("devicePage-health")
        .onAppear { health.refresh() }
    }

    @ViewBuilder private var importRows: some View {
        CyDevActionRow(title: importing ? "Importing…" : "Import now", note: importResult ?? "The last 90 days; duplicates are skipped", id: "healthImportNow") {
            if health.available { runImport() }
        }
        if let d = store.settings.lastHealthImport {
            CyDevFact(title: "Last import", value: d.formatted(date: .abbreviated, time: .shortened), id: "healthLastImport")
        }
    }
}

// MARK: - Apple Watch

/// The existing Apple Watch page's state and actions (WatchConnectionDetail) in the Profile style.
struct CyDeviceWatchPage: View {
    let shown: ProfileConnection?
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var watch: WatchLink

    private var statusNote: String {
        if !watch.paired { return "No Apple Watch is paired with this iPhone" }
        if !watch.appInstalled { return "Cyclift is not installed on the Watch" }
        return watch.hrIsFresh ? "Heart rate arriving now" : watch.reachable ? "Watch app reachable" : "Watch app not open"
    }
    private var useBinding: Binding<Bool> {
        Binding(get: { store.settings.enabledConnections.contains("watch") },
                set: { if $0 { store.settings.enabledConnections.insert("watch") } else { store.settings.enabledConnections.remove("watch") } })
    }
    private func yesNo(_ b: Bool) -> String { b ? "Yes" : "No" }

    var body: some View {
        CyProfilePage(title: "Apple Watch", purpose: "Heart rate from your Apple Watch while you train.") {
            CyDevStatus(state: shown, note: statusNote, id: "deviceStatus-watch")
            CyToggleRow(title: "Use the Apple Watch", note: "Off = the watch is never shown as missing", isOn: useBinding, id: "watchUse")
            CyGroupLabel(text: "RIGHT NOW")
            CyDevFact(title: "Watch paired with this iPhone", value: yesNo(watch.paired), id: "watchPaired")
            CyDevFact(title: "Cyclift installed on the Watch", value: yesNo(watch.appInstalled), id: "watchInstalled")
            CyDevFact(title: "Watch app reachable", value: yesNo(watch.reachable), id: "watchReachable")
            CyDevFact(title: "Workout on the Watch", value: watch.workoutState, id: "watchWorkout")
            CyDevFact(title: "Live heart rate", note: "A reading older than 6 s is dropped, never held", value: watch.hrIsFresh ? "\(watch.hrBpm ?? 0) bpm" : "—", id: "watchHR")
            CyDevFact(title: "Last delivery", value: SourceFormat.ago(watch.lastDeliveryAt), id: "watchLastDelivery")
            CyDevFact(title: "Watch app", value: watch.watchBuild ?? "Not reported yet", id: "watchBuild")
            if let b = watch.watchBattery { CyDevFact(title: "Watch battery", value: "\(b) %", id: "watchBattery") }
            if watch.version == .watchOlder {
                Text(WatchVersion.updateInstruction).font(CyDyn.f(13.5)).foregroundStyle(CyTheme.ink).fixedSize(horizontal: false, vertical: true).padding(.top, 8)
            }
            CyGroupLabel(text: "ACTIONS")
            CyDevActionRow(title: "Test connection to the Watch", note: watch.lastResult, id: "watchTest") { watch.ping() }
            CyDevActionRow(title: "Start watch workout (heart rate)", note: watch.watchStartResult ?? "Starting a ride on the iPhone starts it by itself", id: "watchStart") { watch.startWatchWorkout(reason: "manual") }
            CyDevNote(text: "Install Cyclift on the Watch (Watch app › Available Apps). Not reachable: open the watch app once and make sure the iPhone's Bluetooth is on. No heart rate: the Watch must sit snug and the workout must be running.")
        }
        .accessibilityIdentifier("devicePage-watch")
    }
}

// MARK: - This iPhone (sheet P06) and Permissions (sheet P08 F2)

/// One page for both rows: what this iPhone allows Cyclift to use, each in one word from the real state. Permissions
/// are changed in iPhone Settings; this page shows them. In Cyclift Lab nothing is read and nothing is asked.
struct CyDevicePhonePage: View {
    /// true = the Permissions page of Data, Help & About (adds Apple Health); false = "This iPhone" in Devices.
    let permissions: Bool
    var body: some View {
        CyProfilePage(title: permissions ? "Permissions" : "This iPhone", purpose: "What this iPhone allows Cyclift to use.") {
            if CycliftLab.isLab {
                CyDevFact(title: "Bluetooth", note: "Sensors and the BikeComputer", value: ProfilePhoneWords.labNote, id: "phoneBluetooth")
                CyDevFact(title: "Location", note: "Speed, distance and route while riding", value: ProfilePhoneWords.labNote, id: "phoneLocation")
                if permissions { CyDevFact(title: "Apple Health", note: "Rides, weight, resting heart rate", value: ProfilePhoneWords.labNote, id: "phoneHealth") }
                CyDevFact(title: "Notifications", note: "Ride recording notice", value: ProfilePhoneWords.labNote, id: "phoneNotifications")
                CyDevNote(text: "Cyclift Lab is a demonstration. It asks for no permission and uses none.")
            } else {
                CyDevicePhoneLive(permissions: permissions)
            }
        }
        .accessibilityIdentifier(permissions ? "profilePermissionsPage" : "devicePage-phone")
    }
}

private struct CyDevicePhoneLive: View {
    let permissions: Bool
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var device: DeviceLink
    @EnvironmentObject private var hub: SensorHub
    @EnvironmentObject private var location: LocationService
    @EnvironmentObject private var health: HealthAccess
    @State private var notifications: ProfilePhoneWords.Notifications = .unknown

    private var bluetooth: String {
        ProfilePhoneWords.bluetooth(off: device.state == .off || hub.ble.radio == .off,
                                    unauthorized: device.state == .unauthorized || hub.ble.radio == .unauthorized, unsupported: hub.ble.radio == .unsupported)
    }
    var body: some View {
        CyDevFact(title: "Bluetooth", note: "Sensors and the BikeComputer", value: bluetooth, id: "phoneBluetooth")
        CyDevFact(title: "Location", note: "Speed, distance and route while riding", value: ProfilePhoneWords.location(authorized: location.authorized, denied: location.denied), id: "phoneLocation")
        if permissions {
            CyDevFact(title: "Apple Health", note: "Rides, weight, resting heart rate",
                      value: ProfilePhoneWords.health(available: health.available, writeAuthorized: health.workoutWriteAuthorized, wanted: store.settings.appleHealthWanted), id: "phoneHealth")
        }
        CyDevFact(title: "Notifications", note: store.settings.backgroundNotice ? "Ride recording notice" : "Ride recording notice is switched off in Cyclift",
                  value: ProfilePhoneWords.notifications(notifications), id: "phoneNotifications")
        CyDevButton(title: "Open iPhone Settings", primary: false, id: "phoneOpenSettings") { DeviceLink.openSettings() }.padding(.top, 18)
        CyDevNote(text: "Permissions are changed in iPhone Settings. Cyclift shows their current state here. iOS asks for location and notifications the first time a ride needs them.")
            .onAppear(perform: readNotifications)
    }
    /// Reads the current setting only; it never asks for the permission.
    private func readNotifications() {
        UNUserNotificationCenter.current().getNotificationSettings { s in
            let n: ProfilePhoneWords.Notifications
            switch s.authorizationStatus {
            case .authorized, .provisional, .ephemeral: n = .allowed
            case .denied: n = .notAllowed
            case .notDetermined: n = .notAsked
            @unknown default: n = .unknown
            }
            DispatchQueue.main.async { notifications = n }
        }
    }
}
