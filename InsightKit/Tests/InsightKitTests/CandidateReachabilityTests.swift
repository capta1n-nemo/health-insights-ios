import XCTest
@testable import InsightKit

/// The other direction of the graceful-population invariant.
///
/// `ContributorCandidateTests` pins that every metric a card *reports* is also
/// *declared* — so a scored signal reaches the sections keyed on
/// `candidateMetrics` as well as the ones keyed on `contributors`. That is the
/// direction whose failure hides a signal, and it is the one the cross-card
/// audit found.
///
/// This is the reverse: **a metric a card declares but can never report.** It
/// fails more quietly — the signal appears in "How you compare" and "How far
/// from your normal" and is absent from "What goes into this", so the card looks
/// like it reads something it does not. Nothing was checking, and the audit's
/// open list carried two suspected cases for several sessions on the strength of
/// reading the code.
///
/// **Both suspicions were wrong**, and this test is why that is now settled
/// rather than believed. Sleep's absolute temperatures and Heart Health's second
/// HRV flavour are *fallbacks*: each becomes its card's contributor when the
/// preferred sibling is missing, which is a fact about the reader's device and
/// not a dead declaration.
///
/// ⚠️ **Shadowing is per-model, and checking it across the union hides it.** The
/// first version of this test unioned contributors over every model and
/// concluded body temperature was not a fallback at all — because Vital Signs
/// charts it unconditionally while Sleep only falls back to it. Both statements
/// are true; only the per-model one is useful.
final class CandidateReachabilityTests: XCTestCase {

    /// Per model: a metric whose only route into *that card* is a fallback, and
    /// the siblings that shadow it there.
    private static let shadowed: [(model: InsightID, metric: MetricType,
                                   shadowedBy: [MetricType])] = [
        (.heartHealth, .heartRateVariabilitySDNN, [.heartRateVariabilityRMSSD]),
        (.sleep, .skinTemperature, [.skinTemperatureDeviation]),
        (.sleep, .bodyTemperature, [.skinTemperatureDeviation, .skinTemperature]),
        (.energy, .heartRateVariabilitySDNN, [.heartRateVariabilityRMSSD])
    ]

    private func samples(now: Date, without withheld: Set<MetricType>) -> [HealthMetricSample] {
        var out = ContributorsFixture.fullCoverage(days: 20, now: now)
        let extra: [MetricType: Double] = [
            .exerciseMinutes: 30, .sleepOnset: -1.0, .sleepEfficiency: 90,
            .sleepDeepMinutes: 80, .sleepRemMinutes: 95, .sleepLatencyMinutes: 12,
            .screenTimeMinutes: 180
        ]
        for i in stride(from: 19, through: 0, by: -1) {
            let start = now.addingTimeInterval(-Double(i) * 86_400)
            for (metric, value) in extra {
                out.append(.init(type: metric, value: value, start: start, source: .oura))
            }
            out.append(.init(type: .activeMedicationLevel, value: 8,
                             start: start, source: .calculated))
        }
        return out.filter { !withheld.contains($0.type) }
    }

    /// **Substance Impact has to be handed a log.** Its candidates are every
    /// metric it knows how to compare before and after use, so with an empty log
    /// it reports nothing and every one of them looks unreachable. The engine
    /// binds the log through `withSubstanceLog`, and so must this.
    private func models(now: Date) -> [any InsightModel] {
        let log = stride(from: 18, through: 0, by: -3).map { daysAgo in
            SubstanceEvent(substance: .stimulant,
                           timestamp: now.addingTimeInterval(-Double(daysAgo) * 86_400))
        }
        return InsightEngine().withSubstanceLog(log).models
    }

    private func contributors(of model: any InsightModel, now: Date,
                              without withheld: Set<MetricType>) -> Set<MetricType> {
        Set(model.evaluate(samples: samples(now: now, without: withheld),
                           profile: ContributorsFixture.profile(now: now), now: now)
            .contributors.map(\.metric))
    }

    /// **Every declared candidate must be reachable as a contributor under some
    /// data.** A declaration nothing can ever satisfy is a claim the card makes
    /// and cannot keep.
    func testEveryCandidateMetricIsReachableAsAContributor() {
        let now = TestClock.now
        // Full coverage, then one scenario per shadowing rule.
        let scenarios: [Set<MetricType>] = [[]] + Self.shadowed.map { Set($0.shadowedBy) }

        for model in models(now: now) {
            var seen: Set<MetricType> = []
            for withheld in scenarios {
                seen.formUnion(contributors(of: model, now: now, without: withheld))
            }
            let unreachable = model.candidateMetrics.filter { !seen.contains($0) }
            XCTAssertEqual(
                unreachable.map(\.rawValue).sorted(), [],
                """
                \(model.id.rawValue) declares these in candidateMetrics but never reports \
                them as contributors, under full coverage or with any preferred sibling \
                withheld. They will show in How-you-compare and How-far-from-your-normal \
                while being absent from What-goes-into-this — the card claiming to read \
                something it does not. Either wire them into the score or drop the \
                declaration.
                """)
        }
    }

    /// And the fallbacks really are fallbacks. Without this the test above would
    /// keep passing if a fallback were deleted, because full coverage alone
    /// would still satisfy every declaration.
    func testEachFallbackOnlyStepsInWhenItsSiblingIsMissing() {
        let now = TestClock.now
        let registry = models(now: now)

        for rule in Self.shadowed {
            guard let model = registry.first(where: { $0.id == rule.model }) else {
                return XCTFail("no model with id \(rule.model.rawValue)")
            }
            XCTAssertFalse(
                contributors(of: model, now: now, without: []).contains(rule.metric),
                "\(rule.model.rawValue) reports \(rule.metric.rawValue) even with "
                    + "\(rule.shadowedBy.map(\.rawValue)) present — it is not a fallback "
                    + "there, so this table is wrong")
            XCTAssertTrue(
                contributors(of: model, now: now, without: Set(rule.shadowedBy))
                    .contains(rule.metric),
                "\(rule.model.rawValue) did not fall back to \(rule.metric.rawValue) when "
                    + "\(rule.shadowedBy.map(\.rawValue)) was withheld")
        }
    }
}
