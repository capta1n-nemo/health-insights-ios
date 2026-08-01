import SwiftUI
import InsightKit

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
        // One quiet answer to "did my tap do anything?", visible from every
        // tab while a background sync or summary pass is running. The launch
        // screen owns the launch narration; this covers everything after it —
        // pull-to-refresh, the post-launch sync, a rebuild. Top edge, because
        // the bottom already carries the tab bar and the cards' floating
        // timeframe control.
        .overlay(alignment: .top) {
            if model.isSyncing && !model.isLaunching {
                SyncActivityPill(phase: model.launchPhase)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: model.isSyncing)
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

/// A small floating capsule naming the background work in progress.
///
/// Exists because a sync used to be visible only as a spinner on the Today
/// card: from any other tab the app was doing invisible work, and a slow
/// screen read as a hang. Non-interactive on purpose — it reports, it never
/// blocks a tap.
private struct SyncActivityPill: View {
    let phase: LaunchPhase

    private var label: String {
        switch phase {
        case .reading: return "Reading your history…"
        case .connecting: return "Syncing your devices…"
        case .summarising: return "Writing your summary…"
        case .ready: return "Finishing up…"
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
            Text(label)
                .font(.caption.weight(.medium))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(.quaternary, lineWidth: 0.5))
        .padding(.top, 4)
        .allowsHitTesting(false)
        .accessibilityLabel(label)
    }
}
