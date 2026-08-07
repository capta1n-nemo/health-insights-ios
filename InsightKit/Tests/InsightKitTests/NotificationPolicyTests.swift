import XCTest
@testable import InsightKit

private let cal = TestClock.utc

/// The restraint half of Q11 — `NotificationPolicy`, `NotificationLedger` and
/// `NotificationScheduler`.
///
/// The reason these are worth testing separately from the triggers is the
/// sequencing the reader insisted on: **background delivery first, then
/// notifications on top.** Once `BGTaskScheduler` is waking the app every
/// couple of hours, the trigger pass — which is pure and re-derives every
/// finding from scratch each time — runs many times a day against unchanged
/// data. Everything that stops that becoming a stream is here, and none of it
/// is observable from a screenshot.
final class NotificationPolicyTests: XCTestCase {

    private func at(_ hour: Int) -> Date {
        cal.date(bySettingHour: hour, minute: 30, second: 0, of: TestClock.now)!
    }

    private func note(_ kind: HealthNotificationKind,
                      _ fingerprint: String = "f") -> HealthNotification {
        HealthNotification(kind: kind, fingerprint: fingerprint, title: "t", body: "b")
    }

    private var everything: NotificationPolicy {
        NotificationPolicy(enabledKinds: Set(HealthNotificationKind.allCases),
                           dailyCap: 99)
    }

    // MARK: - Quiet hours

    /// The wrap-around window is the normal one, and it is where every naive
    /// `start <= h && h < end` implementation goes wrong.
    func testQuietHoursWrapMidnight() {
        let policy = NotificationPolicy(enabledKinds: [], quietHoursStart: 22,
                                        quietHoursEnd: 7)
        XCTAssertTrue(policy.isQuiet(at: at(23), calendar: cal))
        XCTAssertTrue(policy.isQuiet(at: at(3), calendar: cal), "3am is the case this exists for")
        XCTAssertTrue(policy.isQuiet(at: at(22), calendar: cal), "the start hour is inside")
        XCTAssertFalse(policy.isQuiet(at: at(7), calendar: cal), "the end hour is outside")
        XCTAssertFalse(policy.isQuiet(at: at(12), calendar: cal))
    }

    /// A window that does not wrap still has to work.
    func testQuietHoursWithoutWrap() {
        let policy = NotificationPolicy(enabledKinds: [], quietHoursStart: 9,
                                        quietHoursEnd: 17)
        XCTAssertTrue(policy.isQuiet(at: at(12), calendar: cal))
        XCTAssertFalse(policy.isQuiet(at: at(3), calendar: cal))
    }

    /// Both ends dragged together means *no* quiet hours. The opposite reading
    /// — twenty-four hours of silence — would let one slider silence the app
    /// permanently with no way for the reader to tell that is what happened.
    func testEqualQuietHourBoundsMeanNoQuietHours() {
        let policy = NotificationPolicy(enabledKinds: [], quietHoursStart: 22,
                                        quietHoursEnd: 22)
        XCTAssertFalse(policy.isQuiet(at: at(23), calendar: cal))
        XCTAssertFalse(policy.isQuiet(at: at(3), calendar: cal))
    }

    // MARK: - Held, not dropped

    /// ⚠️ The whole sequencing argument in one assertion. A finding made at 3am
    /// must survive to morning; discarding it is the failure the background
    /// work was ordered first to prevent.
    func testAThreeAmFindingIsHeldUntilMorningRatherThanDropped() {
        let policy = NotificationPolicy(enabledKinds: Set(HealthNotificationKind.allCases),
                                        quietHoursStart: 22, quietHoursEnd: 7)
        let decision = NotificationScheduler.decide(
            candidates: [note(.symptomsDetected)], policy: policy,
            ledger: NotificationLedger(), now: at(3), calendar: cal)

        XCTAssertEqual(decision.scheduled.count, 1)
        XCTAssertTrue(decision.suppressed.isEmpty, "quiet hours hold; they never suppress")
        let deliverAt = try? XCTUnwrap(decision.scheduled.first).deliverAt
        XCTAssertEqual(cal.component(.hour, from: deliverAt ?? .distantPast), 7)
        XCTAssertGreaterThan(deliverAt ?? .distantPast, at(3))
    }

    func testOutsideQuietHoursDeliveryIsImmediate() {
        let decision = NotificationScheduler.decide(
            candidates: [note(.symptomsDetected)], policy: everything,
            ledger: NotificationLedger(), now: at(9), calendar: cal)
        XCTAssertEqual(decision.scheduled.first?.deliverAt, at(9))
    }

    // MARK: - Deduplication

    /// The rule that makes a stateless trigger pass safe on a stateful
    /// schedule: the same finding, re-derived, is not a second finding.
    func testTheSameFindingIsNeverSentTwice() {
        var ledger = NotificationLedger()
        let first = note(.symptomsDetected, "someSigns|2026-08-07")
        ledger.record(first, at: at(9))

        let decision = NotificationScheduler.decide(
            candidates: [first], policy: everything, ledger: ledger,
            now: at(11), calendar: cal)

        XCTAssertTrue(decision.isEmpty)
        XCTAssertEqual(decision.suppressed.first?.reason, .alreadySent)
    }

    /// A *different* finding of the same kind is still blocked by the cooldown,
    /// which is the floor under the fingerprint check rather than a duplicate
    /// of it.
    func testADifferentFindingOfTheSameKindWaitsForTheCooldown() {
        var ledger = NotificationLedger()
        ledger.record(note(.symptomsDetected, "someSigns|day1"), at: at(9))

        let decision = NotificationScheduler.decide(
            candidates: [note(.symptomsDetected, "strongSigns|day1")],
            policy: everything, ledger: ledger, now: at(13), calendar: cal)

        XCTAssertEqual(decision.suppressed.first?.reason, .tooSoonForKind)
    }

    /// Two candidates of one kind in a single batch: the second must see the
    /// first, not only the stored past.
    func testTwoOfOneKindInOneBatchDoNotBothGoOut() {
        let decision = NotificationScheduler.decide(
            candidates: [note(.connectorStalled, "oura|d1"),
                         note(.connectorStalled, "withings|d1")],
            policy: everything, ledger: NotificationLedger(),
            now: at(9), calendar: cal)

        XCTAssertEqual(decision.scheduled.count, 1)
        XCTAssertEqual(decision.suppressed.first?.reason, .tooSoonForKind)
    }

    // MARK: - The cap, and what it spends itself on

    /// When the cap bites it must be spent on the body, not on the reminder.
    /// This is the same judgement `SuggestionEngine` makes when it ranks an
    /// untried feature below every grounding gap.
    func testTheCapIsSpentOnTheMostImportantFindings() {
        let policy = NotificationPolicy(enabledKinds: Set(HealthNotificationKind.allCases),
                                        quietHoursStart: 0, quietHoursEnd: 0, dailyCap: 2)
        let decision = NotificationScheduler.decide(
            candidates: [note(.bodyScanDue), note(.cardChangedMajorly),
                         note(.symptomsDetected), note(.connectorStalled)],
            policy: policy, ledger: NotificationLedger(), now: at(9), calendar: cal)

        XCTAssertEqual(decision.scheduled.map { $0.notification.kind },
                       [.symptomsDetected, .connectorStalled])
        XCTAssertEqual(Set(decision.suppressed.map { $0.reason }), [.dailyCapReached])
    }

    /// A background pass every two hours must not get a fresh allowance each
    /// time it wakes, so the cap counts what the ledger already delivered today.
    func testTheCapCountsWhatWasAlreadyDeliveredToday() {
        var ledger = NotificationLedger()
        ledger.record(note(.groundingFactStale, "a"), at: at(8))
        ledger.record(note(.bodyScanDue, "b"), at: at(8))

        let policy = NotificationPolicy(enabledKinds: Set(HealthNotificationKind.allCases),
                                        quietHoursStart: 0, quietHoursEnd: 0, dailyCap: 2)
        let decision = NotificationScheduler.decide(
            candidates: [note(.symptomsDetected)], policy: policy, ledger: ledger,
            now: at(14), calendar: cal)

        XCTAssertEqual(decision.suppressed.first?.reason, .dailyCapReached)
    }

    /// A cap of zero is the reader's off switch, and it must not depend on
    /// seven separate toggles agreeing.
    func testACapOfZeroSendsNothingAtAll() {
        let decision = NotificationScheduler.decide(
            candidates: HealthNotificationKind.allCases.map { note($0) },
            policy: .silent, ledger: NotificationLedger(), now: at(9), calendar: cal)
        XCTAssertTrue(decision.isEmpty)
        XCTAssertEqual(Set(decision.suppressed.map { $0.reason }), [.disabled])
    }

    func testAKindTheReaderSwitchedOffIsSuppressedWithAReason() {
        let policy = NotificationPolicy(enabledKinds: [.symptomsDetected])
        let decision = NotificationScheduler.decide(
            candidates: [note(.bodyScanDue)], policy: policy,
            ledger: NotificationLedger(), now: at(9), calendar: cal)
        XCTAssertEqual(decision.suppressed.first?.reason, .disabled)
    }

    // MARK: - Defaults

    /// The two the reader named are on. Everything invented under the creative
    /// authority they granted is opt-in — something nobody asked for should not
    /// arrive unasked.
    func testOnlyTheNamedAsksAndTheDataLossWarningAreOnByDefault() {
        XCTAssertEqual(NotificationPolicy.standard.enabledKinds,
                       [.symptomsDetected, .cardChangedMajorly, .connectorStalled])
    }

    // MARK: - The ledger

    func testTheLedgerForgetsNothingInsideAnyKindsCooldown() {
        let longest = HealthNotificationKind.allCases.map(\.minimumInterval).max() ?? 0
        XCTAssertGreaterThan(NotificationLedger.retention, longest,
                             "pruning must never silently shorten a cooldown")
    }

    func testPruningDropsOnlyWhatIsPastRetention() {
        var ledger = NotificationLedger()
        ledger.record(note(.symptomsDetected, "old"),
                      at: TestClock.now.addingTimeInterval(-NotificationLedger.retention - 86_400))
        ledger.record(note(.symptomsDetected, "new"), at: TestClock.now)
        ledger.pruned(asOf: TestClock.now)

        XCTAssertEqual(ledger.deliveries.count, 1)
        XCTAssertTrue(ledger.hasDelivered("symptomsDetected|new"))
    }

    /// The ledger key is the kind plus the finding, never a timestamp — two
    /// evaluations of one fact have to collide.
    func testIdentityIsTheFindingNotTheDelivery() {
        let a = HealthNotification(kind: .symptomsDetected, fingerprint: "x",
                                   title: "one", body: "one")
        let b = HealthNotification(kind: .symptomsDetected, fingerprint: "x",
                                   title: "reworded", body: "reworded")
        XCTAssertEqual(a.id, b.id)
    }
}
