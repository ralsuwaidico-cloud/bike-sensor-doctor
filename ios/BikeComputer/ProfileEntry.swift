import SwiftUI

// MARK: - S2-0 (owner 2 Nov, evidence E1): entering a value never seeds one.
// "Add" / "Not set" used to write 70 kg or the picker's youngest date and label it `.entered`. These two controls keep
// a local draft and save only what the athlete typed or picked, on an explicit action. Nothing is written otherwise.

/// Weight entry: a typed number in the athlete's units; saved on Save when it parses and is in range (30–200 kg).
struct WeightEntryRow: View {
    @EnvironmentObject private var store: Store
    @State private var draft = ""
    @State private var editing = false
    @FocusState private var focused: Bool
    var identifier = "profileWeight"

    private var imperial: Bool { store.settings.units == .imperial }
    private var parsedKg: Double? {
        guard let v = Double(draft.replacingOccurrences(of: ",", with: ".")) else { return nil }
        let kg = imperial ? v / 2.20462 : v
        return (30...200).contains(kg) ? kg : nil
    }

    var body: some View {
        if editing {
            HStack(spacing: DS.s) {
                TextField(imperial ? "lb" : "kg", text: $draft)
                    .keyboardType(.decimalPad).focused($focused)
                    .textFieldStyle(.roundedBorder).frame(maxWidth: 120)
                    .accessibilityIdentifier("\(identifier)Field")
                Text(imperial ? "lb" : "kg").foregroundStyle(.secondary)
                Spacer()
                Button("Cancel") { editing = false; draft = "" }.accessibilityIdentifier("\(identifier)Cancel")
                Button("Save") { if let kg = parsedKg { store.updateProfile { $0.setWeight(kg) } }; editing = false; draft = "" }
                    .buttonStyle(.borderedProminent).disabled(parsedKg == nil).accessibilityIdentifier("\(identifier)Save")
            }
            .frame(minHeight: DS.minTap)
        } else {
            Button { editing = true; focused = true } label: { LabeledContent("Weight", value: "Not set") }
                .accessibilityIdentifier(identifier)
                .accessibilityHint("Opens a field to type your weight")
        }
    }
}

/// Date-of-birth entry: the wheel starts at a neutral position (or the saved birth year) and the date is written only
/// when the athlete taps Save.
struct DateOfBirthEntryRow: View {
    @EnvironmentObject private var store: Store
    let range: ClosedRange<Date>
    @State private var draft: Date? = nil
    @State private var editing = false
    var identifier = "profileBirth"

    private var title: String {
        if let y = store.profile.birthYear { return "Birth year \(y) · set the date" }
        return "Not set"
    }
    private var startDate: Date {
        if let y = store.profile.birthYear, let d = Calendar.current.date(from: DateComponents(year: y, month: 7, day: 1)), range.contains(d) { return d }
        // a neutral starting point in the middle of the allowed range — it is not saved unless the athlete taps Save
        return Date(timeIntervalSince1970: (range.lowerBound.timeIntervalSince1970 + range.upperBound.timeIntervalSince1970) / 2)
    }

    var body: some View {
        if editing {
            VStack(alignment: .leading, spacing: DS.s) {
                DatePicker("Date of birth", selection: Binding(get: { draft ?? startDate }, set: { draft = $0 }), in: range, displayedComponents: .date)
                    .datePickerStyle(.wheel).labelsHidden().accessibilityIdentifier("\(identifier)Picker")
                HStack {
                    Button("Cancel") { editing = false; draft = nil }.accessibilityIdentifier("\(identifier)Cancel")
                    Spacer()
                    Button("Save") { if let d = draft { store.updateProfile { $0.setDateOfBirth(d) } }; editing = false; draft = nil }
                        .buttonStyle(.borderedProminent).disabled(draft == nil).accessibilityIdentifier("\(identifier)Save")
                }
                if draft == nil { Text("Move the wheel to your date, then Save.").font(.footnote).foregroundStyle(.secondary) }
            }
        } else {
            Button { editing = true } label: { LabeledContent("Date of birth", value: title) }
                .accessibilityIdentifier(identifier)
                .accessibilityHint("Opens a date picker")
        }
    }
}
