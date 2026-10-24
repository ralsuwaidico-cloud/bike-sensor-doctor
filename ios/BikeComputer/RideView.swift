import SwiftUI
import MapKit
import CoreLocation

/// Ride tab. Three statuses at the top (recording · devices · sync), six metric tiles with their source, map of the
/// phone's GPS trace, and the controls. The recorder (BikeComputer or this phone) is fixed when the ride starts.
struct RideTabView: View {
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var device: DeviceLink
    @EnvironmentObject private var watch: WatchLink
    @EnvironmentObject private var location: LocationService
    @EnvironmentObject private var recorder: RideRecorder
    @State private var confirmEnd = false
    @State private var showTiles = false
    @State private var tick = Date()
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var live: BCLink.Live? { device.state == .ready && device.liveIsFresh ? device.live : nil }
    private var boardRecording: Bool { recorder.owner == .board && recorder.isActive }
    private var phoneRecording: Bool { recorder.owner == .phone && recorder.isActive }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    statuses
                    if let l = live, l.demo {
                        Text("DEMO MODE on the BikeComputer — simulated values, never saved").font(.caption.bold()).foregroundStyle(.black)
                            .padding(6).frame(maxWidth: .infinity).background(BC.sim, in: RoundedRectangle(cornerRadius: 8))
                    }
                    if recorder.boardLinkLost {
                        Text("Phone link lost: the BikeComputer keeps recording; this screen shows \"--\" until the link returns.").font(.footnote).foregroundStyle(BC.stale)
                            .padding(8).frame(maxWidth: .infinity).background(BC.stale.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                    }
                    tiles
                    if let z = currentZone { ZoneBar(current: z) }
                    controls
                    if let n = recorder.note { Text(n).font(.footnote).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading) }
                    mapCard
                    sensorsCard
                }.padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Ride")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Tiles") { showTiles = true } } }
            .onReceive(timer) { tick = $0 }
            .sheet(isPresented: $showTiles) { TilePicker() }
            .sheet(item: $recorder.pendingResult) { r in RideResultSheet(ride: r) }
            .alert(recorder.owner == .board ? "End the ride on the BikeComputer?" : "End this ride?", isPresented: $confirmEnd) {
                Button("End ride", role: .destructive) { if recorder.owner == .board { device.control(.stopConfirm) } else { recorder.end() } }
                Button("Keep riding", role: .cancel) {}
            } message: { Text(recorder.owner == .board ? "The board shows its results screen; you save or discard there or here." : "You can save or discard it on the next screen.") }
        }
    }

    // MARK: statuses
    private var recordingText: String {
        if boardRecording { return recorder.boardLinkLost ? "board (phone lost)" : "on the board" }
        if phoneRecording { return recorder.state == .paused ? "paused · phone" : "on this phone" }
        if live != nil { return store.settings.phoneOnlyMode ? "phone only" : "board ready" }
        return "not recording"
    }
    private var recordingColor: Color {
        guard recorder.isActive else { return .secondary }
        return (recorder.boardLinkLost || recorder.state == .paused) ? BC.stale : BC.live
    }
    private var devicesText: String {
        if let l = live { return l.meterLink == 4 ? "board · meter" : "board · no meter" }
        return device.state == .ready ? "board · no data" : "no board"
    }
    private var devicesColor: Color {
        guard let l = live else { return .secondary }
        return l.meterLink == 4 ? BC.live : BC.stale
    }
    private var statuses: some View {
        HStack(spacing: 8) {
            StatusChip(title: "Recording", value: recordingText, color: recordingColor)
            StatusChip(title: "Devices", value: devicesText, color: devicesColor)
            StatusChip(title: "Heart rate", value: hrValue != nil ? hrSourceLabel : "no HR source", color: hrValue != nil ? BC.live : .secondary)
        }
    }

    // MARK: metrics (only real measurements; nil → "--" + "no data")
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
    private var currentZone: Int? { powerValue.map { store.profile.zone(forWatts: $0) } }
    private var imperial: Bool { store.settings.units == .imperial }

    private var distanceText: String? {
        guard recorder.isActive || recorder.state == .ended else { return nil }
        let km = Double(recorder.distanceM) / 1000
        return String(format: "%.2f", imperial ? km / 1.60934 : km)
    }
    private var tiles: some View {
        let defs = store.tiles.prefix(6)
        return LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            ForEach(Array(defs.enumerated()), id: \.offset) { i, key in tile(key, big: i == 0) }
        }
    }
    private func tile(_ key: String, big: Bool) -> some View {
        switch key {
        case "power": return MetricTile(title: "Power", value: powerValue.map { "\($0)" }, unit: "W", source: "XDS via board", big: big)
        case "cadence": return MetricTile(title: "Cadence", value: cadenceValue.map { "\($0)" }, unit: "rpm", source: "XDS via board", big: big)
        case "hr": return MetricTile(title: "Heart rate", value: hrValue.map { "\($0)" }, unit: "bpm", source: hrSourceLabel, big: big)
        case "speed": return MetricTile(title: "Speed", value: speedKmh.map { String(format: "%.1f", imperial ? $0 / 1.609 : $0) }, unit: imperial ? "mph" : "km/h", source: "Phone GPS", big: big)
        case "time": return MetricTile(title: "Time", value: recorder.isActive || recorder.state == .ended ? recorder.elapsedS.asDuration : nil, unit: "", source: recorder.owner.label, big: big)
        case "dist": return MetricTile(title: "Distance", value: distanceText, unit: imperial ? "mi" : "km", source: recorder.owner == .board ? "board (GPS)" : "Phone GPS", big: big)
        case "lap": return MetricTile(title: "Lap \(recorder.lapCount)", value: recorder.isActive ? (recorder.elapsedS - recorder.lapStartS).asDuration : nil, unit: "", source: recorder.owner.label, big: big)
        case "zone": return MetricTile(title: "Zone", value: currentZone.map { "Z\($0)" }, unit: "", source: "from FTP \(store.profile.ftpW) W (\(store.profile.ftpLabel))", big: big)
        case "np": return MetricTile(title: "Normalized", value: RideRecorder.normalized(recorder.samples.compactMap { $0.w }).map { "\($0)" }, unit: "W", source: "phone mirror of the board", big: big)
        case "battery": return MetricTile(title: "Board battery", value: live?.batteryPct.map { "≈\($0)" }, unit: "%", source: "estimate from voltage", big: big)
        default: return MetricTile(title: key, value: nil, unit: "", source: "", big: big)
        }
    }

    // MARK: controls
    @ViewBuilder private var controls: some View {
        let mode = recorder.startMode(locationAuthorized: location.authorized)
        HStack(spacing: 10) {
            if !recorder.isActive {
                switch mode {
                case .blockedByBoardRide:
                    Text("The BikeComputer has a ride running; it is the recorder. Ending it there shows the results here.").font(.footnote).foregroundStyle(.secondary)
                case .board:
                    Button { device.control(.start) } label: { Label("Start ride on the BikeComputer", systemImage: "play.fill").frame(maxWidth: .infinity) }.buttonStyle(.borderedProminent).tint(BC.live).controlSize(.large)
                default:
                    Button { _ = recorder.start() } label: { Label("Start ride · phone only", systemImage: "play.fill").frame(maxWidth: .infinity) }.buttonStyle(.borderedProminent).tint(BC.live).controlSize(.large)
                }
            } else if recorder.owner == .board {
                if recorder.state == .running { Button { device.control(.pause) } label: { Label("Pause", systemImage: "pause.fill").frame(maxWidth: .infinity) }.buttonStyle(.bordered) }
                else { Button { device.control(.resume) } label: { Label("Resume", systemImage: "play.fill").frame(maxWidth: .infinity) }.buttonStyle(.borderedProminent).tint(BC.live) }
                Button { recorder.lap() } label: { Label("Lap", systemImage: "flag").frame(maxWidth: .infinity) }.buttonStyle(.bordered)
                Button { device.control(.stopRequest); confirmEnd = true } label: { Label("End", systemImage: "stop.fill").frame(maxWidth: .infinity) }.buttonStyle(.borderedProminent).tint(BC.warn).disabled(recorder.boardLinkLost)
            } else {
                if recorder.state == .running { Button { recorder.pause() } label: { Label("Pause", systemImage: "pause.fill").frame(maxWidth: .infinity) }.buttonStyle(.bordered) }
                else { Button { recorder.resume() } label: { Label("Resume", systemImage: "play.fill").frame(maxWidth: .infinity) }.buttonStyle(.borderedProminent).tint(BC.live) }
                Button { recorder.lap() } label: { Label("Lap", systemImage: "flag").frame(maxWidth: .infinity) }.buttonStyle(.bordered)
                Button { confirmEnd = true } label: { Label("End", systemImage: "stop.fill").frame(maxWidth: .infinity) }.buttonStyle(.borderedProminent).tint(BC.warn)
            }
        }
        if !recorder.isActive {
            Text(recorderHint(mode)).font(.footnote).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func recorderHint(_ mode: RideRecorder.StartMode) -> String {
        switch mode {
        case .board: return "Recorder: BikeComputer (connected, live). The phone mirrors it and adds GPS for the map."
        case .phone: return device.state == .ready ? "Recorder: this phone (phone-only mode is on or the board has no live data). Board values are shown, not merged." : "Recorder: this phone. GPS speed/distance and watch heart rate; no power without a BikeComputer."
        default: return ""
        }
    }

    // MARK: map
    private var coords: [CLLocationCoordinate2D] { recorder.samples.compactMap { s in if let la = s.lat, let lo = s.lon { return CLLocationCoordinate2D(latitude: la, longitude: lo) }; return nil } }
    private var mapCard: some View {
        Card {
            HStack { Eyebrow(t: "Route"); Spacer(); Text(location.sharing ? location.status : "GPS off").font(.caption2).foregroundStyle(.secondary) }
            if coords.count >= 2 {
                Map { MapPolyline(coordinates: coords).stroke(BC.accent, lineWidth: 4); if let last = coords.last { Marker("", coordinate: last).tint(BC.live) } }
                    .frame(height: 220).clipShape(RoundedRectangle(cornerRadius: 12))
                let gain = elevationGain
                Text("\(coords.count) GPS points" + (gain.map { String(format: " · +%.0f m", $0) } ?? "")).font(.caption2).foregroundStyle(.secondary)
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

    // MARK: sensors
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
        var d = "connected"
        if let r = device.rssi { d += " · \(r) dBm" }
        if let b = live?.batteryPct { d += " · battery ≈\(b)%" }
        return d
    }
    private var meterDetail: String {
        guard let l = live else { return "via the BikeComputer" }
        return meterText(l.meterLink) + (l.meterGaps > 0 ? " · \(l.meterGaps) gaps" : "")
    }
    private func meterText(_ s: Int) -> String { switch s { case 4: return "connected"; case 1: return "not paired"; case 2: return "searching"; case 3: return "connecting"; case 5: return "reconnecting"; default: return "off" } }
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
