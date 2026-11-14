import Blocking
import Core
import ManagedSettings
import UserNotifications

/// Handles the pause-screen buttons. A shield button cannot open the app (decision T3), so
/// "Ask {partner}" posts a time-sensitive local notification whose tap opens the unlock sheet
/// (`couplesapp://unlock`), then closes the paused app. "Not now" just closes it.
final class ShieldActionExtension: ShieldActionDelegate {
    private func respond(to action: ShieldAction, completionHandler: @escaping (ShieldActionResponse) -> Void) {
        guard action == .primaryButtonPressed else {
            completionHandler(.close)
            return
        }
        let store = AppGroupStateStore()
        // Also leave a note in the App Group, in case the person opens the app without tapping the notification.
        let state = store.update { $0.unlockPromptRequestedAt = Date() }
        let scheme = (Bundle.main.object(forInfoDictionaryKey: "AppURLScheme") as? String) ?? "couplesapp"
        let prompt = ShieldPrompt.make(state: state, urlScheme: scheme)
        let content = UNMutableNotificationContent()
        content.title = prompt.title
        content.body = prompt.body
        content.sound = .default
        content.interruptionLevel = .timeSensitive
        content.userInfo = ["link": prompt.deepLink?.absoluteString ?? ""]
        let request = UNNotificationRequest(identifier: ShieldPrompt.identifier, content: content, trigger: nil)
        nonisolated(unsafe) let done = completionHandler
        UNUserNotificationCenter.current().add(request) { _ in
            done(.close)
        }
    }

    override func handle(action: ShieldAction, for application: ApplicationToken, completionHandler: @escaping (ShieldActionResponse) -> Void) {
        respond(to: action, completionHandler: completionHandler)
    }

    override func handle(action: ShieldAction, for webDomain: WebDomainToken, completionHandler: @escaping (ShieldActionResponse) -> Void) {
        respond(to: action, completionHandler: completionHandler)
    }

    override func handle(action: ShieldAction, for category: ActivityCategoryToken, completionHandler: @escaping (ShieldActionResponse) -> Void) {
        respond(to: action, completionHandler: completionHandler)
    }
}
