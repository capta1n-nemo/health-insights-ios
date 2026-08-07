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
        case activityScore, sleepDetail, readiness, stressResilience, unsorted

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
            case .activityScore: return "Activity score components (Oura)"
            case .sleepDetail: return "Sleep detail"
            // "(Oura)" in the heading because these are a vendor's own composite
            // numbers relayed, not this app's — the same honesty rule that dashes
            // an inferred line on a chart.
            case .readiness: return "Readiness (Oura)"
            case .stressResilience: return "Stress & resilience (Oura)"
            case .unsorted: return "Not yet sorted"
            }
        }

        /// **What this group is**, in one sentence, shown under the section.
        ///
        /// Standing rule 9 — every data entry carries a "what this is"
        /// description — reached the canonical metrics through
        /// `MetricExplainer` and stopped at the raw catalogue, where it is
        /// needed most: `MetricType.heartRate` at least names itself, and
        /// "Time restored — 0m" does not. Non-optional over an exhaustive
        /// switch for the same reason `MetricExplainer.explanation(for:)` is:
        /// a new group cannot compile until somebody says what it holds.
        ///
        /// ⚠️ **Where the number is a vendor's, the sentence says so.** Oura's
        /// readiness, stress and resilience are composites with an undisclosed
        /// formula; this app relays them and does not re-derive them, and a
        /// blurb that described them as measurements would be the first half of
        /// the merge backlog N1 forbids.
        public var blurb: String {
            switch self {
            case .nutrition:
                return "Nutrients imported from what you logged elsewhere. Nothing here is modelled — these are the figures the source sent."
            case .hearing:
                return "Sound levels your devices measured around you and through your headphones. The daily doses computed from them sit with the metrics above."
            case .daylight:
                return "Time outdoors and ultraviolet exposure, as your watch recorded it."
            case .respiratory:
                return "Breathing measurements — spirometry, blood oxygen and the fields around them."
            case .mobility:
                return "How you move on your feet: gait, steadiness, stairs and walking tests."
            case .mind:
                return "Mindful minutes, states of mind, and the symptoms you or your devices logged."
            case .movement:
                return "Effort and distance covered, plus the energy your body spends at rest."
            case .heartEvents:
                return "Heart notifications and vascular figures your devices raised, rather than continuous readings."
            case .bodyMeasurements:
                return "Body figures the app receives but does not model yet, including how each reading was taken."
            case .environment:
                return "What was around you when a reading was taken — water temperature, depth."
            case .activityScore:
                return "The workings behind Oura's own daily activity score, each 0–100. Oura's numbers, relayed as sent — this app does not compute them and does not use them in its own scores."
            case .sleepDetail:
                return "The finer detail behind each night, beyond the sleep metrics listed above."
            case .readiness:
                return "Oura's own daily readiness score and the pieces behind it, each 0–100. Relayed as sent: the formula is Oura's and is not published, so this app shows it rather than re-deriving it. This app's own Readiness card is a separate figure."
            case .stressResilience:
                return "Oura's own stress and resilience figures — how much of the day it read as stressful or restorative, and how well it thinks you are coping over time. Relayed as sent; the app models no stress metric of its own yet."
            case .unsorted:
                return "Fields the app has received but cannot yet file under a subject. This list is meant to be short — a long one means the sorting rules have fallen behind what your devices are sending, not that your data is unusual."
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
            // The daily sound doses are canonical metrics now
            // (`environmentalSoundDose`, `headphoneSoundDose`), so the raw dBA
            // fields they are computed from file into the same "Hearing"
            // section rather than opening a second heading with the same name
            // — the two-taxonomies bug described above, pre-empted this time
            // instead of reported by the reader.
            case .hearing: return .hearing
            // No canonical equivalent: the app models none of these yet, so a
            // section of their own is the honest answer rather than filing them
            // under something they are not.
            case .daylight, .mind, .environment: return nil
            // Deliberately its own section even though it *could* fold into
            // Activity: eleven fields that are one score's workings are a
            // different kind of thing from a reading, and burying them among
            // real measurements is what made the flat list unreadable.
            case .activityScore: return nil
            // Oura's readiness is not this app's Readiness card, and filing it
            // under "Sleep & recovery" would put a vendor composite among the
            // measurements the app models itself. Its own section, named for
            // whose number it is.
            case .readiness: return nil
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

    /// Rule 2 — **the connector's own collection decides, contributors and all.**
    ///
    /// ⚠️ **This used to be a bare `contains(".contributors.")` sending every
    /// score's workings to `.activityScore`, and it was wrong on screen.** Oura
    /// publishes the components of *each* daily score under the same
    /// `contributors` container, so the reader's readiness contributors — HRV
    /// balance, body temperature, activity balance — and their sleep
    /// contributors — efficiency, latency, restfulness — were all filed under a
    /// heading reading **"Activity score components"**. Seen in the simulator
    /// while finishing backlog D28: searching "readiness" showed three of the
    /// reader's readiness contributors under the activity heading, and the
    /// readiness score itself in "Not yet sorted" below them.
    ///
    /// A section heading is a statement about a subject — the same rule that
    /// killed the two "Nutrition" headings — so the container cannot decide the
    /// subject. The collection can, and it is sitting in the identifier one
    /// component to the left.
    ///
    /// **Order matters within the table**: `oura.daily_sleep` must be tried
    /// before the `.sleep_` catch below, and `daily_resilience.contributors.
    /// sleep_recovery` contains `.sleep_` without being sleep detail.
    private static let providerCollections: [(String, Group)] = [
        ("oura.daily_stress", .stressResilience),
        ("oura.daily_resilience", .stressResilience),
        ("oura.daily_readiness", .readiness),
        ("oura.daily_activity", .activityScore),
        ("oura.daily_sleep", .sleepDetail),
        ("oura.sleep", .sleepDetail),
        ("oura.daily_spo2", .respiratory),
        ("oura.daily_cardiovascular_age", .heartEvents),
    ]

    public static func group(for identifier: String) -> Group {
        for (prefix, group) in healthKitPrefixes where identifier.hasPrefix(prefix) {
            return group
        }
        let lower = identifier.lowercased()
        for (prefix, group) in providerCollections where lower.hasPrefix(prefix) {
            return group
        }
        // No generic `contributors` rule follows on purpose. An unknown
        // collection's components land in "Not yet sorted", which is the bucket
        // named for its own failure doing its job — where the old rule instead
        // gave them a confident and wrong heading.
        if lower.contains(".sleep_") { return .sleepDetail }
        if lower.contains("breath") { return .respiratory }
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
