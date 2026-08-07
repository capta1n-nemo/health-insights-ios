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
///
/// ## And a second reason, added 2026-08-06: this file is how a norm gets built
///
/// The reader's tenet: *"we need to build this into the export mechanism, all
/// the data points so when we combine it all at a server-level later, we can
/// build these baselines and norms and global trends."* For most of what this
/// app derives there is **no published norm**, and the app is being built to
/// measure one.
///
/// That changes the test for whether something belongs here. **"It is
/// recomputable" is not a reason to leave a quantity out**: recomputability is
/// a property of the device that still holds the raw data, and a server-side
/// pool will have this file and nothing else. `docs/norms-and-telemetry.md`
/// holds the reasoning, and `exportKey(for: .generatedInsights)` records the
/// call it reversed.
///
/// ⚠️ **This is the personal export and it stays faithful.** The coarsened,
/// cohort-stratified, no-free-text thing a pool would actually receive is a
/// different type — `NormContribution` — and nothing in this build sends
/// either.
///
/// ## Why it decodes as well as encodes (2026-08-07)
///
/// This type was `Encodable` only, and every test on it asserted
/// `json.contains("\"key\"")` — one of them titled "must survive the round trip"
/// without ever decoding. A substring check cannot see a *shape*: on 2026-08-05
/// an importer lost all four sections of a file because
/// `UserHealthProfile.inputs` is a dictionary keyed by an enum, which Swift
/// encodes as an alternating key/value **array** rather than an object. The
/// encode side was word-perfect and the file was still unreadable.
///
/// So the conformance is `Codable`, and `decoded(from:)` below is the one place
/// the reading strategy is stated — an importer that calls it cannot pair
/// `.iso8601` on the way out with a bare decoder on the way in. `Equatable` is
/// here for the same reason and is the part that ages well: the round-trip test
/// compares whole values, so a field added later is compared without anyone
/// remembering to add it to a list.
///
/// ## The one exclusion, and why it is a compile error rather than a rule
///
/// **Credentials.** The reader approved the four remaining fields with one
/// condition — *"do not include tokens"* — and that condition is not held by
/// this file remembering to leave them out. `OAuthTokens` is not `Codable`, so
/// a token cannot be a stored property of anything `Encodable`; and
/// `Connection` below carries a closed `ConnectionState` enum rather than a
/// string, so the free text a provider wraps a failed token in has no field to
/// arrive in either. This repo is public — `docs/privacy-and-ip.md` records
/// what was found exposed once, and that git history cannot be redacted in
/// place. "The export happens not to contain tokens today" and "an export
/// containing tokens does not compile" are different promises.
public struct HealthDataExport: Codable, Equatable, Sendable {

    /// Bumped when a field is added or renamed, so an export can be read
    /// against the shape it was written with. 3 added `holidays`;
    /// 4 added `generatedInsights`; 5 added `connections`,
    /// `suggestionDismissals`, `feedback` and `predictionOutcomes`.
    public static let schemaVersion = 5

    public struct Medication: Codable, Equatable, Sendable {
        public struct Dose: Codable, Equatable, Sendable {
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

    public struct SideEffect: Codable, Equatable, Sendable {
        public let name: String
        public let severity: Int
        public let date: Date

        public init(name: String, severity: Int, date: Date) {
            self.name = name
            self.severity = severity
            self.date = date
        }
    }

    /// One period of the reader's leave, from the merged holiday ledger —
    /// backlog B7 H5. Reader-entered data, so it genuinely exports.
    ///
    /// ⚠️ **A detected period's label is nil by construction** — detection
    /// (`HolidayLedger.detected`) never carries an event's title, because
    /// titles are the one thing the export must not hold (see
    /// `exportKey(for: .calendarEvents)`). The dates are the data point;
    /// `label` is only ever the reader's own typed words.
    public struct Holiday: Codable, Equatable, Sendable {
        /// First and last day off, both inclusive — `HolidayLedger.Period`'s
        /// own convention, kept so the file round-trips without an off-by-one.
        public let firstDay: Date
        public let lastDay: Date
        public let label: String?
        /// `"detected"` or `"entered"`, so whoever reads the file can tell the
        /// calendar's suggestion from the reader's statement.
        public let source: String

        public init(firstDay: Date, lastDay: Date, label: String?, source: String) {
            self.firstDay = firstDay
            self.lastDay = lastDay
            self.label = label
            self.source = source
        }

        /// Hand-written for the reason every encoder in this file is: the
        /// synthesised one drops a nil `label`, and "no label" must be
        /// distinguishable from "the exporter forgot labels".
        enum CodingKeys: String, CodingKey {
            case firstDay, lastDay, label, source
        }

        public func encode(to encoder: any Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(firstDay, forKey: .firstDay)
            try c.encode(lastDay, forKey: .lastDay)
            try c.encode(label, forKey: .label)
            try c.encode(source, forKey: .source)
        }
    }

    /// A card's own output — the number the reader was shown, and the replayed
    /// history behind it. These are **derived, not measured**, and the export
    /// says so in the key name rather than mixing them in with `samples`.
    public struct DerivedScore: Codable, Equatable, Sendable {
        public struct Point: Codable, Equatable, Sendable {
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

    /// **One derived series, whole** — its spec and every dated value the app
    /// has worked out for it.
    ///
    /// Flat rather than a spec/points pair, so a reader of the file never has
    /// to join two arrays to find out what a number means. The spec fields are
    /// `DerivedSeriesSpec`'s, in its own vocabulary: `kind` is a
    /// `DerivedSeriesKind` raw value and `producedBy` is an `InsightID` raw
    /// value, so the file says which card owns the figure without anyone
    /// parsing the id.
    public struct DerivedSeries: Codable, Equatable, Sendable {
        public struct Point: Codable, Equatable, Sendable {
            /// Start of the day the value belongs to, as `DerivedPoint` stores it.
            public let day: Date
            public let value: Double
            public init(day: Date, value: Double) {
                self.day = day
                self.value = value
            }
        }
        public let id: String
        public let displayName: String
        /// Empty where the value carries its own — `DerivedSeriesSpec.unit`'s
        /// convention, kept rather than turned into a null.
        public let unit: String
        /// `modelOutput` / `componentScore` / `componentDeparture`.
        public let kind: String
        public let producedBy: String
        public let higherIsBetter: Bool?
        public let precision: Int
        /// Oldest first, the shape `DerivedSeriesStore.series(_:)` returns.
        public let points: [Point]

        public init(id: String, displayName: String, unit: String, kind: String,
                    producedBy: String, higherIsBetter: Bool?, precision: Int,
                    points: [Point]) {
            self.id = id
            self.displayName = displayName
            self.unit = unit
            self.kind = kind
            self.producedBy = producedBy
            self.higherIsBetter = higherIsBetter
            self.precision = precision
            self.points = points
        }

        /// Hand-written for the reason every encoder in this file is: the
        /// synthesised one drops a nil `higherIsBetter`, and "neither direction
        /// is the good one" — which is the honest answer for a departure in SD
        /// — must not read as "the exporter forgot to say".
        enum CodingKeys: String, CodingKey {
            case id, displayName, unit, kind, producedBy, higherIsBetter, precision, points
        }

        public func encode(to encoder: any Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(id, forKey: .id)
            try c.encode(displayName, forKey: .displayName)
            try c.encode(unit, forKey: .unit)
            try c.encode(kind, forKey: .kind)
            try c.encode(producedBy, forKey: .producedBy)
            try c.encode(higherIsBetter, forKey: .higherIsBetter)
            try c.encode(precision, forKey: .precision)
            try c.encode(points, forKey: .points)
        }
    }

    /// **What a source's connection is doing — and nothing about how it
    /// authenticates.**
    ///
    /// A closed set, deliberately, and this is the point of the type. The app's
    /// own `IntegrationStatus` carries free text on two of its five cases
    /// (`unavailable(reason:)`, `error(String)`), and free text from a provider
    /// is the one place an access token can arrive without anyone writing it
    /// down on purpose — an OAuth failure body is quoted straight into
    /// `.error`. Mapping onto a `String` here would have let that through and
    /// left "no credentials in the export" resting on the vigilance of whoever
    /// next edits the mapper.
    ///
    /// So the file records *which* of the five states a source is in and gets no
    /// vocabulary for anything else. It pairs with `OAuthTokens` giving up
    /// `Codable` (backlog Q10, 2026-08-06): between them, neither a token nor
    /// the text a provider wrapped one in has a shape it could take in this
    /// file. The reader's condition was *"do not include tokens"*, and a
    /// condition kept by construction is a different thing from one kept by
    /// habit.
    public enum ConnectionState: String, Codable, Sendable {
        case notConnected, connecting, connected, unavailable, error
    }

    /// One data source and where its connection stands.
    ///
    /// **Why this is in the export at all**, when it is plainly not a health
    /// measurement: the reader's standing rule 11 — *a quantity missing from
    /// the export is a quantity that can never become a norm*. Which sources a
    /// person has connected, and how recently each last delivered, is the
    /// provenance of every other key in this file. A pooled dataset that cannot
    /// tell a phone with four connected wearables from one running on Apple
    /// Health alone cannot honestly compare the two, and there is nowhere else
    /// for it to learn that: connection state lives in the Keychain and
    /// SwiftData, neither of which leaves the device.
    public struct Connection: Codable, Equatable, Sendable {
        /// The integration's stable id — the same string as `MetricSource.id`,
        /// so a connection joins to the samples it produced.
        public let integration: String
        public let state: ConnectionState
        /// When this source last delivered, where the source records it. `null`
        /// where it is connected but has never synced, or does not track it.
        public let lastSync: Date?

        public init(integration: String, state: ConnectionState, lastSync: Date?) {
            self.integration = integration
            self.state = state
            self.lastSync = lastSync
        }

        /// Hand-written for the reason every encoder in this file is: the
        /// synthesised one drops a nil `lastSync`, and "connected but has never
        /// brought anything back" — which is a real and diagnostic state — must
        /// not read as "the exporter forgot to say when".
        enum CodingKeys: String, CodingKey {
            case integration, state, lastSync
        }

        public func encode(to encoder: any Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(integration, forKey: .integration)
            try c.encode(state, forKey: .state)
            try c.encode(lastSync, forKey: .lastSync)
        }
    }

    /// One "was this right?" tap, as the ledger recorded it.
    ///
    /// The cohort travels with it because it was recorded with it: a rating is
    /// only interpretable against who gave it, and re-deriving the cohort from
    /// `profile` at read time would attribute an old rating to today's age band.
    /// Every field is already a coarse bucket — see `Cohort`.
    public struct Feedback: Codable, Equatable, Sendable {
        public let card: InsightID
        public let rating: FeedbackRating
        /// The model revision the rating was about. A rating is not comparable
        /// across versions, which is what this string exists to say.
        public let modelVersion: String
        public let cohort: Cohort
        public let recordedAt: Date

        public init(card: InsightID, rating: FeedbackRating, modelVersion: String,
                    cohort: Cohort, recordedAt: Date) {
            self.card = card
            self.rating = rating
            self.modelVersion = modelVersion
            self.cohort = cohort
            self.recordedAt = recordedAt
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
    ///
    /// ⚠️ **The defaulted argument is the hazard, and no test here can catch
    /// it.** `DataExportView.buildFullExport()` shipped without passing
    /// `cycles:` at all, so a reader with logged bleeding days exported
    /// `"cycles": []` — the *key present and silently wrong* case, which is
    /// worse than the missing key the hand-written encoders exist to prevent,
    /// because nothing about the file says anything was dropped. Fixed
    /// 2026-08-06.
    ///
    /// `testEveryDataDomainHasAKeyThatIsActuallyInTheJSON` cannot see this:
    /// it asserts the key is in the encoded payload, and an empty array
    /// satisfies that. The gap is in the **caller**, and the app target has no
    /// tests to put one in — a single `HealthInsights` native target with no
    /// test host.
    ///
    /// **This is no longer only a comment.** Two checks now hold the category
    /// that `= []` opens, because a comment is not a check:
    ///
    /// - `HealthDataExportTests.testEveryDataDomainsKeyIsPopulatedOnAFullyPopulatedExport`
    ///   decodes the payload and insists every domain's key carries something
    ///   on a fixture that holds one of everything — closing the
    ///   key-present-but-empty half inside InsightKit.
    /// - `scripts/verify.sh` reads the parameter labels off this initialiser
    ///   and fails if `DataExportView.buildFullExport()` does not pass every
    ///   one of them — closing the caller half, which no test can reach.
    public let cycles: [CycleDay]
    /// The merged holiday ledger — dates, reader-typed labels, and which of the
    /// two sources each period came from. **The one calendar-derived thing that
    /// exports**, and it can only do so because detection strips titles; see
    /// `Holiday`.
    public let holidays: [Holiday]
    /// **Every figure the app has derived, day by day** — the fitness ages, the
    /// weekly doses, and each contributor's own 0–100 and departure in SD.
    ///
    /// ⚠️ **This reverses a call made earlier the same day, deliberately.** See
    /// `exportKey(for:)` below, which records the superseded reasoning in full:
    /// these were left out because they replay from `samples`, and that is true
    /// on a phone and false of a server-side pool, which is the only place a
    /// norm can be built. `docs/norms-and-telemetry.md` is the authority.
    ///
    /// Still derived and still never dressed as measured — they are in their
    /// own key, with `kind` and `producedBy` on every one, exactly as
    /// `derivedScores` is separate from `samples`.
    public let generatedInsights: [DerivedSeries]

    // MARK: - The four that were in no key at all (backlog Q10)
    //
    // Connection state, suggestion dismissals, the feedback ledger and
    // prediction outcomes were each held on the phone and named by nothing in
    // this file. The token half of Q10 shipped first and separately — see
    // `ConnectionState` and `OAuthTokens` — because "export the connections"
    // and "never export a credential" are the same sentence, and the second
    // half had to be a compile error before the first could be written at all.
    //
    // None of the four is a `DataDomain`: they are not things the Data tab
    // shows. They are in `additionalKeys` instead, which is what
    // `testTheProfileAndDerivedScoresAreExportedToo` walks.

    /// Every registered source and where its connection stands. **Never a
    /// credential** — `Connection` has no field one could occupy.
    public let connections: [Connection]

    /// Every suggestion the reader has waved away, and when.
    ///
    /// A dismissal is a *judgement*, not a derivation: it is the reader saying
    /// this app was wrong to raise something, and it cannot be recomputed from
    /// anything else in the file. `SuggestionVisibility` prunes a dismissal once
    /// its suggestion stops being true, so what is here is what is still live.
    public let suggestionDismissals: [SuggestionDismissal]

    /// Every "was this accurate?" tap.
    public let feedback: [Feedback]

    /// Every recorded "the model predicted X, the truth was Y" pair, with the
    /// raw numbers as the device holds them.
    ///
    /// ⚠️ **This is the personal export, so the raw pair travels.** The
    /// coarsened, DP-noised thing that would leave the phone if sharing were
    /// ever switched on is `TelemetryEvent`, built by `Telemetry.event(from:)`,
    /// and it is a different type on purpose. Nothing in this build transmits
    /// either.
    public let predictionOutcomes: [PredictionOutcome]

    public init(generatedAt: Date, build: String,
                samples: [HealthMetricSample], unmodelled: [RawMetricSample],
                substances: [SubstanceEvent], medication: Medication?,
                previousMedication: [Medication] = [],
                sideEffects: [SideEffect], symptoms: [SymptomEvent] = [],
                bodyScans: [BodyScan] = [],
                profile: UserHealthProfile,
                derivedScores: [DerivedScore],
                cycles: [CycleDay] = [],
                holidays: [Holiday] = [],
                generatedInsights: [DerivedSeries] = [],
                connections: [Connection] = [],
                suggestionDismissals: [SuggestionDismissal] = [],
                feedback: [Feedback] = [],
                predictionOutcomes: [PredictionOutcome] = []) {
        self.cycles = cycles
        self.holidays = holidays
        self.generatedInsights = generatedInsights
        self.connections = connections
        self.suggestionDismissals = suggestionDismissals
        self.feedback = feedback
        self.predictionOutcomes = predictionOutcomes
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
        // ⚠️ **Deliberately shares the "unmodelled" key and emits nothing.**
        // A calendar event carries a title and a location — the most
        // identifying strings this app holds — and the reader's own condition on
        // the export was that it must not carry credentials. The same reasoning
        // applies here with more force: an export is a file that leaves the
        // device. The events stay on the phone.
        case .calendarEvents: return "unmodelled"
        case .cycles: return "cycles"
        // Reader-entered (and date-only detected) leave genuinely exports —
        // unlike the events above, because the ledger holds no titles.
        case .holidays: return "holidays"
        case .unmodelled: return "unmodelled"
        // ⚠️ **Reversed 2026-08-06, hours after it was written.** The
        // superseded reasoning, kept verbatim because it is sound about the
        // job it was reasoning about:
        //
        //   "Derived series are recomputed from `samples` by replaying the
        //   models — persisting them would export a cache, and an import would
        //   then carry figures a newer model no longer stands behind. The
        //   samples key *is* their data; the figures come back on the first
        //   launch after an import, the same way score history does."
        //
        // That is correct for a **personal** export — restore, inspect, hand
        // back to a session — and wrong for the reader's stated purpose. Their
        // tenet, 2026-08-06: *"we need to build this into the export mechanism,
        // all the data points so when we combine it all at a server-level
        // later, we can build these baselines and norms and global trends."*
        //
        // Recomputability is a property of **the device that still has the raw
        // data**. A server-side pool has the file and nothing else, so a series
        // omitted here is a series that can never become a norm — and the
        // derived figures are precisely the ones with no published norm, which
        // makes them the ones most worth pooling. See
        // `docs/norms-and-telemetry.md`.
        case .generatedInsights: return "generatedInsights"
        }
    }

    /// Every derived series the store holds, in export shape.
    ///
    /// Lives here rather than in the app target so the mapping is tested: the
    /// app target has no test host, and the one line it now writes —
    /// `generatedInsights: HealthDataExport.derivedSeries(from: model.derivedSeries)`
    /// — has nowhere to go wrong.
    public static func derivedSeries(from store: DerivedSeriesStore) -> [DerivedSeries] {
        store.seriesIDs.compactMap { id in
            guard let spec = store.spec(id) else { return nil }
            return DerivedSeries(
                id: id.rawValue,
                displayName: spec.displayName,
                unit: spec.unit,
                kind: spec.kind.rawValue,
                producedBy: spec.producedBy.rawValue,
                higherIsBetter: spec.higherIsBetter,
                precision: spec.precision,
                points: store.series(id).map { .init(day: $0.day, value: $0.value) })
        }
    }

    /// Keys that are not a `DataDomain` but must still be present — the things
    /// the Data tab doesn't file as "data" yet the reader's numbers depend on.
    ///
    /// The last four are Q10's: connection state, suggestion dismissals, the
    /// feedback ledger and prediction outcomes. None is a `DataDomain` — the
    /// Data tab does not show any of them — so the domain switch above cannot
    /// speak for them and this list is what holds them in the file.
    public static let additionalKeys = ["profile", "derivedScores",
                                        "schemaVersion", "generatedAt", "build",
                                        "connections", "suggestionDismissals",
                                        "feedback", "predictionOutcomes"]

    public func json() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }

    /// Read a file this type wrote. **The one place the reading strategy lives.**
    ///
    /// `json()` sets `.iso8601`; a decoder that does not is a file full of
    /// unreadable dates, and the mismatch is invisible until someone tries to
    /// import. Pairing the two here means an importer cannot get half of the
    /// contract — which is the half that went wrong on 2026-08-05.
    ///
    /// ⚠️ Dates round-trip to **whole seconds**: ISO-8601 without fractional
    /// seconds is what `json()` writes, so a re-read `generatedAt` is truncated.
    /// That is a property of the file, not of this function.
    public static func decoded(from data: Data) throws -> HealthDataExport {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(HealthDataExport.self, from: data)
    }

    // MARK: - Encoding

    enum CodingKeys: String, CodingKey {
        case schemaVersion, generatedAt, build, samples, unmodelled, substances
        case medication, previousMedication, sideEffects, symptoms
        case bodyScans, profile, derivedScores, cycles, holidays, generatedInsights
        case connections, suggestionDismissals, feedback, predictionOutcomes
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
        try c.encode(holidays, forKey: .holidays)
        try c.encode(generatedInsights, forKey: .generatedInsights)
        try c.encode(connections, forKey: .connections)
        try c.encode(suggestionDismissals, forKey: .suggestionDismissals)
        try c.encode(feedback, forKey: .feedback)
        try c.encode(predictionOutcomes, forKey: .predictionOutcomes)
    }
}
