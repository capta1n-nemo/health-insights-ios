import Foundation

/// A symptom the reader has, graded by how strongly.
///
/// ## Why this is a domain rather than a metric
///
/// A `MetricType` is one measured series with a unit, a plausible range and a
/// baseline. A symptom is none of those: it is an **event** — it happened, on a
/// day, at a strength somebody chose — and it is absent far more often than it
/// is present, which is not what "no reading" means for a series. Modelled as a
/// metric, a week with no headache would be a week of missing data rather than
/// a week of not having one, and every baseline built on it would be wrong.
///
/// ## Why now
///
/// **The data has been arriving for months and nothing read it.**
/// `HealthKitService.otherCategoryIdentifiers` already pulls fourteen of Apple's
/// symptom categories into the raw catalogue, where they sit unmodelled — the
/// state `progress.md` describes as "already being scraped into the raw pile and
/// read by nothing". Promoting them costs no new permission, no new connector
/// and no new capture: the reader's phone has been collecting this all along.
///
/// It is also the prerequisite for the symptom radar. That card grades *itself*
/// against the reader's own symptom tags, and the best published validation of
/// the approach is 43% sensitivity at 95% specificity — so it can only be built
/// once there is something to grade against.
public enum SymptomType: String, Sendable, CaseIterable, Codable, Identifiable {
    case nausea
    case headache
    case fatigue
    case dizziness
    case fever
    case coughing
    case shortnessOfBreath
    case chestTightnessOrPain
    case abdominalCramps
    case bloating
    case heartburn
    case sleepChanges
    case moodChanges
    case hotFlashes
    // Added 2026-08-04: the two most characteristic GLP-1 GI reactions were
    // unrepresentable, so the radar's dose downgrade could never fire for the
    // classic dose reaction — a reader who vomited for two days after a step-up
    // got the full illness lead instead of the neutral one naming the dose.
    case vomiting
    case diarrhea

    public var id: String { rawValue }

    /// Apple's identifier for this symptom, which is how it arrives.
    public var healthKitIdentifier: String {
        "HKCategoryTypeIdentifier" + rawValue.prefix(1).uppercased() + rawValue.dropFirst()
    }

    /// Every symptom keyed by the identifier it arrives under, so promotion from
    /// the raw catalogue is a dictionary lookup rather than a switch somebody
    /// has to keep in step.
    public static let byHealthKitIdentifier: [String: SymptomType] = Dictionary(
        uniqueKeysWithValues: allCases.map { ($0.healthKitIdentifier, $0) })

    public var title: String {
        switch self {
        case .nausea: return "Nausea"
        case .headache: return "Headache"
        case .fatigue: return "Fatigue"
        case .dizziness: return "Dizziness"
        case .fever: return "Fever"
        case .coughing: return "Coughing"
        case .shortnessOfBreath: return "Shortness of breath"
        case .chestTightnessOrPain: return "Chest tightness or pain"
        case .abdominalCramps: return "Abdominal cramps"
        case .bloating: return "Bloating"
        case .heartburn: return "Heartburn"
        case .sleepChanges: return "Sleep changes"
        case .moodChanges: return "Mood changes"
        case .hotFlashes: return "Hot flushes"
        case .vomiting: return "Vomiting"
        // The raw value keeps Apple's US spelling — it derives the HealthKit
        // identifier — while the title follows this app's British copy, the
        // same split `hotFlashes` / "Hot flushes" already makes.
        case .diarrhea: return "Diarrhoea"
        }
    }

    /// Whether this symptom is a recognised GLP-1 adverse effect.
    ///
    /// **Load-bearing for the symptom radar, which must never call a dose
    /// reaction an infection.** The gastrointestinal cluster is the commonest
    /// reason a reader on a GLP-1 feels unwell in the days after a dose, and a
    /// card that reads that as an early illness signal would be alarming
    /// somebody about their own prescription working as labelled.
    ///
    /// This flags a symptom as *explicable* by medication, never as *caused* by
    /// it — the reader can have a stomach bug while on tirzepatide. What it
    /// buys is the ability to name the likelier explanation alongside the
    /// finding rather than instead of it.
    ///
    /// Vomiting and diarrhoea sit here rather than in `isInfectionLike` even
    /// though they are also gastroenteritis hallmarks: the clusters must stay
    /// disjoint (`SymptomTests.testTheTwoClustersDoNotOverlap`), and the
    /// dose-window copy already carries the ambiguity out loud — "a stomach
    /// bug can look identical, so if this worsens or lingers, believe your
    /// body over this card."
    public var isCommonGLP1Effect: Bool {
        switch self {
        case .nausea, .abdominalCramps, .bloating, .heartburn, .fatigue,
             .vomiting, .diarrhea: return true
        case .headache, .dizziness, .fever, .coughing, .shortnessOfBreath,
             .chestTightnessOrPain, .sleepChanges, .moodChanges, .hotFlashes: return false
        }
    }

    /// Symptoms that an infection typically presents with.
    ///
    /// Deliberately narrow. Fatigue is the commonest illness symptom there is
    /// and is *not* here, because it is also the commonest everything-else
    /// symptom — a signal that fires on every bad night is not a signal.
    public var isInfectionLike: Bool {
        switch self {
        case .fever, .coughing, .shortnessOfBreath: return true
        case .nausea, .headache, .fatigue, .dizziness, .chestTightnessOrPain,
             .abdominalCramps, .bloating, .heartburn, .sleepChanges,
             .moodChanges, .hotFlashes, .vomiting, .diarrhea: return false
        }
    }
}

/// How strongly, on Apple's own scale.
///
/// Kept as Apple grades it rather than rescaled to a 1–10 like the side-effect
/// log. Two reasons: the reader chose one of these words in the Health app and
/// a rescale would put a number in their mouth, and `notPresent` is a real,
/// useful answer — "I checked and I did not have this" is different from
/// silence, and only the reader can say it.
public enum SymptomSeverity: Int, Sendable, CaseIterable, Codable, Comparable {
    case unspecified = 0
    case notPresent = 1
    case mild = 2
    case moderate = 3
    case severe = 4

    public static func < (a: SymptomSeverity, b: SymptomSeverity) -> Bool {
        a.rawValue < b.rawValue
    }

    public var title: String {
        switch self {
        case .unspecified: return "Present"
        case .notPresent: return "Not present"
        case .mild: return "Mild"
        case .moderate: return "Moderate"
        case .severe: return "Severe"
        }
    }

    /// Whether the reader actually had it. `notPresent` is a recorded absence
    /// and must never be counted as an occurrence — which is the whole reason
    /// this is not a Bool.
    public var isPresent: Bool {
        switch self {
        case .notPresent: return false
        case .unspecified, .mild, .moderate, .severe: return true
        }
    }
}

/// One symptom, on one day, at one strength.
public struct SymptomEvent: Sendable, Codable, Hashable, Identifiable {
    public let id: UUID
    public let type: SymptomType
    public let severity: SymptomSeverity
    public let date: Date
    public let source: MetricSource

    public init(id: UUID = UUID(), type: SymptomType, severity: SymptomSeverity,
                date: Date, source: MetricSource) {
        self.id = id
        self.type = type
        self.severity = severity
        self.date = date
        self.source = source
    }
}

public enum SymptomPromotion {

    /// Lift symptom records out of the raw catalogue into first-class events.
    ///
    /// The raw catalogue is where anything imported-but-unmodelled lands, and
    /// these have been landing there since the category identifiers were added.
    /// Promotion reads rather than moves: the raw rows stay exactly where they
    /// are, so nothing that already displays them changes and a promotion bug
    /// cannot lose data.
    ///
    /// A row whose value is not one of Apple's severity constants is dropped
    /// rather than guessed at — `unspecified` already means "present, strength
    /// not stated", so there is no honest place to put an unrecognised number.
    public static func events(from raw: [RawMetricSample]) -> [SymptomEvent] {
        raw.compactMap { sample in
            guard let type = SymptomType.byHealthKitIdentifier[sample.identifier] else { return nil }
            guard let number = sample.numericValue,
                  let severity = SymptomSeverity(rawValue: Int(number)) else { return nil }
            return SymptomEvent(type: type, severity: severity,
                                date: sample.start, source: sample.source)
        }
        .sorted { $0.date > $1.date }
    }
}
