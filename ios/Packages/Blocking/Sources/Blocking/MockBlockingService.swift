import Core
import DesignSystem
import Foundation
import SwiftUI

/// Simulates Screen Time in the App Group state so every flow can run in the Simulator
/// and in UI tests. Nothing is really paused; `isProtectedNow()` and the simulated pause
/// screen (`MockShieldView`) show what Screen Time would do.
public final class MockBlockingService: BlockingService, @unchecked Sendable {
    public let kind = BlockingKind.mock
    private let store: any SharedStateStore
    private let now: NowProvider
    private let timeZone: @Sendable () -> TimeZone
    private let lock = NSLock()
    private var status: BlockingAuthorization
    private var outcome: BlockingAuthorization = .approved

    /// The things the simulated picker offers. Identifiers stand in for Screen Time tokens.
    public struct Item: Identifiable, Hashable, Sendable {
        public enum Group: Sendable { case category, app, website }
        public var id: String
        public var name: String
        public var group: Group
    }

    public static let catalog: [Item] = [
        Item(id: "category.social", name: "Social", group: .category),
        Item(id: "category.games", name: "Games", group: .category),
        Item(id: "category.entertainment", name: "Entertainment", group: .category),
        Item(id: "app.news", name: "News app", group: .app),
        Item(id: "app.shopping", name: "Shopping app", group: .app),
        Item(id: "web.social", name: "Social websites", group: .website),
    ]

    /// What onboarding guides people to pick: the Social category and its websites.
    public static let suggested: Set<String> = ["category.social", "web.social"]

    public init(
        store: any SharedStateStore, authorization: BlockingAuthorization = .notDetermined,
        now: @escaping NowProvider = { Date() }, timeZone: @escaping @Sendable () -> TimeZone = { .current }
    ) {
        self.store = store
        self.now = now
        self.timeZone = timeZone
        status = authorization
        refresh()
    }

    /// What the next `requestAuthorization()` answers (tests can simulate "Don't Allow").
    public func setAuthorizationOutcome(_ outcome: BlockingAuthorization) { lock.withLock { self.outcome = outcome } }

    /// Simulates the user turning Screen Time access off in iOS Settings.
    public func revokeAuthorization() {
        lock.withLock { status = .denied }
        refresh()
    }

    public var authorizationStatus: BlockingAuthorization { lock.withLock { status } }

    public func requestAuthorization() async throws {
        let result = lock.withLock {
            status = outcome
            return status
        }
        refresh()
        if result != .approved { throw BlockingError.authorizationDenied }
    }

    public static func selection(ids: Set<String>) -> PausedAppsSelection {
        let items = catalog.filter { ids.contains($0.id) }
        return PausedAppsSelection(
            data: (try? JSONEncoder().encode(ids.sorted())) ?? Data(),
            applicationCount: items.filter { $0.group == .app }.count,
            categoryCount: items.filter { $0.group == .category }.count,
            webDomainCount: items.filter { $0.group == .website }.count
        )
    }

    public static func ids(of selection: PausedAppsSelection?) -> Set<String> {
        guard let selection else { return [] }
        return Set((try? JSONDecoder().decode([String].self, from: selection.data)) ?? [])
    }

    public func saveSelection(_ selection: PausedAppsSelection) throws {
        guard authorizationStatus == .approved else { throw BlockingError.notAuthorized }
        store.saveSelectionData(try? JSONEncoder().encode(selection))
        refresh()
    }

    public func currentSelection() -> PausedAppsSelection? {
        store.loadSelectionData().flatMap { try? JSONDecoder().decode(PausedAppsSelection.self, from: $0) }
    }

    public func applySchedule(_ schedules: [ProtectedSchedule]) throws {
        store.update { $0.schedules = schedules }
        refresh()
    }

    public func startUnlock(id: UUID, minutes: Int) throws {
        // The simulated pause has no Device Activity minimum, so an emergency remainder under
        // 15 minutes (P14) works here. On a device ScreenTimeBlockingService still needs 15
        // (decision T6); see docs/13-risks-and-open-questions.md, founder decision pending.
        guard minutes >= 1 else { throw BlockingError.unlockTooShort }
        let date = now()
        store.update { $0.activeUnlock = ActiveUnlock.starting(id: id, minutes: minutes, now: date, current: $0.activeUnlock) }
        refresh()
    }

    public func endUnlockEarly(id: UUID) throws {
        store.update { if $0.activeUnlock?.id == id { $0.activeUnlock = nil } }
        refresh()
    }

    public func isProtectedNow() -> Bool {
        refresh()
        return store.load().mockShieldApplied
    }

    public func selectionChange(from old: PausedAppsSelection?, to new: PausedAppsSelection) -> ScheduleChange {
        tokenSetChange(from: Self.ids(of: old), to: Self.ids(of: new))
    }

    /// Recomputes whether the simulated shield is up, as the Monitor extension would.
    private func refresh() {
        let date = now()
        let configured = authorizationStatus == .approved && !(currentSelection()?.isEmpty ?? true)
        let zone = timeZone()
        store.update { state in
            state.protectionConfigured = configured
            if let unlock = state.activeUnlock, !unlock.isActive(at: date) { state.activeUnlock = nil }
            if case .protected = state.phase(at: date, timeZone: zone) {
                state.mockShieldApplied = configured
            } else {
                state.mockShieldApplied = false
            }
        }
    }
}

/// The simulated pause screen: what Apple would draw over a paused app, built from the same
/// `ShieldContent` the real Shield Configuration extension uses.
public struct MockShieldView: View {
    let content: ShieldContent
    let onPrimary: () -> Void
    let onSecondary: () -> Void

    public init(content: ShieldContent, onPrimary: @escaping () -> Void, onSecondary: @escaping () -> Void) {
        self.content = content
        self.onPrimary = onPrimary
        self.onSecondary = onSecondary
    }

    public var body: some View {
        VStack(spacing: Spacing.lg) {
            Spacer()
            TwoCirclesMark(diameter: 44)
            Text(content.title)
                .textRole(.title)
                .foregroundStyle(Color.onDusk)
                .accessibilityAddTraits(.isHeader)
            Text(content.subtitle)
                .textRole(.body)
                .foregroundStyle(Color.onDusk.opacity(0.85))
                .multilineTextAlignment(.center)
            Spacer()
            Button(content.primaryButton, action: onPrimary)
                .buttonStyle(.dsGlow)
                .accessibilityIdentifier("shield.primary")
            Button(content.secondaryButton, action: onSecondary)
                .buttonStyle(.ds(.quiet))
                .tint(Color.onDusk)
                .accessibilityIdentifier("shield.secondary")
            Text(L("Simulated pause screen"))
                .textRole(.caption)
                .foregroundStyle(Color.onDusk.opacity(0.6))
        }
        .padding(Spacing.lg)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.dusk.ignoresSafeArea())
    }
}
