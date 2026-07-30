import Foundation

/// "Improve Your Health" — the one greenfield item on the feedback list.
///
/// The hard part is not generating suggestions, it is refusing to generate the
/// wrong ones. This app is not a medical device and does not give medical
/// advice, so a suggestion here is only ever one of three factual things:
///
/// 1. **Something the user's own data already shows.** `VO2Trajectory` set the
///    precedent — "in weeks where your active energy was above X, your cardio
///    fitness averaged Y against Z in your lighter weeks. That's your own
///    history, not a rule." This generalises that, and it is the strongest kind
///    because the evidence is the person in front of you.
/// 2. **A fact the app is missing.** "Log a cuff reading and Blood Pressure
///    starts scoring" is a statement about the software, not about the body.
/// 3. **A signal sitting away from its own baseline**, named without being
///    explained. Saying resting heart rate has been running high is reporting;
///    saying why, or what to do about it, would not be.
///
/// General population evidence — "adults should get 150 minutes of exercise a
/// week" — is deliberately absent. It is true, it is not about this person, and
/// the moment the app starts dispensing it the framing stops being descriptive.
public struct Suggestion: Sendable, Equatable, Identifiable {

    /// What the suggestion rests on. Also the primary sort key: an observation
    /// about this person outranks a gap in the app's inputs, which outranks a
    /// signal merely being off.
    public enum Basis: String, Sendable, Comparable {
        /// Drawn from a contrast in the user's own history.
        case yourOwnData
        /// A missing or stale grounding fact that would make an insight work.
        case unlockAnInsight
        /// A measured signal away from its own baseline.
        case signalOffBaseline

        private var rank: Int {
            switch self {
            case .yourOwnData: return 0
            case .unlockAnInsight: return 1
            case .signalOffBaseline: return 2
            }
        }
        public static func < (a: Basis, b: Basis) -> Bool { a.rank < b.rank }
    }

    public let id: String
    /// The short line. Never an instruction — a description of what was found.
    public let title: String
    /// The evidence, in the user's own numbers wherever there are any.
    public let detail: String
    public let basis: Basis
    /// Which card this came from, so the row can navigate there.
    public let insight: InsightID?
    public let metric: MetricType?
    /// 0–1, the sort key *within* a basis. How strongly the evidence supports it
    /// — not how important the app thinks it is.
    public let strength: Double

    public init(id: String, title: String, detail: String, basis: Basis,
                insight: InsightID? = nil, metric: MetricType? = nil,
                strength: Double) {
        self.id = id
        self.title = title
        self.detail = detail
        self.basis = basis
        self.insight = insight
        self.metric = metric
        self.strength = strength
    }
}

public enum SuggestionEngine {

    /// How many to show. Past a handful this stops being a list of findings and
    /// starts being a to-do list, which is a different and less honest thing.
    public static let defaultLimit = 5

    /// Everything worth surfacing, strongest evidence first.
    public static func suggestions(results: [InsightResult],
                                   samples: [HealthMetricSample],
                                   profile: UserHealthProfile,
                                   now: Date = Date(),
                                   calendar: Calendar = .current,
                                   limit: Int = defaultLimit) -> [Suggestion] {
        var out: [Suggestion] = []
        out += personalLevers(samples: samples, profile: profile, now: now, calendar: calendar)
        out += unlocks(results: results)
        out += departures(samples: samples, now: now, calendar: calendar)

        return out
            .sorted { a, b in
                a.basis == b.basis ? a.strength > b.strength : a.basis < b.basis
            }
            .prefix(limit)
            .map { $0 }
    }

    // MARK: - 1. The user's own history

    /// The busier-versus-lighter-weeks contrast `VO2Trajectory` already computes.
    ///
    /// Re-derived here rather than plumbed through `InsightResult`, because the
    /// contrast is a structured finding and `drivers` are strings — parsing a
    /// sentence back into numbers would be the wrong direction of travel.
    static func personalLevers(samples: [HealthMetricSample], profile: UserHealthProfile,
                               now: Date, calendar: Calendar) -> [Suggestion] {
        guard let age = profile.age(asOf: now), let sex = profile.sex,
              let trajectory = VO2Trajectory.evaluate(samples: samples, age: age, sex: sex,
                                                      now: now, calendar: calendar),
              let volume = trajectory.volume, volume.difference > 0 else { return [] }

        // The size of the contrast, against a full point of VO₂max as the scale
        // at which a difference is worth mentioning at all.
        let strength = Swift.min(1, volume.difference / 2)
        return [Suggestion(
            id: "volume-\(volume.metric.rawValue)",
            title: "Your busier weeks track higher cardio fitness",
            detail: String(format: "In weeks where your %@ was above %.0f %@, your cardio fitness averaged %.1f — against %.1f in your lighter weeks, across %d weeks of your own history. An association in your data, not a rule.",
                           volume.metric.inSentence, volume.medianWeekly,
                           volume.metric.unit, volume.vo2WhenBusier,
                           volume.vo2WhenLighter, volume.weeksCompared),
            basis: .yourOwnData,
            insight: .cardioTrajectory,
            metric: volume.metric,
            strength: strength)]
    }

    // MARK: - 2. Facts the app is missing

    /// A grounding gap is a statement about the software, which is why it can be
    /// phrased as something to do without becoming advice.
    ///
    /// Ranked by how many cards the fact unblocks, so one blood-pressure reading
    /// — which feeds Blood Pressure, Heart Age and Cardiovascular Risk — leads
    /// over an ethnicity field that refines one.
    static func unlocks(results: [InsightResult]) -> [Suggestion] {
        var blockedBy: [GroundingKind: (mandatory: Bool, insights: [InsightID])] = [:]
        for result in results {
            for requirement in result.unmetRequirements {
                var entry = blockedBy[requirement.kind] ?? (false, [])
                entry.mandatory = entry.mandatory || requirement.isMandatory
                entry.insights.append(result.id)
                blockedBy[requirement.kind] = entry
            }
        }
        // Which cards have no number at all — the ones a missing fact is actually
        // costing something.
        let unscored = Set(results.filter { $0.score == nil }.map(\.id))

        return blockedBy.map { kind, entry in
            let blocked = entry.insights
            let names = blocked.count == 1
                ? "one insight" : "\(blocked.count) insights"
            let costsAScore = blocked.contains { unscored.contains($0) }
            // Mandatory-and-blocking a scoreless card is the strongest case;
            // an optional refinement is the weakest.
            let strength = (entry.mandatory ? 0.6 : 0.2)
                + (costsAScore ? 0.3 : 0)
                + Swift.min(0.1, Double(blocked.count) * 0.03)
            return Suggestion(
                id: "grounding-\(kind.rawValue)",
                title: "Add your \(kind.displayName.lowercased())",
                detail: costsAScore
                    ? "\(names.capitalizedFirst) can't produce a score without it."
                    : "\(names.capitalizedFirst) would get more accurate with it.",
                basis: .unlockAnInsight,
                insight: blocked.first,
                metric: nil,
                strength: Swift.min(1, strength))
        }
    }

    // MARK: - 3. Signals away from their own baseline

    /// Named, not explained. This reports that a signal has moved; it does not
    /// say why, and it does not say what to do — both of which would be claims
    /// this app has no standing to make.
    static func departures(samples: [HealthMetricSample], now: Date,
                           calendar: Calendar) -> [Suggestion] {
        let scan = VitalSignsCheck.evaluate(samples: samples, now: now, calendar: calendar)
        return scan.unusual.compactMap { reading in
            guard let z = reading.zScore, abs(z) >= VitalSignsCheck.unusualZ else { return nil }
            let direction = z > 0 ? "above" : "below"
            return Suggestion(
                id: "departure-\(reading.metric.rawValue)",
                title: "\(reading.metric.displayName) is \(direction) your usual range",
                detail: String(format: "%@ against a baseline of %@, measured %@. Worth keeping an eye on — this is your own pattern, not a diagnosis.",
                               MetricValueFormatter.detailedString(reading.value, reading.metric),
                               reading.baseline.map {
                                   MetricValueFormatter.detailedString($0, reading.metric)
                               } ?? "your recent average",
                               reading.sourceName),
                basis: .signalOffBaseline,
                insight: .vitalSigns,
                metric: reading.metric,
                // Two SDs is the floor for appearing here at all; four is as
                // strong as this evidence gets.
                strength: Swift.min(1, abs(z) / 4))
        }
    }
}
