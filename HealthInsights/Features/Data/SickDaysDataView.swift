import SwiftUI
import InsightKit

/// **Every day the reader was ill, newest first** — the merged `SickDayLedger`,
/// §B11-4.
///
/// Built on `DomainDataScaffold` like every other data page (title, overview,
/// entries newest-first, empty state), and it draws no chart: this page's
/// subject is a list of dated periods, and `docs/data-conventions.md` is
/// explicit that a data page never hand-rolls one. The picture of *when* illness
/// was flagged lives on the symptom radar card, where it can carry the caveats
/// it needs.
///
/// ## Read-only, and the reason is the same one `SymptomDataView` gives
///
/// Every period here is detected from a calendar event, so the place to change
/// one is the event's classification on the Work impact review list — where the
/// reader can retag it, grade its severity, and have the correction stored
/// beside the guess rather than over it. A delete button here would remove a
/// derived row that the next calendar sync would put straight back: a control
/// that appears to work and does not.
///
/// ⚠️ **What this page says, and what it must never say.** Every row is *what
/// the reader recorded*. Nothing on it is a physiological finding, and the
/// footer says so — `docs/illness-detection-evidence-2026-08-07.md` puts
/// prospective positive predictive value for wearable illness detection at
/// 4–12% and finds roughly two-thirds of genuine infections produce no clear
/// signal at all. So this page never compares a recorded sick day against the
/// radar, in either direction.
struct SickDaysDataView: View {
    @Environment(AppModel.self) private var model

    private var periods: [SickDayLedger.Period] {
        model.sickDayLedger.periods.reversed()
    }

    var body: some View {
        DomainDataScaffold(
            title: DataDomain.sickDays.title,
            entriesHeader: "Spells",
            entryCount: periods.count,
            emptyHeadline: "No sick days recorded",
            emptyMessage: "Days your calendar marks as sick appear here. If one is missing, or something was filed as a sick day that wasn't, correct it on the Work impact card's event list — this page follows what you said there.",
            emptySymbol: "bandage",
            overview: {
                Section {
                    Text(standing)
                        .font(.caption).foregroundStyle(.secondary)
                    if totalDays > 0 {
                        HStack {
                            Text("Days ill in the last year")
                                .font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            Text("\(totalDays)")
                                .font(.caption.weight(.medium)).monospacedDigit()
                        }
                    }
                } footer: {
                    Text("These are days you or your calendar said you were ill. Nothing here was worked out from your vitals, and nothing here says whether you were — a quiet symptom radar is not evidence you were well, and a loud one is not evidence you were ill.")
                }
            },
            rows: {
                ForEach(periods) { period in
                    row(period)
                }
            })
    }

    private var standing: String {
        switch model.sickDayLedger.daysSinceLastSickDay(asOf: Date()) {
        case 0: return "Today is marked as a sick day."
        case .some(let days):
            return "You were last ill \(days) \(days == 1 ? "day" : "days") ago."
        case nil:
            return "Nothing recorded before today."
        }
    }

    /// Days ill in the trailing year — the figure that means something on a page
    /// of individual spells. A year rather than the ledger's whole span because
    /// the comparison a reader makes is against last year, and because an adult
    /// averages two to four acute infections in one.
    private var totalDays: Int {
        let end = Date()
        guard let start = Calendar.current.date(byAdding: .year, value: -1, to: end)
        else { return 0 }
        return model.sickDayLedger.dayCount(in: DateInterval(start: start, end: end))
    }

    private func row(_ period: SickDayLedger.Period) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(period.label ?? "From your calendar")
                Text(rangeLabel(period))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                let days = period.dayCount()
                Text("\(days) \(days == 1 ? "day" : "days")")
                    .font(.subheadline).monospacedDigit().foregroundStyle(.secondary)
                // "Not graded" and "graded, and they didn't say how bad" are
                // different records — `SickDayLedger.Period.severity` keeps both
                // and so does this row.
                Text(period.severity.map { $0 == .unstated ? "not graded" : $0.title.lowercased() }
                     ?? "not graded")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
        }
    }

    private func rangeLabel(_ period: SickDayLedger.Period) -> String {
        let first = period.firstDay.formatted(date: .abbreviated, time: .omitted)
        guard period.dayCount() > 1 else { return first }
        return "\(first) – \(period.lastDay.formatted(date: .abbreviated, time: .omitted))"
    }
}
