import Foundation

/// **The phase model and the fertile window.** Backlog #31 / §A3, slice 2.
///
/// `CycleLog.swift` is the log and the arithmetic over it — what was recorded,
/// how long the cycles were, how much they varied. This file is the only place
/// that says anything the log does not literally contain: which phase a day sits
/// in, when ovulation probably was, and which days form the fertile window.
///
/// ## ⚠️ This is information, never contraception
///
/// `notContraceptionNotice` below is the sentence that must reach the screen —
/// small and permanent, not folded behind a disclosure. Nothing in this file may
/// be worded as advice about conceiving or avoiding conception. A fertile window
/// used to *prevent* pregnancy is a regulated medical claim (it is what makes
/// Natural Cycles a cleared device rather than an app), and this is not one. The
/// wording rule is therefore mechanical: every sentence this file produces
/// describes *when the body probably did something*, and none of them describes
/// what the reader should do about it.
///
/// ## The physiology this encodes, and why it is not symmetric
///
/// A cycle has two halves and **only one of them is stable**. After ovulation
/// the corpus luteum has a roughly fixed lifespan, so the luteal phase runs
/// about 14 days in almost everybody and varies by only a day or two; the
/// follicular phase — from the first bleeding day to ovulation — absorbs
/// essentially all of the variation in total cycle length. Lenton, Landgren and
/// Sexton's paired 1984 papers in the *British Journal of Obstetrics and
/// Gynaecology* measured both halves separately and are the standard citation
/// for the asymmetry; Fehring, Schneider and Raviele (*JOGNN*, 2006) reproduced
/// it in a larger modern sample.
///
/// **This is why ovulation is estimated backwards from the next period and never
/// forwards from the last one.** "Day 14 of your cycle" is the single most
/// common thing a consumer tracker gets wrong: it takes a population mean cycle
/// length, halves it, and prints a day. On a reader whose cycles run 24 to 34
/// days, forward-counting puts ovulation up to five days out in a window six
/// days long — which is to say, it misses.
///
/// ## Every boundary carries the reader's own spread
///
/// The ± on a predicted boundary is derived from the reader's own cycle-length
/// range, not from a textbook constant. A textbook constant appears in exactly
/// one place — the ±2 days on the luteal length itself — and it is *added* to
/// the reader's spread rather than replacing it.
public enum CyclePhase: String, Sendable, Codable, CaseIterable, Identifiable {
    /// Bleeding. **The only phase that is observed rather than modelled** — it
    /// is exactly the days in the log, which is why it can be named from a
    /// single cycle while everything else needs three.
    case menstrual
    /// From the end of bleeding to the approach of ovulation. The variable half:
    /// when a cycle is long or short, this is where the difference lives.
    case follicular
    /// Ovulation and the day either side of it.
    case ovulatory
    /// From ovulation to the next period. The stable half, ~14 days.
    case luteal

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .menstrual: return "Menstrual"
        case .follicular: return "Follicular"
        case .ovulatory: return "Ovulatory"
        case .luteal: return "Luteal"
        }
    }
}

/// Where one day sits, and how sure the model is that it sits there.
public struct CyclePhaseEstimate: Sendable, Equatable {
    public let phase: CyclePhase
    /// 1-based day of the whole cycle — day 1 is the first bleeding day.
    public let dayOfCycle: Int
    /// 1-based day within `phase`.
    public let dayInPhase: Int
    /// The ± on `dayInPhase`, in days: how far the boundary this phase is
    /// counted *from* could move. Zero when that boundary was observed.
    public let dayInPhaseUncertaintyDays: Int
    /// True when the day sits close enough to a movable boundary that the phase
    /// *name* is a coin toss — the difference between "you are in the luteal
    /// phase" and "you are probably in the luteal phase".
    public let isBoundaryAmbiguous: Bool
    /// True when nothing about this estimate was predicted: the day is a logged
    /// bleeding day inside a period the log records.
    public let isObserved: Bool
    /// The days this phase is estimated to span.
    public let bounds: ClosedRange<Date>
}

/// The days a conception could plausibly follow from, with the uncertainty that
/// produced them.
///
/// ⚠️ **Information, not contraception.** See `CyclePhaseModel`'s doc comment.
public struct FertileWindow: Sendable, Equatable {
    /// The single most likely ovulation day.
    public let ovulation: Date
    /// The ± on `ovulation`, in days.
    public let uncertaintyDays: Int
    /// **Ovulation minus five days through ovulation day itself.**
    ///
    /// The six-day interval is Wilcox, Weinberg and Baird (*NEJM*, 1995,
    /// "Timing of sexual intercourse in relation to ovulation"): across 625
    /// cycles from women attempting to conceive, every observed conception
    /// followed intercourse inside a six-day interval **ending on the day of
    /// ovulation**. The window is asymmetric because sperm survive in the
    /// reproductive tract for several days and an unfertilised ovum does not —
    /// which is why it opens five days early and closes the same day.
    public let core: ClosedRange<Date>
    /// `core` widened by `uncertaintyDays` at both ends: where the window could
    /// be, given that ovulation itself is an estimate. The UI draws this as the
    /// softened edge and `core` as the solid middle.
    public let outer: ClosedRange<Date>
}

/// A prediction the model is willing to make.
public struct CyclePrediction: Sendable, Equatable {
    public let nextPeriodStart: Date
    /// The ± on `nextPeriodStart`, from the reader's own cycle-length spread.
    public let nextPeriodUncertaintyDays: Int
    public let fertileWindow: FertileWindow
    /// How many completed cycles it was computed from. Carried so the UI can
    /// say it: a prediction from three cycles and one from twelve are not the
    /// same claim, and only one of them knows it.
    public let basedOnCycles: Int
}

/// Why the model declined, in a form the UI can render exhaustively.
///
/// **A refusal is a state, not an error.** Every branch has a sentence, because
/// the empty state a reader sees most often is the one from before they had
/// enough data, and "—" teaches them nothing about what would fix it.
public enum CycleForecastRefusal: Sendable, Equatable {
    case nothingLogged
    /// Fewer than `CyclePhaseModel.minimumCyclesForPrediction` completed cycles.
    case tooFewCycles(have: Int, need: Int)
    /// The log stopped: there is no cycle plausibly in progress to predict from.
    case logStale
    /// The reader's own cycles vary so much that the honest interval is wider
    /// than a fertile window is long.
    case tooVariable(spreadDays: Int, uncertaintyDays: Int)

    /// What to put on screen. First person plural is avoided on purpose — the
    /// app is describing the log, not apologising for itself.
    public var sentence: String {
        switch self {
        case .nothingLogged:
            return "Nothing logged yet. A phase and a fertile window are worked out from your own cycles, so this starts once there are some."
        case let .tooFewCycles(have, need):
            let more = need - have
            return "\(have) complete cycle\(have == 1 ? "" : "s") logged. \(more) more and this can place your phase and your fertile window. A window drawn from \(have) cycle\(have == 1 ? "" : "s") is a guess wearing an interval — the range would be real arithmetic over numbers too few to mean anything."
        case .logStale:
            return "The last logged period is too long ago to predict from. Log the next one and this picks up again."
        case let .tooVariable(spread, uncertainty):
            return "Your cycles have varied by \(spread) days, which puts ±\(uncertainty) days on any ovulation estimate. That is wider than the fertile window itself, so drawing one would be marking most of the month and calling it a prediction."
        }
    }
}

/// A prediction, or a stated reason there is none.
public enum CycleForecast: Sendable, Equatable {
    case forecast(CyclePrediction)
    case refused(CycleForecastRefusal)

    public var prediction: CyclePrediction? {
        if case let .forecast(prediction) = self { return prediction }
        return nil
    }

    public var refusal: CycleForecastRefusal? {
        if case let .refused(reason) = self { return reason }
        return nil
    }
}

public enum CyclePhaseModel {

    /// ⚠️ **The sentence that must be on the screen, not in a disclosure.**
    ///
    /// A fertile window presented as a way to avoid pregnancy is a regulated
    /// medical claim — it is the whole reason Natural Cycles needed clearance
    /// and a period tracker does not. This app makes no such claim and the
    /// screen has to say so where it cannot be missed. Kept here rather than in
    /// the view so a test can pin it and a redesign cannot quietly drop it.
    public static let notContraceptionNotice =
        "This is information about your own cycle. It is not contraception and not fertility advice — an estimated window is not a safe day."

    /// **The stable half of the cycle, in days.**
    ///
    /// The corpus luteum has a roughly fixed functional lifespan, so the
    /// interval from ovulation to the next period is about 14 days in almost
    /// everyone and varies by only a day or two, while the follicular phase
    /// absorbs essentially all of the between-cycle variation. Lenton, Landgren
    /// and Sexton (*BJOG*, 1984) measured the two halves separately and are the
    /// standard citation; Fehring, Schneider and Raviele (*JOGNN*, 2006)
    /// reproduced it in a larger modern sample with a mean luteal length a
    /// little over 13 days.
    ///
    /// Used **backwards from the next predicted period, never forwards from the
    /// last one**, because forward-counting puts the variable half's error
    /// straight onto the ovulation estimate.
    public static let lutealLengthDays = 14

    /// The textbook ± on `lutealLengthDays`, in days.
    ///
    /// Reported luteal-length standard deviations sit around 1.5 days in the
    /// sources above. Rounded **up** to 2 rather than to the nearest whole day,
    /// because the two errors are not symmetric in cost: a window that is too
    /// wide is unhelpful, and one that is too narrow is wrong in the direction
    /// that matters.
    ///
    /// ⚠️ This is the only textbook constant in the uncertainty, and it is
    /// **added to** the reader's own spread rather than used instead of it.
    public static let lutealLengthUncertaintyDays = 2

    /// How many days before ovulation the fertile window opens.
    ///
    /// Five, from Wilcox, Weinberg and Baird (*NEJM*, 1995): every conception
    /// observed across 625 cycles followed intercourse within a six-day interval
    /// ending on the day of ovulation. Sperm survive in the reproductive tract
    /// for several days; the ovum does not, which is why the interval is
    /// one-sided.
    public static let fertileDaysBeforeOvulation = 5

    /// How far either side of the ovulation estimate is called "ovulatory".
    ///
    /// One day. A labelling convention rather than a measurement — ovulation is
    /// an event, not a phase — kept narrow so the label does not eat the
    /// follicular and luteal phases it sits between.
    public static let ovulatoryRadiusDays = 1

    /// Completed cycles required before any prediction is offered.
    ///
    /// Three, and deliberately the same number as
    /// `CycleModel.minimumCyclesForRange`: the whole prediction is built on the
    /// reader's own spread, and the spread is the thing that needs three
    /// observations. Two cycles produce an interval that is arithmetically
    /// well-formed and epistemically empty.
    public static let minimumCyclesForPrediction = CycleModel.minimumCyclesForRange

    /// The widest ± on ovulation that is still worth drawing, in days.
    ///
    /// Derived, not chosen: the fertile window is six days long, so a ± of
    /// seven days makes the outer window twenty days wide — most of a cycle.
    /// Past this the honest output is the refusal, and the refusal says the
    /// spread out loud.
    public static let maximumUsefulUncertaintyDays = 7

    /// A day this many days past the start of a cycle stops being a cycle in
    /// progress. Matches `CycleModel.summarise`'s own staleness rule, which is
    /// what `CycleSummary.currentDay` already applies.
    public static let staleAfterDays = 90

    // MARK: - The forecast

    /// The next period, ovulation and the fertile window — or why not.
    ///
    /// The chain, and every step of its uncertainty:
    ///
    /// 1. `nextPeriodStart = current cycle start + median completed length`.
    ///    Median rather than mean, for the reason `CycleSummary.medianLength`
    ///    gives: one long cycle after an illness should not move the typical
    ///    figure.
    /// 2. Its ± is **half the reader's own observed length range**, floored at
    ///    one day. Half the range is the symmetric interval about the median
    ///    that covers every length actually observed. The floor exists because
    ///    three identical cycles do not prove zero variability — they prove the
    ///    variability is smaller than three observations can resolve.
    /// 3. `ovulation = nextPeriodStart − lutealLengthDays`.
    /// 4. Its ± is the next-period ± **plus** `lutealLengthUncertaintyDays`.
    ///    Added rather than combined in quadrature: quadrature is the right
    ///    move for independent random errors of known distribution, and these
    ///    are one observed range and one literature standard deviation. Adding
    ///    keeps the interval conservative, which is the direction the cost of
    ///    being wrong points.
    /// 5. The fertile window is `ovulation − 5 … ovulation`, and its outer edge
    ///    is that widened by the ovulation ± on both sides.
    public static func forecast(_ summary: CycleSummary, now: Date = Date(),
                                calendar: Calendar = .current) -> CycleForecast {
        guard !summary.cycles.isEmpty else { return .refused(.nothingLogged) }
        guard summary.lengths.count >= minimumCyclesForPrediction else {
            return .refused(.tooFewCycles(have: summary.lengths.count,
                                          need: minimumCyclesForPrediction))
        }
        guard let current = summary.current, summary.currentDay != nil,
              let median = summary.medianLength, let spread = summary.spread
        else { return .refused(.logStale) }

        let nextUncertainty = Swift.max(1, Int((Double(spread) / 2).rounded(.up)))
        let ovulationUncertainty = nextUncertainty + lutealLengthUncertaintyDays
        guard ovulationUncertainty <= maximumUsefulUncertaintyDays else {
            return .refused(.tooVariable(spreadDays: spread,
                                         uncertaintyDays: ovulationUncertainty))
        }

        guard let nextStart = calendar.date(byAdding: .day, value: median, to: current.start),
              let window = fertileWindow(nextPeriodStart: nextStart,
                                         uncertaintyDays: ovulationUncertainty,
                                         calendar: calendar)
        else { return .refused(.logStale) }

        return .forecast(CyclePrediction(nextPeriodStart: nextStart,
                                         nextPeriodUncertaintyDays: nextUncertainty,
                                         fertileWindow: window,
                                         basedOnCycles: summary.lengths.count))
    }

    /// The window implied by a period start, predicted or observed.
    ///
    /// Split out because a *completed* cycle knows when the next period actually
    /// began, so its window carries only the luteal constant's ± — a
    /// retrospective estimate is genuinely tighter than a forward one, and
    /// flattening the two would throw that away.
    static func fertileWindow(nextPeriodStart: Date, uncertaintyDays: Int,
                              calendar: Calendar) -> FertileWindow? {
        guard let ovulation = calendar.date(byAdding: .day, value: -lutealLengthDays,
                                            to: nextPeriodStart),
              let coreStart = calendar.date(byAdding: .day, value: -fertileDaysBeforeOvulation,
                                            to: ovulation),
              let outerStart = calendar.date(byAdding: .day, value: -uncertaintyDays,
                                             to: coreStart),
              let outerEnd = calendar.date(byAdding: .day, value: uncertaintyDays,
                                           to: ovulation)
        else { return nil }
        return FertileWindow(ovulation: ovulation, uncertaintyDays: uncertaintyDays,
                             core: coreStart...ovulation, outer: outerStart...outerEnd)
    }

    // MARK: - The phase of one day

    /// Which phase `date` sits in, with the ± that belongs to it.
    ///
    /// Two paths, and the difference between them is the honest part:
    ///
    /// - **A logged bleeding day is menstrual, full stop.** No model, no ±, no
    ///   minimum number of cycles. It is a record of what happened.
    /// - **Everything else needs the forecast to have succeeded**, even for a
    ///   day in a completed cycle whose both ends were observed. That is
    ///   stricter than the arithmetic requires and it is deliberate: a calendar
    ///   that shades last month's luteal phase while the headline says it cannot
    ///   place your phase yet is a screen arguing with itself.
    ///
    /// Returns nil for a date outside every recorded cycle, or when the forecast
    /// refused.
    public static func phase(on date: Date, summary: CycleSummary,
                             now: Date = Date(),
                             calendar: Calendar = .current) -> CyclePhaseEstimate? {
        let day = calendar.startOfDay(for: date)
        guard let cycle = cycle(containing: day, in: summary, calendar: calendar) else {
            return nil
        }

        // The observed path. `days` holds exactly what was logged, so a gap
        // inside a period — which `CycleModel` deliberately does not split on —
        // still counts as menstrual, because the period it belongs to is one
        // period.
        let isBleedingDay = day >= cycle.start && day <= cycle.periodEnd
        if isBleedingDay {
            return CyclePhaseEstimate(
                phase: .menstrual,
                dayOfCycle: dayCount(from: cycle.start, to: day, calendar: calendar) + 1,
                dayInPhase: dayCount(from: cycle.start, to: day, calendar: calendar) + 1,
                dayInPhaseUncertaintyDays: 0,
                isBoundaryAmbiguous: false,
                isObserved: true,
                bounds: cycle.start...cycle.periodEnd)
        }

        guard case .forecast = forecast(summary, now: now, calendar: calendar),
              let bounds = boundaries(for: cycle, in: summary, now: now, calendar: calendar)
        else { return nil }
        return estimate(for: day, cycle: cycle, bounds: bounds, calendar: calendar)
    }

    /// The four boundaries of one cycle, and what is uncertain about each.
    struct PhaseBoundaries: Equatable {
        let periodEnd: Date
        let ovulatory: ClosedRange<Date>
        let nextStart: Date
        /// Zero when the next period is a fact rather than a prediction.
        let nextStartUncertainty: Int
        let ovulationUncertainty: Int
    }

    static func boundaries(for cycle: Cycle, in summary: CycleSummary, now: Date,
                           calendar: Calendar) -> PhaseBoundaries? {
        let nextStart: Date
        let nextUncertainty: Int
        if let end = cycle.end, let observed = calendar.date(byAdding: .day, value: 1, to: end) {
            // A completed cycle: the next period is recorded, not guessed.
            nextStart = observed
            nextUncertainty = 0
        } else {
            guard let prediction = forecast(summary, now: now, calendar: calendar).prediction
            else { return nil }
            nextStart = prediction.nextPeriodStart
            nextUncertainty = prediction.nextPeriodUncertaintyDays
        }

        let ovulationUncertainty = nextUncertainty + lutealLengthUncertaintyDays
        guard let ovulation = calendar.date(byAdding: .day, value: -lutealLengthDays,
                                            to: nextStart),
              let rawStart = calendar.date(byAdding: .day, value: -ovulatoryRadiusDays,
                                           to: ovulation),
              let rawEnd = calendar.date(byAdding: .day, value: ovulatoryRadiusDays,
                                         to: ovulation),
              let afterPeriod = calendar.date(byAdding: .day, value: 1, to: cycle.periodEnd),
              let beforeNext = calendar.date(byAdding: .day, value: -1, to: nextStart)
        else { return nil }

        // Clamping, for the short cycle where 14 days back from the next period
        // lands on or inside the period itself. It happens — a 21-day cycle with
        // a 7-day period leaves no room — and an unclamped range would run
        // backwards, which `ClosedRange` traps on rather than tolerates.
        let start = Swift.min(Swift.max(rawStart, afterPeriod), beforeNext)
        let end = Swift.min(Swift.max(rawEnd, start), beforeNext)

        return PhaseBoundaries(periodEnd: cycle.periodEnd, ovulatory: start...end,
                               nextStart: nextStart, nextStartUncertainty: nextUncertainty,
                               ovulationUncertainty: ovulationUncertainty)
    }

    private static func estimate(for day: Date, cycle: Cycle, bounds: PhaseBoundaries,
                                 calendar: Calendar) -> CyclePhaseEstimate? {
        let dayOfCycle = dayCount(from: cycle.start, to: day, calendar: calendar) + 1
        guard let afterPeriod = calendar.date(byAdding: .day, value: 1, to: bounds.periodEnd),
              let afterOvulatory = calendar.date(byAdding: .day, value: 1,
                                                 to: bounds.ovulatory.upperBound),
              let beforeOvulatory = calendar.date(byAdding: .day, value: -1,
                                                  to: bounds.ovulatory.lowerBound),
              let beforeNext = calendar.date(byAdding: .day, value: -1, to: bounds.nextStart)
        else { return nil }

        let phase: CyclePhase
        let phaseBounds: ClosedRange<Date>
        // ⚠️ **Each boundary carries its own ±, and they are not the same.**
        // Getting this wrong is the whole reason the estimate is honest or is
        // not: the follicular phase *begins* on the day after the last logged
        // bleeding day, which is a fact, and *ends* at an estimated ovulation.
        // A single "phase uncertainty" would either invent doubt about the
        // observed end or hide it at the modelled one.
        let startUncertainty: Int
        let endUncertainty: Int

        if day < afterPeriod {
            return nil                                   // handled by the observed path
        } else if day < bounds.ovulatory.lowerBound {
            phase = .follicular
            phaseBounds = afterPeriod...beforeOvulatory
            startUncertainty = 0                         // the log says when bleeding stopped
            endUncertainty = bounds.ovulationUncertainty
        } else if day <= bounds.ovulatory.upperBound {
            phase = .ovulatory
            phaseBounds = bounds.ovulatory
            startUncertainty = bounds.ovulationUncertainty
            endUncertainty = bounds.ovulationUncertainty
        } else if day <= beforeNext {
            phase = .luteal
            phaseBounds = afterOvulatory...beforeNext
            startUncertainty = bounds.ovulationUncertainty
            endUncertainty = bounds.nextStartUncertainty
        } else {
            return nil                                   // past this cycle
        }

        let dayInPhase = dayCount(from: phaseBounds.lowerBound, to: day, calendar: calendar) + 1
        let toLower = dayCount(from: phaseBounds.lowerBound, to: day, calendar: calendar)
        let toUpper = dayCount(from: day, to: phaseBounds.upperBound, calendar: calendar)
        // "Ambiguous" is not a hedge word: the day sits inside the distance one
        // of its boundaries could move, so the phase on the other side of that
        // boundary is as consistent with the log as this one. Checked against
        // both edges rather than the nearer one — a short phase can be within
        // reach of the modelled edge while sitting right on the observed one.
        let ambiguous = toLower < startUncertainty || toUpper < endUncertainty

        return CyclePhaseEstimate(phase: phase, dayOfCycle: dayOfCycle,
                                  dayInPhase: dayInPhase,
                                  dayInPhaseUncertaintyDays: startUncertainty,
                                  isBoundaryAmbiguous: ambiguous,
                                  isObserved: false,
                                  bounds: phaseBounds)
    }

    /// The cycle a day falls inside, if any.
    ///
    /// The running cycle is bounded by `staleAfterDays` rather than left open:
    /// without it, a log abandoned last year would claim every day since.
    static func cycle(containing day: Date, in summary: CycleSummary,
                      calendar: Calendar) -> Cycle? {
        for cycle in summary.cycles.reversed() where day >= cycle.start {
            if let end = cycle.end { if day <= end { return cycle } }
            else if dayCount(from: cycle.start, to: day, calendar: calendar) < staleAfterDays {
                return cycle
            }
        }
        return nil
    }

    static func dayCount(from: Date, to: Date, calendar: Calendar) -> Int {
        calendar.dateComponents([.day], from: calendar.startOfDay(for: from),
                                to: calendar.startOfDay(for: to)).day ?? 0
    }

    // MARK: - What the screen says

    /// The phase line. **Never a bare assertion**: it either names an observed
    /// fact or hedges in proportion to the ± it just computed.
    public static func phaseSentence(_ estimate: CyclePhaseEstimate) -> String {
        if estimate.isObserved {
            return "Menstrual, day \(estimate.dayInPhase) — from your log, not a guess."
        }
        let plusMinus = estimate.dayInPhaseUncertaintyDays > 0
            ? " ±\(estimate.dayInPhaseUncertaintyDays)" : ""
        let lead = estimate.isBoundaryAmbiguous ? "Probably " : "Likely "
        return "\(lead)\(estimate.phase.title.lowercased()), day \(estimate.dayInPhase)\(plusMinus)"
    }

    /// The one line under the fertile window. Says what the window is derived
    /// from, because a window with no stated basis is indistinguishable from a
    /// window copied out of a textbook.
    public static func fertileWindowSentence(_ prediction: CyclePrediction,
                                             calendar: Calendar = .current) -> String {
        let window = prediction.fertileWindow
        let opens = window.core.lowerBound.formatted(date: .abbreviated, time: .omitted)
        let closes = window.core.upperBound.formatted(date: .abbreviated, time: .omitted)
        return "Most likely \(opens) to \(closes), working back \(lutealLengthDays) days from a period expected around \(prediction.nextPeriodStart.formatted(date: .abbreviated, time: .omitted)). Ovulation itself is ±\(window.uncertaintyDays) days, which is why the edges are soft — that figure is \(prediction.basedOnCycles) of your own cycles, not an average of other people's."
    }
}
