import Foundation

/// Turns the raw audio-exposure samples into one honest figure per day —
/// the reader's own rule from the refusal it reverses (backlog §B5 #33):
/// **store the dose, never the level.**
///
/// ## Why the arithmetic has to be this one
///
/// A decibel is ten times the logarithm of a power ratio, so levels do not add
/// and do not average: the arithmetic mean of twelve quiet hours at 60 dBA and
/// one minute at 90 dBA is a number no ear experienced, and it overstates the
/// day the moment anything loud but brief appears in it. Equal-energy dose —
/// the basis of every published exposure limit — works in intensity instead:
///
///     LEQ = 10 · log10( Σ tᵢ · 10^(Lᵢ/10) / Σ tᵢ )
///
/// each sample's level Lᵢ converted back to intensity, weighted by its own
/// duration tᵢ, summed, divided by the time actually measured, and taken back
/// to decibels. The result is the steady level that would have delivered the
/// same sound energy as the real mix — for that 60 dBA day with its loud
/// minute, roughly 64 dBA, not 75 and not 60.
///
/// ## The denominator is the measured time, and that is the honesty mechanism
///
/// Dividing by the whole day instead would assert that every unmeasured hour
/// was silent. For headphones that is nearly true; for environmental sound it
/// is flatly false — the watch heard 14 of the reader's last 90 days — and
/// "inventing the quiet hours" is word for word why the original refusal said
/// no. So the figure claims only the hours the sensor could hear, the two
/// exposures are **never summed into one number**, and how much of the day was
/// measured stays visible in the raw samples for the card that will one day
/// state it.
///
/// ## The pattern is `TemperatureReconstructor`'s
///
/// Raw provider data in, canonical derived samples out, applied on the ingest
/// path, idempotently: `withSoundDose` strips every previous derived dose
/// sample before regenerating, so running it twice cannot stack two copies of
/// a day (the same strip-then-rebuild `refreshMedicationLevelSamples` uses).
/// Every emitted sample carries `MetricSource.calculated`, because no device
/// produced this daily figure. **`SoundExposureModel` reads them into a score
/// since 2026-08-07** (backlog §B3 #22) — the headphone series against WHO/ITU's
/// weekly allowance, the environmental one reported beside it and never added.
/// That card is also why each sample's **span is the measured time**: see
/// `measuredSeconds(of:)`.
public enum SoundDoseModel {

    /// The two HealthKit identifiers this model consumes, exactly as they
    /// arrive in the raw "other data" pile from `HealthKitService`. They stay
    /// raw on purpose — they are this model's input, not a second route into
    /// the canonical metrics.
    public static let environmentalIdentifier =
        "HKQuantityTypeIdentifierEnvironmentalAudioExposure"
    public static let headphoneIdentifier =
        "HKQuantityTypeIdentifierHeadphoneAudioExposure"

    /// Which dose series each raw identifier feeds. Two entries, two metrics,
    /// and deliberately no way to land both in one — the type system's version
    /// of "never summed into one figure".
    static let doseMetric: [String: MetricType] = [
        environmentalIdentifier: .environmentalSoundDose,
        headphoneIdentifier: .headphoneSoundDose,
    ]

    /// The derived types, for the strip half of the idempotence.
    public static let doseTypes: Set<MetricType> = [
        .environmentalSoundDose, .headphoneSoundDose,
    ]

    /// A raw sample with no duration still holds a measured level, so it gets
    /// one nominal second of weight rather than vanishing from the sum — the
    /// alternative silently discards data on providers that write instants.
    static let minimumSampleSeconds: TimeInterval = 1

    /// Raw levels a wrist microphone or headphone output cannot genuinely
    /// report. The ceiling matters more than usual here because the next step
    /// is `pow(10, level / 10)`: a unit-slip like the catalogue's famous
    /// 170,000 would not merely skew the day, it would overflow it to
    /// infinity and take the whole series down with it.
    static let plausibleRawLevel = 0.0...140.0

    /// One `HealthMetricSample` per metric per day that has any usable raw
    /// samples — days with none produce nothing, never a zero (a silent day
    /// and an unworn watch are indistinguishable, and only one of them is
    /// quiet).
    ///
    /// A sample is filed under the day its **start** falls in. The exposure
    /// intervals both identifiers write are minutes long, so splitting the
    /// rare one that crosses midnight would complicate every caller to move a
    /// sliver of energy between two days.
    public static func dailySamples(from raw: [RawMetricSample],
                                    calendar: Calendar = .current) -> [HealthMetricSample] {
        struct Key: Hashable {
            let metric: MetricType
            let day: Date
        }
        var weightedIntensity: [Key: Double] = [:]
        var measuredSeconds: [Key: Double] = [:]

        for sample in raw {
            guard let metric = doseMetric[sample.identifier],
                  let level = sample.numericValue,
                  level.isFinite,
                  plausibleRawLevel.contains(level),
                  // A raw 0 dBA is the threshold of hearing — below both
                  // sensors' floors, so it is a placeholder, not a silence.
                  level > 0
            else { continue }
            let key = Key(metric: metric, day: calendar.startOfDay(for: sample.start))
            let seconds = Swift.max(sample.end.timeIntervalSince(sample.start),
                                    minimumSampleSeconds)
            weightedIntensity[key, default: 0] += seconds * pow(10, level / 10)
            measuredSeconds[key, default: 0] += seconds
        }

        return weightedIntensity.compactMap { key, energy -> HealthMetricSample? in
            guard let seconds = measuredSeconds[key], seconds > 0 else { return nil }
            let leq = 10 * log10(energy / seconds)
            // ⚠️ **The span is the measured time, and it is the other half of
            // the figure** — see `measuredSeconds(of:)` directly below for why
            // a level without its duration cannot be weighed against any
            // published limit.
            return HealthMetricSample(type: key.metric, value: leq,
                                      start: key.day,
                                      end: key.day.addingTimeInterval(seconds),
                                      source: .calculated)
        }
        // Deterministic order — a dictionary's is not — so two runs over the
        // same raw pile are equal element-for-element, which the idempotence
        // test asserts and downstream diffing quietly relies on.
        .sorted {
            ($0.start, $0.type.rawValue) < ($1.start, $1.type.rawValue)
        }
    }

    /// **How long the sensor could hear, for a derived dose sample.**
    ///
    /// ⚠️ **A level on its own cannot be weighed against a limit, and this is
    /// the missing half.** Every published exposure budget — WHO/ITU's 80 dB(A)
    /// for 40 hours a week, NIOSH's 85 dB(A) for eight — is a statement about
    /// *energy*, which is a level **times a duration**. 85 dB(A) for ten minutes
    /// and 85 dB(A) for ten hours are the same LEQ and sixty times the dose, so
    /// a card holding only `value` could report the reader's listening level and
    /// never their exposure. That is the gap `SoundExposureModel` exists to
    /// close, and it is why the span is carried.
    ///
    /// **Why `end` rather than a new `MetricType`.** The span of a sample is
    /// already this app's word for how long a reading covers —
    /// `EffortIntensityModel` reads `end − start` off every `physicalEffort`
    /// sample to get its minutes, on the same ingest path and for the same
    /// reason. A second metric would have put the denominator of a figure in a
    /// different series from the figure, where the two could be filtered apart.
    ///
    /// ⚠️ **The span says how much, never when.** `start` is midnight because
    /// this is a daily aggregate; `start + measured` is not a claim that the
    /// listening happened in the small hours. Nothing may read a time of day off
    /// these two dates, and nothing does.
    ///
    /// It can exceed a day where two sources overlap — two headphones paired at
    /// once write overlapping intervals, and both their energy and their time
    /// count. The LEQ is unaffected (both halves of the ratio scale together)
    /// and the dose is legitimately the sum of what each ear took, so it is left
    /// unclamped rather than quietly capped at 24 hours.
    public static func measuredSeconds(of sample: HealthMetricSample) -> TimeInterval {
        Swift.max(0, sample.end.timeIntervalSince(sample.start))
    }

    /// Samples with the daily sound doses merged in — the previous derivation
    /// stripped first, so the operation is idempotent however many times an
    /// ingest path runs it. Mirrors
    /// `TemperatureReconstructor.withReconstructedTemperature`, which sits
    /// beside it on both call sites.
    public static func withSoundDose(_ samples: [HealthMetricSample],
                                     raw: [RawMetricSample],
                                     calendar: Calendar = .current) -> [HealthMetricSample] {
        samples.filter { !doseTypes.contains($0.type) }
            + dailySamples(from: raw, calendar: calendar)
    }
}
