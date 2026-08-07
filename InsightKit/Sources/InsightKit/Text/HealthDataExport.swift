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
/// ## Why it is now the *only* export (2026-08-07, backlog B20)
///
/// Settings ▸ Export my data used to offer five surfaces: this JSON and four
/// separate text files. The reader: *"I hate having all these different export
/// options … just have one export option that contains everything. This should
/// also include troubleshooting, and the data & model improvements."*
///
/// So there is one button and one file. The four text reports are folded in as
/// `reports` — see that type for why each of them earns its place rather than
/// being deleted — and the correction record, which had no export path at all,
/// is `improvements`. Nothing about a question a reader has should require them
/// to have picked the right file before they asked it.
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
    /// `suggestionDismissals`, `feedback` and `predictionOutcomes`;
    /// 6 added `reports` and `improvements` — the four side files folded in and
    /// the correction record, so this file is the *only* export (backlog B20/R4)
    /// — plus `sickDays` (§B11-4) and `tags` (§B12), which landed in parallel.
    /// ⚠️ Three agents raised the version to 6 on the same afternoon; it is one
    /// version carrying all four keys, not three separate bumps.
    /// 7 adds `flaggedEvents` (P32) — **and is subject to the same caveat**: if
    /// another agent in the same wave also lands a key at 7, it is one version
    /// carrying both, not two bumps. The number tracks the *shape* a file was
    /// written with; two keys added the same afternoon share a shape.
    /// 7 added `labResults` (backlog Q7 — every analyte from a report, with the
    /// confidence the reading was made at) and `ecgRecords` (I7 — an imported
    /// trace's metadata, never an interpretation).
    /// 7 added `supplements` — the reader's stack, whole (Q8 / B3-25).
    public static let schemaVersion = 7

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

    /// One stretch of illness from the merged `SickDayLedger` — §B11-4.
    ///
    /// **Reader-stated data, so it genuinely exports**, and the same privacy
    /// rule as `Holiday` is what lets it: a detected period's label is nil by
    /// construction, because `SickDayLedger.detected` never carries an event's
    /// title. A sick-day title is a health fact in somebody's own words, which
    /// is the one thing that must not travel.
    ///
    /// ⚠️ **It is a statement, not a measurement.** Whoever pools this file must
    /// read a sick day as "this person said they were ill", never as a confirmed
    /// illness and never as a label to train a detector against without saying
    /// so — `docs/illness-detection-evidence-2026-08-07.md` has the numbers, and
    /// self-tagged illness is exactly the weak reference standard that makes
    /// every vendor's published accuracy figure unusable.
    /// **One day the app guessed about, and what the reader answered** —
    /// backlog `B11-2`/`B11-9`.
    ///
    /// The guess, the answer and the numbers the guess was made from are three
    /// separate things here exactly as they are in `IllnessJudgement`, and for
    /// the same reason: merged, a pool could never measure how often the model
    /// was right, which is the only thing this record is for.
    ///
    /// ⚠️ **No free text and no symptom names.** The artifact is numbers only —
    /// `docs/privacy-and-ip.md`'s rule is the shape of a finding, never the
    /// reading, and an illness record is the sharpest case of it in this file.
    public struct IllnessAnswer: Codable, Equatable, Sendable {
        public let day: Date
        /// `IllnessKind`'s raw value — the app's own guess, untouched by the
        /// answer.
        public let guessedKind: String
        /// `"unstated"`, `"mild"`, `"moderate"`, `"severe"`, or null.
        public let guessedSeverity: String?
        /// What the reader said, or null where they confirmed the guess rather
        /// than correcting it. **Null and a matching correction are different
        /// records** and both are kept.
        public let correctedKind: String?
        public let correctedSeverity: String?
        public let isConfirmed: Bool
        public let reviewedAt: Date?
        /// The day as it stood when the guess was made, in null SDs.
        public let physiologicalExcess: Double
        public let accumulatedStatistic: Double
        public let reportedExcess: Double
        public let leaningSignals: Int
        public let wasJudged: Bool

        public init(day: Date, guessedKind: String, guessedSeverity: String?,
                    correctedKind: String?, correctedSeverity: String?,
                    isConfirmed: Bool, reviewedAt: Date?,
                    physiologicalExcess: Double, accumulatedStatistic: Double,
                    reportedExcess: Double, leaningSignals: Int, wasJudged: Bool) {
            self.day = day
            self.guessedKind = guessedKind
            self.guessedSeverity = guessedSeverity
            self.correctedKind = correctedKind
            self.correctedSeverity = correctedSeverity
            self.isConfirmed = isConfirmed
            self.reviewedAt = reviewedAt
            self.physiologicalExcess = physiologicalExcess
            self.accumulatedStatistic = accumulatedStatistic
            self.reportedExcess = reportedExcess
            self.leaningSignals = leaningSignals
            self.wasJudged = wasJudged
        }

        /// Straight from the stored judgement, so the file and the phone cannot
        /// disagree about what was answered.
        public init(_ judgement: IllnessJudgement) {
            self.init(day: judgement.day,
                      guessedKind: judgement.estimate.assessment.kind.rawValue,
                      guessedSeverity: judgement.estimate.assessment.severity?.rawValue,
                      correctedKind: judgement.correction?.kind.rawValue,
                      correctedSeverity: judgement.correction?.severity?.rawValue,
                      isConfirmed: judgement.isConfirmed,
                      reviewedAt: judgement.reviewedAt,
                      physiologicalExcess: judgement.estimate.artifact.physiologicalExcess,
                      accumulatedStatistic: judgement.estimate.artifact.accumulatedStatistic,
                      reportedExcess: judgement.estimate.artifact.reportedExcess,
                      leaningSignals: judgement.estimate.artifact.leaningSignals,
                      wasJudged: judgement.estimate.artifact.wasJudged)
        }

        /// Hand-written for the reason every encoder in this file is: the
        /// synthesised one drops nil optionals, and "they confirmed the guess"
        /// must be distinguishable from "the exporter forgot corrections".
        enum CodingKeys: String, CodingKey {
            case day, guessedKind, guessedSeverity, correctedKind, correctedSeverity
            case isConfirmed, reviewedAt
            case physiologicalExcess, accumulatedStatistic, reportedExcess
            case leaningSignals, wasJudged
        }

        public func encode(to encoder: any Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(day, forKey: .day)
            try c.encode(guessedKind, forKey: .guessedKind)
            try c.encode(guessedSeverity, forKey: .guessedSeverity)
            try c.encode(correctedKind, forKey: .correctedKind)
            try c.encode(correctedSeverity, forKey: .correctedSeverity)
            try c.encode(isConfirmed, forKey: .isConfirmed)
            try c.encode(reviewedAt, forKey: .reviewedAt)
            try c.encode(physiologicalExcess, forKey: .physiologicalExcess)
            try c.encode(accumulatedStatistic, forKey: .accumulatedStatistic)
            try c.encode(reportedExcess, forKey: .reportedExcess)
            try c.encode(leaningSignals, forKey: .leaningSignals)
            try c.encode(wasJudged, forKey: .wasJudged)
        }
    }

    public struct SickDay: Codable, Equatable, Sendable {
        /// First and last day ill, both inclusive — `SickDayLedger.Period`'s
        /// convention, so the file round-trips without an off-by-one.
        public let firstDay: Date
        public let lastDay: Date
        public let label: String?
        /// `"unstated"`, `"mild"`, `"moderate"`, `"severe"`, or null where
        /// nobody graded it. Null and `"unstated"` are different records and
        /// both are kept — see `SickDayLedger.Period.severity`.
        public let severity: String?
        /// `"detected"` or `"entered"`.
        public let source: String

        public init(firstDay: Date, lastDay: Date, label: String?,
                    severity: String?, source: String) {
            self.firstDay = firstDay
            self.lastDay = lastDay
            self.label = label
            self.severity = severity
            self.source = source
        }

        /// Hand-written for the reason every encoder in this file is: the
        /// synthesised one drops nil optionals, and "not graded" must be
        /// distinguishable from "the exporter forgot grades".
        enum CodingKeys: String, CodingKey {
            case firstDay, lastDay, label, severity, source
        }

        public func encode(to encoder: any Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(firstDay, forKey: .firstDay)
            try c.encode(lastDay, forKey: .lastDay)
            try c.encode(label, forKey: .label)
            try c.encode(severity, forKey: .severity)
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

    // MARK: - The four side files, folded in (backlog B20)

    /// **The prose reports, as named sections of the one file.**
    ///
    /// The reader, 2026-08-07: *"I hate having all these different export
    /// options in the 'Export my Data', just have one export option that
    /// contains everything. This should also include troubleshooting, and the
    /// data & model improvements."*
    ///
    /// Until then Settings ▸ Export my data offered **five** surfaces — this
    /// JSON plus four separate text files — and choosing between them was left
    /// to a reader who cannot be expected to know which one answers a question
    /// they have not been asked yet. They are folded in here rather than
    /// deleted, because each of them earns its place:
    ///
    /// - `inventory` — one line per signal: how many readings, over what dates,
    ///   from which device, and the range of values. **The most useful single
    ///   artefact this app produces**, and the reason `DataInventory` exists:
    ///   a bedtime sat recorded as unavailable for several sessions while it
    ///   was in every payload, being discarded at ingest.
    /// - `cardOutputs` — every card as the reader actually sees it, with its
    ///   drivers, weighted shares and which declared inputs have data. Built as
    ///   a diagnosis instrument and found a live defect on first use.
    /// - `modelInternals` — what the cards judge *against*: the personal
    ///   baselines behind every "vs your normal", the comparison pools and
    ///   their sizes. Same story.
    /// - `diagnostics` — the troubleshooting log, `DiagnosticsLog.exportText()`.
    ///
    /// ⚠️ **Strings, deliberately.** These are rendered reports meant for a
    /// person (or a session) to read, not structured data to be pooled — every
    /// *quantity* in them is already a first-class key elsewhere in this file.
    /// Re-encoding them as JSON would duplicate the numbers in a second,
    /// drift-prone shape; keeping them as text keeps them honest about being a
    /// rendering.
    ///
    /// An empty string means "this build had nothing to say", never "the
    /// exporter forgot" — the keys are always present, same contract as every
    /// hand-written encoder in this file.
    public struct Reports: Codable, Equatable, Sendable {
        public let inventory: String
        public let cardOutputs: String
        public let modelInternals: String
        public let diagnostics: String

        public init(inventory: String = "", cardOutputs: String = "",
                    modelInternals: String = "", diagnostics: String = "") {
            self.inventory = inventory
            self.cardOutputs = cardOutputs
            self.modelInternals = modelInternals
            self.diagnostics = diagnostics
        }

        /// For a bundle built by something other than the app's own exporter.
        public static let empty = Reports()
    }

    /// **What the app guessed, what the reader said, and the thing it judged.**
    ///
    /// The reader's *"data & model improvement"*, which had no export path at
    /// all until now (backlog R4). `R3` shipped the three-layer record itself —
    /// `CalendarEventJudgement` keeps the classification, the correction and a
    /// snapshot of the event as it stood when it was classified — and `R5` ruled
    /// how much of it may travel. Nothing carried any of it into a file.
    ///
    /// ## Why this is tier-shaped when nothing else in the file is
    ///
    /// Every other key here is the personal export at full fidelity, because a
    /// reader handing back their own data has already decided. A correction is
    /// different in one respect that decides it: **it carries the whole
    /// artifact's words** — an event's title, its location, who was invited —
    /// which are the most identifying strings this app holds, and which is
    /// exactly why `exportKey(for: .calendarEvents)` emits nothing.
    ///
    /// The reader has already ruled on those words, in `R5`: **Full** is *"the
    /// artifact plus the before/after categories"*, **Metadata only** is *"the
    /// correction metadata (e.g. Blood pressure estimate is 13 BP above actual
    /// cuff)"*, and both are on by default. So this key honours that ruling
    /// rather than inventing a second answer to a question the reader has
    /// already answered — and it does it by going through
    /// `SharingTier.shape(kind:changes:fields:)` like every other shaped record,
    /// so a reader who turns Full off sees the difference in their own export.
    ///
    /// ⚠️ **`tier` is `null` where the reader has switched both tiers off**, and
    /// that is the whole reason it is a stored field: an empty `corrections`
    /// array otherwise reads identically to "this person has never corrected
    /// anything", and those are opposite findings.
    public struct Improvements: Codable, Equatable, Sendable {

        /// One correction, dated.
        ///
        /// `SharedRecord` carries no timestamp — it is a payload shape, not a
        /// ledger row — and a correction record with no order is a set of
        /// anecdotes. `recordedAt` is the judgement's `reviewedAt` or the
        /// outcome's `recordedAt`, and it is `null` for the pre-`R3` rows that
        /// never recorded one rather than being invented from today.
        public struct Correction: Codable, Equatable, Sendable {
            public let recordedAt: Date?
            public let record: SharedRecord
            /// The one-sentence rendering, assembled by `SharedRecord.summary`
            /// **from the shaped fields only** — so it can never name something
            /// the tier has already dropped. Stored rather than computed so a
            /// reader of the file gets it without reimplementing the assembly.
            public let summary: String

            public init(recordedAt: Date?, record: SharedRecord) {
                self.recordedAt = recordedAt
                self.record = record
                self.summary = record.summary
            }

            /// Hand-written for the reason every encoder in this file is: a nil
            /// `recordedAt` is a real state (a row written before the reviewed
            /// timestamp existed) and must not read as a dropped field.
            enum CodingKeys: String, CodingKey {
                case recordedAt, record, summary
            }

            public func encode(to encoder: any Encoder) throws {
                var c = encoder.container(keyedBy: CodingKeys.self)
                try c.encode(recordedAt, forKey: .recordedAt)
                try c.encode(record, forKey: .record)
                try c.encode(summary, forKey: .summary)
            }
        }

        /// The tier in force when the file was written, or `null` where the
        /// reader has both switched off — which is a refusal, not an absence.
        public let tier: SharingTier?
        /// Newest first, nils last.
        public let corrections: [Correction]

        public init(tier: SharingTier?, corrections: [Correction]) {
            self.tier = tier
            self.corrections = corrections
        }

        /// For a bundle built by something other than the app's own exporter.
        public static let empty = Improvements(tier: nil, corrections: [])

        /// Hand-written so a nil `tier` is an explicit null. "Both tiers off"
        /// is the one state this key exists to make visible.
        enum CodingKeys: String, CodingKey { case tier, corrections }

        public func encode(to encoder: any Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(tier, forKey: .tier)
            try c.encode(corrections, forKey: .corrections)
        }

        /// **Build the improvement record from the two ledgers that hold one.**
        ///
        /// Lives in InsightKit rather than in the app target for the reason
        /// `derivedSeries(from:)` does: the app target has no test host, so a
        /// mapping written there is a mapping nothing checks. The caller is one
        /// line and has nowhere to go wrong.
        ///
        /// A `nil` tier is the reader having switched both off, and it returns
        /// the refusal — tier `null`, no corrections — rather than silently
        /// emitting an empty list that reads as "never corrected anything".
        public static func build(tier: SharingTier?,
                                 judgements: [CalendarEventJudgement],
                                 outcomes: [PredictionOutcome]) -> Improvements {
            guard let tier else { return Improvements(tier: nil, corrections: []) }
            var corrections: [Correction] = []
            for judgement in judgements {
                guard let record = judgement.sharedRecord(under: tier) else { continue }
                corrections.append(Correction(recordedAt: judgement.reviewedAt, record: record))
            }
            for outcome in outcomes {
                guard let record = outcome.sharedRecord(under: tier) else { continue }
                corrections.append(Correction(recordedAt: outcome.recordedAt, record: record))
            }
            // Newest first, undated last — the order a person reading the file
            // wants, and stable so two exports of the same phone compare.
            corrections.sort {
                switch ($0.recordedAt, $1.recordedAt) {
                case let (a?, b?): return a > b
                case (nil, _?): return false
                case (_?, nil): return true
                case (nil, nil): return false
                }
            }
            return Improvements(tier: tier, corrections: corrections)
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
    /// **The reader's supplement stack**, whole — every product, its declared
    /// ingredient list including the lines that declare no amount, and how many
    /// servings a day of each. Backlog Q8 / B3-25.
    ///
    /// Exported as the *entries* rather than as the computed totals, and
    /// deliberately: a total is a function of a limit table that this app
    /// compiles in and will revise, so a file carrying only totals would carry
    /// figures a later table no longer stands behind. The labels do not change.
    /// The derived shares reach the file too, through `generatedInsights`.
    public let supplements: [SupplementEntry]
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
    /// **One flagged half-hour, its guess and its answer** — backlog P32.
    ///
    /// ⚠️ **The privacy design is the absence of fields, not the discipline of
    /// whoever fills them in.** There is no coordinate property, no note
    /// property and no timestamp finer than a day, so a future caller cannot put
    /// one there by accident — the same construction that lets `Connection`
    /// exist without a credential. `exportKey(for: .flaggedEvents)` says why each
    /// omission is the right call.
    ///
    /// What is left is what a pooled dataset could actually build a norm from,
    /// and it is a norm nobody has: **how often a guess at the cause of an
    /// unexplained heart-rate elevation turns out to be right**. There is no
    /// published figure for that, because it needs labels only the person can
    /// supply. This is that labelled set, built one honest answer at a time.
    ///
    /// ⚠️ **`guess` and `answer` are separate keys and must stay separate.** A
    /// file that merged them would be a file in which the app was never wrong.
    public struct FlaggedEventExport: Codable, Equatable, Sendable {
        /// The day it happened. **Not the time** — see the key comment.
        public let day: Date
        public let minutes: Int
        /// `FlagTrigger.rawValue`.
        public let trigger: String
        /// How far above the reader's own typical level the peak sat, in their
        /// own robust standard deviations. The measured quantity.
        public let departures: Double
        /// How many days of their own history that reference was built from. A
        /// departure travels with its reference depth or it is not a departure.
        public let referenceDays: Int
        /// Steps in the window, where any were recorded. Null and zero are
        /// different records: null is a watch that was off, zero is a person
        /// sitting still.
        public let stepsInWindow: Double?
        /// `PlaceFamiliarity.rawValue` — one of four words, never a position.
        public let placeFamiliarity: String
        /// `EventCause.rawValue`, or null where the app offered nothing.
        public let guess: String?
        /// What the reader said, or null while they have not looked.
        public let answer: String?
        /// True where they looked and agreed. Distinct from an absent answer.
        public let confirmed: Bool
        /// The detector that produced the guess, so a judgement made against one
        /// version is never pooled as evidence about another.
        public let modelVersion: String

        public init(day: Date, minutes: Int, trigger: String, departures: Double,
                    referenceDays: Int, stepsInWindow: Double?,
                    placeFamiliarity: String, guess: String?, answer: String?,
                    confirmed: Bool, modelVersion: String) {
            self.day = day
            self.minutes = minutes
            self.trigger = trigger
            self.departures = departures
            self.referenceDays = referenceDays
            self.stepsInWindow = stepsInWindow
            self.placeFamiliarity = placeFamiliarity
            self.guess = guess
            self.answer = answer
            self.confirmed = confirmed
            self.modelVersion = modelVersion
        }

        /// Built from the **stored judgement**, which is what survives when the
        /// event stops being detected — the artifact carries the measurement, so
        /// an answered event exports whether or not today's detector still finds
        /// it. A row built from the live event instead would silently drop
        /// exactly the corrections that taught the app most.
        ///
        /// Returns nil for a judgement with no artifact: there is nothing to say
        /// about the measurement, and inventing it from today's detector is the
        /// history-rewrite the snapshot exists to prevent.
        public init?(_ judgement: FlaggedEventJudgement,
                     calendar: Calendar = .current) {
            guard let artifact = judgement.artifact else { return nil }
            self.init(day: calendar.startOfDay(for: artifact.start),
                      minutes: Int((artifact.end.timeIntervalSince(artifact.start) / 60).rounded()),
                      trigger: artifact.trigger.rawValue,
                      departures: artifact.evidence.departures,
                      referenceDays: artifact.evidence.referenceDays,
                      stepsInWindow: artifact.evidence.stepsInWindow,
                      placeFamiliarity: artifact.placeFamiliarity.rawValue,
                      guess: judgement.guess?.rawValue,
                      answer: judgement.correction?.rawValue,
                      confirmed: judgement.isConfirmed,
                      modelVersion: artifact.modelVersion)
        }

        /// Hand-written for the reason every encoder in this file is: the
        /// synthesised one drops nil optionals, and "the app had no guess" must
        /// be distinguishable from "the exporter forgot guesses".
        enum CodingKeys: String, CodingKey {
            case day, minutes, trigger, departures, referenceDays, stepsInWindow
            case placeFamiliarity, guess, answer, confirmed, modelVersion
        }

        public func encode(to encoder: any Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(day, forKey: .day)
            try c.encode(minutes, forKey: .minutes)
            try c.encode(trigger, forKey: .trigger)
            try c.encode(departures, forKey: .departures)
            try c.encode(referenceDays, forKey: .referenceDays)
            try c.encode(stepsInWindow, forKey: .stepsInWindow)
            try c.encode(placeFamiliarity, forKey: .placeFamiliarity)
            try c.encode(guess, forKey: .guess)
            try c.encode(answer, forKey: .answer)
            try c.encode(confirmed, forKey: .confirmed)
            try c.encode(modelVersion, forKey: .modelVersion)
        }
    }

    /// **The calendar, at `.full` only.** Empty at every other tier.
    ///
    /// ⚠️ The reader's ruling, 2026-08-07: *"if they have full sharing your
    /// corrections enabled, it will be enabled for that future feature (server)
    /// and the export."* `DataExportView` is where the tier is read; this type
    /// only carries what it was handed, so **nothing here re-decides it**.
    public let calendarEvents: [CalendarEvent]
    /// The merged sick-day ledger — §B11-4. Dates, the reader's own labels, the
    /// grade where anybody gave one, and which source each period came from.
    public let sickDays: [SickDay]
    /// **Every day the reader answered the app's illness guess about** —
    /// backlog `B11-2`. The guess, the answer and the numbers behind the guess,
    /// kept apart so accuracy stays measurable off the phone as well as on it.
    public let illnessAnswers: [IllnessAnswer]
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

    /// **Every tag the reader has applied, with what the app decided it was
    /// about and how it decided.**
    ///
    /// `HealthTag` carries its `TagApplicabilityMapping` whole — applicability,
    /// method, confidence and the rationale in words — and that is deliberate
    /// rather than verbose. The applicability is an **inference**, and an
    /// inference exported without the method that produced it is indistinguishable
    /// in the file from a fact somebody measured. A pooled dataset that cannot
    /// tell "Oura's own type code said alcohol" from "an on-device language model
    /// guessed" cannot honestly use either.
    ///
    /// ⚠️ **These are the reader's own words, and they export.** The same call
    /// as `Holiday.label` — free text the reader typed about themselves is
    /// theirs and belongs in their file — and the opposite of
    /// `exportKey(for: .calendarEvents)`, which emits nothing because an event
    /// title describes *other people* as much as the reader. A tag's free-form
    /// *comment* is not here at all: `TagPromotion` never reads it.
    public let tags: [HealthTag]

    /// **Every half-hour the app asked about, what it guessed, and what the
    /// reader said it was** — backlog P32.
    ///
    /// See `exportKey(for: .flaggedEvents)` for the full list of what this
    /// deliberately cannot carry. The short version: no coordinate, no note, no
    /// timestamp finer than the day.
    public let flaggedEvents: [FlaggedEventExport]

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

    /// **Every blood-test analyte the reader has given the app** — backlog `Q7`.
    ///
    /// The whole `LabResult`, including its `evidence`, and that is the point
    /// rather than verbosity: a value read by OCR and a value typed by a person
    /// are different kinds of fact, and a pooled dataset that cannot tell them
    /// apart cannot honestly use either. `LabResult.confidence` and the checks
    /// behind it travel with the number.
    ///
    /// ⚠️ **The two lipids are also in `profile`, as grounding facts, and that
    /// duplication is deliberate** — the risk models read one current value each
    /// and this key is the history. Neither is derived from the other, so
    /// neither can be dropped without losing something.
    public let labResults: [LabResult]

    /// **Imported ECGs — the metadata, never the document.**
    ///
    /// ⚠️ The trace itself is a binary the app keeps on the phone;
    /// `attachmentFileName` names it and nothing here carries its bytes. That is
    /// not squeamishness about size: this file is JSON, and a base64 waveform
    /// image would make the reader's whole export unreadable in a text editor
    /// for the one key least likely to be read.
    ///
    /// ⚠️ **`printedFinding` is a quotation with an attribution attached**, and
    /// `findingProvenance` travels beside it for exactly the reason
    /// `HealthTag`'s mapping does: a classification exported without who made it
    /// is indistinguishable in the file from one this app produced — and this
    /// app produces none.
    public let ecgRecords: [ECGRecord]

    /// The four prose reports that used to be four separate files. See `Reports`.
    public let reports: Reports

    /// The correction record — guess, correction and artifact — shaped by the
    /// reader's sharing tier. See `Improvements`.
    public let improvements: Improvements

    public init(generatedAt: Date, build: String,
                samples: [HealthMetricSample], unmodelled: [RawMetricSample],
                substances: [SubstanceEvent],
                supplements: [SupplementEntry] = [],
                medication: Medication?,
                previousMedication: [Medication] = [],
                sideEffects: [SideEffect], symptoms: [SymptomEvent] = [],
                bodyScans: [BodyScan] = [],
                profile: UserHealthProfile,
                derivedScores: [DerivedScore],
                cycles: [CycleDay] = [],
                holidays: [Holiday] = [],
                calendarEvents: [CalendarEvent] = [],
                sickDays: [SickDay] = [],
                illnessAnswers: [IllnessAnswer] = [],
                generatedInsights: [DerivedSeries] = [],
                tags: [HealthTag] = [],
                flaggedEvents: [FlaggedEventExport] = [],
                connections: [Connection] = [],
                suggestionDismissals: [SuggestionDismissal] = [],
                feedback: [Feedback] = [],
                predictionOutcomes: [PredictionOutcome] = [],
                labResults: [LabResult] = [],
                ecgRecords: [ECGRecord] = [],
                reports: Reports = .empty,
                improvements: Improvements = .empty) {
        self.labResults = labResults
        self.ecgRecords = ecgRecords
        self.reports = reports
        self.improvements = improvements
        self.cycles = cycles
        self.holidays = holidays
        self.calendarEvents = calendarEvents
        self.sickDays = sickDays
        self.illnessAnswers = illnessAnswers
        self.generatedInsights = generatedInsights
        self.tags = tags
        self.flaggedEvents = flaggedEvents
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
        self.supplements = supplements
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
    ///
    /// ## Naming a key is not the same as having one (backlog D50)
    ///
    /// Three things are enforced when a new domain lands. It must render a
    /// Data-tab section (`DataTabView.section(for:)`, exhaustive — compiler). It
    /// must **name** an export key (this switch, exhaustive — compiler). And
    /// `scripts/verify.sh` checks the caller passes every argument
    /// `HealthDataExport.init` has.
    ///
    /// ⚠️ **The third only ever covered arguments that already existed.**
    /// Nothing required a domain to *have* one — so a domain could ship with a
    /// section (forced), a key (forced) and no data in the file (not forced),
    /// which is exactly what the reader reported on 2026-08-07: new data types
    /// *"aren't making it into exports by default"*.
    ///
    /// `verify.sh` now closes it: a domain's key must be an initialiser argument
    /// the caller passes, and **where two domains share a key, each must carry a
    /// declaration** —
    ///
    ///     // export-domain: <case> — <why it has no argument of its own>
    ///
    /// A shared key is the shape the hole takes: at most one of the domains
    /// sharing it owns the argument, and nothing else in the codebase can tell
    /// whether the others' data is really in the file. There are four below, and
    /// each is a real decision rather than an oversight — which is the point of
    /// writing them down where the switch is.
    public static func exportKey(for domain: DataDomain) -> String {
        switch domain {
        // Cuff readings are canonical samples like everything else measured.
        //
        // export-domain: metrics — owns "samples"; it is the canonical measured
        // series and `samples:` is passed by DataExportView.buildFullExport().
        // export-domain: bloodPressure — shares "samples" with `metrics` and has
        // no argument of its own on purpose: a cuff reading is a
        // `HealthMetricSample` like any other, filed under
        // `.bloodPressureSystolic` / `.bloodPressureDiastolic`. A separate key
        // would put the same readings in the file twice, and two copies of one
        // measurement is how an archive gets to disagree with itself.
        case .metrics, .bloodPressure: return "samples"
        case .substances: return "substances"
        // export-domain: supplements — owns "supplements"; `supplements:` is
        // passed by DataExportView.buildFullExport(). Its own key rather than a
        // share of "substances", because the shapes are nothing alike: a
        // substance event is one dated row and a supplement entry is a product
        // with a whole declared ingredient list hanging off it.
        //
        // ⚠️ **And it is the key most worth pooling, for the reason the reader
        // gave for wanting the export at all** (*"for things that have no
        // research, we are going to do the research and find the norms
        // ourselves"*). Nobody publishes what a real stack adds up to: the
        // Dietary Reference Intakes say what the limit is, and no dataset says
        // how often anyone crosses it or which combination of ordinary products
        // gets them there. That figure can only come from a pool of files like
        // this one.
        case .supplements: return "supplements"
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
        //
        // ⚠️ **That is now only three-quarters true, and the reader is the one
        // who changed it.** `R5`'s two-tier sharing, both tiers on by default,
        // defines **Full** as *"the artifact plus the before/after
        // categories"* — so the reader has already ruled that an event they
        // have *reviewed* may travel, words and all. Since B20/R4 those reach
        // the file through `improvements`, shaped by
        // `SharingTier.shape(kind:changes:fields:)`: the artifact's title,
        // place and attendee count under Full, and nothing but the guess → truth
        // move under Metadata only.
        //
        // ✅ **And the reader ruled on the last quarter, 2026-08-07:** *"if they
        // have full sharing your corrections enabled, it will be enabled for
        // that future feature (server) and the export."*
        //
        // So the **un-reviewed** calendar — every event they have never looked
        // at, which is most of them — travels **at `.full` and at no other
        // tier**. Not at `.metadataOnly`, not with sharing off. The gate is the
        // same switch that already governs corrections, which is the point: the
        // reader made one choice and it means one thing everywhere.
        //
        // ⚠️ **The risk assessment above is unchanged and still true** — titles
        // and locations remain the most identifying strings this app holds. What
        // changed is **who decides**. An unconditional exclusion was the app
        // overruling a choice it had just handed the reader in `R5`.
        //
        // export-domain: calendarEvents — owns "calendarEvents", conditional on
        // the sharing tier. **The only tier-conditional key in this switch**, so
        // `DataExportView` passes `[]` for it below `.full` rather than omitting
        // the argument — an absent key and a withheld one must not look alike.
        case .calendarEvents: return "calendarEvents"
        case .cycles: return "cycles"
        // Reader-entered (and date-only detected) leave genuinely exports —
        // unlike the events above, because the ledger holds no titles.
        case .holidays: return "holidays"
        // export-domain: sickDays — owns "sickDays"; `sickDays:` is passed by
        // DataExportView.buildFullExport(). Same reasoning as `holidays`, and
        // the same thing makes it possible: the ledger holds dates and grades,
        // never an event's title. §B11-4.
        case .sickDays: return "sickDays"
        // export-domain: unmodelled — owns "unmodelled"; `unmodelled:` is passed
        // by DataExportView.buildFullExport() and carries the whole raw
        // catalogue. It shares the key only because `calendarEvents` points at
        // it while emitting nothing.
        // export-domain: labResults — owns "labResults"; `labResults:` is passed
        // by DataExportView.buildFullExport(). Backlog Q7.
        case .labResults: return "labResults"
        // export-domain: ecgRecords — owns "ecgRecords"; `ecgRecords:` is passed
        // by DataExportView.buildFullExport(). Metadata only; the document
        // itself stays on the phone and is named rather than carried. Backlog I7.
        case .ecgRecords: return "ecgRecords"
        case .unmodelled: return "unmodelled"
        // ⚠️ **Its own key, not `unmodelled`, even though the tags are promoted
        // *out of* `unmodelled` and their raw rows are still in it.** Same call
        // as `symptoms`, and the same reason: promotion reads rather than moves,
        // so the raw copy is the safety net and the promoted copy is the one
        // carrying the applicability the app worked out. A pool reading only
        // `unmodelled` would get `oura.enhanced_tag.tag_type_code` strings and
        // none of the classification, which is the part with no published norm
        // and therefore the part worth pooling.
        case .tags: return "tags"
        // export-domain: flaggedEvents — owns "flaggedEvents"; passed by
        // DataExportView.buildFullExport().
        //
        // ⚠️ **The measurement travels; the place and the reader's own words do
        // not.** `FlaggedEventExport` has no field a coordinate or a note could
        // occupy, which is the same construction that lets `Connection` exist
        // without a credential — a rule enforced by the absence of a slot is
        // enforced, and one enforced by remembering to blank a field is not.
        //
        // What is in it is exactly what a pooled dataset would need to build the
        // norm this app has no published basis for: how far above a personal
        // reference an unexplained elevation ran, how long it lasted, what the
        // app guessed and what the person said it was. **That last pair is the
        // whole point** — there is no published accuracy figure for guessing an
        // activity from a heart-rate trace, because nobody has a labelled set,
        // and this is one being built honestly.
        //
        // What is left out, and why each:
        // - **the coordinate** — `PlaceContext` explains at length; a coordinate
        //   history re-identifies from four points and no coarsening survives
        //   that. Only `placeFamiliarity`, one of four words, travels.
        // - **the reader's note** — free text about what somebody was doing
        //   during a flagged half-hour. Unlike a holiday label it routinely
        //   describes *other people*, which is the same test
        //   `exportKey(for: .calendarEvents)` applies to an event title.
        // - **the exact timestamps** — `day` only. A start time to the second,
        //   beside a duration and a familiarity, is a behavioural fingerprint;
        //   the day is what a norm would ever be aggregated over anyway.
        case .flaggedEvents: return "flaggedEvents"
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
    ///
    /// The last two are B20's and R4's: the four folded-in prose reports, and
    /// the correction record. Neither is a `DataDomain` either — the Data tab
    /// shows no report and no correction ledger — so the domain switch cannot
    /// speak for them and this list is what holds them in the file.
    public static let additionalKeys = ["profile", "derivedScores",
                                        "schemaVersion", "generatedAt", "build",
                                        "connections", "suggestionDismissals",
                                        "feedback", "predictionOutcomes",
                                        "reports", "improvements"]

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
        case supplements
        case medication, previousMedication, sideEffects, symptoms
        case bodyScans, profile, derivedScores, cycles, holidays, sickDays
        case illnessAnswers
        case calendarEvents
        case generatedInsights, tags, flaggedEvents
        case connections, suggestionDismissals, feedback, predictionOutcomes
        case labResults, ecgRecords
        case reports, improvements
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
        try c.encode(supplements, forKey: .supplements)
        try c.encode(medication, forKey: .medication)
        try c.encode(previousMedication, forKey: .previousMedication)
        try c.encode(sideEffects, forKey: .sideEffects)
        try c.encode(symptoms, forKey: .symptoms)
        try c.encode(bodyScans, forKey: .bodyScans)
        try c.encode(profile, forKey: .profile)
        try c.encode(derivedScores, forKey: .derivedScores)
        try c.encode(cycles, forKey: .cycles)
        try c.encode(holidays, forKey: .holidays)
        try c.encode(sickDays, forKey: .sickDays)
        try c.encode(illnessAnswers, forKey: .illnessAnswers)
        // ⚠️ Always written, even when empty — an empty array reads as "the
        // reader has full sharing turned off", where an absent key would read as
        // "this app does not export calendars". Different sentences, and
        // `testAnEmptyBundleStillCarriesEveryKey` is what holds the difference.
        try c.encode(calendarEvents, forKey: .calendarEvents)
        try c.encode(generatedInsights, forKey: .generatedInsights)
        try c.encode(tags, forKey: .tags)
        try c.encode(flaggedEvents, forKey: .flaggedEvents)
        try c.encode(connections, forKey: .connections)
        try c.encode(suggestionDismissals, forKey: .suggestionDismissals)
        try c.encode(feedback, forKey: .feedback)
        try c.encode(predictionOutcomes, forKey: .predictionOutcomes)
        try c.encode(labResults, forKey: .labResults)
        try c.encode(ecgRecords, forKey: .ecgRecords)
        try c.encode(reports, forKey: .reports)
        try c.encode(improvements, forKey: .improvements)
    }
}
