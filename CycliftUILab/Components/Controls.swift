import SwiftUI

// Seven-day strip, session status icons, checklist, segmented control, selection cards, form field,
// sport selection, confirmation and review sheets, and the navigation prototype (tab bar).

// MARK: Seven-day training strip

struct CyWeekStrip: View {
    let days: [CyDayModel]
    var isLoading: Bool = false
    let onDay: (CyDayModel) -> Void
    @Environment(\.cyTheme) private var theme

    var body: some View {
        CyCard(padding: CySpace.s) {
            if isLoading {
                HStack(spacing: CySpace.xs) { ForEach(0..<7, id: \.self) { _ in CySkeleton(height: 56) } }
            } else if days.isEmpty {
                Text("No plan for this week yet.").font(CyFont.callout).foregroundStyle(theme.textSecondary)
                    .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading).padding(.horizontal, CySpace.s)
            } else {
                HStack(spacing: 2) { ForEach(days) { d in cell(d) } }
            }
        }
    }

    private func cell(_ d: CyDayModel) -> some View {
        Button(action: { onDay(d) }) {
            VStack(spacing: 3) {
                Text(d.weekday.prefix(1)).font(.caption2.weight(.semibold)).foregroundStyle(d.isToday ? theme.accent : theme.textSecondary)
                ZStack {
                    if d.sessions.isEmpty {
                        Image(systemName: CyCategory.rest.icon).font(.caption).foregroundStyle(theme.textTertiary)
                    } else {
                        VStack(spacing: 1) {
                            ForEach(Array(d.sessions.prefix(2).enumerated()), id: \.offset) { _, s in
                                Image(systemName: s.icon).font(d.sessions.count > 1 ? .caption2 : .caption).foregroundStyle(s.color(theme))
                            }
                        }
                    }
                }
                .frame(height: 26)
                Image(systemName: d.status.icon).font(.caption2).foregroundStyle(d.status.color(theme))
            }
            .frame(maxWidth: .infinity, minHeight: 60)
            .padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: CyRadius.s, style: .continuous).fill(d.isToday ? theme.selectedFill : Color.clear))
            .overlay(RoundedRectangle(cornerRadius: CyRadius.s, style: .continuous).strokeBorder(d.isToday ? theme.selectedBorder : Color.clear, lineWidth: 1.5))
            .contentShape(Rectangle())
        }
        .buttonStyle(CyRingButtonStyle())
        .accessibilityLabel("\(d.weekday) \(d.dayNumber)\(d.isToday ? ", today" : "")")
        .accessibilityValue(d.detail)
        .accessibilityHint("Opens the day")
    }
}

// MARK: Session status icons (legend)

struct CyStatusLegend: View {
    let statuses: [CySessionStatus]
    @Environment(\.cyTheme) private var theme
    var body: some View {
        VStack(alignment: .leading, spacing: CySpace.s) {
            ForEach(Array(statuses.enumerated()), id: \.offset) { _, s in
                HStack(spacing: CySpace.s) {
                    Image(systemName: s.icon).foregroundStyle(s.color(theme)).frame(width: 22)
                    Text(s.label).font(CyFont.callout).foregroundStyle(theme.textPrimary)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }
}

// MARK: Checklist

struct CyChecklist: View {
    let items: [CyChecklistItem]
    var isEnabled: Bool = true
    let onItem: (CyChecklistItem) -> Void
    @Environment(\.cyTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(items) { item in
                Button(action: { onItem(item) }) {
                    HStack(alignment: .top, spacing: CySpace.m) {
                        Image(systemName: item.isDone ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(item.isDone ? theme.success : (isEnabled ? theme.textTertiary : theme.disabledText))
                            .font(.body)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.title).font(CyFont.callout)
                                .foregroundStyle(isEnabled ? theme.textPrimary : theme.disabledText)
                                .strikethrough(item.isDone, color: theme.textTertiary)
                                .fixedSize(horizontal: false, vertical: true)
                            if let d = item.detail {
                                Text(d).font(.caption2).foregroundStyle(isEnabled ? theme.textSecondary : theme.disabledText).fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        Spacer(minLength: 0)
                        if !item.isEssential { Text("Optional").font(.caption2).foregroundStyle(theme.textTertiary) }
                        if !item.isDone { Image(systemName: "chevron.right").font(.caption2.weight(.semibold)).foregroundStyle(theme.textTertiary) }
                    }
                    .frame(minHeight: CyHit.min)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!isEnabled)
                .accessibilityLabel(item.title)
                .accessibilityValue("\(item.isDone ? "done" : "not done")\(item.isEssential ? "" : ", optional")")
                if item.id != items.last?.id { Rectangle().fill(theme.separator).frame(height: 1).padding(.leading, 34) }
            }
        }
    }
}

// MARK: Segmented control

struct CySegmented: View {
    let options: [String]
    @Binding var selection: Int
    var isEnabled: Bool = true
    @Environment(\.cyTheme) private var theme

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Array(options.enumerated()), id: \.offset) { i, title in
                Button(action: { withAnimation(.easeOut(duration: 0.15)) { selection = i } }) {
                    Text(title).font(CyFont.caption)
                        .foregroundStyle(!isEnabled ? theme.disabledText : (selection == i ? theme.textOnAccent : theme.textSecondary))
                        .lineLimit(1).minimumScaleFactor(0.7)
                        .frame(maxWidth: .infinity, minHeight: 36)
                        .background(RoundedRectangle(cornerRadius: CyRadius.s - 2, style: .continuous).fill(selection == i ? (isEnabled ? theme.accent : theme.disabledFill) : Color.clear))
                        .frame(minHeight: CyHit.min)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(title)
                .accessibilityAddTraits(selection == i ? .isSelected : [])
            }
        }
        .padding(.horizontal, 3)
        .background(RoundedRectangle(cornerRadius: CyRadius.s, style: .continuous).fill(theme.surface2).padding(.vertical, 2))
        .overlay(RoundedRectangle(cornerRadius: CyRadius.s, style: .continuous).strokeBorder(theme.border, lineWidth: theme.borderWidth).padding(.vertical, 2))
        .disabled(!isEnabled)
    }
}

// MARK: Selection card

struct CySelectionCard: View {
    let title: String
    var subtitle: String? = nil
    var icon: String? = nil
    let isSelected: Bool
    var isEnabled: Bool = true
    let action: () -> Void
    @Environment(\.cyTheme) private var theme

    var body: some View {
        Button(action: action) {
            CyCard(padding: CySpace.m, isSelected: isSelected) {
                HStack(alignment: .center, spacing: CySpace.m) {
                    if let icon {
                        Image(systemName: icon).font(.title3).foregroundStyle(isEnabled ? (isSelected ? theme.accent : theme.textSecondary) : theme.disabledText).frame(width: 30)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title).font(CyFont.headline).foregroundStyle(isEnabled ? theme.textPrimary : theme.disabledText).fixedSize(horizontal: false, vertical: true)
                        if let subtitle {
                            Text(subtitle).font(CyFont.footnote).foregroundStyle(isEnabled ? theme.textSecondary : theme.disabledText).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Spacer(minLength: 0)
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(isEnabled ? (isSelected ? theme.accent : theme.textTertiary) : theme.disabledText)
                }
                .frame(minHeight: CyHit.min)
            }
        }
        .buttonStyle(CyCardButtonStyle())
        .disabled(!isEnabled)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([title, subtitle ?? ""].filter { !$0.isEmpty }.joined(separator: ", "))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

// MARK: Sport selection

struct CySportOption: Identifiable, Equatable {
    let id: String
    let title: String
    let icon: String
    let note: String?            // e.g. "Logging only" — support level is always stated, never implied
    var isAvailable: Bool = true
}

struct CySportPicker: View {
    let options: [CySportOption]
    @Binding var selection: Set<String>
    private let columns = [GridItem(.adaptive(minimum: 150), spacing: CySpace.s)]
    var body: some View {
        LazyVGrid(columns: columns, spacing: CySpace.s) {
            ForEach(options) { o in
                CySelectionCard(title: o.title, subtitle: o.note, icon: o.icon, isSelected: selection.contains(o.id), isEnabled: o.isAvailable) {
                    if selection.contains(o.id) { selection.remove(o.id) } else { selection.insert(o.id) }
                }
            }
        }
    }
}

// MARK: Form field

struct CyFormField: View {
    let label: String
    @Binding var text: String
    var placeholder: String = ""
    var help: String? = nil
    var error: String? = nil
    var unit: String? = nil
    var isEnabled: Bool = true
    @Environment(\.cyTheme) private var theme
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: CySpace.xs) {
            Text(label).font(CyFont.caption).foregroundStyle(theme.textSecondary)
            HStack(spacing: CySpace.s) {
                TextField("", text: $text, prompt: Text(placeholder).foregroundColor(theme.textTertiary))
                    .font(CyFont.body)
                    .foregroundStyle(isEnabled ? theme.textPrimary : theme.disabledText)
                    .focused($focused)
                    .disabled(!isEnabled)
                    .accessibilityLabel(label)
                if let unit { Text(unit).font(CyFont.callout).foregroundStyle(theme.textSecondary) }
            }
            .padding(.horizontal, CySpace.m)
            .frame(minHeight: 48)
            .background(RoundedRectangle(cornerRadius: CyRadius.s, style: .continuous).fill(isEnabled ? theme.surface2 : theme.disabledFill))
            .overlay(RoundedRectangle(cornerRadius: CyRadius.s, style: .continuous)
                .strokeBorder(error != nil ? theme.danger : (focused ? theme.accent : theme.border), lineWidth: (focused || error != nil) ? 2 : theme.borderWidth))
            if let error {
                HStack(spacing: CySpace.xs) {
                    Image(systemName: "exclamationmark.circle.fill")
                    Text(error).fixedSize(horizontal: false, vertical: true)
                }
                .font(.caption2).foregroundStyle(theme.danger)
                .accessibilityElement(children: .combine)
            } else if let help {
                Text(help).font(.caption2).foregroundStyle(theme.textTertiary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: Sheets

/// Shared sheet chrome: themed background, title, optional close.
struct CySheet<Content: View>: View {
    let title: String
    var onClose: (() -> Void)? = nil
    @ViewBuilder let content: () -> Content
    @Environment(\.cyTheme) private var theme

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: CySpace.l) {
                HStack(alignment: .top) {
                    Text(title).font(CyFont.title).foregroundStyle(theme.textPrimary).fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                    Spacer(minLength: CySpace.m)
                    if let onClose { CyIconButton(systemName: "xmark", label: "Close", action: onClose) }
                }
                content()
            }
            .padding(CySpace.l)
        }
        .background(theme.background.ignoresSafeArea())
        .preferredColorScheme(theme.scheme)
    }
}

struct CyConfirmSheet: View {
    let title: String
    let message: String
    let confirmTitle: String
    var isDestructive: Bool = false
    var isWorking: Bool = false
    let onConfirm: () -> Void
    let onCancel: () -> Void
    @Environment(\.cyTheme) private var theme

    var body: some View {
        CySheet(title: title) {
            Text(message).font(CyFont.body).foregroundStyle(theme.textSecondary).fixedSize(horizontal: false, vertical: true)
            VStack(spacing: CySpace.s) {
                CyButton(title: confirmTitle, kind: isDestructive ? .destructive : .primary, isLoading: isWorking, action: onConfirm)
                CyButton(title: "Cancel", kind: .secondary, action: onCancel).disabled(isWorking)
            }
        }
    }
}

/// Review and approval: what would change, why, expected benefit and possible impact; approve / not now / decline.
/// Nothing changes until Approve (owner Decision 1). The sheet only reports the choice through callbacks.
struct CyReviewSheet: View {
    let title: String
    let reason: String
    let benefit: String
    let impact: String
    let changes: [CyChange]
    var canApprove: Bool = true
    var blockedReason: String? = nil
    let onApprove: () -> Void
    let onPostpone: () -> Void
    let onDecline: () -> Void
    @Environment(\.cyTheme) private var theme

    var body: some View {
        CySheet(title: title) {
            CyCard(padding: CySpace.m) {
                VStack(alignment: .leading, spacing: CySpace.m) {
                    CyOverline(text: "What would change")
                    if changes.isEmpty {
                        Text("No changes to review.").font(CyFont.callout).foregroundStyle(theme.textSecondary)
                    }
                    ForEach(changes) { c in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(c.label).font(CyFont.caption).foregroundStyle(theme.textSecondary)
                            HStack(spacing: CySpace.s) {
                                Text(c.before).font(CyFont.callout).foregroundStyle(theme.textTertiary).strikethrough()
                                Image(systemName: "arrow.right").font(.caption2).foregroundStyle(theme.textTertiary).accessibilityHidden(true)
                                Text(c.after).font(CyFont.callout.weight(.semibold)).foregroundStyle(theme.textPrimary)
                            }
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("\(c.label): from \(c.before) to \(c.after)")
                    }
                }
            }
            labelled("Why", reason)
            labelled("Expected benefit", benefit)
            labelled("Possible impact", impact)
            if let blockedReason {
                HStack(alignment: .top, spacing: CySpace.s) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(theme.warning)
                    Text(blockedReason).font(CyFont.footnote).foregroundStyle(theme.textPrimary).fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
            }
            Text("Nothing changes until you approve.").font(.caption2).foregroundStyle(theme.textTertiary)
            VStack(spacing: CySpace.s) {
                CyButton(title: "Approve", icon: "checkmark", kind: .primary, action: onApprove).disabled(!canApprove)
                CyButton(title: "Not now", kind: .secondary, action: onPostpone)
                CyButton(title: "Decline", kind: .destructive, action: onDecline)
            }
        }
    }
    private func labelled(_ head: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            CyOverline(text: head)
            Text(body).font(CyFont.callout).foregroundStyle(theme.textPrimary).fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: Navigation prototype (tab bar with centre action)

struct CyTabItem: Identifiable, Equatable {
    let id: String
    let title: String
    let icon: String
}

struct CyTabBar: View {
    let items: [CyTabItem]          // four items; the centre action sits between the 2nd and 3rd
    @Binding var selection: String
    let centreTitle: String
    var centreBadge: Int? = nil
    let onCentre: () -> Void
    @Environment(\.cyTheme) private var theme

    var body: some View {
        HStack(alignment: .bottom, spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { i, item in
                if i == items.count / 2 { centre }
                tab(item)
            }
        }
        .padding(.horizontal, CySpace.s)
        .padding(.top, CySpace.s)
        .background(theme.surface.ignoresSafeArea(edges: .bottom))
        .overlay(Rectangle().fill(theme.border).frame(height: theme.borderWidth), alignment: .top)
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }
    private func tab(_ item: CyTabItem) -> some View {
        Button(action: { selection = item.id }) {
            VStack(spacing: 3) {
                Image(systemName: item.icon).font(.body.weight(selection == item.id ? .semibold : .regular))
                Text(item.title).font(.caption2.weight(.medium)).lineLimit(1).minimumScaleFactor(0.7)
            }
            .foregroundStyle(selection == item.id ? theme.accent : theme.textTertiary)
            .frame(maxWidth: .infinity, minHeight: 48)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(item.title)
        .accessibilityAddTraits(selection == item.id ? [.isButton, .isSelected] : .isButton)
    }
    private var centre: some View {
        Button(action: onCentre) {
            VStack(spacing: 3) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: "figure.strengthtraining.functional")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(theme.textOnAccent)
                        .frame(width: 52, height: 52)
                        .background(Circle().fill(theme.accent))
                        .overlay(Circle().strokeBorder(theme.surface, lineWidth: 3))
                    if let b = centreBadge, b > 0 {
                        Text("\(b)").font(.caption2.weight(.bold)).foregroundStyle(theme.textPrimary)
                            .frame(minWidth: 18, minHeight: 18)
                            .background(Circle().fill(theme.surface2))
                            .overlay(Circle().strokeBorder(theme.border, lineWidth: 1))
                    }
                }
                .offset(y: -10)
                Text(centreTitle).font(.caption2.weight(.medium)).foregroundStyle(theme.textSecondary).offset(y: -8)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(CyRingButtonStyle())
        .accessibilityLabel(centreBadge.map { "\(centreTitle), \($0) sessions today" } ?? centreTitle)
    }
}
