import SwiftUI

/// Button looks. `destructive` is the only red one and is reserved for
/// truly destructive actions (delete account, confirm unpair).
public enum ButtonKind: Sendable, CaseIterable {
    case primary, secondary, quiet, glow, onDusk, destructive
}

public struct DSButtonStyle: ButtonStyle {
    let kind: ButtonKind
    let fullWidth: Bool
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.skyMoment) private var skyMoment
    @Environment(\.colorScheme) private var scheme

    public init(_ kind: ButtonKind = .primary, fullWidth: Bool = true) {
        self.kind = kind
        self.fullWidth = fullWidth
    }

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .textRole(.heading)
            .multilineTextAlignment(.center)
            .foregroundStyle(foreground)
            .padding(.horizontal, Spacing.lg)
            .padding(.vertical, Spacing.sm)
            .frame(maxWidth: fullWidth ? .infinity : nil, minHeight: Sizing.minTouchTarget + 4)
            .background(background, in: Capsule())
            .overlay {
                if kind == .secondary {
                    Capsule().strokeBorder(Color.line, lineWidth: 1)
                }
            }
            .opacity(isEnabled ? (configuration.isPressed ? 0.85 : 1) : 0.45)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
            .animation(Motion.resolve(Motion.quick, reduceMotion: reduceMotion), value: configuration.isPressed)
            .contentShape(Capsule())
    }

    private var foreground: Color {
        switch kind {
        case .primary: .onHearth
        case .secondary: .ink
        // On a dark sky a quiet button is cream, so it stays legible.
        case .quiet: skyMoment != nil && SkyInk(moment: skyMoment, scheme: scheme).isDark ? SkyInk(moment: skyMoment, scheme: scheme).primary : .hearth
        case .glow: .onGlow
        case .onDusk: .dusk
        case .destructive: .surfaceRaised
        }
    }

    private var background: Color {
        switch kind {
        case .primary: .hearth
        case .secondary: .surfaceRaised
        case .quiet: .clear
        case .glow: .glow
        case .onDusk: .onDusk
        case .destructive: .danger
        }
    }
}

public extension ButtonStyle where Self == DSButtonStyle {
    static var dsPrimary: DSButtonStyle { DSButtonStyle(.primary) }
    static var dsSecondary: DSButtonStyle { DSButtonStyle(.secondary) }
    static var dsQuiet: DSButtonStyle { DSButtonStyle(.quiet) }
    static var dsGlow: DSButtonStyle { DSButtonStyle(.glow) }
    static var dsOnDusk: DSButtonStyle { DSButtonStyle(.onDusk) }
    /// Red. Destructive actions only.
    static var dsDestructive: DSButtonStyle { DSButtonStyle(.destructive) }
    static func ds(_ kind: ButtonKind, fullWidth: Bool = true) -> DSButtonStyle {
        DSButtonStyle(kind, fullWidth: fullWidth)
    }
}

/// A selectable pill (unlock lengths, categories, weekdays).
public struct Chip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    public init(_ title: String, isSelected: Bool, action: @escaping () -> Void) {
        self.title = title
        self.isSelected = isSelected
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Text(title)
                .textRole(.callout)
                .foregroundStyle(isSelected ? Color.onHearth : Color.ink)
                .padding(.horizontal, Spacing.md)
                .frame(minWidth: Sizing.minTouchTarget, minHeight: Sizing.minTouchTarget)
                .background(isSelected ? Color.hearth : Color.surfaceRaised, in: Capsule())
                .overlay { Capsule().strokeBorder(isSelected ? Color.clear : Color.line, lineWidth: 1) }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}
