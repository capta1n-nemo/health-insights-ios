import Foundation

/// **What the reader logged by hand, against what Health already knew** —
/// backlog `R28`.
///
/// Two records of the same thing exist and have never been put side by side:
/// side effects typed into a medication tracker and imported (`name`, a 1–10
/// severity, a date), and symptom tags from Apple Health
/// (`SymptomEvent`, one of Apple's four grades). They cover overlapping
/// vocabulary — nausea is in both — and the app has been reading only one of
/// them for anything that matters.
///
/// ## The shape is `BodyMeasurementReconciliation`'s, on purpose
///
/// Two sources measured the same thing; one of them is chosen; the others are
/// kept beside it; and where they disagree by more than the two methods' own
/// slop, **the app says so rather than hiding the loser**. Every one of those
/// sentences is true here, so the type reads the same way: an `Outcome` per
/// (day, symptom), a `note` when there is something to flag, and a `disputes`
/// helper for the card that only wants the disagreements.
///
/// ## What is different, and it is the interesting part
///
/// A body site has one true circumference. A symptom does not have one true
/// grade — **the two records were made by the same person about the same day for
/// different purposes**, one while thinking about a drug and one while thinking
/// about their health. So this never picks a winner and never overwrites: it
/// classifies the *relationship*, and the three relationships are the finding.
///
/// - `.both` — the reader wrote it down twice. The strongest record there is.
/// - `.handOnly` — typed into the tracker, never tagged in Health. Very common
///   and completely fine; it is also the reason the symptom radar's own ledger
///   under-counts, because the ledger reads Health alone.
/// - `.healthOnly` — tagged in Health, never typed. Usually because it was not a
///   drug reaction, which is exactly what makes it interesting.
///
/// ## ⚠️ The one inference this must never make
///
/// `SymptomType.isCommonGLP1Effect` and `.isInfectionLike` are disjoint by
/// construction (`SymptomTests.testTheTwoClustersDoNotOverlap`) and both are
/// surfaced here — but **a cluster is a vocabulary, not a diagnosis**. An
/// infection-like tag beside a dose is not evidence of an infection, and a GI
/// tag beside a dose is not proof the dose caused it. The rule this app already
/// wrote down applies unchanged: a symptom is flagged as *explicable* by
/// medication, never as *caused* by it.
public enum SymptomReconciliation {

    /// One hand-entered side effect, in the shape the medication log holds it.
    ///
    /// A tuple-shaped struct rather than the app's `SideEffectRecord`, which is
    /// a SwiftData `@Model` in the app target and cannot be reached from here —
    /// the same split `MedicationResponse.sideEffectTally` already makes.
    public struct LoggedEffect: Sendable, Equatable, Hashable {
        public let name: String
        /// The tracker's own 1–10, kept as recorded. A severity the reader chose
        /// means what they meant by it.
        public let severity: Int
        public let date: Date

        public init(name: String, severity: Int, date: Date) {
            self.name = name
            self.severity = severity
            self.date = date
        }

        /// The 1–10 read as one of Apple's four grades, so two scales can be
        /// compared at all.
        ///
        /// ⚠️ **A stated assumption and nothing more.** Thirds of a ten-point
        /// scale: 1–3 mild, 4–7 moderate, 8–10 severe. Nobody has validated that
        /// a 4 and a "moderate" mean the same thing, and this app has no way to;
        /// what the mapping buys is a comparison that can be *shown* with its
        /// own coarseness admitted, which is better than two columns of numbers
        /// in different units and a reader left to do it in their head.
        ///
        /// ⚠️ Written as `if`s rather than a `case 1...3:` range switch, and not
        /// for taste: `verify.sh`'s band-table lint matches
        /// `case <range>: return <numeric>` and its "numeric" pattern accepts a
        /// bare `.`, so `case 1...3: return .mild` reads to it as a scored band
        /// table. **This is not one** — nothing here feeds a card score, and
        /// there is no continuous quantity to put a curve through; four words
        /// are all the scale has. The false positive is real and worth fixing in
        /// the gate; sidestepping it is not the same as answering it.
        public var asGrade: SymptomSeverity {
            if severity < 1 { return .unspecified }
            if severity <= 3 { return .mild }
            if severity <= 7 { return .moderate }
            return .severe
        }
    }

    /// How the two records stand on one day, for one symptom.
    public enum Agreement: String, Sendable, Equatable {
        case both, handOnly, healthOnly
    }

    /// One day, one symptom, both records.
    public struct Outcome: Sendable, Equatable, Identifiable {
        public let day: Date
        public let symptom: SymptomType
        /// The hand-entered records for that day and symptom. Plural because a
        /// tracker permits several entries a day, and averaging them here would
        /// throw away the worst one.
        public let hand: [LoggedEffect]
        /// The Health tags for that day and symptom.
        public let health: [SymptomEvent]
        public let agreement: Agreement

        public var id: String { "\(day.timeIntervalSince1970)|\(symptom.rawValue)" }

        /// The worst grade each side recorded — the comparison that matters,
        /// since a day holding a 2 and a 9 was a bad day.
        public var handGrade: SymptomSeverity? { hand.map(\.asGrade).max() }
        public var healthGrade: SymptomSeverity? {
            health.filter { $0.severity.isPresent }.map(\.severity).max()
        }

        /// True where both sides recorded it and their grades are **more than
        /// one step apart**.
        ///
        /// One step is inside the slop of mapping a ten-point scale onto four
        /// words — a 3 and a "moderate" are the same day described twice — so
        /// flagging adjacent grades would flag almost everything and mean
        /// nothing. Two steps is a genuine disagreement: one record says mild
        /// and the other says severe.
        public var isDisputed: Bool {
            guard let a = handGrade, let b = healthGrade else { return false }
            return abs(a.rawValue - b.rawValue) > 1
        }

        /// One line for a card, or nil when there is nothing to say.
        ///
        /// Never a verdict on which record is right — the app does not know, and
        /// the reader is the only one who could.
        public var note: String? {
            switch agreement {
            case .both:
                guard isDisputed, let a = handGrade, let b = healthGrade else { return nil }
                return "You logged this as \(a.title.lowercased()) with your medication "
                    + "and tagged it \(b.title.lowercased()) in Health on the same day. "
                    + "Both are your own records — this app cannot tell which you meant."
            case .handOnly:
                return "Logged against your medication, never tagged in Health. "
                    + (symptom.isCommonGLP1Effect
                       ? "That is the usual place for this one, and nothing on this card reads it."
                       : "Anything grading the symptom radar reads Health only, so this one did not count.")
            case .healthOnly:
                return "Tagged in Health, never logged against your medication"
                    + (symptom.isInfectionLike
                       ? " — which is what you would expect for something this app does not treat as a dose reaction."
                       : ".")
            }
        }
    }

    /// Every day either record says something, newest first.
    ///
    /// Joined on **the calendar day and the canonical symptom**, which is the
    /// only join available: the two records share no identifier, and the times
    /// of day are not comparable — a tracker entry is typed whenever the reader
    /// remembers, a Health tag is stamped when they opened the app.
    ///
    /// A hand entry whose name `SymptomType.matching(name:)` cannot resolve is
    /// **not** in this list and is not silently dropped either — it comes back
    /// from `unmatchedNames(in:)`, because a vocabulary the app cannot read is a
    /// finding the reader should see.
    public static func reconcile(symptoms: [SymptomEvent],
                                 sideEffects: [LoggedEffect],
                                 calendar: Calendar = .current) -> [Outcome] {
        struct Key: Hashable {
            let day: Date
            let symptom: SymptomType
        }
        var hand: [Key: [LoggedEffect]] = [:]
        for effect in sideEffects {
            guard let type = SymptomType.matching(name: effect.name) else { continue }
            hand[Key(day: calendar.startOfDay(for: effect.date), symptom: type),
                 default: []].append(effect)
        }
        var health: [Key: [SymptomEvent]] = [:]
        // A recorded *absence* — "I checked and I did not have this" — is a real
        // answer and stays, because "you logged nausea and Health says you
        // explicitly did not have it" is the most interesting row this can
        // produce. `healthGrade` filters it back out of the comparison.
        for event in symptoms {
            health[Key(day: calendar.startOfDay(for: event.date), symptom: event.type),
                   default: []].append(event)
        }

        return Set(hand.keys).union(health.keys).map { key in
            let left = hand[key] ?? []
            let right = health[key] ?? []
            let agreement: Agreement
            if left.isEmpty {
                agreement = .healthOnly
            } else if right.isEmpty {
                agreement = .handOnly
            } else {
                agreement = .both
            }
            return Outcome(day: key.day, symptom: key.symptom, hand: left,
                           health: right, agreement: agreement)
        }
        .sorted {
            $0.day == $1.day ? $0.symptom.rawValue < $1.symptom.rawValue : $0.day > $1.day
        }
    }

    /// Only the days the two records genuinely disagree about.
    public static func disputes(symptoms: [SymptomEvent],
                                sideEffects: [LoggedEffect],
                                calendar: Calendar = .current) -> [Outcome] {
        reconcile(symptoms: symptoms, sideEffects: sideEffects, calendar: calendar)
            .filter(\.isDisputed)
    }

    /// Hand-entered names this app has no canonical symptom for, with how many
    /// entries carry each — worst-represented first.
    ///
    /// **Surfaced rather than swallowed.** Every one of these is a record the
    /// reader made that nothing in the app can read, and the fix is a synonym in
    /// `SymptomType.synonyms` — which cannot be written by somebody who never
    /// learns the word is there.
    public static func unmatchedNames(in sideEffects: [LoggedEffect]) -> [(name: String, count: Int)] {
        Dictionary(grouping: sideEffects.filter { SymptomType.matching(name: $0.name) == nil },
                   by: \.name)
            .map { (name: $0.key, count: $0.value.count) }
            .sorted { $0.count == $1.count ? $0.name < $1.name : $0.count > $1.count }
    }

    /// The counts a card's headline reads.
    public struct Summary: Sendable, Equatable {
        public let both: Int
        public let handOnly: Int
        public let healthOnly: Int
        public let disputed: Int
        public let unmatchedNames: Int

        /// What share of hand-entered days Health also knew about.
        ///
        /// Nil rather than zero when nothing was logged by hand: "you never
        /// tagged any of them" and "you never logged any" are opposite
        /// statements, and a 0% would say the first while meaning the second.
        public var alsoInHealth: Double? {
            let hand = both + handOnly
            return hand > 0 ? Double(both) / Double(hand) : nil
        }
    }

    public static func summary(symptoms: [SymptomEvent], sideEffects: [LoggedEffect],
                               calendar: Calendar = .current) -> Summary {
        let outcomes = reconcile(symptoms: symptoms, sideEffects: sideEffects,
                                 calendar: calendar)
        return Summary(
            both: outcomes.filter { $0.agreement == .both }.count,
            handOnly: outcomes.filter { $0.agreement == .handOnly }.count,
            healthOnly: outcomes.filter { $0.agreement == .healthOnly }.count,
            disputed: outcomes.filter(\.isDisputed).count,
            unmatchedNames: unmatchedNames(in: sideEffects).count)
    }
}
