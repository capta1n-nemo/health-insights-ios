import SwiftUI
import InsightKit

/// **Every blood-test value the app holds** — backlog `Q7`.
///
/// Built with `DomainDataScaffold`, like every other data page: title, an
/// overview, entries newest-first, and a standard empty state. The overview is
/// prose rather than a chart, and `EmptyView()` would be wrong here — a reader
/// arriving at this page wants to know *how many reports, over what span*
/// before they scroll thirty analytes.
///
/// ⚠️ **No chart, on purpose.** A lab result is one reading at one moment, and a
/// reader typically has two or three of them a year. A line through three points
/// implies a rate of change nobody measured — and the app's own rule is that
/// modelled is never dressed as measured. When there is enough history for a
/// per-analyte trend it belongs on the analyte's own page with the error bar
/// stated, not on a summary drawn from two dots.
struct LabResultsDataView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        DomainDataScaffold(
            title: DataDomain.labResults.title,
            entriesHeader: "Values",
            entryCount: model.labResults.count,
            emptyHeadline: "No blood tests yet",
            emptyMessage: "Type your results in, or photograph, scan or import a PDF of a report — Settings ▸ Add or update data. Everything is read on this phone.",
            emptySymbol: "testtube.2",
            overview: { overview },
            rows: { rows })
    }

    @ViewBuilder private var overview: some View {
        if !model.labResults.isEmpty {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text(collectionSummary)
                        .font(.subheadline)
                    if flaggedCount > 0 {
                        // Surfaced at the top rather than left to be discovered
                        // by scrolling. A value the app is unsure it transcribed
                        // is the one thing on this page a reader should act on,
                        // and it is also the one thing that looks identical to a
                        // good value from a distance.
                        Label("\(flaggedCount) value\(flaggedCount == 1 ? "" : "s") worth checking against your report",
                              systemImage: "exclamationmark.triangle.fill")
                            .font(.caption).foregroundStyle(Theme.warn)
                    }
                    Text(DataDomain.labResults.summary)
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder private var rows: some View {
        // Grouped by panel, in the catalogue's own order, so a thirty-row report
        // reads as a report rather than an alphabet. `.other` sorts last: the
        // analytes the app could not name are the least useful place to start.
        //
        // The group heading is a **row**, not a `Section`. `DomainDataScaffold`
        // already wraps this builder in one, and a nested `Section` inside a
        // `List` renders as a stray inset rather than a heading — the kind of
        // thing that ships looking broken with every test green.
        ForEach(orderedPanels, id: \.self) { panel in
            Text(panel.title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .listRowBackground(Color.clear)
            ForEach(grouped[panel] ?? []) { result in
                LabResultRow(result: result, showsChecks: true)
                    .swipeActions {
                        Button(role: .destructive) {
                            model.deleteLabResult(id: result.id)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
            }
        }
    }

    private var grouped: [LabPanel: [LabResult]] {
        Dictionary(grouping: model.labResults) { $0.analyte.panel }
    }

    private var orderedPanels: [LabPanel] {
        LabPanel.allCases.filter { grouped[$0]?.isEmpty == false }
    }

    private var flaggedCount: Int {
        model.labResults.filter { $0.confidence == .doubtful }.count
    }

    /// "12 values from 2 reports, most recently 14 March 2026."
    ///
    /// Reports are counted by distinct collection date, which is what a reader
    /// means by "a report" — not by import, because one report can arrive as
    /// three scanned pages.
    private var collectionSummary: String {
        let results = model.labResults
        guard let newest = results.map(\.collectedAt).max() else { return "" }
        let days = Set(results.map { Calendar.current.startOfDay(for: $0.collectedAt) })
        let valueWord = results.count == 1 ? "value" : "values"
        let reportWord = days.count == 1 ? "report" : "reports"
        return "\(results.count) \(valueWord) from \(days.count) \(reportWord), "
            + "most recently \(newest.formatted(date: .abbreviated, time: .omitted))."
    }
}
