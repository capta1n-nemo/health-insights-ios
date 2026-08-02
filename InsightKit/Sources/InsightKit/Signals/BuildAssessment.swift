import Foundation

/// Where a body's mass actually sits, from circumferences rather than from the
/// scale alone.
///
/// Captured by tape, camera or LiDAR — the capture is device-only (ARKit) and
/// deliberately not modelled here. Everything that *judges* these numbers is in
/// this file, so it is testable in a sandbox that has no camera.
public struct BodyDimensions: Sendable, Equatable, Codable {

    public enum Source: String, Sendable, Codable { case lidar, camera, tape }

    public let capturedAt: Date
    public let heightMetres: Double
    public let waistCentimetres: Double
    public let hipCentimetres: Double?
    public let chestCentimetres: Double?
    public let neckCentimetres: Double?
    public let shoulderCentimetres: Double?
    public let source: Source

    public init(capturedAt: Date, heightMetres: Double, waistCentimetres: Double,
                hipCentimetres: Double? = nil, chestCentimetres: Double? = nil,
                neckCentimetres: Double? = nil, shoulderCentimetres: Double? = nil,
                source: Source) {
        self.capturedAt = capturedAt
        self.heightMetres = heightMetres
        self.waistCentimetres = waistCentimetres
        self.hipCentimetres = hipCentimetres
        self.chestCentimetres = chestCentimetres
        self.neckCentimetres = neckCentimetres
        self.shoulderCentimetres = shoulderCentimetres
        self.source = source
    }

    /// Waist as a share of height — the single most portable measure of central
    /// adiposity, and the one with a published action line that needs no age,
    /// sex or population table: **keep your waist under half your height**.
    public var waistToHeight: Double { waistCentimetres / (heightMetres * 100) }

    public var waistToHip: Double? { hipCentimetres.map { waistCentimetres / $0 } }

    /// Shoulders relative to waist — the "V" ratio somatotype reads for
    /// mesomorphy.
    public var shoulderToWaist: Double? { shoulderCentimetres.map { $0 / waistCentimetres } }
}

/// What a body's dimensions say that its BMI cannot.
public struct BuildAssessment: Sendable, Equatable {
    public let bmi: Double
    public let bmiCategory: String
    /// Relative Fat Mass — Woolcott & Bergman (2018), validated against DXA
    /// across ~12,000 NHANES adults and materially more accurate than BMI,
    /// especially for the muscular and the tall.
    public let relativeFatMass: Double
    public let waistToHeight: Double
    /// True when BMI calls someone obese and their central adiposity does not
    /// agree — the case the brief was written for.
    public let isNonStandardBuild: Bool
    /// One sentence the card can print.
    public let explanation: String
}

public enum BuildAssessmentModel {

    /// "Keep your waist to less than half your height." A single published
    /// threshold, no age or sex table, and the reason waist-to-height is the
    /// measure worth carrying: it is the one anthropometric line a reader can
    /// check on themselves with a piece of string.
    public static let waistToHeightActionLine = 0.5

    /// The BMI at which the WHO calls someone obese, and the only place this
    /// module disagrees with it.
    public static let obeseBMI = 30.0

    /// Relative Fat Mass, in percent.
    ///
    ///     men:   64 − 20 × (height / waist)
    ///     women: 76 − 20 × (height / waist)
    ///
    /// Both lengths in the same unit; the ratio is what matters.
    public static func relativeFatMass(heightMetres: Double, waistCentimetres: Double,
                                       sex: BiologicalSex) -> Double? {
        guard heightMetres > 0.5, waistCentimetres > 20 else { return nil }
        let ratio = (heightMetres * 100) / waistCentimetres
        let base = sex == .male ? 64.0 : 76.0
        return base - 20 * ratio
    }

    public static func evaluate(dimensions: BodyDimensions, weightKg: Double,
                                sex: BiologicalSex) -> BuildAssessment? {
        guard dimensions.heightMetres > 0.5, weightKg > 0,
              let rfm = relativeFatMass(heightMetres: dimensions.heightMetres,
                                        waistCentimetres: dimensions.waistCentimetres,
                                        sex: sex) else { return nil }
        let bmi = weightKg / (dimensions.heightMetres * dimensions.heightMetres)
        let whtr = dimensions.waistToHeight
        let category = BodyCompositionInsight.bmiCategory(bmi)
        let nonStandard = bmi >= obeseBMI && whtr < waistToHeightActionLine

        let explanation: String
        if nonStandard {
            explanation = String(
                format: "Your BMI of %.1f reads as obese, but BMI only knows your "
                    + "height and your weight — it cannot tell muscle from fat. Your "
                    + "waist is %.0f%% of your height, under the half-your-height line, "
                    + "so the mass isn't sitting around your middle. Body fat is "
                    + "estimated at %.0f%% from your waist and height instead.",
                bmi, whtr * 100, rfm)
        } else if whtr >= waistToHeightActionLine {
            explanation = String(
                format: "Your waist is %.0f%% of your height. Keeping it under half "
                    + "is the published line, and it tracks health risk better than "
                    + "BMI does. Body fat estimated at %.0f%% from waist and height.",
                whtr * 100, rfm)
        } else {
            explanation = String(
                format: "Waist %.0f%% of height, inside the under-half line. Body fat "
                    + "estimated at %.0f%% from waist and height.", whtr * 100, rfm)
        }

        return BuildAssessment(bmi: bmi, bmiCategory: category, relativeFatMass: rfm,
                               waistToHeight: whtr, isNonStandardBuild: nonStandard,
                               explanation: explanation)
    }
}
