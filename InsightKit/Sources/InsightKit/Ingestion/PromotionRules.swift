import Foundation

/// A declarative instruction to also record a raw field as a canonical vital.
///
/// Mapping lives in data, not in a `switch` inside a parser. Teaching the app
/// that a connector's field is really Body Fat is adding a row here — the store,
/// the flattener and the insight engine are untouched, which is the whole point
/// of requirement 4.
public struct PromotionRule: Sendable, Hashable, Codable {
    public enum Match: Sendable, Hashable, Codable {
        /// Full namespaced identifier: `oura.vO2_max.vo2_max`.
        case identifier(String)
        /// Last dotted component, whatever the endpoint: `vo2_max`.
        case leaf(String)
        /// Trailing path fragment: `spo2_percentage.average`.
        case suffix(String)
    }

    /// How to read the raw field into a canonical number.
    ///
    /// This exists because promotion used to be *numeric by definition*:
    /// `IngestionPipeline` promoted only fields with a `doubleValue`, so a rule
    /// pointed at a text field matched and then promoted nothing, silently. That
    /// is fine for every vital whose provider sends a number and wrong for the
    /// one canonical metric derived from a **timestamp** — a bedtime arrives as
    /// an ISO-8601 string, and `RawValue.text.doubleValue` is `nil`.
    public enum Interpretation: Sendable, Hashable, Codable {
        /// `value * scale + offset` on a numeric field. What every rule did
        /// before this type existed, and the default.
        case numeric
        /// An ISO-8601 instant read as `MetricType.sleepOnset` — signed hours
        /// from midnight, via `SleepOnset.hoursFromMidnight`.
        ///
        /// Also **re-dates the sample** to the night it belongs to. A promoted
        /// sample is otherwise stamped at the document's own date, and
        /// `SleepOnset` stamps at the night key (the morning the night ends on),
        /// so without this a promoted 23:30 and a parser-built 23:30 for one
        /// night would land on two different days and be read as two nights.
        case sleepOnsetTimestamp
    }

    public let match: Match
    public let metric: MetricType
    /// Applied as `value * scale + offset`, for providers reporting a different
    /// unit to the canonical one (metres vs centimetres, °F vs °C).
    public let scale: Double
    public let offset: Double
    /// Restrict to one connector, when the same leaf name means different
    /// things across providers.
    public let sourceID: String?
    public let interpretation: Interpretation

    public init(match: Match, metric: MetricType, scale: Double = 1, offset: Double = 0,
                sourceID: String? = nil, interpretation: Interpretation = .numeric) {
        self.match = match
        self.metric = metric
        self.scale = scale
        self.offset = offset
        self.sourceID = sourceID
        self.interpretation = interpretation
    }

    func matches(identifier: String, leaf: String, sourceID: String) -> Bool {
        if let required = self.sourceID, required != sourceID { return false }
        switch match {
        case .identifier(let value): return identifier == value
        case .leaf(let value): return leaf == value
        case .suffix(let value): return identifier.hasSuffix(value)
        }
    }

    public func convert(_ value: Double) -> Double { value * scale + offset }

    /// What this rule promotes a raw field to, if anything.
    ///
    /// Returns the canonical value and, for interpretations that know better
    /// than the document which instant the reading belongs to, the date to stamp
    /// it at. `nil` means "this field is not promotable under this rule" — a text
    /// value under a numeric rule, or a timestamp that isn't a plausible bedtime.
    /// Declining is deliberate rather than a fallback: a bedtime outside
    /// 18:00–06:00 is evidence the segment is a nap, and the parsers already
    /// refuse it for the same reason.
    func promotion(of raw: RawValue,
                   calendar: Calendar = .current) -> (value: Double, date: Date?)? {
        switch interpretation {
        case .numeric:
            guard let number = raw.doubleValue else { return nil }
            return (convert(number), nil)
        case .sleepOnsetTimestamp:
            guard case .text(let string) = raw,
                  Self.carriesTimeOfDay(string),
                  let instant = PayloadDate.parse(string),
                  let hours = SleepOnset.hoursFromMidnight(instant, calendar: calendar)
            else { return nil }
            // Scale and offset stay out of it: this value is an hour of the
            // clock, and there is no unit for a provider to disagree about.
            return (hours, SleepOnset.night(of: instant, calendar: calendar))
        }
    }

    /// Whether a date string says anything about the time of day.
    ///
    /// `PayloadDate` accepts a bare `2026-07-31` and returns midnight UTC, which
    /// is the right answer for a daily record and the wrong one for a bedtime:
    /// midnight is a perfectly ordinary time to fall asleep, so a date-only field
    /// would promote a plausible-looking 00:00 every night and there would be
    /// nothing in the data to show it was invented. A bedtime must be declined
    /// unless the provider actually sent an hour.
    private static func carriesTimeOfDay(_ string: String) -> Bool {
        string.contains("T") || string.contains(":")
    }
}

/// The rule table, plus the alias vocabulary used to *propose* mappings for
/// fields nobody has written a rule for yet.
public struct PromotionRuleSet: Sendable {
    public let rules: [PromotionRule]
    /// Leaf names that name a canonical vital. A match here without a matching
    /// rule becomes a proposal — logged and catalogued, never acted on — so a
    /// provider renaming a field can't silently rewire an insight.
    public let aliases: [String: MetricType]

    public init(rules: [PromotionRule], aliases: [String: MetricType]) {
        self.rules = rules
        self.aliases = aliases
    }

    /// The rule authorising promotion of this field, if any.
    public func rule(forIdentifier identifier: String, sourceID: String) -> PromotionRule? {
        let leaf = identifier.split(separator: ".").last.map(String.init) ?? identifier
        return rules.first { $0.matches(identifier: identifier, leaf: leaf, sourceID: sourceID) }
    }

    /// A metric this field plausibly *is*, for a field with no rule.
    public func proposal(forIdentifier identifier: String) -> MetricType? {
        let components = identifier.split(separator: ".").map(String.init)
        guard let leaf = components.last else { return nil }
        if let direct = aliases[leaf] { return direct }
        // `spo2_percentage.average` — the qualifier is the aggregation, the
        // meaning is one level up.
        if components.count >= 2, ["average", "mean", "value"].contains(leaf) {
            return aliases[components[components.count - 2]]
        }
        return nil
    }

    // MARK: - Shipped defaults

    /// Fields the app promotes today. Oura's own canonical parsers already
    /// handle sleep/readiness/spo2/activity, so these are the collections that
    /// had no mapping at all.
    public static let `default` = PromotionRuleSet(
        rules: [
            // Oura's VO₂ Max collection, alongside Apple's Cardio Fitness.
            PromotionRule(match: .identifier("oura.vO2_max.vo2_max"),
                          metric: .vo2Max, sourceID: MetricSource.oura.id),
            // Oura's own cardiovascular-age estimate. Kept as its own metric
            // rather than merged into our heart age: it's a second opinion from
            // a different model, and the value of a second opinion is that it
            // stays separate enough to disagree.
            PromotionRule(match: .identifier("oura.daily_cardiovascular_age.vascular_age"),
                          metric: .vascularAge, sourceID: MetricSource.oura.id),
            // Oura's nightly breathing-disturbance index, from the daily_spo2
            // collection the typed SpO₂ parser reads its percentage from — the
            // index itself only ever reached the raw catalogue (107 nights on
            // the reader's export, 2026-08-06). Promoted for backlog #30/S9:
            // charted and trended on the Sleep card, never scored, because
            // Oura publishes no validated curve for it. No scale or offset —
            // the index is kept on Oura's own scale, since there is no
            // canonical unit to convert a proprietary composite into.
            PromotionRule(match: .identifier("oura.daily_spo2.breathing_disturbance_index"),
                          metric: .breathingDisturbanceIndex, sourceID: MetricSource.oura.id),
            // Withings measure types not covered by the canonical parser but
            // meaning a vital we already model.
            PromotionRule(match: .identifier("withings.measure.12"),
                          metric: .bodyTemperature, sourceID: MetricSource.withings.id),
            PromotionRule(match: .identifier("withings.measure.4"),
                          metric: .height, sourceID: MetricSource.withings.id)
        ],
        aliases: [
            "vo2_max": .vo2Max,
            "vo2max": .vo2Max,
            "vascular_age": .vascularAge,
            "resting_heart_rate": .restingHeartRate,
            "lowest_heart_rate": .restingHeartRate,
            "average_heart_rate": .heartRate,
            "heart_rate": .heartRate,
            "average_hrv": .heartRateVariabilityRMSSD,
            "rmssd": .heartRateVariabilityRMSSD,
            "sdnn": .heartRateVariabilitySDNN,
            "average_breath": .respiratoryRate,
            "breath_average": .respiratoryRate,
            "respiratory_rate": .respiratoryRate,
            // A proposal only, beyond the Oura rule above: another provider's
            // "breathing disturbance index" may be on a different scale, so a
            // human decides before it merges into Oura's series.
            "breathing_disturbance_index": .breathingDisturbanceIndex,
            "spo2": .oxygenSaturation,
            "spo2_percentage": .oxygenSaturation,
            "oxygen_saturation": .oxygenSaturation,
            "temperature_deviation": .skinTemperatureDeviation,
            // A field named `skin_temperature` carries an absolute, not a
            // deviation. Mapping it to the deviation metric labelled ~33 °C
            // readings as if they were "+33 °C away from your baseline".
            "skin_temperature": .skinTemperature,
            "skin_temp_celsius": .skinTemperature,
            "body_temperature": .bodyTemperature,
            "steps": .stepCount,
            "active_calories": .activeEnergyBurned,
            "weight": .bodyMass,
            "fat_ratio": .bodyFatPercentage,
            "fat_free_mass": .leanBodyMass,
            "muscle_mass": .muscleMass,
            "bone_mass": .boneMass,
            "hydration": .bodyWaterPercentage,
            "height": .height,
            "day_strain": .dayStrain,
            "strain": .dayStrain,
            // Bedtimes. Aliases and no shipped rule, deliberately, for two
            // reasons — the second of which will bite anyone who ignores it.
            //
            // First: Oura's and Whoop's own parsers already build `.sleepOnset`
            // from the fields they know, so a rule would promote a second sample
            // for a night that already has one.
            //
            // Second, and the one worth checking before writing any rule here:
            // `bedtime_start` is in `EnvelopeSpec.oura.startDateKeys` (and
            // `start` in Whoop's), and `GenericJSONIngestor` **excludes the date
            // keys from the field sweep** — they are consumed as the document's
            // timestamp instead. So for those two providers the field never
            // reaches promotion at all, and a rule aimed at it would match
            // nothing, silently, forever. A rule is only useful for a provider
            // whose spec does not already spend that field on the date.
            //
            // What these aliases buy meanwhile is the *proposal* — a connector
            // nobody has written a parser for gets its bedtime catalogued and
            // surfaced, and promoting it is then one row in `rules` with
            // `interpretation: .sleepOnsetTimestamp` rather than a parser
            // change. Promotion stays data, never inference.
            //
            // A bare `start` is deliberately **not** here. Whoop's sleep records
            // carry one — and so does every workout, cycle and activity record
            // any provider has ever sent, so the alias would propose a bedtime
            // for all of them. An alias exists to be read by a human deciding
            // whether to write a rule; one that fires on everything tells them
            // nothing and invites a wrong rule.
            "bedtime_start": .sleepOnset,
            "sleep_start": .sleepOnset,
            "sleep_onset": .sleepOnset
        ])
}
