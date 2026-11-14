import Blocking
import Core
import DesignSystem
import FeatureSupport
import PairingFeature
import SwiftUI

/// The onboarding flow, one screen per step of feature spec §2.
public struct OnboardingFlow: View {
    @State private var model: OnboardingModel
    @Environment(\.colorScheme) private var scheme

    public init(app: AppModel) { _model = State(initialValue: OnboardingModel(app: app)) }

    public var body: some View {
        VStack(spacing: 0) {
            header
            Group {
                switch model.step {
                case .welcome: WelcomeStep(model: model)
                case .signIn: SignInStep(model: model)
                case .relationship: RelationshipStep(model: model)
                case .invite: InviteStep(model: model)
                case .notifications: NotificationsStep(model: model)
                case .screenTime: ScreenTimeStep(model: model)
                case .chooseApps: ChooseAppsStep(model: model)
                case .protectedTime: ProtectedTimeStep(model: model)
                case .minutes: MinutesStep(model: model)
                case .ready: ReadyStep(model: model)
                }
            }
            .id(model.step)
            .moveOrFade(from: .trailing)
        }
        .onSky(sky)
        .motion(value: model.step)
        .onChange(of: model.app.session) { _, _ in model.sessionChanged() }
    }

    /// Onboarding is one evening: it starts in daylight and ends at dusk, when protected time is ready.
    private var sky: SkyMoment {
        switch model.step {
        case .welcome, .signIn, .relationship: .daylight
        case .invite, .notifications, .screenTime, .chooseApps: .goldenHour
        case .protectedTime, .minutes, .ready: .dusk
        }
    }

    @ViewBuilder private var header: some View {
        if model.step != .welcome {
            HStack(spacing: Spacing.sm) {
                Button {
                    model.back()
                } label: {
                    Image(systemName: "chevron.left")
                        .frame(width: Sizing.minTouchTarget, height: Sizing.minTouchTarget)
                }
                .foregroundStyle(SkyInk(moment: sky, scheme: scheme).primary)
                .opacity(model.canGoBack ? 1 : 0)
                .disabled(!model.canGoBack)
                .accessibilityLabel(L("Back"))
                .accessibilityIdentifier("onboarding.back")
                Spacer()
                // Progress is the two lights drawing closer with every step.
                TwoLights(closeness: model.progress, diameter: 22, overlap: 0.5, glow: model.progress)
                    .frame(width: 60, height: 22)
                    .accessibilityElement()
                    .accessibilityLabel(L("Setup progress"))
                    .accessibilityValue(model.progress.formatted(.percent.precision(.fractionLength(0))))
                Spacer()
                Spacer().frame(width: Sizing.minTouchTarget)
            }
            .padding(.horizontal, Spacing.sm)
        }
    }
}

private struct MessageNote: View {
    let message: String?
    var body: some View {
        if let message {
            NoteBanner(message, tone: .neutral).accessibilityIdentifier("onboarding.message")
        }
    }
}

struct WelcomeStep: View {
    let model: OnboardingModel
    @State private var together = false

    var body: some View {
        VStack(spacing: Spacing.lg) {
            Spacer()
            TwoLights(closeness: together ? 0.75 : 0, diameter: 110, glow: together ? 0.8 : 0.2)
                .accessibilityHidden(true)
            SkyText(model.app.deps.brand.displayName, role: .label, muted: true)
            SkyText(L("Not about control. About being here, together."), role: .hero)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.6)
                .accessibilityAddTraits(.isHeader)
            SkyText(L("Pause the apps that pull you away, on a schedule you share. Unlock time together, never alone against the clock."), role: .body, muted: true)
                .multilineTextAlignment(.center)
            Spacer()
            Button(L("Get started")) { model.advance() }
                .buttonStyle(.dsPrimary)
                .accessibilityIdentifier("onboarding.start")
        }
        .padding(Spacing.lg)
        .task {
            try? await Task.sleep(for: .milliseconds(300))
            together = true
        }
    }
}

struct SignInStep: View {
    @Bindable var model: OnboardingModel
    @FocusState private var emailFocused: Bool

    var body: some View {
        StepScaffold(title: L("Sign in"), subtitle: L("No passwords. Use your Apple ID, or we'll email you a link.")) {
            if let sent = model.magicLinkSentTo {
                Card(tone: .sage) {
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text(L("Check your email")).textRole(.heading).foregroundStyle(Color.sage)
                        Text(L("We sent a sign-in link to \(sent). Open it on this phone."))
                            .textRole(.callout)
                            .foregroundStyle(Color.ink)
                    }
                }
                .accessibilityIdentifier("signin.sent")
                if model.demoLink != nil {
                    AsyncButton(L("Open the link (demo)"), kind: .secondary) { await model.openDemoLink() }
                        .accessibilityIdentifier("signin.demoLink")
                }
                Button(L("Use a different email")) { model.useDifferentEmail() }
                    .buttonStyle(.dsQuiet)
            } else {
                AsyncButton(kind: .secondary) {
                    await model.signInWithApple()
                } label: {
                    Label(L("Sign in with Apple"), systemImage: "apple.logo")
                }
                .accessibilityIdentifier("signin.apple")
                HStack {
                    Rectangle().fill(Color.line).frame(height: 1)
                    SkyText(L("or"), role: .caption, muted: true)
                    Rectangle().fill(Color.line).frame(height: 1)
                }
                .accessibilityHidden(true)
                TextField(L("Email address"), text: $model.email)
                    .keyboardType(.emailAddress)
                    .textContentType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($emailFocused)
                    .dsField()
                    .accessibilityIdentifier("signin.email")
                AsyncButton(L("Email me a link"), kind: .primary) {
                    emailFocused = false
                    await model.sendMagicLink()
                }
                .disabled(!model.emailLooksValid)
                .accessibilityIdentifier("signin.sendLink")
            }
            MessageNote(message: model.message)
        } actions: {
            EmptyView()
        }
    }
}

struct RelationshipStep: View {
    @Bindable var model: OnboardingModel

    var body: some View {
        StepScaffold(title: L("Who are you pairing with?"), subtitle: L("You both see the same choice.")) {
            // v1 offers only "Couple"; the screen exists so more types can be added later (decision P3).
            ForEach(RelationshipType.availableAtLaunch, id: \.self) { type in
                Button {
                    model.relationship = type
                } label: {
                    Card(tone: model.relationship == type ? .hearth : .raised) {
                        DSRow(L("Couple"), subtitle: L("Partners sharing everyday life"), systemImage: "heart") {
                            Image(systemName: model.relationship == type ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(Color.hearth)
                        }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(model.relationship == type ? [.isSelected] : [])
                .accessibilityIdentifier("relationship.couple")
            }
        } actions: {
            Button(L("Continue")) { model.advance() }
                .buttonStyle(.dsPrimary)
                .accessibilityIdentifier("onboarding.next")
        }
    }
}

struct InviteStep: View {
    let model: OnboardingModel

    var body: some View {
        StepScaffold(
            title: L("Bring your partner in"),
            subtitle: L("Everything here is mutual. You both get the same powers, and either of you can unpair at any time.")
        ) {
            InviteOrJoinView(app: model.app)
        } actions: {
            Button(model.app.isPaired ? L("Continue") : L("Continue on my own for now")) { model.advance() }
                .buttonStyle(.ds(model.app.isPaired ? .primary : .secondary))
                .accessibilityIdentifier("onboarding.next")
            if !model.app.isPaired {
                SkyText(L("Protected time and your emergency unlock work right away. The rest waits for your partner."), role: .caption, muted: true)
                    .multilineTextAlignment(.center)
            }
        }
    }
}

struct NotificationsStep: View {
    let model: OnboardingModel

    var body: some View {
        StepScaffold(title: L("Stay in touch"), subtitle: L("So your partner's requests and kudos reach you.")) {
            Card {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    DSRow(L("When your partner asks for time"), systemImage: "bubble.left.and.bubble.right")
                    DSRow(L("When you get kudos or finish a challenge"), systemImage: "sparkles")
                    DSRow(L("Before minutes expire"), systemImage: "hourglass")
                }
            }
        } actions: {
            AsyncButton(L("Allow notifications")) { await model.allowNotifications() }
                .accessibilityIdentifier("onboarding.next")
            Button(L("Not now")) { model.advance() }
                .buttonStyle(.dsQuiet)
                .accessibilityIdentifier("onboarding.skip")
        }
    }
}

struct ScreenTimeStep: View {
    let model: OnboardingModel

    var body: some View {
        StepScaffold(
            title: L("Let protected time pause your apps"),
            subtitle: L("This uses Apple's Screen Time, on your phone only. Which apps you pause and what you do in them is never shared with your partner or with us.")
        ) {
            if model.screenTimeDeclined {
                NoteBanner(
                    L("No problem. Protected time needs this to pause apps, so you can try again now or turn it on later from the home screen."),
                    tone: .neutral
                )
                .accessibilityIdentifier("screentime.declined")
            }
        } actions: {
            AsyncButton(model.screenTimeDeclined ? L("Try again") : L("Allow Screen Time access")) { await model.allowScreenTime() }
                .accessibilityIdentifier("onboarding.next")
            if model.screenTimeDeclined {
                Button(L("Continue without it")) { model.advance() }
                    .buttonStyle(.dsQuiet)
                    .accessibilityIdentifier("onboarding.skip")
            }
        }
    }
}

struct ChooseAppsStep: View {
    @Bindable var model: OnboardingModel

    var body: some View {
        StepScaffold(
            title: L("Choose what to pause"),
            subtitle: L("Tap Social, and add any other apps you want paused. Phone, Messages, Maps and your bank are best left out.")
        ) {
            PausedAppsPicker(service: model.app.deps.blocking, selection: $model.selection)
                .frame(minHeight: model.app.deps.blocking.kind == .screenTime ? 420 : nil)
            MessageNote(message: model.message)
        } actions: {
            AsyncButton(L("Continue")) { await model.saveApps() }
                .disabled(!model.canSaveApps)
                .accessibilityIdentifier("onboarding.next")
        }
    }
}

struct ProtectedTimeStep: View {
    @Bindable var model: OnboardingModel

    var body: some View {
        StepScaffold(
            title: L("Your protected time"),
            subtitle: L("Every day, your paused apps rest during these hours. You can change this later.")
        ) {
            ScheduleTimesEditor(schedule: $model.schedule)
            if model.app.isPaired {
                SkyText(L("Making protected time shorter later is something you and your partner agree on together."), role: .caption, muted: true)
            }
            MessageNote(message: model.message)
        } actions: {
            AsyncButton(L("Continue")) { await model.saveSchedule() }
                .accessibilityIdentifier("onboarding.next")
        }
    }
}

struct MinutesStep: View {
    @Bindable var model: OnboardingModel

    var body: some View {
        StepScaffold(
            title: L("Your minutes"),
            subtitle: L("Minutes open your paused apps during protected time. You earn more together, and each one lasts 7 days.")
        ) {
            if model.scheduleWaitsForPartner, let name = model.app.partnerName {
                NoteBanner(L("\(name) will be asked about your shorter protected time. Until then it stays as it was."), tone: .neutral)
            }
            Card {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Stepper(value: $model.startingMinutes, in: MinutesRules.startingMinutesRange, step: 5) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(L("Start with")).textRole(.body).foregroundStyle(Color.ink)
                            Text(MinutesText.short(model.startingMinutes)).textRole(.heading).foregroundStyle(Color.glowStrong)
                        }
                    }
                    .accessibilityIdentifier("minutes.starting")
                    Divider().overlay(Color.line)
                    Stepper(value: $model.dailyMax, in: MinutesRules.dailyMaxRange, step: MinutesRules.dailyMaxStep) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(L("Most you'll spend in a day")).textRole(.body).foregroundStyle(Color.ink)
                            Text(MinutesText.short(model.dailyMax)).textRole(.heading).foregroundStyle(Color.glowStrong)
                        }
                    }
                    .accessibilityIdentifier("minutes.dailyMax")
                }
            }
            SkyText(L("Your starting minutes arrive when you and your partner pair."), role: .caption, muted: true)
            MessageNote(message: model.message)
        } actions: {
            AsyncButton(L("Continue")) { await model.saveMinutes() }
                .accessibilityIdentifier("onboarding.next")
        }
    }
}

struct ReadyStep: View {
    let model: OnboardingModel
    @State private var together = false

    var body: some View {
        VStack(spacing: Spacing.lg) {
            Spacer()
            // The evening has arrived: the two lights settle together.
            TwoLights(closeness: together ? 1 : 0.3, diameter: 120, glow: together ? 1 : 0.3)
                .accessibilityHidden(true)
            SkyText(L("You're all set"), role: .title).accessibilityAddTraits(.isHeader)
            SkyText(model.readyLine, role: .display)
                .multilineTextAlignment(.center)
                .accessibilityIdentifier("ready.line")
            if !model.app.isPaired {
                SkyText(L("Invite your partner any time from the home screen."), role: .body, muted: true)
                    .multilineTextAlignment(.center)
            }
            Spacer()
            AsyncButton(L("Done")) { await model.finish() }
                .accessibilityIdentifier("onboarding.done")
        }
        .padding(Spacing.lg)
        .task {
            try? await Task.sleep(for: .milliseconds(300))
            together = true
            Haptics.settle()
        }
    }
}
