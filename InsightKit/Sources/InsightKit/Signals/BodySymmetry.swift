import Foundation

/// Left against right, where a scan measured both.
///
/// ## Why this is worth reporting, and why it is mostly silent
///
/// Left/right girths are the cheapest thing a scan produces — the sides are
/// already measured separately, and `BodyMeasurements` already stores them
/// per-`BodySide`. Nothing else in the app can say "your right arm is a
/// centimetre bigger than your left", and among the scanners researched only
/// the gym-installation systems report it at all.
///
/// **But everybody is slightly asymmetric.** A dominant arm is reliably larger,
/// a habitual stance loads one leg, and none of that is a finding. So the floor
/// is not zero: a difference has to clear the measuring method's own
/// repeatability before it is a difference at all, and `ScanComparability`
/// already owns those numbers — reusing them rather than inventing a second set
/// is what stops the two drifting.
public enum BodySymmetry {

    public struct Finding: Sendable, Equatable, Identifiable {
        public let site: BodySite
        public let leftCentimetres: Double
        public let rightCentimetres: Double
        /// Right minus left. Positive means the right side is larger.
        public let differenceCentimetres: Double
        /// The difference as a share of the larger side.
        public let relativeDifference: Double

        public var id: String { site.rawValue }

        public var largerSide: BodySide {
            differenceCentimetres > 0 ? .right : .left
        }

        /// One line, stating the observation and nothing more.
        ///
        /// Deliberately not advice. A limb difference has many ordinary causes —
        /// handedness first among them — and this app is not in a position to
        /// tell anybody to correct one.
        public var sentence: String {
            String(format: "%@: %.1f cm on the %@, %.1f cm on the other side.",
                   site.displayName,
                   max(leftCentimetres, rightCentimetres),
                   largerSide == .right ? "right" : "left",
                   min(leftCentimetres, rightCentimetres))
        }
    }

    /// Differences worth reporting, largest first.
    ///
    /// - Parameter mode: how the measurements were taken. Sets the floor, so a
    ///   camera scan has to see a bigger gap than a tape before it says anything.
    public static func findings(in measurements: BodyMeasurements,
                                mode: BodyScan.CaptureMode) -> [Finding] {
        let floor = ScanComparability.repeatabilityBandCentimetres(mode)
        return BodySite.allCases.filter(\.isPaired).compactMap { site in
            guard let left = measurements.value(site, .left),
                  let right = measurements.value(site, .right) else { return nil }
            let difference = right - left
            guard abs(difference) >= floor else { return nil }
            let larger = Swift.max(left, right)
            guard larger > 0 else { return nil }
            return Finding(site: site, leftCentimetres: left, rightCentimetres: right,
                           differenceCentimetres: difference,
                           relativeDifference: abs(difference) / larger)
        }
        .sorted { abs($0.differenceCentimetres) > abs($1.differenceCentimetres) }
    }

    /// The share of the larger side past which a difference is worth a word even
    /// to somebody who expects to be asymmetric.
    ///
    /// Five percent. Below it, handedness explains almost anything: the
    /// literature on limb-girth asymmetry in ordinary adults puts dominant-arm
    /// differences in the low single-digit percentages, so a threshold under
    /// that would flag most of the population for being right-handed.
    public static let notableRelativeDifference = 0.05

    /// The findings that clear both floors — the measuring noise *and* ordinary
    /// human asymmetry.
    public static func notableFindings(in measurements: BodyMeasurements,
                                       mode: BodyScan.CaptureMode) -> [Finding] {
        findings(in: measurements, mode: mode)
            .filter { $0.relativeDifference >= notableRelativeDifference }
    }

    /// What the section says when nothing clears the floor — which is the
    /// common case and a real answer, not an empty one.
    public static let balancedSentence =
        "Your left and right measurements are within the range this method can tell apart."
}
