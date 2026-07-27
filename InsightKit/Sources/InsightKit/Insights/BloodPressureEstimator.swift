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
        if systolic >= 180 || diastolic >= 120 { return "Hypertensive crisis" }
        if systolic >= 140 || diastolic >= 90 { return "Stage 2 hypertension" }
        if systolic >= 130 || diastolic >= 80 { return "Stage 1 hypertension" }
        if systolic >= 120 { return "Elevated" }
        return "Normal"
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

    public var requirements: [GroundingRequirement] {
        [
            .init(kind: .cuffSystolic, isMandatory: true,
                  rationale: "Log a real cuff reading — this is your trusted blood-pressure value."),
            .init(kind: .cuffDiastolic, isMandatory: true,
                  rationale: "The diastolic half of your cuff reading.")
        ]
    }

    public func evaluate(samples: [HealthMetricSample], profile: UserHealthProfile, now: Date) -> InsightResult {
        let unmet = unmetRequirements(profile: profile, now: now)

        // Latest trusted reading: prefer fresh grounding, else most recent sample.
        let sys = profile.cuffSystolic ?? samples.latestValue(.bloodPressureSystolic)
        let dia = profile.cuffDiastolic ?? samples.latestValue(.bloodPressureDiastolic)

        var drivers: [String] = []
        var headline = "Log a reading"
        var primary: Double? = nil
        var explanation = "Log a blood-pressure reading from a real cuff. That measured value is what the app trusts and trends over time."
        var confidence: InsightConfidence = .low

        if let s = sys, let d = dia {
            let cat = BloodPressureEstimator.category(systolic: s, diastolic: d)
            headline = "\(Int(s.rounded()))/\(Int(d.rounded()))"
            primary = s
            confidence = unmet.isEmpty ? .high : .moderate
            drivers.append("Latest cuff reading: \(Int(s.rounded()))/\(Int(d.rounded())) mmHg (\(cat))")
            explanation = "Your latest measured blood pressure is \(Int(s.rounded()))/\(Int(d.rounded())) mmHg — \(cat)."
        }

        // Experimental personalised estimate (clearly separated).
        if experimentalEstimateEnabled,
           let restHR = samples.meanValue(.restingHeartRate) {
            let currentHRV = samples.latestValue(.heartRateVariabilityRMSSD)
                ?? samples.latestValue(.heartRateVariabilitySDNN)
            let calibration = BloodPressureEstimator.buildCalibration(from: samples)
            if let est = BloodPressureEstimator.estimate(currentRestingHR: restHR, currentHRV: currentHRV, calibration: calibration) {
                drivers.append(String(format: "Experimental estimate now: %.0f/%.0f mmHg (±%.0f/±%.0f), from %d calibration readings",
                                      est.systolic, est.diastolic,
                                      est.systolicUncertainty, est.diastolicUncertainty,
                                      est.calibrationCount))
                if primary == nil {
                    headline = String(format: "~%.0f/%.0f", est.systolic, est.diastolic)
                    primary = est.systolic
                    confidence = .experimental
                    explanation = "Experimental estimate only — not a measurement. Log a cuff reading for a value you can trust."
                }
            } else {
                let have = calibration.count
                drivers.append("Experimental estimator needs \(BloodPressureEstimator.minimumCalibrationPoints) paired readings to calibrate (have \(have)).")
            }
        }

        return InsightResult(
            id: id, title: title, primaryValue: primary,
            headline: headline, score: nil, confidence: confidence,
            explanation: explanation, drivers: drivers, unmetRequirements: unmet)
    }
}
