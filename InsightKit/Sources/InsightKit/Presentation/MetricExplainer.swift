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

    /// What the term means, for **every** metric the app can show. No
    /// exceptions, and the return type is non-optional so there cannot be one.
    ///
    /// ## This used to be optional, and the reader overruled it
    ///
    /// Until 2026-08-06 this returned `MetricExplanation?`, and thirty-six
    /// metrics returned `nil` under a heading that read *"No explanation
    /// needed, and that is a decision"*. The argument was: a step is a step, a
    /// kilogram is a kilogram, and explaining the self-explanatory is its own
    /// kind of condescension that buries the terms which genuinely puzzle
    /// someone.
    ///
    /// **The reader read the breathing-disturbance card and disagreed**, on
    /// 2026-08-06: *"I like how you added a 'What breathing disturbance index
    /// is' section, to that specific data card. I want that kind of description
    /// on EVERY data entry, make this a requirement everytime we add a new data
    /// type."* Their app, their call — and the argument was wrong anyway, which
    /// is the more useful half. Writing the thirty-six turned up a real trap in
    /// every one of them: what a phone actually counts as a step and why the
    /// watch disagrees; that a weight can move two kilograms in a day on water
    /// alone; that a device's sleep-stage split is not comparable with any
    /// other device's; that every dietary figure is a sum of what was **logged**,
    /// so a gap is a missed entry and not a fast. "Self-explanatory" was a
    /// description of the name, never of the number.
    ///
    /// The old reasoning is kept above rather than deleted because this repo
    /// supersedes its arguments instead of erasing them — the next session
    /// should be able to see that silence was chosen once, and by whom it was
    /// overturned.
    ///
    /// **Exhaustive, and now non-optional too.** A new metric cannot compile
    /// until somebody writes it a definition; `MetricExplainerTests` then checks
    /// that what they wrote is not empty and not a placeholder, which is the
    /// half the type system cannot hold.
    public static func explanation(for metric: MetricType) -> MetricExplanation {
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
        case .breathingDisturbanceIndex:
            return MetricExplanation(
                whatItIs: "How uneven your breathing was while you slept — an index your ring builds overnight from dips in blood oxygen and the movement that goes with interrupted breaths. Higher means a more disturbed night's breathing.",
                soWhat: "Breathing that fragments during sleep undermines a night before it shortens it. This is an index on the maker's own scale, not an apnoea test — it cannot diagnose one, and no published threshold says what any given level means. What it can do honestly is trend: your own nights against your own nights, so a sustained change is visible and, if it persists, is something to raise with a clinician — the only place that question can actually be answered.")
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

        // MARK: The ones that were silent until 2026-08-06
        //
        // Every arm below returned nil until the reader asked for a description
        // on every data entry. Each was written to the same bar the arms above
        // meet: `whatItIs` says what the number physically is and how it was
        // obtained, `soWhat` says the thing a reader cannot get from the name.
        // Where the honest answer is "this is a sum of what you logged", that is
        // the sentence — a gap in a dietary chart is a missed entry, not a fast,
        // and nothing else on the screen says so.

        case .heartRate:
            return MetricExplanation(
                whatItIs: "How many times your heart beat in a minute, sampled by the light sensor in your watch or ring rather than counted continuously. A day is thousands of separate readings, taken more often when you move.",
                soWhat: "Unlike a resting figure this one is meant to move — standing up, a flight of stairs and a strong coffee all show up in it. A single reading says almost nothing on its own; the shape of the day, and how quickly it settles after effort, is where the information is.")
        case .walkingHeartRateAverage:
            return MetricExplanation(
                whatItIs: "The average your heart settled at while you walked at a steady pace, taken from the flat unhurried stretches your watch could pick out. Not the peak of a workout, and not your resting figure either.",
                soWhat: "It is the closest thing to a repeatable effort test that happens by itself: roughly the same task most days, so a change here means your response to it changed rather than the task did. It drifts down as fitness improves and up with heat, illness and a bad night.")

        case .stepCount:
            return MetricExplanation(
                whatItIs: "A count of the movements your phone or watch recognised as a step, from an accelerometer looking for the rhythm of walking. Pushing a trolley, cycling and carrying a bag in that hand all confuse it, in both directions.",
                soWhat: "Phone and watch rarely agree, because they are on different parts of you and neither is wrong — which is why this app keeps the sources apart instead of averaging them. The famous ten thousand is not a research finding either: it was the name of a 1960s Japanese pedometer, and the benefit curve in the literature starts well below it and keeps rising past it.")
        case .activeEnergyBurned:
            return MetricExplanation(
                whatItIs: "An estimate of the calories you burned above simply being alive, worked out from your movement and heart rate against your height, weight, age and sex. Nothing here is measured — it is a model with your body's numbers in it.",
                soWhat: "The error on any single day is large, and it is systematic rather than random: if the model has your weight wrong it is wrong every day in the same direction. That makes it useful for comparing your days against each other and poor as an input to any calorie arithmetic.")
        case .exerciseMinutes:
            return MetricExplanation(
                whatItIs: "Minutes you spent working at least as hard as a brisk walk, judged by your watch from movement and heart rate together. A slow stroll does not count, and neither does an hour of standing still.",
                soWhat: "This is the one activity figure with real published guidance behind it, because the threshold it uses matches what those guidelines mean by moderate intensity. The dose is weekly rather than daily, so a quiet Tuesday means nothing by itself and the week is the unit worth reading.")
        case .distanceWalkingRunning:
            return MetricExplanation(
                whatItIs: "How far you travelled on foot, from GPS when a workout was recording and otherwise from your step count multiplied by an estimate of your stride. Away from GPS it inherits every error the step count has.",
                soWhat: "It only tells you something steps do not when your stride changes — the same number of short careful steps covers less ground, and that is what a tired or sore day looks like here. Treadmill work and days with the phone in a bag tend to go missing from it entirely.")
        case .flightsClimbed:
            return MetricExplanation(
                whatItIs: "How much you climbed, counted in flights of roughly three metres of ascent by the barometer in your phone or watch sensing the air pressure drop. It has no idea whether there were stairs — a steep hill counts.",
                soWhat: "It is the one everyday movement that reads work against gravity rather than ground covered, which is why it tracks leg strength and effort better than distance does. Weather moves air pressure too, so an odd reading on a stormy day is the sky rather than you.")

        case .bodyMass:
            return MetricExplanation(
                whatItIs: "What the scale read in kilograms at whatever moment you stood on it. A smart scale adds body-composition estimates on top, but the mass is the one figure it genuinely measures.",
                soWhat: "It can swing two kilograms inside a single day on water, salt, glycogen and food still in transit — none of that is fat, and all of it is real weight. That is why the trend across weeks is the signal and one morning is noise, and why weighing at the same time of day makes the trend readable weeks sooner.")
        case .height:
            return MetricExplanation(
                whatItIs: "How tall you are, in metres, as somebody typed it in — no phone, watch or scale can measure this. It is a standing fact rather than a series, which is why it gets no chart.",
                soWhat: "It is here because other numbers lean on it: BMI, waist-to-height, stride estimates and every energy model read it. A stale figure quietly biases all of them at once, and adults really do lose a centimetre or two over decades.")

        case .sleepDurationHours:
            return MetricExplanation(
                whatItIs: "How much of the night you were actually asleep, as your watch or ring judged it from movement, heart rate and breathing. No consumer device measures sleep directly — they all infer it, which is why two on the same body disagree by half an hour.",
                soWhat: "Total sleep is the figure everyone watches and the least sensitive of the sleep numbers: a broken seven hours and a solid seven hours look identical here. Read it beside efficiency and latency, which are the two that say whether the time in bed was actually slept.")
        case .sleepDeepMinutes:
            return MetricExplanation(
                whatItIs: "Minutes your device assigned to the deepest, slow-wave stage of sleep. A sleep lab reads stages off brain waves; a watch or ring guesses at them from your pulse and how still you lay, which is a far weaker signal.",
                soWhat: "Because each maker guesses differently, the stage split is not comparable between devices at all — the same night can be ninety minutes of deep on one and forty on another, and neither is the truth. Your own device against its own history is the only honest comparison here.")
        case .sleepRemMinutes:
            return MetricExplanation(
                whatItIs: "Minutes your device assigned to the stage where most dreaming happens and the eyes move under the lids. Like deep sleep it is inferred from pulse and movement rather than brain waves, so it is an estimate wearing a precise-looking number.",
                soWhat: "It comes mostly in the second half of the night, so cutting a night short takes it away out of all proportion to the hour you lost. Alcohol suppresses it early and lets it rebound later, and that shape often appears here before you notice the night was poor.")
        case .sleepOnset:
            return MetricExplanation(
                whatItIs: "The clock time you actually fell asleep, which is not the time you went to bed. It is stored as hours either side of midnight so that half past eleven and half past midnight can be averaged without nonsense.",
                soWhat: "How consistent this is matters more than how early it is — a body clock responds to regularity, and there is no correct bedtime that applies to everybody. It usually drifts several days before the tiredness that follows it does.")

        case .bloodGlucose:
            return MetricExplanation(
                whatItIs: "How much sugar is in your blood, in millimoles per litre, from either a fingerstick or a sensor worn on the arm. A continuous sensor reads the fluid between cells rather than blood itself, so it lags a real change by five to fifteen minutes.",
                soWhat: "It moves with everything — a meal, stress, illness, a short night, a hard session — so one high reading rarely means what it looks like. How much of the day it spends in range, and how quickly it comes back down after eating, carry far more than any single point.")

        // MARK: Nutrition — every figure here is a sum of what was logged
        //
        // Said once properly in each arm rather than in a shared sentence,
        // because a reader lands on exactly one of these pages at a time.

        case .dietaryEnergy:
            return MetricExplanation(
                whatItIs: "The energy in the food you logged, added up across the day. A sum of entries, not a measurement of you — nothing on your phone can see what you ate.",
                soWhat: "A day that looks low is far more often a day you stopped logging than a day you stopped eating, and that is the single most important thing to know about this chart. Even a careful log carries real error, because portion sizes and packet figures are both approximations.")
        case .dietaryProtein:
            return MetricExplanation(
                whatItIs: "How much protein was in the food you logged, in grams. It is the sum of your entries, so it describes your log rather than your intake.",
                soWhat: "Protein need scales with body size and how much you train, which is why no band is drawn here — a fixed line would be wrong for most people who saw it. How it is spread through the day matters alongside the total, since a very large single dose is not banked for later.")
        case .dietaryCarbohydrates:
            return MetricExplanation(
                whatItIs: "Total carbohydrate in the food you logged, in grams — starch and sugars together, and in most food databases fibre as well. A gap in this chart is a missed log, not a day without carbohydrate.",
                soWhat: "The total says very little alone; what the carbohydrate arrived with does most of the work. Read it beside fibre and sugar, which split the same grams into parts that behave completely differently once eaten.")
        case .dietaryFat:
            return MetricExplanation(
                whatItIs: "All the fat in the food you logged, in grams, with the saturated, monounsaturated and polyunsaturated shares counted separately as well. Those three should roughly add back up to this one.",
                soWhat: "Total fat is the least informative of the four, because in the evidence the type does nearly all of the work. The same total made of olive oil and fish is a different day from one made of butter and pastry, and only the split can tell them apart.")
        case .dietarySaturatedFat:
            return MetricExplanation(
                whatItIs: "The share of the day's fat that is saturated — solid at room temperature, mostly from meat, dairy, coconut and palm oil. Counted in grams from the food you logged.",
                soWhat: "The published guidance is a percentage of your total energy rather than a fixed weight, so what counts as a lot moves with how much you ate that day. That is why this chart carries no band and why the figure is worth reading next to calories rather than alone.")
        case .dietarySugar:
            return MetricExplanation(
                whatItIs: "Total sugars in the food you logged, in grams. Food databases almost never separate added sugar from the sugar already in fruit and milk, so both land in this one number.",
                soWhat: "The guidance that exists is about free sugars — what is added, plus juice and honey — and this figure cannot tell those from the rest. A day of fruit and a day of biscuits can read identically here, which is worth knowing before reacting to a spike.")
        case .dietaryFibre:
            return MetricExplanation(
                whatItIs: "The plant material your body cannot digest, in grams, from the food you logged. It passes through largely intact, which is exactly what makes it useful.",
                soWhat: "It feeds your gut bacteria and slows how fast sugar from a meal reaches your blood. It is also one of very few dietary figures with a plain floor and no ceiling, and most people fall well short of it without ever noticing.")
        case .dietarySodium:
            return MetricExplanation(
                whatItIs: "How much sodium was in the food you logged, in milligrams. Salt is about forty percent sodium by weight, so a gram of salt is roughly 400 mg here.",
                soWhat: "Most of it arrives in bread, sauces and prepared food rather than from the salt cellar, so intake is largely decided in the shop and not at the table. It moves blood pressure in people who are salt sensitive, and it moves the number on the scale in everybody, through water.")
        case .dietaryPotassium:
            return MetricExplanation(
                whatItIs: "How much potassium the food you logged contained, in milligrams. It comes mostly from vegetables, fruit, beans and dairy rather than from anything fortified.",
                soWhat: "It works against sodium in setting blood pressure, so the balance between the two says more than either figure by itself. A diet light on plants rarely reaches the recommended intake, and nothing about the shortfall is noticeable day to day.")
        case .dietaryWater:
            return MetricExplanation(
                whatItIs: "The fluid you logged drinking, in litres. Only what you entered counts — the water in food, and anything you drank without recording it, is invisible here.",
                soWhat: "Need varies with heat, activity, body size and what else you drank, so there is no single correct figure and this app draws no line. A sudden drop in this chart is nearly always a logging gap rather than a dry day.")
        case .dietaryCaffeine:
            return MetricExplanation(
                whatItIs: "How much caffeine you logged, in milligrams — roughly 80 to 100 mg in a coffee, about 50 in a strong tea, and often more than you would guess in a soft or energy drink.",
                soWhat: "It has a half-life of around five hours, so a mid-afternoon coffee still has a quarter of its dose in you at bedtime. That is why it can fragment a night in people who are certain it never keeps them awake — the cost shows up in the sleep data rather than in how hard it was to drop off.")

        // MARK: The eleven micronutrients
        //
        // One structure, deliberately: what it does, what depletes or blocks it,
        // and why the published intake is a floor rather than a target. The
        // content is specific to each — a shared arm would have been four lines
        // and would have told the reader nothing about the one they opened.

        case .dietaryMonounsaturatedFat:
            return MetricExplanation(
                whatItIs: "The fat with a single double bond in its chain — the kind that dominates olive oil, avocados and most nuts, liquid at room temperature and thickening in the fridge. Counted in grams from the food you logged.",
                soWhat: "It is the fat most of the Mediterranean-diet evidence is about, and the one usually swapped in when saturated fat is swapped out. Its value shows in what it replaces rather than in the total, so it reads best as a share of the day's fat.")
        case .dietaryPolyunsaturatedFat:
            return MetricExplanation(
                whatItIs: "Fats with several double bonds, covering both the omega-3 family from oily fish and walnuts and the omega-6 family from most seed oils. Food databases lump the two together into this single figure.",
                soWhat: "These are the fats your body cannot make and has to take from food, which is what makes them essential in the strict sense of the word. The lumping is the catch: this number cannot tell a week of salmon from a week of sunflower oil, and the evidence treats those two very differently.")
        case .dietaryCholesterol:
            return MetricExplanation(
                whatItIs: "The cholesterol in what you ate, in milligrams — eggs, shellfish, offal and dairy carry most of it. This is what went into your mouth, not what is in your blood.",
                soWhat: "Your liver makes most of the cholesterol in your body and turns production down when you eat more of it, so the link between this figure and a blood panel is much weaker than it was long assumed to be. Saturated fat moves that panel considerably more than this does.")
        case .dietaryCalcium:
            return MetricExplanation(
                whatItIs: "How much calcium the food you logged contained, in milligrams — dairy, tinned fish with the bones in, tofu set with calcium, and fortified plant milks.",
                soWhat: "Almost all of your calcium is in your skeleton, which the body treats as a bank and will withdraw from to keep blood levels steady, so a shortfall shows in bone and in no reading at all. It needs vitamin D to be absorbed, which is why the two belong on the same page, and the recommended intake is a floor rather than a score to beat.")
        case .dietaryIron:
            return MetricExplanation(
                whatItIs: "How much iron was in the food you logged, in milligrams. Meat carries it in a form the body absorbs several times more readily than the iron in beans, grains and leafy greens.",
                soWhat: "It carries oxygen in your blood, so running short shows as fatigue and breathlessness long before anything else appears. Requirements differ enormously between people — menstruation roughly doubles them, which is why this chart has no band — and tea or coffee with a meal cuts absorption of the plant form sharply.")
        case .dietaryMagnesium:
            return MetricExplanation(
                whatItIs: "How much magnesium the food you logged contained, in milligrams. Nuts, seeds, wholegrains, beans and dark chocolate are the ordinary sources, and refining grain strips most of it out.",
                soWhat: "It is a cofactor in hundreds of enzyme reactions, including every one that spends energy, and in letting muscle relax. A blood test barely detects a shortfall, because levels in blood are held steady by drawing on bone and muscle, so what you take in is the more honest thing to watch.")
        case .dietaryZinc:
            return MetricExplanation(
                whatItIs: "How much zinc was in the food you logged, in milligrams — shellfish, meat, seeds and beans carry most of it. Phytates in wholegrains and legumes bind some of it, so less is absorbed than the figure suggests.",
                soWhat: "It runs immune function, wound healing and your sense of taste, and the body keeps no real store, so intake has to be regular rather than occasional. The recommended figure is a floor, and there is a genuine ceiling too — sustained high doses interfere with copper.")
        case .dietaryVitaminC:
            return MetricExplanation(
                whatItIs: "How much vitamin C the food you logged contained, in milligrams. Peppers, citrus, berries and brassicas are the main sources, and heat and long storage destroy a good part of it before it reaches you.",
                soWhat: "You cannot make it and you cannot store it — the excess leaves in your urine within hours — so how it is spread across the day matters as much as the daily total. It also multiplies the iron you absorb from plants when the two are eaten in the same meal.")
        case .dietaryVitaminA:
            return MetricExplanation(
                whatItIs: "Retinol and the plant carotenes your body converts into it, from the food you logged, in micrograms of retinol activity — a unit that already discounts how inefficiently that conversion runs. Liver, dairy, eggs and orange vegetables are the sources.",
                soWhat: "It is needed for vision in low light, for skin and for immune defence, and being fat soluble it is stored in your liver for months. That store is why the ceiling matters here as much as the floor: the ready-made form from liver and supplements can accumulate to a harmful level, while carotene from vegetables does not.")
        case .dietaryVitaminD:
            return MetricExplanation(
                whatItIs: "The vitamin your skin makes in sunlight, counted here only as the micrograms that arrived in food you logged. Very little food contains it — oily fish, egg yolk and fortified spreads and cereals are close to the entire list.",
                soWhat: "Most of anyone's supply normally comes from sun on skin rather than from eating, so this figure covers a fraction of the story, and a smaller fraction the further from the equator you spend the winter. It governs how much calcium you absorb, which is why the two are worth reading together.")
        case .dietaryVitaminB12:
            return MetricExplanation(
                whatItIs: "The one vitamin no plant makes, counted in micrograms from the food you logged. It comes from animal foods and fortified products — the amounts in seaweed and fermented food are largely inactive lookalikes.",
                soWhat: "It builds red blood cells and maintains the sheath around your nerves, and the liver holds a store lasting years, so a shortfall arrives slowly and can damage nerves before it shows in a blood count. Absorption also falls with age and with long-term acid-reducing medication, so what you eat and what you absorb are two different questions.")
        }
    }
}
