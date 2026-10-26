import SwiftUI

/// Cyclift watch app: live heart rate, workout state, the iPhone link (how readings reach the phone) and the last
/// delivery time, then the phone's ride mirror with wrist controls. Colours match the iPhone app (teal accent).
enum CycliftWatch {
    static let accent = Color(red: 0.204, green: 0.906, blue: 0.894)
    static let live = Color(red: 0.337, green: 0.878, blue: 0.549)
    static let stale = Color(red: 1, green: 0.714, blue: 0.302)
    static let warn = Color(red: 1, green: 0.353, blue: 0.353)
}

struct WatchContentView: View {
    @EnvironmentObject private var phone: PhoneLink
    @EnvironmentObject private var workout: WorkoutManager
    @State private var now = Date()
    private let clock = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var hrValue: some View {
        HStack(alignment: .firstTextBaseline, spacing: 2) {
            Text(workout.hrIsFresh ? "\(workout.hrBpm ?? 0)" : "--")
                .font(.system(size: 46, weight: .bold, design: .rounded)).monospacedDigit()
                .foregroundStyle(workout.hrIsFresh ? .red : .secondary)
            Text("bpm").font(.caption).foregroundStyle(.secondary)
        }.accessibilityElement(children: .combine)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 4) {
                    Text("CYCLIFT").font(.system(.footnote, design: .rounded).weight(.heavy)).tracking(1.5).foregroundStyle(CycliftWatch.accent)
                    Spacer()
                    Text(workoutStateText).font(.caption2.weight(.semibold)).foregroundStyle(workout.phase == .running ? CycliftWatch.live : .secondary)
                }
                // quality release: the elapsed time moves under the heart rate when both do not fit (large text, 41 mm)
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline) { hrValue; Spacer(minLength: 2); Text(elapsed).font(.title3).monospacedDigit() }
                    VStack(alignment: .leading, spacing: 0) { hrValue; Text(elapsed).font(.title3).monospacedDigit() }
                }
                Text(hrLine).font(.caption2).foregroundStyle(.secondary)

                linkCard

                if phone.versionMismatch {
                    Text("This watch app is older than Cyclift on the iPhone. Update it: Watch app on iPhone › Cyclift › Update/Install.")
                        .font(.caption2).foregroundStyle(CycliftWatch.stale)
                }

                rideMirror

                switch workout.phase {
                case .idle:
                    Button { workout.start() } label: { Label("Start cycling", systemImage: "play.fill").frame(maxWidth: .infinity) }
                        .tint(CycliftWatch.live).disabled(!workout.available)
                case .running:
                    HStack {
                        Button { workout.pause() } label: { Image(systemName: "pause.fill").frame(maxWidth: .infinity) }.accessibilityLabel("Pause")
                        Button { workout.end() } label: { Image(systemName: "stop.fill").frame(maxWidth: .infinity) }.tint(.red).accessibilityLabel("End")
                    }
                case .paused:
                    HStack {
                        Button { workout.resume() } label: { Image(systemName: "play.fill").frame(maxWidth: .infinity) }.tint(CycliftWatch.live).accessibilityLabel("Resume")
                        Button { workout.end() } label: { Image(systemName: "stop.fill").frame(maxWidth: .infinity) }.tint(.red).accessibilityLabel("End")
                    }
                case .ended:
                    Text("Save this workout to Apple Health?").font(.footnote)
                    Button("Save to Health") { workout.saveToHealth() }.tint(CycliftWatch.live)
                    Button("Discard") { workout.discard() }.tint(.red)
                    Text("The ride on your iPhone or BikeComputer is kept either way.").font(.caption2).foregroundStyle(.secondary)
                }

                Divider()
                Text(workout.status).font(.caption2).foregroundStyle(.secondary)
                Text("Health permission: \(workout.workoutWriteStatus)").font(.caption2).foregroundStyle(workout.workoutWriteStatus == "denied" ? CycliftWatch.warn : .secondary)
                if workout.workoutWriteStatus == "denied" {
                    Text("Allow it on the iPhone: Settings › Health › Data Access & Devices › Cyclift.").font(.caption2).foregroundStyle(.secondary)
                } else if !workout.permissionAsked, workout.workoutWriteStatus == "not asked" {
                    Button("Allow heart rate") { workout.requestPermission() }.font(.caption)
                }
                Text("Watch \(AppInfo.label)" + (phone.phoneBuild.map { " · iPhone \($0)" } ?? "")).font(.caption2).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onReceive(clock) { now = $0 }
    }

    private var workoutStateText: String {
        switch workout.phase { case .idle: return "ready"; case .running: return "workout running"; case .paused: return "paused"; case .ended: return "ended" }
    }
    private var hrLine: String {
        if workout.hrIsFresh { return "Apple Watch · \(workout.sentCount) sent to iPhone" }
        return workout.phase == .running ? "waiting for a reading…" : "no live heart rate"
    }

    /// How readings reach the iPhone right now, and when the last one arrived there.
    private var linkCard: some View {
        let ok = workout.mirroring || phone.reachable
        let channel = workout.mirroring ? "workout mirroring" : phone.reachable ? "Watch Connectivity" : "not connected"
        return VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Image(systemName: ok ? "iphone" : "iphone.slash").foregroundStyle(ok ? CycliftWatch.live : (workout.phase == .running ? CycliftWatch.stale : .secondary))
                Text("iPhone: \(channel)").font(.caption2.weight(.semibold))
            }
            Text(lastDelivery).font(.caption2).foregroundStyle(workout.deliveryIsFresh || workout.phase != .running ? Color.secondary : CycliftWatch.stale)
        }
    }
    private var lastDelivery: String {
        guard let t = workout.lastDeliveredAt else { return workout.phase == .running ? "nothing delivered yet — reconnecting automatically" : "last delivery: none" }
        let s = max(0, Int(now.timeIntervalSince(t)))
        return "last delivery \(s < 2 ? "just now" : "\(s) s ago") (\(workout.lastDeliveryChannel))"
    }

    /// The phone's ride, mirrored 1 Hz while reachable. Commands go to the phone, which applies the one-owner rules
    /// (board records when connected with live data, otherwise the phone); the mirror shows what it decided.
    @State private var confirmEnd = false
    private var rideMirror: some View {
        let r = phone.ride
        return VStack(alignment: .leading, spacing: 6) {
            Divider()
            HStack { Text("Ride").font(.caption.bold()); Spacer(); Text(r.isFresh ? r.ownerText : (phone.reachable ? "waiting for the phone…" : "phone not reachable")).font(.caption2).foregroundStyle(r.isFresh && r.active ? CycliftWatch.live : .secondary) }
            if r.isFresh, r.active {
                HStack(alignment: .firstTextBaseline) {
                    Text(fmt(r.elapsed)).font(.title3).monospacedDigit()
                    Spacer()
                    Text(String(format: "%.1f km", Double(r.dist) / 1000)).font(.caption).monospacedDigit().foregroundStyle(.secondary)
                }
                HStack {
                    tile("W", r.power.map { "\($0)" }, r.zone.map { "Z\($0)" })
                    tile("rpm", r.cad.map { "\($0)" }, nil)
                    tile("bpm", r.hr.map { "\($0)" }, r.hrSrc)
                }
                if r.state == "paused" { Text("paused").font(.caption2).foregroundStyle(.orange) }
            }
            if r.isFresh {
                if !r.active {
                    Button { phone.send(command: WatchMessage.cmdStart) } label: { Label(r.boardReady ? "Start on the board" : "Start ride · phone", systemImage: "play.fill").frame(maxWidth: .infinity) }.tint(CycliftWatch.live).font(.caption)
                } else if confirmEnd {
                    Text("End the ride?").font(.caption)
                    HStack {
                        Button("End") { phone.send(command: WatchMessage.cmdEndConfirm); confirmEnd = false }.tint(.red)
                        Button("Keep going") { confirmEnd = false }
                    }.font(.caption)
                } else {
                    HStack {
                        if r.state == "running" { Button { phone.send(command: WatchMessage.cmdPause) } label: { Image(systemName: "pause.fill").frame(maxWidth: .infinity) } }
                        else { Button { phone.send(command: WatchMessage.cmdResume) } label: { Image(systemName: "play.fill").frame(maxWidth: .infinity) }.tint(CycliftWatch.live) }
                        Button { confirmEnd = true; if r.owner == "board" { phone.send(command: WatchMessage.cmdEnd) } } label: { Image(systemName: "stop.fill").frame(maxWidth: .infinity) }.tint(.red)
                    }
                }
                Text("Values come from the phone; \"--\" means no live source.").font(.caption2).foregroundStyle(.secondary)
            } else {
                Text("Open Cyclift on the iPhone to control the ride from here.").font(.caption2).foregroundStyle(.secondary)
            }
        }
    }
    private func tile(_ unit: String, _ v: String?, _ sub: String?) -> some View {
        VStack(spacing: 0) {
            Text(v ?? "--").font(.system(size: 18, weight: .bold, design: .rounded)).monospacedDigit().foregroundStyle(v == nil ? .secondary : .primary)
            Text(sub ?? unit).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
        }.frame(maxWidth: .infinity)
    }
    private func fmt(_ s: Int) -> String { s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60) : String(format: "%d:%02d", s / 60, s % 60) }

    private var elapsed: String { let s = Int(workout.elapsed); return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60) : String(format: "%d:%02d", s / 60, s % 60) }
}
