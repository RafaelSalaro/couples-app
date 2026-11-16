import Backend
import Core
import FeatureSupport
import Foundation
import Observation
import Purchases

/// Settings (feature spec §13): profile, daily maximum, notification categories, subscription,
/// export, account deletion, legal and support links.
@MainActor @Observable
public final class SettingsModel {
    public let app: AppModel
    public var name: String
    public var message: String?
    public private(set) var exportURL: URL?
    public private(set) var isDeleting = false

    public init(app: AppModel) {
        self.app = app
        name = app.profile?.displayName ?? ""
    }

    // MARK: Profile

    public var canSaveName: Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && trimmed.count <= 60 && trimmed != app.profile?.displayName
    }

    public func saveName() async {
        do {
            try await app.updateDisplayName(name.trimmingCharacters(in: .whitespacesAndNewlines))
            message = nil
        } catch {
            message = Friendly.message(for: error)
        }
    }

    // MARK: Minutes

    public var dailyMax: Int { app.settings.dailyMaxMinutes }

    public func setDailyMax(_ minutes: Int) async {
        guard MinutesRules.dailyMaxRange.contains(minutes) else { return }
        do {
            try await app.updateSettings { $0.dailyMaxMinutes = minutes }
        } catch {
            message = Friendly.message(for: error)
        }
    }

    /// Weekly emergency minutes, chosen next to the daily maximum (P14).
    public var emergencyAllowance: Int { app.settings.emergencyAllowanceMinutes }

    public func setEmergencyAllowance(_ minutes: Int) async {
        guard EmergencyRules.allowanceChoices.contains(minutes) else { return }
        do {
            try await app.updateSettings { $0.emergencyAllowanceMinutes = minutes }
            await app.refreshEmergency()
        } catch {
            message = Friendly.message(for: error)
        }
    }

    /// What signing out means, said before it happens (P30).
    public var signOutExplanation: String {
        if let partner = app.partnerName {
            return L("Protected time pauses on this phone until you sign back in. You stay paired with \(partner), and \(partner) will see that protected time is off on your phone.")
        }
        return L("Protected time pauses on this phone until you sign back in.")
    }

    // MARK: Notifications

    public static func title(_ kind: NotificationKind) -> String {
        switch kind {
        case .unlockRequest: L("Unlock requests")
        case .requestResult: L("Answers to your requests")
        case .challengeDone: L("Challenges marked done")
        case .kudos: L("Kudos")
        case .scheduleRequest: L("Protected time requests")
        case .minutesExpiring: L("Minutes expiring tomorrow")
        case .weeklyReport: L("Weekly report")
        case .partnerStatus: L("Partner updates")
        }
    }

    public func isOn(_ kind: NotificationKind) -> Bool { !app.settings.notificationPrefs.isMuted(kind) }

    /// Unlock requests and protected-time requests cannot be muted: they are time-sensitive (§11).
    public func setOn(_ isOn: Bool, for kind: NotificationKind) async {
        guard kind.canBeMuted else { return }
        do {
            try await app.updateSettings { $0.notificationPrefs.setMuted(!isOn, for: kind) }
        } catch {
            message = Friendly.message(for: error)
        }
    }

    /// The weekly report by email is off unless the person turns it on (decision P24).
    public var weeklyReportEmail: Bool { app.settings.notificationPrefs.weeklyReportEmail }

    public func setWeeklyReportEmail(_ isOn: Bool) async {
        do {
            try await app.updateSettings { $0.notificationPrefs.weeklyReportEmail = isOn }
        } catch {
            message = Friendly.message(for: error)
        }
    }

    // MARK: Subscription

    public var subscriptionLine: String {
        let premium = app.premium
        guard premium.isPremium else { return L("Free. Premium is one price for both of you.") }
        let payer = premium.payerID == app.myID ? L("you") : (app.partnerName ?? L("your partner"))
        switch premium.kind {
        case .lifetime: return L("Premium for both of you, for good. Thanks to \(payer).")
        case .trial:
            let end = premium.expiresAt.map { $0.formatted(date: .abbreviated, time: .omitted) } ?? ""
            return L("Free trial for both of you until \(end).")
        default: return L("Premium for both of you. Paid by \(payer).")
        }
    }

    // MARK: Export and deletion

    public func export() async {
        do {
            let data = try await app.deps.backend.exportMyData()
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("my-data.json")
            try data.write(to: url, options: .atomic)
            exportURL = url
            message = nil
        } catch {
            message = Friendly.message(for: error)
        }
    }

    /// Where Apple lets people cancel a subscription; deleting the account does not cancel it (§14).
    public static let manageSubscriptionsURL = URL(string: "https://apps.apple.com/account/subscriptions")!

    public var deletionPoints: [String] {
        var points = [
            L("Your account and personal data are removed within 30 days."),
            L("Your minutes, history, challenges and kudos are deleted."),
        ]
        if let name = app.partnerName { points.insert(L("You and \(name) are unpaired right away."), at: 0) }
        points.append(L("This does not cancel an Apple subscription. You can cancel it in your Apple account."))
        return points
    }

    /// Step two of the two-step deletion.
    public func deleteAccount() async {
        isDeleting = true
        defer { isDeleting = false }
        do {
            try await app.deps.backend.deleteAccount()
            await app.deps.purchases.signOut()
            app.accountDeleted()
        } catch {
            message = Friendly.message(for: error)
        }
    }

    public func signOut() async {
        await app.signOut()
    }
}

/// The paywall (06 §6): "One price for both of you", benefits, yearly and lifetime, trial, restore.
@MainActor @Observable
public final class PaywallModel {
    public let app: AppModel
    public private(set) var offers: [ProductOffer] = []
    public var selected = PremiumProduct.yearly
    public var message: String?
    public private(set) var isWorking = false
    /// The purchase went through; premium is on (or on its way from the server).
    public private(set) var thanks = false

    public init(app: AppModel) { self.app = app }

    public func load() async {
        do {
            offers = try await app.deps.purchases.offers()
            if !offers.contains(where: { $0.product == selected }), let first = offers.first { selected = first.product }
        } catch {
            message = L("The store isn't reachable right now. Please try again in a moment.")
        }
    }

    public var benefits: [String] {
        [
            L("The full challenge library, and your own challenges"),
            L("Kudos: give each other minutes, just because"),
            L("Full reports: history, charts and highlights"),
            L("Up to 3 protected times, and any unlock length"),
        ]
    }

    /// The trial is counted once per pair: it is offered only if neither of you has used it.
    public var trialAvailable: Bool { !app.premium.trialUsed && !app.premium.isPremium }
    public var selectedOffer: ProductOffer? { offers.first { $0.product == selected } }
    public func priceLine(_ offer: ProductOffer) -> String { PriceText.line(offer) }
    public func detailLine(_ offer: ProductOffer) -> String? { trialAvailable ? PriceText.trialLine(offer) : nil }
    public var actionTitle: String { selectedOffer.map { PriceText.action($0, trialAvailable: trialAvailable) } ?? L("Continue") }
    public var footnote: String {
        L("Free stays free: pairing, protected time, every way to unlock and the emergency unlock. If premium ends you keep your minutes; extra challenges and protected times rest until you're back.")
    }

    /// Waits briefly for the server (via the store's webhook) to confirm the pair's premium.
    private func confirmPremium() async {
        for _ in 0..<10 {
            await app.refreshPremium()
            if app.isPremium { break }
            try? await Task.sleep(for: .milliseconds(500))
        }
        await app.handle(.premiumChanged)
    }

    public func purchase() async {
        guard !isWorking else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            switch try await app.deps.purchases.purchase(selected) {
            case .purchased:
                await confirmPremium()
                thanks = true
                message = nil
                await app.deps.backend.logEvent("purchase_completed", props: ["product": selected.rawValue])
            case .pending:
                message = L("Your purchase is waiting for approval. Premium turns on for both of you as soon as it goes through.")
            case .cancelled:
                message = nil
            }
        } catch {
            message = L("The purchase didn't go through. Nothing was charged.")
        }
    }

    public func restore() async {
        guard !isWorking else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            if try await app.deps.purchases.restore() {
                await confirmPremium()
                thanks = true
                message = nil
            } else {
                message = L("No earlier purchase was found for this Apple account.")
            }
        } catch {
            message = L("Restoring didn't work just now. Please try again in a moment.")
        }
    }

    public var thanksLine: String {
        app.partnerName.map { L("Premium is on for you and \($0).") } ?? L("Premium is on. It will cover your partner too.")
    }
}
