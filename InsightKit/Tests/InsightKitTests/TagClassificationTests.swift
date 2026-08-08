import XCTest
@testable import InsightKit

/// Backlog B12-1 — tags, and placing one the app has never seen.
///
/// The hard requirement is the one these tests are mostly about: **it must
/// scale to tags nobody wrote down in advance.** So the cases below deliberately
/// use words that are *not* stems in `TagLexicon.stems` — "Kayaking" against the
/// stem "kayak", "Went cycling with Tom" against "cycl" — because a test that
/// only feeds the classifier its own vocabulary back proves nothing.
final class TagClassificationTests: XCTestCase {

    // MARK: - The reader's own worked example

    /// *"whatever it is (eg Kayaking) will have an 'applicability' of 'Activity
    /// & mobility'"* — the brief, verbatim, as a test.
    func testKayakingIsActivityAndMobility() {
        let mapping = TagLexicon.classify(name: "Kayaking")
        XCTAssertEqual(mapping.applicability, .activity)
        XCTAssertEqual(mapping.applicability.rawValue, "Activity & mobility")
        XCTAssertEqual(mapping.method, .lexicon)
    }

    // MARK: - Unseen tags

    /// Inflections, sentences and punctuation — none of which is a lexicon
    /// entry, all of which a person actually types.
    func testInflectionsAndSentencesStillClassify() {
        let cases: [(String, TagApplicability)] = [
            ("kayaked", .activity),
            ("Went cycling with Tom", .activity),
            ("Bouldering session!!", .activity),
            ("Really bad migraine", .illness),
            ("felt so anxious today", .mentalHealth),
            ("Two glasses of wine", .substances),
            ("Long haul flight", .travel),
            ("Deadline week", .work),
            ("napped in the afternoon", .sleepRecovery),
            ("Took my vitamins", .medication),
        ]
        for (name, expected) in cases {
            XCTAssertEqual(TagLexicon.classify(name: name).applicability, expected,
                           "\"\(name)\" should be \(expected.rawValue)")
        }
    }

    /// camelCase and snake_case arrive from providers, not from readers, and
    /// must tokenise the same way.
    func testCaseAndSeparatorFormsTokeniseTheSame() {
        for name in ["lateNight", "late_night", "Late Night", "LATE-NIGHT"] {
            XCTAssertEqual(TagLexicon.classify(name: name).applicability, .sleepRecovery,
                           "\(name) should reach the same answer as the others")
        }
    }

    // MARK: - The provider's own code beats the reader's words

    func testProviderCodeIsUsedAndOutranksTheLexicon() {
        let mapping = TagLexicon.classify(name: "A couple", code: "tag_generic_alcohol")
        XCTAssertEqual(mapping.applicability, .substances)
        XCTAssertEqual(mapping.method, .providerCode)
        XCTAssertGreaterThan(mapping.confidence, 0.75,
                             "a vendor's own type code is stronger evidence than a word match")
    }

    /// Oura's marker for a tag the reader invented says nothing, so the name has
    /// to carry it. This is the custom-tag path and the reason a lookup table
    /// could never have worked.
    func testCustomCodeFallsThroughToTheName() {
        let mapping = TagLexicon.classify(name: "Kayaking", code: "custom")
        XCTAssertEqual(mapping.applicability, .activity)
        XCTAssertEqual(mapping.method, .lexicon,
                       "\"custom\" is not a meaning — the name must decide")
    }

    // MARK: - What it refuses to do

    /// A word nothing recognises is `.unclassified` at zero confidence, not a
    /// guess. This is the state the on-device model is asked about.
    func testAnUnknownWordIsUnclassifiedAndWantsTheModel() {
        let mapping = TagLexicon.classify(name: "Zorbing")
        XCTAssertEqual(mapping.applicability, .unclassified)
        XCTAssertEqual(mapping.method, .unresolved)
        XCTAssertEqual(mapping.confidence, 0)
        XCTAssertTrue(mapping.wantsModelReview)
    }

    /// A tag naming two categories about equally is ambiguous, and the honest
    /// answer is to say so rather than to award it to the one whose stem happens
    /// to be two letters longer.
    ///
    /// ⚠️ **This test found a real hole.** The guard was written as an
    /// exact-tie check and could essentially never fire — "wine dinner"
    /// resolved to Nutrition purely because "dinner" outweighs "wine" by
    /// length. `TagLexicon.decisiveMargin` is the fix.
    func testAnEvenlyAmbiguousTagIsNotAwardedToEither() {
        let mapping = TagLexicon.classify(name: "wine dinner")
        XCTAssertEqual(mapping.applicability, .unclassified,
                       "two near-equally-matched categories must not be resolved by stem length")
        XCTAssertTrue(mapping.wantsModelReview,
                      "an ambiguous tag is exactly what the on-device model is for")
    }

    /// The other half of the same rule: **more evidence wins.** A guard set too
    /// high would send every mixed tag to the model.
    ///
    /// ⚠️ What decides is the *number* of matched stems, never their length.
    /// The first attempt at this test asserted that "Kayaking with a glass of
    /// wine after" should be Activity — one activity stem against one substances
    /// stem — and it failed, correctly: that tag is about both, and awarding it
    /// to whichever word is longer would be exactly the coin toss the margin
    /// exists to prevent. One stem against one stem is ambiguous, full stop.
    func testMoreMatchedStemsWinsOverFewer() {
        let mapping = TagLexicon.classify(name: "Went for a run at the gym, then a beer")
        XCTAssertEqual(mapping.applicability, .activity,
                       "two activity words against one substances word is decided, not a toss-up")
    }

    /// And the case that made the point: one word each way stays unplaced.
    func testOneStemEachWayIsAmbiguousHoweverLongTheWords() {
        let mapping = TagLexicon.classify(name: "Kayaking with a glass of wine after")
        XCTAssertEqual(mapping.applicability, .unclassified)
        XCTAssertTrue(mapping.wantsModelReview)
    }

    func testEmptyAndPunctuationOnlyNamesDoNotCrashOrClassify() {
        for name in ["", "   ", "!!!", "—"] {
            XCTAssertEqual(TagLexicon.classify(name: name).applicability, .unclassified)
        }
    }

    // MARK: - Every category is reachable and explained

    /// A category nothing can ever match is a heading that will never appear —
    /// which reads to a reader as the app having categories it made up.
    func testEveryClassifiableCategoryHasStems() {
        for applicability in TagApplicability.classifiable {
            let stems = MomentConcept.concepts(in: applicability)
                .flatMap { TagLexicon.stems[$0] ?? [] }
            XCTAssertFalse(stems.isEmpty,
                           "\(applicability.rawValue) has no stems, so nothing can ever land in it")
        }
    }

    /// The same rule one level down, and the level the reader actually noticed.
    /// A concept with no stems is an option the picker offers and the classifier
    /// can never reach on its own — which is exactly the state `.intimacy` was
    /// in when an Oura tag reading "Sex" arrived and could not be placed.
    func testEveryConceptHasStems() {
        for concept in MomentConcept.allCases {
            let stems = TagLexicon.stems[concept] ?? []
            XCTAssertFalse(stems.isEmpty,
                           "\(concept.rawValue) has no stems, so the classifier can never reach it")
        }
    }

    /// The reader's own example, 2026-08-09.
    func testTheReadersSexTagResolvesToSexualActivity() {
        for name in ["Sex", "sex", "Sex ", "Intimacy"] {
            let mapping = TagLexicon.classify(name: name)
            XCTAssertEqual(mapping.concept, .intimacy, "“\(name)” did not resolve")
            XCTAssertEqual(mapping.applicability, .social)
        }
        // Oura ships a machine code for it, which is the stronger tier.
        let coded = TagLexicon.classify(name: "Sex", code: "tag_generic_sex")
        XCTAssertEqual(coded.concept, .intimacy)
        XCTAssertEqual(coded.method, .providerCode)
    }

    /// ⚠️ A bare stem, not a prefix: "sexism" and "sextet" are not intimacy.
    func testSexDoesNotClaimUnrelatedWords() {
        XCTAssertNotEqual(TagLexicon.classify(name: "Sexism seminar").concept, .intimacy)
    }

    /// Splitting Substances into four concepts must not make a tag that names
    /// two of them newly unplaceable — the coarse answer is still unambiguous.
    func testTwoSubstancesInOneTagStillResolveToSubstances() {
        let mapping = TagLexicon.classify(name: "wine and a coffee")
        XCTAssertEqual(mapping.applicability, .substances)
        XCTAssertNotNil(mapping.concept)
    }

    /// The finer vocabulary is the point: a tag naming a drink should say so,
    /// not merely say "Substances".
    func testASingleSubstanceResolvesToItsOwnConcept() {
        XCTAssertEqual(TagLexicon.classify(name: "Wine").concept, .alcohol)
        XCTAssertEqual(TagLexicon.classify(name: "Espresso").concept, .caffeine)
        XCTAssertEqual(TagLexicon.classify(name: "Vape").concept, .nicotine)
    }

    /// The mapping is total, so a concept can never be unfileable, and the two
    /// vocabularies can never disagree about where something belongs.
    func testEveryConceptMapsToAClassifiableGrouping() {
        for concept in MomentConcept.allCases {
            XCTAssertNotEqual(concept.applicability, .unclassified,
                              "\(concept.rawValue) maps to the not-placed grouping")
        }
    }

    /// Where a concept is also a flagged-event answer, the two must read
    /// identically — one thing, one word.
    func testConceptAndEventCauseAgreeOnWording() {
        for concept in MomentConcept.allCases {
            guard let cause = concept.eventCause else { continue }
            XCTAssertEqual(concept.displayName, cause.displayName)
            XCTAssertEqual(cause.concept, concept, "the mapping is not reversible")
        }
    }

    /// Standing rule 11 — every data entry carries a "what this is" description.
    func testEveryApplicabilityExplainsItself() {
        for applicability in TagApplicability.allCases {
            XCTAssertGreaterThan(applicability.summary.count, 40,
                                 "\(applicability.rawValue) needs a real explanation")
            XCTAssertFalse(applicability.symbolName.isEmpty)
            XCTAssertFalse(applicability.summary.contains("**"),
                           "a Text prints the asterisks")
        }
    }

    /// The one string the reader named must stay exactly what they named.
    func testActivityUsesTheDataTabsOwnWords() {
        XCTAssertEqual(TagApplicability.activity.rawValue,
                       MetricDataCategory.activity.rawValue)
    }

    // MARK: - Promotion out of the raw catalogue

    private func raw(_ identifier: String, _ text: String, _ date: Date) -> RawMetricSample {
        RawMetricSample(identifier: identifier, displayName: identifier,
                        value: .text(text), unit: "", start: date, source: .oura)
    }

    /// The shape the pipeline actually produces: one record scattered into one
    /// raw sample per field, all sharing the instant.
    func testEnhancedTagRecordIsReassembledFromItsScatteredFields() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let tags = TagPromotion.tags(from: [
            raw("oura.enhanced_tag.tag_type_code", "custom", now),
            raw("oura.enhanced_tag.custom_name", "Kayaking", now),
            raw("oura.enhanced_tag.comment", "rough water, knackered after", now),
        ])
        XCTAssertEqual(tags.count, 1, "three fields are one tag, not three")
        XCTAssertEqual(tags.first?.name, "Kayaking")
        XCTAssertEqual(tags.first?.mapping.applicability, .activity)
        XCTAssertEqual(tags.first?.date, now)
    }

    /// The comment is the reader's note *about* a tag. Treating it as a tag
    /// would fill the section with one-off sentences that group with nothing.
    func testACommentAloneProducesNoTag() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let tags = TagPromotion.tags(from: [
            raw("oura.enhanced_tag.comment", "went for a run and felt awful", now)
        ])
        XCTAssertTrue(tags.isEmpty)
    }

    /// A stock tag has only a code, and its name is read off that code in words
    /// a person would write.
    func testAStockTagIsNamedFromItsCode() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let tags = TagPromotion.tags(from: [
            raw("oura.enhanced_tag.tag_type_code", "tag_generic_late_night", now)
        ])
        XCTAssertEqual(tags.first?.name, "Late night")
        XCTAssertEqual(tags.first?.mapping.applicability, .sleepRecovery)
    }

    /// Oura's legacy `tag` endpoint puts several codes on one record.
    func testLegacyTagArrayBecomesSeveralTags() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let tags = TagPromotion.tags(from: [
            raw("oura.tag.tags.0", "tag_generic_stress", now),
            raw("oura.tag.tags.1", "tag_generic_travel", now),
        ])
        XCTAssertEqual(tags.count, 2)
        XCTAssertEqual(Set(tags.map(\.mapping.applicability)), [.mentalHealth, .travel])
    }

    /// Nothing that is not a tag endpoint may become a tag.
    func testNonTagIdentifiersAreIgnored() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        XCTAssertTrue(TagPromotion.tags(from: [
            raw("oura.daily_sleep.contributors.deep_sleep", "good", now),
            raw("oura.sleep.type", "long_sleep", now),
        ]).isEmpty)
    }

    // MARK: - Grouping, and the mapping store

    func testDistinctTagsGroupCaseAndPunctuationInsensitively() {
        let day = Date(timeIntervalSince1970: 1_800_000_000)
        let tags = ["Kayaking", "kayaking", "Kayaking!"].enumerated().map { index, name in
            HealthTag(name: name, date: day.addingTimeInterval(Double(index) * 3600),
                      source: .oura, mapping: TagLexicon.classify(name: name))
        }
        let distinct = tags.distinctTags()
        XCTAssertEqual(distinct.count, 1)
        XCTAssertEqual(distinct.first?.count, 3)
        XCTAssertEqual(distinct.first?.name, "Kayaking!", "the most recent spelling is shown")
    }

    /// ⚠️ The property the whole store exists for: a reader's correction must
    /// survive the next sync re-classifying the same word.
    func testAReaderCorrectionOutranksALaterModelAnswer() {
        var store = TagMappingStore()
        store.record(TagApplicabilityMapping(applicability: .sleepRecovery, method: .reader,
                                             confidence: 1, rationale: "You said so."),
                     for: "sauna")
        store.record(TagApplicabilityMapping(applicability: .activity, method: .onDeviceModel,
                                             confidence: 0.45, rationale: "Guessed."),
                     for: "sauna")
        XCTAssertEqual(store.mapping(for: "sauna")?.applicability, .sleepRecovery)
        XCTAssertEqual(store.mapping(for: "sauna")?.method, .reader)
    }

    func testAStoredAnswerWinsOverTheLexiconDuringPromotion() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        var store = TagMappingStore()
        store.record(TagApplicabilityMapping(applicability: .social, method: .reader,
                                             confidence: 1, rationale: "You said so."),
                     for: HealthTag.key(for: "Kayaking"))
        let tags = TagPromotion.tags(from: [
            raw("oura.enhanced_tag.custom_name", "Kayaking", now)
        ], resolved: store)
        XCTAssertEqual(tags.first?.mapping.applicability, .social)
        XCTAssertEqual(tags.first?.mapping.method, .reader)
    }

    /// `.unclassified` is grouped last, so an unplaced tag is never the first
    /// thing on the page.
    func testUnclassifiedGroupsLast() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let tags = [
            HealthTag(name: "Zorbing", date: now, source: .oura, mapping: .unresolved),
            HealthTag(name: "Kayaking", date: now, source: .oura,
                      mapping: TagLexicon.classify(name: "Kayaking")),
        ]
        let groups = tags.groupedByApplicability()
        XCTAssertEqual(groups.last?.applicability, .unclassified)
    }

    // MARK: - Export

    /// Standing rule 10 — a quantity missing from the export can never become a
    /// norm. `HealthDataExportTests` walks every domain; this pins the one thing
    /// that would make the tags key useless if it were dropped: the mapping.
    func testAnExportedTagCarriesItsMethodAndConfidence() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let tag = HealthTag(name: "Kayaking", date: now, source: .oura,
                            mapping: TagLexicon.classify(name: "Kayaking"))
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let json = try XCTUnwrap(String(data: encoder.encode([tag]), encoding: .utf8))
        XCTAssertTrue(json.contains("\"method\""),
                      "an inference exported without its method is indistinguishable from a measurement")
        XCTAssertTrue(json.contains("\"confidence\""))
        XCTAssertTrue(json.contains("\"applicability\""))
    }
}
