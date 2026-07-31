import Foundation

/// Where cardio fitness is *heading*, and what has actually moved it for this
/// person before.
///
/// `CardioFitnessInsight` answers "is my VO₂max good for my age?". This answers
/// the more useful question: VO₂max falls with age on its own, so a flat line is
/// already a win and a rising one is unusual. The trajectory is compared against
/// the age-typical drift from the same norm line `FitnessAgeModel` inverts, so
/// "improving" means improving relative to what ageing does anyway.
public enum VO2Trajectory {

    /// Below this there is no trajectory, only noise. VO₂max arrives roughly
    /// weekly from a watch, so six weeks is the earliest a slope means anything.
    public static let minimumReadings = 4
    public static let minimumSpanDays: Double = 42
    /// A slope fitted to readings that stopped six months ago describes a fitness
    /// level the person may no longer have. Past this, there is history but no
    /// current trajectory, and saying so is more useful than extrapolating.
    public static let staleAfter: TimeInterval = 180 * 86_400

    /// How the trajectory reads once age-related drift is accounted for.
    public enum Direction: String, Sendable, Equatable {
        case improving, holding, declining

        public var label: String {
            switch self {
            case .improving: return "Improving"
            case .holding: return "Holding"
            case .declining: return "Declining"
            }
        }
    }

    /// A contrast drawn from the user's own weeks: what their VO₂max averaged in
    /// their busier weeks versus their lighter ones.
    ///
    /// Descriptive, and deliberately not a causal claim — busier weeks and higher
    /// fitness travel together for plenty of reasons. It is still the most
    /// personal answer available to "what would move this?".
    public struct VolumeContrast: Sendable, Equatable {
        public let metric: MetricType
        public let medianWeekly: Double
        public let vo2WhenBusier: Double
        public let vo2WhenLighter: Double
        public let weeksCompared: Int

        public init(metric: MetricType, medianWeekly: Double, vo2WhenBusier: Double,
                    vo2WhenLighter: Double, weeksCompared: Int) {
            self.metric = metric
            self.medianWeekly = medianWeekly
            self.vo2WhenBusier = vo2WhenBusier
            self.vo2WhenLighter = vo2WhenLighter
            self.weeksCompared = weeksCompared
        }

        public var difference: Double { vo2WhenBusier - vo2WhenLighter }
    }

    /// One thing that could move the number, either observed in this person's own
    /// history (`isPersonal`) or established exercise-physiology evidence.
    public struct Lever: Sendable, Equatable {
        public let title: String
        public let detail: String
        public let isPersonal: Bool

        public init(title: String, detail: String, isPersonal: Bool) {
            self.title = title
            self.detail = detail
            self.isPersonal = isPersonal
        }
    }

    public struct Output: Sendable, Equatable {
        public let latest: Double
        /// EWMA of the series — what the projection starts from, so one odd
        /// reading on the final day cannot swing the forecast.
        public let smoothed: Double
        /// Least-squares change per year across the whole window.
        public let perYear: Double
        /// What ageing alone would do at this age and sex (negative).
        public let ageTypicalPerYear: Double
        /// `perYear − ageTypicalPerYear`: the part that is not just getting older.
        public let netPerYear: Double
        public let projectedIn12Months: Double
        /// Residual spread around the fitted line — the honest ± on the forecast.
        public let residualSD: Double
        public let readings: Int
        public let spanDays: Double
        public let fitnessAgeNow: Double
        public let fitnessAgeIn12Months: Double
        public let volume: VolumeContrast?
        /// Filled in after the rest of the output exists, since the levers are
        /// chosen from the trajectory itself.
        public var levers: [Lever]

        public init(latest: Double, smoothed: Double, perYear: Double,
                    ageTypicalPerYear: Double, netPerYear: Double,
                    projectedIn12Months: Double, residualSD: Double,
                    readings: Int, spanDays: Double, fitnessAgeNow: Double,
                    fitnessAgeIn12Months: Double, volume: VolumeContrast?,
                    levers: [Lever]) {
            self.latest = latest
            self.smoothed = smoothed
            self.perYear = perYear
            self.ageTypicalPerYear = ageTypicalPerYear
            self.netPerYear = netPerYear
            self.projectedIn12Months = projectedIn12Months
            self.residualSD = residualSD
            self.readings = readings
            self.spanDays = spanDays
            self.fitnessAgeNow = fitnessAgeNow
            self.fitnessAgeIn12Months = fitnessAgeIn12Months
            self.volume = volume
            self.levers = levers
        }

        public var direction: Direction {
            if perYear >= 0.5 { return .improving }
            if perYear <= -0.5 { return .declining }
            return .holding
        }

        /// Fitness-age years gained (positive) or lost over the next 12 months if
        /// the current trajectory holds.
        ///
        /// This is the trajectory's effect alone: a flat VO₂max leaves your fitness
        /// age where it is, so this is zero. The gain *relative to ageing* is
        /// `netPerYear`, not this — the two answer different questions and adding
        /// them together would double-count.
        public var fitnessYearsGained: Double { fitnessAgeNow - fitnessAgeIn12Months }
    }

    /// The age-related change in the reference VO₂max per year — the slope of the
    /// same norm line `FitnessAgeModel` inverts, read at this age.
    public static func ageTypicalChangePerYear(age: Double, sex: BiologicalSex) -> Double {
        FitnessAgeModel.referenceVO2(age: age + 0.5, sex: sex)
            - FitnessAgeModel.referenceVO2(age: age - 0.5, sex: sex)
    }

    public static func evaluate(samples: [HealthMetricSample], age: Double,
                               sex: BiologicalSex, now: Date = Date(),
                               calendar: Calendar = .current) -> Output? {
        // One value per day, de-duplicated across devices, with the dates kept.
        //
        // De-duplication alone was not enough: the fit ran over *raw samples*, so
        // a day on which the watch published twice weighted that day twice, and
        // two devices reporting the same morning pulled the line toward whichever
        // read higher. `dailySeries` rather than `dailyValues` because the dates
        // are load-bearing — VO₂max arrives irregularly, and regressing an
        // unevenly-spaced series against 0, 1, 2, … answers a different question.
        let series = VitalReader.dailySeries(.vo2Max, from: samples, now: now,
                                             calendar: calendar)
        guard series.count >= minimumReadings,
              let first = series.first, let last = series.last else { return nil }

        let spanDays = last.date.timeIntervalSince(first.date) / 86_400
        guard spanDays >= minimumSpanDays,
              now.timeIntervalSince(last.date) <= staleAfter else { return nil }

        let years = series.map { $0.date.timeIntervalSince(first.date) / (365.2425 * 86_400) }
        let values = series.map(\.value)
        guard let fit = Baseline.linearRegression(x: years, y: values) else { return nil }

        let smoothed = Baseline.ewma(values) ?? last.value
        let ageTypical = ageTypicalChangePerYear(age: age, sex: sex)
        let projected = Swift.max(0, smoothed + fit.slope)

        var output = Output(
            latest: last.value,
            smoothed: smoothed,
            perYear: fit.slope,
            ageTypicalPerYear: ageTypical,
            netPerYear: fit.slope - ageTypical,
            projectedIn12Months: projected,
            residualSD: fit.residualSD,
            readings: series.count,
            spanDays: spanDays,
            fitnessAgeNow: FitnessAgeModel.evaluate(vo2: smoothed, sex: sex).fitnessAge,
            fitnessAgeIn12Months: FitnessAgeModel.evaluate(vo2: projected, sex: sex).fitnessAge,
            volume: volumeContrast(samples: samples, vo2: series, calendar: calendar),
            levers: [])
        output.levers = levers(for: output, samples: samples, now: now)
        return output
    }

    // MARK: - "What would move it"

    static func levers(for output: Output, samples: [HealthMetricSample],
                       now: Date) -> [Lever] {
        var out: [Lever] = []

        // 1. Their own busier-versus-lighter weeks, when the contrast is real.
        if let volume = output.volume, volume.difference >= 0.5 {
            out.append(Lever(
                title: "Your busier weeks look different",
                detail: String(format: "In weeks where your %@ was above %.0f %@, your cardio fitness averaged %.1f — against %.1f in your lighter weeks (%d weeks compared). That's your own history, not a rule.",
                               volume.metric.displayName.lowercased(), volume.medianWeekly,
                               volume.metric.unit, volume.vo2WhenBusier,
                               volume.vo2WhenLighter, volume.weeksCompared),
                isPersonal: true))
        }

        // 2. Resting HR drifting up is the earliest sign the trajectory is about
        //    to turn, and it is measured every night without being asked for.
        // Daily and de-duplicated, so a device reporting through two paths can't
        // weight its own mornings twice. Deliberately *not* freshness-gated: this
        // lever is "here is something that tends to move your trajectory", not a
        // claim about today, and a trajectory is read over months — requiring a
        // reading from the last 36 hours would delete the lever for anyone
        // reviewing a year of history.
        let restingHR = VitalReader.dailyValues(.restingHeartRate, from: samples,
                                                days: 365, now: now)
        if restingHR.count >= 8, let latest = restingHR.last,
           let deviation = Baseline.deviation(latest: latest, history: Array(restingHR.dropLast())),
           deviation.direction > 0 {
            out.append(Lever(
                title: "Resting heart rate is above your baseline",
                detail: String(format: "%.0f bpm against a baseline of %.0f. Resting heart rate and cardio fitness usually move in opposite directions, so bringing this back down tends to show up here too.",
                               latest, deviation.baseline),
                isPersonal: true))
        }

        // 3–4. General evidence, kept short and honest about what it applies to.
        if output.perYear < 1.0 {
            out.append(Lever(
                title: "Hard intervals move it fastest",
                detail: "Across training studies the largest VO₂max gains come from short, hard intervals — the most-studied protocol is 4 × 4 minutes at a hard effort with 3 easy minutes between, once or twice a week. Gains show up over 8–12 weeks, not days.",
                isPersonal: false))
        }
        out.append(Lever(
            title: "Easy volume is the floor",
            detail: "Most of the adaptation comes from total easy aerobic time rather than intensity alone — long, conversational sessions. Consistency over months is what holds a gain in place.",
            isPersonal: false))

        return out
    }

    // MARK: - Weekly pairing

    static func volumeContrast(samples: [HealthMetricSample], vo2: [VitalReader.DailyValue],
                               calendar: Calendar) -> VolumeContrast? {
        let weeklyVO2 = weeklyMean(vo2, calendar: calendar)
        // Active energy first: it counts effort, where steps only count walking.
        for metric in [MetricType.activeEnergyBurned, .stepCount] {
            let weekly = weeklyTotal(samples, metric: metric, calendar: calendar)
            if let found = contrast(vo2: weeklyVO2, volume: weekly, metric: metric) {
                return found
            }
        }
        return nil
    }

    static func contrast(vo2: [Date: Double], volume: [Date: Double],
                         metric: MetricType) -> VolumeContrast? {
        let paired: [(vo2: Double, volume: Double)] = vo2.compactMap {
            week, value -> (vo2: Double, volume: Double)? in
            guard let total = volume[week], total > 0 else { return nil }
            return (vo2: value, volume: total)
        }
        guard paired.count >= 6,
              let median = Baseline.quantile(0.5, of: paired.map { $0.volume }) else { return nil }
        let busier = paired.filter { $0.volume > median }.map { $0.vo2 }
        let lighter = paired.filter { $0.volume <= median }.map { $0.vo2 }
        guard busier.count >= 2, lighter.count >= 2,
              let high = Baseline.mean(busier), let low = Baseline.mean(lighter) else { return nil }
        return VolumeContrast(metric: metric, medianWeekly: median, vo2WhenBusier: high,
                              vo2WhenLighter: low, weeksCompared: paired.count)
    }

    /// Weekly totals for a metric that only means anything added up, taken from
    /// the single richest source. Summing across sources would double-count a
    /// step taken with a watch on the wrist and a phone in the pocket.
    static func weeklyTotal(_ samples: [HealthMetricSample], metric: MetricType,
                            calendar: Calendar) -> [Date: Double] {
        guard let dominant = MultiSource.breakdown(metric, from: samples).sources.first else {
            return [:]
        }
        var out: [Date: Double] = [:]
        for point in dominant.bucketed(by: .week, for: metric, calendar: calendar) {
            out[point.date] = point.value
        }
        return out
    }

    static func weeklyMean(_ values: [VitalReader.DailyValue], calendar: Calendar) -> [Date: Double] {
        var totals: [Date: (sum: Double, count: Int)] = [:]
        for value in values {
            let week = calendar.dateInterval(of: .weekOfYear, for: value.date)?.start
                ?? value.date
            let existing = totals[week] ?? (sum: 0, count: 0)
            totals[week] = (sum: existing.sum + value.value, count: existing.count + 1)
        }
        return totals.mapValues { $0.sum / Double($0.count) }
    }
}

// MARK: - Insight

/// `InsightModel` surface for the trajectory. Needs age and sex, because "is this
/// improving?" is only answerable against the age-typical decline.

