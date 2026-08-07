import SwiftUI
import InsightKit

@main
struct HealthInsightsApp: App {
    /// `AppModel.shared`, not a fresh one: an App Intent invoked from Shortcuts
    /// runs outside this view tree and writes through the same model, and two
    /// `AppModel`s would be two `DataStore`s over one file.
    @State private var model = AppModel.shared
    /// The result of a file the OS just handed us, shown as soon as it lands.
    @State private var importOutcome: FileImportOutcome?
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .tint(Theme.accent)
                // One guaranteed diagnostic line per launch. See
                // `DiagnosticsLog.recordLaunch()` — without it the app emits
                // nothing to the unified log until a sync or an import runs,
                // which on the simulator is never, and `simulator.sh logs`
                // cannot be told apart from a broken mirror.
                // Both idempotent, so a scene change re-running this `task`
                // costs nothing. The watchdog is DEBUG-only and compiles to
                // nothing in a release build — see `MainThreadWatchdog`, and
                // backlog `D54` for the reader's "I see so many hangs".
                .task {
                    DiagnosticsLog.shared.recordLaunch()
                    MainThreadWatchdog.start()
                    HangDiagnosticsReporter.shared.start()
                    // Idempotent, like the three above. The delegate is what
                    // makes a notification visible when the app is already
                    // open, which is also the state anybody testing this will
                    // be in.
                    NotificationCentre.shared.configure()
                    await NotificationCentre.shared.refreshAuthorization()
                    // ⚠️ **No permission prompt here.** iOS allows exactly one
                    // ask, and an alert on first launch — before the reader has
                    // seen a single card — is the cheapest possible way to earn
                    // a permanent no. It is asked for from Settings ▸
                    // Notifications, beside the list of what would be sent.
                    BackgroundRefresh.schedule()
                }
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
                // Backgrounding is the moment iOS is most willing to grant a
                // wake-up, and the moment the reader has stopped looking — so
                // it is the one that matters most for the row this was built
                // for. `schedule()` replaces any pending request of the same
                // identifier rather than stacking them.
                .onChange(of: scenePhase) { _, phase in
                    if phase == .background { BackgroundRefresh.schedule() }
                }
        }
        // ⚠️ **This is the registration**, and it has to be attached to the
        // `Scene` rather than called from a `task`: `BGTaskScheduler` requires
        // every identifier to be registered before the app finishes launching,
        // and SwiftUI's `backgroundTask` is what does that here — which is why
        // there is no `UIApplicationDelegate` in this app and does not need to
        // be one. The identifier must appear in `Info.plist`'s
        // `BGTaskSchedulerPermittedIdentifiers`, or this silently never fires.
        .backgroundTask(.appRefresh(BackgroundRefresh.taskIdentifier)) {
            await BackgroundRefresh.run()
        }
    }
}

/// What an import attempt produced, in the reader's terms.
struct FileImportOutcome: Identifiable {
    let id = UUID()
    let message: String
}
