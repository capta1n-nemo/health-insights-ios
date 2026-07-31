import Foundation

/// What is actually in this person's data, as a report they can hand back.
///
/// This exists to close a blind spot that has cost this project real time:
/// nobody working on the app can see the user's Vitals tab, so every "what data
/// do we have?" question has been answered from the *parsers* rather than from
/// the data. That has been wrong before — circadian consistency sat recorded as
/// blocked for several sessions on a bedtime that was in every payload and being
/// discarded at ingest. A rule worth keeping: *"we don't have X" is a claim
/// about the code until somebody has looked at the data.*
///
/// It lives in InsightKit rather than in the view for the usual reason: it is
/// pure formatting over values, it can be quietly wrong, and the app target has
/// no tests.
///
/// **Never emits credentials.** It is handed samples and raw groups, and there is
/// no path from either to a token or a keychain item.
public enum DataInventory {

    /// One source's contribution to one signal.
    ///
    /// The summary row merges every source into a single distribution, and that
    /// turned out to hide the answer to the question the report exists to
    /// settle. The nap fix was to be proved by `restingHeartRate`'s maximum
    /// falling from 119 — but with Apple Watch, Oura and Shortcuts all feeding
    /// that metric, a merged maximum cannot say *which* of them produced it, so
    /// the fix could be neither confirmed nor refuted from the report designed
    /// to do it. One number per source is what makes a claim like that decidable.
    public struct SourceStat: Sendable, Equatable {
        public let source: String
        public let count: Int
        public let first: Date?
        public let last: Date?
        public let min: Double?
        public let median: Double?
        public let max: Double?
    }

    /// One line per signal. Small enough to paste into a conversation, which is
    /// the whole point — the full export is a file nobody can read.
    public struct Row: Sendable, Equatable {
        public let identifier: String
        public let displayName: String
        public let unit: String
        public let count: Int
        public let first: Date?
        public let last: Date?
        public let sources: [String]
        /// nil for a text field, which has no distribution.
        public let min: Double?
        public let median: Double?
        public let max: Double?
        public let latest: String
        /// Distinct values for a categorical field, e.g. Oura's resilience level.
        public let states: [String]
        /// Whether an insight reads this signal today.
        public let isModelled: Bool
        /// Per-source distributions, sorted by source name. Empty when the
        /// signal has only one source, because then the summary row already
        /// attributes itself and a second table would only add noise.
        public let bySource: [SourceStat]
    }

    // MARK: - Building

    public static func rows(samples: [HealthMetricSample],
                            rawGroups: [RawMetricGroup]) -> [Row] {
        modelledRows(samples) + rawRows(rawGroups)
    }

    /// The canonical metrics — the ones insights can already read.
    static func modelledRows(_ samples: [HealthMetricSample]) -> [Row] {
        Dictionary(grouping: samples, by: \.type)
            .map { type, group in
                let values = group.map(\.value).sorted()
                let byDate = group.sorted { $0.start < $1.start }
                return Row(
                    identifier: type.rawValue,
                    displayName: type.displayName,
                    unit: type.unit,
                    count: group.count,
                    first: byDate.first?.start,
                    last: byDate.last?.start,
                    sources: distinctSources(group.map(\.source)),
                    min: values.first,
                    median: median(values),
                    max: values.last,
                    latest: byDate.last.map { format($0.value) } ?? "—",
                    states: [],
                    isModelled: true,
                    bySource: sourceStats(group))
            }
            .sorted { $0.displayName < $1.displayName }
    }

    /// Everything imported but not yet modelled — the "Other data" section of the
    /// Vitals tab. **This is the half nobody working on the app has ever seen**,
    /// and the reason the report exists.
    static func rawRows(_ groups: [RawMetricGroup]) -> [Row] {
        groups.map { group in
            let numeric = group.samples.compactMap(\.numericValue).sorted()
            let byDate = group.samples.sorted { $0.start < $1.start }
            return Row(
                identifier: group.id,
                displayName: group.displayName,
                unit: group.unit,
                count: group.samples.count,
                first: byDate.first?.start,
                last: byDate.last?.start,
                sources: group.sources.sorted(),
                min: numeric.first,
                median: median(numeric),
                max: numeric.last,
                latest: byDate.last?.formattedValue ?? "—",
                // Capped: a categorical field with hundreds of distinct values
                // is a free-text field wearing a disguise, and listing them all
                // would bury the report.
                states: Array(group.distinctTextValues.prefix(12)),
                isModelled: false,
                // Unmodelled fields are provider-namespaced already
                // (`oura.sleep.*`, `withings.measure.*`), so the identifier
                // names the source and there is nothing to disambiguate.
                bySource: [])
        }
        .sorted { $0.displayName < $1.displayName }
    }

    // MARK: - The report

    public static func markdown(samples: [HealthMetricSample],
                                rawGroups: [RawMetricGroup],
                                generatedAt: Date = Date(),
                                calendar: Calendar = .current) -> String {
        let modelled = modelledRows(samples)
        let raw = rawRows(rawGroups)
        var out: [String] = []

        out.append("# Health Insights — data inventory")
        out.append("")
        out.append("Generated \(day(generatedAt, calendar)). "
                   + "**\(modelled.count) modelled signals**, "
                   + "**\(raw.count) imported but not yet modelled**, "
                   + "\(samples.count + raw.reduce(0) { $0 + $1.count }) readings in total.")
        out.append("")
        out.append("This is the user's own health data, exported by them on purpose. "
                   + "It contains no credentials, tokens or account identifiers.")
        out.append("")

        out.append("## Signals an insight can already read")
        out.append("")
        out.append(table(modelled, calendar: calendar))
        out.append("")

        // Only the signals that merge several sources, because only they can
        // hide which source produced an outlier. Listing the single-source ones
        // would double the report to restate its own Sources column.
        let multi = modelled.filter { !$0.bySource.isEmpty }
        if !multi.isEmpty {
            out.append("### Which source produced which number")
            out.append("")
            out.append("Only the signals with more than one source. A merged "
                       + "minimum or maximum cannot be traced, and tracing one "
                       + "is how a parser fix gets proved or disproved.")
            out.append("")
            out.append("| Signal | Source | N | First | Last | Min | Median | Max |")
            out.append("| --- | --- | ---: | --- | --- | ---: | ---: | ---: |")
            for row in multi {
                for stat in row.bySource {
                    out.append("| \(row.displayName) | \(stat.source) | \(stat.count) "
                        + "| \(stat.first.map { day($0, calendar) } ?? "—") "
                        + "| \(stat.last.map { day($0, calendar) } ?? "—") "
                        + "| \(stat.min.map(format) ?? "—") "
                        + "| \(stat.median.map(format) ?? "—") "
                        + "| \(stat.max.map(format) ?? "—") |")
                }
            }
            out.append("")
        }

        out.append("## Imported, not yet modelled")
        out.append("")
        if raw.isEmpty {
            out.append("_Nothing — every imported field is a first-class metric._")
        } else {
            out.append("These arrive from a provider and are catalogued, but no "
                       + "insight reads them. **This is the list to mine.**")
            out.append("")
            out.append(table(raw, calendar: calendar))
            let categorical = raw.filter { !$0.states.isEmpty }
            if !categorical.isEmpty {
                out.append("")
                out.append("### Categorical fields, and the states they take")
                out.append("")
                for row in categorical {
                    out.append("- **\(row.displayName)** (`\(row.identifier)`): "
                               + row.states.joined(separator: ", "))
                }
            }
        }
        out.append("")

        out.append("## Where it came from")
        out.append("")
        let allSources = Set(modelled.flatMap(\.sources)).union(raw.flatMap(\.sources))
        for source in allSources.sorted() {
            let n = modelled.filter { $0.sources.contains(source) }.count
                + raw.filter { $0.sources.contains(source) }.count
            out.append("- **\(source)** — \(n) signal\(n == 1 ? "" : "s")")
        }

        return out.joined(separator: "\n") + "\n"
    }

    private static func table(_ rows: [Row], calendar: Calendar) -> String {
        guard !rows.isEmpty else { return "_None._" }
        var lines = ["| Signal | Identifier | Unit | N | First | Last | Sources | Min | Median | Max | Latest |",
                     "| --- | --- | --- | ---: | --- | --- | --- | ---: | ---: | ---: | ---: |"]
        for r in rows {
            lines.append("| \(r.displayName) | `\(r.identifier)` | \(r.unit.isEmpty ? "—" : r.unit) "
                + "| \(r.count) | \(r.first.map { day($0, calendar) } ?? "—") "
                + "| \(r.last.map { day($0, calendar) } ?? "—") "
                + "| \(r.sources.isEmpty ? "—" : r.sources.joined(separator: ", ")) "
                + "| \(r.min.map(format) ?? "—") | \(r.median.map(format) ?? "—") "
                + "| \(r.max.map(format) ?? "—") | \(r.latest) |")
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Full export

    /// Every reading, for the questions the inventory can't answer.
    ///
    /// Deliberately a separate call: on a real history this is tens of megabytes,
    /// which is a file to share and never something to paste.
    public static func fullExportJSON(samples: [HealthMetricSample],
                                      rawGroups: [RawMetricGroup]) throws -> Data {
        struct Export: Encodable {
            let schemaVersion = 1
            let samples: [HealthMetricSample]
            let unmodelled: [RawMetricSample]
        }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(Export(samples: samples,
                                         unmodelled: rawGroups.flatMap(\.samples)))
    }

    // MARK: - Helpers

    /// `y-MM-dd` from calendar components rather than a `DateFormatter`.
    ///
    /// Deliberate: `Date.formatted` and friends have bitten this package before
    /// by being Darwin-only, and InsightKit's whole test suite runs on Linux.
    /// Components arithmetic is available everywhere and is deterministic.
    static func day(_ date: Date, _ calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        guard let y = c.year, let m = c.month, let d = c.day else { return "—" }
        return String(format: "%04d-%02d-%02d", y, m, d)
    }

    static func median(_ sorted: [Double]) -> Double? {
        guard !sorted.isEmpty else { return nil }
        let mid = sorted.count / 2
        return sorted.count.isMultiple(of: 2)
            ? (sorted[mid - 1] + sorted[mid]) / 2
            : sorted[mid]
    }

    static func format(_ value: Double) -> String {
        if value == value.rounded() && abs(value) < 1e9 {
            return String(format: "%.0f", value)
        }
        return String(format: "%.2f", value)
    }

    /// Per-source distributions for one metric's samples.
    ///
    /// Returns empty for a single-source signal on purpose — see `Row.bySource`.
    /// Keyed on `displayName` rather than `id` so it lines up with the `Sources`
    /// column, which is what a reader is cross-referencing.
    static func sourceStats(_ group: [HealthMetricSample]) -> [SourceStat] {
        let byName = Dictionary(grouping: group, by: \.source.displayName)
        guard byName.count > 1 else { return [] }
        return byName.map { name, samples in
            let values = samples.map(\.value).sorted()
            let byDate = samples.sorted { $0.start < $1.start }
            return SourceStat(source: name,
                              count: samples.count,
                              first: byDate.first?.start,
                              last: byDate.last?.start,
                              min: values.first,
                              median: median(values),
                              max: values.last)
        }
        .sorted { $0.source < $1.source }
    }

    static func distinctSources(_ sources: [MetricSource]) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for source in sources where !seen.contains(source.displayName) {
            seen.insert(source.displayName)
            out.append(source.displayName)
        }
        return out.sorted()
    }
}
