import Core
import DesignSystem
import FeatureSupport
import SwiftUI

public struct MinutesView: View {
    @State private var model: MinutesModel

    public init(app: AppModel) { _model = State(initialValue: MinutesModel(app: app)) }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.md) {
                balances
                if model.app.isPaired {
                    Picker(L("Whose minutes"), selection: $model.showing) {
                        Text(L("You")).tag(MinutesModel.Person.me)
                        Text(model.app.partnerName ?? "").tag(MinutesModel.Person.partner)
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("minutes.person")
                }
                SectionHeader(L("Expiring soon"))
                Card {
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        ExpiryChart(model: model, person: model.showing)
                        Text(model.timelineSummary(model.showing))
                            .textRole(.callout)
                            .foregroundStyle(Color.ink)
                            .accessibilityIdentifier("minutes.timeline")
                        Text(model.balanceLine(model.showing))
                            .textRole(.caption)
                            .foregroundStyle(Color.inkMuted)
                    }
                }
                if model.app.isPaired { resetSection }
                if let message = model.message { NoteBanner(message, tone: .neutral) }
                SectionHeader(L("History"))
                history
            }
            .padding(Spacing.md)
        }
        .pageBackground()
        .navigationTitle(L("Minutes"))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("minutes.screen")
        .task { await model.load() }
        .refreshable { await model.load() }
        .onChange(of: model.app.myMinutes) { _, _ in Task { await model.load() } }
    }

    private var balances: some View {
        HStack(spacing: Spacing.md) {
            Card(tone: .hearth) {
                StatTile(value: (model.app.myMinutes?.balance ?? 0).formatted(), label: L("your minutes"), tint: .hearth)
                    .accessibilityIdentifier("minutes.myBalance")
            }
            if let partner = model.app.partnerMinutes {
                Card(tone: .glow) {
                    StatTile(value: partner.balance.formatted(), label: L("\(model.app.partnerName ?? "")'s minutes"), tint: .glowStrong)
                        .accessibilityIdentifier("minutes.partnerBalance")
                }
            }
        }
    }

    @ViewBuilder private var resetSection: some View {
        SectionHeader(L("Fresh start"))
        Card {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                if let proposal = model.incomingReset {
                    Text(L("\(model.app.partnerName ?? "") suggests resetting both balances to \(MinutesText.short(proposal.standardMinutes)). Everything you both have now, and anything borrowed, is cleared first."))
                        .textRole(.callout)
                        .foregroundStyle(Color.ink)
                        .accessibilityIdentifier("reset.incoming")
                    AsyncButton(L("Reset both")) { await model.respondReset(proposal, accept: true) }
                        .accessibilityIdentifier("reset.accept")
                    AsyncButton(L("Not now"), kind: .secondary) { await model.respondReset(proposal, accept: false) }
                        .accessibilityIdentifier("reset.decline")
                } else if model.outgoingReset != nil {
                    Text(L("Waiting for \(model.app.partnerName ?? "") to agree to the reset. It takes both of you."))
                        .textRole(.callout)
                        .foregroundStyle(Color.inkMuted)
                        .accessibilityIdentifier("reset.waiting")
                } else {
                    Text(L("Reset both balances to \(MinutesText.short(model.standardMinutes)). You both need to agree."))
                        .textRole(.callout)
                        .foregroundStyle(Color.inkMuted)
                    AsyncButton(L("Suggest a reset"), kind: .secondary) { await model.proposeReset() }
                        .disabled(!model.canProposeReset)
                        .accessibilityIdentifier("reset.propose")
                }
            }
        }
    }

    @ViewBuilder private var history: some View {
        if model.ledger.isEmpty {
            Text(L("Your minutes history will appear here."))
                .textRole(.callout)
                .foregroundStyle(Color.inkMuted)
        } else {
            Card {
                LazyVStack(spacing: Spacing.xs) {
                    ForEach(model.ledger) { entry in
                        DSRow(model.title(entry), subtitle: model.date(entry)) {
                            Text(model.amount(entry))
                                .textRole(.callout)
                                .foregroundStyle(entry.minutes >= 0 ? Color.glowStrong : Color.inkMuted)
                                .monospacedDigit()
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("minutes.history")
        }
    }
}

/// Signature moment 5: bars animate in from the baseline, staggered by day.
struct ExpiryChart: View {
    let model: MinutesModel
    let person: MinutesModel.Person
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let buckets = model.buckets(person)
        // Seven columns: at accessibility sizes the days become single letters ("W"), never cut;
        // VoiceOver reads the full day either way.
        let dayStyle: Date.FormatStyle.Symbol.Weekday = typeSize.isAccessibilitySize ? .narrow : .abbreviated
        HStack(alignment: .bottom, spacing: Spacing.xs) {
            ForEach(Array(buckets.enumerated()), id: \.element.id) { index, bucket in
                VStack(spacing: Spacing.xxs) {
                    // Days with nothing expiring keep the row's height but show no number.
                    if bucket.minutes > 0 {
                        Text(bucket.minutes.formatted()).textRole(.caption).foregroundStyle(Color.glowStrong)
                    } else {
                        Text(verbatim: "0").textRole(.caption).hidden()
                    }
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(bucket.minutes > 0 ? (person == .me ? Color.partnerA : Color.partnerB) : Color.surfaceSunken)
                        .frame(height: max(6, 96 * model.fraction(bucket, in: buckets) * (shown || reduceMotion ? 1 : 0)))
                        .opacity(shown ? 1 : (reduceMotion ? 0 : 1))
                        .animation(
                            Motion.resolve(Motion.gentle, reduceMotion: reduceMotion).delay(Motion.stagger(index: index, reduceMotion: reduceMotion)),
                            value: shown
                        )
                    Text(model.dayName(bucket, style: dayStyle))
                        .textRole(.caption)
                        .foregroundStyle(Color.inkMuted)
                        .fixedSize()
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(L("\(model.dayName(bucket)): \(MinutesText.short(bucket.minutes)) expire"))
            }
        }
        .frame(minHeight: 150, alignment: .bottom)
        .onAppear { shown = true }
        .accessibilityIdentifier("minutes.chart")
    }
}
