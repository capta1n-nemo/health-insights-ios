import Foundation

/// How a day's screen-time figure got here.
///
/// Ordered by how much the app should believe it. The reader's rule, in their
/// own words: *"the screenshot is actual me — manual is manual"*, and a manual
/// entry made afterwards is them correcting the app on purpose. So authority
/// decides between two readings **except** where the reader has acted more
/// recently than the import — see `ScreenTimePrecedence`.
public enum ScreenTimeProvenance: String, Sendable, Codable, CaseIterable, Equatable {
    /// Typed in by hand, or arrived through a Shortcuts automation the reader
    /// set up. Believed least, because the other two are the device's own
    /// accounting rather than a recollection.
    case manual
    /// A day's share of a **Week** screenshot, split by the relative heights of
    /// the seven bars. The week's total is exact; this day's share of it is not.
    case weekEstimate
    /// A **Day** screenshot's own total, read as text. Exact.
    case dayExact

    public var authority: Int {
        switch self {
        case .manual: return 0
        case .weekEstimate: return 1
        case .dayExact: return 2
        }
    }

    /// Whether the number is a share worked out from a chart rather than a
    /// figure that was printed on the screen.
    ///
    /// Every surface that shows one of these has to say so. A split day and a
    /// screenshotted day are different claims, and the app already refuses to
    /// let a modelled series pass as a measured one (`MetricSource.calculated`)
    /// — this is the same rule one level down.
    public var isEstimate: Bool { self == .weekEstimate }

    public var displayName: String {
        switch self {
        case .manual: return "Entered by hand"
        case .weekEstimate: return "Estimated from a week screenshot"
        case .dayExact: return "From a day screenshot"
        }
    }

    /// The short form for a row on a data page.
    public var badge: String {
        switch self {
        case .manual: return "Manual"
        case .weekEstimate: return "Estimated"
        case .dayExact: return "Screenshot"
        }
    }
}

/// One day's screen time, with where it came from and when it was recorded.
public struct ScreenTimeEntry: Sendable, Equatable {
    /// Start of the day this figure is about.
    public let day: Date
    public let minutes: Double
    public let provenance: ScreenTimeProvenance
    /// When this entry was written — **not** the day it describes. What makes
    /// "unless I manually override over the top of it again" decidable.
    public let recordedAt: Date

    public init(day: Date, minutes: Double,
                provenance: ScreenTimeProvenance, recordedAt: Date) {
        self.day = day
        self.minutes = minutes
        self.provenance = provenance
        self.recordedAt = recordedAt
    }
}

/// Which of several figures for one day the app should show.
///
/// ## The rule
///
/// 1. Among the screenshot-derived entries, the **more authoritative** wins:
///    an exact day beats a week-split estimate. Re-importing an old week
///    screenshot must not overwrite a day the reader later screenshotted
///    precisely, even though the import is newer.
/// 2. A **manual** entry wins if and only if it was recorded *after* the
///    screenshot entry it is competing with. That is the reader correcting the
///    app, which is the one thing that should outrank the device's own numbers.
/// 3. Otherwise the screenshot wins, however old, because it is the device's
///    accounting and the manual figure was a recollection made before it.
public enum ScreenTimePrecedence {

    public static func winner(among entries: [ScreenTimeEntry]) -> ScreenTimeEntry? {
        let screenshots = entries.filter { $0.provenance != .manual }
        let manuals = entries.filter { $0.provenance == .manual }

        let bestScreenshot = screenshots.max { left, right in
            if left.provenance.authority != right.provenance.authority {
                return left.provenance.authority < right.provenance.authority
            }
            // **Screen time only accumulates within a day**, so between two
            // exact readings of the *same* day the larger one was captured
            // later in that day and is the more complete figure.
            //
            // The reader's rule, and it is deliberately **not** "newer
            // recordedAt wins": a screenshot taken at 23:00 shows the whole day
            // and one taken at noon shows half of it, and which was *imported*
            // first says nothing about which was *captured* later. Importing
            // the midday shot second would otherwise overwrite the complete day
            // with a partial one — one of the three re-import cases the reader
            // reported from the device on 2026-08-03.
            //
            // Only `.dayExact`. A `.weekEstimate` is a *share* of a total, not
            // an accumulation, so a bigger split is not a more complete one; a
            // week re-uploaded in full is newer and wins on recordedAt below,
            // which is the right rule for that case.
            if left.provenance == .dayExact, left.minutes != right.minutes {
                return left.minutes < right.minutes
            }
            return left.recordedAt < right.recordedAt
        }
        let newestManual = manuals.max { $0.recordedAt < $1.recordedAt }

        switch (bestScreenshot, newestManual) {
        case let (screenshot?, manual?):
            return manual.recordedAt > screenshot.recordedAt ? manual : screenshot
        case let (screenshot?, nil):
            return screenshot
        case let (nil, manual?):
            return manual
        case (nil, nil):
            return nil
        }
    }

    /// Whether a new entry would actually be shown if it were saved.
    ///
    /// Lets an importer skip writing rows that are already outranked, so
    /// re-importing the same screenshot twice is a no-op rather than a pile of
    /// records the resolver has to sort through on every read.
    public static func wouldWin(_ candidate: ScreenTimeEntry,
                                over existing: [ScreenTimeEntry]) -> Bool {
        winner(among: existing + [candidate]) == candidate
    }
}

/// Splitting a Week screenshot's total across its seven days.
///
/// ## Why this is worth doing at all, and why it is honest
///
/// A Week screenshot prints two exact numbers — the week's total and its daily
/// average — and draws seven bars. **The bars are pixels, not text**, so OCR
/// cannot read Monday. What it can do is measure how tall each bar is relative
/// to the others, and the reader asked for exactly that: *"do a good pixel
/// based calculation"*, marked as estimated until a Day screenshot replaces it.
///
/// The property that makes it defensible: **the week's total is preserved
/// exactly.** Only the *split* is estimated. So a week that reads 99h 33m still
/// sums to 99h 33m however badly the bar measurement went, and anything
/// aggregating by week is unaffected by the estimate. The alternative the reader
/// rejected — writing the 14h 13m average onto all seven days — also sums
/// correctly but asserts every day was identical, which the chart it came from
/// visibly contradicts.
///
/// Pure arithmetic, so it is tested here; measuring the bars needs CoreGraphics
/// and lives in the app target.
public enum ScreenTimeWeekBreakdown {

    public static let daysInWeek = 7

    /// A day's estimated share.
    public struct Day: Sendable, Equatable {
        public let date: Date
        public let minutes: Double

        public init(date: Date, minutes: Double) {
            self.date = date
            self.minutes = minutes
        }
    }

    /// Distribute an exact weekly total across seven days in proportion to the
    /// measured bar heights.
    ///
    /// - Parameter barHeights: seven relative heights, in any unit — only their
    ///   ratios are used. A zero is a legitimate day with no screen time.
    /// - Returns: seven days, or `nil` when the input cannot support a split.
    ///   **Nil rather than a flat fallback**: if the bars could not be measured
    ///   the honest outcome is to record the week and no days, not to invent
    ///   seven identical ones.
    public static func split(weekStart: Date, totalMinutes: Double,
                             barHeights: [Double],
                             calendar: Calendar = .current) -> [Day]? {
        guard barHeights.count == daysInWeek,
              totalMinutes >= 0,
              barHeights.allSatisfy({ $0 >= 0 && $0.isFinite }) else { return nil }
        let sum = barHeights.reduce(0, +)
        guard sum > 0 else { return nil }

        let start = calendar.startOfDay(for: weekStart)
        let dates: [Date] = (0..<daysInWeek).compactMap {
            calendar.date(byAdding: .day, value: $0, to: start)
        }
        guard dates.count == daysInWeek else { return nil }

        let shares = apportion(total: totalMinutes, weights: barHeights)
        return zip(dates, shares).map { Day(date: $0, minutes: $1) }
    }

    /// Whole minutes summing **exactly** to the total, by largest remainder.
    ///
    /// Rounding each share independently loses or gains up to three minutes a
    /// week, which would quietly break the one guarantee this type offers. The
    /// leftover goes to the days with the largest fractional parts, which is the
    /// standard apportionment and the only one that cannot be accused of
    /// favouring a particular day.
    static func apportion(total: Double, weights: [Double]) -> [Double] {
        let sum = weights.reduce(0, +)
        guard sum > 0 else { return weights.map { _ in 0 } }
        let exact = weights.map { total * $0 / sum }
        var floors = exact.map { $0.rounded(.down) }
        let assigned = floors.reduce(0, +)
        var leftover = Int((total.rounded() - assigned).rounded())

        // Days with the biggest fractional part get the spare minutes first.
        let order = exact.enumerated()
            .sorted { ($0.element - $0.element.rounded(.down))
                    > ($1.element - $1.element.rounded(.down)) }
            .map(\.offset)
        var index = 0
        while leftover > 0 && !order.isEmpty {
            floors[order[index % order.count]] += 1
            leftover -= 1
            index += 1
        }
        return floors
    }
}
