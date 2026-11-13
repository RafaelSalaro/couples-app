import SwiftUI

/// Signature moment 1 (06 §6): Glow-colored warmth blooms from the center.
/// With Reduce Motion the bloom is a single cross-fade.
public struct GlowBloom: View {
    let isActive: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(isActive: Bool) { self.isActive = isActive }

    public var body: some View {
        Circle()
            .fill(
                RadialGradient(
                    colors: [Color.glow.opacity(0.85), Color.glow.opacity(0.25), Color.glow.opacity(0)],
                    center: .center, startRadius: 0, endRadius: 220
                )
            )
            .scaleEffect(reduceMotion ? 1 : (isActive ? 1.6 : 0.2))
            .opacity(isActive ? 1 : 0)
            .animation(Motion.resolve(Motion.celebration, reduceMotion: reduceMotion), value: isActive)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// Signature moment 4: a short, warm particle drift, played once.
/// With Reduce Motion nothing moves; the particles simply fade in and out.
public struct ParticleDrift: View {
    let isActive: Bool
    let count: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(isActive: Bool, count: Int = 14) {
        self.isActive = isActive
        self.count = count
    }

    public var body: some View {
        GeometryReader { proxy in
            ZStack {
                ForEach(0..<count, id: \.self) { index in
                    let seed = Self.seed(index)
                    Circle()
                        .fill(index.isMultiple(of: 2) ? Color.glow : Color.hearth)
                        .frame(width: 6 + seed.size * 6, height: 6 + seed.size * 6)
                        .position(
                            x: proxy.size.width * seed.x,
                            y: proxy.size.height * (reduceMotion ? seed.y : (isActive ? seed.y * 0.5 : 0.9))
                        )
                        .opacity(isActive ? 0.8 : 0)
                        .animation(
                            Motion.resolve(Motion.celebration, reduceMotion: reduceMotion)
                                .delay(Motion.stagger(index: index, reduceMotion: reduceMotion) * 0.5),
                            value: isActive
                        )
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// Deterministic pseudo-random layout so the drift looks the same every time (and in snapshots).
    nonisolated static func seed(_ index: Int) -> (x: CGFloat, y: CGFloat, size: CGFloat) {
        func unit(_ n: Int) -> CGFloat {
            let v = sin(Double(n) * 12.9898) * 43758.5453
            return CGFloat(v - floor(v))
        }
        return (unit(index * 3 + 1), unit(index * 3 + 2), unit(index * 3 + 3))
    }
}

/// Signature moments 3 and 6: two circles (or avatars) slide together and settle overlapped.
public struct ComingTogether: View {
    let together: Bool
    let diameter: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(together: Bool, diameter: CGFloat = 64) {
        self.together = together
        self.diameter = diameter
    }

    public var body: some View {
        TwoCirclesMark(overlap: reduceMotion ? 1 : (together ? 1 : 0), diameter: diameter)
            .opacity(reduceMotion ? (together ? 1 : 0.4) : 1)
            .animation(Motion.resolve(Motion.gentle, reduceMotion: reduceMotion), value: together)
    }
}
