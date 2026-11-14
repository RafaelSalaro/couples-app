import Backend
import Blocking
import Core
import DesignSystem
import FeatureSupport
import HomeFeature
import OnboardingFeature
import PairingFeature
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
            if phase == .active { Task { await app.becameActive() } }
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
            PlaceItem(id: .us, title: L("Us"), systemImage: "person.2"),
        ]
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            Group {
                switch app.place {
                case .tonight, .together:
                    HomeView(app: app)
                case .us:
                    NavigationStack { SettingsView(app: app) }
                }
            }
            .transition(.opacity)
            PlaceBar(places: places, selection: $app.place)
                .padding(.bottom, Spacing.xs)
        }
        .motion(Motion.standard, value: app.place)
        .sheet(item: $app.sheet) { sheet in
            sheetView(sheet)
        }
        .overlay {
            // Celebrations cover the scene (not a modal, so they never collide with a sheet).
            if case .paired(let name) = app.celebration, app.sheet == nil {
                PairedCelebrationView(myName: app.myName, partnerName: name) { app.celebration = nil }
                    .transition(.opacity)
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
        default:
            Text(verbatim: "")
        }
    }
}
