import Core
import DesignSystem
import FeatureSupport
import QRCode
import SwiftUI

/// The unlock sheet (06 §5): choose a length, then scan, ask, use minutes or the emergency unlock.
public struct UnlockSheet: View {
    @State private var model: UnlockModel
    @State private var path: [UnlockModel.Method] = []
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize

    public init(app: AppModel) { _model = State(initialValue: UnlockModel(app: app)) }

    public var body: some View {
        NavigationStack(path: $path) {
            Group {
                if model.started != nil {
                    UnlockStartedView(model: model) { dismiss() }
                } else {
                    methods
                }
            }
            .navigationTitle(L("Unlock"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    BarButton(L("Close")) { dismiss() }.accessibilityIdentifier("unlock.close")
                }
            }
            .navigationDestination(for: UnlockModel.Method.self) { method in
                Group {
                    if model.started != nil {
                        UnlockStartedView(model: model) { dismiss() }
                    } else {
                        switch method {
                        case .scan: ScanStep(model: model)
                        case .ask: AskStep(model: model)
                        case .minutes: MinutesStep(model: model)
                        case .emergency: EmergencyStep(model: model)
                        }
                    }
                }
                .navigationBarBackButtonHidden(model.started != nil)
            }
        }
        .tint(Color.hearth)
    }

    private var methods: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.md) {
                SectionHeader(L("How long?"))
                lengthPicker
                SectionHeader(L("How?"))
                methodRow(.scan, title: L("Scan \(model.partnerName)'s code"), subtitle: model.isPaired ? L("When you're together. Free, any time.") : L("Invite your partner to use this."), icon: "qrcode.viewfinder", enabled: model.isPaired)
                methodRow(.ask, title: L("Ask \(model.partnerName)"), subtitle: model.isPaired ? L("They answer with one tap.") : L("Invite your partner to use this."), icon: "bubble.left.and.bubble.right", enabled: model.isPaired)
                methodRow(.minutes, title: L("Use your minutes"), subtitle: model.minutesNote, icon: "hourglass", enabled: true)
                // An emergency unlock is always available, partner or not (feature spec §6.4).
                methodRow(.emergency, title: L("Emergency unlock"), subtitle: L("15 minutes, always there if you need it."), icon: "lifepreserver", enabled: true)
            }
            .padding(Spacing.md)
        }
        .onSky(sky)
    }

    /// The sheet sits under the same sky as the home scene.
    private var sky: SkyMoment {
        SkyChoice.moment(for: model.app.protectionPhase, now: model.app.deps.now())
    }

    private var lengthPicker: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            // Three chips in a row; one under the other at accessibility sizes.
            let chips = typeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: Spacing.xs))
                : AnyLayout(HStackLayout(spacing: Spacing.xs))
            chips {
                ForEach(UnlockRules.freeLengths, id: \.self) { minutes in
                    Chip(MinutesText.short(minutes), isSelected: model.length == minutes) {
                        Haptics.tick()
                        model.length = minutes
                    }
                        .accessibilityIdentifier("unlock.length.\(minutes)")
                }
            }
            if model.canStepLength {
                // Premium: any length in 15-minute steps.
                Card {
                    Stepper {
                        Text(L("Or any length: \(MinutesText.short(model.length))"))
                            .textRole(.callout)
                            .foregroundStyle(Color.ink)
                    } onIncrement: {
                        Haptics.tick()
                        model.stepLength(by: 1)
                    } onDecrement: {
                        Haptics.tick()
                        model.stepLength(by: -1)
                    }
                    .accessibilityIdentifier("unlock.length.stepper")
                }
            }
        }
    }

    private func methodRow(_ method: UnlockModel.Method, title: String, subtitle: String, icon: String, enabled: Bool) -> some View {
        Button {
            model.message = nil
            path.append(method)
        } label: {
            Card {
                DSRow(title, subtitle: subtitle, systemImage: icon) {
                    Image(systemName: "chevron.right").foregroundStyle(Color.inkMuted)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.6)
        .accessibilityIdentifier("unlock.method.\(method.rawValue)")
    }
}

private struct MessageNote: View {
    let message: String?
    var body: some View {
        if let message {
            NoteBanner(message, tone: .neutral).accessibilityIdentifier("unlock.message")
        }
    }
}

struct ScanStep: View {
    let model: UnlockModel

    var body: some View {
        VStack(spacing: Spacing.md) {
            Text(L("Ask \(model.partnerName) to open “Show my code”, then point your camera at it."))
                .textRole(.body)
                .foregroundStyle(Color.inkMuted)
                .multilineTextAlignment(.center)
            QRScannerView(sample: model.app.deps.sampleScan.map { sample in { sample(.unlock) } }) { scanned in
                Task { await model.handleScan(scanned) }
            }
            MessageNote(message: model.message)
            Text(L("Works without a connection. Unlocks \(MinutesText.short(model.length))."))
                .textRole(.caption)
                .foregroundStyle(Color.inkMuted)
        }
        .padding(Spacing.md)
        .pageBackground()
        .navigationTitle(L("Scan code"))
    }
}

struct AskStep: View {
    @Bindable var model: UnlockModel
    @FocusState private var focused: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.md) {
                switch model.flow {
                case .idle, .cancelled:
                    Text(L("\(model.partnerName) gets a notification and can answer with one tap."))
                        .textRole(.body)
                        .foregroundStyle(Color.inkMuted)
                    TextField(L("Add a reason (optional)"), text: $model.reason, axis: .vertical)
                        .lineLimit(1...3)
                        .focused($focused)
                        .dsField()
                        .onChange(of: model.reason) { _, value in
                            if value.count > 140 { model.reason = String(value.prefix(140)) }
                        }
                        .accessibilityIdentifier("ask.reason")
                    // Asking as a gesture: bring your light over to theirs. The button below does the same.
                    LightsMeetControl(L("Slide your light to \(model.partnerName)")) {
                        focused = false
                        Task { await model.askPartner() }
                    }
                    .accessibilityHidden(true)
                    AsyncButton(L("Ask \(model.partnerName) for \(MinutesText.short(model.length))")) {
                        focused = false
                        await model.askPartner()
                    }
                    .accessibilityIdentifier("ask.send")
                case .waiting:
                    waiting
                case .declined, .expired:
                    // Never a red "denied" state: a calm note and what to do next.
                    Card(tone: .sunken) {
                        Text(model.outcomeLine ?? "")
                            .textRole(.heading)
                            .foregroundStyle(Color.ink)
                            .accessibilityIdentifier("ask.outcome")
                    }
                    Button(L("Ask again")) { model.askAgain() }
                        .buttonStyle(.dsSecondary)
                        .accessibilityIdentifier("ask.again")
                case .approved:
                    EmptyView()
                }
                MessageNote(message: model.message)
            }
            .padding(Spacing.md)
        }
        .pageBackground()
        .navigationTitle(L("Ask \(model.partnerName)"))
        .task {
            // Drives the 5-minute expiry and picks up the partner's answer.
            while !Task.isCancelled {
                model.tick()
                try? await Task.sleep(for: .milliseconds(500))
            }
        }
    }

    @ViewBuilder private var waiting: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            let seconds = model.waitingSecondsLeft
            Card(tone: .hearth) {
                VStack(spacing: Spacing.sm) {
                    ProgressRing(
                        progress: Double(seconds) / UnlockRules.requestValidity, tint: .hearth, track: .surfaceRaised, lineWidth: 8,
                        accessibilityText: L("Waiting for \(model.partnerName). \(DurationText.spoken(TimeInterval(seconds))) left")
                    ) {
                        Text(String(format: "%d:%02d", seconds / 60, seconds % 60))
                            .textRole(.heading)
                            .foregroundStyle(Color.hearth)
                            .monospacedDigit()
                    }
                    .frame(width: 96, height: 96)
                    Text(L("Waiting for \(model.partnerName)…"))
                        .textRole(.heading)
                        .foregroundStyle(Color.hearth)
                        .accessibilityIdentifier("ask.waiting")
                }
                .frame(maxWidth: .infinity)
            }
        }
        if model.codeEntryAvailable {
            Card {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Text(L("\(model.partnerName) also got an email with a 6-digit code. If they share it with you, type it here."))
                        .textRole(.callout)
                        .foregroundStyle(Color.inkMuted)
                    TextField(L("6-digit code"), text: $model.codeEntry)
                        .keyboardType(.numberPad)
                        .textContentType(.oneTimeCode)
                        .focused($focused)
                        .dsField()
                        .onChange(of: model.codeEntry) { _, value in
                            let digits = String(value.filter(\.isNumber).prefix(UnlockRules.accountabilityCodeLength))
                            if digits != value { model.codeEntry = digits }
                        }
                        .accessibilityIdentifier("ask.code")
                    AsyncButton(L("Unlock with code")) {
                        focused = false
                        await model.redeemCode()
                    }
                    .disabled(!model.canRedeemCode)
                    .accessibilityIdentifier("ask.redeem")
                }
            }
        }
    }
}

struct MinutesStep: View {
    let model: UnlockModel

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Card(tone: .glow) {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    StatTile(value: (model.app.myMinutes?.balance ?? 0).formatted(), label: L("your minutes"), tint: .glowStrong)
                    Text(model.minutesNote)
                        .textRole(.callout)
                        .foregroundStyle(Color.ink)
                        .accessibilityIdentifier("minutes.note")
                }
            }
            Text(L("Minutes closest to expiring are used first."))
                .textRole(.caption)
                .foregroundStyle(Color.inkMuted)
            MessageNote(message: model.message)
            Spacer()
            AsyncButton(L("Unlock \(MinutesText.short(model.length))")) { await model.useMinutes() }
                .disabled(model.minutesAvailability != .available)
                .accessibilityIdentifier("minutes.spend")
        }
        .padding(Spacing.md)
        .pageBackground()
        .navigationTitle(L("Use your minutes"))
    }
}

struct EmergencyStep: View {
    let model: UnlockModel

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Card(tone: .sunken) {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text(L("For when you really need your phone."))
                        .textRole(.heading)
                        .foregroundStyle(Color.ink)
                    Text(model.emergencyNote)
                        .textRole(.callout)
                        .foregroundStyle(Color.inkMuted)
                        .accessibilityIdentifier("emergency.note")
                    if model.isPaired {
                        Text(L("\(model.partnerName) will see a short neutral note. No approval is needed."))
                            .textRole(.callout)
                            .foregroundStyle(Color.inkMuted)
                    }
                }
            }
            MessageNote(message: model.message)
            Spacer()
            AsyncButton(L("Unlock 15 min now")) { await model.useEmergency() }
                .disabled(model.emergencyAvailableAt != nil)
                .accessibilityIdentifier("emergency.use")
        }
        .padding(Spacing.md)
        .pageBackground()
        .navigationTitle(L("Emergency unlock"))
    }
}

/// Success: the two circles slide together (signature moment 3) with a success haptic.
struct UnlockStartedView: View {
    let model: UnlockModel
    let onDone: () -> Void
    @State private var together = false

    var body: some View {
        VStack(spacing: Spacing.lg) {
            Spacer()
            ComingTogether(together: together, diameter: 120)
            SkyText(model.startedLine ?? "", role: .display)
                .multilineTextAlignment(.center)
                .accessibilityIdentifier("unlock.started")
            SkyText(
                model.started?.method == .emergency
                    ? L("Take the time you need. Protected time comes back on its own.")
                    : L("Enjoy it. Protected time comes back on its own."),
                role: .body, muted: true
            )
            .multilineTextAlignment(.center)
            Spacer()
            Button(L("Done"), action: onDone)
                .buttonStyle(.dsPrimary)
                .accessibilityIdentifier("unlock.done")
        }
        .padding(Spacing.lg)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onSky(.goldenHour)
        .task {
            try? await Task.sleep(for: .milliseconds(200))
            together = true
            Haptics.meet()
        }
    }
}

/// "Show my code": a full-screen rotating QR with a 30-second progress ring.
public struct ShowMyCodeView: View {
    @State private var model: ShowCodeModel
    @Environment(\.dismiss) private var dismiss

    public init(app: AppModel) { _model = State(initialValue: ShowCodeModel(app: app)) }

    public var body: some View {
        NavigationStack {
            VStack(spacing: Spacing.lg) {
                if model.secret != nil {
                    TimelineView(.periodic(from: .now, by: 0.5)) { timeline in
                        let now = model.app.deps.now()
                        let _ = timeline.date
                        VStack(spacing: Spacing.lg) {
                            QRCodeView(model.payload(at: now) ?? "", accessibilityText: L("Your unlock code. It changes every 30 seconds."))
                                .frame(maxWidth: 300)
                                .accessibilityIdentifier("code.qr")
                            ProgressRing(
                                progress: 1 - model.progress(at: now), tint: .sage, lineWidth: 6,
                                accessibilityText: L("New code in \(model.secondsRemaining(at: now).formatted()) seconds")
                            ) {
                                Text(model.secondsRemaining(at: now).formatted())
                                    .textRole(.callout)
                                    .foregroundStyle(Color.ink)
                                    .monospacedDigit()
                            }
                            .frame(width: 56, height: 56)
                        }
                    }
                    Text(L("Let \(model.app.partnerName ?? "") scan this to unlock time together. It works without a connection."))
                        .textRole(.body)
                        .foregroundStyle(Color.inkMuted)
                        .multilineTextAlignment(.center)
                } else {
                    Text(L("Your code appears here once you and your partner are paired and this phone has connected once."))
                        .textRole(.body)
                        .foregroundStyle(Color.inkMuted)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(Spacing.lg)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .pageBackground()
            .navigationTitle(L("Show my code"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { BarButton(L("Done")) { dismiss() }.accessibilityIdentifier("code.done") }
            }
        }
    }
}

/// The partner's request: "Ana asks for 30 minutes · 'Reply to a client'" with Go for it / Let's wait.
public struct IncomingRequestView: View {
    @State private var model: IncomingRequestModel

    public init(app: AppModel, request: UnlockRequest) {
        _model = State(initialValue: IncomingRequestModel(app: app, request: request))
    }

    public var body: some View {
        VStack(spacing: Spacing.lg) {
            Spacer()
            // Their light, reaching toward yours.
            TwoLights(closeness: 0.7, diameter: 96, overlap: 0.2, glow: 0.8)
                .accessibilityHidden(true)
            SkyText(model.title, role: .display)
                .multilineTextAlignment(.center)
                .accessibilityIdentifier("request.title")
            if let reason = model.request.reason {
                SkyText("“\(reason)”", role: .body, muted: true).multilineTextAlignment(.center)
            }
            if let message = model.message { NoteBanner(message, tone: .neutral) }
            Spacer()
            // Saying yes as a gesture: bring your light to theirs. The buttons below do the same.
            LightsMeetControl(L("Slide to say go for it")) {
                Task { await model.respond(approve: true) }
            }
            .accessibilityHidden(true)
            AsyncButton(L("Go for it")) { await model.respond(approve: true) }
                .accessibilityIdentifier("request.approve")
            AsyncButton(L("Let's wait"), kind: .secondary) { await model.respond(approve: false) }
                .accessibilityIdentifier("request.wait")
        }
        .padding(Spacing.lg)
        .onSky(.dusk)
        .presentationDetents([.large])
    }
}
