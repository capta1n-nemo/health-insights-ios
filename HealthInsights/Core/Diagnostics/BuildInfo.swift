import Foundation

/// Identifies exactly which build is on the device.
///
/// The deploy workflow stamps `BuildDate` and `GitCommit` into Info.plist before
/// building, so a device can be matched to a commit. Local Xcode builds carry
/// neither, so the date falls back to when the executable was written — which is
/// the build time for a fresh install either way.
enum BuildInfo {
    /// Marketing version, e.g. "0.1.0".
    static var version: String {
        string(for: "CFBundleShortVersionString") ?? "—"
    }

    /// Build number. The deploy workflow sets this to the Actions run number, so
    /// it increases with every deploy.
    static var build: String {
        string(for: "CFBundleVersion") ?? "—"
    }

    /// Short commit the build came from, when stamped.
    static var commit: String? { string(for: "GitCommit") }

    /// When this build was produced.
    static var date: Date? {
        if let stamped = string(for: "BuildDate"),
           let parsed = ISO8601DateFormatter().date(from: stamped) {
            return parsed
        }
        return executableDate
    }

    /// A one-line summary for the Settings row.
    static var summary: String {
        var parts = ["\(version) (\(build))"]
        if let commit { parts.append(commit) }
        return parts.joined(separator: " · ")
    }

    static var formattedDate: String {
        guard let date else { return "Unknown" }
        return date.formatted(date: .abbreviated, time: .shortened)
    }

    private static func string(for key: String) -> String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String,
              !value.isEmpty else { return nil }
        return value
    }

    /// Modification date of the app's executable — the closest thing to a build
    /// timestamp available without a build-time stamp.
    private static var executableDate: Date? {
        guard let url = Bundle.main.executableURL,
              let attributes = try? FileManager.default
                  .attributesOfItem(atPath: url.path) else { return nil }
        return attributes[.modificationDate] as? Date
    }
}
