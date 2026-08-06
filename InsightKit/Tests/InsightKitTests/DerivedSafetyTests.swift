import XCTest
@testable import InsightKit

/// The reader's condition on "anything may read anything": safeguards, tests
/// and reporting from day zero. These are those tests — written while **no
/// registered model reads a derived series yet**, so the first one wired is
/// born inside the fence rather than having it built around it later.
///
/// The three safeguards, and where each is held:
///
/// 1. **Every read is lagged a day** — structural, `DerivedSeriesStore.upTo`.
/// 2. **Every read is declared** — structural, `filtered(to:)` plus the graph.
/// 3. **Every loop's gain is measured** — `DerivedFeedbackAudit`, and the
///    registered-models test here fails CI the day a diverging loop ships.
final class DerivedSafetyTests: XCTestCase {

    private let now = TestClock.day(0)
    private let calendar = TestClock.utc

    // MARK: - Safeguard 1: the snapshot cannot contain the evaluation day

    func testTheConsumerSnapshotExcludesTheEvaluationDay() {
        var store = DerivedSeriesStore()
        let spec = DerivedSeriesSpec(id: DerivedSeriesID(.fitness, "fitnessAge"),
                                     displayName: "Fitness age", unit: "years",
                                     producedBy: .fitness, kind: .modelOutput)
        store.record(spec, value: 67, on: TestClock.day(1), calendar: calendar)
        store.record(spec, value: 66, on: now, calendar: calendar)

        let snapshot = store.upTo(day: now, calendar: calendar)
        XCTAssertNil(snapshot.value(spec.id, on: now, calendar: calendar),
                     "a model scoring today must not be able to see today's own output — this is what makes a self-read a defined difference equation instead of an evaluation-order puzzle")
        XCTAssertEqual(snapshot.value(spec.id, on: TestClock.day(1), calendar: calendar), 67,
                       "yesterday is exactly what it may see")
    }

    func testASeriesWhoseEveryPointIsCutIsAbsentNotEmpty() {
        var store = DerivedSeriesStore()
        let spec = DerivedSeriesSpec(id: DerivedSeriesID(.fitness, "fitnessAge"),
                                     displayName: "Fitness age", unit: "years",
                                     producedBy: .fitness, kind: .modelOutput)
        store.record(spec, value: 66, on: now, calendar: calendar)
        let snapshot = store.upTo(day: now, calendar: calendar)
        XCTAssertNil(snapshot.spec(spec.id),
                     "as of yesterday this series had never been computed, and the snapshot has to say so")
    }

    // MARK: - Safeguard 2: an undeclared read comes back empty

    func testAnUndeclaredSeriesIsInvisibleThroughTheFilter() {
        var store = DerivedSeriesStore()
        let declared = DerivedSeriesSpec(id: DerivedSeriesID(.fitness, "fitnessAge"),
                                         displayName: "Fitness age", unit: "years",
                                         producedBy: .fitness, kind: .modelOutput)
        let undeclared = DerivedSeriesSpec(id: DerivedSeriesID(.sleep, "debt"),
                                           displayName: "Sleep debt", unit: "h",
                                           producedBy: .sleep, kind: .modelOutput)
        store.record(declared, value: 67, on: TestClock.day(1), calendar: calendar)
        store.record(undeclared, value: 2.5, on: TestClock.day(1), calendar: calendar)

        let filtered = store.filtered(to: [declared.id])
        XCTAssertNotNil(filtered.spec(declared.id))
        XCTAssertNil(filtered.spec(undeclared.id),
                     "reading something you did not declare must fail visibly-empty, not work silently — the dependency graph is only complete if declarations are")
    }

    // MARK: - The graph

    private struct Consumer: InsightModel {
        let id: InsightID
        let title = "Test"
        let reads: [DerivedSeriesID]
        var derivedInputs: [DerivedSeriesID] { reads }
        var requirements: [GroundingRequirement] { [] }
        var candidateMetrics: [MetricType] { [.heartRate] }
        var contributions: [ContributionRoute] { [] }
        func evaluate(samples: [HealthMetricSample], profile: UserHealthProfile,
                      now: Date) -> InsightResult {
            InsightResult(id: id, title: title, primaryValue: nil, headline: "",
                          score: nil, confidence: .low, explanation: "",
                          drivers: [], unmetRequirements: [])
        }
    }

    func testAnAcyclicReadIsAnEdgeAndNoCycle() {
        let models: [any InsightModel] = [
            Consumer(id: .biologicalAge, reads: [DerivedSeriesID(.fitness, "fitnessAge")]),
            Consumer(id: .fitness, reads: [])
        ]
        XCTAssertEqual(DerivedDependencies.edges(of: models).count, 1)
        XCTAssertTrue(DerivedDependencies.cycles(in: models).isEmpty)
    }

    func testASelfReadIsReportedAsALoop() {
        let models: [any InsightModel] = [
            Consumer(id: .fitness, reads: [DerivedSeriesID(.fitness, "fitnessAge")])
        ]
        let cycles = DerivedDependencies.cycles(in: models)
        XCTAssertEqual(cycles.count, 1)
        XCTAssertEqual(cycles.first?.cards, [.fitness],
                       "a card reading its own yesterday is allowed — and must be visible, because it is the shape that can drift")
    }

    func testAMutualReadIsOneCycleReportedOnce() {
        let models: [any InsightModel] = [
            Consumer(id: .fitness, reads: [DerivedSeriesID(.biologicalAge, "age")]),
            Consumer(id: .biologicalAge, reads: [DerivedSeriesID(.fitness, "fitnessAge")])
        ]
        let cycles = DerivedDependencies.cycles(in: models)
        XCTAssertEqual(cycles.count, 1,
                       "A→B→A found from either end is the same loop and must have one spelling")
    }

    func testADeclaredInputWithNoProducerIsNamed() {
        let models: [any InsightModel] = [
            Consumer(id: .fitness, reads: [DerivedSeriesID(.sleep, "debt")])
            // .sleep not registered.
        ]
        XCTAssertEqual(DerivedDependencies.unproducedInputs(of: models),
                       [DerivedSeriesID(.sleep, "debt")],
                       "a read that can only ever be empty is the same family of silent wrongness as a cycle")
    }

    // MARK: - Safeguard 3: the gain audit

    /// A contractive loop: each pass moves half as far as the last. The audit
    /// must call it stable.
    func testAContractiveLoopConverges() {
        let spec = DerivedSeriesSpec(id: DerivedSeriesID(.fitness, "x"),
                                     displayName: "x", unit: "",
                                     producedBy: .fitness, kind: .modelOutput)
        let report = DerivedFeedbackAudit.audit { input in
            var out = DerivedSeriesStore()
            for daysAgo in 1...10 {
                let day = TestClock.day(daysAgo)
                let fed = input.value(spec.id,
                                      on: TestClock.day(daysAgo + 1),
                                      calendar: self.calendar) ?? 0
                // value = data + 0.5 × yesterday's value: gain 0.5.
                out.record(spec, value: 10 + 0.5 * fed, on: day, calendar: self.calendar)
            }
            return out
        }
        XCTAssertTrue(report.isStable,
                      "gain 0.5 settles toward a fixed point — flexibility with this shape is safe")
        XCTAssertFalse(report.drifts.isEmpty,
                       "and the loop is still *reported*, not merely tolerated")
    }

    /// An amplifying loop: each pass moves further than the last. This is the
    /// drift the reader asked to be protected from, and the audit must name it.
    func testAnAmplifyingLoopIsCaught() {
        let spec = DerivedSeriesSpec(id: DerivedSeriesID(.fitness, "x"),
                                     displayName: "x", unit: "",
                                     producedBy: .fitness, kind: .modelOutput)
        let report = DerivedFeedbackAudit.audit { input in
            var out = DerivedSeriesStore()
            for daysAgo in 1...10 {
                let day = TestClock.day(daysAgo)
                let fed = input.value(spec.id,
                                      on: TestClock.day(daysAgo + 1),
                                      calendar: self.calendar) ?? 0
                // Gain 2: the score feeds on itself faster than data corrects it.
                out.record(spec, value: 10 + 2.0 * fed, on: day, calendar: self.calendar)
            }
            return out
        }
        XCTAssertFalse(report.isStable)
        XCTAssertEqual(report.diverging.first?.series, spec.id,
                       "the audit names the series doing the drifting, so the fix has an address")
    }

    func testAnAcyclicSystemIsExactAfterOnePass() {
        // The common case: a consumer reading another card's output, no loop
        // anywhere. Order 1 is already the fixed point and the audit is quiet.
        let producer = DerivedSeriesSpec(id: DerivedSeriesID(.fitness, "fitnessAge"),
                                         displayName: "Fitness age", unit: "years",
                                         producedBy: .fitness, kind: .modelOutput)
        let report = DerivedFeedbackAudit.audit { _ in
            var out = DerivedSeriesStore()
            for daysAgo in 1...5 {
                out.record(producer, value: 67, on: TestClock.day(daysAgo),
                           calendar: self.calendar)
            }
            return out
        }
        XCTAssertTrue(report.isStable)
        XCTAssertTrue(report.drifts.isEmpty)
    }

    // MARK: - The fence around the registered models, from day zero

    /// Fails the moment someone wires a diverging loop into the shipped engine.
    /// Runs against every registered model on the full fixture, so it is not an
    /// opt-in for whoever adds the first consumer.
    func testTheRegisteredEngineHasNoUndeclaredProducersAndNoDivergingLoops() {
        let models = InsightEngine().models

        XCTAssertEqual(DerivedDependencies.unproducedInputs(of: models).map(\.rawValue), [],
                       "every declared derived input must name a registered producer")

        let samples = ContributorsFixture.fullCoverage(days: 40, now: now)
        let profile = ContributorsFixture.profile(now: now)
        let report = DerivedFeedbackAudit.audit { _ in
            // Models do not yet bind an input store; when the first consumer
            // lands, this closure must hand `input` to the engine's binding —
            // and the test is already here waiting for it.
            DerivedBackfill.fill(models: models, samples: samples, profile: profile,
                                 days: 20, calendar: calendar, now: now)
        }
        XCTAssertTrue(report.isStable,
                      report.diverging.map(\.series.rawValue).joined(separator: ", "))
    }

    /// The standing report exists and is generated from the models, so it
    /// cannot go stale. Today it says nothing reads anything — which is itself
    /// worth pinning, because the day it changes this line of the report is
    /// how the change announces itself.
    func testTheDependencyReportIsGeneratedNotMaintained() {
        let report = DerivedDependencies.report(models: InsightEngine().models)
        XCTAssertTrue(report.contains("No card reads a derived series yet."))
    }
}
