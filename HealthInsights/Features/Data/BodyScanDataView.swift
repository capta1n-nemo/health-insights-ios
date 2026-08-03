import SwiftUI
import InsightKit

/// The read-only record of every body measurement session.
///
/// Built with `DomainDataScaffold` like every other data page — see
/// `docs/data-conventions.md`. No hand-rolled chart: the seven promoted sites
/// already trend through the metric machinery, and this page is about the
/// *scans*, not the series.
///
/// What each row has to answer, and a metric row cannot: when it was taken, how
/// it was taken, what the reader was wearing, and whether the raw data is still
/// there for a future parser to improve on.
struct BodyScanDataView: View {
    @Environment(AppModel.self) private var model

    private var scans: [BodyScan] { model.bodyScans }

    var body: some View {
        DomainDataScaffold(
            title: "Body measurements",
            entriesHeader: "Sessions",
            entryCount: scans.count,
            emptyHeadline: "Nothing measured yet",
            emptyMessage: "A waist measurement is the one that counts — it lets the Body Composition card judge where your weight sits instead of guessing from BMI. Add one from the + menu.",
            emptySymbol: "figure.mixed.cardio",
            overview: { overview },
            rows: { rows })
    }

    /// What the app is actually using, after every source has been ranked.
    ///
    /// Shown above the sessions because it is the answer to "what does the app
    /// think my waist is" — which is not the same as "what did my last scan
    /// say", once Apple Health and a tape are both in play.
    @ViewBuilder private var overview: some View {
        let reconciled = model.reconciledMeasurements()
        if !reconciled.values.isEmpty {
            Section {
                ForEach(reconciled.sites, id: \.self) { site in
                    if let value = reconciled.mean(site) {
                        HStack {
                            Text(site.displayName)
                            Spacer()
                            Text(String(format: "%.1f cm", value))
                                .foregroundStyle(.secondary).monospacedDigit()
                        }
                    }
                }
            } header: {
                Text("In use now")
            } footer: {
                Text("Where more than one source measured the same place, the more precise method is used — a tape beats a scan, and a scan beats an unlabelled figure from Apple Health.")
            }
        }

        let disputes = model.measurementDisputes()
        if !disputes.isEmpty {
            Section {
                ForEach(disputes, id: \.chosen.site) { dispute in
                    if let note = dispute.note {
                        Text(note).font(.caption)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            } header: {
                Text("Sources that disagree")
            } footer: {
                Text("Kept rather than resolved silently: past a certain gap one of the two is wrong and the app cannot tell which.")
            }
        }
    }

    @ViewBuilder private var rows: some View {
        ForEach(scans, id: \.id) { scan in
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(scan.capturedAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.subheadline.weight(.medium))
                    Spacer()
                    Text(scan.mode.displayName)
                        .font(.caption).foregroundStyle(.secondary)
                }
                Text(siteSummary(scan))
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 10) {
                    Label(scan.conditions.clothing.displayName, systemImage: "tshirt")
                    // Whether this session can still be improved by a future
                    // parser. A reader who turned retention off in Settings is
                    // told here rather than discovering it years later.
                    Label(scan.isReparseable ? "Raw data kept" : "Numbers only",
                          systemImage: scan.isReparseable ? "archivebox" : "number")
                }
                .font(.caption2).foregroundStyle(.tertiary)
            }
            .swipeActions {
                Button("Delete", role: .destructive) {
                    model.deleteBodyScan(id: scan.id)
                }
            }
        }
    }

    private func siteSummary(_ scan: BodyScan) -> String {
        let named = scan.measurements.sites.prefix(4).map(\.displayName)
        let extra = scan.measurements.sites.count - named.count
        let list = named.joined(separator: ", ")
        return extra > 0 ? "\(list) and \(extra) more" : list
    }
}
