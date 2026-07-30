import Foundation

/// What a metric-detail screen is *about*.
///
/// Almost always a single metric, but blood pressure is inherently a
/// systolic/diastolic pair and is meaningless split in half. A closed case
/// rather than a generic `.pair(a, b)`: a generic pair would admit nonsense like
/// height-and-step-count, and would still need blood-pressure-specific handling
/// for reading pairing, mean arterial pressure and the AHA categories.
public enum MetricSubject: Hashable, Sendable, Identifiable {
    case single(MetricType)
    case bloodPressure

    /// Normalising initialiser: either half of a cuff reading resolves to the
    /// paired subject, so no caller can accidentally open a half-BP screen.
    public init(metric: MetricType) {
        switch metric {
        case .bloodPressureSystolic, .bloodPressureDiastolic:
            self = .bloodPressure
        default:
            self = .single(metric)
        }
    }

    public var id: String {
        switch self {
        case .single(let metric): return "single.\(metric.rawValue)"
        case .bloodPressure: return "bloodPressure"
        }
    }

    /// Every metric this subject draws on.
    public var metrics: [MetricType] {
        switch self {
        case .single(let metric): return [metric]
        case .bloodPressure: return [.bloodPressureSystolic, .bloodPressureDiastolic]
        }
    }

    /// The metric to use where exactly one is needed (breakdowns, units).
    public var primaryMetric: MetricType {
        switch self {
        case .single(let metric): return metric
        case .bloodPressure: return .bloodPressureSystolic
        }
    }

    public var displayName: String {
        switch self {
        case .single(let metric): return metric.displayName
        case .bloodPressure: return "Blood Pressure"
        }
    }

    public var unit: String { primaryMetric.unit }

    public var presentation: MetricPresentation {
        switch self {
        case .single(let metric): return metric.presentation
        case .bloodPressure: return .discreteBivariate
        }
    }
}
