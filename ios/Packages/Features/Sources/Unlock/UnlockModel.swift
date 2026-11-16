import Backend
import Core
import FeatureSupport
import Foundation
import Observation
import QRCode

func L(_ key: String.LocalizationValue) -> String { String(localized: key, bundle: .module) }

/// The unlock sheet: choose a length, then one of four ways to unlock (feature spec §6).
@MainActor @Observable
public final class UnlockModel {
    public enum Method: String, CaseIterable, Sendable { case scan, ask, minutes, emergency }

    /// Why spending minutes is or is not possible right now.
    public enum MinutesAvailability: Equatable, Sendable {
        case available
        case notEnough(balance: Int)
        case overDailyMax(remainingToday: Int)
        case inDebt(Int)
    }

    /// The unlock that just started, for the success screen.
    public struct Started: Equatable, Sendable {
        public var method: UnlockMethod
        public var until: Date
    }

    public let app: AppModel
    public var length = UnlockRules.defaultLength
    public var reason = ""
    public var codeEntry = ""
    public private(set) var flow = UnlockRequestFlow.idle
    public private(set) var started: Started?
    public var message: String?
    private var lastSeenUpdate: OutgoingRequestUpdate?

    public init(app: AppModel) {
        self.app = app
        lastSeenUpdate = app.outgoingUpdate
    }

    // MARK: Length

    public var lengths: [Int] { UnlockRules.allowedLengths(isPremium: app.isPremium) }
    public var canStepLength: Bool { app.isPremium }

    public func stepLength(by steps: Int) {
        let next = length + steps * UnlockRules.step
        if UnlockRules.isValidLength(next, isPremium: app.isPremium) { length = next }
    }

    // MARK: Availability

    public var isPaired: Bool { app.isPaired }
    public var partnerName: String { app.partnerName ?? L("your partner") }

    public var minutesAvailability: MinutesAvailability {
        guard let minutes = app.myMinutes else { return .notEnough(balance: 0) }
        if minutes.debt > 0 { return .inDebt(minutes.debt) }
        if minutes.balance < length { return .notEnough(balance: max(0, minutes.balance)) }
        if minutes.spentToday + length > minutes.dailyMax { return .overDailyMax(remainingToday: minutes.remainingToday) }
        return .available
    }

    public var minutesNote: String {
        switch minutesAvailability {
        case .available:
            L("You have \(MinutesText.short(app.myMinutes?.balance ?? 0)).")
        case .notEnough(let balance):
            L("You have \(MinutesText.short(balance)). A challenge together earns more.")
        case .overDailyMax(let remaining):
            L("\(MinutesText.short(remaining)) left of the daily maximum you set.")
        case .inDebt(let debt):
            L("You borrowed \(MinutesText.short(debt)) for an emergency unlock. Earn them back first.")
        }
    }

    /// The weekly emergency allowance (P14).
    public var emergency: EmergencyAllowance { app.emergency }

    private var renewDay: String? {
        emergency.renewsAt.map { ScheduleText.weekday($0, timeZone: app.deps.timeZone()) }
    }

    /// "13 of your 15 emergency minutes left this week · renews Friday".
    public var emergencyLeftLine: String {
        if emergency.isUsedUp, let day = renewDay {
            return L("You've used this week's \(MinutesText.short(emergency.allowance)) emergency minutes. They renew on \(day).")
        }
        let left = L("\(MinutesText.short(emergency.remaining)) of your \(MinutesText.short(emergency.allowance)) emergency minutes left this week")
        if let day = renewDay { return L("\(left) · renews \(day)") }
        return left
    }

    public var emergencyNote: String {
        L("Only the time you use is borrowed, and you earn it back. End it whenever you like and the rest stays available. Your shared streak starts again.")
    }

    // MARK: Ask your partner

    public func askPartner() async {
        guard case .idle = flow else { return }
        do {
            let request = try await app.deps.backend.createUnlockRequest(minutes: length, reason: reason)
            flow = flow.reduce(.created(request))
            message = nil
            await app.deps.backend.logEvent("unlock_requested", props: ["minutes": String(length)])
        } catch {
            message = Friendly.message(for: error)
        }
    }

    /// Called every second while waiting, and whenever the app model reports news about the request.
    public func tick() {
        flow = flow.reduce(.tick(app.deps.now()))
        if let update = app.outgoingUpdate, update != lastSeenUpdate {
            lastSeenUpdate = update
            flow = flow.reduce(.updated(update.request, unlock: update.unlock))
        }
        if case .approved(let unlock) = flow, started == nil { noteStarted(unlock.method) }
    }

    public var waitingSecondsLeft: Int {
        guard case .waiting(let request) = flow else { return 0 }
        return max(0, Int(request.expiresAt.timeIntervalSince(app.deps.now()).rounded(.up)))
    }

    public var codeEntryAvailable: Bool { flow.codeEntryAvailable(now: app.deps.now()) }

    public var canRedeemCode: Bool { codeEntry.count == UnlockRules.accountabilityCodeLength && codeEntry.allSatisfy(\.isNumber) }

    public func redeemCode() async {
        guard case .waiting(let request) = flow, canRedeemCode else { return }
        do {
            let unlock = try await app.deps.backend.redeemAccountabilityCode(requestID: request.id, code: codeEntry)
            flow = flow.reduce(.codeRedeemed(unlock))
            await app.beginUnlock(unlock)
            noteStarted(.accountabilityCode)
        } catch let error as BackendError where error.code == .invalid {
            message = L("That code didn't match. Check it with \(partnerName).")
        } catch {
            message = Friendly.message(for: error)
        }
    }

    /// Words for how the request ended, in the app's voice (never "denied").
    public var outcomeLine: String? {
        switch flow {
        case .declined: L("\(partnerName) says let's wait — maybe later?")
        case .expired: L("No answer this time. You can try again or use your minutes.")
        default: nil
        }
    }

    public func askAgain() {
        flow = .idle
        codeEntry = ""
        message = nil
    }

    // MARK: Minutes and emergency

    public func useMinutes() async {
        do {
            let unlock = try await app.deps.backend.spendMinutesUnlock(minutes: length, clientEventID: UUID())
            await app.beginUnlock(unlock)
            noteStarted(.minutes)
        } catch {
            message = Friendly.message(for: error)
        }
    }

    public func useEmergency() async {
        do {
            let unlock = try await app.deps.backend.emergencyUnlock(clientEventID: UUID())
            await app.beginUnlock(unlock)
            noteStarted(.emergency)
        } catch {
            message = Friendly.message(for: error)
        }
    }

    // MARK: In-person QR

    /// Verifies the partner's rotating code on this phone, offline, and starts the unlock.
    public func handleScan(_ scanned: String) async {
        guard let secret = app.deps.qrSecrets.load() else {
            message = L("This phone needs to connect once to finish pairing before codes can be scanned.")
            return
        }
        let now = app.deps.now()
        switch QRUnlockVerifier(secret: secret, used: app.deps.usedCounters).redeem(scanned, at: now) {
        case .success(let counter):
            let event = QRUnlockEvent(counter: counter, minutes: length, startedAt: now)
            // Logged locally first; synced when online (feature spec §6.1).
            app.deps.pendingQRUnlocks.add(event)
            let unlock = Unlock(
                id: event.clientEventID, userID: app.myID ?? UUID(), method: .qr, minutes: length,
                startedAt: now, endsAt: now.addingTimeInterval(Double(length) * 60), clientEventID: event.clientEventID
            )
            await app.beginUnlock(unlock)
            noteStarted(.qr)
            await app.syncPendingQRUnlocks()
        case .failure(.alreadyUsed):
            message = L("That code was already used. It changes every 30 seconds — scan the next one.")
        case .failure(.outOfDate):
            message = L("That code has changed. Ask \(partnerName) to show the current one.")
        case .failure:
            message = L("That isn't \(partnerName)'s unlock code. Ask them to open “Show my code”.")
        }
    }

    private func noteStarted(_ method: UnlockMethod) {
        guard let active = app.deps.store.load().activeUnlock else { return }
        started = Started(method: method, until: active.endsAt)
        message = nil
    }

    public var startedLine: String? {
        guard let started else { return nil }
        return L("Unlocked until \(ScheduleText.clock(started.until, timeZone: app.deps.timeZone())).")
    }
}

/// "Show my code": the rotating QR the partner scans (feature spec §6.1).
@MainActor @Observable
public final class ShowCodeModel {
    public let app: AppModel

    public init(app: AppModel) { self.app = app }

    public var secret: QRSecret? { app.deps.qrSecrets.load() }

    public func payload(at date: Date) -> String? {
        secret.map { QRUnlockPayload(secret: $0, at: date).string }
    }

    public func progress(at date: Date) -> Double { TOTP.progress(at: date) }
    public func secondsRemaining(at date: Date) -> Int { Int(TOTP.secondsRemaining(at: date).rounded(.up)) }
}

/// Answering the partner's request: "Go for it" or "Let's wait".
@MainActor @Observable
public final class IncomingRequestModel {
    public let app: AppModel
    public let request: UnlockRequest
    public var message: String?
    public private(set) var answered = false

    public init(app: AppModel, request: UnlockRequest) {
        self.app = app
        self.request = request
    }

    public var partnerName: String { app.partnerName ?? L("Your partner") }

    /// "Ana asks for 30 min"
    public var title: String { L("\(partnerName) asks for \(MinutesText.short(request.minutes))") }

    public var isExpired: Bool { app.deps.now() >= request.expiresAt }

    public func respond(approve: Bool) async {
        do {
            try await app.deps.backend.respondUnlockRequest(id: request.id, approve: approve)
            answered = true
            await app.refreshRequests()
            if app.sheet == .incomingRequest(request) { app.sheet = nil }
        } catch let error as BackendError where error.code == .expired {
            message = L("This request has already ended.")
            await app.refreshRequests()
        } catch {
            message = Friendly.message(for: error)
        }
    }
}
