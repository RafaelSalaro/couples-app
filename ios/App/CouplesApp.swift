import Backend
import Blocking
import ChallengesFeature
import Core
import DesignSystem
import FeatureSupport
import HomeFeature
import KudosFeature
import MinutesFeature
import OnboardingFeature
import PairingFeature
import ReportsFeature
import ScheduleFeature
import SettingsFeature
import UnlockFeature
import SwiftUI

@main
struct CouplesApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var model: AppModel

    init() {
        Typography.registerFonts()
        let model = Composition.make()
        _model = State(initialValue: model)
        AppDelegate.model = model
        let notifications = NotificationCoordinator(model: model)
        notifications.start()
        AppDelegate.notifications = notifications
    }

    var body: some Scene {
        WindowGroup {
            RootView(app: model)
        }
    }
}

/// Receives the push token and forwards it to the backend.
final class AppDelegate: NSObject, UIApplicationDelegate {
    @MainActor static var model: AppModel?
    @MainActor static var notifications: NotificationCoordinator?

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        #if DEBUG
        let sandbox = true
        #else
        let sandbox = false
        #endif
        Task { @MainActor in
            try? await AppDelegate.model?.deps.backend.registerPushToken(token, sandbox: sandbox)
        }
    }
}

struct RootView: View {
    @Bindable var app: AppModel
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            switch app.phase {
            case .launching:
                TwoLights(closeness: 0.6, diameter: 64)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .onSky(.daylight)
                    .accessibilityLabel(AppBrand.displayName)
            case .onboarding:
                OnboardingFlow(app: app)
            case .ready:
                MainTabs(app: app)
            }
        }
        .tint(Color.hearth)
        .noticeOverlay($app.notice)
        .task { await app.bootstrap() }
        .onOpenURL { url in Task { await app.open(url) } }
        .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
            if let url = activity.webpageURL { Task { await app.open(url) } }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task {
                    await app.becameActive()
                    await LiveUnlockActivity().endExpired()
                }
            }
        }
    }
}

/// The app's shell: one place at a time, with the floating place bar (no tab-bar template).
/// Tonight is the home scene; "us" holds minutes, the week, protected time and settings.
struct MainTabs: View {
    @Bindable var app: AppModel

    private var places: [PlaceItem<AppPlace>] {
        [
            PlaceItem(id: .tonight, title: L("Tonight"), systemImage: "moon.stars"),
            PlaceItem(id: .together, title: L("Together"), systemImage: "sparkles"),
            PlaceItem(id: .us, title: L("Us"), systemImage: "person.2"),
        ]
    }

    var body: some View {
        Group {
                switch app.place {
                case .tonight:
                    HomeView(app: app)
                case .together:
                    ChallengesView(app: app)
                case .us:
                    UsView(app: app) { destination in
                        switch destination {
                        case .week: ReportsView(app: app)
                        case .schedule: ScheduleView(app: app)
                        default: SettingsScreen(app: app)
                        }
                    }
                }
            }
        .transition(.opacity)
        // An inset, not a ZStack layer: a pushed NavigationStack screen is UIKit-backed and would
        // otherwise sit above the bar and swallow its taps. Skies ignore the safe area, so they
        // still run behind the floating pill.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            PlaceBar(places: places, selection: $app.place)
                .padding(.bottom, Spacing.xs)
        }
        .motion(Motion.standard, value: app.place)
        .sheet(item: $app.sheet) { sheet in
            sheetView(sheet)
        }
        .overlay {
            // Celebrations cover the scene (not a modal, so they never collide with a sheet).
            if app.sheet == nil {
                switch app.celebration {
                case .paired(let name):
                    PairedCelebrationView(myName: app.myName, partnerName: name) { app.celebration = nil }
                        .transition(.opacity)
                case .kudos(let kudos):
                    KudosCelebrationView(kudos: kudos, partnerName: app.partnerName ?? "") { app.celebration = nil }
                        .transition(.opacity)
                case .streak(let days):
                    StreakCelebrationView(days: days) { app.celebration = nil }
                        .transition(.opacity)
                case nil:
                    EmptyView()
                }
            }
        }
        .motion(Motion.gentle, value: app.celebration)
    }

    @ViewBuilder
    private func sheetView(_ sheet: AppSheet) -> some View {
        switch sheet {
        case .invite:
            InviteSheet(app: app)
        case .mockShield:
            MockShieldView(
                content: ShieldContent.make(state: app.deps.store.load(), now: app.deps.now(), timeZone: app.deps.timeZone()),
                // On a real phone this button posts a notification whose tap opens the unlock sheet.
                onPrimary: { app.sheet = .unlock },
                onSecondary: { app.sheet = nil }
            )
        case .unlock:
            UnlockSheet(app: app)
        case .showMyCode:
            ShowMyCodeView(app: app)
        case .incomingRequest(let request):
            IncomingRequestView(app: app, request: request)
        case .giveKudos(let challengeID):
            GiveKudosSheet(app: app, challengeID: challengeID)
        case .paywall:
            PaywallView(app: app)
        }
    }
}
