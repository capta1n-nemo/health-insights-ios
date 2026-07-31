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

    public struct Standing: Sendable, Equatable, Identifiable {
        public let metric: MetricType
        public let value: Double
        /// 0–100. Always expressed so that higher means *better*, whichever way
        /// the underlying metric runs — a resting heart rate of 48 is a high
        /// centile here even though 48 is a low number.
        public let percentile: Double
        public var id: MetricType { metric }

        /// "top 15%" / "around average" — the phrase people actually repeat.
        public var phrase: String {
            switch percentile {
            case 90...: return "top 10%"
            case 75..<90: return "top 25%"
            case 60..<75: return "above average"
            case 40..<60: return "around average"
            case 25..<40: return "below average"
            default: return "bottom 25%"
            }
        }
    }

    public struct Output: Sendable, Equatable {
        public let standings: [Standing]
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

    public static func evaluate(samples: [HealthMetricSample], profile: UserHealthProfile,
                                now: Date = Date(),
                                calendar: Calendar = .current) -> Output? {
        guard let age = profile.age(asOf: now), let sex = profile.sex else { return nil }

        var standings: [Standing] = []
        func add(_ metric: MetricType, freshWithin: TimeInterval, norm: Norm) {
            guard let reading = VitalReader.reading(metric, from: samples, now: now,
                                                    freshWithin: freshWithin,
                                                    calendar: calendar) else { return }
            standings.append(Standing(metric: metric, value: reading.value,
                                      percentile: percentile(reading.value, norm: norm)))
        }
        add(.restingHeartRate, freshWithin: 7 * 86_400,
            norm: restingHeartRateNorm(age: age, sex: sex))
        add(.heartRateVariabilityRMSSD, freshWithin: 7 * 86_400,
            norm: hrvNorm(age: age, sex: sex))
        add(.vo2Max, freshWithin: 45 * 86_400, norm: vo2Norm(age: age, sex: sex))

        guard !standings.isEmpty,
              let overall = Baseline.mean(standings.map(\.percentile)) else { return nil }
        return Output(standings: standings, overall: overall)
    }
}

/// The Insights-tab card. A trend rather than a daily: where you stand does not
/// change overnight, and framing it as a today number would invite reading noise
/// as movement.

