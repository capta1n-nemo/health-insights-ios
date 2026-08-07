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
/// ## One row per instrument, including for the app's own ages
///
/// "All the sources" was two-thirds true until 2026-08-07: the vendor's vascular
/// age got a row per device, while the app's **own** fitness and heart ages
/// arrived here already collapsed to one instrument by `VitalReader`. See
/// `fitnessEstimates` for why that is the section committing its own subject's
/// offence, and what it costs on a record with four VO₂max sources.
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
        /// When the reading behind this estimate was taken.
        ///
        /// ⚠️ **The app's own rows carry one too, since 2026-08-07.** They used
        /// to be documented as "computed from whatever is current", which was
        /// only true because they were computed from one instrument picked by
        /// freshness. Now that every instrument gets its own row, a fitness age
        /// built from a VO₂max that Apple last estimated eight months ago is on
        /// the section beside one from last week — and the older row has to say
        /// so, or the disagreement between them reads as physiology when it is
        /// partly just time.
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

        /// **Set only where the app is unsure what the number *is*.**
        ///
        /// ⚠️ Every other doubt on this section is about width — how far the
        /// answer could move and still be the same answer. This one is about
        /// identity, and it is a different claim: `withings.measure.227` is
        /// believed to be a metabolic age because its values sit where one
        /// would, and Withings publishes no field table that would confirm it
        /// (backlog D20).
        ///
        /// **It is deliberately not an `Uncertainty` case.** `Uncertainty`
        /// answers "±what", and `disagreement(_:)` reads `.years` off it to
        /// decide whether two rows genuinely disagree. Folding an identity
        /// doubt into that would have it answering a question it was never
        /// asked, and would let the row inherit the standard modelled caveat —
        /// which states the wrong uncertainty, confidently. The two are shown
        /// side by side because both are true of this row at once: Withings
        /// publishes no error for the number *and* no name for the field.
        public let identity: RawFieldPresentation.InferredMapping?

        /// The identity sentence for the row, or nil.
        ///
        /// The last clause is not decoration: a reader who has just read four
        /// "±9 years" notes will read a fifth caveat as more of the same unless
        /// something says outright that this one is a different kind.
        public var identityNote: String? {
            identity.map {
                "\($0.caveat) Every other row here is a number whose width is uncertain. "
                    + "On this one it is the subject."
            }
        }

        /// Unique per row, not per label.
        ///
        /// `label` alone was the id, which is fine while every row is a
        /// different kind of age and breaks the moment two devices report the
        /// same kind: two sources sharing a `displayName` produce duplicate ids
        /// and SwiftUI silently drops one — losing exactly the row this change
        /// exists to add.
        public var id: String { "\(label)|\(attribution)" }

        public init(label: String, years: Double, attribution: String,
                    uncertainty: Uncertainty, asOf: Date? = nil,
                    identity: RawFieldPresentation.InferredMapping? = nil) {
            self.label = label
            self.years = years
            self.attribution = attribution
            self.uncertainty = uncertainty
            self.asOf = asOf
            self.identity = identity
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

    /// - Parameter raw: The unmodelled catalogue. A vendor age can arrive with
    ///   no `MetricType` behind it — Withings' is a numbered measure type — and
    ///   the section is a poorer answer to "all the sources" for every one it
    ///   cannot see. See `relayedRawAges`.
    public static func estimates(chronological: Double?,
                                 fitness: FitnessAgeModel.Output?,
                                 heart: HeartAgeModel.Output?,
                                 sex: BiologicalSex?,
                                 samples: [HealthMetricSample],
                                 biological: BiologicalAgeModel.Output? = nil,
                                 heartSubject: HeartAgeModel.Subject? = nil,
                                 raw: [RawMetricSample] = [],
                                 now: Date = Date(),
                                 calendar: Calendar = .current) -> [Estimate] {
        var out: [Estimate] = []

        if let chronological {
            out.append(Estimate(
                label: "Your age", years: chronological,
                attribution: "The date you gave us",
                uncertainty: .derived(years: 0, from: "this one is not an estimate")))
        }

        out += fitnessEstimates(chronological: chronological, sex: sex, samples: samples,
                                fallback: fitness, now: now, calendar: calendar)
        out += heartEstimates(chronological: chronological, subject: heartSubject,
                              samples: samples, fallback: heart,
                              now: now, calendar: calendar)

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

        out += relayedRawAges(raw: raw)

        return out
    }

    // MARK: - Vendor ages with no MetricType behind them

    /// Raw identifiers that carry an age in years, and nothing reads.
    ///
    /// Withings has sent `withings.measure.227` on more distinct days than Oura
    /// has sent a vascular age, and until now the one screen built to show every
    /// product's answer did not know it existed — because the section reads
    /// `HealthMetricSample`s and this field was never promoted to a
    /// `MetricType`. Backlog D20.
    ///
    /// ⚠️ **Every identifier here must have a `RawFieldPresentation`
    /// `InferredMapping`**, and that is not a coincidence to be tidied away: a
    /// raw field's name is by definition not a canonical metric's name, so a
    /// vendor age arriving through this lane is one whose identity the app
    /// worked out. `relayedRawAges` skips anything without a mapping rather
    /// than printing an age under a name nothing stands behind.
    static let relayedRawAgeIdentifiers: [String] = ["withings.measure.227"]

    /// The band a value must sit in to still look like an age in years.
    ///
    /// ⚠️ **This is the identification, re-checked at the moment of printing.**
    /// The only reason the app believes measure type 227 is a metabolic age is
    /// that its values sit where an adult age sits. A reading outside this band
    /// is that evidence being withdrawn — so the row disappears rather than
    /// printing "Withings says you are 4" under a name the number has just
    /// refuted. Wide on purpose: it is a sanity bound on the *mapping*, not a
    /// plausibility filter on the reader.
    static let plausibleAgeYears: ClosedRange<Double> = 5...120

    /// One row per source per relayed raw age, each labelled as inferred.
    ///
    /// **Relay, never merge, exactly as for the vascular age** — the section's
    /// point is naming who computed what, and Withings computed this one. What
    /// is different is *what the caveat says*: not "this figure is modelled"
    /// but "we believe this is their metabolic age, and they publish nothing
    /// that would confirm it". See `Estimate.identity`.
    static func relayedRawAges(raw: [RawMetricSample], now: Date = Date()) -> [Estimate] {
        var out: [Estimate] = []
        for identifier in relayedRawAgeIdentifiers {
            guard let mapping = RawFieldPresentation.inferredMapping(forPath: identifier) else { continue }
            let name = RawFieldPresentation.title(forPath: identifier)
            let bySource = Dictionary(grouping: raw.filter { $0.identifier == identifier },
                                      by: \.source)
            let sources = bySource.keys.sorted { $0.displayName < $1.displayName }
            for source in sources {
                guard let newest = bySource[source]?.max(by: { $0.start < $1.start }),
                      let value = newest.numericValue,
                      plausibleAgeYears.contains(value)
                else { continue }
                // ⚠️ **The label carries the flag, not only the note below it.**
                // The strip above the rows draws `label` and nothing else, so a
                // row labelled plainly "Metabolic age" would put the app's
                // strongest unverified claim on a chart with no caveat attached
                // to it at all — which is the invisible-claim failure this
                // section exists to prevent, one level up.
                let base = "\(name) (unconfirmed)"
                out.append(Estimate(
                    label: sources.count > 1 ? "\(base) · \(source.displayName)" : base,
                    years: value,
                    // Never "This app" — that prefix is what the strip tints as
                    // the app's own, and this number is the vendor's.
                    attribution: "\(source.displayName), from a field this app identified rather than one \(mapping.vendor) documents",
                    uncertainty: .notPublishedByVendor(source.displayName),
                    asOf: newest.start,
                    identity: mapping))
            }
        }
        return out
    }

    // MARK: - The app's own ages, one row per instrument

    /// ⚠️ **The section's own defect, fixed for the app's own rows too.**
    ///
    /// The vascular row stopped picking a winner on 2026-08-06 and these two did
    /// not, which made "every source" two-thirds true for eleven days. Both the
    /// fitness age and the heart age reached this file having already been
    /// collapsed to one instrument by `VitalReader.reading` inside
    /// `HeartAgeAnalyser` — and the reader's export carries **four VO₂max source
    /// ids and four systolic ones**.
    ///
    /// That is the defect this whole section exists to prevent, committed by the
    /// section itself: *a screen whose subject is that instruments disagree must
    /// not manufacture agreement by silently choosing one.* A watch's VO₂max and
    /// a ring's differ by more than the ±9 years either row prints, so the choice
    /// was moving the answer further than its own stated error — invisibly.
    ///
    /// **Why each row is still read through `VitalReader`** rather than off the
    /// newest raw sample the way the vendor rows are: `VitalReader` is what the
    /// Fitness card and the risk card compute their headline from, so handing it
    /// one source's series at a time reproduces the winner's number *exactly*
    /// while keeping the losers. Read the newest raw sample instead and this
    /// section would quietly print a fitness age the card above it disagrees
    /// with — trading one silent disagreement for another.
    static func fitnessEstimates(chronological: Double?,
                                 sex: BiologicalSex?,
                                 samples: [HealthMetricSample],
                                 fallback: FitnessAgeModel.Output?,
                                 now: Date,
                                 calendar: Calendar) -> [Estimate] {
        guard let sex else { return [] }
        let perUnit = vo2YearsPerUnit(sex: sex)
        // Unchanged arithmetic: the norm table's own slope times the instrument's
        // own error. Only the count of rows it is printed on has changed.
        let uncertainty = Uncertainty.derived(
            years: (vo2EstimateError * perUnit).rounded(),
            from: String(format: "a consumer VO₂max estimate is good to about %.1f mL/kg·min, and these norms move %.1f years per unit",
                         vo2EstimateError, perUnit))

        func row(_ years: Double, source: String?, asOf: Date?, named: Bool) -> Estimate {
            Estimate(
                label: named ? "Fitness age · \(source ?? "")" : "Fitness age",
                years: years,
                // The instrument is named even on a single-source row. Naming it
                // costs nothing and is the whole point: "this app, from *this*
                // VO₂max" is a different claim from "this app".
                attribution: source.map {
                    "This app, reading \($0)'s VO₂max against the same fitness norms it scores you against"
                } ?? "This app, by inverting the same fitness norms it scores you against",
                uncertainty: uncertainty,
                asOf: asOf)
        }

        var rows: [Estimate] = []
        if let chronological {
            let readings = MultiSource.breakdown(.vo2Max, from: samples).sources
                .compactMap { VitalReader.reading(.vo2Max, from: $0.samples,
                                                  now: now,
                                                  // An age is a level — "where am I
                                                  // now", not "is this unusual" — so no
                                                  // reference gap, matching what
                                                  // HeartHealthScore passes for this
                                                  // same metric. See ReferenceGap.
                                                  gap: .none, calendar: calendar) }
            for reading in readings {
                let output = FitnessAgeModel.evaluate(vo2: reading.value, sex: sex,
                                                      chronologicalAge: chronological)
                rows.append(row(output.fitnessAge, source: reading.sourceName,
                                asOf: reading.date, named: readings.count > 1))
            }
        }
        // Nothing in `samples` to break out — a caller that computed the age
        // elsewhere still gets its row rather than losing it.
        if rows.isEmpty, let fallback {
            rows.append(row(fallback.fitnessAge, source: nil, asOf: nil, named: false))
        }
        return rows
    }

    /// The heart age, once per blood-pressure instrument.
    ///
    /// **The reader's own cuff is one of them and needs no special case**:
    /// `DataStore.saveGrounding` mirrors every entered cuff reading into a
    /// `.bloodPressureSystolic` sample under `MetricSource.manual`, so the
    /// per-source breakdown already carries it as its own series beside the
    /// sensed ones. A hand-written "the reading you entered" row would have
    /// printed it twice.
    ///
    /// Only the systolic varies between rows. Cholesterol, smoking and diabetes
    /// are facts about the person rather than readings from a device, so holding
    /// them fixed is what makes the spread *between* these rows attributable to
    /// the instruments — which is the only reason to draw them side by side.
    static func heartEstimates(chronological: Double?,
                               subject: HeartAgeModel.Subject?,
                               samples: [HealthMetricSample],
                               fallback: HeartAgeModel.Output?,
                               now: Date,
                               calendar: Calendar) -> [Estimate] {
        // **The error is measurable here, and it is better than a citation.**
        // This number is the mean of two published risk equations, and how far
        // apart *they* land on the reader's own numbers is a direct reading of
        // how much the answer depends on which equation you believe. Where only
        // one engine is in its validated range there is nothing to compare it
        // against, and the section says so.
        func uncertainty(_ output: HeartAgeModel.Output) -> Uncertainty {
            guard output.readings.count >= 2,
                  let low = output.lowestHeartAge, let high = output.highestHeartAge else {
                return .unstated("Only one of the two risk equations covers your age, so there is nothing to measure this against")
            }
            return .derived(
                years: ((high - low) / 2).rounded(),
                from: String(format: "the two published equations behind it land %.0f years apart on your own numbers", high - low))
        }

        func row(_ output: HeartAgeModel.Output, source: String?,
                 asOf: Date?, named: Bool) -> Estimate? {
            guard let heartAge = output.heartAge else { return nil }
            return Estimate(
                label: named ? "Heart age · \(source ?? "")" : "Heart age",
                years: heartAge,
                attribution: source.map {
                    "This app, inverting the risk equations on the risk card against \($0)'s blood pressure"
                } ?? "This app, by inverting the risk equations on the risk card",
                uncertainty: uncertainty(output),
                asOf: asOf)
        }

        var rows: [Estimate] = []
        if let subject, let chronological {
            let solved = MultiSource.breakdown(.bloodPressureSystolic, from: samples).sources
                .compactMap { series -> (VitalReading, HeartAgeModel.Output)? in
                    guard let reading = VitalReader.reading(.bloodPressureSystolic,
                                                            from: series.samples,
                                                            now: now,
                                                            // A level, not an anomaly —
                                                            // same choice as
                                                            // CardiovascularRiskInsight.
                                                            gap: .none, calendar: calendar)
                    else { return nil }
                    var perSource = subject
                    perSource.systolicBP = reading.value
                    return HeartAgeModel.evaluate(subject: perSource, age: chronological)
                        .map { (reading, $0) }
                }
            for (reading, output) in solved {
                if let estimate = row(output, source: reading.sourceName,
                                      asOf: reading.date, named: solved.count > 1) {
                    rows.append(estimate)
                }
            }
        }
        if rows.isEmpty, let fallback, let estimate = row(fallback, source: nil,
                                                         asOf: nil, named: false) {
            rows.append(estimate)
        }
        return rows
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
        var text = String(format: "These disagree by %.0f years — %@ says %.0f and %@ says %.0f. That is wider than their stated errors explain, so at least one of them is measuring something the other is not. A single \"biological age\" is not a thing your data agrees on.",
                          spread, low.label.lowercased(), low.years,
                          high.label.lowercased(), high.years)
        // ⚠️ **A finding built on an inferred identity has to say so, here of
        // all places.** This sentence's whole force is "the disagreement is
        // real" — and it is not, if one of the two endpoints might not be the
        // quantity the app has called it. Naming the endpoint rather than
        // quietly dropping the row: excluding it would leave the spread above
        // disagreeing with the sentence below, which is its own dishonesty.
        for endpoint in [low, high] {
            guard let identity = endpoint.identity else { continue }
            text += " Read the gap carefully, though: \(endpoint.label.lowercased()) rests on a "
                + "field this app identified rather than one \(identity.vendor) documents, so some "
                + "of that distance could be a wrong label rather than your body."
        }
        return text
    }
}
