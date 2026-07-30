import XCTest
@testable import InsightKit

/// Core and skin temperature are different measurements, and for a long time
/// this app held them in one `MetricType`. Every test here fails against the
/// code as it stood before `.skinTemperature` existed.
///
/// The faults, in the order they were found:
///
/// 1. `bodyTemperature`'s lower bound (35.5 °C) was *exactly*
///    `TemperatureReconstructor.defaultBaselineCelsius`, so `value < hardLow`
///    reduced to `deviation < 0` — half of all nights.
/// 2. Its upper bound needed a +2.3 °C deviation, well past what the app itself
///    calls implausible, so a genuine fever never tripped it.
/// 3. Reconstruction is additive and a constant shift leaves the spread alone,
///    so the deviation and its reconstruction carried identical z-scores and one
///    signal was penalised twice.
/// 4. Whoop and Withings type 73 report absolute *skin* °C into the same metric,
///    which sits permanently below the core floor.
/// 5. Worst: the reconstructed series competed with a real thermometer for the
///    same metric, and the source with the most history wins — so a wearable's
///    long run of nights displaced a 38.5 °C fever and the card read "All
///    normal".
final class ThermalProvenanceTests: XCTestCase {

    private let now = TestClock.now
    private let calendar = TestClock.utc
    private func day(_ n: Int) -> Date { TestClock.day(n) }

    /// One reading per day, newest last, ending today.
    private func series(_ type: MetricType, _ values: [Double],
                        source: MetricSource) -> [HealthMetricSample] {
        values.enumerated().map { index, value in
            HealthMetricSample(type: type, value: value,
                               start: day(values.count - 1 - index), source: source)
        }
    }

    /// A fortnight of ordinary nightly deviations, jittering either side of
    /// baseline, with `today` as the final night.
    private func ouraNights(today: Double, days: Int = 15) -> [HealthMetricSample] {
        let history = (0..<(days - 1)).map { Double($0 % 3) * 0.2 - 0.2 }
        return series(.skinTemperatureDeviation, history + [today], source: .oura)
    }

    private func evaluate(_ samples: [HealthMetricSample]) -> VitalSignsCheck.Output {
        VitalSignsCheck.evaluate(samples: samples, now: now, calendar: calendar)
    }

    private func reading(_ output: VitalSignsCheck.Output,
                         _ metric: MetricType) -> VitalSignsCheck.Reading? {
        output.readings.first { $0.metric == metric }
    }

    // MARK: - Fault 1: an ordinary cool night was an alarm

    func testAnOrdinaryCoolNightIsNotReportedAsUnusual() {
        let output = evaluate(
            TemperatureReconstructor.withReconstructedTemperature(ouraNights(today: -0.1)))
        XCTAssertTrue(output.unusual.isEmpty,
                      "a −0.1 °C night flagged: \(output.unusual.map(\.metric))")
        XCTAssertGreaterThan(output.score ?? 0, 80)
    }

    // MARK: - Fault 2: skin data must not invent a core reading

    func testSkinDataNeverInventsACoreTemperatureRow() {
        let output = evaluate(
            TemperatureReconstructor.withReconstructedTemperature(ouraNights(today: 1.2)))
        XCTAssertNil(reading(output, .bodyTemperature),
                     "a ring that only reports deviations produced a core temperature row")
        XCTAssertEqual(reading(output, .skinTemperatureDeviation)?.status, .unusual)
    }

    // MARK: - Fault 3: one signal, one row

    func testOneThermalSignalProducesOneRow() {
        let deviations = ouraNights(today: 0.35)
        let output = evaluate(TemperatureReconstructor.withReconstructedTemperature(deviations))
        XCTAssertEqual(output.readings.filter { $0.metric.family == .thermal }.count, 1)
    }

    /// The sharper statement of the same thing: reconstruction is a *rendering*
    /// of the deviation, so adding it must not move the score at all.
    func testReconstructionIsScoreNeutral() {
        let deviations = ouraNights(today: 0.35)
        let withRecon = evaluate(TemperatureReconstructor.withReconstructedTemperature(deviations))
        let devsOnly = evaluate(deviations)
        XCTAssertEqual(try XCTUnwrap(withRecon.score), try XCTUnwrap(devsOnly.score), accuracy: 1e-9)
    }

    // MARK: - Fault 4: an absolute skin series is not hypothermia

    /// Nightly wrist skin temperature, jittering either side of 33.5 °C with
    /// today sitting on the mean — an ordinary week for a Whoop wearer.
    private func whoopNights(today: Double = 33.5, days: Int = 15) -> [HealthMetricSample] {
        let history = (0..<(days - 1)).map { 33.5 + Double($0 % 4) * 0.2 - 0.3 }
        return series(.skinTemperature, history + [today], source: .whoop)
    }

    func testWhoopSkinTemperatureIsNotJudgedAgainstCoreBounds() {
        let output = evaluate(whoopNights())
        XCTAssertEqual(reading(output, .skinTemperature)?.status, .normal)
        XCTAssertGreaterThan(output.score ?? 0, 80)
    }

    /// A Whoop user has no deviation metric, so nothing supersedes the absolute
    /// and they keep a thermal row rather than losing the signal entirely.
    func testAnAbsoluteOnlyUserStillGetsAThermalRow() {
        XCTAssertNotNil(reading(evaluate(whoopNights()), .skinTemperature))
    }

    // MARK: - Fault 5: a real fever must not be displaced by a wearable

    func testARealThermometerFeverIsNotDisplacedByAWearable() {
        var samples = TemperatureReconstructor.withReconstructedTemperature(ouraNights(today: 0.1, days: 28))
        // A shorter run of genuine oral readings, ending in a fever today.
        samples += series(.bodyTemperature, [36.6, 36.7, 36.6, 36.5, 36.7, 36.6, 36.6, 38.5],
                          source: .manual)
        let output = evaluate(samples)
        let core = reading(output, .bodyTemperature)
        XCTAssertEqual(core?.value ?? 0, 38.5, accuracy: 1e-9,
                       "the thermometer reading was displaced by the reconstructed ring series")
        XCTAssertEqual(core?.status, .unusual)
        XCTAssertNotEqual(output.headline, "All normal")
    }

    // MARK: - Structural pins, so none of the above can quietly come back

    /// `supersededBy` is resolved against the readings gathered so far, so the
    /// superseding spec has to be scanned first. Nothing in the type system says
    /// so; this is the only thing standing between a future reorder and the
    /// silent return of double-counting.
    func testASupersededSpecComesAfterTheOneThatSupersedesIt() {
        for (index, spec) in VitalSignsCheck.specs.enumerated() {
            guard let better = spec.supersededBy else { continue }
            let source = VitalSignsCheck.specs.firstIndex { $0.metric == better }
            XCTAssertNotNil(source, "\(spec.metric) is superseded by a metric with no spec")
            if let source {
                XCTAssertLessThan(source, index,
                                  "\(better) must be scanned before \(spec.metric)")
            }
        }
    }

    /// The original bug stated as an invariant rather than a coincidence.
    ///
    /// `bodyTemperature`'s floor is still 35.5 °C and that is correct — it is
    /// half a degree above the definition of hypothermia. It was only ever
    /// harmful because it also happened to equal the skin baseline that
    /// reconstruction added its deviations to, which turned "is this value low"
    /// into "is this deviation negative". What has to hold is that reconstructed
    /// values never reach that bound at all.
    func testReconstructionNeverWritesIntoACoreBoundedMetric() {
        let deviations = ouraNights(today: -0.1)
        let reconstructed = TemperatureReconstructor.reconstruct(from: deviations)
        XCTAssertFalse(reconstructed.isEmpty)
        for sample in reconstructed {
            let spec = VitalSignsCheck.specs.first { $0.metric == sample.type }
            XCTAssertNil(spec?.hardLow,
                         "reconstructed values land in \(sample.type), which has an absolute floor")
            XCTAssertNil(spec?.hardHigh,
                         "reconstructed values land in \(sample.type), which has an absolute ceiling")
        }
    }

    /// Skin has no defensible absolute bound — it tracks ambient warmth and
    /// bedding — which is exactly why the wearables publish a deviation.
    func testAbsoluteSkinTemperatureIsJudgedOnTheBaselineAlone() {
        let spec = VitalSignsCheck.specs.first { $0.metric == .skinTemperature }
        XCTAssertNotNil(spec)
        XCTAssertNil(spec?.hardLow)
        XCTAssertNil(spec?.hardHigh)
    }
}

/// Withings sends body and skin temperature as two different measure types and
/// they were sharing one `MetricType`.
final class WithingsThermalRoutingTests: XCTestCase {
    func testSkinAndBodyTemperatureAreSeparateMeasures() {
        XCTAssertEqual(WithingsResponseParser.metricType(for: 71), .bodyTemperature)
        XCTAssertEqual(WithingsResponseParser.metricType(for: 73), .skinTemperature)
    }
}
