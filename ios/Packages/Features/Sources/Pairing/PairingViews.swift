import Core
import DesignSystem
import FeatureSupport
import QRCode
import SwiftUI

/// Invite your partner (link, 6-character code or QR) or join with theirs.
public struct InviteOrJoinView: View {
    @State private var model: PairingModel
    @State private var showScanner = false
    @FocusState private var codeFocused: Bool

    public init(app: AppModel) { _model = State(initialValue: PairingModel(app: app)) }

    public var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            if let name = model.app.partnerName, model.isPaired {
                PairedCard(myName: model.app.myName, partnerName: name)
            } else {
                inviteSection
                joinSection
            }
            if let message = model.message {
                NoteBanner(message, tone: .neutral).accessibilityIdentifier("pairing.message")
            }
        }
        .sheet(isPresented: $showScanner) { scanner }
        .task {
            // An invite link that opened the app: join right away.
            if model.app.pendingInvite != nil, !model.isPaired, model.app.session != nil { await model.join() }
        }
    }

    @ViewBuilder private var inviteSection: some View {
        SectionHeader(L("Invite your partner"))
        if let invite = model.invite {
            Card {
                VStack(spacing: Spacing.md) {
                    Text(L("Your invite code"))
                        .textRole(.caption)
                        .foregroundStyle(Color.inkMuted)
                    Text(invite.code)
                        .textRole(.numeral)
                        .tracking(6)
                        .foregroundStyle(Color.hearth)
                        .accessibilityLabel(L("Invite code \(invite.code.map(String.init).joined(separator: " "))"))
                        .accessibilityIdentifier("pairing.code")
                    QRCodeView(invite.link.absoluteString, accessibilityText: L("QR code your partner can scan to join you"))
                        .frame(maxWidth: 200)
                    ShareLink(item: model.shareText(for: invite)) {
                        Label(L("Share invite link"), systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(.dsPrimary)
                    .accessibilityIdentifier("pairing.share")
                    Text(L("Good for 72 hours. Waiting for your partner to join…"))
                        .textRole(.caption)
                        .foregroundStyle(Color.inkMuted)
                        .multilineTextAlignment(.center)
                    AsyncButton(L("Cancel this invite"), kind: .quiet) { await model.revokeInvite() }
                        .accessibilityIdentifier("pairing.revoke")
                }
                .frame(maxWidth: .infinity)
            }
        } else {
            AsyncButton(L("Invite partner")) { await model.createInvite() }
                .accessibilityIdentifier("pairing.invite")
        }
    }

    @ViewBuilder private var joinSection: some View {
        SectionHeader(L("Have an invite?"))
        Card {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                TextField(L("6-character code"), text: $model.codeEntry)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .focused($codeFocused)
                    .dsField()
                    .accessibilityIdentifier("pairing.codeField")
                HStack(spacing: Spacing.sm) {
                    AsyncButton(L("Join"), kind: .primary) {
                        codeFocused = false
                        await model.join()
                    }
                    .disabled(!model.canJoin)
                    .accessibilityIdentifier("pairing.join")
                    Button {
                        showScanner = true
                    } label: {
                        Label(L("Scan"), systemImage: "qrcode.viewfinder")
                    }
                    .buttonStyle(.dsSecondary)
                    .accessibilityIdentifier("pairing.scan")
                }
            }
        }
    }

    private var scanner: some View {
        NavigationStack {
            VStack(spacing: Spacing.md) {
                Text(L("Point the camera at your partner's invite code."))
                    .textRole(.body)
                    .foregroundStyle(Color.inkMuted)
                    .multilineTextAlignment(.center)
                QRScannerView(sample: model.app.deps.sampleScan.map { sample in { sample(.invite) } }) { scanned in
                    showScanner = false
                    Task { await model.join(with: scanned) }
                }
            }
            .padding(Spacing.lg)
            .pageBackground()
            .navigationTitle(L("Scan invite"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(L("Close")) { showScanner = false } }
            }
        }
    }
}

/// "You're now paired with Ana." with the two avatars settled together.
public struct PairedCard: View {
    let myName: String
    let partnerName: String
    @State private var together = false

    public init(myName: String, partnerName: String) {
        self.myName = myName
        self.partnerName = partnerName
    }

    public var body: some View {
        Card(tone: .sage) {
            VStack(spacing: Spacing.md) {
                AvatarsComingTogether(myName: myName, partnerName: partnerName, together: together)
                Text(L("You're now paired with \(partnerName)."))
                    .textRole(.heading)
                    .foregroundStyle(Color.sage)
                    .multilineTextAlignment(.center)
                    .accessibilityIdentifier("pairing.paired")
            }
            .frame(maxWidth: .infinity)
        }
        .onAppear { together = true }
    }
}

/// Signature moment 6: the two lights, each carrying an initial, drift together and settle overlapped.
public struct AvatarsComingTogether: View {
    let myName: String
    let partnerName: String
    let together: Bool
    var diameter: CGFloat = 72
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(myName: String, partnerName: String, together: Bool, diameter: CGFloat = 72) {
        self.myName = myName
        self.partnerName = partnerName
        self.together = together
        self.diameter = diameter
    }

    private func initial(_ name: String) -> some View {
        Text(String(name.trimmingCharacters(in: .whitespaces).prefix(1)).uppercased())
            .font(Typography.font(.title, size: diameter * 0.4))
    }

    public var body: some View {
        TwoLights(closeness: reduceMotion || together ? 1 : 0, diameter: diameter, overlap: 0.3, glow: together ? 1 : 0.3) {
            initial(myName)
        } theirs: {
            initial(partnerName)
        }
        .opacity(reduceMotion && !together ? 0.4 : 1)
        .animation(Motion.resolve(Motion.meet, reduceMotion: reduceMotion), value: together)
        .accessibilityHidden(true)
    }
}

/// Full-screen celebration when pairing completes.
public struct PairedCelebrationView: View {
    let myName: String
    let partnerName: String
    let onDone: () -> Void
    @State private var together = false

    public init(myName: String, partnerName: String, onDone: @escaping () -> Void) {
        self.myName = myName
        self.partnerName = partnerName
        self.onDone = onDone
    }

    public var body: some View {
        VStack(spacing: Spacing.lg) {
            Spacer()
            AvatarsComingTogether(myName: myName, partnerName: partnerName, together: together, diameter: 120)
            SkyText(L("You're now paired with \(partnerName)."), role: .display)
                .multilineTextAlignment(.center)
                .accessibilityIdentifier("celebration.paired")
            SkyText(L("Everything here is shared and equal. Either of you can unpair at any time."), role: .body, muted: true)
                .multilineTextAlignment(.center)
            Spacer()
            Button(L("Continue"), action: onDone)
                .buttonStyle(.dsPrimary)
                .accessibilityIdentifier("celebration.done")
        }
        .padding(Spacing.lg)
        .onSky(.dusk)
        .task {
            try? await Task.sleep(for: .milliseconds(250))
            together = true
            Haptics.meet()
        }
    }
}

/// Settings section: the partner, unpairing (one confirmation, no approval needed) and renewing the unlock code.
public struct PartnerSettingsView: View {
    @State private var model: PairingModel
    @State private var confirmUnpair = false

    public init(app: AppModel) { _model = State(initialValue: PairingModel(app: app)) }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.md) {
                if let name = model.app.partnerName {
                    Card {
                        HStack(spacing: Spacing.md) {
                            Avatar(name: name, tone: .partner)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(name).textRole(.heading).foregroundStyle(Color.ink)
                                Text(L("Your partner")).textRole(.caption).foregroundStyle(Color.inkMuted)
                            }
                        }
                    }
                    if model.app.partnerProtectionIsOff {
                        // Neutral status, never a judgement (decision P23).
                        NoteBanner(L("Protected time is off on \(name)'s phone."), systemImage: "moon.zzz", tone: .neutral)
                    }
                    Card {
                        VStack(alignment: .leading, spacing: Spacing.sm) {
                            Text(L("Lost a phone? Renew the code you two use to unlock in person."))
                                .textRole(.callout)
                                .foregroundStyle(Color.inkMuted)
                            AsyncButton(L("Renew unlock code"), kind: .secondary) { await model.rotateSecret() }
                                .accessibilityIdentifier("partner.rotate")
                        }
                    }
                    Card {
                        VStack(alignment: .leading, spacing: Spacing.sm) {
                            Text(L("Either of you can unpair at any time. Your protected time stays on your phone, your minutes reset to zero and your history is kept."))
                                .textRole(.callout)
                                .foregroundStyle(Color.inkMuted)
                            Button(L("Unpair")) { confirmUnpair = true }
                                .buttonStyle(.dsSecondary)
                                .accessibilityIdentifier("partner.unpair")
                        }
                    }
                } else {
                    Text(L("Pair with your partner to ask each other for time, earn minutes together and share a streak."))
                        .textRole(.body)
                        .foregroundStyle(Color.inkMuted)
                    InviteOrJoinView(app: model.app)
                }
                if let message = model.message { NoteBanner(message, tone: .neutral) }
            }
            .padding(Spacing.md)
        }
        .pageBackground()
        .navigationTitle(L("Partner"))
        .confirmationDialog(
            L("Unpair from \(model.app.partnerName ?? "")?"), isPresented: $confirmUnpair, titleVisibility: .visible
        ) {
            // Destructive: the one place besides account deletion where red is right.
            Button(L("Unpair"), role: .destructive) { Task { await model.unpair() } }
                .accessibilityIdentifier("partner.unpair.confirm")
            Button(L("Stay paired"), role: .cancel) {}
        } message: {
            Text(L("This happens right away and doesn't need your partner's approval."))
        }
    }
}

/// The invite sheet opened from the home screen or an invite link.
public struct InviteSheet: View {
    let app: AppModel
    @Environment(\.dismiss) private var dismiss

    public init(app: AppModel) { self.app = app }

    public var body: some View {
        NavigationStack {
            ScrollView {
                InviteOrJoinView(app: app).padding(Spacing.md)
            }
            .pageBackground()
            .navigationTitle(L("Pair with your partner"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("Done")) { dismiss() }.accessibilityIdentifier("invite.done")
                }
            }
        }
    }
}
