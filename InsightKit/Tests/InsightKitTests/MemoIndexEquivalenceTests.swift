import XCTest
@testable import InsightKit

/// **The memoised path and the plain scan must agree exactly, or this is not a
/// performance fix.**
///
/// `EvaluationMemo` stopped a metric being scanned twice, and did not stop each
/// *distinct* metric costing a walk of the whole array. Measured on the reader's
/// record — 237,935 samples, 45 present types — reading the rarest metric, which
/// has six samples, took 28.8 ms, because the cost is the scan and not the
/// metric. One `Dictionary(grouping:)` replaces all of them.
///
/// Grouping and filtering are only interchangeable while `Dictionary(grouping:)`
/// preserves source order, which `uncachedBreakdown` separately relies on to
/// skip a re-sort. These tests pin that they agree rather than assuming it.
final class MemoIndexEquivalenceTests: XCTestCase {

    /// A mixed set with the shapes that break naive grouping: several sources
    /// per metric, interleaved dates, duplicate instants, and a metric with a
    /// single sample.
    private func mixed() -> [HealthMetricSample] {
        var out: [HealthMetricSample] = []
        let sources: [MetricSource] = [.oura, .appleHealth, .withings]
        let types: [MetricType] = [.restingHeartRate, .heartRateVariabilityRMSSD,
                                   .stepCount, .bodyMass, .respiratoryRate]
        for day in 0..<40 {
            for (i, type) in types.enumerated() {
                for (j, source) in sources.enumerated() {
                    // Not every combination, so some metrics are dense and some
                    // sparse — the sparse ones are where a scan is most wasteful.
                    guard (day + i + j) % (i + 2) == 0 else { continue }
                    let t = TestClock.now.addingTimeInterval(-Double(day) * 86_400
                                                             + Double(j) * 60)
                    out.append(HealthMetricSample(type: type, value: Double(50 + day + i * 3),
                                                  start: t, end: t, source: source))
                }
            }
        }
        // A type with exactly one sample, and one duplicate instant.
        let t = TestClock.now.addingTimeInterval(-1000)
        out.append(HealthMetricSample(type: .vo2Max, value: 42, start: t, end: t, source: .oura))
        out.append(HealthMetricSample(type: .stepCount, value: 999,
                                      start: TestClock.now, end: TestClock.now, source: .oura))
        out.append(HealthMetricSample(type: .stepCount, value: 999,
                                      start: TestClock.now, end: TestClock.now, source: .oura))
        return out
    }

    /// Every metric, whether present or absent, must give the same array
    /// through the memo as through the scan.
    func testSamplesOfTypeAgreeWithAndWithoutTheMemo() {
        let samples = mixed()
        var scanned: [MetricType: [HealthMetricSample]] = [:]
        for type in MetricType.allCases {
            scanned[type] = samples.filter { $0.type == type }.sorted { $0.start < $1.start }
        }

        MultiSource.$memo.withValue(EvaluationMemo(samples)) {
            for type in MetricType.allCases {
                let viaMemo = samples.samples(of: type)
                let direct = scanned[type]!
                XCTAssertEqual(viaMemo.count, direct.count, "\(type) count differs")
                for (a, b) in zip(viaMemo, direct) {
                    XCTAssertEqual(a.value, b.value, accuracy: 1e-9, "\(type) value order differs")
                    XCTAssertEqual(a.start, b.start, "\(type) date order differs")
                    XCTAssertEqual(a.source, b.source, "\(type) source order differs")
                }
            }
        }
    }

    /// The breakdown is the one that actually depends on grouping preserving
    /// order — `deduplicate` returns oldest → newest and the source series are
    /// built without a re-sort.
    func testBreakdownsAgreeWithAndWithoutTheMemo() {
        let samples = mixed()
        var direct: [MetricType: MultiSourceBreakdown] = [:]
        for type in MetricType.allCases {
            direct[type] = MultiSource.breakdown(type, from: samples)
        }

        MultiSource.$memo.withValue(EvaluationMemo(samples)) {
            for type in MetricType.allCases {
                let viaMemo = MultiSource.breakdown(type, from: samples)
                let plain = direct[type]!
                XCTAssertEqual(viaMemo.sources.count, plain.sources.count,
                               "\(type): different number of sources")
                for (a, b) in zip(viaMemo.sources, plain.sources) {
                    XCTAssertEqual(a.source, b.source, "\(type): source identity or order differs")
                    XCTAssertEqual(a.samples.count, b.samples.count,
                                   "\(type): per-source sample count differs")
                    XCTAssertEqual(a.samples.map(\.start), b.samples.map(\.start),
                                   "\(type): per-source ordering differs")
                }
            }
        }
    }

    /// **A memo must never answer for an array it was not opened for.** The
    /// guard existed before this change and matters more after it, because a
    /// wrong answer is now served from an index rather than recomputed.
    func testAMemoRefusesADifferentArray() {
        let samples = mixed()
        let other = Array(samples.dropLast())
        MultiSource.$memo.withValue(EvaluationMemo(samples)) {
            // `other` is a different array, so this must fall through to a scan
            // and produce `other`'s answer, not the memo's.
            XCTAssertEqual(other.samples(of: .stepCount).count,
                           other.filter { $0.type == .stepCount }.count)
        }
    }

    /// The index is built lazily and reused; asking twice must not disagree
    /// with itself, which is the cheapest possible check that the cache is not
    /// being mutated under the lock.
    func testRepeatedReadsAreStable() {
        let samples = mixed()
        MultiSource.$memo.withValue(EvaluationMemo(samples)) {
            for type in [MetricType.restingHeartRate, .stepCount, .vo2Max, .bloodGlucose] {
                let first = samples.samples(of: type)
                let second = samples.samples(of: type)
                XCTAssertEqual(first.map(\.start), second.map(\.start), "\(type) changed between reads")
            }
        }
    }
}
