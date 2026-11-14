import Blocking
import Core
import DesignSystem
import ManagedSettings
import ManagedSettingsUI
import UIKit

/// Draws the custom pause screen (feature spec §5): Dusk background, cream title, Glow accent;
/// "Protected time", the time remaining with an inviting line, "Ask {partner}" and "Not now".
final class ShieldConfigurationExtension: ShieldConfigurationDataSource {
    /// The brand motif: two overlapping circles, Hearth and Glow.
    private static let mark: UIImage = {
        let size = CGSize(width: 120, height: 72)
        return UIGraphicsImageRenderer(size: size).image { _ in
            UIColor(hex: ColorToken.hearth.dark).setFill()
            UIBezierPath(ovalIn: CGRect(x: 0, y: 0, width: 72, height: 72)).fill()
            UIColor(hex: ColorToken.glow.dark).withAlphaComponent(0.9).setFill()
            UIBezierPath(ovalIn: CGRect(x: 48, y: 0, width: 72, height: 72)).fill()
        }
    }()

    private func make() -> ShieldConfiguration {
        let content = ShieldContent.make(state: AppGroupStateStore().load(), now: Date())
        // The pause screen is always the evening look, whatever the phone's appearance.
        let dusk = UIColor(hex: ColorToken.dusk.dark)
        let cream = UIColor(hex: ColorToken.onDusk.dark)
        let glow = UIColor(hex: ColorToken.glow.dark)
        let onGlow = UIColor(hex: ColorToken.onGlow.dark)
        return ShieldConfiguration(
            backgroundBlurStyle: .systemUltraThinMaterialDark,
            backgroundColor: dusk,
            icon: Self.mark,
            title: ShieldConfiguration.Label(text: content.title, color: cream),
            subtitle: ShieldConfiguration.Label(text: content.subtitle, color: cream.withAlphaComponent(0.85)),
            primaryButtonLabel: ShieldConfiguration.Label(text: content.primaryButton, color: onGlow),
            primaryButtonBackgroundColor: glow,
            secondaryButtonLabel: ShieldConfiguration.Label(text: content.secondaryButton, color: cream)
        )
    }

    override func configuration(shielding application: Application) -> ShieldConfiguration { make() }

    override func configuration(shielding application: Application, in category: ActivityCategory) -> ShieldConfiguration { make() }

    override func configuration(shielding webDomain: WebDomain) -> ShieldConfiguration { make() }

    override func configuration(shielding webDomain: WebDomain, in category: ActivityCategory) -> ShieldConfiguration { make() }
}
