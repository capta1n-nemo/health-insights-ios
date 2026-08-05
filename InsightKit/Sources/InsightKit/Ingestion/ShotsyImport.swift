import Foundation

/// Reading a Shotsy backup.
///
/// Shotsy is a GLP-1 tracker with no API, so the only way in is the JSON backup
/// the user exports and shares to us. This parses **export version 2**, taken
/// from a real file rather than from a description of one — which mattered,
/// because the shape is not what a reasonable person would guess:
///
/// - there is no top-level `medications` or `shots` array. There is `days`, a
///   list of single-key dictionaries whose key is a **unix day timestamp as a
///   string** and whose value maps an entry *kind* to its payload;
/// - most kinds are a single object, but `shots` and `sideEffectRecords` are
///   **arrays**, and `sideEffects` is a name→severity dictionary that duplicates
///   `sideEffectRecords` in a lossier form;
/// - measurements come straight out of HealthKit **in HealthKit's canonical
///   units, not display units**. That is the trap, and it is not a small one:
///   body fat arrives in *parts per million* (331890.03 means 33.19%), dietary
///   energy in *joules* (5460872.8 means 1305 kcal), and every macronutrient in
///   *kilograms* (0.0438 means 43.8 g). Imported naively this app would show a
///   body fat of 331,890% and a day's eating as five million calories.
///
/// Every conversion below is therefore named and tested. `ShotsyUnit` is the
/// single place they live, so a second reader of this format cannot invent a
/// different one.
public enum ShotsyImport {

    // MARK: - What a parse produced

    public struct Dose: Sendable, Equatable {
        public let id: String
        public let takenAt: Date
        public let milligrams: Double
        public let medicationName: String
        public let injectionSite: String?
        public let painLevel: Int?
        /// Shotsy records planned shots too. Only `taken` ones happened.
        public let wasTaken: Bool
    }

    public struct Schedule: Sendable, Equatable {
        public let medicationName: String
        public let milligrams: Double
        public let everyDays: Int
        public let startedOn: Date
        public let deliveryMethod: String
    }

    public struct SideEffect: Sendable, Equatable {
        public let name: String
        public let severity: Int      // Shotsy's own 1–10
        public let date: Date
    }

    public struct Result: Sendable {
        public var doses: [Dose] = []
        public var schedule: Schedule?
        /// Body and nutrition measurements, already converted into this app's
        /// canonical units.
        public var samples: [HealthMetricSample] = []
        public var sideEffects: [SideEffect] = []
        /// Entry kinds seen that nothing here maps, so an import can say what
        /// it ignored rather than dropping it silently.
        public var unmappedKinds: [String] = []
        public var exportedAt: Date?
        public var exportVersion: Int?

        public var isEmpty: Bool {
            doses.isEmpty && samples.isEmpty && sideEffects.isEmpty && schedule == nil
        }
    }

    public enum Failure: Error, Equatable {
        case notJSON
        case notAShotsyExport
        case unsupportedVersion(Int)
    }

    /// Versions this parser has actually been run against a real file for.
    /// A newer export is read on a best-effort basis rather than refused —
    /// refusing would strand a user whose app updated — but the caller is told.
    public static let knownExportVersion = 2

    // MARK: - Parsing

    public static func parse(_ data: Data,
                             source: MetricSource = .shotsy,
                             calendar: Calendar = .current) throws -> Result {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        else { throw Failure.notJSON }
        // `days` and `exportVersion` together are the fingerprint. A JSON file
        // shared from anywhere else must not be silently half-imported.
        guard root["days"] != nil || root["schedules"] != nil
        else { throw Failure.notAShotsyExport }

        var result = Result()
        result.exportVersion = root["exportVersion"] as? Int
        if let exported = root["exportDate"] as? Double {
            result.exportedAt = Date(timeIntervalSince1970: exported)
        }

        if let schedules = root["schedules"] as? [[String: Any]] {
            result.schedule = schedules.compactMap(schedule(from:))
                // The most recently started schedule is the live one.
                .max { $0.startedOn < $1.startedOn }
        }

        var unmapped = Set<String>()
        for day in (root["days"] as? [[String: Any]]) ?? [] {
            for (_, entries) in day {
                guard let entries = entries as? [String: Any] else { continue }
                for (kind, payload) in entries {
                    switch kind {
                    case "shots":
                        result.doses += ((payload as? [[String: Any]]) ?? [])
                            .compactMap(dose(from:))
                    case "sideEffectRecords":
                        result.sideEffects += ((payload as? [[String: Any]]) ?? [])
                            .compactMap(sideEffect(from:))
                    // A lossier duplicate of `sideEffectRecords` — same facts,
                    // no date and no identity. Deliberately ignored rather than
                    // merged, which would double every side effect.
                    case "sideEffects":
                        continue
                    default:
                        guard let payload = payload as? [String: Any] else { continue }
                        if let sample = measurement(kind: kind, from: payload, source: source) {
                            result.samples.append(sample)
                        } else if ShotsyUnit.metric(for: kind) == nil {
                            unmapped.insert(kind)
                        }
                    }
                }
            }
        }

        // A backup is a set, not a stream: the same shot can appear in two
        // exports, and a user who shares twice must not get two injections.
        result.doses = dedupe(result.doses)
        result.samples.sort { $0.start < $1.start }
        result.doses.sort { $0.takenAt < $1.takenAt }
        result.sideEffects.sort { $0.date < $1.date }
        result.unmappedKinds = unmapped.sorted()
        return result
    }

    static func dedupe(_ doses: [Dose]) -> [Dose] {
        var seen = Set<String>()
        return doses.filter { seen.insert($0.id).inserted }
    }

    // MARK: - Rows

    static func dose(from raw: [String: Any]) -> Dose? {
        guard let id = raw["id"] as? String,
              let timestamp = numeric(raw["timestamp"]),
              let milligrams = numeric(raw["dosageStrength"]) else { return nil }
        return Dose(
            id: id,
            takenAt: Date(timeIntervalSince1970: timestamp),
            milligrams: milligrams,
            medicationName: (raw["medicationName"] as? String) ?? "Medication",
            injectionSite: cleanedSite(raw["injectionSite"] as? String),
            painLevel: (raw["painLevel"] as? NSNumber)?.intValue,
            // Absent means taken: Shotsy writes the flag on planned shots, and
            // treating a missing flag as "didn't happen" would silently drop
            // real injections.
            wasTaken: (raw["taken"] as? Bool) ?? true)
    }

    static func schedule(from raw: [String: Any]) -> Schedule? {
        guard let strength = numeric(raw["dosageStrength"]),
              let start = numeric(raw["startDate"]) else { return nil }
        return Schedule(
            medicationName: (raw["medicationName"] as? String) ?? "Medication",
            milligrams: strength,
            everyDays: (raw["recurrenceDays"] as? NSNumber)?.intValue ?? 7,
            startedOn: Date(timeIntervalSince1970: start),
            deliveryMethod: (raw["deliveryMethod"] as? String) ?? "injection")
    }

    static func sideEffect(from raw: [String: Any]) -> SideEffect? {
        guard let name = raw["name"] as? String,
              let date = isoDate(raw["date"] as? String) else { return nil }
        return SideEffect(name: name,
                          severity: (raw["severity"] as? NSNumber)?.intValue ?? 0,
                          date: date)
    }

    static func measurement(kind: String, from raw: [String: Any],
                            source: MetricSource) -> HealthMetricSample? {
        guard let metric = ShotsyUnit.metric(for: kind),
              let value = numeric(raw["value"]),
              let date = isoDate(raw["date"] as? String) else { return nil }
        let converted = ShotsyUnit.convert(value, kind: kind,
                                           declaredUnit: raw["unit"] as? String)
        guard let converted else { return nil }
        return HealthMetricSample(type: metric, value: converted, start: date,
                                  source: source)
    }

    // MARK: - Hygiene

    /// Numbers arrive as `Int` or `Double` depending on whether they happened
    /// to be whole, and occasionally as a string. All three are the same fact.
    static func numeric(_ any: Any?) -> Double? {
        if let number = any as? NSNumber { return number.doubleValue }
        guard let text = any as? String else { return nil }
        // A locale that writes decimals with a comma is a real export, and
        // `Double("2,5")` is nil.
        return Double(text.replacingOccurrences(of: ",", with: "."))
    }

    /// Shotsy writes both `2025-08-22T09:53:01Z` and, for some rows, a
    /// fractional-seconds variant, and one `ISO8601DateFormatter` cannot accept
    /// both — the rule this file has stated correctly since it was written.
    /// `PayloadDate.parse` is that rule, held in one place: stating it three
    /// times is what let `OuraResponseParser` state it wrongly and lose every
    /// Oura bedtime in the reader's history without a single failing test.
    static func isoDate(_ text: String?) -> Date? {
        text.flatMap(PayloadDate.parse)
    }

    /// "  stomach - lower right " → "Stomach - Lower Right".
    static func cleanedSite(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return trimmed
    }
}

/// The unit conversions a Shotsy export needs, in one place.
///
/// Shotsy re-exports HealthKit values in HealthKit's **canonical** units rather
/// than display units. Each of these was read off the user's own file, and each
/// would be a visible absurdity if skipped — see `ShotsyImport`'s note.
public enum ShotsyUnit {

    /// Which canonical metric an entry kind maps to. `nil` for kinds this app
    /// has no home for, which the importer reports rather than discarding
    /// quietly.
    public static func metric(for kind: String) -> MetricType? {
        switch kind {
        case "Weight": return .bodyMass
        case "Body Fat": return .bodyFatPercentage
        case "Lean Mass": return .leanBodyMass
        case "Exercise": return .exerciseMinutes
        case "Calories": return .dietaryEnergy
        case "Protein": return .dietaryProtein
        case "Fat": return .dietaryFat
        case "Carbs": return .dietaryCarbohydrates
        case "Fiber": return .dietaryFibre
        default: return nil
        }
    }

    /// Parts per million to percent. 331890.03 ppm is 33.19 % body fat.
    public static let partsPerMillionToPercent = 1.0 / 10_000
    /// Joules to kilocalories.
    public static let joulesToKilocalories = 1.0 / 4184
    /// Kilograms to grams, for the macronutrients.
    public static let kilogramsToGrams = 1000.0
    /// Seconds to minutes, for exercise.
    public static let secondsToMinutes = 1.0 / 60

    /// Convert a raw value into this app's canonical unit for that metric.
    ///
    /// **Driven by the declared unit where there is one**, because a future
    /// Shotsy release that starts exporting percent rather than ppm would
    /// otherwise be silently divided by ten thousand. The kind is the fallback,
    /// not the authority.
    public static func convert(_ value: Double, kind: String,
                               declaredUnit: String?) -> Double? {
        let unit = declaredUnit?.lowercased()
        switch kind {
        case "Weight", "Lean Mass":
            switch unit {
            case "kg", nil: return value
            case "g": return value / 1000
            case "lb": return value * 0.45359237
            default: return value
            }
        case "Body Fat":
            switch unit {
            case "ppm": return value * partsPerMillionToPercent
            case "%": return value
            // A bare fraction (0.33) is the other honest reading of a body fat
            // with no unit, and it is distinguishable by magnitude: nobody is
            // 0.33 % fat, and nobody is 33 000 % fat.
            case nil where value <= 1: return value * 100
            default: return value
            }
        case "Exercise":
            switch unit {
            case "s", nil: return value * secondsToMinutes
            case "min": return value
            default: return value
            }
        // The macros, all four in kilograms in the file and grams in the app.
        // Same rule as everything above: the declared unit is the authority
        // and the kind is only the fallback, so a Shotsy release that starts
        // writing grams is not silently multiplied by a thousand.
        case "Protein", "Fat", "Carbs", "Fiber":
            switch unit {
            case "kg", nil: return value * kilogramsToGrams
            case "g": return value
            case "mg": return value / 1000
            default: return value
            }
        case "Calories":
            switch unit {
            // Joules is what the file actually carries, and the bare case has
            // to mean joules too: a Shotsy export writes no unit for this kind,
            // and reading an unlabelled 8,780,000 as kilocalories would put a
            // day's eating three orders of magnitude out.
            case "j", nil: return value * joulesToKilocalories
            case "kj": return value * joulesToKilocalories * 1000
            case "kcal", "cal": return value
            default: return value
            }
        default:
            return nil
        }
    }

    /// **Empty as of 2026-08-03, and kept as the record of why.**
    ///
    /// This was the ledger of nutrition kinds the file carried and the app had
    /// no home for — the conversions worked out in advance so a later session
    /// would not rediscover that calories arrive in joules and macros in
    /// kilograms. Every one of them is now a `MetricType` and parsed above, so
    /// the ledger is empty rather than deleted: an empty list says "all mapped"
    /// where a missing constant would say nothing, and the next unmapped kind
    /// has an obvious place to be written down.
    public static let pendingNutritionKinds: [String: String] = [:]
}
