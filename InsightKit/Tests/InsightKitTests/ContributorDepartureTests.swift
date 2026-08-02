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
    func testEveryContributorIsAccountedForInTheDeparturePanel() {
        let now = TestClock.now
        let samples = GoldenDataset.samples()
        let profile = ContributorsFixture.profile(now: now)
        let scan = VitalSignsCheck.evaluate(samples: samples, now: now)

        for model in InsightEngine().models {
            let result = model.evaluate(samples: samples, profile: profile, now: now)
            let contributors = result.contributors.map(\.metric)
                .filter { !PeerStandingModel.isModelled($0) }
            guard !contributors.isEmpty else { continue }

            let panel = VitalDeparturePanel.forCard(
                scan,
                cardMetrics: model.id == .readiness ? nil : contributors,
                contributorMetrics: contributors,
                samples: samples, now: now, calendar: TestClock.utc)

            let accounted = Set(panel.rows.map(\.metric))
                .union(panel.unjudged).union(panel.stale)
            for metric in contributors {
                XCTAssertTrue(
                    accounted.contains(metric),
                    "\(model.id.rawValue): \(metric.rawValue) is scored under "
                        + "\"What goes into this\" but appears nowhere in \"How far "
                        + "from your normal\" — the counts on the two sections will "
                        + "disagree and the reader cannot tell why.")
            }
        }
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
