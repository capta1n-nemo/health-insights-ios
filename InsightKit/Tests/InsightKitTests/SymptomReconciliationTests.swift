import XCTest
@testable import InsightKit

/// **What the reader logged by hand, against what Health already knew** —
/// backlog `R28`.
final class SymptomReconciliationTests: XCTestCase {

    private let calendar = TestClock.utc

    private func hand(_ name: String, _ severity: Int, daysAgo: Int)
        -> SymptomReconciliation.LoggedEffect {
        .init(name: name, severity: severity, date: TestClock.day(daysAgo))
    }

    private func tag(_ type: SymptomType, _ severity: SymptomSeverity, daysAgo: Int)
        -> SymptomEvent {
        SymptomEvent(type: type, severity: severity, date: TestClock.day(daysAgo),
                     source: .appleHealth)
    }

    /// The three relationships, which are the finding — this never picks a
    /// winner, because two records made by the same person on the same day for
    /// different purposes do not have one true value between them.
    func testTheThreeRelationshipsAreDistinguished() throws {
        let outcomes = SymptomReconciliation.reconcile(
            symptoms: [tag(.nausea, .moderate, daysAgo: 1),
                       tag(.fever, .mild, daysAgo: 2)],
            sideEffects: [hand("Nausea", 5, daysAgo: 1),
                          hand("Bloating", 3, daysAgo: 3)],
            calendar: calendar)

        let byPair = Dictionary(uniqueKeysWithValues: outcomes.map {
            ("\($0.symptom.rawValue)|\($0.agreement.rawValue)", $0)
        })
        XCTAssertNotNil(byPair["nausea|both"])
        XCTAssertNotNil(byPair["bloating|handOnly"])
        XCTAssertNotNil(byPair["fever|healthOnly"])
        XCTAssertEqual(outcomes.count, 3)
    }

    /// Newest first, like every log in this app.
    func testOutcomesAreNewestFirst() {
        let outcomes = SymptomReconciliation.reconcile(
            symptoms: [], sideEffects: [hand("Nausea", 2, daysAgo: 5),
                                        hand("Nausea", 2, daysAgo: 1)],
            calendar: calendar)
        XCTAssertEqual(outcomes.count, 2)
        XCTAssertGreaterThan(try XCTUnwrap(outcomes.first).day,
                             try XCTUnwrap(outcomes.last).day)
    }

    /// **One step apart is not a disagreement.** Mapping a ten-point scale onto
    /// four words has that much slop in it, and flagging adjacent grades would
    /// flag almost everything and mean nothing.
    func testOnlyGradesMoreThanOneStepApartAreDisputed() throws {
        // 3/10 → mild, tagged moderate: adjacent, and not a dispute.
        let adjacent = SymptomReconciliation.reconcile(
            symptoms: [tag(.nausea, .moderate, daysAgo: 1)],
            sideEffects: [hand("Nausea", 3, daysAgo: 1)], calendar: calendar)
        XCTAssertFalse(try XCTUnwrap(adjacent.first).isDisputed)

        // 9/10 → severe, tagged mild: two steps, and a real disagreement.
        let apart = SymptomReconciliation.reconcile(
            symptoms: [tag(.nausea, .mild, daysAgo: 1)],
            sideEffects: [hand("Nausea", 9, daysAgo: 1)], calendar: calendar)
        let outcome = try XCTUnwrap(apart.first)
        XCTAssertTrue(outcome.isDisputed)
        XCTAssertNotNil(outcome.note)
        XCTAssertEqual(SymptomReconciliation.disputes(
            symptoms: [tag(.nausea, .mild, daysAgo: 1)],
            sideEffects: [hand("Nausea", 9, daysAgo: 1)], calendar: calendar).count, 1)
    }

    /// The worst grade on each side, not an average — a day holding a 2 and a 9
    /// was a bad day, and the mean of them was nobody's experience.
    func testTheWorstGradeOnEachSideIsTheOneCompared() throws {
        let outcome = try XCTUnwrap(SymptomReconciliation.reconcile(
            symptoms: [tag(.nausea, .mild, daysAgo: 1)],
            sideEffects: [hand("Nausea", 2, daysAgo: 1), hand("Nausea", 9, daysAgo: 1)],
            calendar: calendar).first)
        XCTAssertEqual(outcome.handGrade, .severe)
        XCTAssertTrue(outcome.isDisputed)
    }

    /// **A recorded absence is not an occurrence.** `notPresent` means the
    /// reader checked and did not have it, and counting that as agreement would
    /// be the most misleading row this could produce.
    func testARecordedAbsenceNeverCountsAsAHealthGrade() throws {
        let outcome = try XCTUnwrap(SymptomReconciliation.reconcile(
            symptoms: [tag(.nausea, .notPresent, daysAgo: 1)],
            sideEffects: [hand("Nausea", 6, daysAgo: 1)], calendar: calendar).first)
        XCTAssertEqual(outcome.agreement, .both, "both records exist")
        XCTAssertNil(outcome.healthGrade, "but Health says they did not have it")
        XCTAssertFalse(outcome.isDisputed, "and a dispute needs two grades")
    }

    /// A vocabulary the app cannot read is **surfaced, not swallowed** — every
    /// unmatched name is a record the reader made that nothing can see.
    func testUnmatchedNamesComeBackRatherThanDisappearing() {
        let effects = [hand("Brain fog", 4, daysAgo: 1), hand("Brain fog", 5, daysAgo: 2),
                       hand("Nausea", 3, daysAgo: 1)]
        let unmatched = SymptomReconciliation.unmatchedNames(in: effects)
        XCTAssertEqual(unmatched.map(\.name), ["Brain fog"])
        XCTAssertEqual(unmatched.first?.count, 2)
        XCTAssertEqual(SymptomReconciliation.summary(
            symptoms: [], sideEffects: effects, calendar: calendar).unmatchedNames, 1)
    }

    /// Both spellings of the two most characteristic GLP-1 reactions resolve,
    /// and the app's own display titles round-trip.
    func testTheSynonymTableResolvesBothSpellingsAndOwnTitles() {
        XCTAssertEqual(SymptomType.matching(name: "Diarrhoea"), .diarrhea)
        XCTAssertEqual(SymptomType.matching(name: "diarrhea"), .diarrhea)
        XCTAssertEqual(SymptomType.matching(name: "Hot flushes"), .hotFlashes)
        XCTAssertEqual(SymptomType.matching(name: "Shortness of breath"), .shortnessOfBreath)
        for type in SymptomType.allCases {
            XCTAssertEqual(SymptomType.matching(name: type.title), type,
                           "\(type.rawValue) does not round-trip through its own title")
        }
    }

    /// ⚠️ **"Sick" stays unmatched on purpose.** It means vomiting in British
    /// English and ill in American, and a synonym that resolves one way half the
    /// time would make this report agreement it invented.
    func testSickIsDeliberatelyNotASynonym() {
        XCTAssertNil(SymptomType.matching(name: "Sick"))
    }

    /// The headline figure, and the reason it is optional: "you never tagged any
    /// of them" and "you never logged any" are opposite statements, and a 0%
    /// would say the first while meaning the second.
    func testTheShareIsNilRatherThanZeroWhenNothingWasLoggedByHand() {
        let none = SymptomReconciliation.summary(
            symptoms: [tag(.fever, .mild, daysAgo: 1)], sideEffects: [],
            calendar: calendar)
        XCTAssertNil(none.alsoInHealth)
        XCTAssertEqual(none.healthOnly, 1)

        let some = SymptomReconciliation.summary(
            symptoms: [tag(.nausea, .mild, daysAgo: 1)],
            sideEffects: [hand("Nausea", 3, daysAgo: 1), hand("Bloating", 3, daysAgo: 2)],
            calendar: calendar)
        XCTAssertEqual(some.alsoInHealth, 0.5)
    }

    /// The join is on the calendar day, not the instant: a tracker entry is
    /// typed whenever the reader remembers and a Health tag is stamped when they
    /// opened the app, so the times are not comparable.
    func testTheJoinIsOnTheCalendarDayNotTheInstant() throws {
        // Start of day explicitly: `TestClock.day` is a midday anchor, so
        // "+20 hours" off it lands on the following morning and would be
        // testing the opposite of what this claims.
        let day = calendar.startOfDay(for: TestClock.day(1))
        let outcome = try XCTUnwrap(SymptomReconciliation.reconcile(
            symptoms: [SymptomEvent(type: .nausea, severity: .moderate,
                                    date: day.addingTimeInterval(3600),
                                    source: .appleHealth)],
            sideEffects: [.init(name: "Nausea", severity: 5,
                                date: day.addingTimeInterval(20 * 3600))],
            calendar: calendar).first)
        XCTAssertEqual(outcome.agreement, .both)
    }
}
