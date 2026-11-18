import SwiftUI

// Training Hub v1.4 — the strength preparation screen (sheet 01a "J2 Prepare"; golden journey sheet G3).
// A dark, full page: back; "Strength · planned today"; the session's name; "About 35 min · equipment"; the exercises in
// order with their sets × reps, a superset shown as one group with its rounds; one Start button at the bottom.
// It starts the session through the SAME call the existing session page uses (StrengthWorkoutScreen passes it in); it
// has no logic of its own. One addition to the sheet, stated: a "More" button, top right, opens the existing session
// page — adjust sets, swap, why, choose a routine, move, skip, quick log — so no existing function is lost.

struct StrengthPrepareV14: View {
    let overline: String
    let title: String
    let summary: String
    let groups: [PrepareGroup]
    var startLabel: String = "Start"
    let onBack: () -> Void
    let onMore: () -> Void
    let onStart: () -> Void
    @Environment(\.cyTheme) private var theme
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                round("chevron.left", label: "Back", id: "prepareBack", action: onBack)
                Spacer(minLength: 0)
                round("ellipsis", label: "More", id: "prepareMore", action: onMore)
                    .accessibilityHint("Adjust sets, swap an exercise, choose a routine, move or skip this session")
            }
            .padding(.horizontal, CySpace.l).padding(.top, CySpace.s)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: CySpace.s) {
                        RoundedRectangle(cornerRadius: 1.5).fill(theme.strength).frame(width: 3, height: 16).accessibilityHidden(true)
                        Text(overline).font(CyFont.label).foregroundStyle(theme.textSecondary)
                            .accessibilityIdentifier("prepareOverline")
                    }
                    .padding(.top, CySpace.l)
                    Text(title).font(.system(.largeTitle, design: .rounded).weight(.bold)).foregroundStyle(theme.textPrimary)
                        .lineLimit(typeSize.isAccessibilitySize ? 4 : 2).minimumScaleFactor(0.7).fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 6)
                        .accessibilityAddTraits(.isHeader).accessibilityIdentifier("prepareTitle")
                    if !summary.isEmpty {
                        Text(summary).font(CyFont.body).foregroundStyle(theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true).padding(.top, 6)
                            .accessibilityIdentifier("prepareSummary")
                    }
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(groups) { g in group(g) }
                    }
                    .padding(.top, CySpace.xl)
                }
                .padding(.horizontal, CySpace.l).padding(.bottom, CySpace.xl)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Button(action: onStart) {
                Text(startLabel).font(.headline).foregroundStyle(theme.textOnAccent)
                    .frame(maxWidth: .infinity, minHeight: 56)
                    .background(RoundedRectangle(cornerRadius: CyRadius.m, style: .continuous).fill(theme.accent))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("startWorkout")            // the identifier the existing journeys already use for Start
            .padding(.horizontal, CySpace.l).padding(.vertical, CySpace.s)
        }
        .background(theme.background.ignoresSafeArea())
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("strengthPrepareV14")
    }

    @ViewBuilder private func group(_ g: PrepareGroup) -> some View {
        if let heading = g.heading {
            Text(heading.uppercased()).font(CyFont.overline).tracking(1.1).foregroundStyle(theme.textSecondary)
                .padding(.top, CySpace.m).padding(.bottom, 2)
                .accessibilityAddTraits(.isHeader).accessibilityIdentifier("prepareSuperset-\(g.superset ?? "")")
            VStack(spacing: 0) {
                ForEach(Array(g.rows.enumerated()), id: \.element.id) { i, r in
                    row(r).padding(.leading, CySpace.xl)
                    if i < g.rows.count - 1 { Rectangle().fill(theme.separator).frame(height: 1).padding(.leading, CySpace.xl).accessibilityHidden(true) }
                }
            }
        } else if let r = g.rows.first {
            row(r)
        }
    }

    private func row(_ r: PrepareRow) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: CySpace.m) {
            Text(r.name).font(.system(.body, design: .rounded).weight(.semibold)).foregroundStyle(theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: CySpace.s)
            Text(r.target).font(.system(.body, design: .rounded).weight(.medium).monospacedDigit()).foregroundStyle(theme.textSecondary)
                .lineLimit(1)
        }
        .frame(minHeight: 52)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("prepareRow-\(r.id)")
    }

    private func round(_ icon: String, label: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 16, weight: .semibold)).foregroundStyle(theme.textPrimary)
                .frame(width: CyHit.min, height: CyHit.min).background(Circle().fill(theme.surface2))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label).accessibilityIdentifier(id)
    }
}
