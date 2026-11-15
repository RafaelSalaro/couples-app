import Blocking
import Core
import DesignSystem
import FeatureSupport
import SwiftUI

public struct ReportsView: View {
    @State private var model: ReportsModel

    public init(app: AppModel) { _model = State(initialValue: ReportsModel(app: app)) }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.md) {
                if let report = model.shown {
                    Text(model.weekTitle(report))
                        .textRole(.display)
                        .foregroundStyle(Color.ink)
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityIdentifier("report.week")
                    ForEach(model.highlights(report), id: \.self) { line in
                        NoteBanner(line, systemImage: "sparkles", tone: .celebrate).accessibilityIdentifier("report.highlight")
                    }
                    together(report)
                    sideBySide(report)
                } else if model.loaded {
                    Text(model.app.isPaired
                        ? L("Your first week together will show up here on Sunday evening.")
                        : L("Your week together appears here once you and your partner are paired."))
                        .textRole(.body)
                        .foregroundStyle(Color.inkMuted)
                        .accessibilityIdentifier("report.empty")
                }
                history
                SectionHeader(L("Only on your phone"))
                // Apple's Screen Time usage for your paused apps: never sent to us or to your partner.
                PrivateUsageReport(service: model.app.deps.blocking)
            }
            .padding(Spacing.md)
        }
        .pageBackground()
        .navigationTitle(L("Our week"))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("report.screen")
        .task { await model.load() }
        .refreshable { await model.load() }
    }

    private func together(_ report: WeeklyReport) -> some View {
        Card(tone: .sage) {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text(L("Together")).textRole(.label).foregroundStyle(Color.sage)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), alignment: .leading)], alignment: .leading, spacing: Spacing.sm) {
                    ForEach(model.combined(report), id: \.title) { item in
                        StatTile(value: item.value, label: item.title, tint: .sage)
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("report.together")
    }

    private func sideBySide(_ report: WeeklyReport) -> some View {
        Card {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                HStack {
                    Label { Text(L("You")).textRole(.label) } icon: { LightDisc(.me, diameter: 14, glow: 0) }
                    Spacer()
                    Label { Text(model.app.partnerName ?? "").textRole(.label) } icon: { LightDisc(.partner, diameter: 14, glow: 0) }
                }
                .foregroundStyle(Color.inkMuted)
                ForEach(model.rows(report)) { row in
                    VStack(spacing: Spacing.xxs) {
                        HStack {
                            Text(model.value(row, mine: true)).textRole(.heading).foregroundStyle(Color.hearth)
                            Spacer()
                            Text(row.title).textRole(.caption).foregroundStyle(Color.inkMuted)
                            Spacer()
                            Text(model.value(row, mine: false)).textRole(.heading).foregroundStyle(Color.glowStrong)
                        }
                        if model.isPremium {
                            // Charts are premium: each line as the two lights' share.
                            GeometryReader { proxy in
                                HStack(spacing: 2) {
                                    Capsule().fill(Color.partnerA).frame(width: max(4, (proxy.size.width - 2) * model.share(row)))
                                    Capsule().fill(Color.partnerB)
                                }
                            }
                            .frame(height: 6)
                            .accessibilityHidden(true)
                        }
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(L("\(row.title). You: \(model.value(row, mine: true)). \(model.app.partnerName ?? ""): \(model.value(row, mine: false))."))
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("report.rows")
    }

    @ViewBuilder private var history: some View {
        if model.isPremium, !model.history.isEmpty {
            SectionHeader(L("Earlier weeks"))
            Card {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    HStack(alignment: .bottom, spacing: Spacing.xs) {
                        ForEach(model.trend, id: \.week.weekStart) { item in
                            Button {
                                Haptics.tick()
                                model.selectedWeek = item.week.weekStart
                            } label: {
                                VStack(spacing: Spacing.xxs) {
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .fill(item.week.weekStart == model.shown?.weekStart ? Color.glow : Color.glowSoft)
                                        .frame(height: max(8, 80 * item.fraction))
                                    Text(item.week.totalEarnedTogether.formatted()).textRole(.caption).foregroundStyle(Color.inkMuted)
                                }
                                .frame(maxWidth: .infinity, minHeight: Sizing.minTouchTarget, alignment: .bottom)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(L("\(model.weekTitle(item.week)): \(MinutesText.short(item.week.totalEarnedTogether)) earned together"))
                            .accessibilityIdentifier("report.history.bar")
                        }
                    }
                    Text(L("Minutes earned together, week by week. Tap a week to see it."))
                        .textRole(.caption)
                        .foregroundStyle(Color.inkMuted)
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("report.history")
        } else if model.hasLockedHistory, model.current != nil {
            Button {
                model.app.sheet = .paywall
            } label: {
                Card(tone: .sunken) {
                    DSRow(L("Earlier weeks, charts and highlights"), subtitle: L("Part of premium. One price for both of you."), systemImage: "chart.bar") {
                        Image(systemName: "chevron.right").foregroundStyle(Color.inkMuted)
                    }
                }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("report.premium")
        }
    }
}
