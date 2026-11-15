import Backend
import Blocking
import Core
import FeatureSupport
import Foundation
import Observation

func L(_ key: String.LocalizationValue) -> String { String(localized: key, bundle: .module) }

/// Protected time: the editor, paused apps and the approval flow (feature spec §4).
/// Stricter changes apply at once; looser ones wait for the partner for up to 24 hours.
@MainActor @Observable
public final class ScheduleModel {
    /// What saving a draft will do, shown before the person saves.
    public enum Effect: Equatable, Sendable { case nothing, appliesNow, needsPartner }

    public let app: AppModel
    public var message: String?
    /// A calm confirmation after saving ("Ana will be asked.").
    public var savedNote: String?

    public init(app: AppModel) { self.app = app }

    public func load() async {
        await app.refresh()
    }

    public var schedules: [ProtectedSchedule] { app.schedules }
    /// Extra schedules kept but not in effect without premium (hidden, not deleted).
    public func isResting(_ schedule: ProtectedSchedule) -> Bool { !app.effectiveSchedules.contains { $0.id == schedule.id } }
    public var canAdd: Bool { app.isPremium && app.schedules.count < PremiumRules.premiumScheduleLimit }
    public var partnerName: String { app.partnerName ?? L("your partner") }

    private func replacing(_ draft: ProtectedSchedule) -> [ProtectedSchedule] {
        var all = app.schedules
        if let index = all.firstIndex(where: { $0.id == draft.id }) { all[index] = draft } else { all.append(draft) }
        return all
    }

    /// Whether a draft would apply now or needs the partner. Unpaired: everything applies now.
    public func effect(of draft: ProtectedSchedule) -> Effect {
        guard draft != app.schedules.first(where: { $0.id == draft.id }) else { return .nothing }
        let change = ScheduleChange.classify(from: app.schedules, to: replacing(draft))
        return ScheduleChange.appliesImmediately(change, isPaired: app.isPaired) ? .appliesNow : .needsPartner
    }

    public func effectLine(_ effect: Effect) -> String? {
        switch effect {
        case .nothing: nil
        case .appliesNow: L("This applies right away.")
        case .needsPartner: L("This makes protected time shorter, so \(partnerName) will be asked. Until they answer, it stays as it is.")
        }
    }

    public func isValid(_ draft: ProtectedSchedule) -> Bool { !draft.weekdays.isEmpty && draft.name.count <= 40 }

    @discardableResult
    public func save(_ draft: ProtectedSchedule) async -> Bool {
        let isNew = !app.schedules.contains { $0.id == draft.id }
        do {
            let outcome = try await app.submitSchedule(scheduleID: isNew ? nil : draft.id, proposal: .schedule(draft))
            message = nil
            savedNote = outcome == .applied(app.schedules) ? L("Saved.") : L("\(partnerName) will be asked. You'll hear back within 24 hours.")
            return true
        } catch {
            message = Friendly.message(for: error)
            return false
        }
    }

    public func remove(_ schedule: ProtectedSchedule) async {
        do {
            let outcome = try await app.submitSchedule(scheduleID: schedule.id, proposal: .removeSchedule)
            if case .pending = outcome { savedNote = L("\(partnerName) will be asked. You'll hear back within 24 hours.") } else { savedNote = L("Saved.") }
        } catch {
            message = Friendly.message(for: error)
        }
    }

    // MARK: Paused apps

    public var selectionSummary: String {
        guard let selection = app.deps.blocking.currentSelection(), !selection.isEmpty else { return L("Nothing chosen yet") }
        var parts: [String] = []
        if selection.categoryCount == 1 { parts.append(L("1 category")) }
        if selection.categoryCount > 1 { parts.append(L("\(selection.categoryCount.formatted()) categories")) }
        if selection.applicationCount == 1 { parts.append(L("1 app")) }
        if selection.applicationCount > 1 { parts.append(L("\(selection.applicationCount.formatted()) apps")) }
        if selection.webDomainCount == 1 { parts.append(L("1 website")) }
        if selection.webDomainCount > 1 { parts.append(L("\(selection.webDomainCount.formatted()) websites")) }
        return parts.joined(separator: " · ")
    }

    public func selectionEffect(_ selection: PausedAppsSelection?) -> Effect {
        guard let selection, selection != app.deps.blocking.currentSelection() else { return .nothing }
        let change = app.deps.blocking.selectionChange(from: app.deps.blocking.currentSelection(), to: selection)
        return change == .looser && app.isPaired ? .needsPartner : .appliesNow
    }

    public func selectionEffectLine(_ effect: Effect) -> String? {
        switch effect {
        case .nothing: nil
        case .appliesNow: L("This applies right away.")
        // The partner is only told "fewer apps", never which ones.
        case .needsPartner: L("Pausing fewer apps is something you agree on together. \(partnerName) will be asked, without seeing which apps.")
        }
    }

    @discardableResult
    public func saveSelection(_ selection: PausedAppsSelection) async -> Bool {
        do {
            let outcome = try await app.saveSelection(selection)
            savedNote = outcome == .saved ? L("Saved.") : L("\(partnerName) will be asked. You'll hear back within 24 hours.")
            message = nil
            return true
        } catch {
            message = Friendly.message(for: error)
            return false
        }
    }

    // MARK: Approvals

    /// Changes the partner asked for, waiting for this person.
    public var toAnswer: [ScheduleChangeRequest] { app.scheduleRequests.filter { $0.requesterID != app.myID } }
    /// Changes this person asked for, waiting for the partner.
    public var waiting: [ScheduleChangeRequest] { app.scheduleRequests.filter { $0.requesterID == app.myID } }

    /// "Ana would like protected time to start at 7 PM" in the app's words.
    public func describe(_ request: ScheduleChangeRequest, locale: Locale = .current) -> String {
        let mine = request.requesterID == app.myID
        let who = mine ? L("You") : (app.partnerName ?? L("Your partner"))
        switch request.proposed {
        case .schedule(let schedule) where !schedule.enabled:
            return mine ? L("You asked to turn protected time off.") : L("\(who) would like to turn protected time off.")
        case .schedule(let schedule):
            let range = ScheduleText.range(schedule, locale: locale)
            let days = ScheduleText.days(schedule.weekdays, locale: locale).lowercased()
            return mine
                ? L("You asked for protected time to be \(range), \(days).")
                : L("\(who) would like protected time to be \(range), \(days).")
        case .removeSchedule:
            return mine ? L("You asked to remove one of your protected times.") : L("\(who) would like to remove one of their protected times.")
        case .fewerPausedApps:
            return mine ? L("You asked to pause fewer apps.") : L("\(who) would like to pause fewer apps.")
        }
    }

    public func respond(_ request: ScheduleChangeRequest, approve: Bool) async {
        do {
            try await app.deps.backend.respondScheduleChange(requestID: request.id, approve: approve)
            await app.refreshRequests()
            message = nil
        } catch {
            message = Friendly.message(for: error)
            await app.refreshRequests()
        }
    }
}
