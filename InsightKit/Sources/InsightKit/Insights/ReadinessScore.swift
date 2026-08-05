import Foundation

/// A transparent daily "readiness / recovery" score (0–100) in the spirit of
/// Oura Readiness and Whoop Recovery — the single number under-30 wearable users
/// check every morning. Unlike those closed scores, every component and weight
/// here is inspectable, and each signal is judged against the user's OWN recent
/// baseline (not a population model), which is what makes it personal.
///
/// Components (present ones are re-weighted to sum to 1):
///  • HRV vs baseline        — higher than your normal = better recovered
///  • Resting HR vs baseline — lower than your normal = better recovered
///  • Sleep duration         — vs a 7.5 h target
///  • Skin-temp deviation    — near your baseline is good; a spike costs points
///  • Respiratory stability  — a jump above baseline costs points
public enum ReadinessScore {

    public struct Component: Sendable, Equatable {
        public let name: String
        public let score: Double      // 0…100
        public let weight: Double
        public let detail: String
        /// The metric this component read. Carried so the detail screen can
        /// chart exactly what the score used — add a component here and it
        /// appears on the chart with no other edit.
        public let metric: MetricType
        /// nil where neither direction is "better" (temperature deviation).
        public let higherIsBetter: Bool?
    }

    public struct Output: Sendable, Equatable {
        public let score: Double
        public let components: [Component]
        public let band: String

        /// Components as chart contributions, with weights renormalised over the
        /// ones that actually had data — the same division the score itself does.
        public var contributions: [MetricContribution] {
            let total = components.reduce(0) { $0 + $1.weight }
            guard total > 0 else { return [] }
            return components.map {
                MetricContribution(metric: $0.metric, higherIsBetter: $0.higherIsBetter,
                                   weight: $0.weight / total, detail: $0.detail)
            }
        }
    }

    static func clamp(_ x: Double) -> Double { max(0, min(100, x)) }

    /// Map a z-score (value vs baseline history) to 0…100 where higher-is-better
    /// signals score up when above baseline. `polarity` flips it for lower-is-better.
    /// Readiness' blood-oxygen component: the reader's own baseline where there
    /// is one, a published fallback where there is not, and an absolute floor
    /// under both.
    ///
    /// **Extracted so it can be swept.** Both halves were steps until
    /// 2026-08-02 — the fallback read `value >= 95 ? 85 : 60`, and the floor
    /// applied its whole effect the instant the value crossed 92. A pulse
    /// oximeter's own resolution is a percentage point, so both lines were
    /// reachable by rounding.
    ///
    /// It lived inline, which meant the continuity sweep had to re-type the
    /// arithmetic to test it — and a test that re-types the code it is checking
    /// passes whatever the code does. Nothing here is testable that is not
    /// callable.
    ///
    /// The floor still bites hard and is still a floor; it arrives over the two
    /// points below 92 rather than all at once. That the *absolute* floor is
    /// deliberate is the reason it survives at all: a baseline built from
    /// consistently low saturation would otherwise normalise the problem away.
    static func oxygenComponent(value: Double, z: Double?) -> Double {
        let component = z.map { zScoreToScore($0, polarity: 1) }
            ?? ScoreCurve.through([(92, 60), (95, 85)], at: value)
        let severity = Swift.min(1, Swift.max(0, (92 - value) / 2))
        return component * (1 - severity) + Swift.min(component, 40) * severity
    }

    static func zScoreToScore(_ z: Double, polarity: Double) -> Double {
        // z of 0 → 65 (a typical day); +1.5 SD in the good direction → ~95.
        clamp(65 + polarity * z * 20)
    }

    /// The metrics the score above can be built from. The adapter needs this
    /// list to tell "no fresh reading today" apart from "never recorded" when
    /// `evaluate` comes back nil — the two get opposite copy, and the first
    /// used to borrow the second's ("wear your device for a few nights") on
    /// every morning the wearable hadn't synced yet.
    public static let componentMetrics: [MetricType] = [
        .heartRateVariabilityRMSSD, .heartRateVariabilitySDNN, .restingHeartRate,
        .sleepDurationHours, .skinTemperatureDeviation, .respiratoryRate,
        .oxygenSaturation
    ]

    /// Readiness is a statement about *today*, so every component is the day's
    /// de-duplicated value judged against a windowed baseline — see `VitalReader`
    /// for why reading `series.last` against `series.dropLast()` was wrong in
    /// four separate ways. A component whose reading is stale is dropped rather
    /// than counted, because a week-old HRV says nothing about this morning.
    public static func evaluate(samples: [HealthMetricSample],
                                now: Date = Date()) -> Output? {
        var comps: [Component] = []

        func fresh(_ type: MetricType) -> VitalReading? {
            guard let reading = VitalReader.reading(type, from: samples, now: now) else { return nil }
            return reading.isFresh ? reading : nil
        }

        // HRV — prefer rMSSD, fall back to SDNN. Higher than baseline is better.
        let hrvMetric: MetricType = fresh(.heartRateVariabilityRMSSD) == nil
            ? .heartRateVariabilitySDNN : .heartRateVariabilityRMSSD
        if let hrv = fresh(hrvMetric), let z = hrv.zScore {
            comps.append(.init(name: "HRV vs your baseline",
                               score: zScoreToScore(z, polarity: 1),
                               weight: 0.40, detail: String(format: "%.0f ms", hrv.value),
                               metric: hrvMetric, higherIsBetter: true))
        }

        // Resting HR — lower than baseline is better.
        if let rhr = fresh(.restingHeartRate), let z = rhr.zScore {
            comps.append(.init(name: "Resting HR vs your baseline",
                               score: zScoreToScore(z, polarity: -1),
                               weight: 0.25, detail: String(format: "%.0f bpm", rhr.value),
                               metric: .restingHeartRate, higherIsBetter: false))
        }

        // Sleep — vs a 7.5 h target (6 h ≈ 55, 8 h ≈ 90).
        if let sleep = fresh(.sleepDurationHours) {
            let s = clamp((sleep.value - 4) / (8.0 - 4) * 100)
            comps.append(.init(name: "Sleep", score: s, weight: 0.20,
                               detail: String(format: "%.1f h", sleep.value),
                               metric: .sleepDurationHours, higherIsBetter: true))
        }

        // Skin-temp deviation — being near baseline is good; a spike (fever /
        // strain / alcohol) pulls it down. Uses the deviation directly — which
        // is why the name must say "vs your baseline": labelled "Body
        // temperature" this row shipped reading "Body temperature: -0.1 °C",
        // a signed offset presented as an absolute temperature.
        if let temp = fresh(.skinTemperatureDeviation) {
            let penalty = min(70, abs(temp.value) * 60)
            comps.append(.init(name: "Skin temp vs your baseline", score: clamp(92 - penalty),
                               weight: 0.10, detail: String(format: "%+.1f °C", temp.value),
                               metric: .skinTemperatureDeviation, higherIsBetter: nil))
        }

        // Respiratory rate — a rise above baseline is an early strain/illness sign.
        if let resp = fresh(.respiratoryRate), let z = resp.zScore {
            comps.append(.init(name: "Respiratory rate", score: zScoreToScore(z, polarity: -1),
                               weight: 0.05, detail: String(format: "%.0f br/min", resp.value),
                               metric: .respiratoryRate, higherIsBetter: false))
        }

        // Overnight blood oxygen — a drop below your own normal accompanies
        // disrupted breathing, altitude and illness, and it moves before you
        // feel it. Small weight: it's a narrow signal, and most nights it says
        // nothing. Absolute floor as well as a personal one, because a baseline
        // built from consistently low saturation would normalise the problem.
        if let spo2 = fresh(.oxygenSaturation) {
            comps.append(.init(name: "Blood oxygen",
                               score: oxygenComponent(value: spo2.value, z: spo2.zScore),
                               weight: 0.05,
                               detail: String(format: "%.0f%%", spo2.value),
                               metric: .oxygenSaturation, higherIsBetter: true))
        }

        guard !comps.isEmpty else { return nil }
        let total = comps.reduce(0) { $0 + $1.weight }
        let score = comps.reduce(0) { $0 + $1.score * $1.weight } / total
        return Output(score: score, components: comps, band: band(score))
    }

    /// The card's explanation, built **from whatever score is actually shown**.
    ///
    /// It used to be written inside `score(...)` from the raw component score
    /// while the dial displayed the *blended* one that folds in the wider vitals
    /// scan — so the card read "73.8" above a sentence saying "69/100". One
    /// builder, called with the final number, is the only way those cannot
    /// drift apart again.
    public static func explanation(score: Double, scannedSignals: Int) -> String {
        let base = "Your recovery today is \(Int(score.rounded()))/100 (\(band(score))), "
            + "from how your HRV, resting heart rate, sleep and temperature "
            + "compare with your own recent baseline"
        guard scannedSignals > 0 else { return base + "." }
        return base + ", together with \(scannedSignals) other "
            + "\(scannedSignals == 1 ? "vital" : "vitals") the daily scan checked."
    }

    static func band(_ score: Double) -> String {
        switch score {
        case 80...: return "Primed"
        case 66..<80: return "Ready"
        case 50..<66: return "Take it easy"
        default: return "Recover"
        }
    }
}

/// `InsightModel` adapter. Readiness needs no grounding — it's built entirely
/// from sensed signals compared to the user's own history.
/// How you are today: the morning score, the vitals scan, and the early warning.
///
/// One card from three. Readiness scored recovery, Vitals Check listed which
/// signals sat outside their usual range, and Health Watch reported several
/// leaning the same way at once — three cards doing one job, *scanning your
/// signals against your own baseline*, and all three reading HRV and resting
/// heart rate to do it.
///
/// **The two absorbed models are unchanged.** `VitalSignsCheck` and
/// `HealthWatchModel` keep their own tests and are called here as components.
/// They contribute **driver lines**, not score terms: Readiness already weights
/// the signals it scores, and adding a second opinion on the same measurements
/// would count them twice — the double-counting this app has had to unpick
/// before.
public struct ReadinessInsight: InsightModel {
    public let id: InsightID = .readiness
    public let title = "Readiness"
    public init() {}

    public var requirements: [GroundingRequirement] { [] }

    /// Everything `ReadinessScore.evaluate` can read, plus the wider set the two
    /// absorbed scanners cover. Both HRV flavours appear because readiness
    /// prefers rMSSD and falls back to SDNN.
    public var candidateMetrics: [MetricType] {
        var metrics: [MetricType] = [
            .heartRateVariabilityRMSSD, .heartRateVariabilitySDNN, .restingHeartRate,
            .sleepDurationHours, .skinTemperatureDeviation, .respiratoryRate,
            .oxygenSaturation
        ]
        // Union, order-preserving: the scanners add heart rate, walking heart
        // rate, body and skin temperature and the rest of the vitals panel, and
        // a duplicate here would draw the same series twice on the overlay.
        // `{ $0.metric }` rather than `\.metric` on `watched`: it is an array of
        // tuples, and a key path into a tuple element is a compile error.
        for extra in VitalSignsCheck.specs.map(\.metric) + HealthWatchModel.watched.map({ $0.metric })
        where !metrics.contains(extra) {
            metrics.append(extra)
        }
        return metrics
    }

    /// The samples-only overload the protocol requires. Readiness reads events,
    /// so this is the degraded path — a caller with no event source still gets
    /// the score and the vitals scan, just not the device-raised flags.
    public func evaluate(samples: [HealthMetricSample], profile: UserHealthProfile,
                         now: Date) -> InsightResult {
        evaluate(samples: samples, events: [], profile: profile, now: now)
    }

    public func evaluate(samples: [HealthMetricSample], events: [VitalEvent],
                         profile: UserHealthProfile, now: Date) -> InsightResult {
        let base = score(samples: samples, profile: profile, now: now)
        let scan = VitalSignsCheck.evaluate(samples: samples, events: events, now: now)
        let watch = HealthWatchModel.evaluate(samples: samples, now: now)

        // Notable lines from the two scanners, appended to whatever readiness
        // already had to say. A device-raised event leads outright — an
        // irregular-rhythm notification is a judgement Apple already made, and
        // burying it under a recovery score would be the wrong call.
        var extra: [InsightDriver] = scan.events.map {
            .notable("\($0.kind.displayName): \($0.kind.note)")
        }
        let flagged = scan.unusual + scan.watch
        extra += flagged.map { .notable(VitalSignsCheck.describe($0)) }
        // A vital we couldn't judge counts as notable: "not enough history" is a
        // thing to know, not reassurance, and folding it in with the normal
        // readings would let one measurement read as a clean bill.
        extra += scan.unknown.map { .notable(VitalSignsCheck.describe($0)) }
        if let watch, watch.leaning.count >= 2 {
            // The disclaimer travels with the finding, not just with the card.
            // Health Watch carried it in its own explanation; losing the card
            // must not lose the sentence, and a driver line can be read aloud
            // by the summariser well away from any screen disclaimer.
            extra.append(.notable("\(watch.leaning.count) signals are leaning the same way at once — individually inside the noise, together the pattern a body tends to show before an illness announces itself. An observation about your own numbers, not a diagnosis — if you feel unwell, treat that as the better information."))
        }
        // A vital readiness already scored as a component has had its say —
        // "HRV vs your baseline: 50 ms" — and the scan's ordinary-range line for
        // the same metric adds nothing but a second row about one signal. That
        // duplication is why "What's driving this" counted nearly twice what
        // every other section did. Only the *ordinary* lines are dropped:
        // flagged and unjudged readings carry news the component line doesn't,
        // so they stay even when they name a scored metric.
        let componentMetrics = Set(base.contributors.map(\.metric))
        extra += scan.readings
            .filter { $0.status == .normal && !componentMetrics.contains($0.metric) }
            .map { .routine(VitalSignsCheck.describe($0)) }
        extra += scan.stale.map { .routine(VitalSignsCheck.describe($0, now: now)) }

        // Every vital the scan looked at now carries a share, where readiness
        // didn't already weight it.
        //
        // **Nothing is invented for these, and that is the point.** The scan has
        // computed a direction-aware `normality` for each of its seventeen
        // signals since it was written — including the absolute clinical bounds
        // a personal baseline cannot see — and that number is what a share is
        // taken from. It was already trusted enough to decide what the card
        // *says*; it was reaching the score at weight 0 while doing so, so a
        // card could name an unusual vital in its headline and have that vital
        // contribute nothing to the number underneath it.
        //
        // `SupportingSignal.collectiveShare` between them, so eleven ordinary
        // vitals move the number a little and cannot swamp the six components
        // readiness weights on their own terms.
        // The same set the driver lines above de-duplicate against — one
        // statement of "which metrics readiness scored itself".
        let supporting: [ScoreBlend.Term] = scan.readings
            .filter { !componentMetrics.contains($0.metric) && $0.status != .insufficientHistory }
            .map { reading in
                let spec = VitalSignsCheck.specs.first { $0.metric == reading.metric }
                return ScoreBlend.Term(
                    metric: reading.metric,
                    higherIsBetter: spec.flatMap {
                        $0.concernWhenHigh ? false : ($0.concernWhenLow ? true : nil)
                    },
                    score: reading.normality, weight: 1,
                    detail: MetricValueFormatter.string(reading.value, reading.metric)
                        + " · \(reading.note)",
                    isPublishedScale: false)
            }
        let blend = ScoreBlend.blend(
            primary: base.contributors.map {
                ScoreBlend.Term(metric: $0.metric, higherIsBetter: $0.higherIsBetter,
                                score: 0, weight: $0.weight, detail: $0.detail)
            },
            supporting: supporting)
        let contributors = blend?.contributions ?? base.contributors
        // The blended *score*, computed from the same weights, so the bars and
        // the dial cannot disagree. Recombined here rather than taken from
        // `blend` because `base.contributors` carries each component's share and
        // not its 0–100, and re-deriving those would mean running
        // `ReadinessScore` twice.
        let scanShare = supporting.isEmpty ? 0 : SupportingSignal.collectiveShare
        let scanScore = supporting.isEmpty ? 0
            : supporting.reduce(0) { $0 + $1.score } / Double(supporting.count)
        let blendedScore = base.score.map { $0 * (1 - scanShare) + scanScore * scanShare }

        // A device-raised flag outranks a day of ordinary numbers.
        //
        // Apple has already made this judgement with no baseline and no
        // z-score, and burying it under a recovery band would be the wrong
        // call — it was the Vitals Check card's headline before the merge, and
        // losing that would be a safety regression rather than a tidy-up.
        if let event = scan.events.first {
            return InsightResult(
                id: id, title: title,
                primaryValue: blendedScore ?? Double(scan.readings.count),
                headline: event.kind.displayName,
                // Floored, not zeroed: the rest of the morning is still true.
                score: Swift.min(blendedScore ?? 45, 45),
                confidence: base.confidence,
                explanation: "Your \(event.sourceName) flagged \(event.kind.displayName.lowercased()) — \(event.kind.note). " + base.explanation,
                driverLines: (base.driverLines + extra).filter { $0.isNotable == true }
                    + (base.driverLines + extra).filter { $0.isNotable != true },
                unmetRequirements: base.unmetRequirements,
                contributors: contributors, weighting: base.weighting,
                isAwaitingTodaysData: base.isAwaitingTodaysData)
        }

        return InsightResult(
            id: id, title: title, primaryValue: blendedScore ?? base.primaryValue,
            headline: blendedScore.map { ReadinessScore.band($0) } ?? base.headline,
            score: blendedScore, confidence: base.confidence,
            // Rebuilt from the blended score, never inherited: `base` was
            // written before the vitals scan was folded in, and reusing its
            // sentence is what put two different numbers on one card.
            explanation: blendedScore.map {
                ReadinessScore.explanation(score: $0, scannedSignals: supporting.count)
            } ?? base.explanation,
            driverLines: (base.driverLines + extra).filter { $0.isNotable == true }
                + (base.driverLines + extra).filter { $0.isNotable != true },
            unmetRequirements: base.unmetRequirements, contributors: contributors,
            weighting: base.weighting,
            isAwaitingTodaysData: base.isAwaitingTodaysData,
            // Forwarded like every other field from `base`, and it was the one
            // that got missed — `score(_:)` set `invitesInput` and this rebuild
            // silently dropped it, so the card asked for a wearable and was
            // filtered off Today anyway. A wrapper that reconstructs a value
            // field-by-field will lose the next field added to it too; the
            // visibility sweep in `CardVisibilityTests` is what catches that.
            invitesInput: base.invitesInput)
    }

    /// The readiness score proper. Split out so the merged `evaluate` above
    /// reads as "score, then scan, then warn" rather than one long function.
    private func score(samples: [HealthMetricSample], profile: UserHealthProfile,
                       now: Date) -> InsightResult {
        guard let out = ReadinessScore.evaluate(samples: samples, now: now) else {
            // Nothing fresh enough to score. Two very different mornings look
            // like this, and they need opposite sentences: a person who has
            // never worn a device (tell them to start), and a person with
            // months of nights whose wearable simply hasn't synced *today*
            // (tell them that — "wear your device for a few nights" to
            // someone on night 170 reads as the app having lost their data,
            // and hiding the card entirely is how "cards keep disappearing
            // from Today" got reported).
            // "Waiting" is only the honest state when a score would actually
            // come back with fresh data: an established baseline (the same
            // seven-day floor the scan judges by) and a reading recent enough
            // that this is a sync gap, not an abandoned wearable. Two nights of
            // history is genuinely a building baseline however fresh they are —
            // "fills in once your wearable syncs" would be a false promise.
            let recorded = ReadinessScore.componentMetrics
                .flatMap { samples.samples(of: $0) }
                .map(\.start)
            let calendar = Calendar.current
            let recordedDays = Set(recorded.map { calendar.startOfDay(for: $0) })
            if let latest = recorded.max(),
               recordedDays.count >= VitalSignsCheck.minimumBaselineDays {
                let days = max(1, Int(now.timeIntervalSince(latest) / 86_400))
                if days <= 3 {
                    let age = days == 1 ? "yesterday" : "\(days) days ago"
                    return InsightResult(
                        id: id, title: title, primaryValue: nil,
                        headline: "Waiting for today's sync",
                        score: nil, confidence: .low,
                        explanation: "Readiness is about today, and nothing from today has arrived yet — your latest readings are from \(age). This fills in on its own once your wearable syncs; pull to refresh to ask again.",
                        drivers: [], unmetRequirements: [],
                        isAwaitingTodaysData: true)
                }
            }
            // Two different states, and they want two different sentences. A
            // reader with *some* nights is being told to keep going; a reader
            // with none has nothing connected and is being told to connect it.
            // Collapsing them reads as "still building" to someone who has
            // never given the app anything, which is not an ask.
            let hasAnyReadings = !recorded.isEmpty
            return invitingInput(
                id, title,
                action: hasAnyReadings ? "Building baseline" : "Connect a wearable",
                message: hasAnyReadings
                    ? "Wear your device for a few nights so we can learn your normal HRV, resting heart rate and sleep — then you'll get a daily readiness score. Readings older than a day or so don't count: readiness is about today."
                    : "Connect a wearable (Oura, Whoop or Apple Health) and wear it for a few nights. Readiness compares last night against your own normal HRV, resting heart rate and sleep, so it needs a few of your own nights before it can say anything.")
        }
        let confidence: InsightConfidence = out.components.count >= 3 ? .high
            : out.components.count == 2 ? .moderate : .low
        // Components that are holding the score down come first and stay
        // visible; the ones behaving normally fold away on the detail screen.
        // Partitioned rather than sorted: Swift's sort isn't stable, and the
        // weight order components arrive in is meaningful.
        let lines = out.components
            .map { InsightDriver.component("\($0.name): \($0.detail)", score: $0.score) }
        return InsightResult(
            id: id, title: title, primaryValue: out.score,
            headline: out.band, score: out.score, confidence: confidence,
            explanation: ReadinessScore.explanation(score: out.score, scannedSignals: 0),
            driverLines: lines.filter { $0.isNotable == true } + lines.filter { $0.isNotable != true },
            unmetRequirements: [], contributors: out.contributions,
            weighting: .weightedAverage)
    }
}
