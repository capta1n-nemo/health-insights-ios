import Foundation

/// **A date-only field means a day, and a day is local.**
///
/// Connectors send two shapes of date: an instant (`2026-07-19T23:30:00+08:00`)
/// and a bare day (`2026-07-20`). The instant is unambiguous. The bare day is
/// not — it names a calendar day and says nothing about which zone's day — and
/// this app resolved it two different ways at once.
///
/// - `PayloadIngestor`'s and `OuraResponseParser`'s day formatters were pinned
///   to **UTC**. Every one of the 1,720 canonical Oura samples in the reader's
///   own export sits at exactly `T00:00:00Z`.
/// - `SleepOnset.night(of:)`, `ShortcutIngest`, `DataStore.recordScreenTime` and
///   every manual write use `calendar.startOfDay`, i.e. **local** midnight. The
///   reader's 135 Apple sleep samples sit at exactly `T16:00:00Z`, which is
///   00:00 at UTC+8.
///
/// **The two only agree by accident, and the accident is the sign of the
/// device's UTC offset.** `calendar.startOfDay(midnightUTC(D))` is `D` when the
/// offset is ≥ 0 and `D − 1` when it is < 0. The reader is at UTC+8, so today
/// every cross-source join lands on the same day — measured, not assumed: the
/// value-identical duplicate pairs align at lag 0 with a median absolute
/// difference of exactly zero. Fly them to London or New York and the two lanes
/// shear one day apart, silently, on the next sync.
///
/// **So this is not a sensitivity fix and must not be reported as one.** The
/// research note's "+0.79 correlation at one day's lag" is a real measurement of
/// the *export* analysed in a UTC frame; it is not what the app's own cards see
/// at UTC+8 today. What this removes is the accident, not a live misregistration.
///
/// ## Why it is keyed on the string, never on the resulting date
///
/// The tempting rule — "if the instant is exactly midnight UTC, shift it" — is
/// wrong and would corrupt real data. The reader's export holds 27 `stepCount`
/// and 82 `activeEnergyBurned` samples that genuinely land at `T00:00:00Z`,
/// straight from HealthKit as `Date`s, touching no formatter at all. Keying on
/// the **shape of the input field** is safe by construction: an instant carrying
/// a time of day never reaches this function.
///
/// ## Why components rather than a `DateFormatter`
///
/// This package's suite runs on Linux, where several Foundation formatter paths
/// are Darwin-only, and a date parser that cannot be tested is not one worth
/// having. Same rationale and same shape as `ShortcutIngest.parseDate`.
public enum DayStamp {

    /// `2026-07-20` → local midnight on that day, in `calendar`'s zone.
    ///
    /// The `startOfDay` wrap is not redundant: in a zone whose clocks jump at
    /// midnight, `date(from:)` on a bare y/m/d can land at 23:00 the previous
    /// day, and every downstream day-bucket would then disagree with the field
    /// it came from.
    public static func local(_ s: String, calendar: Calendar = .current) -> Date? {
        let bits = s.prefix(10).split(separator: "-")
        guard bits.count == 3,
              let y = Int(bits[0]), let m = Int(bits[1]), let d = Int(bits[2]),
              (1...12).contains(m), (1...31).contains(d),
              let date = calendar.date(from: DateComponents(year: y, month: m, day: d))
        else { return nil }
        return calendar.startOfDay(for: date)
    }
}
