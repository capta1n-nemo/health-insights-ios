import Foundation

/// **The night's breathing, trended against your own nights and never scored.**
///
/// Backlog B18-1 and S9 are one section, not two: the reader asked for a
/// dedicated sleep-apnoea *indicator* that **contains** "Breathing during
/// sleep", and S9's finding is what that section is allowed to say.
///
/// ## The refusal, in full, because it is the feature
///
/// Oura's breathing-disturbance index is a proprietary composite of overnight
/// blood-oxygen dips and the movement that goes with interrupted breaths. It is
/// **not** an apnoea–hypopnoea index. The clinical thresholds that exist — AHI
/// 5, 15 and 30 events per hour — grade a polysomnogram's event count, a
/// different quantity measured a different way, and no published work maps a
/// ring's index onto them. `MetricType.breathingDisturbanceIndex.referenceRange`
/// is therefore nil, and this type produces **no score, no band and no verdict**.
///
/// What it produces instead is the two honest statements available: where last
/// night sat among the reader's own nights, and whether the series is drifting
/// by more than it scatters. Both are claims about this person's history and
/// neither is a claim about their airway.
///
/// ⚠️ **Nothing added here may screen for apnoea.** A section that trends an
/// index is useful; a section that says "your index is high, you may have sleep
/// apnoea" is a diagnosis delivered by a ring, and the only correct answer to
/// the question it raises is a sleep study. `whatWouldAnswerIt` is that sentence
/// and it is not optional decoration.
public struct BreathingDisturbanceTrend: Sendable, Equatable {

    /// The fewest nights that can carry a placement or a line. Fourteen — a
    /// fortnight, the same floor the screen-time contrast uses, and for the same
    /// reason: below it "your own nights" is a handful of nights.
    public static let minimumNights = 14

    /// One night's index, keyed to the wake day the sample carries.
    public struct Night: Sendable, Equatable, Identifiable {
        public let night: Date
        public let value: Double
        public var id: Date { night }

        public init(night: Date, value: Double) {
            self.night = night
            self.value = value
        }
    }

    /// Oldest first.
    public let nights: [Night]
    /// The fitted line, `nil` below the floor. Read `isMeaningful` before naming
    /// a direction: a slope inside the night-to-night scatter is not a drift.
    public let trend: ScoreTrend?
    /// Where the most recent night sits among the rest, **0–1** — `Baseline`'s
    /// own scale, not a percentage, so a caller multiplying by 100 is doing it
    /// once and visibly rather than being handed a number whose scale it has to
    /// guess.
    public let latestPercentile: Double?
    public let coverage: CoverageGate?

    public init(nights: [Night], trend: ScoreTrend?,
                latestPercentile: Double?, coverage: CoverageGate?) {
        self.nights = nights
        self.trend = trend
        self.latestPercentile = latestPercentile
        self.coverage = coverage
    }

    public var latest: Night? { nights.last }
    public var median: Double? { Baseline.median(nights.map(\.value)) }
    public var span: ClosedRange<Date>? {
        guard let first = nights.first?.night, let last = nights.last?.night,
              first <= last else { return nil }
        return first...last
    }

    // MARK: - Building

    public static func build(samples: [HealthMetricSample],
                             calendar: Calendar = .current) -> BreathingDisturbanceTrend {
        // One value per night, latest wins — the same de-duplication the nightly
        // sleep figures use, and the reason a re-synced night cannot appear
        // twice in the fit.
        var byNight: [Date: Double] = [:]
        for sample in samples.samples(of: .breathingDisturbanceIndex) {
            byNight[calendar.startOfDay(for: sample.start)] = sample.value
        }
        let nights = byNight.keys.sorted().map { Night(night: $0, value: byNight[$0] ?? 0) }

        let coverage = CoverageGate.ifShort(
            need: minimumNights, have: nights.count,
            unit: "night with a breathing-disturbance reading",
            unlocks: "this can place a night among your own rather than just listing them")

        guard coverage == nil, let first = nights.first?.night,
              let latest = nights.last?.value else {
            return BreathingDisturbanceTrend(nights: nights, trend: nil,
                                             latestPercentile: nil, coverage: coverage)
        }
        let x = nights.map { $0.night.timeIntervalSince(first) / 86_400 }
        let fit = Baseline.linearRegression(x: x, y: nights.map(\.value))
        return BreathingDisturbanceTrend(
            nights: nights,
            trend: fit.map {
                ScoreTrend(slopePerWeek: $0.slope * 7, residualSD: $0.residualSD,
                           start: first, intercept: $0.intercept,
                           slopePerDay: $0.slope, sampleCount: nights.count)
            },
            latestPercentile: Baseline.percentile(latest, history: nights.map(\.value)),
            coverage: coverage)
    }

    // MARK: - What it is allowed to say

    /// Whether the series is going anywhere, in one sentence that names the
    /// scatter as well as the slope.
    ///
    /// `nil` where there is no line to describe, so the caller shows the
    /// coverage sentence instead of a hedge.
    public var driftSentence: String? {
        guard let trend, let median else { return nil }
        guard trend.isMeaningful else {
            return String(format: "Steady over these %d nights — around %.1f on a "
                          + "typical one, with no drift up or down that stands out "
                          + "from how much the nights differ anyway.",
                          nights.count, median)
        }
        let direction = trend.slopePerWeek > 0 ? "up" : "down"
        return String(format: "Drifting %@ by about %.2f a week over these %d nights, "
                      + "against a night-to-night scatter of %.2f. A direction, not a "
                      + "verdict — nothing here says what a level means.",
                      direction, abs(trend.slopePerWeek), nights.count, trend.residualSD)
    }

    /// The refusal, written once so every surface says the same thing.
    public static let notAnApnoeaTest =
        "This is not an apnoea test and this app does not screen for apnoea. The "
        + "index is your ring's own composite of overnight blood-oxygen dips and "
        + "the movement that goes with interrupted breathing, on its own scale. No "
        + "published work maps it onto the event counts a sleep study grades, so "
        + "nothing here scores it, bands it or tells you what a level means."

    /// What actually answers the question this section raises.
    public static let whatWouldAnswerIt =
        "If your nights here concern you, or you snore, wake unrefreshed or have "
        + "been told you stop breathing, the thing that answers it is a sleep study "
        + "arranged through a doctor — not a ring, and not this app."
}
