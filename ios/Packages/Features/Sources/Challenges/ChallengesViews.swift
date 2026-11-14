import Core
import DesignSystem
import FeatureSupport
import SwiftUI

/// Minutes a challenge earns, as a small Glow light (earned minutes are always Glow).
struct EarnBadge: View {
    let minutes: Int
    let shared: Bool

    var body: some View {
        HStack(spacing: -10) {
            // A shared challenge lights both of you; an individual one, just the person who did it.
            if shared { LightDisc(.me, diameter: 30, glow: 0) }
            LightDisc(.partner, diameter: 44, glow: 0.2) {
                Text(verbatim: "+\(minutes)").font(Typography.font(.heading, size: 15))
            }
        }
        .accessibilityHidden(true)
    }
}

/// "Together": challenges and kudos. The place where minutes are earned and given.
public struct ChallengesView: View {
    @State private var model: ChallengesModel
    @State private var showCustom = false

    public init(app: AppModel) { _model = State(initialValue: ChallengesModel(app: app)) }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    header
                    if !model.canComplete {
                        NoteBanner(L("A preview for now. Invite your partner to start earning minutes together."), systemImage: "person.2")
                            .accessibilityIdentifier("challenges.preview")
                    }
                    confirmations
                    values
                    ForEach(model.sections) { section in
                        SectionHeader(ChallengesModel.title(section.category))
                        ForEach(section.challenges) { challenge in
                            NavigationLink(value: challenge.id) {
                                Card {
                                    DSRow(
                                        challenge.title,
                                        subtitle: model.isWaiting(challenge) ? L("Waiting for \(model.app.partnerName ?? "")") : model.earnLine(challenge),
                                        systemImage: ChallengesModel.symbol(challenge.category)
                                    ) { EarnBadge(minutes: challenge.minutes, shared: challenge.isShared) }
                                }
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("challenge.\(challenge.title)")
                        }
                    }
                    premiumRows
                    if let message = model.message { NoteBanner(message, tone: .neutral) }
                }
                .padding(.horizontal, Spacing.md)
                .padding(.bottom, 96)
            }
            .onSky(SkyChoice.moment(for: model.app.protectionPhase, now: model.app.deps.now()))
            .navigationDestination(for: UUID.self) { id in
                if let challenge = model.challenge(id) { ChallengeDetailView(model: model, challenge: challenge) }
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .accessibilityIdentifier("challenges.screen")
        .task { await model.load() }
        .refreshable { await model.load() }
        .sheet(isPresented: $showCustom) { CustomChallengeSheet(model: model) }
        .onChange(of: model.app.focusedChallengeID) { _, _ in }
    }

    private var header: some View {
        VStack(spacing: Spacing.sm) {
            SkyText(L("Together"), role: .label, muted: true)
            SkyText(L("What shall we do?"), role: .display)
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)
            if model.app.isPaired {
                Button {
                    Haptics.touch()
                    model.app.sheet = .giveKudos(challengeID: nil)
                } label: {
                    Label(L("Give \(model.app.partnerName ?? "") kudos"), systemImage: "sparkles")
                }
                .buttonStyle(.dsGlow)
                .accessibilityIdentifier("together.kudos")
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, Spacing.md)
    }

    @ViewBuilder private var confirmations: some View {
        if !model.toConfirm.isEmpty {
            SectionHeader(L("For you to confirm"))
            ForEach(model.toConfirm) { pending in
                Card(tone: .glow) {
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        Text(model.confirmLine(pending)).textRole(.heading).foregroundStyle(Color.ink)
                        if let note = pending.completion.note {
                            Text(verbatim: "“\(note)”").textRole(.callout).foregroundStyle(Color.inkMuted)
                        }
                        AsyncButton(L("Confirm · +\(model.earnLine(pending.challenge))"), kind: .glow) { await model.confirm(pending) }
                            .accessibilityIdentifier("completion.confirm")
                    }
                }
            }
        }
    }

    @ViewBuilder private var values: some View {
        ForEach(model.valuesToAnswer) { challenge in
            ValueApprovalCard(model: model, challenge: challenge)
        }
        ForEach(model.valuesWaiting) { challenge in
            NoteBanner(L("“\(challenge.title)” is waiting for \(model.app.partnerName ?? "") to agree on \(MinutesText.short(challenge.minutes))."), systemImage: "hourglass")
                .accessibilityIdentifier("custom.waiting")
        }
    }

    @ViewBuilder private var premiumRows: some View {
        if model.canCreateCustom {
            Button {
                showCustom = true
            } label: {
                Label(L("Add your own challenge"), systemImage: "plus")
            }
            .buttonStyle(.dsSecondary)
            .accessibilityIdentifier("custom.add")
        } else if !model.app.isPremium {
            Button {
                model.app.sheet = .paywall
            } label: {
                Card(tone: .sunken) {
                    DSRow(
                        L("\(model.lockedCount.formatted()) more ideas, your own challenges and kudos"),
                        subtitle: L("Part of premium. One price for both of you."), systemImage: "sparkles"
                    ) { Image(systemName: "chevron.right").foregroundStyle(Color.inkMuted) }
                }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("challenges.premium")
        }
    }
}

struct ValueApprovalCard: View {
    let model: ChallengesModel
    let challenge: Challenge
    @State private var counter: Int
    @State private var suggesting = false

    init(model: ChallengesModel, challenge: Challenge) {
        self.model = model
        self.challenge = challenge
        _counter = State(initialValue: challenge.minutes)
    }

    var body: some View {
        Card(tone: .hearth) {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text(model.valueQuestion(challenge))
                    .textRole(.heading)
                    .foregroundStyle(Color.ink)
                    .accessibilityIdentifier("value.question")
                if suggesting {
                    Stepper(value: $counter, in: MinutesRules.customChallengeRange, step: 5) {
                        Text(MinutesText.short(counter)).textRole(.heading).foregroundStyle(Color.glowStrong)
                    }
                    AsyncButton(L("Suggest \(MinutesText.short(counter))"), kind: .secondary) {
                        await model.answerValue(challenge, approve: false, counterMinutes: counter)
                    }
                    .disabled(counter == challenge.minutes)
                    .accessibilityIdentifier("value.counter")
                } else {
                    AsyncButton(L("Sounds right")) { await model.answerValue(challenge, approve: true) }
                        .accessibilityIdentifier("value.approve")
                    Button(L("Suggest a different value")) { suggesting = true }
                        .buttonStyle(.dsQuiet)
                        .accessibilityIdentifier("value.suggest")
                }
            }
        }
    }
}

struct ChallengeDetailView: View {
    let model: ChallengesModel
    let challenge: Challenge
    @State private var note = ""
    @State private var done = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.md) {
                HStack(alignment: .top) {
                    Text(challenge.title)
                        .textRole(.title)
                        .foregroundStyle(Color.ink)
                        .accessibilityAddTraits(.isHeader)
                    Spacer()
                    EarnBadge(minutes: challenge.minutes, shared: challenge.isShared)
                }
                if !challenge.description.isEmpty {
                    Text(challenge.description).textRole(.body).foregroundStyle(Color.inkMuted)
                }
                NoteBanner(
                    challenge.isShared
                        ? L("You both earn \(MinutesText.short(challenge.minutes)) when either of you confirms.")
                        : L("Whoever does it earns \(MinutesText.short(challenge.minutes)) once the other confirms."),
                    systemImage: challenge.isShared ? "person.2" : "person", tone: .celebrate
                )
                if model.isWaiting(challenge) || done {
                    NoteBanner(L("Sent. \(model.app.partnerName ?? "") confirms with one tap, then the minutes arrive."), systemImage: "checkmark", tone: .calm)
                        .accessibilityIdentifier("challenge.sent")
                } else if model.canComplete {
                    TextField(L("Add a note (optional)"), text: $note, axis: .vertical)
                        .lineLimit(1...3)
                        .dsField()
                        .onChange(of: note) { _, value in if value.count > 280 { note = String(value.prefix(280)) } }
                        .accessibilityIdentifier("challenge.note")
                    AsyncButton(L("Done")) {
                        if await model.markDone(challenge, note: note) {
                            Haptics.settle()
                            done = true
                        }
                    }
                    .accessibilityIdentifier("challenge.done")
                } else {
                    NoteBanner(L("Invite your partner to use this."), systemImage: "person.2")
                }
                if model.app.isPaired {
                    // Kudos from the partner's view of a challenge: mark it for them, unprompted.
                    Button {
                        model.app.sheet = .giveKudos(challengeID: challenge.id)
                    } label: {
                        Label(L("\(model.app.partnerName ?? "") did this? Give kudos"), systemImage: "sparkles")
                    }
                    .buttonStyle(.dsQuiet)
                    .accessibilityIdentifier("challenge.kudos")
                }
                if let message = model.message { NoteBanner(message, tone: .neutral) }
            }
            .padding(Spacing.md)
        }
        .pageBackground()
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct CustomChallengeSheet: View {
    let model: ChallengesModel
    @State private var title = ""
    @State private var details = ""
    @State private var minutes = 20
    @State private var category = ChallengeCategory.together
    @State private var shared = true
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    TextField(L("What's the challenge?"), text: $title)
                        .dsField()
                        .onChange(of: title) { _, value in if value.count > 80 { title = String(value.prefix(80)) } }
                        .accessibilityIdentifier("custom.title")
                    TextField(L("A few words about it (optional)"), text: $details, axis: .vertical)
                        .lineLimit(1...3)
                        .dsField()
                        .onChange(of: details) { _, value in if value.count > 280 { details = String(value.prefix(280)) } }
                    Card {
                        VStack(alignment: .leading, spacing: Spacing.sm) {
                            Stepper(value: $minutes, in: MinutesRules.customChallengeRange, step: 5) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(L("Worth")).textRole(.body).foregroundStyle(Color.ink)
                                    Text(MinutesText.short(minutes)).textRole(.heading).foregroundStyle(Color.glowStrong)
                                }
                            }
                            .accessibilityIdentifier("custom.minutes")
                            Divider().overlay(Color.line)
                            Toggle(L("We both earn it"), isOn: $shared).tint(Color.sage)
                            Divider().overlay(Color.line)
                            Picker(L("Kind"), selection: $category) {
                                ForEach(ChallengeCategory.allCases, id: \.self) { Text(ChallengesModel.title($0)).tag($0) }
                            }
                        }
                        .textRole(.body)
                        .foregroundStyle(Color.ink)
                    }
                    Text(L("\(model.app.partnerName ?? "") agrees the minutes before it can be earned, and can suggest a different value."))
                        .textRole(.caption)
                        .foregroundStyle(Color.inkMuted)
                    if let message = model.message { NoteBanner(message, tone: .neutral) }
                    AsyncButton(L("Send to \(model.app.partnerName ?? "")")) {
                        if await model.createCustom(title: title, description: details, minutes: minutes, category: category, isShared: shared) { dismiss() }
                    }
                    .disabled(!model.isValidCustom(title: title, minutes: minutes))
                    .accessibilityIdentifier("custom.send")
                }
                .padding(Spacing.md)
            }
            .pageBackground()
            .navigationTitle(L("Your own challenge"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button(L("Close")) { dismiss() } } }
        }
    }
}
