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
             .sleepDurationHours, .bodyTemperature, .skinTemperatureDeviation,
             .dayStrain:
            return String(format: "%.1f", value)
        // Only these two carry their own "%" — matching what callers already
        // expect, so nothing starts rendering "97% %".
        case .bodyFatPercentage, .oxygenSaturation:
            return String(format: "%.0f%%", value)
        case .stepCount, .activeEnergyBurned:
            return grouped(value)
        default:
            return "\(Int(value.rounded()))"
        }
    }

    /// Whether `string(_:_:)` already includes the unit, so callers don't append
    /// a second one.
    public static func includesUnit(_ type: MetricType) -> Bool {
        switch type {
        case .height, .bodyFatPercentage, .oxygenSaturation:
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
    private static func lengthString(metres: Double, locale: Locale) -> String {
        Measurement(value: metres, unit: UnitLength.meters)
            .formatted(.measurement(width: .abbreviated, usage: .personHeight)
                .locale(locale))
    }

    private static func grouped(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: value.rounded()))
            ?? "\(Int(value.rounded()))"
    }
}
