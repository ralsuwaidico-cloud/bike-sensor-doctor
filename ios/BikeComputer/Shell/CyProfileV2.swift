import SwiftUI

// Profile v2.0 — six-section architecture (information architecture APPROVED 15 Nov 2026; visual design PENDING REVIEW —
// product/profile/v20/PROFILE_V20_DESIGN.md, sheets P02–P08). Reached only from the Home avatar; Home stays the marked
// tab. Open surface: no cards, hairline dividers, 24-pt margins, rows of at least 60 pt (landing rows 74 pt).
//
// One athlete record: every row reads the existing Store and opens the EXISTING editor for that value — nothing is
// edited in two places and no second model exists. The editors behind the rows still have their older look.
// Shared code for both apps; switched on by `CyProduct.redesign`. PROVISIONAL where the design is: the visual treatment.
// Rows whose function the app does not have say "Not available"; in Lab, devices and Apple Health say why they are off.

private enum CyP2 {
    static let margin: CGFloat = 24
    // sizes from the sheets at the standard text size; they follow the athlete's iPhone text-size setting (CyDyn)
    static var title: Font { CyDyn.f(16.5, .semibold) }
    static var summary: Font { CyDyn.f(13.5) }
}

/// What a row does, shown the same way everywhere (one meaning each).
enum CyProfileRowKind { case opens, plan, train, notAvailable, fact }

struct CyProfileRow<Destination: View>: View {
    let title: String
    var summary: String? = nil
    var icon: String? = nil
    var kind: CyProfileRowKind = .opens
    var minHeight: CGFloat = 60
    var id: String
    @ViewBuilder var destination: () -> Destination

    var body: some View {
        Group {
            switch kind {
            case .notAvailable, .fact: label
            default: NavigationLink { destination() } label: { label }.buttonStyle(.plain)
            }
        }
        .overlay(alignment: .bottom) { CyHairline() }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(id)
    }
    private var label: some View {
        HStack(spacing: 14) {
            if let icon { Image(systemName: icon).font(CyDyn.f(20)).foregroundStyle(CyTheme.ink).frame(minWidth: 28).accessibilityHidden(true) }
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(CyP2.title).foregroundStyle(kind == .notAvailable ? CyTheme.ink2 : CyTheme.ink).fixedSize(horizontal: false, vertical: true)
                if let summary, !summary.isEmpty { Text(summary).font(CyP2.summary).foregroundStyle(CyTheme.ink2).fixedSize(horizontal: false, vertical: true) }
            }
            Spacer(minLength: 8)
            switch kind {
            case .plan: tag("Plan"); chevron
            case .train: tag("Train"); chevron
            case .notAvailable: tag("Not available")
            case .fact: EmptyView()
            case .opens: chevron
            }
        }
        .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .leading)
        .contentShape(Rectangle())
    }
    private var chevron: some View { Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(CyTheme.ink3).accessibilityHidden(true) }
    private func tag(_ t: String) -> some View {
        Text(t).font(CyDyn.f(11.5, .semibold)).fixedSize().foregroundStyle(CyTheme.ink2)
            .padding(.horizontal, 7).padding(.vertical, 3).overlay(RoundedRectangle(cornerRadius: 6).stroke(CyTheme.line, lineWidth: 1))
    }
}
extension CyProfileRow where Destination == EmptyView {
    init(title: String, summary: String? = nil, kind: CyProfileRowKind, id: String) {
        self.init(title: title, summary: summary, icon: nil, kind: kind, minHeight: 60, id: id) { EmptyView() }
    }
}

private struct CyHairline: View { var body: some View { Rectangle().fill(CyTheme.line).frame(height: 1).accessibilityHidden(true) } }

/// A Profile page: large title, optional one-line purpose, rows separated by hairlines, clear of the dock.
struct CyProfilePage<Content: View>: View {
    let title: String
    var purpose: String? = nil
    @ViewBuilder var content: () -> Content
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text(title).font(CyDyn.f(32, .bold)).foregroundStyle(CyTheme.ink).fixedSize(horizontal: false, vertical: true).accessibilityAddTraits(.isHeader)
                if let purpose, !purpose.isEmpty { Text(purpose).font(CyP2.summary).foregroundStyle(CyTheme.ink2).fixedSize(horizontal: false, vertical: true).padding(.top, 4) }
                Spacer().frame(height: 14)
                content()
            }
            .padding(.horizontal, CyP2.margin).padding(.top, 8).padding(.bottom, CyTheme.dockClearance)
            .frame(maxWidth: CyTheme.maxContentWidth).frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(CyTheme.canvas.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Rows of one group, each closed by a hairline.
struct CyProfileRows<Content: View>: View {
    @ViewBuilder var content: () -> Content
    var body: some View { VStack(alignment: .leading, spacing: 0) { content() } }
}

// MARK: - Landing

struct CyProfileLanding: View {
    /// Returns to Home (Home stays the marked tab while Profile is shown).
    let onBack: () -> Void
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var hub: SensorHub

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Button(action: onBack) {
                        HStack(spacing: 6) { Image(systemName: "chevron.left").font(.body.weight(.semibold)); Text("Home").font(.body.weight(.medium)) }
                            .foregroundStyle(CyTheme.ink).frame(minHeight: CyTheme.minTap).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain).accessibilityLabel("Back to Home").accessibilityIdentifier("profileBack")
                    HStack(spacing: 16) {
                        ZStack {
                            Circle().stroke(CyTheme.ink, lineWidth: 1.5).frame(width: 60, height: 60)
                            Text(initials).font(CyDyn.f(20, .semibold)).foregroundStyle(CyTheme.ink2).lineLimit(1).minimumScaleFactor(0.5).frame(width: 50)
                        }
                        .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(store.profile.name.isEmpty ? "Athlete" : store.profile.name).font(CyDyn.f(26, .bold)).foregroundStyle(CyTheme.ink).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                            Text(identityLine).font(CyDyn.f(15)).foregroundStyle(CyTheme.ink2).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(.top, 14).padding(.bottom, 10)
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("profileIdentity")
                    CyProfileRows {
                        CyProfileRow(title: "Athlete Profile", summary: athleteLine, icon: "person", minHeight: 74, id: "profileSectionA") { CyProfileAthlete() }
                        CyProfileRow(title: "Training Setup", summary: setupLine, icon: "slider.horizontal.3", minHeight: 74, id: "profileSectionB") { CyProfileSetup() }
                        CyProfileRow(title: "Performance Settings", summary: performanceLine, icon: "waveform.path.ecg", minHeight: 74, id: "profileSectionC") { CyProfilePerformance() }
                        CyProfileRow(title: "Devices & Connections", summary: devicesLine, icon: "iphone", minHeight: 74, id: "profileSectionD") { CyProfileDevices() }
                        CyProfileRow(title: "App Preferences", summary: preferencesLine, icon: "sun.max", minHeight: 74, id: "profileSectionE") { CyProfilePreferences() }
                        CyProfileRow(title: "Data, Help & About", summary: "Stored on this iPhone · version \(AppInfo.label)", icon: "shield", minHeight: 74, id: "profileSectionF") { CyProfileData() }
                    }
                }
                .padding(.horizontal, CyP2.margin).padding(.top, 4).padding(.bottom, CyTheme.dockClearance)
                .frame(maxWidth: CyTheme.maxContentWidth).frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(CyTheme.canvas.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .accessibilityIdentifier("profileLanding")
        }
    }

    private var initials: String { let p = store.profile.name.split(separator: " "); return p.isEmpty ? "A" : p.prefix(2).map { String($0.prefix(1)).uppercased() }.joined() }
    private var identityLine: String {
        let p = store.profile
        return p.trainingMode == .hybrid ? "Hybrid athlete · \(p.priority.title.lowercased())" : "\(ProfileText.mode(p.trainingMode)) athlete"
    }
    private var athleteLine: String {
        let p = store.profile
        var parts = [ProfileText.mode(p.trainingMode)]
        if p.trainingMode.includesCycling { parts.append("riding \(ProfileText.level(p.level).lowercased())") }
        if p.trainingMode.includesLifting { parts.append("lifting \(ProfileText.strengthLevel(store.strengthPrefs.experience ?? .beginner).lowercased())") }
        return parts.joined(separator: " · ")
    }
    private var setupLine: String {
        let e = store.equipment
        let eq = e.isProvisional ? "Equipment not set" : e.owned.isEmpty ? "Bodyweight only" : "\(e.owned.count) equipment item\(e.owned.count == 1 ? "" : "s")"
        return store.strengthPrefs.prefersSupersets == true ? "\(eq) · supersets" : eq
    }
    private var performanceLine: String {
        let p = store.profile
        var parts: [String] = []
        if p.trainingMode.includesCycling { parts.append("FTP \(p.ftpDisplay) · \(p.ftpSource.title.lowercased())") }
        parts.append(p.maxHRForZones.map { "max HR \($0)\(p.maxHRIsEstimate ? " estimated" : "")" } ?? "heart-rate zones not set")
        return parts.joined(separator: " · ")
    }
    private var devicesLine: String {
        if CycliftLab.isLab { return "Not used in Cyclift Lab" }
        let n = hub.deviceStates.values.filter { $0.state.isConnectedOrBetter }.count
        return n == 0 ? "Nothing connected" : "\(n) connected"
    }
    private var preferencesLine: String {
        "\(store.settings.units == .metric ? "Metric" : "Imperial") · \(CyThemeState.available ? CyProfilePreferences.themeLine(CyThemeState.shared.preference) : store.settings.appearance.title)"
    }
}

// MARK: - A · Athlete Profile

struct CyProfileAthlete: View {
    @EnvironmentObject private var store: Store
    var body: some View {
        CyProfilePage(title: "Athlete Profile", purpose: "Who you are as an athlete.") {
            CyProfileRows {
                CyProfileRow(title: "Personal details", summary: store.profile.name.isEmpty ? "Name not set" : store.profile.name, id: "profilePersonal") { CyProfilePersonalDetails() }
                CyProfileRow(title: "My activities", summary: "Choosing activities is designed, not in the app yet", kind: .notAvailable, id: "profileActivities")
                CyProfileRow(title: "Athlete type", summary: ProfileText.mode(store.profile.trainingMode), id: "profileType") { CyProfileTypeExperience() }
                CyProfileRow(title: "Experience", summary: experienceLine, id: "profileExperience") { CyProfileTypeExperience() }
                if store.profile.trainingMode == .hybrid {
                    CyProfileRow(title: "Hybrid balance", summary: store.profile.priority.title, id: "profileBalance") { CyProfileTypeExperience() }
                }
            }
        }
    }
    private var experienceLine: String {
        let p = store.profile
        var parts: [String] = []
        if p.trainingMode.includesCycling { parts.append("Riding: \(ProfileText.level(p.level).lowercased())") }
        if p.trainingMode.includesLifting { parts.append("Lifting: \(ProfileText.strengthLevel(store.strengthPrefs.experience ?? .beginner).lowercased())") }
        return parts.joined(separator: " · ")
    }
}

// MARK: - B · Training Setup

struct CyProfileSetup: View {
    @EnvironmentObject private var store: Store
    @State private var planPreview: PreviewRef? = nil
    @State private var equipmentAtOpen: EquipmentProfile? = nil
    var body: some View {
        CyProfilePage(title: "Training Setup", purpose: "What you train with and how you prefer to train.") {
            CyProfileRows {
                CyProfileRow(title: "Equipment & restrictions", summary: store.equipment.owned.isEmpty ? "Bodyweight only" : "\(store.equipment.owned.count) items owned", id: "profileEquipment") {
                    // the existing equipment editor; on close the edit becomes one plan proposal (preview → approve → undo)
                    CyProfileEquipment()
                        .onAppear { if equipmentAtOpen == nil { equipmentAtOpen = store.equipment } }
                        .onDisappear { if let old = equipmentAtOpen { equipmentAtOpen = nil; planPreview = store.proposeEquipmentEdit(from: old) } }
                }
                CyProfileRow(title: "Strength preferences", summary: store.strengthPrefs.prefersSupersets == true ? "Supersets on" : "Split, goal, supersets", id: "profilePreferences") { CyProfileStrengthPrefs() }
                CyProfileRow(title: "Recovery, pauses & health check", summary: HealthSafetyPage.summary(store.profile).isEmpty ? "No pause" : HealthSafetyPage.summary(store.profile), id: "profileHealthSafety") { CyProfileRecoveryPauses() }
                CyProfileRow(title: "Goals", summary: ProfileText.goals(store.profile), kind: .plan, id: "profileGoal") { GoalsPage() }
                CyProfileRow(title: "Training schedule", summary: "Weekly calendar and recurring plan", kind: .plan, id: "profileWeek") { WeekPage() }
                CyProfileRow(title: "Saved routines", summary: "\(store.templates.count) routine\(store.templates.count == 1 ? "" : "s")", kind: .plan, id: "profileRoutines") { TemplatesView() }
                CyProfileRow(title: "My exercises", summary: "\(store.customExercises.count) of your own", kind: .train, id: "profileExercises") { MyExercisesView() }
            }
        }
        .sheet(item: $planPreview) { r in PlanChangeSheet(proposalId: r.id) }
    }
}

// MARK: - C · Performance Settings

struct CyProfilePerformance: View {
    @EnvironmentObject private var store: Store
    var body: some View {
        CyProfilePage(title: "Performance Settings", purpose: "The numbers your zones are calculated from.") {
            CyProfileRows {
                CyProfileRow(title: "Heart rate", summary: store.profile.maxHRForZones.map { "Max \($0)\(store.profile.maxHRIsEstimate ? " · estimated" : "")" } ?? "Zones not set", id: "profileHR") { CyProfileHeartRate() }
                CyProfileRow(title: "Power", summary: "FTP \(store.profile.ftpDisplay) · \(store.profile.ftpSource.title)", id: "profileFTP") { CyProfilePower() }
                CyProfileRow(title: "Cadence", summary: "\(store.profile.cadenceLow)–\(store.profile.cadenceHigh) rpm", id: "profileCadence") { CyProfileCyclingSources() }
                CyProfileRow(title: "Cycling parameters", summary: "Wheel \(store.profile.wheelMm) mm", id: "profileCycling") { CyProfileCyclingSources() }
                CyProfileRow(title: "Measurement sources", summary: "Preferred heart-rate source", id: "profileSources") { CyProfileCyclingSources() }
            }
        }
    }
}

// MARK: - D · Devices & Connections

/// Sheet P06 D. The rows and every page behind them: Shell/CyProfileDevices.swift.
struct CyProfileDevices: View {
    var body: some View {
        CyProfilePage(title: "Devices & Connections", purpose: CycliftLab.isLab ? "Cyclift Lab is a demonstration: it connects to nothing." : "What Cyclift is connected to.") {
            CyProfileRows {
                if CycliftLab.isLab { CyProfileDeviceFamiliesLab() } else { CyProfileDeviceFamilies() }
            }
        }
        .accessibilityIdentifier("profileDevicesPage")
    }
}

// MARK: - E · App Preferences

struct CyProfilePreferences: View {
    @EnvironmentObject private var store: Store
    @ObservedObject private var theme = CyThemeState.shared

    static func themeLine(_ p: CyThemePreference) -> String {
        p.mode == .system ? "Follows iOS" : p.resolved(systemIsDark: false).title
    }
    var body: some View {
        CyProfilePage(title: "App Preferences", purpose: "How Cyclift looks and behaves.") {
            CyProfileRows {
                if CyThemeState.available {
                    CyProfileRow(title: "Appearance", summary: CyProfilePreferences.themeLine(theme.preference), id: "profileAppearance") { CyProfileThemes() }
                } else {
                    CyProfileRow(title: "Appearance", summary: store.settings.appearance.title, id: "profileAppearance") { SettingsPage() }
                }
                CyProfileRow(title: "Language", summary: "English", kind: .fact, id: "profileLanguage")
                CyProfileRow(title: "Arabic", summary: "Designed, not in the app yet", kind: .notAvailable, id: "profileArabic")
                CyProfileRow(title: "Units", summary: store.settings.units == .metric ? "Metric" : "Imperial", id: "profileUnits") { CyProfileUnits() }
                CyProfileRow(title: "Notifications", summary: "Ride recording notice", id: "profileNotifications") { CyProfileNotificationsDisplay() }
                CyProfileRow(title: "Coach", summary: "Rules-based · never changes the plan without your approval", id: "profileCoach") { CyProfileCoachPreferences() }
                CyProfileRow(title: "Training display", summary: "Keep screen on, ride tiles, ride display", id: "profileDisplay") { CyProfileNotificationsDisplay() }
                CyProfileRow(title: "Accessibility", summary: "Follows your iPhone's text size, contrast and motion settings", id: "profileAccessibility") { CyProfileNotificationsDisplay() }
            }
        }
    }
}

/// The six themes and "follow iOS" — the one place the athlete chooses (Profile → App Preferences → Appearance).
struct CyProfileThemes: View {
    @ObservedObject private var theme = CyThemeState.shared
    private let store = CyThemePreferenceStore()
    private func choose(_ p: CyThemePreference?) { if let p { theme.choose(p); store.save(p) } }
    var body: some View {
        CyProfilePage(title: "Appearance", purpose: "Colour values are provisional until approved.") {
            CyProfileRows {
                ForEach(CyThemeID.allCases, id: \.self) { t in
                    Button { choose(CyThemePreference.always(t)) } label: { row(t.title, t.isDark ? "Dark" : "Light", theme.preference == CyThemePreference.always(t)) }
                        .buttonStyle(.plain).accessibilityIdentifier("theme-\(t.rawValue)")
                }
                Button { choose(CyThemePreference.followSystem()) } label: { row("Follow iOS", "Arctic in light, Obsidian in dark", theme.preference.mode == .system) }
                    .buttonStyle(.plain).accessibilityIdentifier("theme-system")
            }
        }
    }
    private func row(_ title: String, _ sub: String, _ on: Bool) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(CyDyn.f(16.5, .semibold)).foregroundStyle(CyTheme.ink)
                Text(sub).font(CyDyn.f(13.5)).foregroundStyle(CyTheme.ink2).fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            if on { Image(systemName: "checkmark").font(.body.weight(.semibold)).foregroundStyle(CyTheme.ink).accessibilityLabel("selected") }
        }
        .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading).contentShape(Rectangle())
    }
}

// MARK: - F · Data, Help & About

struct CyProfileData: View {
    var body: some View {
        // Sheet P08. Export and Delete keep their existing, protected controls (the page behind "profileSettings");
        // they are reached from their own rows here and are not re-implemented.
        CyProfilePage(title: "Data, Help & About", purpose: CycliftLab.isLab ? "Cyclift Lab holds demo data only, on this iPhone." : "Your data is stored only on this iPhone.") {
            CyGroupLabel(text: "YOUR DATA")
            CyProfileRows {
                CyProfileRow(title: "Where your data lives", summary: "Only on this iPhone", id: "profileDataWhere") { CyProfileDataLives() }
                CyProfileRow(title: "Export my data", summary: "One file with everything", id: "profileExport") { SettingsPage() }
                CyProfileRow(title: "Permissions", summary: CycliftLab.isLab ? "Not used in Cyclift Lab" : "Bluetooth · location · Health · notifications", id: "profilePermissions") { CyDevicePhonePage(permissions: true) }
                CyProfileRow(title: "Delete all data", summary: "Asks you to confirm and states what is removed", id: "profileSettings") { SettingsPage() }
            }
            CyGroupLabel(text: "HELP")
            CyProfileRows {
                CyProfileRow(title: "How Cyclift works", summary: "Plan, numbers, devices, support", id: "profileHelp") { HelpSupportPage() }
                // the existing diagnostics page, as it is (sheet F: "Diagnostics — what the phone is receiving")
                CyProfileRow(title: "Diagnostics", summary: "What the phone is receiving", id: "profileDiagnostics") { PipelineDiagnosticsView() }
                if let mail = SupportInfo.mailURL {
                    // leaves the app for Mail (the same link as the Help page's "Contact support")
                    Link(destination: mail) {
                        HStack(spacing: 10) {
                            Text("Contact support").font(CyDyn.f(16.5, .semibold)).foregroundStyle(CyTheme.ink)
                            Spacer(minLength: 8)
                            Image(systemName: "arrow.up.right").font(.footnote.weight(.semibold)).foregroundStyle(CyTheme.ink3).accessibilityHidden(true)
                        }
                        .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading).contentShape(Rectangle())
                    }
                    .overlay(alignment: .bottom) { Rectangle().fill(CyTheme.line).frame(height: 1).accessibilityHidden(true) }
                    .accessibilityIdentifier("profileSupport")
                }
            }
            CyGroupLabel(text: "ABOUT")
            CyProfileRows {
                CyProfileRow(title: "Privacy policy", id: "profilePrivacy") { LegalView(kind: .privacy) }
                CyProfileRow(title: "Terms of use", id: "profileTerms") { LegalView(kind: .terms) }
                CyProfileRow(title: "Version", summary: "Cyclift \(AppInfo.label)", kind: .fact, id: "profileVersion")
            }
        }
    }
}

/// Sheet P08 F1 — says plainly where the data is and what does not exist.
struct CyProfileDataLives: View {
    var body: some View {
        CyProfilePage(title: "Where your data lives") {
            Text("Everything stays on this iPhone.").font(CyDyn.f(18, .semibold)).foregroundStyle(CyTheme.ink).fixedSize(horizontal: false, vertical: true)
            Text("Profile, plan, rides, strength sessions and routines are stored only inside Cyclift on this phone. There is no account and no copy on a server.")
                .font(CyDyn.f(13.5)).foregroundStyle(CyTheme.ink2).fixedSize(horizontal: false, vertical: true).padding(.top, 8).padding(.bottom, 6)
            CyProfileRows {
                CyProfileRow(title: "Cloud backup", kind: .notAvailable, id: "profileBackup")
                CyProfileRow(title: "Restore or import", kind: .notAvailable, id: "profileRestore")
            }
            Text("If this iPhone is lost or the app is deleted, your Cyclift data is gone unless you exported it or your iPhone backup includes it.")
                .font(CyDyn.f(13.5)).foregroundStyle(CyTheme.ink2).fixedSize(horizontal: false, vertical: true).padding(.top, 14).padding(.bottom, 6)
            CyProfileRows {
                CyProfileRow(title: "Export my data", summary: "One file you can save or share. It cannot be imported back yet.", id: "profileExportFromWhere") { SettingsPage() }
            }
        }
        .accessibilityIdentifier("profileDataLivesPage")
    }
}
