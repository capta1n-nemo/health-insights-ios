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
        /// A day named on the screen ("Today", "Tuesday"), resolved against
        /// `now`. Nil when the screenshot names no day.
        public var date: Date?

        public var isEmpty: Bool { readings.isEmpty }

        /// The one worth offering to record: a day's total, never an average.
        /// Nil when the screenshot only showed an average — which is a real
        /// answer, and the caller says so rather than substituting.
        public var dayTotal: Reading? {
            readings.first { $0.kind == .dailyTotal }
        }

        /// Everything found that is *not* a day's total, so the UI can show what
        /// it read and why it isn't offering it.
        public var otherReadings: [Reading] {
            readings.filter { $0.kind != .dailyTotal }
        }
    }

    // MARK: - Parsing

    public static func parse(_ text: String, now: Date = Date(),
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
            if result.date == nil, let day = namedDay(in: lower, now: now, calendar: calendar) {
                result.date = day
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
        return result
    }

    /// What the words around a duration say it is.
    ///
    /// Order matters: "daily average" contains "daily", and "average" must win,
    /// or the very number this type exists to protect against would be recorded
    /// as a day's total.
    static func classify(_ context: String) -> Reading.Kind {
        if context.contains("average") { return .dailyAverage }
        if context.contains("week") { return .weeklyTotal }
        if context.contains("today") || context.contains("total screen time")
            || context.contains("screen time") || context.contains("total") {
            return .dailyTotal
        }
        return .unlabelled
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
    static func namedDay(in lower: String, now: Date, calendar: Calendar) -> Date? {
        if lower.contains("today") { return calendar.startOfDay(for: now) }
        if lower.contains("yesterday") {
            return calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: now))
        }
        let names = ["sunday", "monday", "tuesday", "wednesday",
                     "thursday", "friday", "saturday"]
        guard let index = names.firstIndex(where: { lower.contains($0) }) else { return nil }
        // The most recent occurrence of that weekday, today included — a Screen
        // Time screenshot is always about the past.
        let target = index + 1                    // Calendar weekdays are 1-based
        let today = calendar.startOfDay(for: now)
        let current = calendar.component(.weekday, from: today)
        let back = (current - target + 7) % 7
        return calendar.date(byAdding: .day, value: -back, to: today)
    }
}
