import SwiftUI
import InsightKit

/// The minimum convention every Data-tab detail page follows.
///
/// ## Why this is a type and not a style guide
///
/// The user found the Data tab's detail destinations were each their own shape:
/// substances opened the *add* page, medication opened the Body Composition
/// *card*, side effects were a static row that opened nothing. *"Build some
/// rules… those menus need to follow at least a minimum convention of how those
/// subpages are built… so I don't need to keep reprompting and checking for
/// this every time."*
///
/// A convention that lives in prose gets skipped the same way the Data tab's
/// completeness did before `DataDomain` made it a compile error. So the
/// convention is this scaffold, and it is enforced two ways:
///
/// 1. **`DataTabView.detailPage(for:)` is exhaustive over `DataDomain`** — a new
///    kind of data cannot ship without a detail page.
/// 2. **`verify.sh` requires every `*DataView` under `Features/Data` to be built
///    with `DomainDataScaffold`** — so the page it ships has the shape below.
///
/// ## The shape
///
/// - A title, inline.
/// - An **optional overview** at the top — a chart or a one-line summary. When a
///   page draws a chart it must be one of the app's shared chart components
///   (`SubstanceLoadChart`, `MedicationCurveChart`, …), which is where the
///   `add-chart` rules already live; a data page never hand-rolls a `Chart {}`.
///   Pass `EmptyView()` for a page with nothing to plot.
/// - A **list of entries, newest first**, under one header.
/// - A **standard empty state** when there is nothing, so an empty page reads as
///   empty rather than broken.
struct DomainDataScaffold<Overview: View, Rows: View>: View {
    let title: String
    /// The header over the entries list — "Doses", "Readings", "Entries".
    let entriesHeader: String
    /// How many entries there are. Drives the empty state, and is shown beside
    /// the header so the reader sees the total without counting.
    let entryCount: Int
    let emptyHeadline: String
    let emptyMessage: String
    let emptySymbol: String
    @ViewBuilder var overview: () -> Overview
    @ViewBuilder var rows: () -> Rows

    init(title: String, entriesHeader: String, entryCount: Int,
         emptyHeadline: String, emptyMessage: String, emptySymbol: String = "tray",
         @ViewBuilder overview: @escaping () -> Overview = { EmptyView() },
         @ViewBuilder rows: @escaping () -> Rows) {
        self.title = title
        self.entriesHeader = entriesHeader
        self.entryCount = entryCount
        self.emptyHeadline = emptyHeadline
        self.emptyMessage = emptyMessage
        self.emptySymbol = emptySymbol
        self.overview = overview
        self.rows = rows
    }

    var body: some View {
        List {
            // The caller wraps a chart in its own `Section`; an `EmptyView` here
            // contributes no row, so a page with nothing to plot pays nothing.
            overview()
            if entryCount > 0 {
                Section {
                    rows()
                } header: {
                    HStack {
                        Text(entriesHeader)
                        Spacer()
                        Text("\(entryCount)").foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .overlay {
            if entryCount == 0 {
                ContentUnavailableView(emptyHeadline, systemImage: emptySymbol,
                                       description: Text(emptyMessage))
            }
        }
    }
}
