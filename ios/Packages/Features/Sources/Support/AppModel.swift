import Backend
import Blocking
import Core
import Foundation
import Observation

/// Sheets any screen can ask for; the app target maps each to its feature view.
public enum AppSheet: Identifiable, Equatable, Sendable {
    case unlock
    case showMyCode
    case incomingRequest(UnlockRequest)
    case giveKudos(challengeID: UUID?)
    case paywall
    case invite
    case mockShield

    public var id: String {
        switch self {
        case .unlock: "unlock"
        case .showMyCode: "showMyCode"
        case .incomingRequest(let request): "request-\(request.id)"
        case .giveKudos: "kudos"
        case .paywall: "paywall"
        case .invite: "invite"
        case .mockShield: "mockShield"
        }
    }
}

/// The app's places (doc 10 §11): tonight (the home scene), together (challenges and kudos)
/// and us (minutes, the week, protected time, settings).
public enum AppPlace: String, Hashable, Sendable, CaseIterable { case tonight, together, us }

/// Screens inside "us" that other places can jump to.
public enum UsDestination: String, Hashable, Sendable { case minutes, week, schedule, partner, settings }

/// Moments worth celebrating (06 §6). Shown once, then cleared.
public enum Celebration: Equatable, Sendable {
    case kudos(Kudos)
    case streak(Int)
    case paired(partnerName: String)
}

/// The latest news about the unlock request this person sent.
public struct OutgoingRequestUpdate: Equatable, Sendable {
    public var request: UnlockRequest
    public var unlock: Unlock?
}

/// The signed-in person's live state and the actions several features share.
@MainActor @Observable
public final class AppModel {
    public enum Phase: Equatable, Sendable { case launching, onboarding, ready }

    public let deps: AppDependencies
    public private(set) var phase: Phase = .launching
    public private(set) var session: AuthSession?
    public private(set) var profile: UserProfile?
    public private(set) var settings = UserSettings()
    public private(set) var pair: PairState?
    public private(set) var myMinutes: MinutesSummary?
    public private(set) var partnerMinutes: MinutesSummary?
    public private(set) var streak = Streak()
    public private(set) var premium = PremiumState.free
    public private(set) var schedules: [ProtectedSchedule] = []
    public private(set) var unlockRequests: [UnlockRequest] = []
    public private(set) var scheduleRequests: [ScheduleChangeRequest] = []
    public private(set) var resetProposals: [ResetProposal] = []
    public private(set) var challenges: [Challenge] = []
    public private(set) var completions: [ChallengeCompletion] = []
    public private(set) var activity: [ActivityItem] = []
    /// The weekly emergency allowance: used, left, renewal (P14).
    public private(set) var emergency = EmergencyAllowance.fresh
    /// Unlocks granted by the server that are opening the paused apps now; ending early ends each (P26).
    public private(set) var runningUnlocks: [Unlock] = []
    public private(set) var outgoingUpdate: OutgoingRequestUpdate?
    public private(set) var blockingStatus: BlockingAuthorization
    public private(set) var isOffline = false
    /// Bumped whenever an unlock starts, so the home ring can play its opening animation.
    public private(set) var unlockStartCount = 0

    public var sheet: AppSheet?
    public var place: AppPlace = .tonight
    /// A screen inside "us" to open (set together with `place = .us`).
    public var usDestination: UsDestination?
    public var celebration: Celebration?
    /// A short neutral note to show once (for example "Ana ended your pairing.").
    public var notice: String?
    /// An invite token or code that arrived by link before the person could use it.
    public var pendingInvite: String?
    /// The address the last sign-in link went to, to send a fresh one if it has expired.
    public var lastMagicLinkEmail: String?
    public var focusedChallengeID: UUID?

    private var listenTask: Task<Void, Never>?
    private var leavingPair = false
    /// The ended pair that was already announced (two refreshes can notice the same ending).
    private var announcedEndOfPair: UUID?
    private var startedUnlocks: Set<UUID> = []

    public init(deps: AppDependencies) {
        self.deps = deps
        blockingStatus = deps.blocking.authorizationStatus
    }

    // MARK: Derived

    public var myID: UUID? { session?.userID }
    public var isPaired: Bool { pair != nil }
    public var isPremium: Bool { premium.isPremium }
    public var myName: String { profile?.displayName.flatMap { $0.isEmpty ? nil : $0 } ?? L("You") }
    public var partnerName: String? {
        guard let pair else { return nil }
        return pair.partner.displayName.flatMap { $0.isEmpty ? nil : $0 } ?? L("your partner")
    }
    /// Requests from the partner waiting for an answer.
    public var incomingUnlockRequests: [UnlockRequest] { unlockRequests.filter { $0.requesterID != myID && $0.status == .pending } }
    public var effectiveSchedules: [ProtectedSchedule] { PremiumRules.effectiveSchedules(schedules, isPremium: isPremium) }
    public var visibleChallenges: [Challenge] { PremiumRules.visibleChallenges(challenges, isPremium: isPremium) }
    public var protectionPhase: SharedState.Phase { deps.store.load().phase(at: deps.now(), timeZone: deps.timeZone()) }
    /// Screen Time access is missing after setup: show the gentle re-enable screen.
    public var protectionNeedsAttention: Bool { phase == .ready && blockingStatus != .approved }
    /// Neutral status for the partner's phone (decision P23).
    public var partnerProtectionIsOff: Bool { pair?.partner.protectedTimeOffSince != nil }

    private func onboardingKey(_ user: UUID) -> String { "onboarding.done.\(user.uuidString)" }

    // MARK: Lifecycle

    /// Runs the launch once. A notification tap or link can arrive before the root view's
    /// `.task` starts it (a cold launch from the lock screen); both then wait for the same launch.
    public func bootstrap() async {
        if let launchTask { return await launchTask.value }
        let task = Task { await self.launch() }
        launchTask = task
        await task.value
    }

    private var launchTask: Task<Void, Never>?

    private func launch() async {
        session = await deps.backend.currentSession()
        if let session {
            // Purchases are tied to our user id so the server can share premium with the partner.
            await deps.purchases.signIn(userID: session.userID)
            await refresh()
            phase = deps.flags.string(onboardingKey(session.userID)) == "1" ? .ready : .onboarding
            startListening()
        } else {
            phase = .onboarding
        }
        await checkProtection()
    }

    /// Called by onboarding once sign-in succeeds. Everything is restored from the server; a
    /// returning user whose onboarding is done (on any phone) goes straight to the app unless
    /// something that lives on this phone is missing (P29).
    /// True while signedIn() is loading the account: the session is set but the profile and
    /// settings are not yet known, so nothing should route on them.
    public private(set) var isLoadingAccount = false

    public func signedIn(_ session: AuthSession) async {
        isLoadingAccount = true
        defer { isLoadingAccount = false }
        self.session = session
        await deps.purchases.signIn(userID: session.userID)
        await refresh()
        startListening()
        if settings.onboardedAt != nil { deps.flags.set("1", for: onboardingKey(session.userID)) }
        if deps.flags.string(onboardingKey(session.userID)) == "1", hasName, phoneIsReady {
            phase = .ready
            await checkProtection()
        }
    }

    /// The partner sees this name; it is required (P27).
    public var hasName: Bool { !(profile?.displayName?.trimmingCharacters(in: .whitespaces).isEmpty ?? true) }

    /// What only this phone holds: Screen Time access and the chosen apps (a new phone asks again).
    public var phoneIsReady: Bool {
        deps.blocking.authorizationStatus == .approved && !(deps.blocking.currentSelection()?.isEmpty ?? true)
    }

    /// Whether this account finished onboarding before (on this phone or another).
    public var isReturning: Bool { settings.onboardedAt != nil }

    public func finishOnboarding() async {
        guard let myID else { return }
        deps.flags.set("1", for: onboardingKey(myID))
        if settings.onboardedAt == nil {
            let at = deps.now()
            try? await updateSettings { $0.onboardedAt = at }
        }
        phase = .ready
        await refresh()
        await checkProtection()
        await deps.backend.logEvent("onboarding_completed", props: [:])
    }


    /// Signing out keeps the pair; protected time pauses on this phone until signing back in,
    /// and the partner sees the neutral "protected time is off" status (P30).
    public func signOut() async {
        listenTask?.cancel()
        if await attempt({ try await deps.backend.setProtectedTimeOff(true) }) != nil {
            deps.flags.set("1", for: Self.reportedOffKey)
        }
        if let active = deps.store.load().activeUnlock { try? deps.blocking.endUnlockEarly(id: active.id) }
        try? deps.blocking.applySchedule([])
        await deps.unlockActivity.end()
        runningUnlocks.removeAll()
        await deps.purchases.signOut()
        try? await deps.backend.signOut()
        clearAccountState()
        place = .tonight // signing back in starts on Tonight, not where you left off
        phase = .onboarding
    }

    private func clearAccountState() {
        session = nil
        profile = nil
        pair = nil
        myMinutes = nil
        partnerMinutes = nil
        streak = Streak()
        premium = .free
        unlockRequests = []
        scheduleRequests = []
        resetProposals = []
        completions = []
        activity = []
        deps.qrSecrets.save(nil)
        deps.store.update {
            $0.partnerName = nil
            $0.myBalance = nil
            $0.partnerBalance = nil
            $0.streak = nil
        }
        deps.reloadWidgets()
    }

    /// The account was deleted on the server: forget everything local, including onboarding.
    public func accountDeleted() {
        if let myID { deps.flags.set(nil, for: onboardingKey(myID)) }
        listenTask?.cancel()
        clearAccountState()
        phase = .onboarding
    }

    /// The app came to the foreground.
    public func becameActive() async {
        await checkProtection()
        let state = deps.store.load()
        if let asked = state.unlockPromptRequestedAt {
            deps.store.update { $0.unlockPromptRequestedAt = nil }
            if deps.now().timeIntervalSince(asked) < 15 * 60, phase == .ready { sheet = .unlock }
        }
        if session != nil { await refresh() }
    }

    // MARK: Loading

    private func attempt<T>(_ body: () async throws -> T) async -> T? {
        do {
            let value = try await body()
            isOffline = false
            return value
        } catch let error as BackendError where error.code == .offline {
            isOffline = true
            return nil
        } catch {
            return nil
        }
    }

    public func refresh() async {
        guard session != nil else { return }
        if let value = await attempt({ try await deps.backend.fetchProfile() }) { profile = value }
        if let value = await attempt({ try await deps.backend.fetchSettings() }) { settings = value }
        await refreshPair()
        await refreshPremium()
        if let value = await attempt({ try await deps.backend.fetchSchedules() }) { schedules = value }
        await refreshMinutes()
        await refreshRequests()
        await refreshChallenges()
        if let value = await attempt({ try await deps.backend.fetchStreak() }) { streak = value }
        if let value = await attempt({ try await deps.backend.fetchActivity(limit: 30) }) { activity = value }
        await refreshEmergency()
        await syncPendingQRUnlocks()
        syncDevice()
    }

    public func refreshEmergency() async {
        if let value = await attempt({ try await deps.backend.emergencyStatus() }) { emergency = value }
    }

    public func refreshPair() async {
        guard let value = await attempt({ try await deps.backend.fetchPairState() }) else { return }
        pair = value
        if value != nil {
            if let secret = await attempt({ try await deps.backend.fetchQRSecret() }) { deps.qrSecrets.save(secret) }
        } else {
            deps.qrSecrets.save(nil)
        }
    }

    public func refreshPremium() async {
        if let value = await attempt({ try await deps.backend.fetchPremium() }) { premium = value }
    }

    public func refreshMinutes() async {
        guard let value = await attempt({ try await deps.backend.fetchMinutes() }) else { return }
        myMinutes = value.mine
        partnerMinutes = value.partner
        syncDevice()
    }

    public func refreshRequests() async {
        if let value = await attempt({ try await deps.backend.fetchPendingUnlockRequests() }) { unlockRequests = value }
        if let value = await attempt({ try await deps.backend.fetchScheduleChangeRequests() }) { scheduleRequests = value }
        if let value = await attempt({ try await deps.backend.fetchResetProposals() }) { resetProposals = value }
    }

    public func refreshChallenges() async {
        if let value = await attempt({ try await deps.backend.fetchChallenges() }) { challenges = value }
        if let value = await attempt({ try await deps.backend.fetchCompletions() }) { completions = value }
    }

    public func refreshActivity() async {
        if let value = await attempt({ try await deps.backend.fetchActivity(limit: 30) }) { activity = value }
    }

    /// Sends offline QR unlocks once the network is back (feature spec §15).
    public func syncPendingQRUnlocks() async {
        let pending = deps.pendingQRUnlocks.all
        guard !pending.isEmpty, isPaired else { return }
        do {
            try await deps.backend.syncQRUnlocks(pending)
            deps.pendingQRUnlocks.remove(pending)
        } catch let error as BackendError where error.code == .duplicateCounter {
            // The server already has (or refuses) them; there is nothing left to retry.
            deps.pendingQRUnlocks.remove(pending)
        } catch {}
    }

    /// Pushes what the extensions and widgets need into the App Group and re-registers the schedule.
    public func syncDevice() {
        try? deps.blocking.applySchedule(effectiveSchedules)
        let partner = partnerName
        deps.store.update {
            $0.myName = profile?.displayName
            $0.partnerName = partner
            $0.myBalance = myMinutes?.balance
            $0.partnerBalance = partnerMinutes?.balance
            $0.streak = pair == nil ? nil : streak.currentLength
        }
        deps.reloadWidgets()
    }

    // MARK: Screen Time access

    /// Checks Screen Time access on launch and whenever the app becomes active (06 §4) and
    /// tells the server when protected time goes off or comes back, so the partner sees a neutral status.
    static let reportedOffKey = "protection.reportedOff"

    public func checkProtection() async {
        blockingStatus = deps.blocking.authorizationStatus
        guard phase == .ready, session != nil else { return }
        let isOff = blockingStatus != .approved
        let key = Self.reportedOffKey
        guard (deps.flags.string(key) == "1") != isOff else { return }
        if await attempt({ try await deps.backend.setProtectedTimeOff(isOff) }) != nil {
            deps.flags.set(isOff ? "1" : nil, for: key)
        }
    }

    public func requestScreenTimeAccess() async throws {
        defer { blockingStatus = deps.blocking.authorizationStatus }
        try await deps.blocking.requestAuthorization()
        blockingStatus = deps.blocking.authorizationStatus
        syncDevice()
        await checkProtection()
    }

    // MARK: Events

    private func startListening() {
        listenTask?.cancel()
        let stream = deps.backend.events()
        listenTask = Task { [weak self] in
            for await event in stream {
                guard let self, !Task.isCancelled else { return }
                await self.handle(event)
            }
        }
    }

    public func handle(_ event: BackendEvent) async {
        switch event {
        case .minutesChanged:
            await refreshMinutes()
            await refreshActivity()
        case .unlockRequestChanged(let request, let unlock):
            if request.requesterID == myID {
                outgoingUpdate = OutgoingRequestUpdate(request: request, unlock: unlock)
                if let unlock, request.status == .approved || request.status == .redeemed { await beginUnlock(unlock) }
            } else {
                await refreshRequests()
                if request.status == .pending, sheet == nil, phase == .ready { sheet = .incomingRequest(request) }
                if request.status != .pending, case .incomingRequest(let shown) = sheet, shown.id == request.id { sheet = nil }
            }
            await refreshActivity()
        case .completionChanged, .challengeChanged:
            await refreshChallenges()
            await refreshMinutes()
        case .kudosReceived(let kudos):
            await refreshMinutes()
            await refreshActivity()
            if kudos.receiverID == myID { celebration = .kudos(kudos) }
        case .scheduleChangeChanged(let request):
            if request.requesterID == myID, request.status == .approved, request.proposed == .fewerPausedApps {
                applyPendingSelection()
            }
            if request.requesterID == myID, request.status != .approved, request.proposed == .fewerPausedApps {
                deps.flags.set(nil, for: Self.pendingSelectionKey)
            }
            if let value = await attempt({ try await deps.backend.fetchSchedules() }) { schedules = value }
            await refreshRequests()
            syncDevice()
        case .resetProposalChanged:
            await refreshRequests()
            await refreshMinutes()
        case .streakChanged(let value):
            let before = streak.currentLength
            streak = value
            syncDevice()
            if value.isMilestone, value.currentLength > before { celebration = .streak(value.currentLength) }
        case .pairChanged:
            let before = pair
            await refreshPair()
            await refreshPremium()
            await refreshMinutes()
            await refreshRequests()
            await refreshChallenges()
            if let value = await attempt({ try await deps.backend.fetchStreak() }) { streak = value }
            if let old = before, pair == nil, announcedEndOfPair != old.pair.id {
                announcedEndOfPair = old.pair.id
                // Gentle, with no reason asked or given (feature spec §3).
                let name = old.partner.displayName ?? L("Your partner")
                notice = leavingPair ? L("You're no longer paired. Your protected time stays as it is.") : L("\(name) ended your pairing.")
                leavingPair = false
                if case .incomingRequest = sheet { sheet = nil }
            } else if before == nil, let name = partnerName {
                // The celebration takes the whole screen; put the invite sheet away first.
                if sheet == .invite { sheet = nil }
                celebration = .paired(partnerName: name)
                // The pair channel only exists now; listen to it.
                startListening()
            }
            syncDevice()
        case .premiumChanged:
            await refreshPremium()
            await refreshChallenges()
            syncDevice()
        case .partnerStatusChanged:
            await refreshPair()
            await refreshActivity()
            if let value = await attempt({ try await deps.backend.fetchStreak() }) { streak = value }
        case .qrSecretRotated:
            await refreshPair()
        }
    }

    // MARK: Shared actions

    /// Opens the paused apps for an unlock the server (or the offline QR check) granted.
    /// Safe to call twice for the same unlock.
    public func beginUnlock(_ unlock: Unlock) async {
        guard !startedUnlocks.contains(unlock.id) else { return }
        startedUnlocks.insert(unlock.id)
        do {
            try deps.blocking.startUnlock(id: unlock.id, minutes: unlock.minutes)
        } catch {
            startedUnlocks.remove(unlock.id)
            notice = Friendly.message(for: error)
            return
        }
        unlockStartCount += 1
        if let active = deps.store.load().activeUnlock {
            await deps.unlockActivity.start(endsAt: active.endsAt, partnerName: partnerName)
        }
        deps.reloadWidgets()
        runningUnlocks.removeAll { !$0.isActive(at: deps.now()) }
        runningUnlocks.append(unlock)
        if unlock.method == .emergency { await refreshEmergency() }
        await refreshMinutes()
        await refreshActivity()
    }

    /// What ending now means for the unused time, for the confirmation (P26). Nil when nothing runs.
    public var endEarlySummary: String? {
        let now = deps.now()
        let running = runningUnlocks.filter { $0.isActive(at: now) }
        guard deps.store.load().activeUnlock?.isActive(at: now) == true else { return nil }
        if let session = running.first(where: { $0.method == .emergency }) {
            let used = emergency.used - session.minutes + min(session.minutes, UnlockRules.minutesUsed(from: session.startedAt, to: now))
            let left = max(0, emergency.allowance - used)
            if let renews = emergency.renewsAt {
                return L("You've used \(MinutesText.short(used)) of your \(MinutesText.short(emergency.allowance)) emergency minutes this week. The other \(MinutesText.short(left)) stay available until \(ScheduleText.weekday(renews, timeZone: deps.timeZone())).")
            }
            return L("You've used \(MinutesText.short(used)) of your \(MinutesText.short(emergency.allowance)) emergency minutes this week. The rest stay available.")
        }
        let refund = running.filter { $0.method == .minutes }.reduce(0) { $0 + UnlockRules.unusedWholeMinutes(endsAt: $1.endsAt, now: now) }
        if refund > 0 {
            return L("The \(MinutesText.short(refund)) you haven't used go back to your balance. Protected time comes back now.")
        }
        return L("Protected time comes back now.")
    }

    /// Ends the current unlock now; protected time resumes. Each running unlock is ended on the
    /// server too, so unused minutes come back and an emergency session borrows only what was used (P26).
    public func endUnlockEarly() async {
        guard let active = deps.store.load().activeUnlock else { return }
        let now = deps.now()
        for unlock in runningUnlocks where unlock.isActive(at: now) && unlock.method != .qr {
            _ = await attempt({ try await deps.backend.endUnlockEarly(unlockID: unlock.id) })
        }
        runningUnlocks.removeAll()
        try? deps.blocking.endUnlockEarly(id: active.id)
        await deps.unlockActivity.end()
        deps.reloadWidgets()
        unlockStartCount += 1
        await refreshMinutes()
        await refreshEmergency()
        await refreshActivity()
    }

    /// Unpairs right away. Either partner can, with no approval from the other (feature spec §3).
    public func unpair() async throws {
        leavingPair = true
        do {
            try await deps.backend.unpair()
        } catch {
            leavingPair = false
            throw error
        }
        await handle(.pairChanged)
    }

    public func updateSettings(_ change: (inout UserSettings) -> Void) async throws {
        var next = settings
        change(&next)
        try await deps.backend.updateSettings(next)
        settings = next
        await refreshMinutes()
    }

    public func updateDisplayName(_ name: String) async throws {
        profile = try await deps.backend.updateProfile(displayName: name, timeZone: deps.timeZone().identifier)
        syncDevice()
    }

    /// Submits a schedule edit. Stricter changes (or any change when unpaired) apply right away;
    /// looser ones wait for the partner.
    @discardableResult
    public func submitSchedule(scheduleID: UUID?, proposal: ScheduleProposal) async throws -> ScheduleChangeOutcome {
        let outcome = try await deps.backend.submitScheduleChange(scheduleID: scheduleID, proposal: proposal)
        if case .applied(let value) = outcome {
            schedules = value
            syncDevice()
        }
        await refreshRequests()
        return outcome
    }

    static let pendingSelectionKey = "selection.pending"

    public enum SelectionOutcome: Equatable, Sendable { case saved, waitingForPartner }

    /// Saves the paused-apps choice. Pausing fewer apps is a looser change: when paired it waits for
    /// the partner, who is only told "fewer apps", never which ones. The tokens stay on this phone.
    public func saveSelection(_ selection: PausedAppsSelection) async throws -> SelectionOutcome {
        let change = deps.blocking.selectionChange(from: deps.blocking.currentSelection(), to: selection)
        if change == .looser, isPaired {
            let outcome = try await deps.backend.submitScheduleChange(scheduleID: nil, proposal: .fewerPausedApps)
            if case .pending = outcome {
                deps.flags.set((try? JSONEncoder().encode(selection))?.base64EncodedString(), for: Self.pendingSelectionKey)
                await refreshRequests()
                return .waitingForPartner
            }
        }
        try deps.blocking.saveSelection(selection)
        syncDevice()
        return .saved
    }

    private func applyPendingSelection() {
        guard let encoded = deps.flags.string(Self.pendingSelectionKey), let data = Data(base64Encoded: encoded),
              let selection = try? JSONDecoder().decode(PausedAppsSelection.self, from: data) else { return }
        try? deps.blocking.saveSelection(selection)
        deps.flags.set(nil, for: Self.pendingSelectionKey)
    }

    // MARK: Notifications

    /// Carries out what a notification (or one of its buttons) asked for (06 §9).
    public func perform(_ intent: PushIntent) async {
        await bootstrap()
        do {
            switch intent {
            case .answerUnlockRequest(let id, let approve):
                try await deps.backend.respondUnlockRequest(id: id, approve: approve)
                await refreshRequests()
                if case .incomingRequest(let shown) = sheet, shown.id == id { sheet = nil }
            case .confirmCompletion(let id):
                try await deps.backend.confirmCompletion(id: id)
                await refreshChallenges()
                await refreshMinutes()
            case .answerScheduleChange(let id, let approve):
                try await deps.backend.respondScheduleChange(requestID: id, approve: approve)
                await refreshRequests()
            case .open(let url):
                await open(url)
            }
        } catch {
            notice = Friendly.message(for: error)
        }
    }

    // MARK: Links

    /// Handles `couplesapp://…` links, invite universal links and the magic-link callback.
    public func open(_ url: URL) async {
        await bootstrap()
        guard let link = DeepLink.parse(url, scheme: deps.brand.urlScheme, domain: deps.brand.websiteDomain) else { return }
        switch link {
        case .unlock:
            if phase == .ready { sheet = .unlock }
        case .request(let id):
            await refreshRequests()
            if let request = incomingUnlockRequests.first(where: { $0.id == id }), phase == .ready {
                sheet = .incomingRequest(request)
            }
        case .challenge(let id):
            if phase == .ready {
                focusedChallengeID = id
                place = .together
            }
        case .invite(let token):
            pendingInvite = token
            if phase == .ready, !isPaired { sheet = .invite }
        case .minutes, .weeklyReport, .schedule:
            guard phase == .ready else { return }
            usDestination = link == .minutes ? .minutes : (link == .weeklyReport ? .week : .schedule)
            place = .us
            sheet = nil
        case .authCallback(let url):
            guard session == nil else { return }
            do {
                await signedIn(try await deps.backend.completeMagicLink(url: url))
            } catch let error as BackendError where error.code == .expired {
                // An old link: send a fresh one to the same address and say so (P29).
                if let email = lastMagicLinkEmail, (try? await deps.backend.sendMagicLink(email: email)) != nil {
                    notice = Friendly.signInMessage(for: error, resentTo: email)
                } else {
                    notice = Friendly.signInMessage(for: error)
                }
            } catch {
                notice = Friendly.signInMessage(for: error)
            }
        }
    }
}
