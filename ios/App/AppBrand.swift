import Foundation

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
}
