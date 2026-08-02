import XCTest
@testable import InsightKit

/// Readiness, Heart Health and Resting Heart Rate each built their own baseline
/// by hand — `series.last` against `series.dropLast()` — and each inherited the
/// same defects Vitals Check was fixed for. These tests pin the behaviour after
/// moving all three onto `VitalReader`.
///
/// Every fixture here is anchored to **local noon**, because the reader buckets
/// by `Calendar.current`. Intra-day samples sit within an hour of noon so they
/// land in one bucket whatever timezone CI runs in.
final class SharedBaselineTests: XCTestCase {

    private let calendar = Calendar.current

    /// Local noon, `back` days ago, relative to a fixed reference.
    private func day(_ back: Int) -> Date {
        let reference = Date(timeIntervalSince1970: 1_800_000_000)
        let noon = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: reference)!
        return noon.addingTimeInterval(-Double(back) * 86_400)
    }

    private var now: Date { day(0) }

    private func sample(_ type: MetricType, _ value: Double, _ back: Int,
                        minutes: Double = 0, source: MetricSource = .oura) -> HealthMetricSample {
        HealthMetricSample(type: type, value: value,
                           start: day(back).addingTimeInterval(minutes * 60), source: source)
    }

    private func profile() -> UserHealthProfile {
        var p = UserHealthProfile()
        p.set(.init(kind: .dateOfBirth,
                    value: now.addingTimeInterval(-40 * 365.25 * 86_400).timeIntervalSince1970,
                    recordedAt: now))
        p.set(.init(kind: .biologicalSex, value: 0, recordedAt: now))
        return p
    }

    // MARK: - Readiness

    /// The defect: `history(.heartRateVariabilityRMSSD).last` is the newest raw
    /// sample. HRV arrives many times a night, so a single artefact reading at
    /// the end of the series was being reported as the whole night's HRV, and
    /// readiness crashed on it. The day's representative value doesn't move.
    func testOneArtefactReadingDoesNotBecomeTheWholeDay() throws {
        var samples: [HealthMetricSample] = []
        // Sixty readings a night, which is the order a wearable actually
        // records at — the defect is invisible at one sample per day, which is
        // the only shape the existing fixtures had.
        for back in 1...10 {
            for i in 0..<60 {
                samples.append(sample(.heartRateVariabilityRMSSD, 58 + Double(back % 3),
                                      back, minutes: Double(i)))
            }
        }
        // Today: an ordinary night, except the last reading recorded is junk.
        samples += (0..<60).map { sample(.heartRateVariabilityRMSSD, 60, 0, minutes: Double($0)) }
        samples.append(sample(.heartRateVariabilityRMSSD, 20, 0, minutes: 60))

        let out = try XCTUnwrap(ReadinessScore.evaluate(samples: samples, now: now))
        let hrv = try XCTUnwrap(out.components.first { $0.name.hasPrefix("HRV") })
        // The night averages ~59 against a baseline of 59 — unremarkable.
        // Reading the artefact as "today's HRV" scores it at zero instead.
        XCTAssertGreaterThan(hrv.score, 50,
                             "one bad reading at the end of the night is not the night")
    }

    /// Readiness is a claim about today. A component whose last reading is a
    /// week old was being counted as current, and it also bought the card its
    /// `.high` confidence.
    func testAStaleComponentIsNotCountedAsToday() throws {
        var samples = (7...17).map { sample(.heartRateVariabilityRMSSD, 58 + Double($0 % 3), $0) }
        samples += (0...10).map { sample(.restingHeartRate, 55 + Double($0 % 3), $0) }

        let out = try XCTUnwrap(ReadinessScore.evaluate(samples: samples, now: now))
        let names = Set(out.components.map(\.name))
        XCTAssertTrue(names.contains { $0.hasPrefix("Resting HR") })
        XCTAssertFalse(names.contains { $0.hasPrefix("HRV") },
                       "HRV last measured a week ago says nothing about this morning")
    }

    /// The same signal arriving from a second device must not change the
    /// verdict. Pooling both series made the gap between two instruments the
    /// standard deviation, which is inter-device disagreement, not physiology.
    func testASecondDeviceDoesNotChangeTheVerdict() {
        let oura = (0...20).map { sample(.restingHeartRate, 55 + Double($0 % 3), $0) }
        // A watch that has only been worn three days, and reads 6 bpm high.
        let watch = (0...2).map {
            sample(.restingHeartRate, 61 + Double($0 % 3), $0, source: .appleHealth)
        }

        let alone = ReadinessScore.evaluate(samples: oura, now: now)
        let both = ReadinessScore.evaluate(samples: oura + watch, now: now)
        XCTAssertNotNil(alone)
        XCTAssertEqual(alone?.score ?? 0, both?.score ?? -1, accuracy: 1e-9,
                       "the device with the established baseline is the one to trust")
    }

    // MARK: - Heart Health

    /// The defect: resting heart rate came from `meanValue`, the mean of every
    /// sample ever recorded. These two fixtures have **identical all-time
    /// means** and opposite recent histories, so under the old code they scored
    /// exactly the same. A real improvement has to move the number.
    func testHeartHealthReadsRecentRestingHeartRateNotTheAllTimeMean() {
        func fixture(recent: Double, earlier: Double) -> [HealthMetricSample] {
            var out: [HealthMetricSample] = []
            for back in 0...59 { out.append(sample(.restingHeartRate, recent, back)) }
            for back in 60...119 { out.append(sample(.restingHeartRate, earlier, back)) }
            // Identical in both fixtures, so resting heart rate is the only
            // thing that differs.
            for back in stride(from: 0, through: 119, by: 7) {
                out.append(sample(.vo2Max, 44, back))
            }
            return out
        }
        let improving = fixture(recent: 50, earlier: 70)   // all-time mean 60
        let worsening = fixture(recent: 70, earlier: 50)   // all-time mean 60

        let better = HeartHealthInsight().evaluate(samples: improving, profile: profile(), now: now)
        let worse = HeartHealthInsight().evaluate(samples: worsening, profile: profile(), now: now)
        XCTAssertNotNil(better.score)
        XCTAssertGreaterThan(better.score ?? 0, worse.score ?? 100,
                             "same all-time mean, opposite recent trends — these cannot score alike")
    }

    /// Shaped like the 2026-08-02 card outputs: "Resting heart rate: 58 bpm"
    /// four rows above "Resting Heart Rate 60 — top 25% for your age and sex" —
    /// one metric, two values, nothing on screen saying why they differ. The
    /// centile now folds into the component's own line.
    func testDriversNameEachMetricOnce() {
        var samples: [HealthMetricSample] = []
        for back in 0...30 {
            samples.append(sample(.restingHeartRate, 58, back))
            samples.append(sample(.heartRateVariabilityRMSSD, 70, back))
        }
        for back in stride(from: 0, through: 60, by: 7) {
            samples.append(sample(.vo2Max, 31, back))
        }
        let result = HeartHealthInsight().evaluate(samples: samples, profile: profile(), now: now)

        for needle in ["resting heart", "vo₂max", "hrv"] {
            let mentions = result.drivers.filter { $0.lowercased().contains(needle) }
            XCTAssertLessThanOrEqual(mentions.count, 1,
                                     "\(needle) reaches the reader twice: \(mentions)")
        }
        let folded = result.drivers.first { $0.lowercased().contains("vo₂max") }
        XCTAssertTrue(folded?.contains("for your age and sex") == true,
                      "the centile phrase survives the fold: \(folded ?? "nil")")
    }

    /// A recovery reading whose baseline is still building must not vanish from
    /// every list on the card. Declared with day-old data, it appeared in
    /// neither the weighted shares nor "charted, not scored" — the invisible
    /// middle state the why-rows exist to forbid.
    func testRecoveryWithoutABaselineIsTrackedNotSilentlyDropped() throws {
        var samples: [HealthMetricSample] = []
        for back in 0...30 {
            samples.append(sample(.restingHeartRate, 58, back))
        }
        for back in stride(from: 0, through: 60, by: 7) {
            samples.append(sample(.vo2Max, 31, back))
        }
        // One recovery reading — data, but nothing to build a baseline from.
        samples.append(sample(.heartRateRecovery, 25, 1))

        let result = HeartHealthInsight().evaluate(samples: samples, profile: profile(), now: now)
        let recovery = try XCTUnwrap(
            result.contributors.first { $0.metric == .heartRateRecovery },
            "the reading exists — it must appear somewhere on the card")
        XCTAssertEqual(recovery.weight, 0, "no baseline, no share")
        XCTAssertTrue(recovery.detail.contains("tracked, not scored"),
                      "the row says why: \(recovery.detail)")
    }

    // MARK: - Resting Heart Rate trend

    // The three tests that stood here exercised the Resting Heart Rate card:
    // that it scored at all, that upward drift scored below downward drift, and
    // that its score combined level with drift.
    //
    // That card is gone. Resting heart rate was never unique to it — it is a
    // scored component of Heart Health and a read of Readiness, Blood Pressure,
    // Energy and Fitness — so what the merge dropped is the *trend framing*,
    // along with `RestingHeartRateTrendInsight.score(z:weeklyDrift:)`, which
    // nothing else called. Deleted rather than repointed: asserting Heart Health
    // emits "Trending up" would be testing a behaviour that no longer exists.
}
