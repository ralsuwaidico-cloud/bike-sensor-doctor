import SwiftUI

struct WatchContentView: View {
    @EnvironmentObject private var phone: PhoneLink
    @EnvironmentObject private var health: HealthAccess

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Text("BikeComputer")
                    .font(.headline)
                Text("Test build \(AppInfo.label)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Divider()

                Label(phone.reachable ? "iPhone reachable" : "iPhone not reachable",
                      systemImage: phone.reachable ? "iphone" : "iphone.slash")
                    .font(.footnote)
                    .foregroundStyle(phone.reachable ? .green : .secondary)
                Text("Tests answered: \(phone.pingsAnswered)")
                    .font(.footnote)

                Divider()

                Button("Allow heart rate") { health.request() }
                    .disabled(!health.available)
                Text(health.status)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
