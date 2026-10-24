import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var device: DeviceLink
    @EnvironmentObject private var watch: WatchLink
    @EnvironmentObject private var recorder: RideRecorder
    @Binding var tab: Int
    @State private var showWorkout = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    if let t = store.today {
                        Button { showWorkout = true } label: {
                            Card(accent: true) {
                                HStack { Eyebrow(t: "Today · \(t.date.shortDay)"); Spacer(); ZonePill(z: t.kind.zone) }
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(t.kind.title).font(.system(size: 28, weight: .bold, design: .rounded)).foregroundStyle(.primary)
                                        Text(t.kind == .rest ? "nothing planned; an easy spin is fine" : t.kind.isRide ? "\(t.minutes) min · targets ready on \(device.state == .ready ? "your BikeComputer" : "this phone")" : "\(t.minutes) min · off the bike").font(.subheadline).foregroundStyle(.secondary)
                                    }
                                    Spacer(); Image(systemName: "chevron.right").foregroundStyle(BC.accent)
                                }
                                if t.done { Pill(text: "done", color: BC.live) } else if t.skipped { Pill(text: "skipped") }
                            }
                        }.buttonStyle(.plain)
                    }
                    let mode = recorder.startMode(locationAuthorized: true)
                    Button { tab = 2; if !recorder.isActive { if mode == .board { device.control(.start) } else if mode == .phone { _ = recorder.start() } } } label: {
                        Label(recorder.isActive ? "Ride in progress · open Ride" : mode == .board ? "Start ride on the BikeComputer" : mode == .blockedByBoardRide ? "Ride running on the BikeComputer" : "Start ride · phone only", systemImage: "play.fill").frame(maxWidth: .infinity)
                    }.buttonStyle(.borderedProminent).tint(BC.live).controlSize(.large)

                    Card {
                        Eyebrow(t: "Coach (rules)")
                        Text(Coach.homeNote(store: store, device: device)).font(.subheadline)
                    }
                    Card {
                        HStack { Eyebrow(t: "Next days"); Spacer(); Button("Plan ›") { tab = 1 }.font(.caption.bold()) }
                        HStack(alignment: .top) {
                            ForEach(nextDays, id: \.id) { w in
                                VStack(alignment: .leading, spacing: 2) { Text(w.date.shortDay).font(.caption.weight(.heavy)).foregroundStyle(.secondary); Text(w.kind.title).font(.caption).lineLimit(1); HStack(spacing: 4) { if w.minutes > 0 { Text("\(w.minutes) min").font(.caption2).foregroundStyle(.secondary) }; ZonePill(z: w.kind.zone) } }.frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                    Card {
                        Eyebrow(t: "Recovery")
                        Text("No sleep or HRV source connected. WHOOP and Apple Health arrive with the integrations phase; recovery is shown only from real measurements.").font(.footnote).foregroundStyle(.secondary)
                    }
                    Card {
                        HStack { Eyebrow(t: "Devices"); Spacer(); Button("Manage ›") { tab = 4 }.font(.caption.bold()) }
                        HStack(spacing: 10) {
                            HStack(spacing: 5) { StatusDot(color: device.state == .ready ? BC.live : .secondary); Text(device.state == .ready ? (store.settings.phoneOnlyMode ? "BikeComputer · phone-only mode" : "BikeComputer") : "no board · phone records").font(.caption) }
                            HStack(spacing: 5) { StatusDot(color: (device.live?.powerW != nil && device.liveIsFresh) ? BC.live : .secondary); Text("meter").font(.caption) }
                            HStack(spacing: 5) { StatusDot(color: watch.hrIsFresh ? BC.live : watch.appInstalled ? BC.stale : .secondary); Text("watch").font(.caption) }
                        }
                    }
                    if store.guest { Card { HStack { Text("Guest: rides stay on this phone.").font(.footnote).foregroundStyle(.secondary); Spacer(); Button("Create account") { tab = 4 }.font(.caption.bold()) } } }
                    HStack { Text("FTP \(store.profile.ftpW) W").font(.footnote).foregroundStyle(.secondary); Pill(text: store.profile.ftpHow.label, color: store.profile.ftpHow == .assumed ? BC.stale : BC.live); Spacer(); Text("\(store.profile.hoursPerWeek) h/week · \(store.profile.level.title.lowercased())").font(.footnote).foregroundStyle(.secondary) }
                }.padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(store.profile.name.isEmpty ? "Hi" : "Hi \(store.profile.name)")
            .sheet(isPresented: $showWorkout) { if let t = store.today { WorkoutDetail(workout: t) } }
        }
    }
    private var nextDays: [Workout] { store.plan.filter { $0.date > Date() }.sorted { $0.date < $1.date }.prefix(3).map { $0 } }
}
