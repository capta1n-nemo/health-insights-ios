import Foundation

/// **One dated record of the days the reader was ill** — backlog §B11-4.
///
/// The reader, on §B11: *"since this 'sick day' is now a new data source, it
/// should of course now be stored in the data section too, so all of this can be
/// viewed and changed from the data section too."* This is that data source: the
/// thing `DataDomain.sickDays` renders, the thing the export carries, and the
/// only place in the app where "was I ill on that date" has an answer.
///
/// ## Deliberately built like `HolidayLedger`, and deliberately not it
///
/// The shape is the same on purpose — dated periods, merged, both ends
/// inclusive, each carrying which source it came from — so the two read
/// identically on a Data page and one bug fixed in either is obviously the same
/// bug in the other. Copying the shape is cheap; sharing the type would not be.
///
/// **A sick day is not leave.** Merging them would let a week of flu satisfy
/// `HolidayLedger.daysSinceLastLeave` and read as recovery to every card §B7 H6
/// will wire — which is the exact inversion of what happened. So `.sick` is its
/// own `Occasion` and this is its own ledger, and `HolidayLedger.detected` still
/// looks only for `.leave`.
///
/// ## ⚠️ What this ledger is NOT, and must never become
///
/// It is **a record of what the reader said**, never a physiological finding.
/// `docs/illness-detection-evidence-2026-08-07.md` is the authority and the
/// numbers are not close: prospective positive predictive value for wearable
/// illness detection is **4–12%**, roughly **two-thirds of genuine infections
/// produce no clear signal at all**, and in the only randomised trial the
/// physiological alerts produced zero confirmed infections. So:
///
/// - A day in this ledger is a day the reader (or their calendar) *said* they
///   were ill. Nothing here is evidence they were.
/// - A day **absent** from this ledger is not evidence they were well.
/// - And the inverse — "the radar was quiet, so this sick day looks unlike
///   illness" — is **not** a finding about honesty. It is the expected reading
///   for most real illness. That comparison is gated on a decision the reader
///   has not made (§B11, the fake-sick-day inversion); this type deliberately
///   offers no method that computes it.
///
/// ## Privacy: a detected period carries no label
///
/// A detected period comes from a calendar event, and an event title is the most
/// identifying string this app holds — the same rule `HolidayLedger` documents
/// at length, with more force here, because a sick-day title is a health fact in
/// somebody's own words. `detected(events:judgements:)` always produces
/// `label: nil`, which is what lets the merged ledger export at all.
public struct SickDayLedger: Sendable, Equatable {

    /// One stretch of illness, in whole days, both ends inclusive.
    public struct Period: Sendable, Equatable, Hashable, Codable, Identifiable {
        /// Where a period came from. Per period, not per ledger — a reviewing
        /// reader is owed the difference between "you told me" and "your
        /// calendar said so".
        public enum Source: String, Sendable, Codable {
            case detected, entered
        }

        /// The first day ill, at start of day.
        public let firstDay: Date
        /// The last day ill, at start of day — **inclusive**, so a one-day
        /// illness has `firstDay == lastDay`. `HolidayLedger.Period`'s own
        /// convention, kept so the two never disagree by one.
        public let lastDay: Date
        /// The reader's own words, when they gave any. Always nil for detected
        /// periods — see the type note on privacy.
        public let label: String?
        /// How ill, where anybody said. `nil` and `.unstated` are different
        /// records and both are kept: nil is "no grade exists", `.unstated` is
        /// "somebody looked and did not grade it".
        public let severity: CalendarEventClassification.SickSeverity?
        public let source: Source

        public var id: String {
            "\(source.rawValue)|\(firstDay.timeIntervalSince1970)|\(lastDay.timeIntervalSince1970)"
        }

        public init(firstDay: Date, lastDay: Date, label: String? = nil,
                    severity: CalendarEventClassification.SickSeverity? = nil,
                    source: Source) {
            // Normalised rather than trusted, exactly as `HolidayLedger.Period`
            // does: a reversed interval from crossed pickers is a data error the
            // type absorbs once, here.
            self.firstDay = min(firstDay, lastDay)
            self.lastDay = max(firstDay, lastDay)
            self.label = label
            self.severity = severity
            self.source = source
        }

        /// Whole days, inclusive of both ends.
        public func dayCount(calendar: Calendar = .current) -> Int {
            (calendar.dateComponents([.day],
                                     from: calendar.startOfDay(for: firstDay),
                                     to: calendar.startOfDay(for: lastDay)).day ?? 0) + 1
        }

        /// Whether a given day falls inside this period.
        public func covers(_ day: Date, calendar: Calendar = .current) -> Bool {
            let start = calendar.startOfDay(for: day)
            return start >= firstDay && start <= lastDay
        }
    }

    /// Merged, deduplicated, ascending by first day.
    public let periods: [Period]

    public init(detected: [Period] = [], entered: [Period] = [],
                calendar: Calendar = .current) {
        let normalised = (detected + entered).map {
            Period(firstDay: calendar.startOfDay(for: $0.firstDay),
                   lastDay: calendar.startOfDay(for: $0.lastDay),
                   label: $0.label, severity: $0.severity, source: $0.source)
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
            // Overlap: one stretch of illness recorded twice. The entered
            // record's label and source win — the reader's statement outranks
            // the calendar's — and the interval is the union.
            let enteredHalf = [last, period].first { $0.source == .entered }
            merged[merged.count - 1] = Period(
                firstDay: last.firstDay,
                lastDay: max(last.lastDay, period.lastDay),
                label: enteredHalf?.label ?? last.label ?? period.label,
                // **The worse grade survives a merge**, not the newer one. Two
                // records of one illness are two partial views of it, and a
                // "mild" written on day one must not overwrite the "severe"
                // written on day three — the reverse would let a merge quietly
                // downgrade how bad a week was.
                severity: Self.worse(last.severity, period.severity),
                source: enteredHalf?.source ?? .detected)
        }
        periods = merged
    }

    /// The stronger of two grades, treating nil as "nothing said".
    static func worse(_ a: CalendarEventClassification.SickSeverity?,
                      _ b: CalendarEventClassification.SickSeverity?)
        -> CalendarEventClassification.SickSeverity? {
        func rank(_ s: CalendarEventClassification.SickSeverity?) -> Int {
            switch s {
            case .none: return -1
            case .some(.unstated): return 0
            case .some(.mild): return 1
            case .some(.moderate): return 2
            case .some(.severe): return 3
            }
        }
        return rank(a) >= rank(b) ? a : b
    }

    // MARK: - What a card or a page reads

    /// Whole days since the reader was last ill.
    ///
    /// - `0` while a period covers `asOf` (they are ill now).
    /// - `nil` when no illness has ever *happened* by `asOf` — including a
    ///   ledger holding only future-dated records, because "nothing recorded"
    ///   and "recorded ahead" are different answers and conflating them is the
    ///   trap `HolidayLedger.daysSinceLastLeave` documents.
    public func daysSinceLastSickDay(asOf: Date = Date(),
                                     calendar: Calendar = .current) -> Int? {
        let day = calendar.startOfDay(for: asOf)
        let past = periods.filter { $0.firstDay <= day }
        guard let latest = past.map(\.lastDay).max() else { return nil }
        guard latest < day else { return 0 }
        return calendar.dateComponents([.day], from: latest, to: day).day
    }

    /// Every period touching the given range. Touching, not contained — an
    /// illness that *ends* inside the range was still illness inside it, and
    /// clipping would misreport its length.
    public func illness(in range: DateInterval,
                        calendar: Calendar = .current) -> [Period] {
        periods.filter { period in
            let periodEnd = calendar.date(byAdding: .day, value: 1,
                                          to: period.lastDay) ?? period.lastDay
            return period.firstDay < range.end && periodEnd > range.start
        }
    }

    /// Every individual day covered by any period, as start-of-day dates.
    ///
    /// What a chart marks and what a comparison joins on. A set rather than an
    /// array because overlapping periods are already merged, so duplicates
    /// would be a bug rather than data.
    public func sickDays(calendar: Calendar = .current) -> Set<Date> {
        var days: Set<Date> = []
        for period in periods {
            var day = period.firstDay
            while day <= period.lastDay {
                days.insert(day)
                guard let next = calendar.date(byAdding: .day, value: 1, to: day),
                      next > day else { break }
                day = next
            }
        }
        return days
    }

    /// Total days ill inside a window — the figure the Data page prints.
    public func dayCount(in range: DateInterval, calendar: Calendar = .current) -> Int {
        sickDays(calendar: calendar).filter { $0 >= range.start && $0 < range.end }.count
    }

    // MARK: - Detection (§B11-6 feeding §B11-4)

    /// The detected half: all-day and multi-day calendar blocks whose effective
    /// classification — correction first, guess otherwise — says the reader was
    /// ill.
    ///
    /// **A timed event the app merely guessed at is excluded**, exactly as
    /// `HolidayLedger.detected` excludes a two-hour "OOO": a one-hour block
    /// titled "sick note — call GP" is an errand, not a day in bed, and counting
    /// it as one would reset `daysSinceLastSickDay` on every appointment.
    ///
    /// ⚠️ **The exclusion is a rule about guesses and stops at the reader**
    /// (2026-08-09, from their own phone: *"I correct a day to include illness
    /// on the calendar… the AI doesn't seem to learn from it"*). The shape test
    /// is a proxy for "was this a day in bed", and a proxy is only wanted while
    /// nobody has answered the question directly. Once the reader has opened the
    /// review row and said *Sick day, severe*, the proxy was overruled by the
    /// only person who was there — so `sicknessIsTheReaders` admits the event
    /// whatever shape it is, and the drop that made their correction produce no
    /// ledger period, no Data-tab row, no radar input and no export line is
    /// closed. A rules-classified timed block is still dropped, which is what
    /// `SickDayTests.testATimedSickBlockIsNotADetectedPeriod` has always pinned.
    ///
    /// Labels are dropped, severity is carried — the grade is a number-ish fact
    /// the reader stated, the title is words about their health.
    public static func detected(events: [CalendarEvent],
                                judgements: [CalendarEventJudgement],
                                calendar: Calendar = .current) -> [Period] {
        // ⚠️ `uniquingKeysWith`, never `uniqueKeysWithValues`. Two judgement
        // rows for one event id is a storage defect, and the strict initialiser
        // answers a storage defect by killing the process on the launch path
        // that builds this ledger. Last one wins, which is the row the store
        // wrote most recently.
        let byID = Dictionary(judgements.map { ($0.eventID, $0.effective) },
                              uniquingKeysWith: { _, latest in latest })
        return events.compactMap { event in
            guard let classification = byID[event.id],
                  classification.occasion == .sick,
                  event.kind == .allDay || event.kind == .multiDay
                      || classification.sicknessIsTheReaders else { return nil }
            let firstDay = calendar.startOfDay(for: event.start)
            // An all-day event's `end` is exclusive — midnight *after* the last
            // day — so the last inclusive day is the day holding the final
            // moment before it. `max` guards a degenerate zero-length event.
            let lastDay = max(firstDay,
                              calendar.startOfDay(for: event.end.addingTimeInterval(-1)))
            return Period(firstDay: firstDay, lastDay: lastDay, label: nil,
                          severity: classification.severity, source: .detected)
        }
    }
}
