import Foundation

/// How fast the reader's metabolism is running, and whether the drug moved it.
///
/// The user's ask: *"I'm always wanting to know how fast my metabolism is at
/// the moment, and how it's sped up by Mounjaro or similar medications, and how
/// it's helping me lose weight — or making it harder."*
///
/// ## A rate is not a speed
///
/// "You burn 2,400 kcal a day" does not answer "is my metabolism fast". Fast is
/// a comparison, so the card's headline is a **ratio**: what the reader's own
/// energy balance says they burn, over what their size and movement predict.
///
/// - **Observed** is back-calculated — `meanIntake − kgPerDay × 7,700`. Summing
///   a wearable's basal and active estimates instead would inherit every
///   calibration error in it; the back-calculation needs only the food log and
///   the scale, and it self-corrects as both accumulate.
/// - **Predicted** is `BMR + measured active energy + the thermic effect of
///   food`. Katch-McArdle where lean mass is known, because this app *does*
///   know it from a Withings scale, and that is exactly the case where it beats
///   Mifflin-St Jeor; Mifflin otherwise. The activity term is measured rather
///   than a lifestyle multiplier chosen off a dropdown.
///
/// ## The gate is the whole card
///
/// **A back-calculation charges every logging error to metabolism.** A reader
/// under-reporting by 400 kcal a day gets a ratio saying their metabolism is
/// 20% faster than predicted — the most flattering possible reading of an
/// incomplete diary. So `NutritionLogging.completeEnough` is a gate, not a
/// caveat: below it the card says it cannot judge, and above 110% the card
/// names the food log *before* it says anything metabolic.
///
/// ## What it must never say
///
/// **Not "Mounjaro speeds up your metabolism."** GLP-1 receptor agonists act
/// principally by reducing intake; expenditure generally falls during weight
/// loss because a smaller body costs less to run. A ratio that rises during
/// treatment is more likely a food log that got worse as appetite fell. What
/// the card *can* say, and nothing else in the app can see, is observed against
/// predicted-for-your-current-size across the treatment period — which is what
/// "my metabolism has slowed" actually means.
public struct EnergyBalance: Sendable, Equatable {
    /// kcal/day, back-calculated from intake and the smoothed weight trend.
    public let observedTDEE: Double
    /// kcal/day predicted from body size, measured movement and the thermic
    /// effect of food. `nil` when neither BMR equation has its inputs.
    public let predictedTDEE: Double?
    /// `observedTDEE / predictedTDEE`. 1.0 is exactly what your size and
    /// movement predict.
    public let speed: Double?
    /// Which equation produced the resting term, for the row that reports it.
    public let basalMethod: String?
    public let basal: Double?
    public let intakeMean: Double
    public let activeMean: Double
    /// Positive when the reader is in deficit — burning more than they eat.
    public let deficitPerDay: Double
    public let kilogramsPerWeek: Double
    public let loggedDays: Int
    public let windowDays: Int

    public var completeness: Double { Double(loggedDays) / Double(windowDays) }
    /// Whether the food log is complete enough for any of this to mean
    /// anything.
    public var isJudgeable: Bool { completeness >= NutritionLogging.completeEnough }
    /// A ratio this far above prediction is more likely an incomplete diary
    /// than a fast metabolism, and the card says so first.
    public var underLoggingSuspected: Bool { (speed ?? 0) > EnergyBalanceModel.underLoggingRatio }
}

public enum EnergyBalanceModel {

    /// The conventional energy density of body mass. A whole-body average: fat
    /// is nearer 9,400 kcal/kg and lean nearer 1,800, and splitting the two by
    /// the reader's own composition is a refinement worth a few per cent — see
    /// `docs/planned-modules.md` ▸ module 5. Not first, because it matters only
    /// once the logging gate below is being met.
    public static let kcalPerKilogram = 7_700.0

    /// Four weeks. A fortnight is the floor — water weight swamps anything
    /// shorter — and four is where a fitted slope stops being mostly noise.
    public static let windowDays = 28
    public static let minimumLoggedDays = 14

    /// The thermic effect of food: about 10% of intake, the conventional mixed-
    /// diet figure the guidance itself assumes.
    public static let thermicEffectShare = 0.10

    /// Above this the card leads with the food log rather than with metabolism.
    public static let underLoggingRatio = 1.10

    /// Katch-McArdle. Uses lean mass, so it needs no age or sex — and it is the
    /// better instrument exactly when a scale reports body composition, which
    /// is the reader this app is built for.
    public static func katchMcArdleBMR(leanKilograms: Double) -> Double {
        370 + 21.6 * leanKilograms
    }

    /// Mifflin-St Jeor, the fallback when nothing reports lean mass.
    public static func mifflinStJeorBMR(kilograms: Double, centimetres: Double,
                                        age: Double, sex: BiologicalSex?) -> Double {
        let base = 10 * kilograms + 6.25 * centimetres - 5 * age
        // The published constant is +5 for men and −161 for women. With no sex
        // on file, split the difference rather than picking one: the error is
        // then bounded at ±83 kcal instead of landing 166 out for half of
        // readers, and the card names the equation it used.
        switch sex {
        case .male: return base + 5
        case .female: return base - 161
        case nil: return base - 78
        }
    }

    /// `nil` when the reader has not logged enough, or the scale has not
    /// reported enough for a trend.
    public static func evaluate(samples: [HealthMetricSample],
                                profile: UserHealthProfile,
                                now: Date = Date(),
                                calendar: Calendar = .current) -> EnergyBalance? {
        // The window is the reader's own logging stretch, not a fixed 28 days —
        // and both terms are taken over it, because an intake mean over one
        // period and a weight slope over another do not belong in the same
        // subtraction.
        guard let window = NutritionLogging.effectiveWindow(samples, days: windowDays,
                                                            now: now, calendar: calendar),
              window.days >= minimumLoggedDays,
              window.logged.count >= minimumLoggedDays else { return nil }
        let logged = window.logged
        guard let trend = weightTrend(samples, days: window.days,
                                      now: now, calendar: calendar) else { return nil }

        let intake = logged.reduce(0, +) / Double(logged.count)
        let kilogramsPerDay = trend.kilogramsPerDay
        // Energy balance: intake − expenditure is what the body stored. So the
        // expenditure is the intake minus what was stored — and storing a
        // negative number (losing) is what puts expenditure above intake.
        let observed = intake - kilogramsPerDay * kcalPerKilogram

        let active = VitalReader.dailyValues(.activeEnergyBurned, from: samples,
                                             days: window.days, now: now, calendar: calendar)
        let activeMean = active.isEmpty ? 0 : active.reduce(0, +) / Double(active.count)

        var basal: Double?
        var basalMethod: String?
        if let lean = samples.latestValue(.leanBodyMass) {
            basal = katchMcArdleBMR(leanKilograms: lean)
            basalMethod = "Katch-McArdle, from your lean mass"
        } else if let height = samples.latestValue(.height), height > 0,
                  let age = profile.age(asOf: now) {
            basal = mifflinStJeorBMR(kilograms: trend.latestWeight,
                                     centimetres: height * 100,
                                     age: age, sex: profile.sex)
            basalMethod = "Mifflin-St Jeor, from your height, weight and age"
        }
        let predicted = basal.map { $0 + activeMean + intake * thermicEffectShare }

        return EnergyBalance(
            observedTDEE: observed,
            predictedTDEE: predicted,
            speed: predicted.map { observed / $0 },
            basalMethod: basalMethod,
            basal: basal,
            intakeMean: intake,
            activeMean: activeMean,
            deficitPerDay: observed - intake,
            kilogramsPerWeek: trend.kilogramsPerDay * 7,
            loggedDays: logged.count,
            windowDays: window.days)
    }

    /// The weight slope, fitted to the **raw** daily weigh-ins.
    ///
    /// **Deliberately not `CompositionVelocity`, and this is the subtle part.**
    /// That model smooths with an EWMA before fitting, which is right for a
    /// *score* — it stops a card lurching on one salty dinner — and wrong here.
    /// An EWMA lags a real trend by about `(1 − α)/α` days, nine at α = 0.10,
    /// so over a four-week window a third of the series is still catching up
    /// and the fitted slope under-reads. Measured on a synthetic body losing
    /// exactly 0.5 kg a week, the smoothed fit returns about 0.36 — and this
    /// arithmetic multiplies that shortfall by 7,700, which is 150 kcal a day
    /// of expenditure that would go missing. The card would then report
    /// metabolic suppression that is entirely an artefact of a smoother.
    ///
    /// Least squares on the raw series is unbiased for a linear trend with
    /// symmetric noise, which is exactly what water weight is.
    static func weightTrend(_ samples: [HealthMetricSample], days: Int, now: Date,
                            calendar: Calendar) -> (kilogramsPerDay: Double, latestWeight: Double)? {
        let series = VitalReader.dailySeries(.bodyMass, from: samples, days: days,
                                             now: now, calendar: calendar)
        guard series.count >= minimumWeighIns, let latest = series.last?.value else { return nil }
        let day = 86_400.0
        let xs = series.map { $0.date.timeIntervalSince1970 / day }
        let ys = series.map(\.value)
        let meanX = xs.reduce(0, +) / Double(xs.count)
        let meanY = ys.reduce(0, +) / Double(ys.count)
        var numerator = 0.0, denominator = 0.0
        for (x, y) in zip(xs, ys) {
            numerator += (x - meanX) * (y - meanY)
            denominator += (x - meanX) * (x - meanX)
        }
        guard denominator > 0 else { return nil }
        return (numerator / denominator, latest)
    }

    /// Weigh-ins needed before a slope is a trend rather than two points and an
    /// opinion. The same floor `CompositionVelocityModel` uses.
    public static let minimumWeighIns = 6

    /// **What the number means, and the one direction that has a meaning.**
    ///
    /// Running below prediction is adaptive suppression, which is the finding
    /// this card exists to surface. Running *above* it is not an achievement —
    /// it is either ordinary variation or, far more often, an incomplete food
    /// log — so the curve holds at 100 rather than rewarding it. Scoring "fast"
    /// as good would make the card pay the reader for logging less.
    public static func score(speed: Double) -> Double {
        ScoreCurve.through([(0.70, 20), (0.85, 55), (0.95, 85), (1.0, 100)], at: speed)
    }
}

/// The card.
public struct MetabolismInsight: InsightModel {
    public let id: InsightID = .metabolism
    public let title = "Metabolism"
    public init() {}

    /// Body mass and lean mass are read as *scale* rather than as inputs with a
    /// share, and they are declared because both are reported below — the
    /// weight trend is half the back-calculation and the lean mass chooses the
    /// equation.
    public var candidateMetrics: [MetricType] {
        [.dietaryEnergy, .bodyMass, .activeEnergyBurned, .leanBodyMass, .activeMedicationLevel]
    }

    /// Only the fallback equation needs these, and only when no scale reports
    /// lean mass — so they are not mandatory, and the card says which equation
    /// it used either way.
    public var requirements: [GroundingRequirement] {
        [.init(kind: .dateOfBirth, isMandatory: false,
               rationale: "Needed only if no scale reports your lean mass — the fallback equation is age-based."),
         .init(kind: .biologicalSex, isMandatory: false,
               rationale: "The fallback equation's constant differs by sex; without it the card splits the difference and says so.")]
    }

    public func evaluate(samples: [HealthMetricSample], profile: UserHealthProfile,
                         now: Date) -> InsightResult {
        guard let balance = EnergyBalanceModel.evaluate(samples: samples, profile: profile,
                                                        now: now) else {
            return invitingInput(id, title,
                                 action: "Log your food and weight",
                                 message: "This needs \(EnergyBalanceModel.minimumLoggedDays) days of food logging and a run of weigh-ins over the same \(EnergyBalanceModel.windowDays) days. It then works your energy expenditure out from what you ate and what your weight actually did, rather than trusting a wearable's estimate.")
        }

        // The gate, before anything else: below it the number is a
        // back-calculation of a diary that is mostly missing, and printing it
        // would be the most flattering reading of the least data.
        guard balance.isJudgeable else {
            // The count belongs in the headline here, the way Blood Pressure
            // says "0 of 5 cuff readings": the reader is part-way, and how far
            // is the thing that tells them whether one more day matters.
            return invitingInput(id, title,
                                 action: "Logged \(balance.loggedDays) of \(balance.windowDays) days",
                                 message: "Working expenditure back from intake charges every missing meal to your metabolism, so under about \(Int(NutritionLogging.completeEnough * 100))% of days logged this card would flatter you rather than inform you. It needs a few more logged days.")
        }

        var drivers: [InsightDriver] = []
        // Under-logging first, when it is the likelier reading — before any
        // metabolic claim, because it explains the same number more simply.
        if balance.underLoggingSuspected {
            drivers.append(.notable(String(format: "Your numbers say you burn %.0f%% more than your size and movement predict. The usual explanation is not a fast metabolism — it is meals that did not make it into the log, which this calculation charges to expenditure.", ((balance.speed ?? 1) - 1) * 100)))
        }
        if let speed = balance.speed, let predicted = balance.predictedTDEE {
            drivers.append(.component(String(format: "Running at %.0f%% of predicted — %.0f kcal a day against a predicted %.0f", speed * 100, balance.observedTDEE, predicted),
                                      score: EnergyBalanceModel.score(speed: speed)))
        } else {
            drivers.append(.routine(String(format: "You are burning about %.0f kcal a day. Add your height and date of birth, or connect a scale that reports lean mass, and this card can also say how that compares with what your size predicts.", balance.observedTDEE)))
        }
        if let method = balance.basalMethod, let basal = balance.basal {
            drivers.append(.routine(String(format: "At rest: about %.0f kcal a day (%@), plus %.0f from movement and %.0f from digesting what you ate.", basal, method, balance.activeMean, balance.intakeMean * EnergyBalanceModel.thermicEffectShare)))
        }
        drivers.append(.routine(deficitLine(balance)))
        drivers.append(.routine("Logged \(balance.loggedDays) of the last \(balance.windowDays) days."))

        let score = balance.speed.map { EnergyBalanceModel.score(speed: $0) }
        return InsightResult(
            id: id, title: title,
            primaryValue: balance.speed.map { $0 * 100 } ?? balance.observedTDEE,
            headline: balance.speed.map { String(format: "%.0f%% of predicted", $0 * 100) }
                ?? String(format: "%.0f kcal/day", balance.observedTDEE),
            score: score,
            confidence: balance.completeness >= 0.95 ? .high : .moderate,
            explanation: "Your expenditure worked out from what you ate and what your weight did — not from a wearable's estimate — against what your size and measured movement predict. Below 100% is your metabolism running slower than predicted, which is what \"my metabolism has slowed\" means. Above it is usually a food log with gaps in it.",
            driverLines: drivers.filter { $0.isNotable == true } + drivers.filter { $0.isNotable != true },
            unmetRequirements: balance.predictedTDEE == nil ? requirements : [],
            contributors: contributors(balance, samples: samples),
            weighting: .equation("your own energy balance against a predicted requirement"))
    }

    private func deficitLine(_ balance: EnergyBalance) -> String {
        let weekly = balance.kilogramsPerWeek
        if balance.deficitPerDay > 0 {
            return String(format: "You are eating about %.0f kcal a day less than you burn, and your weight is moving %.2f kg a week.", balance.deficitPerDay, weekly)
        }
        return String(format: "You are eating about %.0f kcal a day more than you burn, and your weight is moving %.2f kg a week.", -balance.deficitPerDay, weekly)
    }

    /// **Every row here is weight 0, and the reason is the same one for all of
    /// them: this card is an equation, not an average.** Intake and the weight
    /// trend are the two terms of one back-calculation — neither has a "share"
    /// of the answer any more than a numerator has a share of a fraction — and
    /// saying so is better than inventing percentages that would add to 100 and
    /// mean nothing. Same shape as Cardiovascular Risk's rows.
    private func contributors(_ balance: EnergyBalance,
                              samples: [HealthMetricSample]) -> [MetricContribution] {
        // `value` is filled where the equation's own figure is a reading in the
        // metric's unit; `componentScore` never is, because an equation's terms
        // have no 0–100 of their own — which is the whole point of these rows.
        // The body-mass row stays value-less: its figure is a *rate* (kg a
        // week), not a weight, and the detail already says it in words.
        var out: [MetricContribution] = [
            MetricContribution(metric: .dietaryEnergy, higherIsBetter: nil, weight: 0,
                               detail: String(format: "%.0f kcal a day logged — one of the two terms this card solves; it has no share of the answer because it is not averaged into it", balance.intakeMean),
                               value: balance.intakeMean),
            MetricContribution(metric: .bodyMass, higherIsBetter: nil, weight: 0,
                               detail: String(format: "moving %.2f kg a week — the other term; what your weight actually did is what makes this a measurement rather than an estimate", balance.kilogramsPerWeek)),
            MetricContribution(metric: .activeEnergyBurned, higherIsBetter: nil, weight: 0,
                               detail: String(format: "%.0f kcal a day — measured movement, which goes into the *prediction* this is compared against rather than into the observation", balance.activeMean),
                               value: balance.activeMean)
        ]
        if let lean = samples.latestValue(.leanBodyMass) {
            out.append(MetricContribution(metric: .leanBodyMass, higherIsBetter: nil, weight: 0,
                                          detail: String(format: "%.1f kg — chooses the resting-rate equation (Katch-McArdle), and is the reason it needs no age or sex", lean),
                                          value: lean))
        }
        if let level = samples.latestValue(.activeMedicationLevel) {
            out.append(MetricContribution(metric: .activeMedicationLevel, higherIsBetter: nil, weight: 0,
                                          detail: String(format: "%.2f mg active — charted here because the question is which of your two numbers it moved. The evidence is that these drugs work on intake; nothing established says they raise expenditure", level),
                                          value: level))
        }
        return out
    }
}
