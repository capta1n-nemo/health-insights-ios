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
public enum SyntheticSeed {

    /// A day's worth of generated samples for every metric group.
    ///
    /// - Parameters:
    ///   - days: How many days back from `endingOn` to generate.
    ///   - endingOn: The most recent day. Defaults to now.
    ///   - calendar: Day boundaries. The caller's, so a seeded simulator buckets
    ///     the way the app it is feeding does.
    public static func samples(days: Int,
                               endingOn end: Date,
                               calendar: Calendar = .current) -> [HealthMetricSample] {
        guard days > 0 else { return [] }
        var out: [HealthMetricSample] = []
        let today = calendar.startOfDay(for: end)

        for offset in 0..<days {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { continue }
            // Midday, so a sample can never straddle a day boundary — the same
            // reason `TestClock.day` does it.
            let stamp = day.addingTimeInterval(12 * 3600)
            let weekday = calendar.component(.weekday, from: day)
            let isWeekend = weekday == 1 || weekday == 7
            // 0 at the oldest day, 1 at the newest, so a trend runs forwards.
            let t = Double(days - 1 - offset) / Double(max(days - 1, 1))
            var r = Noise(seed: offset)

            func add(_ type: MetricType, _ value: Double) {
                // Respect the app's own plausibility guard rather than working
                // around it: a fixture that could not have arrived through the
                // real ingest path is a fixture that proves nothing about it.
                if let range = type.plausibleRange, !range.contains(value) { return }
                if type.requiresPositiveValue && value <= 0 { return }
                out.append(HealthMetricSample(type: type, value: value,
                                              start: stamp, source: .shortcuts))
            }

            // Cardiovascular. Resting heart rate eases down, HRV rises — the
            // relationship the cards actually read, so a seeded profile does not
            // present the models with a pattern no body produces.
            add(.restingHeartRate, 58 - 3 * t + r.next(spread: 6))
            add(.heartRateVariabilityRMSSD, 42 + 8 * t + r.next(spread: 14))
            add(.respiratoryRate, 14.2 + r.next(spread: 1.6))
            add(.oxygenSaturation, 97 + r.next(spread: 2))
            add(.vo2Max, 41 + 3 * t + r.next(spread: 1.2))

            // Sleep. Longer at weekends, which is what makes the consistency
            // terms have anything to say.
            add(.sleepDurationHours, (isWeekend ? 8.1 : 7.1) + r.next(spread: 1.8))
            add(.sleepEfficiency, 88 + r.next(spread: 10))
            add(.sleepDeepMinutes, 72 + r.next(spread: 36))
            add(.sleepRemMinutes, 96 + r.next(spread: 40))
            add(.sleepLatencyMinutes, 17 + r.next(spread: 18))

            // Activity.
            add(.stepCount, (isWeekend ? 6200 : 9400) + r.next(spread: 4200))
            add(.activeEnergyBurned, (isWeekend ? 380 : 620) + r.next(spread: 300))
            add(.exerciseMinutes, (isWeekend ? 18 : 34) + r.next(spread: 26))

            // Body. ~0.35 kg/week down under a ±0.55 kg water swing — the wobble
            // is the point, since smoothing and the change-confidence ramp are
            // what it exercises.
            add(.bodyMass, 92.0 - 0.05 * Double(days) * t + r.next(spread: 1.1))
            add(.bodyFatPercentage, 26.5 - 3.2 * t + r.next(spread: 1.0))

            // Intake, a little under maintenance.
            add(.dietaryEnergy, 2050 + r.next(spread: 700))
            add(.dietaryProtein, 145 + r.next(spread: 50))
            add(.dietaryCarbohydrates, 190 + r.next(spread: 90))
            add(.dietaryFat, 76 + r.next(spread: 30))
            add(.dietarySugar, 48 + r.next(spread: 36))
            add(.dietaryFibre, 27 + r.next(spread: 14))
            add(.dietaryWater, 2.4 + r.next(spread: 1.2))

            // A cuff reading is something the reader does, not something that
            // happens — twice a week, so the "0 of 5 in the last 30 days"
            // gating has a realistic count to work with.
            if weekday == 2 || weekday == 5 {
                add(.bloodPressureSystolic, 128 - 5 * t + r.next(spread: 10))
                add(.bloodPressureDiastolic, 82 - 3 * t + r.next(spread: 8))
            }
        }
        return out
    }

    /// A tiny deterministic generator.
    ///
    /// Not `SystemRandomNumberGenerator`, and not `Double.random`: the fixture
    /// has to be reproducible, so a screenshot can be compared against one taken
    /// a week later and the difference blamed on the code. A linear congruential
    /// step is plenty — this is dressing a chart, not modelling anything.
    private struct Noise {
        private var state: UInt64

        init(seed: Int) {
            // Offset so day 0 is not a degenerate seed.
            state = UInt64(truncatingIfNeeded: seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407)
        }

        /// The next value in `-spread/2 ... +spread/2`.
        mutating func next(spread: Double) -> Double {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            let unit = Double((state >> 33) & 0x7FFF_FFFF) / Double(0x7FFF_FFFF)
            return (unit - 0.5) * spread
        }
    }
}
