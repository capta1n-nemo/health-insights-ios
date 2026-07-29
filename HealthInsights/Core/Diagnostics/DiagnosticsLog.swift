import Foundation
import Observation

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
    }

    private(set) var entries: [Entry] = []
    private let limit = 500

    private init() {}

    /// Append an entry (newest kept at the front), trimming to `limit`.
    func log(_ category: String, _ message: String, status: Status = .info) {
        entries.insert(Entry(date: Date(), category: category, message: message, status: status),
                       at: 0)
        if entries.count > limit { entries.removeLast(entries.count - limit) }
    }

    func ok(_ category: String, _ message: String) { log(category, message, status: .ok) }
    func fail(_ category: String, _ message: String) { log(category, message, status: .fail) }
    func null(_ category: String, _ message: String) { log(category, message, status: .null) }
    func info(_ category: String, _ message: String) { log(category, message, status: .info) }

    func clear() { entries.removeAll() }

    /// A plain-text export the user can copy/share when asking for help.
    func exportText() -> String {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return entries.reversed().map { e in
            "[\(df.string(from: e.date))] \(e.status.rawValue.uppercased()) · \(e.category): \(e.message)"
        }.joined(separator: "\n")
    }
}
