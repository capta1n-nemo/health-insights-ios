import XCTest
@testable import InsightKit

/// The symptom categories have been arriving in the raw catalogue since
/// `HealthKitService` gained their identifiers, and nothing read them. These
/// hold the promotion honest.
final class SymptomTests: XCTestCase {

    private func raw(_ identifier: String, _ value: Double,
                     daysAgo: Int = 0) -> RawMetricSample {
        RawMetricSample(identifier: identifier, displayName: identifier,
                        value: .number(value), unit: "",
                        start: TestClock.day(daysAgo), source: .appleHealth)
    }

    /// **The identifier has to match Apple's exactly or nothing is promoted at
    /// all** — and it is derived rather than typed out fourteen times, so this
    /// checks the derivation against the strings `HealthKitService` requests.
    func testEveryHealthKitIdentifierIsTheOneAppleUses() {
        XCTAssertEqual(SymptomType.nausea.healthKitIdentifier, "HKCategoryTypeIdentifierNausea")
        XCTAssertEqual(SymptomType.shortnessOfBreath.healthKitIdentifier,
                       "HKCategoryTypeIdentifierShortnessOfBreath")
        XCTAssertEqual(SymptomType.chestTightnessOrPain.healthKitIdentifier,
                       "HKCategoryTypeIdentifierChestTightnessOrPain")
        XCTAssertEqual(SymptomType.hotFlashes.healthKitIdentifier,
                       "HKCategoryTypeIdentifierHotFlashes")
        // Apple spells the identifier the US way; the title is British
        // ("Diarrhoea") — the raw value must follow Apple, not the copy.
        XCTAssertEqual(SymptomType.vomiting.healthKitIdentifier,
                       "HKCategoryTypeIdentifierVomiting")
        XCTAssertEqual(SymptomType.diarrhea.healthKitIdentifier,
                       "HKCategoryTypeIdentifierDiarrhea")
        XCTAssertEqual(SymptomType.byHealthKitIdentifier.count, SymptomType.allCases.count,
                       "two symptoms deriving the same identifier would silently drop one")
    }

    func testItPromotesASymptomOutOfTheRawCatalogue() throws {
        let events = SymptomPromotion.events(from: [raw("HKCategoryTypeIdentifierNausea", 3)])
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.type, .nausea)
        XCTAssertEqual(events.first?.severity, .moderate)
    }

    func testItIgnoresRawRowsThatAreNotSymptoms() {
        let events = SymptomPromotion.events(from: [
            raw("HKQuantityTypeIdentifierDietaryCaffeine", 95),
            raw("oura.daily_activity.equivalent_walking_distance", 4200)
        ])
        XCTAssertTrue(events.isEmpty)
    }

    /// A value outside Apple's severity constants is dropped rather than
    /// guessed at. `unspecified` already means "present, strength not stated",
    /// so there is no honest place to put an unrecognised number.
    func testAnUnrecognisedSeverityIsDroppedRatherThanGuessed() {
        XCTAssertTrue(SymptomPromotion.events(from: [
            raw("HKCategoryTypeIdentifierFever", 99)
        ]).isEmpty)
    }

    /// **`notPresent` is data, not absence.** The reader saying "I checked and I
    /// did not have this" is worth more than silence, and a card counting it as
    /// an occurrence would invert its meaning.
    func testARecordedAbsenceIsKeptButDoesNotCountAsHavingIt() throws {
        let events = SymptomPromotion.events(from: [
            raw("HKCategoryTypeIdentifierCoughing", Double(SymptomSeverity.notPresent.rawValue))
        ])
        let event = try XCTUnwrap(events.first)
        XCTAssertEqual(event.severity, .notPresent)
        XCTAssertFalse(event.severity.isPresent)
    }

    func testNewestFirst() throws {
        let events = SymptomPromotion.events(from: [
            raw("HKCategoryTypeIdentifierHeadache", 2, daysAgo: 10),
            raw("HKCategoryTypeIdentifierFatigue", 2, daysAgo: 1),
            raw("HKCategoryTypeIdentifierBloating", 2, daysAgo: 5)
        ])
        XCTAssertEqual(events.map(\.type), [.fatigue, .bloating, .headache])
    }

    /// The distinction the symptom radar will rest on. A GLP-1's
    /// gastrointestinal cluster must never be reported as an early infection
    /// signal, and fever/cough/breathlessness must not be written off as a dose
    /// reaction.
    func testTheTwoClustersDoNotOverlap() {
        for symptom in SymptomType.allCases {
            XCTAssertFalse(symptom.isCommonGLP1Effect && symptom.isInfectionLike,
                           "\(symptom) is in both clusters, so the radar cannot tell the two explanations apart")
        }
        XCTAssertTrue(SymptomType.nausea.isCommonGLP1Effect)
        // The two most characteristic dose reactions were unrepresentable
        // until 2026-08-04, so the radar's downgrade could never fire for the
        // classic reaction to a step-up. They sit in the GLP-1 cluster despite
        // also being gastroenteritis hallmarks — the disjointness rule above
        // forces the choice, and the card's copy carries the ambiguity.
        XCTAssertTrue(SymptomType.vomiting.isCommonGLP1Effect)
        XCTAssertTrue(SymptomType.diarrhea.isCommonGLP1Effect)
        XCTAssertTrue(SymptomType.fever.isInfectionLike)
        // Fatigue is the commonest illness symptom there is and is deliberately
        // not infection-like: a signal that fires on every bad night is not one.
        XCTAssertFalse(SymptomType.fatigue.isInfectionLike)
    }

    func testSeverityOrdersFromMildToSevere() {
        XCTAssertLessThan(SymptomSeverity.mild, SymptomSeverity.moderate)
        XCTAssertLessThan(SymptomSeverity.moderate, SymptomSeverity.severe)
    }

    // MARK: - The ledger must be gradeable in both directions

    /// ⚠️ **The defect this exists to stop, found on 2026-08-05 before it had a
    /// single instance.** The radar's confirm side counted any non-chronic tag;
    /// its miss side clusters only illness-like ones. `moodChanges` is neither
    /// chronic nor a known GLP-1 effect, so it could **only ever raise the hit
    /// rate and never the miss rate** — a one-directional error on the one
    /// number this app prints about its own accuracy.
    ///
    /// The general rule: **a detector may only be graded by evidence that could
    /// have gone either way.**
    func testOnlyOneDirectionalEvidenceIsBarredFromGradingTheRadar() {
        // ⚠️ Not symmetry with `isInfectionLike` — a first version asserted that
        // and two shipped tests refuted it in one run: nausea and hot flushes
        // legitimately confirm while being deliberately kept out of the miss
        // clustering.
        //
        // The exclusions are named individually rather than derived, because
        // each rests on its own argument: a mood is not evidence of a bodily
        // illness, and pain where a needle went is evidence about the needle.
        // A derived rule would be a fourth classification of the same symptoms
        // and would go stale against the reasoning it replaced.
        let barred: Set<SymptomType> = [.moodChanges, .injectionSitePain]
        for type in SymptomType.allCases where !barred.contains(type) {
            XCTAssertTrue(type.gradesTheRadar, "\(type) stopped grading the radar")
        }
        for type in barred {
            XCTAssertFalse(type.gradesTheRadar,
                           "\(type) can only ever confirm, so it would inflate the hit rate")
            XCTAssertTrue(SymptomType.allCases.contains(type),
                          "an exclusion this rule exists for has been removed")
        }
    }

    /// Named explicitly, because this is the case that was live and the reason
    /// the rule exists.
    func testAMoodTagNeverGradesTheIllnessRadar() {
        XCTAssertFalse(SymptomType.moodChanges.gradesTheRadar,
                       "a low mood would be scored as the illness radar being right")
        // Sleep changes DO grade it — disrupted sleep is a real illness
        // symptom, and unlike mood it is a statement about the body.
        XCTAssertTrue(SymptomType.sleepChanges.gradesTheRadar)
        // And the ones that genuinely are illness evidence still are.
        XCTAssertTrue(SymptomType.fever.gradesTheRadar)
        XCTAssertTrue(SymptomType.coughing.gradesTheRadar)
    }

    // MARK: - The picker must not offer a word the app cannot read

    /// **The ten strings `SideEffectEntrySheet` shipped hardcoded**, copied here
    /// verbatim as the historical record.
    ///
    /// Three of them — "Constipation", "Injection-site pain", "Loss of
    /// appetite" — had no `SymptomType` and no synonym, so the app proposed a
    /// word, wrote it down when the reader picked it, and could then only report
    /// it back through `SymptomReconciliation.unmatchedNames`. Against a daily
    /// GLP-1 log that is the app disagreeing with itself, every day.
    private static let shippedPickerStrings = [
        "Nausea", "Fatigue", "Constipation", "Diarrhoea", "Heartburn",
        "Headache", "Injection-site pain", "Loss of appetite", "Vomiting",
        "Something else"
    ]

    func testEveryNameThePickerOfferedResolvesToACanonicalSymptom() {
        for name in Self.shippedPickerStrings where name != "Something else" {
            XCTAssertNotNil(SymptomType.matching(name: name),
                            "the picker offers \"\(name)\" and nothing can reconcile it")
        }
    }

    /// The one exception, and it is not an oversight: "Something else" is the
    /// free-text sentinel. It must stay unresolvable, or a reader picking it
    /// would have their custom word filed under a symptom named after the
    /// button.
    func testTheFreeTextSentinelStaysUnresolvableAndOutOfTheCanonicalList() {
        XCTAssertNil(SymptomType.matching(name: "Something else"))
        XCTAssertFalse(SymptomType.commonlyLogged.contains { $0.title == "Something else" })
    }

    /// The generated picker must offer the same nine symptoms the hardcoded one
    /// did — this is the check that the list moved rather than changed.
    func testCommonlyLoggedCoversExactlyTheNamesThePickerOffered() {
        let expected = Self.shippedPickerStrings
            .filter { $0 != "Something else" }
            .compactMap { SymptomType.matching(name: $0) }
        XCTAssertEqual(SymptomType.commonlyLogged, expected)
    }

    /// A generated picker writes `title` and reads it back through
    /// `matching(name:)`, so anything that cannot round-trip becomes an
    /// unreconcilable record the moment it is chosen.
    ///
    /// ⚠️ `injectionSitePain` is the first title in this enum containing a
    /// hyphen, and the round-trip does **not** survive on the title fallback
    /// alone: `matching` turns "-" into " " before comparing, so
    /// "Injection-site pain" never equals its own title. It resolves only
    /// because `synonyms` carries the normalised key. Delete that key and this
    /// test is the thing that notices.
    func testEveryCommonlyLoggedSymptomRoundTripsThroughItsOwnTitle() {
        for type in SymptomType.commonlyLogged {
            XCTAssertEqual(SymptomType.matching(name: type.title), type,
                           "\(type.rawValue) does not survive being written to the log and read back")
        }
        XCTAssertEqual(SymptomType.matching(name: "Injection-site pain"), .injectionSitePain)
        XCTAssertEqual(SymptomType.matching(name: "injection site pain"), .injectionSitePain)
    }

    /// The picker's old wording still resolves, because the reader has months of
    /// entries carrying it. Renaming the display title may not orphan them.
    func testThePickersOldWordingStillResolves() {
        XCTAssertEqual(SymptomType.matching(name: "Loss of appetite"), .appetiteChanges)
        XCTAssertEqual(SymptomType.matching(name: "Constipation"), .constipation)
    }

    /// ⚠️ **An increase is deliberately absent.** Apple's category is
    /// bidirectional, so a hand entry meaning "I ate more" mapped into the same
    /// case would let the reconciliation call it agreement with a Health tag
    /// meaning the opposite — manufacturing agreement between two records that
    /// never agreed, which is the one thing the synonym table forbids.
    func testAnIncreasedAppetiteIsNotFiledAsTheDecreaseTheReaderLogs() {
        XCTAssertNil(SymptomType.matching(name: "Increased appetite"))
    }

    // MARK: - Names

    func testEverySymptomHasADistinctDisplayName() {
        for type in SymptomType.allCases {
            XCTAssertFalse(type.title.trimmingCharacters(in: .whitespaces).isEmpty,
                           "\(type.rawValue) has no display name")
        }
        let titles = SymptomType.allCases.map(\.title)
        XCTAssertEqual(Set(titles).count, titles.count,
                       "two symptoms share a display name, so a reconciled row cannot say which it is")
    }

    /// **A synonym key that the normalisation can never produce is dead weight
    /// that reads as coverage.** `matching(name:)` lowercases, turns "-" into
    /// " " and trims before the lookup, so a key carrying a capital or a hyphen
    /// is unreachable — and unreachable is indistinguishable from absent right
    /// up until somebody trusts the table.
    func testEverySynonymKeyIsReachableThroughTheNormalisation() {
        for (key, expected) in SymptomType.synonyms {
            let normalised = key.lowercased()
                .replacingOccurrences(of: "-", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            XCTAssertEqual(key, normalised,
                           "\"\(key)\" can never be looked up — matching(name:) would search for \"\(normalised)\"")
            XCTAssertEqual(SymptomType.matching(name: key), expected)
        }
    }

    /// No two symptoms may claim one word. A duplicate key in the literal traps
    /// at initialisation, so what is checkable here is the subtler collision:
    /// a symptom whose *title* is another symptom's synonym, which would make
    /// the app unable to read back a name it wrote.
    func testNoSymptomsTitleIsClaimedByADifferentSymptom() {
        for type in SymptomType.allCases {
            let key = type.title.lowercased()
                .replacingOccurrences(of: "-", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if let claimed = SymptomType.synonyms[key] {
                XCTAssertEqual(claimed, type,
                               "\"\(type.title)\" is \(type.rawValue)'s own name but resolves to \(claimed.rawValue)")
            }
        }
    }

    /// The new cases must not have quietly undone the two rules the radar rests
    /// on. (`testTheTwoClustersDoNotOverlap` covers disjointness for all cases;
    /// these name the intent for the three added on 2026-08-08.)
    func testTheThreeNewSymptomsAreDoseExplicableAndNotInfectionLike() {
        for type in [SymptomType.constipation, .appetiteChanges, .injectionSitePain] {
            XCTAssertTrue(type.isCommonGLP1Effect,
                          "\(type.rawValue) must be discountable by a dose, or a dose reaction reads as an illness")
            XCTAssertFalse(type.isInfectionLike,
                           "\(type.rawValue) would make a miss out of an ordinary dose week")
        }
    }
}
