import Foundation

/// How much you have left in the tank, right now, and where it went.
///
/// This is the single most-loved number in consumer wearables — Garmin's Body
/// Battery — and it exists nowhere on iOS. Every other app on this phone reports
/// *recovery this morning* and then goes quiet until tomorrow, which is a strange
/// thing to do with a wrist sensor that keeps measuring all day. The question
/// people actually ask at 3pm is "have I got another session in me, or am I done",
/// and nothing answers it.
///
/// ## The model, stated plainly
///
/// Energy is a reservoir. Sleep fills it, exertion empties it, and rest refills
/// it slowly through the day:
///
/// - **Overnight charge** from how much sleep you got against your own need, and
///   how well your autonomic system recovered while you had it (HRV against your
///   own baseline).
/// - **Drain** from work done — active energy — plus time spent with your heart
///   rate meaningfully above resting, which is what catches the strain that isn't
///   a logged workout: a stressful meeting, a hot commute, a hangover.
/// - **Trickle recharge** during genuinely quiet stretches, because a calm hour
///   really does give some back.
///
/// **It is a model, not a measurement**, and the card says so. What makes it
/// honest is that every coefficient below is expressed in units the user can
/// check against their own day, and the drivers name where the energy went.
public enum EnergyModel {

    /// A reading of the reservoir at one instant.
    public struct Point: Sendable, Equatable, Identifiable {
        public let date: Date
        /// 0–100.
        public let level: Double
        /// What had been spent by this point, before any trickle back.
        public let drained: Double
        public var id: Date { date }
    }

    public struct Output: Sendable, Equatable {
        /// Where the reservoir stood when the day started.
        public let morningCharge: Double
        /// Now.
        public let level: Double
        /// The day's curve, hourly, oldest first.
        public let curve: [Point]
        /// Total spent since waking.
        public let spent: Double
        /// Sleep hours behind the morning charge.
        public let sleepHours: Double?
        /// Overnight HRV against baseline, in SDs. Positive is better recovery.
        public let recoveryZ: Double?
        /// Active energy burned so far today, kcal.
        public let activeEnergy: Double?
        /// Hours spent with heart rate meaningfully above resting.
        public let exertionHours: Double?

        /// The word for a level.
        public var band: String {
            switch level {
            case 70...: return "High"
            case 45..<70: return "Steady"
            case 25..<45: return "Running low"
            default: return "Drained"
            }
        }
    }

    // MARK: - Coefficients, each in units you can check

    /// Sleep that fills the reservoir completely, when recovery is ordinary.
    public static let fullChargeSleepHours = 8.0
    /// The floor a night of no sleep at all leaves you on. Not zero: a person
    /// who has not slept still gets out of bed.
    public static let minimumMorningCharge = 25.0
    /// How much a full standard deviation of overnight HRV moves the charge,
    /// in points. Recovery quality is a real modifier, and a smaller one than
    /// duration — you cannot recover your way out of four hours.
    public static let recoveryPointsPerSD = 8.0

    /// Active kilocalories that drain the whole reservoir on their own. A hard
    /// day for most people is 600–900 kcal of *active* burn.
    public static let fullDrainActiveKilocalories = 1_100.0
    /// Hours above resting that would drain it on their own. Eight hours of
    /// elevated heart rate is a day that has taken everything.
    public static let fullDrainExertionHours = 8.0
    /// bpm above the resting baseline before a sample counts as exertion.
    /// Below this is ordinary life — standing up, making coffee.
    public static let exertionThresholdBpm = 15.0
    /// Points given back per quiet hour. A calm afternoon returns something, and
    /// far less than sleep does.
    public static let trickleRechargePerHour = 2.5

    // MARK: - Evaluation

    public static func evaluate(samples: [HealthMetricSample],
                                now: Date = Date(),
                                calendar: Calendar = .current) -> Output? {
        let sleep = VitalReader.reading(.sleepDurationHours, from: samples, now: now,
                                        freshWithin: 36 * 3600, calendar: calendar)
        let hrv = VitalReader.reading(.heartRateVariabilityRMSSD, from: samples, now: now,
                                      calendar: calendar)
            ?? VitalReader.reading(.heartRateVariabilitySDNN, from: samples, now: now,
                                   calendar: calendar)
        let resting = VitalReader.reading(.restingHeartRate, from: samples, now: now,
                                          calendar: calendar)

        // Without a night behind it there is no reservoir to report.
        guard let sleep, sleep.isFresh else { return nil }

        let morning = morningCharge(sleepHours: sleep.value, recoveryZ: hrv?.zScore)
        let dayStart = calendar.startOfDay(for: now)

        let energyToday = samples.samples(of: .activeEnergyBurned)
            .filter { $0.start >= dayStart && $0.start <= now }
        let activeEnergy = energyToday.isEmpty ? nil : energyToday.map(\.value).reduce(0, +)

        let exertion = exertionHours(samples: samples, restingBaseline: resting?.baseline
                                        ?? resting?.value,
                                     since: dayStart, until: now)

        let curve = curve(samples: samples, morningCharge: morning,
                          restingBaseline: resting?.baseline ?? resting?.value,
                          dayStart: dayStart, now: now, calendar: calendar)
        let level = curve.last?.level ?? morning

        return Output(morningCharge: morning, level: level, curve: curve,
                      spent: Swift.max(0, morning - level),
                      sleepHours: sleep.value, recoveryZ: hrv?.zScore,
                      activeEnergy: activeEnergy, exertionHours: exertion)
    }

    /// What sleep and overnight recovery left you starting on.
    ///
    /// Duration leads and recovery modifies, in that order and by that much: you
    /// cannot recover your way out of four hours, and eight good hours after a
    /// hard week still start you lower than eight easy ones.
    public static func morningCharge(sleepHours: Double, recoveryZ: Double?) -> Double {
        let fromSleep = minimumMorningCharge
            + (100 - minimumMorningCharge)
            * Swift.min(1, Swift.max(0, sleepHours / fullChargeSleepHours))
        let fromRecovery = (recoveryZ ?? 0) * recoveryPointsPerSD
        return Swift.max(0, Swift.min(100, fromSleep + fromRecovery))
    }

    /// Hours since `since` with heart rate meaningfully above the resting
    /// baseline.
    ///
    /// This is what catches the strain that never became a workout — a bad
    /// commute, a stressful hour, the day after a heavy night. It is also why
    /// this needs a watch: at roughly 300 samples a day, each one stands for a
    /// few minutes of elapsed time.
    static func exertionHours(samples: [HealthMetricSample], restingBaseline: Double?,
                              since: Date, until: Date) -> Double? {
        guard let restingBaseline else { return nil }
        let heartRate = samples.samples(of: .heartRate)
            .filter { $0.start >= since && $0.start <= until }
        guard heartRate.count >= 4 else { return nil }
        let elapsed = until.timeIntervalSince(since)
        let above = heartRate.filter { $0.value >= restingBaseline + exertionThresholdBpm }
        // Each sample stands for an equal share of the elapsed window. Crude,
        // and honest about it: irregular sampling would need the intervals, and
        // a watch's own sampling gaps are not idle time.
        return elapsed / 3600 * Double(above.count) / Double(heartRate.count)
    }

    /// The day's curve, one point an hour.
    static func curve(samples: [HealthMetricSample], morningCharge: Double,
                      restingBaseline: Double?, dayStart: Date, now: Date,
                      calendar: Calendar) -> [Point] {
        let hours = Swift.max(1, Int(now.timeIntervalSince(dayStart) / 3600))
        var out: [Point] = []
        var level = morningCharge
        var previousDrain = 0.0
        for hour in 1...hours {
            let mark = Swift.min(now, dayStart.addingTimeInterval(Double(hour) * 3600))
            let spent = drain(samples: samples, restingBaseline: restingBaseline,
                              since: dayStart, until: mark)
            let thisHour = Swift.max(0, spent - previousDrain)
            previousDrain = spent
            // A quiet hour gives a little back; a busy one takes.
            level += thisHour > 0.5 ? -thisHour : trickleRechargePerHour
            level = Swift.max(0, Swift.min(100, level))
            out.append(Point(date: mark, level: level, drained: spent))
        }
        return out
    }

    /// Points spent between two instants, from work done and time spent above
    /// resting. The two are added rather than maxed: a long walk and a hard hour
    /// are different costs and both are real.
    static func drain(samples: [HealthMetricSample], restingBaseline: Double?,
                      since: Date, until: Date) -> Double {
        let energy = samples.samples(of: .activeEnergyBurned)
            .filter { $0.start >= since && $0.start <= until }
            .map(\.value).reduce(0, +)
        let fromEnergy = energy / fullDrainActiveKilocalories * 100
        let fromExertion = (exertionHours(samples: samples, restingBaseline: restingBaseline,
                                          since: since, until: until) ?? 0)
            / fullDrainExertionHours * 100
        return Swift.min(100, fromEnergy + fromExertion)
    }
}

/// The Today card.
public struct EnergyInsight: InsightModel {
    public let id: InsightID = .energy
    public let title = "Energy"
    public init() {}

    public var requirements: [GroundingRequirement] { [] }
    public var candidateMetrics: [MetricType] {
        [.sleepDurationHours, .heartRateVariabilityRMSSD, .heartRateVariabilitySDNN,
         .restingHeartRate, .activeEnergyBurned, .heartRate]
    }

    public func evaluate(samples: [HealthMetricSample], profile: UserHealthProfile,
                         now: Date) -> InsightResult {
        guard let output = EnergyModel.evaluate(samples: samples, now: now) else {
            return InsightResult(
                id: id, title: title, primaryValue: nil, headline: "No night yet",
                score: nil, confidence: .low,
                explanation: "Energy is charged by sleep and spent through the day. Record a night with Apple Health or a wearable and this starts tracking what you have left.",
                drivers: [], unmetRequirements: [])
        }

        var drivers: [InsightDriver] = []
        if let hours = output.sleepHours {
            drivers.append(.component(String(format: "Charged to %.0f overnight from %.1f h of sleep",
                                             output.morningCharge, hours),
                                      score: output.morningCharge))
        }
        if let z = output.recoveryZ, abs(z) >= 0.5 {
            drivers.append(InsightDriver(
                text: String(format: "Overnight recovery %@ your usual — %@%.0f points on the morning charge",
                             z > 0 ? "better than" : "worse than",
                             z > 0 ? "+" : "−",
                             abs(z * EnergyModel.recoveryPointsPerSD)),
                isNotable: z < 0))
        }
        if let kcal = output.activeEnergy, kcal > 0 {
            drivers.append(.routine(String(format: "%.0f kcal of active work today", kcal)))
        }
        if let hours = output.exertionHours, hours >= 0.25 {
            drivers.append(InsightDriver(
                text: String(format: "%.1f h with your heart rate above resting", hours),
                // Time above resting is the finding when it is most of the day.
                isNotable: hours >= 4))
        }
        if output.spent >= 1 {
            drivers.append(.routine(String(format: "%.0f points spent since you woke", output.spent)))
        }

        let explanation: String
        switch output.level {
        case 70...:
            explanation = "You have \(Int(output.level.rounded())) left in the tank — a good window for something hard if you want one."
        case 45..<70:
            explanation = "\(Int(output.level.rounded())) left. Enough for an ordinary day; a hard session would take most of the rest."
        case 25..<45:
            explanation = "\(Int(output.level.rounded())) left. You have been spending faster than you charged."
        default:
            explanation = "\(Int(output.level.rounded())) left. Whatever you charged overnight has mostly gone."
        }

        // Only signals that actually reported become contributions.
        var contributors: [MetricContribution] = []
        if let hours = output.sleepHours {
            contributors.append(.init(metric: .sleepDurationHours, higherIsBetter: true,
                                      weight: 0.6, detail: String(format: "%.1f h", hours)))
        }
        if let kcal = output.activeEnergy {
            contributors.append(.init(metric: .activeEnergyBurned, higherIsBetter: nil,
                                      weight: 0.25, detail: String(format: "%.0f kcal", kcal)))
        }
        if output.recoveryZ != nil {
            contributors.append(.init(metric: .heartRateVariabilityRMSSD, higherIsBetter: true,
                                      weight: 0.15, detail: "overnight recovery"))
        }

        return InsightResult(
            id: id, title: title, primaryValue: output.level,
            headline: "\(Int(output.level.rounded())) · \(output.band)",
            score: output.level,
            // A model, not a measurement, and it should never claim otherwise.
            confidence: output.exertionHours == nil ? .low : .moderate,
            explanation: explanation,
            driverLines: drivers.filter { $0.isNotable == true }
                + drivers.filter { $0.isNotable != true },
            unmetRequirements: [], contributors: contributors)
    }
}
