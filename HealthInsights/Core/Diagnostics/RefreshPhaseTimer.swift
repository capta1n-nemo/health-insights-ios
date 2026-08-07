import Foundation

/// **Where the refresh's seconds actually go**, phase by phase, written into the
/// one diagnostic line the reader can already export.
///
/// ## Why this exists (backlog `D57`)
///
/// The measurement that opened `D57` was the app's own line:
///
/// > `Sync: Refresh complete in 15.5s — 377316 samples, 18 insights`
///
/// One number, over a dozen phases: a network sync of every connected
/// integration, an ingest of ~177k unmodelled raw values, two cache
/// load-merge-save round trips over the whole record, the sanitiser, two derived
/// series, the eighteen-model insight pass, a summary and a tag pass. **Nothing
/// in that line says which of them is the fifteen seconds**, and the backlog row
/// itself guessed at the insight pass.
///
/// It was measured instead. On the reader's own 381,701-sample export the whole
/// insight pass — all nineteen registered models, cold memo — is **1.02 s** on
/// an M-series Mac, and after the `FitnessInsight` fix in the same session it is
/// **0.50 s** (`InsightPassBenchmarkTests`). Even allowing several times that on
/// a phone, the insight pass is not fifteen seconds, so **the rest of the
/// refresh is where the time is** — and no instrument existed to say which part.
///
/// This is that instrument, and it is deliberately the cheapest possible one: a
/// monotonic clock, a name per phase, and one extra `detail` block on a log line
/// that was already being written. It costs nothing when nothing is looking, and
/// it means the next session reads the answer out of the reader's exported log
/// rather than re-deriving it.
///
/// ## Why not `os_signpost`
///
/// Signposts are better and Instruments renders them beautifully — on a Mac,
/// attached, with the reader's phone plugged in. That is exactly the situation
/// this project does not have: the hangs are reported from a phone in another
/// house, and the only channel back is the diagnostics export the reader taps.
/// A signpost that nobody is recording is not a measurement. (Adding signposts
/// *as well* is free and worth doing when someone is next at the Mac with the
/// phone; they are not a substitute for this.)
struct RefreshPhaseTimer {

    private var phases: [(name: String, seconds: Double)] = []
    private var mark: UInt64
    private let startedAt: UInt64

    init() {
        let now = DispatchTime.now().uptimeNanoseconds
        mark = now
        startedAt = now
    }

    /// Close the phase that has been running since the last `lap` (or since
    /// `init`) and name it.
    ///
    /// Uptime rather than `Date`: `Date` can move under a clock correction
    /// mid-sync, and a phase that appears to take −0.4 s is worse than no
    /// figure at all.
    mutating func lap(_ name: String) {
        let now = DispatchTime.now().uptimeNanoseconds
        phases.append((name, Double(now &- mark) / 1_000_000_000))
        mark = now
    }

    var total: Double {
        Double(DispatchTime.now().uptimeNanoseconds &- startedAt) / 1_000_000_000
    }

    /// The breakdown, **slowest first** and with anything under 50 ms folded
    /// into one line.
    ///
    /// Slowest first because the reader pastes the top of a log into a message
    /// and the answer must be in what they paste. The fold exists because a
    /// fourteen-line list in which twelve lines say `0.0s` reads as noise, and
    /// the noise is what gets skimmed past.
    func summary() -> String {
        let sorted = phases.sorted { $0.seconds > $1.seconds }
        let notable = sorted.filter { $0.seconds >= 0.05 }
        let rest = sorted.filter { $0.seconds < 0.05 }
        var lines = notable.map { String(format: "· %@: %.2fs", $0.name, $0.seconds) }
        if !rest.isEmpty {
            let restTotal = rest.reduce(0) { $0 + $1.seconds }
            lines.append(String(format: "· %d other phase(s) under 50ms: %.2fs total",
                                rest.count, restTotal))
        }
        return (["Phase breakdown (slowest first):"] + lines).joined(separator: "\n")
    }
}
