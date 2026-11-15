import Core
import DesignSystem
import FeatureSupport
import Purchases
import SwiftUI

public struct SettingsScreen: View {
    @State private var model: SettingsModel
    @State private var deleting = false

    public init(app: AppModel) { _model = State(initialValue: SettingsModel(app: app)) }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.md) {
                SectionHeader(L("Profile"))
                Card {
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        TextField(L("Your name"), text: $model.name)
                            .textContentType(.givenName)
                            .dsField()
                            .accessibilityIdentifier("settings.name")
                        if model.canSaveName {
                            AsyncButton(L("Save name"), kind: .secondary) { await model.saveName() }
                                .accessibilityIdentifier("settings.saveName")
                        }
                        DSRow(L("Relationship"), subtitle: L("Couple"), systemImage: "heart")
                    }
                }

                SectionHeader(L("Minutes"))
                Card {
                    Stepper(
                        value: Binding(get: { model.dailyMax }, set: { value in Task { await model.setDailyMax(value) } }),
                        in: MinutesRules.dailyMaxRange, step: MinutesRules.dailyMaxStep
                    ) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(L("Most you'll spend in a day")).textRole(.body).foregroundStyle(Color.ink)
                            Text(MinutesText.short(model.dailyMax)).textRole(.heading).foregroundStyle(Color.glowStrong)
                        }
                    }
                    .accessibilityIdentifier("settings.dailyMax")
                }

                SectionHeader(L("Notifications"))
                Card {
                    VStack(spacing: Spacing.xs) {
                        ForEach(NotificationKind.allCases, id: \.self) { kind in
                            Toggle(isOn: Binding(get: { model.isOn(kind) }, set: { value in Task { await model.setOn(value, for: kind) } })) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(SettingsModel.title(kind)).textRole(.body).foregroundStyle(Color.ink)
                                    if !kind.canBeMuted {
                                        Text(L("Always on, so you never leave each other waiting")).textRole(.caption).foregroundStyle(Color.inkMuted)
                                    }
                                }
                            }
                            .disabled(!kind.canBeMuted)
                            .tint(Color.sage)
                            .accessibilityIdentifier("notify.\(kind.rawValue)")
                        }
                        Divider().overlay(Color.line)
                        Toggle(isOn: Binding(get: { model.weeklyReportEmail }, set: { value in Task { await model.setWeeklyReportEmail(value) } })) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(L("Weekly report by email")).textRole(.body).foregroundStyle(Color.ink)
                                Text(L("Off unless you turn it on")).textRole(.caption).foregroundStyle(Color.inkMuted)
                            }
                        }
                        .tint(Color.sage)
                        .accessibilityIdentifier("notify.email")
                    }
                }

                SectionHeader(L("Subscription"))
                Button {
                    model.app.sheet = .paywall
                } label: {
                    Card {
                        DSRow(L("Premium"), subtitle: model.subscriptionLine, systemImage: "sparkles") {
                            Image(systemName: "chevron.right").foregroundStyle(Color.inkMuted)
                        }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("settings.subscription")

                SectionHeader(L("Your data"))
                Card {
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        if let url = model.exportURL {
                            ShareLink(item: url) { Label(L("Save or share your data file"), systemImage: "square.and.arrow.up") }
                                .buttonStyle(.dsSecondary)
                                .accessibilityIdentifier("settings.exportShare")
                        } else {
                            AsyncButton(L("Export my data"), kind: .secondary) { await model.export() }
                                .accessibilityIdentifier("settings.export")
                        }
                        NavigationLink {
                            DeleteAccountView(model: model)
                        } label: {
                            DSRow(L("Delete account"), systemImage: "trash") {
                                Image(systemName: "chevron.right").foregroundStyle(Color.inkMuted)
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("settings.delete")
                    }
                }

                SectionHeader(L("Help"))
                Card {
                    VStack(spacing: Spacing.xs) {
                        link(L("Support and relationship safety"), model.app.deps.brand.safetyURL, icon: "lifepreserver", id: "settings.safety")
                        link(L("Help and contact"), model.app.deps.brand.supportURL, icon: "questionmark.circle", id: "settings.support")
                        link(L("Privacy policy"), model.app.deps.brand.privacyURL, icon: "hand.raised", id: "settings.privacy")
                        link(L("Terms"), model.app.deps.brand.termsURL, icon: "doc.text", id: "settings.terms")
                    }
                }
                AsyncButton(L("Sign out"), kind: .quiet) { await model.signOut() }
                    .accessibilityIdentifier("settings.signOut")
                if let message = model.message { NoteBanner(message, tone: .neutral) }
            }
            .padding(Spacing.md)
        }
        .pageBackground()
        .navigationTitle(L("Settings"))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("settings.screen")
    }

    private func link(_ title: String, _ url: URL, icon: String, id: String) -> some View {
        Link(destination: url) {
            DSRow(title, systemImage: icon) { Image(systemName: "arrow.up.right").foregroundStyle(Color.inkMuted) }
        }
        .accessibilityIdentifier(id)
    }
}

/// Account deletion in two steps (feature spec §14): what will happen, then a final confirmation.
struct DeleteAccountView: View {
    let model: SettingsModel
    @State private var confirming = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.md) {
                Text(L("Before you go"))
                    .textRole(.title)
                    .foregroundStyle(Color.ink)
                    .accessibilityAddTraits(.isHeader)
                Card {
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        ForEach(model.deletionPoints, id: \.self) { point in
                            Label(point, systemImage: "circle.fill")
                                .labelStyle(BulletLabelStyle())
                                .textRole(.callout)
                                .foregroundStyle(Color.ink)
                        }
                    }
                }
                Link(destination: SettingsModel.manageSubscriptionsURL) {
                    Label(L("Manage Apple subscriptions"), systemImage: "arrow.up.right")
                }
                .buttonStyle(.dsSecondary)
                if let message = model.message { NoteBanner(message, tone: .neutral) }
                // Red: one of the two truly destructive actions in the app.
                Button(L("Delete my account")) { confirming = true }
                    .buttonStyle(.dsDestructive)
                    .disabled(model.isDeleting)
                    .accessibilityIdentifier("delete.continue")
            }
            .padding(Spacing.md)
        }
        .pageBackground()
        .navigationTitle(L("Delete account"))
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(L("Delete your account for good?"), isPresented: $confirming, titleVisibility: .visible) {
            Button(L("Delete my account"), role: .destructive) { Task { await model.deleteAccount() } }
                .accessibilityIdentifier("delete.confirm")
            Button(L("Keep my account"), role: .cancel) {}
        } message: {
            Text(L("This can't be undone."))
        }
    }
}

private struct BulletLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.xs) {
            configuration.icon.font(.system(size: 6)).foregroundStyle(Color.inkMuted)
            configuration.title
        }
    }
}

/// The paywall. Every price says it covers both of you (decision M7).
public struct PaywallView: View {
    @State private var model: PaywallModel
    @Environment(\.dismiss) private var dismiss

    public init(app: AppModel) { _model = State(initialValue: PaywallModel(app: app)) }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Spacing.md) {
                    TwoLights(closeness: 1, diameter: 84, overlap: 0.45, glow: 0.8).accessibilityHidden(true)
                    SkyText(PriceText.headline, role: .hero)
                        .multilineTextAlignment(.center)
                        .minimumScaleFactor(0.6)
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityIdentifier("paywall.headline")
                    if model.thanks {
                        SkyText(model.thanksLine, role: .display)
                            .multilineTextAlignment(.center)
                            .accessibilityIdentifier("paywall.thanks")
                        Button(L("Lovely")) { dismiss() }
                            .buttonStyle(.dsGlow)
                            .accessibilityIdentifier("paywall.done")
                    } else {
                        SkyText(L("One of you subscribes. Both of you get everything."), role: .body, muted: true)
                            .multilineTextAlignment(.center)
                        Card {
                            VStack(alignment: .leading, spacing: Spacing.sm) {
                                ForEach(model.benefits, id: \.self) { benefit in
                                    Label(benefit, systemImage: "sparkle").textRole(.callout).foregroundStyle(Color.ink)
                                }
                            }
                        }
                        ForEach(model.offers) { offer in
                            Button {
                                Haptics.tick()
                                model.selected = offer.product
                            } label: {
                                Card(tone: model.selected == offer.product ? .glow : .raised) {
                                    DSRow(PriceText.title(offer.product), subtitle: model.detailLine(offer) ?? model.priceLine(offer)) {
                                        VStack(alignment: .trailing, spacing: 2) {
                                            Text(offer.price).textRole(.heading).foregroundStyle(Color.ink)
                                            Text(offer.product == .yearly ? L("a year, for both") : L("once, for both"))
                                                .textRole(.caption)
                                                .foregroundStyle(Color.inkMuted)
                                        }
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("\(PriceText.title(offer.product)). \(model.detailLine(offer) ?? model.priceLine(offer))")
                            .accessibilityAddTraits(model.selected == offer.product ? [.isSelected] : [])
                            .accessibilityIdentifier("paywall.\(offer.product.rawValue)")
                        }
                        if let offer = model.selectedOffer {
                            SkyText(model.detailLine(offer) ?? model.priceLine(offer), role: .callout)
                                .multilineTextAlignment(.center)
                                .accessibilityIdentifier("paywall.priceLine")
                        }
                        if let message = model.message {
                            NoteBanner(message, tone: .neutral).accessibilityIdentifier("paywall.message")
                        }
                        AsyncButton(model.actionTitle) { await model.purchase() }
                            .disabled(model.selectedOffer == nil)
                            .accessibilityIdentifier("paywall.buy")
                        AsyncButton(L("Restore purchases"), kind: .quiet) { await model.restore() }
                            .accessibilityIdentifier("paywall.restore")
                        SkyText(model.footnote, role: .caption, muted: true).multilineTextAlignment(.center)
                        HStack(spacing: Spacing.md) {
                            Link(L("Terms"), destination: model.app.deps.brand.termsURL)
                            Link(L("Privacy"), destination: model.app.deps.brand.privacyURL)
                        }
                        .textRole(.caption)
                    }
                }
                .padding(Spacing.lg)
            }
            .onSky(.goldenHour)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(L("Close")) { dismiss() }.accessibilityIdentifier("paywall.close") }
            }
        }
        .task { await model.load() }
    }
}
