import SwiftUI

// Profile v2.0, sheet P04 (visual design still "Pending Review" on the sheet itself) — Training Setup pages:
//   B1 Equipment & restrictions — equipment as chips; the restriction lists open the existing editors
//   B3 Recovery & pauses        — the recovery preference, the training pause and the saved health answers
// Same stored values and the same change paths as the pages they replace in the redesign (EquipmentPage,
// TrainingPreferencesPage's recovery picker, HealthSafetyPage). The existing app keeps those pages.

/// The three-way control of sheets P03/P04: the chosen option is a light pill with dark text.
struct CyChoiceBar<T: Hashable>: View {
    let options: [(T, String)]
    @Binding var selection: T
    var body: some View {
        HStack(spacing: 2) {
            ForEach(Array(options.enumerated()), id: \.offset) { pair in
                let on = pair.element.0 == selection
                Button { selection = pair.element.0 } label: {
                    Text(pair.element.1).font(.system(size: 15, weight: .semibold)).lineLimit(2).minimumScaleFactor(0.8).multilineTextAlignment(.center)
                        .foregroundStyle(on ? CyTheme.canvas : CyTheme.ink2)
                        .frame(maxWidth: .infinity, minHeight: 38)
                        .background(on ? CyTheme.ink : Color.clear, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .padding(.vertical, 3).contentShape(Rectangle())
                }
                .buttonStyle(.plain).accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(.horizontal, 3)
        .background(CyTheme.card2, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).stroke(CyTheme.line2, lineWidth: 1))
        .accessibilityElement(children: .contain)
    }
}

struct CyGroupLabel: View {
    let text: String
    var body: some View {
        Text(text).font(.system(size: 12, weight: .semibold)).tracking(0.8).foregroundStyle(CyTheme.ink2)
            .padding(.top, 18).padding(.bottom, 8).accessibilityAddTraits(.isHeader)
    }
}

struct CyProfileEquipment: View {
    @EnvironmentObject private var store: Store

    var body: some View {
        CyProfilePage(title: "Equipment & restrictions") {
            CyGroupLabel(text: "EQUIPMENT YOU HAVE")
            FlowLayout(spacing: 8) {
                ForEach(EquipmentProfile.allOptions, id: \.self) { e in
                    let on = store.equipment.owned.contains(e)
                    Button { if on { store.equipment.owned.remove(e) } else { store.equipment.owned.insert(e) } } label: {
                        Text(e.capitalized).font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(on ? CyTheme.canvas : CyTheme.ink2)
                            .padding(.horizontal, 15).frame(minHeight: CyTheme.minTap)
                            .background(on ? CyTheme.ink : Color.clear, in: Capsule())
                            .overlay(Capsule().stroke(on ? Color.clear : CyTheme.line2, lineWidth: 1))
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain).accessibilityAddTraits(on ? .isSelected : [])
                    .accessibilityIdentifier("equip-\(e)")
                }
            }
            .accessibilityElement(children: .contain).accessibilityIdentifier("equipmentChips")
            CyGroupLabel(text: "EXERCISE RESTRICTIONS")
            CyProfileRows {
                CyProfileRow(title: "Exercises I cannot do and other equipment", summary: excludedSummary, id: "equipExcluded") { EquipmentPage() }
                if store.profile.trainingMode.includesLifting {
                    CyProfileRow(title: "Avoided, always use instead, temporarily unavailable", summary: prefsSummary, id: "equipPrefs") { StrengthPrefsPage() }
                }
            }
            Text("Changing equipment changes your plan — preview and approve first.")
                .font(.system(size: 13.5)).foregroundStyle(CyTheme.ink2).fixedSize(horizontal: false, vertical: true).padding(.top, 14)
        }
        .accessibilityIdentifier("profileEquipmentPage")
    }
    private var excludedSummary: String {
        let n = store.equipment.excluded.count
        return n == 0 ? "None excluded" : "\(n) excluded"
    }
    private var prefsSummary: String {
        let p = store.strengthPrefs
        let t = p.temporary.filter { $0.active(now: Date()) }.count
        return "\(p.avoid.count) avoided · \(p.alwaysPrefer.count) replaced · \(t) unavailable"
    }
}

struct CyProfileRecoveryPauses: View {
    @EnvironmentObject private var store: Store
    @State private var preview: PreviewRef? = nil

    private var hasSavedAnswers: Bool {
        guard let s = store.profile.healthScreen else { return false }
        return s.answeredAt != nil && (!s.conditionKeys.isEmpty || s.clearedAt != nil || s.supervisedOnly || s.currentIllness)
    }

    var body: some View {
        CyProfilePage(title: "Recovery & pauses") {
            CyGroupLabel(text: "RECOVERY PREFERENCE")
            CyChoiceBar(options: [(RecoveryCapacity.low, "Slower"), (RecoveryCapacity.normal, "Normal"), (RecoveryCapacity.high, "Faster")],
                        selection: Binding(get: { store.profile.recoveryCapacity ?? .normal },
                                           set: { v in if v != (store.profile.recoveryCapacity ?? .normal) { preview = store.changeTraining(cause: .profile) { $0.profile.recoveryCapacity = v } } }))
                .accessibilityIdentifier("recoveryCapacity")
            CyGroupLabel(text: "TRAINING PAUSE")
            CyProfileRows {
                CyProfileRow(title: "Pause training", summary: store.profile.trainingPause.map { "Paused · \($0.reason.title)" } ?? "Off", id: "healthPause") {
                    TrainingPauseView().navigationTitle("Pause training").navigationBarTitleDisplayMode(.inline)
                }
                if hasSavedAnswers {
                    CyProfileRow(title: "Health check answers", summary: "Saved · review", id: "healthReview") { HealthCheckView() }
                }
            }
            (Text("A pause stops planned sessions without deleting history. ").foregroundColor(CyTheme.ink2)
             + Text("Cyclift gives training guidance, not medical advice. ").foregroundColor(CyTheme.ink).fontWeight(.semibold)
             + Text("Stop and get medical advice if you feel chest pain, dizziness or unusual breathlessness.").foregroundColor(CyTheme.ink2))
                .font(.system(size: 13.5)).fixedSize(horizontal: false, vertical: true).padding(.top, 14)
        }
        .accessibilityIdentifier("profileRecoveryPage")
        .sheet(item: $preview) { r in PlanChangeSheet(proposalId: r.id) }
    }
}
