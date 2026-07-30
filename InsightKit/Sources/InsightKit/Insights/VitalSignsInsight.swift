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
        /// 0–100, or nil when nothing was fresh enough to score.
        public let score: Double?
        /// Fraction of the vitals this user normally records that were
        /// measured in time. What makes a perfect score hard.
        public let coverage: Double

        public var unusual: [Reading] { readings.filter { $0.status == .unusual } }
        public var watch: [Reading] { readings.filter { $0.status == .watch } }
        public var unknown: [Reading] { readings.filter { $0.status == .insufficientHistory } }

        public var headline: String {
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
        Spec(metric: .bodyTemperature, concernWhenHigh: true, concernWhenLow: true,
             hardLow: 35.5, hardHigh: 37.8, hardTolerance: 1.5, relativeFloor: nil,
             freshWithin: 1.5 * day, format: "%.1f"),
        // No absolute bound is defensible — rMSSD spans roughly 15–150 ms with
        // age, fitness and device — but a fall to 60% of the long-run median is
        // a real signal a rolling z-score cannot see.
        Spec(metric: .heartRateVariabilityRMSSD, concernWhenHigh: false, concernWhenLow: true,
             hardLow: nil, hardHigh: nil, hardTolerance: 1, relativeFloor: 0.6,
             freshWithin: 1.5 * day, format: "%.0f")
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

    public static func evaluate(samples: [HealthMetricSample],
                                now: Date = Date(),
                                calendar: Calendar = .current) -> Output {
        var readings: [Reading] = []
        var stale: [StaleReading] = []

        for spec in specs {
            // One line per device, de-duplicated: the same ring arriving
            // directly and through Apple Health is one instrument, and counting
            // it twice was inflating the variance it is measured against.
            let breakdown = MultiSource.breakdown(spec.metric, from: samples)
            guard !breakdown.sources.isEmpty else { continue }

            var candidates: [(reading: Reading, historyCount: Int)] = []
            var mostRecent: (value: Double, date: Date)?

            for series in breakdown.sources {
                // The day's representative value — the mean of the day's
                // readings for a continuously-sampled vital, the median for a
                // metric that says so. This is what the old comment claimed and
                // the old code did not do; it took the newest raw sample, so one
                // high minute during a run was reported as the day's heart rate.
                let daily = series.bucketed(by: .day, for: spec.metric, calendar: calendar)
                guard let today = daily.last else { continue }

                if mostRecent == nil || today.date > mostRecent!.date {
                    mostRecent = (today.value, today.date)
                }

                guard now.timeIntervalSince(today.date) <= spec.freshWithin else { continue }

                let cutoff = today.date.addingTimeInterval(-Double(baselineDays) * day)
                let history = daily.dropLast().filter { $0.date >= cutoff }.map(\.value)

                candidates.append((
                    reading(spec: spec, value: today.value, at: today.date,
                            history: history, source: series.displayName),
                    history.count))
            }

            if let best = primary(from: candidates) {
                readings.append(best)
            } else if let mostRecent,
                      now.timeIntervalSince(mostRecent.date) <= expectedWindow {
                // Recorded by this user, just not lately. Counted against
                // coverage rather than silently reported as fine.
                stale.append(StaleReading(metric: spec.metric, value: mostRecent.value,
                                          lastMeasured: mostRecent.date))
            }
        }

        let expected = readings.count + stale.count
        let coverage = expected == 0 ? 0 : Double(readings.count) / Double(expected)
        return Output(readings: readings, stale: stale,
                      score: score(readings: readings, coverage: coverage),
                      coverage: coverage)
    }

    /// Which device's verdict to report when several measured the same vital.
    ///
    /// The one with the most baseline history: its standard deviation is the
    /// best-established, so its z is the most trustworthy. Pooling them instead
    /// — which is what happened before — let the gap between two miscalibrated
    /// instruments set the variance, and nothing ever cleared the threshold.
    static func primary(from candidates: [(reading: Reading, historyCount: Int)]) -> Reading? {
        candidates.max { a, b in
            a.historyCount == b.historyCount
                ? a.reading.measuredAt < b.reading.measuredAt
                : a.historyCount < b.historyCount
        }?.reading
    }

    static func reading(spec: Spec, value: Double, at date: Date,
                        history: [Double], source: String) -> Reading {
        let deviation = history.count >= minimumBaselineDays
            ? Baseline.deviation(latest: value, history: history)
            : nil
        let z = deviation?.zScore

        var status = Reading.Status.normal
        var note = "in your normal range"

        if let z {
            let magnitude = abs(z)
            let high = z > 0
            let concerning = (high && spec.concernWhenHigh) || (!high && spec.concernWhenLow)
            if magnitude >= unusualZ {
                status = concerning ? .unusual : .watch
                note = high ? "well above your baseline" : "well below your baseline"
            } else if magnitude >= watchZ {
                // Only say "a little above your baseline" when the status
                // actually reflects it. The old version overwrote the note even
                // when it kept `.normal`, so a card could read "All normal" and
                // "a little above your baseline" in the same breath.
                if concerning {
                    status = .watch
                    note = high ? "a little above your baseline" : "a little below your baseline"
                }
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
            normality = Swift.min(normality, boundNormality(distance: hardLow - value, spec: spec))
        }
        if let hardHigh = spec.hardHigh, value > hardHigh {
            status = .unusual
            note = "above the usual healthy range"
            normality = Swift.min(normality, boundNormality(distance: value - hardHigh, spec: spec))
        }

        // The relative floor, for metrics whose baseline can drift downward
        // with the very decline being looked for.
        if let fraction = spec.relativeFloor,
           let median = Baseline.quantile(0.5, of: history),
           median > 0, value < median * fraction {
            status = .unusual
            note = "well below your usual level"
            normality = Swift.min(normality, 25)
        }

        // A reading we cannot judge is not a clean one. Held at a middling
        // figure so it neither rewards nor punishes.
        if status == .insufficientHistory { normality = 70 }

        return Reading(metric: spec.metric, value: value, baseline: deviation?.baseline,
                       zScore: z, status: status, note: note, normality: normality,
                       measuredAt: date, sourceName: source)
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
    static func boundNormality(distance: Double, spec: Spec) -> Double {
        guard spec.hardTolerance > 0 else { return 0 }
        let severity = Swift.min(1, Swift.max(0, distance / spec.hardTolerance))
        return 35 * (1 - severity)
    }

    /// The overall figure.
    ///
    /// Worst-offender-dominant, because this insight reports outliers rather
    /// than averaging them away — but the remaining signals still move it, so a
    /// day where everything is slightly off no longer ties with a pristine one.
    /// Then capped by coverage, which is what makes 100 hard: it requires
    /// everything this person normally records to have been measured *and* to
    /// sit on its baseline.
    static func score(readings: [Reading], coverage: Double) -> Double? {
        guard !readings.isEmpty else { return nil }
        let penalties = readings.map { 100 - $0.normality }.sorted(by: >)
        let worst = penalties[0]
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
public struct VitalSignsInsight: InsightModel {
    public let id: InsightID = .vitalSigns
    public let title = "Vitals Check"
    public init() {}
    public var requirements: [GroundingRequirement] { [] }
    /// Straight off the scan table, so a new `Spec` is a new chart line.
    public var candidateMetrics: [MetricType] { VitalSignsCheck.specs.map(\.metric) }

    public func evaluate(samples: [HealthMetricSample], profile: UserHealthProfile, now: Date) -> InsightResult {
        let output = VitalSignsCheck.evaluate(samples: samples, now: now)
        guard let score = output.score, !output.readings.isEmpty else {
            return InsightResult(
                id: id, title: title, primaryValue: nil,
                headline: output.stale.isEmpty ? "No data yet" : "Nothing measured lately",
                score: nil, confidence: .low,
                explanation: output.stale.isEmpty
                    ? "Connect a wearable or Apple Health to have your vitals checked against your own baseline each day."
                    : "Your vitals haven't reported recently enough to describe today. Sync your wearable to see this again.",
                drivers: output.stale.map { VitalSignsCheck.describe($0, now: now) },
                unmetRequirements: [])
        }

        let flagged = output.unusual + output.watch
        var explanation: String
        if flagged.isEmpty {
            explanation = "\(output.readings.count) vital\(output.readings.count == 1 ? "" : "s") measured recently, all sitting in your normal range."
        } else {
            let names = flagged.map { $0.metric.displayName.lowercased() }
            explanation = "\(listPhrase(names).capitalizedFirst) \(flagged.count == 1 ? "is" : "are") away from your usual pattern. Everything else is normal."
        }
        if !output.stale.isEmpty {
            // Said out loud rather than quietly counted as fine, which is what
            // let a months-old reading buy a perfect score before.
            let names = output.stale.map { $0.metric.displayName.lowercased() }
            explanation += " \(listPhrase(names).capitalizedFirst) \(output.stale.count == 1 ? "hasn't" : "haven't") reported lately, so today's check is partial."
        }

        // Confidence follows coverage, not a bare count of rows — a stale
        // reading used to be able to buy "high".
        let confidence: InsightConfidence
        if output.coverage >= 0.85 && output.readings.count >= 4 {
            confidence = .high
        } else if output.coverage >= 0.5 {
            confidence = .moderate
        } else {
            confidence = .low
        }

        return InsightResult(
            id: id, title: title, primaryValue: Double(output.readings.count),
            headline: output.headline, score: score, confidence: confidence,
            explanation: explanation,
            // Flagged vitals first — the point of a vitals panel is the outlier.
            drivers: (flagged + output.readings.filter { $0.status != .unusual && $0.status != .watch })
                .map(VitalSignsCheck.describe)
                + output.stale.map { VitalSignsCheck.describe($0, now: now) },
            unmetRequirements: [],
            // Weight 0 throughout: this insight deliberately doesn't average its
            // vitals, so claiming a share of the score would be inventing one.
            contributors: output.readings.map { reading in
                let spec = VitalSignsCheck.specs.first { $0.metric == reading.metric }
                let unit = reading.metric.unit
                return MetricContribution(
                    metric: reading.metric,
                    higherIsBetter: spec?.higherIsBetter,
                    weight: 0,
                    detail: String(format: spec?.format ?? "%.1f", reading.value)
                        + (unit.isEmpty ? "" : " \(unit)"))
            })
    }

    private func listPhrase(_ items: [String]) -> String {
        switch items.count {
        case 0: return ""
        case 1: return items[0]
        case 2: return "\(items[0]) and \(items[1])"
        default: return items.dropLast().joined(separator: ", ") + " and " + items[items.count - 1]
        }
    }
}

extension String {
    var capitalizedFirst: String {
        guard let first else { return self }
        return first.uppercased() + dropFirst()
    }
}
