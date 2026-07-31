import SwiftUI

/// Shows onboarding until complete, then the main tabbed experience.
struct RootView: View {
    @Environment(AppModel.self) private var model
    @State private var showOnboarding = false

    var body: some View {
        ZStack {
            TabView {
                TodayView()
                    .tabItem { Label("Today", systemImage: "sun.max.fill") }

                VitalsView()
                    .tabItem { Label("Vitals", systemImage: "waveform.path.ecg") }

                InsightsListView()
                    .tabItem { Label("Insights", systemImage: "chart.xyaxis.line") }

                SettingsView()
                    .tabItem { Label("Settings", systemImage: "gearshape.fill") }
            }
            // The other half of the cross-dissolve. Both sides move on the one
            // animation in `LaunchScreen.narrate()`, so the tabs arrive as the
            // pulse leaves rather than being cut to. The scale is small on
            // purpose: enough to read as settling into place, not as a zoom.
            .opacity(model.isLaunching ? 0 : 1)
            .scaleEffect(model.isLaunching ? 0.97 : 1)

            if model.isLaunching {
                LaunchScreen()
                    .transition(.opacity)
                    .zIndex(1)
            }
        }
        .task {
            if !model.hasCompletedOnboarding { showOnboarding = true }
            await model.refresh()
        }
        .fullScreenCover(isPresented: $showOnboarding) {
            OnboardingView(isPresented: $showOnboarding)
        }
    }
}
