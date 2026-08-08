import Foundation

/// A symptom the reader has, graded by how strongly.
///
/// ## Why this is a domain rather than a metric
///
/// A `MetricType` is one measured series with a unit, a plausible range and a
/// baseline. A symptom is none of those: it is an **event** — it happened, on a
/// day, at a strength somebody chose — and it is absent far more often than it
/// is present, which is not what "no reading" means for a series. Modelled as a
/// metric, a week with no headache would be a week of missing data rather than
/// a week of not having one, and every baseline built on it would be wrong.
///
/// ## Why now
///
/// **The data has been arriving for months and nothing read it.**
/// `HealthKitService.otherCategoryIdentifiers` already pulls fourteen of Apple's
/// symptom categories into the raw catalogue, where they sit unmodelled — the
/// state `progress.md` describes as "already being scraped into the raw pile and
/// read by nothing". Promoting them costs no new permission, no new connector
/// and no new capture: the reader's phone has been collecting this all along.
///
/// It is also the prerequisite for the symptom radar. That card grades *itself*
/// against the reader's own symptom tags, and the best published validation of
/// the approach is 43% sensitivity at 95% specificity — so it can only be built
/// once there is something to grade against.
public enum SymptomType: String, Sendable, CaseIterable, Codable, Identifiable {
    case nausea
    case headache
    case fatigue
    case dizziness
    case fever
    case coughing
    case shortnessOfBreath
    case chestTightnessOrPain
    case abdominalCramps
    case bloating
    case heartburn
    case sleepChanges
    case moodChanges
    case hotFlashes
    // Added 2026-08-04: the two most characteristic GLP-1 GI reactions were
    // unrepresentable, so the radar's dose downgrade could never fire for the
    // classic dose reaction — a reader who vomited for two days after a step-up
    // got the full illness lead instead of the neutral one naming the dose.
    case vomiting
    case diarrhea
    // Added 2026-08-08: **the app's own picker was manufacturing names it could
    // not read.** `SideEffectEntrySheet` offered "Constipation",
    // "Injection-site pain" and "Loss of appetite"; none had a case here and
    // none had a synonym, so every time the reader chose one — daily, against a
    // GLP-1 — the record went straight into
    // `SymptomReconciliation.unmatchedNames`. Not a vocabulary gap between two
    // products: the app proposed the word and then could not read it back.
    // `commonlyLogged` exists so that cannot recur.
    case constipation
    /// Apple's category is **bidirectional** — an appetite *change*, either way
    /// — and this is that category, not a narrower "loss of appetite". The
    /// picker's old wording still resolves through `synonyms`; only
    /// decrease-direction words are listed there, because that is the only
    /// direction a reader on a GLP-1 logs and an increase mapping into the same
    /// case would let the reconciliation call two opposite records agreement.
    case appetiteChanges
    /// **The one symptom here Apple has no category for.** It can only ever
    /// arrive by hand, so the string `healthKitIdentifier` derives for it simply
    /// never matches an incoming sample — the harmless half of that derivation,
    /// and the identifier stays unique so promotion is unaffected.
    ///
    /// It earns a case anyway rather than staying free text: it is one of the
    /// things a reader on an injectable logs most, and free text cannot
    /// reconcile, cannot cluster, and cannot be counted.
    case injectionSitePain

    public var id: String { rawValue }

    /// Apple's identifier for this symptom, which is how it arrives.
    public var healthKitIdentifier: String {
        "HKCategoryTypeIdentifier" + rawValue.prefix(1).uppercased() + rawValue.dropFirst()
    }

    /// Every symptom keyed by the identifier it arrives under, so promotion from
    /// the raw catalogue is a dictionary lookup rather than a switch somebody
    /// has to keep in step.
    public static let byHealthKitIdentifier: [String: SymptomType] = Dictionary(
        uniqueKeysWithValues: allCases.map { ($0.healthKitIdentifier, $0) })

    /// **The side effects the reader is offered by name**, in the order the
    /// picker has always shown them.
    ///
    /// ⚠️ **This is public because a hardcoded UI list is how three
    /// unreconcilable names got shipped.** `SideEffectEntrySheet` held its
    /// choices as a `[String]`, and three of them had no case in this enum and
    /// no entry in `synonyms` — so the app offered the reader a word, wrote it
    /// down when they picked it, and then reported it back through
    /// `SymptomReconciliation.unmatchedNames` as a vocabulary it could not
    /// read. A UI list of a domain enum's members is not a shortcut; it is a
    /// second vocabulary, and the second one drifts silently because nothing
    /// compiles against it.
    ///
    /// Generated from here, the drift is a compile error instead: a new picker
    /// entry is a new case, and a new case does not build until `title`, both
    /// clusters, `gradesTheRadar` and `IllnessKind.kind(for:)` have all answered
    /// for it. The strings come from `title`, so there is one spelling.
    ///
    /// **The free-text escape is deliberately not in this list and must stay in
    /// the UI.** "Something else" is a sentinel, not a symptom, and
    /// `matching(name:)` returns nil for it on purpose. A fixed list of symptoms
    /// is a list of the ones somebody else thought of — the reconciliation is
    /// built to *report* the words it cannot read rather than prevent them.
    public static let commonlyLogged: [SymptomType] = [
        .nausea, .fatigue, .constipation, .diarrhea, .heartburn,
        .headache, .injectionSitePain, .appetiteChanges, .vomiting,
    ]

    /// **The words a hand-typed side effect arrives under**, mapped to the
    /// canonical symptom — backlog `R28`.
    ///
    /// A tracker's side-effect log is free text somebody chose from *its*
    /// picker ("Diarrhea", "Stomach pain", "Tiredness"), and Apple's categories
    /// are a fixed fourteen. Reconciling the two needs a join, and there is no
    /// identifier to join on — so this is the join, written out.
    ///
    /// ⚠️ **Only exact synonyms belong here.** The temptation is to be generous
    /// — "stomach" → nausea, "pain" → chest tightness — and generosity here
    /// manufactures agreement between two records that never agreed. Anything
    /// this cannot name confidently stays unmatched, and the reconciliation says
    /// so out loud rather than guessing; an unmatched hand entry is a finding
    /// about vocabulary, not a failure.
    static let synonyms: [String: SymptomType] = [
        "nausea": .nausea, "nauseous": .nausea, "sick to stomach": .nausea,
        "headache": .headache, "headaches": .headache, "migraine": .headache,
        "fatigue": .fatigue, "tiredness": .fatigue, "tired": .fatigue,
        "exhaustion": .fatigue, "low energy": .fatigue,
        "dizziness": .dizziness, "dizzy": .dizziness, "lightheaded": .dizziness,
        "light headed": .dizziness, "vertigo": .dizziness,
        "fever": .fever, "temperature": .fever, "chills": .fever,
        "cough": .coughing, "coughing": .coughing,
        "shortness of breath": .shortnessOfBreath, "breathlessness": .shortnessOfBreath,
        "short of breath": .shortnessOfBreath,
        "chest pain": .chestTightnessOrPain, "chest tightness": .chestTightnessOrPain,
        "abdominal cramps": .abdominalCramps, "cramps": .abdominalCramps,
        "stomach cramps": .abdominalCramps, "abdominal pain": .abdominalCramps,
        "stomach pain": .abdominalCramps,
        "bloating": .bloating, "bloated": .bloating, "gas": .bloating,
        "heartburn": .heartburn, "acid reflux": .heartburn, "reflux": .heartburn,
        "indigestion": .heartburn,
        "insomnia": .sleepChanges, "poor sleep": .sleepChanges,
        "sleep changes": .sleepChanges, "trouble sleeping": .sleepChanges,
        "mood changes": .moodChanges, "low mood": .moodChanges,
        "irritability": .moodChanges,
        "hot flashes": .hotFlashes, "hot flushes": .hotFlashes,
        "night sweats": .hotFlashes,
        // "Sick" is deliberately absent. In British English it means vomiting
        // and in American English it means ill, and this app's reader writes
        // both — a synonym that resolves one way half the time is worse than no
        // synonym, because the reconciliation would then report agreement it
        // invented. It stays unmatched and visible.
        "vomiting": .vomiting, "throwing up": .vomiting,
        "diarrhea": .diarrhea, "diarrhoea": .diarrhea, "loose stools": .diarrhea,
        "constipation": .constipation, "constipated": .constipation,
        // Keys are looked up after `matching(name:)` lowercases and turns "-"
        // into " ", so "injection site pain" is what the picker's
        // "Injection-site pain" actually arrives as. A key spelled with the
        // hyphen would be unreachable — dead weight that reads as coverage.
        //
        // "Injection site reaction" is deliberately absent. A reaction is
        // redness or itching as readily as pain, and it is a guess at another
        // product's wording rather than a word this app has seen. It stays
        // unmatched and visible, which is how the next session learns it is
        // real — that feedback loop is the whole design of `unmatchedNames`.
        "injection site pain": .injectionSitePain,
        "injection site soreness": .injectionSitePain,
        "sore injection site": .injectionSitePain,
        // Decrease-direction only, on purpose — see the case's own note.
        "appetite changes": .appetiteChanges, "loss of appetite": .appetiteChanges,
        "appetite loss": .appetiteChanges, "reduced appetite": .appetiteChanges,
        "no appetite": .appetiteChanges,
    ]

    /// The canonical symptom a free-text name refers to, or nil where the app
    /// cannot say.
    ///
    /// Case- and punctuation-insensitive, and it also accepts the app's own
    /// display titles, so a name that came *out* of this app round-trips.
    public static func matching(name: String) -> SymptomType? {
        let key = name.lowercased()
            .replacingOccurrences(of: "-", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let direct = synonyms[key] { return direct }
        return allCases.first { $0.title.lowercased() == key }
    }

    public var title: String {
        switch self {
        case .nausea: return "Nausea"
        case .headache: return "Headache"
        case .fatigue: return "Fatigue"
        case .dizziness: return "Dizziness"
        case .fever: return "Fever"
        case .coughing: return "Coughing"
        case .shortnessOfBreath: return "Shortness of breath"
        case .chestTightnessOrPain: return "Chest tightness or pain"
        case .abdominalCramps: return "Abdominal cramps"
        case .bloating: return "Bloating"
        case .heartburn: return "Heartburn"
        case .sleepChanges: return "Sleep changes"
        case .moodChanges: return "Mood changes"
        case .hotFlashes: return "Hot flushes"
        case .vomiting: return "Vomiting"
        // The raw value keeps Apple's US spelling — it derives the HealthKit
        // identifier — while the title follows this app's British copy, the
        // same split `hotFlashes` / "Hot flushes" already makes.
        case .diarrhea: return "Diarrhoea"
        case .constipation: return "Constipation"
        case .injectionSitePain: return "Injection-site pain"
        // Not "Loss of appetite", which is what the picker used to say. This is
        // Apple's bidirectional category and naming a direction the record does
        // not carry would put a claim in the reader's mouth; the old wording
        // still resolves through `synonyms`, so nothing they logged is lost.
        case .appetiteChanges: return "Appetite changes"
        }
    }

    /// Whether this symptom is a recognised GLP-1 adverse effect.
    ///
    /// **Load-bearing for the symptom radar, which must never call a dose
    /// reaction an infection.** The gastrointestinal cluster is the commonest
    /// reason a reader on a GLP-1 feels unwell in the days after a dose, and a
    /// card that reads that as an early illness signal would be alarming
    /// somebody about their own prescription working as labelled.
    ///
    /// This flags a symptom as *explicable* by medication, never as *caused* by
    /// it — the reader can have a stomach bug while on tirzepatide. What it
    /// buys is the ability to name the likelier explanation alongside the
    /// finding rather than instead of it.
    ///
    /// Vomiting and diarrhoea sit here rather than in `isInfectionLike` even
    /// though they are also gastroenteritis hallmarks: the clusters must stay
    /// disjoint (`SymptomTests.testTheTwoClustersDoNotOverlap`), and the
    /// dose-window copy already carries the ambiguity out loud — "a stomach
    /// bug can look identical, so if this worsens or lingers, believe your
    /// body over this card."
    public var isCommonGLP1Effect: Bool {
        switch self {
        case .nausea, .abdominalCramps, .bloating, .heartburn, .fatigue,
             .vomiting, .diarrhea,
             // Constipation is the slowed-gastric-emptying half of the same
             // mechanism as the diarrhoea already here; appetite suppression is
             // the drug *working*, which this property is worded for — it flags
             // a symptom as explicable by medication, never as an adverse
             // event. Injection-site pain is the strongest member of the set:
             // it is explained by the injection by definition.
             //
             // Load-bearing beyond the copy. `HealthWatch`'s `isDoseExplained`
             // only discounts a day when *every* tag on it is one of these, so
             // a day carrying just these three inside a dose window can no
             // longer confirm an illness episode.
             .constipation, .appetiteChanges, .injectionSitePain: return true
        case .headache, .dizziness, .fever, .coughing, .shortnessOfBreath,
             .chestTightnessOrPain, .sleepChanges, .moodChanges, .hotFlashes: return false
        }
    }

    /// Symptoms that an infection typically presents with.
    ///
    /// Deliberately narrow. Fatigue is the commonest illness symptom there is
    /// and is *not* here, because it is also the commonest everything-else
    /// symptom — a signal that fires on every bad night is not a signal.
    public var isInfectionLike: Bool {
        switch self {
        case .fever, .coughing, .shortnessOfBreath: return true
        case .nausea, .headache, .fatigue, .dizziness, .chestTightnessOrPain,
             .abdominalCramps, .bloating, .heartburn, .sleepChanges,
             .moodChanges, .hotFlashes, .vomiting, .diarrhea,
             // Losing your appetite is a real illness symptom and is still
             // false here, for the reason fatigue is: on a reader whose
             // prescription suppresses appetite it would fire most weeks, and
             // this drives the radar's *miss* clustering — a signal that fires
             // on every ordinary week would make a miss of every ordinary week.
             // (The disjointness rule forces it anyway.) Injection-site pain is
             // local to a needle, never systemic; it would make a miss of every
             // dose.
             .constipation, .appetiteChanges, .injectionSitePain: return false
        }
    }

    /// Whether this tag may **grade the symptom radar** — in either direction.
    ///
    /// ⚠️ **The ledger was one-directional and would have started lying the day
    /// the reader logged a mood.** The confirm side counted any tag that was not
    /// chronic and not dose-explained; the miss side clusters only
    /// `isInfectionLike` days. `moodChanges` is neither chronic nor a known
    /// GLP-1 effect, so it could **only ever raise the hit rate and never the
    /// miss rate** — on the one number this app prints back about its own
    /// accuracy.
    ///
    /// It is not hypothetical. `HealthKitService` already requests
    /// `HKCategoryTypeIdentifierMoodChanges`, `SymptomType.moodChanges` exists,
    /// and `SymptomPromotion.events` is a bare identifier lookup with no mood
    /// exclusion — so a single State of Mind entry in Apple Health would have
    /// been promoted, landed in an episode's confirm window during any ordinary
    /// autonomic dip, and been scored as the illness radar having been *right*.
    /// There are zero mood rows in the reader's export today, which is exactly
    /// why this is cheap to fix now and expensive later.
    ///
    /// ⚠️ **The first attempt at this was `isInfectionLike`, and two shipped
    /// tests refuted it in one run.** A dose-window nausea with no dose, and an
    /// occasional hot flush, both legitimately confirm an episode today — they
    /// are plausible illness symptoms even though they are deliberately kept out
    /// of the *miss* clustering, where "a signal that fires on every bad night is
    /// not a signal" (see `isInfectionLike`). That asymmetry is a known,
    /// documented limitation of the ledger and it is not what is wrong here.
    ///
    /// What is wrong is narrower and is not fixable by symmetry: **a mood is not
    /// evidence of a bodily illness.** The radar reads four autonomic channels
    /// and claims to detect infection; a low mood during an autonomic dip is the
    /// one inference this app has written down that it must never make. So this
    /// excludes exactly that, and says why, rather than pretending the rest of
    /// the ledger is symmetric when it is not.
    public var gradesTheRadar: Bool {
        switch self {
        case .moodChanges: return false
        // ⚠️ **Settled 2026-08-09, against the rule this switch's own test
        // states**: *a detector may only be graded by evidence that could have
        // gone either way.* Injection-site pain cannot. It is
        // `isCommonGLP1Effect`, so `isDoseExplained` discounts it whenever a
        // dose covers the day — but where a dose record is *missing* (an
        // imported side-effect log with no matching dose) it confirms an
        // episode, while on the miss side it contributes nothing at all, being
        // `isInfectionLike == false`. One-directional: it can raise the radar's
        // hit rate and can never raise its miss rate.
        //
        // That is the same shape `moodChanges` is excluded for, on a stronger
        // argument than mood's — pain where a needle went is evidence about the
        // needle, not about the body being ill. Settled now rather than left
        // flagged because nothing has ever logged it: the case was added the
        // same day, so the ledger has no history to reinterpret. That is
        // exactly the "cheap now, expensive later" argument the mood exclusion
        // was made on, and waiting would have inverted it.
        case .injectionSitePain: return false
        case .fever, .coughing, .shortnessOfBreath, .nausea, .headache, .fatigue,
             .dizziness, .chestTightnessOrPain, .abdominalCramps, .bloating,
             .heartburn, .sleepChanges, .hotFlashes, .vomiting, .diarrhea,
             // Constipation and appetite changes stay `true`: both are ordinary
             // illness symptoms as well as dose reactions, so both are evidence
             // that could genuinely have gone either way.
             .constipation, .appetiteChanges:
            return true
        }
    }
}

/// How strongly, on Apple's own scale.
///
/// Kept as Apple grades it rather than rescaled to a 1–10 like the side-effect
/// log. Two reasons: the reader chose one of these words in the Health app and
/// a rescale would put a number in their mouth, and `notPresent` is a real,
/// useful answer — "I checked and I did not have this" is different from
/// silence, and only the reader can say it.
public enum SymptomSeverity: Int, Sendable, CaseIterable, Codable, Comparable {
    case unspecified = 0
    case notPresent = 1
    case mild = 2
    case moderate = 3
    case severe = 4

    public static func < (a: SymptomSeverity, b: SymptomSeverity) -> Bool {
        a.rawValue < b.rawValue
    }

    public var title: String {
        switch self {
        case .unspecified: return "Present"
        case .notPresent: return "Not present"
        case .mild: return "Mild"
        case .moderate: return "Moderate"
        case .severe: return "Severe"
        }
    }

    /// Whether the reader actually had it. `notPresent` is a recorded absence
    /// and must never be counted as an occurrence — which is the whole reason
    /// this is not a Bool.
    public var isPresent: Bool {
        switch self {
        case .notPresent: return false
        case .unspecified, .mild, .moderate, .severe: return true
        }
    }
}

/// One symptom, on one day, at one strength.
public struct SymptomEvent: Sendable, Codable, Hashable, Identifiable {
    public let id: UUID
    public let type: SymptomType
    public let severity: SymptomSeverity
    public let date: Date
    public let source: MetricSource

    public init(id: UUID = UUID(), type: SymptomType, severity: SymptomSeverity,
                date: Date, source: MetricSource) {
        self.id = id
        self.type = type
        self.severity = severity
        self.date = date
        self.source = source
    }
}

public enum SymptomPromotion {

    /// Lift symptom records out of the raw catalogue into first-class events.
    ///
    /// The raw catalogue is where anything imported-but-unmodelled lands, and
    /// these have been landing there since the category identifiers were added.
    /// Promotion reads rather than moves: the raw rows stay exactly where they
    /// are, so nothing that already displays them changes and a promotion bug
    /// cannot lose data.
    ///
    /// A row whose value is not one of Apple's severity constants is dropped
    /// rather than guessed at — `unspecified` already means "present, strength
    /// not stated", so there is no honest place to put an unrecognised number.
    public static func events(from raw: [RawMetricSample]) -> [SymptomEvent] {
        raw.compactMap { sample in
            guard let type = SymptomType.byHealthKitIdentifier[sample.identifier] else { return nil }
            guard let number = sample.numericValue,
                  let severity = SymptomSeverity(rawValue: Int(number)) else { return nil }
            return SymptomEvent(type: type, severity: severity,
                                date: sample.start, source: sample.source)
        }
        .sorted { $0.date > $1.date }
    }
}
