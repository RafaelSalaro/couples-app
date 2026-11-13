import CoreText
import SwiftUI
import UIKit

/// The type scale from `docs/10-brand-and-design-system.md` §4.
/// Fraunces for headlines and big numbers, Instrument Sans for everything else.
public enum TextRole: String, CaseIterable, Sendable {
    case hero, title, numeral, heading, body, callout, caption

    public var pointSize: CGFloat {
        switch self {
        case .hero: 44
        case .title: 30
        case .numeral: 40
        case .heading: 20
        case .body: 17
        case .callout: 15
        case .caption: 13
        }
    }

    public var lineHeight: CGFloat {
        switch self {
        case .hero: 48
        case .title: 36
        case .numeral: 44
        case .heading: 26
        case .body: 24
        case .callout: 20
        case .caption: 18
        }
    }

    /// Weight on the variable font's `wght` axis.
    public var weight: CGFloat {
        switch self {
        case .hero, .title, .numeral, .callout, .caption: 500
        case .heading: 600
        case .body: 400
        }
    }

    public var family: FontFamily {
        switch self {
        case .hero, .title, .numeral: .fraunces
        default: .instrumentSans
        }
    }

    /// The Dynamic Type text style this role scales with.
    public var textStyle: Font.TextStyle {
        switch self {
        case .hero, .numeral: .largeTitle
        case .title: .title
        case .heading: .title3
        case .body: .body
        case .callout: .subheadline
        case .caption: .footnote
        }
    }

    var tabularFigures: Bool { self == .numeral }
}

public enum FontFamily: String, CaseIterable, Sendable {
    case fraunces = "Fraunces"
    case instrumentSans = "Instrument Sans"

    var fileName: String {
        switch self {
        case .fraunces: "Fraunces-Variable"
        case .instrumentSans: "InstrumentSans-Variable"
        }
    }
}

/// Registers the bundled fonts and builds fonts for each role.
/// Call `registerFonts()` once at launch in the app and in each extension that draws text.
public enum Typography {
    private static let weightAxis = 2_003_265_652 // 'wght'
    private static let softAxis = 1_397_704_276 // 'SOFT' (Fraunces)

    private static let registered: [FontFamily: Bool] = {
        var result: [FontFamily: Bool] = [:]
        for family in FontFamily.allCases {
            guard let url = Bundle.module.url(
                forResource: family.fileName, withExtension: "ttf", subdirectory: "Fonts"
            ) else {
                result[family] = false
                continue
            }
            var error: Unmanaged<CFError>?
            let ok = CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error)
            // Already registered counts as success.
            result[family] = ok || UIFont.familyNames.contains(family.rawValue)
        }
        return result
    }()

    @discardableResult
    public static func registerFonts() -> Bool {
        registered.values.allSatisfy { $0 }
    }

    public static func isAvailable(_ family: FontFamily) -> Bool {
        registered[family] ?? false
    }

    /// A font for `role` at an explicit size (already scaled for Dynamic Type by the caller).
    public static func uiFont(_ role: TextRole, size: CGFloat? = nil) -> UIFont {
        let size = size ?? role.pointSize
        guard isAvailable(role.family) else { return fallback(role, size: size) }
        var variations: [Int: CGFloat] = [weightAxis: role.weight]
        if role.family == .fraunces { variations[softAxis] = 100 }
        var attributes: [UIFontDescriptor.AttributeName: Any] = [
            .family: role.family.rawValue,
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
        let base = UIFont.systemFont(ofSize: size, weight: weight)
        if role.family == .fraunces, let serif = base.fontDescriptor.withDesign(.serif) {
            return UIFont(descriptor: serif, size: size)
        }
        return base
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
            .lineSpacing(max(0, (role.lineHeight - role.pointSize) * 0.35))
    }
}

public extension View {
    /// Applies a design-system text role. Scales with Dynamic Type.
    func textRole(_ role: TextRole) -> some View {
        modifier(RoleFont(role: role))
    }
}
