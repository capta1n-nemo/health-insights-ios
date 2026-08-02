import Foundation

/// The judgement machinery behind the cards, as one small markdown document —
/// the third leg beside `DataInventory` and `CardStateExport`.
///
/// The inventory answers *"what data does the app hold?"* and the card export
/// answers *"what is the user being told?"*. This answers *"what was the
/// telling judged **against**?"* — the questions the other two kept stopping
/// short of:
///
/// - **"Not enough history yet to judge this" over six years of readings.**
///   The verdict is honest (the baseline needs recent daily values, not old
///   ones) but unverifiable from outside without the baseline's own numbers:
///   how many days it holds, over what window, against what floor.
/// - **"+31 mmHg after use" with no pool sizes.** Whether that is a measured
///   response or three readings against five is exactly the difference between
///   a finding and noise, and `MetricEffect` has carried the counts all along —
///   they were just never exported.
/// - **A nightly figure that looks wrong.** The midnight-crossing bug class is
///   only visible in *derived* nights laid out per source, which no export
///   showed.
///
/// Size is a design constraint, same as the card export: aggregates and
/// verdicts only, bounded tails, tens of kilobytes on any history.
public enum ModelInternalsExport {

    /// Nights included in the per-source nights table. Enough to see a
    /// date-keying disagreement and a pattern; the full export owns the rest.
    public static let nightsTailDays = 30

    public static func markdown(samples: [HealthMetricSample],
                                events: [SubstanceEvent],
                                raw: [RawMetricSample] = [],
                                buildStamp: String,
                                now: Date = Date(),
                                calendar: Calendar = .current) -> String {
        var out: [String] = []
        out.append("# Health Insights — model internals")
        out.append("Generated \(day(now, calendar: calendar)) · build \(buildStamp) · \(samples.count) canonical readings")
        out.append("")
        out.append("_What the cards judge against: the personal baselines behind every "
                   + "\"vs your normal\" figure, the substance comparison pools, and the "
                   + "derived nights. Send this beside \"card outputs\" when the question "
                   + "is why a card judged something, not just what it said._")
        out.append("")

        out.append(contentsOf: floorsSection())
        out.append(contentsOf: baselineSection(samples: samples, now: now, calendar: calendar))
        out.append(contentsOf: substanceSection(samples: samples, events: events, now: now))
        out.append(contentsOf: nightsSection(samples: samples, now: now, calendar: calendar))
        out.append(contentsOf: ouraSegmentsSection(raw: raw, now: now, calendar: calendar))
        return out.joined(separator: "\n")
    }

    /// The constants every verdict below is an application of — quoted from
    /// the code rather than restated, so this section cannot go stale.
    private static func floorsSection() -> [String] {
        [
            "## The floors and windows in force",
            "- Vitals baseline: daily values over the last \(VitalSignsCheck.baselineDays) days; "
                + "no judgement below \(VitalSignsCheck.minimumBaselineDays) days of history "
                + "(that is what \"not enough history yet\" means — it counts *recent* days, "
                + "so years-old readings do not help it).",
            // %g, not the shared one-decimal formatter: 1.25 must not print
            // as "1.2" — a threshold misquoted by the instrument that exists
            // to quote thresholds.
            "- Departure bands: \"to watch\" at |z| ≥ \(String(format: "%g", VitalSignsCheck.watchZ)), "
                + "\"unusual\" at |z| ≥ \(String(format: "%g", VitalSignsCheck.unusualZ)), direction-aware — "
                + "a departure away from the concerning direction costs less.",
            "- Substance comparison: both sides drawn from the last "
                + "\(Int(SubstanceResponseAnalyzer.comparisonWindowDays)) days; a reading counts as "
                + "\"after use\" within \(Int(SubstanceResponseAnalyzer.afterWindow / 3600)) h of a log; "
                + "cumulative load looks back \(SubstanceResponseAnalyzer.loadWindowDays) days.",
            ""
        ]
    }

    /// One row per vital the scan judged today, with the baseline it judged
    /// against — the numbers behind every "vs your normal" on every card.
    private static func baselineSection(samples: [HealthMetricSample], now: Date,
                                        calendar: Calendar) -> [String] {
        let output = VitalSignsCheck.evaluate(samples: samples, now: now, calendar: calendar)
        var out = ["## Baselines — what \"your normal\" is right now"]
        guard !output.readings.isEmpty || !output.stale.isEmpty else {
            out.append("- nothing fresh enough to judge")
            out.append("")
            return out
        }
        if !output.readings.isEmpty {
            out.append("| metric | today | baseline | z | history | verdict | note | source |")
            out.append("|---|---|---|---|---|---|---|---|")
            for r in output.readings {
                let history = "\(r.historyDays) of \(VitalSignsCheck.baselineDays) days"
                    + (r.historyDays < VitalSignsCheck.minimumBaselineDays
                        ? " (needs \(VitalSignsCheck.minimumBaselineDays))" : "")
                out.append("| \(r.metric.displayName) "
                           + "| \(MetricValueFormatter.detailedString(r.value, r.metric)) "
                           + "| \(r.baseline.map { MetricValueFormatter.detailedString($0, r.metric) } ?? "—") "
                           + "| \(r.zScore.map { String(format: "%+.2f", $0) } ?? "—") "
                           + "| \(history) "
                           + "| \(r.status.rawValue) "
                           + "| \(r.note) "
                           + "| \(r.sourceName) |")
            }
        }
        if !output.stale.isEmpty {
            out.append("")
            out.append("Recorded by this user, but not recently enough to describe today:")
            for s in output.stale {
                out.append("- \(s.metric.displayName): "
                           + "\(MetricValueFormatter.detailedString(s.value, s.metric)), "
                           + "last measured \(daysAgo(s.lastMeasured, now: now))")
            }
        }
        out.append("")
        return out
    }

    /// The comparison pools behind the substance card — how many readings sit
    /// on each side of every "after use" delta, and the spread it is judged by.
    private static func substanceSection(samples: [HealthMetricSample],
                                         events: [SubstanceEvent], now: Date) -> [String] {
        var out = ["## Substance comparison pools"]
        guard !events.isEmpty else {
            out.append("- nothing logged, so there is nothing to compare")
            out.append("")
            return out
        }
        let analysis = SubstanceResponseAnalyzer.analyze(events: events, samples: samples, now: now)
        out.append("Recent load \(num(analysis.recentLoad)) (\(analysis.loadBand)) — "
                   + "\(analysis.eventsInWindow) log(s) in the last "
                   + "\(SubstanceResponseAnalyzer.loadWindowDays) days.")
        if analysis.effects.isEmpty {
            out.append("- no metric has enough paired readings inside the window to compare")
        } else {
            out.append("")
            out.append("| metric | clean readings | after-use readings | clean mean | after mean | delta | baseline SD | effect size | adverse? |")
            out.append("|---|---|---|---|---|---|---|---|---|")
            for e in analysis.effects {
                out.append("| \(e.metric.displayName) "
                           + "| \(e.baselineNights) "
                           + "| \(e.affectedNights) "
                           + "| \(num(e.baseline)) "
                           + "| \(num(e.afterUse)) "
                           + "| \(String(format: "%+.1f", e.deltaAbsolute)) "
                           + "| \(String(format: "%.1f", e.baselineSD)) "
                           + "| \(e.effectSize.map { String(format: "%.1f", $0) } ?? "— (flat baseline)") "
                           + "| \(e.isAdverse ? "yes" : "no") |")
            }
            out.append("")
            out.append("_A delta resting on a handful of readings on either side is a hint, "
                       + "not a finding — the pool sizes are the thing to check before "
                       + "trusting the number._")
        }
        out.append("")
        return out
    }

    /// The last month of derived nights, one row per night per source — the
    /// layout that makes a date-keying disagreement between sources visible.
    private static func nightsSection(samples: [HealthMetricSample], now: Date,
                                      calendar: Calendar) -> [String] {
        var out = ["## Recent nights, per source (last \(nightsTailDays) days)"]
        let cutoff = now.addingTimeInterval(-Double(nightsTailDays) * 86_400)
        let nightly: [MetricType] = [.sleepDurationHours, .sleepOnset, .sleepEfficiency]
        let recent = samples.filter { nightly.contains($0.type) && $0.start >= cutoff }
        guard !recent.isEmpty else {
            out.append("- no nightly figures inside the window")
            out.append("")
            return out
        }
        // (night, source) → the night's figures. A night the sources disagree
        // about — a duration filed under two different days — shows up here as
        // rows that don't line up.
        struct Key: Hashable { let day: Date; let source: String }
        var byNight: [Key: [MetricType: Double]] = [:]
        for sample in recent {
            let key = Key(day: calendar.startOfDay(for: sample.start),
                          source: sample.source.displayName)
            byNight[key, default: [:]][sample.type] = sample.value
        }
        out.append("| night of | source | duration | onset | efficiency |")
        out.append("|---|---|---|---|---|")
        for (key, values) in byNight.sorted(by: { ($0.key.day, $0.key.source) > ($1.key.day, $1.key.source) }) {
            func cell(_ metric: MetricType) -> String {
                values[metric].map { MetricValueFormatter.detailedString($0, metric) } ?? "—"
            }
            out.append("| \(day(key.day, calendar: calendar)) | \(key.source) "
                       + "| \(cell(.sleepDurationHours)) | \(cell(.sleepOnset)) "
                       + "| \(cell(.sleepEfficiency)) |")
        }
        out.append("")
        return out
    }

    /// The raw Oura sleep records behind the derived nights above — only the
    /// days that need explaining: more than one segment, or any segment the
    /// night parser excludes as a nap.
    ///
    /// Written for the four nights (07-31, 07-29, 07-20, 07-11) that read half
    /// from Oura and whole from Apple Health *after* the same-day-period fix
    /// was installed and the history rebuilt — values byte-identical across a
    /// re-parse, which rules the grouping out and leaves the type filter. The
    /// hypothesis this table settles: those nights' missing hours are records
    /// Oura itself types `late_nap`/`rest` (a morning re-sleep), which
    /// `OuraResponseParser.isNight` excludes by design while Apple Health's
    /// path sums every segment of the night. If that is what the export shows,
    /// the disagreement is two vendors defining "the night" differently — a
    /// convention to choose, not a parser to fix.
    private static func ouraSegmentsSection(raw: [RawMetricSample], now: Date,
                                            calendar: Calendar) -> [String] {
        let cutoff = now.addingTimeInterval(-Double(nightsTailDays) * 86_400)
        let durations = raw.filter {
            $0.identifier == "oura.sleep.total_sleep_duration" && $0.start >= cutoff
        }
        guard !durations.isEmpty else { return [] }
        // Fields of one record share the record's start instant, which is the
        // only join the raw pile keeps.
        let typeByStart = Dictionary(
            raw.filter { $0.identifier == "oura.sleep.type" && $0.start >= cutoff }
                .compactMap { s -> (Date, String)? in
                    guard case .text(let t) = s.value else { return nil }
                    return (s.start, t)
                },
            uniquingKeysWith: { first, _ in first })

        struct Segment { let start: Date; let hours: Double; let type: String }
        let byDay = Dictionary(grouping: durations.compactMap { s -> Segment? in
            guard let seconds = s.numericValue else { return nil }
            return Segment(start: s.start, hours: seconds / 3600,
                           type: typeByStart[s.start] ?? "?")
        }) { calendar.startOfDay(for: $0.start) }

        let needsExplaining = byDay.filter { _, segments in
            segments.count > 1
                || segments.contains { !OuraResponseParser.isNight($0.type) }
        }
        guard !needsExplaining.isEmpty else { return [] }

        var out = ["### Oura sleep segments — days with more than one, or with naps"]
        out.append("_The raw records behind the Oura rows above. `long_sleep` and "
                   + "`sleep` count toward the night, and so does a nap-typed record "
                   + "that begins before noon — Oura closes a night at the first real "
                   + "wake and types a morning re-sleep `late_nap`, and the user ruled "
                   + "that is one night's sleep. Afternoon and evening naps, and rest "
                   + "records with no start time, stay out._")
        out.append("| starts | type | asleep | counted as night? |")
        out.append("|---|---|---|---|")
        for (_, segments) in needsExplaining.sorted(by: { $0.key > $1.key }) {
            for segment in segments.sorted(by: { $0.start < $1.start }) {
                let hour = calendar.component(.hour, from: segment.start)
                let counted: String
                if OuraResponseParser.isNight(segment.type) {
                    counted = "yes"
                } else if OuraResponseParser.countsTowardNight(type: segment.type,
                                                               localStartHour: hour) {
                    counted = "yes — morning re-sleep"
                } else {
                    counted = "no — nap"
                }
                out.append("| \(timestamp(segment.start, calendar: calendar)) "
                           + "| \(segment.type) "
                           + "| \(String(format: "%.1f h", segment.hours)) "
                           + "| \(counted) |")
            }
        }
        out.append("")
        return out
    }

    // MARK: - Formatting, kept Linux-safe (no DateFormatter)

    private static func num(_ value: Double) -> String {
        value == value.rounded() && abs(value) < 10_000
            ? String(Int(value)) : String(format: "%.1f", value)
    }

    private static func day(_ date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d",
                      parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    private static func timestamp(_ date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        return String(format: "%04d-%02d-%02d %02d:%02d",
                      parts.year ?? 0, parts.month ?? 0, parts.day ?? 0,
                      parts.hour ?? 0, parts.minute ?? 0)
    }

    private static func daysAgo(_ date: Date, now: Date) -> String {
        let days = Int(now.timeIntervalSince(date) / 86_400)
        switch days {
        case ..<1: return "today"
        case 1: return "1 day ago"
        default: return "\(days) days ago"
        }
    }
}
