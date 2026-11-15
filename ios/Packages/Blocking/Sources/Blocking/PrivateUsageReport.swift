import Core
@preconcurrency import DeviceActivity
import DesignSystem
@preconcurrency import FamilyControls
import SwiftUI

public extension DeviceActivityReport.Context {
    /// The private report drawn by the Device Activity Report extension.
    static var pausedApps: Self { Self("pausedApps") }
}

/// The user's own Screen Time usage of their paused apps this week, shown through Apple's
/// report extension. The numbers are computed and drawn inside that extension's sandbox and
/// cannot leave it: not to our server, not to the partner, not even to this app (decision T4).
public struct PrivateUsageReport: View {
    let service: any BlockingService

    public init(service: any BlockingService) { self.service = service }

    public var body: some View {
        Card(tone: .sunken) {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Label(L("Your paused apps this week"), systemImage: "lock.shield")
                    .textRole(.heading)
                    .foregroundStyle(Color.ink)
                switch service.kind {
                case .screenTime:
                    if let filter = Self.filter(selection: service.currentSelection()) {
                        DeviceActivityReport(.pausedApps, filter: filter)
                            .frame(minHeight: 120)
                    } else {
                        Text(L("Choose apps to pause and your own usage will show here."))
                            .textRole(.callout)
                            .foregroundStyle(Color.inkMuted)
                    }
                case .mock:
                    Text(L("On your iPhone this shows your own time in your paused apps, from Apple's Screen Time."))
                        .textRole(.callout)
                        .foregroundStyle(Color.inkMuted)
                }
                Text(L("Private: this never leaves your phone and your partner never sees it."))
                    .textRole(.caption)
                    .foregroundStyle(Color.inkMuted)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("report.private")
    }

    /// This week, this iPhone, only the apps, categories and websites the user paused.
    static func filter(selection: PausedAppsSelection?, now: Date = Date(), calendar: Calendar = .current) -> DeviceActivityFilter? {
        guard let selection, !selection.isEmpty,
              let family = try? PropertyListDecoder().decode(FamilyActivitySelection.self, from: selection.data),
              let week = calendar.dateInterval(of: .weekOfYear, for: now) else { return nil }
        return DeviceActivityFilter(
            segment: .daily(during: week),
            users: .all,
            devices: .init([.iPhone]),
            applications: family.applicationTokens,
            categories: family.categoryTokens,
            webDomains: family.webDomainTokens
        )
    }
}
