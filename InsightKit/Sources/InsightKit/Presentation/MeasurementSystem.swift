import Foundation

// MARK: - What this file is for

/// Units the reader thinks in, and the arithmetic that gets a stored value into
/// them and back out again.
///
/// ## Why this exists
///
/// Every value this app stores is metric — kilograms, centimetres, metres,
/// kilometres, degrees Celsius, millimoles per litre — and until this file
/// landed that assumption was **unstated and unenforced**. `MetricType.unit`
/// returns a hard-coded `"kg"`; a tape-measure sheet drew a hard-coded `"cm"`
/// beside its text field; the cholesterol sheet drew a hard-coded `"mmol/L"`.
/// None of that is wrong for a reader in the UK. All of it is a **wrong number**
/// for a reader who owns an inch tape or holds a US lipid panel, because
/// nothing anywhere converted and nothing anywhere asked.
///
/// A wrong number is the one failure this app is not allowed to have. So the
/// conversion arithmetic lives here, in the testable core, rather than being
/// re-derived at each field.
///
/// ## Two things this file deliberately does NOT do
///
/// 1. **It does not change what anything currently displays.** Rendering is
///    still metric everywhere; see `MetricValueFormatter.string(_:_:in:)` for
///    the one seam a later display pass can widen. The reason is honesty, not
///    laziness: roughly 2,500 prose strings in this package have their units
///    baked into the sentence ("moving %.2f kg a week", "3.9–10.0 mmol/L is the
///    time-in-range target"), and a headline that flipped to pounds above a
///    paragraph still talking kilograms is a *more* confusing wrong number than
///    the one it replaced. Display converts when the prose converts with it.
/// 2. **It does not guess at compound forms.** `6 ft 1 in` and `13 st 4 lb` are
///    rendering problems with locale-specific splitting rules;
///    `MetricValueFormatter.lengthString` already delegates height to
///    `Measurement.formatted(.measurement(usage: .personHeight))`, which knows
///    them. Everything here is a single scalar, which is what an input field
///    needs and what a round-trip test can pin down.
///
/// ## The traps this encodes
///
/// - **A temperature *difference* does not carry the +32 offset.** Skin
///   temperature deviation is stored as a delta in °C; converting `-0.4` with
///   the absolute formula yields `31.3 °F`, which reads as a fever rather than
///   as a small dip. `.temperatureDifference` is a separate quantity for that
///   reason alone.
/// - **Glucose and cholesterol do not share a mmol/L → mg/dL factor.** They are
///   different molecules: glucose is 180.156 g/mol (factor 18.0156), cholesterol
///   is 386.65 g/mol (factor 38.665). Using one factor for both misreads a
///   cholesterol panel by a bit over twofold, straight into the ASCVD and
///   SCORE2 equations.
/// - **The UK is not metric and is not imperial.** It weighs people in stones,
///   measures waists in inches and heights in feet, and then reports temperature
///   in Celsius and blood chemistry in mmol/L. A two-valued metric/imperial flag
///   gets a British reader's cholesterol wrong. Hence three systems, not two.

// MARK: - Preference and system

/// What the reader asked for. Persisted; `automatic` is the default and defers
/// to the locale.
public enum MeasurementSystemPreference: String, Sendable, CaseIterable, Codable, Identifiable {
    case automatic
    case metric
    case britishHybrid
    case usCustomary

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .automatic: return "Match my region"
        case .metric: return "Metric"
        case .britishHybrid: return "British"
        case .usCustomary: return "US"
        }
    }

    /// One line saying what the choice actually changes, because "British" is
    /// not self-explanatory and getting it wrong is a wrong number.
    public var detail: String {
        switch self {
        case .automatic: return "Follows your phone's region setting."
        case .metric: return "Kilograms, centimetres, kilometres, °C, mmol/L."
        case .britishHybrid: return "Pounds and inches, but °C and mmol/L — the way UK measurements and UK blood tests are actually reported."
        case .usCustomary: return "Pounds, inches, miles, °F, mg/dL."
        }
    }
}

/// The resolved system. Distinct from the preference because `automatic` is not
/// a system — it is a question, and this is the answer.
public enum MeasurementSystem: String, Sendable, CaseIterable, Codable {
    case metric
    case britishHybrid
    case usCustomary

    public static func resolved(_ preference: MeasurementSystemPreference,
                                locale: Locale = .current) -> MeasurementSystem {
        switch preference {
        case .metric: return .metric
        case .britishHybrid: return .britishHybrid
        case .usCustomary: return .usCustomary
        case .automatic: return fromLocale(locale)
        }
    }

    /// Region → system, by parsing the locale identifier rather than by asking
    /// `Locale.measurementSystem`.
    ///
    /// Two reasons, and neither is stylistic. `Locale.measurementSystem` returns
    /// a three-valued `.metric` / `.us` / `.uk` that is *exactly* this mapping
    /// on Darwin — but it is not reliably present in swift-corelibs-foundation,
    /// and this package's whole test suite has to run on Linux (see the note on
    /// `MetricValueFormatter.lengthString`, which is the API that already cost
    /// this repo its Linux build once). String parsing behaves identically on
    /// every platform and can be tested without a device.
    static func fromLocale(_ locale: Locale) -> MeasurementSystem {
        switch region(of: locale) {
        case "GB": return .britishHybrid
        // The three countries that have not adopted SI for everyday use, plus
        // the US territories that follow US practice.
        case "US", "LR", "MM", "PR", "GU", "VI", "AS", "MP": return .usCustomary
        default: return .metric
        }
    }

    /// The region subtag of a locale identifier: `en_GB` → `GB`,
    /// `en-US-POSIX` → `US`, `en` → `""`.
    static func region(of locale: Locale) -> String {
        let parts = locale.identifier
            .split(whereSeparator: { $0 == "_" || $0 == "-" })
            .map(String.init)
        // The region is the first two-letter all-uppercase subtag after the
        // language. A three-letter uppercase subtag is a script or a variant,
        // not a region, and `POSIX` must not be read as one.
        for part in parts.dropFirst()
        where part.count == 2 && part.allSatisfy({ $0.isUppercase && $0.isLetter }) {
            return part
        }
        return ""
    }
}

// MARK: - Quantities

/// The kind of physical thing a number is, for the purpose of choosing a unit.
///
/// Coarser than `MetricType` on purpose: a waist and a chest are the same
/// question. Finer than "length" on purpose: a person's height and a tape
/// measurement round to different things and, in Britain, to different units.
public enum MeasurementQuantity: String, Sendable, CaseIterable {
    /// Body mass. Canonical kilograms.
    case bodyMass
    /// A person's height. Canonical metres.
    case personHeight
    /// A tape measurement — waist, chest, step length. Canonical centimetres.
    case tapeLength
    /// Ground covered. Canonical kilometres.
    case distance
    /// An absolute temperature. Canonical °C.
    case temperature
    /// A temperature *change*. Canonical °C, and **no offset**.
    case temperatureDifference
    /// Drunk volume. Canonical litres.
    case volume
    /// Blood glucose. Canonical mmol/L.
    case bloodGlucose
    /// Blood cholesterol. Canonical mmol/L, and a different molar mass from
    /// glucose.
    case cholesterol
    /// Walking speed. Canonical m/s.
    case speed
    /// The unit is the same everywhere — beats per minute, milliseconds,
    /// percent, kilocalories, grams, milligrams, minutes, counts. Nothing to
    /// convert, and saying so explicitly is what makes the switch below an
    /// audit rather than a lookup table with holes in it.
    case universal
}

// MARK: - A unit, and the arithmetic

/// One display unit: what to print after the number, and the affine map to and
/// from the canonical stored value.
///
/// Both directions come from the same pair of constants, so an input field and
/// a read-out cannot disagree — the asymmetry bug is unavailable by
/// construction rather than by test.
public struct DisplayUnit: Sendable, Equatable {
    /// What to print after the number. May be empty for dimensionless metrics.
    public let abbreviation: String
    /// canonical → display is `value * scale + offset`.
    public let scale: Double
    public let offset: Double

    public init(abbreviation: String, scale: Double = 1, offset: Double = 0) {
        self.abbreviation = abbreviation
        self.scale = scale
        self.offset = offset
    }

    /// Stored value → what the reader sees.
    public func fromCanonical(_ value: Double) -> Double { value * scale + offset }

    /// What the reader typed → what gets stored.
    public func toCanonical(_ value: Double) -> Double { (value - offset) / scale }

    /// True when this unit *is* the stored unit, so a caller can skip both the
    /// arithmetic and the "converted" caveat.
    public var isCanonical: Bool { scale == 1 && offset == 0 }
}

public extension DisplayUnit {
    // Mass. NIST: 1 lb = 0.45359237 kg exactly.
    static let kilograms = DisplayUnit(abbreviation: "kg")
    static let pounds = DisplayUnit(abbreviation: "lb", scale: 1 / 0.45359237)

    // Length. 1 in = 2.54 cm exactly.
    static let metres = DisplayUnit(abbreviation: "m")
    static let centimetres = DisplayUnit(abbreviation: "cm")
    static let inches = DisplayUnit(abbreviation: "in", scale: 1 / 2.54)
    /// Metres → inches, for a height stored in metres.
    static let inchesFromMetres = DisplayUnit(abbreviation: "in", scale: 100 / 2.54)

    // Distance. 1 mile = 1.609344 km exactly.
    static let kilometres = DisplayUnit(abbreviation: "km")
    static let miles = DisplayUnit(abbreviation: "mi", scale: 1 / 1.609344)

    // Temperature. The absolute form carries the offset; the difference form
    // must not, and that is the whole reason there are two of each.
    static let celsius = DisplayUnit(abbreviation: "°C")
    static let fahrenheit = DisplayUnit(abbreviation: "°F", scale: 1.8, offset: 32)
    static let celsiusDifference = DisplayUnit(abbreviation: "°C")
    static let fahrenheitDifference = DisplayUnit(abbreviation: "°F", scale: 1.8)

    // Volume. 1 US fluid ounce = 29.5735295625 mL.
    static let litres = DisplayUnit(abbreviation: "L")
    static let usFluidOunces = DisplayUnit(abbreviation: "fl oz", scale: 1000 / 29.5735295625)

    // Blood chemistry. mmol/L → mg/dL is `molarMass(g/mol) / 10`, so the factor
    // is per-molecule and the two below are not interchangeable.
    static let millimolesPerLitre = DisplayUnit(abbreviation: "mmol/L")
    /// Glucose: 180.156 g/mol.
    static let milligramsPerDecilitreGlucose = DisplayUnit(abbreviation: "mg/dL", scale: 18.0156)
    /// Cholesterol: 386.65 g/mol.
    static let milligramsPerDecilitreCholesterol = DisplayUnit(abbreviation: "mg/dL", scale: 38.665)

    // Speed. 1 m/s = 2.2369362920544 mph.
    static let metresPerSecond = DisplayUnit(abbreviation: "m/s")
    static let milesPerHour = DisplayUnit(abbreviation: "mph", scale: 2.2369362920544)

    /// A unit that is the same in every system — the caller supplies the label
    /// the metric already carries.
    static func universal(_ abbreviation: String) -> DisplayUnit {
        DisplayUnit(abbreviation: abbreviation)
    }
}

// MARK: - Quantity → unit

public extension MeasurementQuantity {

    /// The canonical unit — what the stored `Double` means, whatever the reader
    /// prefers. `nil` label for `.universal`, which has no single answer.
    var canonicalUnit: DisplayUnit? {
        switch self {
        case .bodyMass: return .kilograms
        case .personHeight: return .metres
        case .tapeLength: return .centimetres
        case .distance: return .kilometres
        case .temperature: return .celsius
        case .temperatureDifference: return .celsiusDifference
        case .volume: return .litres
        case .bloodGlucose, .cholesterol: return .millimolesPerLitre
        case .speed: return .metresPerSecond
        case .universal: return nil
        }
    }

    /// The unit to show and to accept in a given system.
    ///
    /// Britain diverges from the US on exactly the two rows that come off a
    /// clinical instrument rather than off a tape: temperature and blood
    /// chemistry. That is not a stylistic choice — a UK lipid result is printed
    /// in mmol/L and a UK thermometer reads Celsius, and offering that reader
    /// mg/dL because they also weigh themselves in stones would invite them to
    /// type a number that is 38.665 times too large into the risk equations.
    func unit(in system: MeasurementSystem) -> DisplayUnit? {
        switch (self, system) {
        case (.universal, _): return nil

        case (.bodyMass, .metric): return .kilograms
        case (.bodyMass, .britishHybrid), (.bodyMass, .usCustomary): return .pounds

        case (.personHeight, .metric): return .metres
        case (.personHeight, .britishHybrid), (.personHeight, .usCustomary): return .inchesFromMetres

        case (.tapeLength, .metric): return .centimetres
        case (.tapeLength, .britishHybrid), (.tapeLength, .usCustomary): return .inches

        case (.distance, .metric): return .kilometres
        case (.distance, .britishHybrid), (.distance, .usCustomary): return .miles

        case (.temperature, .metric), (.temperature, .britishHybrid): return .celsius
        case (.temperature, .usCustomary): return .fahrenheit

        case (.temperatureDifference, .metric),
             (.temperatureDifference, .britishHybrid): return .celsiusDifference
        case (.temperatureDifference, .usCustomary): return .fahrenheitDifference

        case (.volume, .metric), (.volume, .britishHybrid): return .litres
        case (.volume, .usCustomary): return .usFluidOunces

        case (.bloodGlucose, .metric), (.bloodGlucose, .britishHybrid): return .millimolesPerLitre
        case (.bloodGlucose, .usCustomary): return .milligramsPerDecilitreGlucose

        case (.cholesterol, .metric), (.cholesterol, .britishHybrid): return .millimolesPerLitre
        case (.cholesterol, .usCustomary): return .milligramsPerDecilitreCholesterol

        case (.speed, .metric): return .metresPerSecond
        case (.speed, .britishHybrid), (.speed, .usCustomary): return .milesPerHour
        }
    }
}

// MARK: - MetricType → quantity

public extension MetricType {

    /// What kind of physical thing this metric is.
    ///
    /// **Exhaustive, with no `default:`, and that is the point.** A new metric
    /// does not compile until somebody has said out loud whether its stored
    /// number changes shape in another country. `.universal` is a perfectly good
    /// answer for most of them — a heart rate is beats per minute everywhere —
    /// but it has to be *given*, because the failure mode this file exists to
    /// close is a metric that quietly inherited "no conversion needed" from a
    /// `default:` branch nobody read.
    var measurementQuantity: MeasurementQuantity {
        switch self {
        // Beats, milliseconds, percentages, breaths, mmHg, years, and one
        // proprietary 0–21 scale. Identical wherever the reader lives.
        case .heartRate, .restingHeartRate, .walkingHeartRateAverage,
             .heartRateVariabilitySDNN, .heartRateVariabilityRMSSD,
             .respiratoryRate, .oxygenSaturation, .dayStrain,
             .bloodPressureSystolic, .bloodPressureDiastolic,
             .vascularAge, .heartRateRecovery,
             .peripheralPerfusionIndex, .atrialFibrillationBurden:
            return .universal

        // mL/kg·min. Metric on its face, and *nobody* reports VO₂max any other
        // way — there is no imperial cardiorespiratory-fitness unit to convert
        // to. Universal by convention rather than by dimensional analysis, which
        // is why it gets its own case and this comment.
        case .vo2Max:
            return .universal

        case .bodyMass, .leanBodyMass, .muscleMass, .boneMass:
            return .bodyMass
        case .bodyFatPercentage, .bodyWaterPercentage:
            return .universal
        case .height:
            return .personHeight

        case .waistCircumference, .hipCircumference, .chestCircumference,
             .neckCircumference, .shoulderWidth, .thighCircumference,
             .upperArmCircumference:
            return .tapeLength

        // Counts, kilocalories and minutes. A kilocalorie is a kilocalorie; the
        // US food label prints the same number this app stores.
        case .stepCount, .activeEnergyBurned, .exerciseMinutes, .flightsClimbed,
             .physicalEffort, .screenTimeMinutes:
            return .universal

        case .distanceWalkingRunning:
            return .distance

        // Grams, milligrams, micrograms and kilocalories — the units every
        // nutrition label on earth is printed in, including US ones.
        case .dietaryEnergy, .dietaryProtein, .dietaryCarbohydrates, .dietaryFat,
             .dietarySaturatedFat, .dietarySugar, .dietaryFibre, .dietarySodium,
             .dietaryPotassium, .dietaryCaffeine, .dietaryMonounsaturatedFat,
             .dietaryPolyunsaturatedFat, .dietaryCholesterol, .dietaryCalcium,
             .dietaryIron, .dietaryMagnesium, .dietaryZinc, .dietaryVitaminC,
             .dietaryVitaminA, .dietaryVitaminD, .dietaryVitaminB12:
            return .universal

        // Litres drunk. The one nutrition row that *does* change: a US reader
        // counts water in fluid ounces or cups, not in litres.
        case .dietaryWater:
            return .volume

        // Hours, minutes, percentages and a clock time. `sleepOnset` is an
        // offset from local midnight and is rendered as `23:30`; there is no
        // imperial midnight.
        case .sleepDurationHours, .sleepOnset, .sleepEfficiency,
             .sleepDeepMinutes, .sleepRemMinutes, .sleepLatencyMinutes,
             .breathingDisturbanceIndex:
            return .universal

        case .bodyTemperature, .skinTemperature, .basalBodyTemperature:
            return .temperature
        // ⚠️ A delta, not a reading. Sharing a case with the three above would
        // add 32 °F to a number that means "0.3 warmer than your baseline".
        case .skinTemperatureDeviation:
            return .temperatureDifference

        case .bloodGlucose:
            return .bloodGlucose

        // Percentages, all four of them — steadiness, asymmetry, double support
        // — and one true length.
        case .walkingSteadiness, .walkingAsymmetry, .walkingDoubleSupport:
            return .universal
        case .walkingSpeed:
            return .speed
        case .walkingStepLength:
            return .tapeLength

        // Milligrams of drug on board, and A-weighted decibels. Both universal,
        // and dBA emphatically so: the WHO and NIOSH exposure limits this is
        // compared against are written in dBA and in nothing else.
        case .activeMedicationLevel:
            return .universal
        case .environmentalSoundDose, .headphoneSoundDose:
            return .universal
        }
    }

    /// The unit to show for this metric in a given system, or `nil` when the
    /// metric's own `unit` string already is the answer.
    func displayUnit(in system: MeasurementSystem) -> DisplayUnit? {
        measurementQuantity.unit(in: system)
    }

    /// Whether this metric's stored number changes when the reader's system
    /// does. Useful for an audit, and for a caveat that should only appear on a
    /// converted figure.
    var convertsBetweenSystems: Bool { measurementQuantity != .universal }
}

// MARK: - Grounding facts

public extension GroundingKind {

    /// The quantity a grounding fact's `Double` carries, for the sheets that
    /// take one by hand.
    ///
    /// Cholesterol is the reason this exists. Total and HDL are stored in
    /// mmol/L and fed straight into ASCVD and SCORE2; a reader holding a US
    /// lipid panel reads `Total 195` off the page, and before this the sheet
    /// offered them a box labelled `mmol/L` and no way to say otherwise. 195
    /// mmol/L is not a high number, it is not a number a human being can have,
    /// and neither risk equation has any way to tell.
    var measurementQuantity: MeasurementQuantity {
        switch self {
        case .totalCholesterol, .hdlCholesterol:
            return .cholesterol
        // Dates, flags, categorical choices, and two cuff readings in mmHg —
        // the one blood-pressure unit in worldwide clinical use.
        case .dateOfBirth, .biologicalSex, .ascvdRaceGroup, .score2Region,
             .currentSmoker, .hasDiabetes, .onBPMedication, .weightGoal,
             .cuffSystolic, .cuffDiastolic:
            return .universal
        }
    }
}
