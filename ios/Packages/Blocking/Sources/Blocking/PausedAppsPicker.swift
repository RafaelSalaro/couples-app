import Core
import DesignSystem
import SwiftUI

/// Lets the user choose what to pause. With Screen Time this is Apple's own picker
/// (the app only ever receives opaque tokens); with the mock it is a simple stand-in list.
public struct PausedAppsPicker: View {
    let service: any BlockingService
    @Binding var selection: PausedAppsSelection?

    public init(service: any BlockingService, selection: Binding<PausedAppsSelection?>) {
        self.service = service
        _selection = selection
    }

    public var body: some View {
        switch service.kind {
        case .mock:
            MockPausedAppsPicker(selection: $selection)
        case .screenTime:
            ScreenTimePausedAppsPicker(selection: $selection)
        }
    }
}

struct MockPausedAppsPicker: View {
    @Binding var selection: PausedAppsSelection?

    private var ids: Set<String> { MockBlockingService.ids(of: selection) }

    private func name(_ item: MockBlockingService.Item) -> String {
        switch item.id {
        case "category.social": L("Social")
        case "category.games": L("Games")
        case "category.entertainment": L("Entertainment")
        case "app.news": L("News app")
        case "app.shopping": L("Shopping app")
        default: L("Social websites")
        }
    }

    var body: some View {
        VStack(spacing: Spacing.xs) {
            ForEach(MockBlockingService.catalog) { item in
                let isOn = ids.contains(item.id)
                Button {
                    var next = ids
                    if isOn { next.remove(item.id) } else { next.insert(item.id) }
                    selection = MockBlockingService.selection(ids: next)
                } label: {
                    DSRow(name(item), systemImage: icon(item.group)) {
                        Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(isOn ? Color.sage : Color.line)
                            .imageScale(.large)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isOn ? [.isSelected] : [])
                .accessibilityIdentifier("picker.\(item.id)")
            }
            // On the sky (onboarding) the sky's muted ink keeps 4.5:1 across the gradient; on paper it is inkMuted.
            SkyReader { ink in
                Text(L("Simulated list. On a real iPhone this is Apple's app picker."))
                    .textRole(.caption)
                    .foregroundStyle(ink.muted)
            }
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func icon(_ group: MockBlockingService.Item.Group) -> String {
        switch group {
        case .category: "square.grid.2x2"
        case .app: "app"
        case .website: "globe"
        }
    }
}
