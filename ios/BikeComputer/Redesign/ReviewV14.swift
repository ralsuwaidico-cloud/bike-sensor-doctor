import SwiftUI

// Training Hub v1.4 — the optional review after a saved session (design sheet 06a, owner decision 3): three sliders
// side by side — Intensity · Performance · Effort — with − / + under each, and NOTHING pre-filled.
//
// WHAT IS STORED, AND WHAT IS NOT
// • The workout is already saved before this page opens. Leaving the page stores nothing about the review.
// • Performance and Effort keep their 1–10 meaning and go into the app's existing check-in record, through the existing
//   Store function. A review is stored only when both are answered (the "no storage change" rule of the design).
// • Intensity is new: optional, stored only, read by no engine.
// • Pain: the existing record always holds a pain answer and the Coach acts on it, so an unanswered pain question
//   cannot be stored truthfully. Until that is decided (v1.4 pending item 4), this page asks it openly with nothing
//   selected and saves the review only when it is answered. It is never recorded as "no pain" by default.
//   This differs from the drawing, which folds it into one collapsed line.

struct ReviewV14: View {
    @EnvironmentObject private var store: Store
    let target: CheckInTarget
    var onDone: () -> Void
    @Environment(\.cyTheme) private var theme
    @Environment(\.dynamicTypeSize) private var dts
    @State private var intensity: Int? = nil
    @State private var performance: Int? = nil
    @State private var effort: Int? = nil
    @State private var pain: PainLevel? = nil
    @State private var area: PainArea = .other
    @State private var note = ""
    @State private var savedLine: String? = nil

    private var canSave: Bool { performance != nil && effort != nil && pain != nil }
    private var missing: String {
        var m: [String] = []
        if performance == nil { m.append("Performance") }
        if effort == nil { m.append("Effort") }
        if pain == nil { m.append("the pain question") }
        return m.isEmpty ? "" : "To save the review, answer " + m.joined(separator: ", ") + ". Or leave: nothing is stored."
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: CySpace.l) {
                    Text(target.isRide ? "How was the ride?" : "How was the session?").font(.system(.title, design: .rounded).weight(.bold)).foregroundStyle(theme.textPrimary)
                    Text("Optional. Your workout is already saved. Nothing here is filled in for you.").font(CyFont.footnote).foregroundStyle(theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    let cols = dts.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: CySpace.l)) : AnyLayout(HStackLayout(alignment: .top, spacing: CySpace.s))
                    cols {
                        CyReviewSlider(title: "Intensity", low: "easy day", high: "hardest", value: $intensity, id: "Intensity", optional: true)
                        CyReviewSlider(title: "Performance", low: "far below", high: "excellent", value: $performance, id: "Performance")
                        CyReviewSlider(title: "Effort", low: "very easy", high: "maximal", value: $effort, id: "Effort")
                    }
                    VStack(alignment: .leading, spacing: CySpace.s) {
                        Text("PAIN OR UNUSUAL DISCOMFORT").font(CyFont.overline).tracking(1.2).foregroundStyle(theme.textSecondary)
                        let rows = dts.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: CySpace.s)) : AnyLayout(HStackLayout(spacing: CySpace.s))
                        rows { ForEach(PainLevel.allCases, id: \.self) { p in painChip(p) } }
                        if let p = pain, p.needsArea {
                            Picker("Where", selection: $area) { ForEach(PainArea.allCases, id: \.self) { Text($0.title).tag($0) } }
                                .tint(theme.accent).accessibilityIdentifier("reviewPainArea")
                            Text(p == .concerning ? (AdaptationExplainer.painAdvice([area]) ?? "") : AdaptationExplainer.discomfortAdvice([area]))
                                .font(CyFont.footnote).foregroundStyle(p == .concerning ? theme.warning : theme.textSecondary).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    TextField("Anything your Coach should know? (optional)", text: $note, axis: .vertical).lineLimit(1...3)
                        .font(CyFont.callout).foregroundStyle(theme.textPrimary)
                        .padding(CySpace.m).background(RoundedRectangle(cornerRadius: CyRadius.s, style: .continuous).fill(theme.surface))
                        .accessibilityIdentifier("reviewNote")
                    if let s = savedLine {
                        Label(s, systemImage: "checkmark.circle.fill").font(CyFont.headline).foregroundStyle(theme.success).accessibilityIdentifier("reviewSaved")
                    } else {
                        Text(missing).font(CyFont.footnote).foregroundStyle(theme.textSecondary).fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("reviewMissing")
                        Button(action: save) {
                            Text("Save review").font(.headline).foregroundStyle(theme.textOnAccent).frame(maxWidth: .infinity, minHeight: 56)
                                .background(RoundedRectangle(cornerRadius: CyRadius.m, style: .continuous).fill(canSave ? theme.accent : theme.disabledFill))
                        }
                        .buttonStyle(.plain).disabled(!canSave).accessibilityIdentifier("reviewSave")
                    }
                    Text(AdaptationExplainer.disclaimer).font(.caption2).foregroundStyle(theme.textTertiary).fixedSize(horizontal: false, vertical: true)
                }
                .padding(CySpace.l)
            }
            .background(theme.background.ignoresSafeArea())
            .navigationTitle("Review").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(savedLine == nil ? "Not now" : "Done") { onDone() }.accessibilityIdentifier("reviewClose")
                }
            }
        }
        .accessibilityIdentifier("reviewV14")
    }

    private func painChip(_ p: PainLevel) -> some View {
        let on = pain == p
        return Button { pain = p } label: {
            Text(p.short).font(CyFont.caption).foregroundStyle(on ? theme.textOnAccent : theme.textPrimary).lineLimit(1).minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity, minHeight: CyHit.min)
                .background(RoundedRectangle(cornerRadius: CyRadius.s, style: .continuous).fill(on ? theme.accent : theme.surface))
                .overlay(RoundedRectangle(cornerRadius: CyRadius.s, style: .continuous).strokeBorder(theme.id == .highContrast ? theme.border : Color.clear, lineWidth: theme.borderWidth))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(p.title).accessibilityAddTraits(on ? .isSelected : [])
        .accessibilityIdentifier("reviewPain-\(p.rawValue)")
    }

    private func save() {
        guard let pf = performance, let ef = effort, let pn = pain, savedLine == nil else { return }
        var c = CheckIn(performance: pf, effort: ef, pain: pn, painArea: pn.needsArea ? area : nil, note: note.trimmingCharacters(in: .whitespacesAndNewlines))
        c.intensity = intensity
        switch target {
        case .ride(let id): _ = store.recordCheckIn(c, rideId: id)
        case .strength(let id): _ = store.recordCheckIn(c, strengthId: id)
        }
        savedLine = "Review saved"
    }
}

/// One review value, 1–10, that starts unanswered. Drag the track or use − / +. Unanswered shows "–" and no thumb.
struct CyReviewSlider: View {
    let title: String
    let low: String
    let high: String
    @Binding var value: Int?
    let id: String
    var optional = false
    @Environment(\.cyTheme) private var theme
    @Environment(\.dynamicTypeSize) private var dts
    private let trackHeight: CGFloat = 200

    var body: some View {
        VStack(spacing: 6) {
            Text(title).font(CyFont.label).foregroundStyle(theme.textPrimary).lineLimit(1).minimumScaleFactor(0.7)
            Text(value.map(String.init) ?? "–").font(.system(size: 40, weight: .heavy, design: .rounded)).monospacedDigit()
                .foregroundStyle(value == nil ? theme.textTertiary : theme.textPrimary)
                .accessibilityIdentifier("review\(id)Value")
            if !dts.isAccessibilitySize { track }
            HStack(spacing: CySpace.s) {
                step("minus", "Lower \(title)", id: "review\(id)Minus") { value = max(1, (value ?? 6) - 1) }
                step("plus", "Raise \(title)", id: "review\(id)Plus") { value = min(10, (value ?? 5) + 1) }
            }
            Text(value == nil ? (optional ? "optional" : "not answered") : (value! <= 3 ? low : value! >= 8 ? high : " "))
                .font(.caption2).foregroundStyle(theme.textSecondary).lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
    }

    private var track: some View {
        GeometryReader { g in
            let h = g.size.height
            ZStack(alignment: .bottom) {
                Capsule().fill(theme.surface2).frame(width: 10)
                if let v = value {
                    Capsule().fill(theme.accent).frame(width: 10, height: max(10, h * CGFloat(v) / 10))
                    Circle().fill(theme.accent).frame(width: 34, height: 34)
                        .overlay(Circle().strokeBorder(theme.background, lineWidth: 3))
                        .offset(y: -(h - 34) * CGFloat(v - 1) / 9)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { d in
                let f = 1 - min(max(d.location.y / max(h, 1), 0), 1)
                value = min(10, max(1, Int((f * 9).rounded()) + 1))
            })
        }
        .frame(height: trackHeight)
        .accessibilityElement()
        .accessibilityLabel(title)
        .accessibilityValue(value.map { "\($0) of 10" } ?? "not answered")
        .accessibilityAdjustableAction { dir in
            switch dir {
            case .increment: value = min(10, (value ?? 5) + 1)
            case .decrement: value = max(1, (value ?? 6) - 1)
            @unknown default: break
            }
        }
        .accessibilityIdentifier("review\(id)Track")
    }
    private func step(_ icon: String, _ label: String, id: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.footnote.weight(.bold)).foregroundStyle(theme.textPrimary)
                .frame(width: CyHit.min, height: CyHit.min).overlay(Circle().strokeBorder(theme.border, lineWidth: 1.2)).contentShape(Circle())
        }
        .buttonStyle(.plain).accessibilityLabel(label).accessibilityIdentifier(id)
    }
}
