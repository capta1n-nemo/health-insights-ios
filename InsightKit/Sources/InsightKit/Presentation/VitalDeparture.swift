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
