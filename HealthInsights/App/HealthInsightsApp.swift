import SwiftUI

@main
struct HealthInsightsApp: App {
    @State private var model = AppModel.makeDefault()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .tint(Theme.accent)
        }
    }
}
