import InsightKit
import SwiftUI

/// The Data tab's read-only page for flagged events — backlog P32.
///
/// Built with `DomainDataScaffold`, like every other data page: a title, an
/// overview, entries newest-first, and a standard empty state. See
/// `docs/data-conventions.md`.
///
/// ## Read-only, and the answering lives elsewhere
///
/// Every domain row opens its *data* page and adding is a separate gesture —
/// the convention `DomainDataScaffold` exists to hold. So this lists what the
/// app asked and what the reader said, and the "Answer these" button pushes the
/// feed. It deliberately does not let a row be answered in place: a data page
/// that also edits is exactly the "view your data and add data are the same tap"
/// inconsistency the scaffold was written to end.
///
/// ⚠️ **No place, anywhere on this page.** The answered rows never had a
/// coordinate to show — it is deleted at the moment of answering — and the
/// pending ones are shown here without one on purpose: the map's justification
/// is that it helps somebody *answer*, and this is not that screen.
struct FlaggedEventDataView: View {
    @State private var model = EventFeedModel.shared

    private var rows: [Row] {
        let answered = (model.feed.answered + model.feed.needingRereview).map {
            Row(event: $0.event, judgement: $0.judgement)
        }
        let pending = model.feed.pending.map { Row(event: $0, judgement: nil) }
        return (answered + pending).sorted { $0.event.start > $1.event.start }
    }

    private struct Row: Identifiable {
        let event: FlaggedEvent
        let judgement: FlaggedEventJudgement?
        var id: String { event.id }
    }

    var body: some View {
        DomainDataScaffold(
            title: DataDomain.flaggedEvents.title,
            entriesHeader: "Moments",
            entryCount: rows.count,
            emptyHeadline: model.feed.gate == nil ? "Nothing flagged" : "Not enough history yet",
            emptyMessage: model.feed.emptyMessage(access: model.access),
            emptySymbol: "questionmark.bubble",
            overview: { overview },
            rows: { ForEach(rows) { row(for: $0) } })
    }

    @ViewBuilder private var overview: some View {
        Section {
            Text(model.feed.accuracy.sentence)
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            NavigationLink {
                EventConfirmationFeedView()
            } label: {
                HStack {
                    Text(model.feed.pending.isEmpty ? "Review your answers" : "Answer these")
                    Spacer()
                    if !model.feed.pending.isEmpty {
                        Text("\(model.feed.pending.count)")
                            .foregroundStyle(.secondary).monospacedDigit()
                    }
                }
            }
        } header: {
            Text("How often it's right")
        } footer: {
            // The standing caution, on the screen that lists these as *data*.
            Text("A flag means a number moved with nothing moving to explain it. Only your answer says what was actually happening — nothing here is the app having detected an activity.")
        }
    }

    @ViewBuilder private func row(for row: Row) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(row.event.start.formatted(date: .abbreviated, time: .shortened))
                    .font(.subheadline)
                Spacer(minLength: 8)
                Text("\(row.event.minutes) min")
                    .font(.caption).foregroundStyle(.secondary).monospacedDigit()
            }
            Text(String(format: "%.1f× your own normal variation for that time of day, over %d days",
                        row.event.evidence.departures, row.event.evidence.referenceDays))
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            // ⚠️ Guess and answer on separate lines, always. Collapsing them to
            // "what it was" would make the app look as though it had never been
            // wrong, which is the exact thing keeping them apart prevents.
            if let judgement = row.judgement {
                if let guess = judgement.guess {
                    Text("App guessed: \(guess.displayName)")
                        .font(.caption2).foregroundStyle(.tertiary)
                }
                Text("You said: \(judgement.effective?.displayName ?? "—")")
                    .font(.caption2).foregroundStyle(Theme.accent)
            } else {
                Text("Not answered yet")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
    }
}
