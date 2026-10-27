import SwiftUI

/// Coach remediation M-01: the health check (Profile › Health check, and the Home card until it is answered).
/// Yes/no only; nothing is diagnosed and nothing leaves the phone.
struct HealthCheckView: View {
    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss
    @State private var draft = HealthScreen()
    @State private var loaded = false

    var body: some View {
        Form {
            Section {
                Text("Eight yes/no questions before the coach plans hard intervals or near-maximal lifting. Your answers stay on this phone.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("Answer each one") {
                ForEach(HealthScreen.questions.indices, id: \.self) { i in
                    let q = HealthScreen.questions[i]
                    Toggle(isOn: Binding(get: { draft[keyPath: q.key] }, set: { draft[keyPath: q.key] = $0 })) {
                        Text(q.text).font(.subheadline).fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(minHeight: DS.minTap)
                }
            }
            if draft.anyYes {
                Section {
                    Text("Talk to your doctor before hard training. Until you confirm clearance, the coach plans easy-to-moderate rides and lifting at RPE 7 or less.")
                        .font(.footnote)
                    Toggle(isOn: Binding(get: { draft.clearedAt != nil }, set: { draft.clearedAt = $0 ? Date() : nil })) {
                        Text("A doctor has cleared me for hard training").font(.subheadline)
                    }.frame(minHeight: DS.minTap)
                } header: { Text("Clearance") }
            }
            Section {
                Button {
                    var s = draft; s.answeredAt = Date()
                    if !s.anyYes { s.clearedAt = nil }
                    store.updateProfile { $0.healthScreen = s }
                    store.rebuildFromHybridAnswers(newDays: false)
                    dismiss()
                } label: { Text("Save answers").frame(maxWidth: .infinity, minHeight: DS.minTap) }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("healthCheckSave")
            } footer: {
                Text("Based on the general questions of the PAR-Q+ screening questionnaire. This is not a medical assessment.")
            }
        }
        .navigationTitle("Health check")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { if !loaded { draft = store.profile.healthScreen ?? HealthScreen(); loaded = true } }
    }
}

/// Home card while the health check is missing or clearance is pending.
struct HealthCheckHomeCard: View {
    @EnvironmentObject private var store: Store
    var body: some View {
        let r = store.profile.readiness
        if !r.vigorousAllowed {
            NavigationLink { HealthCheckView() } label: {
                Card(accent: true) {
                    HStack(alignment: .top, spacing: DS.s) {
                        Image(systemName: "heart.text.square").foregroundStyle(BC.warn).imageScale(.large)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(r.screen == .notAnswered ? "Answer the health check" : "Clearance needed for hard training").bold()
                            Text(r.screen == .notAnswered ? "8 quick questions. Until then, rides stay easy and lifts stop at RPE 7." : "Rides stay easy and lifts stop at RPE 7 until you confirm a doctor's clearance.")
                                .font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right").foregroundStyle(.secondary)
                    }
                }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("healthCheckCard")
        }
    }
}
