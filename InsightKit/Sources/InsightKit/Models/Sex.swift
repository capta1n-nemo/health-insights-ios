import Foundation

/// Biological sex, required by the validated cardiovascular risk equations
/// (SCORE2 and the ASCVD Pooled Cohort Equations are both sex-specific).
public enum BiologicalSex: String, Codable, Sendable, CaseIterable {
    case male
    case female

    public var displayName: String {
        switch self {
        case .male: return "Male"
        case .female: return "Female"
        }
    }
}

/// Race/ethnicity grouping used *only* by the ASCVD Pooled Cohort Equations,
/// which publish separate coefficients for these groups. SCORE2 does not use it.
///
/// This is a clinical-model input, not an identity field; the UI explains why it
/// is requested and it is optional (defaults to `.whiteOrOther`, matching the
/// ACC/AHA guidance to use the White/Other coefficients when unsure).
public enum ASCVDRaceGroup: String, Codable, Sendable, CaseIterable {
    case whiteOrOther
    case africanAmerican

    public var displayName: String {
        switch self {
        case .whiteOrOther: return "White / Other"
        case .africanAmerican: return "Black / African American"
        }
    }
}

/// The calibrated risk region for SCORE2. The 2021 ESC guidelines calibrate the
/// core model to four regions; the user (or their locale) selects one.
public enum SCORE2RiskRegion: String, Codable, Sendable, CaseIterable {
    case low
    case moderate
    case high
    case veryHigh

    public var displayName: String {
        switch self {
        case .low: return "Low risk region"
        case .moderate: return "Moderate risk region"
        case .high: return "High risk region"
        case .veryHigh: return "Very high risk region"
        }
    }
}
