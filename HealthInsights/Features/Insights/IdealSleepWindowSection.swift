import SwiftUI
import Charts
import InsightKit

/// **"Your best bedtime"** — which bedtimes preceded the reader's own better
/// days, over as much of their history as exists.
///
/// The reader, 2026-08-07: *"I also want an ideal sleep timeframe section, which
/// will compare over a very long period the days you feel best vs the times you
/// went to sleep. I think oura does this."* (Backlog B18-8.)
///
/// The arithmetic — the weekend fold-out, the binning, the separation test and
/// the refusal to name a window when nothing separates the bins — is
/// `IdealSleepWindow` in InsightKit, where it is tested. This file makes two
/// decisions the model deliberately does not:
///
/// ## 1. The proxy for "days you feel best" is **next-day Readiness**
///
/// There is no sensor for feeling well, and the model refuses to choose a
/// stand-in for one. This section chooses, and prints the choice in the section
/// itself rather than in a footnote:
///
/// - **Readiness**, and not the Energy level, because Readiness is assembled
///   from that morning's own physiology — overnight HRV, resting heart rate,
///   temperature — where Energy is a modelled state carrying its own sleep term,
///   and asking a sleep-derived quantity which bedtime preceded good sleep is a
///   circle.
/// - **Readiness**, and not the feedback ledger, because the ledger is sparse:
///   it holds the days the reader chose to say something about, which are
///   systematically the unusual ones. That is the strongest proxy the app has
///   and the one to move to once the ledger is dense enough — noted here rather
///   than in a backlog row that would go stale.
///
/// ⚠️ Readiness's own history is a **replay**, so the caveat says so. It is what
/// today's model says about the data as it stood on each of those days.
///
/// ## 2. The span is the reader's history, not a choice
///
/// Whatever Readiness has been replayed over is what the answer rests on, and
/// the section prints the span and the night count rather than implying a
/// standing period.
struct IdealSleepWindowSection: View {
    @Environment(AppModel.self) private var model

    /// What this section calls "feeling best". Printed on screen wherever the
    /// finding is, because a bedtime finding without its outcome named is a
    /// horoscope.
    private static let outcomeName = "next-day Readiness"

    var body: some View {
        let history = model.scoreHistory(for: .readiness, days: 365)
        let analysis = model.memoized("idealSleepWindow.\(history.count)") {
            IdealSleepWindow.evaluate(
                onsets: model.sleepOnsetNights(days: 365),
                outcome: history.map { .init(date: $0.date, value: $0.score) },
                outcomeName: Self.outcomeName)
        }
        InsightSection(
            title: "Your best bedtime",
            trailing: trailing(analysis),
            caveat: .joined([.associationsNotCauses, .replayedHistory]),
            expansion: expansion(analysis)
        ) {
            verdictBody(analysis)
            if !analysis.bins.isEmpty {
                Divider()
                chart(analysis)
                footnotes(analysis)
            }
        }
    }

    private func trailing(_ analysis: IdealSleepWindow.Output) -> String? {
        switch analysis.verdict {
        case let .window(from, to, _):
            return "\(Self.clock(from))–\(Self.clock(to))"
        case .nothingSeparates, .notEnoughNights:
            return nil
        }
    }

    private func expansion(_ analysis: IdealSleepWindow.Output) -> SectionExpansion {
        switch analysis.verdict {
        case .window:
            return .open
        case .nothingSeparates:
            return .collapsed(preview: "No bedtime stood out — your \(Self.outcomeName) "
                              + "did not follow when you went to bed")
        case let .notEnoughNights(have, need):
            return .collapsed(preview: "\(have) of \(need) nights with both a bedtime "
                              + "and a \(Self.outcomeName) score so far")
        }
    }

    // MARK: - What it found

    @ViewBuilder
    private func verdictBody(_ analysis: IdealSleepWindow.Output) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            switch analysis.verdict {
            case let .window(from, to, betterBy):
                Text("\(Self.clock(from)) to \(Self.clock(to))")
                    .font(.title3.weight(.semibold)).monospacedDigit()
                Text(String(format: "Nights you started sleeping in that stretch were "
                            + "followed by days scoring about %.0f points better on %@ "
                            + "than the worst stretch — after taking out the weekend, "
                            + "which is the thing that usually fakes this finding.",
                            betterBy, analysis.outcomeName))
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            case .nothingSeparates:
                Text("No bedtime stands out")
                    .font(.title3.weight(.semibold))
                Text("There are enough nights to look, and your \(analysis.outcomeName) "
                     + "did not follow what time you went to bed — no half-hour ran far "
                     + "enough ahead of the rest to be worth naming. That is the "
                     + "ordinary answer for somebody whose bedtime is already steady, "
                     + "and it is a real result rather than a gap in the data.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            case let .notEnoughNights(have, need):
                Text("Not enough nights yet")
                    .font(.title3.weight(.semibold))
                Text("This holds every bedtime against the day that followed it, which "
                     + "needs \(need) nights with both recorded. There "
                     + "\(have == 1 ? "is" : "are") \(have) so far. It fills in on its "
                     + "own as you keep recording.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let jetlag = analysis.socialJetlagHours, abs(jetlag) >= 0.25 {
                Text(String(format: "Your weekend bedtime runs %.1f h %@ than your "
                            + "weekday one. That gap is removed before anything above "
                            + "is compared, so a late Friday cannot pose as a good "
                            + "bedtime.", abs(jetlag), jetlag > 0 ? "later" : "earlier"))
                    .font(.caption2).foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - The picture

    /// Bins of bedtime against how the following day went, relative to an
    /// ordinary day of the same kind.
    ///
    /// **`// substance-shading: exempt — the x axis is bedtime, not a date`**:
    /// a window that happened last Tuesday has nowhere to land on an axis whose
    /// points are clock times pooled across a year. This is the one exemption
    /// `add-chart` §9a allows, and it is the same one `FitnessProjectionChart`
    /// takes.
    ///
    /// It also cannot pan — the whole domain is on screen — so §9b's
    /// collapse rule has nothing to bite on here.
    @ViewBuilder
    private func chart(_ analysis: IdealSleepWindow.Output) -> some View {
        // substance-shading: exempt — the x axis is bedtime-of-night pooled over
        // a year, not a date, so a logged substance has no position on it.
        Chart {
            bars(analysis)
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 5)) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let hours = value.as(Double.self) {
                        Text(Self.clock(hours)).font(.caption2)
                    }
                }
            }
        }
        .chartYAxis { AxisMarks { _ in AxisGridLine(); AxisValueLabel().font(.caption2) } }
        .frame(height: 170)
    }

    /// Explicit `some ChartContent` (add-chart §2).
    @ChartContentBuilder
    private func bars(_ analysis: IdealSleepWindow.Output) -> some ChartContent {
        ForEach(analysis.bins) { bin in
            BarMark(x: .value("Bedtime", bin.centre),
                    y: .value("Better or worse than usual", bin.mean),
                    width: .fixed(18))
                // Signed against an ordinary day of the same kind, so the hue
                // says direction and nothing else. Not a score ramp: this is a
                // difference, and zero is the meaningful middle rather than the
                // bottom of a scale (add-chart §7a).
                .foregroundStyle(bin.mean >= 0 ? Theme.good.opacity(0.7)
                                               : Theme.warn.opacity(0.7))
        }
        // The spread each bar's height is known to, drawn as the interval it is.
        ForEach(analysis.bins.filter { $0.standardError != nil }) { bin in
            RuleMark(x: .value("Bedtime", bin.centre),
                     yStart: .value("Low", bin.mean - (bin.standardError ?? 0)),
                     yEnd: .value("High", bin.mean + (bin.standardError ?? 0)))
                .foregroundStyle(.secondary)
                .lineStyle(StrokeStyle(lineWidth: 1))
        }
        ForEach([0.0], id: \.self) { zero in
            RuleMark(y: .value("An ordinary day", zero))
                .lineStyle(Theme.referenceStroke)
                .foregroundStyle(.tertiary)
        }
    }

    @ViewBuilder
    private func footnotes(_ analysis: IdealSleepWindow.Output) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Each bar is a half-hour of bedtime. Its height is how the "
                 + "following day's \(analysis.outcomeName) compared with an ordinary "
                 + "day of the same kind — weekdays against weekdays, weekends "
                 + "against weekends. The whiskers are how well each bar is known.")
            Text("\(analysis.nights.count) nights"
                 + (analysis.span.map { span in
                     ", \(span.lowerBound.formatted(date: .abbreviated, time: .omitted))"
                         + " to \(span.upperBound.formatted(date: .abbreviated, time: .omitted))"
                 } ?? "")
                 + (analysis.thinBins > 0
                    ? " · \(analysis.thinBins) half-\(analysis.thinBins == 1 ? "hour" : "hours")"
                        + " had under \(IdealSleepWindow.minimumPerBin) nights and are not drawn"
                    : ""))
            Text("Bedtime is \(analysis.typicalOnset < 0 ? "usually" : "typically") "
                 + Self.clock(analysis.typicalOnset) + " for you.")
        }
        .font(.caption2).foregroundStyle(.tertiary)
        .fixedSize(horizontal: false, vertical: true)
    }

    /// Signed hours from midnight as a clock time — the `.sleepOnset` encoding,
    /// formatted the way `MetricValueFormatter` already does it so this section
    /// and the rest of the card cannot disagree about what −1.5 means.
    private static func clock(_ signedHours: Double) -> String {
        MetricValueFormatter.string(signedHours, .sleepOnset)
    }
}
