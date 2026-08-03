import Foundation

/// Whether two scans can honestly be read against each other.
///
/// ## The gap in the market this is aimed at
///
/// Every consumer body scanner is reviewed the same way: *inconsistent*.
/// MeThreeSixty "varies from day to day"; a Galaxy Watch reported a ten-pound
/// change in skeletal muscle inside one day, which is not a thing that can
/// happen. The technical reviews all reach the same cause — results shift with
/// **clothing tightness, posture, camera height and lighting**, so "consistent
/// setups produce consistent readings, sloppy setups produce noise".
///
/// Every product treats that as an accuracy problem and competes on accuracy
/// against DXA. It is not an accuracy problem. A reader tracking their own body
/// needs the *same* error every time, not a small one — a scan that reads 2 cm
/// high but reads 2 cm high every month still shows the trend perfectly. What
/// breaks is comparing two scans taken under conditions that differ.
///
/// Nobody records the conditions, so nobody can tell the reader which of their
/// scans are comparable. This does, and it is why `ScanConditions` is stored.
public enum ScanComparability {

    public enum Verdict: Sendable, Equatable {
        /// Conditions match closely enough that a difference is a real change.
        case comparable
        /// Usable, but at least one condition moved enough to add error.
        case degraded([Reason])
        /// Something differs so much that a difference between the two says
        /// more about the setup than about the body.
        case notComparable([Reason])

        public var reasons: [Reason] {
            switch self {
            case .comparable: return []
            case let .degraded(reasons), let .notComparable(reasons): return reasons
            }
        }

        /// Whether the pair may be plotted as one continuous series.
        public var isPlottableTogether: Bool {
            if case .notComparable = self { return false }
            return true
        }
    }

    public enum Reason: String, Sendable, Equatable, CaseIterable {
        case clothingDiffers
        case clothingUnknown
        case distanceDiffers
        case deviceHeightDiffers
        case lightingDiffers
        case timeOfDayDiffers
        case captureModeDiffers

        public var explanation: String {
            switch self {
            case .clothingDiffers:
                return "You were wearing something different. Clothing is the single biggest source of difference between two scans."
            case .clothingUnknown:
                return "One of these scans didn't record what you were wearing, so the comparison can't account for it."
            case .distanceDiffers:
                return "You stood a different distance from the phone."
            case .deviceHeightDiffers:
                return "The phone was at a different height."
            case .lightingDiffers:
                return "The lighting was noticeably different, which moves where the edge of your silhouette falls."
            case .timeOfDayDiffers:
                return "These were taken at different times of day. Waist and abdomen genuinely differ between morning and evening."
            case .captureModeDiffers:
                return "These were taken different ways, so they don't carry the same kind of error."
            }
        }
    }

    // MARK: - The thresholds
    //
    // Each is the point past which the condition contributes more than the
    // measurement's own repeatability (±10 mm is the published consumer
    // benchmark for a circumference). Named rather than inline so they can be
    // read, argued with and moved in one place.

    /// Standing 20 cm nearer or further changes the pixels-per-centimetre the
    /// silhouette is scaled by.
    public static let distanceToleranceMetres = 0.20
    /// A phone 15 cm higher looks down at a different angle, which foreshortens.
    public static let deviceHeightToleranceMetres = 0.15
    /// Light is judged on a ratio, not a difference: 50 lux against 100 matters,
    /// 5,000 against 5,050 does not.
    public static let lightingToleranceRatio = 2.0
    /// Four hours apart is a different body — abdominal girth moves across a day
    /// with food and fluid, and it is not a change in composition.
    public static let hourToleranceHours = 4

    /// Judge two sets of conditions.
    ///
    /// Order-independent by construction: this answers "are these two the same
    /// setup", which has no direction.
    public static func compare(_ first: ScanConditions, _ second: ScanConditions,
                               modeFirst: BodyScan.CaptureMode,
                               modeSecond: BodyScan.CaptureMode) -> Verdict {
        var severe: [Reason] = []
        var mild: [Reason] = []

        // Clothing first, because it is the largest term and the only one the
        // reader controls completely.
        if first.clothing == .unknown || second.clothing == .unknown {
            mild.append(.clothingUnknown)
        } else if first.clothing != second.clothing {
            severe.append(.clothingDiffers)
        }

        if modeFirst != modeSecond { severe.append(.captureModeDiffers) }

        if let a = first.subjectDistanceMetres, let b = second.subjectDistanceMetres,
           abs(a - b) > distanceToleranceMetres {
            severe.append(.distanceDiffers)
        }
        if let a = first.deviceHeightMetres, let b = second.deviceHeightMetres,
           abs(a - b) > deviceHeightToleranceMetres {
            severe.append(.deviceHeightDiffers)
        }
        if let a = first.ambientLux, let b = second.ambientLux,
           a > 0, b > 0, max(a, b) / min(a, b) > lightingToleranceRatio {
            mild.append(.lightingDiffers)
        }
        if let a = first.hourOfDay, let b = second.hourOfDay,
           abs(a - b) > hourToleranceHours {
            mild.append(.timeOfDayDiffers)
        }

        if !severe.isEmpty { return .notComparable(severe + mild) }
        if !mild.isEmpty { return .degraded(mild) }
        return .comparable
    }

    /// The smallest change worth calling a change, in centimetres.
    ///
    /// The published consumer benchmark for a scanned circumference is ±10 mm,
    /// so a 1 cm "gain" between two scans is inside the method's own noise.
    /// Reporting it anyway is precisely how a scanner ends up telling somebody
    /// they gained ten pounds of muscle overnight.
    ///
    /// This is the same restraint `ScoreChange` already applies to scores, and
    /// it is applied for the same reason: a number seen every month has to earn
    /// the right to point at something.
    public static func repeatabilityBandCentimetres(_ mode: BodyScan.CaptureMode) -> Double {
        switch mode {
        case .lidarDepth: return 1.0
        case .cameraSegmentation: return 2.0
        // A tape is only as repeatable as the hand holding it, and the
        // literature on self-measured waist puts that near a centimetre.
        case .tape: return 1.0
        }
    }

    /// Whether a difference between two scans of one site is real enough to say.
    ///
    /// Takes the **wider** of the two bands: a comparison is only as repeatable
    /// as its shakier half.
    public static func isMeaningfulChange(_ centimetres: Double,
                                          from: BodyScan.CaptureMode,
                                          to: BodyScan.CaptureMode) -> Bool {
        abs(centimetres) >= max(repeatabilityBandCentimetres(from),
                                repeatabilityBandCentimetres(to))
    }
}
