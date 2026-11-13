import SnapshotSupport
import SwiftUI
import Testing
import UIKit
@testable import DesignSystem

@Suite struct ColorTokenTests {
    @Test func paletteMatchesBrandDocument() {
        #expect(ColorToken.surface.light == 0xFBF6F0)
        #expect(ColorToken.surface.dark == 0x191513)
        #expect(ColorToken.hearth.light == 0xAD472E)
        #expect(ColorToken.hearth.dark == 0xE8836A)
        #expect(ColorToken.glow.light == 0xE9A23B)
        #expect(ColorToken.sage.light == 0x4A6E53)
        #expect(ColorToken.dusk.light == 0x2C2430)
        #expect(ColorToken.danger.light == 0xA8322A)
        #expect(ColorToken.partnerA == ColorToken.hearth)
        #expect(ColorToken.partnerB == ColorToken.glow)
        #expect(ColorToken.all.count == 19)
        #expect(Set(ColorToken.all.map(\.name)).count == 19)
    }

    /// Every text-on-background pairing the components use meets WCAG AA (4.5:1) in both themes.
    @Test(arguments: [ColorScheme.light, ColorScheme.dark])
    func textPairingsMeetAA(scheme: ColorScheme) {
        let pairs: [(ColorToken, ColorToken)] = [
            (.ink, .surface), (.ink, .surfaceRaised), (.ink, .surfaceSunken),
            (.inkMuted, .surface), (.inkMuted, .surfaceRaised),
            (.hearth, .surface), (.hearth, .hearthSoft),
            (.onHearth, .hearth), (.onGlow, .glow), (.onSage, .sage),
            (.glowStrong, .surface), (.glowStrong, .glowSoft),
            (.sage, .surface), (.sage, .sageSoft),
            (.onDusk, .dusk), (.danger, .surface), (.surfaceRaised, .danger),
        ]
        for (text, background) in pairs {
            let ratio = Contrast.ratio(text.hex(for: scheme), background.hex(for: scheme))
            #expect(ratio >= 4.5, "\(text.name) on \(background.name) is \(ratio) in \(scheme)")
        }
    }

    @Test func contrastMathMatchesKnownValues() {
        #expect(abs(Contrast.ratio(0x000000, 0xFFFFFF) - 21) < 0.01)
        #expect(abs(Contrast.ratio(0xAD472E, 0xFBF6F0) - 5.2) < 0.15)
    }

    @Test func partnerColorsDifferInLightness() {
        for scheme in [ColorScheme.light, .dark] {
            let a = Contrast.relativeLuminance(ColorToken.partnerA.hex(for: scheme))
            let b = Contrast.relativeLuminance(ColorToken.partnerB.hex(for: scheme))
            #expect(abs(a - b) > 0.1)
        }
    }

    @MainActor @Test func dynamicColorResolvesPerAppearance() {
        let color = ColorToken.surface.uiColor
        let light = color.resolvedColor(with: UITraitCollection(userInterfaceStyle: .light))
        let dark = color.resolvedColor(with: UITraitCollection(userInterfaceStyle: .dark))
        #expect(light != dark)
    }
}

@Suite struct TypographyTests {
    @Test func bundledFontsRegister() {
        #expect(Typography.registerFonts())
        #expect(Typography.isAvailable(.fraunces))
        #expect(Typography.isAvailable(.instrumentSans))
    }

    @Test func rolesUseTheRightFamilies() {
        _ = Typography.registerFonts()
        #expect(Typography.uiFont(.hero).familyName == "Fraunces")
        #expect(Typography.uiFont(.title).familyName == "Fraunces")
        #expect(Typography.uiFont(.numeral).familyName == "Fraunces")
        #expect(Typography.uiFont(.body).familyName == "Instrument Sans")
        #expect(Typography.uiFont(.caption).familyName == "Instrument Sans")
    }

    @Test func scaleMatchesBrandDocument() {
        #expect(TextRole.hero.pointSize == 44)
        #expect(TextRole.title.pointSize == 30)
        #expect(TextRole.numeral.pointSize == 40)
        #expect(TextRole.heading.pointSize == 20)
        #expect(TextRole.body.pointSize == 17)
        #expect(TextRole.callout.pointSize == 15)
        #expect(TextRole.caption.pointSize == 13)
        #expect(Typography.uiFont(.body, size: 30).pointSize == 30)
    }
}

@Suite struct LayoutAndMotionTests {
    @Test func scales() {
        #expect(Spacing.all == [4, 8, 12, 16, 24, 32, 48])
        #expect(Radius.small == 10)
        #expect(Radius.card == 16)
        #expect(Radius.sheet == 24)
        #expect(Sizing.minTouchTarget == 44)
    }

    @Test func reduceMotionRemovesStagger() {
        #expect(Motion.stagger(index: 3, reduceMotion: true) == 0)
        #expect(Motion.stagger(index: 3, reduceMotion: false) > 0)
        #expect(Motion.celebrationDuration <= 1.2)
        #expect(Motion.maxStandardDuration <= 0.45)
    }

    @Test func particleLayoutIsDeterministic() {
        let a = ParticleDrift.seed(4), b = ParticleDrift.seed(4)
        #expect(a.x == b.x && a.y == b.y && a.size == b.size)
        #expect((0...1).contains(a.x) && (0...1).contains(a.y))
    }
}

/// A gallery of every component, used for the snapshot tests.
struct ComponentGallery: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text(verbatim: "Protected time").textRole(.title).foregroundStyle(Color.ink)
            Text(verbatim: "Not about control. About being here, together.")
                .textRole(.body).foregroundStyle(Color.inkMuted)
            HStack(spacing: Spacing.lg) {
                StatTile(value: "45", label: "your minutes", tint: .hearth)
                StatTile(value: "30", label: "Ana's minutes", tint: .glowStrong)
                StatTile(value: "7", label: "day streak", tint: .sage)
            }
            Button(action: {}) { Text(verbatim: "Ask Ana") }.buttonStyle(.dsPrimary)
            Button(action: {}) { Text(verbatim: "Not now") }.buttonStyle(.dsSecondary)
            Button(action: {}) { Text(verbatim: "Give kudos") }.buttonStyle(.dsGlow)
            Button(action: {}) { Text(verbatim: "Maybe later") }.buttonStyle(.dsQuiet)
            Button(action: {}) { Text(verbatim: "Delete account") }.buttonStyle(.dsDestructive)
            HStack {
                Chip("15 min", isSelected: false) {}
                Chip("30 min", isSelected: true) {}
                Chip("60 min", isSelected: false) {}
            }
            Card {
                DSRow("Walk together without phones", subtitle: "20 min each", systemImage: "figure.walk") {
                    Image(systemName: "chevron.right").foregroundStyle(Color.inkMuted)
                }
            }
            Card(tone: .glow) { Text(verbatim: "Ana says you made her laugh").textRole(.callout).foregroundStyle(Color.glowStrong) }
            Card(tone: .sage) { Text(verbatim: "7 days together").textRole(.callout).foregroundStyle(Color.sage) }
            Card(tone: .dusk) { Text(verbatim: "2h 14m left").textRole(.heading).foregroundStyle(Color.onDusk) }
            HStack(spacing: Spacing.lg) {
                ProgressRing(progress: 0.62, accessibilityText: "1 hour 20 minutes of protected time left") {
                    Text(verbatim: "1h 20m").textRole(.heading).foregroundStyle(Color.ink)
                }
                .frame(width: 120, height: 120)
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    TwoCirclesMark(overlap: 1, diameter: 36)
                    HStack { Avatar(name: "Rafa", tone: .me); Avatar(name: "Ana", tone: .partner) }
                }
            }
            NoteBanner("New streak starts today.", systemImage: "leaf", tone: .calm)
            NoteBanner("Ana says let's wait — maybe later?", tone: .neutral)
            TextField(String("Email"), text: .constant("")).dsField()
        }
        .padding(Spacing.md)
        .background(Color.surface)
    }
}

@Suite(.serialized) @MainActor struct ComponentSnapshotTests {
    init() { _ = Typography.registerFonts() }

    @Test func galleryInBothThemes() {
        for result in Snapshot.verify(ComponentGallery(), named: "gallery", variants: Snapshot.Variant.themes) {
            #expect(result.isAcceptable, "\(result)")
        }
    }

    @Test func galleryAtLargestText() {
        for result in Snapshot.verify(ComponentGallery(), named: "gallery", variants: [.largeText]) {
            #expect(result.isAcceptable, "\(result)")
        }
    }

    @Test func celebrations() {
        let view = ZStack {
            GlowBloom(isActive: true)
            ParticleDrift(isActive: true)
            ComingTogether(together: true)
        }
        .frame(height: 240)
        .background(Color.surface)
        for result in Snapshot.verify(view, named: "celebrations") {
            #expect(result.isAcceptable, "\(result)")
        }
    }

    /// Guards the helper itself: the two themes really render differently.
    @Test func darkThemeRendersDarker() throws {
        let light = try #require(Snapshot.render(ComponentGallery(), variant: .light, width: 390))
        let dark = try #require(Snapshot.render(ComponentGallery(), variant: .dark, width: 390))
        #expect(Snapshot.averageLuminance(light) > 0.7)
        #expect(Snapshot.averageLuminance(dark) < 0.3)
    }

    @Test func largeTextRendersTaller() throws {
        let normal = try #require(Snapshot.render(ComponentGallery(), variant: .light, width: 390))
        let large = try #require(Snapshot.render(ComponentGallery(), variant: .largeText, width: 390))
        #expect(large.size.height > normal.size.height * 1.2)
    }
}
