import Foundation

/// **What the heartbeat did while you were asleep — the stream, not the
/// summary.**
///
/// ## The gap this closes
///
/// Backlog S10, in its own words: *"Sleep is the only card grading a night that
/// reads nothing from the heartbeat stream recorded during it."* That was
/// literally true. `SleepInsight.candidateMetrics` lists duration, onset,
/// efficiency, the two stage minutes, latency, oxygen saturation, respiratory
/// rate, the breathing index and three temperatures — and not one heart
/// measurement, while the reader's own export carries 73k `heartRate` readings
/// and 8k `heartRateVariabilitySDNN` readings, most of them taken in the middle
/// of the nights the card was grading.
///
/// And backlog B3-20, from the competitive scan: **every product reports a
/// nightly summary and none draws the within-night shape.** Oura reports an
/// average HRV; Apple reports a sleeping heart rate. Neither says *when* you
/// settled, which is the part a person can act on — a night that reached its
/// floor forty minutes after lights-out and a night that took three hours are
/// different nights with the same average.
///
/// ## What this does and does not claim
///
/// It reports **where the readings fell**, binned in time from the moment sleep
/// started, and holds one night against the reader's own recent nights. It does
/// not grade a night, and `SleepInsight` does not score any of it — deliberately.
/// Two reasons, both worth stating rather than implying:
///
/// - **HRV is already scored five times over** (Readiness, Heart Health,
///   Biological Age, Energy, Vital Signs). A sixth would be double-counting one
///   measurement across cards, which is the accounting error this app has had to
///   unpick before.
/// - **No published curve grades a within-night shape for an individual.**
///   Settling time varies with age, alcohol, room temperature and the last meal;
///   the literature describes the population, not a threshold a person can be
///   held to. Trending it against the reader's own nights is honest, and the
///   moment it carried a score it would be an assertion nobody has evidence for.
///
/// ## Why the window comes from outside
///
/// A "night" is `NightSleepDetail`'s answer, passed in — the type that already
/// reconciles Oura's phase strings, Apple's per-device stage segments and the
/// window-only fallback. Re-deriving one here would give the app a second
/// definition of when the reader was asleep, and the two would disagree on
/// exactly the nights that matter (the 4.3 h / 8.5 h night this repo already
/// has a section about).
public enum OvernightCardiac {

    // MARK: - The dials, stated once

    /// How wide a bin is. Twenty minutes: fine enough that a settle inside the
    /// first hour is visible, coarse enough that a bin still holds several
    /// readings on a night the watch sampled sparsely.
    public static let bucket: TimeInterval = 20 * 60

    /// Nothing past this is drawn. A window longer than twelve hours is a source
    /// splicing a night onto a morning re-sleep, not a night.
    public static let maximumCurveHours: Double = 12

    /// The fewest readings inside a window that can describe it. Below this the
    /// "median overnight heart rate" is one or two readings wearing a statistic's
    /// name.
    public static let minimumSamplesForNight = 6

    /// The fewest prior nights that can form a typical curve. Seven, so the band
    /// spans a week rather than a couple of unusual nights.
    public static let minimumNightsForTypical = 7

    /// The fewest nights before a nightly series is worth fitting a line
    /// through. Matches `SleepOnsetModel.minimumNights` for the same reason it
    /// picked ten.
    public static let minimumNightsForTrend = 10

    /// How many recent nights the typical curve is built from. A season, not a
    /// year: a curve fitted through last winter describes a different person's
    /// sleep from this month's.
    public static let typicalNightCount = 30

    /// How close to the night's floor counts as *settled*: within a tenth of the
    /// way back up to where the night started.
    ///
    /// An operational definition, and it is stated on screen rather than hidden
    /// here. The obvious alternative — the time of the minimum itself — is worse:
    /// the minimum is one bin, it wanders with a single noisy reading, and on a
    /// flat night it lands wherever the noise did.
    public static let settledFraction = 0.10

    // MARK: - Types

    /// A night, as the sleep sections already understand one.
    public struct NightWindow: Sendable, Equatable {
        /// The wake day — `SleepOnset.night(of:)`'s key, so this lines up with
        /// every other overnight figure in the app.
        public let night: Date
        public let window: ClosedRange<Date>

        public init(night: Date, window: ClosedRange<Date>) {
            self.night = night
            self.window = window
        }
    }

    /// One bin of one night.
    public struct CurvePoint: Sendable, Equatable, Identifiable {
        /// Hours after sleep started, at the bin's centre.
        public let hours: Double
        public let value: Double
        public var id: Double { hours }

        public init(hours: Double, value: Double) {
            self.hours = hours
            self.value = value
        }
    }

    /// One bin across a stretch of nights: the middle and the spread.
    public struct Band: Sendable, Equatable, Identifiable {
        public let hours: Double
        /// Lower quartile across the nights that had a reading in this bin.
        public let low: Double
        public let median: Double
        /// Upper quartile.
        public let high: Double
        /// How many nights fed this bin — it thins out at the far end, because
        /// not every night is as long as the longest one.
        public let nights: Int
        public var id: Double { hours }

        public init(hours: Double, low: Double, median: Double, high: Double, nights: Int) {
            self.hours = hours
            self.low = low
            self.median = median
            self.high = high
            self.nights = nights
        }
    }

    /// What one quantity did across one whole window.
    public struct Summary: Sendable, Equatable {
        public let median: Double
        public let lowest: Double
        public let highest: Double
        public let count: Int

        public init(median: Double, lowest: Double, highest: Double, count: Int) {
            self.median = median
            self.lowest = lowest
            self.highest = highest
            self.count = count
        }
    }

    /// One night's worth of everything this type knows.
    public struct Night: Sendable, Equatable, Identifiable {
        public let night: Date
        public let window: ClosedRange<Date>
        public let heartRate: Summary?
        public let hrv: Summary?
        public let heartRateCurve: [CurvePoint]
        public let hrvCurve: [CurvePoint]
        /// Hours after sleep started at which the heart rate first came within
        /// `settledFraction` of the night's floor. `nil` when the rate never
        /// fell — a night spent at one level has no settling point, and putting
        /// the first bin there would report "settled immediately" for a night
        /// that never settled at all.
        public let settledAfterHours: Double?

        public var id: Date { night }
        public var hours: Double {
            window.upperBound.timeIntervalSince(window.lowerBound) / 3600
        }

        public init(night: Date, window: ClosedRange<Date>,
                    heartRate: Summary?, hrv: Summary?,
                    heartRateCurve: [CurvePoint], hrvCurve: [CurvePoint],
                    settledAfterHours: Double?) {
            self.night = night
            self.window = window
            self.heartRate = heartRate
            self.hrv = hrv
            self.heartRateCurve = heartRateCurve
            self.hrvCurve = hrvCurve
            self.settledAfterHours = settledAfterHours
        }
    }

    /// A nightly figure, keyed to the wake day.
    public struct NightlyPoint: Sendable, Equatable, Identifiable {
        public let night: Date
        public let value: Double
        public var id: Date { night }

        public init(night: Date, value: Double) {
            self.night = night
            self.value = value
        }
    }

    /// Everything the two sections need, built once.
    public struct Output: Sendable, Equatable {
        /// Oldest first.
        public let nights: [Night]

        public init(nights: [Night]) { self.nights = nights }

        public var latest: Night? { nights.last }

        /// Nights carrying an overnight HRV median, oldest first.
        public var hrvNightly: [NightlyPoint] {
            nights.compactMap { night in
                night.hrv.map { NightlyPoint(night: night.night, value: $0.median) }
            }
        }

        /// Nights carrying an overnight heart-rate floor, oldest first.
        ///
        /// The **lowest** reading rather than the median: the floor is the thing
        /// a night is usually judged on, and it is what "resting heart rate"
        /// means when a watch computes one. Both are on `Summary` for a caller
        /// that wants the other.
        public var heartRateFloorNightly: [NightlyPoint] {
            nights.compactMap { night in
                night.heartRate.map { NightlyPoint(night: night.night, value: $0.lowest) }
            }
        }

        /// Nights with a settling time, oldest first.
        public var settlingNightly: [NightlyPoint] {
            nights.compactMap { night in
                night.settledAfterHours.map { NightlyPoint(night: night.night, value: $0) }
            }
        }

        /// How far along the reader is toward a trend line, and `nil` once they
        /// are there — `CoverageGate`'s rule: a met gate says nothing.
        public var hrvCoverage: CoverageGate? {
            CoverageGate.ifShort(need: minimumNightsForTrend, have: hrvNightly.count,
                                 unit: "night with a heart-rate-variability reading during it",
                                 unlocks: "this can say whether yours is drifting rather "
                                     + "than just showing you the nights")
        }

        /// The typical curve, built from the nights **before** the one being
        /// drawn.
        ///
        /// Excluding the drawn night is the whole point: a night held against a
        /// band it is itself inside is being compared with itself, and on a
        /// short history it would pull the band far enough to hide exactly the
        /// unusual night worth noticing.
        public func typicalHeartRate(excluding night: Date) -> [Band] {
            bands(nights.filter { $0.night < night }.suffix(typicalNightCount)
                .map(\.heartRateCurve))
        }

        public func typicalHRV(excluding night: Date) -> [Band] {
            bands(nights.filter { $0.night < night }.suffix(typicalNightCount)
                .map(\.hrvCurve))
        }

        /// Nights available to form a typical curve for the given night.
        public func priorNightCount(before night: Date) -> Int {
            nights.filter { $0.night < night && !$0.heartRateCurve.isEmpty }.count
        }

        public func typicalCoverage(before night: Date) -> CoverageGate? {
            CoverageGate.ifShort(need: minimumNightsForTypical,
                                 have: priorNightCount(before: night),
                                 unit: "earlier night with a heartbeat recorded through it",
                                 unlocks: "last night can be drawn against your own usual shape")
        }

        /// The middle settling time of the nights before this one, for the
        /// sentence that says whether last night was quick or slow.
        public func typicalSettlingHours(excluding night: Date) -> Double? {
            let prior = nights.filter { $0.night < night }.compactMap(\.settledAfterHours)
            guard prior.count >= minimumNightsForTypical else { return nil }
            return Baseline.median(prior)
        }
    }

    // MARK: - Building

    /// Match the heartbeat stream to a list of nights.
    ///
    /// **Two sorted sweeps, not a filter per night.** The reader's heart-rate
    /// series is tens of thousands of readings and there are a hundred and fifty
    /// nights; filtering the whole array once per night is the shape that made
    /// `samples(of:)` worth memoising in the first place. Both inputs are sorted
    /// by time, so one pointer walks each.
    ///
    /// `hrvMetric` is a parameter because two devices report two different
    /// quantities under the same name: Apple's SDNN and Oura's rMSSD are not
    /// interchangeable and must never be pooled into one series. The caller
    /// picks whichever it has more of and the section says which.
    public static func build(windows: [NightWindow],
                             samples: [HealthMetricSample],
                             hrvMetric: MetricType = .heartRateVariabilitySDNN) -> Output {
        let ordered = windows.sorted { $0.night < $1.night }
        let heart = samples.samples(of: .heartRate)
        let hrv = samples.samples(of: hrvMetric)

        let heartByNight = assign(heart, to: ordered)
        let hrvByNight = assign(hrv, to: ordered)

        var out: [Night] = []
        out.reserveCapacity(ordered.count)
        for (index, window) in ordered.enumerated() {
            let heartValues = heartByNight[index]
            let hrvValues = hrvByNight[index]
            let heartCurve = curve(heartValues, from: window.window.lowerBound)
            out.append(Night(
                night: window.night,
                window: window.window,
                heartRate: summary(heartValues.map(\.value)),
                hrv: summary(hrvValues.map(\.value)),
                heartRateCurve: heartCurve,
                hrvCurve: curve(hrvValues, from: window.window.lowerBound),
                settledAfterHours: settling(heartCurve)))
        }
        return Output(nights: out)
    }

    /// Which readings fall inside which window, by one walk of each.
    ///
    /// Windows may overlap — two sources' accounts of one night are reconciled
    /// upstream, but nothing forbids two adjacent nights touching — so the walk
    /// restarts the reading pointer from the first reading that could still be
    /// in range rather than consuming the array. A reading in two windows is
    /// counted in both, which is the honest handling: it genuinely was recorded
    /// during both.
    static func assign(_ readings: [HealthMetricSample],
                       to windows: [NightWindow]) -> [[HealthMetricSample]] {
        var out = [[HealthMetricSample]](repeating: [], count: windows.count)
        guard !readings.isEmpty else { return out }
        var cursor = 0
        for (index, window) in windows.enumerated() {
            while cursor < readings.count && readings[cursor].start < window.window.lowerBound {
                cursor += 1
            }
            var scan = cursor
            while scan < readings.count && readings[scan].start <= window.window.upperBound {
                out[index].append(readings[scan])
                scan += 1
            }
        }
        return out
    }

    static func summary(_ values: [Double]) -> Summary? {
        guard values.count >= minimumSamplesForNight,
              let median = Baseline.median(values),
              let low = values.min(), let high = values.max() else { return nil }
        return Summary(median: median, lowest: low, highest: high, count: values.count)
    }

    /// Readings binned from the moment sleep started, each bin's median.
    ///
    /// The median rather than the mean: a single 140 bpm reading from a roll-over
    /// would drag a twenty-minute mean up by ten beats and draw a spike nobody
    /// experienced.
    static func curve(_ readings: [HealthMetricSample], from start: Date) -> [CurvePoint] {
        guard !readings.isEmpty else { return [] }
        var bins: [Int: [Double]] = [:]
        for reading in readings {
            let elapsed = reading.start.timeIntervalSince(start)
            guard elapsed >= 0, elapsed < maximumCurveHours * 3600 else { continue }
            bins[Int(elapsed / bucket), default: []].append(reading.value)
        }
        return bins.keys.sorted().compactMap { index in
            guard let median = Baseline.median(bins[index] ?? []) else { return nil }
            let centre = (Double(index) + 0.5) * bucket / 3600
            return CurvePoint(hours: centre, value: median)
        }
    }

    /// When the rate first came within `settledFraction` of the night's floor.
    ///
    /// Returns `nil` when the night opened at or below its own floor, which
    /// means the rate never came down — either the reader was already settled
    /// before the source called it sleep, or the night simply has no descent in
    /// it. Reporting the first bin in that case would say "settled immediately"
    /// for both, and only one of them is true.
    static func settling(_ curve: [CurvePoint]) -> Double? {
        guard let opening = curve.first, curve.count >= 3,
              let floor = curve.map(\.value).min(), opening.value > floor else { return nil }
        let threshold = floor + (opening.value - floor) * settledFraction
        return curve.first { $0.value <= threshold }?.hours
    }

    /// Quartiles per bin across a set of nights' curves.
    ///
    /// A bin appears only where enough nights reached it, so the band stops
    /// where the evidence does rather than tapering into a claim about one long
    /// night — the same rule `BodyModelParameters.project` applies to a
    /// forecast.
    static func bands(_ curves: [[CurvePoint]]) -> [Band] {
        guard curves.count >= minimumNightsForTypical else { return [] }
        var bins: [Double: [Double]] = [:]
        for curve in curves {
            for point in curve { bins[point.hours, default: []].append(point.value) }
        }
        // Half the nights, floored at three: a bin fed by two of thirty nights
        // is not "your typical", it is the two nights that ran that long.
        let floor = Swift.max(3, curves.count / 2)
        return bins.keys.sorted().compactMap { hours in
            let values = bins[hours] ?? []
            guard values.count >= floor,
                  let low = Baseline.quantile(0.25, of: values),
                  let median = Baseline.median(values),
                  let high = Baseline.quantile(0.75, of: values) else { return nil }
            return Band(hours: hours, low: low, median: median, high: high,
                        nights: values.count)
        }
    }

    // MARK: - Trend

    /// The fitted line through a nightly series, or `nil` while it is too short.
    ///
    /// Reuses `ScoreTrend` — including its `isMeaningful`, which is the part that
    /// matters: a slope smaller than a quarter of the night-to-night scatter is
    /// not a direction, and this app has to say "steady" rather than name one.
    public static func trend(_ points: [NightlyPoint]) -> ScoreTrend? {
        guard points.count >= minimumNightsForTrend, let first = points.first?.night
        else { return nil }
        let x = points.map { $0.night.timeIntervalSince(first) / 86_400 }
        guard let fit = Baseline.linearRegression(x: x, y: points.map(\.value))
        else { return nil }
        return ScoreTrend(slopePerWeek: fit.slope * 7, residualSD: fit.residualSD,
                          start: first, intercept: fit.intercept,
                          slopePerDay: fit.slope, sampleCount: points.count)
    }
}
