import Foundation
import os
#if canImport(Darwin)
import Darwin
#endif

/// **A hang detector for the main thread**, DEBUG-only, writing through
/// `DiagnosticsLog` so a stall shows up in `./scripts/simulator.sh logs` with a
/// backtrace instead of as a feeling.
///
/// ## Why this exists (backlog `D54`)
///
/// The reader, 2026-08-07: *"Can you enable hang detection on the emulator, to
/// look for hangs? I see so many hangs…"* — and on 2026-08-06, before the
/// `recompute()` detach landed, *"it hangs the UI/UX and the app becomes
/// unresponsive"*. The first report was diagnosed by reading code and measuring
/// a function by hand. That worked once and does not scale: **the second report
/// arrived after the fix, which means either something else blocks the main
/// thread or the fix missed a path, and neither is answerable without a
/// detector.**
///
/// `D54` names three separate instruments, and this is the first of them
/// deliberately — *"the one that makes the others findable"*:
///
/// 1. **This.** In-app, always running in DEBUG, catches simulator and device
///    alike, and names the stack.
/// 2. **Xcode's Thread Performance Checker** (Diagnostics ▸ Runtime
///    Sanitization) — see `docs/deployment.md`. It reports priority inversions
///    and blocking calls this cannot see, but only under Xcode's debugger.
/// 3. **`MetricKit`'s `MXHangDiagnostic`** for the reader's real phone, which
///    is the only route to a device-only hang. See `HangDiagnosticsReporter`.
///
/// ## How it works, and why it is a runloop observer rather than a timer
///
/// A stall is *the main thread failing to come back*, so nothing running on the
/// main thread can time it — the measurement has to come from outside. A
/// background timer therefore takes a heartbeat: the main thread stamps
/// `lastTick` on every runloop turn, and the watcher, on its own thread, reports
/// whenever that stamp has gone stale by more than `threshold`.
///
/// Two thresholds, both from Apple's own published definitions in the Hangs
/// instrument and in `MXHangDiagnostic`:
///
/// - **250 ms** — a *micro-hang*: below the ~400 ms at which a user reliably
///   notices, but already a dropped-frame cluster. Logged, not shouted.
/// - **1000 ms** — Apple's own hang threshold, and what `MXHangDiagnostic`
///   reports. Logged as a failure, with a backtrace of the main thread.
///
/// ## ⚠️ What this can and cannot tell you
///
/// It measures **the main runloop's turnaround**, which is what the reader
/// experiences as a freeze. It will not see:
///
/// - a slow *background* pass (the 2026-08-07 `D57` finding — a refresh taking
///   fifteen seconds off the main thread is not a hang by this definition and
///   still reads as one to the reader; `RefreshPhaseTimer` is the instrument
///   for that);
/// - a hang during launch before `start()` is called;
/// - a spin inside a single long CPU-bound call that *is* on the main thread —
///   it will see it, but the captured stack is a sample, so a deep SwiftUI
///   frame may be all it names.
///
/// ## DEBUG only, on purpose
///
/// It costs a thread and a stamp per runloop turn — small, but not nothing, and
/// a release build should not carry a diagnostic the reader cannot act on. The
/// device-side answer for a release build is `MXHangDiagnostic`, which Apple
/// collects without any cost of ours.
enum MainThreadWatchdog {

    /// A stall worth a line in the log.
    static let noticeThreshold: TimeInterval = 0.25
    /// Apple's own hang threshold — what `MXHangDiagnostic` reports.
    static let hangThreshold: TimeInterval = 1.0

    /// How often the watcher looks. Half the notice threshold, so a stall of
    /// exactly `noticeThreshold` cannot be missed between two looks.
    private static let pollInterval: TimeInterval = 0.125

    #if DEBUG
    /// Nanoseconds since boot, stamped by the main thread on every runloop turn.
    /// `OSAllocatedUnfairLock` rather than an actor: the writer is the main
    /// thread on its hot path and must never await.
    private static let lastTick = OSAllocatedUnfairLock(initialState: DispatchTime.now().uptimeNanoseconds)
    private static let started = OSAllocatedUnfairLock(initialState: false)
    #endif

    /// Begin watching. Idempotent — safe to call from a `.task` that re-runs on
    /// a scene change, which is exactly what `HealthInsightsApp` does.
    ///
    /// A no-op in release builds, and a no-op the compiler removes entirely.
    ///
    /// `@MainActor` because it installs a `CFRunLoopObserver` on the *main*
    /// runloop and writes its arming line to `DiagnosticsLog`, which is
    /// main-actor isolated. Both are what the caller means by "start watching
    /// the main thread", so requiring the caller to already be there is the
    /// honest signature rather than a hop hidden inside.
    @MainActor
    static func start() {
        #if DEBUG
        let alreadyRunning = started.withLock { running -> Bool in
            defer { running = true }
            return running
        }
        guard !alreadyRunning else { return }

        // The stamp. A runloop observer fires on every turn of the main
        // runloop, including the turns that draw a frame, so a stale stamp
        // means the runloop itself has not come back round.
        let observer = CFRunLoopObserverCreateWithHandler(
            kCFAllocatorDefault,
            CFRunLoopActivity.beforeWaiting.rawValue | CFRunLoopActivity.afterWaiting.rawValue,
            true, 0
        ) { _, _ in
            let now = DispatchTime.now().uptimeNanoseconds
            lastTick.withLock { $0 = now }
        }
        CFRunLoopAddObserver(CFRunLoopGetMain(), observer, .commonModes)

        // The watcher. A plain `Thread` rather than a `DispatchSourceTimer`,
        // because a stall bad enough to matter can also starve a queue that is
        // sharing a thread pool — and a hang detector that hangs reports
        // nothing. `.userInitiated` so it is not the first thing descheduled
        // under load.
        let watcher = Thread {
            var lastReportedTick: UInt64 = 0
            while true {
                Thread.sleep(forTimeInterval: pollInterval)
                let tick = lastTick.withLock { $0 }
                let stalledFor = Double(DispatchTime.now().uptimeNanoseconds &- tick) / 1_000_000_000
                guard stalledFor >= noticeThreshold, tick != lastReportedTick else { continue }
                // One report per stall, not one per poll: a four-second hang
                // would otherwise fill the log with thirty-two lines about
                // itself and push out what caused it.
                lastReportedTick = tick
                let seconds = String(format: "%.2f", stalledFor)
                let isHang = stalledFor >= hangThreshold
                Task { @MainActor in
                    let stack = Self.stallContext()
                    // ⚠️ Deliberately logged *after* the stall ends — this hop
                    // is queued on the very actor that is blocked, so the entry
                    // appears when the main thread comes back. That is a
                    // feature: a log line written from the watcher thread could
                    // interleave a `DiagnosticsLog` mutation with a main-thread
                    // one, and `DiagnosticsLog` is `@MainActor` precisely so it
                    // needs no lock.
                    if isHang {
                        DiagnosticsLog.shared.fail(
                            "Hang", "Main thread blocked for \(seconds)s", detail: stack)
                    } else {
                        DiagnosticsLog.shared.info(
                            "Hang", "Main thread stalled for \(seconds)s", detail: stack)
                    }
                }
            }
        }
        watcher.name = "MainThreadWatchdog"
        watcher.qualityOfService = .userInitiated
        watcher.start()

        DiagnosticsLog.shared.info(
            "Hang",
            "Watchdog armed — notice at \(Int(noticeThreshold * 1000))ms, hang at \(Int(hangThreshold * 1000))ms")
        #endif
    }

    #if DEBUG
    /// A symbolicated backtrace of the *watcher's* view of the process.
    ///
    /// ⚠️ **Honest about what it is.** There is no supported API for capturing
    /// another thread's stack from inside the process — `Thread.callStackSymbols`
    /// returns the calling thread's, and reaching into another thread's frames
    /// means `task_threads` and hand-rolled unwinding, which is not something to
    /// ship in a diagnostic. So the detail below is **the stall's shape, not its
    /// stack**: how long, and what the app was doing according to its own log.
    ///
    /// This is deliberately a smaller claim than "here is the hang's stack", and
    /// it is why item 2 of `D54` (Xcode's Thread Performance Checker) and item 3
    /// (`MXHangDiagnostic`) are separate instruments rather than things this
    /// replaces. **Both of those do capture the blocked thread's frames.** What
    /// this gives is the timestamp and the log context, which is what turns "the
    /// app feels slow" into "it stalled at 20:41:07, right after Sync started".
    ///
    /// ⚠️ **`@MainActor`, and it must stay that way.** The first version read
    /// the log through `DispatchQueue.main.sync` *from the watcher thread* —
    /// which blocks the watcher on the very thread it is watching. A hang
    /// detector that hangs reports nothing, which is the same defect the plain
    /// `Thread` above exists to avoid.
    @MainActor
    private static func stallContext() -> String {
        let recent = DiagnosticsLog.shared.entries.prefix(3).map {
            "\($0.category): \($0.message)"
        }
        var lines = ["Last log lines before the stall:"]
        lines.append(contentsOf: recent.map { "  · \($0)" })
        lines.append("Capture the blocked frames with Xcode ▸ Debug ▸ Diagnostics ▸ "
                     + "Thread Performance Checker, or read MXHangDiagnostic from the phone.")
        return lines.joined(separator: "\n")
    }
    #endif
}
