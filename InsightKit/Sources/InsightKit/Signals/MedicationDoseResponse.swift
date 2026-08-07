import Foundation

/// **What the drug is doing** — the two questions `MedicationResponse` does not
/// answer, and the one claim this module must never make.
///
/// `MedicationResponse` reads weight against the dose ladder: what changed, how
/// fast, per rung and per site. That leaves two things the reader has asked for
/// and nothing computes:
///
/// 1. **Intake versus expenditure** (backlog `R24`). Both are dated series and
///    `activeMedicationLevel` is a third, so the before/after contrast has the
///    same shape as Substance Impact's with a different pair of quantities. The
///    expected honest finding is *"the drug moved what you eat, not what you
///    burn"* — and it is reported as **two separate deltas**, never one number,
///    because a ratio of the two would silently be a metabolism claim.
/// 2. **Everything folded onto days-since-dose** (backlog `B3-21`). A weekly
///    injection has a within-week shape that the calendar destroys: fourteen
///    doses laid on top of each other say what day three looks like, and a line
///    against real dates says only what happened.
///
/// ## The claim this file exists partly to refuse
///
/// ⚠️ **"Mounjaro speeds up your metabolism" is a claim this must never make.**
/// No such effect is established. A ratio of logged intake to measured
/// expenditure that rises during treatment is far more likely to be a *food log
/// that got worse as appetite fell* than a body that started burning more, and
/// the app cannot tell those apart — so it reports the two series separately and
/// says which of them is self-reported.
///
/// ⚠️ **And Apple's basal energy is not "your metabolism".** It is a formula the
/// phone evaluated from height, weight, age and sex — the
/// modelled-dressed-as-measured failure this app has rules against. This file
/// therefore reads **only** `dietaryEnergy` (what the reader logged) and
/// `activeEnergyBurned` (what the watch measured moving), and there is no basal
/// term anywhere in it. If one is ever added it is a labelled comparator, never
/// a subject.
public enum MedicationDoseResponse {

    /// Standing copy for both sections. Held here, where it is testable, rather
    /// than in whichever view renders it.
    public static let notMetabolism =
        "This is what you logged eating and what your watch measured you burning. "
        + "Neither is a measurement of your metabolism, and nothing here can say a "
        + "GLP-1 speeds one up or slows one down."

    /// The other half of the honesty, and the more likely confound by far.
    public static let intakeIsSelfReported =
        "Intake is what you logged, not what you ate. Appetite falling is exactly "
        + "when a food log gets patchier, so some of any drop here is the logging "
        + "rather than the eating."

    /// How far either side of the first dose the contrast reaches.
    ///
    /// Ninety days, matching `SubstanceResponseAnalyzer.comparisonWindowDays`
    /// and for the same reason: both sides of an acute contrast have to come
    /// from the same stretch of a life, or the comparison measures the years
    /// between them.
    public static let contrastWindowDays = 90.0

    /// Days with a reading, on the thinner side, before a contrast is drawn at
    /// all. Below it there is nothing to compare and the section says so.
    public static let minimumDaysEachSide = 7

    /// How far a mean must move to be called moved: half of the reader's own
    /// day-to-day spread before treatment. Not a published threshold — a
    /// statement that a change smaller than half your own variability is not
    /// something this section will point at.
    public static let movedThresholdSDs = 0.5

    // MARK: - R24: intake versus expenditure

    /// One quantity, before and after the first dose. **Daily totals**, because
    /// both of these are amounts accumulated over a day rather than readings
    /// taken at a moment; a mean over raw samples would report the size of a
    /// typical meal.
    public struct BeforeAfter: Sendable, Equatable, Identifiable {
        public let metric: MetricType
        /// What the reader sees this called. Spelt out rather than taken from
        /// `MetricType.displayName` because "Active energy" and "Dietary
        /// energy" are the store's words, and the section is a sentence about
        /// eating and moving.
        public let label: String
        /// True where the number came from the reader rather than a sensor.
        public let isSelfReported: Bool
        public let beforeMean: Double
        public let afterMean: Double
        public let beforeSD: Double
        public let beforeDays: Int
        public let afterDays: Int

        public var id: MetricType { metric }
        public var delta: Double { afterMean - beforeMean }
        public var percent: Double {
            beforeMean != 0 ? delta / abs(beforeMean) * 100 : 0
        }
        /// The change in the reader's own pre-treatment day-to-day spread.
        /// `nil` where there was no spread to divide by.
        public var z: Double? { beforeSD > 0 ? delta / beforeSD : nil }
        /// Whether this section will call it moved. See `movedThresholdSDs`.
        public var moved: Bool { (z.map { abs($0) } ?? 0) >= movedThresholdSDs }

        public init(metric: MetricType, label: String, isSelfReported: Bool,
                    beforeMean: Double, afterMean: Double, beforeSD: Double,
                    beforeDays: Int, afterDays: Int) {
            self.metric = metric
            self.label = label
            self.isSelfReported = isSelfReported
            self.beforeMean = beforeMean
            self.afterMean = afterMean
            self.beforeSD = beforeSD
            self.beforeDays = beforeDays
            self.afterDays = afterDays
        }
    }

    /// The pair, and the sentence that is honest about them.
    public struct Contrast: Sendable, Equatable {
        public let firstDose: Date
        public let intake: BeforeAfter?
        public let expenditure: BeforeAfter?
        /// What the two deltas together permit saying. Never a mechanism.
        public let sentence: String

        public var rows: [BeforeAfter] { [intake, expenditure].compactMap { $0 } }
        public var hasAnything: Bool { !rows.isEmpty }

        public init(firstDose: Date, intake: BeforeAfter?, expenditure: BeforeAfter?,
                    sentence: String) {
            self.firstDose = firstDose
            self.intake = intake
            self.expenditure = expenditure
            self.sentence = sentence
        }
    }

    /// Intake and expenditure either side of the first dose.
    ///
    /// Returns `nil` when there is no first dose to divide on — a card with no
    /// regimen has no before.
    public static func contrast(doses: [AdministeredDose],
                                samples: [HealthMetricSample],
                                now: Date = Date(),
                                calendar: Calendar = .current) -> Contrast? {
        // Confirmed doses only for the boundary. The whole contrast hangs on
        // *when treatment started*, and `TitrationEngine` will happily propose a
        // history that never happened — a guessed first dose would move the
        // boundary and both means with it.
        guard let first = doses.filter({ !$0.isInferred }).map(\.takenAt).min()
                ?? doses.map(\.takenAt).min() else { return nil }

        let intake = beforeAfter(metric: .dietaryEnergy, label: "What you ate",
                                 isSelfReported: true, firstDose: first,
                                 samples: samples, now: now, calendar: calendar)
        let expenditure = beforeAfter(metric: .activeEnergyBurned, label: "What you burned moving",
                                      isSelfReported: false, firstDose: first,
                                      samples: samples, now: now, calendar: calendar)
        return Contrast(firstDose: first, intake: intake, expenditure: expenditure,
                        sentence: sentence(intake: intake, expenditure: expenditure))
    }

    /// **The one sentence, and every arm of it refuses a mechanism.**
    ///
    /// The expected shape on this reader's record is intake down, expenditure
    /// flat — which is a fact about two logs and reads naturally as "the drug
    /// moved what you eat, not what you burn". That wording is used only when
    /// the data actually shows it, and it still says *on your own log*.
    static func sentence(intake: BeforeAfter?, expenditure: BeforeAfter?) -> String {
        switch (intake, expenditure) {
        case (nil, nil):
            return "There isn't a logged stretch on both sides of your first dose yet. "
                + "Once there are \(minimumDaysEachSide) days of food or activity either "
                + "side, this shows what each of them did — separately."
        case (let i?, nil):
            return "Only your food log reaches both sides of your first dose, so this can "
                + "say what you ate and nothing about what you burned. "
                + changeClause(i) + " " + intakeIsSelfReported
        case (nil, let e?):
            return "Only your activity reaches both sides of your first dose, so this can "
                + "say what you burned moving and nothing about what you ate. "
                + changeClause(e)
                + " What you move is also what you chose to do that day."
        case (let i?, let e?):
            if i.moved && !e.moved {
                return "On your own log the drug moved what you eat, not what you burn: "
                    + changeClause(i).lowercasedFirst + " while what you burned moving "
                    + "stayed inside your usual day-to-day range. " + intakeIsSelfReported
            }
            if e.moved && !i.moved {
                return "What you burned moving changed and what you logged eating did not: "
                    + changeClause(e).lowercasedFirst
                    + " That is what you chose to do with your days as much as anything "
                    + "the drug did. " + intakeIsSelfReported
            }
            if i.moved && e.moved {
                return "Both moved. \(changeClause(i)) \(changeClause(e)) "
                    + "They are reported separately on purpose — one number combining them "
                    + "would be a claim about your metabolism, which neither of these "
                    + "measures. " + intakeIsSelfReported
            }
            return "Neither moved by more than your own day-to-day spread before you "
                + "started. \(changeClause(i)) \(changeClause(e)) " + intakeIsSelfReported
        }
    }

    static func changeClause(_ row: BeforeAfter) -> String {
        let direction = row.delta >= 0 ? "up" : "down"
        return String(format: "%@ is %@ %.0f kcal a day (%.0f → %.0f, %d days before, %d after).",
                      row.label, direction, abs(row.delta),
                      row.beforeMean, row.afterMean, row.beforeDays, row.afterDays)
    }

    static func beforeAfter(metric: MetricType, label: String, isSelfReported: Bool,
                            firstDose: Date, samples: [HealthMetricSample],
                            now: Date, calendar: Calendar) -> BeforeAfter? {
        let window = contrastWindowDays * 86_400
        let series = samples.samples(of: metric)
            .filter { $0.start >= firstDose.addingTimeInterval(-window) && $0.start <= now }
        guard !series.isEmpty else { return nil }

        let before = dailyTotals(series.filter { $0.start < firstDose }, calendar: calendar)
        let after = dailyTotals(series.filter { $0.start >= firstDose }, calendar: calendar)
        guard before.count >= minimumDaysEachSide, after.count >= minimumDaysEachSide,
              let b = Baseline.mean(before), let a = Baseline.mean(after) else { return nil }
        return BeforeAfter(metric: metric, label: label, isSelfReported: isSelfReported,
                           beforeMean: b, afterMean: a,
                           beforeSD: Baseline.standardDeviation(before) ?? 0,
                           beforeDays: before.count, afterDays: after.count)
    }

    /// Sum per calendar day, oldest first. Energy is accumulated, not sampled.
    static func dailyTotals(_ series: [HealthMetricSample],
                            calendar: Calendar) -> [Double] {
        Dictionary(grouping: series) { calendar.startOfDay(for: $0.start) }
            .sorted { $0.key < $1.key }
            .map { $0.value.reduce(0) { $0 + $1.value } }
    }

    // MARK: - B3-21: folded onto days since dose

    /// One day of the dose cycle, for one metric.
    public struct DayBin: Sendable, Equatable, Identifiable {
        /// Whole days since the dose that preceded these readings. 0 is dose day.
        public let offset: Int
        public let mean: Double
        /// Spread *between doses* at this offset — how alike the fourteen day-3s
        /// were. `nil` at one contributing dose, where there is no spread.
        public let sd: Double?
        /// **How many doses put a reading in this bin.** On the figure, always:
        /// a mean of two doses and a mean of fourteen look identical on a chart
        /// and are not the same claim.
        public let doses: Int
        public let readings: Int

        public var id: Int { offset }

        public init(offset: Int, mean: Double, sd: Double?, doses: Int, readings: Int) {
            self.offset = offset
            self.mean = mean
            self.sd = sd
            self.doses = doses
            self.readings = readings
        }
    }

    /// One metric folded onto the cycle.
    public struct Fold: Sendable, Equatable, Identifiable {
        public let metric: MetricType
        public let bins: [DayBin]
        /// Doses that contributed anything at all.
        public let doseCount: Int
        /// Mean across the whole treated stretch — the flat line the shape is
        /// read against.
        public let treatedMean: Double
        /// Day-to-day spread across the treated stretch, so a swing can be
        /// stated in the reader's own units of ordinary variation.
        public let treatedSD: Double

        public var id: MetricType { metric }

        /// The biggest departure from the treated mean, in the reader's own
        /// spreads. `nil` where there is no spread to divide by.
        public var swingInSDs: Double? {
            guard treatedSD > 0, let hi = bins.map(\.mean).max(),
                  let lo = bins.map(\.mean).min() else { return nil }
            return (hi - lo) / treatedSD
        }

        /// The thinnest bin, which is what the whole shape is only as good as.
        public var weakestBinDoses: Int { bins.map(\.doses).min() ?? 0 }

        public init(metric: MetricType, bins: [DayBin], doseCount: Int,
                    treatedMean: Double, treatedSD: Double) {
            self.metric = metric
            self.bins = bins
            self.doseCount = doseCount
            self.treatedMean = treatedMean
            self.treatedSD = treatedSD
        }
    }

    /// Side-effect records folded the same way — counts, not severities.
    ///
    /// A mean severity per day-offset would be an average of nine numbers spread
    /// over seven bins, which is one or two records a bin. Counting is the only
    /// honest arithmetic at that n, and the count is on the figure.
    public struct SideEffectFold: Sendable, Equatable {
        public let counts: [Int]     // index == day offset
        public let doseCount: Int
        public let recordCount: Int

        public var cycleDays: Int { counts.count }
        public var busiestOffset: Int? {
            guard let peak = counts.max(), peak > 0 else { return nil }
            return counts.firstIndex(of: peak)
        }

        public init(counts: [Int], doseCount: Int, recordCount: Int) {
            self.counts = counts
            self.doseCount = doseCount
            self.recordCount = recordCount
        }
    }

    /// How long the reader's own cycle is, from their own doses.
    ///
    /// The median gap rather than the compound's label: a weekly injection taken
    /// a day late half the time is still one cycle, and rounding each gap to the
    /// median is what folds them onto the same axis. Clamped to 1…14 days —
    /// below one there is no cycle and above fourteen the bins are emptier than
    /// they are informative.
    public static func cycleDays(doses: [AdministeredDose]) -> Int? {
        let times = doses.map(\.takenAt).sorted()
        guard times.count >= 2 else { return nil }
        let gaps = zip(times, times.dropFirst()).map { $1.timeIntervalSince($0) / 86_400 }
        guard let median = Baseline.median(gaps) else { return nil }
        return min(14, max(1, Int(median.rounded())))
    }

    /// Every metric folded onto days-since-dose.
    ///
    /// Metrics with nothing to say are dropped rather than drawn empty: a bin
    /// needs at least one reading, and a fold needs a reading in more than one
    /// bin or it is a single point pretending to be a shape.
    public static func folds(doses: [AdministeredDose],
                             samples: [HealthMetricSample],
                             metrics: [MetricType],
                             now: Date = Date(),
                             calendar: Calendar = .current) -> [Fold] {
        guard let cycle = cycleDays(doses: doses) else { return [] }
        let times = doses.map(\.takenAt).sorted().filter { $0 <= now }
        guard let first = times.first else { return [] }

        return metrics.compactMap { metric -> Fold? in
            let series = samples.samples(of: metric)
                .filter { $0.start >= first && $0.start <= now }
            guard series.count >= cycle else { return nil }

            // (offset, dose index) → values. The dose index is kept so a bin can
            // report how many *doses* it rests on rather than how many readings,
            // which for heart rate differ by three orders of magnitude.
            var grouped: [Int: [Int: [Double]]] = [:]
            for sample in series {
                guard let doseIndex = times.lastIndex(where: { $0 <= sample.start }) else { continue }
                let offset = Int(sample.start.timeIntervalSince(times[doseIndex]) / 86_400)
                guard offset >= 0, offset < cycle else { continue }
                grouped[offset, default: [:]][doseIndex, default: []].append(sample.value)
            }
            guard grouped.count >= 2 else { return nil }

            let bins: [DayBin] = grouped.keys.sorted().compactMap { offset in
                guard let perDose = grouped[offset] else { return nil }
                // Mean of per-dose means, not of every reading: a dose day the
                // reader happened to wear the watch for longer would otherwise
                // outvote the other thirteen.
                let doseMeans = perDose.values.compactMap { Baseline.mean($0) }
                guard let mean = Baseline.mean(doseMeans) else { return nil }
                return DayBin(offset: offset, mean: mean,
                              sd: doseMeans.count >= 2 ? Baseline.standardDeviation(doseMeans) : nil,
                              doses: perDose.count,
                              readings: perDose.values.reduce(0) { $0 + $1.count })
            }
            guard bins.count >= 2, let treated = Baseline.mean(series.map(\.value)) else { return nil }
            return Fold(metric: metric, bins: bins,
                        doseCount: Set(grouped.values.flatMap { $0.keys }).count,
                        treatedMean: treated,
                        treatedSD: Baseline.standardDeviation(series.map(\.value)) ?? 0)
        }
        // Biggest within-cycle swing first, so the metric with a shape leads and
        // the flat ones sit below it.
        .sorted { ($0.swingInSDs ?? 0) > ($1.swingInSDs ?? 0) }
    }

    /// Side effects on the same axis.
    public static func sideEffectFold(doses: [AdministeredDose],
                                      effects: [(name: String, severity: Int, date: Date)],
                                      now: Date = Date()) -> SideEffectFold? {
        guard let cycle = cycleDays(doses: doses) else { return nil }
        let times = doses.map(\.takenAt).sorted().filter { $0 <= now }
        guard !times.isEmpty else { return nil }

        var counts = Array(repeating: 0, count: cycle)
        var used: Set<Int> = []
        var recorded = 0
        for effect in effects where effect.date <= now {
            guard let index = times.lastIndex(where: { $0 <= effect.date }) else { continue }
            let offset = Int(effect.date.timeIntervalSince(times[index]) / 86_400)
            guard offset >= 0, offset < cycle else { continue }
            counts[offset] += 1
            used.insert(index)
            recorded += 1
        }
        guard recorded > 0 else { return nil }
        return SideEffectFold(counts: counts, doseCount: used.count, recordCount: recorded)
    }
}

extension String {
    /// Lowercases only the first character, for a clause being spliced mid-
    /// sentence. `lowercased()` would flatten "Mounjaro" too.
    var lowercasedFirst: String {
        guard let first else { return self }
        return first.lowercased() + dropFirst()
    }
}
