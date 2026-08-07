import Foundation

// MARK: - The rule

/// **Every metric says what the seed writes for it, or why it writes nothing.**
///
/// The reader, 2026-08-07: *"looks like each time we make a new feature, we
/// should be updating the simulate data feature to support it, like i see
/// multiple new cards where there is no data, and i see lots of data fields that
/// have no data…"*
///
/// This is the same class this repo has already paid for three times, one
/// surface further along. `DataDomain` makes a new kind of data appear in the
/// Data tab **or it does not compile**; `InputKind` does it for input surfaces;
/// `MetricExplainer` does it for descriptions. `SyntheticSeed` had no such rule,
/// so it drifted: 25 of the 77 `MetricType` cases were seeded and the other 52
/// were silently absent.
///
/// **And it is worse than cosmetic.** Two cards shipped *invisible* on
/// 2026-08-03 with green tests, green CI and a successful install; the simulator
/// is the tool that catches that class. A card that renders empty because the
/// seed lacks data is indistinguishable, on screen, from a card that is broken —
/// so the one thing that can falsify a UI claim quietly stops working as
/// features land.
///
/// The fix is the shape the other three already have: an **exhaustive switch**.
/// A new `MetricType` does not compile until it has either a `Recipe` or a
/// stated reason for having none. *"Nothing writes this, it is modelled"* is a
/// legitimate answer — but it has to be **written down**, not inferred by a
/// reader staring at an empty chart.
public extension SyntheticSeed {

    /// The shape of one metric's generated series.
    ///
    /// Deliberately a small value rather than a closure: a table of numbers can
    /// be read down the page and checked against `plausibleRange` at a glance,
    /// and every knob here exists because some chart in this app needs the
    /// corresponding behaviour to draw. A flat series satisfies every test and
    /// proves nothing.
    struct Recipe: Sendable {
        /// The value at the **oldest** seeded day, before trend, weekend and noise.
        public var base: Double
        /// Added linearly across the window, reaching this in full on the newest
        /// day. Use it for a drift whose size is a property of the window
        /// ("body fat came down three points over whatever range you asked for").
        public var trend: Double = 0
        /// A drift expressed as a **rate**: multiplied by the window length, so
        /// asking for 30 days and asking for 120 give the same kg/week. Weight
        /// is the case that needs it — a fixed `trend` would make a long window
        /// and a short one lose the same total.
        public var perDay: Double = 0
        /// Peak-to-peak uniform noise, centred on zero. The wobble is the point:
        /// smoothing, the change-confidence ramp and every band in the app are
        /// exercised by it and by nothing else.
        public var spread: Double = 0
        /// Added on Saturdays and Sundays. What gives the consistency terms,
        /// the weekday/weekend splits and `WorkImpactInsight`'s whole premise
        /// something to find.
        public var weekend: Double = 0

        public init(base: Double, trend: Double = 0, perDay: Double = 0,
                    spread: Double = 0, weekend: Double = 0) {
            self.base = base
            self.trend = trend
            self.perDay = perDay
            self.spread = spread
            self.weekend = weekend
        }

        /// One day's value.
        ///
        /// - Parameters:
        ///   - t: 0 at the oldest seeded day, 1 at the newest, so a trend runs
        ///     forwards however many days were asked for.
        ///   - days: The window length, which is what `perDay` scales against.
        func value(t: Double, days: Int, isWeekend: Bool,
                   noise: inout SyntheticSeed.Noise) -> Double {
            base
                + trend * t
                + perDay * Double(days) * t
                + (isWeekend ? weekend : 0)
                + noise.next(spread: spread)
        }
    }

    /// What the seed writes for one metric.
    ///
    /// `notSeeded` is a first-class answer and carries its reason, because the
    /// alternative — an empty chart and no explanation — is exactly the state
    /// that makes a working card look broken.
    enum Plan: Sendable {
        /// A reading every day.
        case daily(Recipe)
        /// A reading only on these weekdays (`Calendar`'s numbering, 1 = Sunday).
        ///
        /// Not decoration: a cuff reading, a tape measure and a thermometer are
        /// things the reader *performs*, and a daily series would misrepresent
        /// how that data arrives — as well as defeating every "0 of 5 readings
        /// in the last 30 days" gate the cards show.
        case onWeekdays([Int], Recipe)
        /// One reading, on the newest day. A static attribute (see the repo rule
        /// separating those from time-series vitals) — a height does not have a
        /// trend and charting one would invent a story.
        case once(Double)
        /// Deliberately absent, with the reason a reader would otherwise have to
        /// guess at from an empty chart.
        case notSeeded(String)
    }
}

// MARK: - The table

public extension MetricType {

    /// **The exhaustive rule.** A new `MetricType` does not compile until it
    /// appears here — with a shape, or with a reason for having none.
    ///
    /// Values are chosen to sit inside the metric's own `plausibleRange` after
    /// noise, because `SyntheticSeed.samples` drops anything outside it rather
    /// than clamping: a fixture that could not have arrived through the real
    /// ingest path proves nothing about it. `SyntheticSeedTests` holds that.
    ///
    /// The person these numbers describe **does not exist**. They are a shape
    /// chosen to make charts draw, and no finding about anybody may be read off
    /// them. See `docs/privacy-and-ip.md`.
    var syntheticSeedPlan: SyntheticSeed.Plan {
        typealias R = SyntheticSeed.Recipe
        switch self {

        // MARK: Cardiovascular
        //
        // Resting heart rate eases down while HRV rises — the relationship the
        // cards actually read, so a seeded profile does not present the models
        // with a pattern no body produces.
        case .restingHeartRate:          return .daily(R(base: 58, trend: -3, spread: 6))
        case .heartRateVariabilityRMSSD: return .daily(R(base: 42, trend: 8, spread: 14))
        // SDNN and rMSSD are different statistics of the same signal and this
        // app keeps them as separate metrics on purpose (Apple reports one,
        // Oura the other). Seeded together so `MultiSource` and the consensus
        // paths have two real series to reconcile rather than one.
        case .heartRateVariabilitySDNN:  return .daily(R(base: 46, trend: 6, spread: 16))
        // A day's average, which sits well above the resting figure and moves
        // with activity — so a chart drawing both does not draw one line twice.
        case .heartRate:                 return .daily(R(base: 71, trend: -2, spread: 10, weekend: -3))
        case .walkingHeartRateAverage:   return .daily(R(base: 104, trend: -4, spread: 8))
        case .respiratoryRate:           return .daily(R(base: 14.2, spread: 1.6))
        case .oxygenSaturation:          return .daily(R(base: 97, spread: 2))
        case .vo2Max:                    return .daily(R(base: 41, trend: 3, spread: 1.2))
        // A provider's own cardiovascular-age estimate. Seeded a few years above
        // the synthetic reader's chronological age (see
        // `SyntheticSeed.profileFacts`) and improving, so the cards that contrast
        // a relayed vendor age with this app's own have two figures that differ —
        // which is the only state in which that contrast is legible.
        case .vascularAge:               return .daily(R(base: 44, trend: -1.5, spread: 1.0))
        // Whoop's 0–21 scale. Lower at weekends for the same reason steps are.
        case .dayStrain:                 return .daily(R(base: 11.5, spread: 5, weekend: -2.5))
        // A one-minute drop after exertion; higher is fitter, so it rises with
        // VO₂max rather than independently of it.
        case .heartRateRecovery:         return .daily(R(base: 28, trend: 4, spread: 8))
        // **Flat zero on purpose, and that is a reading rather than an absence.**
        // Zero is the good value and the overwhelmingly common one; a synthetic
        // burden that wandered would put a fibrillation history on a fictional
        // person and make the card's alarm state the default screenshot.
        case .atrialFibrillationBurden:  return .daily(R(base: 0))
        // Perfusion, off the same sensor as SpO₂.
        case .peripheralPerfusionIndex:  return .daily(R(base: 3.2, spread: 1.6))

        // MARK: Blood pressure
        //
        // A cuff reading is an event the reader performs, not something that
        // happens. Mondays and Thursdays — enough to ground an estimate, sparse
        // enough that the "readings in the last 30 days" gate has a realistic
        // count and the gap handling in the chart is exercised.
        case .bloodPressureSystolic:
            return .onWeekdays([2, 5], R(base: 128, trend: -5, spread: 10))
        case .bloodPressureDiastolic:
            return .onWeekdays([2, 5], R(base: 82, trend: -3, spread: 8))

        // MARK: Body composition
        //
        // ~0.35 kg/week down under a ±0.55 kg water swing. The wobble is the
        // point: smoothing and the change-confidence ramp are what it exercises.
        case .bodyMass:            return .daily(R(base: 92.0, perDay: -0.05, spread: 1.1))
        case .bodyFatPercentage:   return .daily(R(base: 26.5, trend: -3.2, spread: 1.0))
        // Lean mass barely moves while fat comes off — which is the whole story
        // the composition card exists to tell, and it is invisible unless both
        // series are present.
        case .leanBodyMass:        return .daily(R(base: 67.8, trend: -0.4, spread: 0.6))
        case .muscleMass:          return .daily(R(base: 64.6, trend: -0.3, spread: 0.6))
        // A smart scale's bone estimate is near-constant; the noise here is the
        // scale's, not the skeleton's.
        case .boneMass:            return .daily(R(base: 3.3, spread: 0.12))
        case .bodyWaterPercentage: return .daily(R(base: 54.5, trend: 1.2, spread: 1.4))
        // Static attribute, and the repo rule says to treat those separately
        // from time-series vitals. One value, newest day.
        case .height:              return .once(1.83)

        // MARK: Dimensions
        //
        // A tape measure is a Sunday job, not a daily reading — and seeding them
        // weekly is what puts a genuinely sparse series in front of the charts.
        // Every one of these trends down with the weight, or the body-shape
        // cards would show a waist that did not follow a 4 kg loss.
        case .waistCircumference:    return .onWeekdays([1], R(base: 96, trend: -6, spread: 1.0))
        case .hipCircumference:      return .onWeekdays([1], R(base: 104, trend: -3.5, spread: 1.0))
        case .chestCircumference:    return .onWeekdays([1], R(base: 104, trend: -2.5, spread: 1.0))
        case .neckCircumference:     return .onWeekdays([1], R(base: 40.5, trend: -1.0, spread: 0.6))
        // Shoulders are bone; they do not move with a diet, and a fixture that
        // shrank them would make every ratio the somatotype work reads drift for
        // the wrong reason.
        case .shoulderWidth:         return .onWeekdays([1], R(base: 47, spread: 0.6))
        case .thighCircumference:    return .onWeekdays([1], R(base: 60, trend: -2.0, spread: 0.8))
        case .upperArmCircumference: return .onWeekdays([1], R(base: 35, trend: -0.8, spread: 0.6))

        // MARK: Activity
        case .stepCount:              return .daily(R(base: 9400, spread: 4200, weekend: -3200))
        case .activeEnergyBurned:     return .daily(R(base: 620, spread: 300, weekend: -240))
        case .exerciseMinutes:        return .daily(R(base: 34, spread: 26, weekend: -16))
        case .distanceWalkingRunning: return .daily(R(base: 6.8, spread: 3.2, weekend: -2.4))
        case .flightsClimbed:         return .daily(R(base: 11, spread: 10, weekend: -4))
        // METs. Resting is 1 by definition and a desk day averages a little
        // above it; the band structure `EffortIntensityModel` reads needs the
        // spread to straddle the light/moderate boundary.
        case .physicalEffort:         return .daily(R(base: 2.6, spread: 1.2, weekend: -0.4))

        // MARK: Sleep
        //
        // Longer at weekends, which is what makes the consistency terms have
        // anything to say.
        case .sleepDurationHours:  return .daily(R(base: 7.1, spread: 1.8, weekend: 1.0))
        case .sleepEfficiency:     return .daily(R(base: 88, spread: 10))
        case .sleepDeepMinutes:    return .daily(R(base: 72, spread: 36))
        case .sleepRemMinutes:     return .daily(R(base: 96, spread: 40))
        case .sleepLatencyMinutes: return .daily(R(base: 17, spread: 18))
        // Hours from local midnight, negative before it — so −0.6 is 23:24 and a
        // later weekend bedtime is a *larger* number. Social jetlag is the whole
        // point of the metric and it cannot be seen without the weekend term.
        case .sleepOnset:          return .daily(R(base: -0.6, spread: 1.2, weekend: 0.9))
        // Oura's own scale, no published ceiling. Quiet nights with occasional
        // worse ones, which is the shape the trend needs for contrast.
        case .breathingDisturbanceIndex: return .daily(R(base: 8, spread: 6))

        // MARK: Temperature
        //
        // The ring's nocturnal deviation channel. Flat here and biphasic once a
        // cycle log is seeded — the strongest phase marker the app receives, so
        // a cycle fixture without it would leave `PhaseAwareBaseline`'s best
        // input untested on the simulator.
        case .skinTemperatureDeviation: return .daily(R(base: 0, spread: 0.12))
        // The absolute wrist channel, which is a different quantity from the
        // deviation above and must not look like it: skin sits several degrees
        // below core overnight.
        case .skinTemperature:          return .daily(R(base: 34.2, spread: 0.8))
        // A thermometer is an event, and a *weekly* one at that. Seeding this
        // daily would quietly imply the app has a continuous core-temperature
        // feed, which nothing in the reader's setup provides.
        case .bodyTemperature:          return .onWeekdays([4], R(base: 36.7, spread: 0.4))
        // ⚠️ **Waking, not nocturnal, and that is the whole point of the
        // channel.** `basalBodyTemperature` is written deliberately — by a
        // Shortcut on the reader's record, 136 rows over 124 days — which is
        // exactly why the radar wants it: it survives a night the ring was off,
        // and that is the night the radar otherwise goes blind. Seeded daily and
        // narrow, because a waking basal reading is a tight distribution; a wide
        // spread here would make the radar's new channel look noisy when the
        // instrument is the steadiest one it has.
        //
        // ⚠️ Seeded with **no zeros**, though 35 of the reader's own 136 records
        // are exact zeros meaning missing. The placeholder filter is what
        // removes those, and seeding them here would test the filter rather than
        // the channel — a fixture that quietly exercises the wrong thing.
        case .basalBodyTemperature:     return .daily(R(base: 36.5, spread: 0.25))

        // MARK: Metabolic
        //
        // A continuous monitor's daily figure, comfortably normal and drifting
        // down with the weight.
        case .bloodGlucose: return .daily(R(base: 5.3, trend: -0.3, spread: 0.8))

        // MARK: Gait
        //
        // Speed is step length times cadence, so the three move together — the
        // gait card's one genuinely novel claim is naming *which half moved*,
        // and a fixture whose components contradicted each other would make that
        // sentence nonsense.
        case .walkingSpeed:        return .daily(R(base: 1.28, trend: 0.06, spread: 0.14))
        case .walkingStepLength:   return .daily(R(base: 71, trend: 2, spread: 4))
        case .walkingDoubleSupport: return .daily(R(base: 27, trend: -1.2, spread: 2.4))
        case .walkingSteadiness:   return .daily(R(base: 78, trend: 4, spread: 6))
        // Zero is the good value here; a small asymmetry improving slightly.
        case .walkingAsymmetry:    return .daily(R(base: 3.5, trend: -1.0, spread: 3.0))

        // MARK: Intake
        //
        // A little under maintenance, so the metabolism back-calculation has a
        // real deficit to find instead of noise around zero.
        case .dietaryEnergy:        return .daily(R(base: 2050, spread: 700))
        case .dietaryProtein:       return .daily(R(base: 145, spread: 50))
        case .dietaryCarbohydrates: return .daily(R(base: 190, spread: 90))
        case .dietaryFat:           return .daily(R(base: 76, spread: 30))
        case .dietarySugar:         return .daily(R(base: 48, spread: 36))
        case .dietaryFibre:         return .daily(R(base: 27, spread: 14))
        case .dietaryWater:         return .daily(R(base: 2.4, spread: 1.2))
        // The rest of a food log. Every one of these has a `MetricType`, a Data
        // tab row and a `MetricExplainer` entry already — they were simply
        // absent from the seed, which is precisely the "data fields that have no
        // data" the reader saw. Figures are ordinary UK adult intakes, chosen so
        // some sit above published guidance and some below: a fixture where
        // every nutrient passed would make the nutrition card's whole scoring
        // range unreachable on a simulator.
        case .dietarySaturatedFat:        return .daily(R(base: 24, spread: 12))
        case .dietaryMonounsaturatedFat:  return .daily(R(base: 26, spread: 12))
        case .dietaryPolyunsaturatedFat:  return .daily(R(base: 14, spread: 8))
        case .dietaryCholesterol:         return .daily(R(base: 290, spread: 180))
        case .dietarySodium:              return .daily(R(base: 2600, spread: 1200))
        case .dietaryPotassium:           return .daily(R(base: 3100, spread: 1200))
        case .dietaryCalcium:             return .daily(R(base: 950, spread: 400))
        case .dietaryIron:                return .daily(R(base: 13, spread: 6))
        case .dietaryMagnesium:           return .daily(R(base: 340, spread: 140))
        case .dietaryZinc:                return .daily(R(base: 11, spread: 5))
        case .dietaryVitaminC:            return .daily(R(base: 85, spread: 60))
        case .dietaryVitaminA:            return .daily(R(base: 780, spread: 500))
        case .dietaryVitaminD:            return .daily(R(base: 9, spread: 7))
        case .dietaryVitaminB12:          return .daily(R(base: 4.2, spread: 3.0))
        // Caffeine is the one intake metric with a same-day sleep story, so it
        // gets a weekday/weekend split the others do not need.
        case .dietaryCaffeine:            return .daily(R(base: 180, spread: 140, weekend: -60))

        // MARK: Reported by the reader, or by a shortcut
        //
        // Screen time reaches the app through a Shortcuts automation, which is
        // exactly the source this whole fixture writes as.
        case .screenTimeMinutes: return .daily(R(base: 220, spread: 120, weekend: 90))

        // MARK: Sound
        //
        // ⚠️ **The two sensors are deliberately not seeded the same way, and
        // that asymmetry is the card's entire design.** `SoundExposureModel`
        // treats an absent environmental day as "the watch was in a drawer" and
        // an absent headphone day as "no audio played" — the same absence
        // meaning opposite things is why one can carry a weekly cumulative total
        // and the other cannot. A fixture that filled both every day would erase
        // the distinction and make the card's caveat look like superstition.
        case .headphoneSoundDose:
            return .onWeekdays([2, 3, 4, 5, 6], R(base: 72, spread: 16))
        case .environmentalSoundDose:
            return .onWeekdays([3, 6], R(base: 68, spread: 14))

        // MARK: Not seeded, and why
        //
        // **Modelled, never measured.** This is computed by
        // `Pharmacokinetics.levels` from logged doses and a published half-life,
        // and it is written with `MetricSource.calculated` for that reason.
        // Writing it here as a `.shortcuts` sample would dress a model as a
        // measurement — the one thing this repo's rules forbid outright — and
        // would also survive "Clear seeded data", which deletes by source.
        // The honest route is a seeded substance log; see
        // `InsightID.syntheticSeedExpectation` for what that would light up.
        case .activeMedicationLevel:
            return .notSeeded("""
                Modelled from logged doses by Pharmacokinetics.levels and written \
                as MetricSource.calculated. Seeding it directly would dress a \
                model as a measurement. It appears once a substance log is seeded.
                """)
        }
    }

    /// A stable per-metric salt for the fixture's noise.
    ///
    /// **Why not just the case's position.** The generator used to draw every
    /// metric for a day from one stream, in declaration order — so adding a
    /// metric shifted every series after it and invalidated every screenshot
    /// taken before. FNV-1a over the `rawValue` gives each metric its own
    /// independent stream, so a new case changes nothing that already existed.
    ///
    /// Not `hashValue`: Swift seeds `String` hashing per process, so it is not
    /// stable between runs — and reproducibility is the one property that makes
    /// a screenshot comparable to next week's.
    var syntheticSeedSalt: UInt64 {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in rawValue.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        return hash
    }
}
