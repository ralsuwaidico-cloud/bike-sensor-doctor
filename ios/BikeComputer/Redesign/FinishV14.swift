import SwiftUI

// Training Hub v1.4 — Finish and save (sheets 06e, 06f). Presentation only: the pages receive text and report taps.
//  X1 Complete · X2 Partial · X3 Nothing recorded · X6 Save failed  → CyFinishPage
//  X5 Saved — confirmed                                              → CySavedPage
//  X8 Discard                                                        → CyDiscardDialog over the page
// NOT built (the sheet marks both FUTURE, and "save-result handling" is a pending item of the v1.4 approval):
//  X4 Saving (the save has no pending state) and X7 Save not confirmed.

struct CyFinishRow: Identifiable, Equatable { var label: String; var value: String; var id: String }

/// A back circle on the left and, when given, a quiet destructive action on the right.
struct CyPageTopBar: View {
    var backLabel: String = "Back"
    var backID: String
    var onBack: () -> Void
    var trailing: String? = nil
    var trailingID: String = ""
    var trailingDestructive = false
    var onTrailing: () -> Void = {}
    @Environment(\.cyTheme) private var theme
    var body: some View {
        HStack {
            Button(action: onBack) {
                Image(systemName: "chevron.left").font(.system(size: 15, weight: .bold)).foregroundStyle(theme.textPrimary)
                    .frame(width: CyHit.min, height: CyHit.min).background(Circle().fill(theme.surface2))
                    .overlay(Circle().strokeBorder(theme.id == .highContrast ? theme.border : Color.clear, lineWidth: theme.borderWidth))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain).accessibilityLabel(backLabel).accessibilityIdentifier(backID)
            Spacer(minLength: CySpace.s)
            if let t = trailing {
                Button(action: onTrailing) {
                    Text(t).font(.system(.body, design: .rounded).weight(.semibold)).foregroundStyle(trailingDestructive ? theme.danger : theme.textPrimary)
                        .frame(minWidth: CyHit.min, minHeight: CyHit.min).contentShape(Rectangle())
                }
                .buttonStyle(.plain).accessibilityIdentifier(trailingID)
            }
        }
    }
}

/// Label on the left, value on the right, a hairline under each row but the last.
struct CyFactRows: View {
    var rows: [CyFinishRow]
    @Environment(\.cyTheme) private var theme
    @Environment(\.dynamicTypeSize) private var dts
    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.element.id) { i, r in
                let layout = dts.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 2)) : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: CySpace.m))
                layout {
                    Text(r.label).font(.system(.callout)).foregroundStyle(theme.textSecondary)
                    if !dts.isAccessibilitySize { Spacer(minLength: CySpace.s) }
                    Text(r.value).font(.system(.callout, design: .rounded).weight(.semibold)).foregroundStyle(theme.textPrimary)
                        .multilineTextAlignment(dts.isAccessibilitySize ? .leading : .trailing).fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .padding(.vertical, 6)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier(r.id)
                if i < rows.count - 1 { Rectangle().fill(theme.separator).frame(height: 1) }
            }
        }
    }
}

/// The wide primary button and the plain text button under it, pinned to the bottom of a page.
struct CyBottomActions: View {
    var primary: String
    var primaryID: String
    var primaryEnabled = true
    var onPrimary: () -> Void
    var secondary: String? = nil
    var secondaryID: String = ""
    var onSecondary: () -> Void = {}
    @Environment(\.cyTheme) private var theme
    var body: some View {
        VStack(spacing: CySpace.xs) {
            Button(action: onPrimary) {
                Text(primary).font(.system(.headline, design: .rounded)).foregroundStyle(primaryEnabled ? theme.textOnAccent : theme.textSecondary)
                    .frame(maxWidth: .infinity, minHeight: 54)
                    .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(primaryEnabled ? theme.accent : theme.surface2))
                    .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(theme.id == .highContrast ? theme.border : Color.clear, lineWidth: theme.borderWidth))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain).disabled(!primaryEnabled).accessibilityIdentifier(primaryID)
            if let s = secondary {
                Button(action: onSecondary) {
                    Text(s).font(.system(.headline, design: .rounded)).foregroundStyle(theme.textPrimary)
                        .frame(maxWidth: .infinity, minHeight: 52).contentShape(Rectangle())
                }
                .buttonStyle(.plain).accessibilityIdentifier(secondaryID)
            }
        }
    }
}

/// X1 / X2 / X3 / X6: what will be saved, stated before anything is saved.
struct CyFinishPage: View {
    var overline: String
    var title: String
    var titleID: String = "finishTitle"
    var status: String? = nil
    var message: String? = nil
    var messageID: String = "finishMessage"
    var rows: [CyFinishRow]
    var primary: String
    var primaryID: String
    var onPrimary: () -> Void
    var secondary: String? = nil
    var secondaryID: String = ""
    var onSecondary: () -> Void = {}
    var onBack: () -> Void
    var onDiscard: () -> Void
    @Environment(\.cyTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            CyPageTopBar(backLabel: "Back to workout", backID: "finishBack", onBack: onBack,
                         trailing: "Discard…", trailingID: "finishDiscard", trailingDestructive: true, onTrailing: onDiscard)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: CySpace.s) {
                        Capsule().fill(theme.strength).frame(width: 3, height: 14).accessibilityHidden(true)
                        Text(overline).font(CyFont.caption).foregroundStyle(theme.textSecondary).fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("finishOverline")
                    }
                    .padding(.top, 6)
                    Text(title).font(.system(.largeTitle, design: .rounded).weight(.bold)).foregroundStyle(theme.textPrimary)
                        .lineLimit(3).minimumScaleFactor(0.7).fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader).accessibilityIdentifier(titleID)
                        .padding(.top, 4)
                    if let s = status, !s.isEmpty {
                        Text(s).font(.system(.callout, design: .rounded).weight(.semibold)).foregroundStyle(theme.textPrimary)
                            .fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("finishCount").padding(.top, 6)
                    }
                    if let m = message {
                        Text(m).font(.system(.callout)).foregroundStyle(theme.textSecondary).fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier(messageID).padding(.top, 8)
                    }
                    CyFactRows(rows: rows).padding(.top, CySpace.m)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollBounceBehavior(.basedOnSize)
            CyBottomActions(primary: primary, primaryID: primaryID, onPrimary: onPrimary,
                            secondary: secondary, secondaryID: secondaryID, onSecondary: onSecondary)
                .padding(.top, CySpace.s)
        }
        .padding(.horizontal, 20).padding(.top, CySpace.s).padding(.bottom, CySpace.l)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(theme.background.ignoresSafeArea())
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("finishV14")
    }
}

/// X5: shown only after the save is confirmed.
struct CySavedPage: View {
    var subtitle: String
    var rows: [CyFinishRow]
    var onReview: () -> Void
    var onDone: () -> Void
    @Environment(\.cyTheme) private var theme

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 0) {
                    Image(systemName: "checkmark").font(.system(size: 22, weight: .bold)).foregroundStyle(theme.textPrimary)
                        .frame(width: 58, height: 58).overlay(Circle().strokeBorder(theme.textPrimary, lineWidth: 2))
                        .accessibilityHidden(true)
                        .padding(.top, 84)
                    Text("Saved").font(.system(.title, design: .rounded).weight(.bold)).foregroundStyle(theme.textPrimary)
                        .accessibilityAddTraits(.isHeader).accessibilityIdentifier("saveConfirmed").padding(.top, CySpace.l)
                    Text(subtitle).font(.system(.callout)).foregroundStyle(theme.textSecondary).multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("saveSummary").padding(.top, 6)
                    CyFactRows(rows: rows).padding(.top, CySpace.m)
                }
                .frame(maxWidth: .infinity)
            }
            .scrollBounceBehavior(.basedOnSize)
            CyBottomActions(primary: "Add how it felt", primaryID: "saveReview", onPrimary: onReview,
                            secondary: "Done", secondaryID: "saveDone", onSecondary: onDone)
                .padding(.top, CySpace.s)
        }
        .padding(.horizontal, 20).padding(.top, CySpace.s).padding(.bottom, CySpace.l)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.background.ignoresSafeArea())
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("savedV14")
    }
}

/// X8: reached from "Discard…" and always confirmed. Dims the page behind it.
struct CyDiscardDialog: View {
    var message: String
    var onDiscard: () -> Void
    var onKeep: () -> Void
    @Environment(\.cyTheme) private var theme
    var body: some View {
        ZStack {
            Color.black.opacity(0.55).ignoresSafeArea().onTapGesture(perform: onKeep).accessibilityHidden(true)
            VStack(spacing: 0) {
                Text("Discard this workout?").font(.system(.headline, design: .rounded)).foregroundStyle(theme.textPrimary)
                    .multilineTextAlignment(.center).accessibilityAddTraits(.isHeader).padding(.top, CySpace.xl)
                Text(message).font(.system(.subheadline)).foregroundStyle(theme.textSecondary).multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("discardMessage")
                    .padding(.top, CySpace.s).padding(.bottom, CySpace.l)
                Rectangle().fill(theme.separator).frame(height: 1)
                Button(action: onDiscard) {
                    Text("Discard workout").font(.system(.headline, design: .rounded)).foregroundStyle(theme.danger)
                        .frame(maxWidth: .infinity, minHeight: 50).contentShape(Rectangle())
                }
                .buttonStyle(.plain).accessibilityIdentifier("discardConfirm")
                Rectangle().fill(theme.separator).frame(height: 1)
                Button(action: onKeep) {
                    Text("Keep workout").font(.system(.headline, design: .rounded)).foregroundStyle(theme.textPrimary)
                        .frame(maxWidth: .infinity, minHeight: 50).contentShape(Rectangle())
                }
                .buttonStyle(.plain).accessibilityIdentifier("discardKeep")
            }
            .padding(.horizontal, CySpace.xl).padding(.bottom, CySpace.s)
            .background(RoundedRectangle(cornerRadius: 26, style: .continuous).fill(theme.surface2))
            .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).strokeBorder(theme.id == .highContrast ? theme.border : Color.clear, lineWidth: theme.borderWidth))
            .padding(.horizontal, 32)
            .accessibilityElement(children: .contain)
            .accessibilityAddTraits(.isModal)
            .accessibilityIdentifier("discardDialog")
        }
    }
}
