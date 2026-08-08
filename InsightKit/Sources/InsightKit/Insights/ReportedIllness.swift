import Foundation

/// **What the reader said about a day, on the same scale as what their body
/// did** — backlog `B11-8`.
///
/// The reader's instruction: *"Symptoms must go into this card's weightings —
/// as must calendar sick days and other derived symptom scores."*
///
/// ## Three records, one question
///
/// The symptom radar has always scored one thing: how far several overnight
/// signals have leaned together. This is the other half of the evidence, and
/// the app already holds it in three separate places:
///
/// | Source | Where it comes from | Why it is not the others |
/// | --- | --- | --- |
/// | **Symptom tags** | Apple Health (Browse ▸ Symptoms) | graded, dated, one row per symptom |
/// | **Recorded sick days** | `SickDayLedger` — calendar blocks and hand-entered spells | a whole day, said once, about being *ill* rather than about a symptom |
/// | **The side-effect log** | the medication tracker's own 1–10 entries | the reader's second symptom record, which the radar's ledger has never been able to read |
///
/// The third is not an afterthought. `SymptomReconciliation` exists because a
/// reader who types their symptoms into the medication tracker has a record the
/// radar has never seen, and `SickDaysSection` already says so in as many words:
/// *"a hit rate built from one of two logs has been quietly reading half the
/// evidence."* This is that half, wired.
///
/// ## ⚠️ Why this sits OUTSIDE the pooled statistic, and why that is not a
/// convenience
///
/// The obvious implementation is to add a "what you reported" channel to
/// `HealthWatchModel.watched` and let it vote with the rest. **It does not
/// work, and the arithmetic says so before any test does.** The pooled statistic
/// is a *weighted mean* of one-sided departures, standardised by its own null
/// spread — a design whose entire claim is that agreement between channels is
/// the finding and one loud channel is an ordinary Tuesday. Put a reported
/// channel in the pool at weight 1.2 beside four physiological channels sitting
/// at zero, and a reader who has just said they are severely ill produces a
/// concern of about 0.71 against a null mean of 0.40 and a null SD of about
/// 0.41 — an excess of **0.76**, comfortably inside "nothing stirring", scoring
/// in the high nineties. The mean divides the one voice that knows by the number
/// of voices that do not.
///
/// A second cost, just as disqualifying: every extra channel in the pool changes
/// the denominator on *every* day, including the days nothing was reported — so
/// the false-alarm budget the bands are stated in
/// (`HealthWatchModel.score(excess:)`, about two alarming mornings a year) would
/// have to be re-simulated and would no longer mean what the card says it means.
///
/// So the reported channel is a **third quantity joining at the verdict**,
/// exactly as the CUSUM accumulation already does, and for the same stated
/// reason: *arriving at each one's threshold means the same amount of concern*.
/// `SymptomRadarModel.verdict` takes whichever of the three is saying most. On a
/// day nothing was reported this returns zero and the card is arithmetically
/// unchanged, which is what keeps the physiological calibration intact.
///
/// ## ⚠️ What the evidence permits this to claim, and what it does not
///
/// `docs/illness-detection-evidence-2026-08-07.md`: prospective positive
/// predictive value for wearable illness detection is **4–12%**, and roughly
/// **two-thirds of genuine infections produce no clear physiological signal at
/// all**. The direct consequence for this file is the opposite of the one people
/// expect — it is not that self-report should be discounted, it is that **self-
/// report is the better evidence of the two**. A person saying they are ill is
/// the closest thing this app has to the reference standard those studies used;
/// the overnight signals are a proxy for it that misses most cases.
///
/// So the reported channel is allowed to reach the strong-signs edge on its own,
/// where none of the physiological channels may. What it is **never** allowed to
/// do is run the other way: nothing here ever *lowers* a score, because "I felt
/// fine" is not evidence a body was fine, and the same two-thirds figure is why.
public enum ReportedIllness {

    /// Which of the reader's three records spoke.
    ///
    /// Kept apart rather than pooled into one number because the weighting
    /// section shows one row per source and the reader asked for exactly that.
    /// They are also *different acts*: tagging a symptom in Health, marking a
    /// day ill, and typing a side effect beside a dose are three different
    /// statements a person makes for three different reasons.
    public enum Source: String, Sendable, Equatable, CaseIterable {
        /// Apple Health symptom tags.
        case symptomTags
        /// The merged `SickDayLedger` — calendar-detected and hand-entered.
        case recordedSickDay
        /// The medication tracker's own side-effect entries.
        case sideEffectLog

        public var displayName: String {
            switch self {
            case .symptomTags: return "Symptoms you tagged"
            case .recordedSickDay: return "Days you recorded ill"
            case .sideEffectLog: return "Your side-effect log"
            }
        }

        /// The derived-series key this source publishes, so a weighting row can
        /// link through to its history in the Data tab exactly as a metric row
        /// links to its chart (backlog `B11-9`).
        public var seriesKey: String {
            switch self {
            case .symptomTags: return "taggedSymptomLoad"
            case .recordedSickDay: return "recordedSickDayLoad"
            case .sideEffectLog: return "loggedEffectLoad"
            }
        }
    }

    // MARK: - The scale

    /// **Where a stated illness sits on the physiological statistic's scale.**
    ///
    /// Anchored to the model's own band edges rather than to numbers anybody
    /// liked the look of, so the two cannot drift apart when the bands move:
    ///
    /// | What was said | Excess | What the card then says |
    /// | --- | --- | --- |
    /// | ill, grade not stated | just past `someSignsExcess` (1.9) | some signs |
    /// | mild | the same | some signs |
    /// | moderate | midway | some signs, leaning |
    /// | severe | `strongSignsExcess` (3.3) | the strong-signs edge — score 50 |
    ///
    /// ⚠️ **"Just past", not "on".** See `pastTheEdge`: an edge belongs to the
    /// band above it, because every gate downstream is a `>=` on the score and
    /// the curve returns an anchor's score exactly. Anchoring *on* 1.9 put a
    /// stated illness on the quiet side of the quiet gate, which is how a day
    /// the reader had just marked as illness kept rendering as a green square.
    ///
    /// ⚠️ **The severe row is the edge on purpose and is left there.** A stated
    /// severe illness scores exactly 50 — the strong-signs anchor — and 50 is
    /// `.someSigns` by the gates in `SymptomRadarModel.verdict`, which is a
    /// design call somebody made deliberately and
    /// `SickDayReportTests.testASeverelyIllDayIsNotAQuietDay` pins as *"anchored
    /// on the strong-signs edge"*. Whether self-report should be allowed to
    /// paint the strong band outright is a real question and a separate one; it
    /// is not the reported bug, which was **green**.
    ///
    /// The claim being made is narrow and worth stating: **a day the reader said
    /// they were severely ill must not be a day this card calls quiet.** That is
    /// not a physiological finding and the copy never presents it as one — it is
    /// the card declining to contradict the only person who was there.
    public static func excess(for severity: CalendarEventClassification.SickSeverity?) -> Double {
        switch severity {
        case .some(.severe): return HealthWatchModel.strongSignsExcess
        case .some(.moderate):
            return (HealthWatchModel.someSignsExcess + HealthWatchModel.strongSignsExcess) / 2
        case .some(.mild), .some(.unstated), .none:
            return HealthWatchModel.someSignsExcess + pastTheEdge
        }
    }

    /// **How far past a band edge a stated illness is placed, in null SDs.**
    ///
    /// ⚠️ **An edge is not inside the band it opens, and that is what kept a
    /// recorded sick day green.** `HealthWatchModel.score(excess:)` is a
    /// `ScoreCurve` through published anchors and returns an anchor's score
    /// *exactly* at its input, so `someSignsExcess` scores exactly **85** — and
    /// the first gate in both `HealthWatchModel.Output.status` and
    /// `SymptomRadarModel.verdict` is `score >= 85 → quiet`. So the lowest
    /// reported anchor, which the table above says means *some signs*, landed on
    /// the **quiet** side of the boundary, and a reader marking a day as illness
    /// without grading it — which is what a calendar-detected sick day gets, and
    /// what the correction sheet offers first — produced a day the card called
    /// nothing stirring. Reported from the reader's own phone, 2026-08-09.
    ///
    /// A twentieth of a null SD, and both halves of that matter. Small enough
    /// not to be a different claim: it moves a stated mild illness from a score
    /// of 85.0 to about 84.6, which is inside the band and nowhere near the next
    /// edge. Large enough not to be an epsilon that a future re-anchoring of the
    /// curve rounds back onto the gate.
    ///
    /// ⚠️ **It is added, never hard-coded into a new number.** The anchors are
    /// still `HealthWatchModel`'s own, so moving a band still moves this — which
    /// was the right instinct in the original and is the only part of it that
    /// needed keeping.
    public static let pastTheEdge = 0.05

    /// The same, for Apple's four-value symptom grade.
    ///
    /// `notPresent` is **zero and not absent**: a reader who looked at a symptom
    /// and recorded that they did not have it has said something, and what they
    /// said was "no".
    ///
    /// The lowest grade carries `pastTheEdge` for the same reason the sick-day
    /// scale does, and carries it *here* rather than only there so a mild fever
    /// tag and a mild sick day cannot end up on opposite sides of the quiet
    /// gate. A non-specific symptom is still halved afterwards and so still
    /// cannot flag the card alone — `nonSpecificShare`'s guarantee is untouched.
    public static func excess(for severity: SymptomSeverity) -> Double {
        switch severity {
        case .notPresent: return 0
        case .unspecified, .mild: return HealthWatchModel.someSignsExcess + pastTheEdge
        case .moderate:
            return (HealthWatchModel.someSignsExcess + HealthWatchModel.strongSignsExcess) / 2
        case .severe: return HealthWatchModel.strongSignsExcess
        }
    }

    /// How much of that a **non-specific** symptom keeps.
    ///
    /// A fever, a cough or shortness of breath is `SymptomType.isInfectionLike`
    /// and speaks at full strength. A headache, fatigue, nausea, a mood change
    /// or a bad night follows a hangover, a hard session, a late night or a
    /// GLP-1 dose at least as readily as an infection — the evidence doc's own
    /// finding that what these systems detect is *non-specific systemic strain*
    /// applies just as much to what a person notices as to what a ring measures.
    ///
    /// **A half, and the consequence is deliberate**: at 0.5, even a *severe*
    /// non-specific symptom on its own reaches 1.65 — under `someSignsExcess`,
    /// so it can nudge the card but can never flag it alone. Something else has
    /// to agree with it, which is this card's founding argument applied to the
    /// reader's own words rather than only to their vitals.
    public static let nonSpecificShare = 0.5

    // MARK: - One day's answer

    /// What one source said about one day.
    public struct Component: Sendable, Equatable, Identifiable {
        public let source: Source
        /// Where this source sits on the physiological statistic's scale.
        public let excess: Double
        /// The reader's own words for the row — what was said, never a reading.
        public let detail: String
        public var id: String { source.rawValue }

        public init(source: Source, excess: Double, detail: String) {
            self.source = source
            self.excess = excess
            self.detail = detail
        }
    }

    /// Every source that spoke about a day, and the loudest of them.
    public struct Output: Sendable, Equatable {
        public let components: [Component]

        public init(components: [Component]) {
            self.components = components
        }

        public static let silent = Output(components: [])

        /// **The maximum, never the sum.**
        ///
        /// Three records of one illness are three views of one statement, not
        /// three independent findings. Adding them would let "I logged a sick
        /// day and tagged a cough" reach 6.6 on a scale whose strong band is
        /// 3.3 — arithmetic nobody can defend, and the OR-of-six mistake
        /// (`HealthWatchModel.concern`) in a new costume. The card takes the
        /// loudest thing the reader said and stops there.
        public var excess: Double { components.map(\.excess).max() ?? 0 }

        /// Whether the reader said anything at all about this day.
        public var isSpeaking: Bool { !components.isEmpty }

        public func component(_ source: Source) -> Component? {
            components.first { $0.source == source }
        }

        /// This source's excess, or zero where it said nothing — the value the
        /// derived series records, so a silent day is a real zero in the history
        /// rather than a gap.
        public func excess(_ source: Source) -> Double {
            component(source)?.excess ?? 0
        }
    }

    // MARK: - Reading the three records

    /// Everything the reader said about `day`.
    ///
    /// ⚠️ **Same-day only, deliberately.** The physiological half judges a
    /// three-day recent window against a lagged baseline precisely because a
    /// body's departure is slow; a statement is not. "I was ill on Tuesday" is
    /// about Tuesday, and smearing it across the week would put the reader's
    /// words on days they never said anything about — which is the one thing
    /// this channel exists to avoid doing.
    public static func evaluate(day: Date,
                                symptoms: [SymptomEvent],
                                sickDays: SickDayLedger,
                                sideEffects: [SymptomReconciliation.LoggedEffect] = [],
                                calendar: Calendar = .current) -> Output {
        let today = calendar.startOfDay(for: day)
        var components: [Component] = []

        // 1. Health symptom tags.
        let tags = symptoms.filter {
            calendar.isDate($0.date, inSameDayAs: today) && $0.severity.isPresent
        }
        if let worst = tags.map({ tagExcess($0) }).max(), worst > 0 {
            components.append(Component(
                source: .symptomTags, excess: worst,
                detail: phrase(tags: tags)))
        }

        // 2. The merged sick-day ledger.
        if let period = sickDays.periods.first(where: { $0.covers(today, calendar: calendar) }) {
            components.append(Component(
                source: .recordedSickDay,
                excess: excess(for: period.severity),
                detail: phrase(period: period, calendar: calendar)))
        }

        // 3. The medication tracker's own log — **only the symptoms Health does
        //    not already hold for that day.** `SymptomReconciliation` exists
        //    because these two records overlap; counting a name that appears in
        //    both would be one statement voting twice, which is the same
        //    double-count `collapsingDuplicates` refuses on the physiological
        //    side. A name Health has nothing for is the half nothing has read
        //    until now, and it is the whole reason this source is here.
        let taggedNames = Set(tags.map { $0.type.title.lowercased() })
        let unmatched = sideEffects.filter {
            calendar.isDate($0.date, inSameDayAs: today)
                && !taggedNames.contains($0.name.lowercased())
        }
        if let worst = unmatched.map({ effectExcess($0) }).max(), worst > 0 {
            components.append(Component(
                source: .sideEffectLog, excess: worst,
                detail: phrase(effects: unmatched)))
        }

        return Output(components: components)
    }

    /// One tag's excess: its grade, discounted unless it is infection-like.
    static func tagExcess(_ event: SymptomEvent) -> Double {
        excess(for: event.severity) * (event.type.isInfectionLike ? 1 : nonSpecificShare)
    }

    /// One hand-logged effect's excess.
    ///
    /// The tracker's 1–10 is read through `LoggedEffect.asGrade`, whose own doc
    /// comment states the coarseness (thirds, unvalidated). The name is matched
    /// to a `SymptomType` where one exists so the infection-like distinction can
    /// be drawn at all; **a name this app has no symptom for is discounted**,
    /// because "something the reader wrote that nothing here can classify" is
    /// exactly the case where assuming the worse reading would be inventing one.
    static func effectExcess(_ effect: SymptomReconciliation.LoggedEffect) -> Double {
        let matched = SymptomType.allCases.first {
            $0.title.lowercased() == effect.name.lowercased()
        }
        let specific = matched?.isInfectionLike ?? false
        return excess(for: effect.asGrade) * (specific ? 1 : nonSpecificShare)
    }

    // MARK: - Words

    /// ⚠️ Every sentence here reports **what was recorded**, never what it means.
    /// A row on the weighting section saying "you tagged a fever" is a fact; the
    /// same row saying "you have an infection" would be the card doing the one
    /// thing the evidence forbids.
    static func phrase(tags: [SymptomEvent]) -> String {
        let names = tags
            .sorted { $0.severity.rawValue > $1.severity.rawValue }
            .map { $0.type.title.lowercased() }
        let list = names.count == 1 ? names[0]
            : names.count == 2 ? "\(names[0]) and \(names[1])"
            : "\(names[0]), \(names[1]) and \(names.count - 2) more"
        let infectionLike = tags.contains { $0.type.isInfectionLike }
        // ⚠️ **The word "infection" is banned in this card's copy** — the ban is
        // older than this file (`SymptomRadarTests.testItNeverDiagnoses`) and it
        // is the right one: the literature it rests on is explicit that nothing
        // here detects a pathogen. Say what the tag *is not specific enough for*
        // without naming the thing the card may not claim.
        return "You tagged \(list) in Health"
            + (infectionLike ? "" : " — none of them specific to an illness")
    }

    static func phrase(period: SickDayLedger.Period, calendar: Calendar) -> String {
        let length = period.dayCount(calendar: calendar)
        let grade = period.severity.map { $0 == .unstated ? "no grade given" : $0.title.lowercased() }
            ?? "no grade given"
        let origin = period.source == .entered ? "you recorded" : "your calendar recorded"
        return "Inside a \(length)-day spell \(origin) as illness (\(grade))"
    }

    static func phrase(effects: [SymptomReconciliation.LoggedEffect]) -> String {
        let names = effects.sorted { $0.severity > $1.severity }.map { $0.name.lowercased() }
        let list = names.count == 1 ? names[0] : "\(names[0]) and \(names.count - 1) more"
        return "You logged \(list) beside your medication — not in Health, so nothing else here reads it"
    }
}
