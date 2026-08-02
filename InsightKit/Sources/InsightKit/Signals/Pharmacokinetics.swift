import Foundation

/// The GLP-1 receptor agonists this app can model, with the published constants
/// each one needs.
///
/// **This module describes; it never prescribes.** It models what the reader
/// tells it they took, and it may say what that implies about the drug still in
/// them. It must not recommend a dose, advance a titration on its own, or
/// suggest a change — those are prescribing, and this is a health diary.
public enum GLPCompound: String, Sendable, Codable, CaseIterable, Identifiable {
    case tirzepatide, semaglutide, liraglutide

    public var id: String { rawValue }

    /// The names people know them by. Display only — the pharmacology is keyed
    /// on the compound, because the same compound is sold under several names.
    public var brandNames: [String] {
        switch self {
        case .tirzepatide: return ["Mounjaro", "Zepbound"]
        case .semaglutide: return ["Ozempic", "Wegovy"]
        case .liraglutide: return ["Victoza", "Saxenda"]
        }
    }

    public var displayName: String {
        switch self {
        case .tirzepatide: return "Tirzepatide"
        case .semaglutide: return "Semaglutide"
        case .liraglutide: return "Liraglutide"
        }
    }

    /// Published elimination half-life.
    public var eliminationHalfLifeHours: Double {
        switch self {
        case .tirzepatide: return 5 * 24      // ~5 days
        case .semaglutide: return 7 * 24      // ~1 week
        case .liraglutide: return 13          // ~13 hours
        }
    }

    /// Absorption half-life from the subcutaneous depot. Much shorter than
    /// elimination for all three, which is what gives the curve its shape: a
    /// rise over a day or two, then a long tail.
    public var absorptionHalfLifeHours: Double {
        switch self {
        case .tirzepatide, .semaglutide: return 24
        case .liraglutide: return 8
        }
    }

    public var dosingIntervalDays: Int {
        switch self {
        case .tirzepatide, .semaglutide: return 7
        case .liraglutide: return 1
        }
    }

    /// The manufacturer's standard escalation ladder, in milligrams.
    public var titrationLadder: [Double] {
        switch self {
        case .tirzepatide: return [2.5, 5, 7.5, 10, 12.5, 15]
        case .semaglutide: return [0.25, 0.5, 1, 1.7, 2.4]
        case .liraglutide: return [0.6, 1.2, 1.8, 2.4, 3.0]
        }
    }

    /// How long a step on the ladder normally lasts before the next increase.
    public var titrationIntervalDays: Int { 28 }

    /// Elimination rate constant, per hour.
    public var eliminationRate: Double { log(2) / eliminationHalfLifeHours }
    /// Absorption rate constant, per hour.
    public var absorptionRate: Double { log(2) / absorptionHalfLifeHours }
}

/// One dose, as the model needs it. Deliberately a value type: the app's
/// SwiftData record maps into this, so the maths never depends on persistence.
public struct AdministeredDose: Sendable, Equatable {
    public let takenAt: Date
    public let milligrams: Double
    /// True when this dose was *extrapolated* by `TitrationEngine` rather than
    /// entered or confirmed by the reader. Everything derived from it is drawn
    /// dashed — the app's one rule for "not measured".
    public let isInferred: Bool
    /// Where it was injected, when the reader (or an import) said.
    ///
    /// Carried on the dose rather than looked up separately because
    /// `MedicationResponse` attributes weight change to whichever dose was in
    /// effect, and "which site" is a property of that same dose. Free text: it
    /// is Shotsy's vocabulary on the way in, and a fixed enum would drop any
    /// site somebody else's app names differently.
    public let site: String?

    public init(takenAt: Date, milligrams: Double, isInferred: Bool = false,
                site: String? = nil) {
        self.takenAt = takenAt
        self.milligrams = milligrams
        self.isInferred = isInferred
        self.site = site
    }
}

/// A point on the active-compound curve.
public struct ActiveCompoundPoint: Sendable, Equatable, Identifiable {
    public let date: Date
    /// Milligram-equivalent still active, by the one-compartment model.
    public let level: Double
    /// True where any dose contributing here was inferred rather than
    /// confirmed, so the chart can draw it as the estimate it is.
    public let restsOnInferredDose: Bool
    public var id: Date { date }
}

public enum PharmacokineticsModel {

    /// Concentration from a single dose, `hours` after it was given, by the
    /// one-compartment model with first-order absorption and elimination — the
    /// Bateman function:
    ///
    ///     C(t) = D · ka/(ka − ke) · (e^(−ke·t) − e^(−ka·t))
    ///
    /// Zero before the dose, because a drug cannot act before it is taken.
    /// When `ka` and `ke` are equal the expression above is 0/0, and the limit
    /// is `D · ke · t · e^(−ke·t)` — handled explicitly rather than left to
    /// produce a NaN that would propagate silently through every later sum.
    public static func singleDoseLevel(dose: Double, hoursSince hours: Double,
                                       compound: GLPCompound) -> Double {
        guard hours >= 0, dose > 0 else { return 0 }
        let ke = compound.eliminationRate
        let ka = compound.absorptionRate
        guard abs(ka - ke) > 1e-9 else {
            return dose * ke * hours * exp(-ke * hours)
        }
        return dose * (ka / (ka - ke)) * (exp(-ke * hours) - exp(-ka * hours))
    }

    /// Total active compound at an instant.
    ///
    /// Doses superpose because the model is linear in dose — which is also why
    /// the curve can be precomputed and stored without becoming wrong later.
    public static func level(at date: Date, doses: [AdministeredDose],
                             compound: GLPCompound) -> Double {
        doses.reduce(0) { total, dose in
            let hours = date.timeIntervalSince(dose.takenAt) / 3600
            return total + singleDoseLevel(dose: dose.milligrams, hoursSince: hours,
                                           compound: compound)
        }
    }

    /// The curve between two dates.
    public static func curve(doses: [AdministeredDose], compound: GLPCompound,
                             from start: Date, to end: Date,
                             step: TimeInterval = 6 * 3600) -> [ActiveCompoundPoint] {
        guard start < end, step > 0, !doses.isEmpty else { return [] }
        var out: [ActiveCompoundPoint] = []
        var cursor = start
        while cursor <= end {
            let contributing = doses.filter { $0.takenAt <= cursor }
            let level = self.level(at: cursor, doses: contributing, compound: compound)
            out.append(ActiveCompoundPoint(
                date: cursor, level: level,
                // Only doses still meaningfully contributing can make a point
                // an estimate — an inferred dose from six months ago has
                // decayed to nothing and should not dash today's curve.
                restsOnInferredDose: level > 0 && contributing.contains {
                    $0.isInferred
                        && singleDoseLevel(dose: $0.milligrams,
                                           hoursSince: cursor.timeIntervalSince($0.takenAt) / 3600,
                                           compound: compound) > level * 0.01
                }))
            cursor = cursor.addingTimeInterval(step)
        }
        return out
    }

    /// Trough and peak once a repeated dose has stopped accumulating.
    ///
    /// Reached after roughly four to five elimination half-lives, which for a
    /// weekly injectable is a month or more — the reason a steady dose keeps
    /// feeling stronger for weeks after it stops changing.
    public static func steadyState(dose: Double, everyDays: Int,
                                   compound: GLPCompound) -> (trough: Double, peak: Double) {
        guard dose > 0, everyDays > 0 else { return (0, 0) }
        // Simulate far enough out that accumulation has converged, then read
        // one interval. Closed forms exist for the trough but not for the peak
        // of a Bateman superposition, and simulating both keeps one source of
        // truth rather than two that could disagree.
        let interval = Double(everyDays) * 24
        let horizon = Swift.max(20, Int((compound.eliminationHalfLifeHours * 6) / interval))
        let anchor = Date(timeIntervalSince1970: 0)
        let doses = (0...horizon).map {
            AdministeredDose(takenAt: anchor.addingTimeInterval(Double($0) * interval * 3600),
                             milligrams: dose)
        }
        let lastDose = anchor.addingTimeInterval(Double(horizon) * interval * 3600)
        var peak = 0.0
        var hour = 0.0
        while hour <= interval {
            peak = Swift.max(peak, level(at: lastDose.addingTimeInterval(hour * 3600),
                                         doses: doses, compound: compound))
            hour += 1
        }
        let trough = level(at: lastDose.addingTimeInterval(interval * 3600),
                           doses: doses, compound: compound)
        return (trough, peak)
    }
}

/// Working out the doses somebody probably took before they started logging.
///
/// **Everything this produces is a proposal.** `AdministeredDose.isInferred` is
/// true on every one, the app stores them unconfirmed, and the reader confirms
/// or corrects them in a review step. That is the whole safety posture of this
/// module in one flag: the app may guess out loud, and may not act on its own
/// guess as though the reader had said it.
public enum TitrationEngine {

    /// Walk the ladder backwards from the current dose, one step per
    /// `titrationIntervalDays`, stopping at the start date or the bottom of the
    /// ladder — whichever comes first.
    ///
    /// Returns oldest first, and includes the doses at the current step up to
    /// `now`, so the curve has something to draw between the last inferred
    /// step and today.
    public static func inferHistory(currentDose: Double, compound: GLPCompound,
                                    startedOn: Date, now: Date = Date()) -> [AdministeredDose] {
        let ladder = compound.titrationLadder
        guard startedOn < now,
              let currentIndex = ladder.firstIndex(where: { abs($0 - currentDose) < 1e-9 })
                ?? ladder.lastIndex(where: { $0 < currentDose })
        else { return [] }

        let dosingInterval = Double(compound.dosingIntervalDays) * 86_400
        let stepInterval = Double(compound.titrationIntervalDays) * 86_400

        // When each step began, walking back from now.
        var stepStarts: [(dose: Double, from: Date)] = []
        var index = currentIndex
        var stepStart = now.addingTimeInterval(-stepInterval)
        while index >= 0 {
            let from = Swift.max(stepStart, startedOn)
            stepStarts.append((ladder[index], from))
            if from <= startedOn { break }
            index -= 1
            stepStart = stepStart.addingTimeInterval(-stepInterval)
        }

        var out: [AdministeredDose] = []
        for (offset, step) in stepStarts.enumerated() {
            // Each step runs until the next one begins, or until now. The end
            // is **exclusive** for every step but the most recent: the day a
            // step ends is the day the next one starts, and treating it as
            // both emitted two doses on every boundary — which sorted into a
            // ladder that appeared to go backwards.
            let isCurrentStep = offset == 0
            let until = isCurrentStep ? now : stepStarts[offset - 1].from
            var when = step.from
            while isCurrentStep ? when <= until : when < until {
                out.append(AdministeredDose(takenAt: when, milligrams: step.dose,
                                            isInferred: true))
                when = when.addingTimeInterval(dosingInterval)
            }
        }
        return out.sorted { $0.takenAt < $1.takenAt }
    }
}

/// What a camera scan of a medication box yields.
///
/// The seam exists now so the input layer never has to change when the scanner
/// is written: onboarding depends on the protocol, which a stub satisfies in a
/// sandbox with no camera.
public struct MedicationScanPayload: Sendable, Equatable {
    public let recognisedText: [String]
    public let compound: GLPCompound?
    public let milligrams: Double?
    public let confidence: Double

    public init(recognisedText: [String], compound: GLPCompound?,
                milligrams: Double?, confidence: Double) {
        self.recognisedText = recognisedText
        self.compound = compound
        self.milligrams = milligrams
        self.confidence = confidence
    }

    /// Best-effort reading of already-recognised text. Pure, so the parsing
    /// half is testable without a camera or a Vision framework.
    public static func from(recognisedText lines: [String]) -> MedicationScanPayload {
        let joined = lines.joined(separator: " ").lowercased()
        let compound = GLPCompound.allCases.first { candidate in
            joined.contains(candidate.rawValue)
                || candidate.brandNames.contains { joined.contains($0.lowercased()) }
        }
        // "12.5 mg", "2,5mg", "0.25 mg"
        var milligrams: Double?
        let pattern = #"([0-9]+(?:[.,][0-9]+)?)\s*mg"#
        if let regex = try? NSRegularExpression(pattern: pattern),
           let match = regex.firstMatch(in: joined, range: NSRange(joined.startIndex..., in: joined)),
           let range = Range(match.range(at: 1), in: joined) {
            milligrams = Double(joined[range].replacingOccurrences(of: ",", with: "."))
        }
        let confidence = (compound != nil ? 0.5 : 0) + (milligrams != nil ? 0.5 : 0)
        return MedicationScanPayload(recognisedText: lines, compound: compound,
                                     milligrams: milligrams, confidence: confidence)
    }
}

/// Implemented by a Vision-backed scanner in the app target; stubbed in tests.
public protocol MedicationScanner: Sendable {
    func scan(recognisedText: [String]) async throws -> MedicationScanPayload
}
