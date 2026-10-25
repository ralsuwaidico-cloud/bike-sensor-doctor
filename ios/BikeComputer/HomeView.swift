import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var device: DeviceLink
    @EnvironmentObject private var watch: WatchLink
    @EnvironmentObject private var location: LocationService
    @EnvironmentObject private var recorder: RideRecorder
    @EnvironmentObject private var sync: ProfileSync
    @Binding var tab: Int
    @State private var showWorkout = false
    @State private var showWhy = false
    @State private var showAlternatives = false
    @State private var showStrengthLog = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    if store.profile.trainingMode == .cycling { coach } else { HybridCoachCard(tab: $tab, showWorkout: $showWorkout, showAlternatives: $showAlternatives, showStrengthLog: $showStrengthLog) }
                    if store.ftpSuggestion != nil { Card(accent: true) { FTPSuggestionCard() } }
                    if sync.state == .needsConfirmation {
                        NavigationLink { SyncStatusView() } label: {
                            Card(accent: true) { HStack { Image(systemName: "exclamationmark.circle.fill").foregroundStyle(BC.warn); VStack(alignment: .leading) { Text("Phone and BikeComputer profiles differ").bold(); Text("Choose which one the board should use.").font(.footnote).foregroundStyle(.secondary) }; Spacer(); Image(systemName: "chevron.right").foregroundStyle(.secondary) } }
                        }.buttonStyle(.plain)
                    }
                    connections
                    nextDays
                    HStack { Text("FTP \(store.profile.ftpW) W").font(.footnote).foregroundStyle(.secondary); Pill(text: store.profile.ftpLabel, color: store.profile.ftpHow == .assumed ? BC.stale : BC.live); Spacer(); Text(budgetText).font(.footnote).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.8) }
                    if store.guest { Card { HStack { Text("Guest: rides stay on this phone.").font(.footnote).foregroundStyle(.secondary); Spacer(); Button("Create account") { tab = 4 }.font(.caption.bold()) } } }
                }.padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(store.profile.name.isEmpty ? "Hi" : "Hi \(store.profile.name)")
            .sheet(isPresented: $showWorkout) { if let t = store.today { WorkoutDetail(workout: t) } }
            .sheet(isPresented: $showAlternatives) { alternativesSheet }
            .sheet(isPresented: $showStrengthLog) { QuickStrengthLogSheet(date: Date(), presetFocus: store.today?.strengthFocus) }
        }
    }

    // MARK: coach — one line, a compact table, "Why this workout?", actions
    private var coach: some View {
        let t = store.today
        return Card(accent: true) {
            HStack { Eyebrow(t: "Coach (rules) · \(Date().shortDay)"); Spacer(); if let t { if t.done { Pill(text: "done", color: BC.live) } else if t.skipped { Pill(text: "skipped") } else { ZonePill(z: t.kind.zone) } } }
            Text(Coach.todayLine(t)).font(.title3.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
            if let t, t.kind != .rest {
                VStack(spacing: 0) {
                    tableRow("Workout", t.displayTitle)
                    tableRow("Duration", t.minutes > 0 ? Fmt.duration(minutes: t.minutes) : "—")
                    tableRow("Target", t.kind.zone > 0 ? "Zone \(t.kind.zone) · \(zoneWatts(t.kind.zone))" : t.kind.subtitle)
                    tableRow("Benefit", t.benefit)
                    tableRow("Structure", t.structureText)
                    tableRow("Status", t.done ? "done" : t.skipped ? "skipped" : recorder.isActive ? "in progress" : "planned", last: true)
                }
                .background(Color(.systemGroupedBackground).opacity(0.6), in: RoundedRectangle(cornerRadius: 10))
            }
            DisclosureGroup(isExpanded: $showWhy) {
                Text(Coach.why(t, store: store)).font(.footnote).foregroundStyle(.secondary).padding(.top, 4).fixedSize(horizontal: false, vertical: true)
            } label: { Text("Why this workout?").font(.subheadline.weight(.semibold)).foregroundStyle(BC.accent) }
            if let t, t.kind != .rest {
                HStack(spacing: 8) {
                    if t.kind.isRide, !recorder.isActive {
                        Button { tab = 2 } label: { Label("Start", systemImage: "play.fill").frame(maxWidth: .infinity) }.buttonStyle(.borderedProminent).tint(BC.live)
                    } else if t.kind.isRide {
                        Button { tab = 2 } label: { Label("Open ride", systemImage: "bicycle").frame(maxWidth: .infinity) }.buttonStyle(.borderedProminent).tint(BC.live)
                    }
                    Button { showWorkout = true } label: { Text("Adjust").frame(maxWidth: .infinity) }.buttonStyle(.bordered)
                    Button { showAlternatives = true } label: { Text("Alternative").frame(maxWidth: .infinity) }.buttonStyle(.bordered)
                }
                Text("Start opens the Ride screen; recording begins only when you tap Start ride there.").font(.caption2).foregroundStyle(.secondary)
            }
        }
    }
    private func tableRow(_ k: String, _ v: String, last: Bool = false) -> some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline) { Text(k).font(.footnote).foregroundStyle(.secondary).frame(width: 84, alignment: .leading); Text(v).font(.footnote.weight(.medium)).frame(maxWidth: .infinity, alignment: .leading) }.padding(.horizontal, 10).padding(.vertical, 6)
            if !last { Divider().padding(.leading, 10) }
        }
    }
    private var budgetText: String { store.profile.trainingMode == .cycling ? "\(store.profile.hoursPerWeek) h/week · \(store.profile.level.title.lowercased())" : "\(store.profile.hoursPerWeek) h cycling · \(store.profile.liftingHoursPerWeek) h lifting" }
    private func zoneWatts(_ z: Int) -> String { let p = store.profile.powerZones[max(0, min(6, z - 1))]; return "\(p.lo)–\(p.hi.map(String.init) ?? "∞") W" }

    private var alternativesSheet: some View {
        NavigationStack {
            List {
                if let t = store.today {
                    Section("Instead of \(t.kind.title)") {
                        ForEach(Array(Coach.alternatives(for: t).enumerated()), id: \.offset) { _, a in
                            Button { var w = t; w.kind = a.kind; w.minutes = a.minutes; store.update(w); showAlternatives = false } label: {
                                HStack { VStack(alignment: .leading) { Text(a.kind.title).bold().foregroundStyle(.primary); Text("\(Fmt.duration(minutes: a.minutes)) · \(a.kind.subtitle) · \(a.benefit)").font(.footnote).foregroundStyle(.secondary) }; Spacer(); ZonePill(z: a.kind.zone) }
                            }
                        }
                    }
                    Section { Button("Skip today") { var w = t; w.skipped = true; store.update(w); showAlternatives = false } }
                }
            }
            .navigationTitle("Alternatives").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { showAlternatives = false } } }
        }
    }

    // MARK: connections (clearly visible; details in the dashboard)
    private var liveNow: BCLink.Live? { device.state == .ready && device.liveIsFresh ? device.live : nil }
    private var connections: some View {
        NavigationLink { ConnectionsView() } label: {
            Card {
                HStack { Eyebrow(t: "Connections"); Spacer(); Text("Manage ›").font(.caption.bold()).foregroundStyle(BC.accent) }
                VStack(spacing: 6) {
                    connLine(boardStatus, "BikeComputer", boardText)
                    connLine(ConnectionRules.meter(boardLive: liveNow != nil, meterLink: liveNow?.meterLink, enabled: store.settings.enabledConnections.contains("meter") || device.remembered), "Power meter", meterText)
                    connLine(watchStatus, "Apple Watch", watchText)
                    connLine(ConnectionRules.gps(authorized: location.authorized, sharing: location.sharing, hasFix: location.last != nil, requiredForRides: store.settings.phoneOnlyMode || !device.remembered), "Phone GPS", location.authorized ? (location.sharing ? location.status : "ready") : "permission needed")
                }
            }
        }.buttonStyle(.plain)
    }
    private func connLine(_ s: ConnStatus, _ name: String, _ detail: String) -> some View {
        HStack(spacing: 8) { StatusBadge(status: s).frame(width: 20); Text(name).font(.subheadline.weight(.semibold)).foregroundStyle(.primary); Spacer(minLength: 6); Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.tail) }
    }
    private var boardStatus: ConnStatus { ConnectionRules.board(linkState: device.state, liveFresh: device.liveIsFresh, remembered: device.remembered, autoConnect: store.settings.autoConnectBoard, phoneOnlyMode: store.settings.phoneOnlyMode) }
    private var boardText: String {
        if !store.settings.autoConnectBoard { return "link off" }
        switch device.state { case .ready: return "connected" + (device.info.map { " · \($0.fw)" } ?? "") + (store.settings.phoneOnlyMode ? " · phone records" : ""); case .idle: return device.remembered ? "not in range" : "not paired"; default: return device.state.rawValue }
    }
    private var meterText: String { guard let l = liveNow else { return device.remembered ? "via board" : "pairs on the board" }; return l.meterLink == 4 ? "connected" : l.meterLink == 1 ? "not paired" : "searching" }
    private var watchStatus: ConnStatus { ConnectionRules.watch(paired: watch.paired, appInstalled: watch.appInstalled, hrFresh: watch.hrIsFresh, workoutRunning: watch.workoutState == "running", enabled: store.settings.enabledConnections.contains("watch")) }
    private var watchText: String { !store.settings.enabledConnections.contains("watch") ? "off" : watch.hrIsFresh ? "HR live" : watch.appInstalled ? "ready" : watch.paired ? "app missing" : "no watch" }

    private var nextDays: some View {
        Card {
            HStack { Eyebrow(t: "Next days"); Spacer(); Button("Plan ›") { tab = 1 }.font(.caption.bold()) }
            HStack(alignment: .top, spacing: 8) {
                ForEach(upcoming, id: \.id) { w in
                    VStack(alignment: .leading, spacing: 2) { Text(w.date.shortDay).font(.caption.weight(.heavy)).foregroundStyle(.secondary); Text(w.kind.title).font(.caption).lineLimit(2).minimumScaleFactor(0.8); HStack(spacing: 4) { if w.minutes > 0 { Text(Fmt.duration(minutes: w.minutes)).font(.caption2).foregroundStyle(.secondary) }; ZonePill(z: w.kind.zone) } }.frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }
    private var upcoming: [Workout] { store.plan.filter { $0.date > Date() }.sorted { $0.date < $1.date }.prefix(3).map { $0 } }
}
