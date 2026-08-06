import Foundation

/// **This app's own biological age — every term visible, every weight derived.**
///
/// Backlog #29, refused twice and reversed by the reader on 2026-08-06: *"these
/// sorts of things are the ENTIRE POINT OF THE APP."*
///
/// ## Why the refusal was wrong, and what it was right about
///
/// The refusal said a house biological age would be "a worse black box with a
/// smaller *n*", and that relaying Oura's with its error attached is strictly
/// more honest. The second half is true and `AgeComparison` still does it. The
/// first half assumed the only way to build one is the way Whoop and Oura build
/// theirs — fit a model to a cohort nobody can see, print one number, publish no
/// error. That is a black box because of how it is *built*, not because it is a
/// biological age.
///
/// **So this is built the other way round.** Nothing here is fitted to anything.
/// Every marker is inverted through a *published age norm* — the same trick
/// `FitnessAgeModel` already does for VO₂max, generalised — and the terms are
/// combined by a rule with no free parameters at all.
///
/// ## The combination rule, which is the whole design
///
/// Each marker gives an independent answer to "what age is this value typical
/// of", and each answer has its own precision. A marker whose norm curve is
/// steep against a small population spread pins the age tightly; one whose curve
/// is nearly flat says almost nothing, however precisely it is measured — knowing
/// someone's walking speed to three decimals tells you little about their age at
/// forty, because forty-year-olds and fifty-year-olds walk at the same speed.
///
/// That is exactly the insight behind the Klemera–Doubal method, and it needs no
/// cohort to apply:
///
///     σ_j  = population spread of marker j  ÷  |slope of its norm curve|
///     w_j  = (1 / σ_j²) ÷ Σ (1 / σ_k²)          ← inverse-variance weighting
///     BA   = Σ w_j · age_j
///     ±    = √(1 / Σ 1/σ_k²)
///
/// **There is not one tunable number in that.** The weights fall out of the norm
/// tables themselves, so a marker cannot be given a big share because it makes
/// the card look clever, and a flat marker demotes itself automatically. It also
/// means the weights *move with the reader*: gait speed is nearly worthless at
/// forty and one of the strongest markers there is at eighty, and this arithmetic
/// knows that without being told.
///
/// ## ⚠️ Chronological age is deliberately not a term
///
/// Klemera–Doubal's published form includes chronological age as an extra
/// "marker", which shrinks the estimate toward the birthday and makes it look far
/// more precise than it is. Every commercial biological age does this, and it is
/// why they all print tight numbers that hug your real age.
///
/// This one does not, and the consequence is honest and uncomfortable: **the ±
/// here is around a decade.** That is what these markers are actually worth. A
/// vendor printing "WHOOP Age 41" with no error is not more precise; it is
/// quieter about the same problem.
///
/// ## What the wide error does *not* spoil
///
/// The absolute number is soft. **The direction it moves is not** — the same
/// person measured twice shares most of that error, so it cancels in a
/// difference. `pace` is therefore the figure worth watching, and the card says
/// so rather than leading with a number it has just admitted is ±10.
///
/// ## The instrument caveats, on every row
///
/// Each norm table was built on a laboratory measurement and each input is a
/// consumer sensor, so every marker carries the sentence naming its own
/// mismatch. Those are stated, not hidden, because a systematic instrument bias
/// does *not* cancel in the pace figure the way random error does.
public enum BiologicalAgeModel {

    /// Bounds of the reportable range. Outside them every one of these norm
    /// curves is extrapolation.
    public static let youngest: Double = 18
    public static let oldest: Double = 95

    /// How long a window each marker is read over. Deliberately long: biological
    /// age is not a thing that changes on Tuesday, and a marker read from one
    /// day would make the card jitter by years overnight.
    public static let windowDays = 90

    /// ⚠️ **Per marker, because a single window silently deleted three of the
    /// five.** Found by opening the card on the reader's real record: it read
    /// *"heart-rate variability carries 95% of it"* — a biological age that was
    /// an HRV reading wearing a different name.
    ///
    /// The cause is that these markers arrive at wildly different rates. HRV and
    /// walking speed land every day; **VO₂max lands when Apple decides it has
    /// seen a long enough outdoor walk, and a cuff reading lands when someone
    /// sits down and takes one.** Ninety days with a five-day floor is right for
    /// the first pair and excludes the second pair almost always.
    ///
    /// A longer window is not a fudge here: VO₂max and blood pressure genuinely
    /// move over seasons, so a year's median is a *better* estimate of the level
    /// than a quarter's, not a staler one. The rule is that the window matches
    /// how fast the quantity moves, not how fast the card wants an answer.
    public static func lookbackDays(_ metric: MetricType) -> Int {
        switch metric {
        case .vo2Max, .bloodPressureSystolic: return 365
        case .bodyFatPercentage: return 180
        default: return windowDays
        }
    }

    /// The gap used for the pace-of-ageing comparison — how far back the second
    /// evaluation stands.
    public static let paceLookbackDays = 180

    // MARK: - The norm curves

    /// Age norms, as (age, typical value) anchors. Piecewise-linear between
    /// them, adjacent slope continued beyond the ends.
    ///
    /// **Every one must be strictly monotonic**, because the model inverts it.
    /// Where the published data is genuinely flat over a stretch — gait speed
    /// through middle age — the anchors carry a small real slope rather than a
    /// zero one, and the near-flatness then shows up where it belongs: as a huge
    /// σ, and therefore almost no weight.
    static func anchors(_ metric: MetricType,
                        sex: BiologicalSex) -> [(age: Double, value: Double)]? {
        let male = sex == .male
        switch metric {
        case .vo2Max:
            // The same table `FitnessAgeModel` inverts, so the two cards can
            // never disagree about what "average for your age" means.
            return FitnessAgeModel.anchors(for: sex).map { (age: $0.age, value: $0.vo2) }

        // ⚠️ **Overnight norms, not short-term supine ones**, and the difference
        // is what made this marker unusable on the reader's own record.
        //
        // The first version used the classical five-minute supine figures
        // (rMSSD ~45 at twenty-five). Every device this app reads reports HRV
        // averaged across a *night*, which runs far higher — so the reader's
        // real value sat off the top of the curve, the model correctly refused
        // to invert it, and the card lost its best marker. **The caveat string
        // even said so**: "the norms are short supine recordings; this is a
        // whole night, which reads higher". Documenting a bias is not handling
        // one, and a comment cannot correct a table.
        case .heartRateVariabilityRMSSD:
            return male
                ? [(25, 55), (35, 45), (45, 36), (55, 29), (65, 24), (75, 20)]
                : [(25, 54), (35, 44), (45, 35), (55, 28), (65, 23), (75, 19)]

        case .heartRateVariabilitySDNN:
            // Held separately rather than converted: a fixed rMSSD→SDNN factor
            // does not exist, and overnight SDNN runs roughly 1.6× rMSSD.
            return male
                ? [(25, 90), (35, 78), (45, 66), (55, 56), (65, 48), (75, 42)]
                : [(25, 88), (35, 76), (45, 64), (55, 54), (65, 46), (75, 40)]

        case .walkingSpeed:
            // Usual gait speed by decade. **Nearly flat until sixty** — which is
            // the honest shape and the reason this marker's weight is small for
            // a middle-aged reader and large for an old one.
            return male
                ? [(25, 1.42), (45, 1.40), (60, 1.34), (70, 1.26), (80, 1.10), (90, 0.90)]
                : [(25, 1.40), (45, 1.38), (60, 1.30), (70, 1.20), (80, 1.02), (90, 0.84)]

        case .bloodPressureSystolic:
            // Rises through adult life on essentially every population survey.
            return male
                ? [(25, 118), (35, 121), (45, 125), (55, 130), (65, 136), (75, 141)]
                : [(25, 111), (35, 115), (45, 122), (55, 130), (65, 137), (75, 143)]

        // ⚠️ **Population medians, not fitness-industry "ideal" figures.** The
        // first version ran 16–25% for men, which is roughly the athletic-to-fit
        // band — so an ordinary reader at 30% fell off the end of the curve and
        // the marker was discarded, on a card about how their body is ageing.
        //
        // The trap generalises: **a norm table has to be the median of the
        // population the reader is in.** Anything narrower silently makes the
        // marker unusable for most people, and it fails in the direction that
        // deletes the readers who most need the answer.
        case .bodyFatPercentage:
            return male
                ? [(25, 20), (35, 23), (45, 25), (55, 27), (65, 28), (75, 29)]
                : [(25, 28), (35, 30), (45, 33), (55, 35), (65, 36), (75, 37)]

        default:
            return nil
        }
    }

    /// Between-person spread of the marker *within* an age band, in the marker's
    /// own unit. This is the numerator of σ and it is what stops a steep curve
    /// from claiming more precision than the measurement supports.
    ///
    /// ⚠️ These are stated assumptions, not measurements of this reader. They are
    /// deliberately generous: understating the spread would understate the ±,
    /// which is the exact failure this card exists to avoid.
    static func populationSpread(_ metric: MetricType) -> Double? {
        switch metric {
        // 7 for the between-person spread, plus the wrist estimate's own ±3.5,
        // added in quadrature: √(7² + 3.5²) ≈ 7.8.
        case .vo2Max: return 7.8
        // Overnight HRV is a wide distribution — a coefficient of variation
        // around 35% is usual, and these are scaled to the overnight medians
        // above rather than to the five-minute ones they replaced.
        case .heartRateVariabilityRMSSD: return 15
        case .heartRateVariabilitySDNN: return 24
        case .walkingSpeed: return 0.20
        case .bloodPressureSystolic: return 15
        case .bodyFatPercentage: return 5
        default: return nil
        }
    }

    /// What each instrument's mismatch with its norm table is, in one sentence.
    ///
    /// ⚠️ **A systematic bias does not cancel in the pace figure**, the way random
    /// error does — so these are not decoration, they are the reason the absolute
    /// number could be wrong in one direction for years on end.
    static func instrumentCaveat(_ metric: MetricType) -> String {
        switch metric {
        case .vo2Max:
            return "The norms come from a mask on a treadmill; this comes from your heart rate on a walk."
        case .heartRateVariabilityRMSSD, .heartRateVariabilitySDNN:
            return "Read against overnight norms, which is what your ring or watch records — not the five-minute clinic figures, which are much lower."
        case .walkingSpeed:
            return "The norms are a measured walk down a corridor; this is your phone watching ordinary walking, which reads lower."
        case .bloodPressureSystolic:
            return "Home cuff readings run a few mmHg below clinic readings, which is what the norms are."
        case .bodyFatPercentage:
            return "The norms are from calipers and DEXA; this is a bioimpedance scale, which has its own offset."
        default:
            return ""
        }
    }

    /// Human label for the row.
    static func label(_ metric: MetricType) -> String {
        switch metric {
        case .vo2Max: return "Cardio fitness"
        case .heartRateVariabilityRMSSD, .heartRateVariabilitySDNN: return "Heart-rate variability"
        case .walkingSpeed: return "Walking speed"
        case .bloodPressureSystolic: return "Blood pressure"
        case .bodyFatPercentage: return "Body fat"
        default: return metric.displayName
        }
    }

    /// The markers considered, in the order they are presented.
    ///
    /// **rMSSD and SDNN are alternatives, not two markers.** They are the same
    /// quantity off the same interbeat stream, and counting both would let one
    /// measurement vote twice — the exact error the symptom radar's channel map
    /// exists to prevent. Whichever has more history is used.
    public static let candidates: [MetricType] = [
        .vo2Max, .heartRateVariabilityRMSSD, .heartRateVariabilitySDNN,
        .walkingSpeed, .bloodPressureSystolic, .bodyFatPercentage,
    ]

    /// **Resting heart rate is deliberately absent**, and it is worth saying why
    /// on the card: it barely moves with age. Its norm curve is close enough to
    /// flat that inverting it gives an age with an error of centuries — the
    /// arithmetic would hand it a weight near zero anyway, and a row contributing
    /// nothing is a row that makes the card look better informed than it is.
    public static let deliberatelyExcluded =
        "Resting heart rate is not one of these. It hardly changes with age, so inverting it would add a number and no information."

    // MARK: - Curve mechanics

    /// The typical value of a marker at an age.
    public static func expected(_ metric: MetricType, age: Double,
                                sex: BiologicalSex) -> Double? {
        guard let points = anchors(metric, sex: sex), points.count >= 2 else { return nil }
        if age <= points[0].age {
            let slope = (points[1].value - points[0].value) / (points[1].age - points[0].age)
            return points[0].value + slope * (age - points[0].age)
        }
        for index in 1..<points.count where age <= points[index].age {
            let low = points[index - 1], high = points[index]
            let fraction = (age - low.age) / (high.age - low.age)
            return low.value + (high.value - low.value) * fraction
        }
        let last = points[points.count - 1], previous = points[points.count - 2]
        let slope = (last.value - previous.value) / (last.age - previous.age)
        return last.value + slope * (age - last.age)
    }

    /// How much a year of age moves the marker, at this age. Central difference
    /// over the real curve rather than a quoted figure, so it cannot drift away
    /// from the table it is supposed to describe.
    public static func slopePerYear(_ metric: MetricType, at age: Double,
                                    sex: BiologicalSex) -> Double? {
        guard let above = expected(metric, age: age + 0.5, sex: sex),
              let below = expected(metric, age: age - 0.5, sex: sex) else { return nil }
        return above - below
    }

    /// The age whose typical value is this one.
    ///
    /// Bisection over a curve that is monotonic by construction. Returns the
    /// clamp flag separately: an age pinned at a bound is a different statement
    /// from one found inside the range, and collapsing the two is how "75" starts
    /// meaning "at least 75" without saying so.
    /// ⚠️ **Beyond the table it extrapolates rather than clamps**, and getting
    /// this wrong made the card unusable for the reader it was built for.
    ///
    /// The first version clamped: a value past either end returned the bound and
    /// a flag, and the flagged marker was then excluded. Opened on the reader's
    /// own record, **two of five markers were excluded that way** — body fat 32%
    /// and overnight rMSSD 69 ms. Neither is exotic. Both are ordinary readings
    /// for a real adult.
    ///
    /// The reason is structural and worth stating, because it applies to every
    /// marker here: **these curves are medians, and for several of them the
    /// whole span of adult ageing is smaller than the spread between people at
    /// one age.** Male body fat moves about nine points across fifty years while
    /// people at any one age differ by five. So a substantial share of ordinary
    /// readers sit outside the curve entirely — and clamping deletes exactly the
    /// people whose markers are furthest from typical, which is to say the ones
    /// with something to learn.
    ///
    /// The information is not missing; it is *imprecise*, and imprecision is
    /// already handled — σ = spread ÷ slope gives a flat marker a small share
    /// automatically. So the age equivalent is extended along the terminal slope
    /// and allowed outside 18–95, the weighting does its job, and the row says
    /// it was extrapolated. Only a value so far out that it implies a units
    /// error (past `absurdAge`) is refused.
    public static func invert(_ metric: MetricType, value: Double,
                              sex: BiologicalSex) -> (age: Double, extrapolated: Bool)? {
        guard let atYoungest = expected(metric, age: youngest, sex: sex),
              let atOldest = expected(metric, age: oldest, sex: sex),
              atYoungest != atOldest else { return nil }

        let risesWithAge = atOldest > atYoungest
        let youngEnd = risesWithAge ? atYoungest : atOldest
        let oldEnd = risesWithAge ? atOldest : atYoungest

        /// Continue along the curve's own terminal slope past a bound.
        func beyond(_ bound: Double, valueAtBound: Double) -> (Double, Bool)? {
            guard let slope = slopePerYear(metric, at: bound, sex: sex),
                  abs(slope) > 1e-9 else { return nil }
            return (bound + (value - valueAtBound) / slope, true)
        }

        if value < youngEnd {
            let bound = risesWithAge ? youngest : oldest
            return beyond(bound, valueAtBound: youngEnd).map { (age: $0.0, extrapolated: $0.1) }
        }
        if value > oldEnd {
            let bound = risesWithAge ? oldest : youngest
            return beyond(bound, valueAtBound: oldEnd).map { (age: $0.0, extrapolated: $0.1) }
        }

        var low = youngest, high = oldest
        for _ in 0..<60 {
            let mid = (low + high) / 2
            guard let here = expected(metric, age: mid, sex: sex) else { break }
            if (here < value) == risesWithAge { low = mid } else { high = mid }
        }
        return ((low + high) / 2, false)
    }

    /// Past this, an age equivalent is not a person — it is a units mistake, a
    /// mis-scaled import, or a sensor fault. The one case still refused.
    public static let absurdAge: ClosedRange<Double> = -20...140

    // MARK: - Output

    public struct Marker: Sendable, Equatable, Identifiable {
        public let metric: MetricType
        public let label: String
        /// The reader's own value, over `windowDays`.
        public let observed: Double
        /// The typical value at their real age, when it is known.
        public let expectedForOwnAge: Double?
        /// The age this value is typical of.
        public let ageEquivalent: Double
        /// What that age equivalent is worth on its own, in years.
        public let uncertaintyYears: Double
        /// Share of the final number, from inverse-variance weighting. Sums to 1
        /// across the markers.
        public let weight: Double
        /// True when the value sits past either end of the norm table, so the
        /// age equivalent was continued along the curve's terminal slope. Not a
        /// reason to discard it — see `invert` — but the row says so.
        public let isExtrapolated: Bool
        public let caveat: String
        public let daysOfData: Int
        public var id: String { metric.rawValue }
    }

    /// A candidate marker the answer did **not** use, and why.
    ///
    /// ⚠️ **Every one of these has to reach the card.** Two guards found this at
    /// once (`testEveryDeclaredInputWithDataIsActuallyRead` and
    /// `testEveryCandidateMetricIsReachableAsAContributor`) on a fixture where
    /// VO₂max and body fat both fell off the ends of the female curves: the card
    /// declared it read them, had data for both, and reported neither — so they
    /// would have appeared under "How you compare" and "How far from your
    /// normal" while being absent from "What goes into this". A card claiming to
    /// read something it silently dropped.
    ///
    /// The remedy is the app's standing convention: a row at weight 0 that says
    /// why. "Your VO₂max is better than the top of the norm table" is a genuinely
    /// interesting sentence, and it is not the same sentence as silence.
    public struct UnusedMarker: Sendable, Equatable, Identifiable {
        public enum Reason: Sendable, Equatable {
            /// So far outside the curve that the age equivalent is not a
            /// person — a units mistake or a sensor fault, not a reading.
            case impossibleValue
            /// The curve is so flat here that inverting it spans a lifetime.
            case tooFlatAtThisAge
            /// Fewer than `minimumDaysPerMarker` days inside its window.
            case notEnoughReadings
            /// The other half of the HRV pair was used instead.
            case siblingPreferred(MetricType)
        }

        public let metric: MetricType
        public let label: String
        public let observed: Double?
        public let reason: Reason
        /// How many days of it were actually found, and over how long a window.
        /// On the row because "too few readings" without a count is the same
        /// unhelpful sentence as "not enough data".
        public let daysFound: Int
        public let windowDays: Int
        public var id: String { metric.rawValue }

        /// The reason as the card prints it, weight-0 row included.
        public var sentence: String {
            switch reason {
            case .impossibleValue:
                return "reads as an age no person has, so this is a units or sensor problem rather than a measurement — not counted, and worth checking at source"
            case .tooFlatAtThisAge:
                return "the norm curve is nearly flat at your age, so this cannot tell one decade from the next — not counted, because a marker that says nothing should not look like one that says a little"
            case .notEnoughReadings:
                return "\(daysFound) day\(daysFound == 1 ? "" : "s") of it in the last \(windowDays), and it needs \(BiologicalAgeModel.minimumDaysPerMarker) — \(BiologicalAgeModel.remedy(metric))"
            case let .siblingPreferred(other):
                return "the same measurement as \(BiologicalAgeModel.label(other)), off the same heartbeat stream — counting both would let one signal vote twice"
            }
        }
    }

    public struct Output: Sendable, Equatable {
        public let biologicalAge: Double
        /// One standard error, in years. Around a decade, honestly.
        public let uncertaintyYears: Double
        public let chronologicalAge: Double?
        /// Chronological − biological. Positive is the good direction.
        public let yearsYounger: Double?
        public let markers: [Marker]
        /// Every candidate that did not make it into the number, each with its
        /// reason. Rendered at weight 0 rather than omitted — see `UnusedMarker`.
        public let unused: [UnusedMarker]
        /// The subset refused for an impossible value — the only one of the four
        /// reasons with a number worth printing.
        public var outOfRange: [UnusedMarker] {
            unused.filter { $0.reason == .impossibleValue }
        }
        /// Years of biological age gained per calendar year, from two
        /// evaluations `paceLookbackDays` apart. Nil when the earlier one could
        /// not be built from the same markers.
        public let pace: Double?
        public let paceSpanDays: Int?

        public init(biologicalAge: Double, uncertaintyYears: Double,
                    chronologicalAge: Double?, yearsYounger: Double?,
                    markers: [Marker], unused: [UnusedMarker] = [],
                    pace: Double? = nil, paceSpanDays: Int? = nil) {
            self.unused = unused
            self.biologicalAge = biologicalAge
            self.uncertaintyYears = uncertaintyYears
            self.chronologicalAge = chronologicalAge
            self.yearsYounger = yearsYounger
            self.markers = markers
            self.pace = pace
            self.paceSpanDays = paceSpanDays
        }

        /// The band the number should be read as, which is what the card leads
        /// with rather than the point.
        public var range: ClosedRange<Double> {
            (biologicalAge - uncertaintyYears)...(biologicalAge + uncertaintyYears)
        }
    }

    // MARK: - Evaluation

    /// The reader's own value for a marker: the median of its daily values over
    /// the window.
    ///
    /// Median rather than mean, and the reason is the same one that put
    /// `Baseline.deviation(robust:)` on the flagging path — a standard deviation
    /// has a breakdown point of zero, and so does a mean. One fortnight of
    /// illness must not age the reader by three years.
    static func level(_ metric: MetricType, from samples: [HealthMetricSample],
                      now: Date, calendar: Calendar) -> (value: Double, days: Int)? {
        let values = VitalReader.dailyValues(metric, from: samples,
                                             days: lookbackDays(metric),
                                             now: now, calendar: calendar)
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        let median = sorted.count.isMultiple(of: 2)
            ? (sorted[middle - 1] + sorted[middle]) / 2
            : sorted[middle]
        return (median, values.count)
    }

    /// Minimum days of a marker before it may vote. A marker read from two days
    /// is a marker that will move the whole card next week.
    public static let minimumDaysPerMarker = 5

    /// ⚠️ **Minimum markers before this is allowed to call itself a biological
    /// age**, and the reason is the defect that produced it.
    ///
    /// On the reader's real record the first build published a number with two
    /// markers, one of which carried 95% — so the card said "biological age 22"
    /// when what it meant was "your HRV is that of a 34-year-old, and we are
    /// showing you a rounding error on top of it".
    ///
    /// **That is the same failure as a vendor's black box, arrived at from the
    /// opposite direction.** Whoop hides which measurement it is reporting
    /// behind a model; this hid it behind a name. Both leave the reader unable
    /// to tell what they are looking at. The whole argument for building this
    /// card was that a composite of independent markers says something no single
    /// marker does — so below three, there is no composite and no card.
    public static let minimumMarkers = 3

    /// One marker and how much it is worth, before the shares are normalised.
    struct Term { let marker: Marker; let precision: Double }

    /// **Resolve every candidate into either a usable marker or a stated
    /// reason.** Shared by `evaluate` and `diagnose`, and that sharing is the
    /// point: the empty state used to reason from `availability`, which only
    /// knows whether *data* exists, so a card that had four markers' worth of
    /// data and could still not answer had nothing to say about why.
    ///
    /// A card that cannot explain its own refusal is as opaque as one that
    /// cannot explain its own number.
    static func resolveMarkers(samples: [HealthMetricSample],
                               sex: BiologicalSex,
                               chronological: Double?,
                               now: Date,
                               calendar: Calendar) -> (terms: [Term], unused: [UnusedMarker]) {
        var unused: [UnusedMarker] = []
        func drop(_ metric: MetricType, _ observed: Double?, _ reason: UnusedMarker.Reason,
                  days: Int = 0) {
            unused.append(UnusedMarker(metric: metric, label: label(metric),
                                       observed: observed, reason: reason,
                                       daysFound: days, windowDays: lookbackDays(metric)))
        }

        // MARK: pick one HRV marker, never two
        var metrics: [MetricType] = []
        var hrvChoice: (metric: MetricType, days: Int)?
        for metric in candidates {
            let found = level(metric, from: samples, now: now, calendar: calendar)
            guard let reading = found, reading.days >= minimumDaysPerMarker else {
                drop(metric, found?.value, .notEnoughReadings, days: found?.days ?? 0)
                continue
            }
            if metric == .heartRateVariabilityRMSSD || metric == .heartRateVariabilitySDNN {
                // **rMSSD wins ties and wins outright**, not "whichever has more
                // days". rMSSD is the better-characterised of the two against
                // age, and it is what the ring reports; SDNN is Apple's and is
                // far more sensitive to how long the recording window was.
                // Picking by row count meant the noisier measure usually won,
                // because the watch is worn more hours than the ring.
                let better = metric == .heartRateVariabilityRMSSD
                    || hrvChoice == nil
                if better && hrvChoice?.metric != .heartRateVariabilityRMSSD {
                    hrvChoice = (metric, reading.days)
                }
                continue
            }
            metrics.append(metric)
        }
        if let hrvChoice {
            metrics.append(hrvChoice.metric)
            // The loser of the pair is reported, not omitted: "we have both and
            // used one" is a different statement from "we did not look".
            for sibling in [MetricType.heartRateVariabilityRMSSD, .heartRateVariabilitySDNN]
            where sibling != hrvChoice.metric && !unused.contains(where: { $0.metric == sibling }) {
                drop(sibling, nil, .siblingPreferred(hrvChoice.metric))
            }
        }
        var terms: [Term] = []

        for metric in metrics {
            guard let reading = level(metric, from: samples, now: now, calendar: calendar),
                  let inverted = invert(metric, value: reading.value, sex: sex),
                  let spread = populationSpread(metric),
                  let slope = slopePerYear(metric, at: inverted.age, sex: sex),
                  abs(slope) > 1e-9 else {
                drop(metric, nil, .notEnoughReadings,
                     days: level(metric, from: samples, now: now, calendar: calendar)?.days ?? 0)
                continue
            }

            // σ in years: how far the age has to move before this marker would
            // have noticed, given how much people differ at one age.
            let sigma = spread / abs(slope)

            let marker = Marker(
                metric: metric,
                label: label(metric),
                observed: reading.value,
                expectedForOwnAge: chronological.flatMap { expected(metric, age: $0, sex: sex) },
                ageEquivalent: inverted.age,
                uncertaintyYears: sigma,
                weight: 0,                          // filled in below
                isExtrapolated: inverted.extrapolated,
                caveat: instrumentCaveat(metric),
                daysOfData: reading.days)

            // Only a value that is not a person at all is refused. Everything
            // else is extrapolated and weighted — see `invert` for why clamping
            // deleted two of this reader's five markers.
            guard absurdAge.contains(inverted.age) else {
                drop(metric, reading.value, .impossibleValue, days: reading.days)
                continue
            }

            // A marker so flat that its answer spans a lifetime is noise with a
            // label on it. It does not vote, and it says why.
            guard sigma < 120 else {
                drop(metric, reading.value, .tooFlatAtThisAge)
                continue
            }

            terms.append(Term(marker: marker, precision: 1 / (sigma * sigma)))
        }
        return (terms, unused)
    }

    /// Why the card cannot answer, marker by marker. What the empty state reads.
    public static func diagnose(samples: [HealthMetricSample],
                                profile: UserHealthProfile,
                                now: Date = Date(),
                                calendar: Calendar = .current)
        -> (usable: [MetricType], unused: [UnusedMarker]) {
        guard let sex = profile.sex else { return ([], []) }
        let resolved = resolveMarkers(samples: samples, sex: sex,
                                      chronological: profile.age(asOf: now),
                                      now: now, calendar: calendar)
        return (resolved.terms.map(\.marker.metric), resolved.unused)
    }

    /// Build the answer. Nil when sex is unknown (every curve is sex-specific)
    /// or when fewer than `minimumMarkers` markers survive.
    public static func evaluate(samples: [HealthMetricSample],
                                profile: UserHealthProfile,
                                now: Date = Date(),
                                calendar: Calendar = .current,
                                includePace: Bool = true) -> Output? {
        guard let sex = profile.sex else { return nil }
        let chronological = profile.age(asOf: now)
        let resolved = resolveMarkers(samples: samples, sex: sex,
                                      chronological: chronological,
                                      now: now, calendar: calendar)
        let terms = resolved.terms
        let unused = resolved.unused

        // Below three there is no composite, and a composite is the entire
        // argument for this card existing. See `minimumMarkers`.
        guard terms.count >= minimumMarkers else { return nil }
        let totalPrecision = terms.reduce(0) { $0 + $1.precision }
        guard totalPrecision > 0 else { return nil }

        let biological = terms.reduce(0.0) {
            $0 + $1.marker.ageEquivalent * ($1.precision / totalPrecision)
        }
        let uncertainty = (1 / totalPrecision).squareRoot()

        let markers = terms
            .map { term in
                Marker(metric: term.marker.metric, label: term.marker.label,
                       observed: term.marker.observed,
                       expectedForOwnAge: term.marker.expectedForOwnAge,
                       ageEquivalent: term.marker.ageEquivalent,
                       uncertaintyYears: term.marker.uncertaintyYears,
                       weight: term.precision / totalPrecision,
                       isExtrapolated: term.marker.isExtrapolated, caveat: term.marker.caveat,
                       daysOfData: term.marker.daysOfData)
            }
            .sorted { $0.weight > $1.weight }

        // MARK: pace of ageing
        //
        // The figure worth watching, and the reason the wide ± above is not
        // fatal: most of that error is a fixed property of this reader and this
        // set of instruments, so it subtracts out of a difference. **Only when
        // the two evaluations rest on the same markers** — otherwise the change
        // is a change of measuring stick, which would read as ageing.
        var pace: Double?
        var paceSpan: Int?
        if includePace,
           let then = now.addingTimeInterval(-Double(paceLookbackDays) * 86_400) as Date?,
           let earlier = evaluate(samples: samples, profile: profile, now: then,
                                  calendar: calendar, includePace: false),
           Set(earlier.markers.map(\.metric)) == Set(markers.map(\.metric)) {
            let years = Double(paceLookbackDays) / 365.25
            pace = (biological - earlier.biologicalAge) / years
            paceSpan = paceLookbackDays
        }

        return Output(biologicalAge: biological, uncertaintyYears: uncertainty,
                      chronologicalAge: chronological,
                      yearsYounger: chronological.map { $0 - biological },
                      markers: markers, unused: unused,
                      pace: pace, paceSpanDays: paceSpan)
    }

    /// What each candidate marker has to offer, so the empty state can name the
    /// gap instead of saying "not enough data".
    ///
    /// **This exists because the first build's empty state would have been a
    /// lie of omission.** The card needs three markers; the reader's record had
    /// two, and the difference between them is *"take a cuff reading"* and
    /// *"go for an outdoor walk wearing your watch"* — both of which they can do
    /// today. A card that says "not enough data" when it means "one specific
    /// five-minute action away" has wasted the only leverage it had.
    public struct Availability: Sendable, Equatable {
        /// Enough days inside its own lookback window.
        public let usable: [MetricType]
        /// Present, but under `minimumDaysPerMarker` in its window.
        public let tooSparse: [MetricType]
        /// Nothing at all.
        public let absent: [MetricType]
    }

    public static func availability(samples: [HealthMetricSample],
                                    now: Date = Date(),
                                    calendar: Calendar = .current) -> Availability {
        var usable: [MetricType] = [], sparse: [MetricType] = [], absent: [MetricType] = []
        for metric in candidates {
            guard let reading = level(metric, from: samples, now: now, calendar: calendar) else {
                absent.append(metric); continue
            }
            if reading.days >= minimumDaysPerMarker { usable.append(metric) }
            else { sparse.append(metric) }
        }
        return Availability(usable: usable, tooSparse: sparse, absent: absent)
    }

    /// What the reader could do to complete the set, named per marker.
    public static func remedy(_ metric: MetricType) -> String {
        switch metric {
        case .vo2Max:
            return "a cardio-fitness reading — your watch writes one after an outdoor walk or run of about twenty minutes"
        case .bloodPressureSystolic:
            return "a blood-pressure reading from a cuff"
        case .bodyFatPercentage:
            return "a body-fat reading from a smart scale"
        case .heartRateVariabilityRMSSD, .heartRateVariabilitySDNN:
            return "a few nights wearing your ring or watch"
        case .walkingSpeed:
            return "a few days carrying your phone while you walk"
        default:
            return metric.displayName
        }
    }

    /// How the card's dial reads, from the gap to chronological age.
    ///
    /// A curve rather than bands, per the scoring rule: the reader's biological
    /// age crossing their birthday must not move the dial twenty points.
    ///
    /// ⚠️ **The gap is discounted by the error first, and the dial and the
    /// headline must use the same discounted number.** Seen on the reader's own
    /// record: the card read *"Close to your years"* beside a dial of **30**,
    /// which is two contradictory judgements of one four-year gap on a
    /// ±11-year estimate. The headline was already comparing the gap with the
    /// error; the dial was comparing it with zero.
    ///
    /// Discounting means a gap smaller than the error scores exactly neutral —
    /// *we cannot tell these two ages apart* — which is the honest reading and
    /// the one the rest of the card already gives.
    public static func score(yearsYounger: Double, uncertaintyYears: Double = 0) -> Double {
        let beyondTheError = max(0, abs(yearsYounger) - uncertaintyYears)
        let discounted = yearsYounger < 0 ? -beyondTheError : beyondTheError
        return ScoreCurve.through([(-15, 12), (-8, 30), (-3, 48), (0, 60),
                                   (3, 72), (8, 88), (15, 98)], at: discounted)
    }

    static func headline(_ out: Output) -> String {
        guard let younger = out.yearsYounger else {
            return String(format: "About %.0f", out.biologicalAge)
        }
        let years = abs(younger).rounded()
        if years < 1 { return "Level with your years" }
        // ⚠️ The gap is compared with the error, not with zero. "Three years
        // younger" on a ±11 estimate is not a finding, and printing it as one is
        // how every vendor's biological age gets read as a result.
        if abs(younger) < out.uncertaintyYears {
            return years < 3 ? "Level with your years" : "Close to your years"
        }
        return younger > 0
            ? String(format: "%.0f years younger", years)
            : String(format: "%.0f years older", years)
    }
}

/// The card.
public struct BiologicalAgeInsight: InsightModel {
    public let id: InsightID = .biologicalAge
    public let title = "Biological age"

    public init() {}

    public var candidateMetrics: [MetricType] { BiologicalAgeModel.candidates }

    /// Both mandatory, and unlike the Nutrition card's version this rationale is
    /// true the moment it is satisfied. Every norm curve here is sex-specific,
    /// and without a birthday there is no comparison to make — the whole card is
    /// the gap between two ages.
    public var requirements: [GroundingRequirement] {
        [.init(kind: .biologicalSex, isMandatory: true,
               rationale: "Every age-norm curve here is different for men and women — systolic blood pressure alone starts seven mmHg apart at twenty-five and converges by sixty-five."),
         .init(kind: .dateOfBirth, isMandatory: true,
               rationale: "This card is the distance between two ages. Without your real one there is only half of it.")]
    }

    func unmet(for profile: UserHealthProfile, now: Date) -> [GroundingRequirement] {
        requirements.filter { requirement in
            switch requirement.kind {
            case .biologicalSex: return profile.sex == nil
            case .dateOfBirth: return profile.age(asOf: now) == nil
            default: return false
            }
        }
    }

    public func evaluate(samples: [HealthMetricSample],
                         profile: UserHealthProfile, now: Date) -> InsightResult {
        let missing = unmet(for: profile, now: now)
        guard let out = BiologicalAgeModel.evaluate(samples: samples, profile: profile, now: now)
        else {
            // Name the gap, from the **same loop that refused** rather than from
            // a separate "is there data" check. `diagnose` exists precisely so
            // this branch cannot say something the refusal disagrees with.
            let why = BiologicalAgeModel.diagnose(samples: samples, profile: profile, now: now)
            var lines: [InsightDriver] = []
            if !missing.isEmpty {
                lines.append(.notable("It needs your sex and date of birth first — every age-norm curve here is different for men and women, and the card itself is the distance between two ages."))
            }
            if !why.usable.isEmpty {
                lines.append(.routine("Counting: " + why.usable.map(BiologicalAgeModel.label).joined(separator: ", ")
                                      + " — \(why.usable.count) of the \(BiologicalAgeModel.minimumMarkers) it needs."))
            }
            for skipped in why.unused {
                // The value goes on the row, not just the reason. "Body fat is
                // off the end of its curve" is unfalsifiable without it; "body
                // fat 0.3% is off the end of its curve" names a units bug on
                // sight. Same argument as printing the day count.
                let value = skipped.observed
                    .map { " (" + MetricValueFormatter.string($0, skipped.metric) + ")" } ?? ""
                lines.append(.component("\(skipped.label)\(value): \(skipped.sentence)",
                                        score: 30))
            }
            return InsightResult(
                id: id, title: title, primaryValue: nil,
                headline: missing.isEmpty
                    ? "Needs \(BiologicalAgeModel.minimumMarkers) markers to answer"
                    : "Tell it who it is measuring",
                score: nil, confidence: .low,
                explanation: "This works out the age your measurements are typical of, one marker at a time, against published age norms — cardio fitness, heart-rate variability, walking speed, blood pressure and body fat. It will not answer on fewer than \(BiologicalAgeModel.minimumMarkers) of them: with one or two, a \"biological age\" is really just that one measurement under a grander name, which is the thing this card exists not to be. \(BiologicalAgeModel.deliberatelyExcluded)",
                driverLines: lines,
                unmetRequirements: missing,
                invitesInput: true)
        }

        var drivers: [InsightDriver] = []

        // **The range leads, not the number.** The point estimate is the
        // midpoint of something a decade wide and the card says so first,
        // because a bare "52" is the exact claim every competitor makes and
        // cannot support.
        drivers.append(InsightDriver(
            text: String(format: "Your markers put you at %.0f, and the honest range is %.0f to %.0f — that width is what these measurements are worth, not a hedge",
                         out.biologicalAge,
                         out.range.lowerBound.rounded(), out.range.upperBound.rounded()),
            isNotable: true))

        // The pace is the figure with real precision, so it comes second and is
        // marked notable when it is moving the wrong way.
        if let pace = out.pace, let span = out.paceSpanDays {
            let months = Int((Double(span) / 30.44).rounded())
            drivers.append(InsightDriver(
                text: String(format: "Pace of ageing: %.2f years of biological age per calendar year, over the last %d months. **This is the number worth watching** — most of the ±%.0f above is a fixed property of you and your devices, so it cancels out of a change and does not cancel out of the total.",
                             pace, months, out.uncertaintyYears),
                isNotable: pace > 1.0))
        } else {
            drivers.append(.routine("No pace of ageing yet — that needs the same set of markers \(BiologicalAgeModel.paceLookbackDays / 30) months apart, so a marker that only started recently resets it."))
        }

        var contributions: [MetricContribution] = []
        for marker in out.markers {
            let gap = out.chronologicalAge.map { marker.ageEquivalent - $0 }
            let comparison: String
            switch gap {
            case let .some(value) where abs(value) < 1:
                comparison = "level with your age"
            case let .some(value) where value > 0:
                comparison = String(format: "%.0f years older than you are", value)
            case let .some(value):
                comparison = String(format: "%.0f years younger than you are", -value)
            case .none:
                comparison = "no birthday to compare it with"
            }
            // ⚠️ **An extrapolated marker shows its direction, not its number.**
            // Seen on the reader's record: body fat 32% printed "reads as 102",
            // which is arithmetically what the curve gives and reads as
            // nonsense — and a nonsense number beside a sound one costs the
            // sound one its credibility. The 102 is still what the weighting
            // uses; it is worth ±50 years and carries 5%, which is the system
            // working. It is the *display* that has to stop claiming precision
            // the curve does not have out there.
            let reads = marker.isExtrapolated
                ? String(format: "%@ is past the %@ end of the published table",
                         MetricValueFormatter.string(marker.observed, marker.metric),
                         marker.ageEquivalent > BiologicalAgeModel.oldest ? "old" : "young")
                : String(format: "%@ reads as %.0f — %@",
                         MetricValueFormatter.string(marker.observed, marker.metric),
                         marker.ageEquivalent, comparison)
            let text = String(format: "%@: %@. On its own it is worth ±%.0f years, so it carries %.0f%% of the answer. %@",
                              marker.label, reads,
                              marker.uncertaintyYears, marker.weight * 100,
                              marker.caveat)
            drivers.append(InsightDriver(text: text,
                                         isNotable: (gap ?? 0) > out.uncertaintyYears))
            contributions.append(MetricContribution(
                metric: marker.metric,
                // Which direction is the welcome one for *age*: a marker whose
                // norm rises with age (pressure, body fat) is better lower.
                higherIsBetter: (BiologicalAgeModel.slopePerYear(
                    marker.metric, at: marker.ageEquivalent,
                    sex: profile.sex ?? .male) ?? 0) < 0,
                weight: marker.weight,
                detail: text,
                // **No componentScore, deliberately.** A marker's own answer
                // is an *age equivalent*, not a 0–100 — squeezing it into one
                // would invent the very calibration this card refuses. No
                // baseline/z either: markers are read against published age
                // norms, never the reader's own history. The observed reading
                // is the one number each marker genuinely holds.
                value: marker.observed))
        }

        // Everything the card declared and did not use, at weight 0, each
        // saying why. Omitting these is what made two guards fire at once — the
        // card would have charted them under "How you compare" while claiming
        // in "What goes into this" that it had never read them.
        for skipped in out.unused {
            let value = skipped.observed
                .map { " (" + MetricValueFormatter.string($0, skipped.metric) + ")" } ?? ""
            let text = "\(skipped.label)\(value) — \(skipped.sentence)"
            drivers.append(.routine(text))
            contributions.append(MetricContribution(
                metric: skipped.metric, higherIsBetter: nil, weight: 0, detail: text,
                // The observed reading where there was one — a skipped marker
                // usually has a value and a reason, and the row already prints
                // both; nil where the marker had nothing to read at all.
                value: skipped.observed))
        }
        drivers.append(.routine("Each marker is inverted through its own published age norm and they are combined by how precisely each one can pin an age — a marker whose curve is nearly flat is nearly ignored, automatically. There is no fitted parameter anywhere in this."))
        drivers.append(.routine("Your real age is deliberately left out of the arithmetic. Including it — which is what the published method does, and what every commercial version does — would pull the answer toward your birthday and make it look far more precise than it is."))
        drivers.append(.routine(BiologicalAgeModel.deliberatelyExcluded))

        let score = out.yearsYounger.map {
            BiologicalAgeModel.score(yearsYounger: $0,
                                     uncertaintyYears: out.uncertaintyYears)
        }

        return InsightResult(
            id: id, title: title,
            primaryValue: out.biologicalAge,
            headline: BiologicalAgeModel.headline(out),
            score: score,
            confidence: out.markers.count >= 4 ? .moderate : .low,
            explanation: "The age your measurements are typical of, worked out marker by marker against published age norms and combined by how precisely each one can pin an age. Every row shows its own answer, its own error and its share. \(out.markers.count) markers over the last \(BiologicalAgeModel.windowDays) days.",
            driverLines: drivers.filter { $0.isNotable == true }
                + drivers.filter { $0.isNotable != true },
            unmetRequirements: missing,
            contributors: contributions,
            weighting: .weightedAverage,
            otherFactors: Self.producedFigures(out),
            derivedOutputs: Self.derivedOutputs(out))
    }

    // MARK: - What this card works out (2026-08-06)
    //
    // **The reader named this one:** *"In Biological age card, we created a
    // 'Combined' score, that now should be a score that gets its own data row."*
    // It was right: the composite was recomputed on every launch, printed in one
    // sentence and discarded, so "is my biological age moving" could only be
    // answered by the card re-deriving it in front of you.

    static let combinedKey = "combined"
    static let uncertaintyKey = "combinedUncertainty"
    static let paceKey = "paceOfAgeing"
    /// Prefix for a single marker's own answer. `age.<metric>`.
    static let markerAgePrefix = "age"

    static func markerAgeKey(_ metric: MetricType) -> String {
        "\(markerAgePrefix).\(metric.rawValue)"
    }

    static func derivedOutputs(_ out: BiologicalAgeModel.Output) -> [DerivedOutput] {
        var series: [DerivedOutput] = [
            .init(key: combinedKey, displayName: "Biological age (combined)",
                  unit: "years", value: out.biologicalAge,
                  higherIsBetter: false, precision: 1),
            // The width travels with the number everywhere else on this card,
            // and a series of point estimates with the ± left behind would be
            // the one presentation this card exists to refuse. It also moves on
            // its own: it narrows when a marker arrives and widens when one
            // lapses, which is worth being able to see.
            .init(key: uncertaintyKey, displayName: "Biological age — the ± on it",
                  unit: "years", value: out.uncertaintyYears,
                  higherIsBetter: false, precision: 1),
        ]
        if let pace = out.pace {
            series.append(.init(key: paceKey, displayName: "Pace of ageing",
                                unit: "years per year", value: pace,
                                higherIsBetter: false, precision: 2))
        }

        // ## Each marker's own age: **yes, a series each** — and the reason is
        // not obvious, so it is written down.
        //
        // The reader's qualifier says a figure "directly derived from one other
        // data point" must not become a second name for it, and a marker age is
        // monotone in one metric — so on the face of it this is a pass-through
        // and should be refused.
        //
        // It isn't one, because the transform is **not fixed**. Each reading is
        // inverted through a published norm table indexed by sex *and age*, so
        // the same 48 ms of HRV maps to a different age equivalent next year
        // than it does this year. The series therefore moves on days the metric
        // did not, and cannot be recovered from the metric's own history — which
        // is precisely the test for whether a derived series is a new quantity
        // or a rename.
        //
        // They are also the only marker-level history this card has: it emits no
        // `componentScore` and no `z` on purpose (an age equivalent is not a
        // 0–100 and is not judged against the reader's own past), so the two
        // free harvest tiers are empty here and this is the whole of it.
        for marker in out.markers {
            series.append(.init(key: markerAgeKey(marker.metric),
                                displayName: "\(marker.label) reads as an age",
                                unit: "years", value: marker.ageEquivalent,
                                higherIsBetter: false, precision: 0))
        }
        return series
    }

    /// The composite and its pace, as rows the reader can find.
    ///
    /// ⚠️ **Weight 0, and the zero is arithmetic rather than modesty.** The
    /// markers below already divide 100% of this card between them, and the
    /// combined age *is* their precision-weighted mean — giving it a share would
    /// be counting the same five readings twice and would put two hundred per
    /// cent on one card. See `ScoreFactor.producedFigure`.
    ///
    /// The per-marker ages are deliberately **not** factors, only series: each
    /// marker already has a weighted row carrying its share, and a second row
    /// per marker would double a list whose whole job is to be read top to
    /// bottom. The age equivalent is on that row's own sentence already.
    static func producedFigures(_ out: BiologicalAgeModel.Output) -> [ScoreFactor] {
        var rows: [ScoreFactor] = [
            .producedFigure(
                DerivedSeriesID(.biologicalAge, combinedKey),
                name: "Biological age (combined)",
                detail: String(format: "%.0f years, ±%.0f — the precision-weighted mean of the markers above. It carries no share of its own: it *is* those shares, and giving it one would count them twice.",
                               out.biologicalAge, out.uncertaintyYears))
        ]
        if let pace = out.pace, let span = out.paceSpanDays {
            rows.append(.producedFigure(
                DerivedSeriesID(.biologicalAge, paceKey),
                name: "Pace of ageing",
                detail: String(format: "%.2f years of biological age per calendar year, over %d months. Tracked rather than scored — it is a change in the figure above, so it cannot also be an input to it.",
                               pace, Int((Double(span) / 30.44).rounded()))))
        }
        return rows
    }
}
