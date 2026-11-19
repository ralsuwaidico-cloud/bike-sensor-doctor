import SwiftUI

// Profile v2.0, sheet P05 (visual design "Pending Review" on the sheet) — Performance Settings pages:
//   C1 Heart rate — each value with where it came from, the zone method, the calculated zones
//   C2 Power      — FTP with its source, the power meter's real state, the zones calculated from FTP
// These pages show; "Edit" in the bar opens the existing editors (HeartRatePage, PowerCyclingPage), so values are
// changed through exactly the same calls as before. Nothing is typed into a zone; an unknown value stays unknown.

/// A value row of sheet P05: title, where it came from, the value on the right, a hairline.
private struct CyValueRow: View {
    let title: String
    let source: String
    let value: String
    var id: String
    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(CyDyn.f(16.5, .semibold)).foregroundStyle(CyTheme.ink)
                    Text(source).font(CyDyn.f(13.5)).foregroundStyle(CyTheme.ink2).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Text(value).font(CyDyn.f(16, .semibold)).monospacedDigit().foregroundStyle(CyTheme.ink)
            }
            .frame(minHeight: 60)
            Rectangle().fill(CyTheme.line).frame(height: 1).accessibilityHidden(true)
        }
        .accessibilityElement(children: .combine).accessibilityIdentifier(id)
    }
}

private struct CyZoneRow: View {
    let n: Int
    let name: String
    let range: String
    var body: some View {
        HStack(spacing: 10) {
            Text("Z\(n)").font(CyDyn.f(11, .heavy)).foregroundStyle(CyTheme.ink)
                .padding(.horizontal, 6).padding(.vertical, 3)
                .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).stroke(CyTheme.ink, lineWidth: 1.2))
            Text(name).font(CyDyn.f(15)).foregroundStyle(CyTheme.ink2)
            Spacer(minLength: 8)
            Text(range).font(CyDyn.f(14)).monospacedDigit().foregroundStyle(CyTheme.ink2)
        }
        .frame(minHeight: 34).accessibilityElement(children: .combine)
    }
}

private func cySource(_ p: ValueProvenance, unknown: String = "Not set") -> String {
    let when = p.recordedAt.map { " · \($0.formatted(.dateTime.day().month(.abbreviated)))" } ?? ""
    switch p.source {
    case .unknown: return unknown
    case .appleHealth: return "Apple Health\(when)"
    case .measuredTest: return "Recorded test\(when)"
    case .legacyUnverified: return "Earlier version — please confirm"
    default: return "Entered by you\(when)"
    }
}

private struct CyBarEdit<Editor: View>: ViewModifier {
    let id: String
    @ViewBuilder var editor: () -> Editor
    @State private var editing = false
    func body(content: Content) -> some View {
        content
            .toolbar { ToolbarItem(placement: .primaryAction) { Button("Edit") { editing = true }.font(.body.weight(.semibold)).foregroundStyle(CyTheme.ink).accessibilityIdentifier(id) } }
            .navigationDestination(isPresented: $editing) { editor() }
    }
}

struct CyProfileHeartRate: View {
    @EnvironmentObject private var store: Store
    var body: some View {
        let p = store.profile
        CyProfilePage(title: "Heart rate") {
            CyGroupLabel(text: "VALUES")
            CyValueRow(title: "Resting", source: p.restHR == nil ? "Not set" : cySource(p.provenance(.restHR)), value: p.restHR.map { "\($0) bpm" } ?? "—", id: "hrResting")
            CyValueRow(title: "Maximum", source: p.maxHR != nil ? cySource(p.provenance(.maxHR)) : (p.maxHRForZones != nil ? "Estimated from age" : "Not set"),
                       value: p.maxHRForZones.map { "\($0) bpm" } ?? "—", id: "hrMaximum")
            CyValueRow(title: "Threshold", source: p.lthr == nil ? "Not set" : "Entered by you", value: p.lthr.map { "\($0) bpm" } ?? "—", id: "hrThreshold")
            CyGroupLabel(text: "ZONE METHOD")
            CyChoiceBar(options: [(RiderProfile.HRZoneMethod.maxHR, "Max HR"), (RiderProfile.HRZoneMethod.lthr, "Threshold")],
                        selection: Binding(get: { store.profile.hrZoneMethod }, set: { v in store.updateProfile { $0.hrZoneMethod = v } }))
                .accessibilityIdentifier("hrZoneMethod")
            if p.hrZoneMethod == .lthr, p.lthr == nil {
                Text("No threshold heart rate yet; until then zones use maximum heart rate.").font(CyDyn.f(13.5)).foregroundStyle(CyTheme.ink2)
                    .fixedSize(horizontal: false, vertical: true).padding(.top, 8)
            }
            HStack { CyGroupLabel(text: "ZONES"); Spacer(); Text("calculated").font(CyDyn.f(12)).foregroundStyle(CyTheme.ink2).padding(.top, 10) }
            if let zones = p.hrZones {
                ForEach(Array(zones.enumerated()), id: \.offset) { i, z in
                    CyZoneRow(n: i + 1, name: String(HrZones.names[i].dropFirst(3)), range: "\(z.lo)–\(z.hi.map(String.init) ?? "∞")")
                }
            } else {
                Text("Unknown — no maximum or threshold heart rate yet.").font(CyDyn.f(14)).foregroundStyle(CyTheme.ink2).accessibilityIdentifier("hrZonesUnknown")
            }
        }
        .modifier(CyBarEdit(id: "hrEdit") { HeartRatePage() })
        .accessibilityIdentifier("profileHeartRatePage")
    }
}

struct CyProfilePower: View {
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var device: DeviceLink
    var body: some View {
        let p = store.profile
        CyProfilePage(title: "Power") {
            CyGroupLabel(text: "FTP")
            CyValueRow(title: "Functional threshold power", source: p.ftpKnown ? p.ftpSource.title : "Rides use heart rate and effort until an FTP is known",
                       value: p.ftpKnown ? p.ftpDisplay : "Unknown", id: "ftpValue")
            CyValueRow(title: "Power meter", source: "Read only · unverified", value: meterText, id: "powerMeter")
            if p.ftpKnown {
                HStack { CyGroupLabel(text: "POWER ZONES"); Spacer(); Text("calculated from FTP").font(CyDyn.f(12)).foregroundStyle(CyTheme.ink2).padding(.top, 10) }
                ForEach(Array(p.powerZones.enumerated()), id: \.offset) { i, z in
                    CyZoneRow(n: i + 1, name: String(PowerZones.names[i].dropFirst(3)), range: "\(z.lo)–\(z.hi.map(String.init) ?? "∞") W")
                }
            } else {
                CyGroupLabel(text: "POWER ZONES")
                Text("Not shown: there is no FTP to calculate them from.").font(CyDyn.f(14)).foregroundStyle(CyTheme.ink2).accessibilityIdentifier("powerZonesUnknown")
            }
            Text("“Tested” appears only after a recorded FTP test with verified power. Unknown stays unknown.")
                .font(CyDyn.f(13.5)).foregroundStyle(CyTheme.ink2).fixedSize(horizontal: false, vertical: true).padding(.top, 14)
        }
        .modifier(CyBarEdit(id: "powerEdit") { PowerCyclingPage() })
        .accessibilityIdentifier("profilePowerPage")
    }
    private var meterText: String {
        guard device.state == .ready, let l = device.live else { return device.remembered ? "Not connected" : "Not configured" }
        switch l.meterLink { case 4: return "Connected"; case 1: return "Not paired"; case 2: return "Searching"; case 3: return "Connecting"; case 5: return "Reconnecting"; default: return "Off" }
    }
}

/// Sheet P05 C3 — Cycling & sources: the cadence range, the bike's parameters and the one heart-rate source setting.
/// Same stored values and the same calls as PowerCyclingPage and HeartRatePage, which the existing app keeps.
struct CyProfileCyclingSources: View {
    @EnvironmentObject private var store: Store
    @State private var bike = ""
    @State private var wheel = ""
    @State private var loaded = false
    @FocusState private var focus: Int?

    var body: some View {
        CyProfilePage(title: "Cycling & sources") {
            CyGroupLabel(text: "CADENCE PREFERENCE")
            stepRow("Low", value: store.profile.cadenceLow, id: "cadenceLow", range: 50...110) { v in store.updateProfile { $0.cadenceLow = min(v, $0.cadenceHigh - 5) } }
            stepRow("High", value: store.profile.cadenceHigh, id: "cadenceHigh", range: 60...130) { v in store.updateProfile { $0.cadenceHigh = max(v, $0.cadenceLow + 5) } }
            CyGroupLabel(text: "CYCLING PARAMETERS")
            fieldRow("Bike name", note: "Optional") {
                TextField("Not set", text: $bike).multilineTextAlignment(.trailing).font(CyDyn.f(16, .semibold)).foregroundStyle(CyTheme.ink)
                    .focused($focus, equals: 1).submitLabel(.done)
                    .onSubmit { focus = nil; store.updateProfile { $0.bikeName = bike.trimmingCharacters(in: .whitespaces).isEmpty ? nil : bike.trimmingCharacters(in: .whitespaces) } }
                    .accessibilityIdentifier("bikeName")
            }
            fieldRow("Wheel circumference", note: "Used by a speed sensor · millimetres") {
                HStack(spacing: 8) {
                    TextField("2096", text: $wheel).keyboardType(.numberPad).multilineTextAlignment(.trailing).font(CyDyn.f(16, .semibold)).foregroundStyle(CyTheme.ink)
                        .focused($focus, equals: 2).frame(width: 70).accessibilityLabel("Wheel circumference in millimetres").accessibilityIdentifier("wheelMm")
                    if focus == 2 {
                        Button("Done") { focus = nil; if let v = Int(wheel), (1000...2600).contains(v) { store.updateProfile { $0.wheelMm = v } } else { wheel = "\(store.profile.wheelMm)" } }
                            .font(.body.weight(.semibold)).foregroundStyle(CyTheme.ink).frame(minHeight: CyTheme.minTap).accessibilityIdentifier("wheelDone")
                    }
                }
            }
            CyGroupLabel(text: "MEASUREMENT SOURCES")
            Text("Heart rate — preferred").font(CyDyn.f(16.5, .semibold)).foregroundStyle(CyTheme.ink)
            Text("One setting; the BikeComputer follows it.").font(CyDyn.f(13.5)).foregroundStyle(CyTheme.ink2).padding(.bottom, 8)
            CyChoiceBar(options: [(AppSettings.HRPref.watch, "Apple Watch first"), (AppSettings.HRPref.strap, "Strap first")], selection: $store.settings.hrPref)
                .accessibilityIdentifier("hrSource")
        }
        .accessibilityIdentifier("profileCyclingPage")
        .onAppear { guard !loaded else { return }; loaded = true; bike = store.profile.bikeName ?? ""; wheel = "\(store.profile.wheelMm)" }
    }

    private func stepRow(_ title: String, value: Int, id: String, range: ClosedRange<Int>, set: @escaping (Int) -> Void) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Text(title).font(CyDyn.f(16.5, .semibold)).foregroundStyle(CyTheme.ink)
                Spacer(minLength: 8)
                Text("\(value) rpm").font(CyDyn.f(16, .semibold)).monospacedDigit().foregroundStyle(CyTheme.ink)
                Stepper("\(title) cadence", value: Binding(get: { value }, set: set), in: range, step: 5).labelsHidden()
            }
            .frame(minHeight: 60)
            Rectangle().fill(CyTheme.line).frame(height: 1).accessibilityHidden(true)
        }
        .accessibilityElement(children: .contain).accessibilityIdentifier(id)
    }
    private func fieldRow<V: View>(_ title: String, note: String, @ViewBuilder _ value: () -> V) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(CyDyn.f(16.5, .semibold)).foregroundStyle(CyTheme.ink)
                    Text(note).font(CyDyn.f(13.5)).foregroundStyle(CyTheme.ink2)
                }
                Spacer(minLength: 8)
                value()
            }
            .frame(minHeight: 60)
            Rectangle().fill(CyTheme.line).frame(height: 1).accessibilityHidden(true)
        }
    }
}
