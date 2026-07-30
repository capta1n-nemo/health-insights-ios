import Foundation

/// Something a device decided was worth telling you about, as opposed to a
/// measurement it took.
///
/// These are deliberately **not** `MetricType`s. An irregular-rhythm
/// notification has no unit, no baseline, no bucketing rule and no sensible gap
/// interval — forcing it into a numeric series would mean inventing all four.
/// It also needs no z-score: Apple has already made the judgement, and a daily
/// "is anything off today" check that ignores it would be missing the loudest
/// signal available to it.
public enum VitalEventKind: String, Sendable, Codable, CaseIterable {
    case irregularRhythm
    case highHeartRate
    case lowHeartRate
    case lowCardioFitness
    case unsteadyWalking

    /// How much a single one of these should cost a daily vitals score.
    ///
    /// An irregular-rhythm notification is a "speak to someone" event; an
    /// unsteady-walking notification is a slow-burn risk flag, and pricing them
    /// the same would be dishonest in both directions.
    public var severity: Double {
        switch self {
        case .irregularRhythm: return 55
        case .highHeartRate, .lowHeartRate: return 40
        case .lowCardioFitness: return 20
        case .unsteadyWalking: return 25
        }
    }

    public var displayName: String {
        switch self {
        case .irregularRhythm: return "Irregular rhythm"
        case .highHeartRate: return "High heart rate"
        case .lowHeartRate: return "Low heart rate"
        case .lowCardioFitness: return "Low cardio fitness"
        case .unsteadyWalking: return "Unsteady walking"
        }
    }

    /// What to say when one has been recorded. Descriptive, never advice.
    public var note: String {
        switch self {
        case .irregularRhythm:
            return "your watch recorded a rhythm irregular enough to notify you"
        case .highHeartRate:
            return "your heart rate was high while you appeared to be at rest"
        case .lowHeartRate:
            return "your heart rate fell below your notification threshold"
        case .lowCardioFitness:
            return "your cardio fitness is in the low range for your age"
        case .unsteadyWalking:
            return "your walking steadiness was flagged as low"
        }
    }

    /// The HealthKit category identifier this comes from.
    public var healthKitIdentifier: String {
        switch self {
        case .irregularRhythm: return "HKCategoryTypeIdentifierIrregularHeartRhythmEvent"
        case .highHeartRate: return "HKCategoryTypeIdentifierHighHeartRateEvent"
        case .lowHeartRate: return "HKCategoryTypeIdentifierLowHeartRateEvent"
        case .lowCardioFitness: return "HKCategoryTypeIdentifierLowCardioFitnessEvent"
        case .unsteadyWalking: return "HKCategoryTypeIdentifierAppleWalkingSteadinessEvent"
        }
    }

    /// Reverse lookup, so the raw layer can be read without a second table.
    public static func forHealthKitIdentifier(_ identifier: String) -> VitalEventKind? {
        allCases.first { $0.healthKitIdentifier == identifier }
    }
}

public struct VitalEvent: Sendable, Equatable, Identifiable {
    public let id: UUID
    public let kind: VitalEventKind
    public let date: Date
    public let sourceName: String

    public init(id: UUID = UUID(), kind: VitalEventKind, date: Date, sourceName: String) {
        self.id = id
        self.kind = kind
        self.date = date
        self.sourceName = sourceName
    }
}

public extension Array where Element == VitalEvent {
    /// Events recent enough to describe today, most recent first.
    func recent(within window: TimeInterval, of now: Date) -> [VitalEvent] {
        filter { now.timeIntervalSince($0.date) <= window && $0.date <= now }
            .sorted { $0.date > $1.date }
    }
}

/// Turns the untyped imported layer into events.
///
/// Lives here rather than in the app target so it can be tested without
/// HealthKit, and because the one genuinely tricky part is a HealthKit encoding
/// quirk that deserves to be pinned by a test.
public enum VitalEventReader {

    /// HealthKit category samples arrive in the raw layer with a wrinkle: when a
    /// sample's value is `notApplicable` (0) *and* it has a duration, the
    /// importer stores the **duration in minutes** under a `"min"` unit instead
    /// of the enum value. So a raw value of 0 means "an event happened and we
    /// recorded its length as zero", not "no event" — and any positive number
    /// may be either minutes or a category value. Either way the sample's
    /// existence is the signal, which is what this reads.
    public static func events(from raw: [RawMetricSample]) -> [VitalEvent] {
        raw.compactMap { sample in
            guard let kind = VitalEventKind.forHealthKitIdentifier(sample.identifier) else {
                return nil
            }
            return VitalEvent(kind: kind, date: sample.start,
                              sourceName: sample.source.displayName)
        }
        .sorted { $0.date > $1.date }
    }
}
