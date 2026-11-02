import SwiftUI

/// Coach remediation M-01 (independent review F-01 / F-13 / F-18): the health check. rc3 (owner 1 Nov): no longer part of
/// onboarding or ordinary navigation — reachable only from Profile › Settings › Health & safety for riders who saved
/// answers in an earlier version (and from the hold sheet while such a restriction pauses training). Every question needs
/// an explicit Yes or No; nothing is pre-set.
/// Yes/no only; nothing is diagnosed and nothing leaves the phone.
struct HealthCheckView: View {
    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss
    @State private var answers: [Bool?] = Array(repeating: nil, count: HealthScreen.questions.count)
    @State private var clearedOn: Date? = nil
    @State private var clearanceConfirmed = false
    @State private var age: Int = 0
    @State private var loaded = false
    /// Review P3-02: the still-valid previous answers (nil = none), their condition answers, and whether the rider
    /// confirmed or changed the clearance in this visit.
    @State private var previous: HealthScreen? = nil
    @State private var clearanceTouched = false

    private var draft: HealthScreen {
        var s = HealthScreen()
        for (i, q) in HealthScreen.questions.enumerated() { s[keyPath: q.key] = answers[i] ?? false }
        s.clearedAt = clearanceConfirmed && s.clearable ? min(clearedOn ?? Date(), Date()) : nil
        return s
    }
    private var complete: Bool { !answers.contains { $0 == nil } && age > 0 }

    var body: some View {
        Form {
            Section {
                Text("Optional yes/no questions. Your answers stay on this phone.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("Your age") {
                Stepper(value: $age, in: 0...100) { Text(age == 0 ? "Not set" : "\(age) years") }
                    .frame(minHeight: DS.minTap)
                    .accessibilityIdentifier("healthCheckAge")
                Text("Used for recovery and heart-rate estimates.").font(.footnote).foregroundStyle(.secondary)
                if age > 0 && age < 18 {
                    // review P3-17: the screening questions and the coach are written for adults; no youth-specific
                    // programming is claimed
                    Text("Cyclift's coach is designed for adults. If you are under 18, train only with a parent's or guardian's agreement and, ideally, a qualified coach — the plan is not adapted for young athletes.")
                        .font(.footnote).foregroundStyle(BC.warn).fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("healthCheckYouthNotice")
                }
            }
            Section("Answer each one") {
                ForEach(HealthScreen.questions.indices, id: \.self) { i in
                    VStack(alignment: .leading, spacing: DS.s) {
                        Text(HealthScreen.questions[i].text).font(.subheadline).fixedSize(horizontal: false, vertical: true)
                        Picker("Answer", selection: Binding(get: { answers[i].map { $0 ? 1 : 0 } ?? -1 }, set: { answers[i] = $0 < 0 ? nil : $0 == 1 })) {
                            Text("No").tag(0); Text("Yes").tag(1)
                        }
                        .pickerStyle(.segmented)
                        .frame(minHeight: DS.minTap)
                        .accessibilityIdentifier("healthQ\(i)")
                    }
                    .padding(.vertical, DS.xs)
                }
            }
            let d = draft
            if complete && d.anyYes {
                Section {
                    if d.supervisedOnly {
                        Text("Your doctor asked for supervised exercise, so Cyclift will not plan training for you. Train with your doctor's team; you can still record rides and lifts.")
                            .font(.footnote)
                    } else if d.currentIllness && !d.stopAnswers && !d.recentOperation {
                        Text("Rest while you are ill. Cyclift plans no sessions until you answer again when you feel well — no doctor's note needed for a cold or similar.")
                            .font(.footnote)
                    } else if d.currentIllness && !d.stopAnswers {
                        Text("Rest while you are ill. Cyclift plans no sessions until you answer again when you feel well. After an operation, a doctor should clear you before hard training.")
                            .font(.footnote)
                    } else if d.stopAnswers {
                        Text("Chest pain, fainting or dizziness need a doctor's check before any training. Cyclift plans no sessions until you record that a doctor examined you and cleared you.")
                            .font(.footnote)
                    } else {
                        Text("Talk to your doctor before hard training. Until you record a clearance, the coach plans easy-to-moderate rides and lighter lifting without weight increases.")
                            .font(.footnote)
                    }
                    if d.clearable {
                        Toggle(isOn: Binding(get: { clearanceConfirmed }, set: { clearanceConfirmed = $0; clearanceTouched = true })) {
                            Text("A doctor examined me and cleared me for unrestricted training").font(.subheadline).fixedSize(horizontal: false, vertical: true)
                        }.frame(minHeight: DS.minTap)
                        if clearanceConfirmed {
                            DatePicker("Date of the clearance", selection: Binding(get: { clearedOn ?? Date() }, set: { clearedOn = $0; clearanceTouched = true }), in: ...Date(), displayedComponents: .date)
                                .frame(minHeight: DS.minTap)
                            if d.stopAnswers {
                                Text("For chest pain, fainting or dizziness the clearance must be from a check on or after the day you answered these questions.").font(.footnote).foregroundStyle(.secondary)
                            }
                        }
                    }
                } header: { Text("What this means") }
            }
            Section {
                Button {
                    let now = Date()
                    var s = draft; s.answeredAt = now
                    // review P3-02: a clearance covers only the answers it was confirmed for
                    if let prev = previous, prev.conditionKeys == s.conditionKeys { s.conditionsChangedAt = prev.conditionsChangedAt ?? prev.answeredAt } else { s.conditionsChangedAt = now }
                    if s.clearedAt != nil {
                        s.clearanceConfirmedAt = (!clearanceTouched && previous?.clearedAt != nil) ? (previous?.clearanceConfirmedAt ?? previous?.answeredAt ?? now) : now
                    }
                    store.updateProfile { p in
                        p.healthScreen = s
                        // S2-0: an age typed here is the athlete's statement (entered); never a default
                        if age > 0, p.dateOfBirth == nil { p.age = age; p.birthYear = Calendar.current.component(.year, from: Date()) - age; p.setProvenance(.dateOfBirth, ValueProvenance(source: .entered, recordedAt: now)) }
                    }
                    store.rebuildFromHybridAnswers(newDays: false)
                    store.refreshRideSafety()
                    dismiss()
                } label: { Text("Save answers").frame(maxWidth: .infinity, minHeight: DS.minTap) }
                .buttonStyle(.borderedProminent)
                .disabled(!complete)
                .accessibilityIdentifier("healthCheckSave")
            } footer: {
                Text(complete ? "Based on the general questions of the PAR-Q+ screening questionnaire. This is not a medical assessment." : "Answer every question and set your age to save.")
            }
        }
        .navigationTitle("Health check")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            guard !loaded else { return }
            loaded = true
            age = store.profile.effectiveAge ?? 0
            // a previous, still valid check is shown as answered; an expired or older one starts empty again so every
            // question gets an explicit answer (F-13); its old answers still decode (N-12) and a "see a doctor" result
            // stays in force until answered again (N-07)
            if let s = store.profile.healthScreen {
                let current = s.questionSet == HealthScreen.currentQuestionSet && s.status() != .notAnswered
                answers = HealthScreen.questions.map { q in (!current && q.key == \HealthScreen.currentIllness) ? nil : s[keyPath: q.key] }
                if !current { answers = answers.map { _ in nil } }
                clearanceConfirmed = current && s.clearedAt != nil; clearedOn = current ? s.clearedAt : nil
                previous = current ? s : nil
            }
        }
        // review P3-02: changing any answer that needs a doctor (e.g. new chest pain) clears the recorded clearance — it has
        // to be confirmed again for the new answers
        .onChange(of: answers) { _, _ in
            if let prev = previous, clearanceConfirmed, !clearanceTouched, draft.conditionKeys != prev.conditionKeys { clearanceConfirmed = false; clearedOn = nil }
        }
    }
}
