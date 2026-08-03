import Foundation

/// Reads a screenshot of Settings ▸ Screen Time.
///
/// ## Why a screenshot is the right answer here
///
/// Apple sandboxes the Screen Time API so no third-party app can read the
/// figures (see `MetricType.screenTimeMinutes`). A picture of the screen is the
/// one route that gets the **exact** numbers with no entitlement, no paid team
/// and none of the iOS 26 threshold bugs — and this app already reads a
/// pathology report the same way, so the machinery exists.
///
/// ## The distinction this type exists to protect
///
/// **"Daily Average" is not a day's screen time**, and the two sit inches apart
/// on the same screen — the average is usually the *larger*, boldest number, so
/// a naive "find the biggest duration" parser would record a week's average as
/// yesterday and quietly bias every night it is later compared against. So every
/// duration found is **classified by the words above or beside it**, and a
/// reading whose kind cannot be established is returned as `.unlabelled` rather
/// than assumed to be a total. The caller shows the reader what was found and
/// which is which; nothing is saved on a guess.
///
/// Pure text in, structured values out — no Vision, no UIKit — so it is fully
/// testable on Linux like `LabReportParser` beside it.
public enum ScreenTimeScreenshotParser {

    /// What span of time a screenshot is about.
    ///
    /// The Screen Time screen has a Week/Day segmented control, and which side
    /// it is on changes what every number on it means — most sharply "Total
    /// Screen Time", which is a day on one and a week on the other.
    public enum Period: Sendable, Equatable {
        /// One named day, at its start.
        case day(Date)
        /// Seven days beginning at this date.
        case week(start: Date)

        /// The first day either way, for filing.
        public var start: Date {
            switch self {
            case let .day(date): return date
            case let .week(start): return start
            }
        }
    }

    public struct Reading: Sendable, Equatable, Identifiable {
        public enum Kind: String, Sendable, Equatable {
            /// One day's total — the number worth recording.
            case dailyTotal
            /// An average across a week. **Not a day.**
            case dailyAverage
            /// A week's total.
            case weeklyTotal
            /// A duration with no words near it that say what it is.
            case unlabelled

            public var displayName: String {
                switch self {
                case .dailyTotal: return "Day's total"
                case .dailyAverage: return "Daily average"
                case .weeklyTotal: return "Week's total"
                case .unlabelled: return "Unlabelled figure"
                }
            }

            /// Whether recording this as a day's screen time is honest.
            public var isADayTotal: Bool { self == .dailyTotal }
        }

        public let kind: Kind
        public let minutes: Double
        /// The words it was found under, so the reader can check the match.
        public let label: String
        public var id: String { "\(kind.rawValue)-\(minutes)-\(label)" }

        public init(kind: Kind, minutes: Double, label: String) {
            self.kind = kind
            self.minutes = minutes
            self.label = label
        }
    }

    public struct Result: Sendable, Equatable {
        public var readings: [Reading] = []
        /// Times the phone was picked up, where the screenshot shows it.
        public var pickups: Int?
        public var notifications: Int?
        /// A day named on the screen ("Today", "Tuesday"), resolved against the
        /// **capture** date. Nil when the screenshot names no day.
        public var date: Date?
        /// The first day of the week a Week-view screenshot is about, from an
        /// explicit range ("20–27 Jul") or a relative phrase ("Last Week").
        public var weekStart: Date?

        /// Which span this screenshot is about, if it could be established.
        ///
        /// A week wins over a day: a Week-view screenshot has weekday letters
        /// down its axis (M Tu W Th…) and `namedDay` will happily resolve one of
        /// them, which would file a whole week's figures onto a single Tuesday.
        public var period: Period? {
            if let weekStart { return .week(start: weekStart) }
            if let date { return .day(date) }
            return nil
        }

        public var isEmpty: Bool { readings.isEmpty }

        /// The one worth offering to record: a day's total, never an average.
        /// Nil when the screenshot only showed an average — which is a real
        /// answer, and the caller says so rather than substituting.
        public var dayTotal: Reading? {
            readings.first { $0.kind == .dailyTotal }
        }

        /// The week's own total, chosen rather than taken first.
        ///
        /// ⚠️ **Taking the first `.weeklyTotal` shipped a five-fold
        /// under-count.** On a Week view the category subtotals
        /// ("Productivity & Finance 43h 14m", "Other 18h 12m") sit *above* the
        /// "Total Screen Time" row, and OCR reads top to bottom — so the first
        /// weekly-looking figure found was a category, and every day split out
        /// of it was a fraction of the truth. The reader's chart topped out at
        /// 4 h on days they had spent 21 h on the phone.
        ///
        /// Two rules, in order. A reading whose own words say "total screen
        /// time" wins outright. Otherwise the **largest** wins, because the
        /// week's total is by construction the sum of its categories and cannot
        /// be smaller than any of them.
        public var weeklyTotal: Reading? {
            let weeklies = readings.filter { $0.kind == .weeklyTotal }
            if let named = weeklies.first(where: {
                $0.label.lowercased().contains("total screen time")
            }) { return named }
            return weeklies.max { $0.minutes < $1.minutes }
        }

        /// The daily average printed on a Week view, which is an independent
        /// statement of the same quantity.
        public var dailyAverage: Reading? {
            readings.first { $0.kind == .dailyAverage }
        }

        /// Whether the week's total and its printed daily average agree.
        ///
        /// **A free cross-check, and the one that would have caught the
        /// under-count above.** Screen Time prints both `total` and
        /// `total ÷ 7`, so any figure claiming to be the weekly total must be
        /// within rounding of seven times the average. A category subtotal is
        /// not, and fails this immediately.
        ///
        /// Returns nil when either figure is missing — unknown is not the same
        /// as disagreeing, and a screenshot cropped past the average is still
        /// perfectly importable.
        public func totalAgreesWithAverage(tolerance: Double = 0.1) -> Bool? {
            guard let weeklyTotal, let dailyAverage, dailyAverage.minutes > 0 else {
                return nil
            }
            let implied = dailyAverage.minutes * 7
            return abs(weeklyTotal.minutes - implied) / implied <= tolerance
        }

        /// Everything found that is *not* a day's total, so the UI can show what
        /// it read and why it isn't offering it.
        public var otherReadings: [Reading] {
            readings.filter { $0.kind != .dailyTotal }
        }
    }

    // MARK: - Parsing

    /// Read a screenshot's text.
    ///
    /// - Parameter capturedAt: **when the screenshot was taken**, not when it is
    ///   being imported. Every relative phrase on this screen — "Today",
    ///   "Yesterday", "Last Week", a bare weekday — is relative to the moment
    ///   the picture was taken, so anchoring to import time files a screenshot
    ///   from three weeks ago into this week. The parameter is named for the
    ///   thing it must be, because it previously read `now` and every caller
    ///   dutifully passed `Date()`.
    public static func parse(_ text: String, capturedAt: Date,
                            calendar: Calendar = .current) -> Result {
        var result = Result()
        let lines = text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        for (index, line) in lines.enumerated() {
            let lower = line.lowercased()

            // A count, where the label and number may share a line or not.
            if result.pickups == nil, lower.contains("pickup") {
                result.pickups = firstInteger(in: line) ?? nextLineInteger(lines, after: index)
            }
            if result.notifications == nil, lower.contains("notification") {
                result.notifications = firstInteger(in: line)
                    ?? nextLineInteger(lines, after: index)
            }
            // "Show Today" and "Show This Week" are **buttons**, and they name
            // the period you are *not* looking at — the Day view carries "Show
            // Today" above the day it is actually showing, and the Week view
            // carries "Show This Week" above last week's figures. Read as
            // headings they file every retrospective screenshot into the current
            // day or week, which is the exact bug this parser exists to fix,
            // arriving through a different door. Found by a test built from the
            // reader's own screenshots, 2026-08-02.
            if !isPeriodSwitchButton(lower) {
                if result.weekStart == nil,
                   let week = weekStart(in: line, capturedAt: capturedAt, calendar: calendar) {
                    result.weekStart = week
                }
                if result.date == nil,
                   let day = namedDay(in: lower, capturedAt: capturedAt, calendar: calendar) {
                    result.date = day
                }
            }

            guard let minutes = duration(in: line) else { continue }
            // The words that classify it: this line first — Screen Time often
            // renders "Total Screen Time 4h 32m" together — then the line above,
            // which is where a standalone number's heading sits.
            let context = lower + " " + (index > 0 ? lines[index - 1].lowercased() : "")
            result.readings.append(Reading(kind: classify(context),
                                           minutes: minutes,
                                           label: labelText(line, previous: index > 0 ? lines[index - 1] : nil)))
        }

        // A Week view relabels every total on it. "Total Screen Time 99h 33m" is
        // a **week** there, and `classify` reads it as a day because the words
        // are identical to the Day view's — so on a real weekly screenshot the
        // parser would have offered ninety-nine hours as one day's screen time.
        // Reclassified here rather than in `classify`, which sees one line at a
        // time and cannot know which side of the segmented control it is on.
        if result.weekStart != nil {
            result.readings = result.readings.map { reading in
                reading.kind == .dailyTotal
                    ? Reading(kind: .weeklyTotal, minutes: reading.minutes, label: reading.label)
                    : reading
            }
        }
        return result
    }

    /// What the words around a duration say it is.
    ///
    /// Order matters: "daily average" contains "daily", and "average" must win,
    /// or the very number this type exists to protect against would be recorded
    /// as a day's total.
    ///
    /// ## The Day view does not say "Total Screen Time"
    ///
    /// It says **"Yesterday, 2 August"** with the figure underneath, and the
    /// only "Total Screen Time" row on the whole feature is on the *Week* view.
    /// So the original list of day words — which was built around that row —
    /// classified a real day's total as `.unlabelled` and told the reader to
    /// "open a single day in Screen Time and screenshot that", which is what
    /// they had just done. Caught on the device, 2026-08-02, from a screenshot
    /// reading "Yesterday, 2 August / 21h 1m".
    ///
    /// ⚠️ Known false positive: an app called "Monday" in the Most Used list
    /// puts a weekday above a duration. `Result.dayTotal` takes the *first*
    /// day-classified reading and the heading is at the top of the screen, so it
    /// wins in practice — and nothing is saved without the reader confirming it.
    static func classify(_ context: String) -> Reading.Kind {
        if context.contains("average") { return .dailyAverage }
        if context.contains("week") { return .weeklyTotal }
        if namesADay(context) || context.contains("total screen time")
            || context.contains("screen time") || context.contains("total") {
            return .dailyTotal
        }
        return .unlabelled
    }

    /// Whether a line is one of Screen Time's "jump to the current period"
    /// buttons rather than a heading.
    ///
    /// Matched on the whole line rather than a substring anywhere, because
    /// "Show This Week" can share an OCR line with the "Screen Time" title
    /// beside it — so the test is that the line *contains the button's phrase*,
    /// and the phrase itself is specific enough not to appear in a heading.
    /// A real heading is "Last Week's Average" or "Yesterday, 2 August";
    /// neither contains "show".
    static func isPeriodSwitchButton(_ lower: String) -> Bool {
        lower.contains("show today") || lower.contains("show this week")
            || lower.contains("show last week")
    }

    /// Whether these words head up a single day.
    static func namesADay(_ context: String) -> Bool {
        if context.contains("today") || context.contains("yesterday") { return true }
        let names = ["sunday", "monday", "tuesday", "wednesday",
                     "thursday", "friday", "saturday"]
        return names.contains { context.contains($0) }
    }

    private static func labelText(_ line: String, previous: String?) -> String {
        // The words without the duration, or the line above when this line is
        // only a number.
        let stripped = line.filter { !"0123456789hm ".contains($0) }
        if stripped.count >= 3 { return line }
        return previous ?? line
    }

    /// `4h 32m`, `4 h 32 m`, `4h32m`, `32m`, `4h`. Hand-rolled rather than a
    /// regex so it behaves identically on Linux, where this package's tests run.
    ///
    /// Returns nil where no duration is present — a bare number is *not* a
    /// duration, because on this screen a bare number is a pickup count.
    static func duration(in line: String) -> Double? {
        var hours: Double?
        var minutes: Double?
        var current = ""
        for character in line.lowercased() {
            if character.isNumber {
                current.append(character)
                continue
            }
            if character == "h", let value = Double(current) {
                hours = (hours ?? 0) + value
                current = ""
                continue
            }
            if character == "m", let value = Double(current) {
                // Guard against "m" from a word like "min" being double-read —
                // the digits are consumed either way, so this is idempotent.
                minutes = (minutes ?? 0) + value
                current = ""
                continue
            }
            if !character.isWhitespace { current = "" }
        }
        guard hours != nil || minutes != nil else { return nil }
        return (hours ?? 0) * 60 + (minutes ?? 0)
    }

    static func firstInteger(in line: String) -> Int? {
        var digits = ""
        for character in line {
            if character.isNumber { digits.append(character) }
            else if !digits.isEmpty { break }
        }
        return Int(digits)
    }

    private static func nextLineInteger(_ lines: [String], after index: Int) -> Int? {
        guard index + 1 < lines.count else { return nil }
        // Only when that line is *only* a number, so a following heading is
        // never mistaken for the count.
        let next = lines[index + 1].trimmingCharacters(in: .whitespaces)
        guard next.allSatisfy({ $0.isNumber || $0 == "," }) else { return nil }
        return Int(next.replacingOccurrences(of: ",", with: ""))
    }

    /// "Today" or a weekday name, resolved to an actual date.
    ///
    /// Relative to **capture**, so a screenshot taken on a Tuesday three weeks
    /// ago and imported today still means that Tuesday.
    static func namedDay(in lower: String, capturedAt: Date, calendar: Calendar) -> Date? {
        if lower.contains("today") { return calendar.startOfDay(for: capturedAt) }
        if lower.contains("yesterday") {
            return calendar.date(byAdding: .day, value: -1,
                                 to: calendar.startOfDay(for: capturedAt))
        }
        let names = ["sunday", "monday", "tuesday", "wednesday",
                     "thursday", "friday", "saturday"]
        guard let index = names.firstIndex(where: { lower.contains($0) }) else { return nil }
        // The most recent occurrence of that weekday, capture day included — a
        // Screen Time screenshot is always about the past.
        let target = index + 1                    // Calendar weekdays are 1-based
        let captureDay = calendar.startOfDay(for: capturedAt)
        let current = calendar.component(.weekday, from: captureDay)
        let back = (current - target + 7) % 7
        return calendar.date(byAdding: .day, value: -back, to: captureDay)
    }

    // MARK: - Weeks

    /// The first day of the week a line is about, from either shape Screen Time
    /// uses for its heading.
    ///
    /// - **Relative**: "Last Week's Average", "This Week".
    /// - **Explicit**: "20–27 Jul Average", "20 - 26 Jul", "Jul 20 – 26".
    ///
    /// Anchored on the **start** day and always seven days long. Apple's own
    /// label is ambiguous about its end — the user's screenshot reads
    /// "20–27 Jul" for a week whose average is its total ÷ 7, and 20 Jul 2026 is
    /// a Monday, so the 27 is an exclusive end. Rather than guess which
    /// convention a given iOS build uses, the end is read only as a
    /// plausibility check: six or seven days past the start is a week, anything
    /// else is not a range this understands.
    static func weekStart(in line: String, capturedAt: Date,
                          calendar: Calendar) -> Date? {
        let lower = line.lowercased()
        if lower.contains("last week") {
            guard let thisWeek = startOfWeek(containing: capturedAt, calendar: calendar) else {
                return nil
            }
            return calendar.date(byAdding: .day, value: -7, to: thisWeek)
        }
        if lower.contains("this week") {
            return startOfWeek(containing: capturedAt, calendar: calendar)
        }
        return explicitRange(lower, capturedAt: capturedAt, calendar: calendar)
    }

    /// The week's first day under the calendar's own `firstWeekday`.
    ///
    /// Not hard-coded to Monday even though the screenshots show M first: that
    /// is a fact about the reader's locale, and the calendar already carries it.
    static func startOfWeek(containing date: Date, calendar: Calendar) -> Date? {
        let day = calendar.startOfDay(for: date)
        let weekday = calendar.component(.weekday, from: day)
        let back = (weekday - calendar.firstWeekday + 7) % 7
        return calendar.date(byAdding: .day, value: -back, to: day)
    }

    /// English month names, which is what these screenshots are in. A locale
    /// whose Screen Time renders another language returns nil here and falls
    /// back to the reader confirming the week by hand — wrong is worse than
    /// absent for something that files a fortnight of data.
    private static let months = ["jan", "feb", "mar", "apr", "may", "jun",
                                 "jul", "aug", "sep", "oct", "nov", "dec"]

    private static func explicitRange(_ lower: String, capturedAt: Date,
                                      calendar: Calendar) -> Date? {
        let found = monthOccurrences(lower)
        guard let firstMonth = found.first else { return nil }
        let numbers = integers(in: lower).filter { $0 >= 1 && $0 <= 31 }
        // **A single date is not a range.** "Tuesday, 5 August" is the Day
        // view's heading, and reading it as a week relabels that day's total as
        // a week's — which is exactly the confusion the reclassification pass
        // above exists to create, pointed the wrong way.
        guard numbers.count >= 2 else { return nil }

        guard let start = resolve(day: numbers[0], month: firstMonth,
                                  onOrBefore: capturedAt, calendar: calendar) else { return nil }
        // A range can cross a month ("28 Dec – 3 Jan"), in which case the second
        // month name belongs to the end.
        let endMonth = found.count >= 2 ? found[1] : firstMonth
        guard let end = resolve(day: numbers[1], month: endMonth,
                                onOrAfter: start, calendar: calendar),
              let span = calendar.dateComponents([.day], from: start, to: end).day,
              span == 6 || span == 7 else { return nil }
        return start
    }

    /// Months named in a line, **in the order they appear in the text**.
    ///
    /// Scanning `months` in calendar order instead reads "28 Dec – 3 Jan" as
    /// January, because `firstIndex` finds whichever month comes first in the
    /// *array* rather than in the sentence.
    private static func monthOccurrences(_ lower: String) -> [Int] {
        months.enumerated()
            .compactMap { index, name -> (position: Int, month: Int)? in
                guard let range = lower.range(of: name) else { return nil }
                return (lower.distance(from: lower.startIndex, to: range.lowerBound), index + 1)
            }
            .sorted { $0.position < $1.position }
            .map(\.month)
    }

    /// A day and month resolved to the most recent such date at or before a
    /// bound — the year is not printed on this screen and a Screen Time
    /// screenshot is never about the future.
    private static func resolve(day: Int, month: Int, onOrBefore bound: Date,
                                calendar: Calendar) -> Date? {
        let boundDay = calendar.startOfDay(for: bound)
        let year = calendar.component(.year, from: boundDay)
        for candidateYear in [year, year - 1] {
            guard let date = build(day: day, month: month, year: candidateYear,
                                   calendar: calendar) else { continue }
            if date <= boundDay { return date }
        }
        return nil
    }

    /// The same, forwards — used for a range's end, which may be in the year
    /// after its start.
    private static func resolve(day: Int, month: Int, onOrAfter bound: Date,
                                calendar: Calendar) -> Date? {
        let year = calendar.component(.year, from: bound)
        for candidateYear in [year, year + 1] {
            guard let date = build(day: day, month: month, year: candidateYear,
                                   calendar: calendar) else { continue }
            if date >= bound { return date }
        }
        return nil
    }

    private static func build(day: Int, month: Int, year: Int,
                              calendar: Calendar) -> Date? {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        guard let date = calendar.date(from: components) else { return nil }
        // `date(from:)` rolls an impossible date (31 Feb) into the next month.
        guard calendar.component(.day, from: date) == day,
              calendar.component(.month, from: date) == month else { return nil }
        return calendar.startOfDay(for: date)
    }

    /// Every integer in a string, in order. Hand-rolled for the same reason
    /// `duration(in:)` is — identical behaviour on Linux, where these run.
    static func integers(in text: String) -> [Int] {
        var out: [Int] = []
        var digits = ""
        for character in text {
            if character.isNumber { digits.append(character) }
            else if !digits.isEmpty { out.append(Int(digits) ?? 0); digits = "" }
        }
        if !digits.isEmpty { out.append(Int(digits) ?? 0) }
        return out
    }
}
