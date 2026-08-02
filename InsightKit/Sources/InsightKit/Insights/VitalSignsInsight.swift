import Foundation

/// A daily scan of every sensed vital against the user's own recent baseline.
///
/// This exists because several metrics the app collects in quantity had no
/// reader at all: heart rate (tens of thousands of samples), walking heart
/// rate, blood oxygen and body temperature were stored, charted, and then
/// ignored by every insight. Readiness answers "how recovered am I"; this
/// answers the different and more clinical question "is anything off today",
/// which is what a vitals panel is for.
///
/// Deliberately not a weighted score. A vitals check should report the
/// *outliers*, not average an abnormal SpO₂ against a normal heart rate until
/// the abnormality disappears.
///
/// ## Why this was rebuilt
///
/// The first version reported "All normal" and a score of 100 on essentially
/// every day, for reasons that were all structural rather than clinical:
///
/// - **The baseline was the anomaly.** History was `suffix(60)` — sixty
///   *readings*, not sixty days. Heart rate arrives raw at roughly 300 samples
///   a day, so "your personal baseline" was the last five hours, and a
///   sustained fever or tachycardia was mathematically undetectable because the
///   baseline moved with it. It once printed a baseline heart rate of 100 bpm.
/// - **Nothing checked the date.** `now` was accepted and never used, so a
///   reading of any age counted as current, was normal by construction, and
///   bought high confidence. The copy said "measured today" without ever
///   asking.
/// - **Two sources became one inflated variance.** The same ring arriving
///   directly and via Apple Health both survived, and inter-device
///   disagreement — not physiology — set the standard deviation.
/// - **The score was a step function.** `100 - (unusual*25 + watch*10)` ignored
///   the z-scores it carried, so z = 1.24 cost nothing and z = 1.25 cost ten.
///
/// Each is addressed below, and each has a test that the old fixtures could not
/// have caught — every one of them was a single sample per day, from a single
/// source, always fresh, which is the one shape in which the old code behaved.
public enum VitalSignsCheck {

    /// One vital, judged against the personal baseline.
    public struct Reading: Sendable, Equatable {
        public enum Status: String, Sendable, Equatable {
            case normal, watch, unusual
            /// Present, fresh, but without enough history to say anything.
            /// Deliberately not `.normal`: one reading is not a clean bill.
            case insufficientHistory
        }
        public let metric: MetricType
        /// The day's representative value, not the newest raw sample.
        public let value: Double
        public let baseline: Double?
        public let zScore: Double?
        public let status: Status
        public let note: String
        /// 0–100, continuous. How ordinary this reading is for this person.
        public let normality: Double
        /// Start of the day this value represents.
        public let measuredAt: Date
        /// Which device the judgement was made against.
        public let sourceName: String
        /// Days of history the baseline was built from — what
        /// `insufficientHistory` is short of. Carried on the reading so the
        /// model-internals export states the shortfall rather than inferring it.
        public let historyDays: Int
    }

    /// A vital the user records, but not recently enough to describe today.
    public struct StaleReading: Sendable, Equatable {
        public let metric: MetricType
        public let value: Double
        public let lastMeasured: Date
    }

    public struct Output: Sendable, Equatable {
        /// Vitals with a reading recent enough to speak for today.
        public let readings: [Reading]
        /// Vitals this user records, but not lately.
        public let stale: [StaleReading]
        /// Device-raised notifications inside the event window.
        public let events: [VitalEvent]
        /// 0–100, or nil when nothing was fresh enough to score.
        public let score: Double?
        /// Fraction of the vitals this user normally records that were
        /// measured in time. What makes a perfect score hard.
        public let coverage: Double

        public var unusual: [Reading] { readings.filter { $0.status == .unusual } }
        public var watch: [Reading] { readings.filter { $0.status == .watch } }
        public var unknown: [Reading] { readings.filter { $0.status == .insufficientHistory } }

        public var headline: String {
            // A device notification outranks anything a z-score found: the
            // watch has already decided this was worth interrupting you for.
            if let event = events.first { return event.kind.displayName }
            if !unusual.isEmpty { return "\(unusual.count) unusual" }
            if !watch.isEmpty { return "\(watch.count) to watch" }
            if readings.isEmpty { return "Nothing measured" }
            if unknown.count == readings.count { return "Building baseline" }
            // "All normal" is only honest when we actually looked at everything
            // this person records, and had the history to judge it. Previously
            // it was said whatever the coverage.
            if !stale.isEmpty || !unknown.isEmpty || coverage < 0.999 {
                return "\(readings.count - unknown.count) of \(readings.count + stale.count) checked"
            }
            return "All normal"
        }
    }

    /// Vitals to scan, and which direction is a concern.
    ///
    /// `concernWhenHigh` / `concernWhenLow` mark the clinically meaningful
    /// direction; a departure the other way costs less, because a resting heart
    /// rate below baseline is usually good news and shouldn't read like an alarm.
    struct Spec {
        let metric: MetricType
        let concernWhenHigh: Bool
        let concernWhenLow: Bool
        /// Absolute bounds that mean something regardless of personal baseline.
        let hardLow: Double?
        let hardHigh: Double?
        /// How far past a hard bound counts as maximally abnormal. Explicit per
        /// metric because no single rule works: 6 percentage points of oxygen
        /// saturation and 1.5 °C of body temperature are comparable alarms, and
        /// neither is a fixed fraction of its bound.
        let hardTolerance: Double
        /// Fraction of the long-run median below which the value is a concern
        /// regardless of z. HRV has no meaningful absolute floor, but a slow
        /// collapse walks its own baseline down and so is invisible to a
        /// z-score — this is the instrument that catches it.
        let relativeFloor: Double?
        /// How recently this must have been measured to describe today. Not
        /// every vital is a daily one: nobody takes their blood pressure every
        /// morning, and demanding it would permanently cap the score.
        let freshWithin: TimeInterval
        let format: String
        /// A metric that reports this same physiological signal better. When
        /// that one produced a reading on this pass, this spec is skipped.
        ///
        /// One signal, one row. A skin temperature reconstructed from a nightly
        /// deviation is an affine shift of that deviation — adding a constant
        /// moves the mean and leaves the spread alone — so the two carry
        /// *mathematically identical* z-scores. Scanning both put one signal
        /// into the penalty pool twice, and because `score` is
        /// worst-offender-dominant an ordinary +0.35 °C night scored 26.8 as one
        /// row and 1.1 as two.
        ///
        /// Declared last, `var`, and defaulted, on purpose. `Spec` has no
        /// explicit initialiser, so the memberwise one is synthesised in
        /// declaration order — and a `let` that already carries a value is
        /// omitted from it entirely, because it could never be assigned. Only
        /// `var … = nil` yields the optional trailing argument the eighteen
        /// `Spec` literals below rely on.
        var supersededBy: MetricType? = nil

        /// Which direction is the good one, for a chart legend. `nil` when both
        /// directions are a concern (respiratory rate, body temperature) — there
        /// the good place is the middle, and calling either end "better" is wrong.
        var higherIsBetter: Bool? {
            switch (concernWhenHigh, concernWhenLow) {
            case (true, false): return false
            case (false, true): return true
            default: return nil
            }
        }
    }

    static let day: TimeInterval = 86_400

    /// Every metric the scan can judge at all. "How far from your normal" needs
    /// this to tell a card whose signals the scan will *never* cover (body
    /// composition — nothing in `specs` is a scale reading) apart from one whose
    /// signals just lack history: the first shipped as "not enough history yet …
    /// this arrives on its own", two false claims under a legend already quoting
    /// SD-from-baseline figures for those same signals.
    public static var coveredMetrics: Set<MetricType> { Set(specs.map(\.metric)) }

    static let specs: [Spec] = [
        // Bounds now apply to the day's representative value rather than to
        // whatever raw sample happened to be last, so a resting figure of 100
        // is meaningful where the old instantaneous 120 fired on a workout
        // minute and never at rest.
        Spec(metric: .heartRate, concernWhenHigh: true, concernWhenLow: false,
             hardLow: 40, hardHigh: 100, hardTolerance: 30, relativeFloor: nil,
             freshWithin: 1.5 * day, format: "%.0f"),
        Spec(metric: .restingHeartRate, concernWhenHigh: true, concernWhenLow: false,
             hardLow: 38, hardHigh: 100, hardTolerance: 25, relativeFloor: nil,
             freshWithin: 1.5 * day, format: "%.0f"),
        // Was 130, which sits above almost any real walking heart rate and so
        // could never fire.
        Spec(metric: .walkingHeartRateAverage, concernWhenHigh: true, concernWhenLow: false,
             hardLow: nil, hardHigh: 115, hardTolerance: 25, relativeFloor: nil,
             freshWithin: 3 * day, format: "%.0f"),
        // 94% is the clinical attention line. 92% — the old floor — is already
        // "call someone", so it flagged far too late.
        Spec(metric: .oxygenSaturation, concernWhenHigh: false, concernWhenLow: true,
             hardLow: 94, hardHigh: nil, hardTolerance: 6, relativeFloor: nil,
             freshWithin: 1.5 * day, format: "%.0f"),
        Spec(metric: .respiratoryRate, concernWhenHigh: true, concernWhenLow: true,
             hardLow: 10, hardHigh: 20, hardTolerance: 6, relativeFloor: nil,
             freshWithin: 1.5 * day, format: "%.0f"),
        // CORE temperature only. 37.8 °C is the oral fever line (Mackowiak's 1992
        // re-appraisal of 98.6 °F put the 99th centile of normal oral
        // temperature at 37.7 °C), and 35.5 sits half a degree above the <35.0
        // definition of accidental hypothermia. Neither bound means anything
        // applied to *skin*, which runs two to three degrees cooler — and 35.5
        // was identical to `TemperatureReconstructor.defaultBaselineCelsius`, so
        // a reconstructed value read "below the usual healthy range" on every
        // night the deviation happened to be negative. Roughly half of them.
        Spec(metric: .bodyTemperature, concernWhenHigh: true, concernWhenLow: true,
             hardLow: 35.5, hardHigh: 37.8, hardTolerance: 1.5, relativeFloor: nil,
             freshWithin: 1.5 * day, format: "%.1f"),
        // No absolute bound is defensible — rMSSD spans roughly 15–150 ms with
        // age, fitness and device — but a fall to 60% of the long-run median is
        // a real signal a rolling z-score cannot see.
        Spec(metric: .heartRateVariabilityRMSSD, concernWhenHigh: false, concernWhenLow: true,
             hardLow: nil, hardHigh: nil, hardTolerance: 1, relativeFloor: 0.6,
             freshWithin: 1.5 * day, format: "%.0f"),
        // SDNN is the HRV *Apple Watch* actually records — rMSSD only ever
        // arrives from Oura or Whoop. Its absence meant an Apple-only user got
        // no HRV row at all, and so fell below the confidence threshold too.
        Spec(metric: .heartRateVariabilitySDNN, concernWhenHigh: false, concernWhenLow: true,
             hardLow: nil, hardHigh: nil, hardTolerance: 1, relativeFloor: 0.6,
             freshWithin: 1.5 * day, format: "%.0f"),
        // Blood pressure has the least ambiguous bounds in medicine and was
        // missing entirely. A week's freshness because nobody cuffs daily.
        Spec(metric: .bloodPressureSystolic, concernWhenHigh: true, concernWhenLow: true,
             hardLow: 90, hardHigh: 140, hardTolerance: 40, relativeFloor: nil,
             freshWithin: 7 * day, format: "%.0f"),
        Spec(metric: .bloodPressureDiastolic, concernWhenHigh: true, concernWhenLow: true,
             hardLow: 60, hardHigh: 90, hardTolerance: 30, relativeFloor: nil,
             freshWithin: 7 * day, format: "%.0f"),
        // Judged on the deviation itself, which is what it is: no absolute
        // bound, because the zero point is already the personal baseline.
        Spec(metric: .skinTemperatureDeviation, concernWhenHigh: true, concernWhenLow: true,
             hardLow: -1.5, hardHigh: 1.5, hardTolerance: 1, relativeFloor: nil,
             freshWithin: 1.5 * day, format: "%+.1f"),
        // Absolute skin temperature: Whoop's nightly figure, Withings type 73,
        // Apple's sleeping wrist temperature, and deviations reconstructed onto
        // a learned baseline. No hard bound is defensible — nightly wrist skin
        // temperature tracks ambient warmth, bedding and vasomotor tone across
        // roughly 31–36 °C in ordinary sleep, which is precisely why Oura, Apple
        // and Hume publish a deviation rather than a number. Judged on the
        // personal z-score alone, like the two HRV specs above.
        //
        // Must stay *after* the deviation spec: `supersededBy` is resolved
        // against the readings collected so far, and `testASupersededSpecComesAfterTheOneThatSupersedesIt`
        // pins the ordering.
        Spec(metric: .skinTemperature, concernWhenHigh: true, concernWhenLow: true,
             hardLow: nil, hardHigh: nil, hardTolerance: 1, relativeFloor: nil,
             freshWithin: 1.5 * day, format: "%.1f",
             supersededBy: .skinTemperatureDeviation),
        Spec(metric: .bloodGlucose, concernWhenHigh: true, concernWhenLow: true,
             hardLow: 3.9, hardHigh: 10, hardTolerance: 4, relativeFloor: nil,
             freshWithin: 1.5 * day, format: "%.1f"),
        Spec(metric: .peripheralPerfusionIndex, concernWhenHigh: false, concernWhenLow: true,
             hardLow: 0.5, hardHigh: nil, hardTolerance: 0.5, relativeFloor: nil,
             freshWithin: 1.5 * day, format: "%.1f"),
        // Zero is the healthy value, so any burden at all is worth surfacing.
        Spec(metric: .atrialFibrillationBurden, concernWhenHigh: true, concernWhenLow: false,
             hardLow: nil, hardHigh: 2, hardTolerance: 20, relativeFloor: nil,
             freshWithin: 7 * day, format: "%.1f"),
        Spec(metric: .heartRateRecovery, concernWhenHigh: false, concernWhenLow: true,
             hardLow: 12, hardHigh: nil, hardTolerance: 10, relativeFloor: nil,
             freshWithin: 3 * day, format: "%.0f"),
        // Apple publishes its own bands: below 50% is Low, below 20% Very Low.
        // Computed over a rolling window, so a fortnight is not staleness.
        Spec(metric: .walkingSteadiness, concernWhenHigh: false, concernWhenLow: true,
             hardLow: 50, hardHigh: nil, hardTolerance: 30, relativeFloor: nil,
             freshWithin: 14 * day, format: "%.0f"),
        Spec(metric: .walkingAsymmetry, concernWhenHigh: true, concernWhenLow: false,
             hardLow: nil, hardHigh: 10, hardTolerance: 20, relativeFloor: nil,
             freshWithin: 14 * day, format: "%.0f")
    ]

    /// z beyond this is "unusual"; beyond the smaller one is "watch".
    static let unusualZ = 2.0
    static let watchZ = 1.25

    /// Days of history the baseline is built from, and the minimum that must be
    /// present before any judgement is made.
    static let baselineDays = 28
    static let minimumBaselineDays = 7
    /// A metric seen at all within this window is one the user "normally
    /// records", and therefore counts toward coverage.
    static let expectedWindow: TimeInterval = 30 * 86_400

    // MARK: - Evaluation

    /// How recently a device-raised event still describes "today".
    public static let eventWindow: TimeInterval = 36 * 3600

    public static func evaluate(samples: [HealthMetricSample],
                                events: [VitalEvent] = [],
                                now: Date = Date(),
                                calendar: Calendar = .current) -> Output {
        var readings: [Reading] = []
        var stale: [StaleReading] = []

        for spec in specs {
            // One row per physiological signal. A metric that is a derived view
            // of another — an absolute skin temperature reconstructed from a
            // deviation — stands down when the signal it came from already spoke
            // this pass, rather than entering the same z-score twice.
            //
            // Keyed on a reading actually being produced, not merely on samples
            // existing: when the better signal is stale or too short to judge,
            // the derived row stays and the user keeps a thermal reading instead
            // of losing it to a technicality.
            if let better = spec.supersededBy,
               readings.contains(where: { $0.metric == better }) { continue }

            // The day's representative value, from one de-duplicated device,
            // against a windowed baseline, with freshness attached.
            //
            // This used to be forty lines of inline code here — and `VitalReader`
            // is that code, extracted, because every other insight was writing its
            // own version and getting it wrong differently. Keeping a private copy
            // alive in the file the shared one came from is how the two drift
            // apart; `testTheReaderAgreesWithVitalsCheckOnSourceSelection` pins
            // that they don't.
            guard let vital = VitalReader.reading(
                spec.metric, from: samples, now: now,
                windowDays: baselineDays, minimumDays: minimumBaselineDays,
                freshWithin: spec.freshWithin, calendar: calendar) else { continue }

            if vital.isFresh {
                readings.append(reading(spec: spec, value: vital.value, at: vital.date,
                                        history: vital.history, source: vital.sourceName))
            } else if now.timeIntervalSince(vital.date) <= expectedWindow {
                // Recorded by this user, just not lately. Counted against
                // coverage rather than silently reported as fine.
                stale.append(StaleReading(metric: spec.metric, value: vital.value,
                                          lastMeasured: vital.date))
            }
        }

        let expected = readings.count + stale.count
        let coverage = expected == 0 ? 0 : Double(readings.count) / Double(expected)
        let recentEvents = events.recent(within: eventWindow, of: now)
        return Output(readings: readings, stale: stale, events: recentEvents,
                      score: score(readings: readings, events: recentEvents,
                                   coverage: coverage),
                      coverage: coverage)
    }

    // `primary(from:)` lived here — "which device's verdict to report when
    // several measured the same vital". It is `VitalReader`'s job now, and a
    // dead copy of a rule is how two answers to one question get born.

    static func reading(spec: Spec, value: Double, at date: Date,
                        history: [Double], source: String) -> Reading {
        let deviation = history.count >= minimumBaselineDays
            ? Baseline.deviation(latest: value, history: history)
            : nil
        let z = deviation?.zScore

        var status = Reading.Status.normal
        var note = "in your normal range"

        if let z {
            // The thresholds live in `VitalDeparture` so the Readiness strip
            // shades its bands at the edges this scan actually judges by. Two
            // copies of a threshold drift, and here the drift would be invisible:
            // a dot sitting on the quiet side of a line the card had already
            // called. This is the only place they are applied.
            let concerning = VitalDeparture.isConcerning(z: z, spec: spec)
            switch VitalDeparture.band(z: z, concerning: concerning) {
            case .unusual: status = .unusual
            case .watch: status = .watch
            case .ordinary: status = .normal
            }
            // Only re-word when the status actually moved. The old version
            // overwrote the note even when it kept `.normal`, so a card could
            // read "All normal" and "a little above your baseline" in one breath.
            if status != .normal {
                let far = abs(z) >= unusualZ
                note = (far ? "well " : "a little ")
                    + (z > 0 ? "above your baseline" : "below your baseline")
            }
        } else if history.count < minimumBaselineDays {
            status = .insufficientHistory
            note = "not enough history yet to judge this"
        }

        var normality = self.normality(z: z, spec: spec)

        // An absolute bound overrides a personal one: a baseline built from
        // consistently low oxygen saturation would otherwise normalise it.
        if let hardLow = spec.hardLow, value < hardLow {
            status = .unusual
            note = "below the usual healthy range"
            normality = boundNormality(normality, distance: hardLow - value, spec: spec)
        }
        if let hardHigh = spec.hardHigh, value > hardHigh {
            status = .unusual
            note = "above the usual healthy range"
            normality = boundNormality(normality, distance: value - hardHigh, spec: spec)
        }

        // The relative floor, for metrics whose baseline can drift downward
        // with the very decline being looked for.
        // Ramped for the same reason the hard bounds are, and it matters more
        // here: this fires on HRV, the noisiest series in the app. `min(…, 25)`
        // the instant the value crossed `median × 0.6` was a 57-point step for a
        // reader with a wide spread — and a wide spread is exactly who has one.
        if let fraction = spec.relativeFloor,
           let median = Baseline.quantile(0.5, of: history),
           median > 0, value < median * fraction {
            status = .unusual
            note = "well below your usual level"
            let floor = median * fraction
            normality = Swift.min(normality,
                                  relativeFloorNormality(normality, value: value, floor: floor))
        }

        // A reading we cannot judge is not a clean one. Held at a middling
        // figure so it neither rewards nor punishes.
        if status == .insufficientHistory { normality = 70 }

        return Reading(metric: spec.metric, value: value, baseline: deviation?.baseline,
                       zScore: z, status: status, note: note, normality: normality,
                       measuredAt: date, sourceName: source, historyDays: history.count)
    }

    /// How ordinary a reading is, 0–100, continuous in z.
    ///
    /// A Gaussian falloff rather than the old step function: z 0 → 100, 1 → 82,
    /// 2 → 46, 3 → 17. Previously every value inside |z| < 1.25 scored an
    /// identical 100 and a hair's movement past it cost ten points at once.
    static func normality(z: Double?, spec: Spec) -> Double {
        guard let z else { return 85 }
        let base = 100 * exp(-0.5 * pow(z / 1.6, 2))
        let high = z > 0
        let concerning = (high && spec.concernWhenHigh) || (!high && spec.concernWhenLow)
        // A departure away from the concerning direction still costs something
        // — it is a change — but only half as much.
        return concerning ? base : 100 - (100 - base) * 0.5
    }

    /// Normality for a value already outside a hard bound, falling to zero at
    /// the spec's tolerance.
    ///
    /// **It scales what the curve gave rather than capping at a constant**, and
    /// that is a fix. It used to be `min(normality, 35 * (1 - severity))`, which
    /// returns 35 at a distance of zero — so crossing the bound by a thousandth
    /// of a unit dropped a reading's normality from whatever the Gaussian said
    /// straight to 35. For blood oxygen with a baseline of 95 that is 82 → 35 in
    /// one step, and 100 → 35 for a reader whose baseline sits on the bound
    /// itself. Sixty-five points for a number a pulse oximeter cannot even
    /// resolve.
    ///
    /// Scaling is continuous by construction: at distance 0 the factor is 1 and
    /// this returns exactly what it was handed, so the bound stops being a step
    /// and starts being a slope that reaches 0 at the spec's tolerance.
    ///
    /// **The safety intent survives, and it was never carried by the number.**
    /// The point of a hard bound is that a baseline built from consistently low
    /// oxygen must not normalise it — and what says so on screen is `status`
    /// flipping to `.unusual` with "below the usual healthy range" beside it,
    /// which happens at the bound exactly as before. What changed is only that a
    /// reading a hair past the line is no longer scored as though it were half
    /// way to the tolerance.
    static func boundNormality(_ normality: Double, distance: Double, spec: Spec) -> Double {
        guard spec.hardTolerance > 0 else { return 0 }
        let severity = Swift.min(1, Swift.max(0, distance / spec.hardTolerance))
        return normality * (1 - severity)
    }

    /// How far below `median × relativeFloor` a reading has to fall before the
    /// floor takes the whole of its normality.
    ///
    /// A further 40% of the floor. The floor is already `median × 0.6`, so on an
    /// HRV median of 50 the cap starts biting at 30 and is total at 18 — a
    /// range nobody reaches by noise, which is the point. The old version
    /// applied its whole effect at 30 exactly.
    static let relativeFloorSpan = 0.4

    /// The relative floor's cap, ramped rather than applied all at once.
    ///
    /// Continuous at the floor by construction: the factor is 1 there, so this
    /// returns what it was handed and the `min` is a no-op.
    static func relativeFloorNormality(_ normality: Double, value: Double,
                                       floor: Double) -> Double {
        guard floor > 0 else { return normality }
        let span = floor * relativeFloorSpan
        let severity = Swift.min(1, Swift.max(0, (floor - value) / span))
        return normality * (1 - severity)
    }

    /// The overall figure.
    ///
    /// Worst-offender-dominant, because this insight reports outliers rather
    /// than averaging them away — but the remaining signals still move it, so a
    /// day where everything is slightly off no longer ties with a pristine one.
    /// Then capped by coverage, which is what makes 100 hard: it requires
    /// everything this person normally records to have been measured *and* to
    /// sit on its baseline.
    static func score(readings: [Reading], events: [VitalEvent] = [],
                      coverage: Double) -> Double? {
        guard !readings.isEmpty || !events.isEmpty else { return nil }
        // An event enters the pool as a penalty in its own right, so a watch
        // notification can dominate a day of otherwise ordinary numbers — which
        // is exactly what it should do. De-duplicated by kind: three
        // notifications of the same thing is one finding.
        var penalties = readings.map { 100 - $0.normality }
        penalties += Set(events.map(\.kind)).map(\.severity)
        penalties.sort(by: >)
        guard let worst = penalties.first else { return nil }
        let rest = penalties.dropFirst().reduce(0) { $0 + $1 * $1 }
        let raw = worst + 0.35 * rest.squareRoot()
        let cap = 100 * (0.6 + 0.4 * coverage)
        return Swift.max(0, Swift.min(100 - raw, cap))
    }

    static func describe(_ reading: Reading) -> String {
        let spec = specs.first { $0.metric == reading.metric }
        let formatted = String(format: spec?.format ?? "%.1f", reading.value)
        let unit = reading.metric.unit
        var text = "\(reading.metric.displayName): \(formatted)\(unit.isEmpty ? "" : " \(unit)")"
        if let baseline = reading.baseline {
            text += String(format: " (baseline %@)", String(format: spec?.format ?? "%.1f", baseline))
        }
        return "\(text) — \(reading.note)"
    }

    static func describe(_ stale: StaleReading, now: Date) -> String {
        let days = Swift.max(1, Int(now.timeIntervalSince(stale.lastMeasured) / day))
        return "\(stale.metric.displayName): last measured \(days) day\(days == 1 ? "" : "s") ago"
    }
}

/// `InsightModel` adapter — a Today card.

extension String {
    var capitalizedFirst: String {
        guard let first else { return self }
        return first.uppercased() + dropFirst()
    }
}
