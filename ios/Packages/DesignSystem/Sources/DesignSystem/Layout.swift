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

/// Corner radii: generous, like worn paper. 14 (small controls), 22 (cards), 32 (sheets and panels), pill.
public enum Radius {
    public static let small: CGFloat = 14
    public static let card: CGFloat = 22
    public static let sheet: CGFloat = 32
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

    /// A paper page: cream with fine grain. Used for the quieter places behind the scene
    /// (lists, forms, settings). Content on it uses the ordinary ink colors.
    func pageBackground() -> some View {
        environment(\.skyMoment, nil)
            .background {
                ZStack {
                    Color.surface
                    PaperGrain(opacity: 0.03)
                }
                .ignoresSafeArea()
            }
    }
}

/// Motion tokens (10 §7, 06 §6): gentle springs of 200–450 ms; celebrations up to 1.2 s, once.
public enum Motion {
    public static let quick: Animation = .spring(duration: 0.2, bounce: 0.1)
    public static let standard: Animation = .spring(duration: 0.35, bounce: 0.2)
    public static let gentle: Animation = .spring(duration: 0.45, bounce: 0.25)
    public static let entrance: Animation = .easeOut(duration: 0.3)
    public static let celebration: Animation = .spring(duration: 1.1, bounce: 0.3)
    /// The two lights drifting toward or away from each other.
    public static let drift: Animation = .spring(duration: 0.7, bounce: 0.18)
    /// The two lights meeting.
    public static let meet: Animation = .spring(duration: 0.5, bounce: 0.32)
    /// Light changing in the sky.
    public static let light: Animation = .easeInOut(duration: 1.0)
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

/// The haptic vocabulary. Each word means one thing everywhere; there is no "denied" buzz.
///
/// - `tick`: a choice changed (a length, a place, a step of a slider).
/// - `touch`: something answered your finger (a light picked up, a button that starts something).
/// - `settle`: something was saved or sent and is now at rest.
/// - `meet`: the two lights met (an unlock started, pairing completed).
/// - `warmth`: warmth arrived (kudos, a milestone): three soft, rising taps.
@MainActor
public enum Haptics {
    public static func tick() { UISelectionFeedbackGenerator().selectionChanged() }
    public static func touch() { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
    public static func settle() { UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.7) }

    public static func meet() {
        UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.6)
        Task {
            try? await Task.sleep(for: .milliseconds(120))
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
    }

    public static func warmth() {
        Task {
            for intensity in [0.4, 0.65, 0.9] {
                UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: intensity)
                try? await Task.sleep(for: .milliseconds(140))
            }
        }
    }
}
