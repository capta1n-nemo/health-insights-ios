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
        /// When the reading behind a **relayed** estimate was taken. Nil for the
        /// app's own rows, which are computed from whatever is current.
        ///
        /// ⚠️ **This replaced a freshness *filter*, and the swap is the point.**
        /// The vendor row used to be read through `VitalReader.reading`, whose
        /// default window is 36 hours — so a reader whose ring had not synced
        /// since yesterday lost the only non-app estimate on the section
        /// entirely, while the card above it went on printing the same vendor's
        /// number from a 60-day window. Two windows on one card for one number.
        ///
        /// Dropping the filter for `latestBySource` fixed that and introduced
        /// the opposite fault: `latest` is the newest raw sample with no window
        /// at all, so a device that stopped reporting a year ago would read as
        /// current. **Neither hiding it nor pretending it is fresh is honest.**
        /// The row is shown, with its date, and says how old it is.
        public let asOf: Date?

        /// Unique per row, not per label.
        ///
        /// `label` alone was the id, which is fine while every row is a
        /// different kind of age and breaks the moment two devices report the
        /// same kind: two sources sharing a `displayName` produce duplicate ids
        /// and SwiftUI silently drops one — losing exactly the row this change
        /// exists to add.
        public var id: String { "\(label)|\(attribution)" }

        public init(label: String, years: Double, attribution: String,
                    uncertainty: Uncertainty, asOf: Date? = nil) {
            self.label = label
            self.years = years
            self.attribution = attribution
            self.uncertainty = uncertainty
            self.asOf = asOf
        }

        /// How stale a relayed reading is allowed to be before the row says so.
        ///
        /// Sixty days, matching `HeartAgeAnalyser`'s window for the same metric
        /// — chosen so the two places on this card that read a vendor age agree
        /// about what "current" means, which they did not before.
        public static let staleAfter: TimeInterval = 60 * 86_400

        /// The sentence appended when a relayed reading is old, or nil.
        public func staleness(now: Date = Date()) -> String? {
            guard let asOf else { return nil }
            let age = now.timeIntervalSince(asOf)
            guard age > Self.staleAfter else { return nil }
            let days = Int(age / 86_400)
            return days >= 365
                ? "Last reported over a year ago, so this describes you as you were then."
                : "Last reported \(days) days ago, so it may not describe you now."
        }
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
                                 biological: BiologicalAgeModel.Output? = nil,
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

        // **This app's own biological age.** Added 2026-08-06 at the reader's
        // request — *"I wanted it to take all the age estimates from all the
        // sources, and also build our own age estimate."*
        //
        // It belongs here more than any other row, because it is the only one
        // whose error was **derived rather than assumed**: `BiologicalAgeModel`
        // combines its markers by inverse-variance weighting, and the ± that
        // falls out of that arithmetic is the honest width of the answer rather
        // than a figure anybody chose. Every vendor row below it publishes none.
        if let biological {
            out.append(Estimate(
                label: "Biological age", years: biological.biologicalAge,
                attribution: "This app, from \(biological.markers.count) markers against published age norms",
                uncertainty: .derived(
                    years: biological.uncertaintyYears.rounded(),
                    from: "combining \(biological.markers.count) markers by how precisely each can pin an age — this is what those measurements are worth, not a hedge")))
        }

        // ⚠️ **Every source, not the winner.**
        //
        // This used to be `VitalReader.reading(.vascularAge, …)`, which is
        // correct for a *vital* — it picks one instrument by freshness and
        // history and never blends, because a chart of "your resting heart rate"
        // must be one device's series rather than a smear of two.
        //
        // **It is exactly wrong for this section**, whose entire subject is that
        // different instruments disagree. A reader with an Oura *and* a Withings
        // vascular age saw one of them and was never told the other existed —
        // on the one screen built to show the disagreement. The reader asked for
        // "all the age estimates from all the sources" and this is the line that
        // was quietly refusing.
        //
        // `latestBySource` is the right door: one row per device, each attributed
        // to the device that produced it. **Still relayed, never merged** —
        // averaging two vendors' ages into a house number would invent a
        // precision neither of them has, which is the rule at the top of this
        // file.
        let vascular = MultiSource.breakdown(.vascularAge, from: samples)
        for series in vascular.sources {
            guard let newest = series.samples.last else { continue }
            let name = series.displayName
            out.append(Estimate(
                label: vascular.sources.count > 1 ? "Vascular age · \(name)" : "Vascular age",
                years: newest.value,
                attribution: name,
                uncertainty: .notPublishedByVendor(name),
                // Carried rather than filtered on — see `Estimate.asOf`.
                asOf: newest.start))
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
