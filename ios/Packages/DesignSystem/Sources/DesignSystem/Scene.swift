import SwiftUI
import UIKit

// "Two lights, one evening" (docs/10-brand-and-design-system.md §11).
// The app is a scene: a sky that follows the day, and two lights in it. You are Hearth,
// your partner is Glow; both are always drawn the same size and with the same treatment.

/// Where the evening is. Screens choose it from the real time and protected time.
public enum SkyMoment: String, CaseIterable, Sendable {
    /// Protected time is some way off: warm daylight (a lamplit room in the dark theme).
    case daylight
    /// Protected time is near, or an unlock is running: golden hour (candlelight in the dark theme).
    case goldenHour
    /// Protected time: dusk, in both themes.
    case dusk
}

/// The colors of one sky: three gradient stops from top to horizon, and the text colors that sit on it.
public struct SkyPalette: Equatable, Sendable {
    public var stops: [UInt32]
    public var foreground: UInt32
    public var muted: UInt32

    public static func make(_ moment: SkyMoment, scheme: ColorScheme) -> SkyPalette {
        switch (moment, scheme) {
        case (.daylight, .dark): SkyPalette(stops: [0x191513, 0x1F1915, 0x2A2018], foreground: 0xF4EDE5, muted: 0xB6A99E)
        case (.goldenHour, .dark): SkyPalette(stops: [0x231E1B, 0x33261A, 0x4A2E20], foreground: 0xF4EDE5, muted: 0xC9BBB0)
        case (.dusk, .dark): SkyPalette(stops: [0x1C1722, 0x2A2230, 0x3F2A33], foreground: 0xF5EEE6, muted: 0xCDBFC0)
        case (.daylight, _): SkyPalette(stops: [0xFBF6F0, 0xFBF1E4, 0xFCEBCB], foreground: 0x2A211C, muted: 0x6B5E55)
        case (.goldenHour, _): SkyPalette(stops: [0xFCEBCB, 0xF9D9B8, 0xF4C3A6], foreground: 0x2A211C, muted: 0x5C4A40)
        case (.dusk, _): SkyPalette(stops: [0x2C2430, 0x3B2A37, 0x5A3438], foreground: 0xF5EEE6, muted: 0xD8C9C0)
        }
    }

    public var foregroundColor: Color { Color(uiColor: UIColor(hex: foreground)) }
    public var mutedColor: Color { Color(uiColor: UIColor(hex: muted)) }
    /// True when the sky is dark, so content on it should use the evening look.
    public var isDark: Bool { Contrast.relativeLuminance(stops[1]) < 0.2 }
}

private struct SkyMomentKey: EnvironmentKey {
    static let defaultValue: SkyMoment? = nil
}

public extension EnvironmentValues {
    /// The sky a view sits on, when it sits directly on one (nil on paper).
    var skyMoment: SkyMoment? {
        get { self[SkyMomentKey.self] }
        set { self[SkyMomentKey.self] = newValue }
    }
}

/// Text colors for content placed directly on the sky.
public struct SkyInk: Sendable {
    public let primary: Color
    public let muted: Color
    public let isDark: Bool

    public init(moment: SkyMoment?, scheme: ColorScheme) {
        if let moment {
            let palette = SkyPalette.make(moment, scheme: scheme)
            primary = palette.foregroundColor
            muted = palette.mutedColor
            isDark = palette.isDark
        } else {
            primary = .ink
            muted = .inkMuted
            isDark = scheme == .dark
        }
    }
}

/// Reads the right text colors for wherever the view is: `SkyReader { ink in Text("…").foregroundStyle(ink.primary) }`.
public struct SkyReader<Content: View>: View {
    @Environment(\.skyMoment) private var moment
    @Environment(\.colorScheme) private var scheme
    let content: (SkyInk) -> Content

    public init(@ViewBuilder content: @escaping (SkyInk) -> Content) { self.content = content }

    public var body: some View { content(SkyInk(moment: moment, scheme: scheme)) }
}

/// The full-bleed sky with paper grain. Changing `moment` cross-fades, like light changing in a room.
public struct EveningSky: View {
    let moment: SkyMoment
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(_ moment: SkyMoment) { self.moment = moment }

    public var body: some View {
        let palette = SkyPalette.make(moment, scheme: scheme)
        ZStack {
            LinearGradient(colors: palette.stops.map { Color(uiColor: UIColor(hex: $0)) }, startPoint: .top, endPoint: .bottom)
            // A low warm glow on the horizon: the hearth of the scene.
            RadialGradient(
                colors: [Color.hearth.opacity(palette.isDark ? 0.28 : 0.14), Color.hearth.opacity(0)],
                center: UnitPoint(x: 0.5, y: 1.05), startRadius: 0, endRadius: 420
            )
            PaperGrain(opacity: palette.isDark ? 0.05 : 0.035)
        }
        .animation(Motion.resolve(Motion.light, reduceMotion: reduceMotion), value: moment)
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

public extension View {
    /// Puts the view on a sky and tells its content which one, so text picks legible colors.
    func onSky(_ moment: SkyMoment) -> some View {
        modifier(OnSky(moment: moment))
    }
}

/// The sky behind a scene, and a navigation bar that matches it: under the dusk sky (dark in
/// both themes) the title and bar buttons must be light, whatever the phone's appearance.
private struct OnSky: ViewModifier {
    let moment: SkyMoment
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        let dark = SkyPalette.make(moment, scheme: scheme).isDark
        content
            .environment(\.skyMoment, moment)
            .background(EveningSky(moment))
            .toolbarColorScheme(dark ? .dark : .light, for: .navigationBar)
    }
}

/// Fine paper grain: deterministic speckles, drawn once.
public struct PaperGrain: View {
    let opacity: Double

    public init(opacity: Double = 0.04) { self.opacity = opacity }

    public var body: some View {
        Canvas { context, size in
            var seed: UInt64 = 0x9E37_79B9_7F4A_7C15
            func next() -> CGFloat {
                seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
                return CGFloat(seed >> 33) / CGFloat(1 << 31)
            }
            let count = Int(size.width * size.height / 260)
            for _ in 0..<count {
                let rect = CGRect(x: next() * size.width, y: next() * size.height, width: 1, height: 1)
                context.fill(Path(rect), with: .color(next() > 0.5 ? .white : .black))
            }
        }
        .opacity(opacity)
        .blendMode(.overlay)
        .drawingGroup()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Whose light it is. Both are always the same size and drawn the same way.
public enum LightTone: Sendable, CaseIterable {
    case me, partner

    public var fill: Color { self == .me ? .hearth : .glow }
    public var onFill: Color { self == .me ? .onHearth : .onGlow }
}

/// One light: a soft translucent disc with a halo. Content (a name, a number) sits inside it.
public struct LightDisc<Content: View>: View {
    let tone: LightTone
    let diameter: CGFloat
    /// 0 = a calm disc, 1 = glowing (celebrations, protected time).
    let glow: Double
    let content: Content

    public init(_ tone: LightTone, diameter: CGFloat, glow: Double = 0.5, @ViewBuilder content: () -> Content) {
        self.tone = tone
        self.diameter = diameter
        self.glow = glow
        self.content = content()
    }

    public var body: some View {
        ZStack {
            Circle()
                .fill(tone.fill.opacity(0.35 * glow))
                .frame(width: diameter * 1.45, height: diameter * 1.45)
                .blur(radius: diameter * 0.16)
            Circle()
                .fill(
                    RadialGradient(
                        // Opaque, so text on a light keeps its contrast whatever glows behind it.
                        colors: [tone.fill, tone.fill.opacity(0.98)],
                        center: UnitPoint(x: 0.38, y: 0.32), startRadius: 0, endRadius: diameter * 0.7
                    )
                )
                .overlay(Circle().strokeBorder(Color.white.opacity(0.22), lineWidth: 1))
                .frame(width: diameter, height: diameter)
            content
                .foregroundStyle(tone.onFill)
                .frame(width: diameter * 0.78, height: diameter * 0.78)
        }
        .frame(width: diameter, height: diameter)
    }
}

public extension LightDisc where Content == EmptyView {
    init(_ tone: LightTone, diameter: CGFloat, glow: Double = 0.5) {
        self.init(tone, diameter: diameter, glow: glow) { EmptyView() }
    }
}

/// The two lights together. `closeness` runs from 0 (apart) to 1 (as close as `overlap` allows).
/// The overlap is the time together.
public struct TwoLights<Mine: View, Theirs: View>: View {
    let closeness: Double
    let diameter: CGFloat
    /// How far the discs may overlap at closeness 1, as a share of the diameter (keep it small when they hold text).
    let overlap: Double
    let glow: Double
    let mine: Mine
    let theirs: Theirs
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(
        closeness: Double, diameter: CGFloat = 120, overlap: Double = 0.55, glow: Double = 0.5,
        @ViewBuilder mine: () -> Mine, @ViewBuilder theirs: () -> Theirs
    ) {
        self.closeness = closeness
        self.diameter = diameter
        self.overlap = overlap
        self.glow = glow
        self.mine = mine()
        self.theirs = theirs()
    }

    /// Distance between the two centers.
    public nonisolated static func separation(closeness: Double, diameter: CGFloat, overlap: Double) -> CGFloat {
        let near = diameter * (1 - overlap)
        let far = diameter * 1.3
        return far + (near - far) * min(max(closeness, 0), 1)
    }

    public var body: some View {
        let half = Self.separation(closeness: closeness, diameter: diameter, overlap: overlap) / 2
        ZStack {
            LightDisc(.me, diameter: diameter, glow: glow) { mine }.offset(x: -half)
            LightDisc(.partner, diameter: diameter, glow: glow) { theirs }
                .offset(x: half)
                .blendMode(.normal)
        }
        .frame(width: diameter * 2.3, height: diameter)
        .animation(Motion.resolve(Motion.drift, reduceMotion: reduceMotion), value: closeness)
    }
}

public extension TwoLights where Mine == EmptyView, Theirs == EmptyView {
    init(closeness: Double, diameter: CGFloat = 120, overlap: Double = 0.55, glow: Double = 0.5) {
        self.init(closeness: closeness, diameter: diameter, overlap: overlap, glow: glow, mine: { EmptyView() }, theirs: { EmptyView() })
    }
}

/// The arc of the evening: a light travels along it as protected time (or an unlock) passes.
/// It is the status ring of the home scene and always carries a spoken description.
public struct EveningArc: View {
    let progress: Double
    let tint: Color
    let track: Color
    let accessibilityText: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(progress: Double, tint: Color, track: Color, accessibilityText: String) {
        self.progress = progress
        self.tint = tint
        self.track = track
        self.accessibilityText = accessibilityText
    }

    public var body: some View {
        GeometryReader { proxy in
            let clamped = min(max(progress, 0), 1)
            let radius = min(proxy.size.width / 2, proxy.size.height) - 6
            let center = CGPoint(x: proxy.size.width / 2, y: proxy.size.height - 2)
            let angle = Angle.degrees(180 + 180 * clamped)
            ZStack {
                ArcShape().stroke(track, style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [1, 9]))
                ArcShape().trim(from: 0, to: clamped).stroke(tint, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                Circle()
                    .fill(tint)
                    .frame(width: 14, height: 14)
                    .shadow(color: tint.opacity(0.7), radius: 8)
                    .position(x: center.x + radius * CGFloat(cos(angle.radians)), y: center.y + radius * CGFloat(sin(angle.radians)))
            }
            .animation(Motion.resolve(Motion.gentle, reduceMotion: reduceMotion), value: clamped)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private struct ArcShape: Shape {
        func path(in rect: CGRect) -> Path {
            var path = Path()
            let radius = min(rect.width / 2, rect.height) - 6
            path.addArc(center: CGPoint(x: rect.midX, y: rect.maxY - 2), radius: radius, startAngle: .degrees(180), endAngle: .degrees(360), clockwise: false)
            return path
        }
    }
}

/// A floating glass surface for controls that sit over the sky.
public struct Glass: ViewModifier {
    let radius: CGFloat
    @Environment(\.skyMoment) private var moment
    @Environment(\.colorScheme) private var scheme

    public func body(content: Content) -> some View {
        // The material follows the sky, not the phone's appearance: under the dusk sky (dark in
        // both themes) light text needs dark glass behind it to stay readable.
        let dark = SkyInk(moment: moment, scheme: scheme).isDark
        content
            .background {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .environment(\.colorScheme, dark ? .dark : .light)
                    .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).fill(Color.black.opacity(dark ? 0.25 : 0)))
            }
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(Color.white.opacity(0.18), lineWidth: 1))
    }
}

public extension View {
    func glass(radius: CGFloat = Radius.pill) -> some View { modifier(Glass(radius: radius)) }
}

/// One place in the app, for `PlaceBar`.
public struct PlaceItem<ID: Hashable>: Identifiable {
    public let id: ID
    public let title: String
    public let systemImage: String

    public init(id: ID, title: String, systemImage: String) {
        self.id = id
        self.title = title
        self.systemImage = systemImage
    }
}

/// The app's navigation: a small floating pill of places. The current place carries the two lights.
public struct PlaceBar<ID: Hashable>: View {
    let places: [PlaceItem<ID>]
    @Binding var selection: ID
    @Namespace private var namespace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize

    public init(places: [PlaceItem<ID>], selection: Binding<ID>) {
        self.places = places
        _selection = selection
    }

    public var body: some View {
        // Full labels, never cut off; at accessibility text sizes three labels no longer fit
        // one line, so the bar shows icons only (each keeps its name for VoiceOver).
        bar(showTitles: !typeSize.isAccessibilitySize)
    }

    private func bar(showTitles: Bool) -> some View {
        HStack(spacing: Spacing.xxs) {
            ForEach(places) { place in
                let isSelected = place.id == selection
                Button {
                    guard !isSelected else { return }
                    Haptics.tick()
                    withAnimation(Motion.resolve(Motion.standard, reduceMotion: reduceMotion)) { selection = place.id }
                } label: {
                    HStack(spacing: Spacing.xs) {
                        if isSelected {
                            TwoLights(closeness: 1, diameter: 12, overlap: 0.45, glow: 0)
                                .frame(width: 22, height: 12)
                                .matchedGeometryEffect(id: "lights", in: namespace)
                        } else {
                            Image(systemName: place.systemImage).imageScale(.small)
                        }
                        if showTitles {
                            Text(place.title).textRole(.callout).fixedSize()
                        }
                    }
                    .foregroundStyle(isSelected ? Color.ink : Color.inkMuted)
                    .padding(.horizontal, Spacing.md)
                    .frame(minHeight: Sizing.minTouchTarget)
                    .background {
                        if isSelected {
                            Capsule().fill(Color.surfaceRaised).matchedGeometryEffect(id: "pill", in: namespace)
                        }
                    }
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(place.title)
                .accessibilityAddTraits(isSelected ? [.isSelected] : [])
                .accessibilityIdentifier("place.\(place.id)")
            }
        }
        .padding(Spacing.xxs)
        // Solid, so the labels keep their contrast and nothing scrolling beneath shows through.
        .background(Color.surfaceSunken, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.line, lineWidth: 1))
        .warmShadow()
    }
}

/// Unlocking as a gesture between two people: slide your light across to meet your partner's.
/// VoiceOver and Switch Control get it as a plain button, and screens always pair it with one.
public struct LightsMeetControl: View {
    let title: String
    let isEnabled: Bool
    let action: () -> Void
    @State private var travel: CGFloat = 0
    @State private var met = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let knob: CGFloat = 56

    public init(_ title: String, isEnabled: Bool = true, action: @escaping () -> Void) {
        self.title = title
        self.isEnabled = isEnabled
        self.action = action
    }

    public var body: some View {
        GeometryReader { proxy in
            let range = max(1, proxy.size.width - knob * 2 - 8)
            ZStack(alignment: .leading) {
                Capsule().fill(Color.surfaceSunken)
                Capsule().strokeBorder(Color.line, lineWidth: 1)
                Text(title)
                    .textRole(.callout)
                    .foregroundStyle(Color.inkMuted)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, knob + Spacing.sm)
                    .frame(maxWidth: .infinity)
                    .opacity(1 - Double(travel / range))
                LightDisc(.partner, diameter: knob - 8, glow: met ? 1 : 0.3)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.trailing, 4)
                LightDisc(.me, diameter: knob - 8, glow: Double(travel / range))
                    .padding(.leading, 4)
                    .offset(x: travel)
                    .gesture(
                        DragGesture(minimumDistance: 2)
                            .onChanged { value in
                                guard isEnabled, !met else { return }
                                let next = min(max(0, value.translation.width), range)
                                if Int(next / 28) != Int(travel / 28) { Haptics.tick() }
                                travel = next
                            }
                            .onEnded { _ in
                                guard isEnabled, !met else { return }
                                if travel > range * 0.82 {
                                    complete(range)
                                } else {
                                    withAnimation(Motion.resolve(Motion.standard, reduceMotion: reduceMotion)) { travel = 0 }
                                }
                            }
                    )
            }
        }
        .frame(height: knob + 8)
        .opacity(isEnabled ? 1 : 0.45)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { if isEnabled, !met { fire() } }
    }

    private func complete(_ range: CGFloat) {
        withAnimation(Motion.resolve(Motion.meet, reduceMotion: reduceMotion)) {
            travel = range - (knob - 8) * 0.55
            met = true
        }
        fire()
    }

    private func fire() {
        Haptics.meet()
        action()
        Task {
            try? await Task.sleep(for: .seconds(1.2))
            withAnimation(Motion.resolve(Motion.standard, reduceMotion: reduceMotion)) {
                travel = 0
                met = false
            }
        }
    }
}
