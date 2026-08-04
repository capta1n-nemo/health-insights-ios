import XCTest
@testable import InsightKit

/// The seed exists so a Mac session can look at a chart. It is only worth having
/// if what it produces could have arrived through the real ingest path and is
/// the same every time — otherwise a screenshot proves nothing and cannot be
/// compared against the next one.
final class SyntheticSeedTests: XCTestCase {

    private let cal = TestClock.utc

    func testItGeneratesSomethingForEveryDayAsked() {
        let samples = SyntheticSeed.samples(days: 30, endingOn: TestClock.now, calendar: cal)
        let days = Set(samples.map { cal.startOfDay(for: $0.start) })
        XCTAssertEqual(days.count, 30, "a day with no samples is a gap in every chart")
    }

    func testZeroDaysIsEmptyRatherThanACrash() {
        XCTAssertTrue(SyntheticSeed.samples(days: 0, endingOn: TestClock.now, calendar: cal).isEmpty)
        XCTAssertTrue(SyntheticSeed.samples(days: -5, endingOn: TestClock.now, calendar: cal).isEmpty)
    }

    /// **The property that makes a screenshot comparable.** A fixture that
    /// changes between runs turns every visual diff into noise.
    func testItIsDeterministic() {
        let a = SyntheticSeed.samples(days: 20, endingOn: TestClock.now, calendar: cal)
        let b = SyntheticSeed.samples(days: 20, endingOn: TestClock.now, calendar: cal)
        XCTAssertEqual(a.count, b.count)
        for (x, y) in zip(a, b) {
            XCTAssertEqual(x.type, y.type)
            XCTAssertEqual(x.value, y.value, accuracy: 1e-9)
            XCTAssertEqual(x.start, y.start)
        }
    }

    /// **Everything it emits must be something the app would have accepted.**
    ///
    /// `ShortcutIngest` drops a value outside the metric's `plausibleRange`, so
    /// a generator that ignored those bounds would quietly produce a series the
    /// real ingest path would have refused — a fixture proving something about
    /// a route nobody uses. Same trap as a test suite that only passes in UTC.
    func testEveryValueIsInsideTheMetricsOwnPlausibleRange() {
        for sample in SyntheticSeed.samples(days: 120, endingOn: TestClock.now, calendar: cal) {
            if let range = sample.type.plausibleRange {
                XCTAssertTrue(range.contains(sample.value),
                              "\(sample.type) generated \(sample.value), outside its own plausible range — the real ingest would drop it")
            }
            if sample.type.requiresPositiveValue {
                XCTAssertGreaterThan(sample.value, 0, "\(sample.type) must be positive")
            }
        }
    }

    /// The shapes the charts exist to show. A flat series would satisfy every
    /// test above and still make every chart a straight line.
    func testTheSeriesActuallyMove() throws {
        let samples = SyntheticSeed.samples(days: 90, endingOn: TestClock.now, calendar: cal)

        let weights = samples.filter { $0.type == .bodyMass }.sorted { $0.start < $1.start }
        let firstWeight = try XCTUnwrap(weights.first?.value)
        let lastWeight = try XCTUnwrap(weights.last?.value)
        XCTAssertLessThan(lastWeight, firstWeight, "weight should trend down over the window")

        let steps = samples.filter { $0.type == .stepCount }.map(\.value)
        XCTAssertGreaterThan(try XCTUnwrap(steps.max()) - (try XCTUnwrap(steps.min())), 2000,
                             "steps need a real spread or the activity charts draw a flat line")
    }

    /// A cuff reading is an event the reader performs. Daily blood pressure
    /// would misrepresent how that data arrives and would defeat the "0 of 5
    /// readings in the last 30 days" gate the Blood Pressure card shows.
    func testBloodPressureIsOccasionalRatherThanDaily() {
        let samples = SyntheticSeed.samples(days: 70, endingOn: TestClock.now, calendar: cal)
        let bpDays = Set(samples.filter { $0.type == .bloodPressureSystolic }
            .map { cal.startOfDay(for: $0.start) }).count
        XCTAssertGreaterThan(bpDays, 10, "too few to ground an estimate")
        XCTAssertLessThan(bpDays, 35, "a cuff reading every day is not what this data looks like")
    }
}
