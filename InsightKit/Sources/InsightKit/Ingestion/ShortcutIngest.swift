import Foundation

/// Readings handed over by a Shortcuts automation, through the app's own URL
/// scheme.
///
/// ## Why a URL and not an Apple framework
///
/// The interesting health data on a phone is mostly behind a wall. Screen Time
/// is sandboxed so no app can read it (see `MetricType.screenTimeMinutes`);
/// calendar density needs full calendar access; barometric pressure needs
/// WeatherKit and a paid team. **Shortcuts can already reach all of it**, and it
/// can call a URL — so one automation the reader installs once can collect what
/// the app cannot reach for itself and hand it over.
///
/// That makes this a *transport*, not a data type. Anything that is a
/// `MetricType` can arrive this way, today or after some future connector adds
/// one, with no change here and none to the shortcut's shape:
///
/// ```
/// healthinsights://shortcut?date=2026-08-02&screenTimeMinutes=252
/// ```
///
/// Every query item whose name matches a `MetricType` raw value becomes a
/// reading. `date` is optional and applies to all of them.
///
/// ## What it refuses
///
/// - **An unknown key is reported, never guessed at.** A typo'd or renamed
///   metric comes back in `unknownKeys` so the setup screen can say which line
///   of the shortcut is wrong, rather than the reader believing they are
///   collecting something they aren't.
/// - **An implausible value is dropped**, against the metric's own
///   `plausibleRange` — the same guard the provider parsers use. A shortcut that
///   hands over milliseconds where minutes were meant should not put 86 400 000
///   into a baseline.
public enum ShortcutIngest {

    /// The URL host that marks a delivery. `healthinsights://shortcut?…`
    public static let host = "shortcut"

    public struct Result: Sendable, Equatable {
        public var samples: [HealthMetricSample] = []
        /// Query keys that are not a metric — reported so the reader can fix
        /// the shortcut rather than quietly collecting nothing.
        public var unknownKeys: [String] = []
        /// Keys that were a metric but whose value was missing, unparseable or
        /// outside the metric's plausible range.
        public var rejectedKeys: [String] = []

        public var isEmpty: Bool { samples.isEmpty }
    }

    /// Whether this URL is one of ours to read.
    public static func handles(_ url: URL) -> Bool {
        url.host?.lowercased() == host
    }

    public static func parse(_ url: URL, now: Date = Date(),
                             calendar: Calendar = .current) -> Result? {
        guard handles(url),
              let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems else { return nil }

        // One date for the whole delivery. Missing means "today", which is what
        // a shortcut run without an explicit date most likely means.
        let date = items.first { $0.name.lowercased() == "date" }?.value
            .flatMap { parseDate($0, calendar: calendar) } ?? calendar.startOfDay(for: now)

        var result = Result()
        for item in items where item.name.lowercased() != "date" {
            guard let metric = MetricType(rawValue: item.name) else {
                result.unknownKeys.append(item.name)
                continue
            }
            guard let raw = item.value, let value = Double(raw) else {
                result.rejectedKeys.append(item.name)
                continue
            }
            // The same plausibility guard the provider parsers get. A shortcut
            // is a hand-built thing and the commonest failure is a unit slip.
            if let range = metric.plausibleRange, !range.contains(value) {
                result.rejectedKeys.append(item.name)
                continue
            }
            if metric.requiresPositiveValue && value <= 0 {
                result.rejectedKeys.append(item.name)
                continue
            }
            result.samples.append(HealthMetricSample(
                type: metric, value: value, start: date, source: .shortcuts))
        }
        return result
    }

    // MARK: - Building one

    /// The URL that delivers these readings, as `parse` would read it back.
    ///
    /// **The builder exists so that nothing hand-writes this string.** The setup
    /// screen printed the template by interpolating a raw value into a literal,
    /// and the App Intent needed the same string again — two hand-built copies of
    /// a format whose only other definition is the parser above. A round trip
    /// through `parse` is a test; two string literals agreeing is a hope.
    ///
    /// Percent-encoding is `URLComponents`' job rather than ours, which also
    /// means a metric raw value that ever gains an unusual character keeps
    /// working.
    public static func url(for values: [MetricType: Double],
                           on date: Date,
                           calendar: Calendar = .current) -> URL? {
        var components = URLComponents()
        components.scheme = "healthinsights"
        components.host = host
        // Sorted so the same readings always produce the same URL — a template
        // the reader is looking at should not reshuffle itself, and a test can
        // then assert on the whole string.
        components.queryItems = [URLQueryItem(name: "date",
                                              value: dateString(date, calendar: calendar))]
            + values.keys.sorted { $0.rawValue < $1.rawValue }.map { metric in
                URLQueryItem(name: metric.rawValue, value: Self.number(values[metric] ?? 0))
            }
        return components.url
    }

    /// The template the setup screen shows, with `VALUE` where the reader wires
    /// the shortcut's own number in and `YYYY-MM-DD` where Shortcuts formats the
    /// date. Same builder, so it cannot drift from what the parser accepts.
    public static func urlTemplate(for metrics: [MetricType]) -> String {
        let query = (["date=YYYY-MM-DD"] + metrics.map { "\($0.rawValue)=VALUE" })
            .joined(separator: "&")
        return "healthinsights://\(host)?\(query)"
    }

    /// `yyyy-MM-dd` for a date, built from components for the same reason
    /// `parseDate` is: `DateFormatter`'s locale-aware paths are Darwin-only in
    /// places, and this package's tests run on Linux.
    ///
    /// Zero-padded by hand rather than with a format string — `String(format:)`
    /// is available but this is three integers and the padding is the whole of
    /// the requirement.
    public static func dateString(_ date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        let year = parts.year ?? 0, month = parts.month ?? 1, day = parts.day ?? 1
        func pad(_ value: Int, _ width: Int) -> String {
            let digits = String(value)
            return digits.count >= width ? digits
                : String(repeating: "0", count: width - digits.count) + digits
        }
        return "\(pad(year, 4))-\(pad(month, 2))-\(pad(day, 2))"
    }

    /// A number the parser's `Double(_:)` will read back exactly, without an
    /// exponent or a thousands separator.
    static func number(_ value: Double) -> String {
        value == value.rounded() && abs(value) < 1e15
            ? String(Int(value.rounded()))
            : String(value)
    }

    /// `yyyy-MM-dd` or a full ISO-8601 instant — the two shapes Shortcuts'
    /// "Format Date" action produces without the reader having to think.
    ///
    /// Built from components rather than a `DateFormatter`: this package's tests
    /// run on Linux, where several Foundation formatter paths are Darwin-only,
    /// and a date parser that cannot be tested is not one worth having.
    static func parseDate(_ text: String, calendar: Calendar) -> Date? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        let datePart = trimmed.prefix(10)
        let bits = datePart.split(separator: "-")
        guard bits.count == 3, let y = Int(bits[0]), let m = Int(bits[1]),
              let d = Int(bits[2]), (1...12).contains(m), (1...31).contains(d) else {
            return nil
        }
        return calendar.date(from: DateComponents(year: y, month: m, day: d))
    }
}
