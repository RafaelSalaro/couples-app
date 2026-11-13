import SwiftUI
import DesignSystem

@main
struct CouplesApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}

/// Placeholder root. Replaced by the onboarding and home flows in later work packages.
struct RootView: View {
    var body: some View {
        VStack(spacing: 12) {
            Text(AppBrand.displayName)
                .font(.largeTitle.weight(.semibold))
            Text("root.tagline", comment: "Philosophy line on the placeholder root screen")
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
        .padding()
    }
}

#Preview {
    RootView()
}
