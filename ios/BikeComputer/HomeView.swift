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
    @Environment(\.dynamicTypeSize) private var dts

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    DiagCrashBanner()
                    if store.profile.trainingMode == .cycling { coach } else { HybridCoachCard(tab: $tab, showWorkout: $showWorkout, showAlternatives: $showAlternatives, showStrengthLog: $showStrengthLog) }
                    AdjustmentHomeLine()
                    if store.ftpSuggestion != nil { Card(accent: true) { FTPSuggestionCard() } }
                    if sync.state == .needsConfirmation {
                        NavigationLink { SyncStatusView() } label: {
                            Card(accent: true) { HStack { Image(systemName: "exclamationmark.circle.fill").foregroundStyle(BC.warn); VStack(alignment: .leading) { Text("Phone and BikeComputer profiles differ").bold(); Text("Choose which one the board should use.").font(.footnote).foregroundStyle(.secondary) }; Spacer(); Image(systemName: "chevron.right").foregroundStyle(.secondary) } }
                        }.buttonStyle(.plain)
                    }
                    connections
                    nextDays
                    FlowRow(spacing: DS.s) { Text("FTP \(store.profile.ftpW) W").font(.footnote).foregroundStyle(.secondary); FTPConfidencePill(profile: store.profile); Text(budgetText).font(.footnote).foregroundStyle(.secondary) }
                        .frame(maxWidth: .infinity, alignment: .leading)
                }.padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(store.profile.name.isEmpty ? "Hi" : "Hi \(store.profile.name)")
            .sheet(isPresented: $showWorkout) { if let t = store.today { if t.kind == .strength { StrengthWorkoutScreen(workoutId: t.id) } else { WorkoutDetail(workout: t) } } }
            .sheet(isPresented: $showAlternatives) { alternativesSheet }
            .sheet(isPresented: $showStrengthLog) { let open = store.openStrength(on: Date()); QuickStrengthLogSheet(date: Date(), presetFocus: open?.strengthFocus ?? store.today?.strengthFocus, workoutId: open?.id) }
        }
    }

    // MARK: coach — one line, a compact table, "Why this workout?", actions
    private var coach: some View {
        let t = store.today
        return Card(accent: true) {
            HStack { Eyebrow(t: "Coach (rules) · \(Date().shortDay)"); Spacer(); if let t { let st = store.status(t); if st.isCompleted || st == .skipped { WorkoutStatusPill(status: st) } else { ZonePill(z: t.kind.zone) } } }
            Text(Coach.todayLine(t)).font(.title3.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
            if let t, t.kind != .rest {
                VStack(spacing: 0) {
                    tableRow("Workout", t.displayTitle)
                    tableRow("Duration", t.minutes > 0 ? Fmt.duration(minutes: t.minutes) : "—")
                    tableRow("Target", t.kind.zone > 0 ? "Zone \(t.kind.zone) · \(zoneWatts(t.kind.zone))\(store.profile.ftpConfidence.isConfident ? "" : " (conservative)")" : t.kind.subtitle)
                    tableRow("Benefit", t.benefit)
                    tableRow("Structure", t.structureText)
                    tableRow("Status", recorder.isActive && t.kind.isRide ? "in progress" : store.status(t).title.lowercased(), last: true)
                }
                .background(Color(.systemGroupedBackground).opacity(0.6), in: RoundedRectangle(cornerRadius: 10))
            }
            DisclosureGroup(isExpanded: $showWhy) {
                Text(Coach.why(t, store: store)).font(.footnote).foregroundStyle(.secondary).padding(.top, 4).fixedSize(horizontal: false, vertical: true)
            } label: { Text("Why this workout?").font(.subheadline.weight(.semibold)).foregroundStyle(BC.accent) }
            if let t, t.kind != .rest {
                ActionRow(actions: coachActions(t))
            }
        }
    }
    private func coachActions(_ t: Workout) -> [ActionSpec] {
        var a: [ActionSpec] = []
        if t.kind.isRide { a.append(ActionSpec(label: recorder.isActive ? "Ride" : "Start", a11y: recorder.isActive ? "Open ride" : "Start: opens the Ride screen, recording starts there", icon: recorder.isActive ? "bicycle" : "play.fill", prominent: true, tint: BC.live, identifier: "coachStart") { tab = 2 }) }
        a.append(ActionSpec(label: "Adjust", a11y: "Adjust today's session", identifier: "coachAdjust") { showWorkout = true })
        a.append(ActionSpec(label: "Swap", a11y: "Swap today's session", identifier: "coachSwap") { showAlternatives = true })
        return a
    }
    private func tableRow(_ k: String, _ v: String, last: Bool = false) -> some View { KeyValueRow(key: k, value: v, last: last) }
    private var budgetText: String { store.profile.trainingMode == .cycling ? "\(store.profile.hoursPerWeek) h/week · \(store.profile.level.title.lowercased())" : "\(store.profile.hoursPerWeek) h cycling · \(store.profile.liftingHoursPerWeek) h lifting" }
    private func zoneWatts(_ z: Int) -> String { let p = store.profile.prescriptionZones[max(0, min(6, z - 1))]; return "\(p.lo)–\(p.hi.map(String.init) ?? "∞") W" }

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
            .navigationTitle("Swap today's session").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { showAlternatives = false } } }
        }
    }

    // MARK: connections (clearly visible; details in the dashboard)
    private var liveNow: BCLink.Live? { device.state == .ready && device.liveIsFresh ? device.live : nil }
    private var connections: some View {
        NavigationLink { ConnectionsView() } label: {
            Card {
                HStack { Eyebrow(t: "Connections"); Spacer(); Text("Manage ›").font(.footnote.bold()).foregroundStyle(BC.accent) }
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
            HStack { Eyebrow(t: "Next days"); Spacer(); Button("Plan ›") { tab = 1 }.font(.footnote.bold()).frame(minHeight: DS.minTap) }
            if dts.isAccessibilitySize {
                VStack(alignment: .leading, spacing: DS.s) { ForEach(upcoming, id: \.id) { w in dayCell(w) } }
            } else {
                HStack(alignment: .top, spacing: DS.s) { ForEach(upcoming, id: \.id) { w in dayCell(w) } }
            }
        }
    }
    private func dayCell(_ w: Workout) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(w.date.shortDay).font(.caption.weight(.heavy)).foregroundStyle(.secondary)
            Text(w.kind == .strength ? w.displayTitle(routine: store.routine(for: w)) : w.kind.title).font(.caption).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 4) { if w.minutes > 0 { Text(Fmt.duration(minutes: w.minutes)).font(.caption2).foregroundStyle(.secondary) }; ZonePill(z: w.kind.zone) }
        }.frame(maxWidth: .infinity, alignment: .leading).accessibilityElement(children: .combine)
    }
    private var upcoming: [Workout] { store.plan.filter { $0.date > Date() }.sorted { $0.date < $1.date }.prefix(3).map { $0 } }
}
