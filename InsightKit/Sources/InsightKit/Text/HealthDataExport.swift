import Foundation

/// **Everything the app holds, in one file** — the export a reader hands back
/// so a session can see exactly what they see.
///
/// ## Why this is exhaustive over `DataDomain`
///
/// The previous full export carried `samples` and the unmodelled catalogue and
/// nothing else, so the substance log, the medication regimen and its doses, the
/// side effects, the reader's own profile facts and every derived score were all
/// absent from "export my data". That is the same failure the Data tab kept
/// having before `DataDomain` made completeness a compile error, and it has the
/// same fix: **`section(for:)` below is an exhaustive switch, so a new kind of
/// data — a new connector's, whenever it arrives — cannot ship without saying
/// where it lives in the export.** `HealthDataExportTests` then checks the
/// encoded JSON really carries every one of those keys, because a switch that
/// merely *names* a key would still let the payload go out empty.
///
/// The user's rule, 2026-08-02: *"make sure they include all data from all new
/// connectors — ones I have now and in future."*
public struct HealthDataExport: Encodable, Sendable {

    /// Bumped when a field is added or renamed, so an export can be read
    /// against the shape it was written with.
    public static let schemaVersion = 2

    public struct Medication: Encodable, Sendable {
        public struct Dose: Encodable, Sendable {
            public let takenAt: Date
            public let milligrams: Double
            public let injectionSite: String?
            /// Extrapolated rather than entered — everything derived from it is
            /// drawn dashed, and an export must keep that distinction.
            public let isInferred: Bool
            public let confirmedAt: Date?

            public init(takenAt: Date, milligrams: Double, injectionSite: String?,
                        isInferred: Bool, confirmedAt: Date?) {
                self.takenAt = takenAt
                self.milligrams = milligrams
                self.injectionSite = injectionSite
                self.isInferred = isInferred
                self.confirmedAt = confirmedAt
            }
        }
        public let compound: String
        public let brandName: String?
        public let startedOn: Date
        public let doses: [Dose]

        public init(compound: String, brandName: String?, startedOn: Date, doses: [Dose]) {
            self.compound = compound
            self.brandName = brandName
            self.startedOn = startedOn
            self.doses = doses
        }
    }

    public struct SideEffect: Encodable, Sendable {
        public let name: String
        public let severity: Int
        public let date: Date

        public init(name: String, severity: Int, date: Date) {
            self.name = name
            self.severity = severity
            self.date = date
        }
    }

    /// A card's own output — the number the reader was shown, and the replayed
    /// history behind it. These are **derived, not measured**, and the export
    /// says so in the key name rather than mixing them in with `samples`.
    public struct DerivedScore: Encodable, Sendable {
        public struct Point: Encodable, Sendable {
            public let date: Date
            public let score: Double
            public init(date: Date, score: Double) {
                self.date = date
                self.score = score
            }
        }
        public let card: String
        public let title: String
        public let score: Double?
        /// The card's headline quantity in its own units — a risk percentage, a
        /// heart age — which is a different number from the 0–100 dial.
        public let primaryValue: Double?
        public let headline: String
        public let confidence: String
        public let history: [Point]

        public init(card: String, title: String, score: Double?, primaryValue: Double?,
                    headline: String, confidence: String, history: [Point]) {
            self.card = card
            self.title = title
            self.score = score
            self.primaryValue = primaryValue
            self.headline = headline
            self.confidence = confidence
            self.history = history
        }
    }

    public let schemaVersion: Int
    public let generatedAt: Date
    public let build: String
    /// Every canonical measured series, blood pressure included — a cuff reading
    /// is a `HealthMetricSample` like any other.
    public let samples: [HealthMetricSample]
    /// Imported but not yet modelled — the raw catalogue.
    public let unmodelled: [RawMetricSample]
    public let substances: [SubstanceEvent]
    public let medication: Medication?
    public let sideEffects: [SideEffect]
    /// The standing facts the reader entered: age, sex, cholesterol, weight goal.
    public let profile: UserHealthProfile
    /// What each card computed from all of the above.
    public let derivedScores: [DerivedScore]

    public init(generatedAt: Date, build: String,
                samples: [HealthMetricSample], unmodelled: [RawMetricSample],
                substances: [SubstanceEvent], medication: Medication?,
                sideEffects: [SideEffect], profile: UserHealthProfile,
                derivedScores: [DerivedScore]) {
        self.schemaVersion = Self.schemaVersion
        self.generatedAt = generatedAt
        self.build = build
        self.samples = samples
        self.unmodelled = unmodelled
        self.substances = substances
        self.medication = medication
        self.sideEffects = sideEffects
        self.profile = profile
        self.derivedScores = derivedScores
    }

    // MARK: - Completeness

    /// Which top-level key of this export carries a domain's data.
    ///
    /// **Exhaustive on purpose.** A new `DataDomain` — the shape a new connector
    /// brings — does not compile until it says where in the export it lives, and
    /// `HealthDataExportTests` checks the key it names is really in the encoded
    /// JSON. Between them a connector cannot be added and silently left out of
    /// "export my data".
    public static func exportKey(for domain: DataDomain) -> String {
        switch domain {
        // Cuff readings are canonical samples like everything else measured.
        case .metrics, .bloodPressure: return "samples"
        case .substances: return "substances"
        case .medication: return "medication"
        case .sideEffects: return "sideEffects"
        case .derivedScores: return "derivedScores"
        case .unmodelled: return "unmodelled"
        }
    }

    /// Keys that are not a `DataDomain` but must still be present — the things
    /// the Data tab doesn't file as "data" yet the reader's numbers depend on.
    public static let additionalKeys = ["profile", "derivedScores",
                                        "schemaVersion", "generatedAt", "build"]

    public func json() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }

    // MARK: - Encoding

    enum CodingKeys: String, CodingKey {
        case schemaVersion, generatedAt, build, samples, unmodelled, substances
        case medication, sideEffects, profile, derivedScores
    }

    /// Written by hand for **one** reason: the synthesised encoder uses
    /// `encodeIfPresent` for optionals, so `medication` — the only optional here
    /// — disappeared from the file entirely on a phone with no regimen. A reader
    /// then cannot tell "this person takes nothing" from "the exporter forgot
    /// medication", and telling those apart is the whole point of an export.
    /// `encode` rather than `encodeIfPresent` writes an explicit `null`.
    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(schemaVersion, forKey: .schemaVersion)
        try c.encode(generatedAt, forKey: .generatedAt)
        try c.encode(build, forKey: .build)
        try c.encode(samples, forKey: .samples)
        try c.encode(unmodelled, forKey: .unmodelled)
        try c.encode(substances, forKey: .substances)
        try c.encode(medication, forKey: .medication)
        try c.encode(sideEffects, forKey: .sideEffects)
        try c.encode(profile, forKey: .profile)
        try c.encode(derivedScores, forKey: .derivedScores)
    }
}
