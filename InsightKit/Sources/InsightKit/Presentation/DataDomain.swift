import Foundation

/// Every **kind** of data this app holds, whatever shape it takes.
///
/// ## Why this exists
///
/// The Data tab (called Vitals until 2026-08-02) is the app's answer to "what
/// does this thing actually know
/// about me". That claim only holds if it is complete — and it kept not being,
/// because each section was hand-written and staying complete depended on
/// somebody remembering. The substance log was reachable only from a toolbar
/// button for weeks; medication doses and imported side effects were added and
/// listed nowhere. The user's rule, 2026-08-02: **"whenever we add new data, it
/// must have an entry in that tab."**
///
/// A rule that depends on memory is not a rule, so this is the enforcement.
/// `DataTabView` switches **exhaustively** over `allCases`, so a new domain is a
/// compile error in the app target until it has a section. That is the same
/// mechanism `MetricType`'s eight switches and `ContributionRoute` already use,
/// and the reason it is an enum here rather than a list of section builders in
/// the view: the app target has no test target, so the compiler is the only
/// thing that can hold a rule there.
///
/// **Not the same as `MetricType`.** A metric is one measured series. A domain
/// is a *shape* of data — a dated log, a set of paired readings, a regimen with
/// a decay curve — and most of these are not series at all, which is exactly
/// why they kept falling out of a screen built around series.
public enum DataDomain: String, Sendable, CaseIterable, Identifiable {
    /// The canonical time-series vitals, in their category groups.
    case metrics
    /// Paired cuff readings, which are two numbers about one event.
    case bloodPressure
    /// The dated substance log.
    case substances
    /// A medication regimen and its doses.
    case medication
    /// Dated side-effect records — severity against a name.
    case sideEffects
    /// Symptoms the reader has tagged, graded by strength.
    ///
    /// Its own domain and not folded into `sideEffects`, which it visibly
    /// resembles. A side effect is a symptom **attributed to a medication**;
    /// this is the general case, and most of it arrives from Apple Health
    /// rather than from the reader typing it. Merging them would assert an
    /// attribution nobody made — and it is precisely the distinction the
    /// symptom radar rests on, since a dose reaction must never be reported as
    /// an infection.
    case symptoms
    /// Body measurements and the scans that produced them.
    ///
    /// Its own domain rather than folded into `metrics`, even though seven of
    /// the sites *are* metrics and chart there. A scan is a **shape**, not a
    /// series: it carries a date, a capture method, the conditions it was taken
    /// under, the sites it did and did not reach, and whether its raw data was
    /// kept — none of which a metric row can express, and all of which decides
    /// whether two of them can be compared.
    case bodyScans
    /// **What the app worked out**, as opposed to what it measured: each card's
    /// score, and the clinical estimates behind them — SCORE2, ASCVD, heart age.
    ///
    /// The user, 2026-08-02: *"I want any derived data being stored in the data
    /// tab, eg your ASCVD or SCORE2 etc scores."* They are the app's own output
    /// and the reader has never been able to see them as *data* — only as a
    /// number on a card, with no list, no history and no export row. Filed as
    /// their own domain rather than mixed in with `metrics` precisely because
    /// they are modelled: nothing on the phone sensed them.
    case derivedScores
    /// **The menstrual cycle log** — bleeding days, and the cycles they form.
    ///
    /// Its own domain and not a `MetricType`, for the reason the file header
    /// gives: a metric is one measured series, and a cycle is a *shape*. A
    /// bleeding day carries a flow level rather than a quantity, cycles are
    /// derived from the gaps between groups of them, and the interesting figure
    /// is a range of lengths — none of which a metric row can express.
    ///
    /// Backlog #31. See `CycleLog.swift` for who this is for and why the app
    /// stays single-user.
    case cycles
    /// **Calendar events**, grouped into the categories the reader named:
    /// Work, Personal, Travel.
    ///
    /// ⚠️ **One domain rather than three**, and the reader's own sentence is why:
    /// *"this will become a new data source, like Work Events, Personal Events,
    /// Travel Events"* — one source, with those categories. It is also the
    /// honest modelling: a domain is a *shape*, and a work event and a personal
    /// event are the same shape with a different classification. The Data tab
    /// renders them as three labelled groups, so they read as separate sources
    /// without pretending to be separate shapes.
    case calendarEvents
    /// **The reader's leave** — the holiday ledger (backlog B7 H5), merged from
    /// two sources: blocks the calendar classifier read as the reader's own
    /// leave, and holidays entered by hand. The reader's instruction verbatim:
    /// *"we should of course make sure it has a data tab, where I can track
    /// holidays."*
    ///
    /// Its own domain rather than a view of `calendarEvents`, because the shape
    /// is different: an event is one calendar row, a holiday is a dated *period*
    /// that may exist in no calendar at all — planned leave is entered before
    /// any block exists — and the deduplicated merge is precisely what neither
    /// source shows on its own.
    case holidays
    /// **Tags** — the words the reader put on a day, imported from Oura and
    /// from anything else with the same concept.
    ///
    /// The reader's brief, 2026-08-07: *"I want to take tags from Oura, and
    /// other sources that have similar concepts, and allow them to contribute
    /// to relevant cards… in the data section we use AI to map them to relevant
    /// high-level categories… eg if we see a sport related tag, it will live
    /// primarily in its tags section, and whatever it is (eg Kayaking) will have
    /// an 'applicability' of 'Activity & mobility'."*
    ///
    /// **"Lives primarily here" is the whole design.** A tag is not a symptom, a
    /// substance or an activity — it is a *word*, and which of those it is about
    /// is an inference the app makes and can get wrong. So the tag stays in one
    /// place, with its `TagApplicability` shown beside it and the method that
    /// decided it named on the row. Nothing is filed into another domain on the
    /// strength of a guess.
    ///
    /// Its own domain rather than folded into `symptoms` for the same reason
    /// `symptoms` is not folded into `sideEffects`: a tag reading "Sick" is the
    /// reader labelling a day, not a graded symptom record, and merging them
    /// would let self-reported free text into the symptom radar without anybody
    /// deciding it should be there.
    case tags
    /// Everything imported but not yet modelled, from the raw catalogue.
    case unmodelled
    /// **Every figure the app has derived, kept as a day-by-day series** — the
    /// reader's instruction, 2026-08-06: *"for any insight we derive, it is
    /// turned into a data source… and it has its own data source tracking in
    /// the data tab."*
    ///
    /// Distinct from `derivedScores`, and the difference is the shape: that
    /// domain is *today's* card scores and clinical estimates, one value each;
    /// this one is the **series** behind and beneath them — the fitness age
    /// every day for ninety days, each contributor's own 0–100, each departure
    /// in SD. One collapses to a number, the other trends.
    ///
    /// Rendered as one row opening a sub-page, at the reader's own request —
    /// the component tier alone is dozens of series and would flood the tab.
    case generatedInsights

    public var id: String { rawValue }

    /// The section heading the Data tab uses.
    public var title: String {
        switch self {
        case .metrics: return "Measurements"
        case .bloodPressure: return "Blood pressure"
        case .substances: return "Substances"
        case .medication: return "Medication"
        case .sideEffects: return "Side effects"
        case .symptoms: return "Symptoms"
        case .bodyScans: return "Body measurements"
        case .derivedScores: return "Scores & estimates"
        case .cycles: return "Cycles"
        case .calendarEvents: return "Calendar"
        case .holidays: return "Holidays"
        case .tags: return "Tags"
        case .unmodelled: return "Other data"
        case .generatedInsights: return "Generated insights"
        }
    }

    /// What the reader is looking at, for a section that needs saying.
    public var summary: String {
        switch self {
        case .metrics:
            return "Everything measured as a series, grouped by what it is about."
        case .bloodPressure:
            return "Your cuff readings, and the experimental estimate between them."
        case .substances:
            return "What you logged, and the cardiovascular load still carried."
        case .medication:
            return "Your regimen, the doses logged, and how much is still active."
        case .sideEffects:
            return "What you recorded feeling, and how strongly."
        case .symptoms:
            return "What you've tagged in Health, and how strongly — including the days you recorded not having something."
        case .bodyScans:
            return "Every measurement you've taken, how it was taken, and whether two of them can be compared."
        case .derivedScores:
            return "What the app worked out from everything above — each card's score, and the clinical estimates behind them."
        case .calendarEvents:
            return "Your events, sorted into work, personal and travel — what each one was, who decided that, and whether you have agreed with it."
        case .cycles:
            return "Every bleeding day you have logged or synced, and the cycles they form — with the range your cycles actually fall in rather than one average."
        case .holidays:
            return "Your leave, in one record — holidays found in your calendar and ones you entered yourself, deduplicated, with how long since you last had any."
        case .tags:
            return "The words you put on a day, grouped by what the app worked out each one is about — and how it worked that out, so you can disagree with it."
        case .unmodelled:
            return "Imported and catalogued, but no card reads it yet."
        case .generatedInsights:
            return "Every figure the app has worked out, kept day by day — the ages, the doses, and each signal's own score and departure behind every card. Computed, never measured."
        }
    }
}
