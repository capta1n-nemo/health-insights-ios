import XCTest
@testable import InsightKit

/// **A card's copy never states a count the card does not have.** Backlog D19.
///
/// The shipped defect: a section rendered *"All four sitting where they usually
/// sit"* on a card running on three signals, and Mental Health's empty-state
/// line named all four behaviours it watches — including the one it had no data
/// for. `adca807` fixed both and pinned Mental Health with
/// `MentalHealthTests.testTheCopyNeverNamesABehaviourItDidNotRead`.
///
/// This file is the *second* instance, found on 2026-08-07 by the lint written
/// for the class (`verify.sh` ▸ "A hard-coded count inside reader-facing copy",
/// backlog G-check-2). Sustained Load's caveat line said "This measures four
/// signals that load moves" while `SustainedLoadModel.evaluate` guards on
/// `channels.count >= 2` — so on a reader whose device reports no respiratory
/// rate, the card named signals it had never read, three lines above an
/// `explanation` that derived the same count correctly.
///
/// ## Why a test as well as a lint
///
/// The lint is static and can only see the literal. It cannot see that
/// `\(out.channels.count)` resolves to the number of channels *actually
/// scored* rather than the number the model watches for — which is the
/// substitution that would look like a fix and not be one. That distinction
/// needs a run, on data thin enough for the two to differ.
final class HardCodedCountInCopyTests: XCTestCase {

    private let now = TestClock.now

    /// Two of the four watched signals present. Every sentence this card writes
    /// about "how many" has to say two.
    func testSustainedLoadCountsTheSignalsItActuallyRead() {
        let dropped: Set<MetricType> = [.respiratoryRate, .sleepDurationHours]
        let samples = ContributorsFixture.fullCoverage(now: now)
            .filter { !dropped.contains($0.type) }

        let result = SustainedLoadInsight().evaluate(
            samples: samples, profile: ContributorsFixture.profile(now: now), now: now)

        // The fixture has to actually reach the card, or this asserts nothing —
        // the `guard … else { continue }` failure `ContributorsFixture` records.
        XCTAssertNotNil(result.score, "the thinned fixture must still score, or "
                            + "this test is checking an empty state")

        let copy = ([result.explanation] + result.drivers).joined(separator: "\n")
        XCTAssertFalse(copy.lowercased().contains("four signals"),
                       "the card claims four signals on \(result.contributors.count) — "
                           + "the count is written out rather than derived:\n\(copy)")
        XCTAssertTrue(copy.contains("2 signals"),
                      "and it must say how many it did read:\n\(copy)")
    }

    /// Full coverage still reads four, so the fix is a derivation and not a
    /// constant swapped for a smaller constant.
    func testTheSameSentenceSaysFourWhenFourWereRead() {
        let result = SustainedLoadInsight().evaluate(
            samples: ContributorsFixture.fullCoverage(now: now),
            profile: ContributorsFixture.profile(now: now), now: now)
        let copy = ([result.explanation] + result.drivers).joined(separator: "\n")
        XCTAssertTrue(copy.contains("4 signals"),
                      "with every watched signal present the count is four:\n\(copy)")
    }
}
