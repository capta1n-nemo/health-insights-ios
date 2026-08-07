import XCTest
@testable import InsightKit

private let basalNow = TestClock.now
private let basalCalendar = TestClock.utc

/// **The morning thermometer as the symptom radar's standby thermal channel** —
/// backlog R33.
///
/// The row's own finding, against the reader's export: `MenstrualFlow` and
/// `SexualActivity` are zero rows, while `basalBodyTemperature` carries 136
/// records over 124 days, 80 of the last 90, written deliberately through a
/// Shortcut and read by nothing at all. Its value is not a cycle card — it is
/// that **it survives a night the ring was off, which is exactly the night the
/// radar goes blind on its most specific signal.**
///
/// Four things have to be true for that to be an improvement rather than a
/// dressed-up regression, and each has a test here:
///
/// 1. On a day with no wearable temperature, the thermal channel still votes.
/// 2. On a day with one, the wearable votes and the thermometer does not
///    displace it — however hard the thermometer leans.
/// 3. The displaced reading is still *shown*: it lands in `discounted`, which
///    the radar web draws as an open dot.
/// 4. The exact zeros the Shortcut writes for "no reading" — 35 of the 136 —
///    never reach a baseline.
final class BasalTemperatureChannelTests: XCTestCase {

    // MARK: - Fixtures

    private func nights(_ metric: MetricType, _ values: [Double],
                        source: MetricSource = .oura) -> [HealthMetricSample] {
        values.enumerated().map { index, value in
            HealthMetricSample(type: metric, value: value,
                               start: TestClock.day(values.count - 1 - index),
                               source: source)
        }
    }

    /// The same shape `SymptomRadarTests.history` uses, minus the thermal
    /// series — so a test can supply whichever temperature it is about.
    private func historyWithoutTemperature(days: Int = 40,
                                           illWindow: ClosedRange<Int>? = nil)
        -> [HealthMetricSample] {
        var samples: [HealthMetricSample] = []
        func series(_ metric: MetricType, healthy: Double, ill: Double, jitter: Double) {
            let values = (0..<days).map { index -> Double in
                let daysAgo = days - 1 - index
                let base = (illWindow?.contains(daysAgo) ?? false) ? ill : healthy
                return base + Double(index % 3) * jitter - jitter
            }
            samples += nights(metric, values)
        }
        series(.restingHeartRate, healthy: 55, ill: 62, jitter: 1.2)
        series(.heartRateVariabilityRMSSD, healthy: 46, ill: 32, jitter: 2.5)
        series(.respiratoryRate, healthy: 14, ill: 16.5, jitter: 0.3)
        return samples
    }

    /// A morning thermometer series: flat at 36.4 °C, warm across `illWindow`.
    private func basal(days: Int = 40, illWindow: ClosedRange<Int>? = nil,
                       healthy: Double = 36.4, ill: Double = 37.1)
        -> [HealthMetricSample] {
        let values = (0..<days).map { index -> Double in
            let daysAgo = days - 1 - index
            let base = (illWindow?.contains(daysAgo) ?? false) ? ill : healthy
            return base + Double(index % 3) * 0.06 - 0.06
        }
        return nights(.basalBodyTemperature, values, source: .manual)
    }

    private func signal(_ metric: MetricType, _ z: Double,
                        concerning: Bool = true) -> HealthWatchModel.Signal {
        HealthWatchModel.Signal(metric: metric, recent: 0, reference: 0,
                                zScore: z, isConcerning: concerning)
    }

    // MARK: - 1. The night the ring was off

    /// **The whole point of the row.** With no wearable temperature at all, the
    /// radar used to have no thermal channel — its most specific signal — and
    /// this is a straight before/after on the same fixture.
    func testTheThermalChannelSurvivesANightNothingWasWorn() throws {
        let samples = historyWithoutTemperature(illWindow: 0...3) + basal(illWindow: 0...3)
        let output = try XCTUnwrap(HealthWatchModel.evaluate(
            samples: samples, now: basalNow, calendar: basalCalendar))

        XCTAssertTrue(output.signals.contains { $0.metric == .basalBodyTemperature },
                      "with no wearable temperature the thermal channel did not vote at all")
        XCTAssertTrue(output.signals.contains {
            $0.metric == .basalBodyTemperature && $0.isLeaning
        }, "a 0.7 °C rise over a flat baseline did not register as leaning")

        // And the same fixture without the thermometer is the blind night this
        // closes: no thermal signal at any strength.
        let blind = try XCTUnwrap(HealthWatchModel.evaluate(
            samples: historyWithoutTemperature(illWindow: 0...3),
            now: basalNow, calendar: basalCalendar))
        XCTAssertFalse(blind.signals.contains { $0.metric.family == .thermal },
                       "fixture is wrong — it already had a temperature to read")
        XCTAssertLessThan(output.score, blind.score,
                          "adding a raised morning temperature did not make the card more worried")
    }

    // MARK: - 2. A standby never displaces a first choice

    /// ⚠️ **The calibration rule.** `collapsingDuplicates` keeps whichever of a
    /// same-basis pair leans harder, and that maximum is not the statistic the
    /// null assumes. Measured on 400,000 simulated well days through the real
    /// path: letting the thermometer win moved the 99.45th percentile of the
    /// joint statistic from 3.35 to 3.74, took the strong band from about two
    /// false alarms a year to 4.8, and cut the accumulation's in-control run
    /// length from over 300 days to 116. `standbyMetrics` is what stops it.
    func testTheThermometerNeverTakesTheChannelOffTheRing() {
        let collapsed = HealthWatchModel.collapsingDuplicates([
            signal(.skinTemperatureDeviation, 0.4),
            signal(.basalBodyTemperature, 2.9),
            signal(.restingHeartRate, 0.3)
        ])
        let thermal = collapsed.filter { $0.metric.family == .thermal }
        XCTAssertEqual(thermal.count, 1, "two temperatures voted as two channels")
        XCTAssertEqual(thermal.first?.metric, .skinTemperatureDeviation,
                       "the standby displaced the instrument it exists to stand in for")
    }

    /// The mirror: order of arrival must not decide it either. The same pair,
    /// listed the other way round, collapses to the same winner.
    func testTheOrderTheSignalsArriveInDoesNotDecideTheChannel() {
        for pair in [[signal(.basalBodyTemperature, 2.9), signal(.skinTemperatureDeviation, 0.4)],
                     [signal(.skinTemperatureDeviation, 0.4), signal(.basalBodyTemperature, 2.9)]] {
            XCTAssertEqual(HealthWatchModel.collapsingDuplicates(pair).first?.metric,
                           .skinTemperatureDeviation)
        }
    }

    /// And where there is no first choice, the standby is simply the channel —
    /// with no selection happening at all, so nothing is inflated.
    func testWithNoWearableTheStandbyIsTheChannel() {
        let collapsed = HealthWatchModel.collapsingDuplicates([
            signal(.basalBodyTemperature, 2.1),
            signal(.restingHeartRate, 0.3)
        ])
        XCTAssertEqual(collapsed.filter { $0.metric.family == .thermal }.first?.metric,
                       .basalBodyTemperature)
    }

    /// Between two *first-choice* thermal readings the old rule is untouched:
    /// whichever leans harder still wins. A standby rule that quietly changed
    /// the wearable pair's behaviour would have moved the calibration by a
    /// different door.
    func testTwoWearableTemperaturesStillCollapseToWhicheverLeansHarder() {
        let collapsed = HealthWatchModel.collapsingDuplicates([
            signal(.skinTemperatureDeviation, 0.4),
            signal(.skinTemperature, 1.8)
        ])
        XCTAssertEqual(collapsed.first?.metric, .skinTemperature)
    }

    // MARK: - 3. Counted once must not render as not looked at

    func testTheDisplacedReadingIsStillCarriedForTheWebToDraw() throws {
        let output = try XCTUnwrap(HealthWatchModel.output(fromEvaluated: [
            signal(.skinTemperatureDeviation, 0.4),
            signal(.basalBodyTemperature, 2.9),
            signal(.restingHeartRate, 0.3),
            signal(.respiratoryRate, 0.2)
        ]))
        XCTAssertTrue(output.discounted.contains { $0.metric == .basalBodyTemperature },
                      "the thermometer's reading vanished rather than being shown as counted once")
    }

    // MARK: - 4. The zeros are not temperatures

    /// ⚠️ **35 of the reader's 136 records are exact zeros meaning "no
    /// reading".** While the identifier arrived raw, `RawMetricSample
    /// .placeholderZeroIdentifiers` censored them. Promoted to a metric, the
    /// censor is `requiresPositiveValue`, applied by `sanitizedVitals()` on the
    /// ingest path — and a zero surviving it would drag the baseline down every
    /// single time, which is the one failure that would make this channel worse
    /// than no channel.
    func testThePlaceholderZerosAreCensoredBeforeTheyReachABaseline() {
        XCTAssertTrue(MetricType.basalBodyTemperature.requiresPositiveValue)

        var samples = basal()
        // A quarter of them written as the Shortcut's "nothing to report".
        samples = samples.enumerated().map { index, sample in
            index % 4 == 0
                ? HealthMetricSample(type: .basalBodyTemperature, value: 0,
                                     start: sample.start, source: .manual)
                : sample
        }
        let kept = samples.sanitizedVitals()
        XCTAssertFalse(kept.contains { $0.value == 0 },
                       "a placeholder zero survived into the vitals the baselines are built from")
        XCTAssertEqual(kept.count, samples.filter { $0.value > 0 }.count)
        let mean = try? XCTUnwrap(Baseline.mean(kept.map(\.value)))
        XCTAssertNotNil(mean)
        XCTAssertGreaterThan(mean ?? 0, 35, "the zeros dragged the baseline down anyway")
    }

    /// The identifier keeps its raw-lane censor too. It no longer arrives that
    /// way from HealthKit — it moved to `readMap` — but a file import or an
    /// older cache can still carry it, and removing the entry would let those
    /// zeros through a door the promotion did not close.
    func testTheRawLaneStillNamesTheIdentifier() {
        XCTAssertTrue(RawMetricGroup.placeholderZeroIdentifiers
            .contains("HKQuantityTypeIdentifierBasalBodyTemperature"))
    }

    // MARK: - The metric itself

    /// It must not be judged against the daytime oral band. A basal reading is
    /// taken at the circadian trough, so 36.1–37.2 °C would shade an ordinary
    /// morning as borderline-low day after day.
    func testItCarriesNoReferenceBand() {
        XCTAssertNil(MetricType.basalBodyTemperature.referenceRange)
        XCTAssertNotNil(MetricType.bodyTemperature.referenceRange,
                        "fixture is wrong — the core band is what this one must not borrow")
    }

    /// Same family as the wearable temperatures, which is what makes the
    /// collapse happen at all. If this ever stops being true the standby rule
    /// silently becomes a fifth voting channel.
    func testItSharesAMeasurementBasisWithTheWearableTemperatures() {
        for other in [MetricType.skinTemperatureDeviation, .skinTemperature, .bodyTemperature] {
            XCTAssertTrue(MetricType.basalBodyTemperature.sharesMeasurementBasis(with: other),
                          "\(other) would vote alongside the morning thermometer")
        }
    }
}
