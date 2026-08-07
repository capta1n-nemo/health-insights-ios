import Foundation
import Observation
import os
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
/// hooking it in a one-liner with no plumbing through initialisers.
///
/// ## ⚠️ What leaves, precisely — and why this one is genuinely exempt
///
/// Backlog B8 R6 rewrote every "nothing leaves your device" claim in the app to
/// be true under two-tier sharing. **This claim survives, and it is worth saying
/// exactly why rather than leaving it looking overlooked:** the diagnostics log
/// is in no sharing tier at all. `SharedRecord.Kind` has a case for a calendar
/// correction and a case for an estimate error, and none for a log line — so no
/// setting anywhere in Settings can cause an entry from here to be shared.
///
/// Two routes out of the app do exist, both of them the reader's own doing, and
/// both predating B8:
///
/// - **The in-app export**, when the reader taps copy or share (`entries` and
///   their `detail`). Deliberate, initiated by them, and the reason the log
///   exists.
/// - **The unified log**, which carries the one-line messages only — never
///   `detail` — and reaches Console, `log collect` and any sysdiagnose. See
///   `mirrorToUnifiedLog`, which argues that trade in full.
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
        mirrorToUnifiedLog(category, message, status)
    }

    // MARK: - The unified-log mirror

    /// One `os.Logger` per category, created on first use. The subsystem is the
    /// app's own bundle id, so `log stream --predicate 'subsystem == "…"'` (or
    /// `xcrun simctl spawn booted log stream …`) follows a whole sync live.
    private var unifiedLoggers: [String: Logger] = [:]
    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.jasonsalway.healthinsights"

    private func unifiedLogger(for category: String) -> Logger {
        if let logger = unifiedLoggers[category] { return logger }
        let logger = Logger(subsystem: Self.subsystem, category: category)
        unifiedLoggers[category] = logger
        return logger
    }

    /// Mirror the one-line message — never the `detail` — to the unified log.
    ///
    /// This exists because the in-memory log is invisible to `xcrun simctl` and
    /// Console: debugging a sync meant clicking through Settings ▸
    /// Troubleshooting on every run. Unconditional rather than DEBUG-gated, so
    /// a device build can be watched too — and privacy-safe on three counts:
    ///
    /// - **`detail` is deliberately excluded.** It is where server error
    ///   bodies, called URLs and per-metric breakdowns live, which can carry
    ///   health values — and anything handed to os_log leaves the app sandbox
    ///   (Console, `log collect`, a sysdiagnose attached to a bug report).
    ///   The in-app export keeps the details; the mirror never sees them.
    /// - **The message is an interpolated value**, so os_log's default
    ///   redaction applies to it off-debugger — callers do embed counts and
    ///   figures in messages.
    /// - **The status arrives as a static literal per branch** (a literal is
    ///   public by default), so a redacted stream still shows which category
    ///   said ok / fail / null and when — which is most of what a remote
    ///   debugging session needs.
    ///
    /// `fail` maps to `.error` and everything else to `.info`, so error-only
    /// filtering in the tooling surfaces exactly the red rows the
    /// Troubleshooting view would.
    private func mirrorToUnifiedLog(_ category: String, _ message: String, _ status: Status) {
        let logger = unifiedLogger(for: category)
        switch status {
        case .fail: logger.error("fail: \(message)")
        case .ok: logger.info("ok: \(message)")
        case .null: logger.info("null: \(message)")
        case .info: logger.info("info: \(message)")
        }
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

    /// The first line of every launch: which build is running, and when it
    /// started.
    ///
    /// **Two jobs, and the second one is the reason it exists** (backlog D26).
    ///
    /// In the log itself it separates one launch from the next. `entries` holds
    /// a thousand lines and survives well past a relaunch in a long debugging
    /// session, so "the sync that went wrong" and "the sync before the fix"
    /// otherwise run together in the export with nothing between them.
    ///
    /// Through the unified-log mirror it is also **the only line this app emits
    /// unprompted**. Every other producer is the sync pipeline, an integration
    /// or an import — none of which fire on a simulator, which has no Health app
    /// and no connected provider. So `./scripts/simulator.sh logs` came back
    /// with nothing app-shaped at all, and a session could not tell "the mirror
    /// is broken" from "nothing has happened yet". One guaranteed line answers
    /// that in the first second, before anything is driven.
    ///
    /// Idempotent: `AppModel` is a shared singleton and the root view's `task`
    /// can run again on a scene change, and a launch banner per re-entry would
    /// be worse than none.
    @ObservationIgnored private var hasRecordedLaunch = false
    func recordLaunch() {
        guard !hasRecordedLaunch else { return }
        hasRecordedLaunch = true
        info("App", "Launched — \(BuildInfo.summary) on \(Self.deviceDescription)")
    }

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
