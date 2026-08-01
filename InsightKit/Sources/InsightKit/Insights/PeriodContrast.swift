import Foundation

/// One metric's last N days set against the N before them.
///
/// The Today tab's question is "how does today compare with my normal". This is
/// the longer-horizon version: has my normal itself moved? A z-score cannot
/// answer that, because the baseline it measures against drifts along with the
/// change — the same blindness that let a slow HRV collapse go unreported.
public struct PeriodChange: Sendable, Equatable, Identifiable {
    public let metric: MetricType
    public let recentMean: Double
    public let priorMean: Double
    /// In the metric's own units.
    public let delta: Double
    /// Change expressed against the prior period's own spread, so a 2 bpm move
    /// in a steady signal outranks a 2 bpm move in a noisy one.
    public let standardisedDelta: Double
    public let recentCount: Int
    public let priorCount: Int
    /// Whether the direction is the good one, where that is meaningful.
    public let isImprovement: Bool?

    public var id: MetricType { metric }

    public var percentChange: Double? {
        priorMean == 0 ? nil : delta / abs(priorMean) * 100
    }
}

public enum PeriodContrast {

    /// Below this many days on either side there is nothing worth comparing.
    public static let minimumDaysPerPeriod = 7
    /// Changes smaller than this share of the prior spread are noise.
    public static let minimumStandardisedDelta = 0.4
    /// The length of each of the two windows. Named rather than left as a bare
    /// default argument because the card's caveat quotes it, and a caption that
    /// says "28 days" beside a comparison over some other number is the kind of
    /// disagreement nobody notices.
    public static let windowDays = 28

    /// Compare the `days` before `now` with the `days` before that.
    public static func changes(for metrics: [MetricContribution],
                               samples: [HealthMetricSample],
                               days: Int = PeriodContrast.windowDays,
                               now: Date = Date(),
                               calendar: Calendar = .current) -> [PeriodChange] {
        let window = Double(days) * 86_400
        let recentStart = now.addingTimeInterval(-window)
        let priorStart = now.addingTimeInterval(-2 * window)

        return metrics.compactMap { contribution -> PeriodChange? in
            let metric = contribution.metric
            let daily = dailyMeans(metric, samples: samples, calendar: calendar)

            let recent = daily.filter { $0.key >= recentStart && $0.key <= now }.map(\.value)
            let prior = daily.filter { $0.key >= priorStart && $0.key < recentStart }.map(\.value)
            guard recent.count >= minimumDaysPerPeriod,
                  prior.count >= minimumDaysPerPeriod,
                  let recentMean = Baseline.mean(recent),
                  let priorMean = Baseline.mean(prior) else { return nil }

            let delta = recentMean - priorMean
            // Against the prior period's own spread, so "moved" means moved
            // relative to how much this signal normally wanders.
            guard let spread = Baseline.standardDeviation(prior), spread > 0 else { return nil }
            let standardised = delta / spread
            guard abs(standardised) >= minimumStandardisedDelta else { return nil }

            return PeriodChange(
                metric: metric, recentMean: recentMean, priorMean: priorMean,
                delta: delta, standardisedDelta: standardised,
                recentCount: recent.count, priorCount: prior.count,
                isImprovement: contribution.higherIsBetter.map { $0 == (delta > 0) })
        }
        .sorted { abs($0.standardisedDelta) > abs($1.standardisedDelta) }
    }

    /// One value per day, de-duplicated across sources, so a device that samples
    /// more often doesn't weight the mean.
    ///
    /// Extracted so `coverage` counts exactly the days `changes` counts. The
    /// alternative — a second implementation that agrees today — is the shape
    /// `PressureBandTests` exists to catch.
    static func dailyMeans(_ metric: MetricType,
                           samples: [HealthMetricSample],
                           calendar: Calendar) -> [Date: Double] {
        let breakdown = MultiSource.breakdown(metric, from: samples)
        var daily: [Date: Double] = [:]
        for series in breakdown.sources {
            for point in series.bucketed(by: .day, for: metric, calendar: calendar) {
                // One value per day across all sources: mean them, matching how
                // the rest of the app treats disagreeing devices.
                if let existing = daily[point.date] {
                    daily[point.date] = (existing + point.value) / 2
                } else {
                    daily[point.date] = point.value
                }
            }
        }
        return daily
    }

    /// How many of these metrics have enough days in **both** windows to be
    /// compared at all.
    ///
    /// This separates the two reasons the section can come back empty — not
    /// enough history, versus enough history and nothing moved — which is the
    /// difference between "wait" and "you're steady", and the card now has to
    /// say which.
    public static func comparableCount(for metrics: [MetricContribution],
                                       samples: [HealthMetricSample],
                                       days: Int = PeriodContrast.windowDays,
                                       now: Date = Date(),
                                       calendar: Calendar = .current) -> Int {
        let window = Double(days) * 86_400
        let recentStart = now.addingTimeInterval(-window)
        let priorStart = now.addingTimeInterval(-2 * window)
        return metrics.filter { contribution in
            let daily = dailyMeans(contribution.metric, samples: samples, calendar: calendar)
            let recent = daily.keys.filter { $0 >= recentStart && $0 <= now }.count
            let prior = daily.keys.filter { $0 >= priorStart && $0 < recentStart }.count
            return recent >= minimumDaysPerPeriod && prior >= minimumDaysPerPeriod
        }.count
    }
}
