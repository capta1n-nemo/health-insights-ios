import SwiftUI
import InsightKit

struct InsightDetailView: View {
    let insightID: InsightID
    @Environment(AppModel.self) private var model
    @State private var groundingKind: GroundingKind?
    @State private var feedbackGiven = false
    @State private var timeframe: Timeframe = .month
    @State private var scale: SeriesScale = .zScore
    @State private var logarithmic = false
    @State private var showsRoutineDrivers = false
    /// Which signals the overlay draws. Nil until the reader picks — the
    /// default is derived from the data, and pinning it in state on appear
    /// would freeze a selection made before the series finished loading.
    /// Held here so the chart and its legend share one answer.
    @State private var chartSelection: Set<MetricType>?

    /// Resolved against the data being charted, so `.all` doesn't squash a short
    /// history into a sliver of a decade-wide viewport.
    private func window(spanning span: ClosedRange<Date>?) -> TimeInterval {
        timeframe.chartWindow(spanning: span.map { $0.upperBound.timeIntervalSince($0.lowerBound) })
    }

    private var result: InsightResult? { model.result(for: insightID) }

    /// What this card lets the user view and add, asked of the model rather than
    /// decided here — see `ContributionRoute`.
    private var contributionRoutes: [ContributionRoute] {
        model.engine.models.first { $0.id == insightID }?.contributions ?? []
    }

    /// The card's own picture of its own subject, where it has one.
    ///
    /// Collected into a single switch so the placement rule is stated once. The
    /// rest draw their inputs through the shared overlay below, which for a
    /// single-metric insight already *is* its chart.
    @ViewBuilder private var bespokeSection: some View {
        switch insightID {
        case .cardiovascularRisk:
            // Heart age, where the equations that produce it already live.
            ageHistoryCard
        case .fitness:
            // Fitness age against the chronological line.
            ageHistoryCard
        case .bloodPressure:
            bloodPressureChartCard
        case .energy:
            energyCurveCard
        case .sleep:
            sleepRegularityCard
        case .substanceImpact:
            substanceLoadCard
        default:
            EmptyView()
        }
    }

    /// Whether any section below reads `timeframe`.
    ///
    /// The picker used to live inside "Score over time" while also driving the
    /// overlay, the patterns card and the lag card — so an insight with under
    /// two replayable days lost the control for three sections that still used
    /// it, and there was no way to change the window at all.
    private var usesTimeframe: Bool {
        guard let result else { return false }
        return model.scoreHistory(for: insightID).count >= 2
            || !model.overlaySeries(for: insightID,
                                    contributions: resolvedContributions(result),
                                    timeframe: timeframe).isEmpty
    }

    @ViewBuilder private var timeframePicker: some View {
        if usesTimeframe {
            Picker("Timeframe", selection: $timeframe) {
                ForEach(Timeframe.allCases) { Text($0.shortLabel).tag($0) }
            }
            .pickerStyle(.segmented)
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.spacing) {
                if let result {
                    headerCard(result)
                    if !result.drivers.isEmpty {
                        driversCard(result)
                    }
                    // What this card takes from the user, in the one shape every
                    // card uses. Gated *here* rather than inside the view: a
                    // struct View with an empty body is still a VStack child and
                    // would take spacing either side of it, so the nine cards
                    // that ask for nothing would carry a double gap.
                    if !contributionRoutes.isEmpty {
                        ViewAndAddSection(routes: contributionRoutes,
                                          unmetRequirements: result.unmetRequirements)
                    }
                    // One rule for every bespoke section: above "Score over
                    // time". The card's own subject is the finding; the months
                    // of scores derived from it are the supporting context.
                    // Three different placements used to encode the same idea.
                    bespokeSection
                    timeframePicker
                    scoreHistoryCard
                    contributorsCard(result)
                    patternsCard(result)
                    // No longer gated on cadence. The gate argued from the
                    // *tab's* question, but this screen is reached from either
                    // tab and is identical from both — and the daily insights
                    // are the ones with the densest series for a lag to work on.
                    // The sample-count and effect-size floors inside `LagFinder`
                    // and `PeriodContrast` already decide when there is nothing
                    // to say, which is how every other section here works.
                    laggedCard(result)
                    periodContrastCard(result)
                    contributorLinksCard(result)
                    feedbackCard(result)
                    disclaimerCard
                } else {
                    ContentUnavailableView("Not available", systemImage: "questionmark")
                }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(result?.title ?? "Insight")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $groundingKind) { GroundingSheet(kind: $0) }
    }

    private func headerCard(_ result: InsightResult) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    if let score = result.score {
                        ScoreDial(score: score, label: result.headline, size: 96)
                    } else {
                        VStack(alignment: .leading) {
                            Text(result.headline).font(.largeTitle.weight(.bold))
                        }
                    }
                    Spacer()
                    ConfidenceBadge(confidence: result.confidence)
                }
                Text(result.explanation)
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// Blood pressure's own picture, on the card that talks about it.
    ///
    /// It used to be a link to `MetricDetailView`, which made this the one
    /// insight whose chart lived on another screen — behind the calibration
    /// detail and the full dated history, neither of which is what you open the
    /// card to see. Both still exist there; this is the same `BloodPressureChart`
    /// component, not a second copy.
    @ViewBuilder private var bloodPressureChartCard: some View {
        let readings = model.bloodPressureReadings
        if !readings.isEmpty {
            Card {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Your readings").font(.headline)
                        Spacer()
                        if let latest = readings.first {
                            Text(latest.category)
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    BloodPressureChart(readings: readings, timeframe: timeframe)
                }
            }
        }
    }

    /// The age this card owns, over time.
    ///
    /// The pace is the finding, not the level: your real age advances a year per
    /// year regardless, so a heart age gaining 1.0 a year is holding station and
    /// one gaining 0.6 is catching up even though its number keeps rising.
    ///
    /// One chart, two owners. Heart & Fitness Age used to draw both lines beside
    /// a three-age row; that row could not survive the cards being split by
    /// subject, so each card now draws its own age against the chronological
    /// line and the risk card carries the sentence about them disagreeing.
    @ViewBuilder private var ageHistoryCard: some View {
        // Filtered to this card's own age by blanking the other, rather than
        // by teaching the chart a mode: `AgePoint` already carries both as
        // optionals and `AgeHistoryChart` already skips a nil, so the data is
        // the cheaper place to make the cut and the chart stays one thing.
        let points = model.heartAgeHistory().map { point in
            insightID == .fitness
                ? AgePoint(date: point.date, chronological: point.chronological,
                           heart: nil, fitness: point.fitness)
                : AgePoint(date: point.date, chronological: point.chronological,
                           heart: point.heart, fitness: nil)
        }
        if points.count >= 3 {
            Card {
                VStack(alignment: .leading, spacing: 8) {
                    Text(insightID == .fitness ? "Fitness age over time"
                                               : "Heart age over time").font(.headline)
                    AgeHistoryChart(points: points)
                    if let pace = points.yearsPerYear {
                        Text(Self.pacePhrase(pace))
                            .font(.caption).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Text("Rebuilt from the readings as they stood on each day. Facts you entered once — cholesterol, smoking — are applied as they stand now, because the app has no history for them.")
                        .font(.caption2).foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    /// Stated against the pace of time rather than as a bare slope, which would
    /// read as good news at 0.9 years a year when it is merely not-quite-losing.
    static func pacePhrase(_ yearsPerYear: Double) -> String {
        let gap = yearsPerYear - 1
        if abs(gap) < 0.25 {
            return String(format: "Ageing at about the pace of time — %.1f years per year, against the 1.0 everyone gets.", yearsPerYear)
        }
        if gap < 0 {
            return String(format: "Gaining on it: %.1f years per year against the 1.0 of the calendar, so the gap is closing by about %.1f a year.", yearsPerYear, -gap)
        }
        return String(format: "Running ahead: %.1f years per year against the 1.0 of the calendar, so the gap is widening by about %.1f a year.", yearsPerYear, gap)
    }

    /// What's driving this — departures first, the reassuring majority behind a
    /// disclosure.
    ///
    /// Vitals Check scans seventeen signals. On an ordinary day sixteen of them
    /// say "in your normal range", which buries the one that doesn't and makes
    /// the card a wall. Hiding the detail entirely would make it a black box, so
    /// the routine lines are one tap away rather than gone.
    ///
    /// An insight that doesn't classify its lines (`isNotable == nil`) still
    /// shows all of them — absent information is not the same as "all routine".
    private func driversCard(_ result: InsightResult) -> some View {
        let lines = result.driverLines
        let upfront = lines.filter { $0.isNotable != false }
        let routine = lines.filter { $0.isNotable == false }

        return Card {
            VStack(alignment: .leading, spacing: 8) {
                Text("What's driving this").font(.headline)

                if upfront.isEmpty {
                    Label("Nothing is away from your usual pattern.",
                          systemImage: "checkmark.circle")
                        .font(.subheadline).foregroundStyle(Theme.good)
                } else {
                    ForEach(Array(upfront.enumerated()), id: \.offset) { _, line in
                        driverRow(line.text, tint: line.isNotable == true ? Theme.warn : Theme.accent)
                    }
                }

                if !routine.isEmpty {
                    Divider()
                    Button {
                        withAnimation(.snappy) { showsRoutineDrivers.toggle() }
                    } label: {
                        HStack(spacing: 6) {
                            Text(showsRoutineDrivers
                                 ? "Hide the rest"
                                 : "Show \(routine.count) more in your normal range")
                                .font(.caption.weight(.medium))
                            Image(systemName: "chevron.down")
                                .font(.caption2)
                                .rotationEffect(.degrees(showsRoutineDrivers ? 180 : 0))
                            Spacer()
                        }
                        .foregroundStyle(Theme.accent)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    if showsRoutineDrivers {
                        ForEach(Array(routine.enumerated()), id: \.offset) { _, line in
                            driverRow(line.text, tint: .secondary)
                        }
                    }
                }
            }
        }
    }

    private func driverRow(_ text: String, tint: Color) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "circle.fill").font(.system(size: 5)).padding(.top, 6)
                .foregroundStyle(tint)
            Text(text).font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Score over time

    /// How this insight's own number has moved. Part reconstructed from the raw
    /// samples, part read back from what the app recorded on the day — see
    /// `ScoreHistory`. Absent for any insight whose replay can't clear the
    /// two-signal floor.
    @ViewBuilder private var scoreHistoryCard: some View {
        let history = model.scoreHistory(for: insightID)
        if history.count >= 2 {
            Card {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Score over time").font(.headline)
                        Spacer()
                        Text(trendPhrase(history)).font(.caption).foregroundStyle(.secondary)
                    }
                    // The picker that used to live here is now above every
                    // section that reads `timeframe`, this one included.
                    ScoreHistoryChart(points: history,
                                      window: window(spanning: scoreSpan(history)),
                                      showsTrend: insightID.cadence == .trend)
                    if insightID.cadence == .trend, let trend = history.trend, trend.isMeaningful {
                        Text(String(format: "Fitted trend %@%.1f a week, with days scattering about %.0f points either side of it.",
                                    trend.slopePerWeek > 0 ? "+" : "−",
                                    abs(trend.slopePerWeek), trend.residualSD))
                            .font(.caption2).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Text("Days before you had at least two signals recording aren't shown — a score resting on one measurement isn't one.")
                        .font(.caption2).foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    /// Today's reservoir, hour by hour.
    ///
    /// The model computed this curve from the day it shipped and nothing drew
    /// it, so the one insight in this app whose subject is *within* a day was
    /// presented like the ones whose subject is a month.
    @ViewBuilder private var energyCurveCard: some View {
        if let energy = model.energyToday(), energy.curve.count >= 2 {
            Card {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Today").font(.headline)
                        Spacer()
                        Text(String(format: "%.0f spent of %.0f",
                                    energy.spent, energy.morningCharge))
                            .font(.caption).foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    EnergyCurveChart(curve: energy.curve,
                                     morningCharge: energy.morningCharge)
                }
            }
        }
    }

    /// The fortnight of bedtimes, against the middle they are measured from.
    ///
    /// The card reports a spread and the score history plots that spread over
    /// months; neither draws the thing itself. A regular sleeper is a tight
    /// column and an irregular one is scatter, and that is the picture the whole
    /// insight is about.
    @ViewBuilder private var sleepRegularityCard: some View {
        if let regularity = model.sleepRegularity(),
           regularity.nights.count >= CircadianConsistencyModel.minimumNights {
            Card {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Your fortnight").font(.headline)
                        Spacer()
                        if let jetlag = regularity.socialJetlagHours, abs(jetlag) >= 0.5 {
                            Text(String(format: "weekends %.1f h %@",
                                        abs(jetlag), jetlag > 0 ? "later" : "earlier"))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    SleepOnsetStripChart(output: regularity)
                }
            }
        }
    }

    /// Cumulative cardiovascular load from the log, decaying over time.
    ///
    /// Deliberately separate from "Score over time" above: the score is a
    /// judgement about the body's *response*, this is a running total of what
    /// was put in. They move together and are not the same quantity.
    @ViewBuilder private var substanceLoadCard: some View {
        let series = model.substanceLoadSeries()
        if series.count >= 7 {
            Card {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Cardiovascular load").font(.headline)
                        Spacer()
                        if let perWeek = series.trendPerWeek, abs(perWeek) >= 1 {
                            Text(String(format: "%@%.0f a week",
                                        perWeek > 0 ? "+" : "−", abs(perWeek)))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    SubstanceLoadChart(points: series)
                }
            }
        }
    }

    private func scoreSpan(_ history: [ScorePoint]) -> ClosedRange<Date>? {
        guard let first = history.first?.date, let last = history.last?.date,
              first <= last else { return nil }
        return first...last
    }

    /// Direction over the window, stated only when the slope is big enough to be
    /// one. A tenth of a point a week is not a trend.
    private func trendPhrase(_ history: [ScorePoint]) -> String {
        guard let perWeek = history.trendPerWeek, abs(perWeek) >= 0.5 else {
            return "Holding steady"
        }
        return String(format: "%@ %.1f a week", perWeek > 0 ? "↑" : "↓", abs(perWeek))
    }

    // MARK: - What goes into it

    /// Every metric behind the score, standardised onto one axis.
    ///
    /// The series come from `result.contributors`, which the scoring code emits
    /// as it builds each component — so adding an input to a score adds a line
    /// here with no edit to this file. Where a model doesn't yet report its
    /// components, its declared `candidateMetrics` stand in.
    @ViewBuilder private func contributorsCard(_ result: InsightResult) -> some View {
        let contributions = resolvedContributions(result)
        let series = model.overlaySeries(for: insightID, contributions: contributions,
                                         timeframe: timeframe)
        if !series.isEmpty {
            let missing = contributions.metrics.filter { metric in
                !series.contains { $0.metric == metric }
            }
            Card {
                VStack(alignment: .leading, spacing: 10) {
                    Text("What goes into this").font(.headline)
                    Text(scale == .zScore
                         ? "Each signal against its own normal for this period, so they can be read against each other. The dashed line is your average. The list below is ordered by how far each signal has moved — tap any of them to add or remove it."
                         : "Measured values, in their own units. Signals with very different ranges will look flat next to each other — that's what the compare view is for.")
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Picker("Scale", selection: $scale) {
                        ForEach(SeriesScale.allCases) { Text($0.shortLabel).tag($0) }
                    }
                    .pickerStyle(.segmented)

                    MetricOverlayChart(
                        series: series, scale: scale, logarithmic: logarithmic,
                        window: window(spanning: model.overlayRange(for: contributions.metrics,
                                                                    timeframe: timeframe)),
                        selectedMetrics: chartSelection
                            ?? OverlaySelection.defaultSelection(series))

                    if scale == .raw && series.supportsLogScale {
                        Toggle("Logarithmic axis", isOn: $logarithmic)
                            .font(.caption)
                    }

                    Divider()
                    MetricOverlayLegend(
                        series: series, contributions: contributions,
                        missing: missing,
                        selection: Binding(
                            get: { chartSelection ?? OverlaySelection.defaultSelection(series) },
                            set: { chartSelection = $0 }))
                }
            }
        }
    }

    /// Contributions to chart: what the model reported, or its declared inputs
    /// where it doesn't report yet. Without the fallback, an insight that hasn't
    /// been migrated would show an empty card rather than a chart.
    private func resolvedContributions(_ result: InsightResult) -> [MetricContribution] {
        if !result.contributors.isEmpty { return result.contributors }
        return candidateMetrics(for: insightID).map {
            MetricContribution(metric: $0, higherIsBetter: nil, weight: 0, detail: "")
        }
    }

    private func candidateMetrics(for id: InsightID) -> [MetricType] {
        // Not named `model` — that's the AppModel in this scope, and shadowing it
        // here has bitten this codebase before.
        // Substance Impact used to need a special case here, because it wasn't
        // an engine model at all. It is one now.
        model.engine.models.first { $0.id == id }?.candidateMetrics ?? []
    }

    // MARK: - Patterns across those metrics

    /// What reading the series against each other turns up: two signals heading
    /// opposite ways, two that move together, or the one that tracks the score.
    /// Silent when nothing clears the sample-count and effect-size floors —
    /// which is most of the time, and correctly so.
    @ViewBuilder private func patternsCard(_ result: InsightResult) -> some View {
        let series = model.overlaySeries(for: insightID,
                                         contributions: resolvedContributions(result),
                                         timeframe: timeframe)
        let patterns = PatternFinder.patterns(in: series,
                                              against: model.scoreHistory(for: insightID))
        if !patterns.isEmpty {
            Card {
                VStack(alignment: .leading, spacing: 10) {
                    Label("Patterns worth a look", systemImage: "lightbulb")
                        .font(.headline)
                    ForEach(patterns) { pattern in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: icon(for: pattern.kind))
                                .font(.caption)
                                .foregroundStyle(Theme.accent)
                                .frame(width: 16)
                            Text(pattern.sentence)
                                .font(.subheadline)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Text("These are associations found in your own data over this window, not causes, and not medical findings. A short run of days can show a relationship that isn't there.")
                        .font(.caption2).foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func icon(for kind: PatternKind) -> String {
        switch kind {
        case .divergence: return "arrow.up.arrow.down"
        case .coMovement: return "arrow.left.arrow.right"
        case .driver: return "target"
        }
    }

    // MARK: - Deep dive (Insights tab only)

    /// Signals that *lead* the score rather than moving with it.
    ///
    /// This is the one question the Today tab structurally cannot ask: it
    /// compares today with yesterday, so everything it can see is same-day.
    /// Shifting a signal against the score asks whether last night's sleep
    /// predicts tomorrow's number — and a lag only appears here when it
    /// genuinely beats same-day, because otherwise it's the same finding blurred.
    @ViewBuilder private func laggedCard(_ result: InsightResult) -> some View {
        let series = model.overlaySeries(for: insightID,
                                         contributions: resolvedContributions(result),
                                         timeframe: timeframe)
        let leads = LagFinder.relationships(between: series,
                                            and: model.scoreHistory(for: insightID))
        if !leads.isEmpty {
            Card {
                VStack(alignment: .leading, spacing: 10) {
                    Label("What comes first", systemImage: "clock.arrow.circlepath")
                        .font(.headline)
                    // Resolved across this list. Without slots a metric falls
                    // back to its *preferred* hue, and RMSSD and SDNN prefer the
                    // same one — two identical dots in one list, which is the
                    // collision class this app has already shipped once.
                    let slots = MetricPalette.slots(for: leads.map(\.metric))
                    ForEach(leads) { lead in
                        HStack(alignment: .top, spacing: 8) {
                            Circle().fill(Theme.metricColor(lead.metric, slots: slots))
                                .frame(width: 8, height: 8).padding(.top, 6)
                            Text(lead.sentence).font(.subheadline)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
    }

    /// Has your normal itself moved? A z-score can't answer that — its baseline
    /// drifts along with the change, which is exactly how a slow decline stays
    /// invisible day to day.
    @ViewBuilder private func periodContrastCard(_ result: InsightResult) -> some View {
        let changes = PeriodContrast.changes(for: resolvedContributions(result),
                                             samples: model.samples)
        if !changes.isEmpty {
            Card {
                VStack(alignment: .leading, spacing: 10) {
                    Text("What changed").font(.headline)
                    Text("Your last four weeks against the four before them.")
                        .font(.caption).foregroundStyle(.secondary)
                    let slots = MetricPalette.slots(for: changes.map(\.metric))
                    ForEach(changes) { change in
                        HStack(spacing: 8) {
                            Circle().fill(Theme.metricColor(change.metric, slots: slots))
                                .frame(width: 9, height: 9)
                            Text(change.metric.displayName).font(.subheadline)
                            Spacer()
                            Text(deltaLabel(change))
                                .font(.subheadline.weight(.medium)).monospacedDigit()
                                .foregroundStyle(tint(for: change))
                        }
                    }
                }
            }
        }
    }

    private func deltaLabel(_ change: PeriodChange) -> String {
        let unit = change.metric.unit
        let magnitude = abs(change.delta) < 10
            ? String(format: "%.1f", abs(change.delta))
            : String(format: "%.0f", abs(change.delta))
        return "\(change.delta >= 0 ? "+" : "−")\(magnitude)\(unit.isEmpty ? "" : " \(unit)")"
    }

    /// Coloured only where a direction is genuinely better or worse. Where
    /// neither end is good — a temperature deviation — it stays neutral rather
    /// than implying a verdict.
    private func tint(for change: PeriodChange) -> Color {
        guard let improved = change.isImprovement else { return .primary }
        return improved ? Theme.good : Theme.warn
    }

    // MARK: - Full history per metric

    /// One link per input, replacing the single "open full history" that only
    /// ever reached the one metric this screen used to chart.
    @ViewBuilder private func contributorLinksCard(_ result: InsightResult) -> some View {
        let metrics = resolvedContributions(result).metrics
        if !metrics.isEmpty {
            Card {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Full history").font(.headline)
                    let slots = MetricPalette.slots(for: metrics)
                    ForEach(metrics, id: \.self) { metric in
                        NavigationLink {
                            MetricDetailView(metric: metric)
                        } label: {
                            HStack(spacing: 8) {
                                Circle().fill(Theme.metricColor(metric, slots: slots))
                                    .frame(width: 9, height: 9)
                                Text(metric.displayName).font(.subheadline)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption).foregroundStyle(.tertiary)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // Discreet, only-in-detail feedback loop: rate accuracy and (optionally)
    // enter the real value, which trains/refines the model over time.
    @ViewBuilder private func feedbackCard(_ result: InsightResult) -> some View {
        if result.primaryValue != nil {
            Card {
                if feedbackGiven {
                    Label("Thanks — this helps improve the model over time.",
                          systemImage: "checkmark.circle.fill")
                        .font(.caption).foregroundStyle(Theme.good)
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Was this accurate?").font(.subheadline.weight(.semibold))
                        HStack(spacing: 10) {
                            Button {
                                model.recordFeedback(insightID, accurate: true); feedbackGiven = true
                            } label: { Label("Accurate", systemImage: "hand.thumbsup") }
                            Button {
                                model.recordFeedback(insightID, accurate: false); feedbackGiven = true
                            } label: { Label("Not accurate", systemImage: "hand.thumbsdown") }
                        }
                        .font(.caption).buttonStyle(.bordered)

                        if let kind = groundingPromptKind(result) {
                            Button {
                                groundingKind = kind
                            } label: {
                                Text("Have the real number? Enter it →")
                                    .font(.caption).foregroundStyle(Theme.accent)
                            }
                        }
                    }
                }
            }
        }
    }

    /// Which "real value" to invite for this insight (its first unmet input, or a
    /// cuff reading for blood pressure).
    private func groundingPromptKind(_ result: InsightResult) -> GroundingKind? {
        if let first = result.unmetRequirements.first { return first.kind }
        return insightID == .bloodPressure ? .cuffSystolic : nil
    }

    private var disclaimerCard: some View {
        Card {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "info.circle").foregroundStyle(.secondary)
                Text("These insights are for information only and are not a medical diagnosis or advice. Talk to a clinician about any health decisions.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

}
