import SwiftUI
import UIKit

/// One color token from `docs/10-brand-and-design-system.md` §3 with its light and dark values.
public struct ColorToken: Sendable, Hashable {
    public let name: String
    public let light: UInt32
    public let dark: UInt32

    public init(_ name: String, light: UInt32, dark: UInt32) {
        self.name = name
        self.light = light
        self.dark = dark
    }

    /// Adapts to the current light or dark appearance.
    public var uiColor: UIColor {
        let light = light, dark = dark
        return UIColor { traits in
            UIColor(hex: traits.userInterfaceStyle == .dark ? dark : light)
        }
    }

    public var color: Color { Color(uiColor: uiColor) }

    /// Fixed value for one appearance (used by tests and by extensions that cannot adapt).
    public func hex(for scheme: ColorScheme) -> UInt32 { scheme == .dark ? dark : light }
}

public extension ColorToken {
    static let surface = ColorToken("surface", light: 0xFBF6F0, dark: 0x191513)
    static let surfaceRaised = ColorToken("surface-raised", light: 0xFFFFFF, dark: 0x231E1B)
    static let surfaceSunken = ColorToken("surface-sunken", light: 0xF2E9DE, dark: 0x120F0D)
    static let line = ColorToken("line", light: 0xE5D8C8, dark: 0x3A322C)
    static let ink = ColorToken("ink", light: 0x2A211C, dark: 0xF4EDE5)
    static let inkMuted = ColorToken("ink-muted", light: 0x6B5E55, dark: 0xB6A99E)
    static let hearth = ColorToken("hearth", light: 0xAD472E, dark: 0xE8836A)
    static let hearthSoft = ColorToken("hearth-soft", light: 0xF9E4DB, dark: 0x4A2820)
    static let onHearth = ColorToken("on-hearth", light: 0xFFFFFF, dark: 0x191513)
    static let glow = ColorToken("glow", light: 0xE9A23B, dark: 0xF2B65A)
    static let glowStrong = ColorToken("glow-strong", light: 0x8F5A0F, dark: 0xF2B65A)
    static let glowSoft = ColorToken("glow-soft", light: 0xFCEBCB, dark: 0x45351A)
    static let onGlow = ColorToken("on-glow", light: 0x2A211C, dark: 0x191513)
    static let sage = ColorToken("sage", light: 0x4A6E53, dark: 0x8DB596)
    static let sageSoft = ColorToken("sage-soft", light: 0xE1EBDF, dark: 0x22332A)
    static let onSage = ColorToken("on-sage", light: 0xFFFFFF, dark: 0x191513)
    static let dusk = ColorToken("dusk", light: 0x2C2430, dark: 0x2A2230)
    static let onDusk = ColorToken("on-dusk", light: 0xF5EEE6, dark: 0xF5EEE6)
    static let danger = ColorToken("danger", light: 0xA8322A, dark: 0xF0A097)
    /// Charts: the user.
    static let partnerA = hearth
    /// Charts: the partner.
    static let partnerB = glow

    static let all: [ColorToken] = [
        surface, surfaceRaised, surfaceSunken, line, ink, inkMuted, hearth, hearthSoft, onHearth,
        glow, glowStrong, glowSoft, onGlow, sage, sageSoft, onSage, dusk, onDusk, danger,
    ]
}

/// `.foregroundStyle(.hearth)`, `.background(.surface)` and so on.
public extension ShapeStyle where Self == Color {
    static var surface: Color { ColorToken.surface.color }
    static var surfaceRaised: Color { ColorToken.surfaceRaised.color }
    static var surfaceSunken: Color { ColorToken.surfaceSunken.color }
    static var line: Color { ColorToken.line.color }
    static var ink: Color { ColorToken.ink.color }
    static var inkMuted: Color { ColorToken.inkMuted.color }
    static var hearth: Color { ColorToken.hearth.color }
    static var hearthSoft: Color { ColorToken.hearthSoft.color }
    static var onHearth: Color { ColorToken.onHearth.color }
    static var glow: Color { ColorToken.glow.color }
    static var glowStrong: Color { ColorToken.glowStrong.color }
    static var glowSoft: Color { ColorToken.glowSoft.color }
    static var onGlow: Color { ColorToken.onGlow.color }
    static var sage: Color { ColorToken.sage.color }
    static var sageSoft: Color { ColorToken.sageSoft.color }
    static var onSage: Color { ColorToken.onSage.color }
    static var dusk: Color { ColorToken.dusk.color }
    static var onDusk: Color { ColorToken.onDusk.color }
    /// Destructive actions only (delete account, confirm unpair).
    static var danger: Color { ColorToken.danger.color }
    static var partnerA: Color { ColorToken.partnerA.color }
    static var partnerB: Color { ColorToken.partnerB.color }
}

public extension UIColor {
    convenience init(hex: UInt32) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}

/// WCAG 2 contrast math, used by tests to keep the palette accessible.
public enum Contrast {
    public static func relativeLuminance(_ hex: UInt32) -> Double {
        func channel(_ value: UInt32) -> Double {
            let c = Double(value) / 255
            return c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel((hex >> 16) & 0xFF)
            + 0.7152 * channel((hex >> 8) & 0xFF)
            + 0.0722 * channel(hex & 0xFF)
    }

    public static func ratio(_ a: UInt32, _ b: UInt32) -> Double {
        let la = relativeLuminance(a), lb = relativeLuminance(b)
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }
}
