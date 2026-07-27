import Foundation

/// Broad classes of recreational (and everyday) substances a user can log. The
/// point is harm-reduction and self-knowledge: correlate a person's *own*
/// choices with their *own* body signals — never judgement, never advice on use.
///
/// `acuteCardiacLoad` is a rough relative weight (0–1) for the acute
/// cardiovascular strain a typical dose places on the heart, used only to build
/// a personal "recent load" indicator. It is an ordering heuristic grounded in
/// the general pharmacology (sympathomimetic stimulants strain the heart most),
/// not a dose-specific clinical figure.
public enum SubstanceClass: String, Codable, Sendable, CaseIterable, Identifiable {
    case stimulant      // cocaine, amphetamine, etc. — strong sympathomimetic
    case mdma           // empathogen, strongly sympathomimetic + thermoregulatory
    case alcohol
    case nicotine
    case cannabis
    case caffeine
    case psychedelic    // LSD, psilocybin — modest cardiovascular effect
    case dissociative   // ketamine — variable
    case depressant     // benzodiazepines, opioids (respiratory risk)
    case other

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .stimulant: return "Stimulant"
        case .mdma: return "MDMA"
        case .alcohol: return "Alcohol"
        case .nicotine: return "Nicotine"
        case .cannabis: return "Cannabis"
        case .caffeine: return "Caffeine"
        case .psychedelic: return "Psychedelic"
        case .dissociative: return "Dissociative"
        case .depressant: return "Depressant"
        case .other: return "Other"
        }
    }

    /// Relative acute cardiovascular strain weight (0–1).
    public var acuteCardiacLoad: Double {
        switch self {
        case .stimulant: return 1.0
        case .mdma: return 0.9
        case .nicotine: return 0.5
        case .alcohol: return 0.5
        case .cannabis: return 0.4
        case .dissociative: return 0.4
        case .caffeine: return 0.25
        case .psychedelic: return 0.2
        case .depressant: return 0.2
        case .other: return 0.4
        }
    }
}

/// A single logged use event. Amount is intentionally coarse and optional — the
/// app is about physiological response, not dosing.
public struct SubstanceEvent: Codable, Sendable, Identifiable, Hashable {
    public let id: UUID
    public let substance: SubstanceClass
    public let timestamp: Date
    /// Optional free number of "units"/servings for the user's own reference.
    public let units: Double?
    public let note: String?

    public init(id: UUID = UUID(), substance: SubstanceClass, timestamp: Date,
                units: Double? = nil, note: String? = nil) {
        self.id = id
        self.substance = substance
        self.timestamp = timestamp
        self.units = units
        self.note = note
    }
}
