import SwiftUI
import InsightKit

/// **The screen time card's own two pictures** — backlog B9-2.
///
/// | Section | Question | Shape |
/// | --- | --- | --- |
/// | The days you have entered | what does your own screen time look like | the daily series, by source, with the coverage line above it |
/// | Heavier days against lighter ones | did your body read the two halves differently | one row per signal, or the gate saying how many more days it needs |
///
/// ## ⚠️ Why the coverage line is the first thing on the card
///
/// Apple sandboxes Screen Time — `MetricType.screenTimeMinutes` carries the
/// research — so no app can read it and every day here was typed in or read off
/// a screenshot the reader supplied. On their export that is twenty-six rows.
/// **That is the governing fact about this card**, so it is stated before any
/// figure rather than footnoted under one, exactly as
/// `SleepScreenTimeSection` states it for the sleep card's own section.
///
/// ## ⚠️ And why neither section grades the amount
///
/// `ScreenTimeModel.evidenceRefusal` is on screen, in full, in both states. The
/// card has a 0–100 and it is **not** a judgement of how much the reader uses
/// their phone: it is how differently their body read the nights after their
/// heavier days. A section here that shaded a band, coloured a bar by level or
/// put a target on the chart would make the claim the model refuses to make —
/// so none of them does.
///
/// ## Reuse rather than a new chart
///
/// The daily series is drawn by `MultiSourceChart`, the shared component every
/// card uses. That is not laziness about the picture: it splits the series **by
/// source**, so a reader can see at a glance which days they typed and which
/// came off a photographed Screen Time screen — which is precisely the
/// distinction `B10-1` and `B10-2` were about, and the one a bespoke single-line
/// chart would have thrown away. It also inherits panning, the substance
/// shading, the empty-window message and the `‹` `›` jump affordances
/// (`add-chart` §9a, §9b) with no code here.
///
/// ⚠️ **Its own file** — `InsightDetailView` is ~3,700 lines and a section
/// written inline there is a merge conflict for the next agent.
struct ScreenTimeSection: View {
    @Environment(AppModel.self) private var model
    let timeframe: Timeframe

    private var result: ScreenTimeModel.Result {
        model.memoized("screenTime") {
            ScreenTimeModel.analyse(samples: model.samples, now: Date())
        }
    }

    private var breakdown: MultiSourceBreakdown { model.breakdown(.screenTimeMinutes) }

    private var tint: Color { Theme.insightTint(.screenTime) }

    var body: some View {
        switch result {
        case .nothing:
            daysSection(description: nil, gate: nil)
            contrastPlaceholder(
                "Nothing to compare yet. Add a day of screen time — by hand, from a "
                + "photo of your Screen Time screen, or through the Shortcuts "
                + "automation under Settings — and this will start holding your "
                + "heavier days against your lighter ones.")
        case .describing(let description, let gate):
            daysSection(description: description, gate: gate)
            contrastPlaceholder(gate.sentence ?? ScreenTimeModel.evidenceRefusal)
        case .ready(let out):
            daysSection(description: out.description, gate: nil)
            contrastSection(out)
        }
    }

    // MARK: - 1. The days you have entered

    /// ⚠️ **The section, its heading and its coverage line are unconditional**
    /// — `description` is optional rather than the section being wrapped in an
    /// `if let`. A card whose picture vanishes while it is counting is how two
    /// sections shipped invisible on 2026-08-03, and a header derived from the
    /// data disappearing is the collapse `add-chart` §9b bans.
    private func daysSection(description: ScreenTimeModel.Description?,
                             gate: CoverageGate?) -> some View {
        InsightSection(
            title: "The days you have entered",
            icon: "iphone",
            trailing: description.map {
                "\($0.daysRecorded) \($0.daysRecorded == 1 ? "day" : "days")"
            },
            caveat: .computed(.partial, ScreenTimeModel.howItArrives),
            expansion: .open
        ) {
            VStack(alignment: .leading, spacing: 10) {
                if let gate, let sentence = gate.sentence {
                    coverageLine(sentence)
                }
                if let description {
                    caption(ScreenTimeModel.shapeSentence(description))
                    if let week = ScreenTimeModel.weekPatternSentence(description) {
                        caption(week)
                    }
                    if let drift = ScreenTimeModel.driftSentence(description) {
                        caption(drift)
                    }
                    MultiSourceChart(breakdown: breakdown,
                                     window: timeframe.chartWindow(
                                        spanning: breakdown.dateSpan.map {
                                            $0.upperBound.timeIntervalSince($0.lowerBound)
                                        }))
                    footnote("One point per day you supplied, split by where it came "
                             + "from — typed in, read off a screenshot, or sent by a "
                             + "Shortcut. Nothing is shaded, banded or targeted on "
                             + "this chart: there is no level to draw a line at.")
                } else {
                    caption("No days of screen time yet. \(ScreenTimeModel.howItArrives)")
                }
            }
        }
    }

    // MARK: - 2. Heavier days against lighter ones

    private func contrastSection(_ out: ScreenTimeModel.Output) -> some View {
        InsightSection(
            title: "Heavier days against lighter ones",
            icon: "arrow.left.arrow.right",
            trailing: String(format: "%.2f SD pooled", abs(out.pooled)),
            caveat: .associationsNotCauses,
            expansion: .open
        ) {
            VStack(alignment: .leading, spacing: 10) {
                caption(ScreenTimeModel.splitSentence(out))
                caption(ScreenTimeModel.pooledSentence(out))
                Divider()
                ForEach(out.channels) { channel in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: icon(for: channel))
                            .font(.caption).foregroundStyle(tint).frame(width: 16)
                        Text(ScreenTimeModel.sentence(channel))
                            .font(.caption).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Divider()
                refusal
            }
        }
    }

    /// ⚠️ **Three glyphs, not two.** The first version drew "worse" or "equal",
    /// so a signal that ran *notably better* after the heavier days got the same
    /// mark as one that did not move — seen on the simulator, where sleep
    /// duration was half a standard deviation better and rendered as `=`. On a
    /// card whose whole argument is that the direction is read rather than
    /// assumed, quietly having no glyph for "better" is the argument leaking out
    /// of the picture.
    private func icon(for channel: WorkImpactModel.Channel) -> String {
        guard abs(channel.towardWorse) >= ScreenTimeModel.notableResponse else { return "equal" }
        return channel.towardWorse > 0 ? "arrow.down.right" : "arrow.up.right"
    }

    private func contrastPlaceholder(_ message: String) -> some View {
        InsightSection(
            title: "Heavier days against lighter ones",
            icon: "arrow.left.arrow.right",
            trailing: nil,
            caveat: .associationsNotCauses,
            expansion: .collapsed(preview: String(message.prefix(90)))
        ) {
            VStack(alignment: .leading, spacing: 10) {
                caption(message)
                refusal
            }
        }
    }

    // MARK: - The refusal, on screen in every state

    private var refusal: some View {
        Text(ScreenTimeModel.evidenceRefusal)
            .font(.caption2).foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func coverageLine(_ sentence: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "chart.bar.doc.horizontal")
                .font(.caption).foregroundStyle(tint).frame(width: 16)
            Text(sentence)
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func caption(_ text: String) -> some View {
        Text(text)
            .font(.caption).foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func footnote(_ text: String) -> some View {
        Text(text)
            .font(.caption2).foregroundStyle(.tertiary)
            .fixedSize(horizontal: false, vertical: true)
    }
}
