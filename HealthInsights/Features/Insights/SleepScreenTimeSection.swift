import SwiftUI
import Charts
import InsightKit

/// **"Screen time and your sleep"** — backlog B18-2, a dedicated section rather
/// than a driver row inside the sleep-onset deep dive.
///
/// `SleepOnsetModel` already asks *"is it tech time?"* of one outcome, how long
/// the reader takes to fall asleep, and reports it as one line among five
/// drivers. The reader asked for the wider question and its own heading: what did
/// the evening's phone use go with across the whole night — how long it lasted,
/// how fast it started, how much of the time in bed was slept.
///
/// ## Why this section leads with what it hasn't got
///
/// Apple sandboxes Screen Time, so no app can read it (`MetricType
/// .screenTimeMinutes`). Every day of it in this app was typed in or read off a
/// screenshot the reader supplied, and on their export there are twenty-six of
/// them. That is the governing fact about this section, so it is the first thing
/// on it: a `CoverageGate` line saying how many days there are, how many are
/// needed, and — the number that makes somebody carry on — how many more.
///
/// Below the floor there is a scatter and **no contrast**. `ScreenTimeSleepLink`
/// refuses one rather than reporting a weak one, because a median split over six
/// nights reads on screen exactly like a median split over sixty.
///
/// ## The chart
///
/// A scatter, not a time series: the question is *"does a heavier evening go with
/// a shorter night"*, and that is one axis against another rather than either
/// against the calendar. The dashed vertical rule is the reader's own median
/// screen time — the line the contrast splits at — and it is dashed because a
/// fitted middle is not an evening anybody had (`add-chart` §3).
///
// substance-shading: exempt — the x axis is minutes of screen time, not a date,
// so a window in which something was logged has nowhere to land. Same exemption,
// same reason, as SleepStageAverageChart.
struct SleepScreenTimeSection: View {
    @Environment(AppModel.self) private var model

    private var link: ScreenTimeSleepLink {
        model.memoized("screenTimeSleepLink") {
            ScreenTimeSleepLink.build(samples: model.samples)
        }
    }

    private var tint: Color { Theme.insightTint(.sleep) }

    /// Only the pairs with a sleep duration beside them are plottable — the
    /// scatter's y axis is hours slept.
    private var plottable: [ScreenTimeSleepLink.Pair] {
        link.pairs.filter { $0.sleepHours != nil }
    }

    var body: some View {
        InsightSection(
            title: "Screen time and your sleep",
            icon: "iphone",
            trailing: link.pairs.isEmpty ? nil
                : "\(link.pairs.count) \(link.pairs.count == 1 ? "night" : "nights") paired",
            caveat: .associationsNotCauses,
            expansion: expansion
        ) {
            coverageLine
            if plottable.count >= 2 {
                scatter
                caption
            }
            contrastRows
            howToAddMore
        }
    }

    private var expansion: SectionExpansion {
        guard link.pairs.isEmpty else { return .open }
        return .collapsed(preview: "Nothing paired yet — screen time has to be "
                          + "entered by hand, and nothing has been.")
    }

    /// **Unconditional.** The section's own headline sentence is never gated on
    /// having data, because a heading with nothing under it is the state this
    /// whole section exists to explain (`add-chart` §9b, and `CoverageGate`'s own
    /// reason for existing).
    @ViewBuilder private var coverageLine: some View {
        if let sentence = link.coverage?.sentence {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "chart.bar.doc.horizontal")
                    .font(.caption).foregroundStyle(tint).frame(width: 16)
                Text(sentence)
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } else {
            Text("\(link.pairs.count) evenings of screen time with a night beside each — enough to hold your heavier evenings against your lighter ones.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - The scatter

    private var splitMinutes: Double? {
        link.contrasts.first?.splitMinutes
    }

    private var scatter: some View {
        Chart {
            splitRule
            points
        }
        .chartLegend(.hidden)
        .chartXAxisLabel("Screen time that day (min)")
        .chartYAxisLabel("Hours slept that night")
        .frame(height: 170)
    }

    /// Explicit `-> some ChartContent` on every mark builder — without it a
    /// `RuleMark` chain can resolve to `Chart3DContent` on this SDK and silently
    /// drop its modifiers (`add-chart` §2).
    @ChartContentBuilder private var splitRule: some ChartContent {
        ForEach(splitMinutes.map { [$0] } ?? [], id: \.self) { middle in
            RuleMark(x: .value("Your middle", middle))
                .foregroundStyle(tint.opacity(0.55))
                .lineStyle(Theme.projectedStroke)
        }
    }

    @ChartContentBuilder private var points: some ChartContent {
        ForEach(plottable) { pair in
            PointMark(x: .value("Screen time", pair.screenMinutes),
                      y: .value("Hours slept", pair.sleepHours ?? 0))
                .foregroundStyle(tint.opacity(0.8))
                .symbolSize(40)
        }
    }

    private var caption: some View {
        Text(splitMinutes == nil
             ? "Each point is one evening's screen time and the night that followed it. Nothing is fitted through them yet — that waits until there are enough."
             : "Each point is one evening's screen time and the night that followed it. The dashed line is your own middle; everything right of it is your heavier half.")
            .font(.caption2).foregroundStyle(.tertiary)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - The contrast

    @ViewBuilder private var contrastRows: some View {
        if !link.contrasts.isEmpty {
            Text("Your heavier half against your lighter half")
                .font(.caption.weight(.medium))
            ForEach(link.contrasts) { contrast in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: icon(for: contrast.outcome))
                        .font(.caption).foregroundStyle(tint).frame(width: 16)
                    Text(contrast.sentence)
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func icon(for outcome: ScreenTimeSleepLink.Outcome) -> String {
        switch outcome {
        case .sleepHours: return "bed.double"
        case .latencyMinutes: return "hourglass"
        case .efficiency: return "percent"
        }
    }

    /// Where the reader closes the gap, since nothing they do passively will.
    /// The route named is the one that exists — this card's own "View & add",
    /// which `SleepInsight.contributions` already declares.
    private var howToAddMore: some View {
        Text("iOS does not let any app read your Screen Time, so this only ever knows the days you hand it. \"View & add\" near the bottom of this card takes a day's total, and the Shortcuts automation under Settings can send it without you typing anything.")
            .font(.caption2).foregroundStyle(.tertiary)
            .fixedSize(horizontal: false, vertical: true)
    }
}
