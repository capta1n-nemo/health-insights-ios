import SwiftUI
import InsightKit

/// The Generated-insights sub-menu — the reader's own shape for it, 2026-08-06:
/// one row on the Data tab, opening this page, *"so it doesn't blow out that
/// page, but we still collect and track it all to make use of it."*
///
/// Three levels: this page lists the cards that have derived anything; a card's
/// page lists its series, headline figures first and the component tiers under
/// their own headers; a series' page is the chart and the dated values.
struct GeneratedInsightsDataView: View {
    @Environment(AppModel.self) private var model

    private var producers: [InsightID] {
        let cards = Set(model.derivedSeries.specs.values.map(\.producedBy))
        // The engine's own order, so this list reads like the Insights tab
        // rather than alphabetically reshuffling it.
        return model.engine.models.map(\.id).filter { cards.contains($0) }
    }

    var body: some View {
        DomainDataScaffold(
            title: DataDomain.generatedInsights.title,
            entriesHeader: "Cards",
            entryCount: producers.count,
            emptyHeadline: "Nothing derived yet",
            emptyMessage: "As cards compute their figures — ages, doses, each signal's own score — the day-by-day series appear here.",
            emptySymbol: "function",
            overview: {
                Section {
                    Text(DataDomain.generatedInsights.summary)
                        .font(.caption).foregroundStyle(.secondary)
                } footer: {
                    Text("Every figure here was computed by this app, not measured by a device. History is rebuilt by replaying today's models over your data, so improving a model rewrites its own past.")
                }
            },
            rows: {
                ForEach(producers, id: \.self) { card in
                    NavigationLink {
                        GeneratedCardDataView(card: card)
                    } label: {
                        HStack {
                            Text(model.engine.models.first { $0.id == card }?.title
                                 ?? card.rawValue)
                            Spacer()
                            Text("\(model.derivedSeries.series(producedBy: card).count)")
                                .foregroundStyle(.secondary).monospacedDigit()
                        }
                    }
                }
            })
    }
}

/// One card's derived series: the figures it names for itself first, then each
/// signal's own score, then each signal's departure.
struct GeneratedCardDataView: View {
    @Environment(AppModel.self) private var model
    let card: InsightID

    private var all: [DerivedSeriesSpec] { model.derivedSeries.series(producedBy: card) }
    private func tier(_ kind: DerivedSeriesKind) -> [DerivedSeriesSpec] {
        all.filter { $0.kind == kind }
    }

    private var title: String {
        model.engine.models.first { $0.id == card }?.title ?? card.rawValue
    }

    var body: some View {
        DomainDataScaffold(
            title: title,
            entriesHeader: "Series",
            entryCount: all.count,
            emptyHeadline: "Nothing derived yet",
            emptyMessage: "This card has not computed anything on your data yet.",
            emptySymbol: "function",
            rows: {
                // The headline figures — the ones the reader asked to trend.
                ForEach(tier(.modelOutput)) { spec in seriesRow(spec) }
                // The component tiers under their own labels, so ninety rows of
                // machinery never bury four figures that matter.
                tierRows(tier(.componentScore),
                         label: "Each signal's own score",
                         detail: "The 0–100 behind every row of \"What's driving this\", before its weight is applied.")
                tierRows(tier(.componentDeparture),
                         label: "Each signal's departure",
                         detail: "Standard deviations from your own baseline, signed as the metric is measured.")
            })
    }

    @ViewBuilder private func tierRows(_ specs: [DerivedSeriesSpec],
                                       label: String, detail: String) -> some View {
        if !specs.isEmpty {
            DisclosureGroup {
                ForEach(specs) { spec in seriesRow(spec) }
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(label)
                        Spacer()
                        Text("\(specs.count)")
                            .foregroundStyle(.secondary).monospacedDigit()
                    }
                    Text(detail).font(.caption).foregroundStyle(.tertiary)
                }
            }
        }
    }

    private func seriesRow(_ spec: DerivedSeriesSpec) -> some View {
        NavigationLink {
            GeneratedSeriesDataView(spec: spec)
        } label: {
            HStack(alignment: .firstTextBaseline) {
                Text(spec.displayName)
                Spacer()
                if let latest = model.derivedSeries.latest(spec.id) {
                    Text(spec.string(latest.value))
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

/// One derived series: its chart, and every dated value newest first.
struct GeneratedSeriesDataView: View {
    @Environment(AppModel.self) private var model
    let spec: DerivedSeriesSpec

    private var points: [DerivedPoint] { model.derivedSeries.series(spec.id) }

    var body: some View {
        DomainDataScaffold(
            title: spec.displayName,
            entriesHeader: "Days",
            entryCount: points.count,
            emptyHeadline: "Nothing computed yet",
            emptyMessage: "Once this figure has been computed on a day of your data, it appears here.",
            emptySymbol: "function",
            overview: {
                Section {
                    DerivedSeriesChart(spec: spec, points: points)
                } footer: {
                    Text("Computed by this app from your data — not a measurement. Rebuilt with today's model, so a model improvement rewrites this history.")
                }
            },
            rows: {
                ForEach(points.reversed()) { point in
                    HStack {
                        Text(point.day.formatted(date: .abbreviated, time: .omitted))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(spec.string(point.value))
                            .font(.subheadline.monospacedDigit())
                    }
                }
            })
    }
}
