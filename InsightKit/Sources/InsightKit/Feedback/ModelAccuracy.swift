import Foundation

/// # Grading the app against what actually happened.
///
/// Backlog **P24**, asked for by name. The reader wanted per-card
/// prediction-versus-actual over time, and the hard part is not the arithmetic —
/// it is saying something true with the handful of pairs a real person
/// accumulates.
///
/// ## Why not an accuracy percentage
///
/// A single percentage hides the two failures that matter and cannot tell them
/// apart:
///
/// - **Well-calibrated and useless.** A model that predicts blood pressure to
///   within 4 mmHg looks excellent until you notice that this reader's blood
///   pressure only moves 5 mmHg between readings — so *"assume you're the same
///   as last time"* would have done nearly as well. Precision without skill.
/// - **Confident and wrong.** A model out by 4 every single time is not noisy,
///   it is *biased* — and a bias is a fixable defect, whereas scatter usually
///   is not. Averaging the two into one number erases the difference.
///
/// So this reports three separable things — **how far out, which way, and
/// whether it beats doing nothing** — and each one carries the `n` it rests on.
///
/// ## Facts always; summaries gated; verdicts gated harder
///
/// The reader's standing rule is *"honest version, always"*, and at n = 3 an
/// accuracy figure is theatre. But the individual pairs are not theatre: *"on
/// the 4th it said 128 and the cuff said 121"* is a fact, and three of those are
/// three facts. So the layering is:
///
/// | shown | needs |
/// |---|---|
/// | the pairs themselves, and the count | 1 |
/// | typical miss | `minimumForTypicalError` |
/// | which way it leans | `minimumForBias` |
/// | whether it beats assuming no change | `minimumForSkill` |
///
/// Below each threshold the figure is withheld and a `CoverageGate` says how
/// many more are needed and what they buy — never a blank.
///
/// ## ⚠️ The hazard: marking its own homework
///
/// **A prediction graded against an outcome the same model helped define is not
/// evidence of anything.** Every card here produces a daily score, and those
/// scores are stored (`InsightScoreRecord`), so it would be trivial — and
/// completely wrong — to "grade" Monday's readiness prediction against
/// Thursday's readiness score. The model would be both examiner and candidate,
/// the number would look plausible, and it would mean nothing.
///
/// The guard is `admits(_:)`, and it is **deny-by-default**: a pair only counts
/// when the truth it was graded against came from an instrument outside this
/// app (see `externallyMeasuredTruths`). Rejected pairs are counted rather than
/// silently dropped, so the screen can say how many are being held back and
/// why — a silent filter is how this hazard comes back.
public enum ModelAccuracy {

    // MARK: - What counts as truth

    /// The metrics whose `actual` comes from something outside this app —
    /// a cuff, a scale, a tape measure, a glucose meter.
    ///
    /// ⚠️ **Deny-by-default, and deliberately short.** Anything not listed here
    /// is refused as ground truth, so a metric added later is *not* graded
    /// against until somebody decides it qualifies. That is the conservative
    /// direction: the cost of an omission is a missing figure, and the cost of
    /// an over-inclusion is a fabricated accuracy claim.
    ///
    /// It is a `Set` and not an exhaustive `switch` on purpose. An exhaustive
    /// switch would oblige every future `MetricType` to declare itself here
    /// before the package compiles, and a contributor under that pressure picks
    /// whichever case makes the build go green.
    ///
    /// **A vendor's own estimate is not truth.** VO₂max, sleep stages and a
    /// wearable's "recovery" are models too — grading this app's model against
    /// another company's model is a comparison, not a measurement, and it is
    /// excluded for the same reason as the self-grading hazard above. A smart
    /// scale's body-fat reading is a borderline case and is likewise left out;
    /// weight, which the same scale measures directly, is in.
    public static let externallyMeasuredTruths: Set<MetricType> = [
        .bloodPressureSystolic, .bloodPressureDiastolic,
        .bodyMass, .waistCircumference, .bloodGlucose
    ]

    /// Whether a recorded pair may be graded at all.
    ///
    /// ⚠️ See the type's "marking its own homework" note. This is the line
    /// between an accuracy figure and a circular one, and it lives in code
    /// rather than in a convention because a convention is honoured by whoever
    /// remembers it.
    public static func admits(_ outcome: PredictionOutcome) -> Bool {
        externallyMeasuredTruths.contains(outcome.metric)
    }

    // MARK: - Building reports

    /// Group admitted outcomes into one report per card-and-metric, oldest
    /// first.
    ///
    /// Ordering matters and is not cosmetic: the persistence baseline compares
    /// each truth with the one before it, so an unsorted array would measure
    /// how jumbled the array is.
    public static func reports(from outcomes: [PredictionOutcome]) -> [CalibrationReport] {
        let admitted = outcomes.filter(admits)
        let grouped = Dictionary(grouping: admitted) { Key(insight: $0.insightID, metric: $0.metric) }
        return grouped.map { key, group in
            let ordered = group.sorted { $0.recordedAt < $1.recordedAt }
            return CalibrationReport(
                insightID: key.insight,
                metric: key.metric,
                modelVersions: Array(Set(ordered.map(\.modelVersion))).sorted(),
                pairs: ordered.map {
                    GradedPrediction(id: $0.id, date: $0.recordedAt,
                                     predicted: $0.predicted, actual: $0.actual)
                })
        }
        .sorted { ($0.insightID.rawValue, $0.metric.rawValue) < ($1.insightID.rawValue, $1.metric.rawValue) }
    }

    private struct Key: Hashable {
        let insight: InsightID
        let metric: MetricType
    }

    /// One row per card, whatever evidence exists for it — including none.
    ///
    /// **Every card appears.** A card with nothing to grade is the common case
    /// and is not an error; it gets an entry saying what kind of evidence it
    /// would take, which is the only honest thing to print and is more use than
    /// its absence.
    ///
    /// - Parameters:
    ///   - outcomes: every stored `PredictionOutcome`, admitted or not.
    ///   - verdicts: the reader's thumbs, as `(insight, rating)` pairs.
    ///   - scoredDays: how many days each card has a stored score for. **Context
    ///     only** — it is not evidence of accuracy and is never mixed into one.
    ///   - titles: the card titles, which live on `InsightModel` rather than on
    ///     `InsightID`. A missing title falls back to the raw value rather than
    ///     dropping the row.
    public static func ledger(outcomes: [PredictionOutcome],
                              verdicts: [(insight: InsightID, rating: FeedbackRating)],
                              scoredDays: [InsightID: Int] = [:],
                              titles: [InsightID: String] = [:]) -> [ModelAccuracyEntry] {
        let byInsight = Dictionary(grouping: reports(from: outcomes), by: \.insightID)
        let withheld = outcomes.filter { !admits($0) }
            .reduce(into: [InsightID: Int]()) { $0[$1.insightID, default: 0] += 1 }

        return InsightID.allCases.map { id in
            let mine = verdicts.filter { $0.insight == id }
            return ModelAccuracyEntry(
                insightID: id,
                title: titles[id] ?? id.rawValue,
                modelVersion: id.modelVersion,
                reports: byInsight[id] ?? [],
                verdicts: VerdictTally(
                    accurate: mine.filter { $0.rating == .accurate }.count,
                    inaccurate: mine.filter { $0.rating == .inaccurate }.count),
                withheldPairs: withheld[id] ?? 0,
                scoredDays: scoredDays[id] ?? 0)
        }
        .sorted {
            if $0.evidence.rank != $1.evidence.rank { return $0.evidence.rank < $1.evidence.rank }
            return $0.title < $1.title
        }
    }

    // MARK: - What this will look like once there is something

    /// **A worked example on invented numbers**, so a screen with nothing to
    /// report is still worth opening.
    ///
    /// A permanent null is the useless option, not the safe one: a reader who
    /// opens this on day one and finds an empty page learns nothing and does not
    /// come back. This is the same device `SharingExample` uses on the sharing
    /// screen — **built by the real code**, so what the screen promises cannot
    /// drift from what it would actually print.
    ///
    /// The numbers are chosen to teach the distinction the whole screen exists
    /// for: a model that misses by only 4 mmHg, misses in the *same direction*
    /// every time, and is barely better than assuming nothing changed. Small
    /// error, obvious bias, thin skill — three different statements that one
    /// accuracy percentage would have collapsed into "96%".
    ///
    /// ⚠️ It must be labelled as invented wherever it is shown. It is not this
    /// reader's data and never will be.
    public static func workedExample() -> CalibrationReport {
        let start = Date(timeIntervalSince1970: 1_767_225_600)   // 2026-01-01
        let actuals: [Double] = [118, 124, 121, 129, 126, 122, 131, 127, 124, 130, 126, 123]
        let errors: [Double] = [5, 2, 6, 3, 4, 1, 7, 3, 5, 2, 6, 4]
        let pairs = zip(actuals, errors).enumerated().map { index, pair in
            GradedPrediction(
                id: UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", index))
                    ?? UUID(),
                date: start.addingTimeInterval(Double(index) * 3 * 86_400),
                predicted: pair.0 + pair.1,
                actual: pair.0)
        }
        return CalibrationReport(insightID: .bloodPressure, metric: .bloodPressureSystolic,
                                 modelVersions: [InsightID.bloodPressure.modelVersion],
                                 pairs: pairs)
    }
}

// MARK: - One graded pair

/// One "it said X, the truth was Y" pair, stripped to what a chart and a
/// residual need.
public struct GradedPrediction: Sendable, Equatable, Identifiable {
    public let id: UUID
    public let date: Date
    public let predicted: Double
    public let actual: Double

    public init(id: UUID = UUID(), date: Date, predicted: Double, actual: Double) {
        self.id = id; self.date = date; self.predicted = predicted; self.actual = actual
    }

    /// Positive means the model read **higher** than the truth.
    public var signedError: Double { predicted - actual }
    public var absoluteError: Double { abs(signedError) }
}

// MARK: - The report

/// What one card's predictions of one metric have actually done.
///
/// Everything here is a fact about this reader's own record. Nothing is a
/// published validation figure, and nothing is a design budget — see the symptom
/// radar's scorecard, where those two blocks are kept apart for the same reason.
public struct CalibrationReport: Sendable, Equatable, Identifiable {
    public let insightID: InsightID
    public let metric: MetricType
    /// Every model version these pairs were produced under.
    public let modelVersions: [String]
    /// Oldest first. Ordering is load-bearing — see `persistenceSkill`.
    public let pairs: [GradedPrediction]

    public init(insightID: InsightID, metric: MetricType,
                modelVersions: [String], pairs: [GradedPrediction]) {
        self.insightID = insightID
        self.metric = metric
        self.modelVersions = modelVersions
        self.pairs = pairs
    }

    public var id: String { "\(insightID.rawValue).\(metric.rawValue)" }

    // MARK: Thresholds
    //
    // Each one is the point below which the figure above it would be theatre.
    // They are deliberately different numbers: a median needs fewer points than
    // a direction, and a direction needs fewer than a comparison against a
    // baseline that is itself estimated from the same short series.

    /// Below this, no typical-miss figure. Five is the smallest count whose
    /// median is not simply one of the two middle readings shrugging.
    public static let minimumForTypicalError = 5
    /// Below this, no statement about direction. A two-sided sign test cannot
    /// reach p < 0.05 at all until n = 6, so at n = 5 "it always runs high" is
    /// indistinguishable from five coin flips landing the same way.
    public static let minimumForBias = 8
    /// Below this, no skill figure. The baseline is estimated from the same
    /// series, so both terms are noisy and their ratio is noisier still.
    public static let minimumForSkill = 10

    public var n: Int { pairs.count }
    public var signedErrors: [Double] { pairs.map(\.signedError) }
    public var absoluteErrors: [Double] { pairs.map(\.absoluteError) }
    public var firstAt: Date? { pairs.first?.date }
    public var lastAt: Date? { pairs.last?.date }

    /// The unit the errors are in — mmHg, kg, cm. Errors live in the metric's
    /// own units rather than as percentages, because a percentage of a blood
    /// pressure is not a quantity any clinician thinks in.
    public var unit: String { metric.unit }

    // MARK: Figures

    /// **Median** absolute error, not mean: one bad reading at n = 6 drags a
    /// mean somewhere no individual prediction ever was.
    public var typicalError: Double? {
        guard n >= Self.minimumForTypicalError else { return nil }
        return Self.median(absoluteErrors)
    }

    /// The largest miss. A fact rather than a summary, so it is offered at any
    /// `n` — but it is only meaningful printed beside `n`, and the worst of 3 is
    /// a very different claim from the worst of 30.
    public var worstError: Double? { absoluteErrors.max() }

    /// How far the model leans, signed: positive reads **high**.
    public var bias: Double? {
        guard n >= Self.minimumForBias else { return nil }
        return Self.median(signedErrors)
    }

    /// How many predictions came in above the truth.
    public var overPredictions: Int { signedErrors.filter { $0 > 0 }.count }

    /// Two-sided exact binomial p for "over and under are equally likely".
    ///
    /// Exact rather than normal-approximate because the whole point is that `n`
    /// is small, and the normal approximation is worst exactly there.
    public var directionP: Double? {
        guard n > 0 else { return nil }
        let over = overPredictions
        let under = n - over
        let k = Swift.min(over, under)
        var tail = 0.0
        for i in 0...k { tail += Self.binomial(n, i) }
        return Swift.min(1, 2 * tail / pow(2, Double(n)))
    }

    /// True when the lean is beyond what coin-flipping would produce.
    ///
    /// This is the line between *"it is biased"* — a defect somebody can go and
    /// fix — and *"it is noisy"*, which usually cannot be fixed and should not
    /// be described as though it could.
    public var biasIsBeyondChance: Bool {
        guard n >= Self.minimumForBias, let p = directionP else { return false }
        return p < 0.05
    }

    /// The scatter that would remain if the lean were corrected — the part that
    /// is not a fixable offset.
    public var scatterAroundBias: Double? {
        guard let bias else { return nil }
        return Self.median(signedErrors.map { abs($0 - bias) })
    }

    /// Mean absolute error of **"assume it is the same as last time"**, over the
    /// same pairs the model is judged on.
    ///
    /// This is the number that answers *"is the model doing anything?"*. A
    /// quantity that barely moves is easy to predict, and a model that beats
    /// nothing on it is not accurate — it is riding the quantity's own
    /// stability.
    public var persistenceBaselineError: Double? {
        guard n >= 2 else { return nil }
        let diffs = (1..<n).map { abs(pairs[$0 - 1].actual - pairs[$0].actual) }
        return diffs.reduce(0, +) / Double(diffs.count)
    }

    /// The model's own mean absolute error over the same pairs the baseline is
    /// scored on — the first pair has nothing before it, so it is excluded from
    /// **both** sides rather than from one.
    public var comparableError: Double? {
        guard n >= 2 else { return nil }
        let errors = pairs.dropFirst().map(\.absoluteError)
        return errors.reduce(0, +) / Double(errors.count)
    }

    /// `1 - model/baseline`. Zero means "no better than assuming no change";
    /// negative means worse than that; 1 would mean perfect.
    public var persistenceSkill: Double? {
        guard n >= Self.minimumForSkill,
              let baseline = persistenceBaselineError, baseline > 0,
              let model = comparableError else { return nil }
        return 1 - model / baseline
    }

    // MARK: Gates — what is missing, and what it would buy

    public var typicalErrorGate: CoverageGate {
        CoverageGate(need: Self.minimumForTypicalError, have: n, unit: "graded prediction",
                     unlocks: "this can say how far out it typically is")
    }

    public var biasGate: CoverageGate {
        CoverageGate(need: Self.minimumForBias, have: n, unit: "graded prediction",
                     unlocks: "this can say whether it leans one way or is simply noisy")
    }

    public var skillGate: CoverageGate {
        CoverageGate(need: Self.minimumForSkill, have: n, unit: "graded prediction",
                     unlocks: "this can say whether it beats assuming nothing changed")
    }

    /// ⚠️ Pairs recorded under different model versions are not one population.
    ///
    /// `InsightID.modelVersion` exists precisely so a score from one revision is
    /// not silently pooled with one from another, and the same applies here:
    /// averaging an old model's misses with a new model's flatters or damns
    /// whichever is better. Nil when they are all from one version.
    public var comparabilityWarning: String? {
        guard modelVersions.count > 1 else { return nil }
        return "These \(n) come from \(modelVersions.count) versions of the model (\(modelVersions.joined(separator: ", "))). They are pooled here, which the version string exists to stop — read the figures as a rough combined history rather than as one model's record."
    }

    // MARK: The one-line reading

    /// What this record actually supports saying, in the order that keeps it
    /// honest: **too few** beats everything; **no skill** beats a flattering
    /// error figure; a **lean** beats a bare average.
    public enum Reading: Sendable, Equatable {
        /// Not enough to say anything. Carries the gate that says how many more.
        case tooFew(CoverageGate)
        /// Small errors, but no better than assuming nothing changed.
        case noSkill(typicalError: Double, baseline: Double)
        /// Leans one way by more than chance — a fixable defect.
        case leans(by: Double, high: Bool, scatter: Double)
        /// No detectable lean, and it is doing better than nothing.
        case tracking(typicalError: Double, skill: Double?)
    }

    public var reading: Reading {
        guard let typicalError else { return .tooFew(typicalErrorGate) }
        if let skill = persistenceSkill, skill <= 0, let baseline = persistenceBaselineError {
            return .noSkill(typicalError: typicalError, baseline: baseline)
        }
        if biasIsBeyondChance, let bias, let scatter = scatterAroundBias {
            return .leans(by: abs(bias), high: bias > 0, scatter: scatter)
        }
        return .tracking(typicalError: typicalError, skill: persistenceSkill)
    }

    /// The reading as a sentence, always ending in the `n` it rests on.
    ///
    /// The `n` is not decoration and is never dropped: it is the difference
    /// between a measurement and an anecdote, and this app's whole claim is that
    /// it will say which of those it is holding.
    public var sentence: String {
        let count = "\(n) graded prediction\(n == 1 ? "" : "s")"
        switch reading {
        case .tooFew(let gate):
            return gate.sentence ?? "Not enough graded predictions yet."
        case .noSkill(let typical, let baseline):
            return String(format: "Out by %.0f %@ typically — but your own readings only move %.0f %@ between one and the next, so simply assuming no change would have done as well. Precise, and not yet useful. (%@.)",
                          typical, unit, baseline, unit, count)
        case .leans(let by, let high, let scatter):
            return String(format: "It reads about %.0f %@ too %@, consistently rather than by chance, and scatters %.0f %@ around that. A consistent lean is an offset somebody can correct; the scatter is the part that is genuinely uncertain. (%@.)",
                          by, unit, high ? "high" : "low", scatter, unit, count)
        case .tracking(let typical, let skill):
            if let skill {
                return String(format: "Out by %.0f %@ typically, with no lean either way, and %.0f%% better than assuming nothing changed. (%@.)",
                              typical, unit, skill * 100, count)
            }
            return String(format: "Out by %.0f %@ typically, with no lean detectable yet. (%@.)",
                          typical, unit, count)
        }
    }

    // MARK: Small statistics

    static func median(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let mid = sorted.count / 2
        return sorted.count.isMultiple(of: 2)
            ? (sorted[mid - 1] + sorted[mid]) / 2
            : sorted[mid]
    }

    /// `n choose k`, multiplicatively so it stays exact for the sizes involved
    /// and never overflows on the way there.
    static func binomial(_ n: Int, _ k: Int) -> Double {
        guard k >= 0, k <= n else { return 0 }
        var result = 1.0
        for i in 0..<Swift.min(k, n - k) {
            result = result * Double(n - i) / Double(i + 1)
        }
        return result
    }
}

// MARK: - The reader's own verdict

/// Thumbs up and down. **Agreement, not accuracy** — and the two are named
/// apart everywhere they appear.
///
/// A reader is more likely to tap when a card surprises them, so this is a
/// self-selected sample of their own impressions. It is worth showing, and it is
/// worth never calling it a hit rate.
public struct VerdictTally: Sendable, Equatable {
    public let accurate: Int
    public let inaccurate: Int

    public init(accurate: Int, inaccurate: Int) {
        self.accurate = accurate; self.inaccurate = inaccurate
    }

    public var total: Int { accurate + inaccurate }

    /// Ten, because a percentage out of three is a percentage of nothing.
    public static let minimumForRate = 10

    /// The share the reader called accurate, withheld below `minimumForRate`.
    public var agreement: Double? {
        guard total >= Self.minimumForRate else { return nil }
        return Double(accurate) / Double(total)
    }

    public var gate: CoverageGate {
        CoverageGate(need: Self.minimumForRate, have: total, unit: "rating",
                     unlocks: "this can show how often you agreed with it")
    }
}

// MARK: - What kind of evidence a card has

/// The honesty axis of this whole screen: **what is this card graded against?**
public enum AccuracyEvidence: String, Sendable, Equatable, CaseIterable {
    /// A measurement this app did not produce — a cuff, a scale, a tape. The
    /// only kind that can support an error figure.
    case externalTruth
    /// The reader's own thumbs. Real evidence about usefulness; no evidence
    /// about accuracy.
    case readerVerdict
    /// Nothing outside the model. ⚠️ **Ungradable here, on purpose** — see
    /// `ModelAccuracy`'s "marking its own homework" note. The card may still be
    /// good; there is simply nothing to check it against, and inventing a check
    /// would be worse than saying so.
    case selfDefined

    /// Sort order for the screen: what can be measured first, what cannot last.
    public var rank: Int {
        switch self {
        case .externalTruth: return 0
        case .readerVerdict: return 1
        case .selfDefined:   return 2
        }
    }

    public var heading: String {
        switch self {
        case .externalTruth: return "Checked against something measured"
        case .readerVerdict: return "Only your verdict"
        case .selfDefined:   return "Nothing to check it against yet"
        }
    }
}

// MARK: - One card's row

public struct ModelAccuracyEntry: Sendable, Equatable, Identifiable {
    public let insightID: InsightID
    public let title: String
    public let modelVersion: String
    /// One per metric this card has admitted pairs for. Empty is the norm.
    public let reports: [CalibrationReport]
    public let verdicts: VerdictTally
    /// Pairs refused by `ModelAccuracy.admits` — counted rather than dropped, so
    /// the screen can say what is being held back and why.
    public let withheldPairs: Int
    /// Days this card has a stored score for. **Context, never accuracy.**
    public let scoredDays: Int

    public init(insightID: InsightID, title: String, modelVersion: String,
                reports: [CalibrationReport], verdicts: VerdictTally,
                withheldPairs: Int = 0, scoredDays: Int = 0) {
        self.insightID = insightID
        self.title = title
        self.modelVersion = modelVersion
        self.reports = reports
        self.verdicts = verdicts
        self.withheldPairs = withheldPairs
        self.scoredDays = scoredDays
    }

    public var id: String { insightID.rawValue }

    public var evidence: AccuracyEvidence {
        if !reports.isEmpty { return .externalTruth }
        if verdicts.total > 0 { return .readerVerdict }
        return .selfDefined
    }

    /// Total graded pairs across every metric on this card.
    public var gradedPairs: Int { reports.reduce(0) { $0 + $1.n } }

    /// What would have to happen for this card to be gradable at all.
    ///
    /// ⚠️ **Not a nag and not a promise.** Some cards will never have an outside
    /// measurement to check against — nobody sells an instrument that measures
    /// "readiness" — and saying so plainly is more honest than implying the
    /// figure is one export away.
    public var whatWouldMakeItGradable: String {
        switch evidence {
        case .externalTruth:
            return "Every cuff reading you log after an estimate adds one more."
        case .readerVerdict, .selfDefined:
            return "This card would need an outside measurement of the same thing to be checked against — the way a cuff checks the blood-pressure estimate. There is no instrument that measures what this card scores, so what it can honestly offer is your own verdict, not an error figure."
        }
    }
}
