import Foundation

/// The kinds of user-supplied "ground truth" the insight models can require.
/// These are facts a phone cannot sense and must be entered by the user (or
/// synced from a real medical device), e.g. a cuff blood-pressure reading or a
/// lab cholesterol result.
public enum GroundingKind: String, Codable, Sendable, CaseIterable, Identifiable {
    case dateOfBirth
    case biologicalSex
    case ascvdRaceGroup
    case score2Region
    case totalCholesterol      // mmol/L
    case hdlCholesterol        // mmol/L
    case currentSmoker         // 0/1
    case hasDiabetes           // 0/1
    case onBPMedication        // 0/1
    case cuffSystolic          // mmHg — measured by a real cuff
    case cuffDiastolic         // mmHg — measured by a real cuff

    public var displayName: String {
        switch self {
        case .dateOfBirth: return "Date of birth"
        case .biologicalSex: return "Biological sex"
        case .ascvdRaceGroup: return "Ethnicity (for ASCVD)"
        case .score2Region: return "Risk region (for SCORE2)"
        case .totalCholesterol: return "Total cholesterol"
        case .hdlCholesterol: return "HDL cholesterol"
        case .currentSmoker: return "Current smoker"
        case .hasDiabetes: return "Diabetes"
        case .onBPMedication: return "On blood-pressure medication"
        case .cuffSystolic: return "Cuff blood pressure reading"
        case .cuffDiastolic: return "Cuff blood pressure (diastolic)"
        }
    }

    /// How long a value of this kind remains "fresh" before the app should
    /// re-prompt. `nil` means it never goes stale (e.g. date of birth).
    public var id: String { rawValue }

    /// How a stored value reads back to the user.
    ///
    /// Lives here rather than in the view because every one of these is a
    /// `Double` on the way in and several are not numbers on the way out — a
    /// date of birth is an epoch, a sex is 0 or 1, a smoker is a flag. A view
    /// printing the raw value would show "802915200" where it meant an age, and
    /// nothing would catch it. Exhaustive, so a new kind has to say.
    ///
    /// Date of birth reads as an age rather than a date deliberately: it needs
    /// no date-formatting API (several of which are Darwin-only and would take
    /// InsightKit off Linux), and the age is the thing every model actually
    /// uses.
    public func formatted(_ value: Double, asOf now: Date = Date()) -> String {
        switch self {
        case .dateOfBirth:
            let born = Date(timeIntervalSince1970: value)
            let years = now.timeIntervalSince(born) / (365.2425 * 24 * 3600)
            guard years > 0 else { return "—" }
            return "\(Int(years.rounded(.down))) years old"
        case .biologicalSex:
            return value == 0 ? "Male" : "Female"
        case .ascvdRaceGroup:
            return value == 1 ? "Black / African American" : "White / Other"
        case .score2Region:
            switch value {
            case 0: return "Low risk region"
            case 2: return "High risk region"
            case 3: return "Very high risk region"
            default: return "Moderate risk region"
            }
        case .totalCholesterol, .hdlCholesterol:
            return String(format: "%.1f mmol/L", value)
        case .currentSmoker, .hasDiabetes, .onBPMedication:
            return value >= 0.5 ? "Yes" : "No"
        case .cuffSystolic, .cuffDiastolic:
            return String(format: "%.0f mmHg", value)
        }
    }

    public var freshness: TimeInterval? {
        switch self {
        case .dateOfBirth, .biologicalSex, .ascvdRaceGroup, .score2Region:
            return nil
        case .totalCholesterol, .hdlCholesterol:
            // Six months. An aged lab is still the best number available and
            // keeps being used — what it stops buying is high confidence, and a
            // prompt to repeat it. See `CardiovascularRiskInsight`.
            return 180 * 24 * 3600
        case .currentSmoker, .hasDiabetes, .onBPMedication:
            return 180 * 24 * 3600            // six months
        case .cuffSystolic, .cuffDiastolic:
            return 14 * 24 * 3600             // two weeks — BP is dynamic
        }
    }
}

/// A single grounding fact, with the timestamp it was captured. Numeric-only:
/// enums/dates are encoded as `Double` (see `UserHealthProfile`), keeping the
/// pure core free of platform storage concerns.
public struct GroundingInput: Codable, Sendable, Hashable, Identifiable {
    public let id: UUID
    public let kind: GroundingKind
    public let value: Double
    public let recordedAt: Date

    public init(id: UUID = UUID(), kind: GroundingKind, value: Double, recordedAt: Date) {
        self.id = id
        self.kind = kind
        self.value = value
        self.recordedAt = recordedAt
    }

    /// Whether this value is still fresh relative to `now`.
    public func isFresh(asOf now: Date = Date()) -> Bool {
        guard let window = kind.freshness else { return true }
        return now.timeIntervalSince(recordedAt) <= window
    }
}

/// A snapshot of everything the user has told us (their most recent value for
/// each grounding kind), plus convenience accessors used by the insight models.
public struct UserHealthProfile: Codable, Sendable, Equatable {
    /// Most recent grounding input per kind.
    public var inputs: [GroundingKind: GroundingInput]

    public init(inputs: [GroundingKind: GroundingInput] = [:]) {
        self.inputs = inputs
    }

    public mutating func set(_ input: GroundingInput) {
        inputs[input.kind] = input
    }

    public func value(_ kind: GroundingKind) -> Double? { inputs[kind]?.value }
    public func input(_ kind: GroundingKind) -> GroundingInput? { inputs[kind] }

    // Typed convenience accessors -------------------------------------------------

    public func age(asOf now: Date = Date()) -> Double? {
        guard let dobEpoch = value(.dateOfBirth) else { return nil }
        let dob = Date(timeIntervalSince1970: dobEpoch)
        let years = now.timeIntervalSince(dob) / (365.2425 * 24 * 3600)
        return years > 0 ? years : nil
    }

    public var sex: BiologicalSex? {
        guard let raw = value(.biologicalSex) else { return nil }
        return raw == 0 ? .male : .female
    }

    public var raceGroup: ASCVDRaceGroup {
        guard let raw = value(.ascvdRaceGroup) else { return .whiteOrOther }
        return raw == 1 ? .africanAmerican : .whiteOrOther
    }

    public var score2Region: SCORE2RiskRegion {
        switch value(.score2Region) {
        case 0: return .low
        case 2: return .high
        case 3: return .veryHigh
        default: return .moderate
        }
    }

    public var isSmoker: Bool { (value(.currentSmoker) ?? 0) >= 0.5 }
    public var hasDiabetes: Bool { (value(.hasDiabetes) ?? 0) >= 0.5 }
    public var onBPMedication: Bool { (value(.onBPMedication) ?? 0) >= 0.5 }

    public var totalCholesterol: Double? { value(.totalCholesterol) }
    public var hdlCholesterol: Double? { value(.hdlCholesterol) }
    public var cuffSystolic: Double? { value(.cuffSystolic) }
    public var cuffDiastolic: Double? { value(.cuffDiastolic) }
}
