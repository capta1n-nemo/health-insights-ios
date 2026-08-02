import Foundation

/// **Is it working?** — the medication read against the body it is acting on.
///
/// `PharmacokineticsModel` says how much drug is on board. That is a model of
/// the *drug*, and on its own it answers nothing a reader actually wants to
/// know. This is the other half: the weight and body-fat record laid against
/// the dose history, so "the 7.5 was where it stopped moving" is a number
/// rather than a feeling.
///
/// Modelled on the dashboards the user asked for (Shotsy's Results tab): total
/// change and average weekly loss per dose step, the same per injection site,
/// and an overlay of what is on board against what the body did.
///
/// ## What this is not
///
/// **Attribution by time, not cause.** A period is credited with whatever the
/// weight did while that dose was the current one. Nothing here controls for
/// the fortnight of a stomach bug, a holiday, or the plain fact that early
/// weight loss on a GLP-1 is faster than later loss at any dose — so the first
/// rungs of a ladder flatter themselves and the last ones look weak. Every
/// surface drawing this has to say so; `MedicationResponse.caveat` is the
/// sentence, kept here so the four places that need it cannot each write their
/// own softer version.
public enum MedicationResponse {

    /// How far from a period boundary a weigh-in may be and still be taken as
    /// that boundary's weight.
    ///
    /// Ten days rather than a week: the readers this is for weigh most days,
    /// but a run of travel or a flat battery should not silently delete a whole
    /// dose step from the table. Past that the reading is describing a
    /// different fortnight and the honest answer is to have no number.
    public static let attributionTolerance: TimeInterval = 10 * 86_400

    public static let caveat = "Each dose is credited with whatever your weight did while it was the current one. That is timing, not proof — early loss on these drugs is faster at any dose, so the first steps of a ladder always look strongest."

    // MARK: - Periods

    /// One stretch during which a single dose was the most recent one taken.
    public struct Period: Sendable, Equatable {
        public let milligrams: Double
        public let site: String?
        public let start: Date
        public let end: Date
        /// The weigh-ins nearest each boundary, where there were any.
        public let startWeight: Double?
        public let endWeight: Double?

        public var days: Double { end.timeIntervalSince(start) / 86_400 }

        public init(milligrams: Double, site: String?, start: Date, end: Date,
                    startWeight: Double?, endWeight: Double?) {
            self.milligrams = milligrams
            self.site = site
            self.start = start
            self.end = end
            self.startWeight = startWeight
            self.endWeight = endWeight
        }

        /// Kilograms gained (positive) or lost (negative) across the period.
        public var change: Double? {
            guard let startWeight, let endWeight else { return nil }
            return endWeight - startWeight
        }
    }

    /// A dose step or an injection site, with what happened during it.
    public struct Group: Sendable, Equatable, Identifiable {
        /// What the row is about, already formatted — "7.5 mg", "Stomach upper left".
        public let label: String
        /// The dose in milligrams, for the rows that are dose steps. `nil` for
        /// sites, which is what keeps the two tables sorted by the right thing.
        public let milligrams: Double?
        public let doseCount: Int
        /// Whole days covered. Rounded, because a table saying "12.4 days"
        /// implies a precision that a ±10-day weigh-in tolerance does not have.
        public let days: Int
        public let totalChange: Double
        public let perWeek: Double

        public var id: String { label }

        public init(label: String, milligrams: Double?, doseCount: Int, days: Int,
                    totalChange: Double, perWeek: Double) {
            self.label = label
            self.milligrams = milligrams
            self.doseCount = doseCount
            self.days = days
            self.totalChange = totalChange
            self.perWeek = perWeek
        }
    }

    /// The whole regimen in five numbers — Shotsy's header tiles.
    public struct Overall: Sendable, Equatable {
        public let startWeight: Double
        public let latestWeight: Double
        public let weeks: Double

        public init(startWeight: Double, latestWeight: Double, weeks: Double) {
            self.startWeight = startWeight
            self.latestWeight = latestWeight
            self.weeks = weeks
        }

        public var totalChange: Double { latestWeight - startWeight }
        public var percentChange: Double {
            startWeight > 0 ? totalChange / startWeight * 100 : 0
        }
        public var perWeek: Double { weeks > 0 ? totalChange / weeks : 0 }
    }

    public struct Analysis: Sendable, Equatable {
        public let overall: Overall?
        /// Dose steps, ascending by milligrams — the ladder, in ladder order.
        public let byDose: [Group]
        /// Injection sites, biggest total change first.
        public let bySite: [Group]
        public let periods: [Period]

        public var isEmpty: Bool { byDose.isEmpty && overall == nil }

        public init(overall: Overall?, byDose: [Group], bySite: [Group],
                    periods: [Period]) {
            self.overall = overall
            self.byDose = byDose
            self.bySite = bySite
            self.periods = periods
        }
    }

    /// Attribute the weight record to the dose history.
    ///
    /// - Parameters:
    ///   - doses: every dose, inferred ones included. An inferred dose still
    ///     defines which step the reader was on; excluding them would credit a
    ///     whole titration to whichever rung they first logged by hand.
    ///   - weights: body-mass samples in kilograms.
    ///   - now: closes the final period.
    public static func analyze(doses: [AdministeredDose],
                               weights: [HealthMetricSample],
                               now: Date = Date()) -> Analysis {
        let ordered = doses.sorted { $0.takenAt < $1.takenAt }
        let readings = weights
            .filter { $0.type == .bodyMass }
            .map { (date: $0.start, value: $0.value) }
            .sorted { $0.date < $1.date }
        guard !ordered.isEmpty else {
            return Analysis(overall: nil, byDose: [], bySite: [], periods: [])
        }

        let periods = ordered.enumerated().map { index, dose -> Period in
            let end = index + 1 < ordered.count ? ordered[index + 1].takenAt : now
            return Period(milligrams: dose.milligrams,
                          site: dose.site,
                          start: dose.takenAt,
                          end: end,
                          startWeight: nearest(to: dose.takenAt, in: readings),
                          endWeight: nearest(to: end, in: readings))
        }

        return Analysis(overall: overall(doses: ordered, readings: readings),
                        byDose: grouped(periods, by: { String(format: "%g mg", $0.milligrams) },
                                        milligrams: { $0.milligrams })
                            .sorted { ($0.milligrams ?? 0) < ($1.milligrams ?? 0) },
                        bySite: grouped(periods.filter { $0.site != nil },
                                        by: { $0.site ?? "" }, milligrams: { _ in nil })
                            .sorted { abs($0.totalChange) > abs($1.totalChange) },
                        periods: periods)
    }

    /// The nearest weigh-in either side of an instant, within the tolerance.
    ///
    /// Symmetric on purpose. Taking only the last reading *before* a boundary
    /// would make a period that starts the morning after a weigh-in inherit a
    /// number from a fortnight earlier, and there is nothing to prefer about
    /// the past when both sides are equally close.
    static func nearest(to instant: Date,
                        in readings: [(date: Date, value: Double)]) -> Double? {
        let candidate = readings.min {
            abs($0.date.timeIntervalSince(instant)) < abs($1.date.timeIntervalSince(instant))
        }
        guard let candidate,
              abs(candidate.date.timeIntervalSince(instant)) <= attributionTolerance
        else { return nil }
        return candidate.value
    }

    private static func grouped(_ periods: [Period],
                                by key: (Period) -> String,
                                milligrams: (Period) -> Double?) -> [Group] {
        Dictionary(grouping: periods, by: key).compactMap { label, members in
            // A period with no bracketing weigh-in contributes its dose and its
            // days but no change — dropping it entirely would shorten the
            // denominator and inflate the per-week figure for that step.
            let withChange = members.compactMap(\.change)
            let days = members.reduce(0.0) { $0 + $1.days }
            let measuredDays = members.filter { $0.change != nil }
                .reduce(0.0) { $0 + $1.days }
            let total = withChange.reduce(0, +)
            return Group(label: label,
                         milligrams: milligrams(members[0]),
                         doseCount: members.count,
                         days: Int(days.rounded()),
                         totalChange: total,
                         perWeek: measuredDays > 0 ? total / (measuredDays / 7) : 0)
        }
    }

    private static func overall(doses: [AdministeredDose],
                                readings: [(date: Date, value: Double)]) -> Overall? {
        guard let first = doses.first?.takenAt,
              let start = readings.first(where: { $0.date >= first })
                  ?? readings.last(where: { $0.date < first }),
              let latest = readings.last,
              latest.date > start.date else { return nil }
        return Overall(startWeight: start.value,
                       latestWeight: latest.value,
                       weeks: latest.date.timeIntervalSince(start.date) / (7 * 86_400))
    }

    // MARK: - The overlay

    /// One line on the "is it working" chart.
    public struct ResponseSeries: Sendable, Equatable, Identifiable {
        public enum Kind: String, Sendable, CaseIterable, Identifiable {
            case onBoard
            case weight
            case bodyFat

            public var id: String { rawValue }

            public var title: String {
                switch self {
                case .onBoard: return "On board"
                case .weight: return "Weight"
                case .bodyFat: return "Body fat"
                }
            }

            public var unit: String {
                switch self {
                case .onBoard: return "mg"
                case .weight: return "kg"
                case .bodyFat: return "%"
                }
            }

            /// Which palette hue this line takes.
            ///
            /// Fixed here rather than chosen in the view, for the reason the
            /// `add-chart` skill gives: anything deciding whether two lines can
            /// look alike belongs where it can be tested. Three series, three
            /// slots, distinct by construction.
            public var paletteSlot: Int {
                switch self {
                case .onBoard: return 0
                case .weight: return 1
                case .bodyFat: return 2
                }
            }
        }

        public let kind: Kind
        public let points: [ResponsePoint]
        /// The window mean in real units — what "0" on the shared axis means.
        public let baseline: Double

        public var id: String { kind.rawValue }
        public var latest: ResponsePoint? { points.last }

        public init(kind: Kind, points: [ResponsePoint], baseline: Double) {
            self.kind = kind
            self.points = points
            self.baseline = baseline
        }
    }

    /// A standardised point that remembers whether it was measured.
    ///
    /// `NormalizedPoint` would do everything but the last field, and the last
    /// field is the one this app never compromises on: the on-board curve is
    /// held up by doses the reader logged in some stretches and by doses
    /// `TitrationEngine` worked out in others, and the second kind is drawn
    /// dashed wherever it appears. Losing that through the normaliser would put
    /// a guess on the chart as a solid line.
    public struct ResponsePoint: Sendable, Equatable, Identifiable {
        public let date: Date
        /// Standard deviations from this series' own mean over the window.
        public let z: Double
        /// The real value, kept for the scrub read-out — "7.42 mg", not "+1.2".
        public let raw: Double
        public let isInferred: Bool

        public var id: Date { date }

        public init(date: Date, z: Double, raw: Double, isInferred: Bool = false) {
            self.date = date
            self.z = z
            self.raw = raw
            self.isInferred = isInferred
        }
    }

    /// The three series on one axis, each standardised against its own spread.
    ///
    /// **Standardised, not dual-axed.** Milligrams, kilograms and percent share
    /// no scale, and giving each its own y-axis is the classic way to make any
    /// two lines appear to agree — `MetricOverlayChart` refuses to do it and so
    /// does this. Every line is standard deviations from its own mean over the
    /// visible window, which is the only form in which "the fat kept falling
    /// after the weight flattened" is a thing you can see rather than a thing
    /// you have to be told.
    ///
    /// A series with no spread is dropped rather than drawn flat at zero: a
    /// dead-flat line at the baseline reads as "no change measured", and for a
    /// constant series that is a coincidence of the window, not a finding.
    public static func overlay(curve: [ActiveCompoundPoint],
                               weights: [HealthMetricSample],
                               range: ClosedRange<Date>,
                               calendar: Calendar = .current) -> [ResponseSeries] {
        var series: [ResponseSeries] = []
        let onBoard = curve.filter { range.contains($0.date) }
            .map { (date: $0.date, value: $0.level, inferred: $0.restsOnInferredDose) }
        if let built = standardise(onBoard, kind: .onBoard, calendar: calendar) {
            series.append(built)
        }
        for (kind, metric) in [(ResponseSeries.Kind.weight, MetricType.bodyMass),
                               (.bodyFat, .bodyFatPercentage)] {
            let readings = weights
                .filter { $0.type == metric && range.contains($0.start) }
                .map { (date: $0.start, value: $0.value, inferred: false) }
            if let built = standardise(readings, kind: kind, calendar: calendar) {
                series.append(built)
            }
        }
        return series
    }

    /// Daily mean, then z-scored against the window.
    ///
    /// A day counts as inferred if **any** of its readings were: the honest
    /// direction to round in, since the alternative draws a guess solid.
    private static func standardise(
        _ readings: [(date: Date, value: Double, inferred: Bool)],
        kind: ResponseSeries.Kind,
        calendar: Calendar
    ) -> ResponseSeries? {
        let byDay = Dictionary(grouping: readings) { calendar.startOfDay(for: $0.date) }
        let daily = byDay.compactMap { day, group -> (date: Date, value: Double, inferred: Bool)? in
            Baseline.mean(group.map(\.value)).map {
                (date: day, value: $0, inferred: group.contains(where: \.inferred))
            }
        }.sorted { $0.date < $1.date }

        guard daily.count >= 2,
              let mean = Baseline.mean(daily.map(\.value)),
              let sd = Baseline.standardDeviation(daily.map(\.value)), sd > 0
        else { return nil }

        return ResponseSeries(
            kind: kind,
            points: daily.map {
                ResponsePoint(date: $0.date, z: ($0.value - mean) / sd,
                              raw: $0.value, isInferred: $0.inferred)
            },
            baseline: mean)
    }

    // MARK: - Side effects

    /// One symptom, tallied. Shotsy shows an average per symptom; so does this.
    public struct SideEffectTally: Sendable, Equatable, Identifiable {
        public let name: String
        public let occurrences: Int
        public let averageSeverity: Double
        public let latest: Date

        public var id: String { name }

        public init(name: String, occurrences: Int, averageSeverity: Double,
                    latest: Date) {
            self.name = name
            self.occurrences = occurrences
            self.averageSeverity = averageSeverity
            self.latest = latest
        }
    }

    /// Tally recorded side effects by name, worst-average first.
    ///
    /// Sorted by severity rather than by count deliberately: three episodes of
    /// something at 9/10 matters more than eleven at 2/10, and a table ordered
    /// by frequency buries exactly the row worth reading.
    public static func sideEffectTally(
        _ effects: [(name: String, severity: Int, date: Date)]
    ) -> [SideEffectTally] {
        Dictionary(grouping: effects, by: \.name).compactMap { name, group in
            guard let mean = Baseline.mean(group.map { Double($0.severity) }),
                  let latest = group.map(\.date).max() else { return nil }
            return SideEffectTally(name: name, occurrences: group.count,
                                   averageSeverity: mean, latest: latest)
        }
        .sorted {
            $0.averageSeverity == $1.averageSeverity
                ? $0.occurrences > $1.occurrences
                : $0.averageSeverity > $1.averageSeverity
        }
    }
}
