import Foundation

/// **Everything the app knows about one day, assembled once** — backlog
/// `B11-2`, the per-day page reachable from the log and from the calendar.
///
/// The reader asked for four things on that page: the radar for that day, an AI
/// summary for that day, *"the graph of all contributing data sources, so they
/// can see how each contributed"*, and *"an estimated sickness they can correct
/// — type and severity, similar to how you can correct a work or travel event
/// (same concept - then we can learn from it)"*.
///
/// ## ⚠️ This type reuses; it does not recompute
///
/// Every number below already existed somewhere and the whole design of this
/// file is to fetch rather than re-derive:
///
/// | What the page shows | Where it already came from |
/// | --- | --- |
/// | the day's radar | `SymptomRadarModel.timeline` → `DaySnapshot.output.signals` |
/// | per-signal departure and direction | `HealthWatchModel.Signal` — z, recent, reference, all three already on it |
/// | the accumulation that evening | `SymptomRadarModel.history`, one forward pass |
/// | every other card's figure on that day | `DerivedSeriesStore.value(_:on:)` |
/// | what the reader said | `ReportedIllness.evaluate(day:…)` |
///
/// `timeline` produces one scored snapshot per day in a **single** pass and
/// `history` walks that result once more; building a report is a lookup in
/// both. ⚠️ **Never call `HealthWatchModel.evaluate` per day** — that is the
/// `days × evaluate` trap `SymptomRadarModel.history` documents, and it would
/// multiply the page's cost by the span of the chart above it.
///
/// ## The contributing-sources graph is `DerivedSeriesStore`, and that is the
/// point
///
/// The reader's ask — *"the graph of all contributing data sources, so they can
/// see how each contributed"* — is already answered by a mechanism this app
/// built for a different reason. `DerivedSeriesStore.value(_:on:)` is
/// specifically the read a consumer must use rather than `latest`, precisely so
/// a figure is read *on the day being scored*. Every card's derived figures for
/// that day, beside the radar's own signals for that day, **is** the graph.
///
/// ⚠️ **Two of those rows are read-only history and one of them is not.** The
/// signal rows are what the watch saw; the derived rows are what other cards
/// worked out; the reported rows are what the reader said. They are kept as
/// three lists rather than merged into one, because a chart that drew them on
/// one axis would assert they are the same kind of quantity, and they are not.
public struct SickDayReport: Sendable, Equatable {

    /// One watched signal, on that day.
    ///
    /// A projection of `HealthWatchModel.Signal` and not a new computation: the
    /// vote weight is `HealthWatchModel.weight(for:)` and everything else is
    /// already on the signal. `isDiscounted` carries the collapse losers, so
    /// "counted once with its twin" never renders as "not looked at" — the same
    /// distinction `SymptomRadarWebCard` draws with an open dot.
    public struct SignalRow: Sendable, Equatable, Identifiable {
        public let metric: MetricType
        public let zScore: Double
        public let recent: Double
        public let reference: Double
        public let isConcerning: Bool
        public let isDiscounted: Bool
        /// The share of the vote this signal carried, 0 for a collapse loser.
        public let weight: Double

        public var id: MetricType { metric }

        /// How far it leaned the illness way, floored at zero — the quantity the
        /// radar draws and the only one worth a bar. A signal moving the
        /// *welcome* way contributes nothing rather than cancelling one that
        /// moved the wrong way (`HealthWatchModel.concern`'s one-sided rule),
        /// and a bar chart has to say the same thing the score does.
        public var lean: Double { isConcerning ? abs(zScore) : 0 }
    }

    /// One other card's figure, on that day.
    public struct DerivedRow: Sendable, Equatable, Identifiable {
        public let spec: DerivedSeriesSpec
        public let value: Double
        public var id: DerivedSeriesID { spec.id }
        /// The card that worked it out, so the row can say where to go and ask.
        public var producedBy: InsightID { spec.producedBy }
    }

    /// The day, at start of day.
    public let day: Date
    /// The radar's row for that day — nil `output` where nothing was worn.
    public let history: SymptomRadarModel.DayHistory
    /// Every watched signal the day had, voting and discounted.
    public let signals: [SignalRow]
    /// Every derived figure any card produced that day.
    public let derived: [DerivedRow]
    /// What the reader's own records said.
    public let reported: ReportedIllness.Output
    /// The app's guess at what the day was, with its uncertainty attached.
    public let estimate: IllnessEstimate

    public init(day: Date, history: SymptomRadarModel.DayHistory,
                signals: [SignalRow], derived: [DerivedRow],
                reported: ReportedIllness.Output, estimate: IllnessEstimate) {
        self.day = day
        self.history = history
        self.signals = signals
        self.derived = derived
        self.reported = reported
        self.estimate = estimate
    }

    /// Whether the watch could judge this day at all.
    public var wasJudged: Bool { history.output != nil }

    /// The score the card would have shown that morning, memory included.
    public var score: Double? {
        history.output.map {
            SymptomRadarModel.verdict(today: $0, accumulation: history.accumulation,
                                      reported: reported).score
        }
    }

    public var status: SymptomRadarStatus? {
        history.output.map {
            SymptomRadarModel.verdict(today: $0, accumulation: history.accumulation,
                                      reported: reported).status
        }
    }

    // MARK: - Building one

    /// Assemble the report for one day out of work already done.
    ///
    /// - Parameters:
    ///   - history: the whole `SymptomRadarModel.history(over:)` result. Passed
    ///     in rather than computed, so a page opened from a list that already
    ///     holds it pays nothing — and so a caller cannot accidentally rebuild
    ///     six months of replay per day.
    public static func build(day: Date,
                             history: [SymptomRadarModel.DayHistory],
                             derived: DerivedSeriesStore,
                             symptoms: [SymptomEvent],
                             sickDays: SickDayLedger,
                             sideEffects: [SymptomReconciliation.LoggedEffect] = [],
                             calendar: Calendar = .current) -> SickDayReport {
        let today = calendar.startOfDay(for: day)
        let row = history.first { calendar.isDate($0.day, inSameDayAs: today) }
            // A day outside the replay's span is a real answer — nothing was
            // judged — and inventing an empty output is how a page ends up
            // claiming a green morning nobody measured.
            ?? SymptomRadarModel.DayHistory(day: today, output: nil,
                                            accumulation: .none, status: nil)

        var signals: [SignalRow] = []
        if let output = row.output {
            let votingTotal = output.signals.reduce(0.0) {
                $0 + HealthWatchModel.weight(for: $1.metric)
            }
            signals = output.signals.map { signal in
                SignalRow(metric: signal.metric, zScore: signal.zScore,
                          recent: signal.recent, reference: signal.reference,
                          isConcerning: signal.isConcerning, isDiscounted: false,
                          weight: votingTotal > 0
                              ? HealthWatchModel.weight(for: signal.metric) / votingTotal
                              : 0)
            }
            signals += output.discounted.map { signal in
                SignalRow(metric: signal.metric, zScore: signal.zScore,
                          recent: signal.recent, reference: signal.reference,
                          isConcerning: signal.isConcerning, isDiscounted: true,
                          weight: 0)
            }
        }

        // Every series any card recorded a value for on that day. Sorted by the
        // producing card and then the name so the list is stable between
        // launches — a graph whose rows reorder is a graph nobody can read
        // twice.
        let derivedRows = derived.seriesIDs.compactMap { id -> DerivedRow? in
            guard let spec = derived.spec(id),
                  let value = derived.value(id, on: today, calendar: calendar)
            else { return nil }
            return DerivedRow(spec: spec, value: value)
        }
        .sorted {
            ($0.producedBy.rawValue, $0.spec.displayName)
                < ($1.producedBy.rawValue, $1.spec.displayName)
        }

        let reported = ReportedIllness.evaluate(day: today, symptoms: symptoms,
                                                sickDays: sickDays,
                                                sideEffects: sideEffects,
                                                calendar: calendar)
        let estimate = IllnessEstimator.estimate(day: today, history: row,
                                                 reported: reported,
                                                 symptoms: symptoms,
                                                 calendar: calendar)
        return SickDayReport(day: today, history: row, signals: signals,
                             derived: derivedRows, reported: reported,
                             estimate: estimate)
    }

    // MARK: - The day's summary

    /// **The facts an on-device model is allowed to phrase, and nothing else.**
    ///
    /// The same contract `FoundationModelSummarizer.factSheet` already holds the
    /// Today summary to, and for the same reason it was narrowed: *numbers come
    /// from the validated models, the model only phrases them*. Every line here
    /// is a figure this file computed or a statement the reader made. **No
    /// symptom is named** — the sheet says how many and how specific, because a
    /// prompt is a place a health fact can leak and `docs/privacy-and-ip.md`'s
    /// rule is the shape of a finding, never the reading.
    public var factSheet: String {
        var lines: [String] = []
        lines.append("- Date: \(day.formatted(date: .abbreviated, time: .omitted))")
        if let output = history.output {
            lines.append("- Overnight signals judged: \(output.signals.count)")
            lines.append("- Signals leaning the illness way: \(output.leaning.count)")
            lines.append(String(format: "- Day's own score out of 100: %.0f", output.score))
        } else {
            lines.append("- Overnight signals judged: none — nothing was worn, or too little history")
        }
        if history.accumulation.daysRunning > 0 {
            lines.append("- Days running above usual: \(history.accumulation.daysRunning)")
        }
        for component in reported.components {
            lines.append("- \(component.source.displayName): recorded")
        }
        if !reported.isSpeaking {
            lines.append("- You recorded nothing about this day")
        }
        lines.append("- The app's guess: \(estimate.assessment.summary)")
        return lines.joined(separator: "\n")
    }

    /// The deterministic version, and the one that ships where no on-device
    /// model exists. **Written first and tested**, so the model is an
    /// improvement on a working sentence rather than the only path to one.
    public var templateSummary: String {
        guard let output = history.output else {
            return "Nothing was judged on this day — either nothing was worn, or "
                + "there was not enough history behind it to compare against. "
                + "That is missing evidence, not a quiet day."
        }
        let leaning = output.leaning.count
        var sentence: String
        switch output.status {
        case .quiet:
            sentence = leaning == 0
                ? "None of your overnight signals was leaning the way illness pushes them."
                : "\(leaning) signal\(leaning == 1 ? " was" : "s were") a touch outside "
                    + "your usual range, and together still inside the noise."
        case .someSigns:
            sentence = "\(leaning) of \(output.signals.count) watched signals were "
                + "leaning the way illness pushes them."
        case .strongSigns:
            sentence = "\(leaning) of \(output.signals.count) watched signals were "
                + "leaning together, which is the finding this card makes."
        }
        if history.accumulation.daysRunning > 1 {
            sentence += " It was day \(history.accumulation.daysRunning) of a stretch "
                + "away from your usual."
        }
        if reported.isSpeaking {
            sentence += " You also recorded something yourself that day, which counts "
                + "for more here than any of the readings do."
        }
        return sentence
    }
}

/// **The app's guess at what a day was.**
///
/// ⚠️ Read `IllnessJudgement`'s type note before changing anything here. The
/// single rule this estimator obeys, and the reason it looks timid: **a kind of
/// illness is only ever named from something the reader reported.** Physiology
/// contributes severity and nothing else, because the literature is explicit
/// that the signal is non-specific systemic strain — reproduced by alcohol, a
/// hard session, poor sleep, travel and the menstrual cycle — and no study in it
/// detects any organ system at all. An estimator that read "respiratory" off a
/// raised breathing rate would be inventing a specificity nobody has measured.
public enum IllnessEstimator {

    public static func estimate(day: Date,
                                history: SymptomRadarModel.DayHistory,
                                reported: ReportedIllness.Output,
                                symptoms: [SymptomEvent],
                                calendar: Calendar = .current) -> IllnessEstimate {
        let today = calendar.startOfDay(for: day)
        let tags = symptoms.filter {
            calendar.isDate($0.date, inSameDayAs: today) && $0.severity.isPresent
        }
        let artifact = IllnessArtifact(
            physiologicalExcess: history.output?.excess ?? 0,
            accumulatedStatistic: history.accumulation.statistic,
            reportedExcess: reported.excess,
            leaningSignals: history.output?.leaning.count ?? 0,
            wasJudged: history.output != nil)

        var basis: [String] = []

        // 1. The kind, from what was reported and only from what was reported.
        //    The worst-graded tag that points anywhere wins; ties go to the
        //    first, which is stable because `tags` keeps the caller's order.
        let named = tags
            .map { (kind: IllnessKind.kind(for: $0.type), severity: $0.severity) }
            .filter { $0.kind != .unknown }
            .max { $0.severity.rawValue < $1.severity.rawValue }
        var kind: IllnessKind = named?.kind ?? .unknown
        if let named {
            basis.append("You tagged a symptom that points at \(named.kind.title.lowercased()).")
        } else if !tags.isEmpty {
            basis.append("You tagged \(tags.count) symptom\(tags.count == 1 ? "" : "s"), "
                         + "none of them specific enough to name a kind.")
        }

        // 2. A recorded sick day says *ill*, even where nothing named a kind.
        //    `.other` rather than a guess: the reader said they were ill and did
        //    not say what of, and this app does not fill that in for them.
        if let sickDay = reported.component(.recordedSickDay) {
            if kind == .unknown { kind = .other }
            basis.append(sickDay.detail + ".")
        }

        // 3. Severity. The reader's own grade outranks anything measured, and
        //    where they gave none the physiological day supplies one — which is
        //    the *only* thing physiology is trusted with here.
        let statedSeverity = statedGrade(tags: tags, reported: reported)
        let severity: CalendarEventClassification.SickSeverity?
        if let statedSeverity {
            severity = statedSeverity
            basis.append("Graded from what you recorded, not from your readings.")
        } else if kind != .unknown {
            severity = measuredGrade(history: history)
            basis.append(measuredGradeBasis(history: history))
        } else {
            severity = nil
        }

        // 4. Nothing reported at all. The estimate is `.unknown` whatever the
        //    signals did — see the type note. The physiological day still earns
        //    a basis line, because "this is what the app was looking at when it
        //    could not say" is the honest empty state and a blank one is not.
        if kind == .unknown {
            basis.append(unreportedBasis(history: history))
        }

        return IllnessEstimate(
            assessment: IllnessAssessment(kind: kind, severity: severity),
            basis: basis,
            uncertainty: uncertainty(kind: kind, reported: reported, history: history),
            artifact: artifact)
    }

    /// The worst grade the reader stated anywhere, across both records.
    static func statedGrade(tags: [SymptomEvent],
                            reported: ReportedIllness.Output)
        -> CalendarEventClassification.SickSeverity? {
        var candidates: [CalendarEventClassification.SickSeverity] = []
        for tag in tags {
            switch tag.severity {
            case .mild: candidates.append(.mild)
            case .moderate: candidates.append(.moderate)
            case .severe: candidates.append(.severe)
            case .unspecified, .notPresent: continue
            }
        }
        // The sick-day ledger's own grade, where the reader gave one. `.unstated`
        // is skipped deliberately: somebody looked and declined to grade it, and
        // promoting that to "mild" would be the app answering for them.
        if let component = reported.component(.recordedSickDay), component.excess > 0 {
            let ledgerGrade: CalendarEventClassification.SickSeverity? =
                component.excess >= HealthWatchModel.strongSignsExcess ? .severe
                : component.excess > HealthWatchModel.someSignsExcess ? .moderate
                : nil
            if let ledgerGrade { candidates.append(ledgerGrade) }
        }
        return candidates.max { rank($0) < rank($1) }
    }

    static func rank(_ severity: CalendarEventClassification.SickSeverity) -> Int {
        switch severity {
        case .unstated: return 0
        case .mild: return 1
        case .moderate: return 2
        case .severe: return 3
        }
    }

    /// Severity from the physiological day, used only once a kind has been named
    /// by something the reader said.
    ///
    /// Anchored on the model's own band edges so it cannot drift from them, and
    /// **it never returns `.severe`**: the strongest thing the overnight signals
    /// can support is "clearly outside your usual", and a card calling somebody
    /// severely ill on the strength of a 4–12% PPV detector would be exactly the
    /// overreach this whole feature is written against. `.severe` is available
    /// to the reader and to nobody else.
    static func measuredGrade(history: SymptomRadarModel.DayHistory)
        -> CalendarEventClassification.SickSeverity {
        guard let output = history.output else { return .unstated }
        if output.excess >= HealthWatchModel.strongSignsExcess { return .moderate }
        if output.excess >= HealthWatchModel.someSignsExcess { return .mild }
        return .unstated
    }

    static func measuredGradeBasis(history: SymptomRadarModel.DayHistory) -> String {
        guard let output = history.output else {
            return "Nothing was worn that night, so there is no reading to grade it by."
        }
        let leaning = output.leaning.count
        return "You did not grade it, so the grade comes from your readings: "
            + "\(leaning) of \(output.signals.count) watched signals leaning, "
            + "score \(Int(output.score.rounded())). Readings can suggest mild or "
            + "moderate here and never severe — only you can say that."
    }

    static func unreportedBasis(history: SymptomRadarModel.DayHistory) -> String {
        guard let output = history.output else {
            return "Nothing was worn that night and you recorded nothing, so there is "
                + "nothing to go on. Correct it below if you remember."
        }
        let leaning = output.leaning.count
        guard leaning > 0 else {
            return "You recorded nothing, and none of your overnight signals was "
                + "leaning the illness way. That is not evidence you were well — "
                + "it is the absence of evidence either way."
        }
        return "You recorded nothing. \(leaning) overnight signal"
            + "\(leaning == 1 ? " was" : "s were") leaning, which is a reason to look "
            + "and never a reason to name an illness."
    }

    /// ⚠️ **Every estimate carries one of these and none may be empty.**
    /// Enforced by `IllnessJudgementTests`.
    static func uncertainty(kind: IllnessKind,
                            reported: ReportedIllness.Output,
                            history: SymptomRadarModel.DayHistory) -> String {
        guard kind != .unknown else {
            return "This is a prompt, not a finding. Run forward against a real "
                + "test, detectors like this one are right between 4 and 12 times "
                + "in every 100 — and about two-thirds of real illnesses never show "
                + "up in these signals at all. If you remember what this day was, "
                + "your answer is better evidence than anything above it."
        }
        guard reported.isSpeaking else {
            return "Named from your readings alone, which cannot tell one kind of "
                + "illness from another — the same pattern follows alcohol, hard "
                + "training, a poor night, travel and altitude. Correct it."
        }
        return "Named from what you recorded, which is the better evidence of the "
            + "two. The readings beside it agree or they do not; neither confirms "
            + "the other, and this app never treats a quiet card as a reason to "
            + "doubt what you said."
    }
}
