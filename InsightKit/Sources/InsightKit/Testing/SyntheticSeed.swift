import Foundation

/// Physiologically plausible **synthetic** health data, for filling a simulator
/// so the charts can be looked at.
///
/// ## Why this exists
///
/// The Health app does not ship on the iOS Simulator, so HealthKit returns
/// nothing there and every card renders its empty state. That was the documented
/// ceiling on what a Mac session could verify: layout, navigation, tab placement
/// and empty states were answerable, and **a chart, a reference band, a scrub
/// read-out and the substance shading were phone-only**. Charts are where this
/// project's defects have actually lived — a gradient resolving against the
/// mark's own box, an `ImagePaint` tiling inside an `AreaMark`, a `Chart3DContent`
/// overload — and none of them could be falsified anywhere but the reader's
/// phone. Closing that was the top item on the efficiency roadmap.
///
/// ## What this is not
///
/// **It is not the reader's data and it does not replace the phone.** Every
/// series here comes out of a seeded generator below. It answers *"does this
/// chart draw correctly"*; it can never answer *"what is happening to this
/// person"*, and no finding about the user may be drawn from a screenshot of it.
/// Anything that depends on real provenance — HealthKit's own bucketing, a
/// provider's quirks, the substance log's timing against real doses — still
/// needs the device.
///
/// ## Why it is shaped rather than random
///
/// A flat series makes every chart a straight line and proves nothing about how
/// one draws. So: steps follow a weekday/weekend rhythm, weight declines slowly
/// under a water swing big enough to exercise the smoothing, HRV moves opposite
/// to resting heart rate, and blood pressure appears twice a week because a cuff
/// reading is an event the reader performs rather than something that happens
/// daily. Intake sits a little under maintenance so the metabolism
/// back-calculation has a real deficit to find instead of noise around zero.
///
/// Deterministic on purpose: the same `days` and `seed` give the same series, so
/// a screenshot taken today can be compared against one taken next week and any
/// difference is the code rather than the fixture.
///
/// ## Exhaustive since 2026-08-07
///
/// The shapes above no longer live in this file's `for` loop. They live in
/// `MetricType.syntheticSeedPlan`, an **exhaustive switch**, so a new metric
/// does not compile until it has either a series or a written reason for having
/// none. `SyntheticSeedPlan.swift` says why that rule was needed; the short
/// version is that this generator had drifted to covering 25 of 77 metrics and
/// nothing could tell anyone which 52 were missing. The card-level equivalent is
/// `InsightID.syntheticSeedExpectation`, and the profile's is
/// `SyntheticSeed.profileFacts`.
public enum SyntheticSeed {

    /// A day's worth of generated samples for every metric group.
    ///
    /// - Parameters:
    ///   - days: How many days back from `endingOn` to generate.
    ///   - endingOn: The most recent day. Defaults to now.
    ///   - cycleDays: A cycle log, when one is being seeded alongside. Supplying
    ///     it makes the four phase-structured channels *biphasic* — see
    ///     `lutealOffsets`. Empty by default, which is every caller that is not
    ///     filling the cycle tab.
    ///   - calendar: Day boundaries. The caller's, so a seeded simulator buckets
    ///     the way the app it is feeding does.
    public static func samples(days: Int,
                               endingOn end: Date,
                               cycleDays: [CycleDay] = [],
                               calendar: Calendar = .current) -> [HealthMetricSample] {
        guard days > 0 else { return [] }
        var out: [HealthMetricSample] = []
        let today = calendar.startOfDay(for: end)
        let summary = cycleDays.isEmpty
            ? nil : CycleModel.summarise(days: cycleDays, now: end, calendar: calendar)

        for offset in 0..<days {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { continue }
            // Midday, so a sample can never straddle a day boundary — the same
            // reason `TestClock.day` does it.
            let stamp = day.addingTimeInterval(12 * 3600)
            let weekday = calendar.component(.weekday, from: day)
            let isWeekend = weekday == 1 || weekday == 7
            // 0 at the oldest day, 1 at the newest, so a trend runs forwards.
            let t = Double(days - 1 - offset) / Double(max(days - 1, 1))

            // Nought outside the luteal phase, and outside a seeded cycle log.
            let isLuteal = summary.map {
                CyclePhaseModel.phase(on: day, summary: $0, now: end,
                                      calendar: calendar)?.phase == .luteal
            } ?? false

            func add(_ type: MetricType, _ value: Double) {
                // Respect the app's own plausibility guard rather than working
                // around it: a fixture that could not have arrived through the
                // real ingest path is a fixture that proves nothing about it.
                let shifted = value + (isLuteal ? (lutealOffsets[type] ?? 0) : 0)
                if let range = type.plausibleRange, !range.contains(shifted) { return }
                if type.requiresPositiveValue && shifted <= 0 { return }
                out.append(HealthMetricSample(type: type, value: shifted,
                                              start: stamp, source: .shortcuts))
            }

            // **Exhaustive, by construction.** Every metric is asked what it
            // wants; a new one cannot be forgotten because `syntheticSeedPlan`
            // will not compile without it. `allCases` order is the declaration
            // order of `MetricType`, so the output ordering is stable.
            for type in MetricType.allCases {
                // Each metric draws from its own stream, so adding one does not
                // shift the series of any other — see `syntheticSeedSalt`.
                var r = Noise(seed: offset, salt: type.syntheticSeedSalt)
                switch type.syntheticSeedPlan {
                case .notSeeded:
                    continue
                case .once(let value):
                    // Newest day only: a static attribute has no trend, and
                    // charting one would invent a story.
                    if offset == 0 { add(type, value) }
                case .daily(let recipe):
                    add(type, recipe.value(t: t, days: days, isWeekend: isWeekend, noise: &r))
                case .onWeekdays(let days_, let recipe):
                    guard days_.contains(weekday) else { continue }
                    add(type, recipe.value(t: t, days: days, isWeekend: isWeekend, noise: &r))
                }
            }
        }
        return out
    }

    /// What the luteal phase does to the four channels that carry it, when a
    /// cycle log is being seeded alongside the vitals.
    ///
    /// ⚠️ **Deliberately not equal to `PhaseAwareBaseline.literaturePriors`.**
    /// The prior for resting heart rate is +2.0 bpm; this fixture's reader runs
    /// +3.0. If the two matched, a screenshot of the shifts card could not
    /// distinguish "measured from this reader" from "fell back to the textbook",
    /// which is the exact confusion the card exists to prevent.
    ///
    /// Directions and rough magnitudes are the real physiology — progesterone
    /// raises heart rate, breathing rate and temperature and lowers vagal tone.
    /// The sources are on `PhaseAwareBaseline.literaturePriors`.
    static let lutealOffsets: [MetricType: Double] = [
        .restingHeartRate: 3.0,
        .heartRateVariabilityRMSSD: -7.0,
        .respiratoryRate: 0.4,
        .skinTemperatureDeviation: 0.35
    ]

    /// The conventional normal range for a whole cycle, in days. Anything the
    /// generator would produce outside this is dropped rather than clamped —
    /// the same discipline `add(_:_:)` applies with `plausibleRange`, for the
    /// same reason: a fixture that could not have arrived through the real path
    /// proves nothing about it.
    public static let plausibleCycleLengths = 21...35
    /// And for the bleeding days inside one.
    public static let plausiblePeriodLengths = 2...8

    /// Logged bleeding days for a few plausible cycles, for filling a simulator
    /// so the cycle tab can be looked at.
    ///
    /// **The tab is otherwise unverifiable on a Mac.** HealthKit returns nothing
    /// on the Simulator, `MenstrualFlow` is zero rows even on the reader's own
    /// export, and the phase model refuses below three cycles by design — so
    /// every screenshot of the fifth tab was of its empty state, which is
    /// exactly the blind spot that shipped two invisible cards on 2026-08-03.
    ///
    /// ⚠️ **Generated, and about nobody.** `docs/backlog.md` §A3 is explicit
    /// that every zero-row figure in these docs is about the *reader's* export
    /// and says nothing about the person this tab is for. This says less than
    /// that: it is a shape, seeded from an integer.
    ///
    /// Shaped rather than uniform: the lengths walk around 28 by a couple of
    /// days so `CycleSummary` has a real spread to report and the phase model
    /// has a real ± to derive — a metronome fixture would exercise neither, and
    /// the floor-at-one-day rule would be the only thing keeping the interval
    /// off zero.
    ///
    /// - Parameters:
    ///   - cycles: How many periods to lay down, most recent first.
    ///   - mostRecentPeriodStart: Day 1 of the cycle currently running.
    public static func cycleDays(cycles: Int, mostRecentPeriodStart: Date,
                                 calendar: Calendar = .current) -> [CycleDay] {
        guard cycles > 0 else { return [] }
        var out: [CycleDay] = []
        var start = calendar.startOfDay(for: mostRecentPeriodStart)

        for index in 0..<cycles {
            // Deterministic, and deliberately not symmetric about 28: a fixture
            // whose spread happens to be even would hide a rounding bug in the
            // half-the-spread arithmetic the ± is built from.
            let length = 28 + [0, 3, -2, 1, -3, 2][index % 6]
            let period = 5 + [0, -1, 1, 0, 1, -1][index % 6]
            guard plausibleCycleLengths.contains(length),
                  plausiblePeriodLengths.contains(period),
                  // A period must fit inside its cycle with room for the rest of
                  // it, and it must not run into the next one — which is what
                  // `CycleModel.maximumGapWithinAPeriod` would silently merge.
                  period + CycleModel.maximumGapWithinAPeriod < length
            else { continue }

            for offset in 0..<period {
                guard let day = calendar.date(byAdding: .day, value: offset, to: start)
                else { continue }
                out.append(CycleDay(day: day, flow: flow(onDay: offset, of: period)))
            }
            guard let previous = calendar.date(byAdding: .day, value: -length, to: start)
            else { break }
            start = previous
        }
        return out.sorted { $0.day < $1.day }
    }

    /// **The one seeded cycle log, named once.**
    ///
    /// Both the seed button and "clear seeded data" have to agree on exactly
    /// which days were written — cycle days carry no `MetricSource`, so the
    /// clear path cannot find them by provenance and has to regenerate the same
    /// list. Two call sites holding the same two magic numbers is how a clear
    /// silently stops clearing.
    ///
    /// Six cycles, with the running one on **day 9**: past the period, before
    /// ovulation. That is the one position showing every state of the tab at
    /// once — a phase that is modelled rather than logged, a fertile window
    /// still ahead on the calendar, and completed cycles in the history.
    public static let seededCycleCount = 6
    public static let seededCurrentCycleDay = 9

    public static func seededCycleDays(endingOn end: Date = Date(),
                                       calendar: Calendar = .current) -> [CycleDay] {
        let start = calendar.date(byAdding: .day, value: -(seededCurrentCycleDay - 1),
                                  to: calendar.startOfDay(for: end)) ?? end
        return cycleDays(cycles: seededCycleCount, mostRecentPeriodStart: start,
                         calendar: calendar)
    }

    /// Heavier at the front, tapering off — the shape a period actually has, so
    /// the calendar's four-strength opacity ramp has all four strengths in it.
    private static func flow(onDay offset: Int, of length: Int) -> MenstrualFlowLevel {
        switch offset {
        case 0: return .medium
        case 1: return .heavy
        case length - 1: return .spotting
        default: return .light
        }
    }

    /// A tiny deterministic generator.
    ///
    /// Not `SystemRandomNumberGenerator`, and not `Double.random`: the fixture
    /// has to be reproducible, so a screenshot can be compared against one taken
    /// a week later and the difference blamed on the code. A linear congruential
    /// step is plenty — this is dressing a chart, not modelling anything.
    struct Noise {
        private var state: UInt64

        /// - Parameter salt: A per-metric constant, so each metric draws from
        ///   its own stream and adding one changes nothing that already existed.
        ///   See `MetricType.syntheticSeedSalt`.
        init(seed: Int, salt: UInt64 = 0) {
            // Offset so day 0 is not a degenerate seed.
            state = UInt64(truncatingIfNeeded: seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407)
            state ^= salt
            // One step before anything is drawn, so two nearby salts do not
            // produce two nearby first values.
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        }

        /// The next value in `-spread/2 ... +spread/2`. A `spread` of nought
        /// returns nought and still advances the stream.
        mutating func next(spread: Double) -> Double {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            let unit = Double((state >> 33) & 0x7FFF_FFFF) / Double(0x7FFF_FFFF)
            return (unit - 0.5) * spread
        }
    }
}
