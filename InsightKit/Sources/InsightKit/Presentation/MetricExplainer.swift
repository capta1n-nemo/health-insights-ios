import Foundation

/// What a metric **is**, and why it is worth knowing — in the words someone
/// would use out loud.
///
/// The reader, 2026-08-05: *"what even is HRV… am i about to die?"* They asked
/// for three things everywhere a term appears: what it is, what **mine** means,
/// and so what. This type carries the first and third; `MetricExplainer.yours`
/// builds the second, and it builds it from the reader's own history because
/// "what mine means" cannot be answered by a population table.
public struct MetricExplanation: Sendable, Equatable {
    /// One or two sentences. No units, no thresholds, no numbers at all — the
    /// figures belong to `yours`, which has the reader's data in scope.
    public let whatItIs: String
    /// Why it is worth a reader's attention. Never advice.
    public let soWhat: String

    public init(whatItIs: String, soWhat: String) {
        self.whatItIs = whatItIs
        self.soWhat = soWhat
    }
}

public enum MetricExplainer {

    /// The reader-relative half: **what yours means, against your own record.**
    ///
    /// Deliberately no population comparison. A published normal band answers
    /// "is this typical of adults", which is not the question someone asks
    /// about their own body, and for several of these metrics the spread
    /// between healthy people is far wider than the spread within one — an
    /// HRV of 36 ms is unremarkable for one person and a bad week for another.
    /// This app already refuses to draw a fixed band for exactly that reason on
    /// waist circumference and the micronutrients.
    ///
    /// Returns nil rather than a sentence when there is too little history to
    /// say anything, which is honest and is also the common case on a new
    /// install.
    public static func yours(_ metric: MetricType, value: Double,
                             history: [Double]) -> String? {
        // **Sorted once.** `Baseline.quantile` and `Baseline.percentile` each
        // sort their input, so the obvious three calls are three O(n log n)
        // passes over the same array — and on heart rate that array is tens of
        // thousands of readings, from a SwiftUI computed property. Sort here,
        // read three answers off it.
        guard history.count >= minimumHistory else { return nil }
        let sorted = history.sorted()
        guard let low = quantile(0.1, ofSorted: sorted),
              let high = quantile(0.9, ofSorted: sorted),
              high > low else { return nil }
        // Rank of `value`, matching `Baseline.percentile` **exactly**: it counts
        // entries `<= value`, so this is the index of the first entry strictly
        // greater. The first draft of this line used `>=`, i.e. strictly-less
        // — which agrees only when there are no ties, and a rounded daily
        // metric is nothing but ties. On a resting heart rate that reads 66 on
        // twenty days it under-reported the percentile far enough to move the
        // sentence from "toward the upper end of" to "toward the lower end of".
        // A faster percentile that quietly reports a different one is not a
        // performance fix.
        let atOrBelow = sorted.firstIndex { $0 > value } ?? sorted.count
        let percentile = Double(atOrBelow) / Double(sorted.count)

        let unit = metric.unit.isEmpty ? "" : " \(metric.unit)"
        let range = "\(format(low, metric))–\(format(high, metric))\(unit)"
        let position: String
        switch percentile {
        case ..<0.1: return "Yours is \(format(value, metric))\(unit) — lower than almost any day you have recorded. Your usual middle stretch is \(range)."
        case ..<0.35: position = "toward the lower end of"
        case ..<0.65: position = "right in the middle of"
        case ..<0.9: position = "toward the upper end of"
        default: return "Yours is \(format(value, metric))\(unit) — higher than almost any day you have recorded. Your usual middle stretch is \(range)."
        }
        return "Yours is \(format(value, metric))\(unit), \(position) your own usual \(range)."
    }

    /// Ten days is the floor for quoting a personal range. Below it the p10–p90
    /// is two or three readings wide and "your usual" would be a fiction.
    static let minimumHistory = 10

    /// `Baseline.quantile`'s interpolation, on an array already sorted.
    private static func quantile(_ q: Double, ofSorted sorted: [Double]) -> Double? {
        guard !sorted.isEmpty else { return nil }
        if sorted.count == 1 { return sorted[0] }
        let position = Swift.min(Swift.max(q, 0), 1) * Double(sorted.count - 1)
        let lower = Int(position.rounded(.down))
        let upper = Swift.min(lower + 1, sorted.count - 1)
        return sorted[lower] + (sorted[upper] - sorted[lower]) * (position - Double(lower))
    }

    private static func format(_ value: Double, _ metric: MetricType) -> String {
        let decimals = abs(value) < 10 && metric.unit != "bpm" ? 1 : 0
        return String(format: "%.\(decimals)f", value)
    }

    /// What the term means, for every metric the app can show.
    ///
    /// **Exhaustive on purpose.** A new metric cannot be added without a
    /// decision about whether it needs explaining, which is the same discipline
    /// `referenceRange` and `dataCategory` already impose. `nil` is a legitimate
    /// answer — a step is a step — but it has to be chosen.
    public static func explanation(for metric: MetricType) -> MetricExplanation? {
        switch metric {

        // MARK: The terms the reader named

        case .heartRateVariabilityRMSSD, .heartRateVariabilitySDNN:
            return MetricExplanation(
                whatItIs: "The tiny differences in timing between one heartbeat and the next. A healthy heart is not a metronome — the gaps flex slightly with your breathing, and this measures how much.",
                soWhat: "It tracks how much spare capacity your nervous system has. It falls when you are stressed, unwell, short of sleep or drinking, and it climbs back as you recover. The number itself means very little between people — mine and yours are not comparable — so what matters is your own direction of travel.")
        case .restingHeartRate:
            return MetricExplanation(
                whatItIs: "How fast your heart beats when you are doing nothing at all — usually measured while you sleep.",
                soWhat: "It is one of the most responsive numbers your body produces. It rises with illness, alcohol, heat, poor sleep and stress, often a day before you notice any of them, and it drifts down as fitness improves.")
        case .vo2Max:
            return MetricExplanation(
                whatItIs: "The most oxygen your body can use in a minute of hard effort, per kilogram you weigh. Your watch estimates it from how your heart rate responds to exercise rather than measuring it directly.",
                soWhat: "It is the single best-studied measure of cardiovascular fitness, and one of the strongest predictors of long-term health there is. It moves slowly — over months, not days.")
        case .oxygenSaturation:
            return MetricExplanation(
                whatItIs: "The percentage of your blood's carrying capacity that is actually carrying oxygen, read through your skin by a light sensor.",
                soWhat: "It normally sits in a narrow band and barely moves, which is what makes a sustained dip worth noticing. Single low readings are usually the sensor — a loose strap or a cold finger — rather than you.")
        case .sleepEfficiency:
            return MetricExplanation(
                whatItIs: "The share of the time you spent in bed that you were actually asleep.",
                soWhat: "It separates a short night from a broken one. Eight hours in bed at low efficiency is a very different night from six hours at high efficiency, and only one of them is a sleep-length problem.")
        case .sleepLatencyMinutes:
            return MetricExplanation(
                whatItIs: "How long it took you to fall asleep after getting into bed.",
                soWhat: "Very short can mean you were overtired; very long is the classic marker of a racing mind, late caffeine or a body clock that has drifted. It responds quickly to changes in routine.")
        case .vascularAge:
            return MetricExplanation(
                whatItIs: "An estimate of how stiff your arteries are, expressed as the age of a typical person with arteries like yours. It comes from the shape of the pulse wave your ring or watch sees.",
                soWhat: "Arterial stiffness rises with age, blood pressure and inactivity. It is an estimate from one sensor rather than a clinical measurement, so treat it as a direction rather than a verdict.")
        case .respiratoryRate:
            return MetricExplanation(
                whatItIs: "How many breaths you take a minute while asleep.",
                soWhat: "It is remarkably stable night to night, which is exactly why a change matters. It is one of the earliest signals that something is brewing — often before a temperature moves.")
        case .skinTemperature, .skinTemperatureDeviation, .bodyTemperature:
            return MetricExplanation(
                whatItIs: "How warm you are overnight. Wearables usually report the change from your own normal rather than an absolute figure, because wrist and finger temperature depend heavily on the room.",
                soWhat: "A sustained rise is the most specific single sign of an immune response the app can see. A single warm night is usually the bedroom.")
        case .heartRateRecovery:
            return MetricExplanation(
                whatItIs: "How far your heart rate falls in the minute after you stop exercising hard.",
                soWhat: "A quick drop means your nervous system switches out of effort mode efficiently, which tracks both fitness and recovery. It is blunted by alcohol the night before and by stimulants.")

        // MARK: Everything else that carries jargon

        case .bloodPressureSystolic, .bloodPressureDiastolic:
            return MetricExplanation(
                whatItIs: "The pressure in your arteries when the heart squeezes (the upper number) and when it relaxes between beats (the lower one).",
                soWhat: "It is the single most modifiable risk factor for stroke and heart attack. It also moves with the hour, the cuff position and whether you have just walked upstairs, so a run of readings says far more than one.")
        case .atrialFibrillationBurden:
            return MetricExplanation(
                whatItIs: "The share of the time your watch believes your heart was in an irregular rhythm rather than a regular one.",
                soWhat: "It is an estimate from a wrist sensor, not a diagnosis. It exists so a pattern can be brought to a clinician, which is the only thing that can confirm it.")
        case .walkingSteadiness, .walkingAsymmetry:
            return MetricExplanation(
                whatItIs: "How even and stable your walking is, measured from the way your phone moves in your pocket.",
                soWhat: "It changes slowly and for real reasons — injury, fatigue, alcohol, illness. A sudden change is worth noticing precisely because this is normally a boring number.")
        case .walkingSpeed:
            return MetricExplanation(
                whatItIs: "How fast you walk, averaged over the walking your phone was in your pocket for.",
                soWhat: "It is one of the best-studied numbers in the whole of health, and it moves early — before strength, before endurance, before anything you would notice. The catch is that this one is measured by a phone in a pocket, so a quiet week can mean you walked less rather than slower.")
        case .walkingStepLength:
            return MetricExplanation(
                whatItIs: "The distance between one heel landing and the next.",
                soWhat: "Speed can fall two ways — shorter steps or fewer of them — and this is the half that says which. Shorter steps usually mean caution, stiffness or fatigue rather than tiredness of the legs.")
        case .walkingDoubleSupport:
            return MetricExplanation(
                whatItIs: "The share of each stride where both feet are on the ground at once.",
                soWhat: "It is what your body does when it is not certain of the next step, so it rises with caution, pain and unfamiliar ground. It also rises simply because you walked slower, which is why it is worth reading next to your speed rather than alone.")
        case .peripheralPerfusionIndex:
            return MetricExplanation(
                whatItIs: "How strong the blood flow is where the sensor sits, relative to the tissue it shines through.",
                soWhat: "Mostly it tells you how good the reading conditions were — cold hands lower it. It also drops when blood vessels narrow, which stimulants do.")
        case .dayStrain:
            return MetricExplanation(
                whatItIs: "A single figure for how much cardiovascular work you did across the day, weighted so that time spent at a high heart rate counts for much more than time spent walking.",
                soWhat: "It is a load number rather than an achievement. It is most useful read against your own recent days, since the scale is arbitrary.")
        case .screenTimeMinutes:
            return MetricExplanation(
                whatItIs: "How long your phone screen was on and being used.",
                soWhat: "It is here because of what it correlates with rather than for its own sake — late screen time and sleep onset move together for most people.")
        case .activeMedicationLevel:
            return MetricExplanation(
                whatItIs: "A model of roughly how much of your medication is still active in your body, worked out from the doses you have logged and how quickly the drug clears.",
                soWhat: "It is a calculation from your dose log, not a measurement of your blood. It exists so the app can tell a dose change apart from a change in you.")
        case .bodyFatPercentage, .leanBodyMass, .muscleMass, .boneMass, .bodyWaterPercentage:
            return MetricExplanation(
                whatItIs: "What your weight is made of. Smart scales estimate this by passing a tiny current through you and measuring the resistance — fat, muscle and water each conduct differently.",
                soWhat: "The absolute figures carry real uncertainty and shift with how hydrated you are. The trend over weeks is far more trustworthy than any single morning.")
        case .waistCircumference, .hipCircumference, .chestCircumference,
             .neckCircumference, .shoulderWidth, .thighCircumference,
             .upperArmCircumference:
            return MetricExplanation(
                whatItIs: "A tape measurement around one part of your body.",
                soWhat: "Where weight sits matters as much as how much there is — waist relative to height in particular tracks metabolic risk better than weight alone.")

        case .physicalEffort:
            return MetricExplanation(
                whatItIs: "How hard your body was working, in METs — multiples of what you burn sitting still. Sitting is 1, a gentle walk about 3, a brisk one about 5, and running roughly 8 and up. Your watch estimates it from movement and heart rate.",
                soWhat: "Steps and distance say how much you moved; this says how hard. Ten thousand slow steps and an hour of hills are the same on a step counter and very different here, and it is the intensity that most of the health evidence is actually about.")

        // A dose expressed as a level genuinely needs explaining — "your day
        // was 68 dBA" reads as a loudness reading, and it is not one. Two
        // separate arms rather than one shared, because what each sensor could
        // and could not hear is the honest half of each explanation and it
        // differs between them.
        case .environmentalSoundDose:
            return MetricExplanation(
                whatItIs: "How loud the world around you was, folded into one steady level for the day — the constant loudness that would have carried the same sound energy to your ears as the real mix of quiet stretches and loud moments your watch heard.",
                soWhat: "Hearing wears by accumulated dose rather than by single loud moments, which is why the day is summed by energy instead of averaged. The watch can only count the hours it was worn — a quiet-looking day can simply be a day it spent on the charger, so the run of days says more than any one figure.")
        case .headphoneSoundDose:
            return MetricExplanation(
                whatItIs: "Everything your headphones played in a day, folded into one steady level — the constant volume that would have carried the same sound energy as the real mix of quiet podcasts and loud songs.",
                soWhat: "Headphone sound goes straight into the ear, so it is the one exposure you set yourself. Loudness accumulates as energy, not as numbers on a dial — a short very loud stretch can outweigh hours of moderate listening, and that imbalance is exactly what this way of summing a day is built to catch.")

        // MARK: No explanation needed, and that is a decision
        //
        // A step is a step, a kilogram is a kilogram, and a glass of water does
        // not need defining. Explaining the self-explanatory is its own kind of
        // condescension, and it buries the terms that genuinely puzzle someone.
        case .heartRate, .walkingHeartRateAverage, .stepCount, .activeEnergyBurned,
             .exerciseMinutes, .distanceWalkingRunning, .flightsClimbed,
             .bodyMass, .height, .sleepDurationHours,
             .sleepDeepMinutes, .sleepRemMinutes, .sleepOnset, .bloodGlucose,
             .dietaryEnergy, .dietaryProtein, .dietaryCarbohydrates, .dietaryFat,
             .dietarySaturatedFat, .dietarySugar, .dietaryFibre, .dietarySodium,
             .dietaryPotassium, .dietaryWater, .dietaryCaffeine,
             .dietaryMonounsaturatedFat, .dietaryPolyunsaturatedFat,
             .dietaryCholesterol, .dietaryCalcium, .dietaryIron, .dietaryMagnesium,
             .dietaryZinc, .dietaryVitaminC, .dietaryVitaminA, .dietaryVitaminD,
             .dietaryVitaminB12:
            return nil
        }
    }
}
