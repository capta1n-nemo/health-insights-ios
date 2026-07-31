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
            // No .opacity or .scaleEffect on the TabView. Both force the whole
            // four-tab hierarchy — lists, charts and all — through an offscreen
            // buffer for every frame of the transition, which is the last thing
            // a launch that is already fighting for the main thread needs. The
            // splash fading out on top of it *is* the cross-dissolve.

            if model.isLaunching {
                LaunchScreen()
                    .transition(.opacity)
                    .zIndex(1)
            }
        }
        .task {
            if !model.hasCompletedOnboarding { showOnboarding = true }
            // Read the cache first and let the launch screen go the moment it
            // lands. The sync that follows runs behind an app the user can
            // already see — which is where it ran before the launch screen
            // existed, and putting it back in front was the regression.
            await model.hydrate()
            await model.refresh()
        }
        .fullScreenCover(isPresented: $showOnboarding) {
            OnboardingView(isPresented: $showOnboarding)
        }
    }
}
