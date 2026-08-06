import XCTest
@testable import InsightKit

/// The caveat is the honesty claim, so it is the part that can be wrong.
///
/// The app target has no test target, which is why the wording lives here at
/// all. What these check is the class of defect a footnote actually ships with:
/// a count that reads "1 weigh-ins", a caveat that is empty, and copy that
/// drifts from describing into instructing.
final class SectionCaveatTests: XCTestCase {

    /// Every caveat that can be built, for the sweeps below.
    private var all: [SectionCaveat] {
        [.none, .replayedHistory, .scoreFloor, .approximateNorms, .ifTodaysNumbersHold,
         .modelledCurve, .decayingLoad, .associationsNotCauses,
         .unscored(signals: 1), .unscored(signals: 4),
         .compositionWindow(weighIns: 1), .compositionWindow(weighIns: 12),
         .splitOnlyFrom("3 Mar 2026"),
         .fittedCentre(nights: 1), .fittedCentre(nights: 14),
         .periodContrast(days: 1), .periodContrast(days: 28),
         .fittedThrough(points: 1), .fittedThrough(points: 30),
         .computed(.partial, "Blood Oxygen was not measured recently enough to show."),
         .joined([.replayedHistory, .scoreFloor])]
    }

    // MARK: - The count bug

    /// `InsightDetailView` shipped "across \(count) weigh-ins" with no singular
    /// case, so a card with one reading said "across 1 weigh-ins".
    func testCountsAreWordedForTheirOwnNumber() {
        XCTAssertEqual(SectionCaveat.plural(1, "weigh-in"), "weigh-in")
        XCTAssertEqual(SectionCaveat.plural(0, "weigh-in"), "weigh-ins")
        XCTAssertEqual(SectionCaveat.plural(2, "weigh-in"), "weigh-ins")

        let one = try? XCTUnwrap(SectionCaveat.compositionWindow(weighIns: 1).text)
        XCTAssertEqual(one?.contains("1 weigh-in."), true)
        XCTAssertEqual(one?.contains("weigh-ins"), false)

        let many = try? XCTUnwrap(SectionCaveat.compositionWindow(weighIns: 9).text)
        XCTAssertEqual(many?.contains("9 weigh-ins."), true)
    }

    /// The verb has to agree too — "1 more row is", "4 more rows are".
    ///
    /// ⚠️ **"row", not "signal", since 2026-08-06.** The group this caveat sits
    /// over used to hold only measured signals a card charts without scoring; it
    /// now also holds figures the card *works out* — a pooled departure, a
    /// combined age — and "signals checked for anything unusual" would describe
    /// a scan that never ran over those.
    func testVerbsAgreeWithTheirCount() throws {
        let one = try XCTUnwrap(SectionCaveat.unscored(signals: 1).text)
        XCTAssertTrue(one.hasPrefix("1 more row is shown"), one)

        let many = try XCTUnwrap(SectionCaveat.unscored(signals: 4).text)
        XCTAssertTrue(many.hasPrefix("4 more rows are shown"), many)
    }

    func testFittedThroughAgreesToo() throws {
        XCTAssertTrue(try XCTUnwrap(SectionCaveat.fittedThrough(points: 1).text)
            .contains("1 day of overlap"))
        XCTAssertTrue(try XCTUnwrap(SectionCaveat.fittedThrough(points: 21).text)
            .contains("21 days of overlap"))
    }

    // MARK: - The shape of a caveat

    /// `.none` is the only one without words, and it must not be reachable by
    /// accident — an empty string would render as a blank line that reads as a
    /// caveat somebody forgot to write.
    func testOnlyNoneIsSilentAndItIsSilentProperly() {
        XCTAssertNil(SectionCaveat.none.text)
        XCTAssertFalse(SectionCaveat.none.isInference)

        for caveat in all where caveat.kind != .none {
            let text = caveat.text ?? ""
            XCTAssertFalse(text.trimmingCharacters(in: .whitespaces).isEmpty,
                           "\(caveat.kind) has no words")
            XCTAssertTrue(caveat.isInference, "\(caveat.kind) should count as inference")
        }
    }

    func testEveryCaveatIsAWholeSentence() {
        for caveat in all {
            guard let text = caveat.text else { continue }
            XCTAssertTrue(text.hasSuffix("."), "does not end in a full stop: \(text)")
            XCTAssertEqual(text.first, text.first?.uppercased().first,
                           "does not start with a capital: \(text)")
        }
    }

    /// This app describes; it does not instruct. Same rule the suggestion copy
    /// is already swept for — a caveat is the last place a "you should" belongs,
    /// because it is attached to the thing the app is least sure about.
    func testNoCaveatInstructsTheReader() {
        let prescriptive = ["you should", "you must", "make sure", "be sure to",
                            "try to", "you need to", "aim for", "avoid ", "ensure "]
        for caveat in all {
            let text = (caveat.text ?? "").lowercased()
            for phrase in prescriptive {
                XCTAssertFalse(text.contains(phrase),
                               "\"\(phrase)\" in: \(caveat.text ?? "")")
            }
        }
    }

    /// A caveat that claims certainty defeats itself.
    func testNoCaveatOverclaims() {
        let overclaims = ["guarantee", "will happen", "proves", "definitely", "certainly"]
        for caveat in all {
            let text = (caveat.text ?? "").lowercased()
            for phrase in overclaims {
                XCTAssertFalse(text.contains(phrase),
                               "\"\(phrase)\" in: \(caveat.text ?? "")")
            }
        }
    }

    /// A projection has to name its own condition. This is the constraint
    /// `docs/progress.md` records as "lifetime risk was deliberately not faked":
    /// the equations run at ages they are validated for, labelled as an if.
    func testAProjectionSaysWhatWouldHaveToHold() throws {
        let text = try XCTUnwrap(SectionCaveat.ifTodaysNumbersHold.text)
        XCTAssertTrue(text.lowercased().contains("if nothing changes"), text)
        XCTAssertTrue(text.lowercased().contains("not a forecast"), text)
        XCTAssertEqual(SectionCaveat.ifTodaysNumbersHold.kind, .projected)
    }

    /// The centile caveat has to carry `PeerStandingModel`'s own stated
    /// constraint — approximations to summary statistics, and never a verdict.
    func testTheCentileCaveatRepeatsTheModelsOwnHonestyConstraint() throws {
        let text = try XCTUnwrap(SectionCaveat.approximateNorms.text)
        XCTAssertTrue(text.lowercased().contains("approximation"), text)
        XCTAssertTrue(text.lowercased().contains("is a verdict"), text)
        XCTAssertTrue(text.lowercased().contains("none of them"), text)
    }

    /// A panel that computed its own wording still has to declare what kind of
    /// gap it is describing, so nothing escapes the classification.
    func testComputedCaveatsAreStillClassified() {
        let panel = SectionCaveat.computed(.partial, "Two vitals were not measured today.")
        XCTAssertEqual(panel.kind, .partial)
        XCTAssertTrue(panel.isInference)
    }

    // MARK: - Joining

    /// A section carrying two caveats must classify as the stronger claim, not
    /// as whichever was written first.
    func testJoiningKeepsTheStrongerClaim() {
        XCTAssertEqual(SectionCaveat.joined([.scoreFloor, .ifTodaysNumbersHold]).kind,
                       .projected)
        XCTAssertEqual(SectionCaveat.joined([.ifTodaysNumbersHold, .scoreFloor]).kind,
                       .projected)
        XCTAssertEqual(SectionCaveat.joined([.compositionWindow(weighIns: 3),
                                             .splitOnlyFrom("3 Mar")]).kind, .estimated)
    }

    func testJoiningKeepsBothSentences() throws {
        let joined = try XCTUnwrap(
            SectionCaveat.joined([.compositionWindow(weighIns: 3),
                                  .splitOnlyFrom("3 Mar 2026")]).text)
        XCTAssertTrue(joined.contains("3 weigh-ins"), joined)
        XCTAssertTrue(joined.contains("3 Mar 2026"), joined)
    }

    /// Joining nothing, or joining only silences, stays silent — a section that
    /// reports measurements must not acquire an empty caveat line.
    func testJoiningSilenceIsSilent() {
        XCTAssertEqual(SectionCaveat.joined([]), .none)
        XCTAssertEqual(SectionCaveat.joined([.none, .none]), .none)
        XCTAssertNil(SectionCaveat.joined([.none]).text)
    }

    func testJoiningOneRealCaveatWithSilenceKeepsIt() throws {
        let joined = SectionCaveat.joined([.none, .scoreFloor])
        XCTAssertEqual(joined.kind, .partial)
        XCTAssertEqual(joined.text, SectionCaveat.scoreFloor.text)
    }
}
