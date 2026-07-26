import SwiftUI

/// Shows onboarding until complete, then the main tabbed experience.
struct RootView: View {
    @Environment(AppModel.self) private var model
    @State private var showOnboarding = false

    var body: some View {
        TabView {
            DashboardView()
                .tabItem { Label("Today", systemImage: "heart.text.square.fill") }

            InsightsListView()
                .tabItem { Label("Insights", systemImage: "chart.xyaxis.line") }

            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape.fill") }
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
