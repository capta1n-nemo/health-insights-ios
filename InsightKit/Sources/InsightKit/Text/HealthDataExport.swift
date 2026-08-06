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

            /// Hand-written for the same reason the top-level encoder is, and
            /// it should have been written at the same time.
            ///
            /// The top-level fix (see `HealthDataExport.encode`) made the
            /// optional `medication` emit an explicit null, so "takes nothing"
            /// could be told from "the exporter forgot". **Every nested
            /// optional was left on the synthesised encoder**, which uses
            /// `encodeIfPresent` — so an unconfirmed dose simply had no
            /// `confirmedAt` key, which is exactly the ambiguity the top-level
            /// fix existed to remove. Found by audit on 2026-08-04; the guard
            /// test could not see it because its one fixture dose left
            /// `confirmedAt` nil and asserted only on keys that were populated.
            enum CodingKeys: String, CodingKey {
                case takenAt, milligrams, injectionSite, isInferred, confirmedAt
            }

            public func encode(to encoder: any Encoder) throws {
                var c = encoder.container(keyedBy: CodingKeys.self)
                try c.encode(takenAt, forKey: .takenAt)
                try c.encode(milligrams, forKey: .milligrams)
                try c.encode(injectionSite, forKey: .injectionSite)
                try c.encode(isInferred, forKey: .isInferred)
                try c.encode(confirmedAt, forKey: .confirmedAt)
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

        /// Explicit nulls, same reason as `Dose.encode`. A generic prescribed
        /// with no brand must read as `"brandName": null`.
        enum CodingKeys: String, CodingKey {
            case compound, brandName, startedOn, doses
        }

        public func encode(to encoder: any Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(compound, forKey: .compound)
            try c.encode(brandName, forKey: .brandName)
            try c.encode(startedOn, forKey: .startedOn)
            try c.encode(doses, forKey: .doses)
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

        /// Explicit nulls, same reason as `Medication.Dose.encode`. A card that
        /// is not scoring must read as `"score": null` rather than as a missing
        /// key — "this card had nothing to say" and "the exporter dropped it"
        /// are different findings, and the whole point of the file is to let a
        /// reader tell them apart.
        enum CodingKeys: String, CodingKey {
            case card, title, score, primaryValue, headline, confidence, history
        }

        public func encode(to encoder: any Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(card, forKey: .card)
            try c.encode(title, forKey: .title)
            try c.encode(score, forKey: .score)
            try c.encode(primaryValue, forKey: .primaryValue)
            try c.encode(headline, forKey: .headline)
            try c.encode(confidence, forKey: .confidence)
            try c.encode(history, forKey: .history)
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
    /// The regimen the reader is on now, or `null` if none.
    public let medication: Medication?
    /// **Every regimen they were on before it**, newest first.
    ///
    /// `medication` alone loses history, and silently. `startMedication` sets
    /// `isActive = false` on every prior record and `loadActiveMedication`
    /// returns only the active one, so a reader who has ever switched compounds
    /// had the earlier course — and every dose logged against it — missing from
    /// the file while it sat intact in SwiftData. Found by audit on 2026-08-04,
    /// before the reader's first real export rather than after.
    ///
    /// An array rather than a second optional, so an empty history encodes as
    /// `[]` and can never disappear the way a nil optional does.
    public let previousMedication: [Medication]
    public let sideEffects: [SideEffect]
    /// Symptoms the reader tagged, promoted out of the raw catalogue.
    ///
    /// They are also still in `unmodelled`, where they have always been. The
    /// duplication is deliberate: promotion reads rather than moves, so a bug
    /// in it cannot cost the reader data that was already in the file.
    public let symptoms: [SymptomEvent]
    /// Every body scan, whole — measurements, conditions and capture method.
    public let bodyScans: [BodyScan]
    /// The standing facts the reader entered: age, sex, cholesterol, weight goal.
    public let profile: UserHealthProfile
    /// What each card computed from all of the above.
    public let derivedScores: [DerivedScore]
    /// Every logged bleeding day. The cycles themselves are **not** exported:
    /// they are derived from these by `CycleModel`, and exporting a derivation
    /// beside its inputs is how the two get to disagree in someone's archive.
    public let cycles: [CycleDay]

    public init(generatedAt: Date, build: String,
                samples: [HealthMetricSample], unmodelled: [RawMetricSample],
                substances: [SubstanceEvent], medication: Medication?,
                previousMedication: [Medication] = [],
                sideEffects: [SideEffect], symptoms: [SymptomEvent] = [],
                bodyScans: [BodyScan] = [],
                profile: UserHealthProfile,
                derivedScores: [DerivedScore],
                cycles: [CycleDay] = []) {
        self.cycles = cycles
        self.schemaVersion = Self.schemaVersion
        self.generatedAt = generatedAt
        self.build = build
        self.samples = samples
        self.unmodelled = unmodelled
        self.substances = substances
        self.medication = medication
        self.previousMedication = previousMedication
        self.sideEffects = sideEffects
        self.symptoms = symptoms
        self.bodyScans = bodyScans
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
        case .symptoms: return "symptoms"
        case .bodyScans: return "bodyScans"
        case .derivedScores: return "derivedScores"
        case .cycles: return "cycles"
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
        case medication, previousMedication, sideEffects, symptoms
        case bodyScans, profile, derivedScores, cycles
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
        try c.encode(previousMedication, forKey: .previousMedication)
        try c.encode(sideEffects, forKey: .sideEffects)
        try c.encode(symptoms, forKey: .symptoms)
        try c.encode(bodyScans, forKey: .bodyScans)
        try c.encode(profile, forKey: .profile)
        try c.encode(derivedScores, forKey: .derivedScores)
        try c.encode(cycles, forKey: .cycles)
    }
}
