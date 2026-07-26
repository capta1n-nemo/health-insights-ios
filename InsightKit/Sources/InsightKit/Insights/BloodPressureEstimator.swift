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

    /// A cuff reading paired with a contemporaneous feature (resting HR).
    public struct CalibrationPoint: Sendable, Equatable {
        public let restingHR: Double
        public let systolic: Double
        public let diastolic: Double
        public let date: Date
        public init(restingHR: Double, systolic: Double, diastolic: Double, date: Date) {
            self.restingHR = restingHR; self.systolic = systolic
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

    /// Personalised estimate of current BP from resting HR, or nil if there is
    /// not yet enough calibration data. When a feature has no personal
    /// correlation the fit degrades gracefully toward the user's own mean.
    public static func estimate(currentRestingHR: Double, calibration: [CalibrationPoint]) -> Estimate? {
        guard calibration.count >= minimumCalibrationPoints else { return nil }
        let hr = calibration.map(\.restingHR)
        let sys = calibration.map(\.systolic)
        let dia = calibration.map(\.diastolic)

        let meanSys = sys.reduce(0, +) / Double(sys.count)
        let meanDia = dia.reduce(0, +) / Double(dia.count)

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

    /// Build calibration points by pairing each systolic reading with the
    /// diastolic reading at the same instant and the nearest resting-HR sample
    /// within `window`.
    public static func buildCalibration(from samples: [HealthMetricSample], window: TimeInterval = 24 * 3600) -> [CalibrationPoint] {
        let systolic = samples.samples(of: .bloodPressureSystolic)
        let diastolic = samples.samples(of: .bloodPressureDiastolic)
        let restingHR = samples.samples(of: .restingHeartRate)
        guard !systolic.isEmpty, !restingHR.isEmpty else { return [] }

        var points: [CalibrationPoint] = []
        for s in systolic {
            guard let d = diastolic.min(by: {
                abs($0.start.timeIntervalSince(s.start)) < abs($1.start.timeIntervalSince(s.start))
            }), abs(d.start.timeIntervalSince(s.start)) <= window else { continue }
            guard let hr = restingHR.min(by: {
                abs($0.start.timeIntervalSince(s.start)) < abs($1.start.timeIntervalSince(s.start))
            }), abs(hr.start.timeIntervalSince(s.start)) <= window else { continue }
            points.append(.init(restingHR: hr.value, systolic: s.value, diastolic: d.value, date: s.start))
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
            let calibration = BloodPressureEstimator.buildCalibration(from: samples)
            if let est = BloodPressureEstimator.estimate(currentRestingHR: restHR, calibration: calibration) {
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
