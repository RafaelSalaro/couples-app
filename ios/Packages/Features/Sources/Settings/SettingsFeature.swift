import Core
import DesignSystem
import FeatureSupport
import MinutesFeature
import PairingFeature
import SwiftUI

func L(_ key: String.LocalizationValue) -> String { String(localized: key, bundle: .module) }

/// "Us": the quieter place behind the scene. Minutes, the week, protected time, the partner
/// (and unpairing) and settings (feature spec §13). The app target supplies the screens that
/// live in other feature modules.
public struct UsView<Extra: View>: View {
    @Bindable var app: AppModel
    let destination: (UsDestination) -> Extra
    @State private var path: [UsDestination] = []

    public init(app: AppModel, @ViewBuilder destination: @escaping (UsDestination) -> Extra) {
        self.app = app
        self.destination = destination
    }

    public var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(spacing: Spacing.md) {
                    VStack(spacing: Spacing.sm) {
                        TwoLights(closeness: app.isPaired ? 1 : 0.2, diameter: 64, overlap: 0.3, glow: 0.3) {
                            initial(app.myName)
                        } theirs: {
                            if let name = app.partnerName { initial(name) } else { Image(systemName: "plus") }
                        }
                        .accessibilityHidden(true)
                        Text(app.partnerName.map { L("\(app.myName) & \($0)") } ?? app.myName)
                            .textRole(.display)
                            .foregroundStyle(Color.ink)
                            .accessibilityAddTraits(.isHeader)
                    }
                    .padding(.vertical, Spacing.md)

                    Card {
                        VStack(spacing: Spacing.xs) {
                            row(.minutes, L("Minutes"), subtitle: MinutesText.short(app.myMinutes?.balance ?? 0), icon: "hourglass")
                            Divider().overlay(Color.line)
                            row(.week, L("Our week"), subtitle: L("How the two of you are doing"), icon: "chart.bar")
                            Divider().overlay(Color.line)
                            row(.schedule, L("Protected time"), subtitle: app.effectiveSchedules.first.map { ScheduleText.range($0) }, icon: "moon.stars")
                        }
                    }
                    Card {
                        VStack(spacing: Spacing.xs) {
                            // Unpairing lives here: two taps from anywhere, never hidden (feature spec §16).
                            row(.partner, L("Partner"), subtitle: app.partnerName ?? L("Not paired yet"), icon: "person.2")
                            Divider().overlay(Color.line)
                            row(.settings, L("Settings"), subtitle: L("Profile, notifications, subscription, your data"), icon: "gearshape")
                        }
                    }
                }
                .padding(.horizontal, Spacing.md)
                .padding(.bottom, 96)
            }
            .pageBackground()
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: UsDestination.self) { item in
                switch item {
                case .partner: PartnerSettingsView(app: app)
                case .minutes: MinutesView(app: app)
                default: destination(item)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("us.screen")
        .onAppear(perform: follow)
        .onChange(of: app.usDestination) { _, _ in follow() }
    }

    /// Opens a screen another place (or a notification) asked for.
    private func follow() {
        guard let wanted = app.usDestination else { return }
        path = [wanted]
        app.usDestination = nil
    }

    private func initial(_ name: String) -> some View {
        Text(String(name.prefix(1)).uppercased()).font(Typography.font(.title, size: 26))
    }

    private func row(_ item: UsDestination, _ title: String, subtitle: String?, icon: String) -> some View {
        NavigationLink(value: item) {
            DSRow(title, subtitle: subtitle, systemImage: icon) {
                Image(systemName: "chevron.right").foregroundStyle(Color.inkMuted)
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("us.\(item.rawValue)")
    }
}
