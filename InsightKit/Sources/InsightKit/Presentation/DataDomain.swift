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
    /// Everything imported but not yet modelled, from the raw catalogue.
    case unmodelled

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
        case .unmodelled: return "Other data"
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
        case .cycles:
            return "Every bleeding day you have logged or synced, and the cycles they form — with the range your cycles actually fall in rather than one average."
        case .unmodelled:
            return "Imported and catalogued, but no card reads it yet."
        }
    }
}
