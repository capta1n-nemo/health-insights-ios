import SwiftUI
import InsightKit

/// **"Which instrument to believe"** — the disagreement between the reader's own
/// devices, on the card whose number it decided.
///
/// Backlog `B3-23` / `S8`, the reader's ask and one they have made more than
/// once: *"where Watch, ring and scale disagree — show both, say which the app
/// used and why."*
///
/// ## Why it is a section on every card, and not only a page of its own
///
/// Both were built, deliberately, and the ruling on 2026-08-07 says why: a
/// per-card section puts the disagreement **where the decision is made**, which
/// is the reader's own placement of "why is my score low" — *an explanation one
/// tap from the number is one people actually read*. The index — the card on
/// the Insights tab (`InstrumentIndexCard`) — is what makes it findable when
/// the reader is not already looking at a score. Neither substitutes for the
/// other.
///
/// ## What it draws
///
/// One block per signal that more than one instrument reports:
///
/// - **every instrument's own reading**, including the ones nothing used. That
///   is the whole ask: the discarded number is on screen with its own value,
///   its own coverage and the path it arrived by;
/// - **which instrument the app used**, badged — and *twice*, because
///   `VitalReader` picks per question and can name different instruments for
///   the judged reading and for the line on the chart;
/// - **why**, in a sentence that quotes the margin that actually decided it.
///
/// Then, beneath, the signals with only one instrument and the ones with none.
/// Listed rather than dropped: a section showing two rows out of nine otherwise
/// implies the other seven were checked and found to agree, which is the same
/// mistake `unNormedRows` exists to avoid on "How you compare".
///
/// ## No colour dots, on purpose
///
/// The obvious design borrows `Theme.sourceColor` from `SourceBreakdown` so a
/// row matches its line on the overlay chart above. It cannot: those hues are
/// assigned by position in `MultiSourceBreakdown.sources`, and these rows are
/// ordered *chosen first*. A dot that looks like the chart's encoding and is not
/// the chart's encoding is worse than no dot — see `add-chart` on reading the
/// pixel before trusting a colour. Chosen-ness is carried by a badge instead,
/// which is what the section is actually about.
struct InstrumentAgreementSection: View {
    /// The card's own signals. Narrowed per card for the same reason
    /// `vitalDepartureSection` narrows: a Sleep card listing seventeen
    /// instruments answers a question nobody asked.
    let metrics: [MetricType]
    /// The window coverage is measured over — the reader's own timeframe, so
    /// this section obeys the picker like the rest of the screen. It is not
    /// cosmetic: `VitalReader.dailySeries` genuinely picks the instrument that
    /// best covers *the window being read*, so a different timeframe can name a
    /// different instrument, and the copy names the number of days.
    let windowDays: Int
    @Environment(AppModel.self) private var model

    private var panel: InstrumentAgreementPanel {
        // Keyed by the window as well as the card: the answer legitimately
        // changes with the timeframe, so a cache keyed on the card alone would
        // show the reader last timeframe's instrument.
        model.memoized("instrumentAgreement-\(metrics.map(\.rawValue).joined(separator: ","))-\(windowDays)") {
            InstrumentAgreementPanel.forCard(metrics: metrics,
                                             samples: model.samples,
                                             windowDays: windowDays)
        }
    }

    var body: some View {
        let panel = self.panel
        InsightSection(
            title: "Which instrument to believe",
            trailing: panel.rows.isEmpty ? nil : trailing(panel),
            caveat: caveat(panel),
            // Arrives closed, like the other two transparency deep-dives
            // ("How this is weighted", "What comes first"). The preview carries
            // the finding, so a reader who never opens it has still been told
            // that two of their devices disagree.
            expansion: .collapsed(preview: InstrumentAgreementWording.preview(panel))
        ) {
            if panel.rows.isEmpty {
                emptyState(panel)
            } else {
                ForEach(Array(panel.rows.enumerated()), id: \.element.id) { index, row in
                    if index > 0 { Divider() }
                    signalBlock(row)
                }
            }
            if !panel.single.isEmpty || !panel.silent.isEmpty {
                Divider()
                remainder(panel)
            }
        }
    }

    /// The one figure: how many signals have more than one instrument.
    /// Deliberately a count and not the widest gap — one slot, one quantity,
    /// and a gap in bpm on a card whose worst disagreement is in kilograms
    /// would change what the number *is* between cards.
    private func trailing(_ panel: InstrumentAgreementPanel) -> String {
        let n = panel.rows.count
        return "\(n) \(SectionCaveat.plural(n, "signal")) with more than one"
    }

    private func caveat(_ panel: InstrumentAgreementPanel) -> SectionCaveat {
        guard !panel.rows.isEmpty else { return .none }
        return .computed(.partial,
                         "Coverage is counted over the last \(panel.windowDays) days, "
                            + "so changing the timeframe above can change which "
                            + "instrument draws the chart. Nothing here is averaged and "
                            + "nothing is calibrated onto anything else — your devices "
                            + "are not one quantity with a fixed offset between them, so "
                            + "there is no offset to remove.")
    }

    // MARK: - One signal

    @ViewBuilder private func signalBlock(_ row: InstrumentAgreement) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline) {
                Text(row.metric.displayName).font(.subheadline.weight(.semibold))
                Spacer(minLength: 8)
                if let spread = row.spread {
                    Text("they differ by \(formatted(spread, row.metric))")
                        .font(.caption).monospacedDigit()
                        .foregroundStyle(Theme.warn)
                }
            }
            ForEach(row.instruments) { instrument in
                instrumentRow(instrument, metric: row.metric)
            }
            Text(row.readingReason)
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let chartReason = row.chartReason {
                Text(chartReason)
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 2)
    }

    private func instrumentRow(_ instrument: InstrumentAgreement.Instrument,
                               metric: MetricType) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(instrument.name)
                    .font(.subheadline)
                    // The unused instrument is dimmed, never hidden. Hiding it
                    // is the defect this whole section exists to fix.
                    .foregroundStyle(instrument.isUnused ? .secondary : .primary)
                Spacer(minLength: 8)
                if let latest = instrument.latest {
                    Text(formatted(latest, metric))
                        .font(.subheadline).monospacedDigit()
                        .foregroundStyle(instrument.isUnused ? .secondary : .primary)
                }
            }
            HStack(spacing: 4) {
                if instrument.feedsReading { badge("used for the number") }
                if instrument.feedsCharts { badge("draws the chart") }
                if instrument.isUnused { badge("not used", muted: true) }
                if !instrument.isFresh { badge("stopped reporting", muted: true) }
                originLabel(instrument)
                Spacer(minLength: 0)
                Text("\(instrument.daysInWindow)/\(windowDays) days")
                    .font(.caption2).monospacedDigit().foregroundStyle(.tertiary)
            }
        }
    }

    private func badge(_ text: String, muted: Bool = false) -> some View {
        Text(text)
            .font(.caption2)
            .foregroundStyle(muted ? Color.secondary : Theme.accent)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background {
                Capsule().fill(muted ? Color.secondary.opacity(0.10)
                                     : Theme.accent.opacity(0.14))
            }
    }

    /// Which paths this instrument's readings arrived by. The same ring can
    /// report directly and be mirrored through Apple Health, and the two lag
    /// each other — so the merged series says both rather than picking one.
    @ViewBuilder private func originLabel(_ instrument: InstrumentAgreement.Instrument) -> some View {
        if !instrument.origins.isEmpty {
            Text(instrument.origins.combinedLabel)
                .font(.caption2).foregroundStyle(.tertiary)
                .lineLimit(1)
        }
    }

    // MARK: - What is not a row

    /// The signals with one instrument, and the signals with none.
    ///
    /// One instrument is the *answer* for most signals rather than a gap in
    /// this section, and saying so is what stops the rows above reading as a
    /// complete audit of the card.
    @ViewBuilder private func remainder(_ panel: InstrumentAgreementPanel) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if !panel.single.isEmpty {
                Text("One instrument each, so nothing to choose between")
                    .font(.caption.weight(.medium))
                Text(panel.single.map(\.displayName).joined(separator: " · "))
                    .font(.caption2).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !panel.silent.isEmpty {
                Text("Nothing has reported these at all")
                    .font(.caption.weight(.medium))
                    .padding(.top, panel.single.isEmpty ? 0 : 4)
                Text(panel.silent.map(\.displayName).joined(separator: " · "))
                    .font(.caption2).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// Drawn rather than the section disappearing, for `SectionPlaceholder`'s
    /// reason: an absent section is an absence the reader cannot read, and on
    /// most cards "only one device measures this" is the good answer rather
    /// than a missing one.
    private func emptyState(_ panel: InstrumentAgreementPanel) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "checkmark.circle")
                .font(.caption).foregroundStyle(.secondary).frame(width: 16)
            Text(panel.single.isEmpty
                 ? "Nothing on this card has reported yet, so there is nothing to compare. "
                    + "This fills in on its own once a device starts recording."
                 : "Every signal on this card comes from a single instrument, so there is "
                    + "no disagreement to resolve. If you connect a second device that "
                    + "measures one of them, the two readings and the app's choice "
                    + "between them appear here.")
                .font(.subheadline).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func formatted(_ value: Double, _ metric: MetricType) -> String {
        let text = formatMetric(value, metric)
        guard !formatMetricIncludesUnit(metric), !metric.unit.isEmpty else { return text }
        return "\(text) \(metric.unit)"
    }
}
