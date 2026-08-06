import XCTest
@testable import InsightKit

/// The energy arithmetic behind "store the dose, never the level" (backlog
/// §B5 #33), pinned against hand-computed figures — not against the model's
/// own formula, which would only prove it agrees with itself.
final class SoundDoseTests: XCTestCase {

    /// Fixed calendar so day bucketing cannot drift with the machine's zone.
    private var utc: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal
    }

    /// Midnight UTC, 2024-08-01 — 19,935 whole days after the epoch.
    private let midnight = Date(timeIntervalSince1970: 19_935 * 86_400)

    private func raw(_ identifier: String, level: Double,
                     startingSeconds: TimeInterval, seconds: TimeInterval) -> RawMetricSample {
        let start = midnight.addingTimeInterval(startingSeconds)
        return RawMetricSample(identifier: identifier, displayName: "test",
                               value: level, unit: "dBASPL",
                               start: start, end: start.addingTimeInterval(seconds),
                               source: .appleHealthDevice("Apple Watch"))
    }

    // MARK: - The energy mean, against arithmetic temptation

    /// Twelve hours at 60 dBA plus one loud minute at 90 dBA. The arithmetic
    /// mean of the two levels is 75 and the time-weighted arithmetic mean is
    /// barely over 60 — the honest equal-energy figure is neither.
    ///
    /// By hand: 43,200 s · 10⁶ + 60 s · 10⁹ = 1.032 × 10¹¹, over 43,260
    /// measured seconds is 2,385,575.6 mean intensity, and
    /// 10 · log₁₀ of that is 63.776 dBA.
    func testLEQIsTheEnergyMeanNotTheArithmeticMean() throws {
        let samples = SoundDoseModel.dailySamples(from: [
            raw(SoundDoseModel.environmentalIdentifier, level: 60,
                startingSeconds: 8 * 3600, seconds: 12 * 3600),
            raw(SoundDoseModel.environmentalIdentifier, level: 90,
                startingSeconds: 21 * 3600, seconds: 60),
        ], calendar: utc)

        let day = try XCTUnwrap(samples.first)
        XCTAssertEqual(samples.count, 1)
        XCTAssertEqual(day.value, 63.776, accuracy: 0.005)
        // The two failure modes this metric exists to avoid, named:
        XCTAssertNotEqual(day.value, 75, accuracy: 5, "averaged the levels")
        XCTAssertNotEqual(day.value, 60.04, accuracy: 1, "time-weighted the levels, not the energy")
    }

    /// A constant level is its own LEQ, whatever the duration — the identity
    /// any correct implementation must satisfy exactly.
    func testAConstantDayIsItsOwnEquivalentLevel() throws {
        let samples = SoundDoseModel.dailySamples(from: [
            raw(SoundDoseModel.headphoneIdentifier, level: 85,
                startingSeconds: 9 * 3600, seconds: 8 * 3600),
        ], calendar: utc)
        XCTAssertEqual(try XCTUnwrap(samples.first).value, 85, accuracy: 1e-9)
    }

    /// Four hours at 88 and four at 82. Equal durations, so by hand:
    /// (10⁸·⁸ + 10⁸·²) / 2 = 3.94723 × 10⁸, and 10 · log₁₀ gives 85.963 dBA —
    /// almost a decibel above the 85 midpoint, because the louder half
    /// carries four times the energy of the quieter one.
    func testHandComputedTwoBlockFixture() throws {
        let samples = SoundDoseModel.dailySamples(from: [
            raw(SoundDoseModel.headphoneIdentifier, level: 88,
                startingSeconds: 9 * 3600, seconds: 4 * 3600),
            raw(SoundDoseModel.headphoneIdentifier, level: 82,
                startingSeconds: 14 * 3600, seconds: 4 * 3600),
        ], calendar: utc)
        XCTAssertEqual(try XCTUnwrap(samples.first).value, 85.963, accuracy: 0.005)
    }

    // MARK: - Never one figure

    /// Environmental and headphone samples on the same day produce two
    /// samples of two metrics, each carrying only its own sensor's energy —
    /// the original refusal's surviving rule, held by construction.
    func testEnvironmentalAndHeadphoneAreNeverSummedTogether() {
        let samples = SoundDoseModel.dailySamples(from: [
            raw(SoundDoseModel.environmentalIdentifier, level: 60,
                startingSeconds: 10 * 3600, seconds: 3600),
            raw(SoundDoseModel.headphoneIdentifier, level: 90,
                startingSeconds: 10 * 3600, seconds: 3600),
        ], calendar: utc)

        XCTAssertEqual(samples.count, 2)
        let byType = Dictionary(uniqueKeysWithValues: samples.map { ($0.type, $0.value) })
        XCTAssertEqual(byType[.environmentalSoundDose] ?? 0, 60, accuracy: 1e-9)
        XCTAssertEqual(byType[.headphoneSoundDose] ?? 0, 90, accuracy: 1e-9)
    }

    // MARK: - Day bucketing

    func testEachDayGetsItsOwnSample() {
        let samples = SoundDoseModel.dailySamples(from: [
            raw(SoundDoseModel.environmentalIdentifier, level: 70,
                startingSeconds: 10 * 3600, seconds: 3600),
            raw(SoundDoseModel.environmentalIdentifier, level: 80,
                startingSeconds: 34 * 3600, seconds: 3600),   // next day, 10:00
        ], calendar: utc)

        XCTAssertEqual(samples.count, 2)
        XCTAssertEqual(samples.map(\.value), [70, 80])
        XCTAssertEqual(samples.map(\.start),
                       [midnight, midnight.addingTimeInterval(86_400)])
    }

    // MARK: - Provenance and hygiene

    func testEverySampleSaysItWasWorkedOutByThisApp() {
        let samples = SoundDoseModel.dailySamples(from: [
            raw(SoundDoseModel.environmentalIdentifier, level: 70,
                startingSeconds: 3600, seconds: 3600),
            raw(SoundDoseModel.headphoneIdentifier, level: 70,
                startingSeconds: 3600, seconds: 3600),
        ], calendar: utc)
        XCTAssertFalse(samples.isEmpty)
        for sample in samples {
            XCTAssertEqual(sample.source, .calculated)
        }
    }

    /// Unrelated identifiers, text values, placeholder zeros and the
    /// catalogue's famous 170,000-style unit slip all stay out of the energy
    /// sum — the slip especially, because 10^(170000/10) is not a big number
    /// but an infinite one, and it would take the whole series with it.
    func testGarbageNeverReachesTheEnergySum() throws {
        let samples = SoundDoseModel.dailySamples(from: [
            raw(SoundDoseModel.environmentalIdentifier, level: 60,
                startingSeconds: 10 * 3600, seconds: 3600),
            raw(SoundDoseModel.environmentalIdentifier, level: 0,
                startingSeconds: 11 * 3600, seconds: 3600),
            raw(SoundDoseModel.environmentalIdentifier, level: 170_000,
                startingSeconds: 12 * 3600, seconds: 60),
            raw("HKQuantityTypeIdentifierUVExposure", level: 90,
                startingSeconds: 10 * 3600, seconds: 3600),
            RawMetricSample(identifier: SoundDoseModel.headphoneIdentifier,
                            displayName: "test", value: .text("loud"),
                            unit: "", start: midnight, source: .oura),
        ], calendar: utc)

        XCTAssertEqual(samples.count, 1)
        XCTAssertEqual(try XCTUnwrap(samples.first).value, 60, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(samples.first).type, .environmentalSoundDose)
    }

    /// An instantaneous sample still holds a measured level; it gets a nominal
    /// second of weight rather than silently vanishing.
    func testAZeroDurationSampleStillCounts() throws {
        let samples = SoundDoseModel.dailySamples(from: [
            raw(SoundDoseModel.headphoneIdentifier, level: 72,
                startingSeconds: 10 * 3600, seconds: 0),
        ], calendar: utc)
        XCTAssertEqual(try XCTUnwrap(samples.first).value, 72, accuracy: 1e-9)
    }

    // MARK: - Idempotence, the TemperatureReconstructor property

    /// Running the merge twice must not stack two copies of a day, and a stale
    /// previous derivation must be replaced, not joined — the same
    /// strip-then-rebuild contract `refreshMedicationLevelSamples` keeps.
    func testMergingTwiceChangesNothingAndStaleDerivationsAreReplaced() {
        let rawPile = [
            raw(SoundDoseModel.environmentalIdentifier, level: 65,
                startingSeconds: 10 * 3600, seconds: 2 * 3600),
        ]
        // A canonical sample that must survive, and a stale derived figure
        // that must not.
        let existing = [
            HealthMetricSample(type: .heartRate, value: 60,
                               start: midnight, source: .oura),
            HealthMetricSample(type: .environmentalSoundDose, value: 120,
                               start: midnight, source: .calculated),
        ]

        let once = SoundDoseModel.withSoundDose(existing, raw: rawPile, calendar: utc)
        let twice = SoundDoseModel.withSoundDose(once, raw: rawPile, calendar: utc)

        XCTAssertEqual(once.count, 2, "one vital kept, one dose derived, stale dose gone")
        XCTAssertEqual(once.filter { $0.type == .environmentalSoundDose }.map(\.value), [65])
        XCTAssertTrue(once.contains { $0.type == .heartRate })
        XCTAssertEqual(twice.count, once.count)
        XCTAssertEqual(twice.map(\.type), once.map(\.type))
        XCTAssertEqual(twice.map(\.value), once.map(\.value))
        XCTAssertEqual(twice.map(\.start), once.map(\.start))
    }

    /// No samples, no figure — never a zero. A silent day and an unworn watch
    /// are indistinguishable in this data, and only one of them is quiet.
    func testADayWithNoSamplesProducesNothing() {
        XCTAssertTrue(SoundDoseModel.dailySamples(from: [], calendar: utc).isEmpty)
    }
}
