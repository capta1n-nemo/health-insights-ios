import Foundation
import Observation
#if canImport(UIKit)
import UIKit
#endif

/// A live, on-device diagnostic log the sync pipeline writes to — every
/// integration connection, API call, and per-metric import is recorded with a
/// pass / fail / null / info status. It powers the Settings ▸ Troubleshooting
/// view so a non-technical user (or I, remotely) can see exactly what happened.
///
/// It's a `@MainActor` shared instance because every producer (providers,
/// HealthKit service, the app model) already runs on the main actor, which keeps
/// hooking it in a one-liner with no plumbing through initialisers. Nothing here
/// ever leaves the device.
@MainActor
@Observable
final class DiagnosticsLog {
    static let shared = DiagnosticsLog()

    enum Status: String, Sendable {
        case ok, fail, null, info

        var symbol: String {
            switch self {
            case .ok: return "checkmark.circle.fill"
            case .fail: return "xmark.octagon.fill"
            case .null: return "questionmark.circle.fill"
            case .info: return "info.circle"
            }
        }
    }

    struct Entry: Identifiable, Sendable {
        let id = UUID()
        let date: Date
        let category: String
        let message: String
        let status: Status
        /// The evidence behind the one-line message: a server's error body, the
        /// exact URL that was called, a per-metric breakdown. Kept off the
        /// headline so the log stays scannable, but always in the export — a
        /// bare "HTTP 401" is what made the Oura scope failures unreadable.
        let detail: String?
    }

    private(set) var entries: [Entry] = []
    /// Deliberately generous: a full sync now records a line per API call *and*
    /// per imported metric, and the copy-out has to still contain the start of
    /// the sync that went wrong.
    private let limit = 1000

    private init() {}

    /// Append an entry (newest kept at the front), trimming to `limit`.
    func log(_ category: String, _ message: String, status: Status = .info, detail: String? = nil) {
        entries.insert(Entry(date: Date(), category: category, message: message,
                             status: status, detail: detail?.nilIfBlank),
                       at: 0)
        if entries.count > limit { entries.removeLast(entries.count - limit) }
    }

    func ok(_ category: String, _ message: String, detail: String? = nil) {
        log(category, message, status: .ok, detail: detail)
    }
    func fail(_ category: String, _ message: String, detail: String? = nil) {
        log(category, message, status: .fail, detail: detail)
    }
    func null(_ category: String, _ message: String, detail: String? = nil) {
        log(category, message, status: .null, detail: detail)
    }
    func info(_ category: String, _ message: String, detail: String? = nil) {
        log(category, message, status: .info, detail: detail)
    }

    func clear() { entries.removeAll() }

    /// A plain-text export the user can copy/share when asking for help.
    ///
    /// Leads with the build and device so a pasted log identifies which deploy
    /// produced it, then every entry oldest-first with its detail indented
    /// underneath.
    func exportText() -> String {
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.dateFormat = "yyyy-MM-dd HH:mm:ss"

        var lines = [
            "Health Insights diagnostics",
            "App: \(BuildInfo.summary)",
            "Built: \(BuildInfo.formattedDate)",
            "Device: \(Self.deviceDescription)",
            "Exported: \(df.string(from: Date()))",
            "Entries: \(entries.count)\(entries.count == limit ? " (log full — oldest trimmed)" : "")",
            ""
        ]
        for e in entries.reversed() {
            lines.append("[\(df.string(from: e.date))] \(e.status.rawValue.uppercased()) · \(e.category): \(e.message)")
            if let detail = e.detail {
                for detailLine in detail.split(separator: "\n", omittingEmptySubsequences: false) {
                    lines.append("        \(detailLine)")
                }
            }
        }
        return lines.joined(separator: "\n")
    }

    private static var deviceDescription: String {
        #if canImport(UIKit)
        return "\(UIDevice.current.model) · iOS \(UIDevice.current.systemVersion)"
        #else
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return "\(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
        #endif
    }
}

extension String {
    /// `nil` for an empty/whitespace-only string, so callers can pass a computed
    /// detail without guarding it first.
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
