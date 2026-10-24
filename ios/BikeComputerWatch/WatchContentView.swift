import SwiftUI

struct WatchContentView: View {
    @EnvironmentObject private var phone: PhoneLink
    @EnvironmentObject private var workout: WorkoutManager

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("BikeComputer").font(.headline)
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
                    Text("The ride on the Waveshare is kept either way.").font(.caption2).foregroundStyle(.secondary)
                }

                Divider()
                Text(workout.status).font(.caption2).foregroundStyle(.secondary)
                Text("Health permission: \(workout.workoutWriteStatus)").font(.caption2).foregroundStyle(.secondary)
                if !workout.permissionAsked {
                    Button("Allow heart rate") { workout.requestPermission() }.font(.caption)
                }
                Text("Test build \(AppInfo.label)").font(.caption2).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var elapsed: String { let s = Int(workout.elapsed); return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60) : String(format: "%d:%02d", s / 60, s % 60) }

    private func startFlow() {
        if workout.workoutWriteStatus == "not asked" { workout.requestPermission { _ in workout.start() } } else { workout.start() }
    }
}
