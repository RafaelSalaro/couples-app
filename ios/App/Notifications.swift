import ActivityKit
import Blocking
import Core
import FeatureSupport
import UIKit
import UserNotifications

/// Registers the actionable categories (06 §9) and routes notification taps and buttons to the app model.
@MainActor
final class NotificationCoordinator: NSObject, UNUserNotificationCenterDelegate {
    private weak var model: AppModel?

    init(model: AppModel) {
        self.model = model
        super.init()
    }

    func start() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.setNotificationCategories(Self.categories)
    }

    /// "Go for it" / "Let's wait", "Confirm", "Approve" / "Let's talk". Answering needs the phone unlocked.
    static var categories: Set<UNNotificationCategory> {
        func action(_ id: PushIntent.Action, _ title: String) -> UNNotificationAction {
            UNNotificationAction(identifier: id.rawValue, title: title, options: [.authenticationRequired])
        }
        return [
            UNNotificationCategory(
                identifier: PushIntent.Category.unlockRequest.rawValue,
                actions: [action(.goForIt, L("Go for it")), action(.letsWait, L("Let's wait"))], intentIdentifiers: []
            ),
            UNNotificationCategory(
                identifier: PushIntent.Category.completionConfirm.rawValue,
                actions: [action(.confirm, L("Confirm"))], intentIdentifiers: []
            ),
            UNNotificationCategory(
                identifier: PushIntent.Category.scheduleChange.rawValue,
                actions: [action(.approve, L("Approve")), action(.letsTalk, L("Let's talk"))], intentIdentifiers: []
            ),
        ]
    }

    /// The payload's custom string keys.
    nonisolated static func payload(_ userInfo: [AnyHashable: Any]) -> [String: String] {
        var result: [String: String] = [:]
        for (key, value) in userInfo {
            if let key = key as? String, let value = value as? String { result[key] = value }
        }
        return result
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse
    ) async {
        let content = response.notification.request.content
        let action = response.actionIdentifier == UNNotificationDefaultActionIdentifier ? nil : response.actionIdentifier
        let payload = Self.payload(content.userInfo)
        // Awaited, not fired off: a button such as "Go for it" can launch the app in the
        // background, and iOS may suspend it as soon as this returns.
        await handle(category: content.categoryIdentifier, action: action, payload: payload)
    }

    private func handle(category: String, action: String?, payload: [String: String]) async {
        guard let intent = PushIntent.parse(category: category, action: action, payload: payload, urlScheme: AppBrand.urlScheme) else { return }
        await model?.perform(intent)
    }

    /// While the app is open the scene itself shows what happened; refresh and keep the banner quiet
    /// unless it is the pause-screen prompt, which the person asked for.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        Task { @MainActor in await self.model?.refresh() }
        return Self.foregroundOptions(identifier: notification.request.identifier)
    }

    nonisolated static func foregroundOptions(identifier: String) -> UNNotificationPresentationOptions {
        identifier == ShieldPrompt.identifier ? [.banner, .list, .sound] : [.list]
    }
}

/// The unlock countdown Live Activity (06 §8): started on every unlock, ended when the window closes.
struct LiveUnlockActivity: UnlockActivityControlling {
    func start(endsAt: Date, partnerName: String?) async {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let state = UnlockActivityAttributes.ContentState(startedAt: Date(), endsAt: endsAt)
        let content = ActivityContent(state: state, staleDate: endsAt)
        // Extending an unlock updates the running activity instead of starting a second one.
        if let running = Activity<UnlockActivityAttributes>.activities.first {
            await running.update(content)
        } else {
            _ = try? Activity.request(attributes: UnlockActivityAttributes(partnerName: partnerName), content: content, pushType: nil)
        }
        // If the app stays alive until the window closes, end the activity then; otherwise it is
        // marked stale at `endsAt` and cleared the next time the app opens.
        Task {
            try? await Task.sleep(for: .seconds(max(0, endsAt.timeIntervalSinceNow)))
            await endExpired()
        }
    }

    func end() async {
        for activity in Activity<UnlockActivityAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }

    func endExpired() async {
        for activity in Activity<UnlockActivityAttributes>.activities where activity.content.state.endsAt <= Date() {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }
}
