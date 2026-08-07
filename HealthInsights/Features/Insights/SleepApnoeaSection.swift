import SwiftUI
import InsightKit

/// **"Sleep apnoea indicator"** — the dedicated section backlog B18-1 asked for,
/// and the section S9's finding is allowed to fill.
///
/// The reader asked for a dedicated sleep-apnoea indicator that **contains**
/// "Breathing during sleep". Those are one section, not two, and this file is
/// the whole of it: "Breathing during sleep" is a `NestedInsightSection` inside
/// this card rather than a section of its own, so the app never grows two
/// headings about one measurement.
///
/// ## What a section with this title is allowed to do
///
/// **Nothing that resembles screening.** The heading names the question a reader
/// has; the content answers it by refusing, twice and in plain words:
///
/// - it says up front that this is not an apnoea test and that this app does not
///   screen for apnoea (`BreathingDisturbanceTrend.notAnApnoeaTest`);
/// - it ends by naming the only thing that does answer it — a sleep study
///   arranged through a doctor (`whatWouldAnswerIt`).
///
/// In between it draws the reader's own nights and says where the last one sat
/// among them and whether the series is drifting by more than it scatters. Every
/// one of those is a statement about this person's history. None is a statement
/// about their airway.
///
/// The refusal wording lives in InsightKit — the app target has no test target,
/// and this is the honesty claim rather than decoration, the same reason
/// `SectionCaveat`'s words live there.
///
/// ## Where the contents came from
///
/// `InsightDetailView.sleepBreathingSection`, which was a top-level section of
/// its own from 2026-08-07 morning and is now contained here, per B18-1. Its
/// chart, its caveat and its `MetricExplainer.yours` sentence are unchanged; what
/// is new is the framing either side of them and the drift sentence.
struct SleepApnoeaSection: View {
    @Environment(AppModel.self) private var model
    let timeframe: Timeframe

    private var breakdown: MultiSourceBreakdown {
        model.breakdown(.breathingDisturbanceIndex)
    }

    private var trend: BreathingDisturbanceTrend {
        model.memoized("breathingDisturbanceTrend") {
            BreathingDisturbanceTrend.build(samples: model.samples)
        }
    }

    /// The latest night inside the reader's own recent spread — the same
    /// `MetricExplainer.yours` sentence the metric detail page builds, over the
    /// last 90 nights of the densest source. One instrument, not a pool, for the
    /// reason `MetricDetailView.personalReading` documents; memoized for the
    /// reason it is too.
    private var personalSentence: String? {
        model.memoized("explainer.breathingDisturbanceIndex.sleepCard") {
            guard let series = breakdown.sources.max(by: { $0.samples.count < $1.samples.count }),
                  let latest = series.samples.last else { return String?.none }
            return MetricExplainer.yours(.breathingDisturbanceIndex,
                                         value: latest.value,
                                         history: series.samples.suffix(90).map(\.value))
        }
    }

    private var placeholder: SectionPlaceholder? {
        breakdown.dateSpan == nil
            ? SectionPlaceholder.needsInput(
                subject: "The night's breathing",
                what: "a wearable that reports a breathing-disturbance index — "
                    + "Oura's ring does",
                remedy: "connect Oura under Settings")
            : nil
    }

    var body: some View {
        InsightSection(
            title: "Sleep apnoea indicator",
            icon: "lungs",
            trailing: breakdown.mostRecent.map { sample in
                let value = MetricValueFormatter.string(sample.value, .breathingDisturbanceIndex)
                let isRecent = Date().timeIntervalSince(sample.start) < 36 * 3600
                return isRecent ? "\(value) last night" : "\(value) last recorded night"
            },
            caveat: .computed(.estimated, BreathingDisturbanceTrend.notAnApnoeaTest),
            expansion: expansion
        ) {
            if breakdown.dateSpan != nil {
                headline
                breathingDuringSleep
                // S13. The trend surface, in its own file: the nights, the
                // reader's own middle half and the fitted line. It is *here*
                // rather than a section of its own because B18-1's rule stands —
                // one measurement, one heading — and it carries the drift
                // sentence and the placement that used to sit above, so neither
                // is now said twice on one screen.
                BreathingTrendSection(trend: trend, timeframe: timeframe)
                Divider()
                Text(BreathingDisturbanceTrend.whatWouldAnswerIt)
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else if let placeholder {
                emptyState(placeholder)
            }
        }
    }

    private var expansion: SectionExpansion {
        guard let placeholder else { return .open }
        return .collapsed(preview: placeholder.headline)
    }

    /// The refusal, first, before any number. A reader who opens a section called
    /// "Sleep apnoea indicator" and meets a chart has already been told something
    /// this app cannot support.
    private var headline: some View {
        Text("What this is: a trend of your ring's breathing-disturbance index, "
             + "drawn against your own nights. What it is not: a test, a screen or "
             + "a verdict.")
            .font(.caption).foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// The contained section. Nested rather than top-level, per B18-1 — one
    /// measurement, one heading.
    private var breathingDuringSleep: some View {
        NestedInsightSection(
            title: "Breathing during sleep",
            trailing: nightsLabel,
            caveat: .computed(.estimated,
                              "Oura's own index of how uneven your breathing was "
                              + "overnight, derived from blood oxygen and movement. No "
                              + "published scale says what a given level means, so this "
                              + "app trends it against your own nights and never scores "
                              + "it.")
        ) {
            if let sentence = personalSentence {
                Text(sentence)
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            // ⚠️ **The drift sentence and the placement moved out on 2026-08-08
            // (S13), and the move is the point rather than a tidy-up.** They
            // named a slope, a scatter and a percentile above a
            // `MultiSourceChart`, which draws one line per *instrument* and
            // carries no fitted line at all — so the picture on this screen
            // could neither confirm nor contradict the sentence beside it. They
            // now sit in `BreathingTrendSection`, immediately below, under the
            // chart that actually draws that line.
            //
            // What stays here is what this chart genuinely answers: whether the
            // reader's devices agree about the index.
            MultiSourceChart(breakdown: breakdown,
                             window: timeframe.chartWindow(
                                spanning: breakdown.dateSpan.map {
                                    $0.upperBound.timeIntervalSince($0.lowerBound)
                                }))
            Text("One line per device that reported the index. Where two of them "
                 + "disagree, that is a fact about the instruments rather than about "
                 + "your night.")
                .font(.caption2).foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// How many nights are behind the picture. Counted from the data, so it
    /// cannot go stale the way a written figure would.
    private var nightsLabel: String? {
        guard !trend.nights.isEmpty else { return nil }
        return "\(trend.nights.count) nights"
    }

    /// The same shape `InsightDetailView.emptySection` draws, kept here so this
    /// file does not reach back into a 3,700-line view for one helper.
    private func emptyState(_ placeholder: SectionPlaceholder) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "checkmark.circle")
                .font(.caption).foregroundStyle(.secondary)
                .frame(width: 16)
            Text(placeholder.detail)
                .font(.subheadline).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
