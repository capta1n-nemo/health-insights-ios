import XCTest
@testable import InsightKit

/// Structural invariants of the analyte catalogue. Each one is a way a new
/// entry can be added that compiles, looks right, and quietly files values
/// under the wrong analyte or in the wrong unit.
final class LabAnalyteCatalogTests: XCTestCase {

    func testKeysAreUnique() {
        let keys = LabAnalyteCatalog.entries.map(\.key)
        XCTAssertEqual(Set(keys).count, keys.count, "two catalogue entries share a key")
    }

    /// Longest-first synonym matching is what stops "HDL cholesterol" being
    /// consumed by "cholesterol". If the index ever stops being sorted, the
    /// failure is a wrong number in a cardiovascular risk estimate.
    func testTheSynonymIndexIsSortedLongestFirst() {
        let lengths = LabAnalyteCatalog.synonymIndex.map(\.label.count)
        XCTAssertEqual(lengths, lengths.sorted(by: >))
    }

    /// Every entry must be able to store a value in its own canonical unit —
    /// an entry whose unit table omits its canonical unit converts nothing.
    func testEveryEntryCanConvertItsOwnCanonicalUnit() {
        for entry in LabAnalyteCatalog.entries {
            let converted = LabAnalyteCatalog.convert(1, from: entry.canonicalUnit, for: entry)
            XCTAssertNotNil(converted, "\(entry.key) cannot convert its own canonical unit")
        }
    }

    /// A plausible range that excludes the middle of the reference interval
    /// would reject every real value for that analyte.
    func testPlausibleRangesAreNotDegenerate() {
        for entry in LabAnalyteCatalog.entries {
            XCTAssertLessThan(entry.plausible.lowerBound, entry.plausible.upperBound,
                              "\(entry.key) has an empty plausible range")
        }
    }

    /// A label the catalogue does not know must not be silently forced onto one
    /// it does — that is the whole point of `isKnown`.
    func testAnUnknownLabelDoesNotMatch() {
        XCTAssertNil(LabAnalyteCatalog.match(label: "Anti-Mullerian Hormone"))
        XCTAssertFalse(LabAnalyte.unknown(label: "Anti-Mullerian Hormone", unit: nil).isKnown)
    }

    func testTheMicroSignAndGreekMuNormaliseTogether() {
        XCTAssertEqual(LabAnalyteCatalog.normaliseUnit("µmol/L"),
                       LabAnalyteCatalog.normaliseUnit("μmol/L"))
    }

    /// An uncatalogued analyte's key is namespaced, so it can never collide
    /// with a catalogued one that is added later under the same words.
    func testUnknownAnalyteKeysAreNamespaced() {
        XCTAssertTrue(LabAnalyte.unknown(label: "HbA1c", unit: nil).key.hasPrefix("other."))
    }

    /// ⚠️ An analyte that fills a grounding fact feeds SCORE2 and ASCVD. Only
    /// the two lipids may, and a third arriving by accident would change a
    /// cardiovascular risk estimate with nothing in the UI saying so.
    func testOnlyTheTwoLipidsFillGroundingFacts() {
        let grounded = LabAnalyteCatalog.entries.compactMap(\.groundingKind)
        XCTAssertEqual(Set(grounded), [.totalCholesterol, .hdlCholesterol])
    }
}
