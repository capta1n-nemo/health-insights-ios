import Foundation

/// How far behind on sleep you actually are, and what it would take to catch up.
///
/// Every sleep feature in every app reports last night. Nobody reports the
/// *balance*, which is the number people actually feel: four short nights in a
/// row is a different state from one, and an app that scores each night in
/// isolation cannot tell you which one you are in.
///
/// ## Your need, learned rather than assumed
///
/// Eight hours is a population average and a poor description of any individual.
/// This learns the personal figure from the user's own unconstrained nights —
/// the ones where nothing woke them early — approximated by the upper quantile of
/// their recent history. Somebody who reliably takes 9 hours when left alone is
/// in debt at 8; somebody who is genuinely done at 7 is not.
///
/// ## Debt fades
///
/// Sleep loss is not a ledger that keeps perfect books forever. The research on
/// recovery is that most of the deficit is repaid quickly and the remainder
/// decays — so a bad night three weeks ago is not still costing you. Older
/// shortfalls are discounted rather than carried at face value, which is what
/// stops the number ratcheting to infinity for anyone with a busy month.
public enum SleepDebtModel {

    /// Nights considered.
    public static let windowNights = 14
    /// How long a night's shortfall takes to halve.
    ///
    /// Five days. Short enough that a single bad Tuesday is nearly gone by the
    /// weekend, long enough that four short nights in a row still accumulate —
    /// which is the state the card exists to name.
    public static let halfLifeDays = 5.0
    /// Bounds on the learned need, because a quantile over a short or strange
    /// history can produce a silly figure.
    public static let minimumNeed = 6.5
    public static let maximumNeed = 9.5
    /// Where in the user's own distribution their unconstrained night sits.
    public static let needQuantile = 0.75
    /// Extra sleep a person can realistically add per night when catching up.
    public static let catchUpPerNight = 1.0

    public struct Output: Sendable, Equatable {
        /// Hours behind, after discounting.
        public let debtHours: Double
        /// The personal need this was measured against.
        public let needHours: Double
        /// Whether the need was learned or is the fallback.
        public let needIsLearned: Bool
        public let lastNightHours: Double?
        public let nightsCounted: Int
        /// Nights of an extra hour it would take to clear.
        public var nightsToClear: Int {
            Int((debtHours / catchUpPerNight).rounded(.up))
        }

        public var band: String {
            switch debtHours {
            case ..<1: return "Clear"
            case 1..<3: return "Slight"
            case 3..<6: return "Building"
            default: return "Heavy"
            }
        }
    }

    /// The personal need, learned from the user's own longer nights.
    public static func need(from nights: [Double]) -> (hours: Double, learned: Bool) {
        // Enough nights that the upper quartile means something.
        guard nights.count >= 7, let quantile = Baseline.quantile(needQuantile, of: nights) else {
            return (8, false)
        }
        return (Swift.max(minimumNeed, Swift.min(maximumNeed, quantile)), true)
    }

    public static func evaluate(samples: [HealthMetricSample], now: Date = Date(),
                                calendar: Calendar = .current) -> Output? {
        let series = VitalReader.dailySeries(.sleepDurationHours, from: samples,
                                             days: windowNights, now: now, calendar: calendar)
        guard series.count >= 3 else { return nil }

        // The need is learned from a longer run than the debt window, so one bad
        // fortnight cannot quietly redefine what "enough" means.
        let longRun = VitalReader.dailyValues(.sleepDurationHours, from: samples,
                                              days: 90, now: now, calendar: calendar)
        let (needHours, learned) = need(from: longRun)

        var debt = 0.0
        for night in series {
            let shortfall = Swift.max(0, needHours - night.value)
            guard shortfall > 0 else { continue }
            let ageDays = now.timeIntervalSince(night.date) / 86_400
            debt += shortfall * pow(0.5, Swift.max(0, ageDays) / halfLifeDays)
        }

        return Output(debtHours: debt, needHours: needHours, needIsLearned: learned,
                      lastNightHours: series.last?.value, nightsCounted: series.count)
    }

    /// 0–100, higher is better. Six hours behind is a thoroughly depleted
    /// fortnight and dials near zero.
    public static func score(debtHours: Double) -> Double {
        Swift.max(0, Swift.min(100, 100 - debtHours / 6 * 100))
    }
}

/// The Today card.

