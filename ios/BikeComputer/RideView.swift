import SwiftUI
import MapKit
import CoreLocation

/// Ride tab (Cyclift 1.0): one live screen, five selectable layouts (Ride Coach · Large gauges · Classic · Rings ·
/// Analytics — see ios/RIDE_LAYOUTS.md), each with the same CoachPanel, header and controls, on one screen without
/// scrolling. Live metrics come ONLY from the SensorHub (contract in Sources/SensorHub.swift); the recorder (BikeComputer
/// or this phone) is fixed when the ride starts. Switching layout writes AppSettings.rideLayout and nothing else.
/// The map, sensors and the tile picker live behind "Details".
struct RideTabView: View {
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var device: DeviceLink
    @EnvironmentObject private var location: LocationService
    @EnvironmentObject private var recorder: RideRecorder
    @EnvironmentObject private var hub: SensorHub
    @EnvironmentObject private var monitor: PipelineMonitor
    @EnvironmentObject private var link13: Link13Center
    @StateObject private var coach = RideCoach()
    @State private var confirmEnd = false
    @State private var showDetails = false
    @State private var showSettings = false
    @State private var tick = Date()
    @State private var lastTickedSecond = -1
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var boardRecording: Bool { recorder.owner == .board && recorder.isActive }
    private var phoneRecording: Bool { recorder.owner == .phone && recorder.isActive }
    /// Board link status (not a metric): demo flag and battery for the header.
    private var boardLive: BCLink.Live? { device.state == .ready && device.liveIsFresh ? device.live : nil }
    private var layout: RideLayout { store.settings.rideLayout }

    var body: some View {
        NavigationStack {
            GeometryReader { g in
                // first layout pass (and the tab hidden behind Home) can report 0 × 0: draw nothing until there is a real size
                if g.size.width >= 200, g.size.height >= 300 { screen(g.size) } else { Color.clear }
            }
                .background(D7.bg.ignoresSafeArea())
                .toolbar(.hidden, for: .navigationBar)
                .onReceive(timer) { now in tick = now; coachTick(); mirrorTick() }
                .onChange(of: recorder.state) { _, s in if s == .running, recorder.elapsedS <= 1 { coach.reset(); lastTickedSecond = -1 }; if s == .idle { lastTickedSecond = -1 } }
                .onAppear { configureCoach() }
                .onChange(of: store.profile) { _, _ in configureCoach() }
                .onChange(of: store.settings) { _, _ in configureCoach() }
                .onChange(of: powerTrusted) { _, _ in configureCoach() }
                .sheet(isPresented: $showDetails) { RideDetailsSheet() }
                .sheet(isPresented: $showSettings) { RideSettingsSheet() }
                .sheet(item: $recorder.pendingResult) { r in RideResultSheet(ride: r) }
                .alert(recorder.owner == .board ? "End the ride on the BikeComputer?" : "End this ride?", isPresented: $confirmEnd) {
                    Button("End ride", role: .destructive) { if recorder.owner == .board { device.control(.stopConfirm) } else { recorder.end() } }
                    Button("Keep riding", role: .cancel) {}
                } message: { Text(recorder.owner == .board ? "The board shows its results screen; you save or discard there or here." : "You can save or discard it on the next screen.") }
        }
    }

    // MARK: coach feed (one tick per ride second, only while running; only usable hub readings, nothing is invented)
    private var live: RideLive { RideLive.from(hub: hub, profile: store.profile, settings: store.settings, coach: coach) }
    private var powerTrusted: Bool { hub.reading(.power)?.quality == .good }
    private func configureCoach() { coach.configure(profile: store.profile, settings: store.settings, workout: store.today, powerTrusted: powerTrusted) }
    private func coachTick() {
        guard recorder.isActive, recorder.state == .running, recorder.elapsedS != lastTickedSecond else { return }
        lastTickedSecond = recorder.elapsedS
        let l = live
        coach.tick(elapsedS: recorder.elapsedS, cadence: l.cadence.value, hr: l.hr.value, power: l.power.value, speedKmh: l.speedKmh)
    }
    /// Link 1.3 coach mirroring: the board gets the plan this screen's coach runs and, every second, what it shows.
    /// Does nothing unless the connected board's HELLO_ACK enabled the coach feature (Link13Center).
    private func mirrorTick() {
        guard link13.session.coach else { return }
        let hr = CoachMirrorAdapter.hrSource(hub: hub, boardLive: boardLive)
        let live = CoachLiveInput(elapsedS: recorder.elapsedS, session: CoachMirrorAdapter.session(recorder), cue: coach.cue.type, cueAction: coach.cue.action,
                                  cueActive: coach.cueActive && recorder.state == .running, cueShort: coach.cue.short, hrSource: hr.src, hrLive: hr.live)
        link13.coachTick(plan: CoachMirrorAdapter.input(workout: store.today, profile: store.profile, settings: store.settings, powerTrusted: powerTrusted), live: live,
                         boardOwnsRide: recorder.owner == .board && (recorder.isActive || recorder.state == .ended), phoneOwnsRide: recorder.owner == .phone && (recorder.isActive || recorder.state == .ended))
    }
    private func panelModel(_ l: RideLive) -> CoachPanelModel {
        var i = CoachPanelModel.Inputs()
        i.coachEnabled = store.settings.coachEnabled
        i.recording = recorder.isActive; i.paused = recorder.state == .paused
        i.startHint = startHint
        i.cue = coach.cue; i.cueActive = coach.cueActive && recorder.state == .running
        i.phase = coach.phase; i.intervals = coach.intervals != nil
        i.power = l.power.value; i.powerUnverified = l.power.unverified
        i.hr = l.hr.value; i.cadence = l.cadence.value
        i.speedKmh = l.speedKmh; i.speedSource = l.speed.reading?.sourceLabel; i.imperial = l.imperial
        i.ftp = l.ftp; i.ftpProvisional = l.ftpProvisional
        i.targetZone = coach.targetZone; i.hrBand = l.hrBandBpm; i.powerBand = l.powerBandW
        i.cadLo = l.cadLo; i.cadHi = l.cadHi; i.workoutTitle = coach.workoutTitle
        return CoachPanelModel.make(i)
    }

    // MARK: screen = header · layout content (fills what is left) · coach panel · controls — no scrolling
    private func screen(_ size: CGSize) -> some View {
        let l = live
        let panelH: CGFloat = size.height < 560 ? 92 : 104
        return VStack(spacing: 8) {
            header(l)
            GeometryReader { g in
                if g.size.width >= 200, g.size.height >= 120 {
                    RideLayoutContent(layout: layout, live: l, size: g.size, coach: coach, recorder: recorder, tiles: store.tiles, profile: store.profile, boardBattery: boardLive?.batteryPct)
                } else { Color.clear }
            }
            CoachPanel(model: panelModel(l), height: panelH)
            controls
        }
        .padding(.horizontal, 14).padding(.top, 6).padding(.bottom, 8)
        .frame(width: size.width, height: size.height, alignment: .top)
    }

    private func header(_ l: RideLive) -> some View {
        VStack(spacing: 4) {
            HStack(spacing: 6) {
                Circle().fill(linkColor).frame(width: 8, height: 8)
                Text(linkText).font(D7.mono).foregroundStyle(D7.mut).lineLimit(1).minimumScaleFactor(0.7)
                Spacer()
                Text("T \(recorder.isActive || recorder.state == .ended ? recorder.elapsedS.asDuration : "0:00")").font(.system(size: 12, weight: .bold, design: .monospaced)).foregroundStyle(recorder.state == .running ? D7.fg : D7.mut)
            }
            HStack(spacing: 8) {
                layoutMenu
                if recorder.isActive { Text(coach.phaseLabel).font(.system(size: 10, weight: .bold, design: .monospaced)).foregroundStyle(coach.phase == .MAIN ? D7.green : D7.violet) }
                Spacer()
                Button { showSettings = true } label: { Image(systemName: "gearshape").font(.system(size: 15, weight: .semibold)).foregroundStyle(D7.cyan) }
                    .buttonStyle(.minTap)
                    .accessibilityLabel(RideLabels.settings).accessibilityIdentifier("rideSettings")
                Button { showDetails = true } label: { Text(RideLabels.details).font(.system(size: 10, weight: .bold, design: .monospaced)).foregroundStyle(D7.cyan) }
                    .buttonStyle(.minTap)
                    .accessibilityLabel("Ride details: map, sensors, tiles").accessibilityIdentifier("rideDetails")
            }
            HStack(spacing: 4) {
                Text(workoutName).font(.system(size: 9, design: .monospaced)).foregroundStyle(D7.mut).lineLimit(1).minimumScaleFactor(0.7)
                Spacer(minLength: 2)
                if boardLive?.demo == true { DashTag(text: RideLabels.demo, color: D7.amber) }
                if l.power.unverified { DashTag(text: RideLabels.powerUnverified, color: D7.amber) }
                if l.power.usable || l.ftpProvisional { DashTag(text: l.ftpProvisional ? RideLabels.ftpProvisional : "FTP \(l.ftp) W", color: D7.mut) }
            }
            PipelineBanner(monitor: monitor, dark: true)
            ZStack(alignment: .leading) { D7.line.frame(height: 3); (coach.cueActive && recorder.state == .running ? D7.cyan : D7.line).frame(height: 3) }.clipShape(Capsule())
        }
    }
    /// Quick switch, usable during a ride with one tap (next layout) or a long press (choose from the list).
    /// Only writes AppSettings.rideLayout (RideLayoutSwitch) — recording and sensors carry on.
    private var layoutMenu: some View {
        Menu {
            ForEach(RideLayout.allCases) { l in
                Button { RideLayoutSwitch.select(l, store: store) } label: {
                    if l == layout { Label(l.title, systemImage: "checkmark") } else { Label(l.title, systemImage: l.icon) }
                }
                .accessibilityIdentifier("rideLayoutOption.\(l.rawValue)")
            }
        } label: {
            HStack(spacing: 4) {
                Text(layout.title.uppercased()).font(.system(size: 13, design: .monospaced)).tracking(2).foregroundStyle(D7.cyan).lineLimit(1).minimumScaleFactor(0.7)
                Image(systemName: "chevron.down").font(.system(size: 10, weight: .bold)).foregroundStyle(D7.cyan)
            }
        } primaryAction: {
            RideLayoutSwitch.select(layout.next, store: store)
        }
        .menuStyle(.button).buttonStyle(.minTap)        // 44 pt hit area (the layout report measured 116 × 15 pt)
        .accessibilityLabel("\(RideLabels.layoutMenu): \(layout.title)")
        .accessibilityHint("Tap for the next layout, touch and hold to choose one")
        .accessibilityIdentifier("rideLayoutMenu")
    }
    private var workoutName: String {
        let z = coach.targetZone, cad = "\(store.profile.cadenceLow)–\(store.profile.cadenceHigh) RPM"
        let what = coach.intervals != nil ? "Z\(z) INTERVALS" : "Z\(z) TARGET"
        return "\(coach.workoutTitle.uppercased()) · \(what) · \(cad)"
    }
    /// The board counts as LIVE only while one of its metrics is actually shown — a connected link alone is not.
    private var boardHasData: Bool { [MetricKind.power, .cadence, .heartRate].contains { hub.reading($0)?.source.method == .bikeComputer } }
    private var linkColor: Color {
        if boardLive?.demo == true { return D7.amber }
        if boardLive != nil { return boardHasData ? D7.green : D7.amber }
        if device.state == .ready { return D7.amber }
        if device.state == .scanning || device.state == .connecting { return D7.amber }
        if phoneRecording { return D7.green }
        if hub.reading(.heartRate) != nil || hub.reading(.speed) != nil { return D7.cyan }
        // red only for a BikeComputer the rider paired that is now missing; the device is optional otherwise
        return device.remembered ? D7.red : D7.grey
    }
    private var linkText: String {
        var s: String
        if boardLive?.demo == true { s = "SIMULATED" } else if boardLive != nil { s = boardHasData ? "LIVE" : "BOARD CONNECTED · NO SENSOR DATA" } else if device.state == .ready { s = "BOARD CONNECTED · NO LIVE DATA" } else if device.state == .scanning || device.state == .connecting { s = "CONNECTING" } else { s = phoneRecording ? "PHONE" : (device.remembered ? "BIKECOMPUTER NOT FOUND" : "PHONE ONLY") }
        if boardRecording { s += recorder.boardLinkLost ? " · BOARD RECORDS (LINK LOST)" : " · BOARD RECORDS" } else if phoneRecording { s += " · PHONE RECORDS" }
        if let b = boardLive?.batteryPct { s += " · BAT ≈\(b)%" }
        return s
    }
    private var startHint: String {
        switch recorder.startMode(locationAuthorized: location.authorized) {
        case .board: return "BikeComputer records; the phone adds GPS and coaching"
        case .phone: return device.state == .ready ? "this phone records (BikeComputer values shown)" : "this phone records with the sensors that are live"
        case .blockedByBoardRide: return "the BikeComputer has a ride running — it is the recorder"
        case .blockedNoGPSPermission: return "allow location to record on the phone"
        }
    }

    // MARK: controls
    @ViewBuilder private var controls: some View {
        let mode = recorder.startMode(locationAuthorized: location.authorized)
        VStack(spacing: 6) {
            if recorder.state == .running, coach.phase != .COOLDOWN, store.settings.coachEnabled {
                Button { coach.requestCooldown(elapsedS: recorder.elapsedS) } label: { Text("Start cool-down (no more 'push' cues)").font(.system(size: 11, design: .monospaced)).foregroundStyle(D7.violet) }
            }
            HStack(spacing: 8) {
                if !recorder.isActive {
                    switch mode {
                    case .blockedByBoardRide: Text("BikeComputer ride running — end it there or from Details").font(D7.mono).foregroundStyle(D7.mut).frame(maxWidth: .infinity)
                    case .board: BigButton(text: "START ON BIKECOMPUTER", color: D7.green) { device.control(.start) }
                    case .blockedNoGPSPermission: BigButton(text: "ALLOW LOCATION", color: D7.amber) { location.requestPermission() }
                    case .phone: BigButton(text: "START · PHONE", color: D7.green) { _ = recorder.start() }
                    }
                } else if recorder.owner == .board {
                    if recorder.state == .running { BigButton(text: "PAUSE", color: D7.amber) { device.control(.pause) } } else { BigButton(text: "RESUME", color: D7.green) { device.control(.resume) } }
                    BigButton(text: "LAP", color: D7.violet) { recorder.lap() }
                    BigButton(text: "END", color: recorder.boardLinkLost ? D7.grey : D7.red) { if !recorder.boardLinkLost { device.control(.stopRequest); confirmEnd = true } }
                } else {
                    if recorder.state == .running { BigButton(text: "PAUSE", color: D7.amber) { recorder.pause() } } else { BigButton(text: "RESUME", color: D7.green) { recorder.resume() } }
                    BigButton(text: "LAP", color: D7.violet) { recorder.lap() }
                    BigButton(text: "END", color: D7.red) { confirmEnd = true }
                }
            }
        }
    }
}

/// Map, sensors and the classic tiles — everything that used to scroll under the ride screen.
struct RideDetailsSheet: View {
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var device: DeviceLink
    @EnvironmentObject private var watch: WatchLink
    @EnvironmentObject private var location: LocationService
    @EnvironmentObject private var recorder: RideRecorder
    @EnvironmentObject private var hub: SensorHub
    @Environment(\.dismiss) private var dismiss
    @State private var showTiles = false
    private var live: BCLink.Live? { device.state == .ready && device.liveIsFresh ? device.live : nil }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    if recorder.boardLinkLost { Text("Phone link lost: the BikeComputer keeps recording; values return when the link does.").font(.footnote).foregroundStyle(BC.stale).padding(8).frame(maxWidth: .infinity).background(BC.stale.opacity(0.12), in: RoundedRectangle(cornerRadius: 8)) }
                    if let n = recorder.note { Text(n).font(.footnote).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading) }
                    mapCard
                    tiles
                    sensorsCard
                }.padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Ride details").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarLeading) { Button("Tiles") { showTiles = true } }; ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .sheet(isPresented: $showTiles) { TilePicker() }
        }
    }
    /// Same hub readings and the same tile builder as the Classic layout.
    private var metrics: RideLive {
        RideLive(power: hub.reading(.power), hr: hub.reading(.heartRate), cadence: hub.reading(.cadence), speed: hub.reading(.speed),
                 profile: store.profile, imperial: store.settings.units == .imperial, targetZone: 2)
    }
    private var tiles: some View {
        let l = metrics
        return LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            ForEach(Array(store.tiles.prefix(6).enumerated()), id: \.offset) { _, key in RideTiles.tile(key, live: l, recorder: recorder, profile: store.profile, boardBattery: live?.batteryPct) }
        }
    }
    private var coords: [CLLocationCoordinate2D] { recorder.samples.compactMap { s in if let la = s.lat, let lo = s.lon { return CLLocationCoordinate2D(latitude: la, longitude: lo) }; return nil } }
    private var mapCard: some View {
        Card {
            HStack { Eyebrow(t: "Route"); Spacer(); Text(location.sharing ? location.status : "GPS off").font(.caption2).foregroundStyle(.secondary) }
            if coords.count >= 2 {
                Map { MapPolyline(coordinates: coords).stroke(BC.accent, lineWidth: 4); if let last = coords.last { Marker("", coordinate: last).tint(BC.live) } }
                    .frame(height: 240).clipShape(RoundedRectangle(cornerRadius: 12))
                Text("\(coords.count) GPS points" + (elevationGain.map { String(format: " · +%.0f m", $0) } ?? "")).font(.caption2).foregroundStyle(.secondary)
            } else if let l = location.last, location.sharing {
                Map(initialPosition: .region(MKCoordinateRegion(center: l.coordinate, latitudinalMeters: 800, longitudinalMeters: 800))) { UserAnnotation() }
                    .frame(height: 160).clipShape(RoundedRectangle(cornerRadius: 12))
                Text("Waiting for the ride to start; the track is drawn from the phone's GPS.").font(.caption2).foregroundStyle(.secondary)
            } else {
                Text("no data yet").font(.footnote).foregroundStyle(BC.stale)
                if !location.authorized { Button("Allow location") { location.requestPermission() }.font(.footnote.bold()) }
            }
        }
    }
    private var elevationGain: Double? {
        let alts = recorder.samples.compactMap { $0.alt }
        guard alts.count > 10 else { return nil }
        var g = 0.0; for i in 1..<alts.count where alts[i] - alts[i - 1] > 0.5 { g += alts[i] - alts[i - 1] }
        return g
    }
    private var sensorsCard: some View {
        Card {
            HStack { Eyebrow(t: "Connections"); Spacer(); NavigationLink { ConnectionsView() } label: { Text("Manage ›").font(.caption.bold()) } }
            SensorRow(name: "BikeComputer", detail: boardDetail, live: device.state == .ready)
            if device.state == .ready { SensorRow(name: "Power meter via BikeComputer", detail: meterDetail, live: live?.powerW != nil) }
            ForEach(MetricKind.allCases, id: \.self) { k in
                let m = RideMetric(kind: k, reading: hub.reading(k), missing: hub.missingReason[k])
                SensorRow(name: k.title, detail: m.usable ? "\(m.sourceOrMissing) · live" : m.missingText, live: m.usable)
            }
            SensorRow(name: "Phone GPS", detail: location.sharing ? location.status : "off until a ride starts", live: location.sharing && location.last != nil)
            SensorRow(name: "Apple Watch", detail: watch.hrIsFresh ? "heart rate live" : watch.appInstalled ? "app installed · workout \(watch.workoutState)" : "no watch app", live: watch.hrIsFresh)
        }
    }
    private var boardDetail: String {
        guard device.state == .ready else { return device.state.rawValue }
        var d = device.liveIsFresh ? "connected · live data" : "connected — no live data"; if let r = device.rssi { d += " · \(r) dBm" }; if let b = live?.batteryPct { d += " · battery ≈\(b)%" }
        return d
    }
    private var meterDetail: String {
        guard let l = live else { return "via the BikeComputer" }
        let t: String; switch l.meterLink { case 4: t = l.powerW != nil ? "connected · \(l.powerW!) W live" : "connected — waiting for data"; case 7: t = "connected — data stale"; case 1: t = "not paired"; case 2: t = "searching"; case 3: t = "connecting"; case 5: t = "reconnecting"; default: t = "off" }
        return t + (l.meterGaps > 0 ? " · \(l.meterGaps) gaps" : "")
    }
}

struct StatusChip: View {
    let title: String; let value: String; let color: Color
    var body: some View {
        VStack(alignment: .leading, spacing: 3) { Eyebrow(t: title); HStack(spacing: 5) { StatusDot(color: color); Text(value).font(.caption.weight(.bold)).lineLimit(2).minimumScaleFactor(0.7) } }
            .frame(maxWidth: .infinity, alignment: .leading).padding(8).background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
    }
}

struct SensorRow: View {
    let name: String; let detail: String; let live: Bool
    var body: some View { HStack { StatusDot(color: live ? BC.live : .secondary); Text(name).font(.subheadline.weight(.semibold)); Spacer(); Text(detail).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.trailing) }.padding(.vertical, 2) }
}

/// Choose and order the six tiles. Stored in the Store so it survives updates.
struct TilePicker: View {
    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss
    static let all: [(String, String)] = [("power", "Power"), ("cadence", "Cadence"), ("hr", "Heart rate"), ("speed", "Speed"), ("time", "Time"), ("dist", "Distance"), ("lap", "Lap"), ("zone", "Zone"), ("np", "Normalized power"), ("battery", "Board battery")]
    var body: some View {
        NavigationStack {
            List {
                Section("Shown (first is largest, max 6)") {
                    ForEach(store.tiles, id: \.self) { k in Text(Self.all.first { $0.0 == k }?.1 ?? k) }
                        .onMove { store.tiles.move(fromOffsets: $0, toOffset: $1) }
                        .onDelete { store.tiles.remove(atOffsets: $0) }
                }
                Section("Available") {
                    ForEach(Self.all.filter { !store.tiles.contains($0.0) }, id: \.0) { k, t in Button(t) { if store.tiles.count < 6 { store.tiles.append(k) } }.disabled(store.tiles.count >= 6) }
                }
                Section { Button("Reset to default") { store.tiles = Store.defaultTiles } }
            }
            .environment(\.editMode, .constant(.active))
            .navigationTitle("Ride tiles").toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}

/// Save / discard after a ride. Board rides carry the board's totals; phone rides the phone's. Never both.
struct RideResultSheet: View {
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var recorder: RideRecorder
    @Environment(\.dismiss) private var dismiss
    let ride: RideRecord
    @State private var confirmDiscard = false
    /// Adaptive coach: after Save the sheet turns into the post-ride check-in.
    @State private var checkIn = false
    var body: some View {
        if checkIn { CheckInFlow(target: .ride(ride.id)) { recorder.finish(); dismiss() } }
        else { result }
    }
    private var result: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    HStack { Text(ride.title).font(.system(size: 26, weight: .bold, design: .rounded)); Spacer(); Pill(text: "recorded by \(ride.recordedBy)", color: BC.accent) }
                    if ride.demo { Text("Demo ride — cannot be saved").font(.caption.bold()).foregroundStyle(.black).padding(6).frame(maxWidth: .infinity).background(BC.sim, in: RoundedRectangle(cornerRadius: 8)) }
                    RideSummaryTiles(ride: ride, units: store.settings.units)
                    Card { Eyebrow(t: "Coach (rules)"); Text(Coach.rideSummary(ride, profile: store.profile)) }
                    Text("Sources: \(ride.sources.joined(separator: " · "))").font(.footnote).foregroundStyle(.secondary)
                    if ride.recorder == .board { Text("The BikeComputer keeps its own copy of this ride in its history; this is the phone's mirror with the GPS track.").font(.footnote).foregroundStyle(.secondary) }
                    Button { if store.addRide(ride) { checkIn = true } else { recorder.finish(); dismiss() } } label: { Text(ride.demo ? "Close (demo, not saved)" : "Save ride").frame(maxWidth: .infinity) }.buttonStyle(.borderedProminent).tint(BC.live).controlSize(.large)
                    Button("Discard", role: .destructive) { confirmDiscard = true }.frame(maxWidth: .infinity)
                }.padding()
            }
            .background(Color(.systemGroupedBackground))
            .interactiveDismissDisabled()
            .alert("Discard this ride?", isPresented: $confirmDiscard) { Button("Discard", role: .destructive) { recorder.discard(); dismiss() }; Button("Keep", role: .cancel) {} }
        }
    }
}

struct RideSummaryTiles: View {
    let ride: RideRecord; let units: AppSettings.Units
    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
            MetricTile(title: "Time", value: ride.durationS.asDuration, unit: "", source: ride.recordedBy)
            MetricTile(title: "Distance", value: String(format: "%.2f", units == .imperial ? Double(ride.distanceM) / 1609.34 : Double(ride.distanceM) / 1000), unit: units == .imperial ? "mi" : "km", source: ride.recorder == .board ? "board" : "Phone GPS")
            MetricTile(title: "Avg power", value: ride.avgPower.map { "\($0)" }, unit: "W", source: "power source", missing: MetricKind.power.missingText)
            MetricTile(title: "Normalized", value: ride.normalizedPower.map { "\($0)" }, unit: "W", source: "power source", missing: MetricKind.power.missingText)
            MetricTile(title: "Avg HR", value: ride.avgHR.map { "\($0)" }, unit: "bpm", source: ride.sources.contains("Apple Watch") ? "Apple Watch" : "HR source")
            MetricTile(title: "Energy", value: ride.kj.map { "\($0)" }, unit: "kJ", source: "from power", missing: MetricKind.power.missingText)
        }
    }
}
