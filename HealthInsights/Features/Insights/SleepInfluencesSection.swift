import SwiftUI
import Charts
import InsightKit

/// **"What's impacting your sleep"** — the first section in this app built out
/// of other cards' own conclusions.
///
/// The reader, 2026-08-07: *"I want a dedicated bespoke section for 'what is
/// impacting your sleep' and mainly focus on how work, stress, anxiety, food,
/// Screen time and other major life factors are impacting sleep.. this is where
/// we can finally start using the derived outcomes of cards to build new cards
/// and sections like this."* (Backlog B18-6.)
///
/// Every card has declared its figures as `DerivedSeriesID`s since 2026-08-06,
/// and until now nothing consumed that pool. This does.
///
/// ---
///
/// # What this file decides, and what InsightKit decides
///
/// **The statistics are `SleepInfluences`, in InsightKit, where they are
/// tested** — the same-day activity covariate, the fixed day boundary, the
/// circular block permutation null and the max-statistic multiplicity control.
/// Read that file before changing anything about how a finding is reached; each
/// of those four is a fault that was found in this repo's own substance card by
/// an independent review, and each alone produces confident nonsense.
///
/// This file decides three things the model cannot:
///
/// ## 1. Which candidates enter the family
///
/// **Only `.modelOutput` derived series, and only from cards other than Sleep.**
///
/// - `.modelOutput` is the tier the reader actually named — *the derived
///   outcomes of cards*. The other two tiers (`componentScore`,
///   `componentDeparture`) are per-metric restatements harvested for free, and
///   there are roughly ninety of them; putting them in would multiply the family
///   by an order of magnitude and cost every real finding its significance to
///   buy nothing the model outputs do not already say.
/// - **Sleep's own figures are excluded.** Asking whether sleep debt predicts
///   sleep duration is asking whether a quantity computed from the series
///   predicts the series.
///
/// Alongside them, the three **measured** life factors the reader named that are
/// not any card's derived output: screen time, caffeine and the day's food
/// energy. They are listed explicitly rather than swept up, so the family is
/// something a person can read, and it is fixed before the answer is seen.
///
/// ## 2. What "your sleep" means here
///
/// **The night's duration in hours** — measured, unambiguous, and present for
/// anybody with a sleep source. Not the Sleep score: that is a blend this card
/// computes, so a finding against it would be partly a finding about the app's
/// own weighting, and it moves whenever the weights move.
///
/// ## 3. That the ordinary answer is "nothing stands out"
///
/// It is rendered as a finding in its own right, with the number of candidates
/// tested, because *"we looked at eleven things over ninety nights and none of
/// them moved your sleep further than chance would"* is a real and useful
/// sentence — and because a section that only ever renders when it has something
/// to say teaches the reader that silence means no data.
struct SleepInfluencesSection: View {
    @Environment(AppModel.self) private var model

    /// The measured life factors, named here rather than swept up. Fixed before
    /// the answer is seen — a candidate list chosen after looking is a
    /// hyperparameter fitted to noise.
    private static let measuredCandidates: [MetricType] = [
        .screenTimeMinutes, .dietaryCaffeine, .dietaryEnergy
    ]

    var body: some View {
        let analysis = model.memoized("sleepInfluences") { self.analyse() }
        InsightSection(
            title: "What's impacting your sleep",
            trailing: trailing(analysis),
            caveat: .joined([.associationsNotCauses, .replayedHistory]),
            expansion: expansion(analysis)
        ) {
            body(for: analysis)
            Divider()
            method(analysis)
        }
    }

    // MARK: - Assembling the candidates

    private func analyse() -> SleepInfluences.Output {
        let store = model.derivedSeries
        var drivers: [SleepInfluences.Driver] = []

        for spec in store.series(ofKind: .modelOutput)
        where spec.producedBy != .sleep {
            let points = store.series(spec.id)
                .map { VitalReader.DailyValue(date: $0.day, value: $0.value) }
            guard !points.isEmpty else { continue }
            drivers.append(.init(id: spec.id.rawValue, name: spec.displayName,
                                 producedBy: spec.producedBy, unit: spec.unit,
                                 values: points))
        }

        for metric in Self.measuredCandidates {
            let points = VitalReader.dailySeries(metric, from: model.samples, days: 365)
            guard !points.isEmpty else { continue }
            drivers.append(.init(id: metric.rawValue, name: metric.displayName,
                                 producedBy: nil, unit: metric.unit, values: points))
        }

        // The same-day activity covariate. Steps where they exist, active energy
        // where they do not — one or the other, never blended, because they are
        // different quantities and `VitalReader` has spent a page of reasoning on
        // why pooling two instruments' idea of one thing is how variance is
        // invented.
        var activity = VitalReader.dailySeries(.stepCount, from: model.samples, days: 365)
        if activity.isEmpty {
            activity = VitalReader.dailySeries(.activeEnergyBurned,
                                               from: model.samples, days: 365)
        }

        return SleepInfluences.evaluate(
            outcome: VitalReader.dailySeries(.sleepDurationHours,
                                             from: model.samples, days: 365),
            outcomeName: "how long you slept",
            outcomeUnit: "h",
            drivers: drivers,
            activity: activity)
    }

    // MARK: - Header

    private func trailing(_ analysis: SleepInfluences.Output) -> String? {
        switch analysis.verdict {
        case .found:
            let count = analysis.findings.count
            return "\(count) of \(analysis.tested) stood out"
        case .nothingStandsOut:
            return "\(analysis.tested) checked"
        case .notEnoughDays, .nothingTestable, .nothingToCompare:
            return nil
        }
    }

    private func expansion(_ analysis: SleepInfluences.Output) -> SectionExpansion {
        switch analysis.verdict {
        case .found:
            return .open
        case .nothingStandsOut:
            return .collapsed(preview: "Nothing has happened often enough to tell it "
                              + "from an ordinary run")
        case let .notEnoughDays(best, need):
            return .collapsed(preview: "The closest candidate overlaps your nights on "
                              + "\(best) of the \(need) days this needs")
        case .nothingTestable:
            return .collapsed(preview: "Everything on offer turned out to be how active "
                              + "you were that day, which is already in the model")
        case .nothingToCompare:
            return .collapsed(preview: "Nothing to hold your sleep against yet")
        }
    }

    // MARK: - Findings

    @ViewBuilder
    private func body(for analysis: SleepInfluences.Output) -> some View {
        switch analysis.verdict {
        case .found:
            VStack(alignment: .leading, spacing: 10) {
                ForEach(analysis.findings) { finding in
                    row(finding, unit: analysis.outcomeUnit, tested: analysis.tested)
                }
            }
            chart(analysis)
        case .nothingStandsOut:
            statement(
                "Nothing stands out",
                "\(analysis.tested) \(analysis.tested == 1 ? "thing" : "things") this app "
                    + "already works out were held against \(analysis.outcomeName), and "
                    + "none of them moved it further than an ordinary run of days would. "
                    + "That is the usual answer and a real one: it means nothing has "
                    + "happened often enough, or hard enough, to be told apart from "
                    + "chance.")
        case let .notEnoughDays(best, need):
            statement(
                "Not enough overlapping days yet",
                "Holding something against your sleep needs \(need) days on which both "
                    + "were recorded, so the same-day activity adjustment has something "
                    + "to work with. The closest candidate has \(best). This fills in on "
                    + "its own as the other cards keep working things out.")
        case .nothingTestable:
            statement(
                "Nothing left to test",
                "Every candidate here turned out to move almost exactly with how active "
                    + "you were that day — and the day's activity is already taken out "
                    + "before anything is compared, precisely so a busy day cannot pose "
                    + "as a cause. There is nothing left in them to hold against your "
                    + "sleep.")
        case .nothingToCompare:
            statement(
                "Nothing to hold your sleep against yet",
                "This section is built from what your other cards work out. Once a few "
                    + "of them have been running for a while — work impact, stress, "
                    + "mental health, screen time — their figures appear here as "
                    + "candidates.")
        }
        if !analysis.untested.isEmpty {
            Text("Left out: " + analysis.untested.map(\.sentence).joined(separator: ", ")
                 + ". A candidate needs \(SleepInfluences.minimumPairs) overlapping days "
                 + "and has to move by something other than that day's activity.")
                .font(.caption2).foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func statement(_ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.title3.weight(.semibold))
            Text(detail).font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private func row(_ finding: SleepInfluences.Finding, unit: String,
                     tested: Int) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(finding.name).font(.subheadline.weight(.semibold))
                Spacer(minLength: 8)
                Text(String(format: "%+.2f %@", finding.effectPerSD, unit))
                    .font(.subheadline.weight(.semibold)).monospacedDigit()
                    .foregroundStyle(finding.effectPerSD >= 0 ? Theme.good : Theme.warn)
            }
            Text(sentence(finding, unit: unit))
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            // The adjusted p, never a raw one, and always beside the number of
            // checks it was adjusted for — a p-value without its family is the
            // multiplicity error printed on screen.
            Text(String(format: "%d nights · p = %.3f, already allowing for all %d checks",
                        finding.pairs, finding.adjustedP, tested))
                .font(.caption2).foregroundStyle(.tertiary).monospacedDigit()
        }
    }

    /// The card a derived figure came from, by its own title. Read off the
    /// evaluated results rather than a second table of names, so a renamed card
    /// renames itself here.
    private func cardTitle(_ id: InsightID) -> String? {
        model.results.first { $0.id == id }?.title
    }

    private func sentence(_ finding: SleepInfluences.Finding, unit: String) -> String {
        let direction = finding.effectPerSD >= 0 ? "more" : "less"
        let source = finding.producedBy.flatMap(cardTitle).map { "From your \($0) card. " } ?? ""
        return source
            + String(format: "A typical swing in this — one standard deviation — went "
                     + "with about %.2f %@ %@ sleep that night, once the same day's "
                     + "activity and whether the next morning was a free one were "
                     + "taken out.", abs(finding.effectPerSD), unit, direction)
    }

    // MARK: - The picture
    //
    // Only drawn when there is something to draw. A bar per finding, signed, on
    // the outcome's own axis — the quantity a reader can act on, where a
    // correlation is not.

    /// **`// substance-shading: exempt`** — see the marker in the body: the x
    /// axis is hours of sleep per standard deviation of a driver, not a date, so
    /// a logged substance has nowhere to land. It also cannot pan, so §9b's
    /// collapse rule has nothing to bite on.
    @ViewBuilder
    private func chart(_ analysis: SleepInfluences.Output) -> some View {
        // substance-shading: exempt — the x axis is an effect size in hours, not
        // a date; a window that happened on Tuesday has no position on it.
        Chart {
            effectBars(analysis)
        }
        .chartXAxis { AxisMarks { _ in AxisGridLine(); AxisValueLabel().font(.caption2) } }
        .chartYAxis { AxisMarks { _ in AxisValueLabel().font(.caption2) } }
        .frame(height: CGFloat(analysis.findings.count) * 34 + 30)
    }

    /// Explicit `some ChartContent` (add-chart §2).
    @ChartContentBuilder
    private func effectBars(_ analysis: SleepInfluences.Output) -> some ChartContent {
        ForEach(analysis.findings) { finding in
            BarMark(x: .value("Hours of sleep per typical swing", finding.effectPerSD),
                    y: .value("What", finding.name))
                .foregroundStyle(finding.effectPerSD >= 0 ? Theme.good.opacity(0.7)
                                                          : Theme.warn.opacity(0.7))
        }
        ForEach([0.0], id: \.self) { zero in
            RuleMark(x: .value("No effect", zero))
                .lineStyle(Theme.referenceStroke)
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: - How it was worked out
    //
    // Printed on screen, not only in the source. The reader is being shown a
    // claim about their own health built from a statistical test, and the three
    // sentences below are the difference between a finding and an assertion.

    @ViewBuilder
    private func method(_ analysis: SleepInfluences.Output) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("How this was worked out").font(.caption.weight(.semibold))
            // No markdown anywhere in this copy: these reach `Text` as runtime
            // `String`s rather than literals, so the `StringProtocol` overload
            // takes them and asterisks would render as asterisks.
            Text("Each thing is held against the night that followed it — what today "
                 + "did to tonight's sleep. The same day's activity is taken out first, "
                 + "because a busy day changes both and would otherwise look like the "
                 + "cause; so is whether the next morning was a free one.")
            Text("Nothing is called a finding until it beats \(SleepInfluences.permutations) "
                 + "reshuffles of your own data that keep each thing's own week-to-week "
                 + "rhythm intact — and it has to beat the *best* of all "
                 + "\(analysis.tested) at once, so checking more things makes it harder "
                 + "to find one, not easier.")
            Text("Associations in one person's record. Not causes, and not medical "
                 + "findings.")
        }
        .font(.caption2).foregroundStyle(.tertiary)
        .fixedSize(horizontal: false, vertical: true)
    }
}
