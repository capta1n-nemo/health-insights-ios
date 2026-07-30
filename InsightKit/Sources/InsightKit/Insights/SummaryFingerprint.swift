import Foundation

/// A digest of everything the Today summary is written from, so an app open that
/// changed nothing doesn't pay for a fresh one.
///
/// Nothing gated the summariser: every appearance of the root view, and all three
/// pull-to-refresh gestures, ran a full on-device model round-trip whether or not
/// a single sample had landed since the last one.
///
/// **It fingerprints the *results*, not the samples.** That is the tightest
/// correct answer, and it is simpler than it looks: the summary is a function of
/// the insight results and of nothing else, so identical results must produce an
/// identical summary. Fingerprinting samples instead would be both looser (a
/// thousand new heart-rate readings that move no score would force a rewrite) and
/// wronger — scores change with no new sample at all, because a 28-day window
/// slides and a fresh reading goes stale simply from time passing.
///
/// The calendar day is folded in for the same reason: the copy says "today", so a
/// summary must not survive midnight even if every number behind it is unchanged.
public struct SummaryFingerprint: Sendable, Equatable, Codable {
    public let digest: String

    public init(digest: String) { self.digest = digest }

    /// The fingerprint of a set of results as of `now`.
    ///
    /// Scores are rounded to whole points before hashing. A dial cannot render
    /// finer than that and the summariser cannot say anything finer, so letting
    /// 72.4001 → 72.4002 invalidate a summary would defeat the gate on nothing but
    /// floating-point noise.
    public static func of(results: [InsightResult], now: Date,
                          calendar: Calendar = .current) -> SummaryFingerprint {
        let day = calendar.startOfDay(for: now).timeIntervalSince1970
        // Sorted by id, so the engine's registration order can be changed without
        // silently invalidating every stored summary.
        let parts = results
            .sorted { $0.id.rawValue < $1.id.rawValue }
            .map { result -> String in
                let score = result.score.map { String(Int($0.rounded())) } ?? "-"
                // The headline and the leading driver are what the summariser
                // actually reads; the rest of the driver list is detail it does
                // not see, and hashing it would invalidate on invisible changes.
                let lead = result.driverLines.first?.text ?? ""
                return "\(result.id.rawValue)|\(score)|\(result.confidence.rawValue)|\(result.headline)|\(lead)"
            }
        return SummaryFingerprint(digest: "\(Int(day))#" + String(parts.joined(separator: "\n").hashValue))
    }
}

/// Whether a manual refresh should actually run.
///
/// Pull-to-refresh had no floor at all, so three gestures in three seconds paid
/// for three full syncs and three model round-trips.
///
/// A suppressed refresh must not look like a broken one — a gesture that appears
/// to do nothing reads as a bug — which is why this reports *why* it declined and
/// the caller shows the time of the last successful refresh rather than failing
/// silently.
public enum RefreshGate {
    /// How close together two manual refreshes may be.
    public static let manualFloor: TimeInterval = 30

    public enum Decision: Sendable, Equatable {
        case run
        /// Too soon after the last one; the caller should reassure rather than sync.
        case tooSoon(secondsRemaining: TimeInterval)
    }

    public static func decide(lastRefreshAt: Date?, now: Date,
                              floor: TimeInterval = manualFloor) -> Decision {
        guard let lastRefreshAt else { return .run }
        let elapsed = now.timeIntervalSince(lastRefreshAt)
        // A clock that has gone backwards (timezone change, NTP correction) must
        // not lock refreshing out until it catches up.
        guard elapsed >= 0 else { return .run }
        return elapsed >= floor ? .run : .tooSoon(secondsRemaining: floor - elapsed)
    }
}
