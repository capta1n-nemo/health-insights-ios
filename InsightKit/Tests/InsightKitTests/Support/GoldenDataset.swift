import Foundation
@testable import InsightKit

/// The shapes a real phone produces, which no fixture in this repo had ever seen.
///
/// Every number in the suite was invented inline, and inline fixtures are
/// tidy — one sample per day, one source, always fresh, never a gap. That is
/// precisely the one shape in which the old Vitals Check behaved, which is why a
/// baseline built from `suffix(60)` (sixty *readings*, five hours of heart rate)
/// passed every test it had and printed a baseline heart rate of 100 on the
/// phone.
///
/// This is a *generator* rather than a recorded JSON blob, deliberately. What
/// matters for these tests is the **shape** — sampling rate, duplication across
/// delivery paths, a real silence, an abnormal night — and a generator states
/// each of those in one readable line where a 40 000-sample capture would state
/// them nowhere. It is seeded and fully deterministic, so it behaves like a
/// recording; it just says what it is.
///
/// If a genuine capture is ever wanted, this is the place it goes: same API,
/// `resources:` on the test target, and every test below keeps working.
enum GoldenDataset {

    /// A tiny deterministic generator. `SystemRandomNumberGenerator` would make
    /// every assertion below flaky, and `Math.random` is unavailable to the
    /// workflow tooling anyway.
    struct Seeded {
        private var state: UInt64
        init(seed: UInt64 = 0x5DEECE66D) { self.state = seed | 1 }

        /// xorshift64*, which is plenty for jittering a fixture.
        mutating func next() -> Double {
            state ^= state >> 12
            state ^= state << 25
            state ^= state >> 27
            return Double((state &* 2_685_821_657_736_338_717) >> 11) / Double(1 << 53)
        }

        /// Uniform in ±`spread`.
        mutating func jitter(_ spread: Double) -> Double { (next() - 0.5) * 2 * spread }
    }

    /// How long the generated history runs.
    static let days = 60

    /// Heart-rate samples per day. An Apple Watch publishes roughly this many,
    /// and it is the number that broke the original baseline: `suffix(60)` of
    /// *this* is the last five hours.
    static let heartRateSamplesPerDay = 300

    /// The day, counting back from `TestClock.now`, that a fever starts.
    static let feverDaysAgo = 3

    /// The silence: a fortnight where the ring was off the charger and nothing
    /// synced. Real histories have these and no inline fixture ever did.
    static let gapStart = 30
    static let gapEnd = 16

    private static func inGap(_ daysAgo: Int) -> Bool {
        daysAgo <= gapStart && daysAgo >= gapEnd
    }

    /// The whole set: high-frequency heart rate, a duplicated ring, a real gap
    /// and a fever night.
    static func samples() -> [HealthMetricSample] {
        heartRate() + restingHeartRate() + duplicatedHRV() + temperature() + sleep()
    }

    /// ~300 readings a day from one watch, awake hours only.
    ///
    /// The shape that made "your personal baseline" mean "the last five hours".
    static func heartRate() -> [HealthMetricSample] {
        var random = Seeded(seed: 11)
        var out: [HealthMetricSample] = []
        for daysAgo in stride(from: days - 1, through: 0, by: -1) {
            guard !inGap(daysAgo) else { continue }
            let dayStart = TestClock.utc.startOfDay(
                for: TestClock.now.addingTimeInterval(-Double(daysAgo) * 86_400))
            // A fever drags daytime heart rate up with it.
            let base = daysAgo <= feverDaysAgo ? 82.0 : 68.0
            for index in 0..<heartRateSamplesPerDay {
                // Spread across the sixteen waking hours.
                let offset = 6 * 3600 + Double(index) / Double(heartRateSamplesPerDay) * 16 * 3600
                out.append(HealthMetricSample(
                    type: .heartRate, value: base + random.jitter(14),
                    start: dayStart.addingTimeInterval(offset),
                    source: .appleHealthDevice("Apple Watch")))
            }
        }
        return out
    }

    /// One nightly figure, as a watch actually reports it.
    static func restingHeartRate() -> [HealthMetricSample] {
        var random = Seeded(seed: 23)
        return (0..<days).compactMap { daysAgo in
            guard !inGap(daysAgo) else { return nil }
            let base = daysAgo <= feverDaysAgo ? 71.0 : 55.0
            return HealthMetricSample(
                type: .restingHeartRate, value: base + random.jitter(2.5),
                start: TestClock.day(daysAgo),
                source: .appleHealthDevice("Apple Watch"))
        }
    }

    /// **The same ring, arriving twice** — directly and mirrored through Apple
    /// Health, a few minutes apart with a rounding difference.
    ///
    /// De-duplication has to collapse these to one instrument. Counting both let
    /// the gap between two delivery paths set the standard deviation, so nothing
    /// ever cleared a threshold.
    static func duplicatedHRV() -> [HealthMetricSample] {
        var random = Seeded(seed: 37)
        var out: [HealthMetricSample] = []
        for daysAgo in stride(from: days - 1, through: 0, by: -1) {
            guard !inGap(daysAgo) else { continue }
            let base = daysAgo <= feverDaysAgo ? 28.0 : 46.0
            let value = base + random.jitter(6)
            let when = TestClock.day(daysAgo)
            out.append(HealthMetricSample(type: .heartRateVariabilityRMSSD, value: value,
                                          start: when, source: .oura))
            // The mirror: minutes later, rounded to a whole millisecond.
            out.append(HealthMetricSample(type: .heartRateVariabilityRMSSD,
                                          value: value.rounded(),
                                          start: when.addingTimeInterval(420),
                                          source: .appleHealth))
        }
        return out
    }

    /// Nightly deviations from a ring, with a genuine febrile run at the end.
    static func temperature() -> [HealthMetricSample] {
        var random = Seeded(seed: 53)
        return (0..<days).compactMap { daysAgo in
            guard !inGap(daysAgo) else { return nil }
            let deviation = daysAgo <= feverDaysAgo ? 1.1 : 0.0
            return HealthMetricSample(
                type: .skinTemperatureDeviation, value: deviation + random.jitter(0.18),
                start: TestClock.day(daysAgo), source: .oura)
        }
    }

    static func sleep() -> [HealthMetricSample] {
        var random = Seeded(seed: 71)
        return (0..<days).compactMap { daysAgo in
            guard !inGap(daysAgo) else { return nil }
            let base = daysAgo <= feverDaysAgo ? 6.1 : 7.5
            return HealthMetricSample(
                type: .sleepDurationHours, value: base + random.jitter(0.6),
                start: TestClock.day(daysAgo), source: .oura)
        }
    }
}
