import XCTest
@testable import InsightKit

/// **The thin-evidence discount counted readings, so a sub-daily metric evaded
/// it entirely.**
///
/// `MetricEffect.affectedNights` and `.baselineNights` are named for nights and
/// held raw sample counts until 2026-08-05. Heart rate carries tens of thousands
/// of readings in the 90-day comparison window, so `standardErrorInSDs` —
/// `√(1/n₁ + 1/n₂)` — came out near 0.01 SD, and `reliableEffectSize` subtracted
/// essentially nothing. A difference built from a handful of exposure occasions
/// was scored as though it rested on thousands of independent observations.
///
/// They are not independent. Readings minutes apart share whatever the person
/// was doing, and the discount exists precisely because "a handful of readings
/// taken close together may share a confound the clean pool doesn't".
final class SubstanceEvidenceCountTests: XCTestCase {

    private let utc = TestClock.utc

    private func sample(_ metric: MetricType, _ value: Double, at date: Date) -> HealthMetricSample {
        HealthMetricSample(type: metric, value: value, start: date, end: date, source: .appleHealth)
    }

    /// Two days of use and three clean days, sampled every few minutes. The old
    /// counting reported hundreds of "nights" on each side; the fix reports the
    /// days that are actually there.
    func testDenseSamplingCannotManufactureEvidence() throws {
        let now = TestClock.now
        var samples: [HealthMetricSample] = []
        var events: [SubstanceEvent] = []

        // Two exposure days, 120 readings each, an hour after the event.
        for dayOffset in [10, 12] {
            let day = utc.startOfDay(for: now.addingTimeInterval(-Double(dayOffset) * 86_400))
            events.append(SubstanceEvent(substance: .stimulant, timestamp: day))
            for i in 0..<120 {
                samples.append(sample(.heartRate, 80, at: day.addingTimeInterval(Double(i) * 300 + 3600)))
            }
        }
        // Three clean days, same density, well outside any after-window.
        for dayOffset in [30, 32, 34] {
            let day = utc.startOfDay(for: now.addingTimeInterval(-Double(dayOffset) * 86_400))
            for i in 0..<120 {
                samples.append(sample(.heartRate, 60, at: day.addingTimeInterval(Double(i) * 300 + 3600)))
            }
        }

        let effect = try XCTUnwrap(SubstanceResponseAnalyzer.effect(
            for: .heartRate, upIsAdverse: true, events: events,
            samples: samples, now: now, calendar: utc))

        XCTAssertEqual(effect.affectedNights, 2,
                       "240 readings across two days were counted as 240 occasions")
        XCTAssertEqual(effect.baselineNights, 3,
                       "360 readings across three days were counted as 360 occasions")
        XCTAssertEqual(effect.evidencePairs, 2,
                       "the thinner side is two days of use, and the discount must see that")

        // √(1/2 + 1/3) ≈ 0.913 — a real discount. Under sample counting it was
        // √(1/240 + 1/360) ≈ 0.068, which subtracts nothing from anything.
        XCTAssertEqual(effect.standardErrorInSDs, 0.9129, accuracy: 0.001)
        XCTAssertGreaterThan(effect.standardErrorInSDs, 0.5,
                             "the standard error is still small enough to wave a two-day finding through")
    }

    /// The means are deliberately **unchanged** by the fix: an 18-hour window
    /// genuinely covers part of a day, so the effect is still estimated from
    /// every reading at full resolution. Only the uncertainty was recounted.
    func testTheEffectEstimateItselfIsUnchanged() throws {
        let now = TestClock.now
        var samples: [HealthMetricSample] = []
        var events: [SubstanceEvent] = []
        for dayOffset in [10, 12] {
            let day = utc.startOfDay(for: now.addingTimeInterval(-Double(dayOffset) * 86_400))
            events.append(SubstanceEvent(substance: .stimulant, timestamp: day))
            for i in 0..<10 {
                samples.append(sample(.restingHeartRate, 70, at: day.addingTimeInterval(Double(i) * 600 + 3600)))
            }
        }
        for dayOffset in [30, 32, 34] {
            let day = utc.startOfDay(for: now.addingTimeInterval(-Double(dayOffset) * 86_400))
            for i in 0..<10 {
                samples.append(sample(.restingHeartRate, 60, at: day.addingTimeInterval(Double(i) * 600 + 3600)))
            }
        }
        let effect = try XCTUnwrap(SubstanceResponseAnalyzer.effect(
            for: .restingHeartRate, upIsAdverse: true, events: events,
            samples: samples, now: now, calendar: utc))

        XCTAssertEqual(effect.afterUse, 70, accuracy: 0.001)
        XCTAssertEqual(effect.baseline, 60, accuracy: 0.001)
        XCTAssertEqual(effect.deltaAbsolute, 10, accuracy: 0.001,
                       "the estimate moved — only the evidence count was supposed to")
    }

    /// **The day boundary is a parameter now, and it has to be**: the reviewers
    /// measured this reader's whole finding set flipping between timezones —
    /// three metrics confirm at UTC+8, one at UTC, none at UTC−5. A calendar
    /// read ambiently from the device means CI and the phone can disagree about
    /// what the card says.
    func testTheDayBoundaryIsAParameterNotAnAmbientRead() throws {
        let now = TestClock.now
        // One event, and readings that straddle midnight UTC.
        let anchor = utc.startOfDay(for: now.addingTimeInterval(-10 * 86_400))
        let events = [SubstanceEvent(substance: .stimulant, timestamp: anchor.addingTimeInterval(-3600))]
        var samples: [HealthMetricSample] = []
        for i in 0..<6 {
            samples.append(sample(.heartRate, 80, at: anchor.addingTimeInterval(Double(i) * 3600 - 7200)))
        }
        for dayOffset in [30, 32, 34] {
            let day = utc.startOfDay(for: now.addingTimeInterval(-Double(dayOffset) * 86_400))
            for i in 0..<5 {
                samples.append(sample(.heartRate, 60, at: day.addingTimeInterval(Double(i) * 3600)))
            }
        }

        var plus8 = Calendar(identifier: .gregorian)
        plus8.timeZone = TimeZone(secondsFromGMT: 8 * 3600)!

        let atUTC = try XCTUnwrap(SubstanceResponseAnalyzer.effect(
            for: .heartRate, upIsAdverse: true, events: events,
            samples: samples, now: now, calendar: utc))
        let atPlus8 = try XCTUnwrap(SubstanceResponseAnalyzer.effect(
            for: .heartRate, upIsAdverse: true, events: events,
            samples: samples, now: now, calendar: plus8))

        // The readings straddle midnight UTC, so UTC sees two exposure days and
        // UTC+8 sees one. That the two disagree is the point — it is why the
        // calendar must be passed rather than read from the device.
        XCTAssertNotEqual(atUTC.affectedNights, atPlus8.affectedNights,
                          "this fixture no longer straddles a day boundary, so it proves nothing about the parameter")
    }
}
