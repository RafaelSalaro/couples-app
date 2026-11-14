import Backend
import Blocking
import Core
import FeatureSupport
import Foundation
import Observation

func L(_ key: String.LocalizationValue) -> String { String(localized: key, bundle: .module) }

/// The onboarding order of feature spec §2.
public enum OnboardingStep: String, CaseIterable, Sendable {
    case welcome, signIn, relationship, invite, notifications, screenTime, chooseApps, protectedTime, minutes, ready
}

@MainActor @Observable
public final class OnboardingModel {
    public let app: AppModel
    public private(set) var step: OnboardingStep
    public var relationship: RelationshipType = .romantic
    public var schedule: ProtectedSchedule = .standard()
    public var startingMinutes = MinutesRules.defaultStartingMinutes
    public var dailyMax = MinutesRules.defaultDailyMax
    public var selection: PausedAppsSelection?
    public var email = ""
    public private(set) var magicLinkSentTo: String?
    public private(set) var screenTimeDeclined = false
    /// A looser-than-default schedule chosen while already paired waits for the partner.
    public private(set) var scheduleWaitsForPartner = false
    public var message: String?

    public init(app: AppModel) {
        self.app = app
        if let user = app.myID {
            let saved = app.deps.flags.string(Self.stepKey(user)).flatMap(OnboardingStep.init(rawValue:))
            step = saved ?? .relationship
        } else {
            step = .welcome
        }
        loadDrafts()
    }

    static func stepKey(_ user: UUID) -> String { "onboarding.step.\(user.uuidString)" }

    private func loadDrafts() {
        if let existing = app.schedules.first { schedule = existing }
        startingMinutes = app.settings.startingMinutes
        dailyMax = app.settings.dailyMaxMinutes
        selection = app.deps.blocking.currentSelection()
    }

    /// Steps shown as dots: sign-in drops out once there is a session, the picker when Screen Time was declined.
    public var progress: Double {
        let all = OnboardingStep.allCases
        return Double((all.firstIndex(of: step) ?? 0) + 1) / Double(all.count)
    }

    func next(after step: OnboardingStep) -> OnboardingStep {
        switch step {
        case .welcome: app.session == nil ? .signIn : .relationship
        case .signIn: .relationship
        case .relationship: .invite
        case .invite: .notifications
        case .notifications: .screenTime
        // Without Screen Time access there is nothing to choose yet; the home screen offers to turn it on later.
        case .screenTime: app.blockingStatus == .approved ? .chooseApps : .protectedTime
        case .chooseApps: .protectedTime
        case .protectedTime: .minutes
        case .minutes, .ready: .ready
        }
    }

    func previous(before step: OnboardingStep) -> OnboardingStep? {
        switch step {
        case .welcome, .relationship: nil // signing in cannot be undone by going back
        case .signIn: .welcome
        case .invite: .relationship
        case .notifications: .invite
        case .screenTime: .notifications
        case .chooseApps: .screenTime
        case .protectedTime: app.blockingStatus == .approved ? .chooseApps : .screenTime
        case .minutes: .protectedTime
        case .ready: .minutes
        }
    }

    public var canGoBack: Bool { previous(before: step) != nil }

    private func go(to next: OnboardingStep) {
        message = nil
        step = next
        if let user = app.myID { app.deps.flags.set(next.rawValue, for: Self.stepKey(user)) }
    }

    public func advance() { go(to: next(after: step)) }
    public func back() { if let previous = previous(before: step) { go(to: previous) } }

    // MARK: Sign in

    public func signInWithApple() async {
        do {
            let credential = try await app.deps.appleSignIn.credential()
            let session = try await app.deps.backend.signInWithApple(idToken: credential.idToken, nonce: credential.nonce, fullName: credential.fullName)
            await didSignIn(session)
        } catch SignInError.cancelled {
            // Changing your mind is fine; say nothing.
        } catch {
            message = Friendly.message(for: error)
        }
    }

    public var emailLooksValid: Bool {
        let trimmed = email.trimmingCharacters(in: .whitespaces)
        guard let at = trimmed.firstIndex(of: "@"), at != trimmed.startIndex else { return false }
        return trimmed[at...].contains(".") && !trimmed.hasSuffix(".") && !trimmed.contains(" ")
    }

    public func sendMagicLink() async {
        let address = email.trimmingCharacters(in: .whitespaces)
        do {
            try await app.deps.backend.sendMagicLink(email: address)
            magicLinkSentTo = address
            message = nil
        } catch {
            message = Friendly.message(for: error)
        }
    }

    public func useDifferentEmail() { magicLinkSentTo = nil }

    /// Demo builds only: follow the link the email would contain.
    public var demoLink: URL? {
        guard let address = magicLinkSentTo else { return nil }
        return app.deps.demoMagicLink?(address)
    }

    public func openDemoLink() async {
        if let demoLink { await app.open(demoLink) }
        sessionChanged()
    }

    private func didSignIn(_ session: AuthSession) async {
        await app.signedIn(session)
        sessionChanged()
    }

    /// The session appeared (Apple, or the magic link opened the app): move on from the sign-in step.
    public func sessionChanged() {
        guard let user = app.myID, step == .welcome || step == .signIn else { return }
        guard app.phase == .onboarding else { return } // a returning user goes straight to the app
        let saved = app.deps.flags.string(Self.stepKey(user)).flatMap(OnboardingStep.init(rawValue:))
        loadDrafts()
        go(to: saved ?? .relationship)
    }

    // MARK: Permissions

    public func allowNotifications() async {
        _ = await app.deps.notifications.requestAuthorization()
        advance()
    }

    public func allowScreenTime() async {
        do {
            try await app.requestScreenTimeAccess()
            screenTimeDeclined = false
            advance()
        } catch {
            screenTimeDeclined = true
        }
    }

    // MARK: Choices

    public var canSaveApps: Bool { !(selection?.isEmpty ?? true) }

    public func saveApps() async {
        guard let selection, !selection.isEmpty else { return }
        do {
            _ = try await app.saveSelection(selection)
            advance()
        } catch {
            message = Friendly.message(for: error)
        }
    }

    public func saveSchedule() async {
        do {
            let existing = app.schedules.first
            if existing == schedule {
                advance()
                return
            }
            var proposal = schedule
            if let existing { proposal.id = existing.id }
            let outcome = try await app.submitSchedule(scheduleID: existing?.id, proposal: .schedule(proposal))
            if case .pending = outcome {
                scheduleWaitsForPartner = true
                if let existing { schedule = existing }
            } else {
                scheduleWaitsForPartner = false
            }
            advance()
        } catch {
            message = Friendly.message(for: error)
        }
    }

    public func saveMinutes() async {
        do {
            let start = startingMinutes, max = dailyMax
            try await app.updateSettings {
                $0.startingMinutes = start
                $0.dailyMaxMinutes = max
            }
            advance()
        } catch {
            message = Friendly.message(for: error)
        }
    }

    /// "Protected time starts at 6:00 PM." or, when it is already on, when it ends.
    public var readyLine: String {
        let zone = app.deps.timeZone()
        let evaluator = ScheduleEvaluator(timeZone: zone)
        let now = app.deps.now()
        let schedules = app.effectiveSchedules.isEmpty ? [schedule] : app.effectiveSchedules
        if app.blockingStatus != .approved {
            return L("Turn on Screen Time access whenever you're ready, and protected time will start.")
        }
        if let end = evaluator.protectionEnd(at: now, schedules: schedules) {
            return L("Protected time is on until \(ScheduleText.clock(end, timeZone: zone)).")
        }
        if let start = evaluator.nextStart(after: now, schedules: schedules) {
            return L("Protected time starts at \(ScheduleText.clock(start, timeZone: zone)).")
        }
        return L("Protected time is ready when you are.")
    }

    public func finish() async {
        if let user = app.myID { app.deps.flags.set(nil, for: Self.stepKey(user)) }
        await app.finishOnboarding()
    }
}
