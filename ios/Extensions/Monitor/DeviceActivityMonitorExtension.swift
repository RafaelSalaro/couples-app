import Blocking
import Core
import DeviceActivity

/// Applies and removes the pause when a protected-time schedule or an unlock window starts
/// or ends. This is the only code that runs at those moments, even when the app is closed
/// (04 §3.1, §3.2). All decisions live in `ShieldController` so they are unit tested.
final class DeviceActivityMonitorExtension: DeviceActivityMonitor {
    private var controller: ShieldController { ShieldController(store: AppGroupStateStore()) }

    override func intervalDidStart(for activity: DeviceActivityName) {
        super.intervalDidStart(for: activity)
        controller.intervalDidStart(activity)
    }

    override func intervalDidEnd(for activity: DeviceActivityName) {
        super.intervalDidEnd(for: activity)
        controller.intervalDidEnd(activity)
    }
}
