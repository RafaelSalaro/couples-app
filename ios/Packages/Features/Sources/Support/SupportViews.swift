import Core
import DesignSystem
import SwiftUI

/// A button that runs async work, shows progress while it runs and reports a friendly message if it fails.
public struct AsyncButton<Label: View>: View {
    let kind: ButtonKind
    let fullWidth: Bool
    let action: () async throws -> Void
    let onError: (String) -> Void
    let label: Label
    @State private var isRunning = false

    public init(
        kind: ButtonKind = .primary, fullWidth: Bool = true,
        action: @escaping () async throws -> Void,
        onError: @escaping (String) -> Void = { _ in },
        @ViewBuilder label: () -> Label
    ) {
        self.kind = kind
        self.fullWidth = fullWidth
        self.action = action
        self.onError = onError
        self.label = label()
    }

    public var body: some View {
        Button {
            guard !isRunning else { return }
            isRunning = true
            Task {
                do { try await action() } catch is CancellationError {} catch { onError(Friendly.message(for: error)) }
                isRunning = false
            }
        } label: {
            ZStack {
                label.opacity(isRunning ? 0 : 1)
                if isRunning { ProgressView().tint(kind == .primary ? Color.onHearth : Color.ink) }
            }
        }
        .buttonStyle(.ds(kind, fullWidth: fullWidth))
        .disabled(isRunning)
    }
}

public extension AsyncButton where Label == Text {
    init(
        _ title: String, kind: ButtonKind = .primary, fullWidth: Bool = true,
        action: @escaping () async throws -> Void, onError: @escaping (String) -> Void = { _ in }
    ) {
        self.init(kind: kind, fullWidth: fullWidth, action: action, onError: onError) { Text(title) }
    }
}

/// A full-screen step: scrolling content with the actions pinned at the bottom. Reflows at large text sizes.
/// A centred moment (welcome, ready): centred while it fits, scrolling when it does not (the
/// largest text sizes), with the action kept below. Text is never cut off.
public struct CenteredScaffold<Content: View, Actions: View>: View {
    let content: Content
    let actions: Actions

    public init(@ViewBuilder content: () -> Content, @ViewBuilder actions: () -> Actions) {
        self.content = content()
        self.actions = actions()
    }

    @Environment(\.dynamicTypeSize) private var typeSize

    public var body: some View {
        let pinned = !typeSize.isAccessibilitySize
        VStack(spacing: 0) {
            GeometryReader { proxy in
                ScrollView {
                    VStack(spacing: Spacing.lg) {
                        content
                        if !pinned { VStack(spacing: Spacing.xs) { actions } }
                    }
                    .padding(Spacing.lg)
                    .frame(maxWidth: .infinity, minHeight: proxy.size.height)
                }
                .scrollBounceBehavior(.basedOnSize)
            }
            if pinned {
                VStack(spacing: Spacing.xs) { actions }
                    .padding(.horizontal, Spacing.lg)
                    .padding(.bottom, Spacing.lg)
            }
        }
    }
}

public struct StepScaffold<Content: View, Actions: View>: View {
    let title: String
    let subtitle: String?
    let content: Content
    let actions: Actions

    public init(title: String, subtitle: String? = nil, @ViewBuilder content: () -> Content, @ViewBuilder actions: () -> Actions) {
        self.title = title
        self.subtitle = subtitle
        self.content = content()
        self.actions = actions()
    }

    @Environment(\.dynamicTypeSize) private var typeSize

    public var body: some View {
        // The actions sit below the scrolling content; at accessibility sizes they would take
        // most of the screen and be cut off, so they scroll with the content instead.
        let pinned = !typeSize.isAccessibilitySize
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    SkyText(title, role: .title).accessibilityAddTraits(.isHeader)
                    if let subtitle { SkyText(subtitle, role: .body, muted: true) }
                    content
                    if !pinned {
                        VStack(spacing: Spacing.xs) { actions }.padding(.top, Spacing.md)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Spacing.lg)
            }
            if pinned {
                VStack(spacing: Spacing.xs) { actions }
                    .padding(.horizontal, Spacing.lg)
                    .padding(.vertical, Spacing.sm)
            }
        }
    }
}

/// Which sky the home scene and its sheets sit under, from protected time and the clock.
public enum SkyChoice {
    /// Dusk during protected time, golden hour during an unlock or in the hour and a half before
    /// protected time, daylight otherwise.
    public static func moment(for phase: SharedState.Phase, now: Date) -> SkyMoment {
        switch phase {
        case .protected: return .dusk
        case .unlocked: return .goldenHour
        case .open(let next):
            guard let next else { return .daylight }
            return next.timeIntervalSince(now) <= 90 * 60 ? .goldenHour : .daylight
        }
    }
}

/// Start and end time pickers for protected time, with a plain-language summary.
public struct ScheduleTimesEditor: View {
    @Binding var schedule: ProtectedSchedule

    public init(schedule: Binding<ProtectedSchedule>) { _schedule = schedule }

    private func binding(_ keyPath: WritableKeyPath<ProtectedSchedule, LocalTime>) -> Binding<Date> {
        Binding(
            get: { ScheduleText.date(for: schedule[keyPath: keyPath]) },
            set: { schedule[keyPath: keyPath] = ScheduleText.localTime(from: $0) }
        )
    }

    public var body: some View {
        Card {
            VStack(spacing: Spacing.sm) {
                DatePicker(L("Starts"), selection: binding(\.startLocal), displayedComponents: .hourAndMinute)
                    .accessibilityIdentifier("schedule.start")
                Divider().overlay(Color.line)
                DatePicker(L("Ends"), selection: binding(\.endLocal), displayedComponents: .hourAndMinute)
                    .accessibilityIdentifier("schedule.end")
                if schedule.crossesMidnight {
                    Text(L("Runs overnight, so late-night scrolling is paused too."))
                        .textRole(.caption)
                        .foregroundStyle(Color.inkMuted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .textRole(.body)
            .foregroundStyle(Color.ink)
            .tint(Color.hearth)
        }
    }
}

/// Wording for schedules.
public enum ScheduleText {
    static let calendar = Calendar(identifier: .gregorian)

    public static func date(for time: LocalTime) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 1, day: 1, hour: time.hour, minute: time.minute)) ?? Date()
    }

    public static func localTime(from date: Date) -> LocalTime {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return LocalTime(hour: parts.hour ?? 0, minute: parts.minute ?? 0)
    }

    /// "6:00 PM" in the user's locale.
    public static func time(_ time: LocalTime, locale: Locale = .current) -> String {
        var style = Date.FormatStyle(date: .omitted, time: .shortened)
        style.locale = locale
        style.timeZone = calendar.timeZone
        style.calendar = calendar
        return date(for: time).formatted(style)
    }

    /// "6:00 PM – 9:00 AM"
    public static func range(_ schedule: ProtectedSchedule, locale: Locale = .current) -> String {
        "\(time(schedule.startLocal, locale: locale)) – \(time(schedule.endLocal, locale: locale))"
    }

    /// "Every day", "Weekdays", "Weekends" or "Mon, Wed, Fri".
    public static func days(_ weekdays: Set<Int>, locale: Locale = .current) -> String {
        if weekdays == Set(1...7) { return L("Every day") }
        if weekdays == Set(1...5) { return L("Weekdays") }
        if weekdays == [6, 7] { return L("Weekends") }
        return weekdays.sorted().map { shortWeekday($0, locale: locale) }.joined(separator: ", ")
    }

    /// Short weekday name for an ISO weekday (1 = Monday).
    public static func shortWeekday(_ iso: Int, locale: Locale = .current) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = locale
        return calendar.shortWeekdaySymbols[iso % 7]
    }

    /// A clock time for a moment ("6:00 PM"), in the given zone.
    public static func clock(_ date: Date, timeZone: TimeZone = .current, locale: Locale = .current) -> String {
        var style = Date.FormatStyle(date: .omitted, time: .shortened)
        style.locale = locale
        style.timeZone = timeZone
        return date.formatted(style)
    }
}

/// Minutes wording: "30 min".
public enum MinutesText {
    public static func short(_ minutes: Int) -> String { L("\(minutes.formatted()) min") }
}

/// Shows `model.notice` once as a calm banner at the top.
public struct NoticeOverlay: ViewModifier {
    @Binding var notice: String?

    public func body(content: Content) -> some View {
        content.overlay(alignment: .top) {
            if let notice {
                NoteBanner(notice, systemImage: "info.circle", tone: .neutral)
                    .padding(Spacing.md)
                    .warmShadow()
                    .moveOrFade(from: .top)
                    .accessibilityIdentifier("notice")
                    .onTapGesture { self.notice = nil }
                    .task(id: notice) {
                        try? await Task.sleep(for: .seconds(6))
                        if !Task.isCancelled { self.notice = nil }
                    }
            }
        }
        .motion(value: notice)
    }
}

public extension View {
    func noticeOverlay(_ notice: Binding<String?>) -> some View { modifier(NoticeOverlay(notice: notice)) }
}
