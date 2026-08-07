import Foundation

/// One plottable row of the Readiness z-score strip: how far a vital sits from
/// this person's own baseline, and what the scan made of that.
///
/// ## Why the band is not recomputed from z
///
/// The obvious implementation reads `zScore` and re-applies the 1.25 / 2.0
/// thresholds. It would be wrong twice over.
///
/// - **Direction matters.** A departure *towards* the harmless side costs less:
///   `VitalSignsCheck.Spec` marks which direction is clinically meaningful, and
///   a resting heart rate two standard deviations *below* baseline is good news,
///   not an alarm. A strip that coloured by `abs(z)` would paint the best
///   morning of the month in the same red as the worst.
/// - **An absolute bound overrides a personal one.** `VitalSignsCheck` promotes a
///   reading to `.unusual` when it crosses a hard clinical bound whatever its
///   z-score — a baseline built from consistently low oxygen saturation must not
///   normalise it. So a row can legitimately be red while sitting near the middle
///   of the axis, and `isBeyondClinicalBound` is what lets the strip say so
///   instead of looking broken.
///
/// So the band here **is** `Reading.status`, mapped. The strip and the card
/// cannot disagree, because there is nothing for them to disagree about. What is
/// shared in the other direction is the *rule* — `band(z:concerning:)` below is
/// called by `VitalSignsCheck.reading`, so the thresholds exist once.
public struct VitalDeparture: Sendable, Equatable, Identifiable {

    /// How the scan judged this reading. `Reading.Status` minus the case that
    /// cannot be drawn — see `VitalDeparturePanel.unjudged`.
    public enum Band: String, Sendable, Equatable, CaseIterable {
        case ordinary, watch, unusual

        init?(_ status: VitalSignsCheck.Reading.Status) {
            switch status {
            case .normal: self = .ordinary
            case .watch: self = .watch
            case .unusual: self = .unusual
            // Not a quieter kind of normal — a reading nobody could judge. It
            // leaves the axis entirely rather than being drawn at zero, which
            // would read as "measured, and ordinary".
            case .insufficientHistory: return nil
            }
        }

        /// Worst first, matching how every other list on these cards is ordered.
        var severity: Int {
            switch self {
            case .unusual: return 2
            case .watch: return 1
            case .ordinary: return 0
            }
        }
    }

    public let metric: MetricType
    /// The reading's true distance from baseline, in standard deviations.
    public let z: Double
    /// `z` brought inside the drawn axis. A strip with no bound would let one
    /// artefact at z = 12 squash every real departure into a hairline.
    public let plotted: Double
    /// Whether `plotted` had to move — the strip marks these so a dot pinned to
    /// the edge is not read as a measurement that happens to sit there.
    public let isClamped: Bool
    public let band: Band
    /// Whether the departure runs in the direction that matters clinically.
    public let isConcerningDirection: Bool
    /// Whether the band came from an absolute clinical bound rather than from
    /// this person's own spread. Without it, a red dot near the middle of the
    /// axis has no visible explanation.
    public let isBeyondClinicalBound: Bool
    public let value: Double
    public let sourceName: String

    public var id: MetricType { metric }

    // MARK: - The shared threshold rule

    /// z beyond this is "unusual"; beyond the smaller one is "watch". Surfaced
    /// from `VitalSignsCheck`'s own constants rather than copied, so the shaded
    /// band on the strip is drawn at the edges the scan actually judges by.
    public static var watchZ: Double { VitalSignsCheck.watchZ }
    public static var unusualZ: Double { VitalSignsCheck.unusualZ }

    /// The widest departure the strip draws. Three standard deviations is past
    /// the point where further distance tells a reader anything they have not
    /// already been told in red.
    public static let axisLimit = 3.0

    /// The one place the thresholds are applied. `VitalSignsCheck.reading` calls
    /// this, which is what makes "the strip agrees with the score" a structural
    /// fact rather than a thing tests have to keep checking.
    public static func band(z: Double, concerning: Bool) -> Band {
        let magnitude = abs(z)
        if magnitude >= unusualZ { return concerning ? .unusual : .watch }
        if magnitude >= watchZ { return concerning ? .watch : .ordinary }
        return .ordinary
    }

    /// Whether a departure of this sign is the one worth worrying about for this
    /// vital, per the spec's own `concernWhenHigh` / `concernWhenLow`.
    static func isConcerning(z: Double, spec: VitalSignsCheck.Spec) -> Bool {
        z > 0 ? spec.concernWhenHigh : spec.concernWhenLow
    }

    /// A departure row for a metric the **clinical scan doesn't cover** — a step
    /// count, VO₂max, active energy. "How far from your normal" is on every card
    /// and lists that card's signals; it used to draw only the ones with a
    /// `VitalSignsCheck` spec, so a card whose inputs are mostly non-clinical
    /// (Fitness, Sleep, Energy) showed two rows while "How you compare" listed
    /// six. This closes that gap by reading the metric's own baseline.
    ///
    /// Neutral by construction: a non-clinical metric has **no concerning
    /// direction** — fewer steps than usual is not an alarm the way a low blood
    /// oxygen is — so its band never reaches the clinical red, only "worth a
    /// look". `nil` when the metric has no baseline yet.
    public static func baseline(_ reading: VitalReading) -> VitalDeparture? {
        guard let z = reading.zScore else { return nil }
        return VitalDeparture(
            metric: reading.metric, z: z,
            plotted: Swift.max(-axisLimit, Swift.min(axisLimit, z)),
            isClamped: abs(z) > axisLimit,
            band: band(z: z, concerning: false),
            isConcerningDirection: false,
            isBeyondClinicalBound: false,
            value: reading.value, sourceName: reading.sourceName)
    }
}

/// Everything the Readiness strip needs: the rows it can draw, and an honest
/// account of what it cannot.
public struct VitalDeparturePanel: Sendable, Equatable {
    /// Most departed first.
    public let rows: [VitalDeparture]
    /// Measured today, but without enough history behind it to judge.
    public let unjudged: [MetricType]
    /// This person records these, just not lately.
    public let stale: [MetricType]

    public var isEmpty: Bool { rows.isEmpty }

    /// The caveat under the strip. Vitals that could not be plotted are named
    /// here rather than drawn at zero — the same decision the weighted
    /// contribution card makes for zero-weight contributors, and for the same
    /// reason: a mark at the origin claims a measurement that was never judged.
    public var footnote: String? {
        var parts: [String] = []
        if !unjudged.isEmpty {
            parts.append("\(list(unjudged)) \(unjudged.count == 1 ? "has" : "have") "
                         + "too little history to judge yet")
        }
        if !stale.isEmpty {
            parts.append("\(list(stale)) \(stale.count == 1 ? "was" : "were") "
                         + "not measured recently enough to show")
        }
        guard !parts.isEmpty else { return nil }
        return parts.joined(separator: ". ") + "."
    }

    private func list(_ metrics: [MetricType]) -> String {
        let names = metrics.map(\.displayName)
        guard let last = names.last else { return "" }
        if names.count == 1 { return last }
        return names.dropLast().joined(separator: ", ") + " and " + last
    }

    /// Built from the scan's own output, so the strip charts exactly what the
    /// card scored — no second pass over the samples.
    /// Narrowed to the signals one card reads.
    ///
    /// "How far from your normal" is on every card now, and the scan looks at
    /// seventeen vitals regardless of which card is asking. Drawing all
    /// seventeen under the Sleep card would answer a question nobody asked and
    /// bury the two rows that are about sleep. `nil` keeps everything, which is
    /// what the Readiness card wants — its subject *is* the whole scan.
    public static func from(_ output: VitalSignsCheck.Output,
                            limitedTo metrics: [MetricType]?) -> VitalDeparturePanel {
        let whole = from(output)
        guard let metrics else { return whole }
        let wanted = Set(metrics)
        return VitalDeparturePanel(
            rows: whole.rows.filter { wanted.contains($0.metric) },
            unjudged: whole.unjudged.filter { wanted.contains($0) },
            stale: whole.stale.filter { wanted.contains($0) })
    }

    /// A card's departure panel: the clinical scan's rows for the metrics it
    /// covers, **plus** a plain baseline row for every other metric the card
    /// reads. This is what makes "How far from your normal" list the same
    /// signals as "How you compare" — steps, active energy, VO₂max and the rest,
    /// each against the reader's own normal — rather than only the clinical
    /// vitals the scan happens to watch.
    ///
    /// `extraReadings` are the card's non-scan metrics read through
    /// `VitalReader`; the caller supplies them because only it holds the samples.
    /// A metric measured but without a baseline yet joins `unjudged` so it is
    /// named, not silently dropped.
    /// The panel a card draws, computed from the card's own signals.
    ///
    /// **This is the whole rule in one place, and it is here rather than in the
    /// view for the reason every such rule is**: a card's sections have to agree
    /// about which signals they cover, and a view is the one place that claim
    /// cannot be tested. `ContributorDepartureTests` runs it over every shipped
    /// model.
    ///
    /// - `cardMetrics` narrows the clinical scan to the card's own signals
    ///   (`nil` keeps all of it — Readiness, whose subject *is* the scan).
    /// - `contributorMetrics` is what the card actually reports scoring, and
    ///   **every one of them earns a row** — read against its own baseline where
    ///   the clinical scan has no spec for it. That is what stops a scored signal
    ///   (sleep duration on Readiness, steps on Fitness) being listed under "What
    ///   goes into this" and missing from here.
    public static func forCard(_ output: VitalSignsCheck.Output,
                               cardMetrics: [MetricType]?,
                               contributorMetrics: [MetricType],
                               samples: [HealthMetricSample],
                               now: Date = Date(),
                               calendar: Calendar = .current) -> VitalDeparturePanel {
        let extras = contributorMetrics
            // The scan already speaks for these, with its clinical bounds.
            .filter { !VitalSignsCheck.coveredMetrics.contains($0)
                      // A modelled quantity is left out here as it is from the
                      // peer comparison: "unusual for you" would read as a
                      // measurement claim about something nothing measured.
                      && !PeerStandingModel.isModelled($0) }
            // **`judgementGap`, and this is the call site backlog P38 was
            // written about.** Every row here renders as "away from your
            // normal", and without the gap yesterday's excursion is inside the
            // baseline judging today — so a departure stops being a departure by
            // lasting two days, with nothing about the body having changed. The
            // scan's own rows (`from(output:)` above) have had the gap since
            // 2026-08-05; these extra rows sit beside them on the same panel and
            // must be measured the same way, or one card shows two kinds of z.
            .compactMap { VitalReader.reading($0, from: samples, now: now,
                                              gap: VitalReader.judgementGap,
                                              calendar: calendar) }
        return forCard(output, cardMetrics: cardMetrics, extraReadings: extras)
    }

    public static func forCard(_ output: VitalSignsCheck.Output,
                               cardMetrics: [MetricType]?,
                               extraReadings: [VitalReading]) -> VitalDeparturePanel {
        let base = from(output, limitedTo: cardMetrics)
        var rows = base.rows
        var unjudged = base.unjudged
        let alreadyHave = Set(rows.map(\.metric)).union(unjudged).union(base.stale)
        for reading in extraReadings where !alreadyHave.contains(reading.metric) {
            if let row = VitalDeparture.baseline(reading) {
                rows.append(row)
            } else {
                unjudged.append(reading.metric)
            }
        }
        rows.sort {
            $0.band.severity != $1.band.severity
                ? $0.band.severity > $1.band.severity
                : abs($0.z) > abs($1.z)
        }
        return VitalDeparturePanel(rows: rows, unjudged: unjudged, stale: base.stale)
    }

    public static func from(_ output: VitalSignsCheck.Output) -> VitalDeparturePanel {
        var rows: [VitalDeparture] = []
        var unjudged: [MetricType] = []

        for reading in output.readings {
            guard let band = VitalDeparture.Band(reading.status), let z = reading.zScore else {
                unjudged.append(reading.metric)
                continue
            }
            let spec = VitalSignsCheck.specs.first { $0.metric == reading.metric }
            let concerning = spec.map { VitalDeparture.isConcerning(z: z, spec: $0) } ?? true
            // A band the z-score alone would not have produced can only have come
            // from an absolute bound. Derived rather than passed through, because
            // `Reading` carries the verdict and not the route to it.
            let fromBound = band != VitalDeparture.band(z: z, concerning: concerning)
            let limit = VitalDeparture.axisLimit
            rows.append(VitalDeparture(
                metric: reading.metric,
                z: z,
                plotted: Swift.max(-limit, Swift.min(limit, z)),
                isClamped: abs(z) > limit,
                band: band,
                isConcerningDirection: concerning,
                isBeyondClinicalBound: fromBound,
                value: reading.value,
                sourceName: reading.sourceName))
        }

        rows.sort {
            $0.band.severity != $1.band.severity
                ? $0.band.severity > $1.band.severity
                : abs($0.z) > abs($1.z)
        }
        return VitalDeparturePanel(rows: rows, unjudged: unjudged,
                                   stale: output.stale.map(\.metric))
    }
}
