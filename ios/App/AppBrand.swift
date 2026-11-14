import FeatureSupport
import Foundation

func L(_ key: String.LocalizationValue) -> String { String(localized: key) }

/// The app name is not final. Every brand string comes from here.
/// The display name itself is set once, in `Config/Shared.xcconfig`
/// (`APP_DISPLAY_NAME`), and read back from the bundle.
enum AppBrand {
    static let displayName: String = {
        let info = Bundle.main.infoDictionary
        return (info?["CFBundleDisplayName"] as? String)
            ?? (info?["CFBundleName"] as? String)
            ?? "Couples App"
    }()

    /// Custom URL scheme used for deep links (`couplesapp://unlock`).
    static let urlScheme: String =
        (Bundle.main.infoDictionary?["AppURLScheme"] as? String) ?? "couplesapp"

    /// Website domain that hosts universal links, legal pages and support.
    static let websiteDomain: String =
        (Bundle.main.infoDictionary?["AppWebsiteDomain"] as? String) ?? "example.com"

    /// The same values in the form feature modules take.
    static let info = BrandInfo(displayName: displayName, urlScheme: urlScheme, websiteDomain: websiteDomain)
}

/// Build configuration read from Info.plist (filled from the xcconfig files).
enum AppConfig {
    private static func value(_ key: String) -> String? {
        guard let value = Bundle.main.infoDictionary?[key] as? String, !value.isEmpty, !value.hasPrefix("$(") else { return nil }
        return value
    }

    /// Supabase project URL and anon key, when configured in `Config/Secrets.xcconfig.local`.
    static var supabase: (url: URL, anonKey: String)? {
        guard let host = value("SupabaseHost"), let key = value("SupabaseAnonKey"),
              let url = URL(string: "\(value("SupabaseScheme") ?? "https")://\(host)") else { return nil }
        return (url, key)
    }

    static var revenueCatKey: String? { value("RevenueCatAPIKey") }
}
