import Foundation

/// **A baseline per cycle phase — and this is a defect fix, not a feature.**
///
/// Backlog §B5 #31, `docs/activeContext.md`: *"Phase-aware baselines are a fix,
/// not an enhancement. A luteal phase raises resting heart rate and respiratory
/// rate and lowers HRV, which is exactly the pattern `HealthWatchModel` reads as
/// illness. The symptom radar must not ship to a cycling reader without them."*
///
/// The radar's whole claim is that several signals leaning the same way at once
/// is not a coincidence. In the luteal phase they lean together **every single
/// cycle**, driven by progesterone rather than by an immune response, so a
/// cycling reader gets a fortnight of "something is stirring" a month. A
/// per-phase baseline is what makes the comparison like-for-like: the luteal
/// question stops being *"is this higher than your month?"* and becomes *"is
/// this higher than your luteal phase?"*.
///
/// ## ⚠️ This is deliberately NOT wired into anything
///
/// `HealthWatchModel`, `Baseline.deviation` and the symptom radar all still use
/// the whole-window reference, unchanged. Substituting a phase-aware reference
/// underneath them would move the denominator of every z-score the radar has
/// ever recorded, and the radar's thresholds are **calibrated** — `leaningZ`,
/// `strongZ`, `channelCap`, `nullMean`, `assumedDependence` and the simulated
/// false-alarm budget in `SymptomRadarTests` are all stated against the current
/// reference. Swapping the reference without redoing that calibration would
/// leave a card whose documented alarm rate is a number about a different model.
///
/// - TODO(cycle-phase-baseline): wire this into `HealthWatchModel.signal` — the
///   reference statistics there become the phase's own — **and redo the radar's
///   calibration in the same commit**: re-derive the false-alarm simulation in
///   `SymptomRadarTests`, then re-check `leaningZ` / `strongZ` / `channelCap`
///   against it. Also needs a decision the code cannot make: what the radar
///   does for the reader who has no cycle log at all, which is every reader on
///   the current install.
///
/// ## Measured from the reader, with literature only as a prior
///
/// The shift this reports is **the difference between the reader's own phase
/// medians**, not a published effect size. Published values appear in exactly
/// one place — `literaturePriors` — and only while there is too little data to
/// measure, where they are tagged `.literaturePrior` so nothing downstream can
/// mistake them for a measurement of this person.
///
/// ## Median and MAD, for the reason `Baseline` already gives
///
/// A standard deviation has a breakdown point of zero, and a phase window is
/// short — one febrile night in a nine-day luteal window would move both the
/// centre and the spread. `Baseline.median` / `Baseline.robustScale` have a 50%
/// breakdown point, so the estimate survives a bad night without anything
/// having to be marked as bad.
public enum PhaseAwareBaseline {

    /// The phase every other phase is compared against.
    ///
    /// Follicular, because it is the phase with none of the confounds: no
    /// bleeding, no progesterone, and — in the reader's own physiology — the
    /// flattest of the four. Comparing luteal against a whole-cycle mean would
    /// compare it partly against itself.
    public static let referencePhase: CyclePhase = .follicular

    /// Daily values a phase needs before its own baseline is computed.
    ///
    /// Five. A median over fewer is a single reading wearing a robust
    /// statistic's name, and the ovulatory phase is only three days wide by
    /// construction — so it will usually need two cycles to clear this, which is
    /// the correct outcome rather than a limitation.
    public static let minimumDaysPerPhase = 5

    /// Completed cycles a phase needs contributing before its shift counts as
    /// *measured* rather than *prior*.
    ///
    /// Two. One cycle's luteal phase is one fortnight: whatever else was
    /// happening that fortnight — a cold, a holiday, a heatwave — is inside the
    /// estimate with no way to tell. Two separate cycles agreeing is the
    /// weakest evidence that the pattern is the cycle and not the month.
    ///
    /// Lower than `CyclePhaseModel.minimumCyclesForPrediction` on purpose, and
    /// it is not a loosening: **three cycles are needed before a phase can be
    /// labelled at all**, so anything reaching this test has already cleared
    /// that gate. This is the second, separate question of whether the labelled
    /// days are enough to measure a shift from.
    public static let minimumCyclesForMeasuredShift = 2

    /// One phase's centre and spread for one metric.
    public struct PhaseBaseline: Sendable, Equatable {
        public let phase: CyclePhase
        /// The phase's own median, in the metric's canonical unit.
        public let median: Double
        /// `1.4826 × MAD` — a standard deviation's scale, robustly estimated.
        public let robustScale: Double
        public let dayCount: Int
        /// How many distinct cycles contributed days. Carried because twenty
        /// luteal days from one cycle is one cycle's luteal phase.
        public let cycleCount: Int
    }

    /// How far a phase sits from the reference phase, and where that came from.
    public struct PhaseShift: Sendable, Equatable {
        public enum Basis: Sendable, Equatable {
            /// From the reader's own days.
            case measured(phaseDays: Int, referenceDays: Int, cycles: Int)
            /// From `literaturePriors`, because there is not yet enough of the
            /// reader's own data. ⚠️ Never to be rendered as the reader's own
            /// number — `PhaseShift.sentence` states the difference out loud.
            case literaturePrior
        }

        public let metric: MetricType
        public let phase: CyclePhase
        /// Phase median minus reference-phase median, in the metric's own unit.
        /// Positive means the phase runs higher.
        public let delta: Double
        /// The ± on `delta`, same unit.
        public let uncertainty: Double
        public let basis: Basis

        public var isMeasured: Bool {
            if case .measured = basis { return true }
            return false
        }
    }

    /// Every phase baseline for every requested metric, from one pass.
    public struct Profile: Sendable, Equatable {
        public let baselines: [MetricType: [CyclePhase: PhaseBaseline]]
        /// Completed cycles the profile was built over.
        public let cyclesObserved: Int

        /// Public so the app target can hold an empty one as its initial state
        /// — a stored property, per `data-conventions.md`, rather than an
        /// optional every call site has to unwrap.
        public init(baselines: [MetricType: [CyclePhase: PhaseBaseline]],
                    cyclesObserved: Int) {
            self.baselines = baselines
            self.cyclesObserved = cyclesObserved
        }

        public func baseline(metric: MetricType, phase: CyclePhase) -> PhaseBaseline? {
            baselines[metric]?[phase]
        }

        /// **The question the radar will eventually ask.** How much this metric
        /// usually moves in this phase, relative to the follicular baseline.
        ///
        /// Returns the reader's own measured shift when both phases have enough
        /// days from enough cycles; otherwise the literature prior, tagged as
        /// one; otherwise nil, because a metric with neither has nothing honest
        /// to say. The reference phase always returns a zero shift — it is the
        /// origin, and returning nil for it would make every caller special-case
        /// the one phase that is definitionally fine.
        public func expectedShift(metric: MetricType, phase: CyclePhase) -> PhaseShift? {
            if phase == referencePhase {
                let days = baseline(metric: metric, phase: phase)?.dayCount ?? 0
                let cycles = baseline(metric: metric, phase: phase)?.cycleCount ?? 0
                return PhaseShift(metric: metric, phase: phase, delta: 0, uncertainty: 0,
                                  basis: .measured(phaseDays: days, referenceDays: days,
                                                   cycles: cycles))
            }
            if let measured = measuredShift(metric: metric, phase: phase) { return measured }
            guard let prior = literaturePriors[metric]?[phase] else { return nil }
            return PhaseShift(metric: metric, phase: phase, delta: prior.delta,
                              uncertainty: prior.uncertainty, basis: .literaturePrior)
        }

        private func measuredShift(metric: MetricType, phase: CyclePhase) -> PhaseShift? {
            guard let subject = baseline(metric: metric, phase: phase),
                  let reference = baseline(metric: metric, phase: referencePhase),
                  subject.dayCount >= minimumDaysPerPhase,
                  reference.dayCount >= minimumDaysPerPhase,
                  subject.cycleCount >= minimumCyclesForMeasuredShift,
                  reference.cycleCount >= minimumCyclesForMeasuredShift
            else { return nil }

            // The ± on a difference of two medians. `medianStandardErrorFactor`
            // converts each phase's robust scale into the standard error of its
            // median; the two are then combined in quadrature, which *is* the
            // right move here — unlike the boundary arithmetic in
            // `CyclePhaseModel`, these are two independent sampling errors of
            // the same known kind.
            let subjectError = medianStandardErrorFactor * subject.robustScale
                / Double(subject.dayCount).squareRoot()
            let referenceError = medianStandardErrorFactor * reference.robustScale
                / Double(reference.dayCount).squareRoot()
            let uncertainty = (subjectError * subjectError
                               + referenceError * referenceError).squareRoot()

            return PhaseShift(metric: metric, phase: phase,
                              delta: subject.median - reference.median,
                              uncertainty: uncertainty,
                              basis: .measured(phaseDays: subject.dayCount,
                                               referenceDays: reference.dayCount,
                                               cycles: Swift.min(subject.cycleCount,
                                                                 reference.cycleCount)))
        }
    }

    /// √(π/2) ≈ 1.2533.
    ///
    /// The asymptotic standard error of a sample median is `√(π/2) · σ/√n`
    /// against the mean's `σ/√n` — the robustness is paid for with about 25%
    /// more spread on normally-distributed data. Stated rather than folded into
    /// a magic number so the cost is visible.
    static let medianStandardErrorFactor = (Double.pi / 2).squareRoot()

    /// The metrics worth splitting by phase: exactly the channels the symptom
    /// radar votes on.
    ///
    /// Deliberately derived from `HealthWatchModel.watchedMetrics` rather than
    /// listed again — this exists to fix that model's luteal false alarm, and
    /// two lists that must agree are one list that will not.
    public static var defaultMetrics: [MetricType] { HealthWatchModel.watchedMetrics }

    /// Published luteal-phase effects, used **only** while the reader's own data
    /// is too thin to measure one.
    ///
    /// Every entry is a luteal-versus-follicular difference with a stated
    /// source. The uncertainties are wide on purpose: these are population
    /// effects being applied to one person, and the honest error bar on that is
    /// larger than the one the source reports for its own mean.
    ///
    /// - **Resting heart rate, +2.0 bpm (±1.0).** Goodale et al., *JMIR mHealth
    ///   and uHealth* 2019, "Wearable Sensors Reveal Menses-Driven Changes in
    ///   Physiology" — Oura ring data across several hundred cycles, luteal
    ///   resting pulse about 2 bpm above the follicular phase. Shilaih et al.,
    ///   *Scientific Reports* 2017/2018, report the same direction and
    ///   magnitude from wrist wearables.
    /// - **rMSSD, −5.0 ms (±3.0)** and **SDNN, −4.0 ms (±3.0).** Parasympathetic
    ///   tone falls in the luteal phase; the direction is consistent across the
    ///   HRV-across-the-cycle literature and the magnitude is strongly
    ///   device- and person-dependent, hence the wide band.
    /// - **Respiratory rate, +0.3 breaths/min (±0.2).** Progesterone is a
    ///   respiratory stimulant — it raises ventilatory drive and lowers arterial
    ///   pCO₂ through the luteal phase. Classic respiratory physiology rather
    ///   than a wearable finding, which is why the effect is small and reliable.
    /// - **Skin temperature and its deviation channel, +0.30 °C (±0.15).** The
    ///   biphasic shift: basal body temperature rises 0.3–0.5 °C after
    ///   ovulation and stays up until the period. Oura's nocturnal
    ///   `skinTemperatureDeviation` reproduces it, which is what makes that
    ///   channel the strongest phase marker the app receives.
    ///
    /// **Oxygen saturation has no entry**, and that is a finding rather than an
    /// omission: no consistent luteal effect is established for it, so there is
    /// nothing to prior with. It falls through to nil until the reader's own
    /// data can answer.
    ///
    /// Only the luteal phase is priored. The menstrual phase is *observed* — a
    /// reader logging their period has those days before they have anything
    /// else — and the ovulatory phase is three days wide with effects small
    /// enough that a population figure would be mostly noise.
    static let literaturePriors: [MetricType: [CyclePhase: (delta: Double, uncertainty: Double)]] = [
        .restingHeartRate: [.luteal: (2.0, 1.0)],
        .heartRateVariabilityRMSSD: [.luteal: (-5.0, 3.0)],
        .heartRateVariabilitySDNN: [.luteal: (-4.0, 3.0)],
        .respiratoryRate: [.luteal: (0.3, 0.2)],
        .skinTemperature: [.luteal: (0.30, 0.15)],
        .skinTemperatureDeviation: [.luteal: (0.30, 0.15)]
    ]

    // MARK: - Building it

    /// Split each metric's daily series by the phase its day fell in.
    ///
    /// ⚠️ **Through `VitalReader.dailySeries`, which never blends instruments.**
    /// That is load-bearing here rather than incidental: pooling a watch and a
    /// ring makes the series' level track which device reported, and a phase
    /// split over a pooled series would recover the device-swap schedule as
    /// confidently as it recovers progesterone. `VitalReader`'s own doc comment
    /// has the measurement — the reference spread for respiratory rate is 1.77×
    /// wider pooled.
    ///
    /// - Parameter lookbackDays: How far back to read. A year by default, for
    ///   two reasons rather than for speed alone: a phase shift measured on
    ///   four-year-old nights is not this body's current physiology, and the
    ///   whole-history version pays a per-day phase lookup over every cycle ever
    ///   logged on a screen that redraws.
    public static func profile(metrics: [MetricType] = defaultMetrics,
                               samples: [HealthMetricSample],
                               summary: CycleSummary,
                               lookbackDays: Int? = 365,
                               now: Date = Date(),
                               calendar: Calendar = .current) -> Profile {
        var out: [MetricType: [CyclePhase: PhaseBaseline]] = [:]
        for metric in metrics {
            let daily = VitalReader.dailySeries(metric, from: samples, days: lookbackDays,
                                                now: now, calendar: calendar)
            guard !daily.isEmpty else { continue }

            var values: [CyclePhase: [Double]] = [:]
            var cycleStarts: [CyclePhase: Set<Date>] = [:]
            for point in daily {
                guard let estimate = CyclePhaseModel.phase(on: point.date, summary: summary,
                                                           now: now, calendar: calendar),
                      let cycle = CyclePhaseModel.cycle(containing: point.date, in: summary,
                                                        calendar: calendar)
                else { continue }
                values[estimate.phase, default: []].append(point.value)
                cycleStarts[estimate.phase, default: []].insert(cycle.start)
            }

            var byPhase: [CyclePhase: PhaseBaseline] = [:]
            for (phase, phaseValues) in values {
                guard let median = Baseline.median(phaseValues),
                      let scale = Baseline.robustScale(phaseValues) else { continue }
                byPhase[phase] = PhaseBaseline(phase: phase, median: median,
                                               robustScale: scale,
                                               dayCount: phaseValues.count,
                                               cycleCount: cycleStarts[phase]?.count ?? 0)
            }
            if !byPhase.isEmpty { out[metric] = byPhase }
        }
        return Profile(baselines: out, cyclesObserved: summary.lengths.count)
    }
}

public extension PhaseAwareBaseline.PhaseShift {

    /// The sentence a card may print. **It always says where the number came
    /// from**, because a literature prior rendered as "your resting heart rate
    /// runs +2" is the exact dishonesty this whole file exists to avoid.
    var sentence: String {
        let unit = metric.unit
        let magnitude = Swift.abs(delta)
        let direction = delta >= 0 ? "higher" : "lower"
        let figure = String(format: "%.1f", magnitude)
        let band = String(format: "%.1f", uncertainty)
        switch basis {
        case let .measured(phaseDays, _, cycles):
            return "In your \(phase.title.lowercased()) phase your \(metric.displayName.lowercased()) runs about \(figure) \(unit) \(direction) than your follicular baseline, ±\(band). Measured from \(phaseDays) of your own days across \(cycles) cycles."
        case .literaturePrior:
            return "Published figures put the \(phase.title.lowercased()) phase about \(figure) \(unit) \(direction) for \(metric.displayName.lowercased()). ⚠️ That is other people's average, not yours — there is not enough of your own data yet to measure it."
        }
    }
}
