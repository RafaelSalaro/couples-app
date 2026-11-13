import SwiftUI
import UIKit

/// Spacing scale: 4, 8, 12, 16, 24, 32, 48.
public enum Spacing {
    public static let xxs: CGFloat = 4
    public static let xs: CGFloat = 8
    public static let sm: CGFloat = 12
    public static let md: CGFloat = 16
    public static let lg: CGFloat = 24
    public static let xl: CGFloat = 32
    public static let xxl: CGFloat = 48
    public static let all: [CGFloat] = [xxs, xs, sm, md, lg, xl, xxl]
}

/// Corner radii: 10 (small controls), 16 (cards), 24 (sheets, large cards), pill.
public enum Radius {
    public static let small: CGFloat = 10
    public static let card: CGFloat = 16
    public static let sheet: CGFloat = 24
    public static let pill: CGFloat = 999
}

public enum Sizing {
    /// Minimum touch target (06 §11).
    public static let minTouchTarget: CGFloat = 44
}

private struct WarmShadow: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        // Very soft and warm in light theme; none in dark (surface-raised carries the contrast).
        if colorScheme == .dark {
            content
        } else {
            let ink = Color(uiColor: UIColor(hex: ColorToken.ink.light))
            content
                .shadow(color: ink.opacity(0.06), radius: 1, x: 0, y: 1)
                .shadow(color: ink.opacity(0.08), radius: 12, x: 0, y: 8)
        }
    }
}

public extension View {
    func warmShadow() -> some View { modifier(WarmShadow()) }

    /// Full-screen cream page background.
    func pageBackground() -> some View {
        background(Color.surface.ignoresSafeArea())
    }
}

/// Motion tokens (10 §7, 06 §6): gentle springs of 200–450 ms; celebrations up to 1.2 s, once.
public enum Motion {
    public static let quick: Animation = .spring(duration: 0.2, bounce: 0.1)
    public static let standard: Animation = .spring(duration: 0.35, bounce: 0.2)
    public static let gentle: Animation = .spring(duration: 0.45, bounce: 0.25)
    public static let entrance: Animation = .easeOut(duration: 0.3)
    public static let celebration: Animation = .spring(duration: 1.1, bounce: 0.3)
    /// What movement becomes when Reduce Motion is on.
    public static let fade: Animation = .easeInOut(duration: 0.25)

    public static let celebrationDuration: TimeInterval = 1.2
    public static let maxStandardDuration: TimeInterval = 0.45

    /// The animation to use given the Reduce Motion setting: movement becomes a fade.
    public static func resolve(_ animation: Animation, reduceMotion: Bool) -> Animation {
        reduceMotion ? fade : animation
    }

    /// Stagger for list or chart entrances (seconds per item); zero with Reduce Motion.
    public static func stagger(index: Int, reduceMotion: Bool) -> TimeInterval {
        reduceMotion ? 0 : Double(index) * 0.05
    }
}

private struct MotionAware<Value: Equatable>: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let animation: Animation
    let value: Value

    func body(content: Content) -> some View {
        content.animation(Motion.resolve(animation, reduceMotion: reduceMotion), value: value)
    }
}

private struct MoveOrFade: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let edge: Edge

    func body(content: Content) -> some View {
        content.transition(reduceMotion ? .opacity : .move(edge: edge).combined(with: .opacity))
    }
}

public extension View {
    /// Animates changes of `value`, replacing movement with a fade under Reduce Motion.
    func motion<Value: Equatable>(_ animation: Animation = Motion.standard, value: Value) -> some View {
        modifier(MotionAware(animation: animation, value: value))
    }

    /// Slide-in transition that becomes a cross-fade under Reduce Motion.
    func moveOrFade(from edge: Edge = .bottom) -> some View {
        modifier(MoveOrFade(edge: edge))
    }
}

/// Haptics for the signature moments. Never a "denied" buzz.
@MainActor
public enum Haptics {
    public static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    public static func light() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    public static func soft() {
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
    }

    public static func selection() {
        UISelectionFeedbackGenerator().selectionChanged()
    }
}
