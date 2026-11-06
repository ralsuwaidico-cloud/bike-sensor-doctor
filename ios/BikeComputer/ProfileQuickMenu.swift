import SwiftUI
import UIKit

// MARK: - Checkpoint C correction pass (owner 6 Nov addendum): the Profile Quick Menu.
// The Home avatar opens a floating panel anchored under it (Home stays visible, dimmed). Each row opens its own
// destination on Home's navigation stack; the header (or View profile) opens the Profile tab. The menu never writes:
// values come from `ProfileMenuModel.swift`, edits go to the existing editors (preview → approve → undo where the
// plan is affected). Dismissal: outside tap, the avatar again, Close, the VoiceOver escape gesture, or a tab change.

enum ProfileMenuDestination: Hashable { case myProfile, preferences, connections, settings, help }

struct ProfileQuickMenu: View {
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var hub: SensorHub
    let close: () -> Void
    let viewProfile: () -> Void
    let open: (ProfileMenuDestination) -> Void
    @AccessibilityFocusState private var headerFocused: Bool
    @Environment(\.dynamicTypeSize) private var dts

    var body: some View {
        let h = store.profileMenuHeader()
        let connected = hub.deviceStates.values.filter { $0.state.isConnectedOrBetter }.count
        let lines = store.profileMenuLines(connectedDevices: connected, healthReadsOn: store.settings.healthReads.anyEnabled)
        GeometryReader { geo in
            ZStack(alignment: .topTrailing) {
                // dim layer: tapping outside (including where the avatar is) closes the menu
                Color.black.opacity(0.22)
                    .ignoresSafeArea(edges: .bottom)       // the header (date + avatar) stays undimmed and tappable
                    .contentShape(Rectangle())
                    .onTapGesture(perform: close)
                    .accessibilityHidden(true)
                    .accessibilityIdentifier("profileMenuScrim")
                // run 172: the panel hugs its rows; it scrolls only when the rows are taller than the space (large text)
                let rows = VStack(alignment: .leading, spacing: 0) {
                    header(h)
                    CyDivider().padding(.vertical, 6)
                    row("My profile", lines.profile, icon: "person.crop.circle", sport: nil, id: "menuMyProfile") { open(.myProfile) }
                    row("Goals & training preferences", lines.preferences, icon: "target", sport: .goal, id: "menuPreferences") { open(.preferences) }
                    row("Devices & connections", lines.connections, icon: "sensor.tag.radiowaves.forward", sport: .cycling, id: "menuConnections") { open(.connections) }
                    row("App settings", lines.settings, icon: "gearshape", sport: nil, id: "menuSettings") { open(.settings) }
                    row("Help & support", "How Cyclift works · version \(AppInfo.label)", icon: "questionmark.circle", sport: .insight, id: "menuHelp") { open(.help) }
                }
                .padding(12)
                let maxH = max(200, geo.size.height - 12)          // the space between the header and the dock
                ViewThatFits(in: .vertical) {
                    rows
                    ScrollView { rows }.frame(height: maxH)
                }
                .frame(width: min(360, geo.size.width - 2 * CyTheme.margin))
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: CyTheme.rCard, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: CyTheme.rCard, style: .continuous).stroke(CyTheme.line2, lineWidth: 1))
                .shadow(color: .black.opacity(0.16), radius: 24, y: 10)
                .padding(.top, 6).padding(.trailing, CyTheme.margin)
                .accessibilityElement(children: .contain)
                .accessibilityAddTraits(.isModal)
                .accessibilityAction(.escape, close)
                .accessibilityIdentifier("profileMenu")
            }
        }
        .onAppear { headerFocused = true }
    }

    private func header(_ h: ProfileMenuHeader) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Button(action: viewProfile) {
                HStack(spacing: 12) {
                    ZStack {
                        Circle().fill(CyTheme.cta).frame(width: 44, height: 44)
                        if h.initials.isEmpty { Image(systemName: "person.fill").foregroundStyle(CyTheme.ctaInk) }
                        else { Text(h.initials).font(CyType.bodyStrong).foregroundStyle(CyTheme.ctaInk) }
                    }
                    .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(h.name ?? "Name not set").font(CyType.section).foregroundStyle(h.name == nil ? CyTheme.ink3 : CyTheme.ink).fixedSize(horizontal: false, vertical: true)
                        Text(h.athleteType).font(CyType.secondary).foregroundStyle(CyTheme.ink2)
                        Text("View profile ›").font(CyType.captionSmall.weight(.semibold)).foregroundStyle(CyTheme.cta)
                    }
                    Spacer(minLength: 0)
                }
                .frame(minHeight: CyTheme.minTap).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(h.name ?? "Name not set"), \(h.athleteType). View profile")
            .accessibilityFocused($headerFocused)
            .accessibilityIdentifier("menuViewProfile")
            Button(action: close) {
                Image(systemName: "xmark").font(.footnote.weight(.bold)).foregroundStyle(CyTheme.ink2)
                    .frame(width: 30, height: 30).background(CyTheme.line2, in: Circle())
                    .frame(width: CyTheme.minTap, height: CyTheme.minTap).contentShape(Rectangle())
            }
            .buttonStyle(.plain).accessibilityLabel("Close menu").accessibilityIdentifier("profileMenuClose")
        }
    }

    private func row(_ title: String, _ sub: String, icon: String, sport: CySport?, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                CyIconBox(systemName: icon, sport: sport)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(CyType.bodyStrong).foregroundStyle(CyTheme.ink).fixedSize(horizontal: false, vertical: true).multilineTextAlignment(.leading)
                    Text(sub).font(CyType.captionSmall).foregroundStyle(CyTheme.ink2).fixedSize(horizontal: false, vertical: true).multilineTextAlignment(.leading)
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(CyTheme.ink3).accessibilityHidden(true)
            }
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(CyPressStyle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title). \(sub)")
        .accessibilityIdentifier(id)
    }
}

/// Light press feedback for the menu rows (opacity, no scale under Reduce Motion).
struct CyPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.6 : 1)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

// MARK: - Menu destinations

/// A read-only list of facts; each fact with an editor opens that existing editor.
struct ProfileFactsPage: View {
    @EnvironmentObject private var store: Store
    let title: String
    let identifier: String
    let footnote: String?
    let sections: (Store) -> [ProfileFactSection]
    @State private var equipmentAtOpen: EquipmentProfile? = nil
    @State private var planPreview: PreviewRef? = nil

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: CyTheme.sp3) {
                ForEach(sections(store)) { sec in
                    CyCaption(text: sec.title)
                    CyRowGroup {
                        ForEach(Array(sec.facts.enumerated()), id: \.element.id) { i, f in
                            if i > 0 { CyDivider() }
                            factRow(f)
                        }
                    }
                }
                if let n = footnote { Text(n).font(CyType.captionSmall).foregroundStyle(CyTheme.ink3).padding(.horizontal, 4).fixedSize(horizontal: false, vertical: true) }
            }
            .padding(.horizontal, CyTheme.margin).padding(.vertical, CyTheme.sp3).padding(.bottom, CyTheme.dockClearance)
            .frame(maxWidth: CyTheme.maxContentWidth).frame(maxWidth: .infinity)
        }
        .background(CyTheme.canvas)
        .navigationTitle(title).navigationBarTitleDisplayMode(.inline)
        .sheet(item: $planPreview) { r in PlanChangeSheet(proposalId: r.id) }
        .accessibilityIdentifier(identifier)
    }

    @ViewBuilder private func factRow(_ f: ProfileFact) -> some View {
        let content = HStack(alignment: .firstTextBaseline, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(f.title).font(CyType.body).foregroundStyle(CyTheme.ink).fixedSize(horizontal: false, vertical: true)
                if let n = f.note { Text(n).font(CyType.captionSmall).foregroundStyle(CyTheme.ink3).fixedSize(horizontal: false, vertical: true) }
            }
            Spacer(minLength: 8)
            Text(f.value).font(CyType.secondary).foregroundStyle(CyTheme.ink2).multilineTextAlignment(.trailing).fixedSize(horizontal: false, vertical: true)
            if f.edit != nil { Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(CyTheme.ink3).accessibilityHidden(true) }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
        .contentShape(Rectangle())
        let rowId = "fact-" + f.title.replacingOccurrences(of: " ", with: "-").replacingOccurrences(of: "/", with: "")
        if let e = f.edit {
            NavigationLink { editor(e) } label: { content }
                .buttonStyle(.plain)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(f.title), \(f.value)\(f.note.map { ", \($0)" } ?? ""). Edit")
                .accessibilityIdentifier(rowId)
        } else {
            content
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(f.title), \(f.value)\(f.note.map { ", \($0)" } ?? "")")
                .accessibilityIdentifier(rowId)
        }
    }

    @ViewBuilder private func editor(_ e: ProfileFact.Edit) -> some View {
        switch e {
        case .personal: PersonalPage()
        case .typeExperience: TypeExperiencePage()
        case .goals: GoalsPage()
        case .week: WeekPage()
        case .preferences: TrainingPreferencesPage()
        case .strengthProgramming: StrengthPrefsPage()
        case .ftp: PowerCyclingPage()
        case .heartRate: HeartRatePage()
        case .equipment:
            // the same edit-then-propose flow as Profile › Equipment (shared Store.proposeEquipmentEdit)
            EquipmentPage()
                .onAppear { if equipmentAtOpen == nil { equipmentAtOpen = store.equipment } }
                .onDisappear { if let old = equipmentAtOpen { equipmentAtOpen = nil; planPreview = store.proposeEquipmentEdit(from: old) } }
        }
    }
}

/// Help & Support: how the app works, from what it actually does; the version; the real support links.
struct HelpSupportPage: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: CyTheme.sp3) {
                topic("How Cyclift works", "Cyclift plans your week from your available days and minutes, your goals, your experience and your equipment. Each session can be started from the Training Hub (the centre button), recorded on the phone, Apple Watch or BikeComputer, and its result is kept in your history.")
                topic("How your plan is made", "The coach builds rides and strength sessions to fit the minutes you gave each day. When you change a setting that affects the plan, you see a before / after preview first; nothing changes until you approve it, and Plan › Plan changes can undo it. Completed workouts are never changed.")
                topic("Understanding the numbers", "Weekly completion is sessions done ÷ sessions planned, counted from the day your plan became effective; skipped sessions are left out. Values are tagged by where they come from: measured by a sensor, imported from Apple Health, entered by you, or an estimate. Power zones appear only once an FTP is set or tested.")
                topic("Connecting devices", "Apple Watch and Bluetooth heart-rate straps add heart rate; power meters and cadence sensors add power and cadence; the BikeComputer records rides on the bike. Profile › Devices & sensors shows what is paired, connected and sending data right now.")
                VStack(alignment: .leading, spacing: 8) {
                    CyCaption(text: "Troubleshooting")
                    Text("If a sensor shows no data: make sure Bluetooth is on and Cyclift may use it (iOS Settings › Cyclift), wake the sensor, then open Diagnostics to see what the phone is receiving.").font(CyType.secondary).foregroundStyle(CyTheme.ink2).fixedSize(horizontal: false, vertical: true)
                    NavigationLink { PipelineDiagnosticsView() } label: { linkRow("Diagnostics", "stethoscope") }.buttonStyle(.plain).accessibilityIdentifier("helpDiagnostics")
                }
                .padding(14).frame(maxWidth: .infinity, alignment: .leading).cyCard()
                VStack(alignment: .leading, spacing: 4) {
                    CyCaption(text: "Support")
                    Link(destination: SupportInfo.supportPage) { linkRow("Support page", "arrow.up.right.square") }.accessibilityIdentifier("helpSupportPage")
                    if let mail = SupportInfo.mailURL { CyDivider(); Link(destination: mail) { linkRow("Contact support", "envelope") }.accessibilityIdentifier("helpContact") }
                    CyDivider()
                    NavigationLink { LegalView(kind: .privacy) } label: { linkRow("Privacy policy", "hand.raised") }.buttonStyle(.plain)
                    CyDivider()
                    NavigationLink { LegalView(kind: .terms) } label: { linkRow("Terms of use", "doc.text") }.buttonStyle(.plain)
                }
                .padding(14).frame(maxWidth: .infinity, alignment: .leading).cyCard()
                Text("Cyclift \(AppInfo.label)").font(CyType.captionSmall).foregroundStyle(CyTheme.ink3).frame(maxWidth: .infinity).accessibilityIdentifier("helpVersion")
            }
            .padding(.horizontal, CyTheme.margin).padding(.vertical, CyTheme.sp3).padding(.bottom, CyTheme.dockClearance)
            .frame(maxWidth: CyTheme.maxContentWidth).frame(maxWidth: .infinity)
        }
        .background(CyTheme.canvas)
        .navigationTitle("Help & support").navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("helpSupportPage")
    }
    private func topic(_ t: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            CyCaption(text: t)
            Text(body).font(CyType.secondary).foregroundStyle(CyTheme.ink2).fixedSize(horizontal: false, vertical: true)
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading).cyCard()
        .accessibilityElement(children: .combine)
    }
    private func linkRow(_ t: String, _ icon: String) -> some View {
        HStack { Text(t).font(CyType.body).foregroundStyle(CyTheme.ink); Spacer(); Image(systemName: icon).foregroundStyle(CyTheme.ink3) }
            .frame(minHeight: CyTheme.minTap).contentShape(Rectangle())
    }
}
