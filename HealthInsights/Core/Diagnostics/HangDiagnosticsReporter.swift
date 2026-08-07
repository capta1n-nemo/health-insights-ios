import Foundation
#if canImport(MetricKit)
import MetricKit
#endif

/// **`MetricKit`, for the hangs that only happen on the reader's own phone.**
///
/// ## Why this is a third instrument and not a duplicate (backlog `D54`)
///
/// `MainThreadWatchdog` catches a stall in a DEBUG build, wherever it is
/// running. Xcode's Thread Performance Checker catches blocking calls and
/// priority inversions, under the debugger. **Neither is available where the
/// reader's hangs actually are**: a release build, on a phone, in another
/// house, with three years of real data and providers that answer over the
/// network. The simulator cannot reproduce that, and a hang nobody can
/// reproduce is a hang nobody can fix.
///
/// `MXHangDiagnostic` is the only route to it. iOS itself watches the main
/// thread of every app, and when one stops responding for long enough it
/// records the duration **and the blocked thread's call tree**, then hands the
/// payload back to the app on the next launch. That call tree is the thing the
/// in-app watchdog honestly cannot capture (see its `stallContext`).
///
/// ## What this does with a payload
///
/// It writes it into `DiagnosticsLog`, which is the one channel that reaches
/// this project: the reader taps Settings ▸ Troubleshooting ▸ copy, and the
/// export arrives in a message. Nothing is sent anywhere — `MetricKit` delivers
/// locally, and `docs/privacy-and-ip.md`'s rule is respected because a hang
/// diagnostic carries stack frames and durations, never a health value.
///
/// ## ⚠️ Three things about the delivery that make it look broken
///
/// 1. **Payloads arrive at most once a day, on launch, and only after the app
///    has been used for a while.** An empty Hang category is the normal state.
///    It does not mean the reporter is broken; it means iOS has nothing to hand
///    over yet.
/// 2. **Diagnostic payloads (`MXDiagnosticPayload`) are separate from metric
///    payloads.** `didReceive(_ payloads: [MXDiagnosticPayload])` is the one
///    that carries hangs and crashes; the metric callback is required by the
///    protocol and is deliberately a near-no-op here.
/// 3. **The simulator delivers nothing.** This class is not testable there, by
///    design of the framework. That is the whole reason it exists alongside the
///    watchdog rather than instead of it.
@MainActor
final class HangDiagnosticsReporter: NSObject {
    static let shared = HangDiagnosticsReporter()

    private var started = false

    /// Subscribe. Idempotent — `HealthInsightsApp`'s `task` can run again on a
    /// scene change, and `MXMetricManager` would otherwise hold two references
    /// to this object and deliver everything twice.
    func start() {
        guard !started else { return }
        started = true
        #if canImport(MetricKit) && !targetEnvironment(simulator)
        MXMetricManager.shared.add(self)
        DiagnosticsLog.shared.info(
            "Hang", "MetricKit subscribed — hang and crash diagnostics will arrive on a later launch")
        #else
        // Said out loud rather than left silent: a session looking for hang
        // reports on the simulator would otherwise read the absence as a bug in
        // this file.
        DiagnosticsLog.shared.info(
            "Hang", "MetricKit unavailable here — device only; the in-app watchdog is the simulator's detector")
        #endif
    }
}

#if canImport(MetricKit) && !targetEnvironment(simulator)
extension HangDiagnosticsReporter: MXMetricManagerSubscriber {

    /// Daily aggregate metrics. `applicationResponsiveness.histogrammedApplicationHangTime`
    /// is the one line worth keeping: it is the *distribution* of hang durations
    /// over the day, which answers "so many hangs" as a count rather than as an
    /// impression.
    nonisolated func didReceive(_ payloads: [MXMetricPayload]) {
        let lines = payloads.compactMap { payload -> String? in
            guard let responsiveness = payload.applicationResponsivenessMetrics else { return nil }
            let buckets = responsiveness.histogrammedApplicationHangTime.bucketEnumerator
                .compactMap { $0 as? MXHistogramBucket<UnitDuration> }
                .filter { $0.bucketCount > 0 }
                .map { "\($0.bucketCount) hang(s) of \($0.bucketStart.value)–\($0.bucketEnd.value)s" }
            return buckets.isEmpty ? nil : buckets.joined(separator: "\n")
        }
        guard !lines.isEmpty else { return }
        let detail = lines.joined(separator: "\n")
        Task { @MainActor in
            DiagnosticsLog.shared.fail("Hang", "iOS reported hangs over the last day", detail: detail)
        }
    }

    /// Crashes and hangs, **with the blocked thread's call tree**. This is the
    /// payload the whole file is for.
    nonisolated func didReceive(_ payloads: [MXDiagnosticPayload]) {
        var entries: [(message: String, detail: String)] = []
        for payload in payloads {
            for hang in payload.hangDiagnostics ?? [] {
                let seconds = hang.hangDuration.converted(to: .seconds).value
                entries.append((
                    String(format: "Hang on the phone — main thread blocked for %.2fs", seconds),
                    Self.text(from: hang.callStackTree)))
            }
            // ⚠️ **Crashes too, and deliberately.** Backlog `D58` is a
            // `SIGABRT` whose provenance could not be established because the
            // only record was a simulator `.ips` file written while
            // twenty-six agents shared one simulator. A crash the *app* records
            // against its own build, in its own log, cannot be confused for
            // somebody else's.
            for crash in payload.crashDiagnostics ?? [] {
                let reason = [crash.exceptionType.map { "exception \($0)" },
                              crash.signal.map { "signal \($0)" },
                              crash.terminationReason]
                    .compactMap { $0 }
                    .joined(separator: ", ")
                entries.append((
                    "Crash on the phone — \(reason.isEmpty ? "no reason reported" : reason)",
                    Self.text(from: crash.callStackTree)))
            }
        }
        guard !entries.isEmpty else { return }
        Task { @MainActor in
            for entry in entries {
                DiagnosticsLog.shared.fail("Hang", entry.message, detail: entry.detail)
            }
        }
    }

    /// The call tree as JSON text, truncated.
    ///
    /// `DiagnosticsLog` holds a thousand entries in memory and the reader
    /// copy-pastes the whole thing; an unbounded symbol tree per hang would push
    /// out everything that gives the hang its context. The head of the tree is
    /// the blocked frames, which is the part that identifies the hang.
    nonisolated static func text(from tree: MXCallStackTree) -> String {
        let data = tree.jsonRepresentation()
        let text = String(data: data, encoding: .utf8) ?? "<call stack tree could not be decoded>"
        let limit = 4000
        guard text.count > limit else { return text }
        return String(text.prefix(limit)) + "\n… truncated (\(text.count) chars total)"
    }
}
#endif
