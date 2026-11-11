import SwiftUI

// Buttons: primary, secondary, destructive, compact action, icon-only; disabled and loading states.
// Inputs: title / icon / state. Output: one action callback. No navigation or data dependencies.

enum CyButtonKind { case primary, secondary, destructive, compact }

struct CyButtonStyle: ButtonStyle {
    let kind: CyButtonKind
    var fullWidth: Bool = true
    @Environment(\.cyTheme) private var theme
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: kind == .compact ? CyRadius.s : CyRadius.m, style: .continuous)
        configuration.label
            .font(kind == .compact ? CyFont.caption : CyFont.headline)
            .multilineTextAlignment(.center)
            .foregroundStyle(foreground)
            .padding(.horizontal, kind == .compact ? CySpace.m : CySpace.l)
            .padding(.vertical, kind == .compact ? CySpace.s : CySpace.m)
            .frame(maxWidth: (fullWidth && kind != .compact) ? .infinity : nil, minHeight: CyHit.min)
            .background(shape.fill(background))
            .overlay(shape.strokeBorder(borderColor, lineWidth: theme.borderWidth))
            .overlay(shape.fill(configuration.isPressed ? theme.pressedOverlay : Color.clear))
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
            .contentShape(shape)
    }

    private var foreground: Color {
        guard isEnabled else { return theme.disabledText }
        switch kind {
        case .primary: return theme.textOnAccent
        case .secondary, .compact: return theme.accent
        case .destructive: return theme.danger
        }
    }
    private var background: Color {
        guard isEnabled else { return theme.disabledFill }
        switch kind {
        case .primary: return theme.accent
        case .secondary, .compact: return theme.accentSubtle
        case .destructive: return theme.danger.opacity(theme.isDark ? 0.16 : 0.10)
        }
    }
    private var borderColor: Color {
        guard isEnabled else { return theme.id == .highContrast ? theme.disabledText : Color.clear }
        switch kind {
        case .primary: return Color.clear
        case .secondary, .compact: return theme.id == .highContrast ? theme.accent : Color.clear
        case .destructive: return theme.id == .highContrast ? theme.danger : Color.clear
        }
    }
}

struct CyButton: View {
    let title: String
    var icon: String? = nil
    var kind: CyButtonKind = .primary
    var isLoading: Bool = false
    var fullWidth: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: { if !isLoading { action() } }) {
            HStack(spacing: CySpace.s) {
                if isLoading {
                    ProgressView().controlSize(.small)
                } else if let icon {
                    Image(systemName: icon).imageScale(.medium)
                }
                Text(title)
            }
        }
        .buttonStyle(CyButtonStyle(kind: kind, fullWidth: fullWidth))
        .accessibilityLabel(isLoading ? "\(title), loading" : title)
    }
}

struct CyIconButton: View {
    let systemName: String
    let label: String            // accessibility label — required, an icon is never the only description
    var isSelected: Bool = false
    let action: () -> Void
    @Environment(\.cyTheme) private var theme
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.body.weight(.semibold))
                .foregroundStyle(isEnabled ? (isSelected ? theme.textOnAccent : theme.accent) : theme.disabledText)
                .frame(width: CyHit.min, height: CyHit.min)
                .background(Circle().fill(isEnabled ? (isSelected ? theme.accent : theme.accentSubtle) : theme.disabledFill))
                .overlay(Circle().strokeBorder(theme.id == .highContrast ? theme.border : Color.clear, lineWidth: theme.borderWidth))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
