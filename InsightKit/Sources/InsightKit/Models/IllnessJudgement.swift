import Foundation

/// **The app's guess at what a day was, the reader's correction of it, and the
/// snapshot that makes the pair worth keeping** — backlog `B11-2`.
///
/// The reader's own words: *"an estimated sickness they can correct — type and
/// severity, similar to how you can correct a work or travel event (same
/// concept - then we can learn from it)."*
///
/// So this is `CalendarEventJudgement`'s shape, on purpose and almost line for
/// line: **guess, correction and artifact kept in three separate fields.**
/// Merged, a correction is indistinguishable from a good guess the next time
/// anything runs, so the app can never say how often it was right; kept apart,
/// every answered day is a labelled training pair. The reader asked for the same
/// concept and the same concept is what they get.
///
/// ## ⚠️ The estimate is a prompt, never a verdict — and this is not modesty
///
/// `docs/illness-detection-evidence-2026-08-07.md` is the authority and its
/// numbers are not close:
///
/// - prospective positive predictive value for this class of detector is
///   **4–12%** against a real reference test;
/// - roughly **two-thirds of genuine infections** produce no clear
///   physiological signal at all;
/// - in the only randomised trial, the physiological alerts produced **zero**
///   confirmed infections;
/// - and what these systems detect is **non-specific systemic strain** — the
///   identical signature precedes rheumatoid-arthritis flares by four weeks and
///   is reproduced by alcohol, hard training, poor sleep, travel and altitude.
///   No study in that literature detects lung pathology.
///
/// Three consequences are built into the types below rather than left to the
/// copy:
///
/// 1. **`IllnessKind` has no pathogen and no organ diagnosis.** Its cases are
///    patterns of *what was reported*, and `.notIll` is one of them.
/// 2. **An estimate with no reported symptom is `.unknown` and stays there.**
///    Physiology alone cannot name a kind of illness; a card that guessed one
///    from a raised resting heart rate would be inventing the specificity the
///    literature says does not exist.
/// 3. **`IllnessEstimate.uncertainty` is not optional and not empty.** Every
///    estimate carries its own out-loud statement of how little it knows, and
///    `IllnessJudgementTests` fails a build where one does not.
///
/// ## What it must never become
///
/// §B11's fake-sick-day inversion — flagging a recorded sick day the radar did
/// not corroborate — is **not** computable from these types, deliberately.
/// `wasCorrected` is a fact about the app's accuracy; nothing here answers "was
/// the reader telling the truth", because a quiet radar over a genuine illness
/// is the *ordinary* case and presenting it as a discrepancy would be this
/// app's worst possible failure mode.
public enum IllnessKind: String, Sendable, Equatable, Codable, CaseIterable, Identifiable {
    /// Nothing was wrong. A real answer and the most common one — a reader who
    /// says "that was a hangover, not an illness" has corrected the app about
    /// something, and an enum with no way to say so would only ever collect
    /// agreement.
    case notIll
    /// Cough, shortness of breath, sore throat — the cluster
    /// `SymptomType.isInfectionLike` names. **Not "a respiratory infection"**:
    /// it is a description of what was reported.
    case respiratory
    /// Nausea, vomiting, diarrhoea, cramps. Shares its vocabulary with the
    /// GLP-1 effect cluster on purpose — the card already refuses to let a dose
    /// explain an infection-like tag, and this keeps the two tellable apart.
    case gastrointestinal
    /// Fever, aches, the flattened feeling with no localising symptom. The
    /// honest label for most of what this card sees.
    case feverish
    /// Ill, and none of the above.
    case other
    /// **The app has not been told enough to say.** The default for every
    /// estimate made from physiology alone — see the type note.
    case unknown

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .notIll: return "Not ill"
        case .respiratory: return "Cough or breathing"
        case .gastrointestinal: return "Stomach or gut"
        case .feverish: return "Feverish or achy"
        case .other: return "Something else"
        case .unknown: return "Not enough to say"
        }
    }

    /// What the reader can pick from. `.unknown` is excluded: it is the app
    /// admitting it does not know, and a person answering about their own week
    /// is never in that position — they can always say `.notIll`.
    public static var correctable: [IllnessKind] {
        allCases.filter { $0 != .unknown }
    }

    /// The kind a symptom points at, where it points at one.
    ///
    /// ⚠️ Reads `SymptomType`'s existing clusters rather than inventing a third
    /// classification of the same seventeen symptoms. `isInfectionLike` and
    /// `isCommonGLP1Effect` are disjoint by construction and already tested
    /// (`SymptomTests.testTheTwoClustersDoNotOverlap`), so a symptom cannot land
    /// in two kinds and no new vocabulary has to be kept in step with them.
    public static func kind(for symptom: SymptomType) -> IllnessKind {
        switch symptom {
        case .fever: return .feverish
        case .coughing, .shortnessOfBreath: return .respiratory
        case .vomiting, .diarrhea, .nausea, .abdominalCramps: return .gastrointestinal
        case .headache, .fatigue, .dizziness, .chestTightnessOrPain, .bloating,
             .heartburn, .sleepChanges, .moodChanges, .hotFlashes,
             // Added 2026-08-09 with the three cases the app's own side-effect
             // picker was manufacturing and could not read back. ⚠️ **None of
             // them joins `.gastrointestinal`, and constipation is the one to
             // think about**: it is a GI symptom and it is not an infection
             // sign. On an injectable it is a dose reaction almost every time,
             // and filing it with vomiting and diarrhoea would let the radar
             // read a step-up as a stomach bug — the exact inversion
             // `SymptomType`'s two disjoint clusters exist to prevent.
             //
             // Injection-site pain cannot be an illness at all. It still
             // answers `.unknown` rather than `.notIll`, because `.notIll` is a
             // claim *about the reader* and one symptom is not evidence for it.
             .constipation, .appetiteChanges, .injectionSitePain:
            // Every one of these follows a late night, a hard session or a dose
            // as readily as an illness. Naming a kind from one of them alone
            // would be the specificity the evidence says nobody has.
            return .unknown
        }
    }
}

/// **What was wrong, and how badly** — the pair the reader corrects.
///
/// Severity is `CalendarEventClassification.SickSeverity` rather than a new
/// scale, and reusing it is the point: the reader already grades a sick day on
/// the Work impact review list, `SickDayLedger.Period` already carries that
/// grade, and a second four-value word scale would mean two answers to one
/// question that could disagree.
public struct IllnessAssessment: Sendable, Equatable, Codable, Hashable {
    public let kind: IllnessKind
    /// `nil` where nobody has said. **Different from `.unstated`**, which is
    /// somebody having looked and declined to grade it — the distinction
    /// `SickDayLedger.Period.severity` already keeps, kept here too so a merge
    /// between them cannot lose it.
    public let severity: CalendarEventClassification.SickSeverity?

    public init(kind: IllnessKind,
                severity: CalendarEventClassification.SickSeverity? = nil) {
        self.kind = kind
        self.severity = severity
    }

    public static let notIll = IllnessAssessment(kind: .notIll, severity: nil)

    /// One line for a row, without claiming more than was recorded.
    public var summary: String {
        guard kind != .notIll else { return "Not ill" }
        guard let severity, severity != .unstated else { return kind.title }
        return "\(kind.title) · \(severity.title.lowercased())"
    }
}

/// **The day as it stood when the app guessed** — the third layer, and the one
/// that turns a tally into a training set.
///
/// Same argument as `CalendarEventArtifact`: guess and correction alone let the
/// app say it was wrong fourteen times and nothing more, because whatever it was
/// wrong *about* is not in the record. This keeps the numbers the guess was made
/// from, so a later reader can ask what a wrong guess looked like.
///
/// ⚠️ **Numbers, never words.** No symptom names, no calendar titles, no free
/// text — `docs/privacy-and-ip.md`'s rule for this repo is the shape of a
/// finding and never the reading, and this struct is `Codable` because it
/// reaches the export.
public struct IllnessArtifact: Sendable, Equatable, Codable, Hashable {
    /// The physiological day's own excess, in null SDs.
    public let physiologicalExcess: Double
    /// The accumulation as it stood that evening.
    public let accumulatedStatistic: Double
    /// What the reader's own records said that day, on the same scale.
    public let reportedExcess: Double
    /// How many watched signals were leaning. Not which — the count is the
    /// finding this card makes (`agreement is the finding`), and a list of
    /// metric names in an exported artifact says more about the reader than the
    /// count does.
    public let leaningSignals: Int
    /// Whether the watch could judge the day at all.
    public let wasJudged: Bool

    public init(physiologicalExcess: Double, accumulatedStatistic: Double,
                reportedExcess: Double, leaningSignals: Int, wasJudged: Bool) {
        self.physiologicalExcess = physiologicalExcess
        self.accumulatedStatistic = accumulatedStatistic
        self.reportedExcess = reportedExcess
        self.leaningSignals = leaningSignals
        self.wasJudged = wasJudged
    }
}

/// **What the app thinks a day was, with its uncertainty attached to it.**
public struct IllnessEstimate: Sendable, Equatable, Codable, Hashable {
    public let assessment: IllnessAssessment
    /// The reasons, in the order they were weighed. Each line is something the
    /// app read, never a conclusion it drew.
    public let basis: [String]
    /// ⚠️ **Non-optional, and `IllnessJudgementTests` fails a build where any
    /// estimate ships an empty one.** The reader's standing instruction is the
    /// honest version, always; an estimate whose uncertainty is a view's
    /// responsibility is an estimate that will one day be rendered without it.
    public let uncertainty: String
    public let artifact: IllnessArtifact

    public init(assessment: IllnessAssessment, basis: [String],
                uncertainty: String, artifact: IllnessArtifact) {
        self.assessment = assessment
        self.basis = basis
        self.uncertainty = uncertainty
        self.artifact = artifact
    }
}

/// **One day: what the app guessed, what the reader said, and whether they have
/// looked.**
///
/// Structurally `CalendarEventJudgement`, keyed by day instead of by event id.
/// Shared field-for-field on purpose so one bug fixed in either is obviously the
/// same bug in the other; **not** the same type, because an event is a row in
/// somebody's calendar and a day is not, and merging them would put a nil
/// `eventID` on every illness answer.
public struct IllnessJudgement: Sendable, Equatable, Codable, Identifiable {
    /// Start of day, in the calendar the estimate was made in.
    public let day: Date
    /// What the app worked out, untouched by any correction.
    public let estimate: IllnessEstimate
    /// What the reader said, where they said anything.
    public let correction: IllnessAssessment?
    /// True where the reader looked and agreed. **Different from an absent
    /// correction** — "confirmed correct" is a label and "not yet looked at" is
    /// not, and treating them as one inflates any accuracy figure the app ever
    /// computes.
    public let isConfirmed: Bool
    public let reviewedAt: Date?

    public var id: Date { day }

    public init(day: Date, estimate: IllnessEstimate,
                correction: IllnessAssessment? = nil,
                isConfirmed: Bool = false, reviewedAt: Date? = nil) {
        self.day = day
        self.estimate = estimate
        self.correction = correction
        self.isConfirmed = isConfirmed
        self.reviewedAt = reviewedAt
    }

    /// What the rest of the app should use.
    public var effective: IllnessAssessment { correction ?? estimate.assessment }

    /// Whether the reader disagreed on either axis — the training signal.
    public var wasCorrected: Bool {
        guard let correction else { return false }
        return correction.kind != estimate.assessment.kind
            || correction.severity != estimate.assessment.severity
    }

    /// Whether anybody has answered at all.
    public var isAnswered: Bool { isConfirmed || correction != nil }

    /// Record the reader's answer. Returns a new value — the estimate and its
    /// artifact are never touched, which is the whole point of the split.
    public func reviewed(correction: IllnessAssessment?, confirmed: Bool,
                         at date: Date) -> IllnessJudgement {
        IllnessJudgement(day: day, estimate: estimate, correction: correction,
                         isConfirmed: confirmed, reviewedAt: date)
    }
}

/// **How often the app's guess matched the reader's answer.**
///
/// Deliberately counts only days the reader answered: an unanswered estimate is
/// not a silent success, and counting it as one is the arithmetic that turns an
/// accuracy figure into a compliment.
public struct IllnessAccuracy: Sendable, Equatable {
    public let answered: Int
    public let agreed: Int
    public let corrected: Int

    public init(answered: Int, agreed: Int, corrected: Int) {
        self.answered = answered
        self.agreed = agreed
        self.corrected = corrected
    }

    /// `nil` under a stated floor rather than a fraction of three days.
    ///
    /// Five, matching the bar `ModelAccuracy` and the radar's own ledger set:
    /// a hit rate over two answers is noise with a percent sign, and this card
    /// is the last place in the app that should print one.
    public static let minimumAnswers = 5

    public var rate: Double? {
        guard answered >= Self.minimumAnswers else { return nil }
        return Double(agreed) / Double(answered)
    }

    public static func over(_ judgements: [IllnessJudgement]) -> IllnessAccuracy {
        let answered = judgements.filter(\.isAnswered)
        let corrected = answered.filter(\.wasCorrected).count
        return IllnessAccuracy(answered: answered.count,
                               agreed: answered.count - corrected,
                               corrected: corrected)
    }
}
