import Foundation

/// **The night-by-night ledger behind the sleep-debt figure.**
///
/// `SleepDebtModel.evaluate` returns one number: how far behind you are today.
/// That number is the *end* of an arithmetic nobody could see — which night put
/// the debt there, which night paid it back, and what it was all measured
/// against. A card that says "4.2 h behind" and cannot show its working is
/// asking to be believed rather than read.
///
/// This is the same arithmetic, kept per night, so a section can draw it: the
/// running total below is the identical discounted sum `SleepDebtModel.evaluate`
/// takes, with the same window and the same half-life, evaluated at each night's
/// own date rather than only at today's.
///
/// ⚠️ **The last row is the balance as at that night, not as at this minute.**
/// `evaluate` discounts every shortfall forward to `now`, so on a morning when
/// the last recorded night was two days ago its figure is the smaller of the
/// two. That is not a disagreement — debt decays, and the card's headline is the
/// one that has to be current. A section drawing both must label the curve *as
/// at each night* and take the headline from `evaluate`, which is what
/// `SleepDebtSection` does.
///
/// ## The baseline decision, stated in code (backlog B18-7)
///
/// Sleep debt is a shortfall against *something*, and there are three candidates
/// with three different answers:
///
/// 1. **A published need.** Eight hours, or the NSF's 7–9 band. Comparable
///    across people and a poor description of any of them.
/// 2. **The reader's own habitual unconstrained duration** — how long they sleep
///    when nothing wakes them. Personal, and measurable from what is already
///    ingested.
/// 3. **The duration on the days they felt best.** The most personal of the
///    three, and the subject of `IdealSleepWindow`.
///
/// **This app uses (2), and refuses (3) deliberately.** `SleepDebtModel.need`
/// takes the upper quartile of the reader's own nights over ninety days,
/// bounded to 6.5–9.5 h, which is (2) made concrete: the quartile approximates
/// "the nights nothing cut short" without needing an alarm log the app does not
/// have.
///
/// (3) is refused because it would make the *denominator* of the debt a modelled
/// quantity that moves whenever the outcome model moves. The reader would watch
/// their debt change on a day they slept exactly as usual, and nothing on screen
/// could tell them whether their body or the app's opinion had shifted. The same
/// rule the backlog states for `B18-7` against `B19` — build them against one
/// model rather than two — applies inside this card as much as across cards.
///
/// (1) is not thrown away: `publishedBand` carries it, so the section can show
/// where the reader's learned need sits against the published one without either
/// standing in for the other.
public extension SleepDebtModel {

    /// What the shortfall was measured against, and how that was arrived at.
    enum NeedBasis: String, Sendable, Equatable {
        /// The upper quartile of the reader's own recent nights.
        case learnedFromYourOwnNights
        /// The 8 h fallback, used only until there are enough nights to learn
        /// from. Named `assumed` on screen, never "recommended".
        case assumedUntilThereAreEnoughNights

        public var sentence: String {
            switch self {
            case .learnedFromYourOwnNights:
                return "measured from your own longer nights over the last ninety days — "
                    + "the upper quarter of them, which is the closest thing the app has "
                    + "to \"nights nothing cut short\""
            case .assumedUntilThereAreEnoughNights:
                return "an assumed eight hours, because there are not yet enough of your "
                    + "own nights to learn one from. It will become yours as you record more"
            }
        }
    }

    /// One night, and what it did to the balance.
    struct LedgerNight: Sendable, Equatable, Identifiable {
        public let date: Date
        public let hours: Double
        /// Hours short of the need. Zero on a night that met or beat it.
        public let shortfall: Double
        /// Hours over the need. Zero on a night that fell short.
        ///
        /// ⚠️ **Surplus is drawn and never subtracted.** `SleepDebtModel` sums
        /// shortfalls only, and that is the published shape of the thing: a
        /// twelve-hour Sunday does not undo four short weeknights, it just fails
        /// to add to them. Reporting the surplus lets the section show a good
        /// night as a good night without smuggling a credit into the arithmetic.
        public let surplus: Double
        /// The discounted debt as it stood at the end of this night — the same
        /// sum `evaluate` reports, evaluated here.
        public let debtAfter: Double

        public var id: Date { date }
    }

    struct Ledger: Sendable, Equatable {
        public let nights: [LedgerNight]
        public let needHours: Double
        public let basis: NeedBasis
        /// The published consensus band, for context only. Never the thing the
        /// shortfall is measured against.
        public let publishedBand: ClosedRange<Double>
        /// Today's figure — the last night's `debtAfter`, or zero for an empty
        /// ledger.
        public var debtHours: Double { nights.last?.debtAfter ?? 0 }
        public var nightsCounted: Int { nights.count }
    }

    /// The NSF consensus band for a healthy adult, carried for context.
    static var publishedAdultBand: ClosedRange<Double> { 7...9 }

    /// Every night in the window, with the balance as it stood after each.
    ///
    /// `days` is how far back the *chart* runs. The need is still learned over
    /// ninety nights whatever this is set to, for the reason `evaluate` gives:
    /// one bad fortnight must not quietly redefine what "enough" means.
    static func ledger(samples: [HealthMetricSample],
                       days: Int = 90,
                       now: Date = Date(),
                       calendar: Calendar = .current) -> Ledger? {
        let series = VitalReader.dailySeries(.sleepDurationHours, from: samples,
                                             days: days, now: now, calendar: calendar)
        guard series.count >= 3 else { return nil }

        let longRun = VitalReader.dailyValues(.sleepDurationHours, from: samples,
                                              days: 90, now: now, calendar: calendar)
        let (needHours, learned) = need(from: longRun)

        // The debt at the end of night *i* is the same discounted sum `evaluate`
        // takes, over the nights up to and including *i* that are inside the
        // fortnight window ending there. Written as an explicit inner loop
        // rather than an incremental decay, because the two are only equal when
        // the nights are evenly spaced — and a series with a missing night is
        // exactly where an incremental version would drift away from the figure
        // on the card.
        var rows: [LedgerNight] = []
        for (index, night) in series.enumerated() {
            var debt = 0.0
            let windowStart = night.date
                .addingTimeInterval(-Double(windowNights) * 86_400)
            for earlier in series[...index] where earlier.date > windowStart {
                let shortfall = Swift.max(0, needHours - earlier.value)
                guard shortfall > 0 else { continue }
                let ageDays = night.date.timeIntervalSince(earlier.date) / 86_400
                debt += shortfall * pow(0.5, Swift.max(0, ageDays) / halfLifeDays)
            }
            rows.append(LedgerNight(
                date: night.date, hours: night.value,
                shortfall: Swift.max(0, needHours - night.value),
                surplus: Swift.max(0, night.value - needHours),
                debtAfter: debt))
        }

        return Ledger(nights: rows, needHours: needHours,
                      basis: learned ? .learnedFromYourOwnNights
                                     : .assumedUntilThereAreEnoughNights,
                      publishedBand: publishedAdultBand)
    }
}
