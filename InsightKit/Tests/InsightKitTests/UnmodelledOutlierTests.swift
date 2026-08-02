import XCTest
@testable import InsightKit

/// A reading the series' own history says cannot be right.
///
/// From the reader's export: **Vitamin A: 170,000 mcg**, about fifty-seven times
/// the tolerable upper intake and a number no food produces. It arrived through
/// a chain the app does not control — a shortcut writing into Apple Health — and
/// sat in the Data tab looking exactly like a measurement.
final class UnmodelledOutlierTests: XCTestCase {

    private func group(_ values: [Double?], unit: String = "mcg") -> RawMetricGroup {
        let samples = values.enumerated().map { index, value -> RawMetricSample in
            let start = TestClock.now.addingTimeInterval(-Double(index) * 86_400)
            if let value {
                return RawMetricSample(identifier: "diet.vitaminA", displayName: "Vitamin A",
                                       value: value, unit: unit, start: start,
                                       source: .appleHealth)
            }
            return RawMetricSample(identifier: "diet.vitaminA", displayName: "Vitamin A",
                                   value: .text("n/a"), unit: unit, start: start,
                                   source: .appleHealth)
        }
        return RawMetricGroup(id: "diet.vitaminA", displayName: "Vitamin A",
                              unit: unit, samples: samples)
    }

    /// **The reader's case.** A thousandfold slip among ordinary days.
    func testTheVitaminASlipIsCaught() throws {
        let g = group([170_000, 820, 790, 900, 850, 810, 880])
        XCTAssertEqual(g.suspectValues.count, 1)
        let note = try XCTUnwrap(g.suspicionNote)
        XCTAssertTrue(note.contains("One reading here is"), note)
        XCTAssertTrue(note.contains("larger"), note)
        XCTAssertTrue(note.contains("unit mix-up"), note)
    }

    /// The median, not the mean — the outlier is inside the sample it is judged
    /// against, and a mean of 800, 800, 800 and 170,000 is 43,100, which the
    /// outlier then sits comfortably inside.
    func testTheOutlierCannotHideInsideItsOwnAverage() {
        let g = group([170_000, 800, 800, 800, 800])
        XCTAssertEqual(g.suspectValues.count, 1,
                       "the outlier dragged the reference up past itself")
    }

    /// A slip the other way — milligrams recorded as grams — reads as a series
    /// that quietly stopped meaning anything, and is just as wrong.
    func testASlipDownwardsIsCaughtToo() throws {
        let g = group([0.8, 820, 790, 900, 850, 810])
        XCTAssertEqual(g.suspectValues.count, 1)
        XCTAssertTrue(try XCTUnwrap(g.suspicionNote).contains("smaller"))
    }

    /// **A hard day is not a defect.** The factor sits in the empty space
    /// between the largest genuine swing and the smallest real unit slip, and
    /// this is the half of it that matters — a flag that cries wolf gets
    /// ignored, which costs more than not having one.
    func testAGenuinelyBigDayIsNotFlagged() {
        XCTAssertTrue(group([3200, 820, 790, 900, 850, 810]).suspectValues.isEmpty,
                      "a four-times day was called a unit slip")
        XCTAssertNil(group([3200, 820, 790, 900, 850, 810]).suspicionNote)
    }

    /// Two readings that disagree are not evidence that either is wrong. Below
    /// the minimum history there is no typical value to judge against, and the
    /// *first* reading of a new series must never be flagged.
    func testTooLittleHistorySaysNothing() {
        XCTAssertTrue(group([170_000]).suspectValues.isEmpty)
        XCTAssertTrue(group([170_000, 800]).suspectValues.isEmpty)
        XCTAssertTrue(group([170_000, 800, 800, 800]).suspectValues.isEmpty,
                      "one below the minimum must still say nothing")
        XCTAssertFalse(group([170_000, 800, 800, 800, 800]).suspectValues.isEmpty,
                       "and at the minimum it must speak")
    }

    /// Text readings have no number to judge and must not break the count.
    func testTextReadingsAreIgnoredRatherThanCounted() {
        let g = group([170_000, nil, 800, nil, 800, 800, 800, nil])
        XCTAssertEqual(g.suspectValues.count, 1)
    }

    /// A series of zeroes has no scale, so nothing can be far from it.
    func testAllZeroesSaysNothingRatherThanDividingByZero() {
        XCTAssertTrue(group([0, 0, 0, 0, 0, 0]).suspectValues.isEmpty)
        XCTAssertNil(group([0, 0, 0, 0, 0, 0]).suspicionNote)
    }

    /// A steady series is silent, which is the common case and the one a reader
    /// sees on nearly every row.
    func testASteadySeriesIsSilent() {
        XCTAssertNil(group([820, 790, 900, 850, 810, 880, 795]).suspicionNote)
    }

    /// The multiple is rounded to something that reads as a power of ten,
    /// because recognising "1000×" is the whole point of quoting it.
    func testTheMultipleReadsAsAPowerOfTen() throws {
        let note = try XCTUnwrap(group([800_000, 800, 800, 800, 800, 800]).suspicionNote)
        XCTAssertTrue(note.contains("1000×"), note)
    }

    /// Plural when it is plural — a slip usually repeats, because whatever
    /// produced it is still producing it.
    func testRepeatedSlipsAreCountedAndReadAsPlural() throws {
        let g = group([170_000, 165_000, 820, 790, 900, 850, 810, 880])
        XCTAssertEqual(g.suspectValues.count, 2)
        XCTAssertTrue(try XCTUnwrap(g.suspicionNote).contains("2 readings here are"))
    }
}
