import DeviceActivity

/// Applies and removes the pause when a schedule or unlock window starts or ends.
/// Real behavior arrives with the Blocking work package (WP-7).
final class DeviceActivityMonitorExtension: DeviceActivityMonitor {
    override func intervalDidStart(for activity: DeviceActivityName) {
        super.intervalDidStart(for: activity)
    }

    override func intervalDidEnd(for activity: DeviceActivityName) {
        super.intervalDidEnd(for: activity)
    }
}
