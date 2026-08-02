import Foundation

/// Turns a stored value into something readable, respecting the metric's real
/// precision.
///
/// Height is the reason this exists: it is stored in metres, and rounding it to
/// a whole number renders 1.85 m as "2 m". Lengths therefore go through
/// `MeasurementFormatter`, which also gets imperial locales `6 ft 1 in` instead
/// of a metric figure they have to convert in their head.
public enum MetricValueFormatter {

    /// Compact form for rows, chart labels and read-outs. Excludes the unit for
    /// metrics whose unit the caller renders separately; height includes it,
    /// because "1.85" alone is ambiguous.
    public static func string(_ value: Double, _ type: MetricType,
                              locale: Locale = .current) -> String {
        switch type {
        case .height:
            return lengthString(metres: value, locale: locale)
        case .bodyMass, .leanBodyMass, .muscleMass, .boneMass,
             .sleepDurationHours, .bodyTemperature, .skinTemperature,
             .skinTemperatureDeviation,
             .dayStrain:
            return String(format: "%.1f", value)
        // Only these two carry their own "%" — matching what callers already
        // expect, so nothing starts rendering "97% %".
        case .bodyFatPercentage, .oxygenSaturation, .sleepEfficiency:
            return String(format: "%.0f%%", value)
        // Minutes read as hours and minutes past an hour; "94 min" makes the
        // reader do the division.
        case .sleepDeepMinutes, .sleepRemMinutes:
            let total = Int(value.rounded())
            return total >= 60 ? "\(total / 60)h \(total % 60)m" : "\(total)m"
        case .stepCount, .activeEnergyBurned:
            return grouped(value)
        // Stored as signed hours from midnight and read as a clock time, which
        // is the only form anybody thinks about a bedtime in. The default
        // branch would render −1.5 as "-2".
        case .sleepOnset:
            return clockString(hoursFromMidnight: value)
        // Two decimals: between two weekly doses the level moves by tenths of a
        // milligram, and the `default:` branch below would round the whole
        // decay curve into a staircase of integers.
        case .activeMedicationLevel:
            return String(format: "%.2f", value)
        default:
            return "\(Int(value.rounded()))"
        }
    }

    /// Whether `string(_:_:)` already includes the unit, so callers don't append
    /// a second one.
    public static func includesUnit(_ type: MetricType) -> Bool {
        switch type {
        case .height, .bodyFatPercentage, .oxygenSaturation, .sleepEfficiency,
             .sleepDeepMinutes, .sleepRemMinutes:
            return true
        default:
            return false
        }
    }

    /// Larger, unambiguous form for a headline figure.
    public static func detailedString(_ value: Double, _ type: MetricType,
                                      locale: Locale = .current) -> String {
        let text = string(value, type, locale: locale)
        guard !includesUnit(type), !type.unit.isEmpty else { return text }
        return "\(text) \(type.unit)"
    }

    /// Height, in whatever units the reader thinks in.
    ///
    /// The `.personHeight` usage is what produces "6 ft 1 in" rather than
    /// "6.07 ft" in imperial locales, and centimetres rather than metres in
    /// metric ones — which is also what keeps 1.85 m from collapsing to "2 m".
    ///
    /// `Measurement.formatted(_:)` is Darwin-only — swift-corelibs-foundation
    /// has no `FormatStyle` for `Measurement`. This one expression was the sole
    /// reason the whole package would not build on Linux, which meant no agent
    /// sandbox could run `swift test` and every logic error had to be found by
    /// pushing and waiting for CI. The device path is untouched; the fallback
    /// exists so the other 400-odd tests can run anywhere.
    private static func lengthString(metres: Double, locale: Locale) -> String {
        #if canImport(Darwin)
        return Measurement(value: metres, unit: UnitLength.meters)
            .formatted(.measurement(width: .abbreviated, usage: .personHeight)
                .locale(locale))
        #else
        // Deliberately not a reimplementation of `.personHeight`: matching
        // Apple's per-locale unit choice and "6 ft 1 in" splitting is not
        // something to guess at, and `MeasurementFormatter` is itself
        // unavailable here. Metric, to the centimetre — enough for a test to
        // assert on, and never shipped to a device.
        _ = locale
        return String(format: "%.0f cm", metres * 100)
        #endif
    }

    /// Signed hours from midnight → "23:30".
    ///
    /// `formatted(date:time:)` is not used because there is no date here: the
    /// value is an offset, and materialising it onto some arbitrary day to get
    /// a `Date` to format would drag in a calendar and a time zone that this
    /// quantity has already been resolved against at ingest.
    static func clockString(hoursFromMidnight value: Double) -> String {
        let minutes = Int((value * 60).rounded())
        // Modulo into a day, twice, because Swift's `%` keeps the sign.
        let wrapped = ((minutes % 1440) + 1440) % 1440
        return String(format: "%02d:%02d", wrapped / 60, wrapped % 60)
    }

    private static func grouped(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: value.rounded()))
            ?? "\(Int(value.rounded()))"
    }
}
