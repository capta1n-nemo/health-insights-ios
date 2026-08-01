import Foundation

/// Which of your risk factors is carrying your 10-year risk, and by how much.
///
/// ## Why the card could not answer this before
///
/// "How this is weighted" said **"Not a weighted average"** on the risk card,
/// and the reasoning behind that was half right: SCORE2 and ASCVD are published
/// equations, so nobody here *chose* a proportion for blood pressure. But that
/// is an argument about where the numbers come from, not about whether they
/// exist. The equations are perfectly explicit about what each input is doing.
///
/// ## The method, and why it is this one
///
/// **Hold one factor at its optimal value and run the same equation again.** The
/// drop is what that factor is contributing. This is the attribution the
/// vascular-age literature already uses (D'Agostino et al., *Circulation* 2008),
/// it is what the card's own copy already describes — *"10-year risk 8.1%
/// against 3.2% at optimal levels — that gap is the modifiable part"* — and,
/// decisively, it **reuses `HeartAgeModel.riskPercent` unchanged**.
///
/// That last point is the whole reason for this shape. The obvious alternative
/// is to decompose the linear predictor: each term is βᵢ·(xᵢ − x̄ᵢ) and the
/// coefficients are sitting right there in `CardiovascularRiskModel`. It would
/// also be a **second copy of every coefficient**, free to drift from the first
/// — the exact defect `PressureBandTests` and `VitalDeparture` were written to
/// close, one level up. Nothing here knows a single coefficient.
///
/// ## What the shares mean, stated honestly
///
/// Two things are true of them and both are said on the card:
///
/// - **They are shares of one result, not independent additions.** Both
///   equations are exponential in the linear predictor and both carry age
///   interactions, so the drops do not sum to the gap they are divided over.
///   They are normalised into it, which is an approximation, and it is the same
///   approximation every published heart-age calculator makes.
/// - **Age and sex are not modifiable and arrive as one row.** There is no
///   optimal age to hold anything at, so leave-one-out cannot separate them from
///   each other — and it does not need to. What an optimal-factor person of your
///   age and sex already carries *is* the non-modifiable share, and the rest is
///   the part you can move. `ScoreFactor.isModifiable` marks it, because a bar
///   chart that ranks age beside cholesterol without saying so reads as a list
///   of things to work on with the biggest bar on the one nobody can change.
public enum RiskAttribution {

    /// A modifiable input, and how to set it to its optimal value.
    ///
    /// Deliberately **not** `treatedForBP`. Holding it "optimal" would mean
    /// pretending an untreated person, and the equations charge treatment a
    /// higher systolic coefficient precisely because being on medication marks
    /// someone whose pressure needed it. The drop would read as "your blood
    /// pressure treatment is carrying 4% of your risk", which is confounding
    /// stated as a finding.
    enum Lever: CaseIterable {
        case systolic, totalCholesterol, hdlCholesterol, smoking, diabetes

        func optimal(_ subject: HeartAgeModel.Subject) -> HeartAgeModel.Subject {
            var copy = subject
            switch self {
            case .systolic:
                copy.systolicBP = HeartAgeModel.OptimalReference.systolicBP
            case .totalCholesterol:
                copy.totalCholesterolMmol = HeartAgeModel.OptimalReference.totalCholesterolMmol
            case .hdlCholesterol:
                copy.hdlCholesterolMmol = HeartAgeModel.OptimalReference.hdlCholesterolMmol
            case .smoking:
                copy.isSmoker = false
            case .diabetes:
                copy.hasDiabetes = false
            }
            return copy
        }
    }

    /// Every input's share of the risk figure, including the non-modifiable one.
    ///
    /// Blood pressure comes back as `.metric(.bloodPressureSystolic)` so the
    /// caller can put its share on the `MetricContribution` it already emits —
    /// one statement of that number, which the overlay legend reads too.
    ///
    /// - Parameters:
    ///   - engines: the engines the card actually used for its headline. The
    ///     attribution has to be of the number on screen, so an engine dropped
    ///     for being outside its validated age band must be dropped here too.
    ///   - cholesterolAssumed: whether the population average stood in. The
    ///     share is still real — an assumed value drives the equation exactly as
    ///     a measured one does — and saying so is the strongest argument for a
    ///     blood test the card can make.
    public static func factors(engines: [HeartAgeModel.Engine],
                               subject: HeartAgeModel.Subject,
                               age: Double,
                               cholesterolAssumed: Bool) -> [ScoreFactor] {
        guard !engines.isEmpty else { return [] }

        func risk(_ s: HeartAgeModel.Subject) -> Double {
            engines.map { HeartAgeModel.riskPercent($0, subject: s, age: age) }
                .reduce(0, +) / Double(engines.count)
        }

        let mine = risk(subject)
        guard mine > 0 else { return [] }
        let optimal = risk(subject.withOptimalFactors)

        // What an optimal-factor person of the same age and sex already carries.
        // Clamped: a subject who beats the reference on balance would otherwise
        // hand age and sex more than the whole number.
        let baselineShare = Swift.max(0, Swift.min(1, optimal / mine))
        let modifiablePool = 1 - baselineShare

        // Each lever's own drop, floored at zero. A factor already at or better
        // than optimal is not carrying risk, and a negative share drawn as a bar
        // would have to point backwards.
        var drops: [(Lever, Double)] = []
        for lever in Lever.allCases {
            drops.append((lever, Swift.max(0, mine - risk(lever.optimal(subject)))))
        }
        let totalDrop = drops.reduce(0) { $0 + $1.1 }

        var out: [ScoreFactor] = [
            ScoreFactor(
                source: .grounding(.dateOfBirth),
                name: "Age and sex",
                weight: baselineShare,
                detail: "\(Int(age.rounded())), \(subject.sex.displayName.lowercased())",
                isModifiable: false)
        ]
        for (lever, drop) in drops {
            let share = totalDrop > 0 ? modifiablePool * drop / totalDrop : 0
            out.append(factor(lever, subject: subject, share: share,
                              cholesterolAssumed: cholesterolAssumed))
        }
        return out
    }

    /// How each lever names itself and states its value.
    ///
    /// A lever at zero share is still returned, **and says why on its own row**.
    /// "Non-smoker, so it's carrying none of your risk" is the answer somebody
    /// wants under a section about what is driving that risk; dropping the row
    /// would leave them unable to tell "carrying none" from "not looked at", and
    /// a bare zero under a section promising every input carries a share reads
    /// as a fault rather than as good news.
    private static func factor(_ lever: Lever, subject: HeartAgeModel.Subject,
                               share: Double, cholesterolAssumed: Bool) -> ScoreFactor {
        let assumed = cholesterolAssumed ? " (assumed average)" : ""
        let carryingNone = share > 0 ? ""
            : " — at or better than optimal, so it's carrying none of your risk"
        switch lever {
        case .systolic:
            return ScoreFactor(
                source: .metric(.bloodPressureSystolic), name: "Blood pressure",
                weight: share,
                detail: String(format: "%.0f mmHg against an optimal %.0f",
                               subject.systolicBP, HeartAgeModel.OptimalReference.systolicBP)
                    + carryingNone,
                isModifiable: true)
        case .totalCholesterol:
            return ScoreFactor(
                source: .grounding(.totalCholesterol), name: "Total cholesterol",
                weight: share,
                detail: String(format: "%.1f mmol/L against an optimal %.1f%@",
                               subject.totalCholesterolMmol,
                               HeartAgeModel.OptimalReference.totalCholesterolMmol, assumed)
                    + carryingNone,
                isModifiable: true)
        case .hdlCholesterol:
            return ScoreFactor(
                source: .grounding(.hdlCholesterol), name: "HDL cholesterol",
                weight: share,
                detail: String(format: "%.1f mmol/L against an optimal %.1f%@",
                               subject.hdlCholesterolMmol,
                               HeartAgeModel.OptimalReference.hdlCholesterolMmol, assumed)
                    + carryingNone,
                isModifiable: true)
        case .smoking:
            return ScoreFactor(
                source: .grounding(.currentSmoker), name: "Smoking",
                weight: share,
                detail: (subject.isSmoker ? "current smoker" : "non-smoker") + carryingNone,
                isModifiable: true)
        case .diabetes:
            return ScoreFactor(
                source: .grounding(.hasDiabetes), name: "Diabetes",
                weight: share,
                detail: (subject.hasDiabetes ? "yes" : "no") + carryingNone,
                isModifiable: true)
        }
    }
}
