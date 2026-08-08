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

    // MARK: - The app's own picker was the source of the unmatched names

    /// ⚠️ **The defect this batch closed.** Three of the ten strings
    /// `SideEffectEntrySheet` offered had no `SymptomType` and no synonym, so
    /// every one the reader picked arrived here — in a list whose whole purpose
    /// is to report *the reader's* vocabulary back to them. They were the app's
    /// own words. On a daily GLP-1 log that is three unreconcilable rows a day,
    /// and the reconciliation's headline share was being computed against them.
    func testThePickersOwnNamesNoLongerArriveAsUnreadableVocabulary() {
        let effects = ["Constipation", "Injection-site pain", "Loss of appetite"]
            .enumerated().map { hand($0.element, 4, daysAgo: $0.offset) }
        XCTAssertEqual(SymptomReconciliation.unmatchedNames(in: effects).map(\.name), [],
                       "the app is still offering names it cannot read back")
    }

    /// And the safety valve still works — closing the picker's gap must not have
    /// been done by making the matcher generous. A word the app genuinely does
    /// not know still comes back rather than being filed under a near miss.
    func testAGenuinelyUnknownWordIsStillSurfacedRatherThanGuessedAt() {
        let unmatched = SymptomReconciliation.unmatchedNames(
            in: [hand("Brain fog", 4, daysAgo: 1), hand("Constipation", 4, daysAgo: 1)])
        XCTAssertEqual(unmatched.map(\.name), ["Brain fog"])
        // "Sick" is the standing example and stays unmatched — see
        // `testSickIsDeliberatelyNotASynonym`. Three new cases did not change it.
        XCTAssertNil(SymptomType.matching(name: "Sick"))
    }

    /// The point of the whole exercise: a hand entry and a Health tag for the
    /// same thing on the same day now reconcile, where before the hand entry was
    /// invisible and the Health tag looked like a `healthOnly` row nobody had
    /// logged.
    func testAConstipationEntryNowJoinsTheHealthTagForTheSameDay() throws {
        let outcome = try XCTUnwrap(SymptomReconciliation.reconcile(
            symptoms: [tag(.constipation, .moderate, daysAgo: 1)],
            sideEffects: [hand("Constipation", 5, daysAgo: 1)],
            calendar: calendar).first)
        XCTAssertEqual(outcome.symptom, .constipation)
        XCTAssertEqual(outcome.agreement, .both)
    }

    /// The picker's old wording and the app's new display title are the same
    /// symptom, so months of "Loss of appetite" entries reconcile against a
    /// Health appetite tag rather than sitting in a second bucket.
    func testTheOldAndNewWordingForAppetiteReconcileAsOneSymptom() throws {
        let outcomes = SymptomReconciliation.reconcile(
            symptoms: [tag(.appetiteChanges, .mild, daysAgo: 1)],
            sideEffects: [hand("Loss of appetite", 3, daysAgo: 1),
                          hand("Appetite changes", 3, daysAgo: 1)],
            calendar: calendar)
        XCTAssertEqual(outcomes.count, 1, "one symptom, one day, one row")
        XCTAssertEqual(try XCTUnwrap(outcomes.first).agreement, .both)
    }

    /// Injection-site pain can only ever arrive by hand — Apple has no category
    /// for it — so it must reconcile as a `handOnly` row rather than vanishing.
    func testInjectionSitePainIsReadableEvenThoughHealthCanNeverKnowIt() throws {
        let outcome = try XCTUnwrap(SymptomReconciliation.reconcile(
            symptoms: [], sideEffects: [hand("Injection-site pain", 6, daysAgo: 1)],
            calendar: calendar).first)
        XCTAssertEqual(outcome.symptom, .injectionSitePain)
        XCTAssertEqual(outcome.agreement, .handOnly)
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
