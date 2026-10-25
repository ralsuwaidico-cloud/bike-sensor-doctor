import SwiftUI

/// Quick Strength Log (0.6.0 phase 1): focus, duration, effort, optional notes. Saved as a strength session with its
/// own hours. Detailed sets / reps / weights / supersets / templates are phase 2 and are only announced here.
struct QuickStrengthLogSheet: View {
    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss
    var date: Date = Date()
    var presetFocus: StrengthFocus? = nil
    @State private var focus: StrengthFocus = .fullBody
    @State private var customName = ""
    @State private var minutes = 40
    @State private var effort = 6
    @State private var notes = ""
    @State private var when = Date()
    @State private var loaded = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Session") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 100))], spacing: 6) {
                        ForEach(StrengthFocus.allCases, id: \.self) { f in
                            Button { focus = f } label: { Label(f.title, systemImage: f.icon).frame(maxWidth: .infinity) }.buttonStyle(.bordered).tint(focus == f ? BC.accent : .secondary).controlSize(.small)
                        }
                    }
                    if focus == .custom { TextField("Name (e.g. Kettlebell circuit)", text: $customName) }
                    DatePicker("When", selection: $when, in: ...Date(), displayedComponents: [.date, .hourAndMinute])
                }
                Section("Duration") {
                    HStack { Text(Fmt.duration(minutes: minutes)).font(BC.numFont).monospacedDigit(); Spacer() }
                    Slider(value: Binding(get: { Double(minutes) }, set: { minutes = Int($0) }), in: 10...180, step: 5).tint(BC.accent)
                }
                Section {
                    Picker("Effort", selection: $effort) { Text("Easy").tag(4); Text("Moderate").tag(6); Text("Hard").tag(8) }.pickerStyle(.segmented)
                    Stepper("RPE \(effort) of 10", value: $effort, in: 1...10)
                } header: { Text("Effort") } footer: { Text("Rate of perceived exertion: how hard the whole session felt.") }
                Section("Notes (optional)") { TextField("Anything worth remembering", text: $notes, axis: .vertical).lineLimit(2...4) }
                Section {
                    Text("Sets, reps, weights, supersets and reusable templates arrive in a later build. Until then the coach knows the body region you log here and nothing more — it never guesses muscles from a label.").font(.footnote).foregroundStyle(.secondary)
                } header: { Text("Coming in a later build") }
            }
            .navigationTitle("Log strength").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { save() }.disabled(focus == .custom && customName.trimmingCharacters(in: .whitespaces).isEmpty) }
            }
            .onAppear { if !loaded { loaded = true; when = min(date, Date()); if let f = presetFocus { focus = f } } }
        }
    }
    private func save() {
        let s = StrengthSession(date: when, minutes: minutes, focus: focus, customName: customName.trimmingCharacters(in: .whitespaces), rpe: effort, notes: notes)
        _ = store.addStrength(s)
        dismiss()
    }
}

/// Home card for Strength and Hybrid Athlete modes: cycling and strength progress, one recommendation line, the
/// compact workout table and "Why?" — all from the HybridCoach assessment (real data only).
struct HybridCoachCard: View {
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var recorder: RideRecorder
    @Binding var tab: Int
    @Binding var showWorkout: Bool
    @Binding var showAlternatives: Bool
    @Binding var showStrengthLog: Bool
    @State private var showWhy = false

    private var a: HybridAssessment { HybridCoach.assess(profile: store.profile, plan: store.plan, rides: store.rides, strength: store.strength, availability: store.effectiveAvailability) }

    var body: some View {
        let a = self.a
        Card(accent: true) {
            HStack { Eyebrow(t: "\(store.profile.trainingMode.title) coach (rules) · \(Date().shortDay)"); Spacer(); Pill(text: a.combined, color: pillColor(a.combined)) }
            Text(a.recommendation).font(.title3.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                if let c = a.cycling { progress("Cycling", c, color: BC.accent) }
                if let s = a.strength { progress("Strength", s, color: BC.zone(5)) }
            }
            if let t = a.next, t.kind != .rest { table(t) }
            DisclosureGroup(isExpanded: $showWhy) {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(a.why.enumerated()), id: \.offset) { _, line in Text(line).font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
                    ForEach(a.findings.filter { $0.severity != .ok }) { f in
                        HStack(alignment: .top, spacing: 6) { Image(systemName: f.severity == .gap ? "exclamationmark.circle.fill" : f.severity == .conflict ? "calendar.badge.exclamationmark" : "info.circle").foregroundStyle(f.severity == .gap ? BC.warn : f.severity == .conflict ? BC.stale : .secondary).font(.footnote); Text(f.text).font(.footnote).fixedSize(horizontal: false, vertical: true) }
                    }
                }.padding(.top, 4)
            } label: { Text("Why?").font(.subheadline.weight(.semibold)).foregroundStyle(BC.accent) }
            actions(a)
            Text("Start opens the Ride screen; recording begins only when you hold Start ride there. Strength is logged, never recorded automatically.").font(.caption2).foregroundStyle(.secondary)
        }
    }
    @ViewBuilder private func actions(_ a: HybridAssessment) -> some View {
        let next = a.next
        let rideNext = next?.kind.isRide == true && !recorder.isActive
        let liftNext = next?.kind == .strength
        HStack(spacing: 8) {
            if rideNext { startButton }
            logButton(prominent: liftNext)
            if store.today != nil { adjustButton }
            if store.today != nil { alternativeButton }
        }
    }
    private var startButton: some View { Button { tab = 2 } label: { Label("Start", systemImage: "play.fill").frame(maxWidth: .infinity) }.buttonStyle(.borderedProminent).tint(BC.live) }
    private var adjustButton: some View { Button { showWorkout = true } label: { Text("Adjust").frame(maxWidth: .infinity) }.buttonStyle(.bordered) }
    private var alternativeButton: some View { Button { showAlternatives = true } label: { Text("Alternative").frame(maxWidth: .infinity) }.buttonStyle(.bordered) }
    @ViewBuilder private func logButton(prominent: Bool) -> some View {
        if prominent { Button { showStrengthLog = true } label: { Label("Log strength", systemImage: "dumbbell").frame(maxWidth: .infinity) }.buttonStyle(.borderedProminent).tint(BC.zone(5)) }
        else { Button { showStrengthLog = true } label: { Text("Log strength").frame(maxWidth: .infinity) }.buttonStyle(.bordered) }
    }
    private func progress(_ title: String, _ p: SportProgress, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack { Eyebrow(t: title); Spacer(); Text(p.sessionsTarget > 0 ? "\(p.sessionsDone)/\(p.sessionsTarget)" : "\(p.sessionsDone)").font(.caption.weight(.heavy)).monospacedDigit() }
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.secondary.opacity(0.18))
                    if p.minutesTarget > 0 { Capsule().fill(color.opacity(0.35)).frame(width: g.size.width * min(1, Double(p.minutesPlanned) / Double(p.minutesTarget))) }
                    Capsule().fill(color).frame(width: g.size.width * min(1, p.minutesTarget > 0 ? p.ratio : (p.minutesDone > 0 ? 1 : 0)))
                }
            }.frame(height: 7)
            Text(p.minutesTarget > 0 ? "\(Fmt.duration(minutes: p.minutesDone)) of \(Fmt.duration(minutes: p.minutesTarget))" : "\(Fmt.duration(minutes: p.minutesDone)) · no budget set").font(.caption2).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.8)
        }.frame(maxWidth: .infinity).padding(8).background(Color(.systemGroupedBackground).opacity(0.6), in: RoundedRectangle(cornerRadius: 10))
        .accessibilityLabel("\(title): \(p.note)")
    }
    private func intensity(_ t: Workout) -> String {
        if t.kind.zone > 0 { return "Zone \(t.kind.zone) · \(zoneWatts(t.kind.zone))" }
        if t.kind == .strength { return (t.strengthFocus.map { "\($0.title) · " } ?? "") + "moderate (RPE 6–7)" }
        return t.kind.subtitle
    }
    private func pillColor(_ c: String) -> Color { c == "on track" ? BC.live : c.contains("check") ? BC.stale : BC.warn }
    private func status(_ t: Workout) -> String { t.done ? "done" : t.skipped ? "skipped" : recorder.isActive ? "in progress" : "planned" }
    private func table(_ t: Workout) -> some View {
        VStack(spacing: 0) {
            row("Workout", t.displayTitle)
            row("Duration", t.minutes > 0 ? Fmt.duration(minutes: t.minutes) : "—")
            row("Intensity", intensity(t))
            row("Outcome", t.benefit)
            row("Status", status(t), last: true)
        }.background(Color(.systemGroupedBackground).opacity(0.6), in: RoundedRectangle(cornerRadius: 10))
    }
    private func row(_ k: String, _ v: String, last: Bool = false) -> some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline) { Text(k).font(.footnote).foregroundStyle(.secondary).frame(width: 84, alignment: .leading); Text(v).font(.footnote.weight(.medium)).frame(maxWidth: .infinity, alignment: .leading) }.padding(.horizontal, 10).padding(.vertical, 6)
            if !last { Divider().padding(.leading, 10) }
        }
    }
    private func zoneWatts(_ z: Int) -> String { let p = store.profile.powerZones[max(0, min(6, z - 1))]; return "\(p.lo)–\(p.hi.map(String.init) ?? "∞") W" }
}
