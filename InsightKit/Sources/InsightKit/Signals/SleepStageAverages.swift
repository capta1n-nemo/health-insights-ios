import Foundation

/// **What a typical night in the chosen window was made of, per source.**
///
/// The sleep card could draw exactly one night in stages (`NightSleepDetail`)
/// and nothing about a stretch of them, so the timeframe control at the bottom
/// of the page — which drives five other sections — did nothing to the one
/// picture the card is named after. Backlog P22's third part, and the reason it
/// was worth building: *"I slept badly last night"* is an anecdote, *"my deep
/// sleep has averaged 42 minutes a night this month against 55 last"* is a
/// finding.
///
/// ## Per source, never pooled
///
/// This is the same refusal `NightSleepDetail` was written for. On 2026-07-29
/// Oura filed 4.3 h for a night and Apple Health filed 8.5 h, and both were
/// telling the truth about what they saw. Averaging across sources would turn
/// that into a single wrong number and hide the disagreement that is itself the
/// most interesting thing on the chart, so every source keeps its own row and
/// its own night count.
///
/// ## Nights, not hours, are the denominator
///
/// A source's average is *per night it recorded*, not per night in the window.
/// A ring worn nine nights out of thirty is not a person who slept two hours a
/// night, and dividing by thirty would say exactly that. `nights` is published
/// beside every row so the reader can see how thin the evidence is — a mean of
/// three nights is drawn and labelled, never suppressed and never dressed up as
/// a month.
///
/// ## A stageless source is not a source with no deep sleep
///
/// A lane whose bands carry no stage (`Band.stage == nil` — a device that
/// reports only when it thinks you slept) contributes to `asleepHours` and to
/// nothing else, and its row says so via `hasStageDetail`. Filing its whole
/// night under "light" would invent stage detail that was never measured, which
/// is the modelled-as-measured mistake this app has a rule against.
///
/// In InsightKit because it is arithmetic that can be quietly wrong, and the
/// app target has no test target.
public struct SleepStageAverages: Sendable, Equatable {

    /// One source's typical night over the window.
    public struct Row: Sendable, Equatable, Identifiable {
        public let source: String
        /// Nights this source actually recorded inside the window.
        public let nights: Int
        /// Mean hours per recorded night, by stage. A stage the source never
        /// recorded is absent rather than zero — "we never saw REM" and "you
        /// had no REM" are different claims.
        public let hoursByStage: [NightSleepDetail.Stage: Double]
        /// Mean hours asleep per recorded night: everything except `awake`,
        /// including bands with no stage at all.
        public let asleepHours: Double
        /// Whether any night from this source carried stage detail. `false`
        /// means the row can only honestly draw one undivided bar.
        public let hasStageDetail: Bool

        public var id: String { source }

        public init(source: String, nights: Int,
                    hoursByStage: [NightSleepDetail.Stage: Double],
                    asleepHours: Double, hasStageDetail: Bool) {
            self.source = source
            self.nights = nights
            self.hoursByStage = hoursByStage
            self.asleepHours = asleepHours
            self.hasStageDetail = hasStageDetail
        }

        /// Stages in the order the night runs through them, deepest first, so
        /// every row of a stacked bar reads the same way round.
        public var stagesInDrawOrder: [(stage: NightSleepDetail.Stage, hours: Double)] {
            NightSleepDetail.Stage.allCases.compactMap { stage in
                hoursByStage[stage].map { (stage, $0) }
            }
        }
    }

    /// Stage-bearing sources first, then window-only ones; alphabetical within,
    /// which is the order `NightSleepDetail` draws its lanes in.
    public let rows: [Row]
    /// The window these were taken over, for the caption. `nil` lower bound
    /// means all-time.
    public let span: ClosedRange<Date>?
    /// Distinct nights any source recorded inside the window — the honest
    /// answer to "how much is this based on", which no single row gives.
    public let nightsCovered: Int

    public var isEmpty: Bool { rows.isEmpty }

    public init(rows: [Row], span: ClosedRange<Date>?, nightsCovered: Int) {
        self.rows = rows
        self.span = span
        self.nightsCovered = nightsCovered
    }

    // MARK: - Building

    /// Averages over the nights at or after `since`, or over everything when
    /// `since` is `nil`.
    ///
    /// `since` is compared against the **wake day** each night is keyed by, the
    /// same key `NightSleepDetail` files nights under — so "the past week" means
    /// the same seven nights here as it does on every other sleep surface, and a
    /// 3 am bedtime cannot fall into a different bucket than the morning it
    /// belongs to.
    public static func over(_ nights: [NightSleepDetail],
                            since: Date?) -> SleepStageAverages {
        let inWindow = nights.filter { night in
            guard let since else { return true }
            return night.night >= since
        }
        guard !inWindow.isEmpty else {
            return SleepStageAverages(rows: [], span: nil, nightsCovered: 0)
        }

        struct Accumulator {
            var nights = 0
            var stageHours: [NightSleepDetail.Stage: Double] = [:]
            var asleepHours: Double = 0
            var hasStageDetail = false
            /// Where this source first appeared in lane order, so the output
            /// keeps `NightSleepDetail`'s ordering rather than inventing one.
            var firstSeen = Int.max
        }

        var bySource: [String: Accumulator] = [:]
        for (nightIndex, night) in inWindow.enumerated() {
            for (laneIndex, lane) in night.lanes.enumerated() {
                var accumulator = bySource[lane.source] ?? Accumulator()
                accumulator.nights += 1
                accumulator.asleepHours += lane.asleepHours
                accumulator.hasStageDetail = accumulator.hasStageDetail || lane.hasStageDetail
                for band in lane.bands {
                    guard let stage = band.stage else { continue }
                    accumulator.stageHours[stage, default: 0] += band.hours
                }
                // Lane order within the first night that carried the source.
                // `nightIndex` breaks the tie so a source that only ever appears
                // in later nights still sorts after the regulars.
                accumulator.firstSeen = Swift.min(accumulator.firstSeen,
                                                  nightIndex * 1_000 + laneIndex)
                bySource[lane.source] = accumulator
            }
        }

        let rows = bySource
            .sorted { left, right in
                if left.value.hasStageDetail != right.value.hasStageDetail {
                    return left.value.hasStageDetail
                }
                if left.value.firstSeen != right.value.firstSeen {
                    return left.value.firstSeen < right.value.firstSeen
                }
                return left.key < right.key
            }
            .map { source, accumulator -> Row in
                let divisor = Double(accumulator.nights)
                return Row(
                    source: source,
                    nights: accumulator.nights,
                    hoursByStage: accumulator.stageHours.mapValues { $0 / divisor },
                    asleepHours: accumulator.asleepHours / divisor,
                    hasStageDetail: accumulator.hasStageDetail)
            }

        let days = inWindow.map(\.night)
        let span = days.min().flatMap { low in days.max().map { low...$0 } }
        return SleepStageAverages(rows: rows, span: span,
                                  nightsCovered: Set(days).count)
    }
}
