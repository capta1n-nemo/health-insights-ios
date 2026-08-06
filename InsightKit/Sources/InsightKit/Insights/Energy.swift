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
        /// Which HRV flavour the recovery modifier came from, so the card charts
        /// and weights the series the model actually read rather than guessing
        /// at rMSSD. `nil` when there was no overnight HRV at all.
        public let hrvMetric: MetricType?

        /// The word for a level.
        public var band: String {
            switch level {
            case 70...: return "High"
            case 45..<70: return "Steady"
            case 25..<45: return "Running low"
            default: return "Drained"
            }
        }

        /// What each input did to the reservoir, in points.
        ///
        /// Here rather than in the card for the reason every share in this app
        /// is computed beside the number it explains: the coefficients are
        /// twenty lines up, and a card working these out for itself would be a
        /// second copy of them, free to drift the moment one is retuned.
        ///
        /// Signed — sleep and overnight recovery fill the reservoir, work and
        /// time above resting drain it — and the card weights by magnitude,
        /// because "how much of this number is heart rate" is a question about
        /// size, not direction.
        ///
        /// Resting heart rate is deliberately **not** a term. It sets the line
        /// above which a sample counts as exertion; it is what the drain is
        /// measured against rather than something moving the level, the same
        /// standing height has on Body Composition.
        public var terms: [Term] {
            var out: [Term] = []
            if let sleepHours {
                out.append(Term(
                    metric: .sleepDurationHours, higherIsBetter: true,
                    points: (100 - minimumMorningCharge)
                        * Swift.min(1, Swift.max(0, sleepHours / fullChargeSleepHours)),
                    detail: String(format: "%.1f h", sleepHours)))
            }
            if let recoveryZ, let hrvMetric {
                out.append(Term(
                    metric: hrvMetric, higherIsBetter: true,
                    points: recoveryZ * recoveryPointsPerSD,
                    detail: String(format: "%@%.1f SD overnight",
                                   recoveryZ >= 0 ? "+" : "−", abs(recoveryZ))))
            }
            if let activeEnergy {
                out.append(Term(
                    metric: .activeEnergyBurned, higherIsBetter: nil,
                    points: -activeEnergy / fullDrainActiveKilocalories * 100,
                    detail: String(format: "%.0f kcal", activeEnergy)))
            }
            if let exertionHours {
                out.append(Term(
                    metric: .heartRate, higherIsBetter: nil,
                    points: -exertionHours / fullDrainExertionHours * 100,
                    detail: String(format: "%.1f h above resting", exertionHours)))
            }
            return out
        }
    }

    /// One input's effect on the reservoir, in points.
    public struct Term: Sendable, Equatable {
        public let metric: MetricType
        public let higherIsBetter: Bool?
        /// Positive fills, negative drains.
        public let points: Double
        public let detail: String
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
        let rmssd = VitalReader.reading(.heartRateVariabilityRMSSD, from: samples, now: now,
                                        calendar: calendar)
        let hrv = rmssd
            ?? VitalReader.reading(.heartRateVariabilitySDNN, from: samples, now: now,
                                   calendar: calendar)
        let hrvMetric: MetricType? = hrv == nil ? nil
            : (rmssd == nil ? .heartRateVariabilitySDNN : .heartRateVariabilityRMSSD)
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
                      activeEnergy: activeEnergy, exertionHours: exertion,
                      hrvMetric: hrv?.zScore == nil ? nil : hrvMetric)
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

    // MARK: - The overnight half, over history

    /// What each of the last `days` mornings started on.
    ///
    /// Only the overnight half of the model — the drain side needs an intraday
    /// replay per day and answers a different question. This is the one the app
    /// can ask across months: *were my mornings starting well*, which is sleep
    /// length and overnight recovery together and is therefore not the same
    /// series as sleep duration.
    ///
    /// Recovery is scored against the whole run's own spread rather than a
    /// trailing baseline. The question here is a contrast *within* the run —
    /// which weeks started better than which — and a trailing baseline gives
    /// every day a different, drifting zero, which is precisely what makes two
    /// weeks incomparable. Same reasoning as `SeriesNormalizer`.
    public static func morningChargeSeries(samples: [HealthMetricSample],
                                           days: Int = 90,
                                           now: Date = Date(),
                                           calendar: Calendar = .current) -> [VitalReader.DailyValue] {
        let sleep = VitalReader.dailySeries(.sleepDurationHours, from: samples, days: days,
                                            now: now, calendar: calendar)
        guard !sleep.isEmpty else { return [] }

        let hrv = hrvSeries(samples: samples, days: days, now: now, calendar: calendar)
        let history = hrv.map(\.value)
        let mean = Baseline.mean(history)
        let spread = Baseline.standardDeviation(history)
        var recoveryByDay: [Date: Double] = [:]
        if let mean, let spread, spread > 0 {
            for day in hrv { recoveryByDay[day.date] = (day.value - mean) / spread }
        }

        return sleep.map { night in
            VitalReader.DailyValue(
                date: night.date,
                value: morningCharge(sleepHours: night.value,
                                     recoveryZ: recoveryByDay[night.date]))
        }
    }

    /// Whichever HRV metric this person actually records, preferring the one
    /// with more nights. Mixing them would put two differently-scaled
    /// quantities into one standard deviation.
    static func hrvSeries(samples: [HealthMetricSample], days: Int, now: Date,
                          calendar: Calendar) -> [VitalReader.DailyValue] {
        let rmssd = VitalReader.dailySeries(.heartRateVariabilityRMSSD, from: samples,
                                            days: days, now: now, calendar: calendar)
        let sdnn = VitalReader.dailySeries(.heartRateVariabilitySDNN, from: samples,
                                           days: days, now: now, calendar: calendar)
        return rmssd.count >= sdnn.count ? rmssd : sdnn
    }

    /// This week's mornings against the best week in the series.
    public struct WeekContrast: Sendable, Equatable {
        public let recent: Double
        public let best: Double
        public let recentNights: Int
        public let bestNights: Int
        public var shortfall: Double { Swift.max(0, best - recent) }
    }

    /// How many nights a week needs before it may be compared. Below this a
    /// single unusually good night *is* the week.
    public static let minimumNightsPerWeek = 3

    /// The recent week against the best other week in the run.
    ///
    /// The best week deliberately excludes the recent one, so a good week can
    /// never be reported as falling short of itself.
    public static func weekContrast(_ series: [VitalReader.DailyValue],
                                    now: Date = Date()) -> WeekContrast? {
        let weekStart = now.addingTimeInterval(-7 * 86_400)
        let recentDays = series.filter { $0.date >= weekStart }
        guard recentDays.count >= minimumNightsPerWeek,
              let recent = Baseline.mean(recentDays.map(\.value)) else { return nil }

        let earlier = series.filter { $0.date < weekStart }
        var best: (mean: Double, nights: Int)?
        // Every seven-day window that ended before this week started. Sliding
        // rather than calendar-aligned: a person's good stretch does not begin
        // on a Monday.
        for (index, anchor) in earlier.enumerated() {
            let window = earlier[index...].prefix {
                $0.date.timeIntervalSince(anchor.date) < 7 * 86_400
            }
            guard window.count >= minimumNightsPerWeek,
                  let mean = Baseline.mean(window.map(\.value)) else { continue }
            if best == nil || mean > best!.mean { best = (mean, window.count) }
        }
        guard let best else { return nil }
        return WeekContrast(recent: recent, best: best.mean,
                            recentNights: recentDays.count, bestNights: best.nights)
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
            level += hourlyChange(thisHour)
            level = Swift.max(0, Swift.min(100, level))
            out.append(Point(date: mark, level: level, drained: spent))
        }
        return out
    }

    /// The drain at which an hour is fully an *active* hour and stops earning
    /// any of the trickle recharge.
    ///
    /// One point of drain — about eleven kilocalories of work, or five minutes
    /// above resting. Below it an hour is partly rest and gets partly rewarded.
    static let restfulHourCeiling = 1.0

    /// What one hour does to the reservoir, as a continuous function of what it
    /// cost.
    ///
    /// **It used to be `thisHour > 0.5 ? -thisHour : trickleRechargePerHour`**,
    /// which is a three-point discontinuity at half a point of drain: the hour
    /// either handed back 2.5 or took 0.5, with nothing in between. Half a point
    /// is only about five and a half kilocalories, or two and a half minutes
    /// above resting, so an ordinary light-activity hour sits right on it — and
    /// `curve` runs one of these per hour since midnight, so a day of marginal
    /// hours compounds the step a dozen times into the number on the card.
    ///
    /// Now the recharge fades out as the drain fades in, meeting where the hour
    /// stops being restful. The two ends are unchanged: an idle hour still
    /// returns the full trickle, and a genuinely active hour still costs exactly
    /// what it cost.
    static func hourlyChange(_ thisHour: Double) -> Double {
        let activity = Swift.min(1, Swift.max(0, thisHour / restfulHourCeiling))
        return trickleRechargePerHour * (1 - activity) - thisHour * activity
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
            // The model only declines when there is no fresh night to charge
            // from — and a user with months of nights whose wearable hasn't
            // synced this morning is not a user who has never recorded one.
            // "Record a night" to the first reads as data loss, and hiding the
            // card is how Today lost its daily cards every morning until the
            // sync landed.
            // Recency-bounded: a source that stopped recording months ago is
            // not "waiting for last night", and the card must not sit on Today
            // forever promising a sync that isn't coming.
            let nights = samples.samples(of: .sleepDurationHours)
            if let latest = nights.map(\.start).max(),
               Int(now.timeIntervalSince(latest) / 86_400) <= 3 {
                let days = max(1, Int(now.timeIntervalSince(latest) / 86_400))
                let age = days == 1 ? "yesterday" : "\(days) days ago"
                return InsightResult(
                    id: id, title: title, primaryValue: nil,
                    headline: "Waiting for last night",
                    score: nil, confidence: .low,
                    explanation: "Energy starts the day charged by the night behind it, and your newest recorded night is from \(age) — last night hasn't synced yet. This fills in on its own once your wearable catches up; pull to refresh to ask again.",
                    drivers: [], unmetRequirements: [],
                    isAwaitingTodaysData: true)
            }
            // "No night yet" was a statement of the gap rather than an ask, and
            // it was also wrong for the second case below: a reader whose ring
            // stopped syncing a fortnight ago has plenty of nights, just none
            // recent enough. Two states, two sentences.
            return invitingInput(
                id, title,
                action: nights.isEmpty ? "Connect a sleep source" : "Record a night",
                message: nights.isEmpty
                    ? "Energy is charged by sleep and spent through the day. Connect Apple Health or a wearable and record a night, and this starts tracking what you have left."
                    : "Energy is charged by the night behind it, and your most recent night is more than a few days old. Record a night and this picks up again.")
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

        // What each input did to the reservoir, weighted by how much it moved it.
        //
        // These weights were 0.6 / 0.25 / 0.15 — three numbers written here by
        // hand that appear nowhere in the model, so a card claiming to show
        // "the share each signal has of the score" was showing three constants
        // instead. They also left the drain half's *other* term unrepresented:
        // time above resting is a full peer of active energy in `EnergyModel`
        // and reaches the reader as a driver line, and heart rate charted on no
        // card in the app despite being the signal behind it.
        //
        // `Output.terms` is the model's own arithmetic; the share is each term's
        // magnitude over the total. Magnitude, because "how much of this number
        // is time above resting" is a question about size — a drain and a charge
        // both move the level, and signing the denominator would let a hard day
        // cancel a good night and hand the remainder a share above 100%.
        let terms = output.terms
        let totalEffect = terms.reduce(0) { $0 + abs($1.points) }
        let primary = terms.map {
            ScoreBlend.Term(metric: $0.metric, higherIsBetter: $0.higherIsBetter,
                            score: output.level,
                            weight: totalEffect > 0 ? abs($0.points) / totalEffect : 0,
                            detail: $0.detail,
                            // `score` above is the whole reservoir level, fed in
                            // only because the blend needs *something* to weight
                            // — its blended score is discarded (see below). It
                            // is not this term's own 0–100; no term of a
                            // simulated reservoir has one, and before this flag
                            // every row reached the decomposition claiming to
                            // have scored exactly what the card did.
                            scoreIsOwn: false)
        }
        // Resting heart rate is the *line* exertion is counted above, and heart
        // rate lands here whenever the day is too thin to count exertion from —
        // `EnergyModel.exertionHours` needs four samples since midnight, so
        // every card opened before the watch has synced a few is in this state.
        //
        // Both carry a share against the reader's own baseline rather than
        // sitting at weight 0. A resting rate above your normal really does mean
        // less in the tank, which is the model's own premise, and the card was
        // drawing "5.2 h above resting" with the line it was counted above
        // contributing nothing to the number.
        let alreadyScored = Set(terms.map(\.metric))
        let supporting: [ScoreBlend.Term] = [MetricType.restingHeartRate, .heartRate]
            .filter { !alreadyScored.contains($0) }
            .compactMap { metric in
                VitalReader.reading(metric, from: samples, now: now).flatMap {
                    ScoreBlend.supporting($0, higherIsBetter: false)
                }
            }
        // The blend's own score is not used: Energy's number is a reservoir
        // level the model simulated hour by hour, not an average of its terms,
        // and replacing it with one would throw away the trickle recharge and
        // the clamping. Only the *weights* come from here — which is what the
        // section claims to be showing.
        let contributors = ScoreBlend.blend(primary: primary, supporting: supporting)?
            .contributions ?? []

        return InsightResult(
            id: id, title: title, primaryValue: output.level,
            headline: "\(Int(output.level.rounded())) · \(output.band)",
            score: output.level,
            // A model, not a measurement, and it should never claim otherwise.
            confidence: output.exertionHours == nil ? .low : .moderate,
            explanation: explanation,
            driverLines: drivers.filter { $0.isNotable == true }
                + drivers.filter { $0.isNotable != true },
            unmetRequirements: [], contributors: contributors,
            weighting: .weightedAverage)
    }
}
