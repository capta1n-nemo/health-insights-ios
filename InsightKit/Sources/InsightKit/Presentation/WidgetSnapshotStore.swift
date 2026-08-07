import Foundation

/// **The one file the app writes and a widget reads.**
///
/// Backlog `D8`. Deliberately a plain JSON file in a directory rather than
/// `UserDefaults(suiteName:)`: a file is the same code path on Linux, so the
/// round trip is covered by `swift test` — which is this repo's actual gate —
/// and `UserDefaults(suiteName:)` is the one API here that *silently succeeds*
/// without the entitlement. It returns a live object, accepts every write, and
/// hands the extension nothing, which is a failure mode that looks like working
/// software. ``sharedContainer`` returning `nil` is a fact you can act on.
///
/// ## ⚠️ The shared container does not exist yet, and this is not an oversight
///
/// A widget extension and its containing app are separate sandboxes. The
/// **only** way to pass a file between them is an App Group, and App Groups are
/// not among the capabilities a free personal Apple team can sign — the same
/// wall `ShotsyImportAction` hit on 2026-08-02, verbatim in
/// `docs/deployment.md`:
///
/// ```
/// Provisioning profile "iOS Team Provisioning Profile: com.jasonsalway.healthinsights"
///   doesn't include the App Groups capability
/// ```
///
/// So ``resolve()`` falls back to the app's **own** container. That is not a
/// pretend shared container: it is a real, working store that the app writes
/// and the in-app widget preview reads, which is what makes the pipeline
/// exercisable today. The day the entitlement exists, the group path is picked
/// up with no code change and the extension starts reading the same file.
public struct WidgetSnapshotStore: Sendable {

    /// The identifier the entitlement will use when it exists. Named here, once,
    /// so the entitlements file, the extension and this store cannot drift.
    public static let appGroupIdentifier = "group.com.jasonsalway.healthinsights"

    /// Where the snapshot file lives.
    public let directory: URL

    /// One file, overwritten. There is no history here on purpose — a widget
    /// shows now, and a stack of yesterdays in a shared container is health data
    /// sitting somewhere nothing prunes it.
    public var fileURL: URL { directory.appendingPathComponent("widget-snapshot.json") }

    public init(directory: URL) {
        self.directory = directory
    }

    /// The App Group container, or `nil` when the entitlement is absent.
    ///
    /// `nil` is the expected answer on every build shipped so far. Callers must
    /// treat it as "the widget cannot see anything I write", never as an error
    /// to log and move past.
    /// ⚠️ **Resolved once per process, not per call.** Asking for a container
    /// the app is not entitled to makes the OS log
    /// `container_create_or_lookup_app_group_path_by_app_group_identifier:
    /// client is not entitled` — and this is asked after *every* evaluation, so
    /// a computed property put that line in the reader's console dozens of times
    /// a session. Found in the app-target test log on 2026-08-07, where it is
    /// merely noise; on a phone it is noise in the one place a real fault would
    /// have to be spotted. The answer cannot change while the process lives: an
    /// entitlement is fixed at launch.
    private static let resolvedSharedContainer: URL? = {
        #if canImport(Darwin)
        return FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier)
        #else
        return nil
        #endif
    }()

    public static var sharedContainer: URL? { resolvedSharedContainer }

    /// `true` when a widget extension could actually read what the app writes.
    public static var isVisibleToWidgets: Bool { sharedContainer != nil }

    /// The store to use: the shared container when it exists, the app's own
    /// Application Support directory otherwise.
    public static func resolve(fallback: URL? = nil) -> WidgetSnapshotStore? {
        if let shared = sharedContainer { return WidgetSnapshotStore(directory: shared) }
        if let fallback { return WidgetSnapshotStore(directory: fallback) }
        guard let support = try? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true) else { return nil }
        return WidgetSnapshotStore(directory: support)
    }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    /// Write, replacing whatever was there.
    public func write(_ snapshot: WidgetSnapshot) throws {
        try FileManager.default.createDirectory(at: directory,
                                                withIntermediateDirectories: true)
        let data = try Self.encoder.encode(snapshot)
        try data.write(to: fileURL, options: .atomic)
    }

    /// Read the last snapshot, or `nil`.
    ///
    /// **Every failure is `nil`, including a schema mismatch and a corrupt
    /// file.** A widget's honest response to "I cannot read this" is its
    /// placeholder, and a thrown error at this boundary would only ever be
    /// swallowed by a timeline provider that must return *something*.
    public func read() -> WidgetSnapshot? {
        guard let data = try? Data(contentsOf: fileURL),
              let snapshot = try? Self.decoder.decode(WidgetSnapshot.self, from: data),
              snapshot.isReadable else { return nil }
        return snapshot
    }

    /// Remove it. Used when the reader disconnects everything, and by tests.
    public func clear() {
        try? FileManager.default.removeItem(at: fileURL)
    }
}
