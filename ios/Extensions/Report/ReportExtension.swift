import Core
@preconcurrency import DeviceActivity
import DesignSystem
import ExtensionKit
import SwiftUI

func L(_ key: String.LocalizationValue) -> String { String(localized: key) }

/// Shows the user's own usage of their paused apps this week, privately (feature spec §10).
/// The numbers are computed and drawn here, inside Apple's sandbox, and cannot leave it:
/// not to the app, not to our server, not to the partner (decision T4).
@main
struct ReportExtension: @preconcurrency DeviceActivityReportExtension {
    init() { Typography.registerFonts() }

    @MainActor var body: some DeviceActivityReportScene {
        PausedAppsReport { summary in
            PausedAppsReportView(summary: summary)
        }
    }
}

extension DeviceActivityReport.Context {
    /// Must match `DeviceActivityReport.Context.pausedApps` in the Blocking package.
    static let pausedApps = Self("pausedApps")
}

/// What the report shows: time per day and the week's total. Durations only, no app names.
struct UsageSummary: Sendable, Equatable {
    struct Day: Sendable, Equatable, Identifiable {
        var date: Date
        var duration: TimeInterval
        var id: Date { date }
    }

    var days: [Day] = []
    var total: TimeInterval { days.reduce(0) { $0 + $1.duration } }
    var longest: TimeInterval { days.map(\.duration).max() ?? 0 }
}

struct PausedAppsReport: @preconcurrency DeviceActivityReportScene {
    let context: DeviceActivityReport.Context = .pausedApps
    let content: (UsageSummary) -> PausedAppsReportView

    nonisolated func makeConfiguration(representing data: DeviceActivityResults<DeviceActivityData>) async -> UsageSummary {
        var byDay: [Date: TimeInterval] = [:]
        for await device in data {
            for await segment in device.activitySegments {
                byDay[segment.dateInterval.start, default: 0] += segment.totalActivityDuration
            }
        }
        return UsageSummary(days: byDay.keys.sorted().map { UsageSummary.Day(date: $0, duration: byDay[$0] ?? 0) })
    }
}

struct PausedAppsReportView: View {
    let summary: UsageSummary

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text(DurationText.short(summary.total))
                .textRole(.numeral)
                .foregroundStyle(Color.ink)
            Text(L("in your paused apps this week"))
                .textRole(.caption)
                .foregroundStyle(Color.inkMuted)
            HStack(alignment: .bottom, spacing: Spacing.xs) {
                ForEach(summary.days) { day in
                    VStack(spacing: Spacing.xxs) {
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(Color.hearth)
                            .frame(height: max(4, 56 * (summary.longest > 0 ? day.duration / summary.longest : 0)))
                        Text(day.date.formatted(.dateTime.weekday(.narrow)))
                            .textRole(.caption)
                            .foregroundStyle(Color.inkMuted)
                    }
                    .frame(maxWidth: .infinity)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(day.date.formatted(.dateTime.weekday(.wide))): \(DurationText.spoken(day.duration))")
                }
            }
            .frame(height: 80, alignment: .bottom)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
    }
}
