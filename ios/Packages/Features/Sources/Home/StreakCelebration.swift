import Core
import DesignSystem
import FeatureSupport
import SwiftUI

/// Signature moment 4: shared pride. The two lights settle fully together and a few warm
/// sparks drift up, once. With Reduce Motion the lights are simply shown together.
public struct StreakCelebrationView: View {
    let days: Int
    let onDone: () -> Void
    @State private var lit = false

    public init(days: Int, onDone: @escaping () -> Void) {
        self.days = days
        self.onDone = onDone
    }

    public var body: some View {
        ZStack {
            ParticleDrift(isActive: lit)
            VStack(spacing: Spacing.lg) {
                Spacer()
                TwoLights(closeness: lit ? 1 : 0.5, diameter: 120, overlap: 0.6, glow: lit ? 1 : 0.3)
                    .accessibilityHidden(true)
                SkyText(days.formatted(), role: .numeralLarge)
                    .scaleEffect(lit ? 1 : 0.8)
                    .motion(Motion.celebration, value: lit)
                SkyText(L("evenings in a row, together"), role: .display)
                    .multilineTextAlignment(.center)
                    .accessibilityIdentifier("celebration.streak")
                SkyText(L("That's the two of you, choosing each other."), role: .body, muted: true)
                    .multilineTextAlignment(.center)
                Spacer()
                Button(L("Lovely"), action: onDone)
                    .buttonStyle(.dsPrimary)
                    .accessibilityIdentifier("celebration.done")
            }
            .padding(Spacing.lg)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onSky(.dusk)
        .accessibilityElement(children: .contain)
        .task {
            try? await Task.sleep(for: .milliseconds(250))
            lit = true
            Haptics.warmth()
        }
    }
}
