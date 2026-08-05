import Foundation

/// **How old does each thing think you are — and how sure is it?**
///
/// Roadmap #18. The app and its connectors between them produce three or four
/// different answers to "what age does this body look like", and until now each
/// sat on a different card with no way to see that they disagree.
///
/// ## The rule this is built on: relay, never merge
///
/// Averaging four age estimates into one house number invents a precision none
/// of them has. Each is reported **as its own**, attributed to whoever computed
/// it, and where they disagree by more than their stated errors allow, **the
/// disagreement is the finding** rather than something to be smoothed away.
///
/// ## Printing the error, which is the part nobody does
///
/// Whoop sells "WHOOP Age" and a pace-of-aging figure as a headline feature;
/// Oura prints a cardiovascular age as a headline number. Neither publishes what
/// it is worth. This does, and where a figure genuinely cannot be justified it
/// says *that* instead of inventing one.
///
/// ⚠️ **The uncertainties here are derived, not cited.** For the app's own
/// fitness age the arithmetic is available and honest: the norm table it inverts
/// falls about 0.4 mL/kg·min per year of age, so a VO₂max carrying ±3.5 is an
/// age carrying roughly ±9 years. For a vendor's number the app has no such
/// handle — and rather than repeat a validation figure it cannot check, it
/// reports that the vendor publishes none. That sentence is itself the most
/// useful thing on the section.
public enum AgeComparison {

    /// What an estimate's error is worth, and where the figure came from.
    public enum Uncertainty: Sendable, Equatable {
        /// Computed from the model's own slope and the input's own error.
        case derived(years: Double, from: String)
        /// The vendor publishes a number and no error for it.
        case notPublishedByVendor(String)
        /// The app can compute it but the error is not defensible.
        case unstated(String)

        public var years: Double? {
            if case let .derived(years, _) = self { return years }
            return nil
        }

        public var note: String {
            switch self {
            case let .derived(years, from):
                return String(format: "±%.0f years — %@", years, from)
            case let .notPublishedByVendor(who):
                return "\(who) publishes this number without an error, so there is no way to know what it is worth"
            case let .unstated(why):
                return why
            }
        }
    }

    public struct Estimate: Sendable, Equatable, Identifiable {
        public let label: String
        public let years: Double
        /// Who computed it. Never elided — a relayed number that reads as the
        /// app's own is the failure this whole section exists to avoid.
        public let attribution: String
        public let uncertainty: Uncertainty
        public var id: String { label }
    }

    /// How far a year of age moves the reference VO₂max, from the app's own norm
    /// table. Measured across the table rather than asserted, so it cannot drift
    /// away from the curve `FitnessAgeModel` actually inverts.
    static func vo2YearsPerUnit(sex: BiologicalSex) -> Double {
        let anchors = FitnessAgeModel.anchors(for: sex)
        guard let first = anchors.first, let last = anchors.last,
              first.vo2 != last.vo2 else { return 0 }
        return abs((last.age - first.age) / (last.vo2 - first.vo2))
    }

    /// The error an Apple Watch's VO₂max estimate carries, in its own units.
    ///
    /// A stated assumption rather than a measurement of this reader: wrist
    /// cardiorespiratory-fitness estimates are consistently reported as accurate
    /// to a few mL/kg·min against a laboratory test. It exists so the years
    /// figure below has a stated basis and can be argued with, which is the
    /// whole difference from a number printed bare.
    public static let vo2EstimateError = 3.5

    public static func estimates(chronological: Double?,
                                 fitness: FitnessAgeModel.Output?,
                                 heart: HeartAgeModel.Output?,
                                 sex: BiologicalSex?,
                                 samples: [HealthMetricSample],
                                 now: Date = Date(),
                                 calendar: Calendar = .current) -> [Estimate] {
        var out: [Estimate] = []

        if let chronological {
            out.append(Estimate(
                label: "Your age", years: chronological,
                attribution: "The date you gave us",
                uncertainty: .derived(years: 0, from: "this one is not an estimate")))
        }

        if let fitness, let sex {
            let perUnit = vo2YearsPerUnit(sex: sex)
            out.append(Estimate(
                label: "Fitness age", years: fitness.fitnessAge,
                attribution: "This app, by inverting the same fitness norms it scores you against",
                uncertainty: .derived(
                    years: (vo2EstimateError * perUnit).rounded(),
                    from: String(format: "a wrist VO₂max is good to about %.1f mL/kg·min, and these norms move %.1f years per unit",
                                 vo2EstimateError, perUnit))))
        }

        if let heart, let heartAge = heart.heartAge {
            // **The error is measurable here, and it is better than a citation.**
            // This number is the mean of two published risk equations, and how
            // far apart *they* land on the reader's own numbers is a direct
            // reading of how much the answer depends on which equation you
            // believe. Where only one engine is in its validated range there is
            // nothing to compare it against, and the section says so.
            let uncertainty: Uncertainty
            if heart.readings.count >= 2,
               let low = heart.lowestHeartAge, let high = heart.highestHeartAge {
                uncertainty = .derived(
                    years: ((high - low) / 2).rounded(),
                    from: String(format: "the two published equations behind it land %.0f years apart on your own numbers", high - low))
            } else {
                uncertainty = .unstated("Only one of the two risk equations covers your age, so there is nothing to measure this against")
            }
            out.append(Estimate(
                label: "Heart age", years: heartAge,
                attribution: "This app, by inverting the risk equations on the risk card",
                uncertainty: uncertainty))
        }

        // Relayed, never recomputed. `VitalReader` picks one instrument and
        // never blends, so this is a vendor's number reported as a vendor's.
        if let vascular = VitalReader.reading(.vascularAge, from: samples,
                                             now: now, calendar: calendar) {
            out.append(Estimate(
                label: "Vascular age", years: vascular.value,
                attribution: vascular.sourceName,
                uncertainty: .notPublishedByVendor(vascular.sourceName)))
        }

        return out
    }

    /// The spread across every estimate that is not the reader's real age.
    public static func spread(_ estimates: [Estimate]) -> Double? {
        let years = estimates.filter { $0.label != "Your age" }.map(\.years)
        guard let low = years.min(), let high = years.max(), years.count >= 2 else { return nil }
        return high - low
    }

    /// **The finding, when there is one.**
    ///
    /// Two estimates differing by less than their errors allow are not
    /// disagreeing — they are the same answer measured twice. Beyond that they
    /// genuinely disagree, and saying so is more useful than any single number
    /// on the section, because it tells the reader how much to trust the whole
    /// idea of a biological age.
    public static func disagreement(_ estimates: [Estimate]) -> String? {
        guard let spread = spread(estimates), estimates.count >= 2 else { return nil }
        // The largest stated error is the most generous reading available: if
        // the spread clears even that, no combination of the stated errors
        // explains it.
        let widest = estimates.compactMap { $0.uncertainty.years }.max() ?? 0
        guard spread > widest * 2 else { return nil }
        let sorted = estimates.filter { $0.label != "Your age" }.sorted { $0.years < $1.years }
        guard let low = sorted.first, let high = sorted.last else { return nil }
        return String(format: "These disagree by %.0f years — %@ says %.0f and %@ says %.0f. That is wider than their stated errors explain, so at least one of them is measuring something the other is not. A single \"biological age\" is not a thing your data agrees on.",
                      spread, low.label.lowercased(), low.years,
                      high.label.lowercased(), high.years)
    }
}
