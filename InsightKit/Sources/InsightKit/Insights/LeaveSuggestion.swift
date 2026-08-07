import Foundation

/// **"Maybe I should take a long weekend — and the app knows when"** — backlog
/// B7 H7, in the reader's own words:
///
/// > *"if i'm stressed, my health is bad.. maybe I should be recommended to take
/// > some leave, take a long weekend.. and it could even look at my calendar and
/// > predict when is a good time since it knows my calendar!!"*
///
/// Two halves, and the second is the one nothing else in this app does: a
/// suggestion that names **a date**, chosen from the reader's own diary.
///
/// ## ⚠️ The three lines this must not cross
///
/// 1. **It is not medical advice, and the copy never lets it become any.**
///    Suggesting a day off is a scheduling observation about a calendar. The
///    sentence says what was measured (scores below the reader's own range), what
///    was found (no leave recorded for months), and which day is quietest — and
///    stops. No "you need rest", no "this will help", no claim about what leave
///    does to anybody.
/// 2. **It ranks below every grounding gap**, per H7's own note and the app's
///    standing rule against nagging. `Basis.signalOffBaseline` is the bottom of
///    `SuggestionEngine`'s four, which is where this belongs: it rests on scores
///    sitting away from their own range, which is exactly what that basis means.
/// 3. **It never fires on silence.** No recorded leave at all means the app has
///    not been told, not that none was taken — the guard `LeaveRecency` is built
///    around — and neither does it fire at somebody who already has leave
///    booked. Both are the same mistake: telling a reader to do a thing they
///    have already done.
public enum LeaveWindowFinder {

    /// One candidate stretch off, and everything the copy needs to justify it.
    public struct Window: Sendable, Equatable, Identifiable {
        /// The first day off — the working day the reader would take.
        public let workingDay: Date
        /// The whole stretch, first and last day inclusive, weekend included.
        public let start: Date
        public let end: Date
        /// Weighted work load on the working day, from the same `loadHours` the
        /// work-impact card counts. Zero for a day with nothing on it.
        public let loadHours: Double
        /// Whether anything on that day is marathon-length. A single all-day
        /// workshop disqualifies a window however light the rest of it is.
        public let hasMarathonDay: Bool
        /// Whether the stretch touches leave the reader has already booked —
        /// **the strongest kind of candidate**, because extending a break that
        /// already exists costs one day and buys two.
        public let extendsBookedLeave: Bool

        public var id: String { "\(workingDay.timeIntervalSince1970)" }
        public var dayCount: Int { 3 }
    }

    /// How far ahead to look. Twelve weeks: far enough that a genuinely quiet
    /// week exists to be found, near enough that a diary this far out is still
    /// mostly real rather than empty-by-default.
    ///
    /// ⚠️ **The horizon is also the honesty limit and the copy says so.** A
    /// calendar three months out is quiet partly because nobody has filled it
    /// in yet, and a window chosen from empty space is a statement about how far
    /// ahead this reader books rather than about how busy they will be.
    public static let horizonDays = 84

    /// Days from now before a window is worth suggesting. A "quiet Friday"
    /// tomorrow is not something anybody can act on.
    public static let leadTimeDays = 7

    /// Every Friday and Monday in the horizon that is not already leave, with
    /// what is on it — soonest first.
    ///
    /// **Fridays and Mondays only, and that is the reader's own framing**
    /// (*"take a long weekend"*): one working day off, adjacent to a weekend by
    /// construction, which is the cheapest break a calendar can offer. A Friday
    /// gives Fri–Sun; a Monday gives Sat–Mon.
    public static func windows(events: [CalendarEvent],
                               judgements: [CalendarEventJudgement],
                               ledger: HolidayLedger,
                               now: Date = Date(),
                               calendar: Calendar = .current) -> [Window] {
        let byID = Dictionary(judgements.map { ($0.eventID, $0.effective) },
                              uniquingKeysWith: { first, _ in first })
        let today = calendar.startOfDay(for: now)

        // Load per future day, from the same weighting the work-impact card
        // uses — an hour of formal meeting is not an hour of blocked time, and a
        // window chosen on raw duration would call a day of focus time busy.
        var load: [Date: Double] = [:]
        var marathon: Set<Date> = []
        for event in events where event.start >= today {
            let day = calendar.startOfDay(for: event.start)
            let classification = byID[event.id] ?? CalendarEventClassifier.classify(event)
            guard CalendarEventBucket(classification) == .work else { continue }
            load[day, default: 0] += classification.loadHours
            if classification.isMarathon { marathon.insert(day) }
        }

        var out: [Window] = []
        for offset in leadTimeDays...horizonDays {
            guard let day = calendar.date(byAdding: .day, value: offset, to: today)
            else { continue }
            // 6 = Friday, 2 = Monday in every Gregorian calendar.
            let weekday = calendar.component(.weekday, from: day)
            guard weekday == 6 || weekday == 2 else { continue }
            // Already off. Suggesting leave on a day the reader has booked leave
            // is the same failure as suggesting it to somebody just back.
            guard !ledger.periods.contains(where: {
                $0.firstDay <= day && day <= $0.lastDay
            }) else { continue }

            let start = weekday == 6 ? day
                : calendar.date(byAdding: .day, value: -2, to: day) ?? day
            let end = weekday == 6
                ? (calendar.date(byAdding: .day, value: 2, to: day) ?? day) : day
            // Touching booked leave at either end: one day off joins two breaks.
            let extends = ledger.periods.contains { period in
                let before = calendar.date(byAdding: .day, value: -1, to: start) ?? start
                let after = calendar.date(byAdding: .day, value: 1, to: end) ?? end
                return (period.firstDay <= before && before <= period.lastDay)
                    || (period.firstDay <= after && after <= period.lastDay)
            }
            out.append(Window(workingDay: day, start: start, end: end,
                              loadHours: load[day] ?? 0,
                              hasMarathonDay: marathon.contains(day),
                              extendsBookedLeave: extends))
        }
        return out
    }

    /// The best of them, or nil when nothing in the horizon qualifies.
    ///
    /// Ordering, in the order the reader would ask the questions: a window that
    /// **extends leave they already have** beats everything; a marathon day
    /// disqualifies; then the lightest diary; then the soonest. Deliberately not
    /// a scored composite — three of the four terms are booleans, and a weighted
    /// blend of booleans is a number nobody can check against their own calendar.
    public static func best(events: [CalendarEvent],
                            judgements: [CalendarEventJudgement],
                            ledger: HolidayLedger,
                            now: Date = Date(),
                            calendar: Calendar = .current) -> Window? {
        windows(events: events, judgements: judgements, ledger: ledger,
                now: now, calendar: calendar)
            .filter { !$0.hasMarathonDay }
            .min { a, b in
                if a.extendsBookedLeave != b.extendsBookedLeave {
                    return a.extendsBookedLeave
                }
                if abs(a.loadHours - b.loadHours) > 0.25 {
                    return a.loadHours < b.loadHours
                }
                return a.workingDay < b.workingDay
            }
    }
}

/// Everything the leave recommendation reads, in one parameter.
///
/// A struct rather than three arguments on `SuggestionEngine.suggestions`, whose
/// signature is already nine parameters deep — and because the three travel
/// together always: a ledger with no calendar cannot name a date, and a calendar
/// with no ledger cannot know a break is overdue.
public struct LeaveSuggestionInput: Sendable {
    public let ledger: HolidayLedger
    public let events: [CalendarEvent]
    public let judgements: [CalendarEventJudgement]

    public init(ledger: HolidayLedger, events: [CalendarEvent] = [],
                judgements: [CalendarEventJudgement] = []) {
        self.ledger = ledger
        self.events = events
        self.judgements = judgements
    }
}

public extension SuggestionEngine {

    /// How long since a break before this is worth raising at all.
    ///
    /// ⚠️ **Not a claim about how often anybody needs leave**, and the copy
    /// never makes one. It is the point at which `LeaveRecency`'s curve has run
    /// most of its slope, so "a long time" is being read off the same shape the
    /// four cards score with rather than off a second opinion invented here.
    static var leaveOverdueDays: Int { 120 }

    /// How far below its own midpoint a card's score has to sit to count as one
    /// of the two readings this rests on. 60 is where `ScoreBand` stops calling
    /// a number good, which is the app's own line and not a new one.
    static var leaveConcernScore: Double { 60 }

    /// Leave booked inside this many days silences the whole row. Somebody with
    /// a holiday a fortnight out has already acted.
    static var leaveBookedSoonDays: Int { 45 }

    /// **The leave recommendation** — B7 H7.
    ///
    /// Three conditions, all required, and each is a fact rather than a
    /// judgement: a break is a long way back, at least one of the two
    /// stress-shaped cards is sitting below its own good band, and nothing is
    /// booked. Only then does the calendar get read for a date.
    ///
    /// Returns at most one row. A list of candidate weekends would be a
    /// to-do list, which `SuggestionEngine.defaultLimit`'s own note rules out.
    static func leaveWindow(_ input: LeaveSuggestionInput?,
                            results: [InsightResult],
                            now: Date = Date(),
                            calendar: Calendar = .current) -> [Suggestion] {
        guard let input else { return [] }
        let recency = LeaveRecency.read(input.ledger, asOf: now, calendar: calendar)

        // ⚠️ Silence, not a finding. Nothing recorded means the app was not
        // told — see `LeaveRecency`.
        guard let days = recency.daysSinceLastLeave, days >= leaveOverdueDays else { return [] }
        if let next = recency.nextLeaveInDays, next <= leaveBookedSoonDays { return [] }

        // The health half, read off the cards rather than recomputed: two models
        // disagreeing about whether a fortnight was hard is exactly the
        // duplication `SuggestionEngine.convergence` avoids by reusing
        // `HealthWatchModel`.
        let watched: [InsightID] = [.sustainedLoad, .mentalHealth]
        let low = results.filter {
            watched.contains($0.id) && ($0.score ?? 100) < leaveConcernScore
        }
        guard let worst = low.min(by: { ($0.score ?? 100) < ($1.score ?? 100) })
        else { return [] }

        let named = list(low.map { $0.title.lowercased() })
        let months = days / 30
        let sinceClause = months >= 2
            ? "about \(months) months" : "\(days) days"

        // The date half. A row without one is still worth making — the finding
        // stands on its own — so the window is an *addition* to the sentence and
        // never a condition of it.
        let window = LeaveWindowFinder.best(events: input.events,
                                            judgements: input.judgements,
                                            ledger: input.ledger,
                                            now: now, calendar: calendar)
        let when = window.map { w -> String in
            let day = DateFormatter()
            day.dateFormat = "EEEE d MMMM"
            let quiet = w.loadHours < 0.5
                ? "nothing in your work calendar"
                : String(format: "%.1f h of work", w.loadHours)
            let extend = w.extendsBookedLeave
                ? " It also sits next to leave you have already booked, so one day off joins two breaks."
                : ""
            return " The quietest working day next to a weekend in the next "
                + "\(LeaveWindowFinder.horizonDays / 7) weeks is "
                + "\(day.string(from: w.workingDay)), which currently has \(quiet).\(extend) "
                + "A diary that far ahead is partly empty because it has not been "
                + "filled in yet, so read it as the best guess your calendar can make."
        } ?? " Your calendar has nothing far enough ahead to pick a day from."

        return [Suggestion(
            // Stable across dates and scores, so waving it away once is not
            // undone by the window moving to the following Friday.
            id: "leave-window",
            title: "It has been \(sinceClause) since a break",
            detail: "Your last recorded leave ended \(days) days ago, and "
                + "\(named) \(low.count == 1 ? "is" : "are") sitting below "
                + "\(low.count == 1 ? "its" : "their") own good range.\(when) "
                + "This is an observation about your calendar and your own "
                + "scores — not advice about your health, and not a claim that "
                + "time off would change either.",
            basis: .signalOffBaseline,
            insight: worst.id,
            metric: nil,
            // ⚠️ **Capped below what a real vital departure reaches.** Within
            // `.signalOffBaseline`, `departures` scores |z|/4 — so a signal two
            // standard deviations out sits at 0.5 and outranks this. A fact
            // about a diary must not lead a group whose subject is measurements.
            strength: Swift.min(0.45,
                                0.2 + 0.25 * Swift.min(1, Double(days) / 365)))]
    }
}
