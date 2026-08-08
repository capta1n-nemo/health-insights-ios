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
        /// The raw catalogue — what `AppModel.otherSamples` holds. Optional so
        /// an older export without it still drives the insight-pass benchmarks.
        let unmodelled: [RawMetricSample]?
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

    /// **The half of `recompute()` that runs on the main actor** — what the
    /// reader is actually waiting on.
    ///
    /// The 2026-08-06 fix detached `evaluateAll`, and the benchmark above is
    /// about that half. The report came back anyway on 2026-08-08 (*"it hangs
    /// when I add data manually anywhere in the app, opening cards hangs, and
    /// correcting data hangs, and even load screen hangs"*), because the rest
    /// of `recompute()` was still inline — and `recompute()` has thirty-three
    /// call sites, so every reading logged, every judgement corrected and every
    /// card opened paid the whole bill.
    ///
    /// What that bill was, on the reader's own 379,693 samples, **unoptimised —
    /// which is the build their phone runs**, since `deploy.yml` builds
    /// `-configuration Debug`:
    ///
    /// | phase                      | debug   | release |
    /// |----------------------------|---------|---------|
    /// | `refreshCyclePhaseProfile` | 370 ms  |  79 ms  |
    /// | `EventFeedModel.detect`    | 161 ms  |  55 ms  |
    /// | its signature `max`        |  36 ms  |   7 ms  |
    /// | medication-level `contains`|  40 ms  |   8 ms  |
    /// | **total**                  | **849 ms** | **239 ms** |
    ///
    /// All of it is a pure function of `samples`, which is the property that
    /// let the insight pass leave, so on 2026-08-09 all of it left too. The
    /// table below is kept because **the functions did not get cheaper — they
    /// got moved**, and a later session that moves one back needs the number in
    /// front of it.
    ///
    /// The assertion is therefore on the `perRecompute` group alone: the work a
    /// single `recompute()` still holds the interface for. The `perSync` group
    /// — the promotions in `otherSamples.didSet`, ~175 ms unoptimised — is
    /// printed without a ceiling because it is **not fixed**: that `didSet`
    /// promotes synchronously on purpose, so that nothing can read a raw
    /// catalogue whose promoted `symptoms` and `tags` lag behind it, and
    /// detaching it would trade a launch stall for a pass of the symptom radar
    /// scored against yesterday's tags. It is a real remaining cost on the
    /// launch path and it needs a decision, not a reflex.
    func testRecomputeMainActorBenchmark() throws {
        guard let export = try loadExport() else {
            throw XCTSkip("Set IK_BENCH_EXPORT to a health export JSON to run this benchmark.")
        }
        let samples = export.samples
        let raw = export.unmodelled ?? []
        let now = Date()
        let summary = CycleModel.summarise(days: [])

        // Warm the lazily-built statics and fault the decode in, as above.
        _ = samples.max(by: { $0.start < $1.start })

        // Still synchronous inside `recompute()`. Everything here is paid at
        // every one of the thirty-three call sites, so this is the group with
        // a ceiling on it.
        var perRecompute: [(String, Double)] = []
        perRecompute.append(("medication-level scan",
                             elapsed { _ = samples.filter { $0.type == .activeMedicationLevel } }))

        // On the main actor too, but paid once per `otherSamples` assignment —
        // a launch and a sync, not a tap. Reported without a ceiling because
        // the fix is a behavioural one (`otherSamples.didSet` promotes
        // *synchronously* on purpose, so nothing can read a catalogue its
        // promotions lag) and has not been made.
        var perSync: [(String, Double)] = []
        if !raw.isEmpty {
            perSync.append(("otherSamples ▸ tags",
                            elapsed { _ = TagPromotion.tags(from: raw, resolved: TagMappingStore()) }))
            perSync.append(("otherSamples ▸ symptoms",
                            elapsed { _ = SymptomPromotion.events(from: raw) }))
            perSync.append(("vitalEvents (cold)",
                            elapsed { _ = VitalEventReader.events(from: raw) }))
        }

        // Detached as of 2026-08-09. Timed so a session that moves one back
        // can see what it costs before it does.
        var movedOff: [(String, Double)] = []
        movedOff.append(("refreshCyclePhaseProfile",
                         elapsed { _ = PhaseAwareBaseline.profile(samples: samples, summary: summary,
                                                                  now: now) }))
        movedOff.append(("EventFeed signature (max)",
                         elapsed { _ = samples.max(by: { $0.start < $1.start }) }))
        movedOff.append(("EventFeed detect",
                         elapsed { _ = FlaggedEventDetector.detect(samples: samples, now: now) }))

        let held = perRecompute.reduce(0) { $0 + $1.1 }
        print("── on the main actor, every recompute() ──")
        print("samples: \(samples.count), raw rows: \(raw.count)")
        for (name, ms) in perRecompute.sorted(by: { $0.1 > $1.1 }) { print(row(name, ms)) }
        print(row("HELD PER CALL", held))
        print("── on the main actor, once per sync ──")
        for (name, ms) in perSync.sorted(by: { $0.1 > $1.1 }) { print(row(name, ms)) }
        print(row("HELD PER SYNC", perSync.reduce(0) { $0 + $1.1 }))
        print("── moved off it 2026-08-09, still timed ──")
        for (name, ms) in movedOff.sorted(by: { $0.1 > $1.1 }) { print(row(name, ms)) }
        print(row("(off-actor total)", movedOff.reduce(0) { $0 + $1.1 }))
        print("─────────────────────────────────────────")

        // **A ceiling on the frozen interface, not on the work.** 60 Hz is
        // 16 ms; a tap that costs a tenth of a second already reads as
        // sluggish. This is `MainThreadWatchdog.noticeThreshold` — the point at
        // which the app's own detector calls a stall a stall — so the
        // assertion and the instrument agree on what "hang" means.
        //
        // Deliberately on the *group total*: the reader does not experience one
        // line, they experience the tap. A regression that splits 300 ms across
        // three new callers is the same defect as one caller costing 300 ms.
        XCTAssertLessThan(held, 250,
                          "recompute()'s main-actor half exceeds the watchdog's own stall threshold — see the table above")
    }
}
