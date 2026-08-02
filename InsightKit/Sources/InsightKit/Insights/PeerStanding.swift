import Foundation

/// Where your numbers sit against other people your age and sex.
///
/// Every app in this category tells you how you compare against *yourself*, which
/// is the right default and is also why nobody ever learns whether their numbers
/// are actually any good. "Your HRV is 48" means nothing to a person who has
/// never seen anyone else's. "Your HRV is around the 70th centile for men in
/// their forties" is the sentence people screenshot and send to their friends.
///
/// ## Honesty constraints this has to meet
///
/// - **Only metrics with published, age- and sex-stratified norms.** Three
///   qualify. Everything else in the catalogue either has no usable population
///   distribution or one so device-dependent that a centile would be fiction.
/// - **Centiles are approximate and the copy says so.** These are normal
///   approximations to published summary statistics, not lookups into a real
///   distribution — the sources publish means and spreads, not full curves.
/// - **A centile is not a verdict.** Being at the 30th centile for resting heart
///   rate is not a diagnosis of anything, and the wording never implies it is.
public enum PeerStandingModel {

    /// A published age/sex reference: the mean and standard deviation of the
    /// population distribution, and which direction is the healthier one.
    struct Norm {
        let mean: Double
        let sd: Double
        let higherIsBetter: Bool
    }

    /// The stretch of the distribution a centile falls in, and the words for it.
    ///
    /// Extracted from `Standing.phrase`, which used to hold the edges 90 / 75 /
    /// 60 / 40 / 25 inline. A strip that *draws* these bands has to shade them
    /// at the same edges the sentence beside it is chosen by, and two copies of
    /// a threshold drift — the blood-pressure bands are the worked example
    /// (`Category.of` classifies, `systolicRange` shades, and `PressureBandTests`
    /// binds them). Same treatment here: the edges exist once, in `bounds`.
    public enum Band: String, Sendable, Equatable, CaseIterable {
        case top10, top25, aboveAverage, aroundAverage, belowAverage, bottom25

        /// Declared high to low, which is what lets `of(_:)` be a search rather
        /// than a second switch over the same numbers.
        public var bounds: Range<Double> {
            switch self {
            case .top10: return 90..<100
            case .top25: return 75..<90
            case .aboveAverage: return 60..<75
            case .aroundAverage: return 40..<60
            case .belowAverage: return 25..<40
            case .bottom25: return 0..<25
            }
        }

        /// "top 10%" / "around average" — the phrase people actually repeat.
        public var phrase: String {
            switch self {
            case .top10: return "top 10%"
            case .top25: return "top 25%"
            case .aboveAverage: return "above average"
            case .aroundAverage: return "around average"
            case .belowAverage: return "below average"
            case .bottom25: return "bottom 25%"
            }
        }

        /// The middle of the distribution — the one band a strip marks, so a
        /// reader can see what "ordinary" looks like without reading six labels.
        public var isTypical: Bool { self == .aroundAverage }

        public static func of(_ percentile: Double) -> Band {
            allCases.first { percentile >= $0.bounds.lowerBound } ?? .bottom25
        }
    }

    public struct Standing: Sendable, Equatable, Identifiable {
        public let metric: MetricType
        public let value: Double
        /// 0–100. Always expressed so that higher means *better*, whichever way
        /// the underlying metric runs — a resting heart rate of 48 is a high
        /// centile here even though 48 is a low number.
        public let percentile: Double
        /// What the row shows for the value, when the compared quantity is not
        /// the raw reading. Lean body mass is placed by its **fat-free mass
        /// index** (mass ÷ height²), because raw kilograms cannot be compared
        /// across people of different heights — so the centile is height-adjusted
        /// and the row has to say the number it was actually placed on, in the
        /// units it was placed in, rather than the raw kilograms the formatter
        /// would print. `nil` for the metrics compared directly.
        public let displayLabel: String?

        public var id: MetricType { metric }

        public init(metric: MetricType, value: Double, percentile: Double,
                    displayLabel: String? = nil) {
            self.metric = metric
            self.value = value
            self.percentile = percentile
            self.displayLabel = displayLabel
        }

        public var band: Band { Band.of(percentile) }

        /// "top 10%" / "around average" — the phrase people actually repeat.
        public var phrase: String { band.phrase }
    }

    public struct Output: Sendable, Equatable {
        public let standings: [Standing]
        /// Metrics this card reads that **no published norm covers**.
        ///
        /// Carried rather than dropped. "How you compare" renders on every card
        /// now, and a card whose signals are mostly unnormed would otherwise
        /// show two rows and imply the rest had been checked and found
        /// unremarkable. Naming them is also the honest place to say that the
        /// gap is in the literature, not in the reader's data — see
        /// `docs/progress.md` ▸ "Crowd-sourced norms".
        public var unNormed: [MetricType] = []
        /// Metrics this card reads that **are** assessed against a reference —
        /// just not as a centile. Blood pressure is the case: it is classified
        /// into ACC/AHA stages, and a systolic centile beside a stage would be
        /// two answers to one question. Kept apart from `unNormed` so the card
        /// stops implying "nobody has published a distribution" for a reading it
        /// is, in fact, judging elsewhere — the miscategorisation the user found
        /// on the Blood Pressure card.
        public var assessedByCategory: [MetricType] = []
        /// The mean centile across what could be measured.
        public let overall: Double
        public var best: Standing? { standings.max { $0.percentile < $1.percentile } }
    }

    // MARK: - The published norms

    /// Resting heart rate.
    ///
    /// Population distributions cluster tightly around the high sixties with a
    /// spread of roughly 10 bpm, drifting slightly with age. Lower is better
    /// across the healthy range.
    static func restingHeartRateNorm(age: Double, sex: BiologicalSex) -> Norm {
        let mean: Double
        switch (sex, age) {
        case (.male, ..<40):   mean = 68
        case (.male, 40..<60): mean = 67
        case (.male, _):       mean = 66
        case (.female, ..<40): mean = 72
        case (.female, 40..<60): mean = 71
        case (.female, _):     mean = 70
        }
        return Norm(mean: mean, sd: 10, higherIsBetter: false)
    }

    /// rMSSD heart-rate variability.
    ///
    /// Falls steeply and predictably with age — roughly halving between the
    /// twenties and the sixties — and the population spread is wide. Figures
    /// follow the Nunan et al. (2010) normative review, which is the standard
    /// reference for short-recording rMSSD.
    static func hrvNorm(age: Double, sex: BiologicalSex) -> Norm {
        // Approximately exponential decline with age, anchored near 42 ms at 40.
        let mean = Swift.max(15, 60 * exp(-0.022 * Swift.max(20, age - 20)))
        // Women run marginally higher rMSSD at the same age.
        let adjusted = sex == .female ? mean * 1.06 : mean
        return Norm(mean: adjusted, sd: adjusted * 0.42, higherIsBetter: true)
    }

    /// VO₂max — reuses the norm line `FitnessAgeModel` inverts, so this card can
    /// never disagree with Cardio Fitness about what average looks like.
    static func vo2Norm(age: Double, sex: BiologicalSex) -> Norm {
        let mean = FitnessAgeModel.referenceVO2(age: age, sex: sex)
        return Norm(mean: mean, sd: mean * 0.18, higherIsBetter: true)
    }

    /// Body fat percentage.
    ///
    /// Anchored on the **same Gallagher et al. (2000) healthy band the dial is
    /// already scored against** (`BodyCompositionInsight.healthyBodyFatRange`),
    /// so this card cannot disagree with its own score about what a healthy
    /// body fat is — the identical argument `vo2Norm` makes for reusing
    /// `FitnessAgeModel.referenceVO2`.
    ///
    /// The band is the healthy *range*, not the population's *middle*, and the
    /// two are different things: population body fat sits above the healthy
    /// band in every published Western survey. The mean is placed a little
    /// above the band's top edge for that reason, which is what makes a reader
    /// inside the healthy range land well up the distribution rather than at
    /// the fiftieth centile. The spread is wide because the population's is.
    static func bodyFatNorm(age: Double, sex: BiologicalSex) -> Norm {
        let band = BodyCompositionInsight.healthyBodyFatRange(age: age, sex: sex)
        return Norm(mean: band.upper + 4, sd: 7, higherIsBetter: false)
    }

    /// Fat-free mass index — lean mass placed against other people of the same
    /// age and sex, per height.
    ///
    /// Raw lean kilograms cannot be compared across people: a tall person
    /// carries more of everything. FFMI (fat-free mass ÷ height², kg/m²) is the
    /// height-normalised form, and it has a **BIA-measured** age/sex reference —
    /// Kyle et al. (2003), 5 635 healthy Swiss adults on 50 kHz impedance,
    /// cross-validated to DXA. That the reference was measured the same way the
    /// reader's scale measures it is the point: a DXA-derived norm placed against
    /// a BIA reading would carry a method bias the centile could not see.
    ///
    /// Anchored on the paper's young-adult medians — men 18.9, women 15.4 — with
    /// the shallow published age course (roughly flat through midlife, easing
    /// after 60 as fat-free mass falls). Higher is better across the healthy
    /// range, the same orientation VO₂max carries; the wide SD comes from the
    /// paper's own normal-BMI spread.
    static func fatFreeMassIndexNorm(age: Double, sex: BiologicalSex) -> Norm {
        let mean: Double
        switch (sex, age) {
        case (.male, ..<40):     mean = 19.0
        case (.male, 40..<60):   mean = 19.2
        case (.male, _):         mean = 18.4
        case (.female, ..<40):   mean = 15.4
        case (.female, 40..<60): mean = 15.8
        case (.female, _):       mean = 15.2
        }
        return Norm(mean: mean, sd: sex == .male ? 1.7 : 1.5, higherIsBetter: true)
    }

    /// Metrics judged against a reference that isn't a centile.
    ///
    /// Blood pressure is classified into ACC/AHA stages by `BloodPressure`
    /// `Category.of`, which is a stronger statement than a percentile and the
    /// reason a systolic centile is deliberately not drawn. These belong in
    /// `assessedByCategory`, not `unNormed`: the reading *is* placed against a
    /// published reference, just not this section's kind.
    static let categoryAssessed: Set<MetricType> = [.bloodPressureSystolic,
                                                    .bloodPressureDiastolic]

    /// Metrics that have no population distribution and never could — a value
    /// this app **modelled** rather than measured. There is no "other people's
    /// active medication level"; listing it as "no published norm yet" would
    /// imply one might arrive, which is false. Excluded from the comparison
    /// entirely rather than parked in a bucket.
    public static func isModelled(_ metric: MetricType) -> Bool {
        metric == .activeMedicationLevel
    }

    /// The normal-approximation centile of `value` under `norm`, oriented so
    /// higher always means better.
    static func percentile(_ value: Double, norm: Norm) -> Double {
        let z = (value - norm.mean) / norm.sd
        let oriented = norm.higherIsBetter ? z : -z
        return Swift.max(1, Swift.min(99, 100 * normalCDF(oriented)))
    }

    /// Abramowitz & Stegun 7.1.26 — plenty accurate for a centile rounded to a
    /// whole number, and it avoids `erf`, which is Darwin-only in Foundation.
    static func normalCDF(_ z: Double) -> Double {
        let t = 1 / (1 + 0.2316419 * abs(z))
        let d = 0.3989422804014327 * exp(-z * z / 2)
        let p = d * t * (0.319381530 + t * (-0.356563782 + t * (1.781477937
                + t * (-1.821255978 + t * 1.330274429))))
        return z >= 0 ? 1 - p : p
    }

    /// The published norm for a metric, or `nil` where there isn't one.
    ///
    /// **Four metrics, and that is the whole list.** Every other signal this
    /// app reads is either not distributed in a way a normal approximation
    /// describes — blood oxygen sits against a ceiling at 100% and is nothing
    /// like Gaussian — or has no age-and-sex population summary published at
    /// all, which is true of every wearable-native signal: heart rate recovery,
    /// day strain, walking heart rate.
    ///
    /// Returning `nil` rather than guessing is the load-bearing part. A centile
    /// built on an invented mean and spread is indistinguishable on screen from
    /// one built on NHANES, and this section's entire claim is that the number
    /// beside your reading came from a published distribution.
    ///
    /// Blood pressure is deliberately absent even though norms exist: it is
    /// *classified* into ACC/AHA bands rather than ranked, and drawing a
    /// systolic centile beside a category would be two answers to one question.
    static func norm(for metric: MetricType, age: Double,
                     sex: BiologicalSex) -> Norm? {
        switch metric {
        case .restingHeartRate: return restingHeartRateNorm(age: age, sex: sex)
        case .heartRateVariabilityRMSSD: return hrvNorm(age: age, sex: sex)
        case .vo2Max: return vo2Norm(age: age, sex: sex)
        case .bodyFatPercentage: return bodyFatNorm(age: age, sex: sex)
        default: return nil
        }
    }

    /// Whether any published distribution covers this metric. The public half
    /// of `norm(for:age:sex:)`, for a caller that needs the answer without
    /// needing the numbers — the roadmap note and the tests both do.
    public static func hasPublishedNorm(_ metric: MetricType) -> Bool {
        norm(for: metric, age: 40, sex: .male) != nil
    }

    /// How long a reading may be before it is too stale to place against a
    /// population. VO₂max updates every few weeks by design; a resting heart
    /// rate from last month is a fact about last month.
    static func freshness(for metric: MetricType) -> TimeInterval {
        switch metric {
        case .vo2Max: return 45 * 86_400
        // Most people weigh in every few days rather than daily, and body
        // composition does not move fast enough for a fortnight-old reading to
        // be describing someone else.
        case .bodyFatPercentage: return 14 * 86_400
        default: return 7 * 86_400
        }
    }

    /// Where the metrics **this card reads** sit against other people.
    ///
    /// Takes the card's own inputs rather than a fixed list, because "How you
    /// compare" is on every card now and the three heart signals are not what
    /// the Sleep card is about.
    public static func evaluate(metrics: [MetricType],
                                samples: [HealthMetricSample],
                                profile: UserHealthProfile,
                                now: Date = Date(),
                                calendar: Calendar = .current) -> Output? {
        guard let age = profile.age(asOf: now), let sex = profile.sex else { return nil }

        var standings: [Standing] = []
        var unNormed: [MetricType] = []
        var assessedByCategory: [MetricType] = []
        let heightMetres = samples.latestValue(.height)
        // De-duplicated in the card's own order, so the rows read in the same
        // order as every other list on the screen.
        var seen: Set<MetricType> = []
        for metric in metrics where seen.insert(metric).inserted {
            // A value the app worked out, not one it measured, has no population
            // to compare against. Dropped entirely rather than listed.
            if isModelled(metric) { continue }
            // Judged, but by category rather than centile — its own bucket.
            if categoryAssessed.contains(metric) {
                assessedByCategory.append(metric)
                continue
            }
            // Lean mass is placed by FFMI, which needs a height; without one it
            // is genuinely uncomparable, so it falls to the unnormed list.
            if metric == .leanBodyMass {
                guard let height = heightMetres, height > 0.5,
                      let reading = VitalReader.reading(metric, from: samples, now: now,
                                                        freshWithin: freshness(for: metric),
                                                        calendar: calendar) else {
                    unNormed.append(metric)
                    continue
                }
                let ffmi = reading.value / (height * height)
                let norm = fatFreeMassIndexNorm(age: age, sex: sex)
                standings.append(Standing(
                    metric: metric, value: ffmi,
                    percentile: percentile(ffmi, norm: norm),
                    displayLabel: String(format: "%.1f kg/m² (FFMI)", ffmi)))
                continue
            }
            guard let norm = norm(for: metric, age: age, sex: sex) else {
                unNormed.append(metric)
                continue
            }
            guard let reading = VitalReader.reading(metric, from: samples, now: now,
                                                    freshWithin: freshness(for: metric),
                                                    calendar: calendar) else { continue }
            standings.append(Standing(metric: metric, value: reading.value,
                                      percentile: percentile(reading.value, norm: norm)))
        }

        // An overall of nothing is not zero. A card with only unnormed signals
        // still renders — that is the point of carrying them — but it has no
        // average centile and must not print one.
        guard !standings.isEmpty || !unNormed.isEmpty || !assessedByCategory.isEmpty else {
            return nil
        }
        return Output(standings: standings, unNormed: unNormed,
                      assessedByCategory: assessedByCategory,
                      overall: Baseline.mean(standings.map(\.percentile)) ?? 0)
    }

    /// The three heart signals, for callers that predate per-card metrics.
    public static func evaluate(samples: [HealthMetricSample], profile: UserHealthProfile,
                                now: Date = Date(),
                                calendar: Calendar = .current) -> Output? {
        evaluate(metrics: [.restingHeartRate, .heartRateVariabilityRMSSD, .vo2Max],
                 samples: samples, profile: profile, now: now, calendar: calendar)
    }
}

/// The Insights-tab card. A trend rather than a daily: where you stand does not
/// change overnight, and framing it as a today number would invite reading noise
/// as movement.

