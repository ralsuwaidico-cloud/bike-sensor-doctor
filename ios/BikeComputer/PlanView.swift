import SwiftUI

struct PlanView: View {
    @EnvironmentObject private var store: Store
    @State private var weekOffset = 0
    @State private var selected: Workout?

    private var weekDate: Date { Calendar.current.date(byAdding: .day, value: 7 * weekOffset, to: Date())! }
    private var week: [Workout] { store.workouts(weekOf: weekDate) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    HStack {
                        Button { weekOffset -= 1 } label: { Image(systemName: "chevron.left") }
                        Spacer(); Text(weekOffset == 0 ? "This week" : weekOffset == 1 ? "Next week" : weekDate.dayAndDate).font(.headline); Spacer()
                        Button { weekOffset += 1 } label: { Image(systemName: "chevron.right") }.disabled(weekOffset >= 1)
                    }
                    HStack(spacing: 5) {
                        ForEach(week) { w in
                            Button { selected = w } label: {
                                VStack(spacing: 3) {
                                    Text(w.date.shortDay).font(.caption2.weight(.heavy)).foregroundStyle(.secondary)
                                    Text(w.kind.isRide || w.minutes > 0 ? (w.minutes >= 60 ? String(format: "%g h", Double(w.minutes) / 60) : "\(w.minutes)′") : "—").font(.system(size: 16, weight: .bold, design: .rounded))
                                    Text(w.kind.title).font(.system(size: 8)).lineLimit(1).foregroundStyle(.secondary)
                                    RoundedRectangle(cornerRadius: 2).fill(w.kind.zone > 0 ? BC.zone(w.kind.zone) : Color.secondary.opacity(0.3)).frame(height: 4)
                                }.padding(.vertical, 8).padding(.horizontal, 2).frame(maxWidth: .infinity)
                                .background(w.done ? BC.accent.opacity(0.15) : Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
                                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Calendar.current.isDateInToday(w.date) ? BC.accent : (w.skipped ? Color.secondary : Color.clear), lineWidth: 1.5))
                            }.buttonStyle(.plain)
                        }
                    }
                    let planned = PlanEngine.rideMinutes(week), done = week.filter { $0.done }.reduce(0) { $0 + $1.minutes }
                    Card {
                        HStack {
                            stat("Planned", String(format: "%g h", Double(planned) / 60)); stat("Done", String(format: "%g h", Double(done) / 60))
                            stat("Your limit", "\(store.profile.hoursPerWeek) h", warn: Double(planned) / 60 > Double(store.profile.hoursPerWeek)); stat("Hard days", "\(week.filter { $0.kind.zone >= 3 }.count)")
                        }
                        ProgressView(value: planned > 0 ? Double(done) / Double(planned) : 0).tint(BC.accent)
                        if Double(planned) / 60 > Double(store.profile.hoursPerWeek) { Text("Over your weekly hours. Move or shorten a session, or raise the limit in Profile.").font(.footnote).foregroundStyle(BC.warn) }
                    }
                    HStack(spacing: 4) { Text("Intensity:").font(.caption).foregroundStyle(.secondary); ForEach(1...5, id: \.self) { ZonePill(z: $0) } ; Spacer() }
                    Text("Tap a day for the session: move, edit, skip. Sessions are generated from your goal, hours and level; the coach proposes changes and waits for your approval.").font(.footnote).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                    Button { store.plan = store.plan.filter { $0.date < Calendar.current.startOfDay(for: Date()) }; store.ensurePlan() } label: { Text("Regenerate this week from my profile").frame(maxWidth: .infinity) }.buttonStyle(.bordered)
                }.padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Plan")
            .sheet(item: $selected) { w in WorkoutDetail(workout: w) }
        }
    }
    private func stat(_ t: String, _ v: String, warn: Bool = false) -> some View { VStack(alignment: .leading, spacing: 2) { Eyebrow(t: t); Text(v).font(.system(size: 20, weight: .bold, design: .rounded)).foregroundStyle(warn ? BC.warn : .primary) }.frame(maxWidth: .infinity, alignment: .leading) }
}

struct WorkoutDetail: View {
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var device: DeviceLink
    @EnvironmentObject private var recorder: RideRecorder
    @EnvironmentObject private var watch: WatchLink
    @Environment(\.dismiss) private var dismiss
    @State var workout: Workout
    @State private var mode = 0   // 0 detail, 1 move, 2 edit

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    HStack { Text(workout.kind.title).font(.system(size: 28, weight: .bold, design: .rounded)); Spacer(); ZonePill(z: workout.kind.zone) }
                    Text("\(workout.date.dayAndDate) · \(workout.minutes > 0 ? "\(workout.minutes) min · " : "")\(workout.kind.subtitle)").foregroundStyle(.secondary)
                    if mode == 0 {
                        Card { Eyebrow(t: "Why this session"); Text(workout.why) }
                        let steps = workout.steps(ftp: store.profile.ftpW)
                        if !steps.isEmpty { Card { ForEach(steps, id: \.name) { s in HStack { VStack(alignment: .leading) { Text(s.name).bold(); Text(s.target).font(.caption).foregroundStyle(.secondary) }; Spacer(); Text(s.duration).font(.system(size: 20, weight: .bold, design: .rounded)) }.padding(.vertical, 4); if s != steps.last { Divider() } } } }
                        if workout.kind.zone > 0 {
                            Card { Eyebrow(t: "Target zone"); ZoneBar(current: workout.kind.zone)
                                let z = store.profile.powerZones[workout.kind.zone - 1]
                                Text("Z\(workout.kind.zone) = \(z.lo)–\(z.hi.map(String.init) ?? "∞") W from FTP \(store.profile.ftpW) W (\(store.profile.ftpHow.label)). Heart-rate targets appear when a strap or watch is connected\(watch.appInstalled ? ": Z\(workout.kind.zone) ≈ \(hrRange(workout.kind.zone))" : ".")").font(.footnote).foregroundStyle(.secondary) }
                        }
                        HStack { Button("Move") { mode = 1 }.buttonStyle(.bordered); Button("Edit") { mode = 2 }.buttonStyle(.bordered); Button(workout.skipped ? "Unskip" : "Skip") { workout.skipped.toggle(); store.update(workout) }.buttonStyle(.bordered); Spacer() }
                        if workout.kind.isRide, Calendar.current.isDateInToday(workout.date), recorder.state == .idle {
                            Button { if device.state == .ready { device.control(.start) } else { recorder.start() }; dismiss() } label: { Label("Start this workout", systemImage: "play.fill").frame(maxWidth: .infinity) }.buttonStyle(.borderedProminent).tint(BC.live).controlSize(.large)
                            Text("Targets are sent to the BikeComputer when the ride starts; the board shows them on its coach screen.").font(.footnote).foregroundStyle(.secondary)
                        }
                    } else if mode == 1 {
                        Eyebrow(t: "Move to")
                        ForEach(store.workouts(weekOf: workout.date).filter { $0.id != workout.id }) { o in
                            Button { store.swapDays(workout, o); dismiss() } label: { HStack { Text(o.date.dayAndDate).bold(); Spacer(); Text("currently \(o.kind.title) · the two swap").font(.caption).foregroundStyle(.secondary) }.padding(12).frame(maxWidth: .infinity).background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12)) }.buttonStyle(.plain)
                        }
                        Button("Cancel") { mode = 0 }
                    } else {
                        Card { Eyebrow(t: "Type"); LazyVGrid(columns: [GridItem(.adaptive(minimum: 96))], spacing: 6) { ForEach(WorkoutKind.allCases, id: \.self) { k in Button(k.title) { workout.kind = k; if k.minutes0 { workout.minutes = 0 } else if workout.minutes == 0 { workout.minutes = k.defaultMinutes } }.buttonStyle(.bordered).tint(workout.kind == k ? BC.accent : .secondary).controlSize(.small) } } }
                        if !workout.kind.minutes0 { Card { Eyebrow(t: "Duration"); HStack(alignment: .firstTextBaseline) { Text("\(workout.minutes)").font(BC.numFont); Text("min").foregroundStyle(.secondary) }; Slider(value: Binding(get: { Double(workout.minutes) }, set: { workout.minutes = Int($0) }), in: 15...240, step: 5).tint(BC.accent) } }
                        Button { store.update(workout); mode = 0 } label: { Text("Save").frame(maxWidth: .infinity) }.buttonStyle(.borderedProminent).tint(BC.accent).controlSize(.large)
                    }
                }.padding()
            }
            .background(Color(.systemGroupedBackground))
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
    private func hrRange(_ z: Int) -> String { let m = Double(store.profile.estimatedMaxHR); let b: [(Double, Double)] = [(0.5, 0.6), (0.6, 0.75), (0.75, 0.85), (0.85, 0.9), (0.9, 1.0), (0.9, 1.0), (0.9, 1.0)]; return "\(Int(m * b[z - 1].0))–\(Int(m * b[z - 1].1)) bpm" }
}
extension WorkoutKind { var minutes0: Bool { self == .rest || self == .recoveryDay } }
