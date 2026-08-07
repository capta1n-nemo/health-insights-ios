import Foundation

/// **What the app threw away when it picked one instrument, and why.**
///
/// Backlog `B3-23` / `S8` — the reader's ask, made more than once: *"where
/// Watch, ring and scale disagree — show both, say which the app used and
/// why."*
///
/// ## Why this has to exist at all
///
/// `VitalReader` is built on one rule, stated in its own comments: **one
/// instrument, one vote.** *"The winner is always one series, never a blend:
/// pooling them is what let the gap between two miscalibrated instruments
/// become the variance, so nothing ever cleared a threshold."* That rule is
/// right, and it is measured — pooling made the respiratory-rate reference SD
/// 1.77× wider, and flipped the illness radar on 7.3% of day-metric pairs.
///
/// But winner-take-all has a cost the reader pays and cannot see: **a number
/// that another instrument on their own wrist disagreed with, shown with no
/// hint that anything disagreed.** The reader's watch reads about 14 bpm above
/// their ring on the same night. One of those is on the card. Nothing said the
/// other existed.
///
/// This is the record of the vote. It changes no reading; it reports the
/// election.
///
/// ## The app picks per question, not once — and that is the finding
///
/// ⚠️ `VitalReader` has **two** selection rules, both deliberate, both
/// documented at their own definitions, and they can name different
/// instruments for the same metric on the same day:
///
/// - **`reading()`** — the day's value judged against a baseline. Fresh sources
///   first; among those, the longest run of history (its normal is the better
///   established); ties to the most recent.
/// - **`dailySeries()`** — the line a chart draws and a trend is fitted
///   through. The source best covering **the window being read**, then
///   recency, then name. Deliberately *not* `reading()`'s winner: that reader's
///   Apple Watch holds the most resting-heart-rate days overall (116) but only
///   8 in the last 60, and selecting it globally cut the radar's usable
///   signal-days from 138 to 30.
///
/// So "which instrument does the app believe" has two honest answers, and a
/// section that gave one would be hiding the other. Both are reported here,
/// and where they differ the difference is said out loud.
///
/// ## Where the winners come from
///
/// The reading winner is **not** re-derived: `VitalReader.reading` is called
/// and its `sourceName` is read, so this can never drift from the rule it
/// describes. The series winner has to be re-derived, because `dailySeries`
/// returns values and not the name behind them — so `InstrumentAgreementTests`
/// asserts that the series this file names produces exactly what
/// `VitalReader.dailySeries` returns. Drift is a red test, not a wrong sentence
/// on the reader's screen.
///
/// ## What it deliberately does not do
///
/// **It does not calibrate one instrument onto another.** From `dailySeries`'s
/// own note, measured on this reader's export: the watch-versus-ring
/// resting-heart-rate difference has a median of 14.0 bpm, an IQR of 16.25, and
/// drifts by 10.5 between the first and second half of the co-reported days.
/// They are not one quantity with a constant offset, so there is no offset to
/// remove and no "true" value to average toward.
///
/// **It does not call the disagreement an error.** Neither instrument is a
/// reference standard. The honest sentence is *they measure different things
/// and the app had to choose one*, and that is the sentence this produces.
public struct InstrumentAgreement: Sendable, Equatable, Identifiable {

    /// One physical device's account of one metric.
    ///
    /// "Physical device" rather than "source id": `MultiSource.breakdown` has
    /// already collapsed the same ring arriving directly and mirrored into
    /// Apple Health, so a row here is an instrument and not a feed. That
    /// collapse is why the reader's four VO₂max source ids do not become four
    /// rows claiming four opinions.
    public struct Instrument: Sendable, Equatable, Identifiable {
        public let name: String
        /// Every path this instrument's readings arrived by. More than one is
        /// normal and is shown, because a direct pull and an Apple Health
        /// mirror can lag each other.
        public let origins: Set<SourceOrigin>
        /// The most recent day this instrument reported, reduced by the
        /// metric's own bucketing rule — never a raw sample, which for a
        /// continuously sampled vital is one minute of one afternoon.
        public let latest: Double?
        /// The day `latest` represents.
        public let lastReported: Date?
        /// Days it reported inside the window being described. **This is the
        /// quantity `dailySeries` ranks on**, so it is the number the chart
        /// sentence quotes.
        public let daysInWindow: Int
        /// Days it has ever reported. Context only — no rule reads it, and an
        /// earlier draft of the reading sentence quoted this by mistake, which
        /// would have named a margin that decided nothing.
        public let daysAll: Int
        /// Days standing behind this instrument's own baseline, taken from its
        /// own `VitalReading.history`. **This is the quantity `reading()`
        /// ranks fresh sources on** — a 28-day window, not the whole record —
        /// so it is the number the reading sentence quotes.
        public let baselineDays: Int
        /// Whether it reported recently enough to describe now
        /// (`VitalReader.defaultFreshness`).
        public let isFresh: Bool
        /// This is the instrument the day's judged reading came from.
        public let feedsReading: Bool
        /// This is the instrument charts and trends are drawn from.
        public let feedsCharts: Bool

        public var id: String { name }
        /// Neither rule chose it. It is still shown — that is the point.
        public var isUnused: Bool { !feedsReading && !feedsCharts }

        public init(name: String, origins: Set<SourceOrigin>, latest: Double?,
                    lastReported: Date?, daysInWindow: Int, daysAll: Int,
                    baselineDays: Int, isFresh: Bool,
                    feedsReading: Bool, feedsCharts: Bool) {
            self.name = name
            self.origins = origins
            self.latest = latest
            self.lastReported = lastReported
            self.daysInWindow = daysInWindow
            self.daysAll = daysAll
            self.baselineDays = baselineDays
            self.isFresh = isFresh
            self.feedsReading = feedsReading
            self.feedsCharts = feedsCharts
        }
    }

    public let metric: MetricType
    /// Chosen instruments first, then by coverage of the window. Never empty
    /// for a row that exists.
    public let instruments: [Instrument]
    /// Days the coverage figures and the series winner describe.
    public let windowDays: Int
    /// Gap between the highest and lowest latest value **among instruments
    /// still reporting**.
    ///
    /// Stale ones are excluded deliberately, for the reason `SourceBreakdown`
    /// already gives: letting a phone that last logged a weight in 2022 into
    /// today's comparison invents a disagreement that does not exist today.
    /// `nil` when fewer than two are still reporting.
    public let spread: Double?
    /// Name of the instrument the judged reading came from, if there was one.
    public let readingSource: String?
    /// Name of the instrument charts and trends are drawn from, if there was one.
    public let chartSource: String?
    /// Why the reading winner won, in the reader's language.
    public let readingReason: String
    /// Why the chart winner won — `nil` when it is the same instrument, because
    /// repeating the sentence would imply two decisions where there was one.
    public let chartReason: String?

    public var id: String { metric.rawValue }

    /// Whether more than one instrument is currently reporting this — the test
    /// for "there is a disagreement to show" rather than "there is history from
    /// two devices".
    public var isContested: Bool { instruments.filter(\.isFresh).count > 1 }

    /// Whether the two rules landed on different instruments. The most
    /// interesting thing this type can find, and the reason it reports both.
    public var rulesDisagree: Bool {
        guard let readingSource, let chartSource else { return false }
        return readingSource != chartSource
    }

    public init(metric: MetricType, instruments: [Instrument], windowDays: Int,
                spread: Double?, readingSource: String?, chartSource: String?,
                readingReason: String, chartReason: String?) {
        self.metric = metric
        self.instruments = instruments
        self.windowDays = windowDays
        self.spread = spread
        self.readingSource = readingSource
        self.chartSource = chartSource
        self.readingReason = readingReason
        self.chartReason = chartReason
    }
}

// MARK: - The panel a card renders

/// Every signal on one card, asked the same question.
///
/// Shaped like `VitalDeparturePanel.forCard` on purpose: a card's section hands
/// it the card's own metrics and gets back rows plus the *reasons there are not
/// more rows*, because a section showing two of nine signals implies the other
/// seven were checked and found to agree.
public struct InstrumentAgreementPanel: Sendable, Equatable {
    /// Metrics with more than one instrument, most disagreement first.
    public let rows: [InstrumentAgreement]
    /// Metrics only one instrument has ever reported. Listed, not dropped —
    /// "one instrument" is the answer to "which should I believe" for most
    /// signals, and it is a reassuring answer rather than a missing one.
    public let single: [MetricType]
    /// Metrics with no readings at all.
    public let silent: [MetricType]
    public let windowDays: Int

    public var isEmpty: Bool { rows.isEmpty }

    /// Rows where the two rules named different instruments.
    public var conflicted: [InstrumentAgreement] { rows.filter(\.rulesDisagree) }

    public init(rows: [InstrumentAgreement], single: [MetricType],
                silent: [MetricType], windowDays: Int) {
        self.rows = rows
        self.single = single
        self.silent = silent
        self.windowDays = windowDays
    }

    /// Build the panel for a card's own signals.
    ///
    /// - Parameter windowDays: the window coverage is measured over, and the
    ///   one the chart-selection rule is replayed against. It is a parameter
    ///   and not a constant because `dailySeries` genuinely picks per window —
    ///   eighteen callers pass anything from 21 to 180 days — so a single
    ///   number here would be a claim about all of them. The section passes the
    ///   reader's own timeframe, and the copy names the number.
    /// - Parameter gap: the reference gap the judged reading is taken with.
    ///   `VitalReader.judgementGap` by default, matching "How far from your
    ///   normal", which is the number this section is explaining.
    public static func forCard(metrics: [MetricType],
                               samples: [HealthMetricSample],
                               now: Date = Date(),
                               windowDays: Int = 90,
                               gap: ReferenceGap = VitalReader.judgementGap,
                               calendar: Calendar = .current) -> InstrumentAgreementPanel {
        var rows: [InstrumentAgreement] = []
        var single: [MetricType] = []
        var silent: [MetricType] = []

        // Ordered and de-duplicated: a card can declare the same metric twice
        // across contributors and requirements, and two identical rows would
        // read as two instruments' worth of evidence.
        var seen = Set<MetricType>()
        for metric in metrics where seen.insert(metric).inserted {
            switch agreement(for: metric, samples: samples, now: now,
                             windowDays: windowDays, gap: gap, calendar: calendar) {
            case .contested(let row): rows.append(row)
            case .oneInstrument: single.append(metric)
            case .nothing: silent.append(metric)
            }
        }

        // Most disagreement first, scaled by the metric's own spread so a
        // 14 bpm heart-rate gap and a 0.4 kg weight gap can be ranked against
        // each other at all. Without the scaling the order would be whichever
        // metric happens to have the largest units.
        rows.sort { left, right in
            let l = left.relativeSpread ?? -1
            let r = right.relativeSpread ?? -1
            if l != r { return l > r }
            return left.metric.displayName < right.metric.displayName
        }
        return InstrumentAgreementPanel(rows: rows, single: single,
                                        silent: silent, windowDays: windowDays)
    }

    private enum Outcome {
        case contested(InstrumentAgreement)
        case oneInstrument
        case nothing
    }

    private static func agreement(for metric: MetricType,
                                  samples: [HealthMetricSample],
                                  now: Date,
                                  windowDays: Int,
                                  gap: ReferenceGap,
                                  calendar: Calendar) -> Outcome {
        let breakdown = MultiSource.breakdown(metric, from: samples)
        guard !breakdown.sources.isEmpty else { return .nothing }
        let buckets = VitalReader.dailyBuckets(metric, breakdown: breakdown,
                                               from: samples, calendar: calendar)
        let named = zip(breakdown.sources, buckets).filter { !$0.1.isEmpty }
        guard named.count > 1 else {
            return named.isEmpty ? .nothing : .oneInstrument
        }

        let cutoff = now.addingTimeInterval(-Double(windowDays) * 86_400)

        // The reading winner, read off the authoritative call rather than
        // re-derived. See the type's own note.
        let readingSource = VitalReader.reading(metric, from: samples, now: now,
                                                gap: gap, calendar: calendar)?.sourceName
        let chartSource = chartWinner(named, cutoff: cutoff)

        var instruments: [InstrumentAgreement.Instrument] = []
        for (series, daily) in named {
            // **This instrument's own reading, taken the same way the app takes
            // the winner's.** Handing `reading()` a single device's samples
            // gives back exactly what its internal loop computed for that
            // device — the day's bucketed value, its freshness, and the size of
            // the baseline window behind it. Re-deriving those here would be a
            // second copy of a rule that has already been got wrong once.
            let own = VitalReader.reading(metric, from: series.samples, now: now,
                                          gap: gap, calendar: calendar)
            instruments.append(.init(
                name: series.displayName,
                origins: series.origins,
                latest: own?.value ?? daily.last?.value,
                lastReported: own?.date ?? daily.last?.date,
                daysInWindow: daily.filter { $0.date >= cutoff }.count,
                daysAll: daily.count,
                baselineDays: own?.history.count ?? 0,
                isFresh: own?.isFresh ?? false,
                feedsReading: series.displayName == readingSource,
                feedsCharts: series.displayName == chartSource))
        }
        instruments.sort { left, right in
            let lChosen = left.feedsReading || left.feedsCharts
            let rChosen = right.feedsReading || right.feedsCharts
            if lChosen != rChosen { return lChosen }
            if left.daysInWindow != right.daysInWindow {
                return left.daysInWindow > right.daysInWindow
            }
            return left.name < right.name
        }

        let live = instruments.filter(\.isFresh).compactMap(\.latest)
        var spread: Double?
        if live.count > 1, let lo = live.min(), let hi = live.max() { spread = hi - lo }

        let row = InstrumentAgreement(
            metric: metric,
            instruments: instruments,
            windowDays: windowDays,
            spread: spread,
            readingSource: readingSource,
            chartSource: chartSource,
            readingReason: InstrumentAgreementWording.readingReason(
                instruments, metric: metric, now: now),
            chartReason: readingSource == chartSource
                ? nil
                : InstrumentAgreementWording.chartReason(
                    instruments, metric: metric, windowDays: windowDays))
        return .contested(row)
    }

    /// `VitalReader.dailySeries`'s ranking, replayed so the winner can be
    /// **named**.
    ///
    /// ⚠️ This is the one duplicated rule in the file, and it is duplicated
    /// because `dailySeries` returns `[DailyValue]` with the name discarded.
    /// `InstrumentAgreementTests.testTheNamedChartInstrumentIsTheOneDailySeriesActuallyReturns`
    /// holds the two together: it asserts the values of the series named here
    /// are exactly what `dailySeries` produced. Keep that test if this is ever
    /// rewritten — a wrong name here is a confident false sentence on the
    /// reader's screen, which is worse than no section.
    private static func chartWinner(_ named: [(SourceSeries, [AggregatedPoint])],
                                    cutoff: Date) -> String? {
        let windows = named.map { series, daily in
            (daily.filter { $0.date >= cutoff }, series.displayName)
        }.filter { !$0.0.isEmpty }
        // Coverage, then recency, then the name — the third being what stops
        // the same input producing different answers on different runs.
        return windows.max { left, right in
            if left.0.count != right.0.count { return left.0.count < right.0.count }
            let leftLast = left.0.map(\.date).max() ?? .distantPast
            let rightLast = right.0.map(\.date).max() ?? .distantPast
            if leftLast != rightLast { return leftLast < rightLast }
            return left.1 > right.1
        }?.1
    }
}

public extension InstrumentAgreement {
    /// The spread as a fraction of the typical value, so metrics in different
    /// units can be ranked against each other. `nil` where there is no spread
    /// or nothing to scale it by.
    var relativeSpread: Double? {
        guard let spread else { return nil }
        let live = instruments.filter(\.isFresh).compactMap(\.latest)
        guard !live.isEmpty else { return nil }
        let mid = live.reduce(0, +) / Double(live.count)
        guard abs(mid) > 0.000_001 else { return nil }
        return spread / abs(mid)
    }
}

// MARK: - The words

/// The sentences this section says, kept in InsightKit so they can be tested.
///
/// The same reason `SectionCaveat` and `SectionPlaceholder` live here: the app
/// target has no test target, and **the wording is the honesty claim** — it is
/// the part that can actually be wrong. A sentence saying an instrument was
/// chosen for a reason that is not the reason it was chosen is a worse defect
/// than no sentence, because the reader has no way to check it.
public enum InstrumentAgreementWording {

    /// Why the judged reading came from the instrument it came from.
    ///
    /// Derived from the candidates rather than from a fixed string per branch,
    /// so it quotes the actual margin — `reading()`'s rule is freshness first,
    /// then the longest run of history, then recency, and each of those three
    /// gets the sentence that names the numbers it decided on.
    public static func readingReason(_ instruments: [InstrumentAgreement.Instrument],
                                     metric: MetricType,
                                     now: Date) -> String {
        guard let winner = instruments.first(where: \.feedsReading) else {
            return "Nothing here is fresh enough to stand as today's reading, so "
                + "no card is using any of these for \(metric.displayName) right "
                + "now. The readings below are the last each instrument took."
        }
        let others = instruments.filter { $0.name != winner.name }
        let freshOthers = others.filter(\.isFresh)

        if winner.isFresh && freshOthers.isEmpty {
            let ages = others.compactMap { $0.lastReported.map { days(since: $0, now: now) } }
            let quietest = ages.min()
            let howLong = quietest.map { "\($0) \(SectionCaveat.plural($0, "day")) ago" }
                ?? "some time ago"
            return "\(winner.name) is the only one still reporting. The "
                + "\(others.count == 1 ? "other" : "others") last recorded \(howLong), "
                + "and a reading that old cannot describe today — so it is not "
                + "averaged in, and it is not silently used either."
        }
        // The rival is the strongest *loser* by the rule that actually decided
        // it — the size of the baseline window, not the length of the record.
        if winner.isFresh, let rival = freshOthers.max(by: { $0.baselineDays < $1.baselineDays }) {
            if winner.baselineDays != rival.baselineDays {
                return "\(winner.name) and \(rival.name) are both reporting and they "
                    + "do not agree. The app takes \(winner.name) because more of your "
                    + "recent history sits behind it — \(winner.baselineDays) days "
                    + "against \(rival.baselineDays) — so what counts as normal for you "
                    + "is the better established of the two. It is never a blend of "
                    + "them: averaging two instruments that disagree makes the gap "
                    + "between them look like your own variation."
            }
            return "\(winner.name) and \(rival.name) are both reporting, with the same "
                + "\(winner.baselineDays) days behind each of their baselines. "
                + "\(winner.name) recorded most recently, which is the tie-break. It is "
                + "never a blend of them: averaging two instruments that disagree makes "
                + "the gap between them look like your own variation."
        }
        let age = winner.lastReported.map { days(since: $0, now: now) }
        let when = age.map { "\($0) \(SectionCaveat.plural($0, "day")) ago" } ?? "some time ago"
        return "Nothing has reported this recently. \(winner.name) is the most recent "
            + "of them — \(when) — so its reading is the one shown, and every card "
            + "using it is told how old it is rather than treating it as today's."
    }

    /// Why the chart and the trend are drawn from the instrument they are drawn
    /// from, said only when that is a different instrument.
    public static func chartReason(_ instruments: [InstrumentAgreement.Instrument],
                                   metric: MetricType,
                                   windowDays: Int) -> String {
        guard let winner = instruments.first(where: \.feedsCharts) else {
            return "No instrument covers the last \(windowDays) days, so there is no "
                + "line to draw for \(metric.displayName) over this window."
        }
        let reader = instruments.first(where: \.feedsReading)
        let against = reader.map {
            " — \(winner.daysInWindow) days against \($0.daysInWindow)"
        } ?? ""
        return "The chart and the trend come from \(winner.name) instead, because it "
            + "covers the last \(windowDays) days most completely\(against). These are "
            + "two different questions and the app answers them separately on purpose: "
            + "a device with a long memory that stopped reporting still knows what your "
            + "normal is, and still cannot draw this month."
    }

    /// The one-line preview a closed section shows. It has to stand alone —
    /// for most readers it is the whole of this section they will ever see.
    public static func preview(_ panel: InstrumentAgreementPanel) -> String {
        guard let worst = panel.rows.first else {
            return panel.single.isEmpty
                ? "Nothing here has reported yet"
                : "One instrument each — nothing to disagree with"
        }
        guard let spread = worst.spread else {
            let n = panel.rows.count
            return "\(n) \(SectionCaveat.plural(n, "signal")) with more than one "
                + "instrument, none of them still reporting twice"
        }
        let gap = MetricValueFormatter.string(spread, worst.metric)
        let unit = MetricValueFormatter.includesUnit(worst.metric) ? "" : " \(worst.metric.unit)"
        return "\(worst.metric.displayName): your instruments differ by \(gap)\(unit)"
            + (panel.rows.count > 1 ? ", and \(panel.rows.count - 1) more disagree" : "")
    }

    private static func days(since date: Date, now: Date) -> Int {
        max(0, Int((now.timeIntervalSince(date) / 86_400).rounded()))
    }
}
