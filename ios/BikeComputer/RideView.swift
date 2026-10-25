import SwiftUI
import MapKit
import CoreLocation

/// Ride tab (0.5.0): the Power-Focus dashboard ported from the Nokia app — three target gauges, coach box, live
/// graph, stats and controls on one screen, no scrolling. The recorder (BikeComputer or this phone) is fixed when
/// the ride starts; the map, sensors and classic tiles live behind "Details".
struct RideTabView: View {
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var device: DeviceLink
    @EnvironmentObject private var watch: WatchLink
    @EnvironmentObject private var location: LocationService
    @EnvironmentObject private var recorder: RideRecorder
    @StateObject private var coach = RideCoach()
    @State private var confirmEnd = false
    @State private var showDetails = false
    @State private var tick = Date()
    @State private var lastTickedSecond = -1
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    @Environment(\.dynamicTypeSize) private var dts

    private var live: BCLink.Live? { device.state == .ready && device.liveIsFresh ? device.live : nil }
    private var boardRecording: Bool { recorder.owner == .board && recorder.isActive }
    private var phoneRecording: Bool { recorder.owner == .phone && recorder.isActive }

    var body: some View {
        NavigationStack {
            GeometryReader { g in
                // first layout pass (and the tab hidden behind Home) can report 0 × 0: draw nothing until there is a real size
                if g.size.width >= 200, g.size.height >= 300 { dashboard(g.size) } else { Color.clear }
            }
                .background(D7.bg.ignoresSafeArea())
                .toolbar(.hidden, for: .navigationBar)
                .onReceive(timer) { now in tick = now; coachTick() }
                .onChange(of: recorder.state) { _, s in if s == .running, recorder.elapsedS <= 1 { coach.reset(); lastTickedSecond = -1 }; if s == .idle { lastTickedSecond = -1 } }
                .onAppear { configureCoach() }
                .onChange(of: store.profile) { _, _ in configureCoach() }
                .onChange(of: store.settings) { _, _ in configureCoach() }
                .sheet(isPresented: $showDetails) { RideDetailsSheet() }
                .sheet(item: $recorder.pendingResult) { r in RideResultSheet(ride: r) }
                .alert(recorder.owner == .board ? "End the ride on the BikeComputer?" : "End this ride?", isPresented: $confirmEnd) {
                    Button("End ride", role: .destructive) { if recorder.owner == .board { device.control(.stopConfirm) } else { recorder.end() } }
                    Button("Keep riding", role: .cancel) {}
                } message: { Text(recorder.owner == .board ? "The board shows its results screen; you save or discard there or here." : "You can save or discard it on the next screen.") }
        }
    }

    // MARK: coach feed (one tick per ride second, only while running; nothing is invented)
    private func configureCoach() { coach.configure(profile: store.profile, settings: store.settings, workout: store.today, powerTrusted: false) }
    private func coachTick() {
        guard recorder.isActive, recorder.state == .running, recorder.elapsedS != lastTickedSecond else { return }
        lastTickedSecond = recorder.elapsedS
        coach.tick(elapsedS: recorder.elapsedS, cadence: cadenceValue, hr: hrValue, power: powerValue, speedKmh: speedKmh)
    }

    // MARK: metrics (only real measurements; nil → "—")
    private var powerValue: Int? { live?.powerW }
    private var cadenceValue: Int? { live?.cadenceRpm }
    private var hrValue: Int? {
        let boardHR = live?.hrBpm, watchHR = watch.hrIsFresh ? watch.hrBpm : nil
        if store.settings.hrPref == .watch { return watchHR ?? boardHR }
        return boardHR ?? watchHR
    }
    private var hrSourceLabel: String {
        let boardHR = live?.hrBpm, watchHR = watch.hrIsFresh ? watch.hrBpm : nil
        if store.settings.hrPref == .watch, watchHR != nil { return "Apple Watch" }
        if boardHR != nil { return (live?.hrSource.label ?? "board") + " via board" }
        return watchHR != nil ? "Apple Watch" : "none"
    }
    private var speedKmh: Double? {
        guard location.sharing, let l = location.last, l.speed >= 0, Date().timeIntervalSince(l.timestamp) < 5 else { return nil }
        return l.speed * 3.6
    }
    private var imperial: Bool { store.settings.units == .imperial }
    private var ftp: Int { store.profile.ftpW }
    private var maxHr: Int { store.profile.estimatedMaxHR }
    private var powerZone: Int { PowerZones.zone(powerValue, ftp: ftp) }
    private var hrZone: Int { HrZones.zone(hrValue, maxHr: maxHr) }
    private var powerSignal: GaugeText.SignalState { live == nil ? (device.state == .ready ? .stale : .none) : (live!.meterLink == 4 ? .fresh : .none) }
    private var powerStatus: TargetStatus { Targets.power(powerValue, ftp: ftp, targetZone: coach.targetZone) }
    private var hrStatus: TargetStatus { Targets.hr(hrValue, maxHr: maxHr, targetZone: coach.targetHrZone) }
    private var cadStatus: TargetStatus { Targets.cadence(cadenceValue, low: store.profile.cadenceLow, high: store.profile.cadenceHigh) }

    // MARK: dashboard layout (computed geometry so nothing overlaps on any screen size)
    private func dashboard(_ size: CGSize) -> some View {
        let pad = 14.0
        let w = size.width - 2 * pad
        let fixedH = 58.0 + 92.0 + 44.0 + 60.0 + 4 * 8.0           // header, coach, stats, controls, spacing
        let graphH = max(56.0, min(120.0, size.height - fixedH - 300))
        let geo = PowerFocus.compute(contentW: w, maxBlockH: max(150, size.height - fixedH - graphH), labelH: 0, chipH: 24, chipW: 112)
        return VStack(spacing: 8) {
            header
            gauges(geo, width: w)
            coachBox
            LiveGraphView(samples: coach.samples, seconds: RideCoach.keepSeconds).frame(height: graphH)
            stats
            controls
        }
        .padding(.horizontal, pad).padding(.top, 6).padding(.bottom, 8)
        .frame(width: size.width, height: size.height, alignment: .top)
    }

    private var header: some View {
        VStack(spacing: 4) {
            HStack(spacing: 6) {
                Circle().fill(linkColor).frame(width: 8, height: 8)
                Text(linkText).font(D7.mono).foregroundStyle(D7.mut).lineLimit(1).minimumScaleFactor(0.7)
                Spacer()
                Text("T \(recorder.isActive || recorder.state == .ended ? recorder.elapsedS.asDuration : "0:00")").font(.system(size: 12, weight: .bold, design: .monospaced)).foregroundStyle(recorder.state == .running ? D7.fg : D7.mut)
            }
            HStack(spacing: 6) {
                Text("RIDE COACH").font(.system(size: 13, design: .monospaced)).tracking(2).foregroundStyle(D7.cyan)
                if recorder.isActive { Text(coach.phaseLabel).font(.system(size: 10, weight: .bold, design: .monospaced)).foregroundStyle(coach.phase == .MAIN ? D7.green : D7.violet) }
                Spacer()
                Button { showDetails = true } label: { Text("DETAILS ›").font(.system(size: 10, weight: .bold, design: .monospaced)).foregroundStyle(D7.cyan) }.accessibilityLabel("Ride details: map, sensors, tiles")
            }
            HStack(spacing: 4) {
                Text(workoutName).font(.system(size: 9, design: .monospaced)).foregroundStyle(D7.mut).lineLimit(1)
                Spacer()
                if live?.demo == true { DashTag(text: "DEMO — NOT SAVED", color: D7.amber) }
                DashTag(text: "POWER UNVERIFIED", color: D7.amber)
                if store.profile.ftpHow == .assumed { DashTag(text: "FTP ASSUMED", color: D7.mut) } else { DashTag(text: "FTP \(ftp) W", color: D7.mut) }
            }
            ZStack(alignment: .leading) { D7.line.frame(height: 3); (coach.cueActive ? coachColor : D7.line).frame(height: 3) }.clipShape(Capsule())
        }
    }
    private var workoutName: String {
        if let t = store.today, t.kind.isRide { return "\(t.kind.title.uppercased()) · Z\(coach.targetZone) TARGET · \(store.profile.cadenceLow)–\(store.profile.cadenceHigh) RPM" }
        return "FREE RIDE · Z\(coach.targetZone) TARGET · \(store.profile.cadenceLow)–\(store.profile.cadenceHigh) RPM"
    }
    private var linkColor: Color {
        if live?.demo == true { return D7.amber }
        if live != nil { return D7.green }
        if device.state == .ready { return D7.cyan }
        if device.state == .scanning || device.state == .connecting { return D7.amber }
        return phoneRecording ? D7.green : D7.red
    }
    private var linkText: String {
        var s: String
        if live?.demo == true { s = "SIMULATED" } else if live != nil { s = "LIVE" } else if device.state == .ready { s = "READY" } else if device.state == .scanning || device.state == .connecting { s = "CONNECTING" } else { s = phoneRecording ? "PHONE ONLY" : "NO BOARD" }
        if boardRecording { s += recorder.boardLinkLost ? " · BOARD RECORDS (LINK LOST)" : " · BOARD RECORDS" } else if phoneRecording { s += " · PHONE RECORDS" }
        if let b = live?.batteryPct { s += " · BAT ≈\(b)%" }
        return s
    }

    private func gauges(_ geo: PowerFocusGeometry, width w: Double) -> some View {
        ZStack(alignment: .topLeading) {
            TargetGauge(value: powerValue, maxValue: Targets.powerGaugeMaxW(ftp: ftp), color: powerZone > 0 ? D7.powerZone(powerZone) : D7.grey,
                        targetFraction: Targets.powerTargetFraction(targetZone: coach.targetZone, ftp: ftp), zoneTicks: Targets.powerZoneTicks(ftp: ftp),
                        band: powerBand, sub: powerZone > 0 ? "Z\(powerZone) · \(Targets.powerZonePercent(powerValue, ftp: ftp) ?? 0)%" : nil, unit: "WATTS · XDS", big: true,
                        status: powerStatus, statusText: GaugeText.status(powerStatus, kind: "pow", signal: powerSignal), showTgtLabel: true)
                .frame(width: geo.colPower).offset(x: geo.xPower, y: geo.yPower)
            TargetGauge(value: cadenceValue, maxValue: Targets.cadenceGaugeMax, color: D7.violet, targetFraction: nil, zoneTicks: [],
                        band: (Double(store.profile.cadenceLow) / Double(Targets.cadenceGaugeMax), Double(store.profile.cadenceHigh) / Double(Targets.cadenceGaugeMax)),
                        sub: "\(store.profile.cadenceLow)–\(store.profile.cadenceHigh)", unit: "RPM", big: false,
                        status: cadStatus, statusText: GaugeText.status(cadStatus, kind: "cad", signal: powerSignal), showTgtLabel: false)
                .frame(width: geo.colSmall).offset(x: geo.xLeft, y: geo.yLower)
            TargetGauge(value: hrValue, maxValue: maxHr, color: hrValue != nil && hrZone > 0 ? D7.hrZone(hrZone) : D7.faint,
                        targetFraction: Targets.hrTargetFraction(targetZone: coach.targetHrZone), zoneTicks: Targets.hrZoneTicks, band: hrBand,
                        sub: hrValue != nil && hrZone > 0 ? "Z\(hrZone) · \(Targets.hrZonePercent(hrValue, maxHr: maxHr) ?? 0)%" : nil, unit: hrValue != nil ? "BPM · \(hrSourceLabel.uppercased())" : "BPM", big: false,
                        status: hrStatus, statusText: GaugeText.status(hrStatus, kind: "hr"), showTgtLabel: false)
                .frame(width: geo.colSmall).offset(x: geo.xRight, y: geo.yLower)
        }
        .frame(width: w, height: geo.blockHeight, alignment: .topLeading)
    }
    private var powerBand: (Double, Double)? {
        let r = PowerZones.range(coach.targetZone, ftp: ftp); let m = Double(Targets.powerGaugeMaxW(ftp: ftp))
        return (Double(r.lo) / m, Double(r.hi ?? Int(m)) / m)
    }
    private var hrBand: (Double, Double)? {
        let z = store.profile.hrZones; let i = min(z.count - 1, max(0, coach.targetHrZone - 1)); let m = Double(maxHr)
        return (Double(z[i].lo) / m, Double(z[i].hi ?? maxHr) / m)
    }

    // MARK: coach box
    private var coachColor: Color { switch Targets.coachShape(coach.cue.type) { case .up: return D7.cyan; case .check: return D7.green; case .down: return D7.amber; case .none: return D7.violet } }
    private var coachBox: some View {
        let active = coach.cueActive && recorder.state == .running
        let (head, detail): (String, String) = {
            if !store.settings.coachEnabled { return ("COACH OFF", "Turn it on in Profile › App & device settings") }
            if !recorder.isActive { return ("READY", startHint) }
            if recorder.state == .paused { return ("PAUSED", "Resume to continue coaching") }
            if active { return (coach.cue.short.isEmpty ? coach.cue.headline : coach.cue.short, coach.cue.why.isEmpty ? coach.cue.detail : coach.cue.why) }
            return ("RIDING", missingSensorsNote)
        }()
        return CoachBox(headline: head, detail: detail, color: coachColor, shape: active ? Targets.coachShape(coach.cue.type) : .none, direction: active ? Targets.coachDirection(coach.cue.type) : nil, active: active)
    }
    private var missingSensorsNote: String {
        var missing: [String] = []
        if powerValue == nil { missing.append("power") }
        if hrValue == nil { missing.append("heart rate") }
        if cadenceValue == nil { missing.append("cadence") }
        if missing.isEmpty { return "all sensors live · coaching from HR, power and cadence" }
        if missing.count == 3 { return "no sensors live — coaching on time and pace only" }
        return "no \(missing.joined(separator: " or ")) — coaching from what is live"
    }
    private var startHint: String {
        switch recorder.startMode(locationAuthorized: location.authorized) {
        case .board: return "BikeComputer records; phone adds GPS and coaching"
        case .phone: return device.state == .ready ? "this phone records (board values shown)" : "this phone records: GPS, watch HR, no power"
        case .blockedByBoardRide: return "the board has a ride running — it is the recorder"
        case .blockedNoGPSPermission: return "allow location to record on the phone"
        }
    }

    // MARK: stats + controls
    private var distanceText: String {
        guard recorder.isActive || recorder.state == .ended else { return "—" }
        let km = Double(recorder.distanceM) / 1000
        return String(format: imperial ? "%.2f mi" : "%.2f km", imperial ? km / 1.60934 : km)
    }
    private var stats: some View {
        HStack(spacing: 6) {
            DashStat(value: distanceText, label: recorder.owner == .board ? "DISTANCE · BOARD" : "DISTANCE · GPS")
            DashStat(value: speedKmh.map { String(format: imperial ? "%.1f mph" : "%.1f km/h", imperial ? $0 / 1.609 : $0) } ?? "—", label: "SPEED · GPS")
            DashStat(value: RideRecorder.normalized(recorder.samples.compactMap { $0.w }).map { "\($0) W" } ?? "—", label: "NORMALIZED")
            DashStat(value: recorder.isActive ? "L\(recorder.lapCount) \((recorder.elapsedS - recorder.lapStartS).asDuration)" : "—", label: "LAP")
        }
    }
    @ViewBuilder private var controls: some View {
        let mode = recorder.startMode(locationAuthorized: location.authorized)
        VStack(spacing: 6) {
            if recorder.state == .running, coach.phase != .COOLDOWN, store.settings.coachEnabled {
                Button { coach.requestCooldown(elapsedS: recorder.elapsedS) } label: { Text("Start cool-down (no more 'push' cues)").font(.system(size: 11, design: .monospaced)).foregroundStyle(D7.violet) }
            }
            HStack(spacing: 8) {
                if !recorder.isActive {
                    switch mode {
                    case .blockedByBoardRide: Text("Board ride running — end it on the board or from Details").font(D7.mono).foregroundStyle(D7.mut).frame(maxWidth: .infinity)
                    case .board: BigButton(text: "START ON BIKECOMPUTER", color: D7.green) { device.control(.start) }
                    case .blockedNoGPSPermission: BigButton(text: "ALLOW LOCATION", color: D7.amber) { location.requestPermission() }
                    case .phone: BigButton(text: "START · PHONE ONLY", color: D7.green) { _ = recorder.start() }
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
    private var hrValue: Int? { let b = live?.hrBpm, w = watch.hrIsFresh ? watch.hrBpm : nil; return store.settings.hrPref == .watch ? (w ?? b) : (b ?? w) }
    private var hrSourceLabel: String { let b = live?.hrBpm, w = watch.hrIsFresh ? watch.hrBpm : nil; if store.settings.hrPref == .watch, w != nil { return "Apple Watch" }; if b != nil { return (live?.hrSource.label ?? "board") + " via board" }; return w != nil ? "Apple Watch" : "none" }
    private var speedKmh: Double? { guard location.sharing, let l = location.last, l.speed >= 0, Date().timeIntervalSince(l.timestamp) < 5 else { return nil }; return l.speed * 3.6 }
    private var imperial: Bool { store.settings.units == .imperial }
    private var tiles: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            ForEach(Array(store.tiles.prefix(6).enumerated()), id: \.offset) { _, key in tile(key) }
        }
    }
    private func tile(_ key: String) -> some View {
        let z = live?.powerW.map { store.profile.zone(forWatts: $0) }
        switch key {
        case "power": return MetricTile(title: "Power", value: live?.powerW.map { "\($0)" }, unit: "W", source: "XDS via board · unverified")
        case "cadence": return MetricTile(title: "Cadence", value: live?.cadenceRpm.map { "\($0)" }, unit: "rpm", source: "XDS via board")
        case "hr": return MetricTile(title: "Heart rate", value: hrValue.map { "\($0)" }, unit: "bpm", source: hrSourceLabel)
        case "speed": return MetricTile(title: "Speed", value: speedKmh.map { String(format: "%.1f", imperial ? $0 / 1.609 : $0) }, unit: imperial ? "mph" : "km/h", source: "Phone GPS")
        case "time": return MetricTile(title: "Time", value: recorder.isActive || recorder.state == .ended ? recorder.elapsedS.asDuration : nil, unit: "", source: recorder.owner.label)
        case "dist": return MetricTile(title: "Distance", value: recorder.isActive || recorder.state == .ended ? String(format: "%.2f", imperial ? Double(recorder.distanceM) / 1609.34 : Double(recorder.distanceM) / 1000) : nil, unit: imperial ? "mi" : "km", source: recorder.owner == .board ? "board (GPS)" : "Phone GPS")
        case "lap": return MetricTile(title: "Lap \(recorder.lapCount)", value: recorder.isActive ? (recorder.elapsedS - recorder.lapStartS).asDuration : nil, unit: "", source: recorder.owner.label)
        case "zone": return MetricTile(title: "Zone", value: z.map { "Z\($0)" }, unit: "", source: "from FTP \(store.profile.ftpW) W (\(store.profile.ftpLabel))")
        case "np": return MetricTile(title: "Normalized", value: RideRecorder.normalized(recorder.samples.compactMap { $0.w }).map { "\($0)" }, unit: "W", source: "phone mirror of the board")
        case "battery": return MetricTile(title: "Board battery", value: live?.batteryPct.map { "≈\($0)" }, unit: "%", source: "estimate from voltage")
        default: return MetricTile(title: key, value: nil, unit: "", source: "")
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
            SensorRow(name: "Power meter (XDS)", detail: meterDetail, live: live?.meterLink == 4)
            SensorRow(name: "Heart rate", detail: hrValue != nil ? "\(hrSourceLabel) · live" : "none", live: hrValue != nil)
            SensorRow(name: "Phone GPS", detail: location.sharing ? location.status : "off until a ride starts", live: location.sharing && location.last != nil)
            SensorRow(name: "Apple Watch", detail: watch.hrIsFresh ? "heart rate live" : watch.appInstalled ? "app installed · workout \(watch.workoutState)" : "no watch app", live: watch.hrIsFresh)
        }
    }
    private var boardDetail: String {
        guard device.state == .ready else { return device.state.rawValue }
        var d = "connected"; if let r = device.rssi { d += " · \(r) dBm" }; if let b = live?.batteryPct { d += " · battery ≈\(b)%" }
        return d
    }
    private var meterDetail: String {
        guard let l = live else { return "via the BikeComputer" }
        let t: String; switch l.meterLink { case 4: t = "connected"; case 1: t = "not paired"; case 2: t = "searching"; case 3: t = "connecting"; case 5: t = "reconnecting"; default: t = "off" }
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
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    HStack { Text(ride.title).font(.system(size: 26, weight: .bold, design: .rounded)); Spacer(); Pill(text: "recorded by \(ride.recordedBy)", color: BC.accent) }
                    if ride.demo { Text("Demo ride — cannot be saved").font(.caption.bold()).foregroundStyle(.black).padding(6).frame(maxWidth: .infinity).background(BC.sim, in: RoundedRectangle(cornerRadius: 8)) }
                    RideSummaryTiles(ride: ride, units: store.settings.units)
                    Card { Eyebrow(t: "Coach (rules)"); Text(Coach.rideSummary(ride, profile: store.profile)) }
                    Text("Sources: \(ride.sources.joined(separator: " · "))").font(.footnote).foregroundStyle(.secondary)
                    if ride.recorder == .board { Text("The BikeComputer keeps its own copy of this ride in its history; this is the phone's mirror with the GPS track.").font(.footnote).foregroundStyle(.secondary) }
                    Button { _ = store.addRide(ride); recorder.finish(); dismiss() } label: { Text(ride.demo ? "Close (demo, not saved)" : "Save ride").frame(maxWidth: .infinity) }.buttonStyle(.borderedProminent).tint(BC.live).controlSize(.large)
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
            MetricTile(title: "Avg power", value: ride.avgPower.map { "\($0)" }, unit: "W", source: "XDS")
            MetricTile(title: "Normalized", value: ride.normalizedPower.map { "\($0)" }, unit: "W", source: "XDS")
            MetricTile(title: "Avg HR", value: ride.avgHR.map { "\($0)" }, unit: "bpm", source: ride.sources.contains("Apple Watch") ? "Apple Watch" : "HR source")
            MetricTile(title: "Energy", value: ride.kj.map { "\($0)" }, unit: "kJ", source: "XDS")
        }
    }
}
