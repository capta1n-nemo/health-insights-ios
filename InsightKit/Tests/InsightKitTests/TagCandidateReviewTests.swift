import XCTest
@testable import InsightKit

/// Backlog `B12-2` (the half that was missing: a correction that sticks, and a
/// classification that is stable across launches) and `B12-3` (candidates are
/// reviewed, never wired).
///
/// Every test here is a property somebody could plausibly break by making the
/// code tidier — a rank comparison that looks symmetric, a ledger that looks like
/// a cache, a decision store that looks like a feature flag.
final class TagCandidateReviewTests: XCTestCase {

    private func day(_ offset: Double = 0) -> Date {
        Date(timeIntervalSince1970: 1_800_000_000 + offset)
    }

    private func summary(_ name: String, count: Int = 1,
                         mapping: TagApplicabilityMapping? = nil) -> TagSummary {
        TagSummary(key: HealthTag.key(for: name), name: name, code: nil,
                   mapping: mapping ?? TagLexicon.classify(name: name),
                   count: count, firstUsed: day(), lastUsed: day(Double(count)))
    }

    private func reader(_ applicability: TagApplicability) -> TagApplicabilityMapping {
        TagApplicabilityMapping(applicability: applicability, method: .reader,
                                confidence: 1, rationale: "You said so.")
    }

    // MARK: - B12-2 · the reader's correction, and their change of mind

    /// ⚠️ **The bug this test was written from.** Two `.reader` mappings rank
    /// identically (400 + 1.0), so `record`'s strict `>` silently discarded the
    /// second one. A reader who corrected "Sauna" to Sleep & recovery and then
    /// decided it was really Activity tapped the menu, watched the row snap back
    /// and had no way to tell the app was refusing them.
    func testAReaderCanChangeTheirMindAboutTheirOwnCorrection() {
        var store = TagMappingStore()
        store.record(reader(.sleepRecovery), for: "sauna")
        store.record(reader(.activity), for: "sauna")
        XCTAssertEqual(store.mapping(for: "sauna")?.applicability, .activity,
                       "a correction is not evidence to be weighed against the previous correction")
    }

    /// The property that must survive the fix above: nothing weaker may overwrite
    /// the reader, however recently it arrived.
    func testAModelAnswerStillCannotOverwriteTheReader() {
        var store = TagMappingStore()
        store.record(reader(.sleepRecovery), for: "sauna")
        store.record(TagApplicabilityMapping(applicability: .activity, method: .onDeviceModel,
                                             confidence: 0.45, rationale: "Guessed."),
                     for: "sauna")
        XCTAssertEqual(store.mapping(for: "sauna")?.method, .reader)
        XCTAssertEqual(store.mapping(for: "sauna")?.applicability, .sleepRecovery)
    }

    /// **The way back.** Correcting to something else was possible; undoing a
    /// correction was not, so a mis-tap left "You said so" printed under a
    /// heading the reader never chose.
    func testClearingACorrectionRestoresTheDeterministicAnswer() {
        var store = TagMappingStore()
        store.record(reader(.social), for: HealthTag.key(for: "Kayaking"))
        store.clear(HealthTag.key(for: "Kayaking"))

        let raw = RawMetricSample(identifier: "oura.enhanced_tag.custom_name",
                                  displayName: "custom_name", value: .text("Kayaking"),
                                  unit: "", start: day(), source: .oura)
        let tags = TagPromotion.tags(from: [raw], resolved: store)
        XCTAssertEqual(tags.first?.mapping.applicability, .activity)
        XCTAssertEqual(tags.first?.mapping.method, .lexicon)
    }

    // MARK: - B12-2 · stable across launches, and the queue that has to advance

    /// ⚠️ **The starvation bug.** `TagApplicabilityModel` asks about at most a
    /// dozen tags a pass, most-used first, and re-asks anything still unplaced.
    /// A tag the model *cannot* place therefore sat at the head of that queue for
    /// ever and the thirteenth tag was never asked at all.
    func testATagTheModelGaveUpOnIsRememberedSoTheQueueCanAdvance() {
        var store = TagMappingStore()
        XCTAssertFalse(store.modelHasDeclined("zorbing"))
        store.recordModelDeclined("zorbing")
        XCTAssertTrue(store.modelHasDeclined("zorbing"))
        XCTAssertNil(store.mapping(for: "zorbing"),
                     "giving up is not an answer — the tag must stay unplaced, not become a category")
    }

    /// A reader placing a tag themselves settles it, so the model's earlier
    /// shrug is irrelevant — and keeping it would stop a later pass ever looking
    /// again if they cleared the correction.
    func testAReaderCorrectionRetiresTheModelsRefusal() {
        var store = TagMappingStore()
        store.recordModelDeclined("zorbing")
        store.record(reader(.activity), for: "zorbing")
        XCTAssertFalse(store.modelHasDeclined("zorbing"))
    }

    func testClearingATagAlsoLetsTheModelBeAskedAgain() {
        var store = TagMappingStore()
        store.recordModelDeclined("zorbing")
        store.clear("zorbing")
        XCTAssertFalse(store.modelHasDeclined("zorbing"))
    }

    /// ⚠️ **Stability across launches is a decoding problem, not a policy one.**
    /// `declinedByModel` was added to a type already persisted in `UserDefaults`;
    /// the synthesized decoder throws on a missing key, and what would be lost is
    /// every correction the reader has ever made.
    func testAStorePersistedBeforeTheLedgerExistedStillDecodes() throws {
        let legacy = Data("""
        {"mappings":{"kayaking":{"applicability":"Activity & mobility","method":"reader","confidence":1,"rationale":"You said so."}}}
        """.utf8)
        let store = try JSONDecoder().decode(TagMappingStore.self, from: legacy)
        XCTAssertEqual(store.mapping(for: "kayaking")?.method, .reader,
                       "a decode failure here silently discards every correction the reader has made")
        XCTAssertFalse(store.modelHasDeclined("kayaking"))
    }

    /// And the round trip, so a tag does not change category between launches.
    func testTheWholeStoreSurvivesARoundTrip() throws {
        var store = TagMappingStore()
        store.record(reader(.sleepRecovery), for: "sauna")
        store.recordModelDeclined("zorbing")
        let decoded = try JSONDecoder().decode(
            TagMappingStore.self, from: JSONEncoder().encode(store))
        XCTAssertEqual(decoded, store)
        XCTAssertEqual(decoded.mapping(for: "sauna")?.applicability, .sleepRecovery)
        XCTAssertTrue(decoded.modelHasDeclined("zorbing"))
    }

    // MARK: - B12-3 · candidates are surfaced, never wired

    /// ⚠️ **The invariant the whole candidate feature rests on.** If this ever
    /// fails it must be because somebody meant it.
    func testNoCandidateIsWiredToAnyCard() {
        XCTAssertFalse(TagCardCandidate.isWiredToAnyCard,
                       "a tag is self-reported free text; feeding one to a score is a decision, not a follow-up")
    }

    /// The reader's own worked example, carried through to the review queue.
    func testAnActivityTagBecomesACandidateNamingItsCard() {
        let candidates = TagCardCandidate.candidates(from: [summary("Kayaking", count: 3)])
        XCTAssertEqual(candidates.count, 1)
        XCTAssertEqual(candidates.first?.applicability, .activity)
        XCTAssertEqual(candidates.first?.candidateNote,
                       TagApplicability.activity.candidateNote)
        XCTAssertTrue(candidates.first?.candidateNote.contains("not used yet") == true,
                      "the row must say plainly that nothing is using it")
    }

    /// A category that names no card is not a question anybody has, so putting it
    /// in a review queue would be asking the reader to adjudicate nothing.
    func testACategoryWithNoCardIsNotACandidate() {
        for name in ["Long haul flight", "Deadline week"] {
            let placed = TagLexicon.classify(name: name).applicability
            XCTAssertNil(placed.candidateNote, "\(name) → \(placed.rawValue)")
            XCTAssertTrue(TagCardCandidate.candidates(from: [summary(name)]).isEmpty)
        }
    }

    /// An unplaced tag cannot be reviewed: the app has not managed to *pose* the
    /// question, so asking whether it should count towards Fitness is nonsense.
    func testAnUnclassifiedTagIsNotOfferedForReview() {
        let unplaced = summary("Zorbing", mapping: .unresolved)
        XCTAssertEqual(unplaced.mapping.applicability, .unclassified)
        XCTAssertTrue(TagCardCandidate.candidates(from: [unplaced]).isEmpty)
    }

    /// Most-used first, so the review starts with the tag that would matter most
    /// if it ever were wired.
    func testCandidatesAreOrderedByHowOftenTheTagIsUsed() {
        let candidates = TagCardCandidate.candidates(from: [
            summary("Yoga", count: 2),
            summary("Kayaking", count: 9),
            summary("Bouldering", count: 5),
        ])
        XCTAssertEqual(candidates.map(\.summary.name), ["Kayaking", "Bouldering", "Yoga"])
    }

    /// Three states, not a `Bool`: collapsing "not looked at yet" into "no" would
    /// let the app claim the reader declined something they never saw.
    func testNotReviewedIsTheDefaultAndIsDistinctFromDeclining() {
        var decisions = TagCandidateDecisionStore()
        XCTAssertEqual(decisions.decision(for: "kayaking"), .notReviewed)
        decisions.set(.shouldNotCount, for: "kayaking")
        XCTAssertEqual(decisions.decision(for: "kayaking"), .shouldNotCount)
        decisions.set(.notReviewed, for: "kayaking")
        XCTAssertTrue(decisions.isEmpty, "clearing an answer forgets it rather than storing a third value")
    }

    func testUnreviewedCountIsWhatTheReviewRowPromises() {
        var decisions = TagCandidateDecisionStore()
        decisions.set(.shouldCount, for: HealthTag.key(for: "Kayaking"))
        let candidates = TagCardCandidate.candidates(
            from: [summary("Kayaking", count: 3), summary("Yoga", count: 1)],
            decisions: decisions)
        XCTAssertEqual(decisions.unreviewedCount(among: candidates), 1)
        XCTAssertEqual(candidates.first?.decision, .shouldCount)
    }

    /// ⚠️ **The behavioural half of `isWiredToAnyCard`.** A decision must not
    /// reach classification at all — if answering "should count" changed what a
    /// tag *is*, the review would be feeding the app by the back door.
    func testAReviewDecisionChangesNothingAboutTheTagItself() {
        let raw = RawMetricSample(identifier: "oura.enhanced_tag.custom_name",
                                  displayName: "custom_name", value: .text("Kayaking"),
                                  unit: "", start: day(), source: .oura)
        let before = TagPromotion.tags(from: [raw])

        var decisions = TagCandidateDecisionStore()
        decisions.set(.shouldCount, for: HealthTag.key(for: "Kayaking"))
        let after = TagPromotion.tags(from: [raw])

        XCTAssertEqual(before.map(\.mapping), after.map(\.mapping))
        XCTAssertFalse(decisions.isEmpty, "the decision was recorded — it simply changes nothing here")
    }

    /// Standing rule 11 — nothing the reader meets is a bare label.
    func testEveryDecisionExplainsItselfAndAdmitsNothingIsUsingTheTag() {
        for decision in TagCardCandidateDecision.allCases {
            XCTAssertFalse(decision.title.isEmpty)
            XCTAssertFalse(decision.symbolName.isEmpty)
            XCTAssertGreaterThan(decision.detail.count, 30,
                                 "\(decision.rawValue) needs a real explanation")
            XCTAssertFalse(decision.detail.contains("**"), "a Text prints the asterisks")
            let admits = decision.detail.lowercased()
            XCTAssertTrue(admits.contains("isn't being used") || admits.contains("nothing is using")
                            || admits.contains("won't be proposed"),
                          "\(decision.rawValue) must not read as a switch that turned something on")
        }
    }

    func testDecisionStoreSurvivesARoundTrip() throws {
        var decisions = TagCandidateDecisionStore()
        decisions.set(.shouldCount, for: "kayaking")
        decisions.set(.shouldNotCount, for: "sauna")
        let decoded = try JSONDecoder().decode(
            TagCandidateDecisionStore.self, from: JSONEncoder().encode(decisions))
        XCTAssertEqual(decoded, decisions)
    }
}
