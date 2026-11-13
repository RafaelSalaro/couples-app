import SwiftUI
import WidgetKit

@main
struct WidgetsBundle: WidgetBundle {
    var body: some Widget {
        StatusWidget()
    }
}

/// Placeholder widget. Real widgets and the Live Activity arrive with WP-13.
struct StatusWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "status", provider: StatusProvider()) { _ in
            Text("widget.status.placeholder", comment: "Placeholder widget text")
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName(Text("widget.status.name", comment: "Widget gallery name"))
        .description(Text("widget.status.description", comment: "Widget gallery description"))
        .supportedFamilies([.systemSmall])
    }
}

struct StatusEntry: TimelineEntry {
    let date: Date
}

struct StatusProvider: TimelineProvider {
    func placeholder(in context: Context) -> StatusEntry { StatusEntry(date: .now) }

    func getSnapshot(in context: Context, completion: @escaping @Sendable (StatusEntry) -> Void) {
        completion(StatusEntry(date: .now))
    }

    func getTimeline(
        in context: Context,
        completion: @escaping @Sendable (Timeline<StatusEntry>) -> Void
    ) {
        completion(Timeline(entries: [StatusEntry(date: .now)], policy: .never))
    }
}
