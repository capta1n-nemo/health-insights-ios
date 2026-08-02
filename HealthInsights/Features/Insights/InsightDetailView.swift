import SwiftUI
import InsightKit

struct InsightDetailView: View {
    let insightID: InsightID
    @Environment(AppModel.self) private var model
    @State private var groundingKind: GroundingKind?
    @State private var feedbackGiven = false
    @State private var timeframe: Timeframe = .month
    /// The reader's own answer about their build, where they gave one. A
    /// preference about wording rather than an input to any model — see
    /// `somatotypeSection`.
    @AppStorage("somatotypeOverride") private var somatotypeOverrideRaw = ""

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
            sleepNightCard
        case .substanceImpact:
            substanceLoadCard
        // Heart Health and Readiness used to own "How you compare" and "How far
        // from your normal" as their bespoke sections. Both are universal now —
        // every card's inputs can be placed against a population and against
        // the reader's own baseline — which left Heart Health without a picture
        // of its own subject. `heartResponseCard` is that picture.
        case .heartHealth:
            heartResponseCard
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

    /// The window every timeframe-driven section reads, **pinned above the tab
    /// bar** rather than placed in the scroll.
    ///
    /// Five sections read it — the score chart, the bespoke charts, the overlay
    /// and both findings sections — and they are spread from position 3 to
    /// position 11 of fourteen. Anywhere in the scroll it would be out of reach
    /// from most of the sections it drives; at the top it is out of reach from
    /// nearly all of them.
    ///
    /// Its history is worth keeping, because it is the same mistake twice. It
    /// began *inside* "Score over time" while also driving four other sections,
    /// so an insight with too few replayable days lost the control for sections
    /// that still used it. Moving it out fixed that, and a `usesTimeframe` gate
    /// then hid it on cards where nothing read it — including the one case where
    /// widening the window is the remedy, a card with no series, which left
    /// `SectionPlaceholder` telling the reader to widen a timeframe that was not
    /// on screen. **Both bugs were the control being somewhere the reader
    /// wasn't**, and pinning it is the fix that has no third version.
    private var timeframeBar: some View {
        Picker("Timeframe", selection: $timeframe) {
            ForEach(Timeframe.allCases) { Text($0.shortLabel).tag($0) }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        // `.bar` rather than a solid fill: the content scrolling underneath
        // should be visible through it, so the bar reads as floating over the
        // card rather than as the card ending there.
        .background(.bar, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08))
        )
        .shadow(color: .black.opacity(0.12), radius: 8, y: 2)
        .padding(.horizontal)
        .padding(.bottom, 8)
    }

    var body: some View {
        ScrollView {
            // Lazy on purpose: a card is eleven-plus sections and several run
            // real models. Building only what is on screen is what makes the
            // push feel immediate; the sections below the fold build as they
            // scroll into view, each memoised so scrolling back is free.
            LazyVStack(alignment: .leading, spacing: Theme.spacing) {
                if let result {
                    // ─────────────────────────────────────────────────────────
                    // THE ORDER IS THE USER'S, AND IT HAS A RATIONALE.
                    //
                    // Set 2026-08-01. It reads top to bottom as *the number →
                    // why → how it moved → what it is made of → how it compares
                    // → the deep dives → the appendices*, and each position is
                    // argued in `docs/card-sections.md` ▸ "The order, and why".
                    // Read that before moving anything: three of these have been
                    // moved once already for reasons that are written down, and
                    // `scripts/card-map.sh --check` will fail if this list and
                    // that document disagree.
                    // ─────────────────────────────────────────────────────────

                    // 1. The score itself, at a glance.
                    headerCard(result)
                    // 2. Why it says that. The fastest read on the screen.
                    driversCard(result)
                    // 3. How the number has moved. The timeframe control that
                    // used to sit here is pinned above the tab bar instead —
                    // see `timeframeBar`.
                    scoreHistoryCard
                    // 4. The deltas, before any of the machinery behind them.
                    periodContrastCard(result)
                    // 5. The card's own picture of its own subject.
                    bespokeSection
                    // 5b. A second one, where the subject has two halves that
                    // are genuinely different questions. Only Body Composition
                    // has one: *what your body is made of* and *what you are
                    // doing about it* were sharing a slot, and the medication
                    // half had grown five sub-sections inside somebody else's
                    // heading. The user's call, 2026-08-02.
                    secondaryBespokeSection
                    // 6. What feeds the score, then 7. how much each counts —
                    // the overview before the arithmetic, for the reader who
                    // wants the science behind it.
                    contributorsCard(result)
                    weightedContributionCard(result)
                    // 8. You against everyone else, then 9. you against you.
                    peerStandingSection(result)
                    vitalDepartureSection(result)
                    // 10 and 11. The two findings sections: what the app noticed
                    // in the data, and what runs ahead of the score. Both arrive
                    // closed — see `SectionExpansion`.
                    patternsCard(result)
                    laggedCard(result)
                    // 12. The appendix: one link per input.
                    contributorLinksCard(result)
                    // 13. What the card asks *of* the reader. Gated here rather
                    // than inside the view: a struct View with an empty body is
                    // still a VStack child and would take spacing either side,
                    // so the three cards that ask for nothing would carry a
                    // double gap.
                    if !contributionRoutes.isEmpty {
                        ViewAndAddSection(cardTitle: result.title,
                                          metrics: resolvedContributions(result).metrics,
                                          routes: contributionRoutes,
                                          unmetRequirements: result.unmetRequirements)
                    }
                    // 14. The other thing asked of the reader.
                    feedbackCard(result)
                    // Chrome, not a section. Always last.
                    disclaimerCard
                } else {
                    ContentUnavailableView("Not available", systemImage: "questionmark")
                }
            }
            .padding()
        }
        // Pinned rather than placed in the scroll, so the control is in reach
        // from anywhere on a card that is now fourteen sections long.
        //
        // `safeAreaInset` rather than `overlay`: an overlay would sit *on top*
        // of the last section and permanently hide the bottom of the
        // disclaimer. An inset shortens the scrollable area by the bar's own
        // height, so everything can still be scrolled clear of it — and it
        // stacks above the tab bar's safe area on its own, with no hard-coded
        // guess at the tab bar's height.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if result != nil { timeframeBar }
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
    private var bloodPressureChartCard: some View {
        let readings = model.bloodPressureReadings
        var placeholder: SectionPlaceholder?
        if readings.isEmpty {
            placeholder = SectionPlaceholder.needsInput(
                subject: "This chart", what: "cuff readings you enter yourself")
        }
        // `.none`: these are cuff readings the user typed in, drawn as they
        // were entered. The estimator's own uncertainty is the header card's
        // subject, not this chart's.
        return InsightSection(title: "Your readings",
                              trailing: readings.first?.category,
                              caveat: .none,
                              expansion: expansion(preview: placeholder?.headline)) {
            if let placeholder {
                emptySection(placeholder)
            } else {
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
    private var ageHistoryCard: some View {
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
        var placeholder: SectionPlaceholder?
        if points.count < 3 {
            placeholder = SectionPlaceholder.needsMore(
                subject: "A line through your computed age",
                have: points.count, need: 3, noun: "replayed week")
        }

        return InsightSection(
            title: insightID == .fitness ? "Fitness age over time"
                                         : "Heart age over time",
            trailing: points.yearsPerYear.map { String(format: "%.1f a year", $0) },
            caveat: placeholder == nil ? SectionCaveat.replayedHistory
                                       : SectionCaveat.none,
            expansion: expansion(preview: placeholder?.headline)
        ) {
            if let placeholder {
                emptySection(placeholder)
            } else {
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
        if projections.count < 2 {
            Divider()
            NestedInsightSection(title: "If today's numbers hold", trailing: nil,
                                 caveat: .none) {
                emptySection(.needsMore(
                    subject: "Running the equations at future ages",
                    have: projections.count, need: 2, noun: "projected age"))
            }
        } else {
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
        let trajectory = model.fitnessTrajectory()
        let readings = trajectory?.readings ?? 0
        if trajectory == nil || readings < 3 {
            Divider()
            NestedInsightSection(title: "Where this is heading", trailing: nil,
                                 caveat: .none) {
                emptySection(.needsMore(
                    subject: "A trajectory through your VO₂max",
                    have: readings, need: 3, noun: "reading"))
            }
        } else if let trajectory {
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
            trailing: routine.isEmpty ? nil
                : "\(lines.count) \(SectionCaveat.plural(lines.count, "signal"))",
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
        // This is the card in view, so its replay wins the queue over the eight
        // the Insights list requested on open.
        let history = model.scoreHistory(for: insightID, prioritise: true)
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
    /// Sleep's bespoke slot: the night just slept, then the fortnight's shape —
    /// two pictures of one subject in one slot, the Body Composition pattern.
    ///
    /// "Last night in stages" exists because of 2026-07-29: Oura filed 4.3 h,
    /// Apple Health 8.5 h, and no aggregate could show both were true. One lane
    /// per source, stage bands, gaps left visible — the user's request, verbatim:
    /// show the gaps, show what type of sleep each part was, and let the
    /// disagreement between sources be seen instead of averaged.
    @ViewBuilder private var sleepNightCard: some View {
        let detail = model.memoized("nightSleepDetail") {
            NightSleepDetail.latest(raw: model.otherSamples, samples: model.samples)
        }
        InsightSection(
            title: "Last night in stages",
            trailing: detail.flatMap { d in
                d.lanes.first.map { String(format: "%.1f h asleep", $0.asleepHours) }
            },
            caveat: .none
        ) {
            if let detail {
                NightSleepChart(detail: detail)
            } else {
                emptySection(SectionPlaceholder.needsInput(
                    subject: "A night drawn in stages",
                    what: "a sleep source",
                    remedy: "connect Oura (stage detail) or let Apple Health "
                        + "record sleep, under Settings"))
            }

            Divider()

            if let regularity = model.sleepRegularity(),
               regularity.nights.count >= CircadianConsistencyModel.minimumNights {
                let jetlag = regularity.socialJetlagHours
                NestedInsightSection(
                    title: "Your fortnight",
                    trailing: jetlag.flatMap { hours in
                        abs(hours) >= 0.5
                            ? String(format: "weekends %.1f h %@",
                                     abs(hours), hours > 0 ? "later" : "earlier")
                            : nil
                    },
                    caveat: .fittedCentre(nights: regularity.nights.count)
                ) {
                    SleepOnsetStripChart(
                        output: regularity,
                        // A year of bedtimes, not the scored fortnight: the strip
                        // re-fits its centre and band over whatever comes into
                        // view, so it needs something to scroll to.
                        allNights: model.sleepOnsetNights(),
                        window: window(spanning: nightsSpan(model.sleepOnsetNights())))
                }
            } else {
                NestedInsightSection(title: "Your fortnight", trailing: nil,
                                     caveat: .none) {
                    emptySection(SectionPlaceholder.needsMore(
                        subject: "The shape of your fortnight",
                        have: model.sleepRegularity()?.nights.count ?? 0,
                        need: CircadianConsistencyModel.minimumNights,
                        noun: "night with a recorded bedtime",
                        plural: "nights with recorded bedtimes"))
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
        if series.count < 7 {
            let reason = SectionPlaceholder.needsMore(
                subject: "The decaying load curve", have: series.count, need: 7,
                noun: "day of logs", plural: "days of logs")
            InsightSection(title: "Cardiovascular load", trailing: nil,
                           caveat: .none,
                           expansion: expansion(preview: reason.headline)) {
                emptySection(reason)
            }
        } else {
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

    private func nightsSpan(_ nights: [VitalReader.DailyValue]) -> ClosedRange<Date>? {
        guard let first = nights.first?.date, let last = nights.last?.date,
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
    /// Two groups, and the split between them is the point: what carries a share
    /// of the number, and what this card draws without scoring.
    ///
    /// The second group used to be a **count** in the caveat — "5 signals
    /// tracked, not scored" — which cannot answer the question a reader
    /// actually has. Fitness charts five of them and Readiness eleven, and
    /// "which of these moved my number" is unanswerable from a number. Naming
    /// them is also what stops a signal being invisible here while it is drawn
    /// two sections down: heart-rate recovery is the whole of Heart Health's own
    /// bespoke section and appeared in neither.
    ///
    /// Rows are `ScoreFactor`, not `MetricContribution`, because the risk card's
    /// inputs are mostly things no sensor reports — a date of birth, a blood
    /// test — and they carry most of its number. See `ScoreWeighting`.
    private func weightedContributionCard(_ result: InsightResult) -> some View {
        // Not `resolvedContributions`: a stand-in's weights are absences rather
        // than zeroes, and this section is entirely about telling those apart.
        let weighted = result.weightedFactors
        let unweighted = result.unweightedFactors
        var placeholder: SectionPlaceholder?
        if weighted.isEmpty {
            placeholder = SectionPlaceholder.weighting(
                basis: result.weighting,
                areReported: !result.contributors.isEmpty,
                contributorCount: result.contributors.count)
        }
        // Hues come from the metric-backed rows only, so a factor with no metric
        // cannot take a slot the overlay chart has already given to a series.
        let slots = MetricPalette.slots(for: (weighted + unweighted).compactMap(\.metric))

        return InsightSection(
            title: "How this is weighted",
            // The section whose whole subject is percentages had no
            // figure of its own until now.
            trailing: weighted.isEmpty ? "None" : "\(weighted.count) weighted",
            caveat: placeholder == nil && !unweighted.isEmpty
                ? .unscored(signals: unweighted.count)
                : SectionCaveat.none,
            // Open rather than empty-collapsed if both are somehow nil: a
            // closed section with a blank preview line is a dead end.
            expansion: expansion(preview: placeholder?.headline
                                 ?? weighted.weightingPreview)
        ) {
            if let placeholder {
                emptySection(placeholder)
                // Even with nothing to weight, what the card *reads* is worth
                // naming here — this is the section a reader opens to ask it.
                if !unweighted.isEmpty {
                    Divider()
                    unweightedGroup(unweighted, slots: slots)
                }
            } else {
                Text(result.weighting.explanation)
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                ForEach(weighted, id: \.self) { factor in
                    weightRow(factor, slots: slots)
                }
                // Age and sex sit in the same list because they genuinely carry
                // the risk card's largest share, and a reader has to be able to
                // tell the bar they can move from the one they cannot.
                if weighted.contains(where: { !$0.isModifiable }) {
                    Text("Marked \(Image(systemName: "lock.fill")) is not something you can change — it is the risk that comes with your age and sex, and it is here so the rest can be read against it.")
                        .font(.caption2).foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !unweighted.isEmpty {
                    Divider()
                    unweightedGroup(unweighted, slots: slots)
                }
            }
        }
    }

    /// What the card draws but does not score, named rather than counted.
    @ViewBuilder
    private func unweightedGroup(_ factors: [ScoreFactor],
                                 slots: [MetricType: Int]) -> some View {
        Text("Charted, not scored")
            .font(.subheadline.weight(.semibold))
        Text("Everything this card reads carries a share of the number above, however small — except these, and each row says why it doesn't.")
            .font(.caption).foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        ForEach(factors, id: \.self) { factor in
            HStack(alignment: .firstTextBaseline) {
                if let metric = factor.metric {
                    Circle().fill(Theme.metricColor(metric, slots: slots))
                        .frame(width: 7, height: 7)
                }
                Text(factor.name).font(.subheadline)
                Spacer()
                if !factor.detail.isEmpty {
                    Text(factor.detail)
                        .font(.caption).foregroundStyle(.secondary)
                        .multilineTextAlignment(.trailing)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(factor.name), \(factor.detail), charted but not scored")
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
    /// Heart Health's own picture: how the heart responds to a hard effort, and
    /// where the autonomic pair has drifted.
    ///
    /// It replaced "How you compare", which went universal — and the replacement
    /// is deliberately not another risk number. SCORE2 and ASCVD are validated
    /// 40–69 and 40–79, so everything else this app says about the heart is
    /// silent to a young reader. Heart rate recovery is the one cardiac marker
    /// whose published threshold is a fixed count of beats rather than a curve
    /// through age, which is what lets this section say the same thing at 25
    /// and at 65. See `HeartResponseModel` for the sources.
    @ViewBuilder private var heartResponseCard: some View {
        let response = model.memoized("heartResponse") {
            HeartResponseModel.evaluate(samples: model.samples)
        }
        if response.isEmpty {
            let reason = SectionPlaceholder.needsInput(
                subject: "How your heart responds",
                what: "a recorded workout, which is where a recovery reading "
                    + "comes from, plus a few days of resting rate and variability",
                // Not a grounding fact either — nothing under "View & add" can
                // record a workout.
                remedy: "record a workout with your watch and this fills in on "
                    + "the next sync")
            InsightSection(title: "How your heart responds", trailing: nil,
                           caveat: .none,
                           expansion: expansion(preview: reason.headline)) {
                emptySection(reason)
            }
        } else {
            InsightSection(
                title: "How your heart responds",
                trailing: response.recovery.map { String(format: "−%.0f bpm in a minute", $0) },
                caveat: .computed(.approximate,
                                  "The 12-beat mark is from a published cohort study "
                                    + "(Cole et al., NEJM 1999) and describes populations, "
                                    + "not people. One reading after one workout is not a "
                                    + "finding — the direction over months is the part "
                                    + "worth reading."),
                expansion: expansion(preview: heartResponsePreview(response))
            ) {
                if let recovery = response.recovery, let band = response.recoveryBand {
                    recoveryRow(recovery, band: band)
                }
                if !response.autonomic.isEmpty {
                    if response.recovery != nil { Divider() }
                    Text("Resting rate and variability, read off the same beat-to-beat signal.")
                        .font(.caption).foregroundStyle(.secondary)
                    ForEach(response.autonomic) { signal in
                        autonomicRow(signal)
                    }
                    if let sentence = response.autonomicSentence {
                        Text(sentence)
                            .font(.caption).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    private func heartResponsePreview(_ response: HeartResponseModel.Output) -> String {
        if let recovery = response.recovery, let band = response.recoveryBand {
            return String(format: "Your heart dropped %.0f beats in the minute after "
                          + "your last hard effort — %@", recovery, band.phrase)
        }
        return "Resting rate and variability, without a recovery reading yet"
    }

    /// The recovery figure against the one published mark, drawn as a position
    /// on a line rather than as a verdict: the cut-point is a population hazard
    /// ratio and a single workout is not a diagnosis.
    private func recoveryRow(_ bpm: Double,
                             band: HeartResponseModel.RecoveryBand) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("Heart rate recovery").font(.subheadline)
                Spacer()
                Text(String(format: "−%.0f bpm", bpm))
                    .font(.subheadline.weight(.semibold)).monospacedDigit()
                    .foregroundStyle(band == .attenuated ? Theme.warn : Theme.good)
            }
            Text("How far your heart rate fell in the first minute after your last "
                 + "hard effort — \(band.phrase).")
                .font(.caption2).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            RecoveryScale(bpm: bpm)
            Text("A fall of \(Int(HeartResponseModel.attenuatedRecovery)) beats or "
                 + "fewer is the published cut-point; around "
                 + "\(Int(HeartResponseModel.typicalRecovery)) is typical on a wrist "
                 + "device. Unlike a risk score, that mark is the same number at "
                 + "every age.")
                .font(.caption2).foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func autonomicRow(_ signal: HeartResponseModel.Signal) -> some View {
        HStack(spacing: 8) {
            Circle().fill(Theme.metricColor(signal.metric,
                                            slots: MetricPalette.slots(for: [signal.metric])))
                .frame(width: 8, height: 8)
            Text(signal.metric.displayName).font(.subheadline)
            Spacer()
            if let perWeek = signal.perWeek, let improving = signal.isImproving {
                Text(String(format: "%@%.1f a week", perWeek > 0 ? "+" : "−", abs(perWeek)))
                    .font(.caption).monospacedDigit()
                    .foregroundStyle(improving ? Theme.good : Theme.warn)
            } else {
                Text("steady").font(.caption).foregroundStyle(.secondary)
            }
            Text(MetricValueFormatter.string(signal.value, signal.metric))
                .font(.subheadline.weight(.medium)).monospacedDigit()
        }
    }

    private func peerStandingSection(_ result: InsightResult) -> some View {
        let metrics = resolvedContributions(result).metrics
        let standing = model.memoized("peerStanding.\(insightID.rawValue)") {
            PeerStandingModel.evaluate(metrics: metrics,
                                       samples: model.samples,
                                       profile: model.profile)
        }
        var placeholder: SectionPlaceholder?
        if standing == nil {
            if model.profile.age() == nil || model.profile.sex == nil {
                // Without an age and a sex there is no norm table to pick, and
                // that is the one gap on this section the reader can close
                // today. The remedy must be a section this card actually has:
                // the daily cards render no "View & add" at all, and pointing a
                // reader at a section that isn't on the screen is the same
                // failure as pointing at one that says "All set".
                placeholder = SectionPlaceholder.needsInput(
                    subject: "Comparing you with other people",
                    what: "your date of birth and sex",
                    remedy: contributionRoutes.isEmpty
                        ? "add them under \"View & add\" on the Heart Health card"
                        : "see \"View & add\" near the bottom of this card")
            } else {
                // `evaluate` also returns nil when it was handed no metrics at
                // all. The profile is set, so claiming it isn't would be false
                // — this arm exists so a transient empty state can never borrow
                // the missing-details copy.
                placeholder = SectionPlaceholder.notComputable(
                    subject: "Comparing you with other people",
                    because: "needs at least one of this card's signals to have "
                        + "a reading first. This fills in on its own as data "
                        + "arrives.")
            }
        }
        let drawn = standing?.standings ?? []
        let unNormed = standing?.unNormed ?? []
        let byCategory = standing?.assessedByCategory ?? []

        return InsightSection(
            title: "How you compare",
            trailing: drawn.isEmpty
                ? nil
                : "\(Int((standing?.overall ?? 0).rounded()))th centile overall",
            caveat: drawn.isEmpty ? SectionCaveat.none : .approximateNorms,
            expansion: expansion(preview: placeholder?.headline
                                 ?? comparePreview(drawn: drawn, unNormed: unNormed))
        ) {
            if let placeholder {
                emptySection(placeholder)
            } else {
                if !drawn.isEmpty {
                    PeerStandingStrip(standings: drawn)
                }
                if !byCategory.isEmpty {
                    categoryAssessedRows(byCategory, hasStandings: !drawn.isEmpty)
                }
                if !unNormed.isEmpty {
                    unNormedRows(unNormed,
                                 hasStandings: !drawn.isEmpty || !byCategory.isEmpty)
                }
            }
        }
    }

    /// Signals this card judges against a reference that isn't a centile — blood
    /// pressure, placed into ACC/AHA stages. Split out of the "no published
    /// norm" list because it is the opposite claim: these *are* assessed, just
    /// not here. The user found systolic and diastolic sitting under "nobody has
    /// published a distribution", which reads as the app not knowing what a
    /// healthy blood pressure is when it has a whole card that does.
    @ViewBuilder private func categoryAssessedRows(_ metrics: [MetricType],
                                                   hasStandings: Bool) -> some View {
        if hasStandings { Divider() }
        Text("Placed by clinical category, not a centile")
            .font(.caption.weight(.medium))
        ForEach(metrics, id: \.self) { metric in
            HStack(spacing: 8) {
                Image(systemName: "cross.case")
                    .font(.caption2).foregroundStyle(.tertiary).frame(width: 14)
                Text(metric.displayName).font(.subheadline).foregroundStyle(.secondary)
                Spacer()
            }
        }
        Text("Blood pressure is read against the ACC/AHA stages — normal, elevated, stage 1, stage 2 — rather than ranked against a population. The category is a stronger statement than a percentile, and drawing both would be two answers to one question. Your reading and its stage are on the Blood Pressure card.")
            .font(.caption2).foregroundStyle(.tertiary)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// The closed line for "How you compare".
    private func comparePreview(drawn: [PeerStandingModel.Standing],
                                unNormed: [MetricType]) -> String {
        guard let best = drawn.max(by: { $0.percentile < $1.percentile }) else {
            return "No published norms for this card's signals yet"
        }
        let rest = unNormed.isEmpty
            ? ""
            : " · \(unNormed.count) with no published norms"
        return "\(best.metric.displayName): \(best.phrase) for your age and sex\(rest)"
    }

    /// The signals this card reads that no published distribution covers.
    ///
    /// Listed rather than dropped. A section showing two rows out of nine
    /// implies the other seven were checked and found unremarkable, when in
    /// fact nobody has published a distribution to check them against — the gap
    /// is in the literature, not in the reader's data, and only saying so
    /// distinguishes the two.
    @ViewBuilder private func unNormedRows(_ metrics: [MetricType],
                                           hasStandings: Bool) -> some View {
        if hasStandings { Divider() }
        Text(hasStandings
             ? "No published norms for these yet"
             : "None of this card's signals has a published norm yet")
            .font(.caption.weight(.medium))
        ForEach(metrics, id: \.self) { metric in
            HStack(spacing: 8) {
                Image(systemName: "questionmark.circle")
                    .font(.caption2).foregroundStyle(.tertiary).frame(width: 14)
                Text(metric.displayName).font(.subheadline).foregroundStyle(.secondary)
                Spacer()
            }
        }
        Text("Placing a reading against a population needs somebody to have published one, by age and sex. Nobody has for these — they are mostly signals only wearables measure, and the research hasn't caught up. Comparing them against other people using this app is on the roadmap; nothing here is sent anywhere today.")
            .font(.caption2).foregroundStyle(.tertiary)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// Every vital the scan looked at, as a distance from this person's own
    /// baseline. The scan already decided each verdict; this draws them on one
    /// axis so "one thing is off" is visible as a shape rather than counted out
    /// of a list of seventeen sentences.
    ///
    /// Readiness's bespoke slot, promoted for the same reason as the strip above.
    private func vitalDepartureSection(_ result: InsightResult) -> some View {
        // Readiness's subject *is* the whole scan, so it keeps all seventeen
        // vitals; every other card is narrowed to the signals it reads. A Sleep
        // card drawing seventeen rows would answer a question nobody asked and
        // bury the two that are about sleep.
        let scan = model.memoized("vitalScan") {
            VitalSignsCheck.evaluate(samples: model.samples,
                                     events: model.vitalEvents)
        }
        let cardMetrics = insightID == .readiness
            ? nil : resolvedContributions(result).metrics
        let panel = VitalDeparturePanel.from(scan, limitedTo: cardMetrics)
        var placeholder: SectionPlaceholder?
        if let cardMetrics, Set(cardMetrics).isDisjoint(with: VitalSignsCheck.coveredMetrics) {
            // Not a history problem and never will be: the scan watches
            // point-in-time vitals, and nothing this card reads is one. Saying
            // "not enough history … arrives on its own" here was two false
            // claims under a legend already quoting each signal's SD from
            // baseline — the departure the reader wants is on this same screen.
            placeholder = SectionPlaceholder.notComputable(
                subject: "This card's signals",
                because: "aren't among the vitals the daily scan watches — it "
                    + "covers point-in-time readings like heart rate, blood "
                    + "pressure and temperature. How far each of this card's "
                    + "signals sits from your own normal is already shown "
                    + "beside it under \"What goes into this\".")
        } else if panel.isEmpty {
            placeholder = SectionPlaceholder.notComputable(
                subject: "This card's signals",
                because: "need enough of your own history to have a normal "
                    + "before a departure from it means anything. None of them "
                    + "has that yet — a baseline is built from your past "
                    + "readings, so this arrives on its own.")
        }
        return InsightSection(
            title: "How far from your normal",
            trailing: panel.isEmpty ? nil : "\(panel.rows.count) checked",
            caveat: panel.isEmpty
                ? SectionCaveat.none
                : panel.footnote.map { .computed(.partial, $0) } ?? .none,
            expansion: expansion(preview: placeholder?.headline
                                 ?? departurePreview(panel))
        ) {
            if let placeholder {
                emptySection(placeholder)
            } else {
                VitalDepartureStrip(panel: panel)
            }
        }
    }

    /// The closed line for "How far from your normal". Names the furthest-out
    /// signal, or says plainly that nothing is out — which on most days is the
    /// answer, and is the one worth being able to read without opening anything.
    private func departurePreview(_ panel: VitalDeparturePanel) -> String {
        guard let worst = panel.rows.first, worst.band != .ordinary else {
            return "Everything is where it usually is"
        }
        return "\(worst.metric.displayName) is \(String(format: "%.1f", abs(worst.z))) "
            + "SD \(worst.z > 0 ? "above" : "below") your usual"
    }

    /// One share, as a bar.
    ///
    /// A factor with no metric behind it — the risk card's age and sex, its
    /// cholesterol, the substance load — takes the neutral accent rather than a
    /// palette slot: those slots are the overlay chart's identity encoding, and
    /// handing one to something that draws no series would put a line's colour
    /// under a row that has none.
    private func weightRow(_ factor: ScoreFactor,
                           slots: [MetricType: Int]) -> some View {
        let tint = factor.metric.map { Theme.metricColor($0, slots: slots) } ?? Theme.accent
        return VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline) {
                if !factor.isModifiable {
                    Image(systemName: "lock.fill")
                        .font(.caption2).foregroundStyle(.tertiary)
                }
                Text(factor.name).font(.subheadline)
                Spacer()
                if !factor.detail.isEmpty {
                    Text(factor.detail)
                        .font(.caption).foregroundStyle(.secondary)
                        .multilineTextAlignment(.trailing)
                }
                Text("\(Int((factor.weight * 100).rounded()))%")
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(tint)
            }
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(tint.opacity(0.15))
                    Capsule().fill(tint)
                        .frame(width: max(2, geometry.size.width * factor.weight))
                }
            }
            .frame(height: 6)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(factor.name), "
            + "\(Int((factor.weight * 100).rounded())) percent of the score"
            + (factor.isModifiable ? "" : ", not something you can change"))
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
        // Memoised, and computed once rather than once per branch — this used
        // to run the split over the full sample set twice back to back.
        let memoisedSplit = model.memoized("bodySplit") {
            BodyCompositionSplit.from(samples: model.samples)
        }
        if memoisedSplit == nil {
            let reason = SectionPlaceholder.needsInput(
                subject: "The split of your weight",
                what: "a scale that reports body fat alongside your weight",
                // Not a grounding fact, so "View & add" can't close this gap —
                // a smart scale connects under Settings, or writes body fat to
                // Apple Health on its own.
                remedy: "connect one (Withings, or any scale that writes body "
                    + "fat to Apple Health) under Settings")
            InsightSection(title: "What you're made of", trailing: nil,
                           caveat: .none,
                           expansion: expansion(preview: reason.headline)) {
                emptySection(reason)
            }
        } else if let split = memoisedSplit {
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
        let series = model.memoized("bodySplitSeries") {
            BodyCompositionSplit.series(samples: model.samples)
        }
        let visible = series.points
        // Two weigh-ins is the floor for a trend: one is the bar above again.
        if visible.count < 2 {
            Divider()
            NestedInsightSection(title: "How that has changed", trailing: nil,
                                 caveat: .none) {
                emptySection(.needsMore(subject: "A trend through your weigh-ins",
                                        have: visible.count, need: 2,
                                        noun: "weigh-in"))
            }
        } else {
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

        // Your build belongs with what you are made of. The medication moved
        // out to `weightManagementCard` — see `secondaryBespokeSection`.
        Divider()
        somatotypeSection
    }

    /// The second bespoke slot: **Weight management**.
    ///
    /// Split out of "What you're made of" on 2026-08-02 at the user's request.
    /// The two halves answer different questions — one is a measurement of the
    /// body, the other is an intervention and its effect — and the medication
    /// half had grown to five sub-sections under a heading that said nothing
    /// about it.
    ///
    /// `EmptyView` for every other card, and it costs them nothing: a `switch`
    /// in a `@ViewBuilder` with an `EmptyView` arm contributes no spacing.
    @ViewBuilder private var secondaryBespokeSection: some View {
        switch insightID {
        case .bodyComposition:
            MedicationSection(window: window(spanning: nil))
        default:
            EmptyView()
        }
    }

    /// `@AppStorage` cannot hold an optional enum, so it round-trips through
    /// the raw value with empty standing for "use the estimate".
    private var somatotypeOverride: Binding<Somatotype.Component?> {
        Binding(get: { Somatotype.Component(rawValue: somatotypeOverrideRaw) },
                set: { somatotypeOverrideRaw = $0?.rawValue ?? "" })
    }

    /// The three-component build estimate, with the reader's override.
    ///
    /// Stored in `@AppStorage` rather than as a grounding fact: it is a
    /// preference about how the app should describe them, not a measurement any
    /// model reads. Nothing scores off it, which is exactly why it can be a
    /// free choice.
    @ViewBuilder private var somatotypeSection: some View {
        let estimate = model.memoized("somatotype") {
            SomatotypeModel.estimate(
                bodyFatPercentage: model.samples.latestValue(.bodyFatPercentage),
                leanMassKg: model.samples.latestValue(.leanBodyMass),
                weightKg: model.samples.latestValue(.bodyMass) ?? 0,
                heightMetres: model.samples.latestValue(.height) ?? 0,
                dimensions: nil,
                age: model.profile.age() ?? 35,
                sex: model.profile.sex ?? .male)
        }
        if let estimate {
            SomatotypeCard(somatotype: estimate, override: somatotypeOverride)
        } else {
            NestedInsightSection(title: "Your build", trailing: nil, caveat: .none) {
                emptySection(SectionPlaceholder.needsInput(
                    subject: "An estimate of your build",
                    what: "your height and a recent weight",
                    remedy: "add your height in Apple Health, or step on a connected scale"))
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
            // A spinner where the section is genuinely working (the replay), a
            // static tick where it is simply empty. The two states read
            // identically in words — "Working out your history" corrects itself
            // in a second — so the reader needs the motion to tell "loading"
            // from "nothing here".
            Group {
                if placeholder.isLoading {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "checkmark.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
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
        let changes = model.memoized("periodContrast.\(insightID.rawValue)") {
            PeriodContrast.changes(for: contributions, samples: model.samples)
        }
        // Two reasons for an empty section — not enough history, or enough and
        // nothing moved — and only the second is reassuring. Asking how many
        // signals *could* be compared is what separates them.
        let placeholder = changes.isEmpty
            ? SectionPlaceholder.periodContrast(
                comparable: model.memoized("periodComparable.\(insightID.rawValue)") {
                    PeriodContrast.comparableCount(for: contributions,
                                                   samples: model.samples)
                })
            : nil

        return InsightSection(
            title: "What changed",
            trailing: changes.isEmpty ? "No shift"
                : "\(changes.count) \(SectionCaveat.plural(changes.count, "signal"))",
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
                           trailing: "\(metrics.count) \(SectionCaveat.plural(metrics.count, "signal"))",
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
