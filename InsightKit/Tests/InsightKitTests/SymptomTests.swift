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
        XCTAssertTrue(SymptomType.fever.isInfectionLike)
        // Fatigue is the commonest illness symptom there is and is deliberately
        // not infection-like: a signal that fires on every bad night is not one.
        XCTAssertFalse(SymptomType.fatigue.isInfectionLike)
    }

    func testSeverityOrdersFromMildToSevere() {
        XCTAssertLessThan(SymptomSeverity.mild, SymptomSeverity.moderate)
        XCTAssertLessThan(SymptomSeverity.moderate, SymptomSeverity.severe)
    }
}
