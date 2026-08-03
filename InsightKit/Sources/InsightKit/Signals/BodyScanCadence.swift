import Foundation

/// When the next body scan is due.
///
/// Deliberately the same shape as `GroundingRenewal`: four states, a proportional
/// warning window, and no notion of nagging. A scan is not a fact that expires —
/// last month's waist is still a true measurement of last month — so "stale"
/// here means *the trend has a hole in it*, not *this reading is wrong*.
///
/// Thirty days is the reader's own interval, and it is a good one for the
/// subject: body composition moves slowly enough that a fortnight is mostly
/// noise, and slowly enough that a quarter loses the shape of the change.
public enum BodyScanCadence {

    public enum State: String, Sendable, Equatable {
        /// Never scanned.
        case missing
        /// Inside the interval.
        case current
        /// Inside the interval, but near the end of it.
        case expiringSoon
        /// Past due — the trend now has a gap in it.
        case overdue
    }

    /// The reader's interval.
    public static let intervalDays = 30

    /// How much of the interval counts as "coming up", matching
    /// `GroundingRenewal.expiringSoonFraction` so the two read the same on a
    /// screen that shows both.
    public static let expiringSoonFraction = 0.2

    public static func state(lastScan: Date?, now: Date,
                             calendar: Calendar = .current) -> State {
        guard let lastScan else { return .missing }
        let elapsed = calendar.dateComponents([.day], from: calendar.startOfDay(for: lastScan),
                                              to: calendar.startOfDay(for: now)).day ?? 0
        if elapsed >= intervalDays { return .overdue }
        let warnFrom = Double(intervalDays) * (1 - expiringSoonFraction)
        return Double(elapsed) >= warnFrom ? .expiringSoon : .current
    }

    /// Days until the next one is due; negative once overdue. Nil if never
    /// scanned, because "due in −∞ days" is not a thing to render.
    public static func daysUntilDue(lastScan: Date?, now: Date,
                                    calendar: Calendar = .current) -> Int? {
        guard let lastScan else { return nil }
        let elapsed = calendar.dateComponents([.day], from: calendar.startOfDay(for: lastScan),
                                              to: calendar.startOfDay(for: now)).day ?? 0
        return intervalDays - elapsed
    }

    /// What to say, or nil where there is nothing worth saying.
    ///
    /// `.current` returns nil on purpose. A reminder that appears every day
    /// stops being a reminder, and the state is still visible on the card for
    /// anyone who goes looking.
    public static func prompt(lastScan: Date?, now: Date,
                              calendar: Calendar = .current) -> (title: String, detail: String)? {
        switch state(lastScan: lastScan, now: now, calendar: calendar) {
        case .current:
            return nil
        case .missing:
            return ("Take your first body scan",
                    "A scan measures your waist, hips and chest, which tells the Body Composition card things a scale cannot — where the weight actually sits. It takes about a minute.")
        case .expiringSoon:
            let days = max(daysUntilDue(lastScan: lastScan, now: now, calendar: calendar) ?? 0, 0)
            return ("Your next body scan is due in \(days) day\(days == 1 ? "" : "s")",
                    "Scanning about once a month is what turns single measurements into a trend. Take it under the same conditions as last time and the comparison holds.")
        case .overdue:
            let over = -(daysUntilDue(lastScan: lastScan, now: now, calendar: calendar) ?? 0)
            return ("It's been \(intervalDays + over) days since your last body scan",
                    "Your measurements trend has a gap in it. A fresh scan closes it — same spot, same clothes, same time of day if you can.")
        }
    }
}
