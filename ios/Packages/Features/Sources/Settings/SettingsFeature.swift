import Core
import DesignSystem
import FeatureSupport
import PairingFeature
import SwiftUI

func L(_ key: String.LocalizationValue) -> String { String(localized: key, bundle: .module) }

/// Settings root (feature spec §13).
public struct SettingsView: View {
    let app: AppModel

    public init(app: AppModel) { self.app = app }

    public var body: some View {
        ScrollView {
            VStack(spacing: Spacing.md) {
                Card {
                    NavigationLink {
                        PartnerSettingsView(app: app)
                    } label: {
                        DSRow(L("Partner"), subtitle: app.partnerName ?? L("Not paired yet"), systemImage: "person.2") {
                            Image(systemName: "chevron.right").foregroundStyle(Color.inkMuted)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("settings.partner")
                }
            }
            .padding(Spacing.md)
        }
        .pageBackground()
        .navigationTitle(L("Us"))
        .accessibilityIdentifier("settings.screen")
    }
}
