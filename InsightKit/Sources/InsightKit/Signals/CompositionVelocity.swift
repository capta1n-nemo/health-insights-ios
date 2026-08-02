import Foundation

/// How fast the body's mass is moving, and what the moving mass is made of.
///
/// Body Composition scored a **level** and nothing else: a reader twelve
/// kilograms down over three months scored exactly the same as one who had
/// never moved, because body fat percentage on the day was the whole number.
/// For anyone actually changing — which is most people who open this card —
/// the rate and the quality of the change are the subject, and neither was
/// anywhere on it.
///
/// Two numbers carry that, and they are deliberately separate:
///
/// - **rate** — how fast, as a share of body weight per week, judged against
///   published guidance (0.5–1.0 %/week for loss) and against the reader's own
///   stated goal.
/// - **quality** — how much of the change was lean tissue. Under good
///   conditions lean is 20–30% of what is lost; well above that is the
///   difference between losing fat and losing yourself.
///
/// In InsightKit because every line is arithmetic that can be quietly wrong,
/// and the app target has no test target.
public struct CompositionVelocity: Sendable, Equatable {

    public let windowDays: Int
    /// Fitted slope of the smoothed weight series, kg per week. Negative is loss.
    public let kilogramsPerWeek: Double
    /// The same slope as a share of current body weight — the scale the
    /// published bands are defined on, and the only one that compares readers.
    public let percentPerWeek: Double
    /// Fitted slope of lean mass, kg per week. `nil` without a scale reporting it.
    public let leanKilogramsPerWeek: Double?
    /// Of the mass that moved, the share that was lean tissue.
    ///
    /// `nil` when the weight is not meaningfully moving — a ratio whose
    /// denominator is noise is not a finding, it is a division by almost zero.
    public let leanShareOfChange: Double?
    /// Typical distance of a real weigh-in from the fitted line, in kg. Quoted
    /// with the slope wherever the slope is, exactly as `VO2Trajectory` and
    /// `ScoreTrend` already do — a slope alone reads as a promise.
    public let residualSD: Double
    public let weighIns: Int
    public let latestWeight: Double

    /// Whether the weight is moving enough to describe at all.
    public var isMoving: Bool { abs(percentPerWeek) >= CompositionVelocityModel.stableBandPercent }
}

public enum CompositionVelocityModel {

    /// EWMA smoothing factor for the weight series.
    ///
    /// A scale carries one to two kilograms of water swing day to day — the
    /// same swing the sodium and carbohydrate literature attributes to
    /// glycogen and fluid rather than tissue — so an unsmoothed slope through
    /// daily weigh-ins reports mostly hydration. 0.10 is the conventional
    /// choice for daily body-weight smoothing and is what the outside analysis
    /// of the user's export recommended independently.
    public static let smoothing = 0.10

    /// Below this many weigh-ins in the window there is no line worth fitting.
    public static let minimumWeighIns = 6

    /// Eight weeks: long enough that a fortnight's water retention cannot set
    /// the slope, short enough to still be describing now.
    public static let defaultWindowDays = 56

    /// Inside this weekly percentage the weight is called steady rather than
    /// moving — and `leanShareOfChange` stays `nil`, because its denominator
    /// would be noise.
    public static let stableBandPercent = 0.1

    /// The upper end of published loss guidance. Above it, lean loss climbs.
    public static let safeLossPercentPerWeek = 1.0

    /// Lean tissue is 20–30% of what is lost under good conditions (adequate
    /// protein, resistance training). This is the top of that range: above it,
    /// the loss is taking more of you than it should.
    public static let leanShareConcern = 0.30

    // MARK: - Building

    public static func evaluate(samples: [HealthMetricSample],
                                windowDays: Int = defaultWindowDays,
                                now: Date = Date(),
                                calendar: Calendar = .current) -> CompositionVelocity? {
        let weights = dailySeries(.bodyMass, samples: samples, windowDays: windowDays,
                                  now: now, calendar: calendar)
        guard weights.count >= minimumWeighIns, let latest = weights.last?.value,
              latest > 0,
              let weightFit = fit(weights) else { return nil }

        let lean = dailySeries(.leanBodyMass, samples: samples, windowDays: windowDays,
                               now: now, calendar: calendar)
        let leanFit = lean.count >= minimumWeighIns ? fit(lean) : nil

        let kgPerWeek = weightFit.slopePerDay * 7
        let percentPerWeek = kgPerWeek / latest * 100
        let leanPerWeek = leanFit.map { $0.slopePerDay * 7 }

        // Only where the weight is genuinely moving: dividing a lean slope by a
        // weight slope that is indistinguishable from zero manufactures a
        // number between −∞ and +∞ out of noise.
        var leanShare: Double?
        if abs(percentPerWeek) >= stableBandPercent, let leanPerWeek, kgPerWeek != 0 {
            leanShare = leanPerWeek / kgPerWeek
        }

        return CompositionVelocity(
            windowDays: windowDays,
            kilogramsPerWeek: kgPerWeek,
            percentPerWeek: percentPerWeek,
            leanKilogramsPerWeek: leanPerWeek,
            leanShareOfChange: leanShare,
            residualSD: weightFit.residualSD,
            weighIns: weights.count,
            latestWeight: latest)
    }

    /// One value per day, oldest first, EWMA-smoothed.
    static func dailySeries(_ metric: MetricType, samples: [HealthMetricSample],
                            windowDays: Int, now: Date,
                            calendar: Calendar) -> [(date: Date, value: Double)] {
        let daily = VitalReader.dailySeries(metric, from: samples, days: windowDays,
                                            now: now, calendar: calendar)
        guard let first = daily.first else { return [] }
        var smoothed: [(date: Date, value: Double)] = []
        var running = first.value
        for point in daily {
            running = smoothing * point.value + (1 - smoothing) * running
            smoothed.append((point.date, running))
        }
        return smoothed
    }

    /// Least squares through (days, value), with the scatter it was fitted
    /// through. `nil` when every point shares one day and the slope is
    /// undefined.
    static func fit(_ points: [(date: Date, value: Double)]) -> (slopePerDay: Double, residualSD: Double)? {
        guard points.count >= 2, let first = points.first?.date else { return nil }
        let xs = points.map { $0.date.timeIntervalSince(first) / 86_400 }
        let ys = points.map(\.value)
        let n = Double(points.count)
        let meanX = xs.reduce(0, +) / n
        let meanY = ys.reduce(0, +) / n
        let sxx = xs.reduce(0) { $0 + ($1 - meanX) * ($1 - meanX) }
        guard sxx > 0 else { return nil }
        let sxy = zip(xs, ys).reduce(0) { $0 + ($1.0 - meanX) * ($1.1 - meanY) }
        let slope = sxy / sxx
        let intercept = meanY - slope * meanX
        let residuals = zip(xs, ys).map { $1 - (intercept + slope * $0) }
        let variance = residuals.reduce(0) { $0 + $1 * $1 } / n
        return (slope, variance.squareRoot())
    }

    // MARK: - Scoring

    /// 0–100 for how the rate of change compares with what the reader is
    /// trying to do.
    ///
    /// **With no goal set this scores safety alone**, and that is the whole
    /// reason the goal is not defaulted: −0.8 %/week is excellent progress or
    /// an unexplained wasting, and nothing the phone can sense tells them
    /// apart. Absent a stated intention the card judges only what is
    /// defensible without one — that a change inside conventional guidance is
    /// unremarkable in either direction, and that a very fast one is worth
    /// flagging whether or not it was wanted.
    public static func rateScore(percentPerWeek: Double, goal: WeightGoal?) -> Double {
        guard let goal else {
            let magnitude = abs(percentPerWeek)
            guard magnitude > safeLossPercentPerWeek else { return 100 }
            return clamp(100 * exp(-0.5 * pow((magnitude - safeLossPercentPerWeek) / 0.5, 2)))
        }
        let ideal = goal.idealPercentPerWeek
        let distance = percentPerWeek - ideal
        // Three different things can be wrong with a rate, and they are not
        // equally wrong:
        //
        // - **short of the ideal, right direction** — disappointing, and the
        //   most forgiving curve, because it is where most real weeks sit;
        // - **past the ideal** — where the harm is, since fast loss is what
        //   costs lean tissue, so the curve tightens;
        // - **the opposite direction entirely** — not slow progress but the
        //   wrong way, and on a goal of gaining it may be unintended loss,
        //   which is a finding rather than a shortfall.
        //
        // Maintenance has no "beyond" and no wrong side, so it is symmetric —
        // but tighter than a shortfall, because any drift is off-goal.
        let spread: Double
        switch goal {
        case .maintain:
            spread = 0.7
        case .lose:
            spread = percentPerWeek > 0 ? 0.6 : (percentPerWeek < ideal ? 0.45 : 0.9)
        case .gain:
            spread = percentPerWeek < 0 ? 0.6 : (percentPerWeek > ideal ? 0.45 : 0.9)
        }
        return clamp(100 * exp(-0.5 * pow(distance / spread, 2)))
    }

    /// 0–100 for how much of the change was the tissue the reader wanted to
    /// move. `nil` when there is no change to divide, or no lean series.
    ///
    /// Losing: lean should be a *small* share of what goes. Gaining: lean
    /// should be a *large* share of what arrives. Same number, opposite
    /// readings, so the goal decides which.
    public static func qualityScore(leanShareOfChange share: Double?,
                                    isLosing: Bool) -> Double? {
        guard let share else { return nil }
        if isLosing {
            // Lean *gained* while weight fell is the best outcome there is.
            guard share > 0 else { return 100 }
            return clamp(100 - Swift.max(0, share - 0.20) * 200)
        }
        // Gaining: the share of the gain that is lean, straight through.
        guard share > 0 else { return 0 }
        return clamp(share * 200)
    }

    /// The sentence the card says about the rate.
    public static func phrase(_ velocity: CompositionVelocity, goal: WeightGoal?) -> String {
        guard velocity.isMoving else {
            return String(format: "Holding steady — %.1f kg/week over %d weigh-ins",
                          abs(velocity.kilogramsPerWeek), velocity.weighIns)
        }
        let direction = velocity.kilogramsPerWeek < 0 ? "down" : "up"
        let rate = String(format: "%@ %.2f kg a week (%.2f%% of body weight)",
                          direction, abs(velocity.kilogramsPerWeek),
                          abs(velocity.percentPerWeek))
        guard let goal else { return rate }
        switch goal {
        case .lose where velocity.kilogramsPerWeek < 0,
             .gain where velocity.kilogramsPerWeek > 0:
            return abs(velocity.percentPerWeek) > safeLossPercentPerWeek
                ? rate + " — faster than the 0.5–1% a week that protects lean tissue"
                : rate + " — inside the 0.5–1% a week guidance"
        case .maintain:
            return rate + " — against a goal of holding steady"
        default:
            return rate + " — away from your stated goal"
        }
    }

    static func clamp(_ x: Double) -> Double { Swift.max(0, Swift.min(100, x)) }
}
