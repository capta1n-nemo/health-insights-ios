import SwiftUI
import InsightKit

/// **The cycle log as data** — every bleeding day logged or synced, and the
/// cycles they form.
///
/// ## Why this exists (backlog D49)
///
/// `docs/data-conventions.md` ▸ rule 2: every domain row opens a read-only
/// detail page. `cycleSection` was one of three that opened nothing, and it
/// carried a `// data-detail: exempt` comment naming D49 — an exemption written
/// to be spent rather than inherited.
///
/// The gap was in the *convention*, not in the data: the Cycle tab already
/// shows all of this and more. But the reader's complaint behind the convention
/// was precisely about consistency — *"those menus need to follow at least a
/// minimum convention of how those subpages are built… so I don't need to keep
/// reprompting and checking for this every time."* A row that looks like every
/// other Data-tab row and does nothing when tapped is the thing being
/// complained about, whatever else exists elsewhere in the app.
///
/// ## What it deliberately is not
///
/// **Not a second Cycle tab.** No phase, no fertile window, no prediction —
/// those are the Cycle tab's job and duplicating them would be two places for
/// the same model to disagree with itself. This is the Data tab's job: what is
/// held, listed, newest first, with nothing derived that isn't labelled as
/// derived.
///
/// **Read-only.** Tapping a day on the Cycle tab's calendar changes what is
/// stored; nothing here does. Adding lives there and in the `+` menu.
///
/// **The range, never a single length.** `CycleSummary.lengthRange` is nil
/// below `CycleModel.minimumCyclesForRange` completed cycles and this page
/// stays silent when it is, rather than reaching for a mean — the rule
/// `CycleLog` is built around, restated wherever cycles are shown. The median
/// appears only *inside* the range sentence, never on its own.
///
/// **No chart.** There is no shared chart component for cycles, and rule 3
/// forbids a data page hand-rolling a raw Swift Charts view. A summary line is
/// the overview instead — which the scaffold allows for exactly this case.
/// (Spelt out in prose rather than in code font: the lint greps the file text
/// and does not skip comments.)
struct CycleDataView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.calendar) private var calendar

    private var days: [CycleDay] {
        model.cycleDays.sorted { $0.day > $1.day }
    }

    var body: some View {
        let summary = model.cycleSummary
        return DomainDataScaffold(
            title: DataDomain.cycles.title,
            entriesHeader: "Days logged",
            entryCount: days.count,
            emptyHeadline: "Nothing logged yet",
            emptyMessage: "Bleeding days you log on the Cycle tab, or that sync from Health, appear here — newest first.",
            emptySymbol: "drop",
            overview: {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(lengthSentence(summary))
                        if let currentDay = summary.currentDay {
                            // Days *so far*, said as days so far. A running
                            // cycle has no length yet and must never be given
                            // one — the single most common way a tracker
                            // misleads, and the reason `Cycle.length` is nil
                            // until the next cycle starts.
                            Text("Day \(currentDay) of the cycle in progress, which has no length yet.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .fixedSize(horizontal: false, vertical: true)
                } header: {
                    Text("Your cycles")
                } footer: {
                    Text(DataDomain.cycles.summary)
                }
                let completed = summary.cycles.filter { !$0.isInProgress }.reversed()
                if !completed.isEmpty {
                    Section {
                        ForEach(Array(completed)) { cycle in
                            cycleRow(cycle)
                        }
                    } header: {
                        HStack {
                            Text("Completed cycles")
                            Spacer()
                            Text("\(completed.count)").foregroundStyle(.secondary)
                        }
                    }
                }
            },
            rows: {
                ForEach(days) { day in
                    HStack {
                        Text(day.day.formatted(date: .abbreviated, time: .omitted))
                        Spacer()
                        Text(day.flow.title)
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                }
            })
    }

    /// The range sentence, or an honest statement that there isn't one yet.
    private func lengthSentence(_ summary: CycleSummary) -> String {
        guard let range = summary.lengthRange else {
            let completed = summary.cycles.filter { !$0.isInProgress }.count
            return completed == 0
                ? "No completed cycle yet, so there is no length to report."
                : "\(completed) completed cycle\(completed == 1 ? "" : "s") — not enough to describe a range. \(CycleModel.minimumCyclesForRange) are needed before a range means anything."
        }
        let median = summary.medianLength.map { ", typically \($0)" } ?? ""
        return "Your cycles run \(range.lowerBound)–\(range.upperBound) days\(median). That spread is the figure, not one average."
    }

    private func cycleRow(_ cycle: Cycle) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(cycle.start.formatted(date: .abbreviated, time: .omitted))
                Text("\(cycle.periodLength(calendar: calendar)) day period")
                    .font(.caption).foregroundStyle(.tertiary)
            }
            Spacer()
            if let length = cycle.length(calendar: calendar) {
                Text("\(length) days")
                    .font(.subheadline).monospacedDigit().foregroundStyle(.secondary)
            }
        }
    }
}
