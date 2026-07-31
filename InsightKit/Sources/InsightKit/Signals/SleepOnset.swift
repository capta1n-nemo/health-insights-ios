import Foundation

/// Turning "the moment sleep started" into a number that can be averaged.
///
/// The roadmap logged circadian consistency as **blocked on a missing signal**,
/// on the reading that no provider gives us a bedtime. That was true of what the
/// app *ingested* and not of what the providers *serve*: HealthKit's sleep
/// analysis samples carry a real `startDate` per segment, and Oura's sleep
/// records carry `bedtime_start` — which `OuraResponseParser` was already
/// decoding, and using only as a fallback for the record's date. Both were being
/// collapsed to hours-per-calendar-day on the way in, and the timestamp thrown
/// away. The signal was there the whole time.
///
/// ## The encoding, and why it is not a clock hour
///
/// `MetricType.sleepOnset` stores **signed hours from local midnight**: −1.5 is
/// 22:30, +0.5 is 00:30. A clock hour in [0, 24) is the obvious choice and needs
/// circular statistics — the mean of 23:30 and 00:30 is midnight, not noon — and
/// this app's entire baseline machinery is linear. Rather than make one metric
/// the exception that every consumer has to know about, the branch cut is moved
/// to midday, where no real bedtime ever falls. The arithmetic mean is then the
/// circular mean, for free, everywhere.
public enum SleepOnset {

    /// How far either side of midnight a first-sleep segment may fall and still
    /// be treated as the start of a night.
    ///
    /// Six hours, so 18:00 through 06:00. This is a filter against **naps**, not
    /// a judgement about bedtimes: a three-in-the-afternoon nap is genuinely the
    /// earliest sleep of its night by any grouping rule, and reporting 15:00 as
    /// a bedtime would poison the consistency figure with a value that isn't one.
    /// A shift worker who reliably sleeps at 09:00 gets no reading rather than a
    /// wrong one — the honest failure, and it is recorded on the card.
    public static let plausibleHours: Double = 6

    /// Signed hours from local midnight, or `nil` if this instant is not a
    /// plausible sleep onset.
    ///
    /// Returning `nil` rather than clamping is deliberate: a value outside the
    /// band is evidence that this segment is not a night's beginning, and
    /// squeezing it to ±6 would manufacture a bedtime out of an afternoon.
    public static func hoursFromMidnight(_ date: Date,
                                         calendar: Calendar = .current) -> Double? {
        let components = calendar.dateComponents([.hour, .minute], from: date)
        guard let hour = components.hour, let minute = components.minute else { return nil }
        let clock = Double(hour) + Double(minute) / 60
        // Evening times fold to negative; early-morning ones stay positive.
        let signed = clock >= 12 ? clock - 24 : clock
        return abs(signed) <= plausibleHours ? signed : nil
    }

    /// Which night a sleep segment belongs to.
    ///
    /// Grouping by calendar day is what the duration series already does and it
    /// is wrong for a *timestamp*: 23:30 on Monday and 01:00 on Tuesday are one
    /// night and two days. Shifting by six hours before taking the day puts the
    /// boundary at 18:00, so every segment of one night lands under one key and
    /// the key is the morning it ends on.
    ///
    /// Six is the same number as `plausibleHours` and for the same reason — the
    /// window that contains bedtimes is the window that must not be split.
    public static func night(of date: Date, calendar: Calendar = .current) -> Date {
        calendar.startOfDay(for: date.addingTimeInterval(plausibleHours * 3600))
    }

    /// One sample per night, from segments that may arrive in any order and may
    /// include naps.
    ///
    /// The earliest plausible segment of each night wins. Stamped at the night's
    /// key — the morning it ends on — so the series lines up with the way every
    /// other overnight figure in this app is dated.
    public static func samples(fromSegmentStarts starts: [Date],
                               source: MetricSource,
                               calendar: Calendar = .current) -> [HealthMetricSample] {
        var earliest: [Date: (instant: Date, value: Double)] = [:]
        for start in starts {
            guard let value = hoursFromMidnight(start, calendar: calendar) else { continue }
            let key = night(of: start, calendar: calendar)
            if let held = earliest[key], held.instant <= start { continue }
            earliest[key] = (start, value)
        }
        return earliest.keys.sorted().map { key in
            HealthMetricSample(type: .sleepOnset, value: earliest[key]!.value,
                               start: key, end: key, source: source)
        }
    }
}
