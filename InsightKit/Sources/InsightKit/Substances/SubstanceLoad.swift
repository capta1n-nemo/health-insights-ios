import Foundation

/// A day's cardiovascular load from logged substance use.
public struct SubstanceLoadPoint: Sendable, Equatable, Identifiable {
    /// Start of the day this value is measured at the end of.
    public let date: Date
    /// 0–100, on the same scale and with the same bands as the card's figure.
    public let load: Double
    /// Weighted units still live that day, before rescaling. Kept so a scrub
    /// read-out can explain where the number came from rather than assert it.
    public let units: Double
    /// Events logged *on this day*, not the decaying tail. What the chart marks.
    public let eventCount: Int

    public init(date: Date, load: Double, units: Double, eventCount: Int) {
        self.date = date
        self.load = load
        self.units = units
        self.eventCount = eventCount
    }

    public var id: Date { date }
    public var band: String { SubstanceResponseAnalyzer.band(for: load) }
}

/// Cumulative cardiovascular load as a decaying daily series.
///
/// The card's fortnight figure was a box-car: an event counted in full for
/// fourteen days and then disappeared overnight, so a heavy weekend read
/// "considerable" for thirteen days and "light" on the fourteenth. That is
/// tolerable as a single number and useless as a series — the shape it draws is
/// a staircase of the calendar rather than of the body.
///
/// This is an exponential kernel instead, normalised from the box-car's own
/// constants so the two agree at steady state rather than becoming two answers
/// to one question. Someone logging at the rate that saturates the fortnight
/// figure reads 100 here too; the difference is entirely in how the number moves
/// between those points.
public enum SubstanceLoad {

    /// How long a logged event's contribution takes to halve.
    ///
    /// Seven days, so `loadWindowDays` is exactly two half-lives: an event still
    /// carries a quarter of its weight at the moment the old window would have
    /// dropped it outright, and the series inherits none of that cliff.
    public static let halfLifeDays = 7.0

    /// Live weighted units corresponding to a load of 100.
    ///
    /// Derived rather than chosen. `loadSaturationUnits / loadWindowDays` is the
    /// rate of use that saturates the card's figure, and a kernel of half-life
    /// `h` holds `rate × h/ln2` at equilibrium. Deriving it is what keeps the two
    /// figures one answer: change either constant and both move together.
    public static var saturationUnits: Double {
        SubstanceResponseAnalyzer.loadSaturationUnits
            / Double(SubstanceResponseAnalyzer.loadWindowDays)
            * (halfLifeDays / log(2))
    }

    /// Fraction of an event's weight surviving after `daysAgo`.
    ///
    /// Zero for a future event, so a replayed past day never sees a log entry
    /// recorded after it.
    public static func decay(daysAgo: Double) -> Double {
        guard daysAgo >= 0 else { return 0 }
        return pow(0.5, daysAgo / halfLifeDays)
    }

    /// Weighted units still live at `date`.
    public static func units(events: [SubstanceEvent], at date: Date) -> Double {
        events.reduce(0.0) { total, event in
            total + event.substance.acuteCardiacLoad
                * decay(daysAgo: date.timeIntervalSince(event.timestamp) / 86_400)
        }
    }

    /// 0–100 load at `date`, on the card's scale.
    public static func load(events: [SubstanceEvent], at date: Date) -> Double {
        Swift.min(100, units(events: events, at: date) / saturationUnits * 100)
    }

    /// One point per day, oldest first, each measured at that day's end, ending
    /// on the day containing `now`.
    ///
    /// Dense by construction: load is defined on a day with no logs at all,
    /// because the decaying tail of earlier use is exactly what the series exists
    /// to show. So unlike a measured series this one has no gaps and needs no gap
    /// rule — see `MetricType.maxValidInterval` for the other case.
    public static func series(events: [SubstanceEvent], days: Int = 90,
                              now: Date = Date(),
                              calendar: Calendar = .current) -> [SubstanceLoadPoint] {
        guard days > 0 else { return [] }
        let visible = events.filter { $0.timestamp <= now }
        guard !visible.isEmpty else { return [] }

        let today = calendar.startOfDay(for: now)
        var points: [SubstanceLoadPoint] = []
        points.reserveCapacity(days)
        for offset in stride(from: days - 1, through: 0, by: -1) {
            guard let dayStart = calendar.date(byAdding: .day, value: -offset, to: today),
                  let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else { continue }
            // Never measure past the real present: a partial day would otherwise
            // report a decay the clock hasn't delivered yet.
            let asOf = Swift.min(dayEnd, now)
            let logged = visible.filter { $0.timestamp >= dayStart && $0.timestamp < dayEnd }
            points.append(SubstanceLoadPoint(
                date: dayStart,
                load: load(events: visible, at: asOf),
                units: units(events: visible, at: asOf),
                eventCount: logged.count))
        }
        return points
    }
}

public extension Array where Element == SubstanceLoadPoint {
    /// Least-squares change per week, in load points.
    var trendPerWeek: Double? {
        guard count >= 4, let first = self.first?.date else { return nil }
        let x = map { $0.date.timeIntervalSince(first) / 86_400 }
        return Baseline.linearRegression(x: x, y: map(\.load)).map { $0.slope * 7 }
    }

    /// The fitted line and the scatter around it.
    ///
    /// Reuses `ScoreTrend` rather than minting a second trend type: both series
    /// are 0–100 and both need a slope quoted with its residual spread, which is
    /// the whole reason that struct refuses to report a bare number.
    var loadTrend: ScoreTrend? {
        guard count >= 8, let first = self.first?.date else { return nil }
        let x = map { $0.date.timeIntervalSince(first) / 86_400 }
        guard let fit = Baseline.linearRegression(x: x, y: map(\.load)) else { return nil }
        return ScoreTrend(slopePerWeek: fit.slope * 7, residualSD: fit.residualSD,
                          start: first, intercept: fit.intercept,
                          slopePerDay: fit.slope, sampleCount: count)
    }
}
