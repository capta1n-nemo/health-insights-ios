import Foundation

/// Blood pressure support. The honest design here is **grounding-first**: the
/// primary, trustworthy value is the user's *logged cuff readings* and their
/// trend. On top of that sits an **opt-in, clearly-labelled experimental
/// estimator** that only activates once the user has logged enough paired
/// readings to personally calibrate it, and that always reports its uncertainty.
///
/// This is deliberately NOT presented as a medical-grade cuffless BP monitor —
/// wearable-only BP estimation is not reliable without per-person calibration,
/// and even then is approximate. The app frames it accordingly.
public enum BloodPressureEstimator {

    /// Minimum personal calibration pairs before the estimator will produce a
    /// number at all.
    public static let minimumCalibrationPoints = 5

    /// Readings needed to complete the one-time initial calibration.
    public static let initialCalibrationReadings = 5

    /// Readings expected per month afterwards to keep the estimate grounded.
    public static let maintenanceReadingsPerMonth = 2

    /// The trailing window that defines "this month" for maintenance/freshness.
    public static let maintenanceWindow: TimeInterval = 30 * 24 * 3600

    /// How far back the personal regression may reach for calibration points.
    ///
    /// Deliberately not `maintenanceWindow`. Grounding asks "is this estimate
    /// still current?" — thirty days. The fit asks "do we have enough of this
    /// person to draw a line through?" — a different question, and answering it
    /// with thirty days is what forced the app to demand five readings every
    /// month forever just to keep the estimator alive.
    public static let calibrationFitWindow: TimeInterval = 180 * 24 * 3600

    /// A single cuff reading (systolic + diastolic) at a point in time, from any
    /// source — logged in-app, in Apple Health, or synced from Withings. This is
    /// the shared pairing used by both the reading list and calibration counting.
    public struct Reading: Sendable, Equatable, Identifiable {
        public let id: UUID
        public let date: Date
        public let systolic: Double
        public let diastolic: Double
        public let source: String
        public init(id: UUID = UUID(), date: Date, systolic: Double, diastolic: Double, source: String) {
            self.id = id; self.date = date; self.systolic = systolic
            self.diastolic = diastolic; self.source = source
        }
        public var category: String { BloodPressureEstimator.category(systolic: systolic, diastolic: diastolic) }
    }

    /// Pair every systolic sample with its nearest diastolic (within
    /// `pairingWindow`) across **all** sources, newest first. Apple Health and
    /// Withings readings are included automatically, each keeping its own date
    /// and source label.
    public static func pairedReadings(from samples: [HealthMetricSample],
                                      pairingWindow: TimeInterval = 2 * 3600) -> [Reading] {
        let systolic = samples.samples(of: .bloodPressureSystolic)
        let diastolic = samples.samples(of: .bloodPressureDiastolic)
        guard !systolic.isEmpty else { return [] }
        var out: [Reading] = []
        for s in systolic {
            guard let d = diastolic.min(by: {
                abs($0.start.timeIntervalSince(s.start)) < abs($1.start.timeIntervalSince(s.start))
            }), abs(d.start.timeIntervalSince(s.start)) <= pairingWindow else { continue }
            out.append(Reading(date: s.start, systolic: s.value, diastolic: d.value,
                               source: s.source.displayName))
        }
        return out.sorted { $0.date > $1.date }
    }

    /// Where the user is in grounding the estimate. Only readings **within the
    /// last 30 days** count toward grounding — older readings drift and expire,
    /// so the user must keep providing fresh ones. `totalReadings` is kept only
    /// for display ("N in your history").
    public struct CalibrationStatus: Sendable, Equatable {
        /// Where the user is in the calibration lifecycle.
        public enum Phase: Sendable, Equatable {
            /// `initialCalibrationReadings` have never landed inside one 30-day
            /// window.
            case initial
            /// Calibrated, and the fit window still holds enough to refit.
            case maintenance
            /// Calibrated once, but the fit window has emptied out — the
            /// regression cannot be rebuilt, so the full initial ask is honest.
            case expired
        }

        public let totalReadings: Int      // all history, for display
        public let recentReadings: Int     // last 30 days — the grounding set
        /// Readings inside `calibrationFitWindow` — what the regression can use.
        public let fittableReadings: Int
        /// Whether the initial five ever landed inside one 30-day window.
        public let hasCompletedInitial: Bool

        public init(totalReadings: Int, recentReadings: Int,
                    fittableReadings: Int = 0, hasCompletedInitial: Bool = false) {
            self.totalReadings = totalReadings
            self.recentReadings = recentReadings
            self.fittableReadings = fittableReadings
            self.hasCompletedInitial = hasCompletedInitial
        }

        public var phase: Phase {
            guard hasCompletedInitial else { return .initial }
            return fittableReadings >= BloodPressureEstimator.minimumCalibrationPoints
                ? .maintenance : .expired
        }

        /// Readings required within the grounding window.
        ///
        /// Five once, then two a month — which is what
        /// `maintenanceReadingsPerMonth` was declared for. It was never read,
        /// and this was hard-wired to `initialCalibrationReadings`, so the app
        /// demanded five readings every thirty days forever.
        public var required: Int {
            switch phase {
            case .initial, .expired: return BloodPressureEstimator.initialCalibrationReadings
            case .maintenance:       return BloodPressureEstimator.maintenanceReadingsPerMonth
            }
        }
        /// Grounded once there are enough readings *in the last 30 days*.
        public var isGrounded: Bool { recentReadings >= required }
        public var neededForGrounding: Int { max(0, required - recentReadings) }

        /// One plain-language sentence describing what to do next — the same
        /// message the app shows in Vitals, Insights and Settings.
        public var guidance: String {
            let n = neededForGrounding
            switch phase {
            case .initial:
                if isGrounded {
                    return "Grounded — \(recentReadings) cuff readings in the last 30 days. \(BloodPressureEstimator.maintenanceReadingsPerMonth) a month from here keeps it grounded."
                }
                return "\(recentReadings) of \(required) cuff readings in the last 30 days. Log \(n) more from a cuff to ground the estimate — only readings from the last 30 days count (readings already in Apple Health count too)."
            case .maintenance:
                if isGrounded {
                    return "Grounded — \(recentReadings) cuff readings in the last 30 days. \(required) a month keeps it that way."
                }
                return "\(recentReadings) of \(required) cuff readings this month. Log \(n) more to keep the estimate grounded — you've already done the one-off five."
            case .expired:
                return "It's been a while — \(recentReadings) of \(required) cuff readings in the last 30 days. Your earlier calibration is too old to fit against, so it needs the full five again."
            }
        }
    }

    /// Compute grounding status: readings within the last 30 days are the
    /// grounding set; anything older is shown as history but doesn't count
    /// toward grounding — though it may still feed the fit.
    public static func calibrationStatus(from samples: [HealthMetricSample],
                                         now: Date = Date()) -> CalibrationStatus {
        let pairs = pairedReadings(from: samples)
        let recent = pairs.filter { now.timeIntervalSince($0.date) <= maintenanceWindow }.count
        let fittable = pairs.filter { now.timeIntervalSince($0.date) <= calibrationFitWindow }.count
        return CalibrationStatus(totalReadings: pairs.count, recentReadings: recent,
                                 fittableReadings: fittable,
                                 hasCompletedInitial: completedInitialCalibration(pairs))
    }

    /// Whether `initialCalibrationReadings` ever landed inside one 30-day window.
    ///
    /// Anchored on each reading and looking *back* thirty days: the user
    /// completed the one-off calibration the moment such a window existed, and
    /// no later gap un-completes it. Whether the calibration has since gone
    /// stale is a separate question, answered by whether the fit window still
    /// holds enough points — see `CalibrationStatus.phase`.
    static func completedInitialCalibration(_ readings: [Reading]) -> Bool {
        guard readings.count >= initialCalibrationReadings else { return false }
        // `pairedReadings` returns newest-first, so from each anchor the
        // remainder of the array runs backwards in time.
        let dates = readings.map(\.date)
        for (index, anchor) in dates.enumerated() {
            let window = dates[index...].prefix { anchor.timeIntervalSince($0) <= maintenanceWindow }
            if window.count >= initialCalibrationReadings { return true }
        }
        return false
    }

    /// The recent cuff *pattern*, which is what the card is actually about.
    ///
    /// A single reading is a moment: it moves with a rushed morning, a coffee,
    /// a cuff on the wrong arm. The clinical question — and the one the card
    /// asks — is where someone's blood pressure is sitting lately, which is why
    /// the dial reads from this rather than from whichever reading happens to be
    /// newest. It also means someone who cuffs weekly still sees a number, where
    /// before the dial was blank six days in seven.
    public struct Trend: Sendable, Equatable {
        /// Mean systolic across the window — the level being scored.
        public let systolic: Double
        public let diastolic: Double
        public let readingCount: Int
        /// Oldest reading in the window, so the card can say what it covered.
        public let spanDays: Int
        /// Change in systolic per week across the window, when there is enough
        /// spread in time to fit one. Positive is rising.
        public let systolicPerWeek: Double?

        public var category: String {
            BloodPressureEstimator.category(systolic: systolic, diastolic: diastolic)
        }
    }

    /// The recent cuff pattern, or nil when there are too few readings to
    /// describe one.
    ///
    /// Two readings is the floor: one is a moment, not a pattern, and averaging
    /// a single reading would just be the old behaviour wearing a new word.
    public static func recentTrend(from samples: [HealthMetricSample],
                                   now: Date = Date(),
                                   window: TimeInterval = maintenanceWindow,
                                   minimumReadings: Int = 2) -> Trend? {
        let readings = pairedReadings(from: samples)
            .filter { now.timeIntervalSince($0.date) <= window && $0.date <= now }
        guard readings.count >= minimumReadings,
              let systolic = Baseline.mean(readings.map(\.systolic)),
              let diastolic = Baseline.mean(readings.map(\.diastolic)),
              let oldest = readings.map(\.date).min() else { return nil }

        // Drift in mmHg per week, fitted against real elapsed time rather than
        // sample index — cuff readings are irregular, so an index regression
        // would report a slope per *reading*, which means nothing.
        let days = readings.map { $0.date.timeIntervalSince(oldest) / 86_400 }
        let perWeek = Set(days).count >= 2
            ? Baseline.linearRegression(x: days, y: readings.map(\.systolic)).map { $0.slope * 7 }
            : nil

        return Trend(systolic: systolic, diastolic: diastolic,
                     readingCount: readings.count,
                     spanDays: Swift.max(1, Int((now.timeIntervalSince(oldest) / 86_400).rounded())),
                     systolicPerWeek: perWeek)
    }

    /// A cuff reading paired with contemporaneous features (resting HR, and
    /// optionally HRV, which correlates with vascular tone / BP).
    public struct CalibrationPoint: Sendable, Equatable {
        public let restingHR: Double
        public let hrv: Double?
        public let systolic: Double
        public let diastolic: Double
        public let date: Date
        public init(restingHR: Double, hrv: Double? = nil, systolic: Double, diastolic: Double, date: Date) {
            self.restingHR = restingHR; self.hrv = hrv; self.systolic = systolic
            self.diastolic = diastolic; self.date = date
        }
    }

    public struct Estimate: Sendable, Equatable {
        public let systolic: Double
        public let diastolic: Double
        /// ± mmHg, one residual standard deviation of the personal fit.
        public let systolicUncertainty: Double
        public let diastolicUncertainty: Double
        public let calibrationCount: Int
    }

    /// Ordinary least squares y = a + b·x, returning slope, intercept and the
    /// residual standard deviation (a simple uncertainty proxy).
    static func linearFit(x: [Double], y: [Double]) -> (slope: Double, intercept: Double, residualSD: Double)? {
        guard x.count == y.count, x.count >= 2 else { return nil }
        let n = Double(x.count)
        let mx = x.reduce(0, +) / n
        let my = y.reduce(0, +) / n
        var sxx = 0.0, sxy = 0.0
        for i in 0..<x.count {
            sxx += (x[i] - mx) * (x[i] - mx)
            sxy += (x[i] - mx) * (y[i] - my)
        }
        guard sxx > 0 else { return nil }
        let slope = sxy / sxx
        let intercept = my - slope * mx
        // Residual SD (n-2 dof when possible).
        var ss = 0.0
        for i in 0..<x.count {
            let pred = intercept + slope * x[i]
            ss += (y[i] - pred) * (y[i] - pred)
        }
        let dof = max(1.0, n - 2)
        return (slope, intercept, (ss / dof).squareRoot())
    }

    /// Personalised estimate of current BP from resting HR (and HRV when
    /// available), or nil if there isn't enough calibration data. With ≥6 points
    /// that all carry HRV, it fits a two-feature model (resting HR + HRV);
    /// otherwise it falls back to resting-HR-only, and finally to the user's own
    /// mean. Always reports uncertainty.
    public static func estimate(currentRestingHR: Double, currentHRV: Double? = nil,
                                calibration: [CalibrationPoint]) -> Estimate? {
        guard calibration.count >= minimumCalibrationPoints else { return nil }
        let hr = calibration.map(\.restingHR)
        let sys = calibration.map(\.systolic)
        let dia = calibration.map(\.diastolic)
        let meanSys = sys.reduce(0, +) / Double(sys.count)
        let meanDia = dia.reduce(0, +) / Double(dia.count)

        // Prefer the bivariate model when HRV is present everywhere and we have
        // enough points to support two predictors.
        let hrvs = calibration.compactMap(\.hrv)
        if let currentHRV, hrvs.count == calibration.count, calibration.count >= 6,
           let sFit = bivariateFit(x1: hr, x2: hrvs, y: sys),
           let dFit = bivariateFit(x1: hr, x2: hrvs, y: dia) {
            return Estimate(
                systolic: sFit.a + sFit.b1 * currentRestingHR + sFit.b2 * currentHRV,
                diastolic: dFit.a + dFit.b1 * currentRestingHR + dFit.b2 * currentHRV,
                systolicUncertainty: sFit.residualSD, diastolicUncertainty: dFit.residualSD,
                calibrationCount: calibration.count)
        }

        let sFit = linearFit(x: hr, y: sys)
        let dFit = linearFit(x: hr, y: dia)
        let estSys = sFit.map { $0.intercept + $0.slope * currentRestingHR } ?? meanSys
        let estDia = dFit.map { $0.intercept + $0.slope * currentRestingHR } ?? meanDia
        let uSys = sFit?.residualSD ?? (Baseline.standardDeviation(sys) ?? 8)
        let uDia = dFit?.residualSD ?? (Baseline.standardDeviation(dia) ?? 6)
        return Estimate(systolic: estSys, diastolic: estDia,
                        systolicUncertainty: uSys, diastolicUncertainty: uDia,
                        calibrationCount: calibration.count)
    }

    /// Two-feature ordinary least squares y = a + b1·x1 + b2·x2 via the normal
    /// equations, with a residual standard deviation. Returns nil if the system
    /// is degenerate (e.g. collinear features).
    static func bivariateFit(x1: [Double], x2: [Double], y: [Double])
        -> (a: Double, b1: Double, b2: Double, residualSD: Double)? {
        let n = x1.count
        guard n == x2.count, n == y.count, n >= 3 else { return nil }
        let nd = Double(n)
        // Centre the predictors for numerical stability; recover intercept after.
        let m1 = x1.reduce(0, +) / nd, m2 = x2.reduce(0, +) / nd, my = y.reduce(0, +) / nd
        var s11 = 0.0, s22 = 0.0, s12 = 0.0, s1y = 0.0, s2y = 0.0
        for i in 0..<n {
            let a1 = x1[i] - m1, a2 = x2[i] - m2, ay = y[i] - my
            s11 += a1 * a1; s22 += a2 * a2; s12 += a1 * a2
            s1y += a1 * ay; s2y += a2 * ay
        }
        let det = s11 * s22 - s12 * s12
        guard abs(det) > 1e-9 else { return nil }
        let b1 = (s22 * s1y - s12 * s2y) / det
        let b2 = (s11 * s2y - s12 * s1y) / det
        let a = my - b1 * m1 - b2 * m2
        var ss = 0.0
        for i in 0..<n {
            let pred = a + b1 * x1[i] + b2 * x2[i]
            ss += (y[i] - pred) * (y[i] - pred)
        }
        let dof = max(1.0, nd - 3)
        return (a, b1, b2, (ss / dof).squareRoot())
    }

    /// Build calibration points by pairing each systolic reading with the
    /// diastolic reading at the same instant and the nearest resting-HR sample
    /// within `window`.
    public static func buildCalibration(from samples: [HealthMetricSample], window: TimeInterval = 24 * 3600) -> [CalibrationPoint] {
        let systolic = samples.samples(of: .bloodPressureSystolic)
        let diastolic = samples.samples(of: .bloodPressureDiastolic)
        let restingHR = samples.samples(of: .restingHeartRate)
        let hrvSamples = samples.samples(of: .heartRateVariabilityRMSSD).isEmpty
            ? samples.samples(of: .heartRateVariabilitySDNN)
            : samples.samples(of: .heartRateVariabilityRMSSD)
        guard !systolic.isEmpty, !restingHR.isEmpty else { return [] }

        func nearest(_ series: [HealthMetricSample], to date: Date) -> HealthMetricSample? {
            guard let best = series.min(by: {
                abs($0.start.timeIntervalSince(date)) < abs($1.start.timeIntervalSince(date))
            }), abs(best.start.timeIntervalSince(date)) <= window else { return nil }
            return best
        }

        var points: [CalibrationPoint] = []
        for s in systolic {
            guard let d = nearest(diastolic, to: s.start),
                  let hr = nearest(restingHR, to: s.start) else { continue }
            let hrv = nearest(hrvSamples, to: s.start)?.value
            points.append(.init(restingHR: hr.value, hrv: hrv,
                                systolic: s.value, diastolic: d.value, date: s.start))
        }
        return points
    }

    /// Simple ACC/AHA-style category from a systolic/diastolic pair.
    public static func category(systolic: Double, diastolic: Double) -> String {
        Category.of(systolic: systolic, diastolic: diastolic).displayName
    }

    /// A 0–100 dial figure for a reading, from the ACC/AHA band it falls in.
    ///
    /// The card previously passed `score: nil` unconditionally, so blood
    /// pressure was the one insight with a measured value and no score on its
    /// bubble. The bands are the honest basis for one: they're published
    /// thresholds, not a weighting this app invented.
    ///
    /// Graded within each band rather than flat, so 121/79 and 129/79 don't read
    /// identically — a reading drifting up through "elevated" should show it.
    public static func score(systolic: Double, diastolic: Double) -> Double {
        let band = Category.of(systolic: systolic, diastolic: diastolic)
        let (top, bottom, low, high): (Double, Double, Double, Double)
        switch band {
        case .normal:  (top, bottom, low, high) = (100, 85, 90, 120)
        case .elevated:(top, bottom, low, high) = (80, 65, 120, 130)
        case .stage1:  (top, bottom, low, high) = (60, 40, 130, 140)
        case .stage2:  (top, bottom, low, high) = (35, 15, 140, 180)
        case .crisis:  return 5
        }
        // Position within the band, by whichever number put it there.
        let progress = Swift.max(0, Swift.min(1, (systolic - low) / Swift.max(1, high - low)))
        return top - (top - bottom) * progress
    }

    /// The ACC/AHA bands as data rather than a string, so the UI can colour a
    /// reading and show where it sits among the rest.
    public enum Category: String, Sendable, CaseIterable, Comparable {
        case normal, elevated, stage1, stage2, crisis

        public var displayName: String {
            switch self {
            case .normal: return "Normal"
            case .elevated: return "Elevated"
            case .stage1: return "Stage 1 hypertension"
            case .stage2: return "Stage 2 hypertension"
            case .crisis: return "Hypertensive crisis"
            }
        }

        /// Where this band sits on a systolic axis, as a half-open range.
        ///
        /// Exposed so a chart can shade the bands rather than restating the
        /// thresholds beside the ones in `of(systolic:diastolic:)` — two copies
        /// of a clinical threshold is one copy too many. `nil` upper bound means
        /// "and above".
        public var systolicRange: (lower: Double, upper: Double?) {
            switch self {
            case .normal: return (0, 120)
            case .elevated: return (120, 130)
            case .stage1: return (130, 140)
            case .stage2: return (140, 180)
            case .crisis: return (180, nil)
            }
        }

        /// The same bands on a diastolic axis. They do **not** line up with the
        /// systolic ones — 85 is stage 1 diastolic and perfectly normal
        /// systolic — which is why a chart plotting both on one axis cannot
        /// shade a single set of bands and call it correct for both lines.
        public var diastolicRange: (lower: Double, upper: Double?) {
            switch self {
            // Elevated is defined by systolic alone; diastolic has no such band.
            case .normal, .elevated: return (0, 80)
            case .stage1: return (80, 90)
            case .stage2: return (90, 120)
            case .crisis: return (120, nil)
            }
        }

        /// A reading falls in the *higher* of the bands its two numbers imply —
        /// the standard rule, and the safe direction to err in.
        public static func of(systolic: Double, diastolic: Double) -> Category {
            if systolic >= 180 || diastolic >= 120 { return .crisis }
            if systolic >= 140 || diastolic >= 90 { return .stage2 }
            if systolic >= 130 || diastolic >= 80 { return .stage1 }
            if systolic >= 120 { return .elevated }
            return .normal
        }

        private var rank: Int { Self.allCases.firstIndex(of: self) ?? 0 }
        public static func < (a: Category, b: Category) -> Bool { a.rank < b.rank }
    }

    /// Diastolic plus a third of the pulse pressure — the average pressure over
    /// a cardiac cycle, weighted towards diastole because the heart spends
    /// longer there.
    public static func meanArterialPressure(systolic: Double, diastolic: Double) -> Double {
        diastolic + (systolic - diastolic) / 3
    }

    /// Splits readings into those still counting towards grounding and those
    /// that are only history.
    ///
    /// Only the last `maintenanceWindow` counts, so this is what keeps an older
    /// reading visible without letting it prop up the calibration.
    public static func split(_ readings: [Reading], now: Date = Date())
        -> (recent: [Reading], earlier: [Reading]) {
        var recent: [Reading] = []
        var earlier: [Reading] = []
        for reading in readings {
            if now.timeIntervalSince(reading.date) <= maintenanceWindow {
                recent.append(reading)
            } else {
                earlier.append(reading)
            }
        }
        return (recent, earlier)
    }
}

public extension BloodPressureEstimator.Reading {
    var categoryValue: BloodPressureEstimator.Category {
        .of(systolic: systolic, diastolic: diastolic)
    }

    var meanArterialPressure: Double {
        BloodPressureEstimator.meanArterialPressure(systolic: systolic, diastolic: diastolic)
    }
}

/// `InsightModel` adapter. Shows the latest logged cuff reading + category, and,
/// when enough calibration exists, an experimental estimate with uncertainty.
public struct BloodPressureInsight: InsightModel {
    public let id: InsightID = .bloodPressure
    public let title = "Blood Pressure"
    /// Whether to surface the experimental estimator at all.
    public let experimentalEstimateEnabled: Bool

    public init(experimentalEstimateEnabled: Bool = true) {
        self.experimentalEstimateEnabled = experimentalEstimateEnabled
    }

    public var candidateMetrics: [MetricType] {
        [.bloodPressureSystolic, .bloodPressureDiastolic, .restingHeartRate,
         .heartRateVariabilityRMSSD, .heartRateVariabilitySDNN]
    }

    public var requirements: [GroundingRequirement] {
        [
            .init(kind: .cuffSystolic, isMandatory: true,
                  rationale: "Log a real cuff reading — this is your trusted blood-pressure value."),
            .init(kind: .cuffDiastolic, isMandatory: true,
                  rationale: "The diastolic half of your cuff reading.")
        ]
    }

    /// The dated log, **not** the two grounding facts the derived default would
    /// produce.
    ///
    /// `requirements` names `.cuffSystolic` and `.cuffDiastolic` because that is
    /// how the grounding *prompt* works, but what this card actually takes is a
    /// reading with a date on it, calibrating towards a target. Rendering it as
    /// two profile facts would offer the user a single latest number where the
    /// model wants a series — and would hide the calibration progress that says
    /// how many more are needed.
    public var contributions: [ContributionRoute] { [.bloodPressureReadings] }

    public func evaluate(samples: [HealthMetricSample], profile: UserHealthProfile, now: Date) -> InsightResult {
        // Latest trusted reading: prefer fresh grounding, else most recent sample.
        let sys = profile.cuffSystolic ?? samples.latestValue(.bloodPressureSystolic)
        let dia = profile.cuffDiastolic ?? samples.latestValue(.bloodPressureDiastolic)

        // Cuff readings already in Apple Health (or Withings) satisfy the "log a
        // reading" requirement — the user shouldn't be asked to re-enter what
        // the phone already has.
        let status = BloodPressureEstimator.calibrationStatus(from: samples, now: now)
        var unmet = unmetRequirements(profile: profile, now: now)
        if status.totalReadings > 0 || (sys != nil && dia != nil) {
            unmet.removeAll { $0.kind == .cuffSystolic || $0.kind == .cuffDiastolic }
        }

        // The reading itself leads when it's out of range; calibration guidance
        // and the experimental estimate are context, and the estimate is not a
        // finding on any reading of the word.
        var drivers: [InsightDriver] = []
        var headline = "Log a reading"
        var primary: Double? = nil
        var explanation = "Log a blood-pressure reading from a real cuff. That measured value is what the app trusts and trends over time."
        var confidence: InsightConfidence = .low

        // What the dial reads from.
        //
        // A reading from the last 24 hours is today's answer and wins. Failing
        // that, the *recent pattern* — because blood pressure is a level, not an
        // event, and the previous rule (24 hours or nothing) left anyone who
        // cuffs weekly staring at an empty bubble six days in seven. A single
        // aged reading is deliberately not enough: one reading is a moment.
        let trend = BloodPressureEstimator.recentTrend(from: samples, now: now)
        let latestPair = BloodPressureEstimator.pairedReadings(from: samples).first
        let hasFreshReading = latestPair.map { now.timeIntervalSince($0.date) <= 24 * 3600 } ?? false

        var score: Double?
        if let s = sys, let d = dia {
            let cat = BloodPressureEstimator.category(systolic: s, diastolic: d)
            headline = "\(Int(s.rounded()))/\(Int(d.rounded()))"
            primary = s
            confidence = unmet.isEmpty ? .high : .moderate
            drivers.append(InsightDriver(
                text: "Latest cuff reading: \(Int(s.rounded()))/\(Int(d.rounded())) mmHg (\(cat))",
                isNotable: cat != "Normal"))
            explanation = "Your latest measured blood pressure is \(Int(s.rounded()))/\(Int(d.rounded())) mmHg — \(cat)."

            if hasFreshReading {
                score = BloodPressureEstimator.score(systolic: s, diastolic: d)
            }
        }

        if let trend {
            if score == nil {
                // The card is now about where blood pressure has been sitting,
                // and says so rather than implying the number is from today.
                score = BloodPressureEstimator.score(systolic: trend.systolic,
                                                     diastolic: trend.diastolic)
                confidence = .moderate
                explanation += " Your dial reads your recent pattern — an average of \(trend.readingCount) readings over the last \(trend.spanDays) days — rather than any single measurement."
            }
            if !hasFreshReading {
                drivers.append(InsightDriver(
                    text: String(format: "Recent average: %.0f/%.0f mmHg across %d readings in %d days (%@)",
                                 trend.systolic, trend.diastolic, trend.readingCount,
                                 trend.spanDays, trend.category),
                    isNotable: trend.category != "Normal"))
            }
            // A drift worth naming. Half a mmHg a week is roughly 6 over a
            // season, which is the scale at which a trend becomes a finding.
            if let perWeek = trend.systolicPerWeek, abs(perWeek) >= 0.5 {
                drivers.append(InsightDriver(
                    text: String(format: "Systolic trending %@ %.1f mmHg per week",
                                 perWeek > 0 ? "up" : "down", abs(perWeek)),
                    // Falling blood pressure is good news and belongs with the
                    // routine lines, not the alarms.
                    isNotable: perWeek > 0))
            }
        }

        // Calibration expectation, grounded in readings already on the device.
        drivers.append(InsightDriver(text: status.guidance, isNotable: !status.isGrounded))

        // Experimental personalised estimate (clearly separated). Only grounded
        // in the last 30 days of readings, matching the calibration rules.
        if experimentalEstimateEnabled,
           let restHR = samples.meanValue(.restingHeartRate) {
            let currentHRV = samples.latestValue(.heartRateVariabilityRMSSD)
                ?? samples.latestValue(.heartRateVariabilitySDNN)
            // The fit reaches back six months; *grounding* — five once, then two
            // a month — is what says the fit still describes this person now.
            // Without that gate, widening the fit window would let a half-year-old
            // regression speak for today.
            let fittableSamples = samples.filter {
                now.timeIntervalSince($0.start) <= BloodPressureEstimator.calibrationFitWindow
            }
            let calibration = BloodPressureEstimator.buildCalibration(from: fittableSamples)
            if status.isGrounded,
               let est = BloodPressureEstimator.estimate(currentRestingHR: restHR, currentHRV: currentHRV, calibration: calibration) {
                drivers.append(.routine(String(format: "Experimental estimate now: %.0f/%.0f mmHg (±%.0f/±%.0f), from %d recent calibration readings",
                                               est.systolic, est.diastolic,
                                               est.systolicUncertainty, est.diastolicUncertainty,
                                               est.calibrationCount)))
                // The drift counter. The cadence rule ("two a month") shipped
                // without the number it exists to protect, so "log 2 more
                // readings" read the same whether the model was still tracking
                // this person or had wandered off them entirely.
                if let drift = BloodPressureEstimator.drift(calibration: calibration, now: now) {
                    drivers.append(InsightDriver(
                        text: "Estimate accuracy — \(drift.band.lowercased()). \(drift.summary)",
                        isNotable: !drift.isWithinStatedUncertainty))
                }
                if primary == nil {
                    headline = String(format: "~%.0f/%.0f", est.systolic, est.diastolic)
                    primary = est.systolic
                    confidence = .experimental
                    explanation = "Experimental estimate only — not a measurement. Log a cuff reading for a value you can trust."
                }
                if score == nil {
                    score = BloodPressureEstimator.score(systolic: est.systolic,
                                                         diastolic: est.diastolic)
                }
            } else if status.isGrounded {
                // Enough recent readings exist, but too few line up with a nearby
                // resting-HR sample to fit the model yet.
                drivers.append(.routine("Experimental estimate will appear once more of your recent readings line up with resting-heart-rate data."))
            }
        }

        return InsightResult(
            id: id, title: title, primaryValue: primary,
            headline: headline, score: score, confidence: confidence,
            explanation: explanation,
            driverLines: drivers.filter { $0.isNotable == true }
                + drivers.filter { $0.isNotable != true },
            unmetRequirements: unmet,
            contributors: [.bloodPressureSystolic, .bloodPressureDiastolic,
                           .restingHeartRate, .heartRateVariabilityRMSSD,
                           .heartRateVariabilitySDNN]
                .compactMap { metric in
                    samples.latestValue(metric).map {
                        // Weight 0: a cuff reading is trusted outright, and the
                        // experimental estimate is not a weighted blend.
                        MetricContribution(metric: metric,
                                           higherIsBetter: metric == .heartRateVariabilityRMSSD
                                               || metric == .heartRateVariabilitySDNN,
                                           weight: 0,
                                           detail: String(format: "%.0f %@", $0, metric.unit))
                    }
                })
    }
}

// MARK: - Drift

public extension BloodPressureEstimator {

    /// How far the estimate has wandered from the cuff, and how long since
    /// anything checked.
    ///
    /// The cadence rule — five readings to ground, then two per thirty days —
    /// shipped without the number it exists to protect. A user being told to
    /// cuff again had no way to see *why*: whether the model was still tracking
    /// them well and this was routine maintenance, or whether it had drifted and
    /// the reminder was urgent. Those are different situations and they read
    /// identically as "log 2 more readings".
    ///
    /// Drift is measured the only honest way available: **hold out each cuff
    /// reading, fit on the ones before it, and compare.** Scoring the fit
    /// against readings it was fitted through would report how well least
    /// squares interpolates, which is not a question anybody asked and always
    /// flatters.
    struct Drift: Sendable, Equatable {
        /// Signed error at the most recent held-out reading, in mmHg. Positive
        /// means the estimate read *higher* than the cuff.
        public let latestSystolicError: Double
        public let latestDiastolicError: Double
        /// Mean absolute systolic error across every held-out reading.
        public let meanAbsoluteSystolicError: Double
        /// How many readings could be held out and checked.
        public let checkedReadings: Int
        /// Days since the last cuff reading of any kind.
        public let daysSinceLastReading: Int

        /// How the error compares with the fit's own claimed uncertainty.
        ///
        /// An estimate that says "±8" and is out by 6 is behaving exactly as
        /// advertised; one out by 20 is not. Expressing drift against the
        /// model's own stated spread is what stops this being a bare number
        /// nobody can calibrate their reaction to.
        public let systolicUncertainty: Double

        /// The narrowest uncertainty this comparison will credit, in mmHg.
        ///
        /// A least-squares fit through a handful of points can return a residual
        /// SD of nearly zero — and exactly zero for a person whose readings
        /// happen to sit on a line — at which point every subsequent millimetre
        /// reads as catastrophic drift, or the ratio divides by zero outright.
        ///
        /// Five, because that is the accuracy the *cuff* is held to: ISO 81060-2
        /// validates a monitor at a mean error within ±5 mmHg. A model claiming
        /// to predict blood pressure more precisely than the instrument that
        /// measured it is claiming something no amount of fitting can support,
        /// so the comparison declines to believe it.
        public static let uncertaintyFloor: Double = 5

        /// What the error is actually judged against.
        public var effectiveUncertainty: Double {
            Swift.max(systolicUncertainty, Self.uncertaintyFloor)
        }

        /// True when the latest error is inside what the fit claims. The
        /// interesting state is the false one.
        public var isWithinStatedUncertainty: Bool {
            abs(latestSystolicError) <= effectiveUncertainty
        }

        public var band: String {
            switch abs(latestSystolicError) / effectiveUncertainty {
            case ..<1:   return "Tracking"
            case 1..<2:  return "Drifting"
            default:     return "Off"
            }
        }

        /// One sentence, in the terms the user logged their readings in.
        public var summary: String {
            let direction = latestSystolicError > 0 ? "high" : "low"
            let days = daysSinceLastReading
            let since = days == 0 ? "today"
                : days == 1 ? "yesterday" : "\(days) days ago"
            guard abs(latestSystolicError) >= 1 else {
                return "The estimate matched your last cuff reading, taken \(since)."
            }
            return String(
                format: "At your last cuff reading (%@) the estimate read %.0f mmHg %@ on systolic, against the ±%.0f it is judged on. Across %d checked readings it is out by %.0f mmHg on average.",
                since, abs(latestSystolicError), direction, effectiveUncertainty,
                checkedReadings, meanAbsoluteSystolicError)
        }
    }

    /// Held-out drift over the calibration set, or nil when there is not enough
    /// history to hold anything out.
    ///
    /// Needs one more reading than the fit itself does: the last one is the one
    /// being predicted, so it cannot also be in the training set.
    static func drift(calibration: [CalibrationPoint], now: Date = Date()) -> Drift? {
        let ordered = calibration.sorted { $0.date < $1.date }
        guard ordered.count > minimumCalibrationPoints,
              let last = ordered.last else { return nil }

        var systolicErrors: [Double] = []
        var latest: (systolic: Double, diastolic: Double, uncertainty: Double)?
        // Every reading that has at least a full fit's worth of history before
        // it, predicted from that history alone.
        for index in minimumCalibrationPoints..<ordered.count {
            let history = Array(ordered[..<index])
            let held = ordered[index]
            guard let predicted = estimate(currentRestingHR: held.restingHR,
                                           currentHRV: held.hrv,
                                           calibration: history) else { continue }
            systolicErrors.append(predicted.systolic - held.systolic)
            if index == ordered.count - 1 {
                latest = (predicted.systolic - held.systolic,
                          predicted.diastolic - held.diastolic,
                          predicted.systolicUncertainty)
            }
        }
        guard let latest, !systolicErrors.isEmpty else { return nil }

        return Drift(
            latestSystolicError: latest.systolic,
            latestDiastolicError: latest.diastolic,
            meanAbsoluteSystolicError: systolicErrors.map(abs).reduce(0, +)
                / Double(systolicErrors.count),
            checkedReadings: systolicErrors.count,
            daysSinceLastReading: Swift.max(0, Int(
                (now.timeIntervalSince(last.date) / 86_400).rounded(.down))),
            systolicUncertainty: latest.uncertainty)
    }
}
