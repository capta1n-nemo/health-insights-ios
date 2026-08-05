import Foundation

/// A measurement the app has imported but does **not** yet model as a canonical
/// `MetricType`. Every connected platform can produce data we haven't wired into
/// insights or the vitals catalogue yet (new HealthKit types, extra Oura/Withings
/// fields, and — in future — nutrition, medication, environment). Rather than
/// dropping it, we keep it verbatim here so it shows in the Vitals ▸ "Other data"
/// section for review, and is available to power more accurate insights later.
///
/// `value` is a `RawValue`, not a `Double`: providers send strings and booleans
/// as well as numbers, and the string ones are often the most meaningful field
/// in the payload (Oura's resilience `level`, its sleep-phase hypnogram). It
/// encodes as a bare JSON scalar, so caches written when this was a `Double`
/// still decode.
public struct RawMetricSample: Codable, Sendable, Identifiable, Hashable {
    public let id: UUID
    /// Stable native identifier, e.g. "HKQuantityTypeIdentifierDietaryCaffeine"
    /// or "oura.daily_activity.equivalent_walking_distance".
    public let identifier: String
    /// Human-readable name derived from the identifier.
    public let displayName: String
    public let value: RawValue
    public let unit: String
    public let start: Date
    public let end: Date
    public let source: MetricSource

    /// The number to plot, or nil for free text.
    public var numericValue: Double? { value.doubleValue }

    public init(id: UUID = UUID(), identifier: String, displayName: String,
                value: RawValue, unit: String, start: Date, end: Date? = nil,
                source: MetricSource) {
        self.id = id
        self.identifier = identifier
        self.displayName = displayName
        self.value = value
        self.unit = unit
        self.start = start
        self.end = end ?? start
        self.source = source
    }

    /// Numeric convenience for the many call sites that genuinely do have a
    /// number in hand (HealthKit quantities, Withings measures).
    public init(id: UUID = UUID(), identifier: String, displayName: String,
                value: Double, unit: String, start: Date, end: Date? = nil,
                source: MetricSource) {
        self.init(id: id, identifier: identifier, displayName: displayName,
                  value: .number(value), unit: unit, start: start, end: end, source: source)
    }

    /// A value ready for a list row, with its unit where it has one.
    public var formattedValue: String {
        let text = value.displayString
        return unit.isEmpty ? text : "\(text) \(unit)"
    }
}

/// A group of raw samples sharing one identifier, for the "Other data" browser.
public struct RawMetricGroup: Identifiable, Sendable {
    public let id: String            // the identifier
    public let displayName: String
    public let unit: String
    public let samples: [RawMetricSample]   // newest first
    public var latest: RawMetricSample? { samples.first }
    public var sources: Set<String> { Set(samples.map(\.source.displayName)) }

    /// Whether this group can be drawn as a line. Text groups are listed, not
    /// charted; a categorical one is shown as its sequence of states.
    public var isPlottable: Bool { samples.contains { $0.numericValue != nil } }

    /// Distinct text values, newest first — the state history of a categorical
    /// field such as Oura's resilience level.
    public var distinctTextValues: [String] {
        var seen = Set<String>()
        var out: [String] = []
        for sample in samples {
            guard case .text(let s) = sample.value, !seen.contains(s) else { continue }
            seen.insert(s)
            out.append(s)
        }
        return out
    }

    public init(id: String, displayName: String, unit: String, samples: [RawMetricSample]) {
        self.id = id; self.displayName = displayName; self.unit = unit; self.samples = samples
    }

    // MARK: - Providers that write zero where they mean "nothing"

    /// Identifiers whose exact zeros are a provider's placeholder rather than a
    /// reading, and which the reader's own record proves it for.
    ///
    /// **Keyed on the identifier, and an earlier draft keyed on the unit —
    /// which independent review refuted before it shipped.** "A °C series
    /// cannot read zero" sounds like a law and is false three ways:
    ///
    /// - `HKQuantityTypeIdentifierWaterTemperature` arrives through this same
    ///   raw lane, and a 0 °C reading there is a cold plunge. Censoring it
    ///   would be exactly the dishonesty this fix exists to correct, pointed at
    ///   a different series.
    /// - HealthKit converts on read using the **reader's preferred unit**, so a
    ///   placeholder written as 0 °C reads as 32 under a Fahrenheit preference
    ///   and the rule silently stops working, with no failing test.
    /// - Oura's temperature *deviation* is also in °C, and there zero means
    ///   "exactly at your baseline" — a real and common night.
    ///
    /// So the rule names series, not units. Adding one requires evidence from
    /// the data that the zeros are placeholders: in the reader's export,
    /// basal body temperature carries 35 exact zeros in 136 records, 26%, in a
    /// series whose non-zero values never approach zero.
    public static let placeholderZeroIdentifiers: Set<String> = [
        "HKQuantityTypeIdentifierBasalBodyTemperature",
    ]

    /// Whether this group's exact zeros are placeholders.
    public var zerosArePlaceholders: Bool {
        Self.placeholderZeroIdentifiers.contains(id)
    }

    /// Readings that are really "no reading", newest first.
    public var placeholderZeros: [RawMetricSample] {
        guard zerosArePlaceholders else { return [] }
        return samples.filter { $0.numericValue == 0 }
    }

    /// The samples worth reading — placeholders removed.
    ///
    /// Everything that describes this series to the reader goes through here:
    /// the chart, the min, and `latestReal` below. A detector fed 26% zeros
    /// would report a body temperature collapse that never happened.
    public var realSamples: [RawMetricSample] {
        guard zerosArePlaceholders else { return samples }
        return samples.filter { $0.numericValue != 0 }
    }

    /// The newest actual reading.
    ///
    /// **Separate from `latest` on purpose, and both are needed.** `latest` is
    /// the newest row this identifier produced, which is the right answer for
    /// "when did this last report"; `latestReal` is the newest row that means
    /// anything, which is the right answer for "what is my temperature". The
    /// Data tab and the export both showed `latest` and so both could print a
    /// flat 0 beside a min of 35.19 — internally contradictory on one row.
    public var latestReal: RawMetricSample? { realSamples.first }

    // MARK: - Readings this series' own history says cannot be right

    /// How far from its own median a reading has to sit before it is called a
    /// unit slip rather than a big day.
    ///
    /// Twenty. The slips that actually happen are **powers of a thousand**
    /// (grams for milligrams, milligrams for micrograms) or sixty (seconds for
    /// minutes), and the largest genuine day-to-day swing in anything here is
    /// nearer three. Twenty sits in the empty space between them, so a hard
    /// training day is never flagged and a factor-of-1000 slip always is.
    public static let unitSlipFactor = 20.0

    /// Below this many readings there is no "typical" to judge against, and two
    /// readings that disagree are not evidence that either is wrong.
    public static let minimumHistoryForSuspicion = 5

    /// The reader's export carried **Vitamin A: 170,000 mcg** — about
    /// fifty-seven times the tolerable upper intake, and a number no food
    /// produces. It came in through a chain the app does not control (a shortcut
    /// writing into Apple Health), and it sat in the Data tab looking exactly
    /// like a measurement.
    ///
    /// **A plausible range per analyte is not available and never will be** —
    /// this is the *unmodelled* catalogue, whose whole point is holding data
    /// nobody has written a spec for, and there are already 130 such series from
    /// Oura alone. So the judgement is self-referential and needs no catalogue:
    /// **a reading is suspect when its own series says so.**
    ///
    /// The median rather than the mean, because the outlier is in the sample it
    /// is being judged against and a mean of 800, 800, 800 and 170,000 is 43,100
    /// — which the outlier itself would then sit inside four times over.
    ///
    /// Flagged in both directions: a milligram figure recorded in grams is a
    /// thousand times too small, and reads as a series that quietly stopped
    /// meaning anything rather than as an obvious spike.
    public var suspectValues: Set<UUID> {
        // A named pair rather than a tuple: `\.0` and `\.1` are key paths on a
        // tuple element, which do not compile. It is a repo lint precisely
        // because it has cost a CI round trip more than once.
        struct Reading { let id: UUID; let value: Double }
        let numeric = samples.compactMap { sample in
            sample.numericValue.map { Reading(id: sample.id, value: $0) }
        }
        guard numeric.count >= Self.minimumHistoryForSuspicion,
              let median = Baseline.quantile(0.5, of: numeric.map(\.value)),
              median > 0 else { return [] }
        let high = median * Self.unitSlipFactor
        let low = median / Self.unitSlipFactor
        return Set(numeric.filter { $0.value > high || ($0.value > 0 && $0.value < low) }
            .map(\.id))
    }

    /// One sentence for the reader, or nil where nothing looks wrong.
    ///
    /// Deliberately says *check it* rather than *it is wrong*: the app cannot
    /// know, and a series that genuinely jumps a hundredfold is possible even if
    /// it is usually a slip. It also names the multiple, because "1000× your
    /// usual" is what makes somebody recognise a unit mistake.
    public var suspicionNote: String? {
        let suspects = suspectValues
        guard !suspects.isEmpty,
              let median = Baseline.quantile(0.5, of: samples.compactMap(\.numericValue)),
              median > 0,
              let worst = samples.filter({ suspects.contains($0.id) })
                .compactMap(\.numericValue)
                .max(by: { abs(log($0 / median)) < abs(log($1 / median)) })
        else { return nil }

        let multiple = worst > median ? worst / median : median / worst
        let direction = worst > median ? "larger" : "smaller"
        let count = suspects.count
        let subject = count == 1 ? "One reading here is"
            : "\(count) readings here are"
        return "\(subject) far outside the rest of this series — the furthest is about "
            + "\(Self.roundedMultiple(multiple))× \(direction) than your usual. That is the "
            + "shape of a unit mix-up upstream rather than a measurement. Worth checking "
            + "wherever it came from."
    }

    /// "1000" rather than "1000.4" — a multiple is being used to make somebody
    /// recognise a power of ten, so the digits after it are noise.
    static func roundedMultiple(_ value: Double) -> String {
        value >= 100 ? String(Int((value / 10).rounded() * 10))
            : value >= 10 ? String(Int(value.rounded()))
            : String(format: "%.1f", value)
    }
}

public extension Array where Element == RawMetricSample {
    /// Group by identifier, each group's samples newest-first, groups sorted by
    /// display name.
    func groupedByIdentifier() -> [RawMetricGroup] {
        Dictionary(grouping: self, by: \.identifier).map { key, value in
            let sorted = value.sorted { $0.start > $1.start }
            return RawMetricGroup(id: key,
                                  displayName: sorted.first?.displayName ?? key,
                                  unit: sorted.first?.unit ?? "",
                                  samples: sorted)
        }.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    /// Samples within a timeframe (nil window = all).
    func within(_ timeframe: Timeframe, now: Date = Date()) -> [RawMetricSample] {
        guard let start = timeframe.startDate(from: now) else { return self }
        return filter { $0.start >= start }
    }
}
