import Foundation

/// Everything the nine cards are actually showing, as one small markdown
/// document — the card-level counterpart of `DataInventory`.
///
/// The inventory answers *"what data does the app hold?"*; this answers
/// *"what is the user actually being told?"*. It exists because those keep
/// diverging in ways nobody working on the app can see: a card can compute a
/// number from a defensible model and still be wrong on this person's data —
/// the substance dial reading 0, a section quietly empty, a weight resting on
/// two paired nights. Recalibrating any of that needs the outputs as shipped,
/// beside the data behind them, from the build that produced them.
///
/// So every card exports its full result — score, headline, confidence,
/// weighting basis, every driver line, every weighted and unweighted share
/// with its own detail string (which is where a card explains *why*, e.g. the
/// load row's "usage is all this number can rest on until there is paired
/// data") — plus, per declared input, whether data exists at all and how much.
/// The build stamp comes first, because "the fix didn't work" and "the fix
/// isn't installed yet" look identical from a screenshot.
///
/// **Size is a design constraint**: the whole point is to be handed to a chat
/// with a ~30 MB upload limit, so this is aggregates and text only — no raw
/// readings (the full export owns those) and a bounded score-history tail.
/// Nine cards land in the tens of kilobytes.
public enum CardStateExport {

    /// Days of score history included per card. Enough to see a trend and a
    /// band change; the stored total is reported so a longer look can be asked
    /// for deliberately.
    public static let historyTailDays = 21

    /// One card's declared input and what the sample set holds for it.
    struct Availability {
        let metric: MetricType
        let count: Int
        let first: Date?
        let last: Date?
        let sources: [String]
    }

    public static func markdown(results: [InsightResult],
                                candidates: [InsightID: [MetricType]],
                                histories: [InsightID: [ScorePoint]],
                                samples: [HealthMetricSample],
                                profile: UserHealthProfile,
                                buildStamp: String,
                                now: Date,
                                calendar: Calendar = .current) -> String {
        var out: [String] = []
        out.append("# Health Insights — card outputs")
        out.append("Generated \(day(now)) · build \(buildStamp) · \(samples.count) canonical readings")
        out.append("")
        out.append("_What each card is showing right now, from the build above. "
                   + "Aggregates and wording only — pair with the data inventory "
                   + "for distributions, or the full export for raw readings._")
        out.append("")

        // Grounding facts, because half the models hinge on them. Values are
        // rendered through each kind's own formatter — the same words the
        // Settings screen shows.
        out.append("## Grounding facts")
        let entered = GroundingKind.allCases.compactMap { kind -> String? in
            guard let input = profile.input(kind) else { return nil }
            let freshness = input.isFresh(asOf: now) ? "" : " · **stale**"
            return "- \(kind.displayName): \(kind.formatted(input.value, asOf: now)) (entered \(day(input.recordedAt))\(freshness))"
        }
        out.append(contentsOf: entered.isEmpty ? ["- none entered"] : entered)
        out.append("")

        // The glance table, then the per-card detail.
        out.append("## Cards at a glance")
        out.append("| card | headline | score | confidence | basis | listed? |")
        out.append("|---|---|---|---|---|---|")
        for result in results {
            out.append("| \(result.title) | \(result.headline) | \(num(result.score)) "
                       + "| \(result.confidence.rawValue) | \(basis(result.weighting)) "
                       + "| \(result.isWorthShowing ? "yes" : "hidden") |")
        }
        out.append("")

        for result in results {
            out.append(contentsOf: card(result,
                                        candidates: candidates[result.id] ?? [],
                                        history: histories[result.id] ?? [],
                                        samples: samples, now: now))
        }
        return out.joined(separator: "\n")
    }

    // MARK: - One card

    private static func card(_ result: InsightResult, candidates: [MetricType],
                             history: [ScorePoint], samples: [HealthMetricSample],
                             now: Date) -> [String] {
        var out: [String] = []
        out.append("## \(result.title)")
        out.append("**\(result.headline)** · score \(num(result.score)) · "
                   + "\(result.confidence.rawValue) confidence · basis: \(basis(result.weighting))"
                   + (result.primaryValue.map { " · primary value \(num($0))" } ?? ""))
        out.append("")
        out.append("> \(result.explanation)")
        out.append("")

        if !result.unmetRequirements.isEmpty {
            out.append("**Unmet requirements:** "
                       + result.unmetRequirements.map(\.kind.displayName).joined(separator: ", "))
            out.append("")
        }

        out.append("### What's driving this")
        for driver in result.driverLines {
            let marker = driver.isNotable == true ? "▲ " : ""
            out.append("- \(marker)\(driver.text)")
        }
        if result.driverLines.isEmpty { out.append("- (no driver lines)") }
        out.append("")

        // The shares exactly as "How this is weighted" draws them, detail
        // strings included — the details are where a card explains itself.
        let weighted = result.weightedFactors.filter { $0.weight > 0 }
        if !weighted.isEmpty {
            out.append("### Weighted shares")
            out.append("| input | share | detail |")
            out.append("|---|---|---|")
            for factor in weighted {
                out.append("| \(factor.name) | \(String(format: "%.1f%%", factor.weight * 100)) | \(factor.detail) |")
            }
            out.append("")
        }
        let unweighted = result.unweightedFactors
        if !unweighted.isEmpty {
            out.append("### Charted, not scored")
            for factor in unweighted {
                out.append("- \(factor.name): \(factor.detail)")
            }
            out.append("")
        }

        // Per declared input: does data exist at all, and how much. This is
        // the row that separates "the model declined" from "there was nothing
        // to read" — the two ways a card goes quiet.
        if !candidates.isEmpty {
            out.append("### Declared inputs and their data")
            out.append("| metric | readings | span | latest | sources |")
            out.append("|---|---|---|---|---|")
            for metric in candidates {
                let a = availability(metric, samples: samples)
                if a.count == 0 {
                    out.append("| \(metric.displayName) | 0 | — | — | — |")
                } else {
                    out.append("| \(metric.displayName) | \(a.count) "
                               + "| \(day(a.first)) → \(day(a.last)) "
                               + "| \(daysAgo(a.last, now: now)) "
                               + "| \(a.sources.joined(separator: ", ")) |")
                }
            }
            out.append("")
        }

        if history.isEmpty {
            out.append("### Score history\n- none stored yet")
        } else {
            out.append("### Score history — \(history.count) days stored, last \(Swift.min(history.count, historyTailDays)):")
            let tail = history.suffix(historyTailDays)
            out.append(tail.map { "\(day($0.date)) \(Int($0.score.rounded()))(\($0.contributorCount))" }
                .joined(separator: " · "))
        }
        out.append("")
        return out
    }

    static func availability(_ metric: MetricType,
                             samples: [HealthMetricSample]) -> Availability {
        let series = samples.samples(of: metric)
        var sources: [String] = []
        for sample in series where !sources.contains(sample.source.displayName) {
            sources.append(sample.source.displayName)
        }
        return Availability(metric: metric, count: series.count,
                            first: series.first?.start, last: series.last?.start,
                            sources: sources)
    }

    /// Exhaustive on purpose, like every switch over an InsightKit enum: a new
    /// basis must say how it reads in the export.
    private static func basis(_ weighting: ScoreWeighting) -> String {
        switch weighting {
        case .weightedAverage: return "weighted average"
        case .singleMeasure(let against): return "single measure vs \(against)"
        case .equation(let name): return "equation (\(name))"
        case .fit(let what): return "fit (\(what))"
        case .measurement: return "measurement at face value"
        case .worstOffender: return "worst-offender pool"
        case .unstated: return "unstated"
        }
    }

    // MARK: - Formatting

    private static func num(_ value: Double?) -> String {
        guard let value else { return "—" }
        return value == value.rounded() && abs(value) < 10_000
            ? String(Int(value)) : String(format: "%.1f", value)
    }

    /// `yyyy-mm-dd`, without `DateFormatter` — several formatting APIs are
    /// Darwin-only and this file must keep InsightKit on Linux.
    private static func day(_ date: Date?, calendar: Calendar = .current) -> String {
        guard let date else { return "—" }
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d",
                      parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    private static func daysAgo(_ date: Date?, now: Date) -> String {
        guard let date else { return "—" }
        let days = Int(now.timeIntervalSince(date) / 86_400)
        switch days {
        case ..<1: return "today"
        case 1: return "1 day ago"
        default: return "\(days) days ago"
        }
    }
}
