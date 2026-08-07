import Foundation

/// **What, out of everything the app already works out, moves this reader's
/// sleep.**
///
/// The reader, 2026-08-07: *"I want a dedicated bespoke section for 'what is
/// impacting your sleep' … this is where we can finally start using the derived
/// outcomes of cards to build new cards and sections like this."*
///
/// Every card has declared its figures as `DerivedSeriesID`s since 2026-08-06
/// and nothing had yet *consumed* that pool. This is the first thing that does:
/// work exposure, stress channels, mental-health departures, screen time,
/// caffeine, calendar load — all of them are already days-by-value series in
/// `DerivedSeriesStore`, and `value(_:on:)` is exactly the join a cross-card
/// association needs.
///
/// ---
///
/// # ⚠️ The statistics are the hard part, and this repo has been burnt here
///
/// An independent review refuted the substance card's confirmation design on
/// this reader's own record. Four separate faults, each of which alone would
/// have produced a confident wrong answer:
///
/// | What went wrong | What it did | What is done here |
/// | --- | --- | --- |
/// | **Same-day activity omitted** | heart rate's apparent effect fell from min\|z\| 0.91 to **0.03** once step count entered the model | activity is a covariate in *every* test, never optional |
/// | **Permutation null ~2× anti-conservative** | i.i.d. shuffling destroyed the autocorrelation the real series has, so the null was far too narrow | **circular block** permutation, block ≈ a week |
/// | **BH invalid** under measured negative dependence (r = −0.795) | false-discovery control assuming positive dependence, applied to negatively dependent tests | **max-statistic (Westfall–Young) FWER**, valid under arbitrary dependence |
/// | **Findings flipped on the day boundary** | the boundary was effectively a free parameter | the boundary is fixed below, before any data is read |
///
/// Everything in this file exists because of one of those four rows.
///
/// ## The day boundary, fixed in advance
///
/// **A driver's value on waking day D is held against the night that begins that
/// evening** — the night `SleepOnset` keys to the morning of D+1. That is the
/// direction the reader asked about: what today did to tonight's sleep. It is
/// stated here, applied to every driver identically, and never varied to see
/// which way gives more findings.
///
/// ## Why the null is a circular block shift
///
/// Both the outcome and the drivers are autocorrelated — a heavy work week is
/// heavy on Tuesday *and* Wednesday, and sleep debt carries across nights.
/// Shuffling days independently produces a null distribution far narrower than
/// the truth, so ordinary-looking correlations clear it. A **circular shift of
/// the whole driver series** keeps every bit of its own autocorrelation and
/// destroys only its alignment with the outcome, which is precisely the null
/// hypothesis being tested. Shifts are drawn away from zero and from the series
/// ends so a "shifted" series is never nearly the original.
///
/// ## Why the multiplicity control is max-statistic and not BH
///
/// Under the **same** shift, every driver is permuted together, and the largest
/// statistic across all of them is recorded. The p-value for a driver is the
/// share of permutations whose *maximum* beat it. That controls the family-wise
/// error rate under any dependence structure between drivers, positive or
/// negative — which is the exact property BH does not have and which the
/// measured r = −0.795 between two of this reader's channels violated.
///
/// ## The output that is expected most of the time
///
/// `.nothingStandsOut`. Most weeks nothing has happened often enough to tell it
/// from an ordinary run, and saying so is the correct result, not a failure of
/// the section.
public enum SleepInfluences {

    // MARK: - Inputs

    /// One candidate influence: a name, and its value per waking day.
    public struct Driver: Sendable, Equatable, Identifiable {
        /// Stable identity — a `DerivedSeriesID.rawValue` for a card's figure,
        /// or a `MetricType.rawValue` for a measured one.
        public let id: String
        public let name: String
        /// The card this came from, where it came from a card. Shown so the
        /// reader can see the section is built out of their other cards.
        public let producedBy: InsightID?
        public let unit: String
        /// Day (start of day) to value. The day is the **waking** day.
        public let values: [VitalReader.DailyValue]

        public init(id: String, name: String, producedBy: InsightID? = nil,
                    unit: String = "", values: [VitalReader.DailyValue]) {
            self.id = id
            self.name = name
            self.producedBy = producedBy
            self.unit = unit
            self.values = values
        }
    }

    // MARK: - Thresholds, all fixed before the data is seen

    /// Paired nights a driver needs before it is tested at all.
    ///
    /// Thirty. Below that a partial correlation with two covariates is being
    /// fitted on fewer than ten observations per parameter, and the review's
    /// central lesson is that such a fit is not a weak finding — it is an
    /// arbitrary one.
    public static let minimumPairs = 30
    /// Permutations. Two thousand, so the smallest reportable p-value is
    /// 1/2001 ≈ 0.0005 and the resolution near 0.05 is fine enough that the
    /// verdict does not depend on the count.
    public static let permutations = 2_000
    /// Block length for the circular shift, in days. Seven, so a whole weekly
    /// rhythm moves as one and the shift cannot align a Monday with a Monday.
    public static let blockDays = 7
    /// Family-wise error rate the findings are held to.
    public static let alpha = 0.05
    /// How much of a driver's own movement must survive the covariates before it
    /// is worth testing, as a share of its variance.
    ///
    /// ⚠️ **This is the collinearity guard, and it is not a nicety.** A driver
    /// that *is* the day's activity in other units has residuals of the order of
    /// floating-point error after adjustment — and two vectors of rounding error
    /// from the same computation correlate at nearly 1.0. Without this floor the
    /// model reports a perfect finding for a quantity it has just proved carries
    /// no information of its own. A tenth: at least 10% of the driver's variance
    /// has to be something other than how much the reader moved that day.
    public static let minimumTolerance = 0.10

    // MARK: - Output

    public struct Finding: Sendable, Equatable, Identifiable {
        public let driverID: String
        public let name: String
        public let producedBy: InsightID?
        /// Partial correlation with the night's outcome, after the covariates.
        /// Signed as measured: negative means more of this, less of the outcome.
        public let partialR: Double
        /// The outcome's own units, per one standard deviation of the driver
        /// **after the covariates** — the variation this test actually had to
        /// work with, not the raw spread, which the activity adjustment has
        /// already taken a share of. The figure worth printing: a correlation is
        /// not a quantity anybody can act on.
        public let effectPerSD: Double
        /// Family-wise adjusted p. Never a raw per-test p: printing one would
        /// invite exactly the multiplicity error this design refuses.
        public let adjustedP: Double
        public let pairs: Int

        public var id: String { driverID }
    }

    /// Why a candidate never entered the family. Reported rather than swallowed:
    /// "we could not look at this" and "we looked and found nothing" are
    /// different sentences and the reader is owed the right one.
    public enum Untestable: Sendable, Equatable {
        case tooFewDays(Int)
        /// Ruled out by `minimumTolerance` — this quantity is very nearly the
        /// day's activity wearing another name.
        case alreadyExplainedByYourActivity
        /// Flat, or otherwise with no spread to correlate.
        case noVariation
    }

    public struct Untested: Sendable, Equatable, Identifiable {
        public let id: String
        public let name: String
        public let reason: Untestable

        public var sentence: String {
            switch reason {
            case let .tooFewDays(days):
                return "\(name) (\(days) \(days == 1 ? "day" : "days"))"
            case .alreadyExplainedByYourActivity:
                return "\(name) (almost entirely explained by how active you were)"
            case .noVariation:
                return "\(name) (barely moved)"
            }
        }
    }

    public enum Verdict: Sendable, Equatable {
        /// At least one driver cleared the family-wise threshold.
        case found
        /// Enough days, enough drivers, and nothing cleared it.
        case nothingStandsOut
        /// No driver had enough paired days to be worth testing.
        case notEnoughDays(bestPairs: Int, need: Int)
        /// Candidates had the days but none of them survived the covariates —
        /// which is itself a finding: everything on offer was the day's activity
        /// in other clothes.
        case nothingTestable
        /// Nothing to test against — no outcome series, or no drivers at all.
        case nothingToCompare
    }

    public struct Output: Sendable, Equatable {
        public let outcomeName: String
        public let outcomeUnit: String
        public let findings: [Finding]
        /// How many drivers actually entered the family. The denominator of the
        /// multiplicity correction, and the number the section must print — a
        /// reader cannot judge "one finding" without knowing it came out of
        /// four candidates or forty.
        public let tested: Int
        /// Candidates that had data and never entered the family, each with the
        /// reason.
        public let untested: [Untested]
        public let verdict: Verdict
        public let span: ClosedRange<Date>?
    }

    // MARK: - The test

    /// Hold every driver against the night that followed it.
    ///
    /// - Parameters:
    ///   - outcome: one value per **night key** (the morning it ends on).
    ///   - activity: the same-day activity covariate — step count or active
    ///     energy, per waking day. **Required, not optional**: a day with no
    ///     activity reading is dropped rather than tested unadjusted, and an
    ///     empty `activity` therefore yields no findings at all rather than a
    ///     full set of unadjusted ones. That is deliberate and it is the single
    ///     fault that collapsed the substance finding from min|z| 0.91 to 0.03 —
    ///     a section with nothing in it is recoverable, a section confidently
    ///     naming an artefact is not.
    ///   - seed: fixes the permutation draw so the same data gives the same
    ///     answer on every launch. A section whose findings flicker between
    ///     redraws is worse than one with no findings.
    public static func evaluate(outcome: [VitalReader.DailyValue],
                                outcomeName: String,
                                outcomeUnit: String,
                                drivers: [Driver],
                                activity: [VitalReader.DailyValue],
                                seed: UInt64 = 0x5EED_51EE_9,
                                calendar: Calendar = .current) -> Output {
        let span = outcome.map(\.date).min().flatMap { low in
            outcome.map(\.date).max().map { low...Swift.max(low, $0) }
        }
        guard !outcome.isEmpty, !drivers.isEmpty else {
            return Output(outcomeName: outcomeName, outcomeUnit: outcomeUnit,
                          findings: [], tested: 0, untested: [],
                          verdict: .nothingToCompare, span: span)
        }

        var outcomeByNight: [Date: Double] = [:]
        for point in outcome {
            outcomeByNight[calendar.startOfDay(for: point.date)] = point.value
        }
        var activityByDay: [Date: Double] = [:]
        for point in activity {
            activityByDay[calendar.startOfDay(for: point.date)] = point.value
        }

        /// The night that begins on the evening of waking day `day` — keyed to
        /// the morning after. **The day boundary, in one function**, so it is
        /// impossible for two drivers to be joined differently.
        func nightAfter(_ day: Date) -> Date {
            calendar.startOfDay(for: day.addingTimeInterval(86_400 + 3_600))
        }

        // MARK: Build one aligned table per driver

        struct Prepared {
            let driver: Driver
            /// Residual outcome and residual driver, same order, covariates
            /// already projected out of both.
            let outcomeResiduals: [Double]
            let driverResiduals: [Double]
            let driverSD: Double
            let pairs: Int
        }

        var prepared: [Prepared] = []
        var untested: [Untested] = []

        for driver in drivers {
            var days: [Date] = []
            var xs: [Double] = []
            var ys: [Double] = []
            var covariates: [[Double]] = []
            for point in driver.values.sorted(by: { $0.date < $1.date }) {
                let day = calendar.startOfDay(for: point.date)
                guard let y = outcomeByNight[nightAfter(day)] else { continue }
                // The covariate row: an intercept, that day's activity, and
                // whether the night ahead is a no-alarm one. The weekend term is
                // here for the same reason `IdealSleepWindow` de-means by day
                // type — late nights and free mornings travel together.
                guard let steps = activityByDay[day] else {
                    // A day with no activity reading cannot be adjusted for
                    // activity, and adjusting some days and not others is the
                    // omitted-variable fault applied selectively. Dropped.
                    continue
                }
                days.append(day)
                xs.append(point.value)
                ys.append(y)
                covariates.append([1, steps,
                                   calendar.isDateInWeekend(nightAfter(day)) ? 1 : 0])
            }

            guard xs.count >= minimumPairs else {
                if !xs.isEmpty {
                    untested.append(Untested(id: driver.id, name: driver.name,
                                             reason: .tooFewDays(xs.count)))
                }
                continue
            }
            guard let xResid = residuals(of: xs, on: covariates),
                  let yResid = residuals(of: ys, on: covariates),
                  let rawSD = Baseline.standardDeviation(xs), rawSD > 0,
                  let sd = Baseline.standardDeviation(xResid), sd > 0 else {
                untested.append(Untested(id: driver.id, name: driver.name,
                                         reason: .noVariation))
                continue
            }
            // The collinearity guard — see `minimumTolerance`. A driver whose
            // movement is the day's activity in other units has residuals made
            // of rounding error, and two rounding-error vectors from the same
            // computation correlate at nearly one.
            guard (sd * sd) / (rawSD * rawSD) >= minimumTolerance else {
                untested.append(Untested(id: driver.id, name: driver.name,
                                         reason: .alreadyExplainedByYourActivity))
                continue
            }
            prepared.append(Prepared(driver: driver, outcomeResiduals: yResid,
                                     driverResiduals: xResid, driverSD: sd,
                                     pairs: xs.count))
        }

        guard !prepared.isEmpty else {
            // "Nobody had enough days" and "everybody had enough days and none
            // of them was anything but the day's activity" are different
            // answers, and reporting the first for the second would send the
            // reader off to record more of something that is already there.
            let dayCounts = untested.compactMap { untested -> Int? in
                if case let .tooFewDays(days) = untested.reason { return days }
                return nil
            }
            return Output(outcomeName: outcomeName, outcomeUnit: outcomeUnit,
                          findings: [], tested: 0, untested: untested,
                          verdict: dayCounts.isEmpty
                              ? .nothingTestable
                              : .notEnoughDays(bestPairs: dayCounts.max() ?? 0,
                                               need: minimumPairs),
                          span: span)
        }

        // MARK: Observed statistics

        let observed = prepared.map { item -> Double in
            abs(Baseline.correlation(x: item.driverResiduals, y: item.outcomeResiduals) ?? 0)
        }

        // MARK: The null — one shift, applied to every driver at once
        //
        // Shifting them **together** is what makes the max statistic valid under
        // dependence: the permuted family keeps whatever correlation the drivers
        // have with each other, so the null distribution of the maximum is the
        // null distribution of the maximum of *these* tests and not of some
        // independent ones.
        var rng = SplitMix64(seed: seed)
        var exceedances = [Int](repeating: 0, count: prepared.count)
        let shortest = prepared.map(\.pairs).min() ?? 0
        for _ in 0..<permutations {
            // A shift of at least one block and no closer than one block to a
            // full turn, so the shifted series never nearly re-aligns.
            let usable = Swift.max(1, shortest - 2 * blockDays)
            let shift = blockDays + Int(rng.next() % UInt64(usable))
            var maximum = 0.0
            for item in prepared {
                let rotated = rotate(item.driverResiduals, by: shift)
                let r = abs(Baseline.correlation(x: rotated, y: item.outcomeResiduals) ?? 0)
                maximum = Swift.max(maximum, r)
            }
            for (index, value) in observed.enumerated() where maximum >= value {
                exceedances[index] += 1
            }
        }

        var findings: [Finding] = []
        for (index, item) in prepared.enumerated() {
            // `(exceedances + 1) / (permutations + 1)` — the observed
            // arrangement is one of the arrangements under the null, so it
            // belongs in both counts. Leaving it out is how a permutation test
            // reports p = 0, which is never true.
            let p = Double(exceedances[index] + 1) / Double(permutations + 1)
            guard p <= alpha else { continue }
            let r = Baseline.correlation(x: item.driverResiduals,
                                         y: item.outcomeResiduals) ?? 0
            // Slope of outcome-residual on driver-residual, scaled to one SD of
            // the driver as it is actually measured.
            let slope = Baseline.linearRegression(x: item.driverResiduals,
                                                  y: item.outcomeResiduals)?.slope ?? 0
            findings.append(Finding(driverID: item.driver.id, name: item.driver.name,
                                    producedBy: item.driver.producedBy,
                                    partialR: r, effectPerSD: slope * item.driverSD,
                                    adjustedP: p, pairs: item.pairs))
        }
        findings.sort { abs($0.effectPerSD) > abs($1.effectPerSD) }

        return Output(outcomeName: outcomeName, outcomeUnit: outcomeUnit,
                      findings: findings, tested: prepared.count, untested: untested,
                      verdict: findings.isEmpty ? .nothingStandsOut : .found,
                      span: span)
    }

    // MARK: - Arithmetic

    /// Residuals of `y` after least squares on `design`.
    ///
    /// Normal equations with a Gaussian solve. The design is three columns wide
    /// and will not grow — the constraint is deliberate, since every extra
    /// covariate on thirty-odd days buys collinearity rather than adjustment.
    static func residuals(of y: [Double], on design: [[Double]]) -> [Double]? {
        guard let width = design.first?.count, y.count == design.count,
              y.count > width else { return nil }
        var xtx = [[Double]](repeating: [Double](repeating: 0, count: width), count: width)
        var xty = [Double](repeating: 0, count: width)
        for (row, value) in zip(design, y) {
            for i in 0..<width {
                xty[i] += row[i] * value
                for j in 0..<width { xtx[i][j] += row[i] * row[j] }
            }
        }
        guard let beta = solve(xtx, xty) else { return nil }
        return zip(design, y).map { row, value in
            value - zip(row, beta).reduce(0) { $0 + $1.0 * $1.1 }
        }
    }

    /// Gaussian elimination with partial pivoting. `nil` on a singular system —
    /// which is the honest answer when a covariate never varies (a reader with
    /// no step data at all, say), rather than a fitted value from a pseudo
    /// inverse nobody asked for.
    static func solve(_ matrix: [[Double]], _ rhs: [Double]) -> [Double]? {
        var a = matrix
        var b = rhs
        let n = b.count
        for column in 0..<n {
            var pivot = column
            for row in (column + 1)..<n where abs(a[row][column]) > abs(a[pivot][column]) {
                pivot = row
            }
            guard abs(a[pivot][column]) > 1e-10 else { return nil }
            if pivot != column { a.swapAt(pivot, column); b.swapAt(pivot, column) }
            for row in (column + 1)..<n {
                let factor = a[row][column] / a[column][column]
                guard factor != 0 else { continue }
                for col in column..<n { a[row][col] -= factor * a[column][col] }
                b[row] -= factor * b[column]
            }
        }
        var out = [Double](repeating: 0, count: n)
        for row in stride(from: n - 1, through: 0, by: -1) {
            var sum = b[row]
            for col in (row + 1)..<n { sum -= a[row][col] * out[col] }
            out[row] = sum / a[row][row]
        }
        return out.allSatisfy(\.isFinite) ? out : nil
    }

    static func rotate(_ xs: [Double], by shift: Int) -> [Double] {
        guard !xs.isEmpty else { return xs }
        let k = ((shift % xs.count) + xs.count) % xs.count
        guard k != 0 else { return xs }
        return Array(xs[k...] + xs[..<k])
    }

    /// A tiny deterministic generator, so the permutation null is reproducible.
    ///
    /// `SystemRandomNumberGenerator` would make the section's findings depend on
    /// the launch, which for a claim about the reader's health is unacceptable —
    /// and it would make the tests below unwritable.
    struct SplitMix64 {
        private var state: UInt64
        init(seed: UInt64) { state = seed }
        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
    }
}
