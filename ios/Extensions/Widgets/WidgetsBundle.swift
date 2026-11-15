import ActivityKit
import Core
import DesignSystem
import SwiftUI
import WidgetKit

func L(_ key: String.LocalizationValue) -> String { String(localized: key) }

@main
struct WidgetsBundle: WidgetBundle {
    init() { Typography.registerFonts() }

    var body: some Widget {
        TonightWidget()
        TogetherWidget()
        TimeLeftWidget()
        UnlockLiveActivity()
    }
}

// MARK: - Shared timeline

/// What the widgets show: the App Group state at one moment.
struct GlanceEntry: TimelineEntry {
    let date: Date
    let state: SharedState

    var phase: SharedState.Phase { state.phase(at: date) }
    var isOn: Bool { state.protectionConfigured }
}

/// Reads the App Group state and schedules a refresh at each moment the phase changes
/// (protected time starting or ending, an unlock ending), so widgets stay right without the app.
struct GlanceProvider: TimelineProvider {
    func placeholder(in context: Context) -> GlanceEntry {
        var state = SharedState()
        state.schedules = [.standard()]
        state.protectionConfigured = true
        state.myBalance = 30
        state.partnerBalance = 30
        state.partnerName = "Ana"
        state.streak = 4
        return GlanceEntry(date: .now, state: state)
    }

    func getSnapshot(in context: Context, completion: @escaping @Sendable (GlanceEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : GlanceEntry(date: .now, state: AppGroupStateStore().load()))
    }

    func getTimeline(in context: Context, completion: @escaping @Sendable (Timeline<GlanceEntry>) -> Void) {
        let state = AppGroupStateStore().load()
        let now = Date()
        let dates = [now] + state.phaseChanges(after: now, limit: 6)
        completion(Timeline(entries: dates.map { GlanceEntry(date: $0, state: state) }, policy: .atEnd))
    }
}

/// The status line shared by every widget: "Protected time", a live countdown, or when it starts.
struct GlanceStatus: View {
    let entry: GlanceEntry
    var compact = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            switch entry.isOn ? entry.phase : .open(next: nil) {
            case .protected(let until):
                Text(L("Protected time")).font(Typography.widgetFont(.caption)).opacity(0.8)
                Text(timerInterval: entry.date...max(until, entry.date), countsDown: true)
                    .font(Typography.widgetFont(.numeral, size: compact ? 22 : 30))
                    .monospacedDigit()
                    .accessibilityLabel(L("Protected time ends at \(until.formatted(date: .omitted, time: .shortened))"))
            case .unlocked(let until):
                Text(L("Unlocked")).font(Typography.widgetFont(.caption)).opacity(0.8)
                Text(timerInterval: entry.date...max(until, entry.date), countsDown: true)
                    .font(Typography.widgetFont(.numeral, size: compact ? 22 : 30))
                    .monospacedDigit()
                    .accessibilityLabel(L("Unlocked until \(until.formatted(date: .omitted, time: .shortened))"))
            case .open(let next):
                if let next, entry.isOn {
                    Text(L("Protected time starts")).font(Typography.widgetFont(.caption)).opacity(0.8)
                    Text(next, style: .time).font(Typography.widgetFont(.numeral, size: compact ? 22 : 30))
                } else {
                    Text(L("Protected time")).font(Typography.widgetFont(.caption)).opacity(0.8)
                    Text(L("Off")).font(Typography.widgetFont(.numeral, size: compact ? 22 : 30))
                }
            }
        }
    }
}

/// The sky behind a widget, matching the home scene.
struct WidgetSky: View {
    let entry: GlanceEntry
    @Environment(\.colorScheme) private var scheme

    var moment: SkyMoment {
        guard entry.isOn else { return .daylight }
        switch entry.phase {
        case .protected: return .dusk
        case .unlocked: return .goldenHour
        case .open(let next): return (next.map { $0.timeIntervalSince(entry.date) <= 90 * 60 } ?? false) ? .goldenHour : .daylight
        }
    }

    var palette: SkyPalette { SkyPalette.make(moment, scheme: scheme) }

    var body: some View {
        LinearGradient(colors: palette.stops.map { Color(uiColor: UIColor(hex: $0)) }, startPoint: .top, endPoint: .bottom)
    }
}

// MARK: - Small: protected-time status and your balance

struct TonightWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "tonight", provider: GlanceProvider()) { entry in
            TonightWidgetView(entry: entry)
        }
        .configurationDisplayName(Text(L("Tonight")))
        .description(Text(L("Protected time and your minutes.")))
        .supportedFamilies([.systemSmall])
    }
}

struct TonightWidgetView: View {
    let entry: GlanceEntry
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let sky = WidgetSky(entry: entry)
        VStack(alignment: .leading, spacing: 6) {
            GlanceStatus(entry: entry)
            Spacer(minLength: 0)
            HStack(spacing: 6) {
                LightDisc(.me, diameter: 34, glow: 0) {
                    Text((entry.state.myBalance ?? 0).formatted()).font(Typography.widgetFont(.heading, size: 14))
                }
                Text(L("your minutes")).font(Typography.widgetFont(.caption)).opacity(0.85)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(L("Your minutes: \((entry.state.myBalance ?? 0).formatted())"))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .foregroundStyle(sky.palette.foregroundColor)
        .containerBackground(for: .widget) { sky }
    }
}

// MARK: - Medium: both balances and the streak

struct TogetherWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "together", provider: GlanceProvider()) { entry in
            TogetherWidgetView(entry: entry)
        }
        .configurationDisplayName(Text(L("The two of you")))
        .description(Text(L("Both balances and your shared streak.")))
        .supportedFamilies([.systemMedium])
    }
}

struct TogetherWidgetView: View {
    let entry: GlanceEntry

    private func light(_ tone: LightTone, _ name: String, _ minutes: Int?) -> some View {
        LightDisc(tone, diameter: 70, glow: 0) {
            VStack(spacing: -2) {
                Text(name).font(Typography.widgetFont(.caption, size: 10)).lineLimit(1).minimumScaleFactor(0.7)
                Text((minutes ?? 0).formatted()).font(Typography.widgetFont(.numeral, size: 24))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L("\(name): \((minutes ?? 0).formatted()) minutes"))
    }

    var body: some View {
        let sky = WidgetSky(entry: entry)
        HStack(spacing: 12) {
            HStack(spacing: -10) {
                // The two lights are always the same size.
                light(.me, L("You"), entry.state.myBalance)
                light(.partner, entry.state.partnerName ?? L("Partner"), entry.state.partnerBalance)
            }
            VStack(alignment: .leading, spacing: 6) {
                GlanceStatus(entry: entry, compact: true)
                if let streak = entry.state.streak {
                    Text(streak > 0 ? L("\(streak.formatted()) evenings in a row") : L("New streak starts today."))
                        .font(Typography.widgetFont(.caption))
                        .opacity(0.85)
                }
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(sky.palette.foregroundColor)
        .containerBackground(for: .widget) { sky }
    }
}

// MARK: - Lock screen: time left in protected time or in an unlock

struct TimeLeftWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "timeleft", provider: GlanceProvider()) { entry in
            GlanceStatus(entry: entry, compact: true)
                .containerBackground(for: .widget) { Color.clear }
        }
        .configurationDisplayName(Text(L("Time left")))
        .description(Text(L("Time left in protected time or in an unlock.")))
        .supportedFamilies([.accessoryRectangular, .accessoryInline])
    }
}

// MARK: - Live Activity: unlock countdown

struct UnlockLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: UnlockActivityAttributes.self) { context in
            // Lock screen and banner.
            HStack(spacing: 14) {
                TwoLights(closeness: 1, diameter: 34, overlap: 0.45, glow: 0)
                    .frame(width: 60, height: 34)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(context.isStale ? L("Protected time is back") : L("Unlocked"))
                        .font(Typography.widgetFont(.caption))
                        .opacity(0.8)
                    if context.isStale {
                        Text(L("Enjoy your evening.")).font(Typography.widgetFont(.heading))
                    } else {
                        Text(timerInterval: context.state.startedAt...context.state.endsAt, countsDown: true)
                            .font(Typography.widgetFont(.numeral, size: 30))
                            .monospacedDigit()
                    }
                }
                Spacer()
                if !context.isStale {
                    ProgressView(timerInterval: context.state.startedAt...context.state.endsAt, countsDown: true) { EmptyView() } currentValueLabel: { EmptyView() }
                        .progressViewStyle(.circular)
                        .tint(Color(uiColor: UIColor(hex: ColorToken.glow.dark)))
                        .frame(width: 36, height: 36)
                }
            }
            .padding(16)
            .foregroundStyle(Color(uiColor: UIColor(hex: ColorToken.onDusk.dark)))
            .activityBackgroundTint(Color(uiColor: UIColor(hex: ColorToken.dusk.dark)))
            .activitySystemActionForegroundColor(Color(uiColor: UIColor(hex: ColorToken.onDusk.dark)))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    TwoLights(closeness: 1, diameter: 26, overlap: 0.45, glow: 0).frame(width: 46, height: 26)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(timerInterval: context.state.startedAt...context.state.endsAt, countsDown: true)
                        .font(Typography.widgetFont(.numeral, size: 24))
                        .monospacedDigit()
                        .frame(maxWidth: 90)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text(L("Unlocked. Protected time comes back on its own.")).font(Typography.widgetFont(.caption))
                }
            } compactLeading: {
                TwoLights(closeness: 1, diameter: 14, overlap: 0.45, glow: 0).frame(width: 24, height: 14)
            } compactTrailing: {
                Text(timerInterval: context.state.startedAt...context.state.endsAt, countsDown: true)
                    .monospacedDigit()
                    .frame(maxWidth: 52)
            } minimal: {
                TwoLights(closeness: 1, diameter: 12, overlap: 0.45, glow: 0).frame(width: 20, height: 12)
            }
        }
    }
}
