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
                    // A Shortcuts automation handing over readings the app
                    // cannot collect for itself. Checked before the file guard
                    // because it is a custom-scheme URL, not a file.
                    if ShortcutIngest.handles(url) {
                        if let message = model.ingestShortcut(url) {
                            importOutcome = FileImportOutcome(message: message)
                        }
                        return
                    }
                    guard url.isFileURL else { return }
                    Task {
                        importOutcome = FileImportOutcome(
                            message: await model.importSharedFile(at: url))
                    }
                }
                // The wait is visible now. Reading, parsing and re-scoring
                // several hundred readings takes seconds, and without this the
                // app looked frozen until the result alert appeared.
                .overlay { if model.isImporting { ImportProgressOverlay() } }
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
