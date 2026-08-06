import Foundation

/// **One dated record of the reader's leave, from two sources** — backlog B7 H5.
///
/// Detected leave (all-day and multi-day calendar blocks the classifier read as
/// the reader's own — H3) and leave the reader entered by hand (H4) merge into
/// a single, deduplicated list of periods. This is the data point the cards
/// will read: *"knowing you have, or have not been on a holiday is a very good
/// data point"* (the reader, 2026-08-06).
///
/// ## Why merge rather than keep two lists
///
/// The same week off usually exists twice — an "Annual leave" block in the
/// calendar *and* a hand-entered record — and a card that read both would count
/// one holiday as two. Overlapping periods therefore collapse into one, and
/// where an entered record overlaps a detected one **the entered record wins**
/// the label and the source: the reader's own statement outranks a guess, the
/// same precedence `CalendarEventJudgement` gives corrections.
///
/// Adjacent-but-not-overlapping periods stay separate on purpose: two distinct
/// holidays back to back are two holidays, and merging them would erase the
/// reader's own record of which was which.
///
/// ## ⚠️ Privacy: detected periods carry no label
///
/// A detected period comes from a calendar event, and an event title is the
/// most identifying string this app holds — titles never reach the export
/// (`HealthDataExport.exportKey(for: .calendarEvents)` says why). So detection
/// keeps the *dates* and drops the words: `detected(events:judgements:)` always
/// produces `label: nil`, which is what lets the merged ledger export safely.
///
/// ## What is deliberately not here yet
///
/// H6 (the work-impact, travel, stress and mental-health cards reading
/// `daysSinceLastLeave`) and H7 (the "take a long weekend" recommendation) are
/// **not wired** — each scoring model that takes leave as an input needs its
/// `modelVersion` bumped, per the fitness-v2 precedent, and that is its own
/// change. This type is the input they will read.
public struct HolidayLedger: Sendable, Equatable {

    /// One stretch of leave, in whole days, both ends inclusive.
    public struct Period: Sendable, Equatable, Hashable, Codable, Identifiable {
        /// Where a period came from. Kept per period — not per ledger — because
        /// the merged list interleaves them and a reviewing reader is owed the
        /// difference between "you told me" and "your calendar suggested".
        public enum Source: String, Sendable, Codable {
            case detected, entered
        }

        /// The first day off, at start of day.
        public let firstDay: Date
        /// The last day off, at start of day — **inclusive**, so a one-day
        /// holiday has `firstDay == lastDay`. Inclusive rather than exclusive
        /// because every consumer thinks in days ("how many days off"), and an
        /// exclusive end is the off-by-one this repo would otherwise re-derive
        /// at each call site.
        public let lastDay: Date
        /// The reader's own words, when they gave any. Always nil for detected
        /// periods — see the type note on privacy.
        public let label: String?
        public let source: Source

        public var id: String {
            "\(source.rawValue)|\(firstDay.timeIntervalSince1970)|\(lastDay.timeIntervalSince1970)"
        }

        public init(firstDay: Date, lastDay: Date, label: String? = nil,
                    source: Source) {
            // Normalised rather than trusted: a reversed interval from a sheet
            // whose pickers crossed is a data error the type absorbs once, here.
            self.firstDay = min(firstDay, lastDay)
            self.lastDay = max(firstDay, lastDay)
            self.label = label
            self.source = source
        }

        /// Whole days, inclusive of both ends.
        public func dayCount(calendar: Calendar = .current) -> Int {
            (calendar.dateComponents([.day],
                                     from: calendar.startOfDay(for: firstDay),
                                     to: calendar.startOfDay(for: lastDay)).day ?? 0) + 1
        }
    }

    /// Merged, deduplicated, ascending by first day.
    public let periods: [Period]

    public init(detected: [Period] = [], entered: [Period] = [],
                calendar: Calendar = .current) {
        // Everything is normalised to whole days before merging, so "overlap"
        // means overlapping *days* rather than overlapping instants — a
        // detected block ending at 23:59 and an entered one starting that
        // morning are the same day off.
        let normalised = (detected + entered).map {
            Period(firstDay: calendar.startOfDay(for: $0.firstDay),
                   lastDay: calendar.startOfDay(for: $0.lastDay),
                   label: $0.label, source: $0.source)
        }
        .sorted {
            $0.firstDay != $1.firstDay ? $0.firstDay < $1.firstDay
                                       : $0.lastDay < $1.lastDay
        }

        var merged: [Period] = []
        for period in normalised {
            guard let last = merged.last, period.firstDay <= last.lastDay else {
                merged.append(period)
                continue
            }
            // Overlap: one stretch of leave, recorded twice. The entered
            // record's label and source win — the reader's statement outranks
            // the calendar's suggestion — and the interval is the union.
            let enteredHalf = [last, period].first { $0.source == .entered }
            merged[merged.count - 1] = Period(
                firstDay: last.firstDay,
                lastDay: max(last.lastDay, period.lastDay),
                label: enteredHalf?.label ?? last.label ?? period.label,
                source: enteredHalf?.source ?? .detected)
        }
        periods = merged
    }

    // MARK: - What the cards will read (H6, deliberately not wired yet)

    /// Whole days since the reader's last day of leave — the number the
    /// stress-shaped cards will read.
    ///
    /// - `0` while a period covers `asOf` (they are on leave now).
    /// - `nil` when no leave has ever *happened* by `asOf` — including a ledger
    ///   holding only planned future leave, because "you have a holiday booked"
    ///   is a different answer from "you had one recently" and conflating them
    ///   would let a booking silently satisfy a card asking about recovery.
    public func daysSinceLastLeave(asOf: Date = Date(),
                                   calendar: Calendar = .current) -> Int? {
        let day = calendar.startOfDay(for: asOf)
        let past = periods.filter { $0.firstDay <= day }
        guard let latest = past.map(\.lastDay).max() else { return nil }
        guard latest < day else { return 0 }
        return calendar.dateComponents([.day], from: latest, to: day).day
    }

    /// Every period touching the given range — for a card asking "any leave in
    /// the last N months", and for the Data page's windowed views.
    ///
    /// Touching, not contained: a fortnight that *ends* inside the range was
    /// still leave inside the range, and clipping would misreport its length.
    public func leave(in range: DateInterval,
                      calendar: Calendar = .current) -> [Period] {
        periods.filter { period in
            // The period occupies [firstDay, end of lastDay); it touches the
            // range if it starts before the range ends and ends after it starts.
            let periodEnd = calendar.date(byAdding: .day, value: 1,
                                          to: period.lastDay) ?? period.lastDay
            return period.firstDay < range.end && periodEnd > range.start
        }
    }

    // MARK: - Detection (H3)

    /// The detected half: all-day and multi-day calendar blocks whose effective
    /// classification — correction first, guess otherwise — says they are the
    /// reader's own leave.
    ///
    /// Timed events are excluded even when classified `.leave`: a two-hour
    /// "OOO" block is an absence from *meetings*, not a holiday, and counting
    /// it as one would reset `daysSinceLastLeave` on every dentist trip.
    ///
    /// Labels are deliberately dropped — the dates are the data point, and the
    /// event's title must not travel into a ledger that exports.
    public static func detected(events: [CalendarEvent],
                                judgements: [CalendarEventJudgement],
                                calendar: Calendar = .current) -> [Period] {
        let byID = Dictionary(uniqueKeysWithValues: judgements.map { ($0.eventID, $0.effective) })
        return events.compactMap { event in
            guard event.kind == .allDay || event.kind == .multiDay,
                  let classification = byID[event.id],
                  classification.occasion == .leave else { return nil }
            let firstDay = calendar.startOfDay(for: event.start)
            // An all-day event's `end` is exclusive — midnight *after* the last
            // day — so the last inclusive day is the day containing the final
            // moment before it. `max` guards a degenerate zero-length event.
            let lastDay = max(firstDay,
                              calendar.startOfDay(for: event.end.addingTimeInterval(-1)))
            return Period(firstDay: firstDay, lastDay: lastDay,
                          label: nil, source: .detected)
        }
    }
}
