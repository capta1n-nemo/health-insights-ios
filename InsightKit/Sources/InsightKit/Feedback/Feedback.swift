import Foundation

/// A coarse, non-identifying description of the user, used to attribute model
/// error to a *group* rather than a person. Every field is a broad bucket — this
/// is deliberately low-resolution so it can never single someone out.
public struct Cohort: Codable, Sendable, Hashable {
    public let sex: String          // "male" / "female" / "unspecified"
    public let ageBand: String      // "30-39", "40-49", … / "unspecified"
    public let ethnicity: String    // "white_or_other" / "african_american" / "unspecified"
    public let region: String       // SCORE2 region / "unspecified"

    public init(sex: String, ageBand: String, ethnicity: String, region: String) {
        self.sex = sex; self.ageBand = ageBand; self.ethnicity = ethnicity; self.region = region
    }

    public static func from(profile: UserHealthProfile, now: Date = Date()) -> Cohort {
        let sex = profile.sex.map { $0 == .male ? "male" : "female" } ?? "unspecified"
        let ageBand = profile.age(asOf: now).map { Telemetry.ageBand($0) } ?? "unspecified"
        let ethnicity: String = profile.value(.ascvdRaceGroup) == nil
            ? "unspecified" : profile.raceGroup.rawValue
        let region = profile.value(.score2Region) == nil ? "unspecified" : profile.score2Region.rawValue
        return Cohort(sex: sex, ageBand: ageBand, ethnicity: ethnicity, region: region)
    }
}

/// A recorded "the model predicted X, the truth turned out to be Y" pair. Held
/// **on device**; it keeps the raw numbers locally so the app can show you your
/// own history, but only the coarsened error ever becomes a `TelemetryEvent`.
public struct PredictionOutcome: Codable, Sendable, Identifiable {
    public let id: UUID
    public let insightID: InsightID
    public let metric: MetricType
    public let predicted: Double
    public let actual: Double
    public let modelVersion: String
    public let cohort: Cohort
    public let recordedAt: Date

    public init(id: UUID = UUID(), insightID: InsightID, metric: MetricType,
                predicted: Double, actual: Double, modelVersion: String,
                cohort: Cohort, recordedAt: Date = Date()) {
        self.id = id; self.insightID = insightID; self.metric = metric
        self.predicted = predicted; self.actual = actual; self.modelVersion = modelVersion
        self.cohort = cohort; self.recordedAt = recordedAt
    }

    /// Signed error as a percentage of the true value: positive = over-predicted.
    public var signedPercentError: Double {
        actual == 0 ? 0 : (predicted - actual) / actual * 100
    }
    public var absoluteError: Double { predicted - actual }
}

/// A qualitative "was this right?" tap.
public enum FeedbackRating: String, Codable, Sendable { case accurate, inaccurate }

/// **Exactly** what would be transmitted if the user opted in — and nothing
/// more. There are no raw measurements and no identifiers here by construction:
/// only a coarse cohort, the model version, a differentially-private rounded
/// error (or a rating), and a coarse week bucket.
public struct TelemetryEvent: Codable, Sendable, Equatable {
    public let kind: String            // "prediction_error" | "feedback"
    public let insightID: String
    public let metric: String?
    public let sex: String
    public let ageBand: String
    public let ethnicity: String
    public let region: String
    public let modelVersion: String
    public let signedErrorPercent: Double?   // coarsened + DP noise
    public let rating: String?
    public let weekBucket: Int               // whole weeks since 1970 (coarse time)
}

public enum Telemetry {

    /// 10-year age bands.
    public static func ageBand(_ age: Double) -> String {
        let lo = max(0, Int(age / 10) * 10)
        return "\(lo)-\(lo + 9)"
    }

    /// Inverse-CDF Laplace sample from a uniform `u` in (0,1). Deterministic, so
    /// tests are exact and the outbox preview is stable per record.
    public static func laplace(scale: Double, u: Double) -> Double {
        let x = min(max(u, 1e-9), 1 - 1e-9) - 0.5
        return -scale * (x < 0 ? -1.0 : 1.0) * log(1 - 2 * abs(x))
    }

    /// Whole weeks since 1970 — the app's one coarse-time convention.
    ///
    /// Public because `NormContribution` buckets by exactly this and a second
    /// definition of "which week" is how two payloads about the same seven days
    /// end up unpoolable. It is the *only* thing norm telemetry inherits from
    /// accuracy telemetry; the shapes are otherwise deliberately different, and
    /// `docs/norms-and-telemetry.md` says why.
    public static func weekBucket(_ date: Date) -> Int {
        Int(date.timeIntervalSince1970 / (7 * 24 * 3600))
    }

    /// Build the anonymised event for a prediction error: round the percent error
    /// to whole percent and add differential-privacy noise. Raw values never enter.
    public static func event(from outcome: PredictionOutcome,
                             noiseScale: Double = 1.5, u: Double = 0.5) -> TelemetryEvent {
        let rounded = (outcome.signedPercentError).rounded()
        let noisy = (rounded + laplace(scale: noiseScale, u: u)).rounded()
        return TelemetryEvent(
            kind: "prediction_error",
            insightID: outcome.insightID.rawValue,
            metric: outcome.metric.rawValue,
            sex: outcome.cohort.sex, ageBand: outcome.cohort.ageBand,
            ethnicity: outcome.cohort.ethnicity, region: outcome.cohort.region,
            modelVersion: outcome.modelVersion,
            signedErrorPercent: noisy, rating: nil,
            weekBucket: weekBucket(outcome.recordedAt))
    }

    /// Build the anonymised event for a thumbs up/down.
    public static func event(insightID: InsightID, cohort: Cohort, modelVersion: String,
                             rating: FeedbackRating, at date: Date) -> TelemetryEvent {
        TelemetryEvent(
            kind: "feedback", insightID: insightID.rawValue, metric: nil,
            sex: cohort.sex, ageBand: cohort.ageBand, ethnicity: cohort.ethnicity,
            region: cohort.region, modelVersion: modelVersion,
            signedErrorPercent: nil, rating: rating.rawValue, weekBucket: weekBucket(date))
    }

    /// A stable pseudo-random uniform in (0,1) derived from an id, so the outbox
    /// preview doesn't re-randomise the DP noise on every view.
    public static func stableUniform(_ id: UUID) -> Double {
        let h = UInt64(bitPattern: Int64(id.uuidString.hashValue))
        return Double(h % 1_000_000) / 1_000_000.0
    }
}

public extension InsightID {
    /// Version string for the model behind each insight, so the backend can
    /// attribute error to a specific model revision.
    var modelVersion: String {
        switch self {
        // v2 of the risk card: it now also reports heart age, inverting the same
        // equations it already ran.
        case .cardiovascularRisk: return "cvrisk-score2-2021_ascvd-2013-v2"
        // v2: percentile standing against published norms joined the card.
        case .heartHealth: return "hearthealth-v2"
        case .bloodPressure: return "bp-estimator-v2"
        // The three merged cards start at v1 under their own names. A recorded
        // score is only comparable with another from the same model, and these
        // blend components that were previously scored separately — so carrying
        // a predecessor's version string across would be a lie about
        // comparability, which is exactly what this field exists to prevent.
        // **v2, 2026-08-06.** The dose term can now be computed from physical
        // effort instead of Apple's exercise minute, which applies WHO's
        // vigorous-for-moderate substitution and therefore returns a different
        // number for the same week. The weights did not move; the input did.
        // Carrying v1 forward would have made every score recorded before today
        // silently non-comparable with every score after it, which is the one
        // failure this field exists to prevent.
        case .fitness: return "fitness-v2"
        case .sleep: return "sleep-v1"
        // v2: absorbed the vitals scan and the multi-signal early warning that
        // used to be two separate cards, which changes what the score means.
        case .readiness: return "readiness-v2"
        case .bodyComposition: return "bodycomp-v1"
        case .energy: return "energy-v1"
        case .substanceImpact: return "substance-v1"
        case .nutrition: return "nutrition-v1"
        case .metabolism: return "metabolism-v1"
        case .symptomRadar: return "symptom-radar-v1"
        case .sustainedLoad: return "sustained-load-v1"
        case .gait: return "gait-v1"
        case .biologicalAge: return "biological-age-v1"
        case .mentalHealth: return "mental-health-v1"
        // **v2, 2026-08-06 — backlog D41.** The number was a curve over how much
        // the body differed between busy and quiet working days, and the
        // calendar load that decides which day lands in which half was nowhere
        // in it. It now blends **exposure** (how heavy the reader's work
        // actually was, against their own range) with **response** (the same
        // body comparison as before), and the response's share moves with the
        // contrast. Every score recorded under v1 measures a different quantity
        // and is not comparable with one recorded after — which is the one
        // failure this field exists to prevent. The `fitness-v2` precedent.
        case .workImpact: return "work-impact-v2"
        // ⚠️ **Deliberately still v1.** D41 rewrote work impact and stopped
        // there: travel drain's equivalent figure is a count of two-to-four
        // time-zone changes, which is not a distribution to score against and
        // not established as travel at all. Its arithmetic is untouched, so its
        // stored scores stay comparable. Reasoned out at
        // `TravelDrainModel`'s "What the calendar contributes here".
        case .travelDrain: return "travel-drain-v1"
        }
    }
}
