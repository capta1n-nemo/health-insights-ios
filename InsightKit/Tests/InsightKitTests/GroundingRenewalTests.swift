import XCTest
@testable import InsightKit

private let renewNow = Date(timeIntervalSince1970: 1_700_000_000)
private let day: TimeInterval = 86_400

/// `requirementStatuses` has always returned `.satisfied` / `.stale` /
/// `.missing`, and every caller threw away everything but `.missing`. So a fact
/// the user gave was invisible until the day it expired — no "good for another
/// two months", no warning before a cuff reading lapsed, just a prompt appearing
/// out of nowhere for something that had been ageing quietly for six.
final class GroundingRenewalTests: XCTestCase {

    private func renewal(_ kind: GroundingKind, recordedDaysAgo: Double?,
                         mandatory: Bool = true) -> GroundingRenewal {
        let input = recordedDaysAgo.map {
            GroundingInput(kind: kind, value: 5.5,
                           recordedAt: renewNow.addingTimeInterval(-$0 * day))
        }
        return GroundingRenewal.evaluate(kind: kind, input: input,
                                         isMandatory: mandatory, now: renewNow)
    }

    func testAFactNeverRecordedIsMissing() {
        XCTAssertEqual(renewal(.totalCholesterol, recordedDaysAgo: nil).state, .missing)
    }

    /// Cholesterol's window is six months. A month-old panel is comfortably fine.
    func testAFreshFactIsCurrent() {
        XCTAssertEqual(renewal(.totalCholesterol, recordedDaysAgo: 30).state, .current)
    }

    /// The warning has to arrive *before* the lapse, or it isn't a warning.
    /// A fifth of the window: about five weeks' notice on a lipid panel.
    func testAFactNearingItsWindowIsExpiringSoon() {
        XCTAssertEqual(renewal(.totalCholesterol, recordedDaysAgo: 155).state, .expiringSoon)
    }

    func testAFactPastItsWindowIsStale() {
        XCTAssertEqual(renewal(.totalCholesterol, recordedDaysAgo: 200).state, .stale)
    }

    /// The notice scales with the window, which is the whole reason it's a
    /// fraction: three days on a cuff reading, five weeks on a blood test.
    /// A fixed number of days would be useless on one and permanent on the other.
    func testTheWarningWindowScalesWithTheFactsOwnLifetime() {
        XCTAssertEqual(renewal(.cuffSystolic, recordedDaysAgo: 12).state, .expiringSoon)
        XCTAssertEqual(renewal(.cuffSystolic, recordedDaysAgo: 5).state, .current)
    }

    /// A date of birth is not a thing to renew.
    func testAFactThatNeverExpiresIsAlwaysCurrent() {
        let value = renewal(.dateOfBirth, recordedDaysAgo: 4000)
        XCTAssertEqual(value.state, .current)
        XCTAssertNil(value.expiresAt)
        XCTAssertTrue(value.sentence(asOf: renewNow).contains("doesn't expire"))
    }

    func testExpiryIsRecordedPlusTheWindow() throws {
        let value = renewal(.cuffSystolic, recordedDaysAgo: 1)
        let expected = renewNow.addingTimeInterval(-day)
            .addingTimeInterval(try XCTUnwrap(GroundingKind.cuffSystolic.freshness))
        XCTAssertEqual(try XCTUnwrap(value.expiresAt).timeIntervalSince1970,
                       expected.timeIntervalSince1970, accuracy: 1)
    }

    // MARK: - What it says

    /// A stale value keeps being used, and implying it was discarded would be a
    /// second inaccuracy on top of the first.
    func testAStaleFactSaysItIsStillUsed() {
        let sentence = renewal(.totalCholesterol, recordedDaysAgo: 200).sentence(asOf: renewNow)
        XCTAssertTrue(sentence.contains("still used"), sentence)
    }

    func testACurrentFactSaysHowLongItHasLeft() {
        let sentence = renewal(.totalCholesterol, recordedDaysAgo: 30).sentence(asOf: renewNow)
        XCTAssertTrue(sentence.contains("Current for another"), sentence)
    }

    /// Nobody wants "13.4 days".
    func testDurationsAreRoundedToAUnitAPersonWouldSay() {
        XCTAssertEqual(GroundingRenewal.approximate(3 * 3600), "3 hours")
        XCTAssertEqual(GroundingRenewal.approximate(5 * day), "5 days")
        XCTAssertEqual(GroundingRenewal.approximate(21 * day), "3 weeks")
        XCTAssertEqual(GroundingRenewal.approximate(90 * day), "3 months")
        XCTAssertEqual(GroundingRenewal.approximate(1 * day), "1 day")
    }

    // MARK: - The engine-wide view

    /// The whole point: a renewal list that only shows what's missing can't tell
    /// you everything is in order, and can't warn you before it isn't.
    func testTheEngineKeepsTheSatisfiedFactsToo() {
        var profile = UserHealthProfile()
        profile.set(.init(kind: .dateOfBirth, value: 0, recordedAt: renewNow))
        profile.set(.init(kind: .biologicalSex, value: 0, recordedAt: renewNow))
        let renewals = InsightEngine().groundingRenewals(profile: profile, now: renewNow)
        XCTAssertTrue(renewals.contains { $0.kind == .dateOfBirth && $0.state == .current })
        XCTAssertTrue(renewals.contains { $0.state == .missing })
    }

    /// Worst first, so the list opens on what needs doing.
    func testTheListIsOrderedWorstFirst() {
        var profile = UserHealthProfile()
        profile.set(.init(kind: .totalCholesterol, value: 5.5,
                          recordedAt: renewNow.addingTimeInterval(-200 * day)))
        profile.set(.init(kind: .dateOfBirth, value: 0, recordedAt: renewNow))
        let states = InsightEngine().groundingRenewals(profile: profile, now: renewNow)
            .map(\.state)
        let order: [GroundingRenewal.State] = [.missing, .stale, .expiringSoon, .current]
        let ranks = states.compactMap { order.firstIndex(of: $0) }
        XCTAssertEqual(ranks, ranks.sorted(), "renewals came back out of order: \(states)")
    }

    /// Every fact any insight asks for appears exactly once, however many cards
    /// want it.
    func testEachFactAppearsExactlyOnce() {
        let renewals = InsightEngine().groundingRenewals(profile: .init(), now: renewNow)
        XCTAssertEqual(Set(renewals.map(\.kind)).count, renewals.count)
        XCTAssertFalse(renewals.isEmpty)
    }

    /// Mandatory-for-one-card beats optional-for-another; the strictest claim on
    /// a fact is the one that counts.
    func testAFactMandatoryAnywhereIsReportedAsMandatory() throws {
        let renewals = InsightEngine().groundingRenewals(profile: .init(), now: renewNow)
        let dateOfBirth = try XCTUnwrap(renewals.first { $0.kind == .dateOfBirth })
        XCTAssertTrue(dateOfBirth.isMandatory,
                      "Body Composition asks for it optionally; the risk models require it")
    }
}
