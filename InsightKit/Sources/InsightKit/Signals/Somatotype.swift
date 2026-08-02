import Foundation

/// The shape of a body, as three components rather than one label.
///
/// **Why not a single word.** Heath–Carter, the published method, needs
/// skinfold calipers and bone breadths this app will never have, and it does
/// not produce a label either — it produces three ratings, because real bodies
/// are mixtures. An app that printed "you are a mesomorph" from a smart scale
/// would be claiming both a measurement it did not take and a crispness the
/// method itself rejects.
///
/// So this reports the three components on Heath–Carter's own 1–7 scale,
/// estimated from what the app *does* hold, and says what it estimated them
/// from. The dominant one is offered as a convenience, never as a verdict.
public struct Somatotype: Sendable, Equatable, Codable {

    public enum Component: String, Sendable, Codable, CaseIterable, Identifiable {
        case endomorph, mesomorph, ectomorph
        public var id: String { rawValue }

        public var displayName: String {
            switch self {
            case .endomorph: return "Endomorph"
            case .mesomorph: return "Mesomorph"
            case .ectomorph: return "Ectomorph"
            }
        }

        /// What it means, in the reader's terms — no flattery, no diagnosis.
        public var meaning: String {
            switch self {
            case .endomorph:
                return "Rounder build that stores fat readily. Tends to gain weight easily and lose it slowly, and responds well to keeping protein high while losing."
            case .mesomorph:
                return "Naturally sturdy, muscular build. Tends to gain and hold muscle readily, and to change shape faster than the scale suggests."
            case .ectomorph:
                return "Lean, linear build with narrow frame. Tends to stay light and find muscle harder to add, so gains come from eating enough as much as from training."
            }
        }
    }

    public enum Basis: String, Sendable, Codable {
        /// Derived from body fat, lean mass and the reader's proportions.
        case estimatedFromComposition
        /// The reader told us, and their word wins.
        case userDeclared
    }

    /// All three on the Heath–Carter 1–7 scale.
    public let endomorphy: Double
    public let mesomorphy: Double
    public let ectomorphy: Double
    public let basis: Basis
    public let confidence: InsightConfidence

    public var dominant: Component {
        if endomorphy >= mesomorphy && endomorphy >= ectomorphy { return .endomorph }
        if mesomorphy >= ectomorphy { return .mesomorph }
        return .ectomorph
    }

    public func rating(_ component: Component) -> Double {
        switch component {
        case .endomorph: return endomorphy
        case .mesomorph: return mesomorphy
        case .ectomorph: return ectomorphy
        }
    }

    /// Whether two components are close enough that naming one is overstating
    /// it — which is most people, and saying so is the honest part.
    public var isBalanced: Bool {
        let sorted = [endomorphy, mesomorphy, ectomorphy].sorted(by: >)
        return sorted[0] - sorted[1] < 0.75
    }
}

public enum SomatotypeModel {

    /// Ponderal index — height over the cube root of weight. The classical
    /// input to ectomorphy and the one that needs no body-composition scale.
    public static func ponderalIndex(heightMetres: Double, weightKg: Double) -> Double? {
        guard heightMetres > 0.5, weightKg > 0 else { return nil }
        return heightMetres * 100 / pow(weightKg, 1.0 / 3.0)
    }

    /// Fat-free mass index — lean mass over height squared. The standard
    /// measure of musculoskeletal robustness, and what mesomorphy rests on
    /// here. Typical adult men sit near 18–20, women near 15–17.
    public static func fatFreeMassIndex(leanMassKg: Double, heightMetres: Double) -> Double? {
        guard heightMetres > 0.5, leanMassKg > 0 else { return nil }
        return leanMassKg / (heightMetres * heightMetres)
    }

    /// Estimate the three components.
    ///
    /// Each is anchored on something published and then mapped onto 1–7:
    ///
    /// - **endomorphy** from body fat against the age-and-sex healthy band the
    ///   dial already uses, so the two cannot disagree about what "high body
    ///   fat" is;
    /// - **mesomorphy** from fat-free mass index against typical adult values,
    ///   lifted where the shoulders are broad relative to the waist;
    /// - **ectomorphy** from the ponderal index, the classical definition.
    ///
    /// `nil` without a height and a weight — with neither there is no shape to
    /// describe, and guessing one from a body fat alone would be inventing.
    public static func estimate(bodyFatPercentage: Double?,
                                leanMassKg: Double?,
                                weightKg: Double,
                                heightMetres: Double,
                                dimensions: BodyDimensions?,
                                age: Double,
                                sex: BiologicalSex) -> Somatotype? {
        guard let ponderal = ponderalIndex(heightMetres: heightMetres, weightKg: weightKg)
        else { return nil }

        // Endomorphy: the healthy band's midpoint rates 2.5, and each 5 points
        // of body fat above it adds roughly one rating.
        let band = BodyCompositionInsight.healthyBodyFatRange(age: age, sex: sex)
        let bandMiddle = (band.lower + band.upper) / 2
        let endomorphy = bodyFatPercentage.map {
            clampRating(2.5 + ($0 - bandMiddle) / 5)
        }

        // Mesomorphy: typical FFMI rates 4; each 1.5 units moves it a point.
        let typicalFFMI = sex == .male ? 19.0 : 16.0
        var mesomorphy = (leanMassKg.flatMap {
            fatFreeMassIndex(leanMassKg: $0, heightMetres: heightMetres)
        }).map { clampRating(4 + ($0 - typicalFFMI) / 1.5) }
        // Broad shoulders relative to the waist is the frame half of the same
        // judgement, and it is the one thing a tape adds that a scale cannot.
        if let ratio = dimensions?.shoulderToWaist, let current = mesomorphy {
            mesomorphy = clampRating(current + (ratio - 1.4) * 2)
        }

        // Ectomorphy: the classical mapping, where a ponderal index of about
        // 40 is the middle of the range.
        let ectomorphy = clampRating((ponderal - 38.5) * 0.9 + 2.5)

        // Confidence follows what was actually measured rather than derived.
        let measured = [bodyFatPercentage != nil, leanMassKg != nil,
                        dimensions != nil].filter { $0 }.count
        let confidence: InsightConfidence = measured >= 2 ? .moderate : .low

        return Somatotype(
            endomorphy: endomorphy ?? 2.5,
            mesomorphy: mesomorphy ?? 4,
            ectomorphy: ectomorphy,
            basis: .estimatedFromComposition,
            confidence: confidence)
    }

    static func clampRating(_ x: Double) -> Double { Swift.max(1, Swift.min(7, x)) }
}
