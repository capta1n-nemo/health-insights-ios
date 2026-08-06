import XCTest
@testable import InsightKit

/// **A derived weight must say which derived thing it is.**
///
/// The reader, 2026-08-06: *"the metrics we are deriving from each card, are
/// still not being turned into their own individual data sources, and used,
/// especially in weightings. E.g. in Biological age card, we created a
/// 'Combined' score, that now should be a score that gets its own data row."*
/// And, in the same conversation: *"Do this for EVERY card, and make it a rule
/// for every card going forward."*
///
/// `ScoreFactor.Source.derived` used to carry no payload, so a card could put
/// "Recent substance load — 42%" on screen and nothing could answer what that
/// figure had been doing all month. It carries a `DerivedSeriesID` now, and this
/// file is the mechanical half of the rule: **the id has to name a series the
/// same result actually produces.**
///
/// ## Why this check and not the obvious one
///
/// The tempting assertion is *"every card declares at least one derived
/// figure"*. It would be false, and falsely: Readiness and Heart Health are
/// weighted means of per-metric sub-scores with no pooled statistic, no fitted
/// term and no unit conversion anywhere — they have nothing to declare, and a
/// test demanding one would be answered by inventing a figure, which is the
/// opposite of what the rule is for.
///
/// What *is* checkable, and real, is that **no anonymous or dangling derived
/// weight exists anywhere in the shipped engine**. A row that links to a page
/// with nothing on it is worse than a row that links nowhere, and this fails the
/// build on the day one is written.
final class DerivedFactorIdentityTests: XCTestCase {

    private let now = TestClock.now

    // MARK: - The rule, over every registered model

    /// Every `.derived(id)` factor names a series the same result produces.
    ///
    /// The right-hand side is `DerivedHarvest.series(from:)` rather than
    /// `derivedOutputs` alone, because the harvest is the whole truth: a factor
    /// may legitimately point at a `.componentScore` or `.componentDeparture`
    /// tier, which no model declares by hand.
    func testNoCardCarriesAnAnonymousOrDanglingDerivedWeight() {
        let samples = ContributorsFixture.fullCoverage(now: now)
        let profile = ContributorsFixture.profile(now: now)

        for model in InsightEngine().models {
            let result = model.evaluate(samples: samples, profile: profile, now: now)
            let produced = Set(DerivedHarvest.series(from: result).map { $0.0.id })
            let rows = result.weightedFactors + result.unweightedFactors

            for id in rows.compactMap(\.derivedSeries) {
                XCTAssertTrue(produced.contains(id),
                              "\(model.id.rawValue) weights a derived factor on "
                                  + "\(id.rawValue), which it does not produce — the "
                                  + "row would link to an empty page")
                XCTAssertEqual(id.producedBy, result.id,
                               "\(model.id.rawValue) claims a series namespaced to "
                                   + "\(id.producedBy?.rawValue ?? "nothing") — a card's "
                                   + "own rows must name its own series")
            }
        }
    }

    /// The other half of the same rule: a produced figure is not allowed to be a
    /// silent zero. Either it carries a share or its row says why it doesn't.
    ///
    /// `ScoreAttributionTests.testAnUnweightedRowAlwaysSaysWhy` holds this for
    /// every unweighted row on every card; this narrows it to the derived ones
    /// so a failure names the right rule.
    func testEveryDerivedRowEitherCarriesAShareOrSaysWhyItDoesNot() {
        let samples = ContributorsFixture.fullCoverage(now: now)
        let profile = ContributorsFixture.profile(now: now)

        for model in InsightEngine().models {
            let result = model.evaluate(samples: samples, profile: profile, now: now)
            for row in result.unweightedFactors where row.derivedSeries != nil {
                XCTAssertTrue(row.detail.contains(" — "),
                              "\(model.id.rawValue): \"\(row.name)\" is a derived figure "
                                  + "at weight 0 with no stated reason")
            }
        }
    }

    // MARK: - The id round-trips

    func testTheDerivedSourceRoundTripsItsIdentity() {
        let id = DerivedSeriesID(.biologicalAge, "combined")
        let factor = ScoreFactor.producedFigure(id, name: "Biological age (combined)",
                                                detail: "52 — the weighted mean above")
        XCTAssertEqual(factor.derivedSeries, id)
        XCTAssertNil(factor.metric, "a derived factor has no metric behind it")
        XCTAssertEqual(factor.weight, 0, "a produced figure never takes a share")
        XCTAssertEqual(factor.derivedSeries?.producedBy, .biologicalAge)

        let weighted = ScoreFactor.derived(DerivedSeriesID(.substanceImpact, "recentLoad"),
                                           name: "Recent substance load", weight: 0.4,
                                           detail: "heavy — 9 logs in 14 days")
        XCTAssertEqual(weighted.derivedSeries?.rawValue, "substanceImpact.recentLoad")
        XCTAssertEqual(weighted.weight, 0.4)

        // A metric factor and a grounding factor still answer nil, so a caller
        // switching on this cannot silently treat one as the other.
        XCTAssertNil(ScoreFactor(source: .metric(.heartRate), name: "", weight: 1,
                                 detail: "", isModifiable: true).derivedSeries)
        XCTAssertNil(ScoreFactor(source: .grounding(.dateOfBirth), name: "", weight: 1,
                                 detail: "", isModifiable: true).derivedSeries)
    }

    // MARK: - Work impact: the card is finally about work

    /// **The reader's complaint, as a test.** *"The work impact card... 'What's
    /// changed' and 'what goes into this' will only still just show Resting
    /// Heart Rate, HRV and sleep duration.... the entire point of this card is to
    /// take into consideration work impact, where is that on these sections?"*
    ///
    /// Under full coverage the card must now declare the calendar quantities
    /// themselves — as factors, so they render on both sections, and as series,
    /// so they can be trended.
    func testWorkImpactDeclaresTheCalendarItIsAbout() {
        let fixture = WorkFixture()
        let result = WorkImpactInsight(events: fixture.events, judgements: [])
            .evaluate(samples: fixture.samples, profile: UserHealthProfile(),
                      now: fixture.now)

        XCTAssertNotNil(result.score, "the fixture did not reach a scored state")

        let derivedNames = (result.weightedFactors + result.unweightedFactors)
            .filter { $0.derivedSeries != nil }
            .map(\.name)
        XCTAssertFalse(derivedNames.isEmpty,
                       "the calendar is still declared nowhere the reader looks")
        XCTAssertTrue(derivedNames.contains { $0.lowercased().contains("gap") },
                      "the contrast this whole comparison rests on is unnamed: \(derivedNames)")
        XCTAssertTrue(derivedNames.contains { $0.lowercased().contains("working days") },
                      "nothing says how many days the finding rests on: \(derivedNames)")

        let keys = Set(result.derivedOutputs.map(\.key))
        for expected in [WorkImpactModel.busyHoursKey, WorkImpactModel.quietHoursKey,
                         WorkImpactModel.loadGapKey, WorkImpactModel.daysComparedKey,
                         WorkImpactModel.pooledKey] {
            XCTAssertTrue(keys.contains(expected),
                          "\(expected) is not trendable: \(keys.sorted())")
        }

        // The gap is the difference of the two halves, not an independent
        // number — a card reporting three figures that disagree with each other
        // would be worse than one reporting none.
        let by = Dictionary(uniqueKeysWithValues: result.derivedOutputs.map { ($0.key, $0.value) })
        XCTAssertEqual(by[WorkImpactModel.loadGapKey] ?? 0,
                       (by[WorkImpactModel.busyHoursKey] ?? 0)
                           - (by[WorkImpactModel.quietHoursKey] ?? 0),
                       accuracy: 1e-9)
    }

    /// ⚠️ **The calendar quantities carry a real share, and the zeros are gone.**
    ///
    /// This test asserted the opposite until 2026-08-06, and the reasoning was
    /// sound about the card as it then stood: the number was a curve over how
    /// much the *body* differed between two groups of days, and the load gap
    /// decided which day landed in which group without entering that arithmetic
    /// anywhere. A share would have been a proportion nobody computed.
    ///
    /// The reader overruled the card rather than the reasoning — *"I want all
    /// inputs to carry at least some weight, thats the entire point. If i have
    /// had 10 meetings in a day, how would that not leave me impacted and
    /// drained?"* — so the arithmetic changed, `work-impact-v2` marks every
    /// stored score as non-comparable, and the calendar now divides the number
    /// with the body. Backlog D41.
    func testTheCalendarQuantitiesCarryRealShares() {
        let fixture = WorkFixture()
        let result = WorkImpactInsight(events: fixture.events, judgements: [])
            .evaluate(samples: fixture.samples, profile: UserHealthProfile(),
                      now: fixture.now)

        let calendarRows = result.weightedFactors.filter { $0.derivedSeries != nil }
        XCTAssertFalse(calendarRows.isEmpty,
                       "the calendar is back to charted-not-scored: \(result.weightedFactors.map(\.name))")
        for row in calendarRows {
            XCTAssertGreaterThan(row.weight, 0, "\(row.name)")
        }
        // Nothing calendar-shaped is left in the unweighted group either — that
        // is the state the reader objected to.
        XCTAssertTrue(result.unweightedFactors.allSatisfy { $0.derivedSeries == nil },
                      "\(result.unweightedFactors.map(\.name)) still carry no share")
        // And the shares still account for the whole number.
        XCTAssertEqual(result.weightedFactors.reduce(0) { $0 + $1.weight }, 1,
                       accuracy: 1e-9)
        // Both halves are genuinely present: the body has not been squeezed out
        // by the change that gave the calendar its share.
        XCTAssertFalse(result.weightedFactors.filter { $0.metric != nil }.isEmpty)
    }

    // MARK: - Mental health: the pass-throughs stay out

    /// The reader supplied the exception in the same breath as the rule —
    /// *"unless that was just directly derived from one other data point"* — and
    /// every one of this card's four channels is exactly that: one metric's
    /// fortnight against its own season, rescaled. Minting them as series would
    /// put the reader's step count in the Data tab twice under two names.
    ///
    /// What pools — the weighted departure across channels, and how many of them
    /// moved — is kept.
    func testMentalHealthKeepsWhatPoolsAndRefusesThePassThroughs() {
        let samples = ContributorsFixture.fullCoverage(now: now)
        let result = MentalHealthInsight().evaluate(
            samples: samples, profile: ContributorsFixture.profile(now: now), now: now)
        XCTAssertNotNil(result.score, "the fixture did not reach a scored state")

        let keys = Set(result.derivedOutputs.map(\.key))
        XCTAssertTrue(keys.contains(MentalHealthInsight.pooledKey), "\(keys)")
        XCTAssertTrue(keys.contains(MentalHealthInsight.movedKey), "\(keys)")

        // No output may be named after a channel or its metric.
        let names = result.derivedOutputs.map { "\($0.key) \($0.displayName)".lowercased() }
        for channel in MentalHealthModel.channels {
            for name in names {
                XCTAssertFalse(name.contains(channel.metric.rawValue.lowercased()),
                               "\(channel.label) got a series of its own — it is one "
                                   + "metric rescaled, and its departure is already "
                                   + "harvested from MetricContribution.z")
                XCTAssertFalse(name.contains(channel.label.lowercased()),
                               "\(channel.label) got a series of its own")
            }
        }

        // ...and the refusal costs nothing, because the free tier already
        // carries each channel's departure. This is the half that makes saying
        // no affordable, so it is pinned rather than assumed.
        let harvested = DerivedHarvest.series(from: result).map { $0.0 }
        let departures = harvested.filter { $0.kind == .componentDeparture }
        XCTAssertFalse(departures.isEmpty,
                       "the channels lost their departures as well as their names")
    }

    // MARK: - Biological age: the combined figure has a row and a series

    func testBiologicalAgeCombinedIsARowAndASeries() {
        let samples = ContributorsFixture.fullCoverage(now: now)
        let result = BiologicalAgeInsight().evaluate(
            samples: samples, profile: ContributorsFixture.profile(now: now), now: now)
        guard result.score != nil else {
            // The card needs three markers and the fixture may not carry them on
            // every future revision. Skipping loudly beats asserting on nothing.
            return XCTAssertTrue(result.derivedOutputs.isEmpty,
                                 "an unscored card should declare nothing")
        }
        let keys = Set(result.derivedOutputs.map(\.key))
        XCTAssertTrue(keys.contains(BiologicalAgeInsight.combinedKey), "\(keys)")

        let combined = result.unweightedFactors.first {
            $0.derivedSeries == DerivedSeriesID(.biologicalAge,
                                                BiologicalAgeInsight.combinedKey)
        }
        XCTAssertNotNil(combined,
                        "the combined age still appears on no section of its own card")
        XCTAssertEqual(combined?.weight, 0,
                       "the markers already divide 100% of this card; a share here "
                           + "would count the same five readings twice")
    }

    // MARK: - Fixture

    /// Eight weeks of working days at three levels of load, with the body
    /// running a little worse on the mornings after the busiest ones.
    ///
    /// ⚠️ **Three levels, not two, and the reason is the model's own split.**
    /// `WorkImpactModel` divides at the reader's median with `> median` on the
    /// heavy side, so a fixture with exactly two levels puts the median *on* the
    /// high value and leaves the heavy half empty — the card then returns nil
    /// and every assertion below fails for a reason that has nothing to do with
    /// what is being tested.
    ///
    /// Built on `Calendar.current` deliberately: `WorkImpactInsight.evaluate`
    /// takes the default calendar, so a fixture built in UTC would put events
    /// and readings on different days for any reader east or west of it — the
    /// same class the Oura parser's calendar injection closed on 2026-08-04.
    private struct WorkFixture {
        let now = TestClock.now
        let calendar = Calendar.current
        var events: [CalendarEvent] = []
        var samples: [HealthMetricSample] = []
        /// Meetings per working day, by day offset — so the readings can be
        /// built from the same source of truth the events are.
        private var meetingsByOffset: [Int: Int] = [:]

        init() {
            var level = 0
            for offset in 1...56 {
                guard let day = calendar.date(byAdding: .day, value: -offset,
                                              to: calendar.startOfDay(for: now))
                else { continue }
                let weekday = calendar.component(.weekday, from: day)
                guard weekday != 1, weekday != 7 else { continue }

                let count = [1, 2, 3][level % 3]
                level += 1
                meetingsByOffset[offset] = count
                for slot in 0..<count {
                    let start = day.addingTimeInterval(Double(9 + slot * 3) * 3600)
                    events.append(CalendarEvent(
                        id: "w-\(offset)-\(slot)", start: start,
                        end: start.addingTimeInterval(2 * 3600),
                        isAllDay: false, timeZoneIdentifier: "Europe/London",
                        calendarName: "Work", kind: .timed,
                        title: "Project sync", location: nil, hasVideoLink: true))
                }
            }

            // Readings on every day of the window, including the mornings after
            // — the model reads the night *after* the day it is judging.
            for offset in 0...60 {
                guard let day = calendar.date(byAdding: .day, value: -offset,
                                              to: calendar.startOfDay(for: now))
                else { continue }
                // The day this reading is judging is the one before it.
                let busy = (meetingsByOffset[offset + 1] ?? 0) >= 3
                let jitter = Double(offset % 3) * 0.4
                let noon = day.addingTimeInterval(12 * 3600)
                samples.append(.init(type: .restingHeartRate,
                                     value: (busy ? 61 : 56) + jitter,
                                     start: noon, end: noon, source: .appleHealth))
                samples.append(.init(type: .heartRateVariabilityRMSSD,
                                     value: (busy ? 38 : 46) + jitter,
                                     start: noon, end: noon, source: .appleHealth))
                samples.append(.init(type: .sleepDurationHours,
                                     value: (busy ? 6.4 : 7.4) + jitter * 0.1,
                                     start: noon, end: noon, source: .appleHealth))
            }
        }
    }
}
