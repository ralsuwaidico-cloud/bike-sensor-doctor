import SwiftUI

// MARK: - Cyclift design system (quality release): one spacing scale, Dynamic Type text styles, ≥ 44 pt targets,
// action rows that never squeeze or hyphenate labels (they reflow to two rows, then a column), and helper text behind
// an info button instead of long paragraphs. Every screen uses these instead of ad-hoc sizes.
enum DS {
    static let xs: CGFloat = 4, s: CGFloat = 8, m: CGFloat = 12, l: CGFloat = 16, xl: CGFloat = 24
    static let minTap: CGFloat = 44
    static let corner: CGFloat = 14
    /// Large rounded numbers that still follow Dynamic Type (title-sized at the default text size).
    static let number = Font.system(.title, design: .rounded).weight(.bold)
    static let screenTitle = Font.system(.title2, design: .rounded).weight(.bold)
}

/// One action of an `ActionRow`. `label` is short and visible; `a11y` is the full spoken name (VoiceOver, UI tests).
struct ActionSpec: Identifiable {
    var id: String { identifier ?? label }
    var label: String
    var a11y: String? = nil
    var icon: String? = nil
    var prominent = false
    var tint: Color? = nil
    var identifier: String? = nil
    var action: () -> Void
}

/// A row of equal actions: one line when every label fits unclipped, else two per row, else one per row (accessibility
/// sizes, small phones). Labels are never truncated, hyphenated or shrunk.
struct ActionRow: View {
    let actions: [ActionSpec]
    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: DS.s) { ForEach(actions) { ActionButton(spec: $0) } }
            VStack(spacing: DS.s) {
                ForEach(Array(stride(from: 0, to: actions.count, by: 2)), id: \.self) { i in
                    HStack(spacing: DS.s) {
                        ActionButton(spec: actions[i])
                        if i + 1 < actions.count { ActionButton(spec: actions[i + 1]) }
                    }
                }
            }
            VStack(spacing: DS.s) { ForEach(actions) { ActionButton(spec: $0) } }
        }
    }
}

struct ActionButton: View {
    let spec: ActionSpec
    var body: some View {
        let b = Button(action: spec.action) {
            Group {
                if let icon = spec.icon { Label(spec.label, systemImage: icon) } else { Text(spec.label) }
            }
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .frame(maxWidth: .infinity, minHeight: DS.minTap - 12)
        }
        .tint(spec.tint ?? BC.accent)
        .accessibilityLabel(spec.a11y ?? spec.label)
        .accessibilityIdentifier(spec.identifier ?? "action-\(spec.label)")
        if spec.prominent { b.buttonStyle(.borderedProminent).controlSize(.large) } else { b.buttonStyle(.bordered).controlSize(.large) }
    }
}

/// Helper text behind a small (i) button: keeps cards short; the text is one tap away and fully readable.
struct InfoButton: View {
    let title: String
    let text: String
    @State private var show = false
    var body: some View {
        Button { show = true } label: { Image(systemName: "info.circle").font(.body).foregroundStyle(BC.accent) }
            .buttonStyle(.minTap)
            .accessibilityLabel("About \(title)")
            .sheet(isPresented: $show) {
                NavigationStack {
                    ScrollView { Text(text).font(.body).frame(maxWidth: .infinity, alignment: .leading).padding() }
                        .navigationTitle(title).navigationBarTitleDisplayMode(.inline)
                        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { show = false } } }
                }.presentationDetents([.medium, .large])
            }
    }
}

/// Title + trailing value that stack vertically when they do not fit side by side (accessibility sizes).
struct TitleValue<Title: View, Value: View>: View {
    @ViewBuilder var title: Title
    @ViewBuilder var value: Value
    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: DS.s) { title; Spacer(minLength: DS.s); value }
            VStack(alignment: .leading, spacing: DS.xs) { title; value }
        }
    }
}

/// "Deleted · Undo" snackbar for the soft-delete window.
struct UndoSnackbar: ViewModifier {
    @EnvironmentObject private var store: Store
    func body(content: Content) -> some View {
        content.overlay(alignment: .bottom) {
            if let t = store.undoToast {
                HStack(spacing: DS.m) {
                    Text(t.text).font(.subheadline).foregroundStyle(.white).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: DS.s)
                    Button("Undo") { store.undoDelete(t.id) }
                        .font(.subheadline.bold()).foregroundStyle(BC.accent).frame(minWidth: DS.minTap, minHeight: DS.minTap)
                        .accessibilityIdentifier("undoDelete")
                }
                .padding(.horizontal, DS.l).padding(.vertical, DS.xs)
                .background(Color.black.opacity(0.85), in: RoundedRectangle(cornerRadius: DS.corner))
                .padding(.horizontal, DS.l).padding(.bottom, DS.s)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .task(id: t.id) {
                    try? await Task.sleep(nanoseconds: 8_000_000_000)
                    if store.undoToast?.id == t.id { withAnimation { store.undoToast = nil } }
                }
            }
        }
        .animation(.easeOut(duration: 0.2), value: store.undoToast)
    }
}
extension View { func undoSnackbar() -> some View { modifier(UndoSnackbar()) } }

/// The FTP's confidence as a pill with an honest label.
struct FTPConfidencePill: View {
    let profile: RiderProfile
    var body: some View {
        Pill(text: profile.ftpBadge, color: profile.ftpConfidence == .verifiedTest ? BC.live : profile.ftpConfidence.isConfident ? BC.accent : BC.stale)
            .accessibilityLabel("FTP \(profile.ftpBadge): \(profile.ftpLabel)")
            .accessibilityIdentifier("ftpConfidence")
    }
}

/// Status pill of a planned session from the one query layer.
struct WorkoutStatusPill: View {
    let status: WorkoutStatus
    var body: some View {
        switch status {
        case .planned: EmptyView()
        case .completedLogged, .importedHealth: Pill(text: status.pill, color: BC.live)
        case .completedManual: Pill(text: status.pill, color: BC.live)
        case .skipped: Pill(text: status.pill)
        case .started, .inProgress: Pill(text: status.pill, color: BC.accent)
        }
    }
}

// MARK: - FTP confidence (quality release)
enum FTPConfidence: String, Equatable {
    case verifiedTest, estimatedVerified, provisional, unverified
    var title: String {
        switch self {
        case .verifiedTest: return "Verified test"
        case .estimatedVerified: return "Estimated from verified power data"
        case .provisional: return "Provisional estimate"
        case .unverified: return "Unverified"
        }
    }
    var short: String {
        switch self { case .verifiedTest: return "verified test"; case .estimatedVerified: return "estimated · verified power"; case .provisional: return "provisional"; case .unverified: return "unverified" }
    }
    /// Only these drive confident (power-target) prescriptions.
    var isConfident: Bool { self == .verifiedTest || self == .estimatedVerified }
}

extension RiderProfile {
    var ftpConfidence: FTPConfidence {
        switch ftpHow {
        case .tested: return ftpVerifiedTest == true ? .verifiedTest : .unverified
        case .fromRides: return ftpPowerVerified == true ? .estimatedVerified : .unverified
        case .assumed: return .provisional
        case .entered: return .unverified
        }
    }
    /// Where the FTP came from, in one honest sentence.
    var ftpSourceText: String {
        switch (ftpHow, ftpConfidence) {
        case (.tested, .verifiedTest): return "From a completed FTP test ride with verified power (95 % of the 20-minute test effort)."
        case (.tested, _): return "Entered as a test result, but no test ride was recorded in Cyclift, so it is unverified."
        case (.fromRides, .estimatedVerified): return "Estimated as 95 % of the best 20-minute power of a ride with verified power. An estimate, not a test."
        case (.fromRides, _): return "Estimated as 95 % of the best 20-minute power of a recorded ride whose power was never verified. An estimate, not a test."
        case (.assumed, _): return "Starting assumption: \(String(format: "%.0f", weightKg)) kg × \(String(format: "%.2f", level.wkg)) W/kg for \(level.title.lowercased()) riders."
        case (.entered, _): return "Entered by you, without a recorded test."
        }
    }
    /// FTP used for power targets: the value itself when confident, else 5 % lower (conservative zones).
    var prescriptionFTP: Int { ftpConfidence.isConfident ? ftpW : Int((Double(ftpW) * 0.95).rounded()) }
    /// Power zones for prescriptions (targets): conservative when the FTP is not verified.
    var prescriptionZones: [(lo: Int, hi: Int?)] { var p = self; p.ftpW = prescriptionFTP; return p.powerZones }
    var ftpCaution: String? {
        ftpConfidence.isConfident ? nil : "FTP \(ftpBadge): power targets are set 5 % lower and the ride coach does not claim zones from power. Ride by feel and heart rate; a verified FTP test replaces it."
    }
}

// MARK: - Wrapping row (pills, meta text): wraps to the next line instead of clipping or shrinking text
struct FlowLayout: Layout {
    var spacing: CGFloat = 6
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxW = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0, widest: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(ProposedViewSize(width: maxW.isFinite ? maxW : nil, height: nil))
            if x > 0 && x + s.width > maxW + 0.5 { y += rowH + spacing; x = 0; rowH = 0 }
            x += s.width + spacing
            rowH = max(rowH, s.height)
            widest = max(widest, x - spacing)
        }
        return CGSize(width: maxW.isFinite ? min(widest, maxW) : widest, height: y + rowH)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        // Line breaks use exactly the width the size was measured for (the proposal), with the same rule and tolerance
        // as sizeThatFits: a bounds width a fraction of a point narrower must never add a row the height did not
        // include (that drew the next row over the text below at large sizes).
        let maxW = proposal.width.map { $0.isFinite ? $0 : bounds.width } ?? bounds.width
        var x: CGFloat = 0, y = bounds.minY, rowH: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(ProposedViewSize(width: maxW, height: nil))
            if x > 0 && x + s.width > maxW + 0.5 { y += rowH + spacing; x = 0; rowH = 0 }
            v.place(at: CGPoint(x: bounds.minX + x, y: y), anchor: .topLeading, proposal: ProposedViewSize(width: min(s.width, maxW), height: s.height))
            x += s.width + spacing
            rowH = max(rowH, s.height)
        }
    }
}

struct FlowRow<Content: View>: View {
    var spacing: CGFloat = 6
    @ViewBuilder var content: Content
    var body: some View { FlowLayout(spacing: spacing).callAsFunction { content } }
}

/// Key / value table row: side by side normally, stacked at accessibility sizes (no hyphenated keys).
struct KeyValueRow: View {
    let key: String
    let value: String
    var last = false
    @Environment(\.dynamicTypeSize) private var dts
    var body: some View {
        VStack(spacing: 0) {
            Group {
                if dts.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(key).font(.footnote).foregroundStyle(.secondary)
                        Text(value).font(.footnote.weight(.medium)).fixedSize(horizontal: false, vertical: true)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    HStack(alignment: .firstTextBaseline) {
                        Text(key).font(.footnote).foregroundStyle(.secondary).frame(width: 84, alignment: .leading)
                        Text(value).font(.footnote.weight(.medium)).frame(maxWidth: .infinity, alignment: .leading).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .accessibilityElement(children: .combine)
            if !last { Divider().padding(.leading, 10) }
        }
    }
}

/// Card header: eyebrow and a trailing pill side by side, or stacked when they do not fit on one line.
struct HeaderRow<Trailing: View>: View {
    let title: String
    @ViewBuilder var trailing: Trailing
    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline) { Eyebrow(t: title).fixedSize(); Spacer(minLength: DS.s); trailing }
            VStack(alignment: .leading, spacing: DS.xs) { Eyebrow(t: title).fixedSize(horizontal: false, vertical: true); trailing }
        }
    }
}

/// A summary line limit that is lifted at the largest text sizes (XXXL and accessibility sizes), so long names and
/// lists wrap instead of ending in "…" when the rider has asked for bigger text.
struct ClampLines: ViewModifier {
    @Environment(\.dynamicTypeSize) private var dts
    let n: Int
    func body(content: Content) -> some View { content.lineLimit(dts >= .xxxLarge ? nil : n) }
}
extension View { func clampLines(_ n: Int) -> some View { modifier(ClampLines(n: n)) } }

/// Text-link buttons ("Plan ›", "Review ›", "Show all", "Adjust sets") with a 44 × 44 pt hit area that is also the
/// accessibility frame (a frame put around a plain Button does not enlarge where it can be tapped).
struct TapTargetStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.foregroundStyle(BC.accent)
            .frame(minWidth: DS.minTap, minHeight: DS.minTap).contentShape(Rectangle())
            .opacity(configuration.isPressed ? 0.5 : 1)
    }
}
extension ButtonStyle where Self == TapTargetStyle { static var tapTarget: TapTargetStyle { TapTargetStyle() } }

/// Like a plain button, but the 44 × 44 pt minimum is the real hit area AND the accessibility frame (a frame inside a
/// plain button's label does not enlarge either — the layout audit measured an (i) button at 17 × 17 pt).
struct MinTapStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.frame(minWidth: DS.minTap, minHeight: DS.minTap).contentShape(Rectangle())
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}
extension ButtonStyle where Self == MinTapStyle { static var minTap: MinTapStyle { MinTapStyle() } }
