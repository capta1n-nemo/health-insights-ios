import Foundation

/// Published intakes for the eleven promoted micronutrients, **resolved against
/// the reader's own sex and age**.
///
/// This is why `MetricType.referenceRange` returns nil for all eleven: a
/// reference range is a fixed band with no reader in scope, and almost every
/// figure here moves with sex, several with age, and iron by more than twofold.
/// A single band would be wrong for half its readers in the direction that
/// tells someone deficient they are fine. The profile is in scope here, so the
/// band can be right.
///
/// **Two different quantities, and conflating them is the classic error.** The
/// RDA is a floor — the intake that meets the needs of nearly everyone. The
/// tolerable upper intake is a ceiling from a different body of evidence
/// entirely, and for several of these it is the figure that actually matters.
/// They are not the ends of one band and are never drawn as one.
///
/// Every figure is from the US Institute of Medicine Dietary Reference Intakes
/// as published by the NIH Office of Dietary Supplements, and each row states
/// that rather than leaving the reader to trust an unattributed number.
public enum MicronutrientTargets {

    public struct Target: Sendable, Equatable {
        /// Recommended daily intake — a floor, in the metric's own unit.
        public let recommended: Double
        /// Tolerable upper intake, where one is established. `nil` means no
        /// upper limit has been set, **not** that more is harmless.
        public let upperLimit: Double?
        /// Named, always. A number a reader cannot trace is a number they have
        /// to take on faith, which is what this app refuses to ask for.
        public let provenance: String

        public init(recommended: Double, upperLimit: Double?, provenance: String) {
            self.recommended = recommended
            self.upperLimit = upperLimit
            self.provenance = provenance
        }
    }

    /// How a day's intake sits against the target.
    public enum Standing: Sendable, Equatable {
        case below, met, aboveUpperLimit
    }

    private static let odsIOM = "US Institute of Medicine Dietary Reference Intakes, via NIH Office of Dietary Supplements."

    /// The target for a metric, or nil where no published figure applies.
    ///
    /// `age` is optional because several figures need it and several do not —
    /// returning nil when a needed one is missing is the honest answer, rather
    /// than quietly picking the young-adult row for a reader of seventy.
    public static func target(for metric: MetricType,
                              sex: BiologicalSex?,
                              age: Int?) -> Target? {
        guard let sex else { return nil }
        let male = sex == .male

        switch metric {
        case .dietaryVitaminC:
            return Target(recommended: male ? 90 : 75, upperLimit: 2_000, provenance: odsIOM)
        case .dietaryVitaminD:
            guard let age else { return nil }
            return Target(recommended: age > 70 ? 20 : 15, upperLimit: 100, provenance: odsIOM)
        case .dietaryVitaminA:
            return Target(recommended: male ? 900 : 700, upperLimit: 3_000,
                          provenance: odsIOM + " The upper limit is preformed vitamin A only; carotenoids are not capped.")
        case .dietaryVitaminB12:
            return Target(recommended: 2.4, upperLimit: nil,
                          provenance: odsIOM + " No upper limit is set — that is an absence of evidence of harm, not a licence.")
        case .dietaryCalcium:
            guard let age else { return nil }
            let rda: Double = age >= 71 ? 1_200 : (male ? 1_000 : (age >= 51 ? 1_200 : 1_000))
            return Target(recommended: rda, upperLimit: age >= 51 ? 2_000 : 2_500, provenance: odsIOM)
        case .dietaryIron:
            guard let age else { return nil }
            // **The widest sex gap in the group, and the reason none of these
            // could ever be a fixed band**: 18 mg against 8 is more than
            // twofold, and the higher figure applies to menstruating readers.
            return Target(recommended: male ? 8 : (age >= 51 ? 8 : 18), upperLimit: 45,
                          provenance: odsIOM + " The higher figure covers menstrual losses.")
        case .dietaryMagnesium:
            guard let age else { return nil }
            let rda: Double = male ? (age >= 31 ? 420 : 400) : (age >= 31 ? 320 : 310)
            // The upper limit is for *supplemental* magnesium only — food
            // magnesium is not capped — so applying it to a total intake figure
            // would flag ordinary eating. Deliberately nil.
            return Target(recommended: rda, upperLimit: nil,
                          provenance: odsIOM + " The 350 mg upper limit applies to supplements only, so it is not drawn against a total intake.")
        case .dietaryZinc:
            return Target(recommended: male ? 11 : 8, upperLimit: 40, provenance: odsIOM)

        // MARK: Deliberately no target
        //
        // Dietary cholesterol had its numeric limit **removed** from the US
        // Dietary Guidelines in 2015 for want of evidence that intake drives
        // serum cholesterol in most people; drawing the retired 300 mg line
        // would be quoting a figure its own authors withdrew. The two
        // unsaturated fats have no recommended intake at all — the guidance is
        // about what they *replace*, which is a ratio this app does not compute.
        case .dietaryCholesterol, .dietaryMonounsaturatedFat, .dietaryPolyunsaturatedFat:
            return nil
        default:
            return nil
        }
    }

    /// Where a day's intake sits. `nil` when there is no target to sit against.
    public static func standing(_ intake: Double, for metric: MetricType,
                                sex: BiologicalSex?, age: Int?) -> Standing? {
        guard let target = target(for: metric, sex: sex, age: age) else { return nil }
        if let ceiling = target.upperLimit, intake > ceiling { return .aboveUpperLimit }
        return intake >= target.recommended ? .met : .below
    }

    /// The metrics that can carry a target at all, for a card listing them.
    public static let targetable: [MetricType] = [
        .dietaryVitaminC, .dietaryVitaminD, .dietaryVitaminA, .dietaryVitaminB12,
        .dietaryCalcium, .dietaryIron, .dietaryMagnesium, .dietaryZinc,
    ]
}
