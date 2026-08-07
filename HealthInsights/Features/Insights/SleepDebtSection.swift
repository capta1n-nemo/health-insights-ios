import SwiftUI
import Charts
import InsightKit

/// **"Sleep debt"** — how far behind you are, what that is measured against, and
/// the nights that put you there.
///
/// The reader, 2026-08-07: *"I also want a sleep debt section."* (Backlog B18-7.)
///
/// The figure itself is not new — `SleepDebtModel` has been a 12% term of the
/// Sleep score for months. What was missing is everything around it: a reader
/// looking at "4.2 h behind" could not see which nights it came from, could not
/// see what "behind" was measured against, and had no way to know that the
/// number decays rather than accumulating forever.
///
/// ## The baseline decision, and where it is written down
///
/// `SleepDebtModel.NeedBasis` in InsightKit carries it, with the argument: the
/// need is **the reader's own habitual unconstrained duration** — the upper
/// quartile of their last ninety nights — and not a published figure, and not
/// the duration on the days they felt best. The published band is shown beside
/// it for context and is never the thing the shortfall is measured against.
///
/// That decision belongs in InsightKit rather than here because it is the claim,
/// and the app target has no test target. This section's job is to *say* it, in
/// the reader's own numbers, every time the section is open — which is why
/// `basis.sentence` is rendered unconditionally rather than tucked into a
/// caveat that only appears in some states.
struct SleepDebtSection: View {
    /// The card's timeframe, so the ledger obeys the picker like everything else
    /// on the page.
    let window: TimeInterval
    @Environment(AppModel.self) private var model
    @State private var selection: Date?

    private var days: Int { max(14, Int(window / 86_400)) }

    var body: some View {
        let ledger = model.memoized("sleepDebtLedger.\(days)") {
            SleepDebtModel.ledger(samples: model.samples, days: max(days, 90))
        }
        let today = model.memoized("sleepDebtToday") {
            SleepDebtModel.evaluate(samples: model.samples)
        }
        InsightSection(
            title: "Sleep debt",
            // The one figure, and it is the *current* one — `evaluate`'s, not
            // the ledger's last row. See `SleepDebtLedger`: the ledger draws the
            // balance as at each night, and debt decays, so on a morning after a
            // missing night the two legitimately differ. The header must be the
            // one that is true now.
            trailing: today.map {
                $0.debtHours < 1 ? "clear"
                    : String(format: "%.1f h behind", $0.debtHours)
            },
            caveat: .computed(.estimated, Self.caveatText),
            expansion: expansion(for: ledger)
        ) {
            if let ledger, let today {
                headline(today, ledger: ledger)
                Divider()
                baselineStatement(ledger)
                if ledger.nights.count >= 2 {
                    Divider()
                    chart(ledger)
                }
            } else {
                emptyBody
            }
        }
    }

    private static let caveatText =
        "Debt is a running total of hours short of your own need, with older "
        + "shortfalls discounted — a bad night five days ago counts half. A long "
        + "night does not pay it back: it simply adds nothing. This is arithmetic "
        + "over your recorded nights, not a measurement of how tired you are."

    private func expansion(for ledger: SleepDebtModel.Ledger?) -> SectionExpansion {
        guard ledger == nil else { return .open }
        return .collapsed(preview: "Needs a few recorded nights before a balance means anything")
    }

    private var emptyBody: some View {
        Text("Sleep debt needs at least three recorded nights before a balance "
             + "means anything. Connect Oura, Whoop or Apple Health under Settings, "
             + "or give it a few more nights.")
            .font(.subheadline).foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - The figure

    @ViewBuilder
    private func headline(_ today: SleepDebtModel.Output,
                          ledger: SleepDebtModel.Ledger) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(today.debtHours < 1 ? "Clear"
                     : String(format: "%.1f h", today.debtHours))
                    .font(.title2.weight(.semibold)).monospacedDigit()
                    .foregroundStyle(Theme.color(forScore:
                        SleepDebtModel.score(debtHours: today.debtHours)))
                Text(today.band.lowercased())
                    .font(.subheadline).foregroundStyle(.secondary)
                Spacer()
            }
            Text(today.debtHours < 1
                 ? "You are level with your own need over the last fortnight."
                 : "About \(today.nightsToClear) "
                    + (today.nightsToClear == 1 ? "night" : "nights")
                    + " of an extra hour would clear it — and it also fades on its "
                    + "own, halving about every \(Int(SleepDebtModel.halfLifeDays)) days.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            let short = ledger.nights.filter { $0.shortfall > 0 }.count
            Text("\(short) of the last \(ledger.nights.count) recorded nights fell short.")
                .font(.caption2).foregroundStyle(.tertiary)
        }
    }

    /// **The baseline, said out loud.** Never a footnote: a debt figure whose
    /// denominator is invisible is a number the reader cannot argue with.
    @ViewBuilder
    private func baselineStatement(_ ledger: SleepDebtModel.Ledger) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(String(format: "Measured against %.1f h a night", ledger.needHours))
                .font(.subheadline.weight(.semibold))
            Text("Your need here is \(ledger.basis.sentence).")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text(String(format: "For context, the published adult band is %.0f–%.0f h. "
                        + "It is shown to place your figure, never to score you against it — "
                        + "the shortfall above is measured from yours.",
                        ledger.publishedBand.lowerBound, ledger.publishedBand.upperBound))
                .font(.caption2).foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - The nights

    @ViewBuilder
    private func chart(_ ledger: SleepDebtModel.Ledger) -> some View {
        // The scrub read-out sits **above** the chart as a normal view, never as
        // a mark annotation — 3D content has no `annotation` (add-chart §2).
        readout(ledger)
        ScrollableMetricChart(
            dataSpan: span(ledger),
            window: window,
            selection: $selection,
            height: 180,
            emptyMessage: "Nothing was recorded in the period on screen. Swipe "
                + "sideways, tap the arrows on the chart's edges to jump to your "
                + "nearest nights, or pick a longer timeframe.",
            isEmpty: { range in
                !ledger.nights.contains { range.contains($0.date) }
            },
            yDomain: { range in
                let visible = ledger.nights.filter { range.contains($0.date) }
                guard !visible.isEmpty else { return nil }
                let highest = visible.map { max($0.hours, ledger.needHours) }.max() ?? 9
                return 0...(highest + 0.5)
            }
        ) { range in
            marks(ledger, in: range)
        }
        legend
    }

    private func span(_ ledger: SleepDebtModel.Ledger) -> ClosedRange<Date>? {
        guard let first = ledger.nights.first?.date,
              let last = ledger.nights.last?.date, first <= last else { return nil }
        return first...last
    }

    /// Explicit `some ChartContent`: without it this chain can resolve to 3D
    /// content on this SDK and silently drop `.foregroundStyle` (add-chart §2).
    @ChartContentBuilder
    private func marks(_ ledger: SleepDebtModel.Ledger,
                       in range: ClosedRange<Date>) -> some ChartContent {
        let visible = ledger.nights.filter { range.contains($0.date) }
        // The shortfall drawn as the gap it is: a bar from the night's own hours
        // up to the need. Nothing is drawn on a night that met it, because there
        // is nothing there — a zero-height bar would be a mark claiming an event.
        ForEach(visible.filter { $0.shortfall > 0 }) { night in
            BarMark(x: .value("Night", night.date),
                    yStart: .value("Slept", night.hours),
                    yEnd: .value("Need", ledger.needHours),
                    width: .fixed(5))
                .foregroundStyle(Theme.warn.opacity(0.55))
        }
        // Hours slept — measured, so solid and linear. A curve between two
        // nights would invent a night nobody recorded.
        ForEach(visible) { night in
            LineMark(x: .value("Night", night.date),
                     y: .value("Hours", night.hours),
                     series: .value("Series", "slept"))
                // No `slots:` because there is exactly one metric series here —
                // the hue cannot collide with a line that does not exist. Any
                // second metric added to this chart must resolve both through
                // `MetricPalette.slots(for:)` (add-chart §3).
                .foregroundStyle(Theme.metricColor(.sleepDurationHours))
                .interpolationMethod(.linear)
        }
        // The need. A reference level, not a reading — dashed, per the rule that
        // a dash means "not measured". `ForEach` rather than a bare `if`: a
        // conditional inside a chart builder is the exact shape that has dropped
        // modifiers on this SDK before (add-chart §2).
        ForEach(visible.isEmpty ? [] : [ledger.needHours], id: \.self) { need in
            RuleMark(y: .value("Your need", need))
                .lineStyle(Theme.referenceStroke)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func readout(_ ledger: SleepDebtModel.Ledger) -> some View {
        let night = selection.flatMap { instant in
            ledger.nights.min {
                abs($0.date.timeIntervalSince(instant)) < abs($1.date.timeIntervalSince(instant))
            }
        }
        HStack(spacing: 8) {
            if let night {
                Text(night.date.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption.weight(.semibold)).monospacedDigit()
                Text(String(format: "%.1f h", night.hours)).foregroundStyle(.secondary)
                Text(night.shortfall > 0
                     ? String(format: "%.1f h short", night.shortfall)
                     : String(format: "%.1f h over", night.surplus))
                    .foregroundStyle(night.shortfall > 0 ? Theme.warn : Theme.good)
                Text(String(format: "balance %.1f h", night.debtAfter))
                    .foregroundStyle(.tertiary)
            } else {
                Text("Hours slept each night, and the gap to your own need.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .font(.caption2)
    }

    private var legend: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Shaded bars are hours short of your need on that night. The "
                 + "dashed line is the need itself.")
            Text(SubstanceShading.caption)
        }
        .font(.caption2).foregroundStyle(.tertiary)
        .fixedSize(horizontal: false, vertical: true)
    }
}
