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

    public let match: Match
    public let metric: MetricType
    /// Applied as `value * scale + offset`, for providers reporting a different
    /// unit to the canonical one (metres vs centimetres, °F vs °C).
    public let scale: Double
    public let offset: Double
    /// Restrict to one connector, when the same leaf name means different
    /// things across providers.
    public let sourceID: String?

    public init(match: Match, metric: MetricType, scale: Double = 1, offset: Double = 0, sourceID: String? = nil) {
        self.match = match
        self.metric = metric
        self.scale = scale
        self.offset = offset
        self.sourceID = sourceID
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
            "spo2": .oxygenSaturation,
            "spo2_percentage": .oxygenSaturation,
            "oxygen_saturation": .oxygenSaturation,
            "temperature_deviation": .skinTemperatureDeviation,
            "skin_temperature": .skinTemperatureDeviation,
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
            "strain": .dayStrain
        ])
}
