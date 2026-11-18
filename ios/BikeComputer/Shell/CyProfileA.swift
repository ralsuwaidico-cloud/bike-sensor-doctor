import SwiftUI

// Profile v2.0, sheet P03 — the two editing pages of Athlete Profile in the approved style:
//   A1 Personal details   — label, value, where the value came from, a hairline; Save in the bar, lit only on a change
//   A3 Type & experience  — four labelled three-way controls; Save in the bar; the plan change is previewed first
// They store through exactly the same calls as the pages they replace in the redesign (PersonalPage,
// TypeExperiencePage in ProfileScreens.swift, which the existing app keeps). Nothing new is stored.
// Not drawn here because the app has no such value today (sheet note "NOT IN APP TODAY"): Height.

private struct CyBarSave: ViewModifier {
    let enabled: Bool
    let id: String
    let action: () -> Void
    func body(content: Content) -> some View {
        content.toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save", action: action).disabled(!enabled)
                    .font(.body.weight(.semibold)).foregroundStyle(enabled ? CyTheme.ink : CyTheme.ink3)
                    .accessibilityIdentifier(id)
            }
        }
    }
}

/// One field of sheet A1: small label, the value (or its editor), the source on the right, a hairline underneath.
private struct CyFieldRow<Value: View>: View {
    let label: String
    let source: String
    @ViewBuilder var value: () -> Value
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.system(size: 13)).foregroundStyle(CyTheme.ink2)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                value().frame(maxWidth: .infinity, alignment: .leading)
                Text(source).font(.system(size: 13)).foregroundStyle(CyTheme.ink2).lineLimit(2).multilineTextAlignment(.trailing)
            }
            .frame(minHeight: CyTheme.minTap)
            Rectangle().fill(CyTheme.ink2).frame(height: 1).accessibilityHidden(true)
        }
        .padding(.top, 14)
    }
}

struct CyProfilePersonalDetails: View {
    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var dob: Date? = nil
    @State private var weightText = ""
    @State private var editingDOB = false
    @State private var loaded = false
    @FocusState private var focus: Int?

    private var units: AppSettings.Units { store.settings.units }
    private var storedWeight: Double? { store.profile.provenance(.weight).source == .unknown ? nil : store.profile.weightKg }
    private var weight: Double? { AthleteTypeEditor.parseWeight(weightText, units) }
    private var changed: Bool {
        name.trimmingCharacters(in: .whitespaces) != store.profile.name || dob != store.profile.dateOfBirth
            || weightText != (storedWeight.map { AthleteTypeEditor.weightString($0, units) } ?? "")
    }
    private var valueFont: Font { .system(size: 20, weight: .semibold) }

    var body: some View {
        CyProfilePage(title: "Personal details") {
            CyFieldRow(label: "Name", source: name.isEmpty ? "not set" : "entered by you") {
                TextField("Your name", text: $name).textContentType(.givenName).font(valueFont).foregroundStyle(CyTheme.ink)
                    .focused($focus, equals: 1).submitLabel(.done).onSubmit { focus = nil }
                    .accessibilityIdentifier("personalName")
            }
            CyFieldRow(label: "Date of birth", source: sourceLine(.dateOfBirth, set: dob != nil, edited: dob != store.profile.dateOfBirth)) {
                Button { focus = nil; editingDOB.toggle() } label: {
                    Text(dob.map { $0.formatted(date: .abbreviated, time: .omitted) } ?? "Not set").font(valueFont)
                        .foregroundStyle(dob == nil ? CyTheme.ink2 : CyTheme.ink).frame(maxWidth: .infinity, minHeight: CyTheme.minTap, alignment: .leading).contentShape(Rectangle())
                }
                .buttonStyle(.plain).accessibilityLabel("Date of birth, \(dob.map { $0.formatted(date: .abbreviated, time: .omitted) } ?? "not set")")
                .accessibilityIdentifier("personalDOB")
            }
            if editingDOB {
                DatePicker("Date of birth", selection: Binding(get: { dob ?? AthleteTypeEditor.dobNeutral }, set: { dob = $0 }), in: AthleteTypeEditor.dobRange, displayedComponents: .date)
                    .datePickerStyle(.wheel).labelsHidden().frame(maxWidth: .infinity)
                HStack {
                    if dob != nil { Button("Clear") { dob = nil; editingDOB = false }.foregroundStyle(CyTheme.ink2).frame(minHeight: CyTheme.minTap) }
                    Spacer()
                    Button("Done") { editingDOB = false }.font(.body.weight(.semibold)).foregroundStyle(CyTheme.ink).frame(minHeight: CyTheme.minTap)
                        .accessibilityIdentifier("personalDOBDone")
                }
            }
            CyFieldRow(label: "Weight", source: sourceLine(.weight, set: weight != nil, edited: weightText != (storedWeight.map { AthleteTypeEditor.weightString($0, units) } ?? ""))) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    TextField("Not set", text: $weightText).keyboardType(.decimalPad).font(valueFont).foregroundStyle(CyTheme.ink)
                        .focused($focus, equals: 2).fixedSize()
                        .accessibilityLabel("Weight in \(units == .imperial ? "pounds" : "kilograms")").accessibilityIdentifier("personalWeight")
                    if !weightText.isEmpty { Text(units == .imperial ? "lb" : "kg").font(valueFont).foregroundStyle(CyTheme.ink) }
                }
            }
            Text("Age is needed for heart-rate zones; weight for watts per kilogram. Each value shows where it came from.")
                .font(.system(size: 13.5)).foregroundStyle(CyTheme.ink2).fixedSize(horizontal: false, vertical: true).padding(.top, 14)
            if store.profile.provenance(.dateOfBirth).needsConfirmation || store.profile.provenance(.weight).needsConfirmation {
                Text("A value came from an earlier version and could not be verified. Please confirm or re-enter it.")
                    .font(.system(size: 13.5)).foregroundStyle(CyTheme.ink).fixedSize(horizontal: false, vertical: true).padding(.top, 8)
            }
        }
        .modifier(CyBarSave(enabled: changed, id: "personalSave", action: save))
        .toolbar { ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("Done") { focus = nil }.accessibilityIdentifier("keyboardDone") } }
        .accessibilityIdentifier("profilePersonalPage")
        .onAppear {
            guard !loaded else { return }
            loaded = true
            name = store.profile.name; dob = store.profile.dateOfBirth
            weightText = storedWeight.map { AthleteTypeEditor.weightString($0, units) } ?? ""
        }
    }

    private func sourceLine(_ f: ProfileField, set: Bool, edited: Bool) -> String {
        guard set else { return "not set" }
        if edited { return "entered by you" }
        let p = store.profile.provenance(f)
        let when = p.recordedAt.map { " · \($0.formatted(date: .abbreviated, time: .omitted))" } ?? ""
        switch p.source {
        case .unknown: return "not set"
        case .appleHealth: return "Apple Health\(when)"
        case .legacyUnverified: return "earlier version — please confirm"
        default: return "entered by you"
        }
    }
    /// The same rules as the page it replaces: the name never touches the plan; a cleared date or weight is stored as
    /// unknown, never as a default.
    private func save() {
        store.updateProfile { p in
            p.name = name.trimmingCharacters(in: .whitespaces)
            if dob != p.dateOfBirth { p.setDateOfBirth(dob) }
            let cur = p.provenance(.weight).source == .unknown ? nil : p.weightKg
            if weight != cur { p.setWeight(weight) }
        }
        dismiss()
    }
}

struct CyProfileTypeExperience: View {
    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss
    @State private var mode: TrainingMode = .hybrid
    @State private var priority: TrainingPriority = .balanced
    @State private var riding: RiderProfile.Level = .beginner
    @State private var lifting: StrengthPrefs.Experience = .beginner
    @State private var loaded = false
    @State private var preview: PreviewRef? = nil

    private var changed: Bool {
        mode != store.profile.trainingMode
            || (mode.includesCycling && riding != store.profile.level)
            || (mode.includesLifting && lifting != (store.strengthPrefs.experience ?? .beginner))
            || (mode == .hybrid && priority != store.profile.priority)
    }

    var body: some View {
        CyProfilePage(title: "Type & experience") {
            group("ATHLETE TYPE", id: "typeMode") {
                CySegmentedControl(options: [(TrainingMode.cycling, "Cycling"), (TrainingMode.strength, "Strength"), (TrainingMode.hybrid, "Hybrid")], selection: $mode)
            }
            if mode == .hybrid {
                group("HYBRID BALANCE", id: "typeBalance") {
                    CySegmentedControl(options: [(TrainingPriority.cycling, "Cycling"), (TrainingPriority.balanced, "Balanced"), (TrainingPriority.strength, "Strength")], selection: $priority)
                }
            }
            if mode.includesCycling {
                group("RIDING EXPERIENCE", id: "typeRiding") {
                    CySegmentedControl(options: RiderProfile.Level.allCases.map { ($0, ProfileText.level($0)) }, selection: $riding)
                }
            }
            if mode.includesLifting {
                group("LIFTING EXPERIENCE", id: "typeLifting") {
                    CySegmentedControl(options: StrengthPrefs.Experience.allCases.map { ($0, ProfileText.strengthLevel($0)) }, selection: $lifting)
                }
            }
            Text("Changing these changes your plan. You will see a preview and approve it first.")
                .font(.system(size: 13.5)).foregroundStyle(CyTheme.ink2).fixedSize(horizontal: false, vertical: true).padding(.top, 18)
        }
        .modifier(CyBarSave(enabled: changed, id: "typeSave", action: save))
        .accessibilityIdentifier("profileTypePage")
        .onAppear {
            guard !loaded else { return }
            loaded = true
            mode = store.profile.trainingMode; riding = store.profile.level
            lifting = store.strengthPrefs.experience ?? .beginner
            priority = store.profile.trainingMode == .hybrid ? store.profile.priority : .balanced
        }
        .sheet(item: $preview) { r in PlanChangeSheet(proposalId: r.id) { dismiss() } }
    }

    private func group<C: View>(_ title: String, id: String, @ViewBuilder _ control: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.system(size: 12, weight: .semibold)).tracking(0.8).foregroundStyle(CyTheme.ink2).accessibilityAddTraits(.isHeader)
            control()
                .padding(3)
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(CyTheme.line, lineWidth: 1))
                .accessibilityElement(children: .contain).accessibilityIdentifier(id)
        }
        .padding(.top, 18)
    }

    /// The same path as the page it replaces: one training change, previewed and approved before the plan is rebuilt.
    private func save() {
        var d = OnboardingAnswers()
        d.mode = mode
        d.cyclingLevel = riding
        d.strengthLevel = mode.includesLifting ? lifting : store.strengthPrefs.experience
        d.priority = mode == .hybrid ? priority : nil
        if let r = store.changeTraining(cause: .profile, { x in d.apply(to: &x) }) { preview = r } else { dismiss() }
    }
}
