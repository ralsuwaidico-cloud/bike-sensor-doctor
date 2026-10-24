import SwiftUI
import Charts

/// Plan tab (0.5.0): a clean weekly calendar built around the rider's own availability, a weekly summary with the
/// time budget, and the historical timeline below. Tap a day to view / edit / move / skip / replace / add.
struct PlanView: View {
    @EnvironmentObject private var store: Store
    @State private var weekOffset = 0
    @State private var selected: Workout?
    @State private var dayList: PlanDay?
    @State private var showAvailability = false
    @State private var confirmRegenerate = false
    @State private var addOn: Date?

    private var weekDate: Date { Calendar.current.date(byAdding: .day, value: 7 * weekOffset, to: Date())! }
    private var week: [Workout] { store.workouts(weekOf: weekDate) }
    private var days: [PlanDay] { PlanDay.group(week, weekOf: weekDate) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    weekHeader
                    calendar
                    summary
                    dayCards
                    availabilityCard
                    TimelineSection()
                }.padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Plan")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button { showAvailability = true } label: { Label("Days", systemImage: "calendar.badge.clock") } } }
            .sheet(item: $selected) { w in WorkoutDetail(workout: w) }
            .sheet(isPresented: $showAvailability) { AvailabilityEditor() }
            .sheet(item: $addOn) { d in AddWorkoutSheet(date: d) }
            .sheet(item: $dayList) { day in dayListSheet(day) }
            .alert("Replace your edited sessions?", isPresented: $confirmRegenerate) {
                Button("Replace", role: .destructive) { store.regenerate(weekOf: weekDate, replaceEdited: true) }
                Button("Keep my edits") { store.regenerate(weekOf: weekDate, replaceEdited: false) }
                Button("Cancel", role: .cancel) {}
            } message: { Text("\(store.editedCount(weekOf: weekDate)) session(s) this week were changed by hand. Completed sessions and past days are never touched.") }
        }
    }

    // MARK: header + calendar
    private var weekHeader: some View {
        HStack {
            Button { weekOffset -= 1 } label: { Image(systemName: "chevron.left").frame(width: 36, height: 36) }.accessibilityLabel("Previous week")
            Spacer()
            VStack(spacing: 2) {
                Text(weekOffset == 0 ? "This week" : weekOffset == 1 ? "Next week" : weekOffset == -1 ? "Last week" : weekTitle).font(.headline)
                Text(weekRange).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button { weekOffset += 1 } label: { Image(systemName: "chevron.right").frame(width: 36, height: 36) }.disabled(weekOffset >= 1).accessibilityLabel("Next week")
        }
    }
    private var weekTitle: String { let f = DateFormatter(); f.dateFormat = "d MMM"; return "Week of \(f.string(from: days.first?.date ?? weekDate))" }
    private var weekRange: String {
        let f = DateFormatter(); f.dateFormat = "d MMM"
        guard let a = days.first?.date, let b = days.last?.date else { return "" }
        return "\(f.string(from: a)) – \(f.string(from: b))"
    }

    private var calendar: some View {
        HStack(alignment: .top, spacing: 4) {
            ForEach(days, id: \.date) { day in
                Button { if day.items.count > 1 { dayList = day } else if let w = day.items.first { selected = w } else { addOn = day.date } } label: {
                    VStack(spacing: 4) {
                        Text(day.date.shortDay).font(.caption2.weight(.heavy)).foregroundStyle(Calendar.current.isDateInToday(day.date) ? BC.accent : .secondary)
                        Image(systemName: icon(day)).font(.system(size: 15, weight: .semibold)).foregroundStyle(color(day)).frame(height: 18)
                        Text(day.items.first.map { Fmt.compact(minutes: $0.minutes) } ?? "—").font(.system(size: 13, weight: .bold, design: .rounded)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
                        HStack(spacing: 2) { ForEach(day.items.prefix(3)) { w in RoundedRectangle(cornerRadius: 2).fill(w.kind.zone > 0 ? BC.zone(w.kind.zone) : Color.secondary.opacity(0.35)).frame(height: 4) } }
                        if day.items.count > 1 { Text("+\(day.items.count - 1)").font(.system(size: 9, weight: .heavy)).padding(.horizontal, 4).background(BC.accent.opacity(0.18), in: Capsule()) }
                    }
                    .padding(.vertical, 8).padding(.horizontal, 2).frame(maxWidth: .infinity, minHeight: 78)
                    .background(day.items.contains { $0.done } ? BC.live.opacity(0.14) : Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Calendar.current.isDateInToday(day.date) ? BC.accent : Color.clear, lineWidth: 1.5))
                }.buttonStyle(.plain)
                .accessibilityLabel("\(day.date.dayAndDate): \(day.items.isEmpty ? "free" : day.items.map { "\($0.kind.title) \(Fmt.duration(minutes: $0.minutes))" }.joined(separator: ", "))")
            }
        }
    }
    private func icon(_ d: PlanDay) -> String {
        guard let w = d.items.first else { return "plus" }
        switch w.kind { case .rest: return "moon.zzz"; case .recoveryDay: return "leaf"; case .strength: return "dumbbell"; case .mobility: return "figure.yoga"; case .other: return "figure.run"; case .ftpTest: return "stopwatch"; default: return "bicycle" }
    }
    private func color(_ d: PlanDay) -> Color {
        guard let w = d.items.first else { return .secondary }
        if w.skipped { return .secondary }
        return w.kind.zone > 0 ? BC.zone(w.kind.zone) : w.kind == .rest ? .secondary : BC.accent
    }

    // MARK: summary
    private var summary: some View {
        let planned = PlanEngine.rideMinutes(week), total = PlanEngine.totalMinutes(week)
        let done = week.filter { $0.done }.reduce(0) { $0 + $1.minutes }
        let limit = store.profile.hoursPerWeek * 60
        let suggestions = PlanEngine.suggestions(for: week, hoursPerWeek: store.profile.hoursPerWeek)
        return Card {
            HStack { Eyebrow(t: "Weekly summary"); Spacer(); Text("\(week.filter { $0.kind.isRide && !$0.skipped }.count) rides · \(week.filter { $0.kind.zone >= 3 }.count) hard").font(.caption).foregroundStyle(.secondary) }
            HStack(alignment: .top) {
                stat("Riding", Fmt.duration(minutes: planned), warn: planned > limit)
                stat("All training", Fmt.duration(minutes: total))
                stat("Done", Fmt.duration(minutes: done))
                stat("Budget", Fmt.duration(minutes: limit))
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack { Text("Time budget").font(.caption2.weight(.heavy)).foregroundStyle(.secondary); Spacer(); Text(planned > limit ? "\(Fmt.duration(minutes: planned - limit)) over" : "\(Fmt.duration(minutes: limit - planned)) spare").font(.caption2.weight(.heavy)).foregroundStyle(planned > limit ? BC.warn : .secondary) }
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.secondary.opacity(0.18))
                        Capsule().fill(planned > limit ? BC.warn : BC.accent).frame(width: g.size.width * min(1, limit > 0 ? Double(planned) / Double(limit) : 0))
                        Capsule().fill(BC.live).frame(width: g.size.width * min(1, limit > 0 ? Double(done) / Double(limit) : 0))
                    }
                }.frame(height: 8)
            }
            if !suggestions.isEmpty { ForEach(suggestions, id: \.self) { Text($0).font(.footnote).foregroundStyle(BC.warn) } }
        }
    }
    private func stat(_ t: String, _ v: String, warn: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 2) { Eyebrow(t: t); Text(v).font(.system(size: 17, weight: .bold, design: .rounded)).lineLimit(1).minimumScaleFactor(0.7).foregroundStyle(warn ? BC.warn : .primary) }.frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: day cards (workouts and recovery days as separate cards)
    private var dayCards: some View {
        VStack(spacing: 8) {
            ForEach(days, id: \.date) { day in
                if day.items.isEmpty {
                    Button { addOn = day.date } label: { HStack { Text(day.date.dayAndDate).font(.subheadline.weight(.semibold)); Spacer(); Text("free · add").font(.caption).foregroundStyle(.secondary) }.padding(12).frame(maxWidth: .infinity).background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12)) }.buttonStyle(.plain)
                } else {
                    ForEach(day.items) { w in
                        Button { selected = w } label: { WorkoutCard(workout: w) }.buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var availabilityCard: some View {
        Card {
            HStack { Eyebrow(t: "Your training days"); Spacer(); Button("Edit ›") { showAvailability = true }.font(.caption.bold()) }
            let a = store.effectiveAvailability
            HStack(spacing: 4) {
                ForEach(0..<7, id: \.self) { i in
                    VStack(spacing: 3) {
                        Text(WeeklyAvailability.dayNames[i]).font(.system(size: 9, weight: .heavy)).foregroundStyle(.secondary)
                        Image(systemName: a.days[i].activity.icon).font(.system(size: 12)).foregroundStyle(a.days[i].activity == .rest ? .secondary : BC.accent)
                        Text(a.days[i].activity == .rest ? "—" : Fmt.compact(minutes: a.days[i].minutes)).font(.system(size: 10, weight: .bold)).monospacedDigit()
                    }.frame(maxWidth: .infinity)
                }
            }
            Text(store.availability == nil ? "Suggested from your \(store.profile.hoursPerWeek) h/week. Set the days you can train and the plan is built around them." : "\(a.cycleDays) cycling days · \(Fmt.duration(minutes: a.cycleMinutes)) riding · \(Fmt.duration(minutes: a.totalMinutes)) total").font(.footnote).foregroundStyle(.secondary)
            Button {
                if store.editedCount(weekOf: weekDate) > 0 { confirmRegenerate = true } else { store.regenerate(weekOf: weekDate, replaceEdited: false) }
            } label: { Text("Rebuild this week from my days").frame(maxWidth: .infinity) }.buttonStyle(.bordered).disabled(weekOffset < 0)
        }
    }

    private func dayListSheet(_ day: PlanDay) -> some View {
        NavigationStack {
            List {
                ForEach(day.items) { w in
                    Button { dayList = nil; DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { selected = w } } label: {
                        HStack { ZonePill(z: w.kind.zone); VStack(alignment: .leading) { Text(w.kind.title).bold().foregroundStyle(.primary); Text("\(Fmt.duration(minutes: w.minutes)) · \(w.kind.subtitle)").font(.footnote).foregroundStyle(.secondary) }; Spacer(); if w.done { Pill(text: "done", color: BC.live) } else if w.skipped { Pill(text: "skipped") } }
                    }
                }
                Button("Add another activity") { let d = day.date; dayList = nil; DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { addOn = d } }
            }
            .navigationTitle(day.date.dayAndDate).navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dayList = nil } } }
        }.presentationDetents([.medium])
    }
}

extension Date: Identifiable { public var id: TimeInterval { timeIntervalSince1970 } }

/// One session as a card: rides and off-bike sessions look different, recovery/rest days are quiet.
struct WorkoutCard: View {
    let workout: Workout
    @Environment(\.dynamicTypeSize) private var dts
    var body: some View {
        let quiet = workout.kind == .rest || workout.kind == .recoveryDay
        HStack(alignment: .top, spacing: 10) {
            RoundedRectangle(cornerRadius: 3).fill(workout.skipped ? Color.secondary.opacity(0.4) : workout.kind.zone > 0 ? BC.zone(workout.kind.zone) : quiet ? Color.secondary.opacity(0.3) : BC.accent).frame(width: 5)
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline) {
                    Text(workout.date.dayAndDate).font(.caption.weight(.heavy)).foregroundStyle(Calendar.current.isDateInToday(workout.date) ? BC.accent : .secondary)
                    Spacer()
                    if workout.done { Pill(text: "done", color: BC.live) } else if workout.skipped { Pill(text: "skipped") } else if workout.edited { Pill(text: "edited", color: BC.accent) }
                }
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline) { titleBlock; Spacer(); durationBlock }
                    VStack(alignment: .leading, spacing: 4) { titleBlock; durationBlock }
                }
                if !quiet { Text(workout.structureText + " · " + workout.benefit).font(.caption).foregroundStyle(.secondary).lineLimit(2) }
            }
        }
        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
        .background(quiet ? Color(.secondarySystemGroupedBackground).opacity(0.6) : Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
        .accessibilityElement(children: .combine)
    }
    private var titleBlock: some View { HStack(spacing: 6) { Text(workout.kind.title).font(.body.weight(.bold)).lineLimit(1).minimumScaleFactor(0.8); ZonePill(z: workout.kind.zone) } }
    private var durationBlock: some View { Text(workout.minutes > 0 ? Fmt.duration(minutes: workout.minutes) : "—").font(.system(size: 17, weight: .bold, design: .rounded)).monospacedDigit().lineLimit(1) }
}

/// The editable weekly availability: which days you cycle, lift, do something else or rest, and for how long.
struct AvailabilityEditor: View {
    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss
    @State private var draft: WeeklyAvailability = WeeklyAvailability.suggested(hoursPerWeek: 5)
    @State private var loaded = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("The coach builds every week around these days. Rest days stay empty, lift days get strength sessions, cycling days get rides at the duration you set.").font(.footnote).foregroundStyle(.secondary)
                }
                ForEach(0..<7, id: \.self) { i in
                    Section(WeeklyAvailability.longDayNames[i]) {
                        Picker("Activity", selection: $draft.days[i].activity) { ForEach(DayAvailability.Activity.allCases, id: \.self) { Label($0.title, systemImage: $0.icon).tag($0) } }.pickerStyle(.segmented)
                        if draft.days[i].activity != .rest {
                            HStack {
                                Text("Preferred duration"); Spacer()
                                Text(Fmt.duration(minutes: draft.days[i].minutes)).monospacedDigit().foregroundStyle(.secondary)
                            }
                            Slider(value: Binding(get: { Double(draft.days[i].minutes) }, set: { draft.days[i].minutes = Int($0) }), in: 15...240, step: 5).tint(BC.accent)
                                .onChange(of: draft.days[i].activity) { _, a in if draft.days[i].minutes == 0 { draft.days[i].minutes = a == .cycle ? 60 : 30 } }
                        }
                    }
                }
                Section {
                    LabeledContent("Cycling", value: "\(draft.cycleDays) days · \(Fmt.duration(minutes: draft.cycleMinutes))")
                    LabeledContent("All training", value: Fmt.duration(minutes: draft.totalMinutes))
                    LabeledContent("Your weekly limit", value: "\(store.profile.hoursPerWeek) h")
                    if draft.cycleMinutes > store.profile.hoursPerWeek * 60 { Text("Riding time is over your weekly limit by \(Fmt.duration(minutes: draft.cycleMinutes - store.profile.hoursPerWeek * 60)). The plan will show suggestions rather than cut sessions; raise the limit in Profile › Training profile if this is realistic.").font(.footnote).foregroundStyle(BC.warn) }
                    Button("Reset to the suggestion from my hours") { draft = WeeklyAvailability.suggested(hoursPerWeek: store.profile.hoursPerWeek) }
                }
            }
            .navigationTitle("Training days").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { save() } }
            }
            .onAppear { if !loaded { draft = store.effectiveAvailability; loaded = true } }
        }
    }
    private func save() {
        for i in 0..<7 where draft.days[i].activity == .rest { draft.days[i].minutes = 0 }
        for i in 0..<7 where draft.days[i].activity != .rest && draft.days[i].minutes == 0 { draft.days[i].minutes = draft.days[i].activity == .cycle ? 60 : 30 }
        store.availability = draft
        // this week and next are rebuilt; hand-edited and completed sessions stay
        store.regenerate(weekOf: Date(), replaceEdited: false)
        store.regenerate(weekOf: Calendar.current.date(byAdding: .day, value: 7, to: Date())!, replaceEdited: false)
        dismiss()
    }
}

/// Add a session on a given day (type + duration); counted as hand-edited.
struct AddWorkoutSheet: View {
    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss
    let date: Date
    @State private var kind: WorkoutKind = .endurance
    @State private var minutes = 60
    var body: some View {
        NavigationStack {
            Form {
                Section("Type") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 100))], spacing: 6) {
                        ForEach(WorkoutKind.allCases.filter { $0 != .rest }, id: \.self) { k in Button(k.title) { kind = k; if k.minutes0 { minutes = 0 } else if minutes == 0 { minutes = k.defaultMinutes } }.buttonStyle(.bordered).tint(kind == k ? BC.accent : .secondary).controlSize(.small) }
                    }
                }
                if !kind.minutes0 { Section("Duration") { HStack { Text(Fmt.duration(minutes: minutes)).font(BC.numFont).monospacedDigit(); Spacer() }; Slider(value: Binding(get: { Double(minutes) }, set: { minutes = Int($0) }), in: 15...240, step: 5).tint(BC.accent) } }
            }
            .navigationTitle(date.dayAndDate).navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Add") { store.add(Workout(date: Calendar.current.startOfDay(for: date).addingTimeInterval(7 * 3600), kind: kind, minutes: minutes)); dismiss() } }
            }
        }
    }
}

struct WorkoutDetail: View {
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var device: DeviceLink
    @EnvironmentObject private var recorder: RideRecorder
    @EnvironmentObject private var watch: WatchLink
    @Environment(\.dismiss) private var dismiss
    @State var workout: Workout
    @State private var mode = 0   // 0 detail, 1 move, 2 edit, 3 replace
    @State private var confirmDelete = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    HStack { Text(workout.kind.title).font(.system(size: 28, weight: .bold, design: .rounded)).lineLimit(2).minimumScaleFactor(0.7); Spacer(); ZonePill(z: workout.kind.zone) }
                    Text("\(workout.date.dayAndDate) · \(workout.minutes > 0 ? "\(Fmt.duration(minutes: workout.minutes)) · " : "")\(workout.kind.subtitle)").foregroundStyle(.secondary)
                    if workout.edited { Pill(text: "edited by you — kept when the week is rebuilt", color: BC.accent) }
                    if mode == 0 { detail } else if mode == 1 { move } else if mode == 2 { edit } else { replace }
                }.padding()
            }
            .background(Color(.systemGroupedBackground))
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .alert("Remove this session?", isPresented: $confirmDelete) { Button("Remove", role: .destructive) { store.remove(workout); dismiss() }; Button("Cancel", role: .cancel) {} }
        }
    }

    @ViewBuilder private var detail: some View {
        Card { Eyebrow(t: "Why this session"); Text(workout.why) }
        let steps = workout.steps(ftp: store.profile.ftpW)
        if !steps.isEmpty { Card { ForEach(steps, id: \.name) { s in HStack { VStack(alignment: .leading) { Text(s.name).bold(); Text(s.target).font(.caption).foregroundStyle(.secondary) }; Spacer(); Text(s.duration).font(.system(size: 18, weight: .bold, design: .rounded)).lineLimit(1).minimumScaleFactor(0.7) }.padding(.vertical, 4); if s != steps.last { Divider() } } } }
        if workout.kind.zone > 0 {
            Card { Eyebrow(t: "Target zone"); ZoneBar(current: workout.kind.zone)
                let z = store.profile.powerZones[workout.kind.zone - 1]
                Text("Z\(workout.kind.zone) = \(z.lo)–\(z.hi.map(String.init) ?? "∞") W from FTP \(store.profile.ftpW) W (\(store.profile.ftpLabel)). Heart-rate targets apply when a strap or watch is connected\(watch.appInstalled ? ": Z\(workout.kind.zone) ≈ \(hrRange(workout.kind.zone))" : ".")").font(.footnote).foregroundStyle(.secondary) }
        }
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 90))], spacing: 8) {
            Button("Move") { mode = 1 }.buttonStyle(.bordered)
            Button("Edit") { mode = 2 }.buttonStyle(.bordered)
            Button("Replace") { mode = 3 }.buttonStyle(.bordered)
            Button(workout.skipped ? "Unskip" : "Skip") { workout.skipped.toggle(); store.edit(workout) }.buttonStyle(.bordered)
            Button("Remove", role: .destructive) { confirmDelete = true }.buttonStyle(.bordered)
        }
        if workout.kind.isRide, Calendar.current.isDateInToday(workout.date), !recorder.isActive, recorder.startMode(locationAuthorized: true) != .blockedByBoardRide {
            Button { if recorder.startMode(locationAuthorized: true) == .board { device.control(.start) } else { _ = recorder.start() }; dismiss() } label: { Label("Start this workout", systemImage: "play.fill").frame(maxWidth: .infinity) }.buttonStyle(.borderedProminent).tint(BC.live).controlSize(.large)
            Text("The Ride screen coaches against this session's zone; targets reach the BikeComputer when it is connected.").font(.footnote).foregroundStyle(.secondary)
        }
    }
    @ViewBuilder private var move: some View {
        Eyebrow(t: "Move to (the two days swap)")
        ForEach(store.workouts(weekOf: workout.date).filter { $0.id != workout.id }) { o in
            Button { store.swapDays(workout, o); dismiss() } label: { HStack { Text(o.date.dayAndDate).bold(); Spacer(); Text("now \(o.kind.title)").font(.caption).foregroundStyle(.secondary) }.padding(12).frame(maxWidth: .infinity).background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12)) }.buttonStyle(.plain)
        }
        Button("Cancel") { mode = 0 }
    }
    @ViewBuilder private var edit: some View {
        Card { Eyebrow(t: "Type"); LazyVGrid(columns: [GridItem(.adaptive(minimum: 100))], spacing: 6) { ForEach(WorkoutKind.allCases, id: \.self) { k in Button(k.title) { workout.kind = k; if k.minutes0 { workout.minutes = 0 } else if workout.minutes == 0 { workout.minutes = k.defaultMinutes } }.buttonStyle(.bordered).tint(workout.kind == k ? BC.accent : .secondary).controlSize(.small) } } }
        if !workout.kind.minutes0 { Card { Eyebrow(t: "Duration"); Text(Fmt.duration(minutes: workout.minutes)).font(BC.numFont).monospacedDigit(); Slider(value: Binding(get: { Double(workout.minutes) }, set: { workout.minutes = Int($0) }), in: 15...240, step: 5).tint(BC.accent) } }
        Button { store.edit(workout); mode = 0 } label: { Text("Save").frame(maxWidth: .infinity) }.buttonStyle(.borderedProminent).tint(BC.accent).controlSize(.large)
        Button("Cancel") { mode = 0 }
    }
    @ViewBuilder private var replace: some View {
        Eyebrow(t: "Replace with")
        ForEach(Coach.alternatives(for: workout), id: \.kind) { alt in
            Button { var w = workout; w.kind = alt.kind; w.minutes = alt.minutes; workout = w; store.edit(w); mode = 0 } label: {
                HStack { ZonePill(z: alt.kind.zone); VStack(alignment: .leading) { Text(alt.kind.title).bold().foregroundStyle(.primary); Text(alt.minutes > 0 ? Fmt.duration(minutes: alt.minutes) : "").font(.caption).foregroundStyle(.secondary) }; Spacer() }
                    .padding(12).frame(maxWidth: .infinity).background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
            }.buttonStyle(.plain)
        }
        Button("Cancel") { mode = 0 }
    }
    private func hrRange(_ z: Int) -> String { let m = Double(store.profile.estimatedMaxHR); let b: [(Double, Double)] = [(0.5, 0.6), (0.6, 0.75), (0.75, 0.85), (0.85, 0.9), (0.9, 1.0), (0.9, 1.0), (0.9, 1.0)]; return "\(Int(m * b[z - 1].0))–\(Int(m * b[z - 1].1)) bpm" }
}
extension WorkoutKind { var minutes0: Bool { self == .rest || self == .recoveryDay } }

/// Activities grouped per calendar day for the week strip (pure, unit-tested).
struct PlanDay: Identifiable, Equatable {
    var id: Date { date }
    let date: Date
    let items: [Workout]
    static func group(_ week: [Workout], weekOf d: Date, calendar cal: Calendar = .current) -> [PlanDay] {
        let d0 = cal.startOfDay(for: d)
        let wd = (cal.component(.weekday, from: d0) + 5) % 7
        let monday = cal.date(byAdding: .day, value: -wd, to: d0)!
        return (0..<7).map { i in
            let day = cal.date(byAdding: .day, value: i, to: monday)!
            let items = week.filter { cal.isDate($0.date, inSameDayAs: day) }.sorted { a, b in a.kind.isRide != b.kind.isRide ? a.kind.isRide : a.minutes > b.minutes }
            return PlanDay(date: day, items: items)
        }
    }
}

// MARK: - Historical timeline
struct TimelineSection: View {
    @EnvironmentObject private var store: Store
    @State private var showAll = false
    private var entries: [TimelineEntry] { Timeline.build(rides: store.rides, plan: store.plan, ftp: store.profile.ftpW) }

    var body: some View {
        let all = entries
        let shown = showAll ? all : Array(all.prefix(12))
        VStack(alignment: .leading, spacing: 8) {
            HStack { Eyebrow(t: "History"); Spacer(); Text("\(all.filter { $0.status == .completed }.count) completed").font(.caption).foregroundStyle(.secondary) }
            if all.isEmpty {
                Card { Text("No rides or completed sessions yet. Rides recorded on this phone or on the BikeComputer appear here; Apple Health import is not connected in this build.").font(.footnote).foregroundStyle(.secondary) }
            } else {
                trends(all)
                ForEach(shown) { e in
                    if let rid = e.rideId, let r = store.rides.first(where: { $0.id == rid }) {
                        NavigationLink { RideDetailView(ride: r) } label: { TimelineRow(entry: e, units: store.settings.units) }.buttonStyle(.plain)
                    } else { TimelineRow(entry: e, units: store.settings.units) }
                }
                if all.count > 12 { Button(showAll ? "Show less" : "Show all \(all.count)") { showAll.toggle() }.font(.footnote.bold()) }
            }
        }
    }
    @ViewBuilder private func trends(_ all: [TimelineEntry]) -> some View {
        let pw = Timeline.trend(all) { $0.avgPower }, hr = Timeline.trend(all) { $0.avgHR }, tss = Timeline.trend(all) { $0.tss }, mins = Timeline.trend(all) { $0.status == .completed ? $0.minutes : nil }
        if pw != nil || hr != nil || tss != nil || mins != nil {
            HStack(spacing: 8) {
                if let v = mins { Spark(title: "Duration", values: v, unit: "min", color: BC.accent) }
                if let v = pw { Spark(title: "Avg power", values: v, unit: "W", color: BC.zone(3)) }
                if let v = hr { Spark(title: "Avg HR", values: v, unit: "bpm", color: BC.warn) }
                if let v = tss { Spark(title: "Load", values: v, unit: "TSS", color: BC.zone(5)) }
            }
        }
    }
}

struct Spark: View {
    let title: String; let values: [Int]; let unit: String; let color: Color
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title.uppercased()).font(.system(size: 8, weight: .heavy)).foregroundStyle(.secondary)
            Chart(Array(values.enumerated()), id: \.offset) { i, v in LineMark(x: .value("i", i), y: .value("v", v)).foregroundStyle(color).interpolationMethod(.catmullRom) }
                .chartXAxis(.hidden).chartYAxis(.hidden).frame(height: 28)
            Text("\(values.last ?? 0) \(unit)").font(.system(size: 11, weight: .bold, design: .rounded)).monospacedDigit()
        }.frame(maxWidth: .infinity, alignment: .leading).padding(8).background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10))
    }
}

struct TimelineRow: View {
    let entry: TimelineEntry; let units: AppSettings.Units
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(spacing: 2) {
                Image(systemName: entry.rideId != nil ? "bicycle" : entry.title == "Strength" ? "dumbbell" : "figure.run").font(.system(size: 14, weight: .semibold)).foregroundStyle(statusColor)
                Circle().fill(statusColor).frame(width: 6, height: 6)
            }.frame(width: 24)
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline) {
                    Text(entry.date.dayAndDate).font(.caption.weight(.heavy)).foregroundStyle(.secondary)
                    Text(entry.title).font(.subheadline.weight(.bold)).lineLimit(1)
                    Spacer()
                    Pill(text: entry.status.rawValue, color: statusColor)
                }
                HStack(spacing: 10) {
                    metric(Fmt.duration(minutes: entry.minutes), "")
                    if let d = entry.distanceM { metric(Fmt.km(d, imperial: units == .imperial), "") }
                    if let p = entry.avgPower { metric("\(p)", "W" + (entry.normalizedPower.map { " · NP \($0)" } ?? "")) }
                    if let h = entry.avgHR { metric("\(h)", "bpm" + (entry.maxHR.map { " · max \($0)" } ?? "")) }
                    if let c = entry.cadence { metric("\(c)", "rpm") }
                    if let t = entry.tss { metric("\(t)", "TSS") }
                }.font(.caption).lineLimit(1).minimumScaleFactor(0.7)
                if entry.zoneSeconds.reduce(0, +) > 0 { ZoneStrip(seconds: entry.zoneSeconds) }
                if let r = entry.recorder { Text("recorded by \(r)").font(.caption2).foregroundStyle(.secondary) }
            }
        }
        .padding(10).frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
        .opacity(entry.status == .completed ? 1 : 0.75)
    }
    private func metric(_ v: String, _ u: String) -> some View { HStack(spacing: 2) { Text(v).bold().monospacedDigit(); if !u.isEmpty { Text(u).foregroundStyle(.secondary) } } }
    private var statusColor: Color { switch entry.status { case .completed: return BC.live; case .planned: return BC.accent; case .skipped: return .secondary; case .missed: return BC.stale } }
}

/// Time-in-zone as proportional segments (no numbers to read while scanning).
struct ZoneStrip: View {
    let seconds: [Int]
    var body: some View {
        let total = max(1, seconds.reduce(0, +))
        GeometryReader { g in
            HStack(spacing: 1) {
                ForEach(Array(seconds.enumerated()), id: \.offset) { i, s in
                    if s > 0 { RoundedRectangle(cornerRadius: 1).fill(BC.zone(i + 1)).frame(width: max(2, g.size.width * Double(s) / Double(total))) }
                }
            }
        }.frame(height: 5).accessibilityLabel("time in zones")
    }
}
