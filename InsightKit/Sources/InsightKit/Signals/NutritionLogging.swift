import Foundation

/// How completely the reader logs what they eat.
///
/// **One figure, one place, two cards.** Nutrition scores the days the reader
/// wrote down, and Metabolism gates on them — its back-calculation charges
/// every logging error to metabolism, so how much was logged decides whether
/// the number means anything at all. Two cards computing "how well do you log"
/// separately would eventually disagree, which is one number contradicting
/// itself in front of the reader.
///
/// A day counts when it carries an energy figure. Not a macro: a reader whose
/// tracker records only caffeine has logged coffee, not a diet.
public enum NutritionLogging {

    /// Days in the window carrying a logged energy figure.
    public static func loggedDays(_ samples: [HealthMetricSample], days: Int,
                                  now: Date = Date(),
                                  calendar: Calendar = .current) -> [Double] {
        VitalReader.dailyValues(.dietaryEnergy, from: samples, days: days,
                                now: now, calendar: calendar)
    }

    /// The window the reader has actually been logging in: from their first
    /// logged day inside `days` up to now, never longer than `days`.
    ///
    /// **This is what completeness should be measured against**, not the
    /// nominal window. A reader who started logging a fortnight ago and has
    /// logged every day since is logging perfectly; scoring them 14/28 would
    /// mark them down for the days before they had the app. It also keeps the
    /// metabolism card's two terms over the *same* period — intake and the
    /// weight trend have to describe one stretch of time or the arithmetic
    /// between them is meaningless.
    public static func effectiveWindow(_ samples: [HealthMetricSample], days: Int,
                                       now: Date = Date(),
                                       calendar: Calendar = .current) -> (days: Int, logged: [Double])? {
        let series = VitalReader.dailySeries(.dietaryEnergy, from: samples, days: days,
                                             now: now, calendar: calendar)
        guard let first = series.first else { return nil }
        let span = calendar.dateComponents([.day], from: calendar.startOfDay(for: first.date),
                                           to: calendar.startOfDay(for: now)).day ?? 0
        // +1 so a first log today reads as one day rather than zero.
        return (Swift.min(days, Swift.max(1, span + 1)), series.map(\.value))
    }

    /// Logged days as a share of the window.
    public static func completeness(_ samples: [HealthMetricSample], days: Int,
                                    now: Date = Date(),
                                    calendar: Calendar = .current) -> Double {
        guard days > 0 else { return 0 }
        return Double(loggedDays(samples, days: days, now: now, calendar: calendar).count)
            / Double(days)
    }

    /// Where logging stops being complete enough to describe a diet — or, on
    /// the metabolism card, to back-calculate anything from.
    ///
    /// Under-reporting is not a fringe case: it is the normal finding in the
    /// literature, routinely 20–30%, and it is *systematic* rather than random,
    /// so averaging more days does not cancel it.
    public static let completeEnough = 0.8
}
