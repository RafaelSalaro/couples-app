import SwiftUI

/// Surface tints a card can take.
public enum CardTone: Sendable, CaseIterable {
    case raised, sunken, hearth, glow, sage, dusk

    var background: Color {
        switch self {
        case .raised: .surfaceRaised
        case .sunken: .surfaceSunken
        case .hearth: .hearthSoft
        case .glow: .glowSoft
        case .sage: .sageSoft
        case .dusk: .dusk
        }
    }
}

public struct Card<Content: View>: View {
    let tone: CardTone
    let radius: CGFloat
    let content: Content

    public init(tone: CardTone = .raised, radius: CGFloat = Radius.card, @ViewBuilder content: () -> Content) {
        self.tone = tone
        self.radius = radius
        self.content = content()
    }

    public var body: some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        Group {
            if tone == .raised {
                padded.background(tone.background, in: shape).warmShadow()
            } else {
                padded.background(tone.background, in: shape)
            }
        }
    }

    private var padded: some View {
        content
            .padding(Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A circular progress ring. Always give it a spoken description, for example
/// "1 hour 20 minutes of protected time left" (06 §11).
public struct ProgressRing<Center: View>: View {
    let progress: Double
    let tint: Color
    let track: Color
    let lineWidth: CGFloat
    let accessibilityText: String
    let center: Center
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(
        progress: Double,
        tint: Color = .sage,
        track: Color = .surfaceSunken,
        lineWidth: CGFloat = 12,
        accessibilityText: String,
        @ViewBuilder center: () -> Center
    ) {
        self.progress = progress
        self.tint = tint
        self.track = track
        self.lineWidth = lineWidth
        self.accessibilityText = accessibilityText
        self.center = center()
    }

    public var body: some View {
        ZStack {
            Circle().stroke(track, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: min(max(progress, 0), 1))
                .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(Motion.resolve(Motion.gentle, reduceMotion: reduceMotion), value: progress)
            center
        }
        .padding(lineWidth / 2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }
}

/// The brand motif: two overlapping circles, Hearth and Glow; the overlap is the time together.
/// `overlap` runs from 0 (apart) to 1 (settled, overlapping).
public struct TwoCirclesMark: View {
    let overlap: Double
    let diameter: CGFloat

    public init(overlap: Double = 1, diameter: CGFloat = 56) {
        self.overlap = overlap
        self.diameter = diameter
    }

    public var body: some View {
        let offset = diameter * (0.75 - 0.45 * min(max(overlap, 0), 1))
        ZStack {
            Circle().fill(Color.hearth).frame(width: diameter, height: diameter).offset(x: -offset)
            Circle().fill(Color.glow.opacity(0.9)).frame(width: diameter, height: diameter).offset(x: offset)
        }
        .frame(width: diameter * 2.5, height: diameter)
        .accessibilityHidden(true)
    }
}

/// A round avatar with the person's initial, tinted with their partner color.
public struct Avatar: View {
    public enum Tone: Sendable { case me, partner }
    let name: String
    let tone: Tone
    let diameter: CGFloat

    public init(name: String, tone: Tone, diameter: CGFloat = 44) {
        self.name = name
        self.tone = tone
        self.diameter = diameter
    }

    public var body: some View {
        Text(String(name.trimmingCharacters(in: .whitespaces).prefix(1)).uppercased())
            .font(Typography.font(.heading, size: diameter * 0.42))
            .foregroundStyle(tone == .me ? Color.onHearth : Color.onGlow)
            .frame(width: diameter, height: diameter)
            .background(tone == .me ? Color.hearth : Color.glow, in: Circle())
            .accessibilityHidden(true)
    }
}

/// A big Fraunces number with a caption, used for balances and streaks.
public struct StatTile: View {
    let value: String
    let label: String
    let tint: Color

    public init(value: String, label: String, tint: Color = .ink) {
        self.value = value
        self.label = label
        self.tint = tint
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            Text(value)
                .textRole(.numeral)
                .foregroundStyle(tint)
                .contentTransition(.numericText())
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            Text(label)
                .textRole(.caption)
                .foregroundStyle(Color.inkMuted)
        }
        .accessibilityElement(children: .combine)
    }
}

/// A calm inline note. Tones are never red: information is neutral, warm or celebratory.
public struct NoteBanner: View {
    public enum Tone: Sendable, CaseIterable { case neutral, warm, celebrate, calm }
    let text: String
    let systemImage: String?
    let tone: Tone

    public init(_ text: String, systemImage: String? = nil, tone: Tone = .neutral) {
        self.text = text
        self.systemImage = systemImage
        self.tone = tone
    }

    public var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.xs) {
            if let systemImage {
                Image(systemName: systemImage).accessibilityHidden(true)
            }
            Text(text).textRole(.callout)
        }
        .foregroundStyle(foreground)
        .padding(Spacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(background, in: RoundedRectangle(cornerRadius: Radius.small, style: .continuous))
    }

    private var foreground: Color {
        switch tone {
        case .neutral: .ink
        case .warm: .hearth
        case .celebrate: .glowStrong
        case .calm: .sage
        }
    }

    private var background: Color {
        switch tone {
        case .neutral: .surfaceSunken
        case .warm: .hearthSoft
        case .celebrate: .glowSoft
        case .calm: .sageSoft
        }
    }
}

/// Text field look shared by forms: `TextField(...).dsField()`.
private struct DSField: ViewModifier {
    func body(content: Content) -> some View {
        content
            .textRole(.body)
            .foregroundStyle(Color.ink)
            .padding(.horizontal, Spacing.md)
            .frame(minHeight: Sizing.minTouchTarget + 4)
            .background(Color.surfaceRaised, in: RoundedRectangle(cornerRadius: Radius.small, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Radius.small, style: .continuous)
                    .strokeBorder(Color.line, lineWidth: 1)
            }
    }
}

public extension View {
    func dsField() -> some View { modifier(DSField()) }
}

/// Section heading used above groups of cards.
public struct SectionHeader: View {
    let title: String

    public init(_ title: String) { self.title = title }

    public var body: some View {
        Text(title)
            .textRole(.heading)
            .foregroundStyle(Color.ink)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
    }
}

/// A navigation-style row inside a card.
public struct DSRow<Trailing: View>: View {
    let title: String
    let subtitle: String?
    let systemImage: String?
    let trailing: Trailing

    public init(
        _ title: String,
        subtitle: String? = nil,
        systemImage: String? = nil,
        @ViewBuilder trailing: () -> Trailing = { EmptyView() }
    ) {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.trailing = trailing()
    }

    public var body: some View {
        HStack(spacing: Spacing.sm) {
            if let systemImage {
                Image(systemName: systemImage)
                    .foregroundStyle(Color.hearth)
                    .frame(width: 28)
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title).textRole(.body).foregroundStyle(Color.ink)
                if let subtitle {
                    Text(subtitle).textRole(.caption).foregroundStyle(Color.inkMuted)
                }
            }
            Spacer(minLength: Spacing.xs)
            trailing
        }
        .frame(minHeight: Sizing.minTouchTarget)
        .contentShape(Rectangle())
    }
}
