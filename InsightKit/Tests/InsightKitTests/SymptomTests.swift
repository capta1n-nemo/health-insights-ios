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
    func testOnlyMoodIsBarredFromGradingTheRadar() {
        // ⚠️ Not symmetry with `isInfectionLike` — a first version asserted that
        // and two shipped tests refuted it in one run: nausea and hot flushes
        // legitimately confirm while being deliberately kept out of the miss
        // clustering. The exclusion is mood specifically, and the reason is that
        // a mood is not evidence of a bodily illness.
        for type in SymptomType.allCases where type != .moodChanges {
            XCTAssertTrue(type.gradesTheRadar, "\(type) stopped grading the radar")
        }
        XCTAssertTrue(SymptomType.allCases.contains(.moodChanges),
                      "the one exclusion this rule exists for has been removed")
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
}
