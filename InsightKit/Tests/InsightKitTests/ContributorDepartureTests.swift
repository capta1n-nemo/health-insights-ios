import XCTest
@testable import InsightKit

/// **The sections must agree about which signals a card has.**
///
/// The user, counting the Readiness card's own headers: drivers 20, "What goes
/// into this" 11, "How this is weighted" 11, "How you compare" 11, "How far from
/// your normal" 10. *"How is this possible and why!?"*
///
/// Two different faults produced that, and this pins the one that is a real
/// coverage gap: a metric a card **scores** was missing from "How far from your
/// normal" whenever the clinical scan had no spec for it — sleep duration on
/// Readiness (weight 0.20), steps and active energy on Fitness. The other fault
/// was a mislabel: "What's driving this" counts sentences, and called them
/// signals.
final class ContributorDepartureTests: XCTestCase {

    /// Every metric a model reports as a contributor is accounted for by the
    /// departure panel — drawn as a row, or named as unjudged/stale. Silence is
    /// the one thing it may not be.
    ///
    /// ⚠️ **On `ContributorsFixture.fullCoverage`, not `GoldenDataset`, since
    /// 2026-08-07.** The golden dataset carries five metrics (HR, RHR, rMSSD,
    /// temperature, sleep), and this sweep opens with
    /// `guard !contributors.isEmpty else { continue }` — so Fitness, Body
    /// Composition, Blood Pressure, Nutrition, Metabolism, Gait and the rest
    /// had **never once** been checked against the departure panel. Every one
    /// of them was skipped in silence by the test whose name says it covers
    /// every contributor. The guard survives because log-driven cards
    /// legitimately have nothing to check; what it may no longer do is decide
    /// on its own which cards those are, which is
    /// `testTheSweepExaminesEveryModelThatCanHaveContributors` below.
    /// A metric the clinical scan deliberately hides behind a better one.
    ///
    /// `Spec.supersededBy` exists so the same physiology is not drawn twice —
    /// raw skin temperature stands down when the deviation produced a reading.
    /// The card still scores both, so "accounted for" has to mean *this metric
    /// or the one standing in for it*, or the sweep would demand the panel undo
    /// a rule the scan applies on purpose.
    private func supersedes(_ metric: MetricType) -> MetricType? {
        VitalSignsCheck.specs.first { $0.metric == metric }?.supersededBy
    }

    func testEveryContributorIsAccountedForInTheDeparturePanel() {
        let now = TestClock.now
        let samples = ContributorsFixture.fullCoverage(now: now)
        let profile = ContributorsFixture.profile(now: now)
        let scan = VitalSignsCheck.evaluate(samples: samples, now: now)
        var checked = 0

        for model in InsightEngine().models {
            let result = model.evaluate(samples: samples, profile: profile, now: now)
            let contributors = result.contributors.map(\.metric)
                .filter { !PeerStandingModel.isModelled($0) }
            // **What the card actually scores.** A zero-weight contributor is
            // charted rather than scored, and the panel leaves it out on
            // purpose — its own doc: "the same decision the weighted
            // contribution card makes for zero-weight contributors ... a mark
            // at the origin claims a measurement that was never judged". The
            // regression this test was written for (sleep duration on
            // Readiness) carries weight 0.20, so this narrowing keeps every
            // case the name promises.
            let scored = result.contributors.filter { $0.weight > 0 }.map(\.metric)
                .filter { !PeerStandingModel.isModelled($0) }
            guard !contributors.isEmpty else { continue }

            let panel = VitalDeparturePanel.forCard(
                scan,
                cardMetrics: model.id == .readiness ? nil : contributors,
                contributorMetrics: contributors,
                samples: samples, now: now, calendar: TestClock.utc)

            let accounted = Set(panel.rows.map(\.metric))
                .union(panel.unjudged).union(panel.stale)
            for metric in scored {
                checked += 1
                XCTAssertTrue(
                    accounted.contains(metric)
                        || supersedes(metric).map(accounted.contains) == true,
                    "\(model.id.rawValue): \(metric.rawValue) is scored under "
                        + "\"What goes into this\" but appears nowhere in \"How far "
                        + "from your normal\" — the counts on the two sections will "
                        + "disagree and the reader cannot tell why.")
            }
        }

        // The sweep's own reach, stated so a future narrowing cannot hollow it
        // out in silence: on `GoldenDataset` it checked a couple of dozen
        // metric/card pairs across five cards; it now checks the register.
        XCTAssertGreaterThan(checked, 50,
                             "the sweep now examines only \(checked) scored contributors — "
                             + "something upstream stopped producing them")
    }

    /// **The census.** The sweep above may skip a card only because that card
    /// genuinely reports no sensed contributors — never because the fixture was
    /// too thin to make it speak.
    ///
    /// Same shape as `ScoreAttributionTests.testEveryRegisteredModelScores
    /// OnTheFixture`, and here for the same reason: a `guard … continue` is a
    /// guard that hides, and the only defence is a companion asserting that the
    /// set examined is the set that exists. The exemption is derived from
    /// `InsightModel.readsOnlySamples` rather than listed, so a new log-driven
    /// card needs no edit here and a new *sensed* card that stays silent fails.
    func testTheSweepExaminesEveryModelThatCanHaveContributors() {
        let now = TestClock.now
        let samples = ContributorsFixture.fullCoverage(now: now)
        let profile = ContributorsFixture.profile(now: now)

        var examined: [InsightID] = []
        var silent: [InsightID] = []
        for model in InsightEngine().models {
            let contributors = model.evaluate(samples: samples, profile: profile, now: now)
                .contributors.map(\.metric)
                .filter { !PeerStandingModel.isModelled($0) }
            if contributors.isEmpty { silent.append(model.id) } else { examined.append(model.id) }
        }

        // Cards whose input is a log the fixture does not carry — a substance
        // entry, a calendar, a flight. They have nothing sensed to place on a
        // departure panel, and that is a property of the card, not of the data.
        let logDriven = Set(InsightEngine().models.filter { !$0.readsOnlySamples }.map(\.id))
        XCTAssertTrue(silent.allSatisfy { logDriven.contains($0) },
                      "these cards read samples and still contribute nothing on a fully "
                      + "covered fixture, so the departure sweep skips them without "
                      + "saying so: \(silent.filter { !logDriven.contains($0) }.map(\.rawValue))")

        // Stated in the failing direction as well: the sweep must actually be
        // looking at more than a handful of cards. On `GoldenDataset` — five
        // metrics — it examined a fraction of the register for weeks.
        XCTAssertGreaterThanOrEqual(
            examined.count, InsightEngine().models.count - logDriven.count,
            "the departure sweep examines only \(examined.count) of "
            + "\(InsightEngine().models.count) cards: \(examined.map(\.rawValue))")
    }

    /// The specific regression: Readiness scores sleep duration at weight 0.20,
    /// the clinical scan has no spec for it, and it must still reach the strip.
    func testReadinessSleepDurationReachesTheDepartureStrip() throws {
        let now = TestClock.now
        let samples = GoldenDataset.samples()
        let scan = VitalSignsCheck.evaluate(samples: samples, now: now)
        XCTAssertFalse(VitalSignsCheck.coveredMetrics.contains(.sleepDurationHours),
                       "premise: the clinical scan has no sleep-duration spec")

        let panel = VitalDeparturePanel.forCard(
            scan, cardMetrics: nil,
            contributorMetrics: [.sleepDurationHours],
            samples: samples, now: now, calendar: TestClock.utc)

        let accounted = Set(panel.rows.map(\.metric))
            .union(panel.unjudged).union(panel.stale)
        XCTAssertTrue(accounted.contains(.sleepDurationHours))
    }

    /// Readiness used to narrate a scored metric twice — its own component line
    /// plus the scan's "in your normal range" line for the same signal — which is
    /// most of why its driver count ran to nearly double every other section's.
    ///
    /// **Built on a deliberately steady fixture.** The shared golden dataset has
    /// every vital flagged watch/unusual, so it produces no ordinary-range lines
    /// at all and this test would pass without testing anything. The duplication
    /// only fires when vitals are *normal* — which is most days, and is exactly
    /// the reader's own situation.
    func testReadinessDoesNotNarrateAScoredMetricTwice() {
        let now = TestClock.now
        let cal = TestClock.utc
        // Rock-steady vitals, so the scan calls them normal and readiness scores
        // the same metrics as components.
        var samples: [HealthMetricSample] = []
        let steady: [MetricType: Double] = [
            .restingHeartRate: 58, .heartRateVariabilityRMSSD: 48,
            .respiratoryRate: 14, .oxygenSaturation: 97,
            .skinTemperatureDeviation: 0.05, .sleepDurationHours: 7.5
        ]
        for day in stride(from: 27, through: 0, by: -1) {
            let start = cal.date(byAdding: .day, value: -day, to: now) ?? now
            for (metric, value) in steady {
                // Real day-to-day movement, so each series has a spread and can
                // yield a z-score — without one the component is skipped and the
                // duplication this test is about never arises. (The first version
                // used `(day * 3) % 3`, which is identically zero: a constant
                // series, no spread, no components. It looked like a fixture and
                // behaved like a flat line.)
                let jitter = Double(day % 5 - 2) * 0.02 * value
                samples.append(.init(type: metric, value: value + jitter,
                                     start: start, source: .oura))
            }
        }

        let result = ReadinessInsight().evaluate(
            samples: samples, events: [], profile: UserHealthProfile(), now: now)
        let scan = VitalSignsCheck.evaluate(samples: samples, now: now)

        // **The metrics readiness scored as its own components** — not the
        // blended contributor list. A metric that reaches the score only as a
        // *supporting* scan signal has no component line of its own, so the
        // scan's line is the only thing naming it and must stay.
        let scored = Set(ReadinessScore.evaluate(samples: samples, now: now)?
            .contributions.map(\.metric) ?? [])
        XCTAssertFalse(scored.isEmpty, "fixture produced no scored components")

        // The premise: this fixture really does produce ordinary-range readings
        // for metrics readiness scores. Without it the assertion below is empty.
        let normalAndScored = scan.readings.filter {
            $0.status == .normal && scored.contains($0.metric)
        }
        XCTAssertFalse(normalAndScored.isEmpty,
                       "fixture no longer exercises the duplication it was built for")

        for metric in scored {
            let ordinaryLines = result.driverLines.filter {
                $0.text.hasPrefix(metric.displayName)
                    && $0.text.lowercased().contains("in your normal range")
            }
            XCTAssertTrue(ordinaryLines.isEmpty,
                          "\(metric.rawValue) is scored as a component and still "
                              + "gets its own ordinary-range line — that is the "
                              + "duplication that doubled the driver count")
        }
    }
}
