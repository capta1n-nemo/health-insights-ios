import Foundation

/// Every age the app can put on a day, beside the real one.
///
/// ⚠️ **It held exactly two until 2026-08-07, and the app had four.** The
/// comparison section — the one whose entire subject is that different
/// instruments and products answer "how old is this body" differently — listed
/// heart age, fitness age, the app's own biological age and every vendor's
/// vascular age. The chart on the same screen could draw only the first two,
/// because this struct had nowhere to put the other two. **So the two halves of
/// one card disagreed about how many ages exist**, and the two that could not be
/// drawn were the two a reader is most likely to ask "is this getting better?"
/// about: the app's own composite, and the number their ring prints on its
/// front page.
public struct AgePoint: Sendable, Equatable, Identifiable {
    public let date: Date
    /// Your actual age that day. Carried per point rather than assumed constant
    /// because over a long window it isn't.
    public let chronological: Double
    public let heart: Double?
    public let fitness: Double?
    /// A provider's own vascular/cardiovascular age — Oura's, Withings'.
    /// Relayed, never recomputed, exactly as the comparison section relays it.
    public let vascular: Double?
    /// This app's own composite, from `BiologicalAgeModel`.
    public let biological: Double?

    public var id: Date { date }

    public init(date: Date, chronological: Double, heart: Double?, fitness: Double?,
                vascular: Double? = nil, biological: Double? = nil) {
        self.date = date
        self.chronological = chronological
        self.heart = heart
        self.fitness = fitness
        self.vascular = vascular
        self.biological = biological
    }

    /// The age this point is *about*.
    ///
    /// Ordered rather than merged, and the order is the app's own confidence in
    /// what the number rests on: the heart age inverts two published, validated
    /// risk equations; the fitness age inverts one published norm table; the
    /// biological age combines several such tables and says out loud that it is
    /// worth about ±10 years; the vendor's number publishes no error at all.
    ///
    /// **Never an average of the ones present.** Every caller draws one card's
    /// own age and blanks the rest, so in practice exactly one of these is
    /// non-nil — and averaging them would be the merge this whole family of
    /// screens exists to refuse.
    public var leadingAge: Double? { heart ?? fitness ?? biological ?? vascular }

    /// Years the leading age runs ahead of your real one. Positive is bad news.
    public var excessYears: Double? {
        leadingAge.map { $0 - chronological }
    }
}

/// Every age the app can compute, over time.
///
/// Four series since 2026-08-07, not two — see `AgePoint` for why the chart
/// holding two while the comparison section listed four was a defect and not a
/// missing feature.
///
/// The Heart & Fitness Age card had two numbers and a dial, which answers "where
/// am I" and nothing about "which way is this going" — and the direction is the
/// part you can act on. A heart age of 46 means one thing after a year at 50 and
/// something else entirely after a year at 42.
///
/// Rebuilt the same way `ScoreHistory` rebuilds a score: by **truncation**, not
/// by passing a past `now`. `HeartAgeAnalyser.analyse` reads the latest value of
/// each series, so replaying a past day means handing it only the samples that
/// existed by then. Grounding facts (cholesterol, smoking, a cuff reading) are
/// taken as they stand today — the profile has no history to replay, and saying
/// so here is better than pretending the reconstruction is exact.
public enum HeartAgeHistory {

    /// Both ages move in steps as slow inputs land, so a daily replay would draw
    /// a staircase of duplicates. Weekly is the honest resolution.
    public static let strideDays = 7

    /// **The biological age is replayed monthly, not weekly, and that is a
    /// statement about the model rather than a budget.**
    ///
    /// `BiologicalAgeModel` reads each marker over its own window — 90 days for
    /// HRV and gait, 365 for VO₂max and blood pressure — precisely because a
    /// biological age is not a thing that changes on Tuesday. Two evaluations a
    /// week apart therefore share 51/52nds of their input and differ by noise.
    /// Weekly would draw thirteen real points and thirty-nine restatements of
    /// them.
    ///
    /// It is also the most expensive model in the app and the only one here that
    /// scans high-frequency series (HRV, walking speed), so a weekly replay is
    /// what would turn this background pass into something the reader waits on.
    /// Both facts point the same way, which is the only reason to act on either.
    public static let biologicalStrideDays = 28

    /// Every metric any of the four ages is built from.
    ///
    /// The biological age's markers join the analyser's three because the replay
    /// truncates *this* array — a marker missing from it is a marker the replayed
    /// biological age silently never sees, which would draw a line that is
    /// systematically different from the one the card computes today.
    public static var replayMetrics: Set<MetricType> {
        Set(HeartAgeAnalyser().candidateMetrics).union(BiologicalAgeModel.candidates)
    }

    public static func replay(samples: [HealthMetricSample],
                              profile: UserHealthProfile,
                              days: Int = 365,
                              calendar: Calendar = .current,
                              now: Date = Date()) -> [AgePoint] {
        guard days > 0 else { return [] }
        let insight = HeartAgeAnalyser()
        let relevant = replayMetrics
        let sorted = samples.filter { relevant.contains($0.type) }
            .sorted { $0.start < $1.start }
        guard !sorted.isEmpty else { return [] }

        let today = calendar.startOfDay(for: now)
        var points: [AgePoint] = []
        let offsets = Array(stride(from: days - 1, through: 0, by: -strideDays))
        // Counted **from the end**, so the newest point always carries a
        // biological age: it is the one the reader compares against the number
        // the card itself prints, and a chart whose last point is a month stale
        // would look like the card had moved without it.
        let biologicalEvery = Swift.max(1, biologicalStrideDays / strideDays)
        for (index, offset) in offsets.enumerated() {
            let wantsBiological = (offsets.count - 1 - index) % biologicalEvery == 0
            guard let dayStart = calendar.date(byAdding: .day, value: -offset, to: today),
                  let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else { continue }
            let asOf = Swift.min(dayEnd, now)
            guard asOf > dayStart else { continue }

            let cut = ScoreHistory.firstIndex(in: sorted, atOrAfter: asOf)
            guard cut > 0 else { continue }

            let truncated = Array(sorted[..<cut])
            let analysis = insight.analyse(samples: truncated, profile: profile, now: asOf)
            // ⚠️ `includePace: false` halves this, and it is also the correct
            // answer rather than only the cheap one: `pace` runs a **second**
            // full evaluation 180 days further back, so leaving it on would
            // double the most expensive model in the app for a figure this
            // chart does not draw. The pace the card reports is its own, taken
            // once from today; a replayed one would be a slope through a slope.
            let biological = wantsBiological
                ? BiologicalAgeModel.evaluate(samples: truncated, profile: profile,
                                              now: asOf, calendar: calendar,
                                              includePace: false)
                : nil
            guard let age = analysis.chronologicalAge else { continue }
            let point = AgePoint(date: dayStart,
                                 chronological: age,
                                 heart: analysis.heart?.heartAge,
                                 fitness: analysis.fitness?.fitnessAge,
                                 // Relayed as the provider reported it, the same
                                 // number the comparison section shows.
                                 vascular: analysis.vascularAgeUsed,
                                 biological: biological?.biologicalAge)
            // At least one computed age. This used to read
            // `heart != nil || fitness != nil`, which would drop every day on
            // which only the ring's vascular age or the app's own biological age
            // existed — so the two series added here would have started only on
            // the day the *heart* age did, which is months later for a reader
            // who has never entered a cuff reading.
            guard point.leadingAge != nil else { continue }
            points.append(point)
        }
        return points
    }
}

public extension Array where Element == AgePoint {

    /// Change in the leading age per year, over the points present.
    ///
    /// Reported against the *pace of time itself*: your chronological age climbs
    /// one year per year no matter what, so a heart age climbing at 1.0 is
    /// standing still and one climbing at 2.0 is losing a year every year. A
    /// bare slope would read as good news at 0.9.
    var yearsPerYear: Double? {
        let usable = compactMap { point -> (Double, Double)? in
            point.leadingAge.map { (point.date.timeIntervalSince1970, $0) }
        }
        guard usable.count >= 3 else { return nil }
        let fit = Baseline.linearRegression(x: usable.map { $0.0 }, y: usable.map { $0.1 })
        return fit.map { $0.slope * 365.25 * 86_400 }
    }
}
