import CoreText
import SwiftUI
import UIKit

/// The type scale (`docs/10-brand-and-design-system.md` §4).
/// Fraunces, soft and a little italic, speaks; Instrument Sans does the work.
public enum TextRole: String, CaseIterable, Sendable {
    /// The one big line of a scene ("Not about control…").
    case hero
    /// Scene statements in Fraunces italic ("Tonight is yours.").
    case display
    case title
    /// Big numbers inside the lights and stat tiles.
    case numeral
    /// The single number a scene is about (time left).
    case numeralLarge
    case heading
    case body
    case callout
    case caption
    /// Small tracked labels over the sky ("TONIGHT").
    case label

    public var pointSize: CGFloat {
        switch self {
        case .hero: 44
        case .display: 30
        case .title: 28
        case .numeral: 40
        case .numeralLarge: 64
        case .heading: 19
        case .body: 17
        case .callout: 15
        case .caption: 13
        case .label: 12
        }
    }

    public var lineHeight: CGFloat {
        switch self {
        case .hero: 48
        case .display: 36
        case .title: 34
        case .numeral: 44
        case .numeralLarge: 66
        case .heading: 25
        case .body: 24
        case .callout: 20
        case .caption: 18
        case .label: 16
        }
    }

    /// Weight on the variable font's `wght` axis.
    public var weight: CGFloat {
        switch self {
        case .hero, .display, .title, .numeral, .callout, .caption: 500
        case .numeralLarge: 400
        case .heading, .label: 600
        case .body: 400
        }
    }

    public var family: FontFamily {
        switch self {
        case .hero, .display, .title, .numeral, .numeralLarge: .fraunces
        default: .instrumentSans
        }
    }

    public var isItalic: Bool { self == .display }

    /// Letter spacing in points.
    public var tracking: CGFloat {
        switch self {
        case .label: 1.4
        case .hero, .numeralLarge: -0.6
        default: 0
        }
    }

    /// The Dynamic Type text style this role scales with.
    public var textStyle: Font.TextStyle {
        switch self {
        case .hero, .numeral, .numeralLarge: .largeTitle
        case .display, .title: .title
        case .heading: .title3
        case .body: .body
        case .callout: .subheadline
        case .caption: .footnote
        case .label: .caption
        }
    }

    var tabularFigures: Bool { self == .numeral || self == .numeralLarge }
}

public enum FontFamily: String, CaseIterable, Sendable {
    case fraunces = "Fraunces"
    case instrumentSans = "Instrument Sans"
}

/// Registers the bundled fonts and builds fonts for each role.
/// Call `registerFonts()` once at launch in the app and in each extension that draws text.
public enum Typography {
    private static let weightAxis = 2_003_265_652 // 'wght'
    private static let softAxis = 1_397_704_276 // 'SOFT' (Fraunces)

    private enum Face: String, CaseIterable {
        case fraunces = "Fraunces-Variable"
        case fraunceItalic = "Fraunces-Italic-Variable"
        case instrumentSans = "InstrumentSans-Variable"
    }

    /// PostScript name of each registered face (nil when registration failed).
    private static let faces: [Face: String] = {
        var result: [Face: String] = [:]
        for face in Face.allCases {
            guard let url = Bundle.module.url(forResource: face.rawValue, withExtension: "ttf", subdirectory: "Fonts") else { continue }
            var error: Unmanaged<CFError>?
            // A failure here usually means "already registered", which is fine.
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error)
            guard let descriptors = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor],
                  let first = descriptors.first,
                  let name = CTFontDescriptorCopyAttribute(first, kCTFontNameAttribute) as? String else { continue }
            result[face] = name
        }
        return result
    }()

    @discardableResult
    public static func registerFonts() -> Bool { faces.count == Face.allCases.count }

    public static func isAvailable(_ family: FontFamily) -> Bool {
        switch family {
        case .fraunces: faces[.fraunces] != nil && faces[.fraunceItalic] != nil
        case .instrumentSans: faces[.instrumentSans] != nil
        }
    }

    private static func face(for role: TextRole) -> String? {
        switch role.family {
        case .fraunces: faces[role.isItalic ? .fraunceItalic : .fraunces]
        case .instrumentSans: faces[.instrumentSans]
        }
    }

    /// A font for `role` at an explicit size (already scaled for Dynamic Type by the caller).
    public static func uiFont(_ role: TextRole, size: CGFloat? = nil) -> UIFont {
        let size = size ?? role.pointSize
        guard let name = face(for: role) else { return fallback(role, size: size) }
        var variations: [Int: CGFloat] = [weightAxis: role.weight]
        // The SOFT axis rounds Fraunces' terminals: the brand's warmth, in the letterforms.
        if role.family == .fraunces { variations[softAxis] = 100 }
        var attributes: [UIFontDescriptor.AttributeName: Any] = [
            .name: name,
            UIFontDescriptor.AttributeName(rawValue: kCTFontVariationAttribute as String): variations,
        ]
        if role.tabularFigures {
            attributes[.featureSettings] = [[
                UIFontDescriptor.FeatureKey.type: kNumberSpacingType,
                UIFontDescriptor.FeatureKey.selector: kMonospacedNumbersSelector,
            ]]
        }
        return UIFont(descriptor: UIFontDescriptor(fontAttributes: attributes), size: size)
    }

    public static func font(_ role: TextRole, size: CGFloat? = nil) -> Font {
        Font(uiFont(role, size: size))
    }

    private static func fallback(_ role: TextRole, size: CGFloat) -> UIFont {
        let weight: UIFont.Weight = role.weight >= 600 ? .semibold : (role.weight >= 500 ? .medium : .regular)
        var descriptor = UIFont.systemFont(ofSize: size, weight: weight).fontDescriptor
        if role.family == .fraunces, let serif = descriptor.withDesign(.serif) { descriptor = serif }
        if role.isItalic, let italic = descriptor.withSymbolicTraits(.traitItalic) { descriptor = italic }
        return UIFont(descriptor: descriptor, size: size)
    }
}

private struct RoleFont: ViewModifier {
    let role: TextRole
    @ScaledMetric private var size: CGFloat

    init(role: TextRole) {
        self.role = role
        _size = ScaledMetric(wrappedValue: role.pointSize, relativeTo: role.textStyle)
    }

    func body(content: Content) -> some View {
        content
            .font(Typography.font(role, size: size))
            .tracking(role.tracking)
            .lineSpacing(max(0, (role.lineHeight - role.pointSize) * 0.35))
            .textCase(role == .label ? .uppercase : nil)
    }
}

public extension View {
    /// Applies a design-system text role. Scales with Dynamic Type.
    func textRole(_ role: TextRole) -> some View {
        modifier(RoleFont(role: role))
    }
}
