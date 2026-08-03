import Foundation

/// Where one body measurement came from, and how much to believe it.
///
/// The reader's rule: *"a body scan you do through our app will override
/// because it's based on actuals, **unless we see an issue with the
/// measurements in Apple Health being more accurate than ours**."*
///
/// Both halves matter, and the second is the harder one. A blanket "our scan
/// always wins" would quietly discard a tape measurement — the most accurate
/// circumference anybody here will ever have — because it arrived through
/// Health rather than through the scanner. So authority is ranked by **method**,
/// not by whose app it came from, and where two sources genuinely disagree the
/// answer is to say so rather than to pick a winner silently.
public enum BodyMeasurementProvenance: String, Sendable, Codable, CaseIterable {
    /// This app's LiDAR scan. True metric depth.
    case lidarScan
    /// A tape measure, entered here.
    case tape
    /// Apple Health or a connected provider. **Method unknown** — it may be a
    /// tape somebody typed in, a smart scale, or another scanning app, and
    /// HealthKit does not say which.
    case externalHealthApp
    /// This app's camera scan, with no depth sensor.
    case cameraScan

    /// Higher wins.
    ///
    /// The ordering, and why it is not simply "ours first":
    ///
    /// - **A tape beats everything.** It is a direct measurement of the quantity
    ///   itself rather than an inference from pixels, and no optical method
    ///   matches it.
    /// - **LiDAR beats an unknown external source.** This is the reader's rule:
    ///   a depth-sensed circumference is an actual, and a Health entry of
    ///   unknown provenance is not known to be better.
    /// - **An unknown external source beats our camera scan.** This is the
    ///   escape hatch they asked for. A camera silhouette is the weakest method
    ///   here (±20 mm), so deferring to it over *anything* would be the app
    ///   preferring its own guess to somebody else's measurement.
    public var authority: Int {
        switch self {
        case .tape: return 3
        case .lidarScan: return 2
        case .externalHealthApp: return 1
        case .cameraScan: return 0
        }
    }

    /// Typical repeatability of the method, in centimetres — the band inside
    /// which a difference is not a difference.
    public var repeatabilityCentimetres: Double {
        switch self {
        case .tape: return 1.0
        case .lidarScan: return 1.0
        case .externalHealthApp: return 1.5   // unknown method, assume mid
        case .cameraScan: return 2.0
        }
    }

    public var displayName: String {
        switch self {
        case .lidarScan: return "Scan (LiDAR)"
        case .cameraScan: return "Scan (camera)"
        case .tape: return "Tape measure"
        case .externalHealthApp: return "Apple Health"
        }
    }
}

/// One site's value from one source.
public struct SourcedMeasurement: Sendable, Equatable {
    public let site: BodySite
    public let centimetres: Double
    public let provenance: BodyMeasurementProvenance
    public let measuredAt: Date

    public init(site: BodySite, centimetres: Double,
                provenance: BodyMeasurementProvenance, measuredAt: Date) {
        self.site = site
        self.centimetres = centimetres
        self.provenance = provenance
        self.measuredAt = measuredAt
    }
}

/// Choosing between sources that measured the same thing.
public enum BodyMeasurementReconciliation {

    /// What the app should show for one site.
    public struct Outcome: Sendable, Equatable {
        public let chosen: SourcedMeasurement
        /// Sources that measured the same site and were not chosen.
        public let alternatives: [SourcedMeasurement]
        /// True where a source disagrees with the chosen one by more than the
        /// two methods' combined repeatability.
        ///
        /// **The reader's "unless we see an issue", made concrete.** A
        /// disagreement inside the noise is two methods agreeing; a
        /// disagreement outside it means one of them is wrong and the app
        /// cannot tell which, so it says so rather than hiding the loser.
        public let isDisputed: Bool

        /// One line for the card, or nil when there is nothing to flag.
        public var note: String? {
            guard isDisputed, let other = alternatives.first else { return nil }
            let gap = abs(chosen.centimetres - other.centimetres)
            return String(
                format: "%@ says %.1f cm and %@ says %.1f cm — %.1f cm apart, which is "
                    + "more than either method's usual variation. The more precise "
                    + "method is being used; re-measure if that looks wrong.",
                chosen.provenance.displayName, chosen.centimetres,
                other.provenance.displayName, other.centimetres, gap)
        }
    }

    /// How stale a measurement may be before a fresher one of *lower* authority
    /// takes over.
    ///
    /// Without this, one tape measurement would outrank every scan forever, and
    /// a body that has changed since would keep being described by the old
    /// number. Ninety days is three of the reader's own thirty-day scan cycles —
    /// long enough that a better method still wins in the normal case, short
    /// enough that it cannot go stale unnoticed.
    public static let authorityHoldsForDays = 90

    /// Pick the value for one site.
    ///
    /// Ranked by method, then by recency — except that an authoritative reading
    /// older than `authorityHoldsForDays` stops outranking a fresher one.
    public static func resolve(_ candidates: [SourcedMeasurement],
                               now: Date,
                               calendar: Calendar = .current) -> Outcome? {
        guard !candidates.isEmpty else { return nil }

        func isStale(_ measurement: SourcedMeasurement) -> Bool {
            let days = calendar.dateComponents([.day], from: measurement.measuredAt,
                                               to: now).day ?? 0
            return days > authorityHoldsForDays
        }

        let ranked = candidates.sorted { left, right in
            // A stale reading loses its seniority, whatever method produced it.
            let leftStale = isStale(left), rightStale = isStale(right)
            if leftStale != rightStale { return !leftStale }
            if left.provenance.authority != right.provenance.authority {
                return left.provenance.authority > right.provenance.authority
            }
            return left.measuredAt > right.measuredAt
        }

        let chosen = ranked[0]
        let alternatives = Array(ranked.dropFirst())
        let disputed = alternatives.contains { other in
            let band = chosen.provenance.repeatabilityCentimetres
                + other.provenance.repeatabilityCentimetres
            return abs(chosen.centimetres - other.centimetres) > band
        }
        return Outcome(chosen: chosen, alternatives: alternatives, isDisputed: disputed)
    }

    /// Resolve every site at once, into the shape the body model reads.
    public static func merge(_ candidates: [SourcedMeasurement], now: Date,
                             calendar: Calendar = .current) -> BodyMeasurements {
        let bySite = Dictionary(grouping: candidates, by: \.site)
        let values = BodySite.allCases.compactMap { site -> BodyMeasurement? in
            guard let group = bySite[site],
                  let outcome = resolve(group, now: now, calendar: calendar) else { return nil }
            return BodyMeasurement(site: site, centimetres: outcome.chosen.centimetres)
        }
        return BodyMeasurements(values)
    }

    /// Every site where two sources disagree beyond the noise — what a card
    /// shows when it wants to say "these two do not agree".
    public static func disputes(_ candidates: [SourcedMeasurement], now: Date,
                                calendar: Calendar = .current) -> [Outcome] {
        Dictionary(grouping: candidates, by: \.site)
            .compactMap { resolve($0.value, now: now, calendar: calendar) }
            .filter(\.isDisputed)
            .sorted { $0.chosen.site.rawValue < $1.chosen.site.rawValue }
    }
}
