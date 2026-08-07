import XCTest
@testable import InsightKit

/// A measurement harness for the insight pass, run against a **real-scale**
/// sample set rather than a fixture.
///
/// ## Why this exists (backlog `D57`)
///
/// The reader's own diagnostic line said
/// `Sync: Refresh complete in 15.5s — 377316 samples, 18 insights`, and there
/// was no way to attribute that number to a phase. Guessing which of the
/// eighteen models is expensive is how an optimisation becomes a story: the
/// first run of this harness found that **one model accounted for most of the
/// pass** and several of the suspects cost under a millisecond.
///
/// ## How to run it
///
/// It is **skipped unless `IK_BENCH_EXPORT` names a file**, because the only
/// real-scale input is the reader's own export and that must never be committed
/// or checked into CI:
///
/// ```bash
/// IK_BENCH_EXPORT=~/HealthSeed/exports/promoted-for-sim.json \
///   swift test --filter InsightPassBenchmark -c release
/// ```
///
/// `-c release` matters — a debug build of Swift generics measures the
/// optimiser's absence, not the algorithm.
///
/// ## ⚠️ What it may print
///
/// **Counts and durations only, never a reading.** `docs/privacy-and-ip.md`'s
/// rule is "the shape of a finding, never the value", and this harness runs
/// over one person's real health record. Every line below prints a metric name,
/// a sample count or a millisecond figure; none prints a `value`.
final class InsightPassBenchmarkTests: XCTestCase {

    private struct Export: Decodable {
        let samples: [HealthMetricSample]
        let profile: UserHealthProfile?
    }

    /// The reader's export, or `nil` when the harness is not being driven.
    private func loadExport() throws -> Export? {
        guard let raw = ProcessInfo.processInfo.environment["IK_BENCH_EXPORT"],
              !raw.isEmpty else { return nil }
        let expanded = (raw as NSString).expandingTildeInPath
        let data = try Data(contentsOf: URL(fileURLWithPath: expanded))
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(Export.self, from: data)
    }

    /// `String(format:)`'s `%@` padding needs `NSString` and does not pad
    /// reliably off Darwin, so the column is built by hand — the harness has to
    /// read the same on Linux CI as on the Mac it was written on.
    private func row(_ name: String, _ ms: Double) -> String {
        let padded = name.count >= 26 ? name : name + String(repeating: " ", count: 26 - name.count)
        return String(format: "  %@%8.1f ms", padded, ms)
    }

    private func elapsed(_ body: () -> Void) -> Double {
        let start = DispatchTime.now().uptimeNanoseconds
        body()
        return Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
    }

    /// Per-model timings for one full evaluation, plus the whole-pass figure.
    ///
    /// The two are deliberately both reported: the models are timed *inside* one
    /// shared memo, so their sum is the pass minus the memo's own build, and a
    /// large gap between the sum and the total is itself a finding.
    func testInsightPassBenchmark() throws {
        guard let export = try loadExport() else {
            throw XCTSkip("Set IK_BENCH_EXPORT to a health export JSON to run this benchmark.")
        }
        let samples = export.samples
        let profile = export.profile ?? UserHealthProfile()
        let engine = InsightEngine()
        let now = Date()

        print("── insight pass benchmark ──")
        print("samples: \(samples.count), models: \(engine.models.count)")

        // Warm: the first pass pays for lazily-built statics and for the OS
        // faulting in a 150 MB decode. Timing it would measure the fixture.
        _ = engine.evaluateAll(samples: samples, profile: profile, now: now)

        var perModel: [(String, Double)] = []
        let total = elapsed {
            MultiSource.withMemo(for: samples) {
                for model in engine.models {
                    let ms = elapsed {
                        _ = model.evaluate(samples: samples, events: [], profile: profile, now: now)
                    }
                    perModel.append((String(describing: model.id), ms))
                }
            }
        }

        for (name, ms) in perModel.sorted(by: { $0.1 > $1.1 }) {
            print(row(name, ms))
        }
        print(row("TOTAL (warm memo)", total))

        // A cold pass — memo built from scratch, as every real recompute does.
        var results: [InsightResult] = []
        let cold = elapsed {
            results = engine.evaluateAll(samples: samples, profile: profile, now: now)
        }
        print(row("TOTAL (cold memo)", cold))
        print("────────────────────────────")

        XCTAssertEqual(results.count, engine.models.count,
                       "every registered model must produce a result — a pass that skipped one would also look fast")
        // **A regression ceiling, not a target.** Ten times the 0.50 s measured
        // on an M-series Mac after the `FitnessInsight` fix, so ordinary machine
        // variance and a slower runner cannot trip it — but the defect this
        // harness found (one model at 783 ms of a 979 ms pass, from a filtered
        // array that defeated the memo) would return as a failure rather than
        // as a number nobody reads.
        XCTAssertLessThan(cold, 5_000,
                          "the insight pass has regressed badly — see the per-model table above")
    }

    /// What the memo's own construction costs, and what a single memoised read
    /// costs once it is built. Run when the per-model table says the models are
    /// cheap and the pass is not.
    func testMemoBuildBenchmark() throws {
        guard let export = try loadExport() else {
            throw XCTSkip("Set IK_BENCH_EXPORT to a health export JSON to run this benchmark.")
        }
        let samples = export.samples
        _ = MultiSource.withMemo(for: samples) { samples.samples(of: .heartRate).count }

        let build = elapsed {
            MultiSource.withMemo(for: samples) { _ = samples.samples(of: .heartRate) }
        }
        print(String(format: "memo build + one metric read: %.1f ms", build))

        MultiSource.withMemo(for: samples) {
            let first = elapsed { _ = samples.samples(of: .restingHeartRate) }
            let second = elapsed { _ = samples.samples(of: .restingHeartRate) }
            print(String(format: "restingHeartRate first read: %.1f ms, second: %.3f ms", first, second))
            // The memo's whole claim in one assertion: the second read of a
            // metric is a dictionary hit. If this ever fails, every "seven
            // models read resting heart rate" saving in this file is fiction.
            XCTAssertLessThan(second, first / 10,
                              "the second memoised read is not materially cheaper than the first")
        }
    }
}
