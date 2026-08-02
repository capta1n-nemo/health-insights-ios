import SwiftUI

@main
struct HealthInsightsApp: App {
    @State private var model = AppModel.makeDefault()
    /// The result of a file the OS just handed us, shown as soon as it lands.
    @State private var importOutcome: FileImportOutcome?

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .tint(Theme.accent)
                // The share-sheet and "Open With" entry point. A shared file
                // arrives as a URL the OS opens the app with, so this is the
                // only hook that sees it — there is no callback and nothing to
                // poll.
                .onOpenURL { url in
                    // The OAuth redirect comes through the same door. It is a
                    // custom scheme rather than a file, and handing it to the
                    // importer would try to read "healthinsights://…" as JSON.
                    guard url.isFileURL else { return }
                    importOutcome = FileImportOutcome(message: model.importSharedFile(at: url))
                }
                .alert("Import", isPresented: Binding(
                    get: { importOutcome != nil },
                    set: { if !$0 { importOutcome = nil } }
                ), presenting: importOutcome) { _ in
                    Button("OK") { importOutcome = nil }
                } message: { outcome in
                    Text(outcome.message)
                }
        }
    }
}

/// What an import attempt produced, in the reader's terms.
struct FileImportOutcome: Identifiable {
    let id = UUID()
    let message: String
}
