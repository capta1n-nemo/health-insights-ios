import Foundation

/// Which group a raw, unmodelled field belongs in.
///
/// The reader's Data tab holds **158 distinct raw identifiers across 320,913
/// rows**, in one flat alphabetical list at the very bottom of the page. The
/// category was never missing — it is sitting in the identifier, being thrown
/// away. `HKQuantityTypeIdentifierDietaryCalcium` says nutrition;
/// `oura.daily_activity.contributors.stay_active` says which score it is part
/// of and that it is a component rather than a reading.
///
/// Four rules in order, and the fourth is a measurement of the other three:
/// **if "Not yet sorted" is long, rule 1 is missing a prefix.** That is the
/// point of naming it rather than calling it "Other" — a bucket named for its
/// own failure gets fixed.
public enum RawFieldGrouping {

    public enum Group: String, Sendable, CaseIterable, Comparable {
        case nutrition, hearing, daylight, respiratory, mobility, mind
        case movement, heartEvents, bodyMeasurements, environment
        case activityScore, sleepDetail, stressResilience, unsorted

        public var title: String {
            switch self {
            case .nutrition: return "Nutrition"
            case .hearing: return "Hearing"
            case .daylight: return "Daylight & UV"
            case .respiratory: return "Breathing"
            case .mobility: return "Walking & balance"
            case .mind: return "Mind"
            case .movement: return "Movement & effort"
            case .heartEvents: return "Heart events"
            case .bodyMeasurements: return "Body measurements"
            case .environment: return "Environment"
            case .activityScore: return "Activity score components"
            case .sleepDetail: return "Sleep detail"
            // "(Oura)" in the heading because these are a vendor's own composite
            // numbers relayed, not this app's — the same honesty rule that dashes
            // an inferred line on a chart.
            case .stressResilience: return "Stress & resilience (Oura)"
            case .unsorted: return "Not yet sorted"
            }
        }

        /// Ordering for the tab. `unsorted` is deliberately last **and
        /// deliberately visible** — a bucket hidden is a bucket never emptied.
        var rank: Int { Group.allCases.firstIndex(of: self) ?? 0 }
        public static func < (a: Group, b: Group) -> Bool { a.rank < b.rank }

        /// The Data-tab section this group belongs **inside**, when the app
        /// already has one for the same subject.
        ///
        /// ⚠️ **Two taxonomies produced two "Nutrition" headings**, one from
        /// `MetricDataCategory` (the canonical metrics) and one from here (the
        /// raw fields) — reported by the reader within an hour of the grouped
        /// catalogue shipping, along with its twin: *"at the very bottom of the
        /// page I see a VO₂ Max data point from Oura… why isn't that with the
        /// other VO₂ max?"*
        ///
        /// Both are the same mistake. A reader looking for their VO₂max does not
        /// care which internal pile the app keeps a field in — **the section
        /// heading is a statement about the subject, and two headings with one
        /// name are a bug whatever is under them.** So a raw group that has a
        /// canonical equivalent names it here and its fields are listed in that
        /// section; only the groups with no canonical home keep one of their own.
        public var canonicalCategory: MetricDataCategory? {
            switch self {
            case .nutrition: return .nutrition
            // Respiratory rate and oxygen saturation are already filed under
            // Heart & circulation as canonical metrics, so their raw siblings
            // belong beside them rather than under a heading of their own.
            case .respiratory, .heartEvents: return .heart
            case .mobility, .movement: return .activity
            case .bodyMeasurements: return .body
            case .sleepDetail: return .sleepRecovery
            // No canonical equivalent: the app models none of these yet, so a
            // section of their own is the honest answer rather than filing them
            // under something they are not.
            case .hearing, .daylight, .mind, .environment: return nil
            // Deliberately its own section even though it *could* fold into
            // Activity: eleven fields that are one score's workings are a
            // different kind of thing from a reading, and burying them among
            // real measurements is what made the flat list unreadable.
            case .activityScore: return nil
            // The stress research's raw material (backlog N1), kept together
            // and labelled: the app models no stress metric yet, so a section
            // of its own is the honest answer until one exists.
            case .stressResilience: return nil
            // Named for its own failure, so a long one gets fixed rather than
            // tolerated. Never folded into a real section — that would hide it.
            case .unsorted: return nil
            }
        }
    }

    /// Rule 1 — HealthKit's own naming, which is already a taxonomy.
    private static let healthKitPrefixes: [(String, Group)] = [
        ("HKQuantityTypeIdentifierDietary", .nutrition),
        ("HKQuantityTypeIdentifierEnvironmentalAudio", .hearing),
        ("HKQuantityTypeIdentifierHeadphoneAudio", .hearing),
        ("HKQuantityTypeIdentifierEnvironmentalSound", .hearing),
        ("HKQuantityTypeIdentifierTimeInDaylight", .daylight),
        ("HKQuantityTypeIdentifierUVExposure", .daylight),
        ("HKQuantityTypeIdentifierForcedVital", .respiratory),
        ("HKQuantityTypeIdentifierForcedExpiratory", .respiratory),
        ("HKQuantityTypeIdentifierPeakExpiratory", .respiratory),
        ("HKQuantityTypeIdentifierInhaler", .respiratory),
        ("HKQuantityTypeIdentifierWalking", .mobility),
        ("HKQuantityTypeIdentifierStairAscent", .mobility),
        ("HKQuantityTypeIdentifierStairDescent", .mobility),
        ("HKQuantityTypeIdentifierRunning", .mobility),
        ("HKQuantityTypeIdentifierSixMinuteWalk", .mobility),
        ("HKQuantityTypeIdentifierAppleWalking", .mobility),
        ("HKCategoryTypeIdentifierMindful", .mind),
        ("HKStateOfMind", .mind),
        ("HKQuantityTypeIdentifierBodyMassIndex", .bodyMeasurements),
        ("HKQuantityTypeIdentifierWaistCircumference", .bodyMeasurements),
        ("HKQuantityTypeIdentifierLeanBodyMass", .bodyMeasurements),
        // Added after running the rules over the reader's own 158 identifiers
        // and reading what fell through — which is the mechanism working rather
        // than an oversight being patched. Unsorted went 20% → 6%.
        ("HKCategoryTypeIdentifierAudioExposureEvent", .hearing),
        ("HKCategoryTypeIdentifierHeadphoneAudioExposureEvent", .hearing),
        ("HKQuantityTypeIdentifierAppleStand", .movement),
        ("HKCategoryTypeIdentifierAppleStand", .movement),
        ("HKQuantityTypeIdentifierFlightsClimbed", .movement),
        ("HKQuantityTypeIdentifierDistance", .movement),
        ("HKQuantityTypeIdentifierPhysicalEffort", .movement),
        ("HKQuantityTypeIdentifierBasalEnergyBurned", .movement),
        ("HKQuantityTypeIdentifierPushCount", .movement),
        ("HKQuantityTypeIdentifierSwimming", .movement),
        ("HKQuantityTypeIdentifierCycling", .movement),
        ("HKCategoryTypeIdentifierLowHeartRateEvent", .heartEvents),
        ("HKCategoryTypeIdentifierHighHeartRateEvent", .heartEvents),
        ("HKCategoryTypeIdentifierIrregularHeartRhythm", .heartEvents),
        ("HKCategoryTypeIdentifierLowCardioFitnessEvent", .heartEvents),
        ("HKQuantityTypeIdentifierBasalBodyTemperature", .bodyMeasurements),
        ("HKQuantityTypeIdentifierWaterTemperature", .environment),
        ("HKQuantityTypeIdentifierUnderwaterDepth", .environment),
    ]

    /// Rule 2/3 — a connector's own namespace, and its sub-scores.
    ///
    /// `contributors.*` is the giveaway: Oura publishes the components of a
    /// daily score under it, and eleven of them arriving as eleven top-level
    /// rows is what made this list unreadable. They are one score's workings,
    /// so they group as one.
    public static func group(for identifier: String) -> Group {
        for (prefix, group) in healthKitPrefixes where identifier.hasPrefix(prefix) {
            return group
        }
        let lower = identifier.lowercased()
        // Oura's stress and resilience fields are one subject — the raw
        // material the stress research reads (backlog N1) — and they file
        // together. ⚠️ **Before the two generic rules below**, both of which
        // would otherwise claim pieces of it: `daily_resilience.contributors.*`
        // are the workings of the *resilience* level, not of an activity score,
        // and `contributors.sleep_recovery` contains `.sleep_` without being
        // sleep detail.
        if lower.hasPrefix("oura.daily_stress") || lower.hasPrefix("oura.daily_resilience") {
            return .stressResilience
        }
        if lower.contains(".contributors.") { return .activityScore }
        if lower.hasPrefix("oura.sleep") || lower.contains(".sleep_") { return .sleepDetail }
        if lower.hasPrefix("oura.daily_activity") { return .activityScore }
        if lower.hasPrefix("oura.daily_spo2") || lower.contains("breath") { return .respiratory }
        if lower.hasPrefix("oura.daily_cardiovascular_age") { return .heartEvents }
        // ⚠️ **Reported by the reader**: *"at the very bottom of the page I see
        // a VO₂ Max data point from Oura… why isn't that with the other VO₂
        // max?"* `oura.vO2_max.vo2_max` matched no rule and landed in "Not yet
        // sorted", which is the bottom of the tab — while the canonical
        // `.vo2Max` it is *already promoted into* sat under Heart & circulation.
        // The bucket named for its own failure did exactly its job.
        if lower.contains("vo2") { return .heartEvents }
        // Withings measure types this app has not promoted. Filed by what they
        // measure rather than left in the bucket — see `RawFieldPresentation`
        // for what each number means, which is the other half of the reader's
        // question about them.
        if lower.hasPrefix("withings.measure.") { return .bodyMeasurements }
        // A HealthKit *category* this app has not prefixed is almost always a
        // symptom tag — Dizziness, Nausea, Fatigue. They have a domain of
        // their own already, so they belong with it rather than in the bucket.
        if identifier.hasPrefix("HKCategoryTypeIdentifier") { return .mind }
        return .unsorted
    }

    /// Whether a field is a component of a score rather than a reading in its
    /// own right — the app should be able to fold these behind one row.
    public static func isScoreComponent(_ identifier: String) -> Bool {
        identifier.lowercased().contains(".contributors.")
    }

    /// **The health check on rule 1.** If more than this share of a reader's
    /// fields land in "Not yet sorted", the prefix table is out of date rather
    /// than the reader being unusual — and a test asserts it against a fixture
    /// built from the identifiers this reader actually has.
    public static let acceptableUnsortedShare = 0.35
}
