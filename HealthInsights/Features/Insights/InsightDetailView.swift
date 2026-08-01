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
    @Environment(\.colorScheme) private var colorScheme

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
        case .heartHealth:
            // The centiles this card absorbed from "Where You Stand". Both of
            // these used to be nested under "How this is weighted", which was
            // this card's bespoke section until that went universal.
            peerStandingSection
        case .readiness:
            vitalDepartureSection
        case .bodyComposition:
            bodyCompositionSplitCard
        // Kept, though all nine cases are now named: making this exhaustive
        // would add a *sixth* build-breaking switch over `InsightID` to the
        // `add-insight` path, which `docs/activeContext.md` singles out as the
        // most expensive way to add a feature here. A new insight having no
        // bespoke section until someone writes one is the right default anyway.
        default:
            EmptyView()
        }
    }

    /// The window every timeframe-driven section below reads.
    ///
    /// It used to live inside "Score over time" while also driving the overlay,
    /// the patterns card and the lag card — so an insight with under two
    /// replayable days lost the control for three sections that still used it,
    /// and there was no way to change the window at all. Moving it out fixed
    /// that; a `usesTimeframe` gate then kept it off cards where nothing read it.
    ///
    /// **That gate is gone, and its own reasoning is what retired it.** Both
    /// findings sections now render on every card whatever they found, and both
    /// read this window, so there is always a section below that this control
    /// moves. More to the point, the one case the gate hid it in — a card with
    /// no series at all — is exactly where widening the window is the remedy:
    /// `overlaySeries` filters by it, so a card drawing nothing over a month can
    /// draw plenty over a year. Hiding the control there left
    /// `SectionPlaceholder` telling the reader to widen a timeframe that wasn't
    /// on screen.
    private var timeframePicker: some View {
        Picker("Timeframe", selection: $timeframe) {
            ForEach(Timeframe.allCases) { Text($0.shortLabel).tag($0) }
        }
        .pickerStyle(.segmented)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.spacing) {
                if let result {
                    headerCard(result)
                    // Above "Score over time" because that section reads it,
                    // and it is a screen-level control rather than a card.
                    timeframePicker
                    // **The first section on every card**, by the user's call on
                    // 2026-08-01. The placement rule it replaces put the card's
                    // own bespoke picture here and argued that the months of
                    // scores derived from it were supporting context; the number
                    // over time is what the reader opens the card for.
                    scoreHistoryCard
                    driversCard(result)
                    // How the number divides, on every card — including the ones
                    // where the answer is "it doesn't divide", which is a fact
                    // about the card rather than a gap in the data.
                    weightedContributionCard(result)
                    // The card's own picture of its own subject, directly under
                    // the three sections that explain its number.
                    bespokeSection
                    // The two findings sections sit above the inputs the score
                    // is built from. They used to sit *below* "What goes into
                    // this", so the reader met a chart, a scale picker and a
                    // thirteen-row legend before reaching the one part of the
                    // screen that had actually looked at the data for them.
                    //
                    // Both render on every card, whatever they found. See
                    // `SectionExpansion` for why a section that vanishes is
                    // worse than one that says why it is empty. Neither is
                    // gated on cadence: the gate argued from the *tab's*
                    // question, but this screen is reached from either tab and
                    // is identical from both.
                    patternsCard(result)
                    laggedCard(result)
                    contributorsCard(result)
                    periodContrastCard(result)
                    contributorLinksCard(result)
                    // What this card takes from the user, in the one shape every
                    // card uses. Gated *here* rather than inside the view: a
                    // struct View with an empty body is still a VStack child and
                    // would take spacing either side of it, so the three cards
                    // that ask for nothing would carry a double gap.
                    //
                    // Second from the bottom, beside the other thing the screen
                    // asks *of* the reader rather than tells them. It used to be
                    // third from the top, which put a data-entry prompt ahead of
                    // every finding on a screen nobody opens to type.
                    if !contributionRoutes.isEmpty {
                        ViewAndAddSection(routes: contributionRoutes,
                                          unmetRequirements: result.unmetRequirements)
                    }
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
            // `.none`: these are cuff readings the user typed in, drawn as they
            // were entered. The estimator's own uncertainty is the header card's
            // subject, not this chart's.
            InsightSection(title: "Your readings",
                           trailing: readings.first?.category,
                           caveat: .none) {
                BloodPressureChart(readings: readings, timeframe: timeframe)
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
            InsightSection(
                title: insightID == .fitness ? "Fitness age over time"
                                             : "Heart age over time",
                trailing: points.yearsPerYear.map { String(format: "%.1f a year", $0) },
                caveat: .replayedHistory
            ) {
                // The window comes from the card's own picker, like every
                // other chart here. It used to fall back to the chart's
                // 365-day default because no call site passed one, so this
                // was the one section that ignored the control above it.
                AgeHistoryChart(points: points,
                                window: window(spanning: ageSpan(points)))
                if let pace = points.yearsPerYear {
                    Text(Self.pacePhrase(pace))
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                // Where this age goes next, on today's numbers. Both cards
                // computed a projection from the day they shipped and neither
                // drew one — see `projectionSection`.
                projectionSection
            }
        }
    }

    /// Where this card's own number goes next, on today's inputs.
    ///
    /// Both owners of `ageHistoryCard` computed a projection from the day they
    /// shipped and neither drew one. The risk card's is the starker case:
    /// `HeartAgeAnalyser` fills `Analysis.projections` and
    /// `CardiovascularRiskInsight` reads four other fields off that value and
    /// discards it — while the analyser's own `explanation` writes *"The
    /// projections below run the same validated equations at future ages"*, a
    /// sentence about a section that did not exist.
    ///
    /// The framing is fixed and is not a style choice: `docs/progress.md`
    /// records that lifetime risk was **deliberately not faked**, because
    /// nothing here is validated past 79 and compounding decades of ten-year
    /// risk invents a number. So these are the same equations run at ages they
    /// *are* validated for, labelled as a conditional.
    @ViewBuilder private var projectionSection: some View {
        switch insightID {
        case .cardiovascularRisk: riskProjectionSection
        case .fitness: fitnessProjectionSection
        default: EmptyView()
        }
    }

    @ViewBuilder private var riskProjectionSection: some View {
        let projections = model.heartAgeProjections()
        if projections.count >= 2 {
            Divider()
            NestedInsightSection(
                title: "If today's numbers hold",
                trailing: projections.last.map { "out to \(ageLabel($0))" },
                caveat: .ifTodaysNumbersHold
            ) {
                ForEach(projections, id: \.age) { projection in
                    HStack(spacing: 10) {
                        Text("at \(ageLabel(projection))")
                            .font(.subheadline.monospacedDigit())
                            .frame(width: 88, alignment: .leading)
                        // Dashed, because nobody measured this. Same rule as
                        // every projected line in the app.
                        RiskProjectionBar(percent: projection.percent,
                                          peak: projections.map(\.percent).max() ?? 1)
                        Text(String(format: "%.1f%%", projection.percent))
                            .font(.caption.monospacedDigit())
                            .frame(width: 46, alignment: .trailing)
                    }
                }
            }
        }
    }

    /// "79 or older" rather than an extrapolated number — the engines are only
    /// inverted inside their own validated bands, and printing 84 would be
    /// inventing one. Same rule the heart-age headline already follows.
    private func ageLabel(_ projection: HeartAgeModel.Projection) -> String {
        let age = Int(projection.age.rounded())
        return age >= 79 ? "79 or older" : "\(age)"
    }

    @ViewBuilder private var fitnessProjectionSection: some View {
        if let trajectory = model.fitnessTrajectory(), trajectory.readings >= 3 {
            Divider()
            NestedInsightSection(
                title: "Where this is heading",
                trailing: String(format: "%.1f in a year", trajectory.projectedIn12Months),
                caveat: .ifTodaysNumbersHold
            ) {
                FitnessProjectionChart(trajectory: trajectory)
                Text(String(format: "That would put your fitness age at %.0f, against %.0f now.",
                            trajectory.fitnessAgeIn12Months, trajectory.fitnessAgeNow))
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
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

        let placeholder = lines.isEmpty
            ? SectionPlaceholder.drivers(hasScore: result.score != nil)
            : nil

        // `.none`: every line here is the model narrating its own inputs. The
        // lines that *are* inferences say so in their own words, which is where
        // that judgement belongs.
        return InsightSection(
            title: "What's driving this",
            trailing: routine.isEmpty ? nil : "\(lines.count) signals",
            caveat: .none,
            expansion: expansion(preview: placeholder?.headline)
        ) {
            if let placeholder {
                emptySection(placeholder)
            } else if upfront.isEmpty {
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
    /// `ScoreHistory`.
    ///
    /// **Renders on every card.** A line needs two days on which at least two of
    /// the card's signals recorded, and on a realistic dataset four of the nine
    /// cards clear that on no day at all — so this section was absent more often
    /// than present, and its absence read as the chart having been taken away
    /// rather than as the data not being there. It now says which.
    private var scoreHistoryCard: some View {
        let history = model.scoreHistory(for: insightID)
        var placeholder: SectionPlaceholder?
        if history.count < 2 {
            placeholder = SectionPlaceholder.scoreHistory(
                points: history.count,
                isComputing: model.scoreHistoryIsPending(for: insightID))
        }

        return InsightSection(
            title: "Score over time",
            trailing: placeholder == nil ? trendPhrase(history) : nil,
            // The floor caveat explains which days were left out of a line.
            // With no line, it would be a footnote about nothing — and the
            // placeholder states the same floor as the reason instead.
            caveat: placeholder == nil ? SectionCaveat.scoreFloor : SectionCaveat.none,
            expansion: expansion(preview: placeholder?.headline)
        ) {
            if let placeholder {
                emptySection(placeholder)
            } else {
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
            InsightSection(title: "Today",
                           trailing: String(format: "%.0f spent of %.0f",
                                            energy.spent, energy.morningCharge),
                           caveat: .modelledCurve) {
                EnergyCurveChart(curve: energy.curve,
                                 morningCharge: energy.morningCharge)
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
            let jetlag = regularity.socialJetlagHours
            InsightSection(
                title: "Your fortnight",
                trailing: jetlag.flatMap { hours in
                    abs(hours) >= 0.5
                        ? String(format: "weekends %.1f h %@",
                                 abs(hours), hours > 0 ? "later" : "earlier")
                        : nil
                },
                caveat: .fittedCentre(nights: regularity.nights.count)
            ) {
                SleepOnsetStripChart(output: regularity)
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
            InsightSection(
                title: "Cardiovascular load",
                trailing: series.trendPerWeek.flatMap { perWeek in
                    abs(perWeek) >= 1
                        ? String(format: "%@%.0f a week", perWeek > 0 ? "+" : "−",
                                 abs(perWeek))
                        : nil
                },
                caveat: .decayingLoad
            ) {
                // Same fix as the age chart: the 90-day default was winning
                // over the picker.
                SubstanceLoadChart(points: series,
                                   window: window(spanning: loadSpan(series)))
            }
        }
    }

    /// The span each chart's own data covers, so `.all` doesn't squash a short
    /// history into a sliver. Three of these rather than one generic helper:
    /// the point types are unrelated and a protocol for `.date` would be more
    /// machinery than the six lines it saves.
    private func ageSpan(_ points: [AgePoint]) -> ClosedRange<Date>? {
        guard let first = points.first?.date, let last = points.last?.date,
              first <= last else { return nil }
        return first...last
    }

    private func compositionSpan(_ points: [BodyCompositionSplit.Dated]) -> ClosedRange<Date>? {
        guard let first = points.first?.date, let last = points.last?.date,
              first <= last else { return nil }
        return first...last
    }

    private func loadSpan(_ points: [SubstanceLoadPoint]) -> ClosedRange<Date>? {
        guard let first = points.first?.date, let last = points.last?.date,
              first <= last else { return nil }
        return first...last
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
    // MARK: - Phase 2 bespoke sections

    /// How a score divides between its inputs — **on every card**, and closed by
    /// default.
    ///
    /// It began as a bespoke section for the two cards that are weighted
    /// composites, Heart Health and Readiness. But "nothing here is weighted" is
    /// a fact about how a card works rather than a gap in the data, and it is
    /// precisely what a reader cannot infer from a missing section: Blood
    /// Pressure runs an estimator, Cardiovascular Risk runs published equations,
    /// Substance Impact reports what each signal did after a logged event. All
    /// three report their contributors at **weight 0 on purpose**, and that
    /// deliberate zero was invisible.
    ///
    /// Only weighted contributors are drawn. Readiness appends the vitals it
    /// merely *scans* at weight 0, and showing those as zero-width bars would
    /// imply they were weighed and found irrelevant, when in fact they were
    /// never in the average. They are counted in a footnote instead.
    private func weightedContributionCard(_ result: InsightResult) -> some View {
        // Not `resolvedContributions`: a stand-in's weights are absences rather
        // than zeroes, and this section is entirely about telling those apart.
        let weighted = result.contributors.weighted
        let scanned = result.contributors.count - weighted.count
        var placeholder: SectionPlaceholder?
        if weighted.isEmpty {
            placeholder = SectionPlaceholder.weighting(
                areReported: !result.contributors.isEmpty,
                contributorCount: result.contributors.count)
        }
        let slots = MetricPalette.slots(for: weighted.map(\.metric))

        return InsightSection(
            title: "How this is weighted",
            // The section whose whole subject is percentages had no
            // figure of its own until now.
            trailing: weighted.isEmpty ? "None" : "\(weighted.count) weighted",
            caveat: placeholder == nil && scanned > 0
                ? .unscored(signals: scanned)
                : SectionCaveat.none,
            // Open rather than empty-collapsed if both are somehow nil: a
            // closed section with a blank preview line is a dead end.
            expansion: expansion(preview: placeholder?.headline
                                 ?? result.contributors.weightingPreview)
        ) {
            if let placeholder {
                emptySection(placeholder)
            } else {
                Text("The share each signal has of the score, after dividing over the ones that had data today. A signal missing today isn't counted as zero — the others simply carry more.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                ForEach(weighted, id: \.metric) { contribution in
                    weightRow(contribution, slots: slots)
                }
            }
        }
    }

    /// Where your three comparable numbers sit against other people your age
    /// and sex. Deliberately positions on an axis rather than a distribution
    /// curve: the published sources give means and spreads, not full curves,
    /// and a bell curve would draw a precision the model does not have.
    ///
    /// Heart Health's bespoke slot in its own right now. It used to be nested
    /// under "How this is weighted", which was fine while that section was this
    /// card's bespoke one — but that section is now universal *and closed by
    /// default*, and a card's own picture of its own subject must not arrive
    /// hidden inside a collapsed generic section.
    @ViewBuilder private var peerStandingSection: some View {
        if let standing = PeerStandingModel.evaluate(samples: model.samples,
                                                     profile: model.profile),
           !standing.standings.isEmpty {
            InsightSection(
                title: "How you compare",
                trailing: "\(Int(standing.overall.rounded()))th centile overall",
                caveat: .approximateNorms
            ) {
                PeerStandingStrip(standings: standing.standings)
            }
        }
    }

    /// Every vital the scan looked at, as a distance from this person's own
    /// baseline. The scan already decided each verdict; this draws them on one
    /// axis so "one thing is off" is visible as a shape rather than counted out
    /// of a list of seventeen sentences.
    ///
    /// Readiness's bespoke slot, promoted for the same reason as the strip above.
    @ViewBuilder private var vitalDepartureSection: some View {
        let panel = VitalDeparturePanel.from(
            VitalSignsCheck.evaluate(samples: model.samples,
                                     events: model.vitalEvents))
        if !panel.isEmpty {
            InsightSection(
                title: "How far from your normal",
                trailing: "\(panel.rows.count) checked",
                caveat: panel.footnote.map { .computed(.partial, $0) } ?? .none
            ) {
                VitalDepartureStrip(panel: panel)
            }
        }
    }

    private func weightRow(_ contribution: MetricContribution,
                           slots: [MetricType: Int]) -> some View {
        let tint = Theme.metricColor(contribution.metric, slots: slots)
        return VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline) {
                Text(contribution.metric.displayName).font(.subheadline)
                Spacer()
                if !contribution.detail.isEmpty {
                    Text(contribution.detail)
                        .font(.caption).foregroundStyle(.secondary)
                }
                Text("\(Int((contribution.weight * 100).rounded()))%")
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(tint)
            }
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(tint.opacity(0.15))
                    Capsule().fill(tint)
                        .frame(width: max(2, geometry.size.width * contribution.weight))
                }
            }
            .frame(height: 6)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(contribution.metric.displayName), "
            + "\(Int((contribution.weight * 100).rounded())) percent of the score")
    }

    /// What the weight on the scale is made of.
    ///
    /// Body Composition narrates six measurements as separate lines and scores
    /// none of them — its contributor weights are deliberately zero — so it had
    /// numbers and no picture of the thing they jointly describe. The arithmetic
    /// is `BodyCompositionSplit` in InsightKit, where it is tested; this only
    /// draws it.
    /// Which substance a `Part` is, for the semantic palette. The legend still
    /// lists `parts` (the true partition of body mass) while the bar stacks
    /// `bands` (the same partition with the water share cut out of its host), so
    /// only the legend needs this.
    /// Which band a water inset's host metric refers to.
    private func kind(ofMetric metric: MetricType) -> BodyCompositionSplit.Band.Kind {
        metric == .muscleMass ? .muscle : .lean
    }

    private func kind(of part: BodyCompositionSplit.Part) -> BodyCompositionSplit.Band.Kind {
        switch part.metric {
        case .bodyFatPercentage: return .fat
        case .muscleMass: return .muscle
        case .boneMass: return .bone
        case .leanBodyMass: return part.label == "Lean" ? .lean : .otherLean
        default: return .otherLean
        }
    }

    @ViewBuilder private var bodyCompositionSplitCard: some View {
        if let split = BodyCompositionSplit.from(samples: model.samples) {
            // `.none`: every figure here is a reading off the scale. The two
            // notes below are *findings about the data* — a scale contradicting
            // itself — so they stay in the content in `Theme.warn`, where they
            // read as findings. A caveat is context and is always quiet.
            InsightSection(title: "What you're made of",
                           trailing: String(format: "%.1f kg", split.total),
                           caveat: .none) {
                Group {
                    // The same `bands` the trend chart stacks, so the bar and the
                    // chart below it cannot draw the same body differently — and
                    // the water drawn the same way too: a real translucent film
                    // laid over the intact muscle block, not a slice cut out of
                    // it. Carving it out is what made every previous attempt read
                    // as a third substance, whatever colour it was given.
                    GeometryReader { geometry in
                        let spacing = 1.5
                        let usable = geometry.size.width
                            - spacing * Double(max(0, split.bands.count - 1))
                        HStack(spacing: spacing) {
                            ForEach(split.bands) { band in
                                Rectangle()
                                    .fill(Theme.compositionColour(band.kind))
                                    .frame(width: max(2, usable * band.fraction))
                                    .overlay(alignment: .leading) {
                                        if let water = split.water,
                                           kind(ofMetric: water.host) == band.kind {
                                            Rectangle()
                                                .fill(Theme.waterHatch(colorScheme))
                                                .frame(width: max(2, usable * band.fraction)
                                                              * water.fractionOfHost)
                                        }
                                    }
                            }
                        }
                        .clipShape(Capsule())
                    }
                    .frame(height: 14)

                    ForEach(split.parts, id: \.metric) { part in
                        VStack(spacing: 3) {
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(Theme.compositionLegendColour(kind(of: part)))
                                    .frame(width: 8, height: 8)
                                Text(part.label).font(.subheadline)
                                Spacer()
                                Text(String(format: "%.1f kg", part.kilograms))
                                    .font(.caption.monospacedDigit())
                                Text("\(Int((part.fraction * 100).rounded()))%")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                                    .frame(width: 34, alignment: .trailing)
                            }
                            // The sub-dot: indented under its host, so the
                            // legend says "part of that" rather than "beside it".
                            if let water = split.water, water.host == part.metric {
                                HStack(spacing: 8) {
                                    Rectangle().fill(.clear).frame(width: 10)
                                    Image(systemName: "arrow.turn.down.right")
                                        .font(.system(size: 8))
                                        .foregroundStyle(.secondary)
                                    Circle().fill(Theme.compositionWater)
                                        .frame(width: 6, height: 6)
                                    Text("of which water").font(.caption)
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                    Text(String(format: "%.1f kg", water.kilograms))
                                        .font(.caption2.monospacedDigit())
                                        .foregroundStyle(.secondary)
                                    Text("\(Int((water.fractionOfHost * 100).rounded()))%")
                                        .font(.caption2.monospacedDigit())
                                        .foregroundStyle(.secondary)
                                        .frame(width: 34, alignment: .trailing)
                                }
                            }
                        }
                    }

                    if let water = split.water, water.exceedsHost {
                        Text("Your total body water is larger than the muscle it's drawn inside — ordinary, since blood and organs hold water too, but it means the shaded part is capped rather than exact.")
                            .font(.caption2).foregroundStyle(Theme.warn)
                            .fixedSize(horizontal: false, vertical: true)
                    } else if split.water != nil {
                        Text("The blue stripes are water, laid over the tissue holding it rather than given a block of its own — it's already counted there, and showing it twice would make you heavier than you are. Striped rather than shaded so the muscle red stays visible between them; the plain red beyond the stripes is the muscle that isn't water.")
                            .font(.caption2).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if split.isPartial {
                        Text("These readings don't quite add up to your weight — they come from separate estimates the scale makes independently.")
                            .font(.caption2).foregroundStyle(Theme.warn)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                bodyCompositionTrend
            }
        }
    }

    /// The same bands over time, zoomed by the screen's own timeframe picker —
    /// deliberately that control rather than a second one, so the card has one
    /// idea of "how far back" across all its sections.
    ///
    /// **The picker is the zoom, not a filter.** It used to slice the series and
    /// hand the chart only what survived, which is why this was one of two
    /// charts in the app you could not pan: there was nothing off-screen to
    /// scroll to. The chart now takes the whole series and shows a window of it,
    /// exactly like "Score over time" and the overlay.
    @ViewBuilder private var bodyCompositionTrend: some View {
        let series = BodyCompositionSplit.series(samples: model.samples)
        let visible = series.points
        // Two weigh-ins is the floor for a trend: one is the bar above again.
        if visible.count >= 2 {
            let begins = series.finerSplitBegins
            Divider()
            NestedInsightSection(
                title: "How that has changed",
                // One slot, one quantity. This used to fall back to a count of
                // weigh-ins when there was no delta — a different measurement
                // in the same position, with nothing to tell a reader which one
                // they were looking at. The count is in the caveat, where it is
                // context for the picture rather than the headline.
                trailing: BodyCompositionSplit.change(over: visible).map { change in
                    String(format: "%@%.1f kg", change.totalDelta > 0 ? "+" : "−",
                           abs(change.totalDelta))
                },
                caveat: .joined([
                    .compositionWindow(weighIns: visible.count),
                    begins.map { .splitOnlyFrom($0.formatted(date: .abbreviated, time: .omitted)) }
                        ?? .none
                ])
            ) {
                BodyCompositionTrendChart(points: visible, finerSplitBegins: begins,
                                          window: window(spanning: compositionSpan(visible)))
            }
        }
    }

    private func contributorsCard(_ result: InsightResult) -> some View {
        let contributions = resolvedContributions(result)
        let series = model.overlaySeries(for: insightID,
                                         contributions: contributions.contributions,
                                         timeframe: timeframe)
        let missing = contributions.metrics.filter { metric in
            !series.contains { $0.metric == metric }
        }
        let placeholder = series.isEmpty
            ? SectionPlaceholder.overlay(inputCount: contributions.metrics.count)
            : nil

        // `.none`: these are measured series. Where a gap is bridged the
        // chart draws it dashed and dimmed, which states the inference at
        // the place it happens rather than in a footnote about the whole
        // section.
        return InsightSection(
            title: "What goes into this",
            trailing: "\(series.count) of \(contributions.metrics.count)",
            caveat: .none,
            expansion: expansion(preview: placeholder?.headline)
        ) {
            if let placeholder {
                emptySection(placeholder)
            } else {
                Text(scale == .zScore
                     ? "Each signal against its own normal for this period, so they can be read against each other. The dashed line is your average. The list below is ordered by how far each signal has moved — tap any of them to add or remove it."
                     : "Measured values, in their own units. Signals with very different ranges will look flat next to each other — that's what the compare view is for.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                // The key to the legend line. Three facts on every row is only
                // an improvement if the reader knows what the third one means —
                // “tracked, not scored” in particular reads as a fault without
                // this, when it is a deliberate refusal to invent a weight. Not
                // said where the model reported no weights at all, because then
                // no row says it.
                //
                // Typographic quotes rather than markdown emphasis: the two
                // arms would have to agree on which `Text` overload the ternary
                // resolves to, and a stray asterisk on the card is not worth
                // finding out on the phone.
                legendKey(weightsReported: contributions.areReported)

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

    /// What the three parts of each legend line mean.
    @ViewBuilder
    private func legendKey(weightsReported: Bool) -> some View {
        let text = weightsReported
            ? "Every signal below says which way it is going, whether that is the direction you want for it, and how much of the score it carries. “Tracked, not scored” means the app charts it but has no validated scale to score it on, so it doesn’t move the number."
            : "Every signal below says which way it is going. This card doesn’t report a weighting or a preferred direction for its inputs, so neither is claimed here."
        Text(text)
            .font(.caption2).foregroundStyle(.tertiary)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// Contributions to chart: what the model reported, or its declared inputs
    /// where it reports nothing. Without the fallback, an insight that hasn't
    /// been migrated — or Substance Impact before its first logged event —
    /// would show an empty card rather than a chart.
    ///
    /// `ChartedContributions` carries *which of the two* it is, because the
    /// stand-ins' zeroes look exactly like a deliberate weight of zero and the
    /// legend now says that out loud. See its own documentation.
    private func resolvedContributions(_ result: InsightResult) -> ChartedContributions {
        .resolve(reported: result.contributors,
                 declaredInputs: candidateMetrics(for: insightID))
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
    ///
    /// **Renders on every card, always**, including when nothing clears the
    /// sample-count and effect-size floors — which is most of the time. It used
    /// to vanish then, and a vanishing section is an absence the reader cannot
    /// read: "no data", "not enough days" and "we looked and everything is
    /// steady" are three different answers and only the last is reassuring.
    /// `SectionPlaceholder` works out which one applies and says it.
    private func patternsCard(_ result: InsightResult) -> some View {
        let series = model.overlaySeries(for: insightID,
                                         contributions: resolvedContributions(result).contributions,
                                         timeframe: timeframe)
        let history = model.scoreHistory(for: insightID)
        let patterns = PatternFinder.patterns(in: series, against: history)
        var placeholder: SectionPlaceholder?
        if patterns.isEmpty {
            placeholder = SectionPlaceholder.patterns(series: series, score: history)
        }

        return InsightSection(
            title: "Patterns worth a look", icon: "lightbulb",
            // The same quantity either way — how many patterns — worded rather
            // than printed as "0 found", which reads like a broken counter.
            trailing: patterns.isEmpty ? "None yet" : "\(patterns.count) found",
            // The caveat qualifies findings. With none to qualify there is
            // nothing here that was inferred, and `.associationsNotCauses`
            // under an empty section would be warning about claims nobody made.
            caveat: patterns.isEmpty ? SectionCaveat.none : .associationsNotCauses,
            expansion: expansion(preview: placeholder?.headline
                                 ?? patterns[0].sentence)
        ) {
            if let placeholder {
                emptySection(placeholder)
            } else {
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
            }
        }
    }

    /// Closed behind its reason where a section is empty, open where it isn't.
    ///
    /// A function rather than `placeholder.map { .collapsed(…) } ?? .open` at
    /// four call sites: that form leans on leading-dot inference flowing back
    /// through `map` and `??`, and the app target is compiled only by CI, so a
    /// type-inference gamble costs a push-and-wait to settle.
    private func expansion(preview: String?) -> SectionExpansion {
        guard let preview, !preview.isEmpty else { return .open }
        return .collapsed(preview: preview)
    }

    /// What a section draws when it has nothing to show.
    ///
    /// Deliberately not `Theme.warn` and not a "no data" glyph: on most cards on
    /// most days this is the *good* answer, and drawing it as a fault would
    /// teach the reader to read an empty patterns card as a problem.
    private func emptySection(_ placeholder: SectionPlaceholder) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "checkmark.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 16)
            Text(placeholder.detail)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
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
    /// Renders on every card whatever it found, for the reason under
    /// `patternsCard` above — and here the empty answer is the more useful one,
    /// because "nothing runs ahead of your score" is a finding about your data
    /// that no reader could ever have inferred from a missing section.
    private func laggedCard(_ result: InsightResult) -> some View {
        let series = model.overlaySeries(for: insightID,
                                         contributions: resolvedContributions(result).contributions,
                                         timeframe: timeframe)
        let history = model.scoreHistory(for: insightID)
        let leads = LagFinder.relationships(between: series, and: history)
        var placeholder: SectionPlaceholder?
        if leads.isEmpty {
            placeholder = SectionPlaceholder.leads(series: series, score: history)
        }

        // This section had no footnote at all, and it makes the most
        // inferential claim on the screen: a correlation at a lag, fitted
        // through however many days the two series happen to overlap on.
        // The narrowest overlap is the honest number to quote — and where there
        // is no lag, nothing was fitted and there is nothing to caveat.
        return InsightSection(
            title: "What comes first", icon: "clock.arrow.circlepath",
            trailing: leads.isEmpty ? "None yet" : "\(leads.count) leading",
            caveat: leads.isEmpty
                ? SectionCaveat.none
                : .fittedThrough(points: leads.map(\.sampleCount).min() ?? 0),
            expansion: expansion(preview: placeholder?.headline ?? leads[0].sentence)
        ) {
            if let placeholder {
                emptySection(placeholder)
            } else {
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

    /// Has your normal itself moved? A z-score can't answer that — its baseline
    /// drifts along with the change, which is exactly how a slow decline stays
    /// invisible day to day.
    private func periodContrastCard(_ result: InsightResult) -> some View {
        let contributions = resolvedContributions(result).contributions
        let changes = PeriodContrast.changes(for: contributions, samples: model.samples)
        // Two reasons for an empty section — not enough history, or enough and
        // nothing moved — and only the second is reassuring. Asking how many
        // signals *could* be compared is what separates them.
        let placeholder = changes.isEmpty
            ? SectionPlaceholder.periodContrast(
                comparable: PeriodContrast.comparableCount(for: contributions,
                                                           samples: model.samples))
            : nil

        return InsightSection(
            title: "What changed",
            trailing: changes.isEmpty ? "No shift" : "\(changes.count) signals",
            caveat: changes.isEmpty
                ? SectionCaveat.none
                : .periodContrast(days: PeriodContrast.windowDays),
            expansion: expansion(preview: placeholder?.headline)
        ) {
            if let placeholder {
                emptySection(placeholder)
            } else {
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
            InsightSection(title: "Full history",
                           trailing: "\(metrics.count) signals",
                           caveat: .none) {
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
                    VStack(alignment: .leading, spacing: Theme.sectionSpacing) {
                        Text("Was this accurate?").font(.headline)
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
