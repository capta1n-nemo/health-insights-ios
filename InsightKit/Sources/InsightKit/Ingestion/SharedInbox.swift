import Foundation

/// The hand-off between the share-sheet **action** and the app.
///
/// ## Why a staging directory and not a direct import
///
/// The app row at the top of the share sheet was solved by declaring the type
/// (`UTImportedTypeDeclarations`, 2026-08-02) — the OS launches the app and
/// hands it the file. The **bottom row is a different mechanism**: it lists
/// *Action Extensions*, which run in their own process, with their own sandbox
/// and no way to reach the app's SwiftData store. The user asked for that row
/// specifically: *"why is it not in the bottom like other 3 apps that support
/// actions, I want an action."*
///
/// So the extension does the only thing it can do well: copy the bytes
/// somewhere both processes can see, and say so. The app drains that directory
/// on launch and on every return to the foreground, running the same
/// `ShotsyImport` path a directly-shared file takes. One importer, two doors.
///
/// **That shared place is an App Group container, and there is no alternative.**
/// An extension cannot write into its containing app's container, and 84 KB of
/// JSON does not fit in a URL. It is worth knowing that App Groups are not
/// available to free personal development teams — if signing ever fails with
/// that complaint, the extension is the thing to drop, not something to work
/// around.
///
/// Everything that can be decided without a container is decided here, in the
/// Linux-buildable half, so it is tested rather than eyeballed: the directory
/// name, the staged file name, and which files count as pending.
public enum SharedInbox {

    /// The container both targets share. Declared once, here, because it has to
    /// match in two entitlements files and two bundles, and a typo would be a
    /// silently empty inbox rather than an error.
    public static let appGroupIdentifier = "group.com.jasonsalway.healthinsights"

    /// Subdirectory inside the container. A named folder rather than the root:
    /// the container is shared with anything else that ever needs it, and a
    /// drain that deletes what it reads must be certain of what it owns.
    public static let directoryName = "ShotsyInbox"

    /// The extension writes this, the app reads it back, and it is the only
    /// contract between them.
    ///
    /// Prefixed with a sortable timestamp so two files shared in one minute
    /// drain oldest-first, and suffixed with a short random component so two
    /// shared in the same *second* cannot collide. The original name is kept —
    /// stripped to something a filesystem is happy with — because it is what
    /// the reader will see in a diagnostic.
    public static func stagedFileName(original: String, at date: Date,
                                      salt: String = UUID().uuidString) -> String {
        let stamp = Int(date.timeIntervalSince1970)
        let cleaned = sanitised(original)
        return "\(stamp)-\(salt.prefix(8))-\(cleaned)"
    }

    /// Keep it to characters no filesystem or shell argues about, and keep the
    /// extension, since that is what identifies the file to the importer.
    static func sanitised(_ name: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: ".-_"))
        let mapped = String(name.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" })
        // Dots as well as dashes, and at both ends: a name left starting with
        // a dot is a hidden file, and `ordered` skips those — so a traversal
        // attempt would have staged a file the app then refused to see.
        let trimmed = mapped.trimmingCharacters(in: CharacterSet(charactersIn: "-."))
        // An empty or all-punctuation name still has to produce something the
        // importer will recognise as a Shotsy backup.
        return trimmed.isEmpty ? "shared.shotsyjson" : String(trimmed.suffix(80))
    }

    /// Files in a drained listing, oldest first.
    ///
    /// Sorted by the name's own timestamp prefix rather than by a filesystem
    /// date: the extension chose the order when it wrote them, and a copy's
    /// modification date is not reliably the order they arrived in.
    public static func ordered(_ names: [String]) -> [String] {
        names.filter { !$0.hasPrefix(".") }
            .sorted { leading(of: $0) < leading(of: $1) }
    }

    private static func leading(of name: String) -> Int {
        Int(name.prefix(while: \.isNumber)) ?? 0
    }
}

#if canImport(Darwin)
public extension SharedInbox {

    /// The staging directory, created if needed.
    ///
    /// `nil` — never a crash — when the container is unavailable, which is what
    /// a missing or unprovisioned App Group entitlement looks like at runtime.
    /// Both callers say so out loud rather than failing quietly: the extension
    /// tells the reader to use the app row instead, and the app simply has
    /// nothing to drain.
    static func directory(using fileManager: FileManager = .default) -> URL? {
        guard let container = fileManager.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupIdentifier) else { return nil }
        let directory = container.appendingPathComponent(directoryName, isDirectory: true)
        if !fileManager.fileExists(atPath: directory.path) {
            try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        return directory
    }

    /// Copy a shared file in. Returns where it landed.
    static func stage(_ data: Data, originalName: String,
                      at date: Date = Date(),
                      using fileManager: FileManager = .default) throws -> URL {
        guard let directory = directory(using: fileManager) else {
            throw SharedInboxError.containerUnavailable
        }
        let url = directory.appendingPathComponent(
            stagedFileName(original: originalName, at: date))
        try data.write(to: url, options: .atomic)
        return url
    }

    /// Everything waiting to be imported, oldest first.
    static func pending(using fileManager: FileManager = .default) -> [URL] {
        guard let directory = directory(using: fileManager),
              let names = try? fileManager.contentsOfDirectory(atPath: directory.path)
        else { return [] }
        return ordered(names).map { directory.appendingPathComponent($0) }
    }

    /// Drop a file once it has been imported.
    ///
    /// Deleted rather than kept: the reader's history now lives in the store,
    /// and a staged copy that is never removed means every launch re-imports
    /// the same backup. The import itself is idempotent, so a failure to delete
    /// costs time and not correctness.
    static func remove(_ url: URL, using fileManager: FileManager = .default) {
        try? fileManager.removeItem(at: url)
    }
}

public enum SharedInboxError: Error, LocalizedError {
    case containerUnavailable

    public var errorDescription: String? {
        "This build can't reach its shared storage, so the file couldn't be handed to Health Insights. Share it to the app itself from the top row instead."
    }
}
#endif
