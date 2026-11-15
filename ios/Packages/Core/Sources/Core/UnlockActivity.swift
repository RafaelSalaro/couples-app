import Foundation

#if os(iOS)
import ActivityKit

/// The unlock countdown Live Activity (06 §8). Shared by the app, which starts and ends it,
/// and the widget extension, which draws it.
public struct UnlockActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable, Sendable {
        public var startedAt: Date
        public var endsAt: Date

        public init(startedAt: Date, endsAt: Date) {
            self.startedAt = startedAt
            self.endsAt = endsAt
        }
    }

    /// The partner's first name, for "Time with Ana" style wording; nil when unpaired.
    public var partnerName: String?

    public init(partnerName: String?) { self.partnerName = partnerName }
}
#endif

/// What a push notification asks the app to do (06 §9). Parsed from the payload's custom keys.
public enum PushIntent: Equatable, Sendable {
    /// Answer the partner's unlock request from the notification: "Go for it" or "Let's wait".
    case answerUnlockRequest(id: UUID, approve: Bool)
    case confirmCompletion(id: UUID)
    case answerScheduleChange(id: UUID, approve: Bool)
    /// Open something in the app.
    case open(URL)

    public enum Category: String, CaseIterable, Sendable {
        case unlockRequest = "UNLOCK_REQUEST"
        case completionConfirm = "COMPLETION_CONFIRM"
        case scheduleChange = "SCHEDULE_CHANGE"
    }

    public enum Action: String, Sendable {
        case goForIt = "GO_FOR_IT"
        case letsWait = "LETS_WAIT"
        case confirm = "CONFIRM"
        case approve = "APPROVE"
        case letsTalk = "LETS_TALK"
    }

    /// - Parameters:
    ///   - action: the tapped action identifier, or nil when the notification itself was tapped.
    ///   - payload: the notification's custom keys (`request_id`, `completion_id`, `change_id`, `link`, `kind`).
    public static func parse(category: String, action: String?, payload: [String: String], urlScheme: String) -> PushIntent? {
        func id(_ key: String) -> UUID? { payload[key].flatMap(UUID.init(uuidString:)) }
        let tapped = action.flatMap(Action.init(rawValue:))
        switch (Category(rawValue: category), tapped) {
        case (.unlockRequest, .goForIt): if let id = id("request_id") { return .answerUnlockRequest(id: id, approve: true) }
        case (.unlockRequest, .letsWait): if let id = id("request_id") { return .answerUnlockRequest(id: id, approve: false) }
        case (.completionConfirm, .confirm): if let id = id("completion_id") { return .confirmCompletion(id: id) }
        case (.scheduleChange, .approve): if let id = id("change_id") { return .answerScheduleChange(id: id, approve: true) }
        case (.scheduleChange, .letsTalk): if let id = id("change_id") { return .answerScheduleChange(id: id, approve: false) }
        default: break
        }
        // A plain tap: follow the link if there is one, else open the matching place.
        if let link = payload["link"].flatMap(URL.init(string:)), link.scheme != nil { return .open(link) }
        if let id = id("request_id") { return URL(string: "\(urlScheme)://request/\(id.uuidString)").map(PushIntent.open) }
        if let id = payload["challenge_id"].flatMap(UUID.init(uuidString:)) {
            return URL(string: "\(urlScheme)://challenge/\(id.uuidString)").map(PushIntent.open)
        }
        if let kind = payload["kind"], let url = URL(string: "\(urlScheme)://\(kind)") { return .open(url) }
        return nil
    }
}
