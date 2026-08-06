import SwiftUI
import InsightKit

/// A non-metric input to a card — a grounding fact or a derived figure — shaped
/// for the two contributor sections that were metric-only. See
/// `InsightDetailView.auxiliaryInputs`.
private struct AuxInput: Identifiable {
    let id: String
    let name: String
    let detail: String
    /// Its share of the score, where it carries one.
    let share: Double?
    /// Where a tap goes, for a grounding fact; `nil` for a derived figure.
    let groundingKind: GroundingKind?
    let isModifiable: Bool
}

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
        case .symptomRadar:
            // The radar itself: the seven watched signals, each z-score, its
            // direction and whether it is leaning — roadmap #31's "which
            // signals moved is more actionable than a score".
            symptomRadarWebCard
        case .biologicalAge:
            // Every marker's own answer, its own error bar and its own share,
            // on one axis of years. This is the section that makes the card not
            // a black box, so it is the card's bespoke slot rather than an
            // extra.
            biologicalAgeMarkersCard
        case .gait:
            // The decomposition. Backlog S1 called this the worst of the five
            // missing sections and it is right: `speed = step length × cadence`
            // is the *whole* reason this card exists, and with no section it
            // reached the reader as one driver line inside a generic card.
            gaitDecompositionCard
        case .mentalHealth:
            // Four behaviours on one signed axis, so "several things moved the
            // same way" is a picture rather than an assertion.
            mentalHealthChannelsCard
        case .sustainedLoad:
            sustainedLoadChannelsCard
        case .nutrition:
            micronutrientCard
        case .metabolism:
            energyBalanceCard
        // ⚠️ **The one card whose bespoke picture is drawn universally.**
        // Readiness's subject *is* the seventeen-vital scan, and
        // `vitalDepartureSection` — which was Readiness's bespoke slot before it
        // was promoted — still keeps all seventeen rows for this card and
        // narrows to the card's own signals for every other. Drawing a second
        // one here would render the same strip twice.
        //
        // This case exists so that fact is a decision rather than an omission.
        // An audit on 2026-08-06 listed Readiness among the cards "with no
        // bespoke section", which was true of the switch and false of the
        // screen — the cost of reading a `default:` instead of the card.
        case .readiness:
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
                    VStack(alignment: .trailing, spacing: 4) {
                        ConfidenceBadge(confidence: result.confidence)
                        // Same reason as on the card row: the badge says
                        // "Experimental" while the dial may be reading a real
                        // cuff, so the other figure belongs next to the badge
                        // that is describing it.
                        if let subheadline = result.subheadline {
                            Text(subheadline)
                                .font(.caption2).foregroundStyle(.secondary)
                                .multilineTextAlignment(.trailing)
                        }
                    }
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
            // "+1.4 years a year" rather than "1.4 a year". The unit was
            // missing on both this section and the projection beneath it, and
            // two unitless figures in different units stacked on one card is
            // how 68 and 31.7 came to look like a contradiction. The sign is
            // explicit too: for an age, up is the bad direction, and a bare
            // number does not say which way it is going.
            trailing: points.yearsPerYear.map { String(format: "%+.1f years a year", $0) },
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
                // **Both quantities, both named.** This section plots VO₂max
                // and sits directly beneath "Fitness age over time", which
                // plots years — and until 2026-08-04 its trailing figure was a
                // bare "29.9 in a year" with the unit rendered nowhere at all.
                // So a *falling* VO₂max line read as a *falling* (improving)
                // fitness age, the exact opposite of what the model says: the
                // reader saw 31.7 here against 68 above and asked why the card
                // contradicted itself. It never did — one card, one series, two
                // units, neither of them stated.
                title: "Where your VO₂max is heading",
                trailing: String(format: "%.1f mL/kg·min · age %.0f",
                                 trajectory.projectedIn12Months,
                                 trajectory.fitnessAgeIn12Months),
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
            // **"notes", not "signals".** These are sentences the model wrote,
            // and one signal can legitimately earn more than one — a reading
            // plus the event it raised. Calling them signals put a count here
            // that disagreed with every other section's on the same card, and
            // the reader had no way to know the two words meant different
            // things. The other four sections all count signals and now agree.
            trailing: routine.isEmpty ? nil
                : "\(lines.count) \(SectionCaveat.plural(lines.count, "note"))",
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
                VStack(alignment: .leading, spacing: 12) {
                    EnergyCurveChart(curve: energy.curve,
                                     morningCharge: energy.morningCharge)
                    // The reader could not read this chart, and the header said
                    // "84 spent of 96" with nothing anywhere saying what a unit
                    // is or where the morning figure came from. It is the one
                    // chart whose subject is inside a day, and it was the only
                    // one with no sentence attached.
                    if let how = EnergyCurveExplainer.howItWorks(energy) {
                        Text("How this works").font(.subheadline.weight(.semibold))
                        Text(how).font(.footnote).foregroundStyle(.secondary)
                    }
                    Text("So what?").font(.subheadline.weight(.semibold))
                    Text(EnergyCurveExplainer.soWhat(energy))
                        .font(.footnote).foregroundStyle(.secondary)
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

            Divider()
            sleepOnsetSection
        }
    }

    /// "How fast you fall asleep" — the reader's own request: a graph of nightly
    /// sleep latency with its drift, and a deep-dive on what moves it, from the
    /// four things the app can actually see (substances, medication, temperature,
    /// how active the day was). What it can't see is named rather than left as a
    /// silent gap.
    @ViewBuilder private var sleepOnsetSection: some View {
        // `sleepOnsetAnalysis()` caches in the model, so no render-memo wrapper.
        let analysis = model.sleepOnsetAnalysis()
        NestedInsightSection(
            title: "How fast you fall asleep",
            trailing: analysis.map { "\(Int($0.medianMinutes.rounded())) min typical" },
            caveat: .associationsNotCauses
        ) {
            if let analysis {
                Text(onsetTrendSentence(analysis))
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                SleepOnsetChart(points: analysis.nights,
                                window: window(spanning: onsetSpan(analysis.nights)))

                if analysis.drivers.isEmpty {
                    Text("Nothing the app can see stood out as moving it over this stretch — not your substances, medication, temperature or how active the day was. That is the usual answer, and a reassuring one.")
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("What looks like it's moving it")
                        .font(.caption.weight(.medium))
                    ForEach(analysis.drivers) { driver in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: onsetDriverIcon(driver.factor))
                                .font(.caption).foregroundStyle(Theme.accent)
                                .frame(width: 16)
                            Text(driver.sentence)
                                .font(.caption).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }

                Text("Can't see: \(analysis.unseenFactors.joined(separator: ", ")). These matter for a lot of people and aren't on your phone, so they're not in the picture above — worth keeping in mind before blaming what is.")
                    .font(.caption2).foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                emptySection(SectionPlaceholder.needsMore(
                    subject: "How fast you fall asleep",
                    have: model.sleepOnsetAnalysis()?.nightsAnalysed ?? 0,
                    need: SleepOnsetModel.minimumNights,
                    noun: "night with a recorded sleep-onset time",
                    plural: "nights with recorded sleep-onset times"))
            }
        }
    }

    private func onsetTrendSentence(_ analysis: SleepOnsetModel.Output) -> String {
        guard let trend = analysis.trend, trend.isMeaningful else {
            return "Around \(Int(analysis.medianMinutes.rounded())) minutes to fall asleep on a typical night, steady over the last while — no clear drift up or down."
        }
        let perWeek = abs(trend.slopePerWeek)
        let direction = trend.slopePerWeek > 0 ? "longer" : "shorter"
        return String(format: "Taking about %.0f min %@ to fall asleep each week over this window — days scatter about %.0f min either side of that line, so it's a drift, not a promise.",
                      perWeek, direction, trend.residualSD)
    }

    private func onsetDriverIcon(_ factor: SleepOnsetModel.Factor) -> String {
        switch factor {
        case .substances: return "wineglass"
        case .medication: return "pills"
        case .temperature: return "thermometer.medium"
        case .eveningExertion: return "figure.run"
        case .screenTime: return "iphone"
        }
    }

    /// The radar web: this morning's watch verdict, drawn as the shape it is.
    ///
    /// `HealthWatchModel.evaluate` is pure and `model.samples` is a stored,
    /// observed property, so computing it in the body both tracks the
    /// dependency and cannot disagree with the result the card renders — they
    /// are the same evaluation. The view never reads `model.symptoms`:
    /// everything tag-derived reaches this screen through `InsightResult`.
    @ViewBuilder private var symptomRadarWebCard: some View {
        InsightSection(
            title: "The radar",
            trailing: nil,
            caveat: .computed(.partial,
                              "Each spoke is one watched signal's last three days "
                              + "against your own three-week baseline. Distance from "
                              + "the centre is how far it is leaning the illness way "
                              + "— movement in the healthy direction sits at the "
                              + "centre, because \"not leaning\" is the claim.")
        ) {
            if let watch = HealthWatchModel.evaluate(samples: model.samples,
                                                     now: Date(),
                                                     calendar: .current) {
                SymptomRadarWebCard(output: watch, tint: Theme.insightTint(.symptomRadar))
            } else {
                emptySection(SectionPlaceholder.needsMore(
                    subject: "The radar",
                    have: 0, need: HealthWatchModel.minimumReferenceDays,
                    noun: "day of overnight vitals",
                    plural: "days of overnight vitals"))
            }
            radarScorecard
        }
    }

    /// **The radar's report on itself** — backlog #36.
    ///
    /// The original refusal was right about the hard part: an honest
    /// *sensitivity* figure is years away at one symptom tag, and this card must
    /// never print one. What it was wrong about is that there is nothing
    /// printable today. **How often this card spoke, and how much of the window
    /// it could see at all, are facts about the reader's own record**, and they
    /// are the two numbers that make a quiet radar readable: green over 30%
    /// coverage means something very different from green over 95%.
    ///
    /// ⚠️ **Two blocks, never mixed, and the separation is the design.** What it
    /// did on this record is descriptive and carries no truth claim. What it was
    /// designed to do is a simulation under a stated assumption. Merging them is
    /// how a design budget becomes a measured accuracy.
    ///
    /// Nothing here is titled "accuracy", and no hit rate, sensitivity or
    /// positive predictive value appears — every one of those needs a symptom
    /// log this reader does not have, and printing a degenerate one would be
    /// worse than printing nothing.
    @ViewBuilder private var radarScorecard: some View {
        let ledger = model.memoized("radarDayCounters") {
            SymptomRadarModel.dayCounters(samples: model.samples)
        }
        if let flagRate = ledger.flagRate, let coverage = ledger.coverage {
            Divider()
            VStack(alignment: .leading, spacing: 6) {
                Text("What this card has done on your record")
                    .font(.subheadline.weight(.medium))
                scorecardRow("Days it said something",
                             String(format: "%d of %d judged · %.0f%%",
                                    ledger.flaggedDays, ledger.gradedDays, flagRate * 100))
                if ledger.strongDays > 0 {
                    scorecardRow("Of those, at its strongest", "\(ledger.strongDays)")
                }
                scorecardRow("Days it could judge at all",
                             String(format: "%d of %d · %.0f%%",
                                    ledger.gradedDays, ledger.windowDays, coverage * 100))
                Text(coverage < 0.7
                     ? "It was blind for \(ledger.windowDays - ledger.gradedDays) of those days — nothing worn, or nothing synced. A quiet card over patchy coverage is not the same as a quiet card over a full one, and this is the number that tells them apart."
                     : "Coverage that high means a quiet card is genuinely quiet rather than absent.")
                    .font(.caption2).foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)

                Divider().padding(.vertical, 2)
                Text("What it was designed to do")
                    .font(.subheadline.weight(.medium))
                Text("The bands were set to a stated false-alarm budget of about two mornings a year, under the assumption that the signals are only partly correlated. That is a design figure from a simulation, not a measurement of you — the line above is the measurement.")
                    .font(.caption2).foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("⚠️ It cannot tell you how often it is right. The best published validation of this approach catches under half of what it looks for, so a quiet radar is not reassurance — and grading it against your own symptom tags needs far more of them than exist here.")
                    .font(.caption2).foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func scorecardRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Spacer()
            Text(value).font(.caption.weight(.medium)).monospacedDigit()
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

    private func onsetSpan(_ nights: [SleepOnsetModel.Sample]) -> ClosedRange<Date>? {
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

    // MARK: - Gait: which half of the speed change moved

    /// **The card's reason to exist, drawn.**
    ///
    /// `speed = step length × cadence` is an identity, so taking logs makes the
    /// change additive and the two shares sum to the whole *without any
    /// fitting*. That is the one thing this app can say about walking that no
    /// competitor can, and until now it reached the reader as a single sentence
    /// among nine driver lines.
    ///
    /// Drawn by hand rather than with Swift Charts: this is a one-dimensional
    /// split of a single quantity, not a series, so the substance shading every
    /// chart carries would have no time axis to sit on.
    @ViewBuilder private var gaitDecompositionCard: some View {
        let out = model.memoized("gait") { GaitModel.evaluate(samples: model.samples) }
        if let out, let split = out.split, let share = split.stepLengthShare {
            InsightSection(
                title: "Which half moved",
                trailing: String(format: "%@%.0f%% speed",
                                 split.speedChange >= 0 ? "+" : "−",
                                 abs(split.speedChange) * 100),
                caveat: .computed(.approximate,
                                  "Speed is step length times cadence exactly, so these two shares "
                                    + "are an identity rather than a fit — nothing here is fitted or "
                                    + "assumed. What they describe is the walking your phone was in "
                                    + "your pocket for."),
                expansion: expansion(preview: gaitSplitPreview(split, share: share))
            ) {
                gaitShareBar(stepLengthShare: share)
                gaitSplitRow("Step length", change: split.stepLengthChange,
                             metric: .walkingStepLength, out: out)
                gaitSplitRow("Cadence — steps per second", change: split.cadenceChange,
                             metric: nil, out: out)
                Divider()
                Text(gaitSplitSentence(split, share: share))
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } else if out != nil {
            InsightSection(
                title: "Which half moved",
                trailing: nil,
                caveat: .none,
                expansion: expansion(preview: "Too small a change to apportion")
            ) {
                Text("Your walking speed is within half a percent of your previous year. That is too small a difference to divide into step length and rhythm — splitting a rounding error into halves produces two confident-looking numbers about nothing.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func gaitSplitPreview(_ split: GaitModel.SpeedSplit, share: Double) -> String {
        share >= 0.6 ? "Mostly your step length"
            : (share <= 0.4 ? "Mostly your rhythm" : "Both, about equally")
    }

    /// The one sentence that says what the split *means*, which is the part a
    /// percentage cannot carry.
    private func gaitSplitSentence(_ split: GaitModel.SpeedSplit, share: Double) -> String {
        let slower = split.speedChange < 0
        if share >= 0.6 {
            return slower
                ? "Shorter steps at much the same rhythm. That pattern tracks caution, stiffness and pain more than it tracks fitness — it is what someone does when each step costs something."
                : "Longer steps at much the same rhythm, which is usually confidence or range of movement rather than effort."
        }
        if share <= 0.4 {
            return slower
                ? "The same length of step, taken less often. That tracks drive and fatigue rather than the mechanics of the step itself."
                : "The same length of step, taken more often — a change of pace rather than of stride."
        }
        return "Step length and rhythm moved together, in about equal measure, which is what a general change in pace looks like rather than a change in how you step."
    }

    /// Two proportions of one change. A single bar rather than two, because the
    /// shares sum to the whole and drawing them apart would invite reading them
    /// as independent quantities.
    private func gaitShareBar(stepLengthShare: Double) -> some View {
        let length = min(max(stepLengthShare, 0), 1)
        return VStack(alignment: .leading, spacing: 6) {
            GeometryReader { geometry in
                HStack(spacing: 2) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Theme.accent.opacity(0.75))
                        .frame(width: max(0, (geometry.size.width - 2) * length))
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Theme.accent.opacity(0.28))
                }
                .frame(height: 12)
            }
            .frame(height: 12)
            HStack {
                Text(String(format: "Step length %.0f%%", length * 100))
                    .font(.caption2).foregroundStyle(.secondary)
                Spacer()
                Text(String(format: "Rhythm %.0f%%", (1 - length) * 100))
                    .font(.caption2).foregroundStyle(.tertiary)
            }
        }
    }

    /// One half of the split, with its own figures where the app holds them.
    ///
    /// Cadence has no `MetricType` and deliberately does not get one: nothing
    /// publishes it, and it is *derived* from two numbers the phone already
    /// writes. A metric case would put a fourth walking line on every chart to
    /// say what the other two already say.
    @ViewBuilder private func gaitSplitRow(_ label: String, change: Double,
                                           metric: MetricType?,
                                           out: GaitModel.Output) -> some View {
        HStack(spacing: 8) {
            Text(label).font(.subheadline)
            Spacer()
            if let metric, let channel = out.channels.first(where: { $0.metric == metric }) {
                Text(MetricValueFormatter.string(channel.recent, metric))
                    .font(.caption).monospacedDigit().foregroundStyle(.secondary)
            }
            Text(String(format: "%@%.1f%%", change >= 0 ? "+" : "−", abs(change) * 100))
                .font(.subheadline.weight(.medium)).monospacedDigit()
                .foregroundStyle(change < 0 ? Theme.warn : Theme.good)
        }
    }

    // MARK: - Mental health: four behaviours on one signed axis

    /// **Several unrelated things moving the same way is the only claim this
    /// card makes**, so it has to be visible as a shape rather than asserted in
    /// a sentence. One axis, zero in the middle, right is the direction low mood
    /// usually shows.
    @ViewBuilder private var mentalHealthChannelsCard: some View {
        let out = model.memoized("mentalHealth") {
            MentalHealthModel.evaluate(samples: model.samples)
        }
        if let out {
            InsightSection(
                title: "What moved, and which way",
                trailing: out.moved.isEmpty ? nil : "\(out.moved.count) of \(out.readings.count)",
                caveat: .computed(.approximate,
                                  "Each bar is that behaviour against your own previous "
                                    + "\(MentalHealthModel.referenceDays) days, not against anybody "
                                    + "else. Right is the direction low mood usually shows — which "
                                    + "is a direction, not a diagnosis, and every one of these has "
                                    + "an ordinary explanation."),
                expansion: expansion(preview: out.moved.isEmpty
                                     ? "None of the \(out.readings.count) has moved much"
                                     : out.moved.map(\.channel.label).joined(separator: ", "))
            ) {
                ForEach(out.readings) { reading in
                    mentalHealthChannelRow(reading)
                }
                Divider()
                if out.readings.count < MentalHealthModel.channels.count {
                    Text("\(MentalHealthModel.channels.count - out.readings.count) of the \(MentalHealthModel.channels.count) behaviours this watches had too few days in the last fortnight to compare, so they are not here at all.")
                        .font(.caption2).foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text("A bar near the middle means that behaviour is sitting where it usually sits. It does not mean anything about how the fortnight felt.")
                    .font(.caption2).foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// The shared strip, plus the one thing this card adds to it: the innocent
    /// explanation, on the row, always.
    ///
    /// `hasMoved`'s own threshold is passed through rather than re-stated here.
    /// Two copies of "what counts as moved" is how a card ends up disagreeing
    /// with its own driver lines about which signals shifted.
    private func mentalHealthChannelRow(_ reading: MentalHealthModel.Reading) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            signedDepartureRow(label: reading.channel.label,
                               towardBad: reading.towardLowMood,
                               figure: nil,
                               threshold: 0.8)
            Text(reading.channel.alternative)
                .font(.caption2).foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Stress load: the four channels, and how long they have been there

    /// The same signed strip as mental health, over four nocturnal channels
    /// against a season.
    ///
    /// **Why this card needed a picture more than most:** its whole claim is
    /// *duration* — Readiness answers this morning and the radar answers "is
    /// something converging", so the only thing this card adds is that a drift
    /// has persisted. A single number cannot show persistence, and the four
    /// driver lines it shipped with could not either.
    @ViewBuilder private var sustainedLoadChannelsCard: some View {
        let out = model.memoized("sustainedLoad") {
            SustainedLoadModel.evaluate(samples: model.samples)
        }
        if let out {
            let leaning = out.channels.filter { $0.loadZ >= 0.5 }
            InsightSection(
                title: "Where the load is sitting",
                trailing: leaning.isEmpty ? nil : "\(leaning.count) of \(out.channels.count)",
                caveat: .computed(.approximate,
                                  "Each bar is that signal's last \(SustainedLoadModel.recentDays) "
                                    + "days against your previous \(SustainedLoadModel.referenceDays), "
                                    + "not against a published normal. Right is toward load."),
                // ⚠️ The count is derived. This said "All four" and the card was
                // running on three, because one channel had too few days — the
                // same fault as the copy inside `MentalHealthModel`, found on
                // the same screenshot.
                expansion: expansion(preview: leaning.isEmpty
                                     ? "All \(out.channels.count) sitting where they usually sit"
                                     : leaning.map { $0.metric.displayName }.joined(separator: ", "))
            ) {
                ForEach(out.channels, id: \.metric) { channel in
                    signedDepartureRow(
                        label: channel.metric.displayName,
                        towardBad: channel.loadZ,
                        figure: String(format: "%@ → %@",
                                       MetricValueFormatter.string(channel.reference, channel.metric),
                                       MetricValueFormatter.string(channel.recent, channel.metric)))
                }
                Divider()
                Text("These are the same signals Readiness and the symptom radar read. The difference is the window: this one asks whether a drift has *lasted*, which neither of the others can see.")
                    .font(.caption2).foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Nutrition: the eight vitamins and minerals

    /// **The section that makes this card's mandatory ask honest.**
    ///
    /// Nutrition demands sex and date of birth *because* the eleven
    /// micronutrients cannot be scored without them — a rationale that was
    /// untrue from the day it shipped until `MicronutrientEstimate` was wired
    /// on 2026-08-06. This is where the reader finally sees what those two facts
    /// bought them.
    ///
    /// A logged nutrient and a modelled one are drawn differently and are never
    /// summed into one verdict: the modelled figure answers "what would an
    /// ordinary diet this size carry", which is a fact about diets and not about
    /// this reader.
    @ViewBuilder private var micronutrientCard: some View {
        let out = model.memoized("nutritionMicros") {
            NutritionModel.evaluate(samples: model.samples, profile: model.profile)
        }
        if let micros = out?.micronutrients {
            let short = micros.rows.filter { $0.standing == .below }
            InsightSection(
                title: "Vitamins and minerals",
                trailing: "\(micros.loggedCount) of \(micros.rows.count) from your log",
                caveat: .computed(micros.estimatedCount > 0 ? .estimated : .partial,
                                  MicronutrientEstimate.caveat(estimatedCount: micros.estimatedCount,
                                                               of: micros.rows.count)),
                expansion: expansion(preview: short.isEmpty
                                     ? "All \(micros.rows.count) reach their published floor"
                                     : "Under: " + short.map(\.metric.displayName)
                                        .joined(separator: ", "))
            ) {
                ForEach(micros.rows) { row in
                    micronutrientRow(row)
                }
            }
        }
    }

    private func micronutrientRow(_ row: MicronutrientEstimate.Row) -> some View {
        // Fraction of the recommended floor, capped for drawing at twice it —
        // beyond that the bar says nothing more, and none of these eight has
        // evidence that more is better above the RDA.
        let fraction = min(row.intake / max(row.target.recommended, 0.0001), 2) / 2
        let overCeiling = row.standing == .aboveUpperLimit
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                // A hollow marker for a modelled figure and a filled one for a
                // logged figure — the same visual grammar the app uses for
                // modifiable versus locked inputs, so it does not have to be
                // learnt twice.
                Image(systemName: row.isEstimated ? "circle" : "circle.fill")
                    .font(.system(size: 7)).foregroundStyle(.tertiary).frame(width: 9)
                Text(row.metric.displayName).font(.subheadline)
                Spacer()
                Text(MetricValueFormatter.string(row.intake, row.metric))
                    .font(.caption).monospacedDigit()
                    .foregroundStyle(row.standing == .met ? .secondary
                                     : (overCeiling ? Theme.warn : Theme.warn))
            }
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.secondary.opacity(0.12)).frame(height: 5)
                    Capsule()
                        .fill(row.standing == .met ? Theme.good : Theme.warn)
                        .opacity(row.isEstimated ? 0.35 : 0.8)
                        .frame(width: max(2, geometry.size.width * fraction), height: 5)
                    // The published floor, at half width by construction.
                    Rectangle().fill(Color.primary.opacity(0.3))
                        .frame(width: 1, height: 11)
                        .offset(x: geometry.size.width * 0.5)
                }
                .frame(height: 11)
            }
            .frame(height: 11)
        }
        .padding(.vertical, 1)
    }

    // MARK: - Metabolism: observed against predicted

    /// Two bars and the gap between them, which is the whole card.
    ///
    /// The ratio on the dial is a speed; **what a reader actually wants to see
    /// is the two numbers it came from**, because a ratio of 0.9 built from a
    /// 1,400 kcal log means something very different from one built from 2,800.
    @ViewBuilder private var energyBalanceCard: some View {
        let out = model.memoized("metabolism") {
            EnergyBalanceModel.evaluate(samples: model.samples, profile: model.profile)
        }
        if let out, let predicted = out.predictedTDEE {
            let ceiling = max(out.observedTDEE, predicted) * 1.1
            InsightSection(
                title: "What you burn against what you should",
                trailing: out.speed.map { String(format: "%.0f%%", $0 * 100) },
                caveat: .computed(.fitted,
                                  "The observed figure is back-calculated from what you logged and "
                                    + "how your weight moved, so **every logging error is charged to "
                                    + "your metabolism** — an incomplete food log reads as a fast "
                                    + "one. \(out.loggedDays) of the last \(out.windowDays) days "
                                    + "carry a log."),
                expansion: expansion(preview: String(format: "%.0f against %.0f kcal a day",
                                                     out.observedTDEE, predicted))
            ) {
                energyBalanceBar("Observed", value: out.observedTDEE, ceiling: ceiling,
                                 tint: Theme.accent)
                energyBalanceBar("Predicted for your size", value: predicted, ceiling: ceiling,
                                 tint: Color.secondary)
                if let basal = out.basal, let method = out.basalMethod {
                    Divider()
                    HStack {
                        Text("Resting, before you move (\(method))")
                            .font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Text(String(format: "%.0f kcal", basal))
                            .font(.caption).monospacedDigit().foregroundStyle(.secondary)
                    }
                }
                Text(String(format: "Intake %.0f kcal a day, movement %.0f — a deficit of %.0f, which is about %.2f kg a week.",
                            out.intakeMean, out.activeMean, out.deficitPerDay,
                            abs(out.kilogramsPerWeek)))
                    .font(.caption2).foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func energyBalanceBar(_ label: String, value: Double,
                                  ceiling: Double, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label).font(.subheadline)
                Spacer()
                Text(String(format: "%.0f kcal", value))
                    .font(.subheadline.weight(.medium)).monospacedDigit()
            }
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.secondary.opacity(0.12)).frame(height: 8)
                    Capsule().fill(tint.opacity(0.7))
                        .frame(width: max(2, geometry.size.width * min(value / max(ceiling, 1), 1)),
                               height: 8)
                }
                .frame(height: 8)
            }
            .frame(height: 8)
        }
        .padding(.vertical, 2)
    }

    // MARK: - The shared signed-departure strip

    /// One signal against the reader's own usual, zero in the middle, **right is
    /// always the unwelcome direction**.
    ///
    /// Shared by Stress load and Mental health rather than written twice: both
    /// draw a signed departure in SDs, and two implementations of one encoding
    /// is exactly how the same silence ends up with two renderings — a defect
    /// this repo has already shipped once, in the chart gap bridges.
    private func signedDepartureRow(label: String, towardBad: Double,
                                    figure: String?, threshold: Double = 0.5) -> some View {
        let scale = 3.0
        let fraction = min(max(towardBad / scale, -1), 1)
        let leaning = abs(towardBad) >= threshold
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(label).font(.subheadline)
                Spacer()
                if let figure {
                    Text(figure).font(.caption).monospacedDigit().foregroundStyle(.tertiary)
                }
                Text(leaning ? String(format: "%.1f SD", abs(towardBad)) : "about usual")
                    .font(.caption).monospacedDigit()
                    .foregroundStyle(leaning && towardBad > 0 ? Theme.warn : .secondary)
            }
            GeometryReader { geometry in
                let half = geometry.size.width / 2
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.secondary.opacity(0.12)).frame(height: 6)
                    Rectangle().fill(Color.primary.opacity(0.35))
                        .frame(width: 1, height: 14).offset(x: half)
                    Capsule()
                        .fill((towardBad > 0 ? Theme.warn : Theme.good)
                            .opacity(leaning ? 0.75 : 0.3))
                        .frame(width: max(2, abs(fraction) * half), height: 6)
                        .offset(x: fraction >= 0 ? half : half - abs(fraction) * half)
                }
                .frame(height: 14)
            }
            .frame(height: 14)
        }
        .padding(.vertical, 2)
    }

    // MARK: - Biological age: every marker's own answer

    /// **The section that stops this card being a black box.**
    ///
    /// Each marker gets one row on a shared axis of years: a bar for its own
    /// error, a dot for its own answer, and its share of the final number. The
    /// reader's real age is a vertical line through all of them.
    ///
    /// Drawn by hand rather than with Swift Charts on purpose. The x axis here
    /// is *age in years*, not time, so the substance shading every chart carries
    /// would be meaningless on it — the same reason `FitnessProjectionChart` is
    /// exempt — and a five-row strip is less code without a `Chart` than with
    /// one.
    @ViewBuilder private var biologicalAgeMarkersCard: some View {
        let out = model.memoized("biologicalAge") {
            BiologicalAgeModel.evaluate(samples: model.samples,
                                        profile: model.profile)
        }
        if let out {
            InsightSection(
                title: "What each marker says",
                trailing: String(format: "±%.0f years", out.uncertaintyYears),
                caveat: .computed(.approximate,
                                  "Every bar is one marker's own answer and its own error. "
                                    + "They are combined by precision, so the narrow bars "
                                    + "count for more — that weighting is arithmetic from "
                                    + "the norm tables, not a choice anybody made."),
                expansion: expansion(preview: biologicalAgePreview(out))
            ) {
                let span = biologicalAgeSpan(out)
                ForEach(out.markers) { marker in
                    biologicalAgeRow(marker, chronological: out.chronologicalAge, span: span)
                }
                Divider()
                biologicalAgeRow(nil, chronological: out.chronologicalAge, span: span,
                                 combined: out)
                if let age = out.chronologicalAge {
                    Text(String(format: "The dotted line is you, at %.0f.", age))
                        .font(.caption2).foregroundStyle(.tertiary)
                }
            }
        }
    }

    /// The axis both the rows and the combined bar share. Widened to hold every
    /// error bar **and** the reader's real age, so no row can be drawn clipped
    /// at an edge and read as pinned there.
    private func biologicalAgeSpan(_ out: BiologicalAgeModel.Output) -> ClosedRange<Double> {
        var low = out.range.lowerBound
        var high = out.range.upperBound
        for marker in out.markers {
            low = min(low, marker.ageEquivalent - marker.uncertaintyYears)
            high = max(high, marker.ageEquivalent + marker.uncertaintyYears)
        }
        if let age = out.chronologicalAge {
            low = min(low, age - 3)
            high = max(high, age + 3)
        }
        // Clamp to the model's own reportable range, then guarantee a width so
        // the division below can never be by zero.
        low = max(BiologicalAgeModel.youngest - 2, low)
        high = min(BiologicalAgeModel.oldest + 2, high)
        return low...max(low + 1, high)
    }

    private func biologicalAgePreview(_ out: BiologicalAgeModel.Output) -> String {
        guard let strongest = out.markers.first else { return "" }
        return String(format: "%@ carries %.0f%% of it", strongest.label,
                      strongest.weight * 100)
    }

    /// One marker's row, or — when `combined` is set — the answer itself.
    @ViewBuilder private func biologicalAgeRow(
        _ marker: BiologicalAgeModel.Marker?,
        chronological: Double?,
        span: ClosedRange<Double>,
        combined: BiologicalAgeModel.Output? = nil
    ) -> some View {
        let centre = combined?.biologicalAge ?? marker?.ageEquivalent ?? 0
        let error = combined?.uncertaintyYears ?? marker?.uncertaintyYears ?? 0
        let title = combined == nil ? (marker?.label ?? "") : "Combined"
        let width = span.upperBound - span.lowerBound

        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(title)
                    .font(combined == nil ? .subheadline : .subheadline.weight(.semibold))
                Spacer()
                Text(String(format: "%.0f ±%.0f", centre, error))
                    .font(.caption).monospacedDigit().foregroundStyle(.secondary)
                if let marker {
                    Text(String(format: "%.0f%%", marker.weight * 100))
                        .font(.caption.weight(.medium)).monospacedDigit()
                        .frame(width: 38, alignment: .trailing)
                } else {
                    Text("100%")
                        .font(.caption.weight(.medium)).monospacedDigit()
                        .frame(width: 38, alignment: .trailing)
                }
            }
            GeometryReader { geometry in
                let scale = geometry.size.width / width
                let barStart = (max(span.lowerBound, centre - error) - span.lowerBound) * scale
                let barEnd = (min(span.upperBound, centre + error) - span.lowerBound) * scale
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.secondary.opacity(0.12))
                        .frame(height: 6)
                    Capsule()
                        .fill((combined == nil ? Theme.accent : Theme.good).opacity(0.28))
                        .frame(width: max(2, barEnd - barStart), height: 6)
                        .offset(x: barStart)
                    Circle()
                        .fill(combined == nil ? Theme.accent : Theme.good)
                        .frame(width: 9, height: 9)
                        .offset(x: (centre - span.lowerBound) * scale - 4.5)
                    if let chronological,
                       span.contains(chronological) {
                        Rectangle()
                            .fill(Color.primary.opacity(0.45))
                            .frame(width: 1.5, height: 16)
                            .offset(x: (chronological - span.lowerBound) * scale)
                    }
                }
                .frame(height: 16)
            }
            .frame(height: 16)
            if let marker, !marker.caveat.isEmpty, combined == nil {
                Text(marker.caveat)
                    .font(.caption2).foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 2)
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
        // Readiness's subject *is* the whole scan, so it keeps every scan row;
        // every other card narrows to its own signals. Either way the card's
        // **contributors** each earn a row — that is what stopped sleep duration
        // (scored at 0.20 on Readiness, no clinical spec) being counted under
        // "What goes into this" and missing here. The rule lives in InsightKit,
        // where `ContributorDepartureTests` can hold it.
        let contributionMetrics = resolvedContributions(result).metrics
        let panel = VitalDeparturePanel.forCard(
            scan,
            cardMetrics: insightID == .readiness ? nil : contributionMetrics,
            contributorMetrics: contributionMetrics,
            samples: model.samples)
        var placeholder: SectionPlaceholder?
        if panel.isEmpty {
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
        //
        // The body model leads the nested block: it is the picture of the
        // subject, and the split and the build estimate are both readings *of*
        // it. Nested rather than a third top-level bespoke slot — the ordering
        // block in `docs/card-sections.md` is generated from this file and a
        // new slot moves four hand-written tables with it, for a section that
        // belongs beside these two anyway.
        Divider()
        BodyOverTimeSection()
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
        // Roadmap #18. A second, genuinely different question about this card's
        // own subject — *how old does each thing think you are* sits beside
        // *what is your risk*, and neither is the other. The same slot, and the
        // same reasoning, as Body Composition's medication half.
        case .cardiovascularRisk:
            ageComparisonSection
        default:
            EmptyView()
        }
    }

    /// **Relay, never merge — and print the error.**
    ///
    /// Whoop sells a "WHOOP Age" and Oura prints a cardiovascular age; neither
    /// publishes what its number is worth. Every row here names who computed it
    /// and what its error is, and where a vendor publishes none, that sentence
    /// *is* the row. See `AgeComparison`, where all of it is decided and tested.
    @ViewBuilder private var ageComparisonSection: some View {
        // Shares the background pass with the projections, so asking for those
        // is what fills this.
        let _ = model.heartAgeProjections()
        let estimates = model.ageEstimates
        if estimates.count >= 2 {
            Divider()
            NestedInsightSection(
                title: "How old does each thing think you are",
                trailing: AgeComparison.spread(estimates).map { String(format: "%.0f years apart", $0) },
                caveat: .none
            ) {
                VStack(alignment: .leading, spacing: Theme.spacing) {
                    // **The chart, above the rows** — the reader's request,
                    // 2026-08-06. Four numbers in a column make the reader do
                    // the comparison; one axis does it for them, and the
                    // *subject of this section is the disagreement*. Where two
                    // error bars overlap they are the same answer measured
                    // twice; where they do not, something real is going on, and
                    // that is visible at a glance and invisible in a list.
                    //
                    // Same shape as `biologicalAgeMarkersCard` on purpose: one
                    // axis of years, a dot per estimate, its error bar around
                    // it, a dashed line at the reader's real age. Two strips
                    // drawing the same encoding differently is how the chart
                    // gap-bridge defect happened.
                    ageEstimateStrip(estimates)
                    ForEach(estimates) { estimate in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(estimate.label).font(.subheadline.weight(.medium))
                                Spacer()
                                Text(String(format: "%.0f", estimate.years))
                                    .font(.title3.monospacedDigit().weight(.semibold))
                                Text("years").font(.caption).foregroundStyle(.secondary)
                            }
                            Text(estimate.attribution)
                                .font(.caption).foregroundStyle(.secondary)
                            Text(estimate.uncertainty.note)
                                .font(.caption2).foregroundStyle(.tertiary)
                            // A relayed reading that has gone quiet is shown
                            // with its age rather than hidden — see
                            // `AgeComparison.Estimate.asOf`.
                            if let stale = estimate.staleness() {
                                Text(stale)
                                    .font(.caption2).foregroundStyle(Theme.warn)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    if let disagreement = AgeComparison.disagreement(estimates) {
                        Text(disagreement)
                            .font(.footnote)
                            .padding(.top, 4)
                    }
                }
            }
        }
    }

    // MARK: - The age chart

    /// **Every age estimate on one axis of years**, each with its own error bar,
    /// and the reader's real age as a dashed line through all of them.
    ///
    /// Drawn by hand rather than with Swift Charts, for the same reason the
    /// biological-age marker strip is: the x axis here is *age*, not time, so
    /// the substance shading every chart in this app carries would have nothing
    /// to sit on — the exemption `FitnessProjectionChart` already holds.
    ///
    /// ⚠️ **The rule this drawing must not break is "relay, never merge".**
    /// There is no combined marker, no mean of the estimates and no shaded
    /// consensus band, because averaging four ages into one would invent a
    /// precision none of them has. What the picture adds is the *comparison* —
    /// overlapping bars are the same answer measured twice, separated bars are a
    /// real disagreement — and that is a reading of the data, not a fifth
    /// number laid on top of it.
    @ViewBuilder private func ageEstimateStrip(_ estimates: [AgeComparison.Estimate]) -> some View {
        let chronological = estimates.first { $0.label == "Your age" }?.years
        let others = estimates.filter { $0.label != "Your age" }
        let span = ageStripSpan(estimates)
        if !others.isEmpty, span.upperBound > span.lowerBound {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(others) { estimate in
                    ageStripRow(estimate, chronological: chronological, span: span)
                }
                HStack {
                    Text(String(format: "%.0f", span.lowerBound))
                    Spacer()
                    if let chronological {
                        Text(String(format: "you · %.0f", chronological))
                    }
                    Spacer()
                    Text(String(format: "%.0f", span.upperBound))
                }
                .font(.caption2).monospacedDigit().foregroundStyle(.tertiary)
            }
        }
    }

    /// The axis every row shares. Widened to hold every error bar **and** the
    /// reader's real age, so no bar is drawn clipped at an edge and read as
    /// pinned there — the same guard `biologicalAgeSpan` carries.
    private func ageStripSpan(_ estimates: [AgeComparison.Estimate]) -> ClosedRange<Double> {
        var low = Double.greatestFiniteMagnitude
        var high = -Double.greatestFiniteMagnitude
        for estimate in estimates {
            let error = estimate.uncertainty.years ?? 0
            low = min(low, estimate.years - error)
            high = max(high, estimate.years + error)
        }
        guard low < high else { return 0...1 }
        // A little air either side, so a dot never sits on the frame.
        let padding = max(2, (high - low) * 0.06)
        return (low - padding)...(high + padding)
    }

    private func ageStripRow(_ estimate: AgeComparison.Estimate,
                             chronological: Double?,
                             span: ClosedRange<Double>) -> some View {
        let width = span.upperBound - span.lowerBound
        let error = estimate.uncertainty.years ?? 0
        // The app's own estimates are the ones with a derived error; a vendor's
        // is relayed with none. Tinting them apart is the same claim the rows
        // below make in words.
        let isOurs = estimate.attribution.hasPrefix("This app")
        return VStack(alignment: .leading, spacing: 2) {
            Text(estimate.label)
                .font(.caption2).foregroundStyle(.secondary)
            GeometryReader { geometry in
                let scale = geometry.size.width / width
                let centre = (estimate.years - span.lowerBound) * scale
                let barStart = (max(span.lowerBound, estimate.years - error) - span.lowerBound) * scale
                let barEnd = (min(span.upperBound, estimate.years + error) - span.lowerBound) * scale
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.secondary.opacity(0.10)).frame(height: 6)
                    if error > 0 {
                        Capsule()
                            .fill((isOurs ? Theme.accent : Color.secondary).opacity(0.30))
                            .frame(width: max(2, barEnd - barStart), height: 6)
                            .offset(x: barStart)
                    }
                    Circle()
                        .fill(isOurs ? Theme.accent : Color.secondary)
                        .frame(width: 9, height: 9)
                        .offset(x: centre - 4.5)
                    if let chronological, span.contains(chronological) {
                        // Dashed, because it is the one line here that is not an
                        // estimate — the app's own convention that a dash means
                        // "not measured the way the solid ones were".
                        Rectangle()
                            .fill(Color.primary.opacity(0.45))
                            .frame(width: 1.5, height: 18)
                            .offset(x: (chronological - span.lowerBound) * scale)
                    }
                }
                .frame(height: 18)
            }
            .frame(height: 18)
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
                // Live since 2026-08-03. This was `nil` from the day the model
                // shipped, so the shoulder-to-waist lift for mesomorphy — the
                // one component with a measured input — never once ran.
                dimensions: model.bodyScans.first?
                    .dimensions(heightMetres: model.samples.latestValue(.height) ?? 0),
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

                // The inputs that aren't measured series — a lab value, the
                // weight goal, a decaying substance load. They can't be a chart
                // line, but this is the section that answers "what goes into
                // this", so they belong on it, listed rather than plotted.
                auxiliaryInputsList(auxiliaryInputs(result))
            }
        }
    }

    /// The non-charted inputs, under "What goes into this" and shaped like the
    /// legend rows above them: a name, its value, and its share where it carries
    /// one. This is what stops a grounding fact or a derived figure driving the
    /// number while appearing nowhere the reader looks for what drives it.
    @ViewBuilder private func auxiliaryInputsList(_ inputs: [AuxInput]) -> some View {
        if !inputs.isEmpty {
            Divider()
            Text("Also feeding this — not a measured series")
                .font(.caption.weight(.medium))
            ForEach(inputs) { input in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: input.isModifiable ? "circle.fill" : "lock.fill")
                        .font(.system(size: 7))
                        .foregroundStyle(.tertiary)
                        .frame(width: 10)
                    Text(input.name).font(.subheadline)
                    Spacer(minLength: 6)
                    Text(input.detail)
                        .font(.caption).foregroundStyle(.secondary)
                        .multilineTextAlignment(.trailing)
                    if let share = input.share {
                        Text("\(Int((share * 100).rounded()))%")
                            .font(.caption.weight(.semibold).monospacedDigit())
                            .foregroundStyle(Theme.accent)
                    }
                }
            }
            Text("These carry a share of the score without being something the app charts over time. A lab value, a goal you set, or a figure the app works out — shown here so nothing that moves the number is left off this section.")
                .font(.caption2).foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
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

    /// The inputs that feed this card but are **not** measured series — grounding
    /// facts (age, cholesterol, weight goal) and derived quantities (a decaying
    /// substance load).
    ///
    /// They drive the number exactly as a metric does, but being non-metric they
    /// were absent from every section keyed on `MetricType` — "What goes into
    /// this", "Full history", "How you compare", the Data tab. So a card listed
    /// its blood pressure and silently dropped the cholesterol that moved its
    /// risk more, and Substance Impact hid the recent-load figure that can carry
    /// most of its score. This gathers them so the two contributor sections can
    /// be complete on every card at once, rather than each model re-declaring
    /// what it already states in `otherFactors` and `requirements`.
    private func auxiliaryInputs(_ result: InsightResult) -> [AuxInput] {
        var out: [AuxInput] = []
        var coveredKinds = Set<GroundingKind>()
        var seenNames = Set<String>()

        // 1. Non-metric factors the model actually emitted, with their shares —
        //    cholesterol and smoking on the risk card, the substance load.
        for factor in result.weightedFactors + result.unweightedFactors
        where factor.metric == nil {
            guard seenNames.insert(factor.name).inserted else { continue }
            var kind: GroundingKind?
            if case .grounding(let k) = factor.source { kind = k; coveredKinds.insert(k) }
            out.append(AuxInput(id: factor.name, name: factor.name, detail: factor.detail,
                                share: factor.weight > 0 ? factor.weight : nil,
                                groundingKind: kind, isModifiable: factor.isModifiable))
        }
        // Age and sex always travel together in this app, so if either is already
        // a factor (the risk card's "Age and sex" row) don't also list the raw
        // pair beneath it.
        if coveredKinds.contains(.dateOfBirth) || coveredKinds.contains(.biologicalSex) {
            coveredKinds.insert(.dateOfBirth); coveredKinds.insert(.biologicalSex)
        }
        // 2. Grounding requirements the model did *not* emit as a factor — age and
        //    sex on the cards that scale their references by them (Fitness, Heart
        //    Health, Body Composition emit no factors at all), the weight goal on
        //    Body Composition. Listed as context, valued from the profile, so a
        //    score-driving fact the reader supplied is never invisible.
        let requirements = model.engine.models.first { $0.id == insightID }?.requirements ?? []
        for req in requirements where !coveredKinds.contains(req.kind) {
            coveredKinds.insert(req.kind)
            let detail = model.profile.value(req.kind).map { req.kind.formatted($0) }
                ?? "Not set"
            out.append(AuxInput(id: req.kind.rawValue, name: req.kind.displayName,
                                detail: detail, share: nil, groundingKind: req.kind,
                                isModifiable: true))
        }
        return out
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
        // The grounding-fact inputs get a row too — tapping opens the sheet that
        // sets them, which is their "history": the value and when it was
        // entered. Derived figures (a substance load) are listed but not linked,
        // because there is nowhere to send a tap yet.
        let aux = auxiliaryInputs(result)
        if !metrics.isEmpty || !aux.isEmpty {
            let total = metrics.count + aux.count
            InsightSection(title: "Full history",
                           trailing: "\(total) \(SectionCaveat.plural(total, "signal"))",
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
                if !aux.isEmpty {
                    if !metrics.isEmpty { Divider() }
                    ForEach(aux) { input in
                        auxHistoryRow(input)
                    }
                }
            }
        }
    }

    /// A grounding fact opens its entry sheet; a derived figure is a plain row.
    @ViewBuilder private func auxHistoryRow(_ input: AuxInput) -> some View {
        if let kind = input.groundingKind {
            Button {
                groundingKind = kind
            } label: {
                auxHistoryLabel(input, chevron: "chevron.right")
            }
            .buttonStyle(.plain)
        } else {
            auxHistoryLabel(input, chevron: nil)
        }
    }

    private func auxHistoryLabel(_ input: AuxInput, chevron: String?) -> some View {
        HStack(spacing: 8) {
            Image(systemName: input.isModifiable ? "circle" : "lock.fill")
                .font(.system(size: 8)).foregroundStyle(.tertiary).frame(width: 9)
            Text(input.name).font(.subheadline)
            Spacer()
            Text(input.detail).font(.caption).foregroundStyle(.secondary)
                .lineLimit(1)
            if let chevron {
                Image(systemName: chevron).font(.caption).foregroundStyle(.tertiary)
            }
        }
        .contentShape(Rectangle())
    }

    // Discreet, only-in-detail feedback loop: rate accuracy and (optionally)
    // enter the real value, which trains/refines the model over time.
    //
    // ⚠️ **Not gated on `primaryValue`** (backlog Q5, ungated 2026-08-06). It
    // used to be, which meant a card in its empty state could not be rated —
    // and *the cards most likely to be wrong are exactly the ones the reader
    // could not tell you were wrong.* Nutrition and Metabolism have never
    // scored, so neither had ever been rateable, from the day each shipped.
    //
    // An unscored card is still making a claim: it is saying "I have nothing
    // from you, and here is what I need". That claim can be false — the reader
    // may well be logging food somewhere this app is not reading — so the
    // question changes with the state rather than the control disappearing.
    @ViewBuilder private func feedbackCard(_ result: InsightResult) -> some View {
        Card {
            if feedbackGiven {
                Label("Thanks — this helps improve the model over time.",
                      systemImage: "checkmark.circle.fill")
                    .font(.caption).foregroundStyle(Theme.good)
            } else {
                VStack(alignment: .leading, spacing: Theme.sectionSpacing) {
                    Text(result.primaryValue == nil
                         ? "Is this right about you?"
                         : "Was this accurate?")
                        .font(.headline)
                    HStack(spacing: 10) {
                        Button {
                            model.recordFeedback(insightID, accurate: true); feedbackGiven = true
                        } label: {
                            Label(result.primaryValue == nil ? "Yes" : "Accurate",
                                  systemImage: "hand.thumbsup")
                        }
                        Button {
                            model.recordFeedback(insightID, accurate: false); feedbackGiven = true
                        } label: {
                            Label(result.primaryValue == nil ? "No" : "Not accurate",
                                  systemImage: "hand.thumbsdown")
                        }
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
