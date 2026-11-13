@preconcurrency import DeviceActivity
import ExtensionKit
import SwiftUI

/// Shows the user's own usage of paused apps, privately. Its data never leaves
/// the extension. Real content arrives with WP-10.
@main
struct ReportExtension: @preconcurrency DeviceActivityReportExtension {
    @MainActor var body: some DeviceActivityReportScene {
        PausedAppsReport { summary in
            Text(summary)
        }
    }
}

extension DeviceActivityReport.Context {
    static let pausedApps = Self("pausedApps")
}

struct PausedAppsReport: @preconcurrency DeviceActivityReportScene {
    let context: DeviceActivityReport.Context = .pausedApps
    let content: (String) -> Text
    nonisolated func makeConfiguration(
        representing data: DeviceActivityResults<DeviceActivityData>
    ) async -> String {
        ""
    }
}
