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
                    Text(title).font(.system(size: 16.5, weight: .semibold)).foregroundStyle(CyTheme.ink)
                    Text(source).font(.system(size: 13.5)).foregroundStyle(CyTheme.ink2).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Text(value).font(.system(size: 16, weight: .semibold)).monospacedDigit().foregroundStyle(CyTheme.ink)
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
            Text("Z\(n)").font(.system(size: 11, weight: .heavy)).foregroundStyle(CyTheme.ink)
                .padding(.horizontal, 6).padding(.vertical, 3)
                .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).stroke(CyTheme.ink, lineWidth: 1.2))
            Text(name).font(.system(size: 15)).foregroundStyle(CyTheme.ink2)
            Spacer(minLength: 8)
            Text(range).font(.system(size: 14)).monospacedDigit().foregroundStyle(CyTheme.ink2)
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
                Text("No threshold heart rate yet; until then zones use maximum heart rate.").font(.system(size: 13.5)).foregroundStyle(CyTheme.ink2)
                    .fixedSize(horizontal: false, vertical: true).padding(.top, 8)
            }
            HStack { CyGroupLabel(text: "ZONES"); Spacer(); Text("calculated").font(.system(size: 12)).foregroundStyle(CyTheme.ink2).padding(.top, 10) }
            if let zones = p.hrZones {
                ForEach(Array(zones.enumerated()), id: \.offset) { i, z in
                    CyZoneRow(n: i + 1, name: String(HrZones.names[i].dropFirst(3)), range: "\(z.lo)–\(z.hi.map(String.init) ?? "∞")")
                }
            } else {
                Text("Unknown — no maximum or threshold heart rate yet.").font(.system(size: 14)).foregroundStyle(CyTheme.ink2).accessibilityIdentifier("hrZonesUnknown")
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
                HStack { CyGroupLabel(text: "POWER ZONES"); Spacer(); Text("calculated from FTP").font(.system(size: 12)).foregroundStyle(CyTheme.ink2).padding(.top, 10) }
                ForEach(Array(p.powerZones.enumerated()), id: \.offset) { i, z in
                    CyZoneRow(n: i + 1, name: String(PowerZones.names[i].dropFirst(3)), range: "\(z.lo)–\(z.hi.map(String.init) ?? "∞") W")
                }
            } else {
                CyGroupLabel(text: "POWER ZONES")
                Text("Not shown: there is no FTP to calculate them from.").font(.system(size: 14)).foregroundStyle(CyTheme.ink2).accessibilityIdentifier("powerZonesUnknown")
            }
            Text("“Tested” appears only after a recorded FTP test with verified power. Unknown stays unknown.")
                .font(.system(size: 13.5)).foregroundStyle(CyTheme.ink2).fixedSize(horizontal: false, vertical: true).padding(.top, 14)
        }
        .modifier(CyBarEdit(id: "powerEdit") { PowerCyclingPage() })
        .accessibilityIdentifier("profilePowerPage")
    }
    private var meterText: String {
        guard device.state == .ready, let l = device.live else { return device.remembered ? "Not connected" : "Not configured" }
        switch l.meterLink { case 4: return "Connected"; case 1: return "Not paired"; case 2: return "Searching"; case 3: return "Connecting"; case 5: return "Reconnecting"; default: return "Off" }
    }
}
