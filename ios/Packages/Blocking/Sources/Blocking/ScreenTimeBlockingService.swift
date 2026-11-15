import Core
@preconcurrency import DeviceActivity
@preconcurrency import FamilyControls
import Foundation
@preconcurrency import ManagedSettings
import SwiftUI

// The real Screen Time implementation (06 §4). It compiles for the Simulator but only works
// on a real iPhone with the Family Controls entitlement. Nothing here has been verified on a
// device yet; see the device checklist in ios/README.md.

public extension ManagedSettingsStore.Name {
    /// The one named store that holds the pause.
    static var protectedTime: Self { Self("protectedTime") }
}

/// Names of the Device Activity monitors the app registers.
public enum ActivityNames {
    static let protectedPrefix = "protected-"
    static let unlockPrefix = "unlock-"

    public static func protected(_ scheduleID: UUID, part: String) -> DeviceActivityName {
        DeviceActivityName("\(protectedPrefix)\(scheduleID.uuidString)-\(part)")
    }

    public static func unlock(_ id: UUID) -> DeviceActivityName {
        DeviceActivityName("\(unlockPrefix)\(id.uuidString)")
    }

    public static func isProtected(_ name: DeviceActivityName) -> Bool { name.rawValue.hasPrefix(protectedPrefix) }

    public static func unlockID(_ name: DeviceActivityName) -> UUID? {
        guard name.rawValue.hasPrefix(unlockPrefix) else { return nil }
        return UUID(uuidString: String(name.rawValue.dropFirst(unlockPrefix.count)))
    }
}

/// One Device Activity monitor to register for a schedule.
public struct MonitorPlan: Equatable, Sendable {
    public var part: String
    public var start: DateComponents
    public var end: DateComponents
}

public enum SchedulePlanner {
    /// Fallback for midnight-crossing schedules if a single interval does not fire correctly
    /// on some iOS version (04 §3.1): split into start–23:59 and 00:00–end. Off until a device says otherwise.
    public static let splitAtMidnight = false

    /// Calendar weekday (1 = Sunday) for an ISO weekday (1 = Monday).
    static func calendarWeekday(_ iso: Int) -> Int { iso % 7 + 1 }

    /// The monitors needed for one schedule. A schedule that runs every day needs one repeating
    /// interval; otherwise one per start weekday.
    public static func plans(for schedule: ProtectedSchedule, splitAtMidnight: Bool = SchedulePlanner.splitAtMidnight) -> [MonitorPlan] {
        guard schedule.enabled, !schedule.weekdays.isEmpty else { return [] }
        let everyDay = schedule.weekdays == Set(1...7)
        let days: [Int?] = everyDay ? [nil] : schedule.weekdays.sorted().map { $0 }
        var plans: [MonitorPlan] = []
        for day in days {
            let startDay = day.map(calendarWeekday)
            let endDay = day.map { calendarWeekday(schedule.crossesMidnight ? $0 % 7 + 1 : $0) }
            let label = day.map(String.init) ?? "all"
            let start = DateComponents(hour: schedule.startLocal.hour, minute: schedule.startLocal.minute, weekday: startDay)
            let end = DateComponents(hour: schedule.endLocal.hour, minute: schedule.endLocal.minute, weekday: endDay)
            if schedule.crossesMidnight, splitAtMidnight, schedule.endLocal.minutesFromMidnight > 0 {
                plans.append(MonitorPlan(part: "\(label)-a", start: start, end: DateComponents(hour: 23, minute: 59, weekday: startDay)))
                plans.append(MonitorPlan(part: "\(label)-b", start: DateComponents(hour: 0, minute: 0, weekday: endDay), end: end))
            } else {
                plans.append(MonitorPlan(part: label, start: start, end: end))
            }
        }
        return plans
    }
}

/// Where the pause is actually put up or taken down. On a phone this is the named
/// ManagedSettings store; tests record the calls instead.
public protocol ShieldTarget: Sendable {
    func apply(_ selection: FamilyActivitySelection)
    func clear()
}

public struct ManagedSettingsShieldTarget: ShieldTarget {
    public init() {}

    public func apply(_ selection: FamilyActivitySelection) {
        let settings = ManagedSettingsStore(named: .protectedTime)
        settings.shield.applications = selection.applicationTokens.isEmpty ? nil : selection.applicationTokens
        settings.shield.applicationCategories = selection.categoryTokens.isEmpty ? nil : .specific(selection.categoryTokens)
        settings.shield.webDomains = selection.webDomainTokens.isEmpty ? nil : selection.webDomainTokens
        settings.shield.webDomainCategories = selection.categoryTokens.isEmpty ? nil : .specific(selection.categoryTokens)
        // The app cannot be deleted mid-session (feature spec §4).
        settings.application.denyAppRemoval = true
    }

    public func clear() {
        ManagedSettingsStore(named: .protectedTime).clearAllSettings()
    }
}

/// Applies and clears the pause. Used by the app and by the Monitor extension, which is the
/// only code running when a schedule or unlock window starts or ends.
public struct ShieldController: Sendable {
    public let store: any SharedStateStore
    public let target: any ShieldTarget
    /// Device Activity callbacks can arrive a little early or late; look slightly ahead when deciding.
    public static let callbackTolerance: TimeInterval = 90

    public init(store: any SharedStateStore, target: any ShieldTarget = ManagedSettingsShieldTarget()) {
        self.store = store
        self.target = target
    }

    static func familySelection(from data: Data?) -> FamilyActivitySelection? {
        guard let data, let wrapper = try? JSONDecoder().decode(PausedAppsSelection.self, from: data) else { return nil }
        return try? PropertyListDecoder().decode(FamilyActivitySelection.self, from: wrapper.data)
    }

    public func applyShields() {
        guard let selection = Self.familySelection(from: store.loadSelectionData()) else { return }
        target.apply(selection)
    }

    public func clearShields() {
        target.clear()
    }

    /// Whether the pause should be up at `date`: inside protected time and not inside an unlock.
    public static func shouldShield(state: SharedState, at date: Date, timeZone: TimeZone = .current) -> Bool {
        guard state.protectionConfigured else { return false }
        if case .protected = state.phase(at: date, timeZone: timeZone) { return true }
        return false
    }

    /// Brings the shields in line with the schedule and any unlock, dropping a finished unlock.
    public func reconcile(at date: Date = Date(), timeZone: TimeZone = .current) {
        let state = store.update { state in
            if let unlock = state.activeUnlock, !unlock.isActive(at: date) { state.activeUnlock = nil }
        }
        if Self.shouldShield(state: state, at: date, timeZone: timeZone) { applyShields() } else { clearShields() }
    }

    /// Monitor extension entry points.
    public func intervalDidStart(_ activity: DeviceActivityName, now: Date = Date()) {
        // A protected interval starting, or an unlock window starting: either way re-evaluate.
        reconcile(at: ActivityNames.isProtected(activity) ? now.addingTimeInterval(Self.callbackTolerance) : now)
    }

    public func intervalDidEnd(_ activity: DeviceActivityName, now: Date = Date()) {
        if let id = ActivityNames.unlockID(activity) {
            // Ignore the end of an unlock that was since extended under a new id.
            let state = store.load()
            if let current = state.activeUnlock, current.id != id, current.isActive(at: now.addingTimeInterval(Self.callbackTolerance)) { return }
            store.update { $0.activeUnlock = nil }
        }
        reconcile(at: now.addingTimeInterval(Self.callbackTolerance))
    }
}

public final class ScreenTimeBlockingService: BlockingService, @unchecked Sendable {
    public let kind = BlockingKind.screenTime
    private let store: any SharedStateStore
    private let now: NowProvider
    private let target: any ShieldTarget
    private var controller: ShieldController { ShieldController(store: store, target: target) }

    public init(store: any SharedStateStore, target: any ShieldTarget = ManagedSettingsShieldTarget(), now: @escaping NowProvider = { Date() }) {
        self.store = store
        self.target = target
        self.now = now
    }

    public var authorizationStatus: BlockingAuthorization {
        switch AuthorizationCenter.shared.authorizationStatus {
        case .approved: .approved
        case .denied: .denied
        default: .notDetermined
        }
    }

    public func requestAuthorization() async throws {
        do {
            try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
        } catch {
            throw BlockingError.authorizationDenied
        }
        guard authorizationStatus == .approved else { throw BlockingError.authorizationDenied }
        refreshConfigured()
    }

    private func refreshConfigured() {
        let configured = authorizationStatus == .approved && !(currentSelection()?.isEmpty ?? true)
        store.update { $0.protectionConfigured = configured }
    }

    public func saveSelection(_ selection: PausedAppsSelection) throws {
        guard authorizationStatus == .approved else { throw BlockingError.notAuthorized }
        store.saveSelectionData(try? JSONEncoder().encode(selection))
        refreshConfigured()
        controller.reconcile(at: now())
    }

    public func currentSelection() -> PausedAppsSelection? {
        store.loadSelectionData().flatMap { try? JSONDecoder().decode(PausedAppsSelection.self, from: $0) }
    }

    public func applySchedule(_ schedules: [ProtectedSchedule]) throws {
        let center = DeviceActivityCenter()
        center.stopMonitoring(center.activities.filter(ActivityNames.isProtected))
        store.update { $0.schedules = schedules }
        refreshConfigured()
        do {
            for schedule in schedules {
                for plan in SchedulePlanner.plans(for: schedule) {
                    try center.startMonitoring(
                        ActivityNames.protected(schedule.id, part: plan.part),
                        during: DeviceActivitySchedule(intervalStart: plan.start, intervalEnd: plan.end, repeats: true)
                    )
                }
            }
        } catch {
            throw BlockingError.system(String(describing: error))
        }
        // Monitors only fire at the next boundary; bring the shields in line right now.
        controller.reconcile(at: now())
    }

    public func startUnlock(id: UUID, minutes: Int) throws {
        guard minutes >= UnlockRules.minimumLength else { throw BlockingError.unlockTooShort }
        let date = now()
        let center = DeviceActivityCenter()
        let unlock = store.update {
            $0.activeUnlock = ActiveUnlock.starting(id: id, minutes: minutes, now: date, current: $0.activeUnlock)
        }.activeUnlock
        guard let unlock else { return }
        controller.clearShields()
        center.stopMonitoring(center.activities.filter { ActivityNames.unlockID($0) != nil })
        let calendar = Calendar.current
        let parts: Set<Calendar.Component> = [.year, .month, .day, .hour, .minute, .second]
        do {
            try center.startMonitoring(
                ActivityNames.unlock(id),
                during: DeviceActivitySchedule(
                    intervalStart: calendar.dateComponents(parts, from: date),
                    intervalEnd: calendar.dateComponents(parts, from: unlock.endsAt),
                    repeats: false
                )
            )
        } catch {
            // Without the monitor nothing would bring the pause back: undo the unlock.
            store.update { $0.activeUnlock = nil }
            controller.reconcile(at: date)
            throw BlockingError.system(String(describing: error))
        }
    }

    public func endUnlockEarly(id: UUID) throws {
        DeviceActivityCenter().stopMonitoring([ActivityNames.unlock(id)])
        store.update { if $0.activeUnlock?.id == id { $0.activeUnlock = nil } }
        controller.reconcile(at: now())
    }

    public func isProtectedNow() -> Bool {
        ShieldController.shouldShield(state: store.load(), at: now())
    }

    public func selectionChange(from old: PausedAppsSelection?, to new: PausedAppsSelection) -> ScheduleChange {
        func decode(_ selection: PausedAppsSelection?) -> FamilyActivitySelection {
            selection.flatMap { try? PropertyListDecoder().decode(FamilyActivitySelection.self, from: $0.data) } ?? FamilyActivitySelection()
        }
        let before = decode(old), after = decode(new)
        let changes = [
            tokenSetChange(from: before.applicationTokens, to: after.applicationTokens),
            tokenSetChange(from: before.categoryTokens, to: after.categoryTokens),
            tokenSetChange(from: before.webDomainTokens, to: after.webDomainTokens),
        ]
        if changes.contains(.looser) { return .looser }
        return changes.contains(.stricter) ? .stricter : .same
    }

    static func wrap(_ selection: FamilyActivitySelection) -> PausedAppsSelection {
        PausedAppsSelection(
            data: (try? PropertyListEncoder().encode(selection)) ?? Data(),
            applicationCount: selection.applicationTokens.count,
            categoryCount: selection.categoryTokens.count,
            webDomainCount: selection.webDomainTokens.count
        )
    }
}

/// Apple's picker. The app receives opaque tokens only and cannot pre-select apps (decision T5).
struct ScreenTimePausedAppsPicker: View {
    @Binding var selection: PausedAppsSelection?
    @State private var family = FamilyActivitySelection()
    @State private var loaded = false

    var body: some View {
        FamilyActivityPicker(selection: $family)
            .onAppear {
                guard !loaded else { return }
                loaded = true
                if let data = selection?.data, let existing = try? PropertyListDecoder().decode(FamilyActivitySelection.self, from: data) {
                    family = existing
                }
            }
            .onChange(of: family) { _, value in
                selection = ScreenTimeBlockingService.wrap(value)
            }
    }
}

/// Picks the implementation for this build (06 §3, WP-11): Screen Time on a real device unless
/// the build configuration or a launch argument asks for the mock; always the mock in the Simulator.
public enum BlockingServiceFactory {
    /// `BlockingServiceKind` in Info.plist comes from `BLOCKING_SERVICE` in the xcconfig files.
    public static func configuredKind(info: [String: Any]? = Bundle.main.infoDictionary, arguments: [String] = ProcessInfo.processInfo.arguments) -> BlockingKind {
        #if targetEnvironment(simulator)
        return .mock
        #else
        if let index = arguments.firstIndex(of: "-blockingService"), arguments.indices.contains(index + 1),
           let kind = BlockingKind(rawValue: arguments[index + 1]) {
            return kind
        }
        return resolve(setting: info?["BlockingServiceKind"] as? String)
        #endif
    }

    static func resolve(setting: String?) -> BlockingKind {
        setting?.lowercased() == "mock" ? .mock : .screenTime
    }

    public static func make(kind: BlockingKind = configuredKind(), store: any SharedStateStore) -> any BlockingService {
        switch kind {
        case .mock: MockBlockingService(store: store)
        case .screenTime: ScreenTimeBlockingService(store: store)
        }
    }
}
