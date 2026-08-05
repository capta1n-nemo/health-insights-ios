import Foundation

/// **A modelled micronutrient intake for the days the reader logged calories but
/// not vitamins** — and the honest statement of what it is worth.
///
/// Backlog Q4, answered by the reader on 2026-08-06: *"do an estimation, note
/// the limitation and need for more data."*
///
/// ## Why this has to exist at all
///
/// `MicronutrientTargets` has held published, sex-and-age-resolved figures for
/// eight vitamins and minerals since it was written, and **nothing has ever
/// called it.** Meanwhile the Nutrition card makes sex and date of birth
/// *mandatory* on the stated grounds that "without it none of them can be
/// scored" — and then scores none of them. That rationale was untrue on the day
/// it shipped. This closes it from the other end: the targets get used, so the
/// ask becomes true.
///
/// ## What the estimate is, precisely
///
/// Most food logs carry energy and macros and almost no micronutrients — a
/// barcode gives calories, protein, fat and carbohydrate, and that is where it
/// stops. So for a nutrient the reader has no rows for, the intake is modelled
/// as
///
///     estimated intake = logged energy (kcal) × typical density (per 1000 kcal)
///
/// where the density is a population mean intake divided by a population mean
/// energy intake. It answers one question and only one: **"if you eat a fairly
/// ordinary diet, roughly what would that many calories have carried?"**
///
/// ## ⚠️ What it is emphatically not
///
/// It is **not a measurement of this reader**. Two people eating identical
/// calories can differ several-fold in any of these — the whole point of
/// micronutrients is that they track *what* you ate, not *how much*. So:
///
/// - Every estimated row carries **weight 0** and never moves the card's score.
///   Only a nutrient the reader actually logged is scored. (`Standing`
///   still resolves, so the row can say "below the published figure" — it just
///   cannot vote.)
/// - Every estimated row says on its face that it came from calories, not food.
/// - The card states how many of the eight were real and how many were modelled.
///
/// That split is the app's third structural invariant applied to a number rather
/// than to a sample: modelled is never dressed as measured.
///
/// ## The densities, and how much to trust them
///
/// Each is a published adult population **mean daily intake** divided by the
/// same population's mean daily energy, rounded hard because the third
/// significant figure would be false precision. They are order-of-magnitude
/// constants: right to within roughly a factor for a typical mixed diet, and
/// capable of being wrong by several times for a restricted one. A reader who
/// eats no dairy will have a real calcium intake nothing like the modelled one,
/// and the card cannot know that — which is exactly why these do not vote and
/// why the remedy stated on the card is *log your food properly*.
public enum MicronutrientEstimate {

    /// Typical intake per 1,000 kcal, in each metric's own unit (mg, except the
    /// three the app records in micrograms — vitamins A, D and B12).
    ///
    /// Deliberately a flat table rather than a computed model. A more elaborate
    /// estimator here would be more precise about a quantity that is not
    /// measured at all, which is precision pointed at the wrong thing.
    public static func densityPer1000kcal(_ metric: MetricType) -> Double? {
        switch metric {
        case .dietaryVitaminC:   return 38      // mg
        case .dietaryVitaminD:   return 2.4     // mcg
        case .dietaryVitaminA:   return 300     // mcg RAE
        case .dietaryVitaminB12: return 2.3     // mcg
        case .dietaryCalcium:    return 450     // mg
        case .dietaryIron:       return 7       // mg
        case .dietaryMagnesium:  return 150     // mg
        case .dietaryZinc:       return 5.7     // mg
        default:                 return nil
        }
    }

    /// Where a micronutrient figure came from. The card renders these
    /// differently and must never be able to forget which it has.
    public enum Basis: Sendable, Equatable {
        /// The reader's own log carried this nutrient.
        case logged
        /// Modelled from logged energy and a population density.
        case estimatedFromEnergy
    }

    public struct Row: Sendable, Equatable, Identifiable {
        public let metric: MetricType
        public let intake: Double
        public let basis: Basis
        public let target: MicronutrientTargets.Target
        public let standing: MicronutrientTargets.Standing
        public var id: String { metric.rawValue }

        public var isEstimated: Bool { basis == .estimatedFromEnergy }

        public init(metric: MetricType, intake: Double, basis: Basis,
                    target: MicronutrientTargets.Target,
                    standing: MicronutrientTargets.Standing) {
            self.metric = metric
            self.intake = intake
            self.basis = basis
            self.target = target
            self.standing = standing
        }
    }

    public struct Output: Sendable, Equatable {
        public let rows: [Row]
        /// How many of `rows` came from the reader's own log.
        public var loggedCount: Int { rows.filter { !$0.isEstimated }.count }
        public var estimatedCount: Int { rows.filter(\.isEstimated).count }
        /// Rows that are below their published floor, or over a ceiling.
        public var flagged: [Row] { rows.filter { $0.standing != .met } }

        public init(rows: [Row]) { self.rows = rows }
    }

    /// Build the eight rows.
    ///
    /// - Parameters:
    ///   - means: mean daily intake per metric over the logged days, as the
    ///     Nutrition card already computes for its macros.
    ///   - energy: mean daily energy over the same days — the scale the
    ///     estimate rests on.
    ///
    /// Returns nil when neither sex nor age is known, because then not one
    /// target resolves and there is nothing to compare against. That nil is what
    /// makes the card's mandatory ask honest.
    public static func evaluate(means: [MetricType: Double],
                                energy: Double,
                                sex: BiologicalSex?,
                                age: Int?) -> Output? {
        var rows: [Row] = []
        for metric in MicronutrientTargets.targetable {
            guard let target = MicronutrientTargets.target(for: metric, sex: sex, age: age)
            else { continue }

            let intake: Double
            let basis: Basis
            if let logged = means[metric], logged > 0 {
                intake = logged
                basis = .logged
            } else if let density = densityPer1000kcal(metric), energy > 0 {
                intake = energy / 1_000 * density
                basis = .estimatedFromEnergy
            } else {
                continue
            }

            guard let standing = MicronutrientTargets.standing(
                intake, for: metric, sex: sex, age: age) else { continue }
            rows.append(Row(metric: metric, intake: intake, basis: basis,
                            target: target, standing: standing))
        }
        return rows.isEmpty ? nil : Output(rows: rows)
    }

    /// The sentence that has to appear whenever an estimated row does.
    ///
    /// Kept here rather than written at each call site so the caveat cannot
    /// drift away from the thing it qualifies — the failure `SubstanceShading`
    /// and `MetricSource.calculated` both exist to prevent.
    public static func caveat(estimatedCount: Int, of total: Int) -> String {
        guard estimatedCount > 0 else {
            return "All \(total) came from what you logged."
        }
        if estimatedCount == total {
            return "None of these came from your food log — every figure is modelled from the calories you logged and a typical diet's nutrient density, so it says what an ordinary diet of that size would carry, not what yours did. Log food that carries vitamin and mineral data and these become real."
        }
        return "\(total - estimatedCount) of \(total) came from your log. The other \(estimatedCount) are modelled from your calories and a typical diet's nutrient density — an ordinary diet of that size, not yours. They are shown, and they do not count towards the score."
    }

    /// How an individual estimated row explains itself.
    public static func rowDetail(_ row: Row) -> String {
        let unit = row.metric.unit
        let intake = String(format: row.intake < 10 ? "%.1f" : "%.0f", row.intake)
        let floor = String(format: row.target.recommended < 10 ? "%.1f" : "%.0f",
                           row.target.recommended)
        let comparison: String
        switch row.standing {
        case .below:
            comparison = "under the \(floor) \(unit) figure"
        case .met:
            comparison = "at or over the \(floor) \(unit) figure"
        case .aboveUpperLimit:
            let ceiling = row.target.upperLimit.map {
                String(format: $0 < 10 ? "%.1f" : "%.0f", $0)
            } ?? "the"
            comparison = "⚠️ over the \(ceiling) \(unit) tolerable upper intake"
        }
        let source = row.isEstimated
            ? "estimated from your calories, not from your log"
            : "from your log"
        return "\(intake) \(unit) a day — \(comparison) · \(source)"
    }
}
