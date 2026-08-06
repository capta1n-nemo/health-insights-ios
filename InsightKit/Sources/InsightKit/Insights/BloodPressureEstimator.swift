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

    /// Days the readings must span before a per-week slope is offered at all.
    /// Two weeks is the smallest window in which "per week" describes the
    /// pattern rather than the gap between two mornings.
    public static let minimumTrendSpanDays = 14.0

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
        //
        // And only across a spread that supports the unit it is quoted in. A
        // fit through readings a few days apart extrapolates day-to-day cuff
        // noise (±10–15 mmHg is ordinary) into a weekly figure — this shipped
        // as "trending up 49.3 mmHg per week" from readings clustered inside
        // one, a slope no living person's blood pressure sustains. Same
        // lesson as the drift counter's ±5 floor: a relative measure needs an
        // absolute companion, here a floor on the baseline it is measured over.
        let days = readings.map { $0.date.timeIntervalSince(oldest) / 86_400 }
        let spreadDays = (days.max() ?? 0) - (days.min() ?? 0)
        let perWeek = spreadDays >= Self.minimumTrendSpanDays
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
        /// How the fit's predictors divided the systolic estimate's departure
        /// from this person's own mean.
        ///
        /// Carried on the estimate rather than recomputed by the card, because
        /// working it out again means choosing between the bivariate and
        /// univariate fits a second time — and a second selection is free to
        /// pick differently from the one that produced the number on screen.
        /// Shares of the departure, not of the number: the mean itself is not
        /// attributable to either predictor.
        public let restingHRShare: Double
        /// `nil` when HRV was not in the fit at all, which is a different
        /// statement from a share of zero.
        public let hrvShare: Double?

        public init(systolic: Double, diastolic: Double,
                    systolicUncertainty: Double, diastolicUncertainty: Double,
                    calibrationCount: Int,
                    restingHRShare: Double = 1, hrvShare: Double? = nil) {
            self.systolic = systolic
            self.diastolic = diastolic
            self.systolicUncertainty = systolicUncertainty
            self.diastolicUncertainty = diastolicUncertainty
            self.calibrationCount = calibrationCount
            self.restingHRShare = restingHRShare
            self.hrvShare = hrvShare
        }
    }

    /// How much of a two-predictor estimate each predictor is responsible for.
    ///
    /// Both predictors' effects are measured as their departure from the
    /// calibration set's own mean — `b·(x − x̄)` — because that is what moves
    /// the estimate off the person's average. Split evenly when neither has
    /// departed at all: the estimate is then exactly the mean, and handing one
    /// predictor the whole of nothing would draw a full bar under a signal doing
    /// nothing.
    static func predictorShares(b1: Double, x1: Double, mean1: Double,
                                b2: Double, x2: Double, mean2: Double)
        -> (restingHR: Double, hrv: Double) {
        let e1 = abs(b1 * (x1 - mean1))
        let e2 = abs(b2 * (x2 - mean2))
        guard e1 + e2 > 0 else { return (0.5, 0.5) }
        return (e1 / (e1 + e2), e2 / (e1 + e2))
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
            let shares = predictorShares(
                b1: sFit.b1, x1: currentRestingHR,
                mean1: hr.reduce(0, +) / Double(hr.count),
                b2: sFit.b2, x2: currentHRV,
                mean2: hrvs.reduce(0, +) / Double(hrvs.count))
            return Estimate(
                systolic: sFit.a + sFit.b1 * currentRestingHR + sFit.b2 * currentHRV,
                diastolic: dFit.a + dFit.b1 * currentRestingHR + dFit.b2 * currentHRV,
                systolicUncertainty: sFit.residualSD, diastolicUncertainty: dFit.residualSD,
                calibrationCount: calibration.count,
                restingHRShare: shares.restingHR, hrvShare: shares.hrv)
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
    /// **Each number is scored on its own ladder and the worse one wins**, which
    /// is `Category.of`'s "higher of the two bands" rule made continuous.
    ///
    /// It used to pick the band from both numbers and then grade the position
    /// inside it from `systolic` alone — the comment said "by whichever number
    /// put it there", and the code only ever read one of them. When **diastolic**
    /// promoted the band, systolic sat below that band's floor, the progress
    /// term clamped to zero, and the score snapped to the new band's top:
    ///
    /// | reading | band | score |
    /// | --- | --- | --- |
    /// | 90/79.9 | normal | 100 |
    /// | 90/80.0 | stage 1 | 60 |
    ///
    /// Forty points for a tenth of a millimetre of mercury, on a quantity that
    /// moves five to ten between two cuff readings of the same arm.
    ///
    /// The ladders are the published thresholds with one score at each — so a
    /// boundary reads the same from both sides — and diastolic's run-up to 80
    /// spans the gap where its band table has no "elevated" step and systolic's
    /// does. That missing band **was** the cliff: normal's floor and stage 1's
    /// ceiling do not meet, and systolic only gets away with it by passing
    /// through elevated in between.
    ///
    /// A crisis no longer returns a flat 5. It falls from 15 to 5 across the
    /// twenty points above the threshold, because 179 and 181 are not different
    /// readings and the *category* — which is what the card says out loud — still
    /// changes at 180.
    public static func score(systolic: Double, diastolic: Double) -> Double {
        Swift.min(ScoreCurve.through(systolicLadder, at: systolic),
                  ScoreCurve.through(diastolicLadder, at: diastolic))
    }

    /// ACC/AHA systolic thresholds — 120 elevated, 130 stage 1, 140 stage 2,
    /// 180 crisis — with one score at each boundary.
    static let systolicLadder: [(input: Double, score: Double)] = [
        (90, 100), (120, 85), (130, 65), (140, 40), (180, 15), (200, 5)
    ]

    /// The diastolic thresholds — 80 stage 1, 90 stage 2, 120 crisis — carrying
    /// **the same score at each as systolic carries at its equivalent**, so
    /// neither axis is harsher than the other about the same band.
    ///
    /// The 75 anchor is this app's own and is the one invented number here. ACC/
    /// AHA gives systolic an elevated band between normal and stage 1 and gives
    /// diastolic nothing, so a faithful diastolic ladder has to fall from 100 to
    /// 65 with no landing in between — which either makes the whole normal range
    /// harsh (118/76, a healthy reading, scored 74) or puts the drop in a cliff
    /// at 80. A five-point run-up mirroring systolic's ten-point one keeps the
    /// published boundary values exactly and puts the descent somewhere
    /// defensible: 79 really is closer to stage 1 than 70 is.
    ///
    /// It is still the steepest stretch in either ladder — about four points per
    /// mmHg, so a cuff's own ±5 mmHg can move the card twenty points there. That
    /// is the band table's claim, not this curve's: the published thresholds do
    /// assert that 79 and 81 differ. What is fixed is the forty points for a
    /// tenth of a mmHg; what remains is the guidance being steep where it is
    /// steep.
    ///
    /// The low anchor is 60 rather than the bottom of the physiological range:
    /// below that the number stops being reassuring and starts being low blood
    /// pressure, which this card does not attempt to score and should not
    /// reward with a rising number.
    static let diastolicLadder: [(input: Double, score: Double)] = [
        (60, 100), (75, 85), (80, 65), (90, 40), (120, 15), (140, 5)
    ]

    /// How a reading's two numbers divide the score between them.
    ///
    /// Both determine it — `Category.of` takes the higher of the two bands they
    /// imply — so neither can be reported as the whole of it, and 50/50 would
    /// say a systolic of 175 beside a diastolic of 78 is an even split.
    ///
    /// Each number's share is how far it has travelled along **its own** axis,
    /// from the bottom of normal to the crisis line: 90→180 for systolic and
    /// 60→120 for diastolic. Separate scales because the bands do not line up —
    /// 85 is stage 1 diastolic and perfectly normal systolic, which is the same
    /// reason a chart cannot shade one set of bands for both lines.
    ///
    /// Always positive and always sums to one, so a normal reading still shows
    /// which of its numbers is carrying more. A leave-one-out against 120/80 was
    /// the obvious alternative and has the wrong shape here: it measures the
    /// *deficit*, so a reader at 112/72 has no deficit to divide and both rows
    /// would come back at zero on the best reading they have ever taken.
    static func readingShares(systolic: Double, diastolic: Double)
        -> (systolic: Double, diastolic: Double) {
        let sys = Swift.max(0.01, Swift.min(1, (systolic - 90) / 90))
        let dia = Swift.max(0.01, Swift.min(1, (diastolic - 60) / 60))
        return (sys / (sys + dia), dia / (sys + dia))
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

        // What the dial reads from — three routes, in this order.
        //
        // **A reading from the last 24 hours is today's answer and wins.** It is
        // a measurement of the quantity the card is about, and nothing modelled
        // beats one.
        //
        // **Past a day, the experimental estimate takes over**, because it is
        // the only one of the three that is a statement about *now*: it reads
        // today's resting heart rate and HRV through a regression fitted to this
        // person's own cuff readings. It ranked below the recent average until
        // 2026-08-01 and that was the wrong way round — an average of readings
        // taken over the past month answers "where has this been sitting", which
        // is a different question from the one a dial labelled with today's date
        // is asking, and it cannot move when the person does.
        //
        // **The recent average is the floor**, for whoever has cuff readings but
        // no wearable to estimate from — and because the estimate is gated on
        // being grounded, which is exactly when it should not be trusted. A
        // single aged reading is deliberately not enough for it: one reading is
        // a moment.
        let trend = BloodPressureEstimator.recentTrend(from: samples, now: now)
        let latestPair = BloodPressureEstimator.pairedReadings(from: samples).first
        let freshPair = latestPair.flatMap {
            now.timeIntervalSince($0.date) <= 24 * 3600 ? $0 : nil
        }
        let hasFreshReading = freshPair != nil

        // Both figures, so whichever one the dial does *not* show can still be
        // seen. The card is badged "Experimental" and was leading with a cuff
        // reading — badge and number disagreeing — while the estimate the badge
        // refers to could never reach the headline at all. See
        // `InsightResult.subheadline`.
        var estimatePair: (systolic: Double, diastolic: Double)?

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
        }
        // Scored from the *fresh pair's own numbers*, not from `sys`/`dia`.
        // Those prefer `profile.cuffSystolic`, which is a grounding fact with no
        // date attached to it here — so a stale profile value was being dialled
        // under a freshness test that a newer sample had passed.
        if let freshPair {
            score = BloodPressureEstimator.score(systolic: freshPair.systolic,
                                                 diastolic: freshPair.diastolic)
        }

        if let trend {
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

        // Which of the three routes the dial ended up on, so the weighting
        // section describes the number actually on screen. Set as each route
        // claims the score rather than re-derived afterwards from what is nil.
        var weighting: ScoreWeighting = .unstated
        var contributorWeights: [MetricType: Double] = [:]
        // Notes for the signals that feed a different number on this card than
        // the one on the dial — see the `contributors` block at the end.
        var contributorNotes: [MetricType: String] = [:]

        // Route one: a cuff reading from the last 24 hours. The two numbers are
        // scored against the published ACC/AHA bands, and both determine the
        // category, so both carry a share of it.
        if let freshPair {
            let shares = BloodPressureEstimator.readingShares(systolic: freshPair.systolic,
                                                              diastolic: freshPair.diastolic)
            contributorWeights[.bloodPressureSystolic] = shares.systolic
            contributorWeights[.bloodPressureDiastolic] = shares.diastolic
            weighting = .singleMeasure("the published ACC/AHA blood-pressure bands — "
                                       + "this is your own cuff reading from the last "
                                       + "24 hours, taken at face value")
        }

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
            // ⚠️ **No longer gated on `status.isGrounded`** (backlog #28,
            // 2026-08-06). The reader: *"stop hiding it behind the cuff"* — and
            // they were right that a fitted, personally-calibrated estimate
            // vanishing the moment a month goes by without a cuff reading is the
            // app refusing to say what it knows.
            //
            // What made the gate defensible was that a stale fit speaks for a
            // person it no longer describes. That is answered better by
            // `statedUncertainty`, which widens the error bar to whatever the
            // model has *measurably* been out by on this reader's own held-out
            // readings. A lapsed estimate now says "±12, and your last
            // calibration was 40 days ago" instead of disappearing — which is
            // more information, not less, and the widening comes from the
            // record rather than from a decay constant somebody chose.
            if let est = BloodPressureEstimator.estimate(currentRestingHR: restHR, currentHRV: currentHRV, calibration: calibration) {
                let drift = BloodPressureEstimator.drift(calibration: calibration, now: now)
                // **One ±, used by every line on this card.** See
                // `BloodPressureEstimator.statedUncertainty`.
                let plusMinus = BloodPressureEstimator.statedUncertainty(fit: est, drift: drift)
                drivers.append(.routine(String(format: "Experimental estimate now: %.0f/%.0f mmHg (±%.0f), from %d calibration readings",
                                               est.systolic, est.diastolic,
                                               plusMinus, est.calibrationCount)))
                if !status.isGrounded {
                    drivers.append(InsightDriver(
                        text: "This estimate is running on an older calibration — \(status.recentReadings) cuff readings in the last 30 days, against the \(status.required) that keep it current. It is still shown, with the error bar widened to what it has actually been out by. A fresh cuff reading narrows it.",
                        isNotable: true))
                }
                // The drift counter. The cadence rule ("two a month") shipped
                // without the number it exists to protect, so "log 2 more
                // readings" read the same whether the model was still tracking
                // this person or had wandered off them entirely.
                if let drift {
                    drivers.append(InsightDriver(
                        text: "Estimate accuracy — \(drift.band.lowercased()). \(drift.summary(statedUncertainty: plusMinus))",
                        isNotable: abs(drift.latestSystolicError) > plusMinus))
                }
                estimatePair = (est.systolic, est.diastolic)
                if primary == nil {
                    headline = String(format: "~%.0f/%.0f", est.systolic, est.diastolic)
                    primary = est.systolic
                    confidence = .experimental
                    explanation = "Experimental estimate only — not a measurement. Log a cuff reading for a value you can trust."
                }
                // The estimate takes the dial the moment the last cuff reading
                // is over a day old — ahead of the recent average below, which
                // is a statement about the past month rather than about now.
                if score == nil {
                    score = BloodPressureEstimator.score(systolic: est.systolic,
                                                         diastolic: est.diastolic)
                    confidence = .experimental
                    // **One cuff age too** (backlog Q2). This said "over a day
                    // old" while the drift line below said "2 days ago", about
                    // the same reading. `Drift.lastReadingPhrase` is the single
                    // source; without a drift there is no held-out history, and
                    // "over a day old" is then the only true thing to say.
                    let age = drift.map { "was \($0.lastReadingPhrase)" } ?? "is over a day old"
                    explanation += String(format: " Your last cuff reading %@, so the dial reads the experimental estimate from today's resting heart rate%@ — ~%.0f/%.0f mmHg, ±%.0f, fitted to %d of your own readings. It is a model, not a measurement: cuff again to replace it.",
                                          age,
                                          est.hrvShare == nil ? "" : " and HRV",
                                          est.systolic, est.diastolic,
                                          plusMinus, est.calibrationCount)
                    weighting = .fit("a regression through \(est.calibrationCount) of your own cuff readings and the "
                                     + (est.hrvShare == nil
                                        ? "resting heart rate recorded beside each"
                                        : "resting heart rate and HRV recorded beside each"))
                    // All four inputs carry a share here, and the split says
                    // something a reader should know: the estimate is
                    // `your own average + b1*(today's resting HR - its mean)
                    // + b2*(today's HRV - its mean)`, so **your cuff readings
                    // supply the level and today's autonomic readings supply the
                    // nudge**. That is why the estimate moves so little day to
                    // day, and why the cadence rule exists at all.
                    let calibrationShare = 1 - SupportingSignal.collectiveShare
                    let cuff = BloodPressureEstimator.readingShares(systolic: est.systolic,
                                                                    diastolic: est.diastolic)
                    contributorWeights[.bloodPressureSystolic] = cuff.systolic * calibrationShare
                    contributorWeights[.bloodPressureDiastolic] = cuff.diastolic * calibrationShare
                    let nudge = SupportingSignal.collectiveShare
                    contributorWeights[.restingHeartRate] = est.restingHRShare * nudge
                    if let hrvShare = est.hrvShare {
                        let hrvMetric: MetricType = samples.latestValue(.heartRateVariabilityRMSSD) != nil
                            ? .heartRateVariabilityRMSSD : .heartRateVariabilitySDNN
                        contributorWeights[hrvMetric] = hrvShare * nudge
                    }
                }
            } else if status.isGrounded {
                // Enough recent readings exist, but too few line up with a nearby
                // resting-HR sample to fit the model yet.
                drivers.append(.routine("Experimental estimate will appear once more of your recent readings line up with resting-heart-rate data."))
            }
        }
        // Say why, on the row, wherever an autonomic signal ends up with no
        // share. Two different reasons and they must not borrow each other's
        // words: on a cuff route the estimate is not what the dial reads, and on
        // the estimate route a signal can still be absent from the *fit* — the
        // model drops to resting-heart-rate-only until enough readings carry an
        // HRV beside them, which is a thing the reader can act on.
        // A predictor that *is* in the fit can still land on zero, when today's
        // value sits exactly on its own calibration average — it is in the
        // model and moving nothing. That is a third state and it needs its own
        // sentence, or the row shows a bare zero under a section that has just
        // promised every input carries a share.
        let estimateDrivesDial: Bool = { if case .fit = weighting { return true }; return false }()
        for metric in [MetricType.restingHeartRate, .heartRateVariabilityRMSSD,
                       .heartRateVariabilitySDNN]
        where (contributorWeights[metric] ?? 0) == 0 {
            guard estimateDrivesDial else {
                contributorNotes[metric] = " — feeds the experimental estimate, "
                    + "which isn't what your dial is reading"
                continue
            }
            contributorNotes[metric] = contributorWeights[metric] == nil
                ? " — not in the fit yet; the estimate uses resting heart rate alone "
                    + "until more of your readings have an HRV beside them"
                : " — in the fit, but sitting on your own average today, so it "
                    + "isn't moving the estimate either way"
        }

        // The floor: where blood pressure has been sitting, for whoever has cuff
        // readings and nothing to estimate from. Below the estimate rather than
        // above it since 2026-08-01 — see the routing note above.
        if score == nil, let trend {
            score = BloodPressureEstimator.score(systolic: trend.systolic,
                                                 diastolic: trend.diastolic)
            confidence = .moderate
            explanation += " Your dial reads your recent pattern — an average of \(trend.readingCount) readings over the last \(trend.spanDays) days — rather than any single measurement."
            let shares = BloodPressureEstimator.readingShares(systolic: trend.systolic,
                                                              diastolic: trend.diastolic)
            contributorWeights[.bloodPressureSystolic] = shares.systolic
            contributorWeights[.bloodPressureDiastolic] = shares.diastolic
            weighting = .singleMeasure("the published ACC/AHA blood-pressure bands, over an "
                                       + "average of \(trend.readingCount) cuff readings across "
                                       + "\(trend.spanDays) days")
        }

        // **The number the dial is not showing, with its date.**
        //
        // Whichever route claimed the headline, the other figure is the one the
        // reader has to go looking for — and on this card that mattered twice
        // over: the card is badged "Experimental" while often leading with a
        // *measured* cuff value, and `sys`/`dia` prefer `profile.cuffSystolic`,
        // a grounding fact carrying no date at all. So a reader saw a badge
        // that disagreed with the number, and a number that would not say how
        // old it was.
        //
        // The date comes from `latestPair`, the dated sample — never from the
        // profile fact, which is exactly the value that has no date to give.
        let subheadline: String? = {
            let showingEstimate = headline.hasPrefix("~")
            if showingEstimate {
                guard let latestPair else { return nil }
                let ago = RelativeDateTimeFormatter()
                ago.unitsStyle = .full
                return "Last cuff \(Int(latestPair.systolic.rounded()))/"
                    + "\(Int(latestPair.diastolic.rounded())) — "
                    + ago.localizedString(for: latestPair.date, relativeTo: now)
            }
            // The dial is on a measured reading. Show the estimate beside it so
            // the "Experimental" badge has something it can actually refer to,
            // and mark it as modelled in the same breath.
            guard let estimatePair else {
                guard let latestPair, sys != nil else { return nil }
                let ago = RelativeDateTimeFormatter()
                ago.unitsStyle = .full
                return "Cuff, \(ago.localizedString(for: latestPair.date, relativeTo: now))"
            }
            return String(format: "Estimate ~%.0f/%.0f — a model, not a measurement",
                          estimatePair.systolic, estimatePair.diastolic)
        }()

        return InsightResult(
            id: id, title: title, primaryValue: primary,
            headline: headline, subheadline: subheadline,
            score: score, confidence: confidence,
            explanation: explanation,
            driverLines: drivers.filter { $0.isNotable == true }
                + drivers.filter { $0.isNotable != true },
            unmetRequirements: unmet,
            // On the two cuff routes the autonomic pair carries nothing, and it
            // is one of only two places left in the app where a charted signal
            // has no share. The reason is specific and worth stating on the row
            // rather than leaving as a bare zero: **they feed a different number
            // on this card.** They are the estimator's inputs, the card is about
            // the estimator as well as the readings, and a measured cuff reading
            // outranks a model of one — so on those routes the estimate is not
            // what the dial reads and its inputs are not in today's number.
            contributors: [.bloodPressureSystolic, .bloodPressureDiastolic,
                           .restingHeartRate, .heartRateVariabilityRMSSD,
                           .heartRateVariabilitySDNN]
                .compactMap { metric in
                    samples.latestValue(metric).map { value in
                        let weight = contributorWeights[metric] ?? 0
                        let base = String(format: "%.0f %@", value, metric.unit)
                        let note = weight > 0 ? "" : (contributorNotes[metric] ?? "")
                        return MetricContribution(
                            metric: metric,
                            higherIsBetter: metric == .heartRateVariabilityRMSSD
                                || metric == .heartRateVariabilitySDNN,
                            weight: weight,
                            detail: base + note)
                    }
                },
            weighting: score == nil ? .unstated : weighting,
            otherFactors: Self.producedFigures(estimate: estimatePair,
                                               drivesDial: estimateDrivesDial),
            derivedOutputs: Self.derivedOutputs(estimate: estimatePair))
    }

    // MARK: - What this card works out (2026-08-06)
    //
    // **The estimate, and only the estimate.** It is a fit over the reader's own
    // paired cuff-and-wearable readings, so it is a genuinely modelled number
    // over two metrics — and it moves when the fit is refreshed even if nothing
    // was measured that day, which is what makes it a series in its own right
    // rather than a rename of resting heart rate.
    //
    // ## Refused — this card is mostly measurements
    //
    // - **`sys` / `dia` / `trend`** — cuff readings, and a mean of cuff
    //   readings. The most literal pass-through in the app: blood pressure has
    //   its own Data-tab home and its own card, and a second series called
    //   "recent pattern" would be that same number under a worse name.
    // - **Drift** (`BloodPressureEstimator` ▸ Drift) — held-out error of the
    //   fit. A property of the model rather than of the reader, and the card
    //   already renders it where it means something. Named here so the decision
    //   is not re-taken.
    // - **The ACC/AHA stage** — a category, not a quantity. `DerivedPoint`
    //   holds a `Double`, and encoding a clinical stage as 0…3 would invite
    //   exactly the arithmetic on it that the stages forbid.

    static let estimateSystolicKey = "estimatedSystolic"
    static let estimateDiastolicKey = "estimatedDiastolic"

    static func derivedOutputs(estimate: (systolic: Double, diastolic: Double)?)
        -> [DerivedOutput] {
        guard let estimate else { return [] }
        return [
            .init(key: estimateSystolicKey, displayName: "Estimated systolic",
                  unit: "mmHg", value: estimate.systolic,
                  higherIsBetter: false, precision: 0),
            .init(key: estimateDiastolicKey, displayName: "Estimated diastolic",
                  unit: "mmHg", value: estimate.diastolic,
                  higherIsBetter: false, precision: 0),
        ]
    }

    /// ⚠️ Weight 0 — see `ScoreFactor.producedFigure`, and here the zero carries
    /// a second meaning worth keeping distinct. On the estimate route the fit's
    /// shares are already on the autonomic rows; on a cuff route the estimate is
    /// not what the dial reads at all, and this row says so out loud rather than
    /// letting a reader assume the "Experimental" badge applies to their
    /// measured number.
    static func producedFigures(estimate: (systolic: Double, diastolic: Double)?,
                                drivesDial: Bool) -> [ScoreFactor] {
        guard let estimate else { return [] }
        let where_ = drivesDial
            ? "This is what the dial is reading. Its shares are on the rows above — this row is the output of them."
            : "A cuff reading outranks a model of one, so this is *not* what the dial is reading today. Kept and charted so you can watch the two against each other."
        return [
            .producedFigure(
                DerivedSeriesID(.bloodPressure, estimateSystolicKey),
                name: "Estimated blood pressure",
                detail: String(format: "~%.0f/%.0f mmHg, from a fit over your own paired readings — a model, not a measurement. %@",
                               estimate.systolic, estimate.diastolic, where_))
        ]
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

        /// How this card refers to the age of the last cuff reading, everywhere.
        ///
        /// Backlog Q2's second half: the card said "over a day old" in one place
        /// and "2 days ago" in another, about the same reading. One phrase, one
        /// source, so they cannot disagree.
        public var lastReadingPhrase: String {
            switch daysSinceLastReading {
            case 0: return "today"
            case 1: return "yesterday"
            default: return "\(daysSinceLastReading) days ago"
            }
        }

        /// One sentence, in the terms the user logged their readings in.
        ///
        /// ⚠️ **Takes the ± rather than choosing one.** It used to print
        /// `effectiveUncertainty` — this held-out fit's own spread — while the
        /// estimate line above printed the current fit's. See
        /// `BloodPressureEstimator.statedUncertainty`.
        public func summary(statedUncertainty: Double) -> String {
            let direction = latestSystolicError > 0 ? "high" : "low"
            guard abs(latestSystolicError) >= 1 else {
                return "The estimate matched your last cuff reading, taken \(lastReadingPhrase)."
            }
            return String(
                format: "At your last cuff reading (%@) the estimate read %.0f mmHg %@ on systolic, against the ±%.0f it states. Across %d checked readings it is out by %.0f mmHg on average.",
                lastReadingPhrase, abs(latestSystolicError), direction, statedUncertainty,
                checkedReadings, meanAbsoluteSystolicError)
        }
    }

    /// **The one ± this card is allowed to print.**
    ///
    /// Backlog Q2. The card used to state two on one screen — the current fit's
    /// residual SD on the estimate line ("±14, fitted to 23 readings") and a
    /// *different* fit's residual SD in the drift sentence ("against the ±13 it
    /// is judged on"). Each was defensible alone: the first is what today's
    /// regression claims, the second is what the regression that made the last
    /// held-out prediction claimed. Together they read as the card contradicting
    /// itself, and the reader had no way to know which number to believe.
    ///
    /// So there is one, and it is the **widest** of three, because an error bar
    /// is a promise and the honest promise is the weakest one that is still true:
    ///
    /// - the fit's own residual spread;
    /// - **what the model has actually been out by**, measured by holding each
    ///   reading out and predicting it from the ones before — a claim of ±5 from
    ///   a model that misses by 9 is not an error bar, it is a wish;
    /// - the ISO 81060-2 floor of ±5, because nothing here can be more precise
    ///   than the cuff that produced the training data.
    ///
    /// The measured term is what makes ungating safe (see the card): an estimate
    /// whose calibration has gone stale does not vanish, it widens — and it
    /// widens by an amount taken from this reader's own record rather than from
    /// a decay constant somebody chose.
    public static func statedUncertainty(fit: Estimate, drift: Drift?) -> Double {
        Swift.max(Swift.max(fit.systolicUncertainty, Drift.uncertaintyFloor),
                  drift?.meanAbsoluteSystolicError ?? 0)
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
