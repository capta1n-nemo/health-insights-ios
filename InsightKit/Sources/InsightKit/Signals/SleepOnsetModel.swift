import Foundation

/// How long you take to fall asleep, whether that is drifting, and what — of the
/// things this app can actually see — moves it.
///
/// ## What it can and cannot answer
///
/// The reader's own question was *"is it the drugs? is it tech time? am I eating
/// too late? am I too hot or too cold?"* — and honesty about which of those the
/// app can see is the whole point. It can see:
///
/// - **substances** you logged that evening,
/// - **medication** still in your system (the GLP-1 curve),
/// - **temperature** — how far your skin ran from its own baseline, warm *or*
///   cool, which is the "too hot / too cold" question,
/// - **evening exertion** — how active the day was,
/// - **screen time** — *"is it tech time?"*, once the reader is entering it.
///   Apple sandboxes Screen Time so no app can read it automatically (see
///   `MetricType.screenTimeMinutes`), so this factor appears only on the days
///   it was supplied, and `unseenFactors` keeps naming it until then.
///
/// It still **cannot** see when you last ate, and `unseenFactors` names what is
/// missing rather than letting its absence read as "nothing else matters".
///
/// ## Why a contrast, not a single correlation
///
/// Each driver is judged by splitting your nights into higher- and
/// lower-exposure halves and contrasting the *median-split* mean latency, the
/// same shape `SubstanceResponseAnalyzer` uses. A raw Pearson r assumes a
/// straight line, and temperature is the counter-example the reader raised
/// themselves: both too-hot and too-cold nights are worse, so a line through the
/// middle finds nothing. Temperature is therefore judged three ways — warm,
/// cool, and neutral — and reports whichever extreme actually cost more sleep.
///
/// Everything here is an **association, never a cause**, and every sentence says
/// so. On a phone full of confounds that sentence is not a disclaimer, it is the
/// finding.
public enum SleepOnsetModel {

    /// One night's value of something, keyed to the night's wake day so a driver
    /// measured on that day lines up with the latency it might explain.
    public struct Sample: Sendable, Equatable {
        public let date: Date
        public let value: Double
        public init(date: Date, value: Double) {
            self.date = date
            self.value = value
        }
    }

    /// The four things the app can hold up against your sleep onset.
    public enum Factor: String, Sendable, CaseIterable {
        case substances, medication, temperature, eveningExertion, screenTime

        public var displayName: String {
            switch self {
            case .substances: return "Substances that evening"
            case .medication: return "Medication in your system"
            case .temperature: return "Skin temperature"
            case .eveningExertion: return "How active the day was"
            case .screenTime: return "Screen time"
            }
        }

        /// The reader's own phrasing, for the section that lists what was checked.
        public var question: String {
            switch self {
            case .substances: return "Is it what you used that evening?"
            case .medication: return "Is it the medication?"
            case .temperature: return "Were you too hot or too cold?"
            case .eveningExertion: return "Is it how hard the day was?"
            case .screenTime: return "Is it tech time?"
            }
        }

        /// Temperature is judged in both directions; the rest are more-vs-less.
        var isSigned: Bool { self == .temperature }
    }

    public struct Driver: Sendable, Equatable, Identifiable {
        public let factor: Factor
        /// Exposed-nights mean minus baseline-nights mean, in minutes. Positive
        /// means the exposure went with a *longer* time to fall asleep.
        public let deltaMinutes: Double
        public let exposedNights: Int
        public let baselineNights: Int
        /// Pearson r where the contrast is linear (nil for temperature's
        /// three-way split, where a single r would be meaningless).
        public let correlation: Double?
        public let sentence: String
        public var id: String { factor.rawValue }
    }

    public struct Output: Sendable, Equatable {
        /// The nightly latency the trend was fitted on, oldest first — one value
        /// per night, so the chart draws exactly what was analysed.
        public let nights: [Sample]
        /// The fitted line through your nightly latency — its slope is whether
        /// you are drifting longer or shorter, quoted with the scatter it was
        /// drawn through so a slope is never read as a promise.
        public let trend: ScoreTrend?
        public let medianMinutes: Double
        public let nightsAnalysed: Int
        /// Drivers that cleared the floor, worst (largest delay) first.
        public let drivers: [Driver]
        /// What the app cannot see, named so its silence isn't read as absence.
        public let unseenFactors: [String]

        /// Whether the trend is worth a direction word, given the scatter.
        public var trendIsMeaningful: Bool { trend?.isMeaningful ?? false }
    }

    /// Nights needed before any of this is worth saying.
    public static let minimumNights = 10
    /// And the least a contrast may rest on, per side.
    public static let minimumPerSide = 5
    /// A contrast smaller than this is not worth a sentence — a couple of minutes
    /// is inside the night-to-night noise of falling asleep.
    public static let minimumDeltaMinutes = 3.0
    /// How far skin temperature must run from baseline to count as warm or cool,
    /// in °C. Below this a night is "neutral".
    public static let temperatureThreshold = 0.3

    public static func analyse(latency: [Sample],
                               factors: [(Factor, [Sample])],
                               calendar: Calendar = .current) -> Output? {
        // One value per night, newest wins, oldest-first.
        var byDay: [Date: Double] = [:]
        for s in latency { byDay[calendar.startOfDay(for: s.date)] = s.value }
        let nights = byDay.map { Sample(date: $0.key, value: $0.value) }
            .sorted { $0.date < $1.date }
        guard nights.count >= minimumNights else { return nil }

        let minutes = nights.map(\.value)
        let median = Self.median(minutes)

        // The trend, as a fitted line with its scatter — reusing the type every
        // other slope in this app is quoted through.
        let first = nights[0].date
        let x = nights.map { $0.date.timeIntervalSince(first) / 86_400 }
        let trend = Baseline.linearRegression(x: x, y: minutes).map {
            ScoreTrend(slopePerWeek: $0.slope * 7, residualSD: $0.residualSD,
                       start: first, intercept: $0.intercept,
                       slopePerDay: $0.slope, sampleCount: nights.count)
        }

        var drivers: [Driver] = []
        for (factor, values) in factors {
            var factorByDay: [Date: Double] = [:]
            for s in values { factorByDay[calendar.startOfDay(for: s.date)] = s.value }
            // Pair a driver value with the latency of the same night.
            let pairs = nights.compactMap { night -> (factor: Double, latency: Double)? in
                factorByDay[night.date].map { (factor: $0, latency: night.value) }
            }
            if let driver = factor.isSigned
                ? signedDriver(factor, pairs: pairs)
                : splitDriver(factor, pairs: pairs) {
                drivers.append(driver)
            }
        }
        drivers.sort { $0.deltaMinutes > $1.deltaMinutes }

        // What the app still cannot see. Screen time drops off this list the
        // moment the reader is actually entering it — the honesty runs both
        // ways, and naming a factor as unseen while charting it would be its
        // own kind of lie.
        var unseen = ["how late you ate"]
        if !factors.contains(where: { $0.0 == .screenTime }) {
            unseen.insert("screen or phone time before bed", at: 0)
        }
        return Output(nights: nights, trend: trend, medianMinutes: median,
                      nightsAnalysed: nights.count, drivers: drivers,
                      unseenFactors: unseen)
    }

    // MARK: - Contrasts

    /// More-vs-less: split the nights at the median driver value and contrast the
    /// mean latency of the two halves.
    private static func splitDriver(_ factor: Factor,
                                    pairs: [(factor: Double, latency: Double)]) -> Driver? {
        guard pairs.count >= 2 * minimumPerSide else { return nil }
        let sorted = pairs.sorted { $0.factor < $1.factor }
        let mid = sorted.count / 2
        let low = Array(sorted[..<mid])
        let high = Array(sorted[mid...])
        guard low.count >= minimumPerSide, high.count >= minimumPerSide,
              let lowMean = Baseline.mean(low.map(\.latency)),
              let highMean = Baseline.mean(high.map(\.latency)) else { return nil }
        let delta = highMean - lowMean
        guard abs(delta) >= minimumDeltaMinutes else { return nil }
        let r = Baseline.correlation(x: pairs.map(\.factor), y: pairs.map(\.latency))
        return Driver(
            factor: factor, deltaMinutes: delta,
            exposedNights: high.count, baselineNights: low.count, correlation: r,
            sentence: splitSentence(factor, delta: delta, nights: high.count))
    }

    /// Warm-vs-cool-vs-neutral, for temperature: contrast each extreme against
    /// the neutral nights and report whichever extreme cost more.
    private static func signedDriver(_ factor: Factor,
                                     pairs: [(factor: Double, latency: Double)]) -> Driver? {
        let warm = pairs.filter { $0.factor >= temperatureThreshold }
        let cool = pairs.filter { $0.factor <= -temperatureThreshold }
        let neutral = pairs.filter { abs($0.factor) < temperatureThreshold }
        guard neutral.count >= minimumPerSide,
              let neutralMean = Baseline.mean(neutral.map(\.latency)) else { return nil }

        func extreme(_ side: [(factor: Double, latency: Double)]) -> (Double, Int)? {
            guard side.count >= minimumPerSide,
                  let mean = Baseline.mean(side.map(\.latency)) else { return nil }
            return (mean - neutralMean, side.count)
        }
        let candidates = [(extreme(warm), "warmer"), (extreme(cool), "cooler")]
            .compactMap { pair -> (delta: Double, nights: Int, word: String)? in
                pair.0.map { (delta: $0.0, nights: $0.1, word: pair.1) }
            }
        // The extreme that delayed sleep most.
        guard let worst = candidates.max(by: { $0.delta < $1.delta }),
              worst.delta >= minimumDeltaMinutes else { return nil }
        return Driver(
            factor: factor, deltaMinutes: worst.delta,
            exposedNights: worst.nights, baselineNights: neutral.count, correlation: nil,
            sentence: "On nights your skin ran \(worst.word) than usual you took about "
                + "\(Int(worst.delta.rounded())) min longer to fall asleep, over "
                + "\(worst.nights) \(SleepOnsetModel.plural(worst.nights, "night")) — "
                + "an association, not proof it's the cause.")
    }

    private static func splitSentence(_ factor: Factor, delta: Double, nights: Int) -> String {
        let mins = Int(abs(delta).rounded())
        let dir = delta > 0 ? "longer" : "shorter"
        let lead: String
        switch factor {
        case .substances: lead = "On your higher-use evenings"
        case .medication: lead = "On nights with more medication in your system"
        case .eveningExertion: lead = "After your more active days"
        case .screenTime: lead = "On your heavier screen days"
        case .temperature: lead = "On your warmer nights"   // unreachable (signed)
        }
        return "\(lead) you fell asleep about \(mins) min \(dir), over \(nights) "
            + "\(plural(nights, "night")) — an association, not proof it's the cause."
    }

    // MARK: - Small helpers

    static func median(_ xs: [Double]) -> Double {
        guard !xs.isEmpty else { return 0 }
        let s = xs.sorted()
        let mid = s.count / 2
        return s.count.isMultiple(of: 2) ? (s[mid - 1] + s[mid]) / 2 : s[mid]
    }

    static func plural(_ n: Int, _ singular: String) -> String {
        n == 1 ? singular : singular + "s"
    }
}
