import Core
import DesignSystem
import FeatureSupport
import SwiftUI

/// The give-kudos sheet: your light sends warmth to your partner's.
public struct GiveKudosSheet: View {
    @State private var model: KudosModel
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focused: Bool

    public init(app: AppModel, challengeID: UUID? = nil) {
        _model = State(initialValue: KudosModel(app: app, challengeID: challengeID))
    }

    public var body: some View {
        NavigationStack {
            Group {
                if !model.isPremium {
                    premiumNote
                } else if model.sent != nil {
                    sentView
                } else {
                    form
                }
            }
            .navigationTitle(L("Kudos"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(L("Close")) { dismiss() }.accessibilityIdentifier("kudos.close") }
            }
        }
        .task { await model.load() }
    }

    private var form: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.md) {
                SkyText(L("Tell \(model.partnerName) you noticed."), role: .display)
                    .accessibilityAddTraits(.isHeader)
                TextField(L("You made me laugh today"), text: $model.note, axis: .vertical)
                    .lineLimit(1...3)
                    .focused($focused)
                    .dsField()
                    .onChange(of: model.note) { _, value in if value.count > 140 { model.note = String(value.prefix(140)) } }
                    .accessibilityIdentifier("kudos.note")
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Spacing.xs) {
                        ForEach(model.suggestions, id: \.self) { line in
                            Chip(line, isSelected: model.note == line) {
                                Haptics.tick()
                                model.note = line
                            }
                        }
                    }
                }
                SectionHeader(L("How many minutes?"))
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Spacing.xs) {
                        ForEach(model.amounts, id: \.self) { amount in
                            Chip(MinutesText.short(amount), isSelected: model.minutes == amount) {
                                Haptics.tick()
                                model.minutes = amount
                            }
                            .disabled(amount > model.remainingToday)
                            .opacity(amount > model.remainingToday ? 0.4 : 1)
                            .accessibilityIdentifier("kudos.amount.\(amount)")
                        }
                    }
                }
                SkyText(model.remainingLine, role: .caption, muted: true)
                if let message = model.message { NoteBanner(message, tone: .neutral).accessibilityIdentifier("kudos.message") }
                AsyncButton(L("Give \(MinutesText.short(model.minutes)) to \(model.partnerName)"), kind: .glow) {
                    focused = false
                    await model.give()
                }
                .disabled(!model.canGive)
                .accessibilityIdentifier("kudos.give")
            }
            .padding(Spacing.md)
        }
        .onSky(.goldenHour)
    }

    private var sentView: some View {
        KudosGlow(minutes: model.sent?.minutes ?? 0, title: model.sentLine ?? "", bodyText: nil, receiving: false) { dismiss() }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("kudos.sent")
    }

    private var premiumNote: some View {
        VStack(spacing: Spacing.lg) {
            Spacer()
            TwoLights(closeness: 0.8, diameter: 96, glow: 0.6).accessibilityHidden(true)
            SkyText(L("Kudos are part of premium."), role: .display).multilineTextAlignment(.center)
            SkyText(L("Give each other minutes just because. One price covers both of you."), role: .body, muted: true)
                .multilineTextAlignment(.center)
            Spacer()
            Button(L("See premium")) { model.app.sheet = .paywall }
                .buttonStyle(.dsPrimary)
                .accessibilityIdentifier("kudos.premium")
        }
        .padding(Spacing.lg)
        .onSky(.goldenHour)
    }
}

/// Signature moment 1: warmth arriving. The giver's light swells, its glow washes over the other,
/// and the minutes count up. With Reduce Motion the glow simply fades in and the number is shown.
struct KudosGlow: View {
    let minutes: Int
    let title: String
    let bodyText: String?
    /// True when this person received the kudos (the partner's light glows); false when they gave it.
    let receiving: Bool
    let onDone: () -> Void
    @State private var lit = false
    /// The number on screen while it counts up to `minutes`.
    @State private var shown = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            GlowBloom(isActive: lit)
            VStack(spacing: Spacing.lg) {
                Spacer()
                TwoLights(closeness: lit ? 1 : 0.4, diameter: 110, overlap: 0.45, glow: lit ? 1 : 0.3)
                    .scaleEffect(lit && !reduceMotion ? 1.06 : 1)
                    .animation(Motion.resolve(Motion.celebration, reduceMotion: reduceMotion), value: lit)
                    .accessibilityHidden(true)
                SkyText(KudosText.amount(minutes: shown), role: .numeralLarge)
                    .contentTransition(.numericText(value: Double(shown)))
                    // VoiceOver hears the amount once, not every step of the count.
                    .accessibilityLabel(KudosText.amount(minutes: minutes))
                    .accessibilityIdentifier("kudos.amount")
                SkyText(title, role: .display).multilineTextAlignment(.center)
                if let bodyText {
                    SkyText(bodyText, role: .body, muted: true).multilineTextAlignment(.center)
                }
                Spacer()
                Button(receiving ? L("Lovely") : L("Done"), action: onDone)
                    .buttonStyle(.dsGlow)
                    .accessibilityIdentifier("kudos.done")
            }
            .padding(Spacing.lg)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onSky(.goldenHour)
        .task {
            try? await Task.sleep(for: .milliseconds(200))
            lit = true
            Haptics.warmth()
            guard !reduceMotion else {
                shown = minutes
                return
            }
            for value in KudosText.countSteps(to: minutes) {
                try? await Task.sleep(for: .milliseconds(70))
                withAnimation(Motion.resolve(Motion.standard, reduceMotion: false)) { shown = value }
            }
        }
    }
}

/// Shown to the person who received kudos: "Ana says you made her laugh · +10 min".
public struct KudosCelebrationView: View {
    let kudos: Kudos
    let partnerName: String
    let onDone: () -> Void

    public init(kudos: Kudos, partnerName: String, onDone: @escaping () -> Void) {
        self.kudos = kudos
        self.partnerName = partnerName
        self.onDone = onDone
    }

    public var body: some View {
        KudosGlow(
            minutes: kudos.minutes, title: KudosText.title(from: partnerName),
            bodyText: KudosText.body(kudos, partnerName: partnerName), receiving: true, onDone: onDone
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("celebration.kudos")
    }
}
