import SwiftUI

// Training Hub v1.4 — the optional review after a saved session (design sheet 06a, owner decision 3): three sliders
// side by side — Intensity · Performance · Effort — with − / + under each, and NOTHING pre-filled.
// Composition as drawn on 06a: "✓ SAVED · name · minutes" and "How was it?" with Skip on the right (R1) · three wide
// columns with the value, its word and a pill track (R2) · one line "Anything your Coach should know?" that opens to
// Pain · Fatigue · Equipment · Note (R3) · the pain sheet: where, then how you would describe it (R4) · stacked rows
// with − / + at accessibility text sizes (R5). The page does not scroll, so a drag is never a scroll.
// Differences from the sheet, each a labelled CANDIDATE until reviewed:
//  • the words under the numbers: only "Demanding" (7) and "Hard" (8) are drawn; the rest are provisional (ReviewScale);
//  • Fatigue and Equipment are written notes, kept in the review's one note under their own label (no new stored field);
//  • the pain sheet keeps "No pain to report" as a quiet line: without it "no pain" could not be said at all, and the
//    Coach only receives a full check-in when performance, effort and pain are all answered.
//
// WHAT IS STORED, AND WHAT IS NOT (owner decisions of 16 Nov 2026)
// • The workout is already saved before this page opens. Leaving the page stores nothing about the review.
// • Intensity, Performance and Effort are three independent, optional values. One, two, three or none may be given.
//   Nothing is pre-filled and an unanswered value is stored as "not answered", never as a number.
// • Pain is optional too. Not answered = unknown. "None" is stored only when the athlete taps it.
// • Storage is SessionReview (AdaptiveModels.swift), through Store.recordReview. A review that happens to answer
//   performance, effort and pain is also recorded as a complete check-in, so the Coach works as before; a partial
//   review is not an assessment, and only a pain it reports reaches the Coach.

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
    @State private var area: PainArea? = nil
    @State private var notes = ReviewNotes()
    @State private var coachOpen = false
    @State private var painSheet = false
    @State private var writing: Writing? = nil
    @State private var failed = false

    private enum Writing: String, Identifiable { case fatigue, equipment, note; var id: String { rawValue }
        var title: String { switch self { case .fatigue: return "Fatigue"; case .equipment: return "Equipment"; case .note: return "Note" } }
        var prompt: String { switch self { case .fatigue: return "How tired you felt, and where"; case .equipment: return "Anything about the equipment"; case .note: return "Anything else for your Coach" } }
    }

    private var draft: SessionReview {
        SessionReview(intensity: intensity, performance: performance, effort: effort, pain: pain, painArea: (pain?.needsArea ?? false) ? (area ?? .other) : nil,
                      note: notes.composed)
    }
    private var canSave: Bool { !draft.isEmpty }

    /// "SAVED · FULL BODY · 35 MIN" — read from the saved record itself.
    private var savedLine: String {
        switch target {
        case .strength(let id):
            guard let s = store.strength.first(where: { $0.id == id }) else { return "Saved" }
            let planned = s.workoutId.flatMap { wid in store.plan.first { $0.id == wid } }.map { StrengthPrepare.title($0.displayTitle) }
            let name = planned ?? (s.customName.isEmpty ? "Strength workout" : s.customName)
            return "Saved · \(name) · \(s.minutes < 1 ? "under 1 min" : "\(s.minutes) min")"
        case .ride(let id):
            guard let r = store.rides.first(where: { $0.id == id }) else { return "Saved" }
            return "Saved · Ride · \(max(1, (r.durationS + 30) / 60)) min"
        }
    }

    var body: some View {
        Group {
            if dts.isAccessibilitySize { ScrollView { content.padding(.bottom, CySpace.l) } }
            else { content }
        }
        .padding(.horizontal, 20).padding(.top, CySpace.m).padding(.bottom, CySpace.l)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(theme.background.ignoresSafeArea())
        .sheet(isPresented: $painSheet) {
            ReviewPainSheet(pain: $pain, area: $area) { painSheet = false }
                .presentationDetents([.fraction(0.62), .large]).presentationDragIndicator(.visible).cyThemeRoot()
        }
        .sheet(item: $writing) { w in
            ReviewWriteSheet(title: w.title, prompt: w.prompt, text: binding(w)) { writing = nil }
                .presentationDetents([.medium]).presentationDragIndicator(.visible).cyThemeRoot()
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("reviewV14")
    }
    private func binding(_ w: Writing) -> Binding<String> {
        switch w {
        case .fatigue: return $notes.fatigue
        case .equipment: return $notes.equipment
        case .note: return $notes.note
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if dts.isAccessibilitySize {
                VStack(spacing: 0) {
                    Rectangle().fill(theme.separator).frame(height: 1)
                    CyReviewSlider(scale: .intensity, value: $intensity)
                    Rectangle().fill(theme.separator).frame(height: 1)
                    CyReviewSlider(scale: .performance, value: $performance)
                    Rectangle().fill(theme.separator).frame(height: 1)
                    CyReviewSlider(scale: .effort, value: $effort)
                    Rectangle().fill(theme.separator).frame(height: 1)
                }
                .padding(.top, CySpace.l)
            } else {
                HStack(alignment: .top, spacing: CySpace.s) {
                    CyReviewSlider(scale: .intensity, value: $intensity)
                    CyReviewSlider(scale: .performance, value: $performance)
                    CyReviewSlider(scale: .effort, value: $effort)
                }
                .padding(.top, 22)
            }
            coach.padding(.top, CySpace.l)
            if !dts.isAccessibilitySize { Spacer(minLength: CySpace.m) }
            if failed {
                Text("The review could not be saved. Your workout is saved; try again.").font(CyFont.footnote).foregroundStyle(theme.danger)
                    .fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("reviewNotSaved").padding(.bottom, CySpace.s)
            }
            CyBottomActions(primary: canSave ? "Save review" : "Nothing to save yet", primaryID: "reviewSave", primaryEnabled: canSave, onPrimary: save)
                .padding(.top, dts.isAccessibilitySize ? CySpace.xl : 0)
        }
    }

    private var header: some View {
        HStack(alignment: .bottom, spacing: CySpace.s) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Image(systemName: "checkmark").font(.system(size: 9, weight: .heavy)).accessibilityHidden(true)
                    Text(dts.isAccessibilitySize ? "Saved" : savedLine.uppercased()).font(CyFont.overline).tracking(dts.isAccessibilitySize ? 0 : 1.4)
                        .lineLimit(2).minimumScaleFactor(0.8)
                }
                .foregroundStyle(theme.textSecondary)
                .accessibilityElement(children: .ignore).accessibilityLabel(savedLine).accessibilityIdentifier("reviewSavedLine")
                Text("How was it?").font(.system(.title, design: .rounded).weight(.bold)).foregroundStyle(theme.textPrimary)
                    .accessibilityAddTraits(.isHeader).accessibilityIdentifier("reviewTitle")
            }
            Spacer(minLength: CySpace.s)
            Button(action: onDone) {
                Text("Skip").font(.system(.body, design: .rounded).weight(.semibold)).foregroundStyle(theme.textPrimary)
                    .frame(minWidth: CyHit.min, minHeight: CyHit.min).contentShape(Rectangle())
            }
            .buttonStyle(.plain).accessibilityHint("Leaves every rating unanswered. Your workout stays saved").accessibilityIdentifier("reviewClose")
        }
    }

    /// One line that opens to four choices. Not opening it means "nothing reported" — it is not a "no".
    @ViewBuilder private var coach: some View {
        if coachOpen {
            VStack(alignment: .leading, spacing: CySpace.m) {
                Text("ANYTHING YOUR COACH SHOULD KNOW?").font(CyFont.overline).tracking(1.4).foregroundStyle(theme.textSecondary)
                let row = dts.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: CySpace.s)) : AnyLayout(HStackLayout(spacing: CySpace.s))
                row {
                    chip("Pain", on: pain != nil, id: "reviewChipPain") { painSheet = true }
                    chip("Fatigue", on: !notes.fatigue.isEmpty, id: "reviewChipFatigue") { writing = .fatigue }
                    chip("Equipment", on: !notes.equipment.isEmpty, id: "reviewChipEquipment") { writing = .equipment }
                    chip("Note", on: !notes.note.isEmpty, id: "reviewChipNote") { writing = .note }
                }
            }
        } else {
            VStack(spacing: 0) {
                Rectangle().fill(theme.separator).frame(height: 1)
                Button { coachOpen = true } label: {
                    HStack(spacing: CySpace.s) {
                        Text(dts.isAccessibilitySize ? "For your Coach" : "Anything your Coach should know?").font(.system(.callout, design: .rounded).weight(.semibold)).foregroundStyle(theme.textPrimary)
                            .lineLimit(2).minimumScaleFactor(0.85).multilineTextAlignment(.leading)
                        Spacer(minLength: CySpace.s)
                        if !dts.isAccessibilitySize { Text("Optional").font(.system(.callout)).foregroundStyle(theme.textSecondary) }
                        Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(theme.textSecondary).accessibilityHidden(true)
                    }
                    .frame(minHeight: 56).contentShape(Rectangle())
                }
                .buttonStyle(.plain).accessibilityHint("Optional. Opens Pain, Fatigue, Equipment and Note").accessibilityIdentifier("reviewCoachRow")
                Rectangle().fill(theme.separator).frame(height: 1)
            }
        }
    }
    private func chip(_ title: String, on: Bool, id: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.system(.subheadline, design: .rounded).weight(.semibold)).foregroundStyle(on ? theme.background : theme.textPrimary)
                .lineLimit(1).minimumScaleFactor(0.7).padding(.horizontal, 4)
                .frame(maxWidth: .infinity, minHeight: 46)
                .background(RoundedRectangle(cornerRadius: 13, style: .continuous).fill(on ? theme.textPrimary : Color.clear))
                .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).strokeBorder(on ? Color.clear : theme.border, lineWidth: 1.2))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain).accessibilityAddTraits(on ? .isSelected : []).accessibilityIdentifier(id)
    }

    private func save() {
        let r = draft
        guard !r.isEmpty else { return }
        let ok: Bool
        switch target {
        case .ride(let id): ok = store.recordReview(r, rideId: id)
        case .strength(let id): ok = store.recordReview(r, strengthId: id)
        }
        // 06e: "optional review → return". A stored review returns; one that could not be stored stays and says so.
        if ok { onDone() } else { failed = true }
    }
}

/// R4 — where, then how you would describe it. A level is needed for the Coach to act: an area without a level stores
/// nothing about pain (and no level is invented).
struct ReviewPainSheet: View {
    @Binding var pain: PainLevel?
    @Binding var area: PainArea?
    var close: () -> Void
    @Environment(\.cyTheme) private var theme
    @Environment(\.dynamicTypeSize) private var dts
    private func areaTitle(_ a: PainArea) -> String { a == .other ? "Not sure" : a.title }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: CySpace.m) {
                Text("Pain or discomfort").font(.system(.title2, design: .rounded).weight(.bold)).foregroundStyle(theme.textPrimary)
                    .accessibilityAddTraits(.isHeader).padding(.top, CySpace.xl)
                Text("WHERE?").font(CyFont.overline).tracking(1.4).foregroundStyle(theme.textSecondary).padding(.top, CySpace.xs)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: CySpace.s), count: dts.isAccessibilitySize ? 1 : 3), spacing: CySpace.s) {
                    ForEach(PainArea.allCases, id: \.self) { a in
                        option(areaTitle(a), on: area == a, id: "reviewArea-\(a.rawValue)") { area = area == a ? nil : a }
                    }
                }
                Text("HOW WOULD YOU DESCRIBE IT? · NEEDED FOR COACH TO ACT").font(CyFont.overline).tracking(1.4).foregroundStyle(theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true).padding(.top, CySpace.s)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: CySpace.s), count: dts.isAccessibilitySize ? 1 : 3), spacing: CySpace.s) {
                    ForEach([PainLevel.soreness, .discomfort, .concerning], id: \.self) { p in
                        option(p.title, on: pain == p, id: "reviewPain-\(p.rawValue)") { pain = pain == p ? nil : p }
                    }
                }
                if let p = pain, p.needsArea {
                    let a = [area ?? .other]
                    Text(p == .concerning ? (AdaptationExplainer.painAdvice(a) ?? "") : AdaptationExplainer.discomfortAdvice(a))
                        .font(CyFont.footnote).foregroundStyle(p == .concerning ? theme.warning : theme.textSecondary).fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("reviewPainAdvice")
                }
                Button { pain = pain == .noPain ? nil : .noPain; if pain == .noPain { area = nil } } label: {
                    HStack(spacing: 6) {
                        Image(systemName: pain == .noPain ? "checkmark.circle.fill" : "circle").accessibilityHidden(true)
                        Text("No pain to report")
                    }
                    .font(.system(.subheadline)).foregroundStyle(pain == .noPain ? theme.textPrimary : theme.textSecondary)
                    .frame(minHeight: CyHit.min).contentShape(Rectangle())
                }
                .buttonStyle(.plain).accessibilityAddTraits(pain == .noPain ? .isSelected : []).accessibilityIdentifier("reviewPain-none")
                CyBottomActions(primary: "Done", primaryID: "reviewPainDone", onPrimary: close)
                Text(AdaptationExplainer.disclaimer).font(.caption2).foregroundStyle(theme.textTertiary).fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 20).padding(.bottom, CySpace.l)
        }
        .background(theme.surface.ignoresSafeArea())
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("reviewPainSheet")
    }
    private func option(_ title: String, on: Bool, id: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.system(.subheadline, design: .rounded).weight(.semibold)).foregroundStyle(on ? theme.background : theme.textPrimary)
                .multilineTextAlignment(.center).lineLimit(2).minimumScaleFactor(0.8).padding(.horizontal, 6)
                .frame(maxWidth: .infinity, minHeight: 54)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(on ? theme.textPrimary : Color.clear))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(on ? Color.clear : theme.border, lineWidth: 1.2))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain).accessibilityAddTraits(on ? .isSelected : []).accessibilityIdentifier(id)
    }
}

/// Fatigue · Equipment · Note: a few written words, optional.
struct ReviewWriteSheet: View {
    let title: String
    let prompt: String
    @Binding var text: String
    var close: () -> Void
    @Environment(\.cyTheme) private var theme
    @FocusState private var focused: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: CySpace.m) {
            Text(title).font(.system(.title2, design: .rounded).weight(.bold)).foregroundStyle(theme.textPrimary)
                .accessibilityAddTraits(.isHeader).padding(.top, CySpace.xl)
            TextField(prompt, text: $text, axis: .vertical).lineLimit(2...5).focused($focused)
                .font(CyFont.callout).foregroundStyle(theme.textPrimary)
                .padding(CySpace.m).background(RoundedRectangle(cornerRadius: CyRadius.s, style: .continuous).fill(theme.surface2))
                .accessibilityIdentifier("reviewNote")
            Text("Optional. Leaving it empty stores nothing.").font(CyFont.footnote).foregroundStyle(theme.textSecondary)
            Spacer(minLength: 0)
            CyBottomActions(primary: "Done", primaryID: "reviewWriteDone", onPrimary: close)
        }
        .padding(.horizontal, 20).padding(.bottom, CySpace.l)
        .background(theme.surface.ignoresSafeArea())
        .onAppear { focused = true }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("reviewWriteSheet")
    }
}

/// One review value, 1–10, that starts unanswered. Drag inside the column or use − / +. Unanswered shows "–", the
/// words "Not answered" and an empty track with its ten marks. At accessibility text sizes the column becomes a row
/// and − / + are the control (06a R5).
struct CyReviewSlider: View {
    let scale: ReviewScale
    @Binding var value: Int?
    @Environment(\.cyTheme) private var theme
    @Environment(\.dynamicTypeSize) private var dts
    private var id: String { scale.title }
    private func lower() { value = max(1, (value ?? 6) - 1) }
    private func raise() { value = min(10, (value ?? 5) + 1) }

    var body: some View {
        if dts.isAccessibilitySize {
            HStack(alignment: .center, spacing: CySpace.m) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(scale.title).font(.system(.subheadline, design: .rounded).weight(.semibold)).foregroundStyle(theme.textSecondary)
                    number
                    Text(scale.word(value)).font(.system(.headline, design: .rounded)).foregroundStyle(theme.textPrimary).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: CySpace.s)
                step("minus", "Lower \(scale.title)", id: "review\(id)Minus", round: true, lower)
                step("plus", "Raise \(scale.title)", id: "review\(id)Plus", round: true, raise)
            }
            .padding(.vertical, CySpace.m)
            .accessibilityElement(children: .contain)
        } else {
            VStack(spacing: 0) {
                Text(scale.title.uppercased()).font(CyFont.overline).tracking(1.4).foregroundStyle(theme.textPrimary).lineLimit(1).minimumScaleFactor(0.7)
                number.frame(height: 50)
                Text(scale.word(value)).font(.system(.footnote)).foregroundStyle(theme.textSecondary).lineLimit(1).minimumScaleFactor(0.7)
                    .accessibilityIdentifier("review\(id)Word")
                track.padding(.top, CySpace.l)
                HStack(spacing: CySpace.s) {
                    step("minus", "Lower \(scale.title)", id: "review\(id)Minus", round: false, lower)
                    step("plus", "Raise \(scale.title)", id: "review\(id)Plus", round: false, raise)
                }
                .padding(.top, CySpace.m)
            }
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .contain)
        }
    }

    private var number: some View {
        Text(value.map(String.init) ?? "–").font(.system(size: 42, weight: .heavy, design: .rounded)).monospacedDigit()
            .foregroundStyle(value == nil ? theme.textSecondary : theme.textPrimary)
            .accessibilityIdentifier("review\(id)Value")
    }

    /// A wide pill: empty with ten marks until answered, then filled from the bottom to the value with a handle on top.
    private var track: some View {
        GeometryReader { g in
            let h = g.size.height, w: CGFloat = 64
            ZStack(alignment: .bottom) {
                Capsule().fill(theme.surface)
                if let v = value {
                    let fill = max(w * 0.62, h * CGFloat(v) / 10)
                    Rectangle().fill(theme.textPrimary).frame(height: fill)
                    Capsule().fill(theme.background).frame(width: w - 12, height: 11)
                        .overlay(Capsule().strokeBorder(theme.textPrimary, lineWidth: 2))
                        .offset(y: -(fill - 8))
                } else {
                    VStack(spacing: 0) {
                        ForEach(0..<10, id: \.self) { _ in
                            Capsule().fill(theme.textTertiary).frame(width: 16, height: 1.5).frame(maxHeight: .infinity)
                        }
                    }
                    .padding(.vertical, 6)
                }
            }
            .frame(width: w, height: h)
            .clipShape(Capsule())
            .overlay(Capsule().strokeBorder(theme.border, lineWidth: 1))
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { d in
                let f = 1 - min(max(d.location.y / max(h, 1), 0), 1)
                value = min(10, max(1, Int((f * 10).rounded(.up))))
            })
        }
        .frame(minHeight: 120, idealHeight: 232, maxHeight: 232)
        .accessibilityElement()
        .accessibilityLabel(scale.title)
        .accessibilityValue(value.map { "\($0) of 10, \(scale.word($0))" } ?? "not answered")
        .accessibilityAdjustableAction { dir in
            switch dir {
            case .increment: raise()
            case .decrement: lower()
            @unknown default: break
            }
        }
        .accessibilityIdentifier("review\(id)Track")
    }
    private func step(_ icon: String, _ label: String, id: String, round: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.footnote.weight(.bold)).foregroundStyle(theme.textPrimary)
                .frame(width: round ? 56 : CyHit.min, height: round ? 56 : CyHit.min)
                .overlay(RoundedRectangle(cornerRadius: round ? 28 : 13, style: .continuous).strokeBorder(theme.border, lineWidth: 1.2))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain).accessibilityLabel(label).accessibilityIdentifier(id)
    }
}
