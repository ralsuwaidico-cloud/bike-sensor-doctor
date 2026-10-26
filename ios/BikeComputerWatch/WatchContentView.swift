import SwiftUI

struct WatchContentView: View {
    @EnvironmentObject private var phone: PhoneLink
    @EnvironmentObject private var workout: WorkoutManager

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Cyclift").font(.headline)
                    Spacer()
                    Image(systemName: phone.reachable ? "iphone" : "iphone.slash").foregroundStyle(phone.reachable ? .green : .secondary)
                }
                HStack(alignment: .firstTextBaseline) {
                    Text(workout.hrIsFresh ? "\(workout.hrBpm ?? 0)" : "--")
                        .font(.system(size: 44, weight: .bold, design: .rounded)).monospacedDigit()
                        .foregroundStyle(workout.hrIsFresh ? .red : .secondary)
                    Text("bpm").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Text(elapsed).font(.title3).monospacedDigit()
                }
                Text(workout.hrIsFresh ? "Apple Watch · sent \(workout.sentCount)" : (workout.phase == .running ? "waiting for a reading…" : "no live heart rate"))
                    .font(.caption2).foregroundStyle(.secondary)

                rideMirror

                switch workout.phase {
                case .idle:
                    Button { startFlow() } label: { Label("Start cycling", systemImage: "play.fill").frame(maxWidth: .infinity) }
                        .tint(.green).disabled(!workout.available)
                case .running:
                    HStack {
                        Button { workout.pause() } label: { Image(systemName: "pause.fill").frame(maxWidth: .infinity) }
                        Button { workout.end() } label: { Image(systemName: "stop.fill").frame(maxWidth: .infinity) }.tint(.red)
                    }
                case .paused:
                    HStack {
                        Button { workout.resume() } label: { Image(systemName: "play.fill").frame(maxWidth: .infinity) }.tint(.green)
                        Button { workout.end() } label: { Image(systemName: "stop.fill").frame(maxWidth: .infinity) }.tint(.red)
                    }
                case .ended:
                    Text("Save this workout to Apple Health?").font(.footnote)
                    Button("Save to Health") { workout.saveToHealth() }.tint(.green)
                    Button("Discard") { workout.discard() }.tint(.red)
                    Text("The ride on your iPhone or BikeComputer is kept either way.").font(.caption2).foregroundStyle(.secondary)
                }

                Divider()
                Text(workout.status).font(.caption2).foregroundStyle(.secondary)
                Text("Health permission: \(workout.workoutWriteStatus)").font(.caption2).foregroundStyle(.secondary)
                if !workout.permissionAsked {
                    Button("Allow heart rate") { workout.requestPermission() }.font(.caption)
                }
                Text("Version \(AppInfo.label)").font(.caption2).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// The phone's ride, mirrored 1 Hz while reachable. Commands go to the phone, which applies the one-owner rules
    /// (board records when connected with live data, otherwise the phone); the mirror shows what it decided.
    @State private var confirmEnd = false
    private var rideMirror: some View {
        let r = phone.ride
        return VStack(alignment: .leading, spacing: 6) {
            Divider()
            HStack { Text("Ride").font(.caption.bold()); Spacer(); Text(r.isFresh ? r.ownerText : (phone.reachable ? "waiting for the phone…" : "phone not reachable")).font(.caption2).foregroundStyle(r.isFresh && r.active ? .green : .secondary) }
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
                    Button { phone.send(command: WatchMessage.cmdStart) } label: { Label(r.boardReady ? "Start on the board" : "Start ride · phone", systemImage: "play.fill").frame(maxWidth: .infinity) }.tint(.green).font(.caption)
                } else if confirmEnd {
                    Text("End the ride?").font(.caption)
                    HStack {
                        Button("End") { phone.send(command: WatchMessage.cmdEndConfirm); confirmEnd = false }.tint(.red)
                        Button("Keep going") { confirmEnd = false }
                    }.font(.caption)
                } else {
                    HStack {
                        if r.state == "running" { Button { phone.send(command: WatchMessage.cmdPause) } label: { Image(systemName: "pause.fill").frame(maxWidth: .infinity) } }
                        else { Button { phone.send(command: WatchMessage.cmdResume) } label: { Image(systemName: "play.fill").frame(maxWidth: .infinity) }.tint(.green) }
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
            Text(sub ?? unit).font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(1)
        }.frame(maxWidth: .infinity)
    }
    private func fmt(_ s: Int) -> String { s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60) : String(format: "%d:%02d", s / 60, s % 60) }

    private var elapsed: String { let s = Int(workout.elapsed); return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60) : String(format: "%d:%02d", s / 60, s % 60) }

    private func startFlow() {
        if workout.workoutWriteStatus == "not asked" { workout.requestPermission { _ in workout.start() } } else { workout.start() }
    }
}
