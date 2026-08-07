import Foundation

/// **"Have you had a break, and how long ago"** — the one reading of
/// `HolidayLedger` that the scoring cards share. Backlog B7 H6.
///
/// The reader, 2026-08-06: *"knowing you have, or have not been on a holiday is
/// a very good data point."* Four cards now take it — Work impact, Travel drain,
/// Stress load and Mental health — and they take it *through this type* rather
/// than each reading `daysSinceLastLeave` and inventing its own curve, because
/// four independently invented curves is four different opinions about the same
/// fact appearing on four screens.
///
/// ## ⚠️ What this is allowed to claim, and what it is not
///
/// **It is a fact about a diary, not a measurement of a body.** Nothing here
/// senses anything. Two guards follow from that and neither is negotiable:
///
/// 1. **Nothing recorded scores nothing.** `score` is `nil` until a period of
///    leave has actually *happened*, and a card with a nil here emits no row and
///    no share — it says so in a driver line instead. The alternative is the
///    worst thing this file could do: read "I have never told the app about a
///    holiday" as "I have not had one", and mark a reader down for a silence.
///    A ledger holding only *booked* leave is still nil for the same reason
///    `HolidayLedger.daysSinceLastLeave` returns nil for it — a booking is not
///    a break.
/// 2. **The curve is a shape, and the copy says so every time.** There is no
///    published figure for how much leave a person needs and this does not
///    invent one (`docs/norms-and-telemetry.md`). What *is* published is the
///    **fade-out**: the restorative effect of a holiday is largest immediately
///    afterwards and decays over the following weeks — de Bloom et al. (2009),
///    *Do we recover from vacation?*, J Occup Health 51:13–25; Kühnel &
///    Sonnentag (2011), *How long do you benefit from vacation?*, J Organ Behav
///    32:125–143. So the score decays with time since the last break and then
///    **flattens at a floor**, and the floor is well above zero: a calendar on
///    its own is never a health catastrophe, exactly as
///    `WorkImpactModel.exposureScore` argues about meeting hours.
public struct LeaveRecency: Sendable, Equatable {

    /// Where the reader stands, in one word — for a headline or a chip that must
    /// not restate the arithmetic.
    public enum Standing: String, Sendable, Equatable, CaseIterable {
        /// A recorded period covers today.
        case onLeaveNow
        /// Inside the window the fade-out literature is about.
        case recent
        /// Months, but inside the half-year the curve still slopes across.
        case aWhileAgo
        /// Past the point where the curve has flattened.
        case longAgo
        /// **Nothing has happened yet** — never any leave, or only leave booked
        /// ahead. Deliberately one case for both: neither answers "have you had
        /// a break", and a card must treat them identically.
        case unrecorded

        public var title: String {
            switch self {
            case .onLeaveNow: return "On leave"
            case .recent: return "Recent break"
            case .aWhileAgo: return "A while since a break"
            case .longAgo: return "A long time since a break"
            case .unrecorded: return "No leave recorded"
            }
        }
    }

    /// Whole days since the last day of recorded leave. Nil when none has
    /// happened — see the type note.
    public let daysSinceLastLeave: Int?
    /// Days off inside the last year, counted once where periods overlap the
    /// window's edges. The context that stops a bare "142 days" reading as a
    /// verdict on somebody who took a month off last spring.
    public let daysOffInLastYear: Int
    /// How many separate periods those days came from.
    public let periodsInLastYear: Int
    /// Days until the next period that starts in the future, when one is
    /// recorded. **Never satisfies the recovery question** — it is carried so a
    /// card and the leave suggestion can say "you have one booked" rather than
    /// nagging somebody who already acted.
    public let nextLeaveInDays: Int?
    /// Whether the ledger holds anything at all, past or planned. Distinct from
    /// `daysSinceLastLeave != nil`, and the distinction is what lets the copy
    /// tell "you have told me nothing" from "you have a week booked".
    public let hasAnyRecord: Bool

    public init(daysSinceLastLeave: Int?, daysOffInLastYear: Int,
                periodsInLastYear: Int, nextLeaveInDays: Int?,
                hasAnyRecord: Bool) {
        self.daysSinceLastLeave = daysSinceLastLeave
        self.daysOffInLastYear = daysOffInLastYear
        self.periodsInLastYear = periodsInLastYear
        self.nextLeaveInDays = nextLeaveInDays
        self.hasAnyRecord = hasAnyRecord
    }

    // MARK: - Reading the ledger

    /// The whole of what the cards read, from the merged ledger.
    public static func read(_ ledger: HolidayLedger, asOf: Date = Date(),
                            calendar: Calendar = .current) -> LeaveRecency {
        let today = calendar.startOfDay(for: asOf)
        let yearAgo = calendar.date(byAdding: .day, value: -365, to: today) ?? today

        var daysOff = 0
        var periodsInYear = 0
        for period in ledger.periods {
            // Clipped to the year *and* to today: leave booked for next month is
            // not time the reader has had off, and counting it here would let a
            // booking answer a question about recovery through the back door.
            let first = Swift.max(period.firstDay, yearAgo)
            let last = Swift.min(period.lastDay, today)
            guard first <= last else { continue }
            periodsInYear += 1
            daysOff += (calendar.dateComponents([.day], from: first, to: last).day ?? 0) + 1
        }

        let next = ledger.periods
            .filter { $0.firstDay > today }
            .map(\.firstDay)
            .min()
            .flatMap { calendar.dateComponents([.day], from: today, to: $0).day }

        return LeaveRecency(
            daysSinceLastLeave: ledger.daysSinceLastLeave(asOf: asOf, calendar: calendar),
            daysOffInLastYear: daysOff,
            periodsInLastYear: periodsInYear,
            nextLeaveInDays: next,
            hasAnyRecord: !ledger.periods.isEmpty)
    }

    public var standing: Standing {
        guard let days = daysSinceLastLeave else { return .unrecorded }
        if days == 0 { return .onLeaveNow }
        if days <= Self.fadeWindowDays { return .recent }
        if days <= Int(Self.curveFlattensAtDays) { return .aWhileAgo }
        return .longAgo
    }

    // MARK: - The shape

    /// The window the fade-out literature is about — the weeks over which a
    /// holiday's measured effect on wellbeing has largely gone. Used only to
    /// name the standing; the score itself is a curve with no step in it.
    public static let fadeWindowDays = 30
    /// Where the curve stops sloping. Past this, more days without leave do not
    /// make a different finding — they make the same one, older.
    public static let curveFlattensAtDays: Double = 365
    /// The floor. **Not zero, and the reason is the same one
    /// `WorkImpactModel.exposureScore` gives for its own floor of 30:** what can
    /// take a card to the bottom is a body, and a body reaches it through the
    /// measured rows. A diary alone must not.
    public static let floorScore: Double = 45

    /// Days since the last break → 0–100, higher is better.
    ///
    /// A curve rather than a band table, per the repo rule `verify.sh` enforces:
    /// a `switch` on a measurement puts a cliff between two readings a day
    /// apart, and "89 days" and "91 days" are not different findings.
    ///
    /// The anchors carry the fade-out shape and nothing else. They are steepest
    /// across the first months — which is where the published effect actually
    /// decays — and flat from a year, because the evidence says nothing about
    /// the difference between fourteen and twenty months and neither will this.
    public static func score(daysSince: Int) -> Double {
        ScoreCurve.through([(0, 95), (Double(fadeWindowDays), 88), (90, 74),
                            (180, 58), (curveFlattensAtDays, floorScore)],
                           at: Double(daysSince))
    }

    /// This reader's 0–100, or **nil when nothing has been recorded** — the
    /// guard the whole type is built around.
    public var score: Double? {
        daysSinceLastLeave.map { Self.score(daysSince: $0) }
    }

    // MARK: - Copy
    //
    // Written once, here, so four cards cannot end up saying four different
    // things about one fact. Every count in it is derived — the repo's
    // hard-coded-count-in-copy lint exists because "four" sat inside a sentence
    // on a card that runs on two.

    /// How the year reads, as a clause. Empty when there is nothing to say.
    private var yearClause: String {
        guard daysOffInLastYear > 0 else { return "" }
        let periods = periodsInLastYear == 1 ? "one period" : "\(periodsInLastYear) periods"
        return " — \(daysOffInLastYear) \(daysOffInLastYear == 1 ? "day" : "days") "
            + "off across \(periods) in the last year"
    }

    /// The clause about leave already booked, or empty.
    public var bookedClause: String {
        guard let next = nextLeaveInDays else { return "" }
        return next == 0
            ? " You have leave starting today."
            : " You have leave booked in \(next) \(next == 1 ? "day" : "days") — booked is not the same as had, so it does not answer this."
    }

    /// The sentence the card puts in its drivers.
    public func driverLine(share: Double) -> String {
        guard let days = daysSinceLastLeave else {
            return hasAnyRecord
                ? "No leave has happened yet on your record, so this card is not scoring it.\(bookedClause) It can only read leave your calendar shows or you have entered."
                : "No leave is recorded at all, so this card is not scoring it — and it cannot tell a year without a break from a break it was never told about. Adding one under \"Holiday or leave\" is what turns that silence into an input."
        }
        let since = days == 0
            ? "You are on leave today"
            : "Your last recorded leave ended \(days) \(days == 1 ? "day" : "days") ago"
        return "\(since)\(yearClause), and that carries \(Int((share * 100).rounded()))% of this number. Time off is the one thing on a calendar meant to undo load, so a long stretch without any is part of what this reads.\(bookedClause)"
    }

    /// The weighted row's detail — the one that has to state the basis, because
    /// this is where a reader goes to ask why a share exists at all.
    public var rowDetail: String {
        let days = daysSinceLastLeave ?? 0
        let since = days == 0
            ? "On leave today"
            : "\(days) \(days == 1 ? "day" : "days") since your last recorded leave"
        return "\(since)\(yearClause). Scored on a shape rather than a norm — the published work on holidays finds their restorative effect is largest straight afterwards and fades over the following weeks (de Bloom et al., 2009; Kühnel & Sonnentag, 2011), so this decays with time and then flattens. There is no published figure for how much leave anybody needs and this is not one: it never falls below \(Int(Self.floorScore)), because a diary is not a health measurement. It reads only leave your calendar shows or you have entered."
    }

    // MARK: - The series
    //
    // One key, shared by every card that scores this, namespaced per card by
    // `DerivedSeriesID` exactly as `bodyDifferencePooled` already is on both
    // calendar cards. Baked into stored ids, so renaming it orphans history —
    // treat it like a `modelVersion`.

    public static let daysSinceLeaveKey = "daysSinceLeave"

    /// The trendable figure behind the row, emitted **only** when the row is —
    /// a series that appears while nothing was scored would be a link to a
    /// number the card did not use.
    public var derivedOutput: DerivedOutput? {
        guard let days = daysSinceLastLeave else { return nil }
        return DerivedOutput(key: Self.daysSinceLeaveKey,
                             displayName: "Days since your last leave",
                             unit: "days", value: Double(days),
                             higherIsBetter: false, precision: 0)
    }
}

/// **Folding the leave row into a card that has already scored itself.**
///
/// The four cards that take this compute their numbers four different ways —
/// work impact blends two groups through `ScoreBlend`, the other three are
/// curves over a pooled departure — and none of them can express "and one more
/// input, worth a tenth of the whole" without restructuring. So the fold happens
/// *after*: the card's own number becomes `1 - share` of the result, every
/// weight it already emitted is scaled by the same factor, and the leave row
/// takes the remainder.
///
/// ⚠️ **The shares still sum to one**, which is the claim "How this is weighted"
/// makes on screen and the thing `DerivedFactorIdentityTests` checks. Scaling
/// both groups by the same factor is what preserves it; scaling only the
/// contributions would put 108% on a card.
///
/// ⚠️ **A card with nothing recorded comes back untouched** — same score, same
/// weights, no row. That is not only the honest answer (see `LeaveRecency`'s own
/// note), it is what keeps every score this app has already recorded comparable
/// for a reader who never enters a holiday.
public struct LeaveBlend: Sendable {
    public let score: Double
    public let contributions: [MetricContribution]
    public let factors: [ScoreFactor]
    /// Whether the leave row was actually emitted. The card branches its driver
    /// line on this rather than re-testing the ledger, so the sentence and the
    /// arithmetic cannot disagree.
    public let didScore: Bool

    public static func fold(score cardScore: Double,
                            contributions: [MetricContribution],
                            factors: [ScoreFactor],
                            recency: LeaveRecency,
                            on id: InsightID,
                            share: Double) -> LeaveBlend {
        guard let leaveScore = recency.score, share > 0, share < 1 else {
            return LeaveBlend(score: cardScore, contributions: contributions,
                              factors: factors, didScore: false)
        }
        let keep = 1 - share
        let scaledContributions = contributions.map { c in
            MetricContribution(metric: c.metric, higherIsBetter: c.higherIsBetter,
                               weight: c.weight * keep, detail: c.detail,
                               componentScore: c.componentScore, value: c.value,
                               baseline: c.baseline, z: c.z)
        }
        let scaledFactors = factors.map { f in
            ScoreFactor(source: f.source, name: f.name, weight: f.weight * keep,
                        detail: f.detail, isModifiable: f.isModifiable)
        }
        let row = ScoreFactor.derived(
            DerivedSeriesID(id, LeaveRecency.daysSinceLeaveKey),
            name: "Time since your last leave",
            weight: share,
            detail: recency.rowDetail)
        return LeaveBlend(score: cardScore * keep + leaveScore * share,
                          contributions: scaledContributions,
                          factors: scaledFactors + [row],
                          didScore: true)
    }
}
