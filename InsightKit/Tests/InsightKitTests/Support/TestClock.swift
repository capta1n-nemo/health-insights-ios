import Foundation
@testable import InsightKit

/// The one anchor and calendar the backward-looking fixtures share.
///
/// Twenty-six test files built their own, and four `day()` helpers were
/// character-identical. This is the *narrow* consolidation: only the files that
/// already anchor at `1_700_000_000` and look backward from a fixed `now`.
///
/// The obvious version — one `Clock` for the whole target — was audited and
/// rejected, and the reasons are worth keeping because they will look like
/// oversights otherwise:
///
/// - `CardioTrajectoryTests` and `NewInsightsTests` model a *forward* study
///   timeline with a movable `now` (`day(9)`, `day(60)`, `afterAYear`). A
///   backward-only helper renders "after a year" as `day(-364)`, which
///   reintroduces the exact sign footgun it claims to remove.
/// - `SharedBaselineTests` uses `Calendar.current` on purpose: it never passes a
///   calendar, and `VitalReader` defaults to `.current`, so fixture and bucketing
///   calendar are coupled by construction. Moving it to UTC while production
///   reads `.current` would *decouple* them.
/// - `PresentationTests` needs a fractional `daysAgo: 29.9` to probe a boundary,
///   which an `Int` helper cannot express — hence the `Double` overload here.
///
/// Named `TestClock`, not `Clock`: the latter would shadow the stdlib protocol
/// module-wide.
enum TestClock {
    /// 2023-11-14T22:13:20Z. Arbitrary, fixed, and shared.
    static let now = Date(timeIntervalSince1970: 1_700_000_000)

    /// UTC, because almost everything here buckets by calendar day and a machine
    /// in another zone — or on a DST boundary — would bucket differently.
    static let utc: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    /// Midday, `n` days before `now`, so a reading can never straddle midnight.
    static func day(_ n: Int) -> Date { day(Double(n)) }

    /// The fractional variant, for probing a boundary that falls inside a day.
    static func day(_ n: Double) -> Date {
        utc.startOfDay(for: now.addingTimeInterval(-n * 86_400))
            .addingTimeInterval(12 * 3600)
    }

    /// An exact offset from `now`, with no day-snapping — for the fixtures that
    /// care about hours rather than calendar days.
    static func hours(_ n: Double) -> Date { now.addingTimeInterval(-n * 3600) }
}

extension OuraResponseParser {

    /// `parseSleep` with the calendar pinned to UTC.
    ///
    /// **Every Oura expectation in this suite is a UTC answer**, because until
    /// 2026-08-04 the suite had only ever run in CI's UTC container and the
    /// parser read `Calendar.current` with no way to inject one. On the user's
    /// UTC+8 Mac three tests failed in two directions:
    /// `SleepOnset.hoursFromMidnight` keeps bedtimes within ±6 h of *local*
    /// midnight, so a fixture's `23:00+00:00` reads as 07:00 and is thrown away,
    /// while `23:10+10:00` — discarded in UTC — becomes a valid bedtime.
    ///
    /// Pinning is the same discipline `TestClock.utc` already applies to dates,
    /// and for the reason stated there: a machine in another zone buckets
    /// differently. Use this rather than `parseSleep` in any test that asserts
    /// on nights, bedtimes or nap filtering.
    static func parseSleepUTC(_ data: Data) throws -> [HealthMetricSample] {
        try parseSleep(data, calendar: TestClock.utc)
    }
}

extension WhoopResponseParser {

    /// The Whoop twin, added 2026-08-07 with the parser's calendar overload.
    ///
    /// Whoop's sleep parser feeds `SleepOnset.samples(fromSegmentStarts:)` and
    /// so has exactly the local-midnight dependence the Oura note above
    /// describes: a `23:10Z` fixture is a valid bedtime in UTC and, at UTC+10,
    /// a 09:10 reading thrown away as a nap. Until this existed the Whoop
    /// onset output was untested *and untestable deterministically* — which is
    /// the reason the audit called it out, not the parser being wrong.
    static func parseSleepUTC(_ data: Data) throws -> [HealthMetricSample] {
        try parseSleep(data, calendar: TestClock.utc)
    }
}
